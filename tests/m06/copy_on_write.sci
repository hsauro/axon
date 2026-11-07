A = [1, 2; 3, 4]
B = A
B[1, 1] = 100
print(A[1, 1], B[1, 1])
c0 = __copies()
function total(M) return sum(M) end
s = total(A)
print(s, __copies() - c0)
function zero_corner(M)
  M[1, 1] = 0
  return M
end
N = zero_corner(A)
print(A[1, 1], N[1, 1], __copies() - c0)
c1 = __copies()
for k in 1:100
  A[1, 2] = k
end
print(A[1, 2], __copies() - c1)
C = A
for x in C
  C[1, 1] = -1
end
print(A[1, 1], C[1, 1])
