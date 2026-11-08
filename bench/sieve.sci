## The sieve of Eratosthenes: vector reads and writes in nested loops.
import time

function sieve(n: int): int
  flags = ones(n)
  flags[1] = 0.0
  count = 0
  for i in 2:n
    if flags[i] == 1.0
      count = count + 1
      j = i * i
      while j <= n
        flags[j] = 0.0
        j = j + i
      end
    end
  end
  return count
end

print("sieve", sieve(100000) == 9592, time.format(time.bench(sieve, 100000).best))
