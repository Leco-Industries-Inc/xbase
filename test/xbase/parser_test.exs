defmodule Xbase.ParserTest do
  use ExUnit.Case, async: true

  alias Xbase.Parser
  alias Xbase.Types.Header
  alias Xbase.Types.FieldDescriptor

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
end