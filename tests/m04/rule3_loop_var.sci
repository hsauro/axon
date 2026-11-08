# Rule 3: the loop variable is local to the body, with a fresh binding per
# iteration, so closures made in different iterations see different values.
first = nothing
second = nothing
for i in 1:3
  if i == 1
    first = function() return i end
  elseif i == 2
    second = function() return i end
  end
end
println(first(), second())
