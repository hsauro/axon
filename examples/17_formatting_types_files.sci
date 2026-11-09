## Formatting output, checking types, and reading and writing files.
## Part 1 asks values what they are (typeof, eltype, isa); part 2 controls how
## numbers and arrays print (the fmt module); part 3 writes and reads text,
## CSV and JSON files (the io module). Files it makes are deleted at the end.

import fmt
import io

# ---------------------------------------------------------------- 1. types

println("== Types")
values = {42, 2.5, 1 + 2i, true, "text", [1; 2; 3], [1.0, 2.0; 3.0, 4.0],
          1:5, {1, 2}, {name: "Ann"}, dict("k" => 1), sin, nothing}
kinds = {}
for v in values
  kinds = append(kinds, typeof(v))
end
println(join(kinds, ", "))

# eltype says what an array holds; isa tests a type, element type included.
A = [1.0, 2.0; 3.0, 4.0]
println("eltype:", eltype(A), eltype([1; 2]), eltype([true; false]))
println("isa:", isa(A, "matrix"), isa(A, "matrix{real}"), isa(A, "vector"), isa(3, "real"))

# One function, different behaviour for different kinds of value.
function describe(x)
  if isa(x, "string")
    return "a string of " + string(length(x)) + " characters"
  elseif isa(x, "vector") or isa(x, "matrix")
    [m, n] = size(x)
    return "a " + string(m) + " by " + string(n) + " " + typeof(x) + " of " + eltype(x)
  elseif isa(x, "int") or isa(x, "real")
    return "the number " + string(x)
  end
  return "a " + typeof(x)
end
for v in {"hello", A, [1; 2; 3], 7, {1, 2}}
  println(describe(v))
end

# ---------------------------------------------------------------- 2. formatting

println()
println("== Formatting")
B = [1.5, -22.25; 3.0, 1.0 / 3.0]
println(B)                                  # the standard display, with header

# Display settings: they change every printed value until changed back.
fmt.set_header(false)                       # no "2x2 matrix{real}" line
fmt.set_decimals(3)                         # three decimals for every real
println(B)
fmt.set_decimals()                          # back to significant digits
fmt.set_header()

fmt.set_sci(1e-6, 1e9)                      # scientific only below 1e-6 or from 1e9
println(0.00002, 3.5e8, 2.0e9, 4.0e-7)
fmt.set_sci()                               # back to 1e-4 and 1e15
println(0.00002, 3.5e8)

# Formatting for one use, returned as text: the settings stay as they are.
println(fmt.matrix(B, decimals = 2))
println(fmt.matrix(B, decimals = 1, sep = ", ", align = false))
println("pi:", fmt.number(pi, decimals = 4), fmt.number(pi, digits = 3),
        fmt.number(6.02214076e23, sci = true, decimals = 3))

# A small aligned report built from those pieces.
names = {"Na", "K", "Ca"}
conc = [140.0; 4.2; 2.45]
println("Ion   mM")
for k in 1:length(names)
  println(names[k] + repeat(" ", 4 - length(names[k])) + fmt.number(conc[k], decimals = 2, width = 7))
end

# ---------------------------------------------------------------- 3. files

println()
println("== Files")

# A CSV table with a header: write it, look at it, read it back.
t = [range(0, 10, 2)]
y = round(100.0 * exp(-t / 4.0) * 1000) / 1000      # to 3 decimals, as measured
io.write_csv("_decay.csv", [t, y], {"time", "amount"})
for line in io.read_lines("_decay.csv")
  println(line)
end
table = io.read_csv("_decay.csv")
println("columns:", table.names, "rows:", size(table.data, 1))
println("amount at t = 4:", fmt.number(table.data[3, 2], decimals = 3))

# A text file read line by line, with each line taken apart.
io.write_file("_settings.txt", """
    # model settings
    rate = 0.25
    steps = 40
    label = first run
    """)
settings = dict()
for line in io.read_lines("_settings.txt")
  line = trim(line)
  if line == "" or startswith(line, "#")
    continue
  end
  parts = split(line, "=")
  settings[trim(parts[1])] = trim(parts[2])
end
rate = real(settings["rate"])
steps = int(settings["steps"])
println(settings["label"] + ":", "rate", rate, "steps", steps, typeof(rate), typeof(steps))

# Results saved as JSON keep their structure: records, lists and vectors.
io.write_json("_results.json", {label: settings["label"], rate: rate, amounts: y})
back = io.read_json("_results.json")
println("from JSON:", back.label, typeof(back.amounts), length(back.amounts))

# Tidy up.
for f in {"_decay.csv", "_settings.txt", "_results.json"}
  if io.file_exists(f)
    io.delete_file(f)
  end
end
println("files left:", io.file_exists("_decay.csv"), io.file_exists("_results.json"))
