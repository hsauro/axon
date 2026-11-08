import time
# The clock is monotonic; sleep waits at least as long as asked.
t0 = time.clock()
time.sleep(0.02)
t1 = time.clock()
print(typeof(t0), t1 >= t0, t1 - t0 >= 0.019)
time.sleep(0)
# Wall clock: seconds since 1970, later than 2023-11-14.
print(typeof(time.now()), time.now() > 1.7e9)

# elapsed passes the arguments on and returns seconds.
calls = 0
function work(a, b)
  global calls
  calls = calls + 1
  return a + b
end
e = time.elapsed(work, 2, 3)
print(typeof(e), e >= 0, calls)
print(time.elapsed(sin, 1.0) >= 0)

# bench: per-call times from 5 runs of the same number of loops.
r = time.bench(function() return 1 + 1 end)
print(r.runs, r.loops >= 1, r.best <= r.mean, r.mean <= r.worst, r.best > 0)
calls = 0
r = time.bench(work, 1, 2)
print(calls == r.loops * r.runs + (r.loops - 1))

# format: three significant digits in a fitting unit.
print(time.format(1.5), time.format(12.345), time.format(1234.5))
print(time.format(0.0123), time.format(0.00456), time.format(4.56e-5))
print(time.format(7e-9), time.format(1.5e-10), time.format(0), time.format(2))
print(time.format(0.99996), time.format(9.9996e-4), time.format(-0.25))
