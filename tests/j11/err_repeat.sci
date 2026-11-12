#! error: ArgumentError
__jit_mode("on")
function rule(n)
  return "=" * n
end
rule(-2)
