#! error: SingularMatrix
# The second column is empty.
x = sparse([1, 2], [1, 1], [1.0, 1.0], 2, 2) \ [1.0; 1.0]
