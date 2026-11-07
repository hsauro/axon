#! error: DimensionError
import linalg
[L, U] = linalg.lu(sparse([1], [2], [1.0]))
