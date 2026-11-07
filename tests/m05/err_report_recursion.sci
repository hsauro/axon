#! error: RecursionError
function f(n) return f(n + 1) end
f(0)
