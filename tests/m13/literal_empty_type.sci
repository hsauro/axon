# A vector with no elements still counts towards a literal's element type;
# a skipped [] block does not.
println(eltype([zeros(0); 5]), eltype([5; zeros(0)]), eltype([zeros(0); true]))
println(eltype([[]; 5]), eltype([1:0; 2]), eltype([zeros(0); 1 + 2i]))

function odds(n)
  v = zeros(0)
  for k in 1:n
    if mod(k, 2) == 1
      v = [v; k]
    end
  end
  return v
end
println(eltype(odds(5)), length(odds(5)))
mode = __jit_mode("force")
println(eltype(odds(5)), length(odds(5)))
__jit_mode(mode)
