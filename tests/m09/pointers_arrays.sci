extern "axontest"
  function scale_f64(p: ptr float64, n: int32, f: float64)
  function sum_i32(p: ptr int32, n: int32): int32
  function double_i32(p: ptr int32, n: int32)
  function negate_i64(p: ptr int64, n: int32)
  function conj_c(p: ptr complex, n: int32)
  function halve_f32(p: ptr float32, n: int32)
  function is_null(p: ptr void): int32
end
v = [1.0; 2.0; 3.0]
c0 = __copies()
scale_f64(v, 3, 10.0)
print(v', __copies() - c0)
A = [1.0, 2.0; 3.0, 4.0]
B = A
c0 = __copies()
scale_f64(A, 4, 2.0)
print(A[1, 2], A[2, 1], B[1, 2], __copies() - c0)
w = [1; 2; 3]
print(sum_i32(w, 3))
double_i32(w, 3)
negate_i64(w, 3)
print(w')
z = [1 + 2i; 3 - 4i]
conj_c(z, 2)
print(z')
h = [1.0, 3.0]
halve_f32(h, 2)
print(h)
print(is_null(nothing), is_null([1, 2]), is_null(w))
