import plot
import io

# The position of a text in an SVG file: the translate(x y) of the <text>
# element holding it, read with a small parser (tests only).
function find(s, t, start)
  n = length(t)
  for k in start:length(s) - n + 1
    if s[k:k + n - 1] == t return k end
  end
  return 0
end

function number_at(s, k)
  digits = "0123456789"
  v = 0.0
  scale = 0.0
  while k <= length(s)
    c = s[k]
    if c == "."
      scale = 1.0
    else
      d = find(digits, c, 1)
      if d == 0 return v, k end
      if scale > 0
        scale = scale / 10
        v = v + (d - 1) * scale
      else
        v = 10 * v + (d - 1)
      end
    end
    k = k + 1
  end
  return v, k
end

function text_position(path, label)
  s = io.read_file(path)
  at = find(s, label, 1)
  k = at
  while s[k:k + 9] != "translate("
    k = k - 1
  end
  [x, k] = number_at(s, k + 10)
  [y, k] = number_at(s, k + 1)
  return x, y
end

function legend_at(where)
  plot.figure()
  x = linspace(0.0, 10.0, 50)
  plot.line(x, x .* x, label = "rising")
  if typeof(where) != "nothing" plot.legend_position(where) end
  plot.save("_tmp_legend.svg")
  [lx, ly] = text_position("_tmp_legend.svg", "rising")
  [tx, ty] = text_position("_tmp_legend.svg", "\t10\n")
  io.delete_file("_tmp_legend.svg")
  return lx, ly, tx
end

# The default, best: the curve fills the top right, so the legend goes top
# left (the figure is 640 points wide and 480 high).
[x, y, tick] = legend_at(nothing)
println(plot.gcf().legend_position, x < 320, y < 240)
# Fixed corners.
[x, y, tick] = legend_at("top right")
println(x > 320, y < 240, x < tick)
[x, y, tick] = legend_at("bottom left")
println(x < 320, y > 240)
# Outside: right of the plot area, so right of its last tick label.
[x, y, tick] = legend_at("outside")
println(x > tick, y < 240)
