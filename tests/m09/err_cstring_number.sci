#! error: TypeError
extern "axontest"
  function add_i32(a: int32, b: int32): int32
  function add_u8(a: uint8, b: uint8): uint8
  function mul_f64(a: float64, b: float64): float64
  function set_i32(p: ref int32, v: int32)
  function scale_f64(p: ptr float64, n: int32, f: float64)
  function sum_i32(p: ptr int32, n: int32): int32
  function str_len(s: cstring): int32
  function char_code(c: char): int32
  function apply_cb(cb: callback(x: int32): int32, x: int32): int32
  function register_cb(cb: callback(x: int32): int32)
  function fire(x: int32): int32
  function call_in_thread(cb: callback(x: int32): int32, x: int32): int32
end
x = str_len(5)
