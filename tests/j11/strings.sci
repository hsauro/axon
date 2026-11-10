# Strings in compiled code (J11). Each line: the compiled result, whether
# the interpreter gives the same, and whether the function compiled.

function both(f, x)
  __jit_mode("on")
  a = f(x)
  __jit_mode("off")
  b = f(x)
  __jit_mode("on")
  println(string(a), string(a) == string(b), __jit_compiled(f))
end

# Literals, + and string(): building labels in a loop.
function labels(n)
  out = {}
  for k in 1:n
    out = append(out, "x" + string(k) + "=" + string(k * 0.5))
  end
  return out
end
both(labels, 3)

# Comparisons: equality and order by character codes; a string is never
# equal to a number.
function compare(s)
  return {eq: s == "beta", ne: s != "beta", lt: s < "beta", ge: s >= "alpha",
          num: s == 1, numne: s != 1}
end
both(compare, "alpha")
both(compare, "beta")

# The string built-ins.
function tools(s)
  t = trim(s)
  parts = split(t, ",")
  return {upper: upper(t), lower: lower(t), n: length(t), parts: parts,
          joined: join(parts, "+"), has: contains(t, "b"), starts: startswith(t, "a"),
          ends: endswith(t, "c"), at: find(t, ","), rep: replace(t, ",", ";"),
          twice: repeat("ab", 2), l: ltrim("  x "), r: rtrim("  x ")}
end
both(tools, "  a,b,c  ")

# Numbers from text and to text.
function numbers(s)
  return int(s) + real(s + ".5") + length(format(3.14159, 2))
end
both(numbers, "41")

# typeof is known from the static types.
function kinds(x)
  r = {a: x}
  return {t: typeof(x), r: typeof(r), l: typeof({x}), v: typeof(zeros(2)),
          s: typeof("s"), isreal: typeof(x) == "real"}
end
both(kinds, 2.5)
both(kinds, 3)

# A string parameter choosing what to do, as plotting options do.
function apply(kind)
  if kind == "square"
    return 4.0
  elseif kind == "cube"
    return 8.0
  end
  return 0.0
end
both(apply, "cube")
both(apply, "other")

# string() of a bool, an int and a real, and length counting code points.
function shown(k)
  return string(k > 1) + "," + string(-k) + "," + string(k / 4) + "," + string(length("a😀b"))
end
both(shown, 2)

# Strings in records and lists, and messages with print.
function report(n)
  s = {name: "run", steps: n, notes: {"start"}}
  for k in 1:n
    s.notes = append(s.notes, "step " + string(k))
  end
  s.name = upper(s.name)
  println(s.name, length(s.notes), s.notes[end])
  return s
end
both(report, 2)

# Shapes the JIT rejects, with the interpreter's result.
function chars(s)
  return s[1]
end
both(chars, "abc")
