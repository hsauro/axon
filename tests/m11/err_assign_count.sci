#! error: DimensionError
S = speye(3)
S[1, :] = [1, 2]
