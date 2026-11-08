# ref ptr T: a C out-parameter (char **endptr). libc resolves through
# package.toml to a system library that is not next to the manifest.
extern "libc"
  function strtod(s: cstring, endp: ref ptr void): float64
end
p = nothing
x = strtod("2.5abc", p)
println(x, typeof(p))
q = nothing
println(strtod("", q), typeof(q))
