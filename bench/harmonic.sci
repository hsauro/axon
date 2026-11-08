## A scalar loop: the partial sum of the harmonic series.
import time

function harmonic(n: int): real
  s = 0.0
  for k in 1:n
    s = s + 1.0 / k
  end
  return s
end

print("harmonic", abs(harmonic(100000) - 12.090146129863428) < 1e-9, time.format(time.bench(harmonic, 100000).best))
