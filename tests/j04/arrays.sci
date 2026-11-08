# Arrays in compiled code. Each line: the compiled result, whether the
# interpreter gives the same, the array copies the compiled call made,
# whether the interpreter made as many, and whether the function compiled.

function both1(f, x)
  __jit_mode("on")
  c = __copies()
  a = f(x)
  ca = __copies() - c
  __jit_mode("off")
  c = __copies()
  b = f(x)
  cb = __copies() - c
  __jit_mode("on")
  print(string(a), string(a) == string(b), ca, ca == cb, __jit_compiled(f))
end

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

function trace(A: matrix{real}): real
  s = 0.0
  for i in 1:size(A, 1)
    s = s + A[i, i]
  end
  return s
end

function matmul(A: matrix{real}, B: matrix{real}): matrix{real}
  C = zeros(size(A, 1), size(B, 2))
  for i in 1:size(A, 1)
    for j in 1:size(B, 2)
      s = 0.0
      for k in 1:size(A, 2)
        s = s + A[i, k] * B[k, j]
      end
      C[i, j] = s
    end
  end
  return C
end

function mm_trace(n: int): real
  A = zeros(n, n)
  for i in 1:n
    for j in 1:n
      A[i, j] = i + 2 * j
    end
  end
  return trace(matmul(A, A))
end

function total(v: vector{real}): real
  s = 0.0
  for x in v
    s = s + x
  end
  return s + v[end]
end

# The argument is shared with the caller: the first write copies, the
# second does not.
function bump_first(v: vector{real}): real
  v[1] = v[1] + 100.0
  v[2] = v[2] + 1.0
  return v[1] + v[2]
end

# The loop holds the array it iterates, so the first write copies.
function self_write(v: vector{real}): real
  for x in v
    v[1] = v[1] + x
  end
  return v[1]
end

function isum(v: vector{int}): int
  s = 0
  for k in 1:length(v)
    s = s + v[k] * k
  end
  v[1] = true
  return s + v[1]
end

function shape(A: matrix{real}): int
  [m, n] = size(A)
  return m * 10 + n
end

function ops(v: vector{real}): real
  w = 2 * v - v ./ 2.0
  return sum(w) + sum(-v)
end

both1(sieve, 1000)
both1(mm_trace, 3)
both1(total, [1.0; 2.0; 3.0])
both1(bump_first, [1.0; 2.0])
both1(self_write, [1.0; 2.0; 3.0])
both1(isum, [1; 2; 3])
both1(shape, zeros(2, 3))
both1(ops, [1.0; 2.0])
print(__jit_compiled(matmul), __jit_compiled(trace))
