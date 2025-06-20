defmodule Xbase.TypesTest do
  use ExUnit.Case, async: true

  alias Xbase.Types.Header
  alias Xbase.Types.FieldDescriptor
  alias Xbase.Types.Record

  describe "Header struct" do
    test "has all required fields" do
      header = %Header{}
      
      # Basic DBF header fields
      assert Map.has_key?(header, :version)
      assert Map.has_key?(header, :last_update_year)
      assert Map.has_key?(header, :last_update_month)
      assert Map.has_key?(header, :last_update_day)
      assert Map.has_key?(header, :record_count)
      assert Map.has_key?(header, :header_length)
      assert Map.has_key?(header, :record_length)
      assert Map.has_key?(header, :transaction_flag)
      assert Map.has_key?(header, :encryption_flag)
      assert Map.has_key?(header, :mdx_flag)
      assert Map.has_key?(header, :language_driver)
    end

    test "can be created with values" do
      header = %Header{
        version: 0x03,
        last_update_year: 2024,
        last_update_month: 12,
        last_update_day: 17,
        record_count: 100,
        header_length: 161,
        record_length: 50
      }
      
      assert header.version == 0x03
      assert header.record_count == 100
      assert header.header_length == 161
      assert header.record_length == 50
    end
  end

  describe "FieldDescriptor struct" do
    test "has all required fields" do
      field = %FieldDescriptor{}
      
      assert Map.has_key?(field, :name)
      assert Map.has_key?(field, :type)
      assert Map.has_key?(field, :length)
      assert Map.has_key?(field, :decimal_count)
      assert Map.has_key?(field, :work_area_id)
      assert Map.has_key?(field, :set_fields_flag)
      assert Map.has_key?(field, :index_field_flag)
    end

    test "can be created with values" do
      field = %FieldDescriptor{
        name: "CUSTOMER_ID",
        type: "C",
        length: 10,
        decimal_count: 0
      }
      
      assert field.name == "CUSTOMER_ID"
      assert field.type == "C"
      assert field.length == 10
      assert field.decimal_count == 0
    end
  end

  describe "Record struct" do
    test "has all required fields" do
      record = %Record{}
      
      assert Map.has_key?(record, :data)
      assert Map.has_key?(record, :deleted)
      assert Map.has_key?(record, :raw_data)
    end

    test "can be created with parsed data" do
      data = %{"NAME" => "John Doe", "AGE" => 25, "ACTIVE" => true}
      record = %Record{
        data: data,
        deleted: false,
        raw_data: <<0x20, "John Doe  ", "25 ", "T">>
      }
      
      assert record.data == data
      assert record.deleted == false
      assert record.raw_data == <<0x20, "John Doe  ", "25 ", "T">>
    end

    test "can represent deleted record" do
      record = %Record{
        data: %{"NAME" => "Jane Doe", "AGE" => 30},
        deleted: true,
        raw_data: <<0x2A, "Jane Doe  ", "30 ">>
      }
      
      assert record.deleted == true
      assert record.data["NAME"] == "Jane Doe"
    end
  end
end