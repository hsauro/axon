#! error: ArgumentError
__jit_mode("on")
function parse(s): int
  n = int(trim(s))
  return n + 1
end
function outer(text)
  return parse(text) * 2
end
outer(" 12x ")
