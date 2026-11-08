#! error: DimensionError
__jit_mode("on")
function add(v: vector{real}, w: vector{real}): vector{real}
  return v + w
end
println(add([1.0; 2.0], [3.0; 4.0]) == [4.0; 6.0])
add([1.0; 2.0], [1.0; 2.0; 3.0])
