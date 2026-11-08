# display_size: arrays up to rows x cols are shown in full; above that, the
# first (n + 1) div 2 and last n div 2 rows or columns.
A = reshape([1:36], 3, 12)
println(A)
display_size(3, 12)
println(A)
display_size(2, 3)
println(A)
display_size()
println(A[1:2, 1:9])

# display_decimals: every displayed real, scalars and array entries alike;
# ints are unaffected, and exponent form stays from 1e15.
display_decimals(3)
println(1 / 3, 2.0, -0.0001, 1e20, 2 + 3.5i)
println(0.0:0.25:1.0, {1.5, [2.25]})
println([1.0, 22.5; -3.25, 4.0])
println(string(0.5), 0.0 / 0.0, -1.0 / 0.0)
println(7, [1, 2])
display_decimals()
println(1 / 3)

# format: exactly that many decimals, rounded from the exact binary value
# (ties to even), independent of display_decimals.
println(format(3.14159, 2), format(2.675, 2), format(0.125, 2), format(0.375, 2),
  format(2.5, 0), format(3.5, 0))
println(format(-0.001, 2), format(-1.006, 2), format(7, 3), format(999.9996, 3),
  format(1e20, 1))
println(format(1 / 3, 20), typeof(format(1.0, 1)), format(5e-324, 2))
