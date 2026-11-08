#! error: ArgumentError
__jit_mode("on")
function make(n: int): real
  v = zeros(n)
  return sum(v)
end
println(make(2))
make(-1)
