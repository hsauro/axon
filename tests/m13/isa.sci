# isa(x, T): exact types, by name or by declared record type.
println(isa(1, "int"), isa(1, "real"), isa(1.0, "real"), isa(true, "bool"))
println(isa(1 + 2i, "complex"), isa("a", "string"), isa(nothing, "nothing"))
println(isa([1; 2], "vector"), isa([1; 2], "vector{int}"), isa([1; 2], "vector{real}"))
println(isa([1, 2; 3, 4], "matrix"), isa([1, 2; 3, 4], "vector"), isa([1.0, 2.0], "matrix{real}"))
println(isa(1:3, "range"), isa({1, 2}, "list"), isa(dict("a" => 1), "dict"))
println(isa(sin, "function"), isa(function(x) return x end, "function"), isa(1, "function"))
println(isa({a: 1}, "record"), isa(speye(2), "sparse"), isa(1, "vector"))

record Point
  x: real
  y: real
end
p = Point(1.0, 2.0)
println(isa(p, Point), isa(p, "Point"), isa(p, "record"), isa({x: 1.0, y: 2.0}, Point))

# Generic behaviour from one function.
function describe(v)
  if isa(v, "vector{real}")
    return "real vector"
  elseif isa(v, Point)
    return "point"
  end
  return typeof(v)
end
println(describe([1.0; 2.0]), "|", describe(p), "|", describe("s"))
