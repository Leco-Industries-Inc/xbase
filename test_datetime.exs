# Test the round-trip that's failing
alias Xbase.{FieldParser, FieldEncoder, Types.FieldDescriptor}

field_desc = %FieldDescriptor{name: "TIMESTAMP", type: "T", length: 8, decimal_count: 0}
datetime = DateTime.new!(~D[2024-03-15], ~T[14:30:45.123], "Etc/UTC")

IO.puts("Original datetime: #{inspect(datetime)}")

case FieldEncoder.encode(field_desc, datetime) do
  {:ok, binary_result} ->
    IO.puts("Encoded binary (#{byte_size(binary_result)} bytes): #{Base.encode16(binary_result)}")
    
    case FieldParser.parse(field_desc, binary_result) do
      {:ok, parsed_datetime} ->
        IO.puts("Parsed datetime: #{inspect(parsed_datetime)}")
      {:error, reason} ->
        IO.puts("Parse error: #{inspect(reason)}")
    end
  {:error, reason} ->
    IO.puts("Encode error: #{inspect(reason)}")
end