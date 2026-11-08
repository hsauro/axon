## A naive triple-loop matrix product, against BLAS through *.
import time

function matmul(A: matrix, B: matrix): matrix
  n = size(A, 1)
  m = size(B, 2)
  p = size(A, 2)
  C = zeros(n, m)
  for i in 1:n
    for j in 1:m
      s = 0.0
      for k in 1:p
        s = s + A[i, k] * B[k, j]
      end
      C[i, j] = s
    end
  end
  return C
end

A = rand(60, 60)
B = rand(60, 60)
print("matmul", max(abs(matmul(A, B) - A * B)) < 1e-9, time.format(time.bench(matmul, A, B).best))
print("blas", true, time.format(time.bench(function() return A * B end).best))
