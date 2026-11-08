extern "axontest"
  function add_i32(a: int32, b: int32): int32
  function add_i64(a: int64, b: int64): int64
  function add_u8(a: uint8, b: uint8): uint8
  function neg_i8(a: int8): int8
  function max_u32(): uint32
  function mul_f64(a: float64, b: float64): float64
  function mul_f32(a: float32, b: float32): float32
  function mixed(a: int32, b: float64, c: int64, d: float32, e: int32, f: float64): float64
  function many(a1: int64, a2: int64, a3: int64, a4: int64, a5: int64,
                a6: int64, a7: int64, a8: int64, a9: int64, a10: int64): int64
  function char_code(c: char): int32
  function plus(a: int32, b: int32): int32 name "add_i32"
end
println(add_i32(2, 3), add_i32(-7, true), add_i64(9000000000, 1))
println(add_u8(200, 100), neg_i8(-128), max_u32())
println(mul_f64(1.5, 4), mul_f32(1.5, 2), typeof(mul_f32(1.0, 1.0)))
println(mixed(1, 0.5, 10, 0.25, 100, 0.125))
println(many(1, 2, 3, 4, 5, 6, 7, 8, 9, 10))
println(char_code("A"), char_code(66), plus(40, 2))
println(typeof(add_i32), add_i32)
