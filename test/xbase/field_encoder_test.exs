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
  end
end