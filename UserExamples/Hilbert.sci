

# Compute the Hilbert Matrix

n = 5 # Size of matrix
m = zeros(n, n)

for i in 1:n
    for j in 1:n
        m[i,j] = 1/(i+j-1);
    end;
end;

println (m)