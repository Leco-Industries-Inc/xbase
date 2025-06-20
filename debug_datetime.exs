# Debug the DateTime parsing issue
alias Xbase.{FieldParser, FieldEncoder, Types.FieldDescriptor}

field_desc = %FieldDescriptor{name: "TIMESTAMP", type: "T", length: 8, decimal_count: 0}
binary_data = <<0xE1, 0x8A, 0x25, 0x00, 0x83, 0x32, 0x1D, 0x03>>

IO.puts("Binary data: #{Base.encode16(binary_data)}")
IO.puts("Binary size: #{byte_size(binary_data)}")

# Extract the Julian day and milliseconds
<<julian_day::little-32, milliseconds::little-32>> = binary_data
IO.puts("Julian day: #{julian_day}")
IO.puts("Milliseconds: #{milliseconds}")

# Check if it tries text parsing first
trimmed = String.trim(binary_data)
IO.puts("Trimmed as text: #{inspect(trimmed)}")

# Let's manually check the date conversion
try do
  # Algorithm from "Astronomical Algorithms" by Jean Meeus
  a = julian_day + 32044
  b = div(4 * a + 3, 146097)
  c = a - div(146097 * b, 4)
  d = div(4 * c + 3, 1461)
  e = c - div(1461 * d, 4)
  m = div(5 * e + 2, 153)
  
  day = e - div(153 * m + 2, 5) + 1
  month = m + 3 - 12 * div(m, 10)
  year = 100 * b + d - 4800 + div(m, 10)
  
  IO.puts("Converted date: #{year}-#{month}-#{day}")
  
  case Date.new(year, month, day) do
    {:ok, date} -> IO.puts("Date conversion successful: #{date}")
    {:error, reason} -> IO.puts("Date conversion failed: #{reason}")
  end
rescue
  error -> IO.puts("Date conversion crashed: #{inspect(error)}")
end

# Check time conversion
total_seconds = div(milliseconds, 1000)
remaining_milliseconds = rem(milliseconds, 1000)

hours = div(total_seconds, 3600)
minutes = div(rem(total_seconds, 3600), 60)
seconds = rem(total_seconds, 60)
microseconds = remaining_milliseconds * 1000

IO.puts("Time components: #{hours}:#{minutes}:#{seconds}.#{remaining_milliseconds}")

if milliseconds >= 0 and milliseconds < 86_400_000 do
  case Time.new(hours, minutes, seconds, microseconds) do
    {:ok, time} -> IO.puts("Time conversion successful: #{time}")
    {:error, reason} -> IO.puts("Time conversion failed: #{reason}")
  end
else
  IO.puts("Milliseconds out of range: #{milliseconds}")
end