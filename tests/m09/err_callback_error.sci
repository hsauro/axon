#! error: UserError
extern "axontest"
  function apply_cb(cb: callback(x: int32): int32, x: int32): int32
end
function bad(x)
  error("bad callback")
end
y = apply_cb(bad, 1)
println("not reached")
