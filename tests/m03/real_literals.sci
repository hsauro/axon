# Real literals are read to the nearest double, ties to even.
function half(k)
  # 2^-k, by exact halvings.
  x = 1.0
  for i in 1:k
    x = x / 2
  end
  return x
end
# 17 significant digits: these two literals are adjacent doubles, one unit
# in the last place (2^-54 here) apart.
println(0.47659061098406563 - 0.4765906109840656 == half(54))
println(imag(0.47659061098406563i) - imag(0.4765906109840656i) == half(54))
# Halfway between two doubles: ties go to the even one.
println(9007199254740993.0 == 9007199254740992.0, 9007199254740995.0 == 9007199254740996.0)
println(9007199254740993.000000000000000001 == 9007199254740994.0)
# The shortest round-trip forms.
println(0.1 + 0.2 == 0.30000000000000004, 0.1 + 0.2 == 0.3)
# Subnormals: half the smallest one rounds to zero (even), anything more up.
println(4.9406564584124654e-324 == half(1074), 2.4703282292062327e-324 == 0.0,
  2.4703282292062328e-324 == half(1074))
println(2.2250738585072014e-308 == half(1022), 1e-400 == 0.0)
# The largest double, from either side of its rounding interval.
println(1.7976931348623158e308 == 1.7976931348623157e308)
# Many digits, and digits before a negative exponent.
println(0.1000000000000000055511151231257827021181583404541015625 == 0.1)
println(1000000000000000000000000.0e-24 == 1.0, 123.456e2 == 12345.6)
