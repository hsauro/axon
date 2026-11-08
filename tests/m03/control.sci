x = 5
if x > 3
  println("big")
elseif x > 1
  println("medium")
else
  println("small")
end
if x < 0 println("neg") elseif x == 5 println("five") else println("other") end
i = 0
while i < 3
  i = i + 1
  println("while", i)
end
for k in 1:3
  println("for", k)
end
for k in 5:-2:1
  println("down", k)
end
for k in 3:1
  println("never")
end
n = 0
for t in 0:0.1:1
  n = n + 1
  last = t
end
println("count", n, "last", last)
for k in 1:10
  if k == 2 continue end
  if k == 4 break end
  println("k", k)
end
for q in 1:3
  for r in 1:3
    if r == 2 break end
    println(q, r)
  end
end
w = 0
while true
  w = w + 1
  if w >= 3 break end
end
println("w", w)
for k in 1.5:1:3.5
  println(k)
end
for k in 0:0
  println("one", k)
end
