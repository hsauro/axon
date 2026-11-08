#! error: RecursionError
__jit_mode("on")
function f(n: int): int return f(n + 1) end
f(0)
