function pair(a: real, b: int)
  return [a; b]
end

function grid(a: real)
  return [a, 2.0; 3, a]
end

function ints(n: int)
  return [n; n + 1]
end

function flags(p: bool)
  return [p; p]
end
