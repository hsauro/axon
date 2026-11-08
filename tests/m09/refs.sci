extern "axontest"
  function set_i32(p: ref int32, v: int32)
  function incr_f64(p: ref float64)
  function swap_i64(a: ref int64, b: ref int64)
end
x = 0
set_i32(x, 42)
y = 1.5
incr_f64(y)
a = 1
b = 2
swap_i64(a, b)
println(x, y, a, b)
function inside()
  local z = 7
  set_i32(z, -3)
  return z
end
println(inside())
n = 2
incr_f64(n)
println(n, typeof(n))
