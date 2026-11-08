## Timing code with the time module.
## time.bench calls a function repeatedly and reports the time per call.
## Each bench takes a second or two, so this runs for about ten seconds.

import time

## Fibonacci by recursion: many small calls.
function fib(n)
  if n < 2
    return n
  end
  return fib(n - 1) + fib(n - 2)
end

## The same with a loop.
function fib_loop(n)
  a = 0
  b = 1
  for k in 1:n
    c = a + b
    a = b
    b = c
  end
  return a
end

## One timed call, with a clock.
t0 = time.clock()
f = fib(22)
print("fib(22) =", f, "took", time.format(time.clock() - t0))

## Or let elapsed do it; extra arguments go to the function.
print("again:", time.format(time.elapsed(fib, 22)))

## bench repeats the call until a run lasts long enough, five times over.
for n in [10, 20]
  r = time.bench(fib, n)
  q = time.bench(fib_loop, n)
  print("n =", n, "  recursive", time.format(r.best), "  loop", time.format(q.best))
end

## A lambda times any expression.
A = rand(200, 200)
r = time.bench(function() return A * A end)
print("200x200 matrix product:", time.format(r.best), "(best of", r.runs, "runs of", r.loops, "loops)")
