## Geometry helpers.
export function area(r)
  return 3.0 * square(r)
end
function square(x) return x * x end
export record Point
  x: real; y: real
end
print("geometry loaded")
