# Strings in JIR (J11): constants, concat, comparisons, built-ins through
# the interpreter's routines, and typeof as a constant.

function label(k: int)
  return "x" + string(k)
end

function width(s: string)
  return length(s) + 1
end

function pick(kind: string): real
  if kind == "square"
    return 4.0
  end
  if typeof(kind) == "string" and kind < "m"
    return 1.0
  end
  return 0.0
end
