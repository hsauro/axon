# split, join, trim, and int/real reading numbers from strings.
println(split("  a  b\tc\n"))
println(split("a,,b", ","), split("x", ","), split("", ","), split("a::b", "::"))
println(join({"a", "b", "c"}, ", "), join({"x", "y"}), join({}, "-"))
println("[" + trim("  hi there \n") + "]")
println(int("42"), int(" -7 "), int("+3"))
println(real("2.5"), real("1e-3"), real("-Inf"), real(".5"), real(" 7 "))
println(real("0.1") == 0.1, real("NaN") == real("NaN"), typeof(real("3")))

# A line of numbers, the way a data file gives it.
fields = split("1.5, 2.5, 4.0", ",")
total = 0.0
for f in fields
  total = total + real(f)
end
println(total)
