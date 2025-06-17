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

  # Private functions

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
end