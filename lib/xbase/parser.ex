defmodule Xbase.Parser do
  @moduledoc """
  Binary parser for DBF file format components.
  
  This module provides functions to parse DBF file headers and field descriptors
  from binary data using Elixir's efficient binary pattern matching.
  """

  alias Xbase.Types.{Header, FieldDescriptor, Record}

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
    open_dbf(path, [:read])
  end

  @doc """
  Opens a DBF file and parses its header and field descriptors with specified file modes.
  
  ## Parameters
  - `path` - Path to the DBF file
  - `modes` - List of file open modes (e.g., [:read], [:read, :write])
  
  ## Returns
  - `{:ok, %{header: header, fields: fields, file: file}}` - Successfully opened DBF
  - `{:error, reason}` - Error opening or parsing file
  """
  def open_dbf(path, modes) do
    file_modes = modes ++ [:binary, :random]
    
    case :file.open(path, file_modes) do
      {:ok, file} ->
        case read_and_parse_header(file) do
          {:ok, header} ->
            case read_and_parse_fields(file, header) do
              {:ok, fields} ->
                {:ok, %{header: header, fields: fields, file: file, file_path: path}}
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

  @doc """
  Calculates the byte offset for a specific record in the file.
  
  ## Parameters
  - `header` - The DBF header containing file structure information
  - `record_index` - Zero-based record index
  
  ## Returns
  - The byte offset where the record starts
  
  ## Examples
      iex> header = %Header{header_length: 97, record_length: 25}
      iex> Xbase.Parser.calculate_record_offset(header, 0)
      97
      iex> Xbase.Parser.calculate_record_offset(header, 1)
      122
  """
  def calculate_record_offset(%Header{header_length: header_length, record_length: record_length}, record_index) do
    header_length + (record_index * record_length)
  end

  @doc """
  Validates if a record index is within the valid range for the file.
  
  ## Parameters
  - `header` - The DBF header containing record count
  - `record_index` - Zero-based record index to validate
  
  ## Returns
  - `true` if the index is valid, `false` otherwise
  """
  def is_valid_record_index?(%Header{record_count: record_count}, record_index) 
      when record_index >= 0 and record_index < record_count do
    true
  end

  def is_valid_record_index?(_header, _record_index) do
    false
  end

  @doc """
  Extracts the deletion flag from record data.
  
  ## Parameters
  - `record_binary` - The raw record binary data
  
  ## Returns
  - `{:ok, boolean}` - true if deleted (0x2A), false if active (0x20)
  - `{:error, reason}` - Error for invalid data
  """
  def get_deletion_flag(<<>>) do
    {:error, :invalid_record_data}
  end

  def get_deletion_flag(<<deletion_flag, _rest::binary>>) do
    case deletion_flag do
      0x20 -> {:ok, false}  # Active record
      0x2A -> {:ok, true}   # Deleted record
      _ -> {:ok, false}     # Treat other values as active (defensive)
    end
  end

  @doc """
  Parses record field data according to field descriptors.
  
  ## Parameters
  - `record_data` - Binary data for the record fields (without deletion flag)
  - `fields` - List of field descriptors
  
  ## Returns
  - `{:ok, %{field_name => parsed_value}}` - Parsed field data
  - `{:error, reason}` - Parse error
  """
  def parse_record_data(record_data, fields) do
    expected_length = Enum.sum(Enum.map(fields, & &1.length))
    
    if byte_size(record_data) != expected_length do
      {:error, :invalid_record_length}
    else
      parse_fields_from_record(record_data, fields, 0, %{})
    end
  end

  @doc """
  Reads a complete record from the DBF file at the specified index.
  
  ## Parameters
  - `dbf` - DBF file structure from open_dbf/1
  - `record_index` - Zero-based record index
  
  ## Returns
  - `{:ok, %Record{}}` - Successfully parsed record
  - `{:error, reason}` - Error reading or parsing record
  
  ## Examples
      iex> {:ok, dbf} = Xbase.Parser.open_dbf("data.dbf")
      iex> {:ok, record} = Xbase.Parser.read_record(dbf, 0)
      iex> record.data["NAME"]
      "John Doe"
  """
  def read_record(%{header: header, fields: fields, file: file}, record_index) do
    # Validate record index
    case is_valid_record_index?(header, record_index) do
      false ->
        {:error, :invalid_record_index}
      true ->
        # Calculate offset and read record
        offset = calculate_record_offset(header, record_index)
        
        case :file.pread(file, offset, header.record_length) do
          {:ok, record_binary} ->
            # Extract deletion flag
            case get_deletion_flag(record_binary) do
              {:ok, deleted} ->
                # Parse field data (skip deletion flag)
                <<_deletion_flag, field_data::binary>> = record_binary
                
                case parse_record_data(field_data, fields) do
                  {:ok, parsed_data} ->
                    record = %Record{
                      data: parsed_data,
                      deleted: deleted,
                      raw_data: record_binary
                    }
                    {:ok, record}
                  {:error, reason} ->
                    {:error, reason}
                end
              {:error, reason} ->
                {:error, reason}
            end
          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Creates a new DBF file with the specified field structure.
  
  ## Parameters
  - `path` - Path for the new DBF file
  - `fields` - List of field descriptors defining the schema
  - `opts` - Options (version, overwrite)
  
  ## Returns
  - `{:ok, dbf}` - Successfully created DBF file structure
  - `{:error, reason}` - Error creating file
  
  ## Examples
      iex> fields = [%FieldDescriptor{name: "NAME", type: "C", length: 20}]
      iex> {:ok, dbf} = Xbase.Parser.create_dbf("new.dbf", fields)
  """
  def create_dbf(path, fields, opts \\ []) do
    # Validate inputs
    case validate_create_inputs(path, fields, opts) do
      :ok ->
        case build_and_write_dbf(path, fields, opts) do
          {:ok, file} ->
            # Create DBF structure similar to open_dbf
            header = build_header(fields, opts)
            {:ok, %{header: header, fields: fields, file: file, file_path: path}}
          {:error, reason} ->
            {:error, reason}
        end
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Appends a new record to the DBF file.
  
  ## Parameters
  - `dbf` - DBF file structure from open_dbf/1 or create_dbf/2
  - `record_data` - Map of field name => value
  
  ## Returns
  - `{:ok, updated_dbf}` - Successfully appended with updated DBF structure
  - `{:error, reason}` - Error appending record
  
  ## Examples
      iex> {:ok, dbf} = Xbase.Parser.open_dbf("data.dbf")
      iex> {:ok, updated_dbf} = Xbase.Parser.append_record(dbf, %{"NAME" => "John", "AGE" => 30})
  """
  def append_record(%{header: header, fields: fields, file: file} = dbf, record_data) do
    # Encode the record data
    case encode_record(fields, record_data) do
      {:ok, encoded_record} ->
        # Calculate where to write the new record
        offset = calculate_record_offset(header, header.record_count)
        
        # Write the record
        case :file.pwrite(file, offset, encoded_record) do
          :ok ->
            # Update header with new record count and timestamp
            updated_header = update_header_for_append(header)
            
            # Write updated header to file
            case write_header(file, updated_header) do
              :ok ->
                {:ok, %{dbf | header: updated_header}}
              {:error, reason} ->
                {:error, reason}
            end
          {:error, reason} ->
            {:error, reason}
        end
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Reads all records from a DBF file.
  
  ## Parameters
  - `dbf` - DBF file structure from open_dbf/1
  
  ## Returns
  - `{:ok, [record_data]}` - List of record data maps
  - `{:error, reason}` - Error reading records
  
  ## Examples
      iex> {:ok, dbf} = Xbase.Parser.open_dbf("data.dbf")
      iex> {:ok, records} = Xbase.Parser.read_records(dbf)
      iex> length(records)
      10
  """
  def read_records(%{header: header} = dbf) do
    read_records_recursive(dbf, 0, header.record_count, [])
  end

  @doc """
  Updates an existing record in the DBF file.
  
  ## Parameters
  - `dbf` - DBF file structure from open_dbf/1
  - `record_index` - Zero-based index of the record to update
  - `update_data` - Map of field name => value for fields to update
  
  ## Returns
  - `{:ok, updated_dbf}` - Successfully updated with updated DBF structure
  - `{:error, reason}` - Error updating record
  
  ## Examples
      iex> {:ok, dbf} = Xbase.Parser.open_dbf("data.dbf")
      iex> {:ok, updated_dbf} = Xbase.Parser.update_record(dbf, 0, %{"NAME" => "Updated", "AGE" => 40})
  """
  def update_record(%{header: header, fields: fields, file: file} = dbf, record_index, update_data) do
    # Validate record index
    case is_valid_record_index?(header, record_index) do
      false ->
        {:error, :invalid_record_index}
      true ->
        # Read the existing record to preserve unmodified fields and deletion flag
        case read_record(dbf, record_index) do
          {:ok, existing_record} ->
            # Merge update data with existing data
            merged_data = Map.merge(existing_record.data, update_data)
            
            # Encode the updated record
            case encode_record_with_deletion_flag(fields, merged_data, existing_record.deleted) do
              {:ok, encoded_record} ->
                # Calculate where to write the updated record
                offset = calculate_record_offset(header, record_index)
                
                # Write the updated record
                case :file.pwrite(file, offset, encoded_record) do
                  :ok ->
                    # Update header timestamp only (not record count)
                    updated_header = update_header_timestamp(header)
                    
                    # Write updated header to file
                    case write_header(file, updated_header) do
                      :ok ->
                        {:ok, %{dbf | header: updated_header}}
                      {:error, reason} ->
                        {:error, reason}
                    end
                  {:error, reason} ->
                    {:error, reason}
                end
              {:error, reason} ->
                {:error, reason}
            end
          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Marks a record as deleted in the DBF file.
  
  ## Parameters
  - `dbf` - DBF file structure from open_dbf/1
  - `record_index` - Zero-based index of the record to mark as deleted
  
  ## Returns
  - `{:ok, updated_dbf}` - Successfully marked as deleted with updated DBF structure
  - `{:error, reason}` - Error marking record as deleted
  
  ## Examples
      iex> {:ok, dbf} = Xbase.Parser.open_dbf("data.dbf")
      iex> {:ok, updated_dbf} = Xbase.Parser.mark_deleted(dbf, 2)
  """
  def mark_deleted(%{header: header} = dbf, record_index) do
    case is_valid_record_index?(header, record_index) do
      false ->
        {:error, :invalid_record_index}
      true ->
        update_deletion_flag(dbf, record_index, true)
    end
  end

  @doc """
  Undeletes a previously deleted record in the DBF file.
  
  ## Parameters
  - `dbf` - DBF file structure from open_dbf/1
  - `record_index` - Zero-based index of the record to undelete
  
  ## Returns
  - `{:ok, updated_dbf}` - Successfully undeleted with updated DBF structure
  - `{:error, reason}` - Error undeleting record
  
  ## Examples
      iex> {:ok, dbf} = Xbase.Parser.open_dbf("data.dbf")
      iex> {:ok, updated_dbf} = Xbase.Parser.undelete_record(dbf, 2)
  """
  def undelete_record(%{header: header} = dbf, record_index) do
    case is_valid_record_index?(header, record_index) do
      false ->
        {:error, :invalid_record_index}
      true ->
        update_deletion_flag(dbf, record_index, false)
    end
  end

  @doc """
  Packs a DBF file by removing all deleted records and creating a compacted file.
  
  ## Parameters
  - `dbf` - DBF file structure from open_dbf/1
  - `output_path` - Path for the packed output file
  
  ## Returns
  - `{:ok, packed_dbf}` - Successfully packed DBF file structure
  - `{:error, reason}` - Error packing file
  
  ## Examples
      iex> {:ok, dbf} = Xbase.Parser.open_dbf("data.dbf")
      iex> {:ok, packed_dbf} = Xbase.Parser.pack(dbf, "data_packed.dbf")
  """
  def pack(%{header: header, fields: fields} = dbf, output_path) do
    # Collect all active (non-deleted) records
    case collect_active_records(dbf) do
      {:ok, active_records} ->
        # Create a new packed file with the active records
        case create_packed_file(output_path, fields, active_records, header) do
          {:ok, packed_dbf} ->
            {:ok, packed_dbf}
          {:error, reason} ->
            {:error, reason}
        end
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Counts the number of active (non-deleted) records in the DBF file.
  
  ## Parameters
  - `dbf` - DBF file structure from open_dbf/1
  
  ## Returns
  - `{:ok, count}` - Number of active records
  - `{:error, reason}` - Error reading records
  
  ## Examples
      iex> {:ok, dbf} = Xbase.Parser.open_dbf("data.dbf")
      iex> Xbase.Parser.count_active_records(dbf)
      {:ok, 150}
  """
  def count_active_records(%{header: header} = dbf) do
    count_records_by_status(dbf, header.record_count, false)
  end

  @doc """
  Counts the number of deleted records in the DBF file.
  
  ## Parameters
  - `dbf` - DBF file structure from open_dbf/1
  
  ## Returns
  - `{:ok, count}` - Number of deleted records
  - `{:error, reason}` - Error reading records
  
  ## Examples
      iex> {:ok, dbf} = Xbase.Parser.open_dbf("data.dbf")
      iex> Xbase.Parser.count_deleted_records(dbf)
      {:ok, 25}
  """
  def count_deleted_records(%{header: header} = dbf) do
    count_records_by_status(dbf, header.record_count, true)
  end

  @doc """
  Provides comprehensive statistics about records in the DBF file.
  
  ## Parameters
  - `dbf` - DBF file structure from open_dbf/1
  
  ## Returns
  - `{:ok, %{total_records: int, active_records: int, deleted_records: int, deletion_percentage: float}}` - Statistics
  - `{:error, reason}` - Error reading records
  
  ## Examples
      iex> {:ok, dbf} = Xbase.Parser.open_dbf("data.dbf")
      iex> Xbase.Parser.record_statistics(dbf)
      {:ok, %{total_records: 100, active_records: 85, deleted_records: 15, deletion_percentage: 15.0}}
  """
  def record_statistics(%{header: header} = dbf) do
    total_records = header.record_count
    
    if total_records == 0 do
      {:ok, %{
        total_records: 0,
        active_records: 0,
        deleted_records: 0,
        deletion_percentage: 0.0
      }}
    else
      case count_active_records(dbf) do
        {:ok, active_count} ->
          deleted_count = total_records - active_count
          deletion_percentage = (deleted_count / total_records) * 100.0
          
          {:ok, %{
            total_records: total_records,
            active_records: active_count,
            deleted_records: deleted_count,
            deletion_percentage: deletion_percentage
          }}
        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Deletes multiple records by their indices in a single operation.
  
  ## Parameters
  - `dbf` - DBF file structure from open_dbf/1
  - `indices` - List of record indices to delete
  
  ## Returns
  - `{:ok, updated_dbf}` - Successfully deleted records
  - `{:error, reason}` - Error during deletion
  
  ## Examples
      iex> {:ok, dbf} = Xbase.Parser.open_dbf("data.dbf", [:read, :write])
      iex> Xbase.Parser.batch_delete(dbf, [1, 5, 10])
      {:ok, updated_dbf}
  """
  def batch_delete(dbf, indices) when is_list(indices) do
    # Validate all indices first
    case validate_indices(dbf, indices) do
      :ok ->
        # Remove duplicates and sort for efficient processing
        unique_indices = indices |> Enum.uniq() |> Enum.sort()
        batch_delete_by_indices(dbf, unique_indices)
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Deletes records in a specified index range (inclusive).
  
  ## Parameters
  - `dbf` - DBF file structure from open_dbf/1
  - `start_index` - Starting index (inclusive)
  - `end_index` - Ending index (inclusive)
  
  ## Returns
  - `{:ok, updated_dbf}` - Successfully deleted records in range
  - `{:error, reason}` - Error during deletion
  
  ## Examples
      iex> {:ok, dbf} = Xbase.Parser.open_dbf("data.dbf", [:read, :write])
      iex> Xbase.Parser.batch_delete_range(dbf, 10, 20)
      {:ok, updated_dbf}
  """
  def batch_delete_range(%{header: header} = dbf, start_index, end_index) 
      when is_integer(start_index) and is_integer(end_index) do
    cond do
      start_index > end_index ->
        {:error, :invalid_range}
      start_index < 0 or end_index >= header.record_count ->
        {:error, :invalid_record_index}
      true ->
        indices = Enum.to_list(start_index..end_index)
        batch_delete_by_indices(dbf, indices)
    end
  end

  @doc """
  Deletes records that match a given condition function.
  
  ## Parameters
  - `dbf` - DBF file structure from open_dbf/1
  - `condition_fn` - Function that takes record data and returns true to delete
  
  ## Returns
  - `{:ok, updated_dbf}` - Successfully deleted matching records
  - `{:error, reason}` - Error during deletion
  
  ## Examples
      iex> {:ok, dbf} = Xbase.Parser.open_dbf("data.dbf", [:read, :write])
      iex> condition = fn record -> record["STATUS"] == "inactive" end
      iex> Xbase.Parser.batch_delete_where(dbf, condition)
      {:ok, updated_dbf}
  """
  def batch_delete_where(%{header: header} = dbf, condition_fn) when is_function(condition_fn, 1) do
    case find_matching_indices(dbf, header.record_count, condition_fn) do
      {:ok, matching_indices} ->
        batch_delete_by_indices(dbf, matching_indices)
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Executes a transaction function with rollback capability.
  
  ## Parameters
  - `dbf` - DBF file structure from open_dbf/1
  - `transaction_fn` - Function that takes a DBF and returns {:ok, updated_dbf} or {:error, reason}
  
  ## Returns
  - `{:ok, final_dbf}` - Successfully committed transaction
  - `{:error, reason}` - Transaction failed and was rolled back
  
  ## Examples
      iex> {:ok, dbf} = Xbase.Parser.open_dbf("data.dbf")
      iex> {:ok, final_dbf} = Xbase.Parser.transaction(dbf, fn dbf ->
      ...>   {:ok, dbf1} = Xbase.Parser.append_record(dbf, %{"NAME" => "John"})
      ...>   {:ok, dbf2} = Xbase.Parser.update_record(dbf1, 0, %{"STATUS" => "active"})
      ...>   {:ok, dbf2}
      ...> end)
  """
  def transaction(dbf, transaction_fn) when is_function(transaction_fn, 1) do
    # Get the file path from the DBF structure
    file_path = get_file_path(dbf)
    backup_path = file_path <> ".backup"
    
    # Close the current file to avoid descriptor conflicts
    close_dbf(dbf)
    
    # Create backup of the original file
    case create_backup(file_path, backup_path) do
      :ok ->
        # Reopen the file for the transaction with read-write access
        case open_dbf(file_path, [:read, :write]) do
          {:ok, reopened_dbf} ->
            try do
              # Execute the transaction function with the reopened DBF
              result = transaction_fn.(reopened_dbf)
              
              case result do
                {:ok, updated_dbf} ->
                  # Transaction succeeded - close file and clean up backup
                  close_dbf(updated_dbf)
                  cleanup_backup(backup_path)
                  # Return the final state by reopening the file
                  open_dbf(file_path, [:read, :write])
                
                {:error, reason} ->
                  # Transaction failed - close file and restore from backup
                  close_dbf(reopened_dbf)
                  restore_from_backup(file_path, backup_path)
                  {:error, reason}
                
                _invalid_return ->
                  # Invalid return value - close file and restore from backup
                  close_dbf(reopened_dbf)
                  restore_from_backup(file_path, backup_path)
                  {:error, :invalid_transaction_return}
              end
            rescue
              exception ->
                # Exception occurred - close file and restore from backup
                close_dbf(reopened_dbf)
                restore_from_backup(file_path, backup_path)
                {:error, exception}
            end
          
          {:error, reason} ->
            # Failed to reopen file - restore from backup
            restore_from_backup(file_path, backup_path)
            {:error, {:reopen_failed, reason}}
        end
      
      {:error, reason} ->
        {:error, {:backup_failed, reason}}
    end
  end

  # Private functions

  defp validate_create_inputs(path, fields, opts) do
    cond do
      length(fields) == 0 ->
        {:error, :no_fields}
      
      not valid_field_names?(fields) ->
        {:error, :invalid_field_name}
      
      File.exists?(path) and not Keyword.get(opts, :overwrite, false) ->
        {:error, :file_exists}
      
      true ->
        :ok
    end
  end

  defp valid_field_names?(fields) do
    Enum.all?(fields, fn field ->
      byte_size(field.name) <= 10 and byte_size(field.name) > 0
    end)
  end

  defp build_and_write_dbf(path, fields, opts) do
    version = Keyword.get(opts, :version, 0x03)
    
    # Calculate sizes
    field_count = length(fields)
    header_length = 32 + (field_count * 32) + 1  # header + fields + terminator
    record_length = 1 + Enum.sum(Enum.map(fields, & &1.length))  # deletion flag + field data
    
    # Get current date
    {{year, month, day}, _time} = :calendar.local_time()
    
    # Build header
    header_binary = <<
      version,
      year - 1900, month, day,   # last update date
      0::little-32,              # record count (initially 0)
      header_length::little-16,
      record_length::little-16,
      0::16,                     # reserved
      0, 0,                      # transaction, encryption flags
      0::12*8,                   # reserved (12 bytes)
      0, 0,                      # MDX flag, language driver
      0::16                      # reserved
    >>
    
    # Build field descriptors
    field_binaries = Enum.map(fields, &build_field_descriptor/1)
    fields_binary = Enum.join(field_binaries) <> <<0x0D>>  # Add terminator
    
    # Write complete file
    complete_binary = header_binary <> fields_binary
    
    case :file.open(path, [:write, :read, :binary, :random]) do
      {:ok, file} ->
        case :file.write(file, complete_binary) do
          :ok -> {:ok, file}
          {:error, reason} ->
            :file.close(file)
            {:error, reason}
        end
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_header(fields, opts) do
    version = Keyword.get(opts, :version, 0x03)
    field_count = length(fields)
    header_length = 32 + (field_count * 32) + 1
    record_length = 1 + Enum.sum(Enum.map(fields, & &1.length))
    
    {{year, month, day}, _time} = :calendar.local_time()
    
    %Header{
      version: version,
      last_update_year: year - 1900,
      last_update_month: month,
      last_update_day: day,
      record_count: 0,
      header_length: header_length,
      record_length: record_length,
      transaction_flag: 0,
      encryption_flag: 0,
      mdx_flag: 0,
      language_driver: 0
    }
  end

  defp build_field_descriptor(field) do
    # Pad name to 11 bytes with null bytes
    padded_name = String.pad_trailing(field.name, 11, <<0>>)
    
    <<
      padded_name::binary-size(11),
      field.type::binary-size(1),
      0::32,                    # data address (unused)
      field.length,
      field.decimal_count,
      0::16,                    # reserved
      0,                        # work area ID
      0::16,                    # reserved
      0,                        # set fields flag
      0::7*8,                   # reserved (7 bytes)
      0                         # index field flag
    >>
  end

  defp parse_fields_from_record(_data, [], _offset, acc) do
    {:ok, acc}
  end

  defp parse_fields_from_record(data, [field | rest_fields], offset, acc) do
    field_length = field.length
    
    case data do
      <<_::binary-size(offset), field_data::binary-size(field_length), _::binary>> ->
        case Xbase.FieldParser.parse(field, field_data) do
          {:ok, parsed_value} ->
            updated_acc = Map.put(acc, field.name, parsed_value)
            parse_fields_from_record(data, rest_fields, offset + field_length, updated_acc)
          {:error, reason} ->
            {:error, reason}
        end
      _ ->
        {:error, :invalid_record_length}
    end
  end

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

  defp encode_record(fields, record_data) do
    # Start with deletion flag (0x20 = active record)
    initial_binary = <<0x20>>
    
    # Encode each field
    encode_fields_recursive(fields, record_data, initial_binary)
  end

  defp encode_record_with_deletion_flag(fields, record_data, deleted) do
    # Use appropriate deletion flag
    deletion_flag = if deleted, do: <<0x2A>>, else: <<0x20>>
    
    # Encode each field
    encode_fields_recursive(fields, record_data, deletion_flag)
  end

  defp encode_fields_recursive([], _record_data, acc) do
    {:ok, acc}
  end

  defp encode_fields_recursive([field | rest], record_data, acc) do
    # Get value for field, using default if not provided
    value = Map.get(record_data, field.name, get_default_value(field.type))
    
    # Encode the field value
    case Xbase.FieldEncoder.encode(field, value) do
      {:ok, encoded_value} ->
        encode_fields_recursive(rest, record_data, acc <> encoded_value)
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_default_value(type) do
    case type do
      "C" -> ""          # Character - empty string
      "N" -> 0           # Numeric - zero
      "L" -> false       # Logical - false
      "D" -> nil         # Date - nil (will be encoded as spaces)
      "M" -> 0           # Memo - zero block reference
      _ -> ""            # Default to empty string
    end
  end

  defp update_header_for_append(header) do
    {{year, month, day}, _time} = :calendar.local_time()
    
    %{header |
      record_count: header.record_count + 1,
      last_update_year: year - 1900,
      last_update_month: month,
      last_update_day: day
    }
  end

  defp update_header_timestamp(header) do
    {{year, month, day}, _time} = :calendar.local_time()
    
    %{header |
      last_update_year: year - 1900,
      last_update_month: month,
      last_update_day: day
    }
  end

  defp write_header(file, header) do
    header_binary = <<
      header.version,
      header.last_update_year,
      header.last_update_month,
      header.last_update_day,
      header.record_count::little-32,
      header.header_length::little-16,
      header.record_length::little-16,
      0::16,                              # reserved
      header.transaction_flag,
      header.encryption_flag,
      0::12*8,                            # reserved (12 bytes)
      header.mdx_flag,
      header.language_driver,
      0::16                               # reserved
    >>
    
    :file.pwrite(file, 0, header_binary)
  end

  defp read_records_recursive(_dbf, index, max, acc) when index >= max do
    {:ok, Enum.reverse(acc)}
  end

  defp read_records_recursive(dbf, index, max, acc) do
    case read_record(dbf, index) do
      {:ok, record} ->
        # Only include non-deleted records
        if record.deleted do
          read_records_recursive(dbf, index + 1, max, acc)
        else
          read_records_recursive(dbf, index + 1, max, [record.data | acc])
        end
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp update_deletion_flag(%{header: header, file: file} = dbf, record_index, deleted) do
    # Calculate the offset to the deletion flag (first byte of the record)
    offset = calculate_record_offset(header, record_index)
    
    # Set the appropriate deletion flag
    deletion_flag = if deleted, do: <<0x2A>>, else: <<0x20>>
    
    # Write just the deletion flag
    case :file.pwrite(file, offset, deletion_flag) do
      :ok ->
        # Update header timestamp
        updated_header = update_header_timestamp(header)
        
        # Write updated header to file
        case write_header(file, updated_header) do
          :ok ->
            {:ok, %{dbf | header: updated_header}}
          {:error, reason} ->
            {:error, reason}
        end
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp collect_active_records(%{header: header} = dbf) do
    collect_active_records_recursive(dbf, 0, header.record_count, [])
  end

  defp collect_active_records_recursive(_dbf, index, max, acc) when index >= max do
    {:ok, Enum.reverse(acc)}
  end

  defp collect_active_records_recursive(dbf, index, max, acc) do
    case read_record(dbf, index) do
      {:ok, record} ->
        # Only collect non-deleted records
        if record.deleted do
          collect_active_records_recursive(dbf, index + 1, max, acc)
        else
          collect_active_records_recursive(dbf, index + 1, max, [record.data | acc])
        end
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_packed_file(output_path, fields, active_records, original_header) do
    # Calculate new record count
    active_count = length(active_records)
    
    # Build header for packed file
    field_count = length(fields)
    header_length = 32 + (field_count * 32) + 1
    record_length = 1 + Enum.sum(Enum.map(fields, & &1.length))
    
    {{year, month, day}, _time} = :calendar.local_time()
    
    # Create new header with updated record count and timestamp
    packed_header = %{original_header |
      record_count: active_count,
      header_length: header_length,
      record_length: record_length,
      last_update_year: year - 1900,
      last_update_month: month,
      last_update_day: day
    }
    
    # Build complete file binary
    header_binary = build_header_binary(packed_header)
    field_binaries = Enum.map(fields, &build_field_descriptor/1)
    fields_binary = Enum.join(field_binaries) <> <<0x0D>>
    
    # Encode all active records
    case encode_all_records(fields, active_records) do
      {:ok, records_binary} ->
        complete_binary = header_binary <> fields_binary <> records_binary
        
        # Write the packed file
        case :file.open(output_path, [:write, :read, :binary, :random]) do
          {:ok, file} ->
            case :file.write(file, complete_binary) do
              :ok ->
                {:ok, %{header: packed_header, fields: fields, file: file, file_path: output_path}}
              {:error, reason} ->
                :file.close(file)
                {:error, reason}
            end
          {:error, reason} ->
            {:error, reason}
        end
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_header_binary(header) do
    <<
      header.version,
      header.last_update_year,
      header.last_update_month,
      header.last_update_day,
      header.record_count::little-32,
      header.header_length::little-16,
      header.record_length::little-16,
      0::16,                              # reserved
      header.transaction_flag,
      header.encryption_flag,
      0::12*8,                            # reserved (12 bytes)
      header.mdx_flag,
      header.language_driver,
      0::16                               # reserved
    >>
  end

  defp encode_all_records(fields, records) do
    encode_all_records_recursive(fields, records, <<>>)
  end

  defp encode_all_records_recursive(_fields, [], acc) do
    {:ok, acc}
  end

  defp encode_all_records_recursive(fields, [record | rest], acc) do
    case encode_record(fields, record) do
      {:ok, encoded_record} ->
        encode_all_records_recursive(fields, rest, acc <> encoded_record)
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_indices(%{header: header}, indices) do
    invalid_indices = Enum.filter(indices, fn index ->
      index < 0 or index >= header.record_count
    end)
    
    if Enum.empty?(invalid_indices) do
      :ok
    else
      {:error, :invalid_record_index}
    end
  end

  defp batch_delete_by_indices(dbf, []) do
    {:ok, dbf}
  end

  defp batch_delete_by_indices(%{header: header, file: file} = dbf, indices) do
    # Process deletions efficiently by batching file writes
    case batch_write_deletion_flags(file, header, indices) do
      :ok ->
        # Update header timestamp once for the entire batch
        updated_header = update_header_timestamp(header)
        case write_header(file, updated_header) do
          :ok ->
            {:ok, %{dbf | header: updated_header}}
          {:error, reason} ->
            {:error, reason}
        end
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp batch_write_deletion_flags(file, header, indices) do
    deletion_flag = <<0x2A>>  # Deleted record flag
    
    # Create list of {offset, data} tuples for batch writing
    write_operations = Enum.map(indices, fn index ->
      offset = calculate_record_offset(header, index)
      {offset, deletion_flag}
    end)
    
    # Execute all writes
    batch_write_operations(file, write_operations)
  end

  defp batch_write_operations(_file, []) do
    :ok
  end

  defp batch_write_operations(file, [{offset, data} | rest]) do
    case :file.pwrite(file, offset, data) do
      :ok ->
        batch_write_operations(file, rest)
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp find_matching_indices(dbf, total_records, condition_fn) do
    find_matching_indices_recursive(dbf, 0, total_records, condition_fn, [])
  end

  defp find_matching_indices_recursive(_dbf, index, max, _condition_fn, acc) when index >= max do
    {:ok, Enum.reverse(acc)}
  end

  defp find_matching_indices_recursive(dbf, index, max, condition_fn, acc) do
    case read_record(dbf, index) do
      {:ok, record} ->
        # Only check condition for non-deleted records
        if not record.deleted and condition_fn.(record.data) do
          find_matching_indices_recursive(dbf, index + 1, max, condition_fn, [index | acc])
        else
          find_matching_indices_recursive(dbf, index + 1, max, condition_fn, acc)
        end
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp count_records_by_status(dbf, total_records, target_deleted_status) do
    count_records_by_status_recursive(dbf, 0, total_records, target_deleted_status, 0)
  end

  defp count_records_by_status_recursive(_dbf, index, max, _target_deleted_status, acc) when index >= max do
    {:ok, acc}
  end

  defp count_records_by_status_recursive(dbf, index, max, target_deleted_status, acc) do
    case read_record(dbf, index) do
      {:ok, record} ->
        new_acc = if record.deleted == target_deleted_status, do: acc + 1, else: acc
        count_records_by_status_recursive(dbf, index + 1, max, target_deleted_status, new_acc)
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_file_path(%{file_path: path}) do
    path
  end

  defp create_backup(source_path, backup_path) do
    case File.cp(source_path, backup_path) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp cleanup_backup(backup_path) do
    File.rm(backup_path)
    :ok
  end

  defp restore_from_backup(original_path, backup_path) do
    case File.cp(backup_path, original_path) do
      :ok -> 
        File.rm(backup_path)
        :ok
      {:error, reason} -> 
        {:error, reason}
    end
  end

end