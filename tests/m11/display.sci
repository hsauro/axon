# Above 20 entries only the first and last 10 are shown.
print(sparse(1:21, 1:21, 2.0))
# Exactly 20 are all shown.
print(nnz(sparse(1:20, 1:20, 1.0)))
# No entries at all.
print(sparse(zeros(2, 3)))
# Inside a list.
print({speye(3), 1})
