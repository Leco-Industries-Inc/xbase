# Configure ExUnit
ExUnit.start()

# Configure integration test tags
ExUnit.configure(
  exclude: [:integration, :performance],
  timeout: 60_000  # 60 seconds for integration tests
)

# Print information about test data files
IO.puts("\n=== Xbase Test Configuration ===")

test_dbf_path = "test/prrolls.DBF"
test_cdx_path = "test/prrolls.CDX"

if File.exists?(test_dbf_path) do
  {:ok, stat} = File.stat(test_dbf_path)
  IO.puts("✓ Real test data found: #{test_dbf_path} (#{stat.size} bytes)")
else
  IO.puts("⚠ Real test data missing: #{test_dbf_path}")
  IO.puts("  Integration tests will be skipped")
end

if File.exists?(test_cdx_path) do
  {:ok, stat} = File.stat(test_cdx_path)
  IO.puts("✓ Real index data found: #{test_cdx_path} (#{stat.size} bytes)")
else
  IO.puts("⚠ Real index data missing: #{test_cdx_path}")
  IO.puts("  CDX integration tests will be skipped")
end

IO.puts("\nTo run integration tests: mix test --include integration")
IO.puts("To run performance tests: mix test --include performance")
IO.puts("To run all tests: mix test --include integration --include performance")
IO.puts("================================\n")
