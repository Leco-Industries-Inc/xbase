defmodule Xbase.Parser do
  @moduledoc """
  Binary parser for DBF file format components.
  
  This module provides functions to parse DBF file headers and field descriptors
  from binary data using Elixir's efficient binary pattern matching.
  """

  alias Xbase.Types.{Header, FieldDescriptor}

  @doc """
  Parses a 32-byte DBF header from binary data.
  
  ## Parameters  
  - `binary` - The binary data containing the DBF header
  
  ## Returns
  - `{:ok, %Header{}}` - Successfully parsed header
  - `{:error, reason}` - Parse error with reason
  
  ## Examples
      iex> header_data = <<0x03, 124, 12, 17, 100::little-32, 161::little-16, 50::little-16, 0::16, 0, 0, 0::12*8, 0, 0, 0::16>>
      iex> Xbase.Parser.parse_header(header_data)
      {:ok, %Xbase.Types.Header{version: 3, record_count: 100, ...}}
  """
  def parse_header(binary) when byte_size(binary) != 32 do
    {:error, :invalid_header_size}
  end

  def parse_header(binary) do
    case binary do
      <<version, yy, mm, dd, record_count::little-32, 
        header_length::little-16, record_length::little-16,
        _reserved1::16, transaction_flag, encryption_flag,
        _reserved2::12*8, mdx_flag, language_driver, _reserved3::16>> ->
        
        case validate_version(version) do
          :ok ->
            {:ok, %Header{
              version: version,
              last_update_year: yy,
              last_update_month: mm,
              last_update_day: dd,
              record_count: record_count,
              header_length: header_length,
              record_length: record_length,
              transaction_flag: transaction_flag,
              encryption_flag: encryption_flag,
              mdx_flag: mdx_flag,
              language_driver: language_driver
            }}
          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Parses field descriptors from binary data until field terminator (0x0D).
  
  ## Parameters
  - `binary` - The binary data containing field descriptors
  - `offset` - Starting offset in the binary data
  
  ## Returns
  - `{:ok, [%FieldDescriptor{}]}` - List of parsed field descriptors
  - `{:error, reason}` - Parse error with reason
  """
  def parse_fields(binary, offset \\ 0) do
    parse_fields_recursive(binary, offset, [])
  end

  @doc """
  Opens a DBF file and parses its header and field descriptors.
  
  ## Parameters
  - `path` - Path to the DBF file
  
  ## Returns
  - `{:ok, %{header: header, fields: fields, file: file}}` - Successfully opened DBF
  - `{:error, reason}` - Error opening or parsing file
  
  ## Examples
      iex> Xbase.Parser.open_dbf("data.dbf")
      {:ok, %{header: %Header{...}, fields: [...], file: #Port<...>}}
  """
  def open_dbf(path) do
    case :file.open(path, [:read, :binary, :random]) do
      {:ok, file} ->
        case read_and_parse_header(file) do
          {:ok, header} ->
            case read_and_parse_fields(file, header) do
              {:ok, fields} ->
                {:ok, %{header: header, fields: fields, file: file}}
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

  @doc """
  Closes a DBF file handle.
  
  ## Parameters
  - `dbf` - DBF structure returned from open_dbf/1
  
  ## Returns
  - `:ok` - File closed successfully
  """
  def close_dbf(%{file: file}) do
    :file.close(file)
  end

  # Private functions

  defp read_and_parse_header(file) do
    case :file.read(file, 32) do
      {:ok, header_binary} ->
        parse_header(header_binary)
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp read_and_parse_fields(file, header) do
    # Calculate how many bytes to read for fields
    # header_length - 32 (header size) = field descriptors + terminator
    fields_size = header.header_length - 32
    
    case :file.read(file, fields_size) do
      {:ok, fields_binary} ->
        parse_fields(fields_binary, 0)
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_version(version) do
    case version do
      0x02 -> :ok  # FoxBASE
      0x03 -> :ok  # dBase III without memo
      0x04 -> :ok  # dBase IV without memo
      0x05 -> :ok  # dBase V without memo
      0x07 -> :ok  # Visual Objects
      0x30 -> :ok  # Visual FoxPro
      0x31 -> :ok  # Visual FoxPro with AutoIncrement
      0x83 -> :ok  # dBase III with memo
      0x8B -> :ok  # dBase IV with memo
      0x8E -> :ok  # dBase IV with SQL table
      0xF5 -> :ok  # FoxPro with memo
      _ -> {:error, :invalid_version}
    end
  end

  defp parse_fields_recursive(binary, offset, acc) do
    if offset >= byte_size(binary) do
      {:error, :missing_field_terminator}
    else
      case binary do
        <<_::binary-size(offset), 0x0D, _::binary>> ->
          {:ok, Enum.reverse(acc)}
        
        _ when offset + 32 <= byte_size(binary) ->
          <<_::binary-size(offset), field_data::binary-size(32), _rest::binary>> = binary
          case parse_single_field(field_data) do
            {:ok, field} ->
              parse_fields_recursive(binary, offset + 32, [field | acc])
          end
        
        _ ->
          {:error, :missing_field_terminator}
      end
    end
  end

  defp parse_single_field(field_binary) do
    case field_binary do
      <<name::binary-size(11), type::binary-size(1), _data_address::32,
        length, decimal_count, _reserved1::16, work_area_id, _reserved2::16,
        set_fields_flag, _reserved3::7*8, index_field_flag>> ->
        
        # Clean field name (remove null bytes and trim)
        clean_name = name 
          |> :binary.replace(<<0>>, "", [:global]) 
          |> String.trim()
        
        {:ok, %FieldDescriptor{
          name: clean_name,
          type: type,
          length: length,
          decimal_count: decimal_count,
          work_area_id: work_area_id,
          set_fields_flag: set_fields_flag,
          index_field_flag: index_field_flag
        }}
    end
  end
end