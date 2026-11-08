#! error: OverflowError
__jit_mode("on")
function grow(x)
  return x * x
end
println(grow(3), grow(2.0))
grow(4000000000)
