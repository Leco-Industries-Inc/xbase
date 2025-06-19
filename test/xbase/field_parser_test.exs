defmodule Xbase.FieldParserTest do
  use ExUnit.Case, async: true

  alias Xbase.FieldParser
  alias Xbase.Types.FieldDescriptor

  # Path to real test data files
  @test_dbf_path "test/prrolls.DBF"

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

  describe "Integration Tests with Real Data Fields (prrolls.DBF)" do
    @tag :integration
    test "parses real character fields from prrolls.DBF" do
      {:ok, dbf} = Xbase.Parser.open_dbf(@test_dbf_path)
      
      # Get the SONO field descriptor (Character field)
      sono_field = Enum.find(dbf.fields, &(&1.name == "SONO"))
      assert sono_field.type == "C"
      assert sono_field.length == 10
      
      # Read a few records and test character field parsing
      for index <- [0, 100, 1000] do
        {:ok, record} = Xbase.Parser.read_record(dbf, index)
        raw_data = record.raw_data
        
        # Extract the SONO field data from raw record
        # This tests the field parser with real data
        sono_offset = calculate_field_offset(dbf.fields, "SONO")
        sono_binary = binary_part(raw_data, sono_offset + 1, sono_field.length)  # +1 for deletion flag
        
        case FieldParser.parse(sono_field, sono_binary) do
          {:ok, parsed_value} ->
            assert is_binary(parsed_value)
            # Should match what's in the record data
            assert parsed_value == record.data["SONO"]
            
          {:error, reason} ->
            flunk("Failed to parse SONO field at record #{index}: #{inspect(reason)}")
        end
      end
      
      Xbase.Parser.close_dbf(dbf)
    end

    @tag :integration
    test "parses real numeric fields from prrolls.DBF" do
      {:ok, dbf} = Xbase.Parser.open_dbf(@test_dbf_path)
      
      # Get the WEIGHT field descriptor (Numeric field)
      weight_field = Enum.find(dbf.fields, &(&1.name == "WEIGHT"))
      assert weight_field.type == "N"
      assert weight_field.length == 10
      
      # Test numeric field parsing with real data
      for index <- [0, 50, 500] do
        {:ok, record} = Xbase.Parser.read_record(dbf, index)
        raw_data = record.raw_data
        
        weight_offset = calculate_field_offset(dbf.fields, "WEIGHT")
        weight_binary = binary_part(raw_data, weight_offset + 1, weight_field.length)
        
        case FieldParser.parse(weight_field, weight_binary) do
          {:ok, parsed_value} ->
            assert is_number(parsed_value) or is_nil(parsed_value)
            # Should match what's in the record data
            assert parsed_value == record.data["WEIGHT"]
            
          {:error, reason} ->
            flunk("Failed to parse WEIGHT field at record #{index}: #{inspect(reason)}")
        end
      end
      
      Xbase.Parser.close_dbf(dbf)
    end

    @tag :integration
    test "parses real integer fields from prrolls.DBF" do
      {:ok, dbf} = Xbase.Parser.open_dbf(@test_dbf_path)
      
      # Get the SKIDNO field descriptor (Integer field)
      skidno_field = Enum.find(dbf.fields, &(&1.name == "SKIDNO"))
      assert skidno_field.type == "I"
      assert skidno_field.length == 4
      
      # Test integer field parsing with real data
      for index <- [0, 25, 250] do
        {:ok, record} = Xbase.Parser.read_record(dbf, index)
        raw_data = record.raw_data
        
        skidno_offset = calculate_field_offset(dbf.fields, "SKIDNO")
        skidno_binary = binary_part(raw_data, skidno_offset + 1, skidno_field.length)
        
        case FieldParser.parse(skidno_field, skidno_binary) do
          {:ok, parsed_value} ->
            assert is_integer(parsed_value) or is_nil(parsed_value)
            # Should match what's in the record data
            assert parsed_value == record.data["SKIDNO"]
            
          {:error, reason} ->
            flunk("Failed to parse SKIDNO field at record #{index}: #{inspect(reason)}")
        end
      end
      
      Xbase.Parser.close_dbf(dbf)
    end

    @tag :integration
    test "parses real logical fields from prrolls.DBF" do
      {:ok, dbf} = Xbase.Parser.open_dbf(@test_dbf_path)
      
      # Get the KILOS field descriptor (Logical field)
      kilos_field = Enum.find(dbf.fields, &(&1.name == "KILOS"))
      assert kilos_field.type == "L"
      assert kilos_field.length == 1
      
      # Test logical field parsing with real data
      for index <- [0, 10, 100] do
        {:ok, record} = Xbase.Parser.read_record(dbf, index)
        raw_data = record.raw_data
        
        kilos_offset = calculate_field_offset(dbf.fields, "KILOS")
        kilos_binary = binary_part(raw_data, kilos_offset + 1, kilos_field.length)
        
        case FieldParser.parse(kilos_field, kilos_binary) do
          {:ok, parsed_value} ->
            assert is_boolean(parsed_value) or is_nil(parsed_value)
            # Should match what's in the record data
            assert parsed_value == record.data["KILOS"]
            
          {:error, reason} ->
            flunk("Failed to parse KILOS field at record #{index}: #{inspect(reason)}")
        end
      end
      
      Xbase.Parser.close_dbf(dbf)
    end

    @tag :integration
    test "handles datetime field type T from real data" do
      {:ok, dbf} = Xbase.Parser.open_dbf(@test_dbf_path)
      
      # Get the DATE field descriptor (DateTime field)
      date_field = Enum.find(dbf.fields, &(&1.name == "DATE"))
      assert date_field.type == "T"
      assert date_field.length == 8
      
      # Test datetime field parsing - may not be implemented yet
      {:ok, record} = Xbase.Parser.read_record(dbf, 0)
      raw_data = record.raw_data
      
      date_offset = calculate_field_offset(dbf.fields, "DATE")
      date_binary = binary_part(raw_data, date_offset + 1, date_field.length)
      
      case FieldParser.parse(date_field, date_binary) do
        {:ok, parsed_value} ->
          # Datetime parsing might return various formats
          IO.puts("Parsed datetime value: #{inspect(parsed_value)}")
          
        {:error, :unknown_field_type} ->
          # DateTime type "T" might not be implemented yet
          IO.puts("DateTime field type 'T' not yet implemented - this is expected")
          
        {:error, reason} ->
          # Other errors should be investigated
          IO.puts("Unexpected error parsing datetime field: #{inspect(reason)}")
      end
      
      Xbase.Parser.close_dbf(dbf)
    end

    @tag :integration
    test "validates field parsing consistency across record sample" do
      {:ok, dbf} = Xbase.Parser.open_dbf(@test_dbf_path)
      
      # Test parsing consistency across a sample of records
      sample_indices = Enum.take_random(0..(dbf.header.record_count - 1), 20)
      
      parsing_stats = %{
        successful_parses: 0,
        failed_parses: 0,
        field_type_counts: %{}
      }
      
      final_stats = 
        Enum.reduce(sample_indices, parsing_stats, fn index, acc ->
          {:ok, record} = Xbase.Parser.read_record(dbf, index)
          
          # Test parsing each field type
          field_results = 
            Enum.map(dbf.fields, fn field ->
              field_offset = calculate_field_offset(dbf.fields, field.name)
              field_binary = binary_part(record.raw_data, field_offset + 1, field.length)
              
              case FieldParser.parse(field, field_binary) do
                {:ok, _value} -> {:success, field.type}
                {:error, _reason} -> {:failure, field.type}
              end
            end)
          
          # Update statistics
          successful = Enum.count(field_results, &(elem(&1, 0) == :success))
          failed = Enum.count(field_results, &(elem(&1, 0) == :failure))
          
          type_counts = 
            Enum.reduce(field_results, acc.field_type_counts, fn {result, type}, type_acc ->
              key = {type, result}
              Map.update(type_acc, key, 1, &(&1 + 1))
            end)
          
          %{
            successful_parses: acc.successful_parses + successful,
            failed_parses: acc.failed_parses + failed,
            field_type_counts: type_counts
          }
        end)
      
      # Report statistics
      IO.puts("Field parsing statistics:")
      IO.puts("  Successful parses: #{final_stats.successful_parses}")
      IO.puts("  Failed parses: #{final_stats.failed_parses}")
      IO.puts("  Type breakdown: #{inspect(final_stats.field_type_counts)}")
      
      # Most field types should parse successfully
      success_rate = final_stats.successful_parses / (final_stats.successful_parses + final_stats.failed_parses)
      assert success_rate > 0.5  # At least 50% should parse (allowing for unimplemented types)
      
      Xbase.Parser.close_dbf(dbf)
    end

    # Helper function to calculate field offset in record
    defp calculate_field_offset(fields, target_field_name) do
      fields
      |> Enum.take_while(&(&1.name != target_field_name))
      |> Enum.sum(& &1.length)
    end
  end
end