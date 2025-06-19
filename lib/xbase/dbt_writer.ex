defmodule Xbase.DbtWriter do
  @moduledoc """
  Module for writing and managing memo content in DBT files.
  
  Provides comprehensive memo writing capabilities including append, update,
  deletion, block management, and file compaction. Coordinates with DBF
  record operations to maintain consistency.
  """

  alias Xbase.DbtParser
  alias Xbase.Types.{DbtHeader, DbtFile}

  @doc """
  Opens a DBT file for writing operations.
  
  ## Parameters
  - `file_path` - Path to the DBT file
  - `version` - DBT format version (optional, defaults to :dbase_iii)
  
  ## Returns
  - `{:ok, DbtFile.t()}` - Successfully opened DBT file for writing
  - `{:error, reason}` - Error opening file
  """
  def open_dbt_for_writing(file_path, version \\ :dbase_iii) do
    case File.exists?(file_path) do
      true ->
        # Open existing DBT file
        case :file.open(file_path, [:read, :write, :binary]) do
          {:ok, file} ->
            case :file.read(file, 512) do
              {:ok, header_binary} ->
                case DbtParser.parse_header(header_binary, version) do
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
      false ->
        {:error, :file_not_found}
    end
  end

  @doc """
  Creates a new DBT file with initial header.
  
  ## Parameters
  - `file_path` - Path for the new DBT file
  - `opts` - Options for DBT creation
    - `:version` - DBT format version (default: :dbase_iii)
    - `:block_size` - Block size in bytes (default: 512)
  
  ## Returns
  - `{:ok, DbtFile.t()}` - Successfully created DBT file
  - `{:error, reason}` - Error creating file
  """
  def create_dbt(file_path, opts \\ []) do
    version = Keyword.get(opts, :version, :dbase_iii)
    block_size = Keyword.get(opts, :block_size, 512)
    
    # Validate block size
    if block_size < 512 or block_size > 65536 do
      {:error, :invalid_block_size}
    else
      case :file.open(file_path, [:read, :write, :binary]) do
        {:ok, file} ->
          # Create initial header
          header = %DbtHeader{
            next_block: 1,  # First memo block
            block_size: block_size,
            version: version
          }
          
          case write_header(file, header) do
            :ok ->
              dbt_file = %DbtFile{
                header: header,
                file: file,
                file_path: file_path
              }
              {:ok, dbt_file}
            {:error, reason} ->
              :file.close(file)
              File.rm(file_path)
              {:error, reason}
          end
        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Writes new memo content to the DBT file and returns the block number.
  
  ## Parameters
  - `dbt_file` - DbtFile structure opened for writing
  - `content` - Memo content to write (string)
  
  ## Returns
  - `{:ok, {block_number, updated_dbt_file}}` - Successfully written memo
  - `{:error, reason}` - Error writing memo
  """
  def write_memo(%DbtFile{header: header, file: file} = dbt_file, content) when is_binary(content) do
    block_number = header.next_block
    
    # Prepare memo content with termination
    memo_data = prepare_memo_content(content, header.block_size)
    
    # Calculate offset for the new block
    offset = DbtParser.calculate_block_offset(header, block_number)
    
    case :file.pwrite(file, offset, memo_data) do
      :ok ->
        # Update header with next available block
        updated_header = %{header | next_block: header.next_block + 1}
        
        case update_dbt_header(file, updated_header) do
          :ok ->
            updated_dbt_file = %{dbt_file | header: updated_header}
            {:ok, {block_number, updated_dbt_file}}
          {:error, reason} ->
            {:error, reason}
        end
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Updates existing memo content at a specific block.
  
  ## Parameters
  - `dbt_file` - DbtFile structure opened for writing
  - `block_number` - Block number to update
  - `content` - New memo content (string)
  
  ## Returns
  - `{:ok, dbt_file}` - Successfully updated memo
  - `{:error, reason}` - Error updating memo
  """
  def update_memo(%DbtFile{header: header, file: file} = dbt_file, block_number, content) when is_binary(content) do
    cond do
      block_number <= 0 ->
        {:error, :invalid_block_number}
      block_number >= header.next_block ->
        {:error, :block_not_allocated}
      true ->
        # Prepare memo content with termination
        memo_data = prepare_memo_content(content, header.block_size)
        
        # Calculate offset for the block
        offset = DbtParser.calculate_block_offset(header, block_number)
        
        case :file.pwrite(file, offset, memo_data) do
          :ok ->
            {:ok, dbt_file}
          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Marks a memo block as deleted by writing empty content.
  
  ## Parameters
  - `dbt_file` - DbtFile structure opened for writing
  - `block_number` - Block number to delete
  
  ## Returns
  - `{:ok, dbt_file}` - Successfully deleted memo
  - `{:error, reason}` - Error deleting memo
  """
  def delete_memo(%DbtFile{header: header, file: file} = dbt_file, block_number) do
    cond do
      block_number <= 0 ->
        {:error, :invalid_block_number}
      block_number >= header.next_block ->
        {:error, :block_not_allocated}
      true ->
        # Write empty block (all zeros)
        empty_block = :binary.copy(<<0>>, header.block_size)
        offset = DbtParser.calculate_block_offset(header, block_number)
        
        case :file.pwrite(file, offset, empty_block) do
          :ok ->
            {:ok, dbt_file}
          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Analyzes DBT file fragmentation and returns statistics.
  
  ## Parameters
  - `dbt_file` - DbtFile structure
  
  ## Returns
  - `{:ok, %{total_blocks: n, used_blocks: n, free_blocks: n, fragmentation_ratio: f}}`
  - `{:error, reason}` - Error analyzing file
  """
  def analyze_fragmentation(%DbtFile{header: header, file: file}) do
    total_blocks = header.next_block - 1  # Exclude header block
    
    if total_blocks <= 0 do
      {:ok, %{total_blocks: 0, used_blocks: 0, free_blocks: 0, fragmentation_ratio: 0.0}}
    else
      used_blocks = count_used_blocks(file, header, 1, header.next_block - 1, 0)
      free_blocks = total_blocks - used_blocks
      fragmentation_ratio = if total_blocks > 0, do: free_blocks / total_blocks, else: 0.0
      
      {:ok, %{
        total_blocks: total_blocks,
        used_blocks: used_blocks,
        free_blocks: free_blocks,
        fragmentation_ratio: fragmentation_ratio
      }}
    end
  end

  @doc """
  Compacts a DBT file by removing unused blocks and rebuilding the file.
  
  ## Parameters
  - `dbt_file` - DbtFile structure to compact
  - `output_path` - Path for the compacted file (can be same as input)
  
  ## Returns
  - `{:ok, compacted_dbt_file}` - Successfully compacted DBT file
  - `{:error, reason}` - Error during compaction
  """
  def compact_dbt(%DbtFile{header: header, file: file, file_path: input_path} = _dbt_file, output_path) do
    temp_path = output_path <> ".tmp"
    
    case create_dbt(temp_path, version: header.version, block_size: header.block_size) do
      {:ok, temp_dbt} ->
        case copy_used_blocks(file, temp_dbt, header) do
          {:ok, final_dbt} ->
            # Close files
            close_dbt(final_dbt)
            :file.close(file)
            
            # Replace original with compacted version
            case File.rename(temp_path, output_path) do
              :ok ->
                # Reopen compacted file
                open_dbt_for_writing(output_path, header.version)
              {:error, reason} ->
                File.rm(temp_path)
                {:error, reason}
            end
          {:error, reason} ->
            close_dbt(temp_dbt)
            File.rm(temp_path)
            {:error, reason}
        end
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Closes a DBT file opened for writing.
  
  ## Parameters
  - `dbt_file` - DbtFile structure
  
  ## Returns
  - `:ok` - File closed successfully
  """
  def close_dbt(%DbtFile{file: file}) do
    :file.close(file)
  end

  # Private helper functions

  defp write_header(file, %DbtHeader{version: version} = header) do
    header_binary = case version do
      :dbase_iii ->
        <<header.next_block::little-32, -1::little-32, 0::16, 
          header.block_size::little-16, 0::500*8>>
      :dbase_iv ->
        <<header.next_block::little-32, header.block_size::little-16, 
          0::16, 0::504*8>>
    end
    
    case :file.pwrite(file, 0, header_binary) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp update_dbt_header(file, header) do
    write_header(file, header)
  end

  defp prepare_memo_content(content, block_size) do
    # Add termination markers
    content_with_termination = content <> <<0x1A, 0x1A>>
    
    # Pad to block size
    if byte_size(content_with_termination) > block_size do
      # Content too large for single block - truncate for now
      # TODO: Implement multi-block memos
      binary_part(content_with_termination, 0, block_size - 2) <> <<0x1A, 0x1A>>
    else
      padding_size = block_size - byte_size(content_with_termination)
      content_with_termination <> :binary.copy(<<0>>, padding_size)
    end
  end

  defp count_used_blocks(_file, _header, current, max, count) when current >= max do
    count
  end

  defp count_used_blocks(file, header, current, max, count) do
    offset = DbtParser.calculate_block_offset(header, current)
    
    case :file.pread(file, offset, header.block_size) do
      {:ok, block_data} ->
        used = if is_block_used?(block_data), do: 1, else: 0
        count_used_blocks(file, header, current + 1, max, count + used)
      {:error, _reason} ->
        count
    end
  end

  defp is_block_used?(block_data) do
    # Check if block contains non-zero data or has termination markers
    # A block is used if it's not all zeros
    case block_data do
      <<>> -> false
      _ -> 
        # Check if entire block is zeros
        all_zeros = :binary.copy(<<0>>, byte_size(block_data))
        block_data != all_zeros
    end
  end

  defp copy_used_blocks(source_file, %DbtFile{header: target_header} = target_dbt, source_header) do
    copy_blocks_recursive(source_file, target_dbt, source_header, target_header, 1, 1)
  end

  defp copy_blocks_recursive(_source_file, target_dbt, source_header, target_header, source_block, _target_block) 
       when source_block >= source_header.next_block do
    # Update target header with final next_block
    case update_dbt_header(target_dbt.file, target_header) do
      :ok -> {:ok, %{target_dbt | header: target_header}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp copy_blocks_recursive(source_file, target_dbt, source_header, target_header, source_block, target_block) do
    source_offset = DbtParser.calculate_block_offset(source_header, source_block)
    
    case :file.pread(source_file, source_offset, source_header.block_size) do
      {:ok, block_data} ->
        if is_block_used?(block_data) do
          # Copy this block to target
          target_offset = DbtParser.calculate_block_offset(target_header, target_block)
          
          case :file.pwrite(target_dbt.file, target_offset, block_data) do
            :ok ->
              updated_target_header = %{target_header | next_block: target_block + 1}
              copy_blocks_recursive(source_file, target_dbt, source_header, updated_target_header, 
                                   source_block + 1, target_block + 1)
            {:error, reason} ->
              {:error, reason}
          end
        else
          # Skip unused block
          copy_blocks_recursive(source_file, target_dbt, source_header, target_header, 
                               source_block + 1, target_block)
        end
      {:error, reason} ->
        {:error, reason}
    end
  end
end