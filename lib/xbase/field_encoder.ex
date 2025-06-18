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

  def encode(%FieldDescriptor{type: _type} = _field_desc, _value) do
    # Unknown field type
    {:error, :unknown_field_type}
  end
end