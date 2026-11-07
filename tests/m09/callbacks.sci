extern "axontest"
  type IntFn = callback(x: int32): int32
  function apply_cb(cb: IntFn, x: int32): int32
  function apply_twice(cb: IntFn, x: int32): int32
  function sum_cb(cb: callback(t: float64, y: float64): float64, n: int32): float64
  function call_mixed(cb: callback(a: int32, b: float64, c: ptr void, d: float32, e: int64): float64): float64
  function call_many(cb: callback(a1: int64, a2: int64, a3: int64, a4: int64, a5: int64,
                                  a6: int64, d1: float64): int64): int64
  function apply_f32(cb: callback(x: float32): float32, x: float32): float32
  function apply_ptr(cb: callback(p: ptr void): ptr void, p: ptr void): ptr void
  function call_void(cb: callback(x: int32), x: int32)
  function make_handle(v: int32): ptr void
  function handle_value(h: ptr void): int32
  function add_i32(a: int32, b: int32): int32
end
print(apply_cb(function(k) return k * k end, 7), apply_twice(function(k) return k + 10 end, 1))
print(sum_cb(function(t, y) return t * y end, 4))
print(call_mixed(function(a, b, c, d, e) return a + b + d + e end))
seen = nothing
call_mixed(function(a, b, c, d, e)
  seen = {a, b, c, d, e}
  return 0.0
end)
print(seen)
print(call_many(function(a1, a2, a3, a4, a5, a6, d)
  return a1 + 10*a2 + 100*a3 + 1000*a4 + 10000*a5 + 100000*a6 + int(d * 2)
end))
print(apply_f32(function(x) return x * 4 end, 0.75))
h = make_handle(9)
print(handle_value(apply_ptr(function(p) return p end, h)))
total = 0
call_void(function(x) total = total + x end, 5)
call_void(function(x) total = total + x end, 6)
print(total)
print(apply_cb(function(k) return add_i32(k, 100) end, 1))
function square(k) return k * k end
print(apply_cb(square, 12), apply_cb(abs, -5))
