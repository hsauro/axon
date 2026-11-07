## Linear algebra: decompositions and related functions over LAPACK,
## through the LAPACKE interface of OpenBLAS. See the Language Reference,
## "The linalg module". The operators \, / and ^ are core and are used here.

extern "libopenblas"
  function LAPACKE_dgetrf(layout: int32, m: int32, n: int32, a: ptr float64, lda: int32,
                          ipiv: ptr int32): int32
  function LAPACKE_zgetrf(layout: int32, m: int32, n: int32, a: ptr complex, lda: int32,
                          ipiv: ptr int32): int32
  function LAPACKE_dgeev(layout: int32, jobvl: char, jobvr: char, n: int32, a: ptr float64,
                         lda: int32, wr: ptr float64, wi: ptr float64, vl: ptr float64,
                         ldvl: int32, vr: ptr float64, ldvr: int32): int32
  function LAPACKE_zgeev(layout: int32, jobvl: char, jobvr: char, n: int32, a: ptr complex,
                         lda: int32, w: ptr complex, vl: ptr complex, ldvl: int32,
                         vr: ptr complex, ldvr: int32): int32
  function LAPACKE_dgesvd(layout: int32, jobu: char, jobvt: char, m: int32, n: int32,
                          a: ptr float64, lda: int32, s: ptr float64, u: ptr float64,
                          ldu: int32, vt: ptr float64, ldvt: int32, superb: ptr float64): int32
  function LAPACKE_zgesvd(layout: int32, jobu: char, jobvt: char, m: int32, n: int32,
                          a: ptr complex, lda: int32, s: ptr float64, u: ptr complex,
                          ldu: int32, vt: ptr complex, ldvt: int32, superb: ptr float64): int32
  function LAPACKE_dgeqrf(layout: int32, m: int32, n: int32, a: ptr float64, lda: int32,
                          tau: ptr float64): int32
  function LAPACKE_zgeqrf(layout: int32, m: int32, n: int32, a: ptr complex, lda: int32,
                          tau: ptr complex): int32
  function LAPACKE_dorgqr(layout: int32, m: int32, n: int32, k: int32, a: ptr float64,
                          lda: int32, tau: ptr float64): int32
  function LAPACKE_zungqr(layout: int32, m: int32, n: int32, k: int32, a: ptr complex,
                          lda: int32, tau: ptr complex): int32
  function LAPACKE_dpotrf(layout: int32, uplo: char, n: int32, a: ptr float64, lda: int32): int32
  function LAPACKE_zpotrf(layout: int32, uplo: char, n: int32, a: ptr complex, lda: int32): int32
  function LAPACKE_dgelsd(layout: int32, m: int32, n: int32, nrhs: int32, a: ptr float64,
                          lda: int32, b: ptr float64, ldb: int32, s: ptr float64,
                          rcond: float64, rank: ref int32): int32
  function LAPACKE_zgelsd(layout: int32, m: int32, n: int32, nrhs: int32, a: ptr complex,
                          lda: int32, b: ptr complex, ldb: int32, s: ptr float64,
                          rcond: float64, rank: ref int32): int32
end

COL = 102                          # LAPACK_COL_MAJOR
EPS = 2.220446049250313e-16        # machine epsilon for real

# ---------------------------------------------------------------- helpers

function is_complex(A) return eltype(A) == "complex" end

# A fresh real (or complex) m×n matrix holding A, for LAPACK to overwrite.
function float_matrix(A)
  if typeof(A) == "sparse" A = full(A) end
  [m, n] = size(A)
  return reshape([A] + 0.0, m, n)
end

function square_size(A, what)
  [m, n] = size(A)
  if m != n
    error("DimensionError", what + " needs a square matrix, got " + string(m) + "×" + string(n))
  end
  return n
end

function check(info, what)
  if info < 0
    error("ArgumentError", what + ": LAPACK rejected argument " + string(-info))
  end
end

# M with everything below the diagonal set to zero.
function upper(M)
  [m, n] = size(M)
  for j in 1:n
    for i in (j + 1):m
      M[i, j] = 0
    end
  end
  return M
end

function singular_values(A)
  [m, n] = size(A)
  k = min(m, n)
  M = float_matrix(A)
  s = zeros(k)
  superb = zeros(max(k - 1, 1))
  if is_complex(M)
    info = LAPACKE_zgesvd(COL, "N", "N", m, n, M, max(m, 1), s, nothing, 1, nothing, 1, superb)
  else
    info = LAPACKE_dgesvd(COL, "N", "N", m, n, M, max(m, 1), s, nothing, 1, nothing, 1, superb)
  end
  check(info, "svd")
  if info > 0 error("DomainError", "svd: the SVD did not converge") end
  return s
end

# ---------------------------------------------------------------- solving

## The solution of A x = b for square A (the same as A \ b).
export function solve(A, b)
  square_size(A, "solve")
  return A \ b
end

## The minimum-norm least-squares solution of A x = b, for any shape of A.
export function lstsq(A, b)
  [m, n] = size(A)
  [mb, nrhs] = size(b)
  if mb != m
    error("DimensionError", "lstsq: A has " + string(m) + " rows but b has " + string(mb))
  end
  M = float_matrix(A)
  cplx = is_complex(M) or eltype(b) == "complex"
  ldb = max(max(m, n), 1)
  if cplx
    M = M + 0i
    B = complex(zeros(ldb, nrhs))
  else
    B = zeros(ldb, nrhs)
  end
  B[1:m, :] = b
  s = zeros(max(min(m, n), 1))
  r = 0
  if cplx
    info = LAPACKE_zgelsd(COL, m, n, nrhs, M, max(m, 1), B, ldb, s, -1.0, r)
  else
    info = LAPACKE_dgelsd(COL, m, n, nrhs, M, max(m, 1), B, ldb, s, -1.0, r)
  end
  check(info, "lstsq")
  if info > 0 error("DomainError", "lstsq: the SVD did not converge") end
  if typeof(b) == "vector"
    return B[1:n, 1]
  end
  return B[1:n, :]
end

## The inverse of a square matrix; SingularMatrix when it is singular.
export function inv(A)
  n = square_size(A, "inv")
  return A \ eye(n)
end

## The determinant, from the LU factorisation.
export function det(A)
  n = square_size(A, "det")
  if n == 0 return 1.0 end
  M = float_matrix(A)
  ipiv = int(zeros(n))
  if is_complex(M)
    info = LAPACKE_zgetrf(COL, n, n, M, n, ipiv)
  else
    info = LAPACKE_dgetrf(COL, n, n, M, n, ipiv)
  end
  check(info, "det")
  d = M[1, 1] * 0 + 1
  for i in 1:n
    d = d * M[i, i]
    if ipiv[i] != i d = -d end
  end
  return d
end

# ---------------------------------------------------------------- decompositions

## The eigenvalues: real when all are real, complex otherwise.
## eig(A, vectors=true) also returns the eigenvectors as the columns of a matrix.
export function eig(A; vectors = false)
  n = square_size(A, "eig")
  M = float_matrix(A)
  if is_complex(M)
    w = complex(zeros(n))
    if vectors
      V = complex(zeros(n, n))
      info = LAPACKE_zgeev(COL, "N", "V", n, M, max(n, 1), w, nothing, 1, V, max(n, 1))
    else
      info = LAPACKE_zgeev(COL, "N", "N", n, M, max(n, 1), w, nothing, 1, nothing, 1)
    end
    check(info, "eig")
    if info > 0 error("DomainError", "eig: the QR algorithm did not converge") end
    if vectors return w, V end
    return w
  end
  wr = zeros(n)
  wi = zeros(n)
  if vectors
    VR = zeros(n, n)
    info = LAPACKE_dgeev(COL, "N", "V", n, M, max(n, 1), wr, wi, nothing, 1, VR, max(n, 1))
  else
    info = LAPACKE_dgeev(COL, "N", "N", n, M, max(n, 1), wr, wi, nothing, 1, nothing, 1)
  end
  check(info, "eig")
  if info > 0 error("DomainError", "eig: the QR algorithm did not converge") end
  if all(wi == 0)
    if vectors return wr, VR end
    return wr
  end
  w = complex(wr, wi)
  if not vectors return w end
  # A complex conjugate pair keeps its real and imaginary parts in columns j and j+1.
  V = complex(VR)
  j = 1
  while j <= n
    if wi[j] != 0
      re = VR[:, j]
      im = VR[:, j + 1]
      V[:, j] = re + 1i * im
      V[:, j + 1] = re - 1i * im
      j = j + 2
    else
      j = j + 1
    end
  end
  return w, V
end

## Three values U, s, V with A = U * S * V' (adjoint for complex) and s the
## singular values in decreasing order.
export function svd(A)
  [m, n] = size(A)
  k = min(m, n)
  M = float_matrix(A)
  s = zeros(k)
  superb = zeros(max(k - 1, 1))
  if is_complex(M)
    U = complex(zeros(m, m))
    VT = complex(zeros(n, n))
    info = LAPACKE_zgesvd(COL, "A", "A", m, n, M, max(m, 1), s, U, max(m, 1), VT, max(n, 1), superb)
  else
    U = zeros(m, m)
    VT = zeros(n, n)
    info = LAPACKE_dgesvd(COL, "A", "A", m, n, M, max(m, 1), s, U, max(m, 1), VT, max(n, 1), superb)
  end
  check(info, "svd")
  if info > 0 error("DomainError", "svd: the SVD did not converge") end
  return U, s, adjoint(VT)
end

## The thin QR factorisation: Q (m×k, orthonormal columns) and R (k×n, upper).
export function qr(A)
  [m, n] = size(A)
  k = min(m, n)
  M = float_matrix(A)
  cplx = is_complex(M)
  tau = zeros(max(k, 1))
  if cplx
    tau = complex(tau)
    info = LAPACKE_zgeqrf(COL, m, n, M, max(m, 1), tau)
  else
    info = LAPACKE_dgeqrf(COL, m, n, M, max(m, 1), tau)
  end
  check(info, "qr")
  R = upper(M[1:k, :])
  Q = M[:, 1:k]
  if cplx
    info = LAPACKE_zungqr(COL, m, k, k, Q, max(m, 1), tau)
  else
    info = LAPACKE_dorgqr(COL, m, k, k, Q, max(m, 1), tau)
  end
  check(info, "qr")
  return Q, R
end

## Two values L, U with A = L * U: U upper triangular and L a row permutation
## of a unit lower-triangular matrix.
export function lu(A)
  if typeof(A) == "sparse"
    [L, U] = splu(A)
    return L, U
  end
  [m, n] = size(A)
  k = min(m, n)
  M = float_matrix(A)
  ipiv = int(zeros(max(k, 1)))
  if is_complex(M)
    info = LAPACKE_zgetrf(COL, m, n, M, max(m, 1), ipiv)
  else
    info = LAPACKE_dgetrf(COL, m, n, M, max(m, 1), ipiv)
  end
  check(info, "lu")
  U = upper(M[1:k, :])
  L = M[:, 1:k]
  for j in 1:k
    for i in 1:j - 1
      L[i, j] = 0
    end
    L[j, j] = 1
  end
  # Undo the row interchanges: row i of the factors is row perm[i] of A.
  perm = [1:m]
  for i in 1:k
    p = ipiv[i]
    t = perm[i]
    perm[i] = perm[p]
    perm[p] = t
  end
  P = L * 0
  P[perm, :] = L
  return P, U
end

## The upper-triangular Cholesky factor R with A = R' * R.
export function chol(A)
  n = square_size(A, "chol")
  M = float_matrix(A)
  if is_complex(M)
    info = LAPACKE_zpotrf(COL, "U", n, M, max(n, 1))
  else
    info = LAPACKE_dpotrf(COL, "U", n, M, max(n, 1))
  end
  check(info, "chol")
  if info > 0 error("DomainError", "chol: the matrix is not positive definite") end
  return upper(M)
end

# ---------------------------------------------------------------- derived

## The numerical rank: singular values above tol.
export function rank(A; tol = nothing)
  s = singular_values(A)
  if length(s) == 0 return 0 end
  [m, n] = size(A)
  if tol == nothing
    tol = max(m, n) * EPS * max(s)
  end
  return sum(s > tol)
end

## An orthonormal basis of the null space of A, as the columns of a matrix.
export function null(A; tol = nothing)
  [m, n] = size(A)
  [U, s, V] = svd(A)
  if tol == nothing
    smax = 0.0
    if length(s) > 0 smax = max(s) end
    tol = max(m, n) * EPS * smax
  end
  r = sum(s > tol)
  return V[:, (r + 1):n]
end

## The p-norm of a vector, or a matrix norm: p = 2, 1, "inf" or "fro".
export function norm(x; p = 2)
  t = typeof(x)
  if t == "int" or t == "real" or t == "complex" or t == "bool"
    return abs(x) * 1.0
  end
  if t == "vector" or t == "range"
    a = abs(x)
    if length(a) == 0 return 0.0 end
    if p == "inf" return max(a) * 1.0 end
    if p == 1 return sum(a) * 1.0 end
    if p == 2 return sqrt(sum(a .^ 2) * 1.0) end
    return sum(a .^ p) ^ (1 / p)
  end
  if p == 2
    s = singular_values(x)
    if length(s) == 0 return 0.0 end
    return max(s)
  end
  if p == 1 return max(sum(abs(x), 1)) * 1.0 end
  if p == "inf" return max(sum(abs(x), 2)) * 1.0 end
  if p == "fro" return sqrt(sum(abs(x) .^ 2) * 1.0) end
  error("ArgumentError", "norm: for a matrix p must be 1, 2, \"inf\" or \"fro\"")
end

## The matrix exponential, by scaling and squaring with a degree-13 Padé
## approximant (Higham, 2005).
export function expm(A)
  n = square_size(A, "expm")
  M = float_matrix(A)
  b = [64764752532480000.0, 32382376266240000.0, 7771770303897600.0,
       1187353796428800.0, 129060195264000.0, 10559470521600.0, 670442572800.0,
       33522128640.0, 1323241920.0, 40840800.0, 960960.0, 16380.0, 182.0, 1.0]
  theta = 5.371920351148152
  nrm = norm(M, p = 1)
  s = 0
  if nrm > theta
    s = ceil(log(nrm / theta) / log(2.0))
  end
  M = M / 2^s
  I = eye(n)
  A2 = M * M
  A4 = A2 * A2
  A6 = A4 * A2
  U = M * (A6 * (b[14]*A6 + b[12]*A4 + b[10]*A2) + b[8]*A6 + b[6]*A4 + b[4]*A2 + b[2]*I)
  V = A6 * (b[13]*A6 + b[11]*A4 + b[9]*A2) + b[7]*A6 + b[5]*A4 + b[3]*A2 + b[1]*I
  X = (V - U) \ (V + U)
  for k in 1:s
    X = X * X
  end
  return X
end
