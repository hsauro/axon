## Calling C: functions from the C runtime library.
## package.toml (next to this file) maps "libc" to the library on each platform.

extern "libc"
  function c_cos(x: float64): float64 name "cos"
  function strlen(s: cstring): csize
  function labs(n: clong): clong
end

println(c_cos(0.5), cos(0.5))
println(strlen("Axon"))
println(labs(-42))
