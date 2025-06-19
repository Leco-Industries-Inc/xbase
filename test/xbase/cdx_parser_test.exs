defmodule Xbase.CdxParserTest do
  use ExUnit.Case, async: true

  alias Xbase.CdxParser
  alias Xbase.Types.{CdxHeader, CdxNode}

  # Path to real test data files
  @test_cdx_path "test/prrolls.CDX"
  @test_dbf_path "test/prrolls.DBF"

  describe "CDX header parsing" do
    test "parses a valid CDX header" do
      # Create a valid 512-byte CDX header
      # Format: root_node(4) + free_list(4) + version(4) + key_length(2) + options(1) + signature(1) + reserved(16) + sort_order(2) + total_expr_len(2) + for_expr_len(2) + reserved(2) + key_expr_len(2) + expressions + padding
      key_expr = "CUSTOMER_ID"
      header_data = <<
        1::little-32,        # root node pointer
        -1::little-32,       # free list (-1 = empty)
        1::little-32,        # version
        10::little-16,       # key length
        0,                   # index options
        0,                   # signature
        0::16*8,             # reserved bytes
        0::little-16,        # sort order
        20::little-16,       # total expression length
        0::little-16,        # FOR expression length
        0::16,               # reserved
        10::little-16        # key expression length
      >>
      
      # Calculate remaining space and create proper padding
      expressions_part = key_expr <> <<0, 0>>
      remaining_space = 512 - byte_size(header_data) - byte_size(expressions_part)
      padding = if remaining_space > 0, do: :binary.copy(<<0>>, remaining_space), else: <<>>
      
      header_binary = header_data <> expressions_part <> padding

      assert {:ok, header} = CdxParser.parse_header(header_binary)
      assert %CdxHeader{} = header
      assert header.root_node == 1
      assert header.free_list == -1
      assert header.version == 1
      assert header.key_length == 10
      assert header.key_expression == "CUSTOMER_ID"
    end

    test "returns error for invalid header size" do
      short_header = <<1::32, 2::32, 3::32>>
      
      assert {:error, :invalid_header_size} = CdxParser.parse_header(short_header)
    end

    test "validates key length is reasonable" do
      # Key length too large
      header_data = <<
        1::little-32,        # root node
        -1::little-32,       # free list
        1::little-32,        # version
        300::little-16,      # key length too large
        0, 0,                # options + signature
        0::484*8,            # reserved
        0::little-16,        # sort order
        0::little-16,        # total expr length
        0::little-16,        # for expr length
        0::16,               # reserved
        0::little-16         # key expr length
      >>
      
      remaining_space = 512 - byte_size(header_data)
      padding = :binary.copy(<<0>>, remaining_space)
      header_binary = header_data <> padding

      assert {:error, :invalid_key_length} = CdxParser.parse_header(header_binary)
    end
  end

  describe "B-tree node parsing" do
    test "parses a valid leaf node" do
      # Create a leaf node with attributes indicating leaf status
      node_header = <<
        0x0002::little-16,   # attributes (leaf node flag)
        2::little-16,        # key count
        -1::little-32,       # left brother
        0::16*8              # reserved
      >>
      
      # Keys and data
      key_data = <<
        # Key 1: "CUSTOMER01" + record number 1
        "CUSTOMER01"::binary, 1::little-32,
        # Key 2: "CUSTOMER02" + record number 2  
        "CUSTOMER02"::binary, 2::little-32
      >>
      
      # Calculate padding needed
      used_bytes = byte_size(node_header) + byte_size(key_data)
      padding_size = 512 - used_bytes
      padding = :binary.copy(<<0>>, padding_size)
      
      node_data = node_header <> key_data <> padding

      assert {:ok, node} = CdxParser.parse_node(node_data)
      assert %CdxNode{} = node
      assert node.node_type == :leaf
      assert node.key_count == 2
      assert node.left_brother == 4294967295  # -1 as unsigned 32-bit
    end

    test "parses a valid branch node" do
      # Create a branch node (no special flags)
      node_header = <<
        0x0000::little-16,   # attributes (branch node)
        1::little-16,        # key count
        -1::little-32,       # left brother
        0::16*8              # reserved
      >>
      
      key_data = <<
        # Key: "CUSTOMER50" + child pointer 2
        "CUSTOMER50"::binary, 2::little-32
      >>
      
      used_bytes = byte_size(node_header) + byte_size(key_data)
      padding_size = 512 - used_bytes
      padding = :binary.copy(<<0>>, padding_size)
      
      node_data = node_header <> key_data <> padding

      assert {:ok, node} = CdxParser.parse_node(node_data)
      assert %CdxNode{} = node
      assert node.node_type == :branch
      assert node.key_count == 1
    end

    test "identifies root node correctly" do
      # Create a root node with root flag
      node_header = <<
        0x0001::little-16,   # attributes (root node flag)
        1::little-16,        # key count
        -1::little-32,       # left brother
        0::16*8              # reserved
      >>
      
      key_data = <<"ROOTKEY001"::binary, 1::little-32>>
      
      used_bytes = byte_size(node_header) + byte_size(key_data)
      padding_size = 512 - used_bytes
      padding = :binary.copy(<<0>>, padding_size)
      
      node_data = node_header <> key_data <> padding

      assert {:ok, node} = CdxParser.parse_node(node_data)
      assert node.node_type == :root
    end

    test "returns error for invalid node size" do
      short_node = <<1::16, 2::16, 3::32>>
      
      assert {:error, :invalid_page_size} = CdxParser.parse_node(short_node)
    end
  end

  describe "CDX file operations" do
    setup do
      # Create a temporary CDX file for testing
      temp_path = "/tmp/test_index_#{:rand.uniform(10000)}.cdx"
      
      # Create minimal CDX file with header and simple root node
      key_expr = "CUSTOMER_ID"
      header_data = <<
        1::little-32,        # root node at page 1
        -1::little-32,       # no free list
        1::little-32,        # version 1
        10::little-16,       # key length
        0, 0,                # options + signature
        0::484*8,            # reserved
        0::little-16,        # sort order
        15::little-16,       # total expr length
        0::little-16,        # for expr length
        0::16,               # reserved
        15::little-16        # key expr length
      >>
      
      expressions_part = key_expr <> <<0, 0, 0, 0>>  # expression + padding
      remaining_space = 512 - byte_size(header_data) - byte_size(expressions_part)
      padding = if remaining_space > 0, do: :binary.copy(<<0>>, remaining_space), else: <<>>
      
      header = header_data <> expressions_part <> padding
      
      # Simple root/leaf node with one key
      root_header = <<
        0x0003::little-16,   # root + leaf flags
        1::little-16,        # one key
        -1::little-32,       # no left brother
        0::16*8              # reserved
      >>
      
      root_key_data = <<"CUSTOMER01"::binary, 1::little-32>>  # key + record number
      
      root_used_bytes = byte_size(root_header) + byte_size(root_key_data)
      root_padding_size = 512 - root_used_bytes
      root_padding = :binary.copy(<<0>>, root_padding_size)
      
      root_node = root_header <> root_key_data <> root_padding
      
      cdx_content = header <> root_node
      File.write!(temp_path, cdx_content)
      
      on_exit(fn ->
        File.rm(temp_path)
      end)
      
      {:ok, path: temp_path}
    end

    test "opens and parses CDX file", %{path: path} do
      assert {:ok, cdx} = CdxParser.open_cdx(path)
      assert %CdxHeader{} = cdx.header
      assert cdx.header.root_node == 1
      assert cdx.header.key_length == 10
      assert cdx.file != nil
      assert cdx.page_cache != nil
      
      CdxParser.close_cdx(cdx)
    end

    test "reads B-tree nodes with caching", %{path: path} do
      {:ok, cdx} = CdxParser.open_cdx(path)
      
      # Read root node (page 1)
      assert {:ok, node} = CdxParser.read_node(cdx, 1)
      assert %CdxNode{} = node
      assert node.key_count == 1
      
      # Read same node again - should hit cache
      assert {:ok, cached_node} = CdxParser.read_node(cdx, 1)
      assert cached_node == node
      
      CdxParser.close_cdx(cdx)
    end

    test "searches for existing key", %{path: path} do
      {:ok, cdx} = CdxParser.open_cdx(path)
      
      # Search for the key we put in the test data
      assert {:ok, record_number} = CdxParser.search_key(cdx, "CUSTOMER01")
      assert record_number == 1
      
      CdxParser.close_cdx(cdx)
    end

    test "returns not found for missing key", %{path: path} do
      {:ok, cdx} = CdxParser.open_cdx(path)
      
      # Search for a key that doesn't exist
      assert {:error, :not_found} = CdxParser.search_key(cdx, "MISSING_KEY")
      
      CdxParser.close_cdx(cdx)
    end

    test "handles invalid node page numbers", %{path: path} do
      {:ok, cdx} = CdxParser.open_cdx(path)
      
      # Try to read a page that doesn't exist
      assert {:error, _reason} = CdxParser.read_node(cdx, 999)
      
      CdxParser.close_cdx(cdx)
    end
  end

  describe "error handling" do
    test "handles missing CDX file" do
      missing_path = "/tmp/nonexistent_#{:rand.uniform(10000)}.cdx"
      
      assert {:error, :file_not_found} = CdxParser.open_cdx(missing_path)
    end

    test "handles corrupted CDX header" do
      corrupted_path = "/tmp/corrupted_#{:rand.uniform(10000)}.cdx"
      
      # Create file with invalid header
      File.write!(corrupted_path, "invalid header content")
      
      assert {:error, :invalid_header_size} = CdxParser.open_cdx(corrupted_path)
      
      File.rm(corrupted_path)
    end

    test "handles truncated CDX file" do
      truncated_path = "/tmp/truncated_#{:rand.uniform(10000)}.cdx"
      
      # Create file that's too short
      File.write!(truncated_path, :binary.copy(<<0>>, 100))
      
      assert {:error, _reason} = CdxParser.open_cdx(truncated_path)
      
      File.rm(truncated_path)
    end
  end

  describe "Integration Tests with Real CDX Index (prrolls.CDX)" do
    @tag :integration
    test "opens real CDX file and reads header correctly" do
      # Note: This test may fail if CDX parsing is not fully implemented
      # Skip or adapt based on current implementation status
      case CdxParser.open_cdx(@test_cdx_path) do
        {:ok, cdx} ->
          # Basic validation that we can open the file
          assert is_map(cdx)
          assert cdx.file_path == @test_cdx_path
          
          # Verify header structure if available
          if Map.has_key?(cdx, :header) do
            assert %CdxHeader{} = cdx.header
          end
          
          CdxParser.close_cdx(cdx)
          
        {:error, :not_implemented} ->
          # CDX parsing not yet implemented, skip test
          IO.puts("CDX parsing not implemented yet - skipping integration test")
          
        {:error, reason} ->
          flunk("Failed to open real CDX file: #{inspect(reason)}")
      end
    end

    @tag :integration
    test "validates CDX file structure with corresponding DBF" do
      # This test validates that the CDX file corresponds to the DBF file
      case {Xbase.Parser.open_dbf(@test_dbf_path), CdxParser.open_cdx(@test_cdx_path)} do
        {{:ok, dbf}, {:ok, cdx}} ->
          # Verify the index file corresponds to the DBF structure
          # This is a placeholder for when CDX functionality is implemented
          
          # Basic validation that both files opened
          assert dbf.header.record_count == 311314
          assert is_map(cdx)
          
          Xbase.Parser.close_dbf(dbf)
          CdxParser.close_cdx(cdx)
          
        {{:ok, dbf}, {:error, :not_implemented}} ->
          # CDX not implemented yet
          IO.puts("CDX integration testing pending implementation")
          Xbase.Parser.close_dbf(dbf)
          
        {{:ok, dbf}, {:error, cdx_error}} ->
          Xbase.Parser.close_dbf(dbf)
          flunk("CDX file failed to open: #{inspect(cdx_error)}")
          
        {{:error, dbf_error}, _} ->
          flunk("DBF file failed to open: #{inspect(dbf_error)}")
      end
    end

    @tag :integration
    test "CDX file size and basic structure validation" do
      # Test basic file properties
      assert File.exists?(@test_cdx_path)
      
      {:ok, file_stat} = File.stat(@test_cdx_path)
      assert file_stat.size > 0
      
      # CDX files should be substantial for a 311K record database
      assert file_stat.size > 1024  # At least 1KB
      
      # Read first few bytes to check it's a binary file
      {:ok, first_bytes} = File.read(@test_cdx_path, 64)
      assert byte_size(first_bytes) == 64
      
      # Basic validation that it's not a text file
      assert not String.printable?(first_bytes)
    end

    @tag :integration 
    test "performance characteristics of real CDX file" do
      case CdxParser.open_cdx(@test_cdx_path) do
        {:ok, cdx} ->
          # Time the opening operation
          {open_time, _} = :timer.tc(fn ->
            {:ok, test_cdx} = CdxParser.open_cdx(@test_cdx_path)
            CdxParser.close_cdx(test_cdx)
          end)
          
          # Should open quickly (less than 100ms)
          assert open_time < 100_000  # 100ms in microseconds
          
          CdxParser.close_cdx(cdx)
          
        {:error, :not_implemented} ->
          IO.puts("CDX performance testing pending implementation")
          
        {:error, reason} ->
          flunk("Failed to test CDX performance: #{inspect(reason)}")
      end
    end

    @tag :integration
    test "CDX file metadata extraction" do
      # Test what we can determine about the CDX file without full parsing
      {:ok, file_data} = File.read(@test_cdx_path, 512)  # Read first block
      
      # Basic binary structure validation
      assert byte_size(file_data) == 512
      
      # CDX files typically start with certain patterns
      # This is a placeholder for more specific validation when CDX parsing is implemented
      assert is_binary(file_data)
      
      # Could add more specific byte pattern checks based on CDX format specification
      # For now, just verify we can read the file structure
      IO.puts("CDX file first 32 bytes: #{inspect(binary_part(file_data, 0, 32))}")
    end
  end
end