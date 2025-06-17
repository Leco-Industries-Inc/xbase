defmodule Xbase.FieldParserTest do
  use ExUnit.Case, async: true

  alias Xbase.FieldParser
  alias Xbase.Types.FieldDescriptor

  describe "Character field parsing" do
    test "parses character field with trimming" do
      field_desc = %FieldDescriptor{name: "NAME", type: "C", length: 10, decimal_count: 0}
      binary_data = <<"John Doe  ">>  # 10 bytes with trailing spaces
      
      assert {:ok, "John Doe"} = FieldParser.parse(field_desc, binary_data)
    end

    test "handles empty character field" do
      field_desc = %FieldDescriptor{name: "NAME", type: "C", length: 5, decimal_count: 0}
      binary_data = <<"     ">>  # 5 spaces
      
      assert {:ok, ""} = FieldParser.parse(field_desc, binary_data)
    end

    test "handles character field with only spaces" do
      field_desc = %FieldDescriptor{name: "DESC", type: "C", length: 8, decimal_count: 0}
      binary_data = <<"        ">>  # 8 spaces
      
      assert {:ok, ""} = FieldParser.parse(field_desc, binary_data)
    end
  end

  describe "Numeric field parsing" do
    test "parses integer numeric field" do
      field_desc = %FieldDescriptor{name: "AGE", type: "N", length: 3, decimal_count: 0}
      binary_data = <<" 25">>  # Right-aligned with space
      
      assert {:ok, 25} = FieldParser.parse(field_desc, binary_data)
    end

    test "parses decimal numeric field" do
      field_desc = %FieldDescriptor{name: "PRICE", type: "N", length: 6, decimal_count: 2}
      binary_data = <<" 12.50">>  # Right-aligned decimal
      
      assert {:ok, 12.50} = FieldParser.parse(field_desc, binary_data)
    end

    test "handles empty numeric field" do
      field_desc = %FieldDescriptor{name: "COUNT", type: "N", length: 4, decimal_count: 0}
      binary_data = <<"    ">>  # All spaces
      
      assert {:ok, nil} = FieldParser.parse(field_desc, binary_data)
    end

    test "returns error for invalid numeric data" do
      field_desc = %FieldDescriptor{name: "BAD", type: "N", length: 3, decimal_count: 0}
      binary_data = <<"ABC">>  # Invalid numeric data
      
      assert {:error, :invalid_numeric} = FieldParser.parse(field_desc, binary_data)
    end
  end

  describe "Date field parsing" do
    test "parses valid date in YYYYMMDD format" do
      field_desc = %FieldDescriptor{name: "BIRTH", type: "D", length: 8, decimal_count: 0}
      binary_data = <<"20240315">>  # March 15, 2024
      
      assert {:ok, ~D[2024-03-15]} = FieldParser.parse(field_desc, binary_data)
    end

    test "handles empty date field" do
      field_desc = %FieldDescriptor{name: "DATE", type: "D", length: 8, decimal_count: 0}
      binary_data = <<"        ">>  # 8 spaces
      
      assert {:ok, nil} = FieldParser.parse(field_desc, binary_data)
    end

    test "returns error for invalid date format" do
      field_desc = %FieldDescriptor{name: "BAD_DATE", type: "D", length: 8, decimal_count: 0}
      binary_data = <<"ABCD1234">>  # Invalid date
      
      assert {:error, :invalid_date} = FieldParser.parse(field_desc, binary_data)
    end

    test "returns error for invalid date values" do
      field_desc = %FieldDescriptor{name: "BAD_DATE", type: "D", length: 8, decimal_count: 0}
      binary_data = <<"20241332">>  # Invalid day (32)
      
      assert {:error, :invalid_date} = FieldParser.parse(field_desc, binary_data)
    end
  end

  describe "Logical field parsing" do
    test "parses true logical values" do
      field_desc = %FieldDescriptor{name: "ACTIVE", type: "L", length: 1, decimal_count: 0}
      
      assert {:ok, true} = FieldParser.parse(field_desc, <<"T">>)
      assert {:ok, true} = FieldParser.parse(field_desc, <<"t">>)
      assert {:ok, true} = FieldParser.parse(field_desc, <<"Y">>)
      assert {:ok, true} = FieldParser.parse(field_desc, <<"y">>)
    end

    test "parses false logical values" do
      field_desc = %FieldDescriptor{name: "ACTIVE", type: "L", length: 1, decimal_count: 0}
      
      assert {:ok, false} = FieldParser.parse(field_desc, <<"F">>)
      assert {:ok, false} = FieldParser.parse(field_desc, <<"f">>)
      assert {:ok, false} = FieldParser.parse(field_desc, <<"N">>)
      assert {:ok, false} = FieldParser.parse(field_desc, <<"n">>)
    end

    test "parses unknown logical value" do
      field_desc = %FieldDescriptor{name: "MAYBE", type: "L", length: 1, decimal_count: 0}
      
      assert {:ok, nil} = FieldParser.parse(field_desc, <<"?">>)
      assert {:ok, nil} = FieldParser.parse(field_desc, <<" ">>)
    end
  end

  describe "Memo field parsing" do
    test "parses memo field reference" do
      field_desc = %FieldDescriptor{name: "NOTES", type: "M", length: 10, decimal_count: 0}
      binary_data = <<"        42">>  # Memo block reference
      
      assert {:ok, {:memo_ref, 42}} = FieldParser.parse(field_desc, binary_data)
    end

    test "handles empty memo field" do
      field_desc = %FieldDescriptor{name: "NOTES", type: "M", length: 10, decimal_count: 0}
      binary_data = <<"          ">>  # All spaces
      
      assert {:ok, nil} = FieldParser.parse(field_desc, binary_data)
    end
  end

  describe "Unknown field types" do
    test "returns error for unknown field type" do
      field_desc = %FieldDescriptor{name: "UNKNOWN", type: "X", length: 5, decimal_count: 0}
      binary_data = <<"12345">>
      
      assert {:error, :unknown_field_type} = FieldParser.parse(field_desc, binary_data)
    end
  end
end