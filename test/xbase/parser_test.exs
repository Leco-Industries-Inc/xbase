defmodule Xbase.ParserTest do
  use ExUnit.Case, async: true

  alias Xbase.Parser
  alias Xbase.Types.Header
  alias Xbase.Types.FieldDescriptor
  alias Xbase.Types.Record

  describe "parse_header/1" do
    test "parses a valid dBase III header" do
      # Create a valid 32-byte dBase III header
      header_binary = <<
        0x03,           # version (dBase III)
        124, 12, 17,    # last update: 2024-12-17 (year=124, month=12, day=17)
        100::little-32, # record count: 100
        161::little-16, # header length: 161 bytes  
        50::little-16,  # record length: 50 bytes
        0::16,          # reserved
        0x00,           # transaction flag
        0x00,           # encryption flag
        0::12*8,        # reserved (12 bytes)
        0x00,           # MDX flag
        0x00,           # language driver
        0::16           # reserved
      >>

      assert {:ok, header} = Parser.parse_header(header_binary)
      assert %Header{} = header
      assert header.version == 0x03
      assert header.last_update_year == 124
      assert header.last_update_month == 12
      assert header.last_update_day == 17
      assert header.record_count == 100
      assert header.header_length == 161
      assert header.record_length == 50
      assert header.transaction_flag == 0x00
      assert header.encryption_flag == 0x00
      assert header.mdx_flag == 0x00
      assert header.language_driver == 0x00
    end

    test "parses a dBase IV header with MDX flag" do
      header_binary = <<
        0x8B,           # version (dBase IV with memo)
        124, 12, 17,    # last update: 2024-12-17
        250::little-32, # record count: 250
        193::little-16, # header length: 193 bytes
        75::little-16,  # record length: 75 bytes
        0::16,          # reserved
        0x00,           # transaction flag
        0x00,           # encryption flag
        0::12*8,        # reserved (12 bytes)
        0x01,           # MDX flag (has index)
        0x00,           # language driver
        0::16           # reserved
      >>

      assert {:ok, header} = Parser.parse_header(header_binary)
      assert header.version == 0x8B
      assert header.record_count == 250
      assert header.header_length == 193
      assert header.record_length == 75
      assert header.mdx_flag == 0x01
    end

    test "returns error for invalid header size" do
      short_binary = <<0x03, 124, 12>>
      assert {:error, :invalid_header_size} = Parser.parse_header(short_binary)
    end

    test "returns error for invalid version" do
      invalid_header = <<
        0xFF,           # invalid version
        124, 12, 17,    # last update
        100::little-32, # record count
        161::little-16, # header length
        50::little-16,  # record length
        0::16,          # reserved
        0x00,           # transaction flag
        0x00,           # encryption flag
        0::12*8,        # reserved
        0x00,           # MDX flag
        0x00,           # language driver
        0::16           # reserved
      >>

      assert {:error, :invalid_version} = Parser.parse_header(invalid_header)
    end
  end

  describe "parse_fields/2" do
    test "parses field descriptors until terminator" do
      # Create field descriptors: NAME (C,10), AGE (N,3), ACTIVE (L,1) + terminator
      fields_binary = <<
        # Field 1: NAME (Character, 10 bytes)
        "NAME", 0, 0, 0, 0, 0, 0, 0,  # name (11 bytes, null-padded)
        "C",                           # type
        0, 0, 0, 0,                   # data address (unused)
        10,                           # length
        0,                            # decimal count
        0, 0,                         # reserved
        0,                            # work area ID
        0, 0,                         # reserved
        0,                            # set fields flag
        0, 0, 0, 0, 0, 0, 0,         # reserved
        0,                            # index field flag
        
        # Field 2: AGE (Numeric, 3 bytes)
        "AGE", 0, 0, 0, 0, 0, 0, 0, 0, # name (11 bytes)
        "N",                           # type
        0, 0, 0, 0,                   # data address
        3,                            # length
        0,                            # decimal count
        0, 0,                         # reserved
        0,                            # work area ID
        0, 0,                         # reserved
        0,                            # set fields flag
        0, 0, 0, 0, 0, 0, 0,         # reserved
        0,                            # index field flag
        
        # Field 3: ACTIVE (Logical, 1 byte)
        "ACTIVE", 0, 0, 0, 0, 0,      # name (11 bytes)
        "L",                          # type
        0, 0, 0, 0,                   # data address
        1,                            # length
        0,                            # decimal count
        0, 0,                         # reserved
        0,                            # work area ID
        0, 0,                         # reserved
        0,                            # set fields flag
        0, 0, 0, 0, 0, 0, 0,         # reserved
        0,                            # index field flag
        
        0x0D                          # field terminator
      >>

      assert {:ok, fields} = Parser.parse_fields(fields_binary, 0)
      assert length(fields) == 3

      [name_field, age_field, active_field] = fields

      assert %FieldDescriptor{} = name_field
      assert name_field.name == "NAME"
      assert name_field.type == "C"
      assert name_field.length == 10
      assert name_field.decimal_count == 0

      assert age_field.name == "AGE"
      assert age_field.type == "N"
      assert age_field.length == 3

      assert active_field.name == "ACTIVE"
      assert active_field.type == "L"
      assert active_field.length == 1
    end

    test "returns error for missing terminator" do
      # Single field without terminator
      incomplete_binary = <<
        "NAME", 0, 0, 0, 0, 0, 0, 0,  # name
        "C",                           # type
        0, 0, 0, 0,                   # data address
        10,                           # length
        0,                            # decimal count
        0, 0,                         # reserved
        0,                            # work area ID
        0, 0,                         # reserved
        0,                            # set fields flag
        0, 0, 0, 0, 0, 0, 0,         # reserved
        0                             # index field flag (no terminator)
      >>

      assert {:error, :missing_field_terminator} = Parser.parse_fields(incomplete_binary, 0)
    end
  end

  describe "file I/O functions" do
    test "open_dbf/1 opens DBF file and parses header and fields" do
      # Create a temporary DBF file for testing
      temp_path = create_test_dbf_file()
      
      assert {:ok, dbf} = Parser.open_dbf(temp_path)
      assert %{header: header, fields: fields, file: file} = dbf
      assert %Header{} = header
      assert is_list(fields)
      assert length(fields) == 2  # NAME and AGE fields
      assert is_pid(file) or is_port(file)  # file handle
      
      # Clean up
      Parser.close_dbf(dbf)
      File.rm(temp_path)
    end

    test "close_dbf/1 closes file handle" do
      temp_path = create_test_dbf_file()
      {:ok, dbf} = Parser.open_dbf(temp_path)
      
      assert :ok = Parser.close_dbf(dbf)
      
      # File should be closed now, attempting to read should fail
      assert {:error, _} = :file.read(dbf.file, 10)
      
      File.rm(temp_path)
    end

    test "open_dbf/1 returns error for non-existent file" do
      assert {:error, :enoent} = Parser.open_dbf("non_existent_file.dbf")
    end

    test "open_dbf/1 returns error for invalid DBF file" do
      # Create invalid file (32 bytes but invalid version)
      temp_path = "/tmp/invalid.dbf"
      invalid_data = <<0xFF>> <> :binary.copy(<<0>>, 31)  # Invalid version + 31 zero bytes
      File.write!(temp_path, invalid_data)
      
      assert {:error, :invalid_version} = Parser.open_dbf(temp_path)
      
      File.rm(temp_path)
    end
  end

  # Helper function to create a test DBF file
  defp create_test_dbf_file do
    temp_path = "/tmp/test_#{:rand.uniform(10000)}.dbf"
    
    # Create a minimal valid DBF file with header + 2 fields + terminator
    header = <<
      0x03,           # version (dBase III)
      124, 12, 17,    # last update: 2024-12-17
      0::little-32,   # record count: 0 (no data records)
      97::little-16,  # header length: 32 + (2 * 32) + 1 = 97 bytes
      21::little-16,  # record length: 10 + 3 + 1 (deletion flag) + padding = 21 bytes
      0::16,          # reserved
      0x00,           # transaction flag
      0x00,           # encryption flag
      0::12*8,        # reserved (12 bytes)
      0x00,           # MDX flag
      0x00,           # language driver
      0::16           # reserved
    >>
    
    # Field 1: NAME (Character, 10 bytes)
    field1 = <<
      "NAME", 0, 0, 0, 0, 0, 0, 0,  # name (11 bytes)
      "C",                           # type
      0, 0, 0, 0,                   # data address
      10,                           # length
      0,                            # decimal count
      0, 0,                         # reserved
      0,                            # work area ID
      0, 0,                         # reserved
      0,                            # set fields flag
      0, 0, 0, 0, 0, 0, 0,         # reserved
      0                             # index field flag
    >>
    
    # Field 2: AGE (Numeric, 3 bytes)
    field2 = <<
      "AGE", 0, 0, 0, 0, 0, 0, 0, 0, # name (11 bytes)
      "N",                           # type
      0, 0, 0, 0,                   # data address
      3,                            # length
      0,                            # decimal count
      0, 0,                         # reserved
      0,                            # work area ID
      0, 0,                         # reserved
      0,                            # set fields flag
      0, 0, 0, 0, 0, 0, 0,         # reserved
      0                             # index field flag
    >>
    
    # Field terminator
    terminator = <<0x0D>>
    
    # Write the complete DBF file
    File.write!(temp_path, header <> field1 <> field2 <> terminator)
    
    temp_path
  end

  describe "record navigation functions" do
    test "calculate_record_offset/2 calculates correct offset for record" do
      header = %Header{header_length: 97, record_length: 25}
      
      assert 97 = Parser.calculate_record_offset(header, 0)   # First record
      assert 122 = Parser.calculate_record_offset(header, 1)  # Second record (97 + 25)
      assert 147 = Parser.calculate_record_offset(header, 2)  # Third record (97 + 50)
      assert 172 = Parser.calculate_record_offset(header, 3)  # Fourth record (97 + 75)
    end

    test "calculate_record_offset/2 handles zero-based indexing" do
      header = %Header{header_length: 65, record_length: 30}
      
      # Record 0 starts immediately after header
      assert 65 = Parser.calculate_record_offset(header, 0)
      # Each subsequent record is offset by record_length
      assert 95 = Parser.calculate_record_offset(header, 1)
      assert 125 = Parser.calculate_record_offset(header, 2)
    end

    test "is_valid_record_index?/2 validates record indices" do
      header = %Header{record_count: 10}
      
      assert true == Parser.is_valid_record_index?(header, 0)
      assert true == Parser.is_valid_record_index?(header, 5)
      assert true == Parser.is_valid_record_index?(header, 9)  # Last valid record
      assert false == Parser.is_valid_record_index?(header, 10) # Beyond record count
      assert false == Parser.is_valid_record_index?(header, -1) # Negative index
    end

    test "get_deletion_flag/1 extracts deletion status from record data" do
      active_record = <<0x20, "John Doe  ", "25 ", "T">>  # 0x20 = active
      deleted_record = <<0x2A, "Jane Doe  ", "30 ", "F">> # 0x2A = deleted
      
      assert {:ok, false} = Parser.get_deletion_flag(active_record)
      assert {:ok, true} = Parser.get_deletion_flag(deleted_record)
    end

    test "get_deletion_flag/1 returns error for empty data" do
      assert {:error, :invalid_record_data} = Parser.get_deletion_flag(<<>>)
    end

    test "parse_record_data/2 parses record fields according to field descriptors" do
      fields = [
        %FieldDescriptor{name: "NAME", type: "C", length: 10, decimal_count: 0},
        %FieldDescriptor{name: "AGE", type: "N", length: 3, decimal_count: 0},
        %FieldDescriptor{name: "ACTIVE", type: "L", length: 1, decimal_count: 0}
      ]
      
      # Skip deletion flag (first byte) and parse field data
      record_data = <<"John Doe  ", " 25", "T">>
      
      assert {:ok, parsed_data} = Parser.parse_record_data(record_data, fields)
      assert parsed_data["NAME"] == "John Doe"
      assert parsed_data["AGE"] == 25
      assert parsed_data["ACTIVE"] == true
    end

    test "parse_record_data/2 handles mismatched record length" do
      fields = [
        %FieldDescriptor{name: "NAME", type: "C", length: 10, decimal_count: 0}
      ]
      
      short_data = <<"John">>  # Only 4 bytes, expected 10
      
      assert {:error, :invalid_record_length} = Parser.parse_record_data(short_data, fields)
    end
  end

  describe "read_record/2" do
    test "reads and parses a complete record" do
      # Create a DBF file with actual data records
      temp_path = create_test_dbf_with_data()
      
      {:ok, dbf} = Parser.open_dbf(temp_path)
      
      # Read first record
      assert {:ok, record} = Parser.read_record(dbf, 0)
      assert %Record{} = record
      assert record.deleted == false
      assert record.data["NAME"] == "John Doe"
      assert record.data["AGE"] == 25
      
      # Read second record (should be deleted)
      assert {:ok, record2} = Parser.read_record(dbf, 1)
      assert record2.deleted == true
      assert record2.data["NAME"] == "Jane Smith"
      assert record2.data["AGE"] == 30
      
      Parser.close_dbf(dbf)
      File.rm(temp_path)
    end

    test "returns error for invalid record index" do
      temp_path = create_test_dbf_with_data()
      {:ok, dbf} = Parser.open_dbf(temp_path)
      
      # Try to read beyond available records
      assert {:error, :invalid_record_index} = Parser.read_record(dbf, 10)
      assert {:error, :invalid_record_index} = Parser.read_record(dbf, -1)
      
      Parser.close_dbf(dbf)
      File.rm(temp_path)
    end

    test "returns error for file read failure" do
      temp_path = create_test_dbf_with_data()
      {:ok, dbf} = Parser.open_dbf(temp_path)
      
      # Close the file to simulate read failure
      Parser.close_dbf(dbf)
      
      # Now try to read - should fail
      assert {:error, _reason} = Parser.read_record(dbf, 0)
      
      File.rm(temp_path)
    end
  end

  # Helper function to create a test DBF file with actual data records
  defp create_test_dbf_with_data do
    temp_path = "/tmp/test_data_#{:rand.uniform(10000)}.dbf"
    
    # Create header for 2 records
    header = <<
      0x03,           # version (dBase III)
      124, 12, 17,    # last update: 2024-12-17
      2::little-32,   # record count: 2 records
      97::little-16,  # header length: 32 + (2 * 32) + 1 = 97 bytes
      14::little-16,  # record length: 10 + 3 + 1 (deletion flag) = 14 bytes
      0::16,          # reserved
      0x00,           # transaction flag
      0x00,           # encryption flag
      0::12*8,        # reserved (12 bytes)
      0x00,           # MDX flag
      0x00,           # language driver
      0::16           # reserved
    >>
    
    # Field 1: NAME (Character, 10 bytes)
    field1 = <<
      "NAME", 0, 0, 0, 0, 0, 0, 0,  # name (11 bytes)
      "C",                           # type
      0, 0, 0, 0,                   # data address
      10,                           # length
      0,                            # decimal count
      0, 0,                         # reserved
      0,                            # work area ID
      0, 0,                         # reserved
      0,                            # set fields flag
      0, 0, 0, 0, 0, 0, 0,         # reserved
      0                             # index field flag
    >>
    
    # Field 2: AGE (Numeric, 3 bytes)
    field2 = <<
      "AGE", 0, 0, 0, 0, 0, 0, 0, 0, # name (11 bytes)
      "N",                           # type
      0, 0, 0, 0,                   # data address
      3,                            # length
      0,                            # decimal count
      0, 0,                         # reserved
      0,                            # work area ID
      0, 0,                         # reserved
      0,                            # set fields flag
      0, 0, 0, 0, 0, 0, 0,         # reserved
      0                             # index field flag
    >>
    
    # Field terminator
    terminator = <<0x0D>>
    
    # Record 1: Active record - John Doe, 25
    record1 = <<
      0x20,           # active record flag
      "John Doe  ",   # NAME field (10 bytes - note extra space)
      " 25"           # AGE field (3 bytes)
    >>
    
    # Record 2: Deleted record - Jane Smith, 30
    record2 = <<
      0x2A,           # deleted record flag
      "Jane Smith",   # NAME field (10 bytes) 
      " 30"           # AGE field (3 bytes)
    >>
    
    # Write the complete DBF file with data
    File.write!(temp_path, header <> field1 <> field2 <> terminator <> record1 <> record2)
    
    temp_path
  end

  describe "create_dbf/2" do
    test "creates a new DBF file with field definitions" do
      temp_path = "/tmp/test_create_#{:rand.uniform(10000)}.dbf"
      
      fields = [
        %FieldDescriptor{name: "NAME", type: "C", length: 20, decimal_count: 0},
        %FieldDescriptor{name: "AGE", type: "N", length: 3, decimal_count: 0},
        %FieldDescriptor{name: "ACTIVE", type: "L", length: 1, decimal_count: 0}
      ]
      
      assert {:ok, dbf} = Parser.create_dbf(temp_path, fields)
      
      # Verify the file was created and is readable
      assert File.exists?(temp_path)
      
      # Verify we can open and read the created file
      Parser.close_dbf(dbf)
      {:ok, reopened_dbf} = Parser.open_dbf(temp_path)
      
      # Check header
      assert reopened_dbf.header.version == 0x03  # dBase III
      assert reopened_dbf.header.record_count == 0  # No records yet
      assert reopened_dbf.header.header_length == 129  # 32 + (3 * 32) + 1
      assert reopened_dbf.header.record_length == 25  # 20 + 3 + 1 + deletion flag
      
      # Check fields
      assert length(reopened_dbf.fields) == 3
      [name_field, age_field, active_field] = reopened_dbf.fields
      
      assert name_field.name == "NAME"
      assert name_field.type == "C"
      assert name_field.length == 20
      
      assert age_field.name == "AGE"
      assert age_field.type == "N"
      assert age_field.length == 3
      
      assert active_field.name == "ACTIVE"
      assert active_field.type == "L"
      assert active_field.length == 1
      
      Parser.close_dbf(reopened_dbf)
      File.rm(temp_path)
    end

    test "creates DBF file with custom version" do
      temp_path = "/tmp/test_create_v4_#{:rand.uniform(10000)}.dbf"
      
      fields = [
        %FieldDescriptor{name: "ID", type: "N", length: 5, decimal_count: 0}
      ]
      
      assert {:ok, dbf} = Parser.create_dbf(temp_path, fields, version: 0x04)
      
      Parser.close_dbf(dbf)
      {:ok, reopened_dbf} = Parser.open_dbf(temp_path)
      
      assert reopened_dbf.header.version == 0x04  # dBase IV
      
      Parser.close_dbf(reopened_dbf)
      File.rm(temp_path)
    end

    test "returns error for invalid field definitions" do
      temp_path = "/tmp/test_invalid_#{:rand.uniform(10000)}.dbf"
      
      # Empty fields list
      assert {:error, :no_fields} = Parser.create_dbf(temp_path, [])
      
      # Field with invalid name (too long)
      invalid_fields = [
        %FieldDescriptor{name: "THIS_NAME_IS_TOO_LONG", type: "C", length: 10, decimal_count: 0}
      ]
      assert {:error, :invalid_field_name} = Parser.create_dbf(temp_path, invalid_fields)
      
      refute File.exists?(temp_path)
    end

    test "returns error for existing file without overwrite option" do
      temp_path = "/tmp/test_existing_#{:rand.uniform(10000)}.dbf"
      
      # Create an existing file
      File.write!(temp_path, "existing content")
      
      fields = [
        %FieldDescriptor{name: "TEST", type: "C", length: 5, decimal_count: 0}
      ]
      
      assert {:error, :file_exists} = Parser.create_dbf(temp_path, fields)
      
      File.rm(temp_path)
    end

    test "overwrites existing file with overwrite option" do
      temp_path = "/tmp/test_overwrite_#{:rand.uniform(10000)}.dbf"
      
      # Create an existing file
      File.write!(temp_path, "existing content")
      
      fields = [
        %FieldDescriptor{name: "TEST", type: "C", length: 5, decimal_count: 0}
      ]
      
      assert {:ok, dbf} = Parser.create_dbf(temp_path, fields, overwrite: true)
      
      # Verify it's a valid DBF file now
      Parser.close_dbf(dbf)
      assert {:ok, _reopened} = Parser.open_dbf(temp_path)
      
      File.rm(temp_path)
    end
  end

  describe "append_record/2" do
    setup do
      # Create a test DBF file
      temp_path = "/tmp/test_append_#{:rand.uniform(10000)}.dbf"
      
      fields = [
        %FieldDescriptor{name: "NAME", type: "C", length: 20, decimal_count: 0},
        %FieldDescriptor{name: "AGE", type: "N", length: 3, decimal_count: 0},
        %FieldDescriptor{name: "ACTIVE", type: "L", length: 1, decimal_count: 0},
        %FieldDescriptor{name: "JOINED", type: "D", length: 8, decimal_count: 0}
      ]
      
      {:ok, dbf} = Parser.create_dbf(temp_path, fields)
      
      on_exit(fn ->
        File.rm(temp_path)
      end)
      
      {:ok, path: temp_path, dbf: dbf}
    end

    test "appends a record with valid data", %{path: path, dbf: dbf} do
      record_data = %{
        "NAME" => "John Doe",
        "AGE" => 30,
        "ACTIVE" => true,
        "JOINED" => ~D[2024-01-15]
      }
      
      assert {:ok, updated_dbf} = Parser.append_record(dbf, record_data)
      assert updated_dbf.header.record_count == 1
      
      # Read the record back
      Parser.close_dbf(updated_dbf)
      {:ok, dbf2} = Parser.open_dbf(path)
      assert dbf2.header.record_count == 1
      
      {:ok, records} = Parser.read_records(dbf2)
      assert length(records) == 1
      
      record = hd(records)
      assert record["NAME"] == "John Doe"
      assert record["AGE"] == 30
      assert record["ACTIVE"] == true
      assert record["JOINED"] == ~D[2024-01-15]
      
      Parser.close_dbf(dbf2)
    end

    test "appends multiple records", %{path: path, dbf: dbf} do
      records = [
        %{"NAME" => "Alice", "AGE" => 25, "ACTIVE" => true, "JOINED" => ~D[2024-01-01]},
        %{"NAME" => "Bob", "AGE" => 35, "ACTIVE" => false, "JOINED" => ~D[2024-02-01]},
        %{"NAME" => "Charlie", "AGE" => 45, "ACTIVE" => true, "JOINED" => ~D[2024-03-01]}
      ]
      
      # Append records one by one
      {:ok, dbf1} = Parser.append_record(dbf, Enum.at(records, 0))
      {:ok, dbf2} = Parser.append_record(dbf1, Enum.at(records, 1))
      {:ok, dbf3} = Parser.append_record(dbf2, Enum.at(records, 2))
      
      assert dbf3.header.record_count == 3
      
      # Verify all records
      Parser.close_dbf(dbf3)
      {:ok, dbf_read} = Parser.open_dbf(path)
      {:ok, read_records} = Parser.read_records(dbf_read)
      
      assert length(read_records) == 3
      assert Enum.at(read_records, 0)["NAME"] == "Alice"
      assert Enum.at(read_records, 1)["NAME"] == "Bob"
      assert Enum.at(read_records, 2)["NAME"] == "Charlie"
      
      Parser.close_dbf(dbf_read)
    end

    test "handles missing fields with defaults", %{dbf: dbf} do
      # Only provide some fields
      record_data = %{
        "NAME" => "Incomplete"
      }
      
      assert {:ok, updated_dbf} = Parser.append_record(dbf, record_data)
      
      # Read back and check defaults
      {:ok, records} = Parser.read_records(updated_dbf)
      
      record = hd(records)
      assert record["NAME"] == "Incomplete"
      assert record["AGE"] == 0  # Numeric default
      assert record["ACTIVE"] == false  # Logical default
      assert record["JOINED"] == nil  # Date default (empty)
    end

    test "validates field values", %{dbf: dbf} do
      # Invalid age value
      record_data = %{
        "NAME" => "Test",
        "AGE" => "not a number"
      }
      
      assert {:error, _} = Parser.append_record(dbf, record_data)
    end

    test "handles string truncation", %{dbf: dbf} do
      # Name longer than field length (20)
      record_data = %{
        "NAME" => "This is a very long name that exceeds the field length"
      }
      
      assert {:ok, updated_dbf} = Parser.append_record(dbf, record_data)
      
      # Read back and verify truncation
      {:ok, records} = Parser.read_records(updated_dbf)
      
      record = hd(records)
      # Check that it's truncated to 20 characters (may be trimmed)
      assert String.length(record["NAME"]) <= 20
      assert String.starts_with?(record["NAME"], "This is a very long")
    end

    test "preserves existing records when appending", %{dbf: dbf} do
      # Add first record
      {:ok, dbf1} = Parser.append_record(dbf, %{"NAME" => "First", "AGE" => 10})
      
      # Add second record
      {:ok, dbf2} = Parser.append_record(dbf1, %{"NAME" => "Second", "AGE" => 20})
      
      # Read all records
      {:ok, records} = Parser.read_records(dbf2)
      
      assert length(records) == 2
      assert Enum.at(records, 0)["NAME"] == "First"
      assert Enum.at(records, 0)["AGE"] == 10
      assert Enum.at(records, 1)["NAME"] == "Second"
      assert Enum.at(records, 1)["AGE"] == 20
    end

    test "updates header timestamp on append", %{path: path, dbf: dbf} do
      # Append a record
      {:ok, updated_dbf} = Parser.append_record(dbf, %{"NAME" => "Test"})
      
      # Check that record count increased
      assert updated_dbf.header.record_count == 1
      
      # Verify it persists
      Parser.close_dbf(updated_dbf)
      {:ok, dbf2} = Parser.open_dbf(path)
      assert dbf2.header.record_count == 1
      
      # The date should be current
      {{year, month, day}, _} = :calendar.local_time()
      assert dbf2.header.last_update_year == year - 1900
      assert dbf2.header.last_update_month == month
      assert dbf2.header.last_update_day == day
      
      Parser.close_dbf(dbf2)
    end
  end

  describe "update_record/3" do
    setup do
      # Create a test DBF file with some records
      temp_path = "/tmp/test_update_#{:rand.uniform(10000)}.dbf"
      
      fields = [
        %FieldDescriptor{name: "ID", type: "N", length: 5, decimal_count: 0},
        %FieldDescriptor{name: "NAME", type: "C", length: 20, decimal_count: 0},
        %FieldDescriptor{name: "AGE", type: "N", length: 3, decimal_count: 0},
        %FieldDescriptor{name: "ACTIVE", type: "L", length: 1, decimal_count: 0},
        %FieldDescriptor{name: "JOINED", type: "D", length: 8, decimal_count: 0}
      ]
      
      {:ok, dbf} = Parser.create_dbf(temp_path, fields)
      
      # Add some initial records
      {:ok, dbf1} = Parser.append_record(dbf, %{
        "ID" => 1,
        "NAME" => "Alice",
        "AGE" => 25,
        "ACTIVE" => true,
        "JOINED" => ~D[2024-01-01]
      })
      
      {:ok, dbf2} = Parser.append_record(dbf1, %{
        "ID" => 2,
        "NAME" => "Bob",
        "AGE" => 30,
        "ACTIVE" => false,
        "JOINED" => ~D[2024-02-01]
      })
      
      {:ok, dbf3} = Parser.append_record(dbf2, %{
        "ID" => 3,
        "NAME" => "Charlie",
        "AGE" => 35,
        "ACTIVE" => true,
        "JOINED" => ~D[2024-03-01]
      })
      
      on_exit(fn ->
        File.rm(temp_path)
      end)
      
      {:ok, path: temp_path, dbf: dbf3}
    end

    test "updates a record with new data", %{path: path, dbf: dbf} do
      # Update Bob's record (index 1)
      update_data = %{
        "NAME" => "Robert",
        "AGE" => 31,
        "ACTIVE" => true
      }
      
      assert {:ok, updated_dbf} = Parser.update_record(dbf, 1, update_data)
      
      # Read the updated record
      {:ok, record} = Parser.read_record(updated_dbf, 1)
      assert record.data["ID"] == 2  # ID unchanged
      assert record.data["NAME"] == "Robert"  # Updated
      assert record.data["AGE"] == 31  # Updated
      assert record.data["ACTIVE"] == true  # Updated
      assert record.data["JOINED"] == ~D[2024-02-01]  # Unchanged
      
      # Verify it persists
      Parser.close_dbf(updated_dbf)
      {:ok, dbf2} = Parser.open_dbf(path)
      {:ok, record2} = Parser.read_record(dbf2, 1)
      assert record2.data["NAME"] == "Robert"
      Parser.close_dbf(dbf2)
    end

    test "partial update preserves unspecified fields", %{dbf: dbf} do
      # Update only the age
      update_data = %{"AGE" => 26}
      
      assert {:ok, updated_dbf} = Parser.update_record(dbf, 0, update_data)
      
      # Check that other fields are preserved
      {:ok, record} = Parser.read_record(updated_dbf, 0)
      assert record.data["ID"] == 1
      assert record.data["NAME"] == "Alice"  # Unchanged
      assert record.data["AGE"] == 26  # Updated
      assert record.data["ACTIVE"] == true  # Unchanged
      assert record.data["JOINED"] == ~D[2024-01-01]  # Unchanged
    end

    test "validates record index", %{dbf: dbf} do
      # Invalid index (negative)
      assert {:error, :invalid_record_index} = Parser.update_record(dbf, -1, %{"AGE" => 50})
      
      # Invalid index (too large)
      assert {:error, :invalid_record_index} = Parser.update_record(dbf, 10, %{"AGE" => 50})
    end

    test "validates field values", %{dbf: dbf} do
      # Invalid type for AGE
      update_data = %{"AGE" => "not a number"}
      
      assert {:error, _} = Parser.update_record(dbf, 0, update_data)
    end

    test "handles string truncation on update", %{dbf: dbf} do
      # Update with a long name
      update_data = %{
        "NAME" => "This is a very long name that exceeds the field length"
      }
      
      assert {:ok, updated_dbf} = Parser.update_record(dbf, 0, update_data)
      
      # Verify truncation
      {:ok, record} = Parser.read_record(updated_dbf, 0)
      assert String.length(record.data["NAME"]) <= 20
      assert String.starts_with?(record.data["NAME"], "This is a very long")
    end

    test "updates multiple records independently", %{dbf: dbf} do
      # Update first record
      {:ok, dbf1} = Parser.update_record(dbf, 0, %{"AGE" => 26})
      
      # Update third record
      {:ok, dbf2} = Parser.update_record(dbf1, 2, %{"NAME" => "Chuck"})
      
      # Verify all records
      {:ok, records} = Parser.read_records(dbf2)
      assert Enum.at(records, 0)["AGE"] == 26
      assert Enum.at(records, 0)["NAME"] == "Alice"  # Unchanged
      assert Enum.at(records, 1)["NAME"] == "Bob"  # Unchanged
      assert Enum.at(records, 2)["NAME"] == "Chuck"  # Updated
      assert Enum.at(records, 2)["AGE"] == 35  # Unchanged
    end

    test "preserves deletion flag when updating", %{dbf: dbf} do
      # First, mark a record as deleted using our function
      {:ok, dbf_with_deletion} = Parser.mark_deleted(dbf, 1)
      
      # Now update the deleted record
      update_data = %{"NAME" => "Updated Bob"}
      {:ok, updated_dbf} = Parser.update_record(dbf_with_deletion, 1, update_data)
      
      # Verify the record is still marked as deleted
      {:ok, record} = Parser.read_record(updated_dbf, 1)
      assert record.deleted == true
      assert record.data["NAME"] == "Updated Bob"
      
      # Verify deleted records don't appear in read_records
      {:ok, records} = Parser.read_records(updated_dbf)
      assert length(records) == 2  # Only 2 active records
    end

    test "updates header timestamp on update", %{path: path, dbf: dbf} do
      # Update a record
      {:ok, updated_dbf} = Parser.update_record(dbf, 0, %{"AGE" => 26})
      
      # Check that record count stayed the same
      assert updated_dbf.header.record_count == 3
      
      # Verify timestamp is current
      Parser.close_dbf(updated_dbf)
      {:ok, dbf2} = Parser.open_dbf(path)
      
      {{year, month, day}, _} = :calendar.local_time()
      assert dbf2.header.last_update_year == year - 1900
      assert dbf2.header.last_update_month == month
      assert dbf2.header.last_update_day == day
      
      Parser.close_dbf(dbf2)
    end
  end

  describe "mark_deleted/2" do
    setup do
      # Create a test DBF file with some records
      temp_path = "/tmp/test_delete_#{:rand.uniform(10000)}.dbf"
      
      fields = [
        %FieldDescriptor{name: "ID", type: "N", length: 5, decimal_count: 0},
        %FieldDescriptor{name: "NAME", type: "C", length: 20, decimal_count: 0},
        %FieldDescriptor{name: "STATUS", type: "L", length: 1, decimal_count: 0}
      ]
      
      {:ok, dbf} = Parser.create_dbf(temp_path, fields)
      
      # Add some initial records
      {:ok, dbf1} = Parser.append_record(dbf, %{"ID" => 1, "NAME" => "Alice", "STATUS" => true})
      {:ok, dbf2} = Parser.append_record(dbf1, %{"ID" => 2, "NAME" => "Bob", "STATUS" => false})
      {:ok, dbf3} = Parser.append_record(dbf2, %{"ID" => 3, "NAME" => "Charlie", "STATUS" => true})
      
      on_exit(fn ->
        File.rm(temp_path)
      end)
      
      {:ok, path: temp_path, dbf: dbf3}
    end

    test "marks a record as deleted", %{path: path, dbf: dbf} do
      # Mark the second record (Bob) as deleted
      assert {:ok, updated_dbf} = Parser.mark_deleted(dbf, 1)
      
      # Verify the record is marked as deleted
      {:ok, record} = Parser.read_record(updated_dbf, 1)
      assert record.deleted == true
      assert record.data["NAME"] == "Bob"  # Data should still be there
      
      # Verify it persists
      Parser.close_dbf(updated_dbf)
      {:ok, dbf2} = Parser.open_dbf(path)
      {:ok, record2} = Parser.read_record(dbf2, 1)
      assert record2.deleted == true
      Parser.close_dbf(dbf2)
    end

    test "deleted records don't appear in read_records", %{dbf: dbf} do
      # Initially all 3 records are active
      {:ok, records} = Parser.read_records(dbf)
      assert length(records) == 3
      
      # Mark one record as deleted
      {:ok, updated_dbf} = Parser.mark_deleted(dbf, 1)
      
      # Only 2 records should appear now
      {:ok, records} = Parser.read_records(updated_dbf)
      assert length(records) == 2
      assert Enum.at(records, 0)["NAME"] == "Alice"
      assert Enum.at(records, 1)["NAME"] == "Charlie"
      # Bob should be missing from the list
    end

    test "validates record index", %{dbf: dbf} do
      # Invalid index (negative)
      assert {:error, :invalid_record_index} = Parser.mark_deleted(dbf, -1)
      
      # Invalid index (too large)
      assert {:error, :invalid_record_index} = Parser.mark_deleted(dbf, 10)
    end

    test "can mark already deleted records", %{dbf: dbf} do
      # Mark record as deleted
      {:ok, dbf1} = Parser.mark_deleted(dbf, 1)
      
      # Mark it again - should succeed
      assert {:ok, dbf2} = Parser.mark_deleted(dbf1, 1)
      
      # Should still be deleted
      {:ok, record} = Parser.read_record(dbf2, 1)
      assert record.deleted == true
    end

    test "updates header timestamp on deletion", %{path: path, dbf: dbf} do
      # Mark a record as deleted
      {:ok, updated_dbf} = Parser.mark_deleted(dbf, 0)
      
      # Check that record count stayed the same
      assert updated_dbf.header.record_count == 3
      
      # Verify timestamp is current
      Parser.close_dbf(updated_dbf)
      {:ok, dbf2} = Parser.open_dbf(path)
      
      {{year, month, day}, _} = :calendar.local_time()
      assert dbf2.header.last_update_year == year - 1900
      assert dbf2.header.last_update_month == month
      assert dbf2.header.last_update_day == day
      
      Parser.close_dbf(dbf2)
    end

    test "marks multiple records independently", %{dbf: dbf} do
      # Mark first and third records as deleted
      {:ok, dbf1} = Parser.mark_deleted(dbf, 0)
      {:ok, dbf2} = Parser.mark_deleted(dbf1, 2)
      
      # Verify deletion status
      {:ok, record0} = Parser.read_record(dbf2, 0)
      {:ok, record1} = Parser.read_record(dbf2, 1)
      {:ok, record2} = Parser.read_record(dbf2, 2)
      
      assert record0.deleted == true
      assert record1.deleted == false
      assert record2.deleted == true
      
      # Only middle record should appear in read_records
      {:ok, records} = Parser.read_records(dbf2)
      assert length(records) == 1
      assert hd(records)["NAME"] == "Bob"
    end
  end

  describe "undelete_record/2" do
    setup do
      # Create a test DBF file with some records, some already deleted
      temp_path = "/tmp/test_undelete_#{:rand.uniform(10000)}.dbf"
      
      fields = [
        %FieldDescriptor{name: "ID", type: "N", length: 5, decimal_count: 0},
        %FieldDescriptor{name: "NAME", type: "C", length: 20, decimal_count: 0},
        %FieldDescriptor{name: "STATUS", type: "L", length: 1, decimal_count: 0}
      ]
      
      {:ok, dbf} = Parser.create_dbf(temp_path, fields)
      
      # Add some initial records
      {:ok, dbf1} = Parser.append_record(dbf, %{"ID" => 1, "NAME" => "Alice", "STATUS" => true})
      {:ok, dbf2} = Parser.append_record(dbf1, %{"ID" => 2, "NAME" => "Bob", "STATUS" => false})
      {:ok, dbf3} = Parser.append_record(dbf2, %{"ID" => 3, "NAME" => "Charlie", "STATUS" => true})
      
      # Mark the second record as deleted
      {:ok, dbf4} = Parser.mark_deleted(dbf3, 1)
      
      on_exit(fn ->
        File.rm(temp_path)
      end)
      
      {:ok, path: temp_path, dbf: dbf4}
    end

    test "undeletes a deleted record", %{path: path, dbf: dbf} do
      # Verify record is initially deleted
      {:ok, record} = Parser.read_record(dbf, 1)
      assert record.deleted == true
      
      # Undelete the record
      assert {:ok, updated_dbf} = Parser.undelete_record(dbf, 1)
      
      # Verify the record is no longer deleted
      {:ok, record} = Parser.read_record(updated_dbf, 1)
      assert record.deleted == false
      assert record.data["NAME"] == "Bob"  # Data should still be there
      
      # Verify it persists
      Parser.close_dbf(updated_dbf)
      {:ok, dbf2} = Parser.open_dbf(path)
      {:ok, record2} = Parser.read_record(dbf2, 1)
      assert record2.deleted == false
      Parser.close_dbf(dbf2)
    end

    test "undeleted records appear in read_records", %{dbf: dbf} do
      # Initially only 2 records are active (one is deleted)
      {:ok, records} = Parser.read_records(dbf)
      assert length(records) == 2
      
      # Undelete the deleted record
      {:ok, updated_dbf} = Parser.undelete_record(dbf, 1)
      
      # Now all 3 records should appear
      {:ok, records} = Parser.read_records(updated_dbf)
      assert length(records) == 3
      
      # Verify Bob is back in the list
      names = Enum.map(records, & &1["NAME"])
      assert "Alice" in names
      assert "Bob" in names
      assert "Charlie" in names
    end

    test "validates record index", %{dbf: dbf} do
      # Invalid index (negative)
      assert {:error, :invalid_record_index} = Parser.undelete_record(dbf, -1)
      
      # Invalid index (too large)
      assert {:error, :invalid_record_index} = Parser.undelete_record(dbf, 10)
    end

    test "can undelete already active records", %{dbf: dbf} do
      # Undelete an already active record (index 0)
      assert {:ok, updated_dbf} = Parser.undelete_record(dbf, 0)
      
      # Should still be active
      {:ok, record} = Parser.read_record(updated_dbf, 0)
      assert record.deleted == false
    end

    test "updates header timestamp on undeletion", %{path: path, dbf: dbf} do
      # Undelete a record
      {:ok, updated_dbf} = Parser.undelete_record(dbf, 1)
      
      # Check that record count stayed the same
      assert updated_dbf.header.record_count == 3
      
      # Verify timestamp is current
      Parser.close_dbf(updated_dbf)
      {:ok, dbf2} = Parser.open_dbf(path)
      
      {{year, month, day}, _} = :calendar.local_time()
      assert dbf2.header.last_update_year == year - 1900
      assert dbf2.header.last_update_month == month
      assert dbf2.header.last_update_day == day
      
      Parser.close_dbf(dbf2)
    end

    test "delete and undelete cycle works correctly", %{dbf: dbf} do
      # Start with record 0 active
      {:ok, record} = Parser.read_record(dbf, 0)
      assert record.deleted == false
      
      # Delete it
      {:ok, dbf1} = Parser.mark_deleted(dbf, 0)
      {:ok, record} = Parser.read_record(dbf1, 0)
      assert record.deleted == true
      
      # Undelete it
      {:ok, dbf2} = Parser.undelete_record(dbf1, 0)
      {:ok, record} = Parser.read_record(dbf2, 0)
      assert record.deleted == false
      
      # Data should be intact
      assert record.data["NAME"] == "Alice"
      assert record.data["ID"] == 1
    end
  end

  describe "pack/2" do
    setup do
      # Create a test DBF file with some records, some deleted
      temp_path = "/tmp/test_pack_#{:rand.uniform(10000)}.dbf"
      
      fields = [
        %FieldDescriptor{name: "ID", type: "N", length: 5, decimal_count: 0},
        %FieldDescriptor{name: "NAME", type: "C", length: 20, decimal_count: 0},
        %FieldDescriptor{name: "STATUS", type: "L", length: 1, decimal_count: 0}
      ]
      
      {:ok, dbf} = Parser.create_dbf(temp_path, fields)
      
      # Add some initial records
      {:ok, dbf1} = Parser.append_record(dbf, %{"ID" => 1, "NAME" => "Alice", "STATUS" => true})
      {:ok, dbf2} = Parser.append_record(dbf1, %{"ID" => 2, "NAME" => "Bob", "STATUS" => false})
      {:ok, dbf3} = Parser.append_record(dbf2, %{"ID" => 3, "NAME" => "Charlie", "STATUS" => true})
      {:ok, dbf4} = Parser.append_record(dbf3, %{"ID" => 4, "NAME" => "Diana", "STATUS" => false})
      {:ok, dbf5} = Parser.append_record(dbf4, %{"ID" => 5, "NAME" => "Eve", "STATUS" => true})
      
      # Mark some records as deleted (Bob and Diana)
      {:ok, dbf6} = Parser.mark_deleted(dbf5, 1)  # Bob
      {:ok, dbf7} = Parser.mark_deleted(dbf6, 3)  # Diana
      
      on_exit(fn ->
        File.rm(temp_path)
      end)
      
      {:ok, path: temp_path, dbf: dbf7, fields: fields}
    end

    test "packs file by removing deleted records", %{path: path, dbf: dbf} do
      # Verify initial state: 5 total records, 3 active
      assert dbf.header.record_count == 5
      {:ok, records} = Parser.read_records(dbf)
      assert length(records) == 3
      
      # Pack the file in place
      assert {:ok, packed_dbf} = Parser.pack(dbf, path)
      
      # Verify packed file has only active records
      assert packed_dbf.header.record_count == 3
      {:ok, packed_records} = Parser.read_records(packed_dbf)
      assert length(packed_records) == 3
      
      # Verify the correct records remain
      names = Enum.map(packed_records, & &1["NAME"])
      assert "Alice" in names
      assert "Charlie" in names  
      assert "Eve" in names
      refute "Bob" in names      # Should be gone
      refute "Diana" in names    # Should be gone
      
      # Verify IDs are preserved
      ids = Enum.map(packed_records, & &1["ID"])
      assert 1 in ids
      assert 3 in ids
      assert 5 in ids
      
      Parser.close_dbf(packed_dbf)
    end

    test "creates packed file at different location", %{dbf: dbf} do
      packed_path = "/tmp/test_pack_output_#{:rand.uniform(10000)}.dbf"
      
      on_exit(fn ->
        File.rm(packed_path)
      end)
      
      # Pack to a different file
      assert {:ok, packed_dbf} = Parser.pack(dbf, packed_path)
      
      # Verify the new file
      assert File.exists?(packed_path)
      assert packed_dbf.header.record_count == 3
      
      # Verify we can open the packed file independently
      Parser.close_dbf(packed_dbf)
      {:ok, reopened_dbf} = Parser.open_dbf(packed_path)
      {:ok, records} = Parser.read_records(reopened_dbf)
      assert length(records) == 3
      
      Parser.close_dbf(reopened_dbf)
    end

    test "handles file with no deleted records", %{fields: fields} do
      # Create a file with no deleted records
      clean_path = "/tmp/test_pack_clean_#{:rand.uniform(10000)}.dbf"
      {:ok, clean_dbf} = Parser.create_dbf(clean_path, fields)
      
      {:ok, dbf1} = Parser.append_record(clean_dbf, %{"ID" => 1, "NAME" => "Alice"})
      {:ok, dbf2} = Parser.append_record(dbf1, %{"ID" => 2, "NAME" => "Bob"})
      
      packed_path = "/tmp/test_pack_clean_output_#{:rand.uniform(10000)}.dbf"
      
      on_exit(fn ->
        File.rm(clean_path)
        File.rm(packed_path)
      end)
      
      # Pack the clean file
      assert {:ok, packed_dbf} = Parser.pack(dbf2, packed_path)
      
      # Should have the same number of records
      assert packed_dbf.header.record_count == 2
      {:ok, records} = Parser.read_records(packed_dbf)
      assert length(records) == 2
      
      Parser.close_dbf(packed_dbf)
    end

    test "handles file with all records deleted", %{fields: fields} do
      # Create a file and delete all records
      all_deleted_path = "/tmp/test_pack_all_deleted_#{:rand.uniform(10000)}.dbf"
      {:ok, dbf} = Parser.create_dbf(all_deleted_path, fields)
      
      {:ok, dbf1} = Parser.append_record(dbf, %{"ID" => 1, "NAME" => "Alice"})
      {:ok, dbf2} = Parser.append_record(dbf1, %{"ID" => 2, "NAME" => "Bob"})
      {:ok, dbf3} = Parser.mark_deleted(dbf2, 0)
      {:ok, dbf4} = Parser.mark_deleted(dbf3, 1)
      
      packed_path = "/tmp/test_pack_empty_output_#{:rand.uniform(10000)}.dbf"
      
      on_exit(fn ->
        File.rm(all_deleted_path)
        File.rm(packed_path)
      end)
      
      # Pack the file with all records deleted
      assert {:ok, packed_dbf} = Parser.pack(dbf4, packed_path)
      
      # Should have zero records
      assert packed_dbf.header.record_count == 0
      {:ok, records} = Parser.read_records(packed_dbf)
      assert length(records) == 0
      
      Parser.close_dbf(packed_dbf)
    end

    test "preserves field structure and types", %{dbf: dbf} do
      packed_path = "/tmp/test_pack_structure_#{:rand.uniform(10000)}.dbf"
      
      on_exit(fn ->
        File.rm(packed_path)
      end)
      
      # Pack the file
      assert {:ok, packed_dbf} = Parser.pack(dbf, packed_path)
      
      # Verify field structure is preserved
      assert length(packed_dbf.fields) == 3
      
      [id_field, name_field, status_field] = packed_dbf.fields
      assert id_field.name == "ID"
      assert id_field.type == "N"
      assert id_field.length == 5
      
      assert name_field.name == "NAME"
      assert name_field.type == "C"
      assert name_field.length == 20
      
      assert status_field.name == "STATUS"
      assert status_field.type == "L"
      assert status_field.length == 1
      
      Parser.close_dbf(packed_dbf)
    end

    test "updates header calculations correctly", %{dbf: dbf} do
      packed_path = "/tmp/test_pack_header_#{:rand.uniform(10000)}.dbf"
      
      on_exit(fn ->
        File.rm(packed_path)
      end)
      
      # Pack the file
      assert {:ok, packed_dbf} = Parser.pack(dbf, packed_path)
      
      # Verify header calculations
      expected_header_length = 32 + (3 * 32) + 1  # header + 3 fields + terminator = 129
      expected_record_length = 1 + 5 + 20 + 1     # deletion flag + field lengths = 27
      
      assert packed_dbf.header.header_length == expected_header_length
      assert packed_dbf.header.record_length == expected_record_length
      assert packed_dbf.header.record_count == 3
      
      # Verify current timestamp
      {{year, month, day}, _} = :calendar.local_time()
      assert packed_dbf.header.last_update_year == year - 1900
      assert packed_dbf.header.last_update_month == month
      assert packed_dbf.header.last_update_day == day
      
      Parser.close_dbf(packed_dbf)
    end

    test "handles empty source file", %{fields: fields} do
      # Create an empty file
      empty_path = "/tmp/test_pack_empty_source_#{:rand.uniform(10000)}.dbf"
      {:ok, empty_dbf} = Parser.create_dbf(empty_path, fields)
      
      packed_path = "/tmp/test_pack_from_empty_#{:rand.uniform(10000)}.dbf"
      
      on_exit(fn ->
        File.rm(empty_path)
        File.rm(packed_path)
      end)
      
      # Pack the empty file
      assert {:ok, packed_dbf} = Parser.pack(empty_dbf, packed_path)
      
      # Should still be empty
      assert packed_dbf.header.record_count == 0
      {:ok, records} = Parser.read_records(packed_dbf)
      assert length(records) == 0
      
      Parser.close_dbf(packed_dbf)
    end
  end
end