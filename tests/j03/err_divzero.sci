#! error: DomainError
__jit_mode("on")
function inner(a: int, b: int): int
  return div(a, b)
end
function outer(a: int): int
  return inner(a, 0) * 2
end
outer(5)
