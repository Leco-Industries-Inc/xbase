defmodule Xbase.FieldEncoder do
  @moduledoc """
  Field encoder for DBF data types.
  
  This module provides encoding functionality for different DBF field types,
  converting Elixir values to binary data based on field descriptors.
  This is the reverse operation of Xbase.FieldParser.
  """

  alias Xbase.Types.FieldDescriptor

  @doc """
  Encodes a value to binary field data based on the field descriptor.
  
  ## Parameters
  - `field_desc` - The field descriptor containing type and length information
  - `value` - The Elixir value to encode
  
  ## Returns
  - `{:ok, binary_data}` - Successfully encoded binary
  - `{:error, reason}` - Encoding error with reason
  
  ## Examples
      iex> field_desc = %FieldDescriptor{type: "C", length: 10}
      iex> Xbase.FieldEncoder.encode(field_desc, "John Doe")
      {:ok, "John Doe  "}
  """
  def encode(%FieldDescriptor{type: "C", length: length} = _field_desc, value) do
    # Character field: pad with trailing spaces, truncate if necessary
    string_value = case value do
      nil -> ""
      val when is_binary(val) -> val
      val -> to_string(val)
    end
    
    cond do
      byte_size(string_value) == length ->
        {:ok, string_value}
      byte_size(string_value) < length ->
        padded = String.pad_trailing(string_value, length)
        {:ok, padded}
      byte_size(string_value) > length ->
        truncated = String.slice(string_value, 0, length)
        {:ok, truncated}
    end
  end

  def encode(%FieldDescriptor{type: "N", length: length, decimal_count: 0} = _field_desc, value) do
    # Numeric field (integer): right-align with spaces
    case value do
      nil -> 
        {:ok, String.duplicate(" ", length)}
      val when is_integer(val) ->
        string_val = Integer.to_string(val)
        if byte_size(string_val) > length do
          {:error, :field_too_large}
        else
          padded = String.pad_leading(string_val, length)
          {:ok, padded}
        end
      val when is_float(val) ->
        # Convert float to integer for integer fields
        string_val = Integer.to_string(trunc(val))
        if byte_size(string_val) > length do
          {:error, :field_too_large}
        else
          padded = String.pad_leading(string_val, length)
          {:ok, padded}
        end
      _ ->
        {:error, :invalid_type}
    end
  end

  def encode(%FieldDescriptor{type: "N", length: length, decimal_count: decimal_count} = _field_desc, value) 
      when decimal_count > 0 do
    # Numeric field (decimal): right-align with spaces
    case value do
      nil -> 
        {:ok, String.duplicate(" ", length)}
      val when is_number(val) ->
        # Format with proper decimal places
        string_val = :erlang.float_to_binary(val * 1.0, [{:decimals, decimal_count}])
        if byte_size(string_val) > length do
          {:error, :field_too_large}
        else
          padded = String.pad_leading(string_val, length)
          {:ok, padded}
        end
      _ ->
        {:error, :invalid_type}
    end
  end

  def encode(%FieldDescriptor{type: "D", length: 8} = _field_desc, value) do
    # Date field: YYYYMMDD format
    case value do
      nil -> 
        {:ok, "        "}
      %Date{} = date ->
        formatted = Date.to_string(date) |> String.replace("-", "")
        {:ok, formatted}
      _ ->
        {:error, :invalid_type}
    end
  end

  def encode(%FieldDescriptor{type: "L", length: 1} = _field_desc, value) do
    # Logical field: T/F/?
    case value do
      true -> {:ok, "T"}
      false -> {:ok, "F"}
      nil -> {:ok, "?"}
      _ -> {:error, :invalid_type}
    end
  end

  def encode(%FieldDescriptor{type: "M", length: length} = _field_desc, value) do
    # Memo field: reference to memo block (right-aligned)
    case value do
      nil -> 
        {:ok, String.duplicate(" ", length)}
      {:memo_ref, block_number} when is_integer(block_number) ->
        string_val = Integer.to_string(block_number)
        if byte_size(string_val) > length do
          {:error, :field_too_large}
        else
          padded = String.pad_leading(string_val, length)
          {:ok, padded}
        end
      _ ->
        {:error, :invalid_type}
    end
  end

  def encode(%FieldDescriptor{type: "I", length: 4} = _field_desc, value) do
    # Integer field: 4-byte signed little-endian integer
    case value do
      nil -> 
        # Null integer represented as zero
        {:ok, <<0::little-signed-32>>}
      val when is_integer(val) ->
        # Check if value fits in 32-bit signed integer range
        if val >= -2_147_483_648 and val <= 2_147_483_647 do
          {:ok, <<val::little-signed-32>>}
        else
          {:error, :integer_out_of_range}
        end
      val when is_float(val) ->
        # Convert float to integer
        int_val = trunc(val)
        if int_val >= -2_147_483_648 and int_val <= 2_147_483_647 do
          {:ok, <<int_val::little-signed-32>>}
        else
          {:error, :integer_out_of_range}
        end
      _ ->
        {:error, :invalid_type}
    end
  end

  def encode(%FieldDescriptor{type: "T", length: 8} = _field_desc, value) do
    # DateTime field: 8-byte timestamp (Julian day + milliseconds since midnight)
    case value do
      nil -> 
        # Null datetime represented as zeros
        {:ok, <<0::little-32, 0::little-32>>}
      %DateTime{} = datetime ->
        # Convert datetime to UTC if not already
        utc_datetime = DateTime.shift_zone!(datetime, "Etc/UTC")
        
        # Extract date and time components
        date_part = Date.new!(utc_datetime.year, utc_datetime.month, utc_datetime.day)
        time_part = Time.new!(utc_datetime.hour, utc_datetime.minute, utc_datetime.second, utc_datetime.microsecond)
        
        # Convert to Julian day and milliseconds
        case date_to_julian(date_part) do
          {:ok, julian_day} ->
            case time_to_milliseconds(time_part) do
              {:ok, milliseconds} ->
                {:ok, <<julian_day::little-32, milliseconds::little-32>>}
              {:error, reason} -> {:error, reason}
            end
          {:error, reason} -> {:error, reason}
        end
      %NaiveDateTime{} = naive_datetime ->
        # Treat naive datetime as UTC
        date_part = Date.new!(naive_datetime.year, naive_datetime.month, naive_datetime.day)
        time_part = Time.new!(naive_datetime.hour, naive_datetime.minute, naive_datetime.second, naive_datetime.microsecond)
        
        case date_to_julian(date_part) do
          {:ok, julian_day} ->
            case time_to_milliseconds(time_part) do
              {:ok, milliseconds} ->
                {:ok, <<julian_day::little-32, milliseconds::little-32>>}
              {:error, reason} -> {:error, reason}
            end
          {:error, reason} -> {:error, reason}
        end
      _ ->
        {:error, :invalid_type}
    end
  end

  def encode(%FieldDescriptor{type: _type} = _field_desc, _value) do
    # Unknown field type
    {:error, :unknown_field_type}
  end

  # Helper function to convert date to Julian day number
  defp date_to_julian(%Date{year: year, month: month, day: day}) do
    try do
      # Algorithm from "Astronomical Algorithms" by Jean Meeus
      # Handles the conversion from Gregorian calendar to Julian day number
      a = div(14 - month, 12)
      y = year + 4800 - a
      m = month + 12 * a - 3
      
      julian_day = day + div(153 * m + 2, 5) + 365 * y + div(y, 4) - div(y, 100) + div(y, 400) - 32045
      
      {:ok, julian_day}
    rescue
      _ -> {:error, :invalid_date_conversion}
    end
  end

  # Helper function to convert time to milliseconds since midnight
  defp time_to_milliseconds(%Time{hour: hour, minute: minute, second: second, microsecond: {microsecond, _}}) do
    try do
      total_milliseconds = (hour * 3600 + minute * 60 + second) * 1000 + div(microsecond, 1000)
      
      if total_milliseconds >= 0 and total_milliseconds < 86_400_000 do
        {:ok, total_milliseconds}
      else
        {:error, :invalid_time_range}
      end
    rescue
      _ -> {:error, :invalid_time_conversion}
    end
  end
end