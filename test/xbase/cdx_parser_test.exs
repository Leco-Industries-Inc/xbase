defmodule Xbase.CdxParserTest do
  use ExUnit.Case, async: true

  alias Xbase.CdxParser
  alias Xbase.Types.{CdxHeader, CdxNode}

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
end