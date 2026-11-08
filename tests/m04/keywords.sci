function solve(f, y0; method = "bdf", rtol = 1e-6, atol = rtol / 1000)
  return method + " " + string(rtol) + " " + string(atol)
end
println(solve(1, 2))
println(solve(1, 2, rtol = 1e-8))
println(solve(1, 2, atol = 0.5, method = "rk45"))

# Defaults are evaluated at each call
n = 0
function next_id()
  global n
  n = n + 1
  return n
end
function tag(; id = next_id()) return id end
println(tag(), tag(), tag(id = 100), tag())

# Defaults are evaluated in the defining scope, so they see later changes there
scale = 2
function scaled(x; k = scale) return x * k end
println(scaled(5))
scale = 10
println(scaled(5))

# Keyword-only functions and lambdas with keywords
greet = function(; name = "world", punct = "!") return "hello " + name + punct end
println(greet(), greet(punct = "?", name = "Axon"))
