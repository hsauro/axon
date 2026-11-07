# Catching an error raised in a called function
function risky(x)
  if x < 0
    error("negative input")
  end
  return sqrt(x)
end
try
  print(risky(4.0))
  print(risky(-1.0))
  print("not reached")
catch err
  print("caught:", err.message)
end
print("after")

# No error: the catch block is skipped
try
  y = 1
catch
  print("not printed")
end
print(y)

# Nested try: the inner one handles its own error
try
  try
    error("inner")
  catch e
    print("inner caught", e.message)
  end
  error("outer")
catch e
  print("outer caught", e.message)
end

# An error raised in a catch block goes to the enclosing try
try
  try
    error("first")
  catch e
    error("second, from the handler")
  end
catch e
  print(e.message)
end

# return, break and continue pass through try
function first_negative(a, b, c)
  for v in 1:3
    try
      if v == 1 and a < 0 return "a" end
      if v == 2 and b < 0 return "b" end
      if v == 3 and c < 0 return "c" end
    catch
    end
  end
  return "none"
end
print(first_negative(1, -1, -1), first_negative(1, 1, 1))
for i in 1:5
  try
    if i == 2 continue end
    if i == 4 break end
    print("loop", i)
  catch
  end
end

# Recovering inside a function and returning from the catch block
function safe_div(a, b)
  try
    return div(a, b)
  catch err
    return err.kind
  end
end
print(safe_div(7, 2), safe_div(7, 0))

# Variables assigned in the try block before the error keep their values
try
  progress = 1
  error("stop")
  progress = 2
catch
end
print(progress)
