# linalg.qrp: QR with column pivoting, A[:, p] = Q * R.
import linalg
from testing import approx, orthonormal

# Column 3 has the largest norm and is taken first; columns 1 and 2 are
# parallel, so the rank is 2 and R's last diagonal entry is (nearly) zero.
A = [1.0, 2, 10; 2, 4, 1; 3, 6, 0; 4, 8, 2]
[Q, R, p] = linalg.qrp(A)
println(typeof(p), eltype(p), length(p), size(Q, 1), size(Q, 2), size(R, 1), size(R, 2))
println(p[1] == 2 or p[1] == 3, approx(A[:, p], Q * R), orthonormal(Q))
println(abs(R[1, 1]) >= abs(R[2, 2]), abs(R[2, 2]) > 1, abs(R[3, 3]) < 1e-12)
println(approx(R[2, 1], 0.0), approx(R[3, 1], 0.0), approx(R[3, 2], 0.0))

# A wide matrix: k = min(m, n).
B = [1.0, 2, 3; 4, 5, 7]
[Q, R, p] = linalg.qrp(B)
println(size(Q, 2), size(R, 1), size(R, 2), approx(B[:, p], Q * R))
