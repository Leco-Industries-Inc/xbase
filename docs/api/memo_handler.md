# Xbase.MemoHandler

High-level module for seamless memo field integration, providing coordinated operations between DBF and DBT files with automatic memo content handling.

## Core Functions

### File Operations

#### `open_dbf_with_memo(dbf_path, modes \\ [:read], opts \\ [])`

Opens a DBF file with automatic memo file discovery and coordination.

**Parameters:**
- `dbf_path` - Path to the DBF file
- `modes` - File access modes (`:read`, `:write`)
- `opts` - Options:
  - `:memo` - Memo mode (`:auto`, `:required`, `:disabled`)
  - `:dbt_path` - Explicit DBT file path

**Returns:**
- `{:ok, %MemoHandler{}}` - Successfully opened coordinated files
- `{:error, reason}` - Error opening files

**Example:**
```elixir
# Automatic memo file discovery
{:ok, handler} = Xbase.MemoHandler.open_dbf_with_memo("data.dbf")

# Read-write mode with required memo support
{:ok, handler} = Xbase.MemoHandler.open_dbf_with_memo("data.dbf", [:read, :write], memo: :required)

# Explicit DBT file path
{:ok, handler} = Xbase.MemoHandler.open_dbf_with_memo("data.dbf", [], dbt_path: "memos.dbt")
```

#### `create_dbf_with_memo(dbf_path, fields, opts \\ [])`

Creates a new DBF file with memo support and coordinated DBT file.

**Parameters:**
- `dbf_path` - Path for the new DBF file
- `fields` - Field definitions for the DBF file
- `opts` - Options:
  - `:version` - DBF version (automatically set to memo-capable if memo fields present)
  - `:dbt_path` - Explicit DBT file path
  - `:block_size` - DBT block size (default: 512)

**Returns:**
- `{:ok, %MemoHandler{}}` - Successfully created coordinated files
- `{:error, reason}` - Error creating files

**Example:**
```elixir
fields = [
  %Xbase.Types.FieldDescriptor{name: "NAME", type: "C", length: 30},
  %Xbase.Types.FieldDescriptor{name: "NOTES", type: "M", length: 10}
]
{:ok, handler} = Xbase.MemoHandler.create_dbf_with_memo("data.dbf", fields)
```

#### `close_memo_files(handler)`

Closes both DBF and DBT files properly.

**Parameters:**
- `handler` - MemoHandler structure

**Returns:**
- `:ok` - Files closed successfully

### Record Operations

#### `append_record_with_memo(handler, record_data)`

Appends a record with automatic memo content handling.

**Parameters:**
- `handler` - MemoHandler structure
- `record_data` - Map of field names to values, where memo fields contain content strings

**Returns:**
- `{:ok, updated_handler}` - Successfully appended record with memo content
- `{:error, reason}` - Error appending record

**Example:**
```elixir
record_data = %{
  "NAME" => "John Doe",
  "NOTES" => "This memo content will be automatically stored in the DBT file"
}
{:ok, updated_handler} = Xbase.MemoHandler.append_record_with_memo(handler, record_data)
```

#### `update_record_with_memo(handler, record_index, record_data)`

Updates a record with automatic memo content handling.

**Parameters:**
- `handler` - MemoHandler structure
- `record_index` - Zero-based record index to update
- `record_data` - Map of field names to values for update

**Returns:**
- `{:ok, updated_handler}` - Successfully updated record with memo content
- `{:error, reason}` - Error updating record

**Example:**
```elixir
{:ok, updated_handler} = Xbase.MemoHandler.update_record_with_memo(handler, 0, %{
  "NOTES" => "Updated memo content"
})
```

#### `read_record_with_memo(handler, record_index)`

Reads a record with automatic memo content resolution.

**Parameters:**
- `handler` - MemoHandler structure  
- `record_index` - Zero-based record index to read

**Returns:**
- `{:ok, record_data}` - Record data with memo content resolved
- `{:error, reason}` - Error reading record

**Example:**
```elixir
{:ok, record} = Xbase.MemoHandler.read_record_with_memo(handler, 0)
# => %{"NAME" => "John Doe", "NOTES" => "This memo content..."}
```

### Transaction Support

#### `memo_transaction(handler, transaction_fn)`

Executes a function with transaction safety across both DBF and DBT files.

**Parameters:**
- `handler` - MemoHandler structure
- `transaction_fn` - Function to execute with the handler

**Returns:**
- `{:ok, {result, updated_handler}}` - Transaction successful
- `{:error, reason}` - Transaction failed, changes rolled back

**Example:**
```elixir
{:ok, {result, final_handler}} = Xbase.MemoHandler.memo_transaction(handler, fn h ->
  {:ok, h1} = Xbase.MemoHandler.append_record_with_memo(h, record1)
  {:ok, h2} = Xbase.MemoHandler.append_record_with_memo(h1, record2)
  {:ok, :success, h2}
end)
```

## Data Handling

### Memo Field Processing

The MemoHandler automatically processes memo fields during record operations:

1. **String Content**: Automatically writes to DBT file and converts to memo reference
2. **Memo References**: Preserves existing `{:memo_ref, block_number}` tuples
3. **Mixed Data**: Handles records with both string content and memo references
4. **Empty Content**: Properly handles empty memo fields

### Memo Content Types

#### String Content (Automatic Storage)
```elixir
%{"NOTES" => "This string will be stored in the DBT file"}
```

#### Memo Reference (Direct Reference)
```elixir
%{"NOTES" => {:memo_ref, 42}}  # Direct reference to block 42
```

#### Mixed Usage
```elixir
%{
  "NOTES" => "New content to store",           # Will be written to DBT
  "COMMENTS" => {:memo_ref, 15}                # Existing reference preserved
}
```

### Block Management

- **Smart Reuse**: Updates existing memo blocks when possible
- **Automatic Allocation**: Creates new blocks for new content
- **Reference Tracking**: Maintains proper memo reference counts
- **Content Validation**: Ensures memo content fits within block constraints

## Error Handling

### Common Error Codes

- `:dbf_no_memo_support` - DBF file doesn't support memo fields
- `:dbt_file_required` - DBT file required but not found
- `:memo_content_without_dbt` - Memo content provided but no DBT file available
- `:invalid_memo_value` - Invalid value for memo field
- `:memo_write_failed` - Error writing memo content
- `:memo_read_failed` - Error reading memo content

### Error Examples

```elixir
# Handle missing DBT file
case Xbase.MemoHandler.open_dbf_with_memo("data.dbf", memo: :required) do
  {:ok, handler} -> 
    # Process with memo support
    :ok
  {:error, :dbt_file_required} ->
    IO.puts("Memo file required but not found")
  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end

# Handle memo content errors
case Xbase.MemoHandler.append_record_with_memo(handler, invalid_data) do
  {:ok, updated_handler} ->
    # Success
    :ok
  {:error, {:invalid_memo_value, field_name, value}} ->
    IO.puts("Invalid memo value for field #{field_name}: #{inspect(value)}")
end
```

## Performance Considerations

### Optimization Tips

1. **Batch Operations**: Group multiple record operations when possible
2. **Memo Block Reuse**: Updates reuse existing blocks when content fits
3. **Transaction Scope**: Use transactions for related operations only
4. **File Coordination**: Automatic coordination minimizes file I/O overhead

### Memory Management

- **Lazy Resolution**: Memo content resolved only when accessed
- **Efficient Caching**: Built-in caching for frequently accessed memo blocks
- **Resource Cleanup**: Proper file handle management and cleanup

### Concurrent Access

- **File Locking**: Coordinated locking across both DBF and DBT files
- **Transaction Safety**: ACID compliance across both file types
- **Conflict Detection**: Automatic detection of concurrent modifications

## Integration Examples

### Basic Workflow
```elixir
# Open files
{:ok, handler} = Xbase.MemoHandler.open_dbf_with_memo("data.dbf", [:read, :write])

# Add records with memo content
{:ok, handler} = Xbase.MemoHandler.append_record_with_memo(handler, %{
  "NAME" => "Customer 1",
  "NOTES" => "Long memo content goes here..."
})

# Read back with resolved content
{:ok, record} = Xbase.MemoHandler.read_record_with_memo(handler, 0)

# Update memo content
{:ok, handler} = Xbase.MemoHandler.update_record_with_memo(handler, 0, %{
  "NOTES" => "Updated memo content"
})

# Close files
Xbase.MemoHandler.close_memo_files(handler)
```

### Advanced Usage with Transactions
```elixir
{:ok, handler} = Xbase.MemoHandler.open_dbf_with_memo("data.dbf", [:read, :write])

# Complex transaction with multiple memo operations
{:ok, {result, final_handler}} = Xbase.MemoHandler.memo_transaction(handler, fn h ->
  # Add multiple records with memo content
  {:ok, h1} = Xbase.MemoHandler.append_record_with_memo(h, record1)
  {:ok, h2} = Xbase.MemoHandler.append_record_with_memo(h1, record2)
  
  # Update existing memo content
  {:ok, h3} = Xbase.MemoHandler.update_record_with_memo(h2, 0, updates)
  
  {:ok, :batch_complete, h3}
end)

Xbase.MemoHandler.close_memo_files(final_handler)
```