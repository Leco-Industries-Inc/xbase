defmodule Xbase.FieldParser do
  @moduledoc """
  Field parser for DBF data types.
  
  This module provides parsing functionality for different DBF field types,
  converting binary data to appropriate Elixir types based on field descriptors.
  """

  alias Xbase.Types.FieldDescriptor

  @doc """
  Parses field data based on the field descriptor.
  
  ## Parameters
  - `field_desc` - The field descriptor containing type and length information
  - `binary_data` - The raw binary data for this field
  
  ## Returns
  - `{:ok, parsed_value}` - Successfully parsed value
  - `{:error, reason}` - Parse error with reason
  
  ## Examples
      iex> field_desc = %FieldDescriptor{type: "C", length: 10}
      iex> Xbase.FieldParser.parse(field_desc, "John Doe  ")
      {:ok, "John Doe"}
  """
  def parse(%FieldDescriptor{type: "C"} = _field_desc, binary_data) do
    # Character field: trim trailing spaces
    trimmed = String.trim_trailing(binary_data)
    {:ok, trimmed}
  end

  def parse(%FieldDescriptor{type: "N", decimal_count: 0} = _field_desc, binary_data) do
    # Numeric field (integer)
    trimmed = String.trim(binary_data)
    
    case trimmed do
      "" -> {:ok, nil}  # Empty field
      _ ->
        case Integer.parse(trimmed) do
          {value, ""} -> {:ok, value}
          _ -> {:error, :invalid_numeric}
        end
    end
  end

  def parse(%FieldDescriptor{type: "N", decimal_count: decimal_count} = _field_desc, binary_data) 
      when decimal_count > 0 do
    # Numeric field (decimal)
    trimmed = String.trim(binary_data)
    
    case trimmed do
      "" -> {:ok, nil}  # Empty field
      _ ->
        case Float.parse(trimmed) do
          {value, ""} -> {:ok, value}
          _ -> {:error, :invalid_numeric}
        end
    end
  end

  def parse(%FieldDescriptor{type: "D"} = _field_desc, binary_data) do
    # Date field: YYYYMMDD format
    trimmed = String.trim(binary_data)
    
    case trimmed do
      "" -> {:ok, nil}  # Empty field
      <<year::binary-size(4), month::binary-size(2), day::binary-size(2)>> ->
        case {Integer.parse(year), Integer.parse(month), Integer.parse(day)} do
          {{y, ""}, {m, ""}, {d, ""}} ->
            case Date.new(y, m, d) do
              {:ok, date} -> {:ok, date}
              {:error, _} -> {:error, :invalid_date}
            end
          _ -> {:error, :invalid_date}
        end
      _ -> {:error, :invalid_date}
    end
  end

  def parse(%FieldDescriptor{type: "L"} = _field_desc, binary_data) do
    # Logical field: T/F, Y/N, or ?
    case String.upcase(String.trim(binary_data)) do
      "T" -> {:ok, true}
      "Y" -> {:ok, true}
      "F" -> {:ok, false}
      "N" -> {:ok, false}
      "?" -> {:ok, nil}
      "" -> {:ok, nil}  # Empty/space treated as unknown
      _ -> {:ok, nil}   # Any other value treated as unknown
    end
  end

  def parse(%FieldDescriptor{type: "M"} = _field_desc, binary_data) do
    # Memo field: reference to memo block
    trimmed = String.trim(binary_data)
    
    case trimmed do
      "" -> {:ok, nil}  # Empty memo reference
      _ ->
        case Integer.parse(trimmed) do
          {block_number, ""} -> {:ok, {:memo_ref, block_number}}
          _ -> {:ok, nil}  # Invalid memo reference treated as empty
        end
    end
  end

  def parse(%FieldDescriptor{type: _type} = _field_desc, _binary_data) do
    # Unknown field type
    {:error, :unknown_field_type}
  end
end