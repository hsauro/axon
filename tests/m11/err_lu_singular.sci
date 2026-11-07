#! error: SingularMatrix
import linalg
[L, U] = linalg.lu(sparse([1, 2], [1, 2], [1.0, 0.0]) + sparse([1], [1], [1.0], 2, 2))
