function no_annot(x)
  return x
end

function changes_type(n: int)
  x = 1
  x = 2.5
  return x
end

function maybe_unset(c: bool): int
  if c
    y = 1
  end
  return y
end

function reads_global(n: int): int
  return n + offset
end

function var_power(a: int, b: int)
  return a ^ b
end

function calls(x: real): real
  return mean(x)
end

function bad_cond(n: int)
  if n
    return 1
  end
  return 0
end

function mixed_returns(c: bool)
  if c
    return 1
  end
  return 2.0
end

function falls_off(c: bool)
  if c
    return 1
  end
end

function narrows(x: real): int
  return x
end

function loop_var_after(n: int): int
  for i in 1:n
  end
  return i
end

function nested(n: int)
  function g(x)
    return x
  end
  return n
end
