d = dict("Km" => 0.5, "Vm" => 10.0)
println(d)
println(d["Km"], d["Vm"], length(d))
d["Km"] = 0.7
d["n"] = 2
println(d)
println(get(d, "Km", 0), get(d, "zz", "default"))
println(keys(d), haskey(d, "n"), haskey(d, "zz"))
for k in d
  println(k, d[k])
end
n = dict(1 => "one", 2.5 => "two and a half")
println(n[1.0], n[2.5], haskey(n, true))
e = dict()
println(e, length(e), typeof(e))
println(dict("a" => 1, "b" => 2) == dict("b" => 2, "a" => 1), dict("a" => 1) == dict("a" => 2))
nested = dict("p" => {x: 1})
nested["p"].x = 5
println(nested)
