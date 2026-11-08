#! error: DomainError
__jit_mode("on")
function a(x: real): int
  return b(x) + 1
end
function b(x): int
  return c(x)
end
function c(x: real): int
  return floor(x / 0.0 * 0.0)
end
a(1.0)
