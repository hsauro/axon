A = [1, 2; 3, 4]
B = [5, 6; 7, 8]
print(A * B)
v = [1; 1]
print(A * v)
print(v' * v, typeof(v' * v))
print(v * v')
print([1, 2, 3] * [4; 5; 6])
print(A * 2.5)
C = [1, 2, 3; 4, 5, 6]
print(C * [1; 0; 1])
print([1, 2; 3, 4] * [1i; 1])
