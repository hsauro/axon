## Timing code, and what the JIT compiler does for a loop.

import time

## A loop that sums 1/k^2; it converges to pi^2 / 6.
function basel(n: int): real
  s = 0.0
  for k in 1:n
    s = s + 1.0 / (k * k)
  end
  return s
end

println("basel(1e6) =", basel(1000000), " pi^2/6 =", pi^2 / 6)

# bench calls the function repeatedly and reports seconds per call.
r = time.bench(basel, 100000)
println("basel(1e5):", time.format(r.best), "per call")

# A built-in operator runs native code whatever the JIT does.
A = rand(200, 200)
q = time.bench(function() return A * A end)
println("200 by 200 product:", time.format(q.best))
