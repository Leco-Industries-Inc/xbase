defmodule Xbase.FieldEncoderTest do
  use ExUnit.Case, async: true

  alias Xbase.FieldEncoder
  alias Xbase.Types.FieldDescriptor

  describe "Character field encoding" do
    test "encodes character field with padding" do
      field_desc = %FieldDescriptor{name: "NAME", type: "C", length: 10, decimal_count: 0}
      value = "John Doe"
      
      assert {:ok, "John Doe  "} = FieldEncoder.encode(field_desc, value)
    end

    test "encodes empty character field" do
      field_desc = %FieldDescriptor{name: "NAME", type: "C", length: 5, decimal_count: 0}
      value = ""
      
      assert {:ok, "     "} = FieldEncoder.encode(field_desc, value)
    end

    test "truncates character field if too long" do
      field_desc = %FieldDescriptor{name: "DESC", type: "C", length: 5, decimal_count: 0}
      value = "This is way too long"
      
      assert {:ok, "This "} = FieldEncoder.encode(field_desc, value)
    end

    test "handles nil character field" do
      field_desc = %FieldDescriptor{name: "NAME", type: "C", length: 8, decimal_count: 0}
      value = nil
      
      assert {:ok, "        "} = FieldEncoder.encode(field_desc, value)
    end
  end

  describe "Numeric field encoding" do
    test "encodes integer numeric field" do
      field_desc = %FieldDescriptor{name: "AGE", type: "N", length: 3, decimal_count: 0}
      value = 25
      
      assert {:ok, " 25"} = FieldEncoder.encode(field_desc, value)
    end

    test "encodes decimal numeric field" do
      field_desc = %FieldDescriptor{name: "PRICE", type: "N", length: 6, decimal_count: 2}
      value = 12.50
      
      assert {:ok, " 12.50"} = FieldEncoder.encode(field_desc, value)
    end

    test "right-aligns numeric field with spaces" do
      field_desc = %FieldDescriptor{name: "COUNT", type: "N", length: 5, decimal_count: 0}
      value = 7
      
      assert {:ok, "    7"} = FieldEncoder.encode(field_desc, value)
    end

    test "handles nil numeric field" do
      field_desc = %FieldDescriptor{name: "COUNT", type: "N", length: 4, decimal_count: 0}
      value = nil
      
      assert {:ok, "    "} = FieldEncoder.encode(field_desc, value)
    end

    test "returns error for numeric field too large" do
      field_desc = %FieldDescriptor{name: "SMALL", type: "N", length: 3, decimal_count: 0}
      value = 1000  # Too large for 3 digits
      
      assert {:error, :field_too_large} = FieldEncoder.encode(field_desc, value)
    end

    test "returns error for invalid numeric type" do
      field_desc = %FieldDescriptor{name: "BAD", type: "N", length: 3, decimal_count: 0}
      value = "not a number"
      
      assert {:error, :invalid_type} = FieldEncoder.encode(field_desc, value)
    end
  end

  describe "Date field encoding" do
    test "encodes valid date in YYYYMMDD format" do
      field_desc = %FieldDescriptor{name: "BIRTH", type: "D", length: 8, decimal_count: 0}
      value = ~D[2024-03-15]
      
      assert {:ok, "20240315"} = FieldEncoder.encode(field_desc, value)
    end

    test "handles nil date field" do
      field_desc = %FieldDescriptor{name: "DATE", type: "D", length: 8, decimal_count: 0}
      value = nil
      
      assert {:ok, "        "} = FieldEncoder.encode(field_desc, value)
    end

    test "returns error for invalid date type" do
      field_desc = %FieldDescriptor{name: "BAD_DATE", type: "D", length: 8, decimal_count: 0}
      value = "2024-03-15"  # String instead of Date
      
      assert {:error, :invalid_type} = FieldEncoder.encode(field_desc, value)
    end
  end

  describe "Logical field encoding" do
    test "encodes true logical values" do
      field_desc = %FieldDescriptor{name: "ACTIVE", type: "L", length: 1, decimal_count: 0}
      
      assert {:ok, "T"} = FieldEncoder.encode(field_desc, true)
    end

    test "encodes false logical values" do
      field_desc = %FieldDescriptor{name: "ACTIVE", type: "L", length: 1, decimal_count: 0}
      
      assert {:ok, "F"} = FieldEncoder.encode(field_desc, false)
    end

    test "encodes nil logical value" do
      field_desc = %FieldDescriptor{name: "MAYBE", type: "L", length: 1, decimal_count: 0}
      
      assert {:ok, "?"} = FieldEncoder.encode(field_desc, nil)
    end

    test "returns error for invalid logical type" do
      field_desc = %FieldDescriptor{name: "BAD", type: "L", length: 1, decimal_count: 0}
      value = "maybe"
      
      assert {:error, :invalid_type} = FieldEncoder.encode(field_desc, value)
    end
  end

  describe "Memo field encoding" do
    test "encodes memo field reference" do
      field_desc = %FieldDescriptor{name: "NOTES", type: "M", length: 10, decimal_count: 0}
      value = {:memo_ref, 42}
      
      assert {:ok, "        42"} = FieldEncoder.encode(field_desc, value)
    end

    test "handles nil memo field" do
      field_desc = %FieldDescriptor{name: "NOTES", type: "M", length: 10, decimal_count: 0}
      value = nil
      
      assert {:ok, "          "} = FieldEncoder.encode(field_desc, value)
    end

    test "returns error for invalid memo type" do
      field_desc = %FieldDescriptor{name: "BAD", type: "M", length: 10, decimal_count: 0}
      value = "not a memo ref"
      
      assert {:error, :invalid_type} = FieldEncoder.encode(field_desc, value)
    end
  end

  describe "Integer field encoding (type I)" do
    test "encodes positive integer to binary" do
      field_desc = %FieldDescriptor{name: "ID", type: "I", length: 4, decimal_count: 0}
      value = 1000
      
      assert {:ok, <<1000::little-signed-32>>} = FieldEncoder.encode(field_desc, value)
    end

    test "encodes negative integer to binary" do
      field_desc = %FieldDescriptor{name: "ID", type: "I", length: 4, decimal_count: 0}
      value = -500
      
      assert {:ok, <<-500::little-signed-32>>} = FieldEncoder.encode(field_desc, value)
    end

    test "encodes zero integer to binary" do
      field_desc = %FieldDescriptor{name: "ID", type: "I", length: 4, decimal_count: 0}
      value = 0
      
      assert {:ok, <<0::little-signed-32>>} = FieldEncoder.encode(field_desc, value)
    end

    test "handles nil integer field" do
      field_desc = %FieldDescriptor{name: "ID", type: "I", length: 4, decimal_count: 0}
      value = nil
      
      assert {:ok, <<0::little-signed-32>>} = FieldEncoder.encode(field_desc, value)
    end

    test "converts float to integer" do
      field_desc = %FieldDescriptor{name: "ID", type: "I", length: 4, decimal_count: 0}
      value = 42.7
      
      assert {:ok, <<42::little-signed-32>>} = FieldEncoder.encode(field_desc, value)
    end

    test "returns error for integer out of range" do
      field_desc = %FieldDescriptor{name: "ID", type: "I", length: 4, decimal_count: 0}
      value = 3_000_000_000  # Larger than 32-bit signed integer max
      
      assert {:error, :integer_out_of_range} = FieldEncoder.encode(field_desc, value)
    end

    test "returns error for invalid integer type" do
      field_desc = %FieldDescriptor{name: "ID", type: "I", length: 4, decimal_count: 0}
      value = "not an integer"
      
      assert {:error, :invalid_type} = FieldEncoder.encode(field_desc, value)
    end
  end

  describe "DateTime field encoding (type T)" do
    test "encodes datetime to Julian day and milliseconds" do
      field_desc = %FieldDescriptor{name: "TIMESTAMP", type: "T", length: 8, decimal_count: 0}
      # 2024-03-15 14:30:45.123 UTC
      datetime = DateTime.new!(~D[2024-03-15], ~T[14:30:45.123], "Etc/UTC")
      
      assert {:ok, binary_result} = FieldEncoder.encode(field_desc, datetime)
      assert byte_size(binary_result) == 8
      
      # Verify we can parse it back
      alias Xbase.FieldParser
      assert {:ok, parsed_datetime} = FieldParser.parse(field_desc, binary_result)
      assert parsed_datetime.year == 2024
      assert parsed_datetime.month == 3
      assert parsed_datetime.day == 15
      assert parsed_datetime.hour == 14
      assert parsed_datetime.minute == 30
      assert parsed_datetime.second == 45
    end

    test "encodes naive datetime" do
      field_desc = %FieldDescriptor{name: "TIMESTAMP", type: "T", length: 8, decimal_count: 0}
      naive_datetime = NaiveDateTime.new!(~D[2024-01-01], ~T[00:00:00])
      
      assert {:ok, binary_result} = FieldEncoder.encode(field_desc, naive_datetime)
      assert byte_size(binary_result) == 8
      
      # Verify round-trip
      alias Xbase.FieldParser
      assert {:ok, parsed_datetime} = FieldParser.parse(field_desc, binary_result)
      assert parsed_datetime.year == 2024
      assert parsed_datetime.month == 1
      assert parsed_datetime.day == 1
      assert parsed_datetime.hour == 0
      assert parsed_datetime.minute == 0
      assert parsed_datetime.second == 0
    end

    test "handles nil datetime field" do
      field_desc = %FieldDescriptor{name: "TIMESTAMP", type: "T", length: 8, decimal_count: 0}
      value = nil
      
      assert {:ok, <<0::little-32, 0::little-32>>} = FieldEncoder.encode(field_desc, value)
    end

    test "handles timezone conversion" do
      field_desc = %FieldDescriptor{name: "TIMESTAMP", type: "T", length: 8, decimal_count: 0}
      # Create datetime already in a known timezone (UTC)
      utc_datetime = DateTime.new!(~D[2024-03-15], ~T[15:30:45], "Etc/UTC")
      
      assert {:ok, binary_result} = FieldEncoder.encode(field_desc, utc_datetime)
      
      # Verify it's properly encoded and can be parsed back
      alias Xbase.FieldParser
      assert {:ok, parsed_datetime} = FieldParser.parse(field_desc, binary_result)
      assert parsed_datetime.time_zone == "Etc/UTC"
      assert parsed_datetime.hour == 15
      assert parsed_datetime.minute == 30
      assert parsed_datetime.second == 45
    end

    test "returns error for invalid datetime type" do
      field_desc = %FieldDescriptor{name: "TIMESTAMP", type: "T", length: 8, decimal_count: 0}
      value = "2024-03-15 14:30:45"  # String instead of DateTime
      
      assert {:error, :invalid_type} = FieldEncoder.encode(field_desc, value)
    end
  end

  describe "Unknown field types" do
    test "returns error for unknown field type" do
      field_desc = %FieldDescriptor{name: "UNKNOWN", type: "X", length: 5, decimal_count: 0}
      value = "12345"
      
      assert {:error, :unknown_field_type} = FieldEncoder.encode(field_desc, value)
    end
  end

  describe "Round-trip encoding/decoding" do
    test "character field round trip" do
      field_desc = %FieldDescriptor{name: "NAME", type: "C", length: 10, decimal_count: 0}
      original_value = "John Doe"
      
      {:ok, encoded} = FieldEncoder.encode(field_desc, original_value)
      {:ok, decoded} = Xbase.FieldParser.parse(field_desc, encoded)
      
      assert decoded == original_value
    end

    test "numeric field round trip" do
      field_desc = %FieldDescriptor{name: "AGE", type: "N", length: 3, decimal_count: 0}
      original_value = 25
      
      {:ok, encoded} = FieldEncoder.encode(field_desc, original_value)
      {:ok, decoded} = Xbase.FieldParser.parse(field_desc, encoded)
      
      assert decoded == original_value
    end

    test "date field round trip" do
      field_desc = %FieldDescriptor{name: "BIRTH", type: "D", length: 8, decimal_count: 0}
      original_value = ~D[2024-03-15]
      
      {:ok, encoded} = FieldEncoder.encode(field_desc, original_value)
      {:ok, decoded} = Xbase.FieldParser.parse(field_desc, encoded)
      
      assert decoded == original_value
    end

    test "logical field round trip" do
      field_desc = %FieldDescriptor{name: "ACTIVE", type: "L", length: 1, decimal_count: 0}
      original_value = true
      
      {:ok, encoded} = FieldEncoder.encode(field_desc, original_value)
      {:ok, decoded} = Xbase.FieldParser.parse(field_desc, encoded)
      
      assert decoded == original_value
    end

    test "integer field round trip" do
      field_desc = %FieldDescriptor{name: "ID", type: "I", length: 4, decimal_count: 0}
      original_value = 42000
      
      {:ok, encoded} = FieldEncoder.encode(field_desc, original_value)
      {:ok, decoded} = Xbase.FieldParser.parse(field_desc, encoded)
      
      assert decoded == original_value
    end

    test "datetime field round trip" do
      field_desc = %FieldDescriptor{name: "TIMESTAMP", type: "T", length: 8, decimal_count: 0}
      original_value = DateTime.new!(~D[2024-03-15], ~T[14:30:45.123], "Etc/UTC")
      
      {:ok, encoded} = FieldEncoder.encode(field_desc, original_value)
      {:ok, decoded} = Xbase.FieldParser.parse(field_desc, encoded)
      
      # Compare main components (microsecond precision might differ slightly)
      assert decoded.year == original_value.year
      assert decoded.month == original_value.month
      assert decoded.day == original_value.day
      assert decoded.hour == original_value.hour
      assert decoded.minute == original_value.minute
      assert decoded.second == original_value.second
      # Check millisecond precision (123 milliseconds)
      {microseconds, _} = decoded.microsecond
      assert div(microseconds, 1000) == 123
    end
  end
end