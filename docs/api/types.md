# Xbase.Types

Data structures and type definitions for DBF file format components.

## Core Data Structures

### Header

DBF file header structure containing metadata about the database file.

```elixir
defmodule Xbase.Types.Header do
  defstruct [
    :version,           # File type flag (dBase version)
    :last_update_year,  # Year of last update (0-99, add 1900)
    :last_update_month, # Month of last update (1-12)
    :last_update_day,   # Day of last update (1-31)
    :record_count,      # Number of records in file
    :header_length,     # Number of bytes in header
    :record_length,     # Number of bytes in record
    :transaction_flag,  # Transaction flag
    :encryption_flag,   # Encryption flag
    :mdx_flag,         # MDX flag
    :language_driver   # Language driver ID
  ]
end
```

**Example:**
```elixir
%Xbase.Types.Header{
  version: 3,
  last_update_year: 124,    # 2024
  last_update_month: 3,
  last_update_day: 15,
  record_count: 1000,
  header_length: 161,
  record_length: 50,
  transaction_flag: 0,
  encryption_flag: 0,
  mdx_flag: 0,
  language_driver: 0
}
```

### FieldDescriptor

Field descriptor structure defining database schema.

```elixir
defmodule Xbase.Types.FieldDescriptor do
  defstruct [
    :name,            # Field name (up to 10 characters)
    :type,            # Field type (C, N, D, L, M, etc.)
    :length,          # Field length in bytes
    :decimal_count,   # Number of decimal places (for numeric fields)
    :work_area_id,    # Work area ID
    :set_fields_flag, # Set fields flag
    :index_field_flag # Index field flag
  ]
end
```

**Field Types:**
- `"C"` - Character (text) field
- `"N"` - Numeric field (integer or decimal)
- `"D"` - Date field (YYYYMMDD format)
- `"L"` - Logical field (true/false)
- `"M"` - Memo field (variable-length text)

**Examples:**
```elixir
# Character field
%Xbase.Types.FieldDescriptor{
  name: "CUSTOMER_NAME", 
  type: "C", 
  length: 50, 
  decimal_count: 0
}

# Numeric field with decimals
%Xbase.Types.FieldDescriptor{
  name: "PRICE", 
  type: "N", 
  length: 8, 
  decimal_count: 2
}

# Date field
%Xbase.Types.FieldDescriptor{
  name: "ORDER_DATE", 
  type: "D", 
  length: 8, 
  decimal_count: 0
}

# Logical field
%Xbase.Types.FieldDescriptor{
  name: "IS_ACTIVE", 
  type: "L", 
  length: 1, 
  decimal_count: 0
}

# Memo field
%Xbase.Types.FieldDescriptor{
  name: "NOTES", 
  type: "M", 
  length: 10, 
  decimal_count: 0
}
```

### Record

DBF record structure containing parsed field data and metadata.

```elixir
defmodule Xbase.Types.Record do
  defstruct [
    :data,      # Map of field_name => parsed_value
    :deleted,   # Boolean indicating if record is deleted
    :raw_data   # Original binary data for debugging
  ]
end
```

**Example:**
```elixir
%Xbase.Types.Record{
  data: %{
    "CUSTOMER_NAME" => "John Doe",
    "PRICE" => 29.99,
    "ORDER_DATE" => ~D[2024-03-15],
    "IS_ACTIVE" => true,
    "NOTES" => {:memo_ref, 42}
  },
  deleted: false,
  raw_data: <<32, 74, 111, 104, 110, ...>>
}
```

## Memo Field Types

### DbtHeader

DBT (memo) file header structure containing metadata about memo storage.

```elixir
defmodule Xbase.Types.DbtHeader do
  defstruct [
    :next_block,    # Next available block number for allocation
    :block_size,    # Size of each memo block in bytes (typically 512)
    :version        # DBT format version (:dbase_iii or :dbase_iv)
  ]
end
```

**Example:**
```elixir
%Xbase.Types.DbtHeader{
  next_block: 15,
  block_size: 512,
  version: :dbase_iii
}
```

### DbtFile

DBT file structure containing header information and file handle.

```elixir
defmodule Xbase.Types.DbtFile do
  defstruct [
    :header,     # DbtHeader structure
    :file,       # File handle for I/O operations
    :file_path   # Path to the DBT file
  ]
end
```

### Memo References

Memo fields store references to memo blocks using tuples:

```elixir
{:memo_ref, block_number}
```

**Examples:**
```elixir
{:memo_ref, 0}   # Empty memo (no content)
{:memo_ref, 1}   # Reference to memo block 1
{:memo_ref, 42}  # Reference to memo block 42
```

## Index Types

### CdxHeader

CDX index file header structure.

```elixir
defmodule Xbase.Types.CdxHeader do
  defstruct [
    :root_node,        # Root node page number
    :free_list,        # Free page list
    :version,          # CDX format version
    :key_length,       # Length of index keys
    :index_options,    # Index options flags
    :signature,        # File signature
    :sort_order,       # Sort order specification
    :total_expr_len,   # Total expression length
    :for_expr_len,     # FOR expression length
    :key_expr_len,     # Key expression length
    :key_expression,   # Key expression string
    :for_expression    # FOR expression string
  ]
end
```

### CdxNode

CDX B-tree node structure.

```elixir
defmodule Xbase.Types.CdxNode do
  defstruct [
    :node_type,        # Node type (root, branch, leaf)
    :keys_count,       # Number of keys in node
    :keys,             # List of keys
    :pointers,         # List of child pointers (for branch nodes)
    :record_numbers    # List of record numbers (for leaf nodes)
  ]
end
```

### CdxFile

CDX file structure for index operations.

```elixir
defmodule Xbase.Types.CdxFile do
  defstruct [
    :header,           # CdxHeader structure
    :file,             # File handle
    :file_path,        # Path to CDX file
    :cache             # ETS cache for pages
  ]
end
```

### IndexKey

Index key structure for search operations.

```elixir
defmodule Xbase.Types.IndexKey do
  defstruct [
    :key_value,        # The key value for searching
    :record_number     # Associated record number
  ]
end
```

## Field Value Types

### Character Fields (Type "C")
- **Elixir Type**: `String.t()`
- **Format**: UTF-8 strings, right-padded with spaces
- **Example**: `"John Doe"`

### Numeric Fields (Type "N")
- **Elixir Type**: `integer()` or `float()`
- **Format**: Right-aligned strings converted to numbers
- **Examples**: `42`, `29.99`, `-15.5`

### Date Fields (Type "D")
- **Elixir Type**: `Date.t()` or `nil`
- **Format**: YYYYMMDD string format
- **Examples**: `~D[2024-03-15]`, `nil` (for empty dates)

### Logical Fields (Type "L")
- **Elixir Type**: `boolean()` or `nil`
- **Format**: Single character (T/F, Y/N, or ?)
- **Examples**: `true`, `false`, `nil` (for unknown)

### Memo Fields (Type "M")
- **Elixir Type**: `{:memo_ref, integer()}` or `String.t()` (when resolved)
- **Format**: Reference to memo block or actual content
- **Examples**: `{:memo_ref, 42}`, `"Long memo content..."`

## Data Validation

### Field Constraints

#### Character Fields
- Maximum length defined by field descriptor
- Automatically truncated if too long
- Null bytes removed

#### Numeric Fields
- Must be valid integer or float
- Decimal places must match field descriptor
- Range limited by field length

#### Date Fields
- Must be valid Date struct or nil
- Invalid dates stored as nil
- Format: YYYY-MM-DD

#### Logical Fields
- Accepts: `true`, `false`, `nil`
- Other values treated as `nil`

#### Memo Fields
- Content stored in separate DBT file
- Block references must be valid
- Content automatically managed by MemoHandler

### Error Types

Common validation errors:
- `:invalid_field_type` - Unsupported field type
- `:field_too_large` - Data exceeds field length
- `:invalid_date_format` - Invalid date value
- `:invalid_numeric_format` - Non-numeric value for numeric field

## Type Conversion Examples

### Reading Field Values
```elixir
# From DBF record to Elixir types
record = %Xbase.Types.Record{
  data: %{
    "NAME" => "John Doe",        # String
    "AGE" => 30,                 # Integer
    "SALARY" => 50000.00,        # Float
    "HIRE_DATE" => ~D[2020-01-15], # Date
    "IS_ACTIVE" => true,         # Boolean
    "NOTES" => {:memo_ref, 5}    # Memo reference
  }
}
```

### Writing Field Values
```elixir
# Elixir values to DBF format
record_data = %{
  "NAME" => "Jane Smith",
  "AGE" => 28,
  "SALARY" => 55000.50,
  "HIRE_DATE" => ~D[2021-03-01],
  "IS_ACTIVE" => true,
  "NOTES" => "This will be stored as memo content"
}
```

### Default Values
When fields are not provided in record data, default values are used:
- Character fields: Empty string (`""`)
- Numeric fields: `0`
- Date fields: `nil`
- Logical fields: `nil`
- Memo fields: `{:memo_ref, 0}` (empty memo)