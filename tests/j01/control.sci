function sign(x: real): int
  if x > 0
    s = 1
  elseif x < 0
    s = -1
  else
    s = 0
  end
  return s
end

function count_up(n: int): int
  i = 0
  total = 0
  while true
    i = i + 1
    if i > n or total >= 1000
      break
    end
    if i == 3
      continue
    end
    total = total + i
  end
  return total
end
