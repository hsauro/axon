

# The Ackermann function is a classic example of a recursive function
# See https://rosettacode.org/wiki/Ackermann_function

function ack (x, y)
  if x == 0 
     return y+1
  end
  if y == 0 
     return ack(x-1, 1)
  end
  return ack(x-1, ack(x, y-1))
end;

println(ack(0, 0))
println(ack(3, 4))
println(ack(3, 5))

for m in 0:3
  for n in 0:6
      println ("ack (" + string (m) + ", " + string (n) + ") =", ack (m, n))
  end
end
