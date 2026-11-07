d = dict("Km" => 0.5, "Vm" => 10.0)
print(d)
print(d["Km"], d["Vm"], length(d))
d["Km"] = 0.7
d["n"] = 2
print(d)
print(get(d, "Km", 0), get(d, "zz", "default"))
print(keys(d), haskey(d, "n"), haskey(d, "zz"))
for k in d
  print(k, d[k])
end
n = dict(1 => "one", 2.5 => "two and a half")
print(n[1.0], n[2.5], haskey(n, true))
e = dict()
print(e, length(e), typeof(e))
print(dict("a" => 1, "b" => 2) == dict("b" => 2, "a" => 1), dict("a" => 1) == dict("a" => 2))
nested = dict("p" => {x: 1})
nested["p"].x = 5
print(nested)
