## Recursive Fibonacci: call overhead and int arithmetic.
import time

function fib(n: int): int
  if n < 2
    return n
  end
  return fib(n - 1) + fib(n - 2)
end

print("fib", fib(22) == 17711, time.format(time.bench(fib, 22).best))
