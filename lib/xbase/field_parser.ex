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

  def parse(%FieldDescriptor{type: "I"} = _field_desc, binary_data) do
    # Integer field: 4-byte signed little-endian integer
    case byte_size(binary_data) do
      4 ->
        <<value::little-signed-32>> = binary_data
        {:ok, value}
      _ ->
        {:error, :invalid_integer_size}
    end
  end

  def parse(%FieldDescriptor{type: "T"} = _field_desc, binary_data) do
    # DateTime field: 8-byte timestamp (Julian day + milliseconds since midnight)
    case byte_size(binary_data) do
      8 ->
        <<julian_day::little-32, milliseconds::little-32>> = binary_data
        
        # Handle empty/null datetime (often represented as all zeros)
        case {julian_day, milliseconds} do
          {0, 0} -> {:ok, nil}
          _ ->
            # Convert Julian day to date
            case julian_to_date(julian_day) do
              {:ok, date} ->
                # Convert milliseconds to time
                case milliseconds_to_time(milliseconds) do
                  {:ok, time} ->
                    # Combine date and time into datetime
                    case DateTime.new(date, time, "Etc/UTC") do
                      {:ok, datetime} -> {:ok, datetime}
                      {:error, _} -> {:error, :invalid_datetime}
                    end
                  {:error, reason} -> {:error, reason}
                end
              {:error, reason} -> {:error, reason}
            end
        end
      _ ->
        {:error, :invalid_datetime_size}
    end
  end

  def parse(%FieldDescriptor{type: _type} = _field_desc, _binary_data) do
    # Unknown field type
    {:error, :unknown_field_type}
  end

  # Helper function to convert Julian day number to date
  defp julian_to_date(julian_day) do
    # Julian day calculation based on astronomical Julian day
    # This handles the conversion from Julian day number to Gregorian calendar
    try do
      # Algorithm from "Astronomical Algorithms" by Jean Meeus
      a = julian_day + 32044
      b = div(4 * a + 3, 146097)
      c = a - div(146097 * b, 4)
      d = div(4 * c + 3, 1461)
      e = c - div(1461 * d, 4)
      m = div(5 * e + 2, 153)
      
      day = e - div(153 * m + 2, 5) + 1
      month = m + 3 - 12 * div(m, 10)
      year = 100 * b + d - 4800 + div(m, 10)
      
      Date.new(year, month, day)
    rescue
      _ -> {:error, :invalid_julian_day}
    end
  end

  # Helper function to convert milliseconds since midnight to time
  defp milliseconds_to_time(milliseconds) do
    # Ensure milliseconds is within valid range (0 to 86399999 for 24 hours)
    if milliseconds >= 0 and milliseconds < 86_400_000 do
      total_seconds = div(milliseconds, 1000)
      remaining_milliseconds = rem(milliseconds, 1000)
      
      hours = div(total_seconds, 3600)
      minutes = div(rem(total_seconds, 3600), 60)
      seconds = rem(total_seconds, 60)
      
      # Convert milliseconds to microseconds for Time.new/4
      microseconds = remaining_milliseconds * 1000
      
      Time.new(hours, minutes, seconds, microseconds)
    else
      {:error, :invalid_time_milliseconds}
    end
  end
end