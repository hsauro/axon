## Collections: lists, records and dictionaries, and handling errors.

samples = {1.5, 2.25, 3.0}
samples = append(samples, 4.75)
total = 0.0
for s in samples
  total = total + s
end
println("samples:", samples, " mean:", total / length(samples))

# A record groups named values; fields are read with a dot.
params = {rate: 0.3, capacity: 100.0, label: "logistic"}
println("model", params.label, "with rate", params.rate)

# A dictionary maps keys to values.
counts = dict("A" => 3, "C" => 1)
counts["G"] = 5
for k in keys(counts)
  println(k, "->", counts[k])
end
println("T present?", haskey(counts, "T"), " default:", get(counts, "T", 0))

# Errors are values you can catch and inspect.
try
  counts["T"]
catch err
  println("caught", err.kind, "-", err.message)
end
