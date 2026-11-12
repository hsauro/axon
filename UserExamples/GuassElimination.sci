## Gaussian elimination with partial pivoting, 1-based throughout.
## (Axon indexes from 1, so there is no "ignore row/col 0" padding trick
##  needed, and no separate 0-based variant either -- one routine covers both
##  of the original BASIC-style versions.)

function swap_row(A, b, r1, r2, n)
  if r1 != r2
    for j in 1:n
      tmp = A[r1, j]
      A[r1, j] = A[r2, j]
      A[r2, j] = tmp
    end
    tmp = b[r1]
    b[r1] = b[r2]
    b[r2] = tmp
  end
  return A, b          # Axon has no out-parameters: return the changes
end

function gauss_eliminate(A, b, n)
  x = zeros(n)

  for k in 1:(n - 1)
    pivot = abs(A[k, k])
    max_row = k

    for row in (k + 1):n
      tmp = abs(A[row, k])
      if tmp > pivot
        max_row = row
        pivot = tmp
      end
    end

    [A, b] = swap_row(A, b, k, max_row, n)

    for row in (k + 1):n
      factor = A[row, k] / A[k, k]
      for col in (k + 1):n
        A[row, col] = A[row, col] - factor * A[k, col]
      end
      A[row, k] = 0
      b[row] = b[row] - factor * b[k]
    end
  end

  println("Back substitution")
  for row in n:-1:1
    tmp = b[row]
    for j in (row + 1):n
      tmp = tmp - x[j] * A[row, j]
    end
    x[row] = tmp / A[row, row]
  end

  return x
end

# --- Solve A x = b for:
#   2x1 +  x2             = 2
#    x1 +  x2 +  x3        = 1
#          x2 + 2x3 +  x4  = 4
#                x3 + 2x4  = 8

# Must use real matrix for JIT, set one element to a real value
A = [2.0, 1.0, 0.0, 0.0;
     1.0, 1.0, 1.0, 0.0;
     0.0, 1.0, 2.0, 1.0;
     0.0, 0.0, 1.0, 2.0]

# Must use real vector for JIT, set one element to a real value
b = [2.0; 1; 4; 8]

println(A)
println(b)

x = gauss_eliminate(A, b, 4)

println(string(x[1]) + ", " + string(x[2]) + ", " + string(x[3]) + ", " + string(x[4]))
