defmodule Xbase.MemoHandlerTest do
  use ExUnit.Case, async: true

  alias Xbase.MemoHandler
  alias Xbase.Parser
  alias Xbase.Types.FieldDescriptor

  describe "opening DBF files with memo support" do
    setup do
      dbf_path = "/tmp/test_memo_#{:rand.uniform(10000)}.dbf"
      dbt_path = "/tmp/test_memo_#{:rand.uniform(10000)}.dbt"
      
      on_exit(fn ->
        if File.exists?(dbf_path), do: File.rm(dbf_path)
        if File.exists?(dbt_path), do: File.rm(dbt_path)
      end)
      
      {:ok, dbf_path: dbf_path, dbt_path: dbt_path}
    end

    test "opens DBF file without memo support", %{dbf_path: dbf_path} do
      # Create DBF without memo fields
      fields = [
        %FieldDescriptor{name: "NAME", type: "C", length: 20, decimal_count: 0},
        %FieldDescriptor{name: "AGE", type: "N", length: 3, decimal_count: 0}
      ]
      
      {:ok, dbf} = Parser.create_dbf(dbf_path, fields)
      Parser.close_dbf(dbf)
      
      assert {:ok, handler} = MemoHandler.open_dbf_with_memo(dbf_path)
      assert handler.memo_mode == :disabled
      assert handler.dbt == nil
      assert handler.dbt_path == nil
      
      MemoHandler.close_memo_files(handler)
    end

    test "auto-discovers DBT file for memo-capable DBF", %{dbf_path: dbf_path} do
      dbt_path = Path.rootname(dbf_path) <> ".dbt"
      
      # Create memo-capable DBF
      fields = [
        %FieldDescriptor{name: "NAME", type: "C", length: 20, decimal_count: 0},
        %FieldDescriptor{name: "NOTES", type: "M", length: 10, decimal_count: 0}
      ]
      
      {:ok, handler} = MemoHandler.create_dbf_with_memo(dbf_path, fields)
      MemoHandler.close_memo_files(handler)
      
      # Now open it with auto-discovery
      assert {:ok, reopened_handler} = MemoHandler.open_dbf_with_memo(dbf_path)
      assert reopened_handler.memo_mode == :auto
      assert reopened_handler.dbt != nil
      assert reopened_handler.dbt_path == dbt_path
      
      MemoHandler.close_memo_files(reopened_handler)
    end

    test "handles explicit DBT path", %{dbf_path: dbf_path, dbt_path: dbt_path} do
      # Create memo-capable DBF
      fields = [
        %FieldDescriptor{name: "NAME", type: "C", length: 20, decimal_count: 0},
        %FieldDescriptor{name: "NOTES", type: "M", length: 10, decimal_count: 0}
      ]
      
      {:ok, handler} = MemoHandler.create_dbf_with_memo(dbf_path, fields, dbt_path: dbt_path)
      assert handler.dbt_path == dbt_path
      
      MemoHandler.close_memo_files(handler)
    end

    test "handles required memo mode", %{dbf_path: dbf_path} do
      # Create DBF without memo support
      fields = [
        %FieldDescriptor{name: "NAME", type: "C", length: 20, decimal_count: 0}
      ]
      
      {:ok, dbf} = Parser.create_dbf(dbf_path, fields)
      Parser.close_dbf(dbf)
      
      # Should fail with required memo mode
      assert {:error, :dbf_no_memo_support} = MemoHandler.open_dbf_with_memo(dbf_path, [:read], memo: :required)
    end
  end

  describe "creating DBF files with memo support" do
    setup do
      dbf_path = "/tmp/test_create_#{:rand.uniform(10000)}.dbf"
      dbt_path = "/tmp/test_create_#{:rand.uniform(10000)}.dbt"
      
      on_exit(fn ->
        if File.exists?(dbf_path), do: File.rm(dbf_path)
        if File.exists?(dbt_path), do: File.rm(dbt_path)
      end)
      
      {:ok, dbf_path: dbf_path, dbt_path: dbt_path}
    end

    test "creates coordinated DBF and DBT files", %{dbf_path: dbf_path} do
      fields = [
        %FieldDescriptor{name: "NAME", type: "C", length: 20, decimal_count: 0},
        %FieldDescriptor{name: "NOTES", type: "M", length: 10, decimal_count: 0}
      ]
      
      assert {:ok, handler} = MemoHandler.create_dbf_with_memo(dbf_path, fields)
      
      # Verify both files exist
      assert File.exists?(dbf_path)
      assert File.exists?(handler.dbt_path)
      
      # Verify handler structure
      assert handler.dbf != nil
      assert handler.dbt != nil
      assert handler.memo_mode == :auto
      
      MemoHandler.close_memo_files(handler)
    end

    test "creates DBF without memo support when no memo fields", %{dbf_path: dbf_path} do
      fields = [
        %FieldDescriptor{name: "NAME", type: "C", length: 20, decimal_count: 0},
        %FieldDescriptor{name: "AGE", type: "N", length: 3, decimal_count: 0}
      ]
      
      assert {:ok, handler} = MemoHandler.create_dbf_with_memo(dbf_path, fields)
      
      # Should have no DBT file
      assert handler.dbt == nil
      assert handler.dbt_path == nil
      assert handler.memo_mode == :disabled
      
      MemoHandler.close_memo_files(handler)
    end

    test "uses explicit DBT path", %{dbf_path: dbf_path, dbt_path: dbt_path} do
      fields = [
        %FieldDescriptor{name: "NOTES", type: "M", length: 10, decimal_count: 0}
      ]
      
      assert {:ok, handler} = MemoHandler.create_dbf_with_memo(dbf_path, fields, dbt_path: dbt_path)
      assert handler.dbt_path == dbt_path
      assert File.exists?(dbt_path)
      
      MemoHandler.close_memo_files(handler)
    end
  end

  describe "record operations with memo content" do
    setup do
      dbf_path = "/tmp/test_records_#{:rand.uniform(10000)}.dbf"
      
      fields = [
        %FieldDescriptor{name: "NAME", type: "C", length: 20, decimal_count: 0},
        %FieldDescriptor{name: "NOTES", type: "M", length: 10, decimal_count: 0},
        %FieldDescriptor{name: "COMMENTS", type: "M", length: 10, decimal_count: 0}
      ]
      
      {:ok, handler} = MemoHandler.create_dbf_with_memo(dbf_path, fields)
      
      on_exit(fn ->
        MemoHandler.close_memo_files(handler)
        if File.exists?(dbf_path), do: File.rm(dbf_path)
        if File.exists?(handler.dbt_path), do: File.rm(handler.dbt_path)
      end)
      
      {:ok, handler: handler}
    end

    test "appends record with memo content", %{handler: handler} do
      record_data = %{
        "NAME" => "John Doe",
        "NOTES" => "This is a test memo",
        "COMMENTS" => "Additional comments here"
      }
      
      assert {:ok, updated_handler} = MemoHandler.append_record_with_memo(handler, record_data)
      
      # Verify record was written
      assert {:ok, read_record} = MemoHandler.read_record_with_memo(updated_handler, 0)
      assert read_record["NAME"] == "John Doe"
      assert read_record["NOTES"] == "This is a test memo"
      assert read_record["COMMENTS"] == "Additional comments here"
    end

    test "handles mixed memo references and content", %{handler: handler} do
      # First, append a record with memo content
      {:ok, handler1} = MemoHandler.append_record_with_memo(handler, %{
        "NAME" => "First User",
        "NOTES" => "First memo content"
      })
      
      # Then append a record with memo reference and new content
      record_data = %{
        "NAME" => "Second User",
        "NOTES" => {:memo_ref, 1},  # Reference to existing memo
        "COMMENTS" => "New comment content"
      }
      
      assert {:ok, updated_handler} = MemoHandler.append_record_with_memo(handler1, record_data)
      
      # Verify both records
      assert {:ok, record1} = MemoHandler.read_record_with_memo(updated_handler, 0)
      assert record1["NOTES"] == "First memo content"
      
      assert {:ok, record2} = MemoHandler.read_record_with_memo(updated_handler, 1)
      assert record2["NOTES"] == "First memo content"  # Same as block 1
      assert record2["COMMENTS"] == "New comment content"
    end

    test "updates record with memo content", %{handler: handler} do
      # Create initial record
      {:ok, handler1} = MemoHandler.append_record_with_memo(handler, %{
        "NAME" => "Test User",
        "NOTES" => "Original memo"
      })
      
      # Update with new memo content
      update_data = %{
        "NOTES" => "Updated memo content"
      }
      
      assert {:ok, updated_handler} = MemoHandler.update_record_with_memo(handler1, 0, update_data)
      
      # Verify update
      assert {:ok, updated_record} = MemoHandler.read_record_with_memo(updated_handler, 0)
      assert updated_record["NAME"] == "Test User"  # Unchanged
      assert updated_record["NOTES"] == "Updated memo content"  # Updated
    end

    test "handles empty memo content", %{handler: handler} do
      record_data = %{
        "NAME" => "Empty Memo User",
        "NOTES" => "",
        "COMMENTS" => "Some comments"
      }
      
      assert {:ok, updated_handler} = MemoHandler.append_record_with_memo(handler, record_data)
      
      assert {:ok, read_record} = MemoHandler.read_record_with_memo(updated_handler, 0)
      assert read_record["NOTES"] == ""
      assert read_record["COMMENTS"] == "Some comments"
    end
  end

  describe "record operations without memo support" do
    setup do
      dbf_path = "/tmp/test_no_memo_#{:rand.uniform(10000)}.dbf"
      
      fields = [
        %FieldDescriptor{name: "NAME", type: "C", length: 20, decimal_count: 0},
        %FieldDescriptor{name: "AGE", type: "N", length: 3, decimal_count: 0}
      ]
      
      {:ok, handler} = MemoHandler.create_dbf_with_memo(dbf_path, fields)
      
      on_exit(fn ->
        MemoHandler.close_memo_files(handler)
        if File.exists?(dbf_path), do: File.rm(dbf_path)
      end)
      
      {:ok, handler: handler}
    end

    test "appends regular records", %{handler: handler} do
      record_data = %{
        "NAME" => "John Doe",
        "AGE" => 30
      }
      
      assert {:ok, updated_handler} = MemoHandler.append_record_with_memo(handler, record_data)
      
      # Read record back
      assert {:ok, read_record} = MemoHandler.read_record_with_memo(updated_handler, 0)
      assert read_record["NAME"] == "John Doe"
      assert read_record["AGE"] == 30
    end

    test "updates regular records", %{handler: handler} do
      # Create initial record
      {:ok, handler1} = MemoHandler.append_record_with_memo(handler, %{
        "NAME" => "Test User",
        "AGE" => 25
      })
      
      # Update record
      assert {:ok, updated_handler} = MemoHandler.update_record_with_memo(handler1, 0, %{"AGE" => 26})
      
      # Verify update
      assert {:ok, updated_record} = MemoHandler.read_record_with_memo(updated_handler, 0)
      assert updated_record["NAME"] == "Test User"
      assert updated_record["AGE"] == 26
    end
  end

  describe "transaction support" do
    setup do
      dbf_path = "/tmp/test_transaction_#{:rand.uniform(10000)}.dbf"
      
      fields = [
        %FieldDescriptor{name: "NAME", type: "C", length: 20, decimal_count: 0},
        %FieldDescriptor{name: "NOTES", type: "M", length: 10, decimal_count: 0}
      ]
      
      {:ok, handler} = MemoHandler.create_dbf_with_memo(dbf_path, fields)
      
      on_exit(fn ->
        MemoHandler.close_memo_files(handler)
        if File.exists?(dbf_path), do: File.rm(dbf_path)
        if File.exists?(handler.dbt_path), do: File.rm(handler.dbt_path)
        
        # Clean up any backup files
        if File.exists?(dbf_path <> ".bak"), do: File.rm(dbf_path <> ".bak")
        if File.exists?(handler.dbt_path <> ".bak"), do: File.rm(handler.dbt_path <> ".bak")
      end)
      
      {:ok, handler: handler}
    end

    test "successful transaction commits changes", %{handler: handler} do
      transaction_fn = fn h ->
        {:ok, h1} = MemoHandler.append_record_with_memo(h, %{
          "NAME" => "User 1",
          "NOTES" => "First memo"
        })
        
        {:ok, h2} = MemoHandler.append_record_with_memo(h1, %{
          "NAME" => "User 2", 
          "NOTES" => "Second memo"
        })
        
        {:ok, :transaction_success, h2}
      end
      
      assert {:ok, {:transaction_success, final_handler}} = MemoHandler.memo_transaction(handler, transaction_fn)
      
      # Verify both records exist
      assert {:ok, record1} = MemoHandler.read_record_with_memo(final_handler, 0)
      assert record1["NAME"] == "User 1"
      assert record1["NOTES"] == "First memo"
      
      assert {:ok, record2} = MemoHandler.read_record_with_memo(final_handler, 1)
      assert record2["NAME"] == "User 2"
      assert record2["NOTES"] == "Second memo"
    end

    test "failed transaction rolls back changes", %{handler: handler} do
      # First add a record outside transaction
      {:ok, initial_handler} = MemoHandler.append_record_with_memo(handler, %{
        "NAME" => "Initial User",
        "NOTES" => "Initial memo"
      })
      
      transaction_fn = fn h ->
        {:ok, h1} = MemoHandler.append_record_with_memo(h, %{
          "NAME" => "Transaction User",
          "NOTES" => "Transaction memo"
        })
        
        # Simulate failure
        {:error, :simulated_failure}
      end
      
      assert {:error, :simulated_failure} = MemoHandler.memo_transaction(initial_handler, transaction_fn)
      
      # Verify only the initial record exists
      assert {:ok, record} = MemoHandler.read_record_with_memo(initial_handler, 0)
      assert record["NAME"] == "Initial User"
      
      # Transaction record should not exist
      assert {:error, :invalid_record_index} = MemoHandler.read_record_with_memo(initial_handler, 1)
    end
  end

  describe "error handling" do
    test "handles missing DBF file" do
      assert {:error, :enoent} = MemoHandler.open_dbf_with_memo("/nonexistent/file.dbf")
    end

    test "handles memo content without DBT file" do
      dbf_path = "/tmp/test_error_#{:rand.uniform(10000)}.dbf"
      
      # Create memo-capable DBF but don't create DBT
      fields = [
        %FieldDescriptor{name: "NOTES", type: "M", length: 10, decimal_count: 0}
      ]
      
      {:ok, dbf} = Parser.create_dbf(dbf_path, fields, version: 0x8B)
      Parser.close_dbf(dbf)
      
      on_exit(fn ->
        if File.exists?(dbf_path), do: File.rm(dbf_path)
      end)
      
      # Open without write access (so DBT won't be created)
      {:ok, handler} = MemoHandler.open_dbf_with_memo(dbf_path, [:read])
      
      # Try to append record with memo content
      record_data = %{"NOTES" => "This should fail"}
      assert {:error, {:memo_content_without_dbt, ["NOTES"]}} = 
        MemoHandler.append_record_with_memo(handler, record_data)
      
      MemoHandler.close_memo_files(handler)
    end

    test "handles invalid memo field values" do
      dbf_path = "/tmp/test_invalid_#{:rand.uniform(10000)}.dbf"
      
      fields = [
        %FieldDescriptor{name: "NOTES", type: "M", length: 10, decimal_count: 0}
      ]
      
      {:ok, handler} = MemoHandler.create_dbf_with_memo(dbf_path, fields)
      
      on_exit(fn ->
        MemoHandler.close_memo_files(handler)
        if File.exists?(dbf_path), do: File.rm(dbf_path)
        if File.exists?(handler.dbt_path), do: File.rm(handler.dbt_path)
      end)
      
      # Try invalid memo field value
      record_data = %{"NOTES" => 123}  # Number instead of string or memo_ref
      assert {:error, {:invalid_memo_value, "NOTES", 123}} = 
        MemoHandler.append_record_with_memo(handler, record_data)
    end
  end

  describe "integration with existing DBF operations" do
    setup do
      dbf_path = "/tmp/test_integration_#{:rand.uniform(10000)}.dbf"
      
      fields = [
        %FieldDescriptor{name: "NAME", type: "C", length: 20, decimal_count: 0},
        %FieldDescriptor{name: "NOTES", type: "M", length: 10, decimal_count: 0}
      ]
      
      {:ok, handler} = MemoHandler.create_dbf_with_memo(dbf_path, fields)
      
      on_exit(fn ->
        MemoHandler.close_memo_files(handler)
        if File.exists?(dbf_path), do: File.rm(dbf_path)
        if File.exists?(handler.dbt_path), do: File.rm(handler.dbt_path)
      end)
      
      {:ok, handler: handler}
    end

    test "works with batch operations concept", %{handler: handler} do
      # Simulate batch record insertion
      records = [
        %{"NAME" => "User 1", "NOTES" => "First user notes"},
        %{"NAME" => "User 2", "NOTES" => "Second user notes"},
        %{"NAME" => "User 3", "NOTES" => "Third user notes"}
      ]
      
      # Add records sequentially (batch support would be a future enhancement)
      final_handler = Enum.reduce(records, handler, fn record, acc_handler ->
        {:ok, updated_handler} = MemoHandler.append_record_with_memo(acc_handler, record)
        updated_handler
      end)
      
      # Verify all records
      for {expected_record, index} <- Enum.with_index(records) do
        {:ok, actual_record} = MemoHandler.read_record_with_memo(final_handler, index)
        assert actual_record["NAME"] == expected_record["NAME"]
        assert actual_record["NOTES"] == expected_record["NOTES"]
      end
    end

    test "maintains header consistency", %{handler: handler} do
      # Add some records
      {:ok, h1} = MemoHandler.append_record_with_memo(handler, %{
        "NAME" => "Test User 1",
        "NOTES" => "Test memo 1"
      })
      
      {:ok, h2} = MemoHandler.append_record_with_memo(h1, %{
        "NAME" => "Test User 2", 
        "NOTES" => "Test memo 2"
      })
      
      # Verify record count in header
      assert h2.dbf.header.record_count == 2
      
      # Verify DBT header shows allocated blocks
      assert h2.dbt.header.next_block == 3  # Header is block 0, memos in blocks 1 and 2
    end
  end
end