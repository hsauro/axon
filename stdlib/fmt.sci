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
## significant digits, whatever the display settings.
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
## entry). Every row and column is included, whatever set_size says. The
## text has no line break at the end.
export function matrix(A; decimals = nothing, digits = 6, sci = false, header = false,
                       sep = "  ", align = true)
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
  lines = {}
  if header
    if is_vector
      lines = append(lines, string(m) + "-vector{" + eltype(A) + "}")
    else
      lines = append(lines, string(m) + "\u{D7}" + string(n) + " matrix{" + eltype(A) + "}")
    end
  end
  for i in 1:m
    row = cells[i]
    if align
      for j in 1:n
        row[j] = repeat(" ", int(widths[j]) - length(row[j])) + row[j]
      end
    end
    lines = append(lines, join(row, sep))
  end
  return join(lines, "\n")
end
