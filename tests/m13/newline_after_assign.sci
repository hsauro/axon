# A line break after "=" continues the statement on the next line.
r = {products: dict("A" => 2), reactants: dict("A" => 1)}
N = zeros(2, 2)
N[1, 1] =
  get(r.products, "A", 0) -
  get(r.reactants, "A", 0)
a =
  3
local b: real =

  4
[p, q] =
  size(N)
f = function(x, y =
    2; z =
    3)
  return x + y + z
end
println(N[1, 1], a, b, p, q, f(1))
