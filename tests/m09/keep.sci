extern "axontest"
  function register_cb(cb: callback(x: int32): int32)
  function fire(x: int32): int32
end
f = keep(function(x) return x + 1 end)
register_cb(f)
println(fire(1), fire(41))
register_cb(f)
println(fire(0))
