x = 5
if x > 3
  print("big")
elseif x > 1
  print("medium")
else
  print("small")
end
if x < 0 print("neg") elseif x == 5 print("five") else print("other") end
i = 0
while i < 3
  i = i + 1
  print("while", i)
end
for k in 1:3
  print("for", k)
end
for k in 5:-2:1
  print("down", k)
end
for k in 3:1
  print("never")
end
n = 0
for t in 0:0.1:1
  n = n + 1
  last = t
end
print("count", n, "last", last)
for k in 1:10
  if k == 2 continue end
  if k == 4 break end
  print("k", k)
end
for q in 1:3
  for r in 1:3
    if r == 2 break end
    print(q, r)
  end
end
w = 0
while true
  w = w + 1
  if w >= 3 break end
end
print("w", w)
for k in 1.5:1:3.5
  print(k)
end
for k in 0:0
  print("one", k)
end
