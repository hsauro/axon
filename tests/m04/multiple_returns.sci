function minmax(a, b)
  if a < b return a, b end
  return b, a
end
[lo, hi] = minmax(7, 3)
print(lo, hi)
function three() return 1, "two", 3.0 end
[a, b, c] = three()
print(a, b, c)
[x] = 5
print(x)
# Swapping through a function
function swap(p, q) return q, p end
[lo, hi] = swap(lo, hi)
print(lo, hi)
