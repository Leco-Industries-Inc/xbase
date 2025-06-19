# Xbase

A comprehensive Elixir library for reading, writing, and manipulating dBase database files (DBF) with full support for memo fields (DBT) and indexes (CDX).

## Features

- **Complete DBF Support**: Read and write dBase III, IV, and compatible formats
- **Data Types**: Full support for Character, Numeric, Date, Logical, and Memo fields
- **Memo Fields**: Seamless integration with DBT files for variable-length text
- **Index Support**: B-tree based CDX index files for fast data access
- **Streaming**: Memory-efficient processing of large files
- **Transactions**: ACID-compliant operations with rollback support
- **Performance**: Optimized binary parsing and lazy evaluation

## Installation

```elixir
def deps do
  [
    {:xbase, "~> 0.1.0"}
  ]
end
```

## Quick Start

### Reading DBF Files

```elixir
# Open a DBF file
{:ok, dbf} = Xbase.Parser.open_dbf("data.dbf")

# Read a single record
{:ok, record} = Xbase.Parser.read_record(dbf, 0)
# => %Xbase.Types.Record{data: %{"NAME" => "John Doe", "AGE" => 30}, deleted: false}

# Read all records
records = Xbase.Parser.read_all_records(dbf)

# Stream records for memory efficiency
dbf
|> Xbase.Parser.stream_records()
|> Stream.filter(fn record -> record.data["AGE"] > 25 end)
|> Enum.to_list()

# Don't forget to close
Xbase.Parser.close_dbf(dbf)
```

### Writing DBF Files

```elixir
# Define field structure
fields = [
  %Xbase.Types.FieldDescriptor{name: "NAME", type: "C", length: 30},
  %Xbase.Types.FieldDescriptor{name: "AGE", type: "N", length: 3, decimal_count: 0},
  %Xbase.Types.FieldDescriptor{name: "BIRTHDATE", type: "D", length: 8},
  %Xbase.Types.FieldDescriptor{name: "ACTIVE", type: "L", length: 1}
]

# Create new DBF file
{:ok, dbf} = Xbase.Parser.create_dbf("output.dbf", fields)

# Append records
{:ok, dbf} = Xbase.Parser.append_record(dbf, %{
  "NAME" => "Jane Smith",
  "AGE" => 28,
  "BIRTHDATE" => ~D[1995-03-15],
  "ACTIVE" => true
})

# Update existing record
{:ok, dbf} = Xbase.Parser.update_record(dbf, 0, %{"AGE" => 29})

# Mark record as deleted
{:ok, dbf} = Xbase.Parser.mark_deleted(dbf, 0)

# Pack file to remove deleted records
{:ok, dbf} = Xbase.Parser.pack(dbf, "packed.dbf")

Xbase.Parser.close_dbf(dbf)
```

### Working with Memo Fields

```elixir
# Using MemoHandler for seamless memo support
{:ok, handler} = Xbase.MemoHandler.open_dbf_with_memo("data.dbf", [:read, :write])

# Append record with memo content
{:ok, handler} = Xbase.MemoHandler.append_record_with_memo(handler, %{
  "NAME" => "John Doe",
  "NOTES" => "This is a long memo that will be stored in the DBT file automatically"
})

# Read record with resolved memo content
{:ok, record} = Xbase.MemoHandler.read_record_with_memo(handler, 0)
# => %{"NAME" => "John Doe", "NOTES" => "This is a long memo..."}

# Update memo content
{:ok, handler} = Xbase.MemoHandler.update_record_with_memo(handler, 0, %{
  "NOTES" => "Updated memo content"
})

Xbase.MemoHandler.close_memo_files(handler)
```

### Using Indexes

```elixir
# Open DBF with index
{:ok, dbf} = Xbase.Parser.open_dbf("data.dbf")
{:ok, cdx} = Xbase.CdxParser.open_cdx("data.cdx")

# Search using index
{:ok, key_info} = Xbase.CdxParser.search_key(cdx, "SMITH")
# => Returns record number for fast access

# Range queries
keys = Xbase.CdxParser.search_range(cdx, "A", "M")

Xbase.CdxParser.close_cdx(cdx)
```

### Transactions

```elixir
# Wrap operations in a transaction
{:ok, result} = Xbase.Parser.with_transaction(dbf, fn dbf ->
  {:ok, dbf} = Xbase.Parser.append_record(dbf, record1)
  {:ok, dbf} = Xbase.Parser.append_record(dbf, record2)
  {:ok, dbf} = Xbase.Parser.update_record(dbf, 0, updates)
  {:ok, :success}
end)
# Automatically rolls back on error
```

### Batch Operations

```elixir
# Batch append for performance
records = [record1, record2, record3, ...]
{:ok, dbf} = Xbase.Parser.batch_append_records(dbf, records)

# Batch update
updates = [{0, %{"STATUS" => "ACTIVE"}}, {1, %{"STATUS" => "INACTIVE"}}]
{:ok, dbf} = Xbase.Parser.batch_update_records(dbf, updates)

# Batch delete
{:ok, dbf} = Xbase.Parser.batch_delete(dbf, [5, 10, 15])
```

## API Reference

### Core Modules

- `Xbase.Parser` - Main DBF file operations
- `Xbase.MemoHandler` - Integrated memo field support
- `Xbase.FieldParser` - Field type parsing
- `Xbase.FieldEncoder` - Field type encoding
- `Xbase.CdxParser` - Index file support
- `Xbase.DbtParser` - Low-level DBT file operations
- `Xbase.DbtWriter` - DBT file writing

### Data Types

See `Xbase.Types` for all data structure definitions.

## Performance Considerations

- **Streaming**: Use `stream_records/1` for large files to avoid loading everything into memory
- **Batch Operations**: Use batch functions when working with multiple records
- **Indexes**: Leverage CDX indexes for fast lookups on large datasets
- **Caching**: The library includes built-in caching for frequently accessed data

## Error Handling

All functions return `{:ok, result}` or `{:error, reason}` tuples for consistent error handling:

```elixir
case Xbase.Parser.open_dbf("data.dbf") do
  {:ok, dbf} ->
    # Work with the file
    :ok
  {:error, :enoent} ->
    IO.puts("File not found")
  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

