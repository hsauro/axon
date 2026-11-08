function minmax(a, b)
  if a < b return a, b end
  return b, a
end
[lo, hi] = minmax(7, 3)
println(lo, hi)
function three() return 1, "two", 3.0 end
[a, b, c] = three()
println(a, b, c)
[x] = 5
println(x)
# Swapping through a function
function swap(p, q) return q, p end
[lo, hi] = swap(lo, hi)
println(lo, hi)
