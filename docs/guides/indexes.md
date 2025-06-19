# Working with Indexes

CDX (Compound Index) files provide fast B-tree based lookups for DBF files. Indexes dramatically improve search performance on large datasets by maintaining sorted key structures.

## Understanding CDX Indexes

### What are CDX Indexes?

CDX files are compound index files that store:
- **B-tree structures** for fast key lookups
- **Multiple indexes** in a single file
- **Key expressions** for complex indexing
- **Sort order information** for proper collation

### Benefits of Using Indexes

- **Fast Searches**: O(log n) lookup time vs O(n) linear search
- **Range Queries**: Efficient range-based searches
- **Sorted Access**: Iterate through records in key order
- **Multiple Keys**: Support for multiple indexes per file

## Basic Index Operations

### Opening Index Files

```elixir
# Open DBF and its associated CDX file
{:ok, dbf} = Xbase.Parser.open_dbf("customers.dbf")
{:ok, cdx} = Xbase.CdxParser.open_cdx("customers.cdx")

# Index files typically have the same name as DBF with .cdx extension
{:ok, cdx} = Xbase.CdxParser.open_cdx("customers.cdx")
```

### Creating Index Files

```elixir
# Create index on a field
{:ok, cdx} = Xbase.CdxParser.create_index("customers.cdx", %{
  key_expression: "LAST_NAME",
  key_length: 30,
  index_name: "LASTNAME_IDX"
})

# Create compound index (multiple fields)
{:ok, cdx} = Xbase.CdxParser.create_index("customers.cdx", %{
  key_expression: "LAST_NAME + FIRST_NAME",
  key_length: 60,
  index_name: "FULLNAME_IDX"
})

# Create expression-based index
{:ok, cdx} = Xbase.CdxParser.create_index("orders.cdx", %{
  key_expression: "DTOS(ORDER_DATE) + STR(AMOUNT, 10, 2)",
  key_length: 18,
  index_name: "DATE_AMOUNT_IDX"
})
```

## Search Operations

### Exact Key Searches

```elixir
# Search for exact key match
case Xbase.CdxParser.search_key(cdx, "SMITH") do
  {:ok, %{record_number: record_num, found: true}} ->
    # Key found, get the record
    {:ok, record} = Xbase.Parser.read_record(dbf, record_num)
    IO.inspect(record.data)
    
  {:ok, %{found: false}} ->
    IO.puts("Key not found")
    
  {:error, reason} ->
    IO.puts("Search error: #{inspect(reason)}")
end
```

### Range Searches

```elixir
# Find all records with keys between "A" and "M"
{:ok, results} = Xbase.CdxParser.search_range(cdx, "A", "M")

# Process matching records
Enum.each(results, fn %{record_number: record_num, key_value: key} ->
  {:ok, record} = Xbase.Parser.read_record(dbf, record_num)
  IO.puts("#{key}: #{record.data["FIRST_NAME"]} #{record.data["LAST_NAME"]}")
end)
```

### Partial Key Searches

```elixir
# Find all keys starting with "SMI"
{:ok, matches} = Xbase.CdxParser.search_partial(cdx, "SMI")

# Get first 10 matching records
matches
|> Enum.take(10)
|> Enum.each(fn %{record_number: record_num} ->
  {:ok, record} = Xbase.Parser.read_record(dbf, record_num)
  IO.inspect(record.data)
end)
```

## Advanced Index Usage

### Multiple Indexes

```elixir
# Work with multiple indexes on the same file
{:ok, name_idx} = Xbase.CdxParser.open_index(cdx, "LASTNAME_IDX")
{:ok, date_idx} = Xbase.CdxParser.open_index(cdx, "BIRTHDATE_IDX")
{:ok, amount_idx} = Xbase.CdxParser.open_index(cdx, "AMOUNT_IDX")

# Search using different indexes
{:ok, by_name} = Xbase.CdxParser.search_key(name_idx, "JOHNSON")
{:ok, by_date} = Xbase.CdxParser.search_range(date_idx, "19900101", "19991231")
{:ok, by_amount} = Xbase.CdxParser.search_range(amount_idx, "1000.00", "9999.99")
```

### Ordered Iteration

```elixir
# Iterate through records in index order
{:ok, iterator} = Xbase.CdxParser.create_iterator(cdx)

# Process records in sorted order
Xbase.CdxParser.iterate_keys(iterator, fn key_info ->
  {:ok, record} = Xbase.Parser.read_record(dbf, key_info.record_number)
  process_record_in_order(record)
  :continue  # or :halt to stop
end)
```

### Index Maintenance

```elixir
# Rebuild index for consistency
{:ok, cdx} = Xbase.CdxParser.rebuild_index(cdx, dbf)

# Compact index to remove fragmentation
{:ok, compacted_cdx} = Xbase.CdxParser.compact_index(cdx, "customers_new.cdx")

# Verify index integrity
case Xbase.CdxParser.verify_index(cdx, dbf) do
  {:ok, :valid} ->
    IO.puts("Index is consistent with DBF file")
  {:error, inconsistencies} ->
    IO.puts("Index inconsistencies found: #{inspect(inconsistencies)}")
end
```

## Performance Optimization

### Index Selection Strategy

```elixir
# Choose indexes based on query patterns
defmodule IndexStrategy do
  def choose_index(query_type, available_indexes) do
    case query_type do
      {:exact_match, field} ->
        find_best_index_for_field(available_indexes, field)
        
      {:range_query, field} ->
        find_sorted_index_for_field(available_indexes, field)
        
      {:compound_search, fields} ->
        find_compound_index(available_indexes, fields)
    end
  end
  
  defp find_best_index_for_field(indexes, field) do
    # Find index with field as primary key
    Enum.find(indexes, fn idx ->
      idx.key_expression == field or 
      String.starts_with?(idx.key_expression, field <> " + ")
    end)
  end
end
```

### Caching Strategies

```elixir
# Use ETS for index result caching
defmodule IndexCache do
  def setup_cache do
    :ets.new(:index_cache, [:set, :public, :named_table])
  end
  
  def cached_search(cdx, key) do
    case :ets.lookup(:index_cache, key) do
      [{^key, result}] ->
        result
      [] ->
        result = Xbase.CdxParser.search_key(cdx, key)
        :ets.insert(:index_cache, {key, result})
        result
    end
  end
end
```

## Index Types and Expressions

### Simple Field Indexes

```elixir
# Single field indexes
indexes = [
  %{key_expression: "CUSTOMER_ID", key_length: 10},    # Numeric field
  %{key_expression: "LAST_NAME", key_length: 30},      # Character field
  %{key_expression: "ORDER_DATE", key_length: 8},      # Date field
  %{key_expression: "IS_ACTIVE", key_length: 1}        # Logical field
]
```

### Compound Field Indexes

```elixir
# Multiple field indexes for complex queries
compound_indexes = [
  %{
    key_expression: "STATE + CITY + LAST_NAME",
    key_length: 65,
    name: "GEOGRAPHIC_NAME"
  },
  %{
    key_expression: "DTOS(ORDER_DATE) + CUSTOMER_ID",
    key_length: 18,
    name: "DATE_CUSTOMER"
  }
]
```

### Expression-Based Indexes

```elixir
# Complex expression indexes
expression_indexes = [
  %{
    # Uppercase index for case-insensitive searches
    key_expression: "UPPER(LAST_NAME)",
    key_length: 30,
    name: "UPPER_LASTNAME"
  },
  %{
    # Combined date and amount for financial queries
    key_expression: "DTOS(ORDER_DATE) + STR(AMOUNT, 12, 2)",
    key_length: 20,
    name: "DATE_AMOUNT"
  },
  %{
    # Full name concatenation
    key_expression: "TRIM(FIRST_NAME) + ' ' + TRIM(LAST_NAME)",
    key_length: 61,
    name: "FULL_NAME"
  }
]
```

## Common Index Patterns

### Customer Database

```elixir
# Typical indexes for a customer database
defmodule CustomerIndexes do
  def create_standard_indexes(dbf_path) do
    cdx_path = String.replace(dbf_path, ".dbf", ".cdx")
    
    indexes = [
      # Primary key
      %{key_expression: "CUSTOMER_ID", key_length: 10, name: "PK_CUSTOMER"},
      
      # Name searches
      %{key_expression: "LAST_NAME", key_length: 30, name: "IDX_LASTNAME"},
      %{key_expression: "LAST_NAME + FIRST_NAME", key_length: 60, name: "IDX_FULLNAME"},
      
      # Geographic searches
      %{key_expression: "STATE + CITY", key_length: 35, name: "IDX_LOCATION"},
      
      # Contact searches
      %{key_expression: "EMAIL", key_length: 50, name: "IDX_EMAIL"},
      %{key_expression: "PHONE", key_length: 15, name: "IDX_PHONE"},
      
      # Business logic
      %{key_expression: "UPPER(COMPANY_NAME)", key_length: 50, name: "IDX_COMPANY"}
    ]
    
    {:ok, cdx} = Xbase.CdxParser.create_multiple_indexes(cdx_path, indexes)
    cdx
  end
end
```

### Sales Database

```elixir
# Indexes optimized for sales queries
defmodule SalesIndexes do
  def create_sales_indexes(dbf_path) do
    cdx_path = String.replace(dbf_path, ".dbf", ".cdx")
    
    indexes = [
      # Time-based queries
      %{key_expression: "DTOS(SALE_DATE)", key_length: 8, name: "IDX_DATE"},
      %{key_expression: "DTOS(SALE_DATE) + CUSTOMER_ID", key_length: 18, name: "IDX_DATE_CUSTOMER"},
      
      # Amount-based queries
      %{key_expression: "STR(AMOUNT, 12, 2)", key_length: 12, name: "IDX_AMOUNT"},
      %{key_expression: "PRODUCT_CODE + DTOS(SALE_DATE)", key_length: 18, name: "IDX_PRODUCT_DATE"},
      
      # Status tracking
      %{key_expression: "STATUS + DTOS(SALE_DATE)", key_length: 11, name: "IDX_STATUS_DATE"},
      
      # Salesperson performance
      %{key_expression: "SALESPERSON_ID + DTOS(SALE_DATE)", key_length: 18, name: "IDX_SALES_PERSON"}
    ]
    
    {:ok, cdx} = Xbase.CdxParser.create_multiple_indexes(cdx_path, indexes)
    cdx
  end
end
```

## Error Handling

### Index-Specific Errors

```elixir
defmodule IndexErrorHandler do
  def safe_index_operation(operation_fn) do
    try do
      operation_fn.()
    rescue
      error ->
        handle_index_error(error)
    end
  end
  
  defp handle_index_error(error) do
    case error do
      %{reason: :index_corrupted} ->
        {:error, "Index file is corrupted and needs rebuilding"}
        
      %{reason: :key_too_long} ->
        {:error, "Search key exceeds maximum index key length"}
        
      %{reason: :index_not_found} ->
        {:error, "Specified index does not exist in CDX file"}
        
      %{reason: :unsupported_expression} ->
        {:error, "Index expression contains unsupported functions"}
        
      _ ->
        {:error, "Unexpected index error: #{inspect(error)}"}
    end
  end
end
```

### Recovery Procedures

```elixir
defmodule IndexRecovery do
  def recover_corrupted_index(cdx_path, dbf_path) do
    with {:ok, dbf} <- Xbase.Parser.open_dbf(dbf_path),
         {:ok, backup_path} <- create_backup(cdx_path),
         {:ok, cdx} <- rebuild_from_dbf(cdx_path, dbf) do
      
      case Xbase.CdxParser.verify_index(cdx, dbf) do
        {:ok, :valid} ->
          File.rm(backup_path)
          {:ok, "Index successfully recovered"}
          
        {:error, _} ->
          File.rename(backup_path, cdx_path)
          {:error, "Recovery failed, original index restored"}
      end
    end
  end
  
  defp create_backup(cdx_path) do
    backup_path = cdx_path <> ".backup"
    case File.copy(cdx_path, backup_path) do
      {:ok, _} -> {:ok, backup_path}
      error -> error
    end
  end
  
  defp rebuild_from_dbf(cdx_path, dbf) do
    # Extract index definitions from existing CDX or use defaults
    index_definitions = extract_index_definitions(cdx_path)
    Xbase.CdxParser.create_multiple_indexes(cdx_path, index_definitions)
  end
end
```

## Best Practices

### 1. Index Design Guidelines

```elixir
# Good index design principles
defmodule IndexDesignGuidelines do
  def design_indexes(table_analysis) do
    [
      # Index frequently searched fields
      create_search_indexes(table_analysis.search_patterns),
      
      # Index foreign key relationships
      create_relationship_indexes(table_analysis.relationships),
      
      # Index sort operations
      create_sort_indexes(table_analysis.sort_patterns),
      
      # Compound indexes for multi-field queries
      create_compound_indexes(table_analysis.compound_queries)
    ]
    |> List.flatten()
  end
  
  defp create_search_indexes(search_patterns) do
    search_patterns
    |> Enum.filter(fn pattern -> pattern.frequency > 0.1 end)  # 10% threshold
    |> Enum.map(fn pattern ->
      %{
        key_expression: pattern.field,
        key_length: calculate_key_length(pattern.field),
        name: "IDX_#{String.upcase(pattern.field)}"
      }
    end)
  end
end
```

### 2. Maintenance Schedule

```elixir
defmodule IndexMaintenance do
  def schedule_maintenance(cdx_files) do
    Enum.each(cdx_files, fn cdx_path ->
      case analyze_index_health(cdx_path) do
        {:needs_rebuild, reason} ->
          schedule_rebuild(cdx_path, reason)
          
        {:needs_compact, fragmentation} ->
          schedule_compaction(cdx_path, fragmentation)
          
        {:healthy, stats} ->
          log_health_status(cdx_path, stats)
      end
    end)
  end
  
  defp analyze_index_health(cdx_path) do
    with {:ok, cdx} <- Xbase.CdxParser.open_cdx(cdx_path),
         {:ok, stats} <- Xbase.CdxParser.get_index_statistics(cdx) do
      
      cond do
        stats.corruption_detected -> {:needs_rebuild, :corruption}
        stats.fragmentation_ratio > 0.4 -> {:needs_compact, stats.fragmentation_ratio}
        true -> {:healthy, stats}
      end
    end
  end
end
```

### 3. Performance Monitoring

```elixir
defmodule IndexPerformanceMonitor do
  def monitor_index_performance(cdx, operations) do
    Enum.map(operations, fn operation ->
      {time, result} = :timer.tc(fn -> execute_operation(cdx, operation) end)
      
      %{
        operation: operation,
        execution_time_ms: time / 1000,
        result: result,
        performance_rating: rate_performance(time, operation)
      }
    end)
  end
  
  defp rate_performance(time_microseconds, operation) do
    time_ms = time_microseconds / 1000
    
    case operation.type do
      :exact_search when time_ms < 1 -> :excellent
      :exact_search when time_ms < 10 -> :good
      :range_query when time_ms < 50 -> :excellent
      :range_query when time_ms < 200 -> :good
      _ -> :needs_optimization
    end
  end
end
```

## Integration with DBF Operations

### Coordinated File Operations

```elixir
defmodule CoordinatedOperations do
  def insert_with_index_update(dbf, cdx, record_data) do
    Xbase.Parser.with_transaction(dbf, fn dbf ->
      # Add record to DBF
      {:ok, updated_dbf} = Xbase.Parser.append_record(dbf, record_data)
      
      # Update all indexes
      record_index = updated_dbf.header.record_count - 1
      {:ok, updated_cdx} = update_all_indexes(cdx, record_data, record_index)
      
      {:ok, {updated_dbf, updated_cdx}}
    end)
  end
  
  def update_with_index_maintenance(dbf, cdx, record_index, new_data) do
    # Get old record for index removal
    {:ok, old_record} = Xbase.Parser.read_record(dbf, record_index)
    
    Xbase.Parser.with_transaction(dbf, fn dbf ->
      # Update DBF record
      {:ok, updated_dbf} = Xbase.Parser.update_record(dbf, record_index, new_data)
      
      # Remove old index entries
      {:ok, cdx_after_removal} = remove_from_indexes(cdx, old_record.data, record_index)
      
      # Add new index entries
      {:ok, updated_cdx} = add_to_indexes(cdx_after_removal, new_data, record_index)
      
      {:ok, {updated_dbf, updated_cdx}}
    end)
  end
  
  defp update_all_indexes(cdx, record_data, record_index) do
    # Implementation would iterate through all indexes in CDX
    # and add entries for the new record
    Xbase.CdxParser.add_record_to_all_indexes(cdx, record_data, record_index)
  end
end
```

This comprehensive guide covers all aspects of working with CDX indexes in Xbase, from basic operations to advanced optimization strategies.