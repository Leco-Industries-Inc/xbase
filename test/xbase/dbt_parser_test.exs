defmodule Xbase.DbtParserTest do
  use ExUnit.Case, async: true

  alias Xbase.DbtParser
  alias Xbase.Types.DbtHeader

  describe "DBT header parsing" do
    test "parses a valid dBase III DBT header" do
      # Create a valid 512-byte dBase III DBT header
      # Format: next_block(4) + unknown(2) + block_size(2) + padding(504)
      header_binary = <<
        8::little-32,    # next available block number
        0::16,           # unknown/reserved
        512::little-16,  # block size
        0::504*8         # padding to 512 bytes
      >>

      assert {:ok, header} = DbtParser.parse_header(header_binary)
      assert %DbtHeader{} = header
      assert header.next_block == 8
      assert header.block_size == 512
      assert header.version == :dbase_iii
    end

    test "parses a valid dBase IV DBT header" do
      # dBase IV format: next_block(4) + block_size(2) + unknown(2) + padding(504)
      header_binary = <<
        16::little-32,   # next available block number
        1024::little-16, # block size
        0::16,           # unknown/reserved
        0::504*8         # padding to 512 bytes
      >>

      assert {:ok, header} = DbtParser.parse_header(header_binary, :dbase_iv)
      assert %DbtHeader{} = header
      assert header.next_block == 16
      assert header.block_size == 1024
      assert header.version == :dbase_iv
    end

    test "returns error for invalid header size" do
      short_header = <<1::32, 2::16, 3::16>>
      
      assert {:error, :invalid_header_size} = DbtParser.parse_header(short_header)
    end

    test "validates block size is reasonable" do
      # Block size too small
      header_binary = <<
        8::little-32,    # next block
        0::16,           # unknown
        128::little-16,  # block size too small
        0::504*8         # padding
      >>

      assert {:error, :invalid_block_size} = DbtParser.parse_header(header_binary)
    end
  end

  describe "block reading" do
    test "calculates correct block offset" do
      header = %DbtHeader{
        next_block: 5,
        block_size: 512,
        version: :dbase_iii
      }

      # Block 0 (header) = offset 0
      assert DbtParser.calculate_block_offset(header, 0) == 0
      
      # Block 1 = offset 512
      assert DbtParser.calculate_block_offset(header, 1) == 512
      
      # Block 3 = offset 1536
      assert DbtParser.calculate_block_offset(header, 3) == 1536
    end

    test "reads memo content from block with termination" do
      # Create memo content with proper termination
      memo_text = "This is a memo field content."
      memo_block = memo_text <> <<0x1A, 0x1A>> <> String.duplicate(<<0>>, 512 - byte_size(memo_text) - 2)

      assert {:ok, content} = DbtParser.extract_memo_content(memo_block)
      assert content == memo_text
    end

    test "handles memo content without termination" do
      # Memo content that fills entire block without termination
      memo_text = String.duplicate("X", 512)
      
      assert {:ok, content} = DbtParser.extract_memo_content(memo_text)
      assert content == memo_text
    end

    test "handles empty memo blocks" do
      # Block with just termination markers
      empty_block = <<0x1A, 0x1A>> <> String.duplicate(<<0>>, 510)
      
      assert {:ok, content} = DbtParser.extract_memo_content(empty_block)
      assert content == ""
    end

    test "handles memo content with internal 0x1A bytes" do
      # Memo with single 0x1A (not termination)
      memo_text = "Text with \x1A character inside"
      memo_block = memo_text <> <<0x1A, 0x1A>> <> String.duplicate(<<0>>, 512 - byte_size(memo_text) - 2)

      assert {:ok, content} = DbtParser.extract_memo_content(memo_block)
      assert content == memo_text
    end
  end

  describe "DBT file operations" do
    setup do
      # Create a temporary DBT file for testing
      temp_path = "/tmp/test_memo_#{:rand.uniform(10000)}.dbt"
      
      # Create DBT file with header and some memo blocks
      header = <<
        3::little-32,    # next available block (block 3)
        0::16,           # unknown
        512::little-16,  # block size
        0::504*8         # padding
      >>
      
      # Block 1: Memo content
      memo1 = "First memo content" <> <<0x1A, 0x1A>> <> String.duplicate(<<0>>, 512 - 18 - 2)
      
      # Block 2: Another memo content
      memo2 = "Second memo with more text content" <> <<0x1A, 0x1A>> <> String.duplicate(<<0>>, 512 - 33 - 2)
      
      dbt_content = header <> memo1 <> memo2
      File.write!(temp_path, dbt_content)
      
      on_exit(fn ->
        File.rm(temp_path)
      end)
      
      {:ok, path: temp_path}
    end

    test "opens and parses DBT file", %{path: path} do
      assert {:ok, dbt} = DbtParser.open_dbt(path)
      assert %DbtHeader{} = dbt.header
      assert dbt.header.next_block == 3
      assert dbt.header.block_size == 512
      assert dbt.file != nil
    end

    test "reads memo content by block number", %{path: path} do
      {:ok, dbt} = DbtParser.open_dbt(path)
      
      # Read block 1
      assert {:ok, content1} = DbtParser.read_memo(dbt, 1)
      assert content1 == "First memo content"
      
      # Read block 2
      assert {:ok, content2} = DbtParser.read_memo(dbt, 2)
      assert content2 == "Second memo with more text content"
      
      DbtParser.close_dbt(dbt)
    end

    test "handles invalid block numbers", %{path: path} do
      {:ok, dbt} = DbtParser.open_dbt(path)
      
      # Block 0 is header, should return error
      assert {:error, :invalid_block_number} = DbtParser.read_memo(dbt, 0)
      
      # Block beyond next_block should return error
      assert {:error, :block_not_allocated} = DbtParser.read_memo(dbt, 5)
      
      DbtParser.close_dbt(dbt)
    end

    test "validates DBT file integrity", %{path: path} do
      assert {:ok, valid} = DbtParser.validate_dbt_file(path)
      assert valid == true
    end
  end

  describe "error handling" do
    test "handles missing DBT file" do
      missing_path = "/tmp/nonexistent_#{:rand.uniform(10000)}.dbt"
      
      assert {:error, :file_not_found} = DbtParser.open_dbt(missing_path)
    end

    test "handles corrupted DBT header" do
      corrupted_path = "/tmp/corrupted_#{:rand.uniform(10000)}.dbt"
      
      # Create file with invalid header
      File.write!(corrupted_path, "invalid header content")
      
      assert {:error, :invalid_header_size} = DbtParser.open_dbt(corrupted_path)
      
      File.rm(corrupted_path)
    end
  end
end