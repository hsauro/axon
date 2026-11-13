## Formatting values as text: numbers and arrays with chosen decimals,
## digits, separators and alignment, and the display settings that decide
## how println and the REPL show values. See the Language Reference,
## "The fmt module".

import fmtcore

# ------------------------------------------------------------ display settings

## Arrays up to rows by cols are displayed in full; larger ones show their
## first and last rows and columns. set_size() restores 10 by 8.
export function set_size(rows = nothing, cols = nothing)
  if typeof(rows) == "nothing" and typeof(cols) == "nothing"
    fmtcore.set_size()
  elseif typeof(rows) == "nothing" or typeof(cols) == "nothing"
    error("ArgumentError", "fmt.set_size takes both rows and columns, or neither")
  else
    fmtcore.set_size(rows, cols)
  end
end

## Displayed reals show exactly n decimals (1 to 15) instead of their
## significant digits. set_decimals() restores significant digits.
export function set_decimals(n = nothing)
  if typeof(n) == "nothing"
    fmtcore.set_decimals()
  else
    fmtcore.set_decimals(n)
  end
end

## Displayed reals use scientific notation when their magnitude is below
## small or at least large: fmt.set_sci(1e-6, 1e9). set_sci() restores 1e-4
## and 1e15. set_sci(0, 1.0 / 0.0) never uses it; set_sci(1, 1) always does.
export function set_sci(small = nothing, large = nothing)
  if typeof(small) == "nothing" and typeof(large) == "nothing"
    fmtcore.set_sci()
  elseif typeof(small) == "nothing" or typeof(large) == "nothing"
    error("ArgumentError", "fmt.set_sci takes both limits, or neither")
  else
    fmtcore.set_sci(small, large)
  end
end

## Whether displayed arrays start with their header line, such as
## "2x3 matrix{int}". set_header(false) leaves just the rows, starting at
## the left margin; set_header() turns the header back on.
export function set_header(on = true)
  fmtcore.set_header(on)
end

# ------------------------------------------------------------ text

## A number as text. Keywords: decimals (exactly that many digits after the
## point), digits (up to that many significant digits), sci (scientific
## notation, with decimals digits after the point, 6 by default) and width
## (padded on the left with spaces to at least that many characters). With
## none of them, an int is written in full and a real with up to 15
## significant digits, in scientific notation outside the limits of set_sci;
## the other display settings do not apply.
export function number(x; decimals = nothing, digits = nothing, sci = false, width = 0)
  t = typeof(x)
  if t == "bool" or t == "complex"
    s = string(x)
  elseif t != "int" and t != "real"
    error("TypeError", "fmt.number needs a number, got " + t)
  elseif sci
    d = 6
    if typeof(decimals) != "nothing" d = decimals end
    s = fmtcore.sci(x, d)
  elseif typeof(decimals) != "nothing"
    s = format(x, decimals)
  elseif typeof(digits) != "nothing"
    s = fmtcore.digits(x, digits)
  elseif t == "int"
    s = string(x)
  else
    s = fmtcore.digits(x, 15)
  end
  if length(s) < width
    s = repeat(" ", width - length(s)) + s
  end
  return s
end

## An array as text: one line per row, the elements separated by sep. A
## vector is a column, one element per line (write v' for a row). Keywords:
## decimals, digits (6 by default, as arrays are displayed) and sci, as for
## number; header (false: true puts a line such as "2x3 matrix{int}" first);
## sep (two spaces); align (true: each column right-aligned to its widest
## entry); rows and cols (lists of names: the row names down the left,
## padded to the longest, and the column names on a line above the entries,
## each column as wide as its widest entry or its name; unaligned, the names
## are fields like the entries, as for CSV). Every row and column
## is included, whatever set_size says. The text has no line break at the
## end.
export function matrix(A; decimals = nothing, digits = 6, sci = false, header = false,
                       sep = "  ", align = true, rows = nothing, cols = nothing)
  t = typeof(A)
  if t == "range" or t == "int" or t == "real" or t == "bool" or t == "complex"
    A = [A]
  elseif t != "vector" and t != "matrix"
    error("TypeError", "fmt.matrix needs a vector or matrix, got " + t)
  end
  if typeof(sep) != "string"
    error("TypeError", "fmt.matrix: sep must be a string, got " + typeof(sep))
  end
  [m, n] = size(A)
  is_vector = isa(A, "vector")
  # The text of each element, row by row, and each column's width.
  cells = {}
  widths = zeros(n)
  for i in 1:m
    row = {}
    for j in 1:n
      if is_vector
        x = A[i]
      else
        x = A[i, j]
      end
      s = number(x, decimals = decimals, digits = digits, sci = sci)
      row = append(row, s)
      widths[j] = max(widths[j], length(s))
    end
    cells = append(cells, row)
  end
  rnames = names_of(rows, m, "rows")
  cnames = names_of(cols, n, "cols")
  if typeof(cnames) != "nothing"
    for j in 1:n
      widths[j] = max(widths[j], length(cnames[j]))
    end
  end
  # The row names, as wide as the longest (when aligned).
  rw = 0
  if typeof(rnames) != "nothing"
    for name in rnames
      rw = max(rw, length(name))
    end
  end
  lines = {}
  if header
    if is_vector
      lines = append(lines, string(m) + "-vector{" + eltype(A) + "}")
    else
      lines = append(lines, string(m) + "\u{D7}" + string(n) + " matrix{" + eltype(A) + "}")
    end
  end
  if typeof(cnames) != "nothing"
    row = {}
    for j in 1:n
      if align
        row = append(row, repeat(" ", int(widths[j]) - length(cnames[j])) + cnames[j])
      else
        row = append(row, cnames[j])
      end
    end
    line = join(row, sep)
    if typeof(rnames) != "nothing" and align
      line = repeat(" ", rw) + sep + line
    elseif typeof(rnames) != "nothing"
      line = sep + line          # unaligned, as for CSV: an empty first field
    end
    lines = append(lines, line)
  end
  for i in 1:m
    row = cells[i]
    if align
      for j in 1:n
        row[j] = repeat(" ", int(widths[j]) - length(row[j])) + row[j]
      end
    end
    line = join(row, sep)
    if typeof(rnames) != "nothing"
      name = rnames[i]
      if align
        name = name + repeat(" ", rw - length(name))
      end
      line = name + sep + line
    end
    lines = append(lines, line)
  end
  return join(lines, "\n")
end

# Row or column names for matrix: nothing, or a list of count strings.
function names_of(v, count, what)
  if typeof(v) == "nothing"
    return nothing
  end
  if typeof(v) != "list"
    error("TypeError", "fmt.matrix: " + what + " must be a list of strings, got " + typeof(v))
  end
  if length(v) != count
    error("DimensionError", "fmt.matrix: " + what + " needs " + string(count) + " names, got " +
      string(length(v)))
  end
  for name in v
    if typeof(name) != "string"
      error("TypeError", "fmt.matrix: " + what + " must be a list of strings, got one " +
        typeof(name))
    end
  end
  return v
end
