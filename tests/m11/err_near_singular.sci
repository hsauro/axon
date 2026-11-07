#! error: SingularMatrix
# The second pivot is 1e-20 against a first of 1.
x = sparse([1, 2, 2], [1, 1, 2], [1.0, 1.0, 1e-20]) \ [1.0; 1.0]
