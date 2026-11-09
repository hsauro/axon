# range(start, stop) and range(start, stop, step): the same as start:step:stop.
println(range(1, 9, 2))
println(isequal([range(1, 9, 2)], [1:2:9]))
println(isequal([range(1, 5)], [1:5]))
println(isequal([range(4)], [1; 2; 3; 4]), length(range(0)))
println(isequal([range(5, 1, -1)], [5; 4; 3; 2; 1]))
println(typeof(range(1, 3)), length(range(3, 1)))
r = range(0, 1, 0.1)
println(length(r), r[1], r[end])
println(eltype([range(0, 1, 0.5)]), eltype([range(1, 3)]))

# In a loop, compiled or not.
function odd_sum(n)
  s = 0
  for k in range(1, n, 2)
    s = s + k
  end
  for k in range(n)
    s = s + 1
  end
  return s
end
println(odd_sum(9))
mode = __jit_mode("force")
println(odd_sum(9), __jit_compiled(odd_sum))
__jit_mode(mode)

# The arguments are evaluated in the order written.
seen = {}
note = function(x)
  global seen
  seen = append(seen, x)
  return x
end
for k in range(note(1), note(3), note(1))
end
println(seen)
