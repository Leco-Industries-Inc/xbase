# Xbase Documentation

Complete documentation for the Xbase library - a comprehensive Elixir library for reading, writing, and manipulating dBase database files.

## Quick Navigation

### 📚 Getting Started
- **[Getting Started Guide](guides/getting_started.md)** - Your first steps with Xbase
- **[Installation & Setup](../README.md#installation)** - How to add Xbase to your project

### 📖 User Guides
- **[Working with Memo Fields](guides/memo_fields.md)** - Complete guide to variable-length text fields
- **[Performance Optimization](guides/performance.md)** - Tips for high-performance applications
- **[Streaming Large Files](guides/streaming.md)** - Memory-efficient processing
- **[Using Indexes](guides/indexes.md)** - Fast data access with CDX files

### 🔍 API Reference
- **[Xbase.Parser](api/parser.md)** - Main DBF file operations
- **[Xbase.MemoHandler](api/memo_handler.md)** - Integrated memo field support  
- **[Xbase.Types](api/types.md)** - Data structures and type definitions
- **[Xbase.FieldParser](api/field_parser.md)** - Field type parsing
- **[Xbase.FieldEncoder](api/field_encoder.md)** - Field type encoding
- **[Xbase.CdxParser](api/cdx_parser.md)** - Index file support

### 🛠️ Advanced Topics
- **[Transactions](advanced/transactions.md)** - ACID compliance and rollback
- **[Batch Operations](advanced/batch_operations.md)** - High-performance bulk operations
- **[File Format Details](advanced/file_formats.md)** - Deep dive into DBF/DBT/CDX formats
- **[Concurrency](advanced/concurrency.md)** - Multi-process access patterns

### 🎯 Examples & Recipes
- **[Common Patterns](examples/common_patterns.md)** - Frequently used code patterns
- **[Data Migration](examples/data_migration.md)** - Converting between formats
- **[Report Generation](examples/reports.md)** - Creating reports from DBF data
- **[Integration Examples](examples/integration.md)** - Using Xbase with other libraries

## Feature Overview

### ✅ Core Features
- **Complete DBF Support**: Read and write dBase III, IV, and compatible formats
- **All Data Types**: Character, Numeric, Date, Logical, and Memo fields
- **Memo Fields**: Seamless integration with DBT files for variable-length text
- **Index Support**: B-tree based CDX index files for fast data access
- **Streaming**: Memory-efficient processing of large files
- **Transactions**: ACID-compliant operations with rollback support

### 🚀 Performance Features  
- **Lazy Evaluation**: Stream-based processing for large datasets
- **Batch Operations**: Optimized bulk operations
- **Caching**: Built-in caching for frequently accessed data
- **Binary Optimization**: Efficient binary parsing and pattern matching

### 🔒 Reliability Features
- **Error Handling**: Comprehensive error handling with detailed messages
- **Transaction Safety**: Automatic rollback on failures
- **File Validation**: Built-in file integrity checking
- **Resource Management**: Proper file handle lifecycle management

## Quick Examples

### Reading a DBF File
```elixir
{:ok, dbf} = Xbase.Parser.open_dbf("data.dbf")
{:ok, record} = Xbase.Parser.read_record(dbf, 0)
IO.inspect(record.data)
Xbase.Parser.close_dbf(dbf)
```

### Creating a DBF File
```elixir
fields = [
  %Xbase.Types.FieldDescriptor{name: "NAME", type: "C", length: 30},
  %Xbase.Types.FieldDescriptor{name: "AGE", type: "N", length: 3}
]
{:ok, dbf} = Xbase.Parser.create_dbf("new.dbf", fields)
{:ok, dbf} = Xbase.Parser.append_record(dbf, %{"NAME" => "John", "AGE" => 30})
Xbase.Parser.close_dbf(dbf)
```

### Working with Memo Fields
```elixir
{:ok, handler} = Xbase.MemoHandler.open_dbf_with_memo("data.dbf", [:read, :write])
{:ok, handler} = Xbase.MemoHandler.append_record_with_memo(handler, %{
  "TITLE" => "Article",
  "CONTENT" => "Long memo content..."
})
{:ok, record} = Xbase.MemoHandler.read_record_with_memo(handler, 0)
Xbase.MemoHandler.close_memo_files(handler)
```

### Streaming Large Files
```elixir
{:ok, dbf} = Xbase.Parser.open_dbf("large.dbf")
results = 
  dbf
  |> Xbase.Parser.stream_records()
  |> Stream.filter(fn record -> record.data["ACTIVE"] == true end)
  |> Enum.count()
Xbase.Parser.close_dbf(dbf)
```

## Architecture Overview

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Your App      │    │   Xbase.Parser  │    │  Xbase.Types    │
│                 │◄──►│                 │◄──►│                 │
│ - Business      │    │ - File I/O      │    │ - Data Structs  │
│   Logic         │    │ - Record Ops    │    │ - Validation    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│ MemoHandler     │    │ Field Parser/   │    │   DBF Files     │
│                 │    │ Encoder         │    │                 │
│ - Memo Coord.   │    │                 │    │ - Header        │
│ - Transactions  │    │ - Type Convert  │    │ - Records       │
│ - File Mgmt     │    │ - Validation    │    │ - Fields        │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   DBT Files     │    │   CDX Files     │    │  File System    │
│                 │    │                 │    │                 │
│ - Memo Content  │    │ - B-tree Index  │    │ - Binary Data   │
│ - Block Mgmt    │    │ - Fast Lookup   │    │ - I/O Ops       │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Module Hierarchy

```
Xbase
├── Parser              # Main DBF operations
├── MemoHandler         # Integrated memo support
├── Types               # Data structures
├── FieldParser         # Field type parsing
├── FieldEncoder        # Field type encoding
├── DbtParser           # DBT file reading
├── DbtWriter           # DBT file writing
└── CdxParser           # Index file support
```

## Error Handling Philosophy

Xbase follows Elixir conventions for error handling:
- All functions return `{:ok, result}` or `{:error, reason}` tuples
- Detailed error messages with context
- No exceptions for expected error conditions
- Graceful degradation when possible

## Performance Characteristics

| Operation | Time Complexity | Memory Usage | Notes |
|-----------|----------------|--------------|-------|
| Open file | O(1) | Constant | Header + field descriptors only |
| Read record | O(1) | Constant | Direct file access by index |
| Stream records | O(n) | Constant | Lazy evaluation |
| Append record | O(1) | Constant | Append to file end |
| Update record | O(1) | Constant | Direct file access |
| Index search | O(log n) | Constant | B-tree lookup |
| Memo read | O(1) | Variable | Cached after first read |

## Compatibility

### dBase Versions
- ✅ dBase III
- ✅ dBase IV  
- ✅ dBase 5
- ✅ FoxPro (basic compatibility)
- ✅ Visual FoxPro (basic compatibility)

### Field Types
- ✅ Character (C) - Text fields
- ✅ Numeric (N) - Integer and decimal numbers
- ✅ Date (D) - Date values
- ✅ Logical (L) - Boolean values
- ✅ Memo (M) - Variable-length text
- 🔄 Float (F) - IEEE floating point (planned)
- 🔄 DateTime (T) - Date/time stamps (planned)
- 🔄 Currency (Y) - Currency values (planned)

### File Types
- ✅ DBF - Database files
- ✅ DBT - Memo files (dBase III/IV format)
- ✅ CDX - Compound index files
- 🔄 MDX - Multiple index files (planned)
- 🔄 FPT - FoxPro memo files (planned)

## Contributing

We welcome contributions! See the main README for contribution guidelines.

### Documentation Contributions
- Fix typos or improve clarity
- Add more examples and use cases
- Expand API documentation
- Create new guides for advanced topics

### Code Contributions
- Add new features (see roadmap)
- Fix bugs and improve performance
- Enhance error handling
- Add more comprehensive tests

## Support

- **Issues**: [GitHub Issues](https://github.com/your-org/xbase/issues)
- **Discussions**: [GitHub Discussions](https://github.com/your-org/xbase/discussions)
- **Documentation**: This documentation site
- **Examples**: See the `examples/` directory

## Changelog

See the [CHANGELOG.md](../CHANGELOG.md) for version history and breaking changes.

## License

This project is licensed under the MIT License - see the [LICENSE](../LICENSE) file for details.