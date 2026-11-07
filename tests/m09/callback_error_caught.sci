extern "axontest"
  function apply_cb(cb: callback(x: int32): int32, x: int32): int32
end
try
  apply_cb(function(x) error("ValueBad", "inside") end, 1)
catch e
  print(e.kind, e.message)
end
print(apply_cb(function(x) return x end, 3))
