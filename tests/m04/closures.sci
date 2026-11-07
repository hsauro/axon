# The reference's examples
count = 0
tick = function() count = count + 1 end
tick(); tick()
print(count)
count = 0
tick = function()
  local count = 0
  count = count + 1
end
tick(); tick()
print(count)

# A closure sees later changes outside it
a = 1
get_a = function() return a end
a = 5
print(get_a())

# Independent counters: each call makes a new scope, kept alive by its closure
function make_counter()
  n = 0
  return function()
    n = n + 1
    return n
  end
end
c1 = make_counter()
c2 = make_counter()
print(c1(), c1(), c1(), c2())

# Closures over parameters
function adder(k) return function(x) return x + k end end
add5 = adder(5)
add10 = adder(10)
print(add5(1), add10(1))
