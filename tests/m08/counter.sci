count = 0
export function next()
  global count
  count = count + 1
  return count
end
println("counter loaded")
early = later()
function later() return "later ok" end
println(early)
