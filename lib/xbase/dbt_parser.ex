defmodule Xbase.DbtParser do
  @moduledoc """
  Parser for DBT (memo) files used in dBase for storing variable-length text data.
  
  DBT files store memo field content in a block-based structure with a 512-byte header
  followed by fixed-size blocks containing memo data terminated by 0x1A 0x1A markers.
  """

  alias Xbase.Types.{DbtHeader, DbtFile}

  @doc """
  Parses a DBT file header from binary data.
  
  ## Parameters
  - `header_binary` - 512 bytes of header data
  - `version` - DBT format version (defaults to :dbase_iii)
  
  ## Returns
  - `{:ok, DbtHeader.t()}` - Successfully parsed header
  - `{:error, reason}` - Error parsing header
  """
  def parse_header(header_binary, version \\ :dbase_iii)

  def parse_header(header_binary, _version) when byte_size(header_binary) != 512 do
    {:error, :invalid_header_size}
  end

  def parse_header(header_binary, :dbase_iii) do
    case header_binary do
      <<next_block::little-32, _unknown::little-32, _unknown2::16, block_size::little-16, _padding::500*8>> ->
        if block_size >= 512 and block_size <= 65536 do
          {:ok, %DbtHeader{
            next_block: next_block,
            block_size: block_size,
            version: :dbase_iii
          }}
        else
          {:error, :invalid_block_size}
        end
      _ ->
        {:error, :invalid_header_format}
    end
  end

  def parse_header(header_binary, :dbase_iv) do
    case header_binary do
      <<next_block::little-32, block_size::little-16, _unknown::16, _padding::504*8>> ->
        if block_size >= 512 and block_size <= 65536 do
          {:ok, %DbtHeader{
            next_block: next_block,
            block_size: block_size,
            version: :dbase_iv
          }}
        else
          {:error, :invalid_block_size}
        end
      _ ->
        {:error, :invalid_header_format}
    end
  end

  @doc """
  Calculates the byte offset for a specific block number.
  
  ## Parameters
  - `header` - DbtHeader structure
  - `block_number` - Block number to calculate offset for
  
  ## Returns
  - Integer byte offset from start of file
  """
  def calculate_block_offset(%DbtHeader{block_size: block_size}, block_number) do
    # Block 0 is the header (512 bytes), so block 1 starts at offset 512
    # Block N starts at offset (N * block_size)
    block_number * block_size
  end

  @doc """
  Extracts memo content from a block, handling termination markers.
  
  ## Parameters
  - `block_data` - Binary data from a memo block
  
  ## Returns
  - `{:ok, String.t()}` - Extracted memo content
  - `{:error, reason}` - Error extracting content
  """
  def extract_memo_content(block_data) when is_binary(block_data) do
    # Look for double 0x1A termination markers
    case :binary.match(block_data, <<0x1A, 0x1A>>) do
      {pos, _len} ->
        # Extract content up to termination markers
        content = binary_part(block_data, 0, pos)
        {:ok, content}
      :nomatch ->
        # No termination found, use entire block (trim null bytes)
        content = String.trim_trailing(block_data, <<0>>)
        {:ok, content}
    end
  end

  @doc """
  Opens a DBT file and parses its header.
  
  ## Parameters
  - `file_path` - Path to the DBT file
  - `version` - DBT format version (optional)
  
  ## Returns
  - `{:ok, DbtFile.t()}` - Successfully opened DBT file
  - `{:error, reason}` - Error opening or parsing file
  """
  def open_dbt(file_path, version \\ :dbase_iii) do
    case File.exists?(file_path) do
      false ->
        {:error, :file_not_found}
      true ->
        case :file.open(file_path, [:read, :binary, :random]) do
          {:ok, file} ->
            case :file.read(file, 512) do
              {:ok, header_binary} ->
                case parse_header(header_binary, version) do
                  {:ok, header} ->
                    dbt_file = %DbtFile{
                      header: header,
                      file: file,
                      file_path: file_path
                    }
                    {:ok, dbt_file}
                  {:error, reason} ->
                    :file.close(file)
                    {:error, reason}
                end
              {:error, reason} ->
                :file.close(file)
                {:error, reason}
            end
          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Reads memo content from a specific block number.
  
  ## Parameters
  - `dbt_file` - DbtFile structure from open_dbt/1
  - `block_number` - Block number to read (1-based, 0 is header)
  
  ## Returns
  - `{:ok, String.t()}` - Memo content
  - `{:error, reason}` - Error reading block
  """
  def read_memo(%DbtFile{header: header, file: file}, block_number) do
    cond do
      block_number <= 0 ->
        {:error, :invalid_block_number}
      block_number >= header.next_block ->
        {:error, :block_not_allocated}
      true ->
        offset = calculate_block_offset(header, block_number)
        case :file.pread(file, offset, header.block_size) do
          {:ok, block_data} ->
            extract_memo_content(block_data)
          :eof ->
            {:error, :block_beyond_file_end}
          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Closes a DBT file handle.
  
  ## Parameters
  - `dbt_file` - DbtFile structure from open_dbt/1
  
  ## Returns
  - `:ok` - File closed successfully
  """
  def close_dbt(%DbtFile{file: file}) do
    :file.close(file)
  end

  @doc """
  Validates a DBT file for basic integrity.
  
  ## Parameters
  - `file_path` - Path to the DBT file to validate
  
  ## Returns
  - `{:ok, boolean()}` - Validation result
  - `{:error, reason}` - Error during validation
  """
  def validate_dbt_file(file_path) do
    case open_dbt(file_path) do
      {:ok, dbt_file} ->
        # Basic validation: check if header is readable
        close_dbt(dbt_file)
        {:ok, true}
      {:error, _reason} ->
        {:ok, false}
    end
  end
end