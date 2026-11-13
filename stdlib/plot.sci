## Line, scatter, bar, histogram, surface, 3D bar and 3D curve and scatter plots, saved as PNG, SVG or PDF. Plotting calls
## add to the current figure; plot.save writes it. See the Language
## Reference, "The plot module".

import graphics

# The figure that plotting calls add to (nothing until the first call). In a
# figure divided by plot.subplot, it is the current cell, a record of the same
# shape sized to the cell.
current = nothing
# The grid of a figure divided by plot.subplot, or nothing: its size, overall
# title, rows and columns, the cells (nothing where never selected) and the
# number of the current cell, which is kept in current while it is selected.
layout = nothing
# Whether it has changed since plot.show or plot.save last drew it.
changed = false

# matplotlib's "tab10" colours, used in turn for series without a colour.
CYCLE = {"#1f77b4", "#ff7f0e", "#2ca02c", "#d62728", "#9467bd",
         "#8c564b", "#e377c2", "#7f7f7f", "#bcbd22", "#17becf"}

# viridis at eleven evenly spaced points, for surfaces.
VIRIDIS = [0.267, 0.005, 0.329;
           0.283, 0.141, 0.458;
           0.254, 0.265, 0.530;
           0.207, 0.372, 0.553;
           0.164, 0.471, 0.558;
           0.128, 0.567, 0.551;
           0.135, 0.659, 0.518;
           0.267, 0.749, 0.441;
           0.478, 0.821, 0.318;
           0.741, 0.873, 0.150;
           0.993, 0.906, 0.144]

# plasma, coolwarm and jet, as the IDE's 3D chart has them (evenly spaced).
PLASMA = [0.051, 0.031, 0.529;
          0.255, 0.016, 0.616;
          0.416, 0.000, 0.659;
          0.561, 0.051, 0.643;
          0.694, 0.165, 0.565;
          0.800, 0.278, 0.471;
          0.882, 0.392, 0.384;
          0.949, 0.518, 0.294;
          0.988, 0.651, 0.212;
          0.988, 0.808, 0.145;
          0.941, 0.976, 0.129]
# A diverging map: blue below the middle, red above.
COOLWARM = [0.231, 0.298, 0.753;
            0.384, 0.510, 0.918;
            0.553, 0.690, 0.996;
            0.725, 0.816, 0.976;
            0.867, 0.867, 0.867;
            0.961, 0.769, 0.675;
            0.957, 0.604, 0.482;
            0.871, 0.376, 0.302;
            0.706, 0.016, 0.149]
# The rainbow map, for familiarity; viridis or plasma read better.
JET = [0.000, 0.000, 0.498;
       0.000, 0.000, 1.000;
       0.000, 0.498, 1.000;
       0.000, 1.000, 1.000;
       0.498, 1.000, 0.498;
       1.000, 1.000, 0.000;
       1.000, 0.498, 0.000;
       1.000, 0.000, 0.000;
       0.498, 0.000, 0.000]

# The colour maps a surface may have.
COLORMAPS = {"viridis", "plasma", "coolwarm", "gray", "jet"}

TICK_SIZE = 10.0
LABEL_SIZE = 11.0
TITLE_SIZE = 13.0

function fail(kind, message)
  error(kind, message)
end

function real_vector(x, what)
  t = typeof(x)
  if t != "vector" and t != "matrix" and t != "range" and t != "real" and t != "int"
    fail("TypeError", what + " must be a real vector, got " + t)
  end
  if eltype([x]) == "complex"
    fail("TypeError", what + " must be real, not complex")
  end
  return reshape([x] + 0.0, length([x]))
end

function check_marker(marker, where)
  if typeof(marker) == "nothing" return end
  for m in {"circle", "square", "diamond", "triangle", "plus", "cross"}
    if marker == m return end
  end
  fail("ArgumentError", where + ": unknown marker \"" + string(marker) +
    "\" (circle, square, diamond, triangle, plus, cross)")
end

function new_figure(width, height, title)
  return {width: width + 0.0, height: height + 0.0, title: title, xlabel: nothing,
          ylabel: nothing, zlabel: nothing, xlim: nothing, ylim: nothing, grid: true,
          legend: true, series: {}, three_d: false, elev: 30.0, azim: -60.0,
          xcategories: nothing, xticks: nothing, legend_position: "best",
          title_size: nothing, xlabel_size: nothing, ylabel_size: nothing,
          zlabel_size: nothing}
end

# A figure record with the font-size fields, which records saved before they
# existed (and read back with io.read_json) lack: nothing, the default size.
function sized(fig)
  try
    s = fig.title_size
  catch err
    fig.title_size = nothing
    fig.xlabel_size = nothing
    fig.ylabel_size = nothing
    fig.zlabel_size = nothing
  end
  return fig
end

# A size that was set, or the default.
function size_or(v, default)
  if typeof(v) == "nothing"
    return default
  end
  return v
end

# A font size for a title or label: nothing (the default) or a positive number.
function font_size(size, what)
  if typeof(size) == "nothing"
    return nothing
  end
  if typeof(size) != "int" and typeof(size) != "real"
    fail("TypeError", what + ": size must be a number, got " + typeof(size))
  end
  if not (size > 0)
    fail("ArgumentError", what + ": size must be positive")
  end
  return size + 0.0
end

# Every plotting call goes through here (or plot.figure), so the figure is
# marked as changed.
function figure_now()
  global current
  global changed
  if typeof(current) == "nothing"
    current = new_figure(640, 480, nothing)
  end
  changed = true
  return current
end

# A figure with something in it that has changed since it was last shown or
# saved is shown when the program ends, and when plot.figure replaces it, so
# plot.show() can be left out.
function show_unshown()
  if changed and has_plots()
    show()
  end
end

# Whether the figure (any of its cells) has something plotted.
function has_plots()
  if typeof(current) == "nothing"
    return false
  end
  if length(current.series) > 0
    return true
  end
  if typeof(layout) != "nothing"
    for c in layout.cells
      if typeof(c) != "nothing"
        if length(c.series) > 0 return true end
      end
    end
  end
  return false
end
atexit(show_unshown)

function next_color(fig)
  return CYCLE[mod(length(fig.series), length(CYCLE)) + 1]
end

function add_series(s)
  global current
  figure_now()
  if s.three_d != current.three_d and length(current.series) > 0
    fail("ArgumentError", "a figure cannot mix 3D plots (surface, bar3, line3, scatter3) with 2D ones")
  end
  current.three_d = s.three_d
  current.series = append(current.series, s)
end

# ---------------------------------------------------------------- public API

## Starts a new current figure of the given size in points (1/72 inch). The
## figure it replaces is shown first, if it has changed since it was last
## shown or saved, so each figure of a script is shown.
export function figure(; width = 640, height = 480, title = nothing)
  global current
  global changed
  global layout
  for v in {width, height}
    if typeof(v) != "int" and typeof(v) != "real"
      fail("TypeError", "plot.figure: width and height must be numbers, got " + typeof(v))
    end
  end
  if not (width > 0 and height > 0)
    fail("ArgumentError", "plot.figure: width and height must be positive")
  end
  label_text(title, "plot.figure: the title")
  show_unshown()
  current = new_figure(width, height, title)
  layout = nothing
  changed = true
end

## Divides the figure into a grid of rows by cols cells and makes cell k the
## current one, so later plotting calls (lines, titles, limits, ...) go to
## it. Cells are numbered along each row, from the top left. Selecting a cell
## again goes back to what is plotted there. A title given to plot.figure
## goes above the whole grid.
export function subplot(rows, cols, k)
  global current
  global layout
  global changed
  for v in {rows, cols, k}
    if typeof(v) != "int"
      fail("TypeError", "plot.subplot: rows, cols and k must be ints, got " + typeof(v))
    end
  end
  if rows < 1 or cols < 1
    fail("ArgumentError", "plot.subplot: rows and cols must be at least 1")
  end
  if k < 1 or k > rows * cols
    fail("ArgumentError", "plot.subplot: cell " + string(k) + " is outside a " + string(rows) +
      " by " + string(cols) + " grid (1 to " + string(rows * cols) + ")")
  end
  figure_now()
  if typeof(layout) == "nothing"
    if length(current.series) > 0
      fail("ArgumentError", "plot.subplot: the figure already has plots outside a grid; " +
        "start a new one with plot.figure()")
    end
    cells = {}
    for j in 1:rows * cols cells = append(cells, nothing) end
    layout = {width: current.width, height: current.height, title: current.title,
              rows: rows, cols: cols, cells: cells, index: k}
  else
    if rows != layout.rows or cols != layout.cols
      fail("ArgumentError", "plot.subplot: this figure is a " + string(layout.rows) + " by " +
        string(layout.cols) + " grid; start a new figure for another grid")
    end
    layout.cells[layout.index] = current
  end
  layout.index = k
  if typeof(layout.cells[k]) == "nothing"
    [x, y, w, h] = cell_box(layout, k)
    current = new_figure(w, h, nothing)
  else
    current = layout.cells[k]
  end
  changed = true
end

# The position and size of cell k of the grid g, in points.
function cell_box(g, k)
  top = 0.0
  if typeof(g.title) != "nothing" top = TITLE_SIZE * 2.2 end
  w = g.width / g.cols
  h = (g.height - top) / g.rows
  row = div(k - 1, g.cols)
  col = mod(k - 1, g.cols)
  return col * w, top + row * h, w, h
end

# The whole figure: the current figure, or the grid with the current cell in
# place.
function whole_figure()
  if typeof(layout) == "nothing"
    return current
  end
  g = layout
  g.cells[g.index] = current
  return g
end

# The scene of the whole current figure.
function figure_scene()
  return scene_of(whole_figure())
end

# Whether a figure record is a grid (it has cells).
function is_grid(fig)
  try
    c = fig.cells
    return true
  catch err
    return false
  end
end

# The scene of a figure record: a figure, or a grid whose cells are each
# drawn as a figure of their own size and moved into place.
function scene_of(fig)
  if not is_grid(fig)
    return render(fig)
  end
  g = fig
  items = {}
  if typeof(g.title) != "nothing"
    items = append(items, {kind: "text", x: g.width / 2, y: TITLE_SIZE * 1.1, text: g.title,
                           size: TITLE_SIZE, anchor: "middle", baseline: "middle",
                           bold: true, color: "black"})
  end
  for k in 1:length(g.cells)
    c = g.cells[k]
    if typeof(c) != "nothing"
      if length(c.series) > 0 or typeof(c.title) != "nothing"
        [x, y, w, h] = cell_box(g, k)
        sc = render(c)
        items = append(items, {kind: "group", dx: x, dy: y, clip: {x: 0.0, y: 0.0, w: w, h: h},
                               items: sc.items})
      end
    end
  end
  return {width: g.width, height: g.height, background: "white", items: items}
end

## Starts a new plot: the same as figure, under a name that says so. The
## figure it replaces is shown first if it has changed since it was last
## shown or saved; width and height are in points, title goes on top.
export function new(; width = 640, height = 480, title = nothing)
  figure(width = width, height = height, title = title)
end

## Removes everything plotted in the current figure (in a figure with
## subplots, the current cell) but keeps its frame: size, title, axis labels,
## limits, ticks, legend placement and 3D view. Nothing is shown, so
## clear, plot again and show draws the same frame with new data.
export function clear()
  global current
  figure_now()
  current.series = {}
  current.three_d = false
  current.xcategories = nothing
end

## Adds a line through the points (x[k], y[k]). Keywords: label, color,
## width (points), style ("-", "--", ":" or "-.") and marker (a marker shape
## drawn at each point, with marker_size).
export function line(x, y; label = nothing, color = nothing, width = 1.5, style = "-",
                     marker = nothing, marker_size = 5.0)
  xs = real_vector(x, "plot.line: x")
  ys = real_vector(y, "plot.line: y")
  if length(xs) != length(ys)
    fail("DimensionError", "plot.line: x has " + string(length(xs)) + " values but y has " +
      string(length(ys)))
  end
  if style != "-" and style != "--" and style != ":" and style != "-."
    fail("ArgumentError", "plot.line: style must be \"-\", \"--\", \":\" or \"-.\", got \"" +
      string(style) + "\"")
  end
  check_marker(marker, "plot.line")
  fig = figure_now()
  if typeof(color) == "nothing" color = next_color(fig) end
  add_series({type: "line", three_d: false, x: xs, y: ys, label: label, color: color,
              width: width + 0.0, style: style, marker: marker, marker_size: marker_size + 0.0})
end

## Adds a marker at each point (x[k], y[k]). Keywords: label, color, size
## (points) and marker ("circle", "square", "diamond", "triangle", "plus",
## "cross").
export function scatter(x, y; label = nothing, color = nothing, size = 6.0, marker = "circle")
  xs = real_vector(x, "plot.scatter: x")
  ys = real_vector(y, "plot.scatter: y")
  if length(xs) != length(ys)
    fail("DimensionError", "plot.scatter: x has " + string(length(xs)) + " values but y has " +
      string(length(ys)))
  end
  check_marker(marker, "plot.scatter")
  fig = figure_now()
  if typeof(color) == "nothing" color = next_color(fig) end
  add_series({type: "scatter", three_d: false, x: xs, y: ys, label: label, color: color,
              size: size + 0.0, marker: marker})
end

# The edges of the bins: bins equal bins over the finite data, or the given
# increasing edges.
function bin_edges(xs, bins, where)
  if typeof(bins) == "int"
    if bins < 1
      fail("ArgumentError", where + ": bins must be at least 1, got " + string(bins))
    end
    lo = 1.0 / 0.0
    hi = -1.0 / 0.0
    for v in xs
      if v == v and abs(v) < 1.0 / 0.0
        if v < lo lo = v end
        if v > hi hi = v end
      end
    end
    if lo > hi
      lo = 0.0
      hi = 1.0
    elseif lo == hi
      lo = lo - 0.5
      hi = hi + 0.5
    end
    e = linspace(lo, hi, bins + 1)
    e[bins + 1] = hi
    return e
  end
  if typeof(bins) != "vector" and typeof(bins) != "range" and typeof(bins) != "matrix"
    fail("TypeError", where + ": bins must be an int or a vector of edges, got " +
      typeof(bins))
  end
  e = real_vector(bins, where + ": bins")
  if length(e) < 2
    fail("ArgumentError", where + ": bins needs at least 2 edges")
  end
  for k in 1:length(e) - 1
    if not (e[k] < e[k + 1])
      fail("ArgumentError", where + ": bin edges must be strictly increasing")
    end
  end
  return e
end

# How many values fall in each bin [e[k], e[k + 1]); the last bin includes
# its right edge. Values outside the edges, and NaN, are not counted.
function bin_counts(xs: vector{real}, e: vector{real}): vector{real}
  nb = length(e) - 1
  counts = zeros(nb)
  top = e[nb + 1]
  for v in xs
    if v >= e[1] and v <= top
      lo = 1
      hi = nb + 1
      while hi - lo > 1
        mid = div(lo + hi, 2)
        if v >= e[mid]
          lo = mid
        else
          hi = mid
        end
      end
      counts[lo] = counts[lo] + 1.0
    end
  end
  return counts
end

# A series of bars from left[k] to right[k], rising (or falling) from 0 to
# heights[k]. x and y hold the ends and 0, so the axis ranges cover them.
function bar_series(left, right, heights, label, color)
  return {type: "bars", three_d: false, x: [left; right], y: [0.0; heights], left: left,
          right: right, heights: heights, label: label, color: color}
end

## Adds a bar chart: a bar of the given height at each position of x. x is a
## real vector of bar centres, or a list of strings naming categories, which
## places the bars at 1, 2, ... and labels the x axis with the names; bar(y)
## alone places the bars at 1, 2, ... Bars rise from 0, or fall for negative
## heights. Keywords: width (of each bar, in x units), label, color.
export function bar(x, heights = nothing; width = 0.8, label = nothing, color = nothing)
  global current
  categories = nothing
  if typeof(heights) == "nothing"
    if typeof(x) == "list"
      fail("TypeError", "plot.bar: give the heights after the category names")
    end
    heights = x
    x = 1:length(real_vector(heights, "plot.bar: heights"))
  end
  if typeof(x) == "list"
    for c in x
      if typeof(c) != "string"
        fail("TypeError", "plot.bar: categories must be strings, got " + typeof(c))
      end
    end
    categories = x
    xs = zeros(length(x))
    for k in 1:length(x) xs[k] = k end
  else
    xs = real_vector(x, "plot.bar: x")
  end
  hs = real_vector(heights, "plot.bar: heights")
  if length(xs) != length(hs)
    fail("DimensionError", "plot.bar: x has " + string(length(xs)) + " values but heights has " +
      string(length(hs)))
  end
  if typeof(width) != "int" and typeof(width) != "real"
    fail("TypeError", "plot.bar: width must be a number, got " + typeof(width))
  end
  if not (width > 0)
    fail("ArgumentError", "plot.bar: width must be positive")
  end
  fig = figure_now()
  if typeof(categories) != "nothing"
    if typeof(fig.xcategories) != "nothing" and not isequal(fig.xcategories, categories)
      fail("ArgumentError", "plot.bar: the figure already has different categories")
    end
  end
  if typeof(color) == "nothing" color = next_color(fig) end
  add_series(bar_series(xs - width / 2, xs + width / 2, hs, label, color))
  if typeof(categories) != "nothing"
    current.xcategories = categories
  end
end

function add_bars(x, bins, label, color, density, where)
  xs = real_vector(x, where + ": x")
  e = bin_edges(xs, bins, where)
  c = bin_counts(xs, e)
  heights = c
  if density
    total = sum(c)
    if total > 0
      heights = c ./ (total * (e[2:end] - e[1:end - 1]))
    end
  end
  fig = figure_now()
  if typeof(color) == "nothing" color = next_color(fig) end
  add_series(bar_series(e[1:end - 1], e[2:end], heights, label, color))
  return {counts: int(c), edges: e, heights: heights}
end

## Adds a histogram of the values x: bars whose heights are the number of
## values in each bin. bins is a number of equal bins spanning the data, or a
## vector of increasing bin edges; each bin includes its left edge, and the
## last also its right. Returns {counts, edges, heights}. Keywords: label,
## color.
export function hist(x; bins = 10, label = nothing, color = nothing)
  return add_bars(x, bins, label, color, false, "plot.hist")
end

## Like hist, but the heights are scaled so the bars' total area is 1, for
## comparison with a probability density.
export function hist_density(x; bins = 10, label = nothing, color = nothing)
  return add_bars(x, bins, label, color, true, "plot.hist_density")
end

## Adds the surface z = Z[i, j] over the grid (x[j], y[i]), coloured by height.
## Keywords: label, colormap ("viridis", "plasma", "coolwarm", "gray" or
## "jet"), color_by (a matrix the shape of Z to colour by instead of the
## height, such as log10(1 + Z) for a function with a few large values),
## clim ([lo, hi]: the values the two ends of the colour map stand for,
## instead of the smallest and largest), edges (draw the mesh), elev and azim
## (viewing angles in degrees).
export function surface(x, y, Z; label = nothing, colormap = "viridis", color_by = nothing,
                        clim = nothing, edges = true, elev = 30.0, azim = -60.0)
  global current
  xs = real_vector(x, "plot.surface: x")
  ys = real_vector(y, "plot.surface: y")
  if typeof(Z) != "matrix"
    fail("TypeError", "plot.surface: Z must be a real matrix, got " + typeof(Z))
  end
  [m, n] = size(Z)
  if m != length(ys) or n != length(xs)
    fail("DimensionError", "plot.surface: Z is " + string(m) + "×" + string(n) +
      " but needs length(y) × length(x) = " + string(length(ys)) + "×" + string(length(xs)))
  end
  if m < 2 or n < 2
    fail("DimensionError", "plot.surface: the grid needs at least 2 points each way")
  end
  if typeof(colormap) != "string" or not contains_name(COLORMAPS, colormap)
    fail("ArgumentError", "plot.surface: colormap must be \"viridis\", \"plasma\", " +
      "\"coolwarm\", \"gray\" or \"jet\"")
  end
  c = nothing
  if typeof(color_by) != "nothing"
    if typeof(color_by) != "matrix"
      fail("TypeError", "plot.surface: color_by must be a real matrix, got " + typeof(color_by))
    end
    [cm, cn] = size(color_by)
    if cm != m or cn != n
      fail("DimensionError", "plot.surface: color_by is " + string(cm) + "×" + string(cn) +
        " but Z is " + string(m) + "×" + string(n))
    end
    c = reshape([color_by] + 0.0, m, n)
  end
  climits = color_limits(clim, "plot.surface")
  add_series({type: "surface", three_d: true, x: xs, y: ys, z: reshape([Z] + 0.0, m, n),
              label: label, colormap: colormap, c: c, clim: climits, edges: edges})
  current.elev = elev + 0.0
  current.azim = azim + 0.0
end

## Adds a 3D bar chart: a bar standing at (x[j], y[i]) for each entry of Z,
## rising from 0 to Z[i, j], or going down for a negative value (NaN leaves
## the place empty). bar3(Z) alone places the bars at 1, 2, ... both ways; a
## vector Z is one column of bars along y. x or y may instead be a list of
## names, such as reactions or species: the bars then stand at 1, 2, ... on
## that axis, which is labelled with the names. The bars are coloured by
## height. Keywords: width (of each bar, as a fraction of the grid spacing,
## at most 1), colormap ("viridis", "plasma", "coolwarm", "gray" or "jet"),
## color_by (a matrix the shape of Z to colour by instead of the height),
## clim ([lo, hi]: the values the two ends of the colour map stand for, such
## as [-1, 1] to put the middle of "coolwarm" at 0), color (one colour for
## every bar instead of the colour map), label, edges (outline the bars),
## elev and azim (viewing angles in degrees).
export function bar3(x, y = nothing, Z = nothing; width = 0.8, colormap = "viridis",
                     color_by = nothing, clim = nothing, color = nothing, label = nothing,
                     edges = true, elev = 30.0, azim = -60.0)
  global current
  if typeof(y) == "nothing" and typeof(Z) == "nothing"
    Z = x
  elseif typeof(y) == "nothing" or typeof(Z) == "nothing"
    fail("TypeError", "plot.bar3: give x, y and Z, or Z alone")
  end
  t = typeof(Z)
  if t == "vector" or t == "range"
    Z = reshape([Z], length(Z), 1)
  elseif t != "matrix"
    fail("TypeError", "plot.bar3: Z must be a real matrix, got " + t)
  end
  if eltype(Z) == "complex"
    fail("TypeError", "plot.bar3: Z must be real, not complex")
  end
  [m, n] = size(Z)
  xnames = nothing
  ynames = nothing
  if typeof(y) == "nothing"
    xs = real_vector(1:n, "plot.bar3: x")
    ys = real_vector(1:m, "plot.bar3: y")
  else
    if typeof(x) == "list"
      xnames = category_names(x, "plot.bar3: x")
      x = 1:length(x)
    end
    if typeof(y) == "list"
      ynames = category_names(y, "plot.bar3: y")
      y = 1:length(y)
    end
    xs = real_vector(x, "plot.bar3: x")
    ys = real_vector(y, "plot.bar3: y")
    if m != length(ys) or n != length(xs)
      fail("DimensionError", "plot.bar3: Z is " + string(m) + "×" + string(n) +
        " but needs length(y) × length(x) = " + string(length(ys)) + "×" + string(length(xs)))
    end
  end
  if m < 1 or n < 1
    fail("DimensionError", "plot.bar3: Z is empty")
  end
  if typeof(width) != "int" and typeof(width) != "real"
    fail("TypeError", "plot.bar3: width must be a number, got " + typeof(width))
  end
  if not (width > 0 and width <= 1)
    fail("ArgumentError", "plot.bar3: width must be above 0 and at most 1")
  end
  if typeof(colormap) != "string" or not contains_name(COLORMAPS, colormap)
    fail("ArgumentError", "plot.bar3: colormap must be \"viridis\", \"plasma\", " +
      "\"coolwarm\", \"gray\" or \"jet\"")
  end
  c = nothing
  if typeof(color_by) != "nothing"
    if typeof(color_by) == "vector" and n == 1
      color_by = reshape([color_by], length(color_by), 1)
    end
    if typeof(color_by) != "matrix"
      fail("TypeError", "plot.bar3: color_by must be a real matrix, got " + typeof(color_by))
    end
    [cm, cn] = size(color_by)
    if cm != m or cn != n
      fail("DimensionError", "plot.bar3: color_by is " + string(cm) + "×" + string(cn) +
        " but Z is " + string(m) + "×" + string(n))
    end
    c = reshape([color_by] + 0.0, m, n)
  end
  climits = color_limits(clim, "plot.bar3")
  add_series({type: "bar3", three_d: true, x: xs, y: ys, z: reshape([Z] + 0.0, m, n),
              label: label, colormap: colormap, c: c, clim: climits, color: color,
              width: width + 0.0, edges: edges, xnames: xnames, ynames: ynames})
  current.elev = elev + 0.0
  current.azim = azim + 0.0
end

# The names of a list of categories, checked to be strings.
function category_names(v, what)
  for c in v
    if typeof(c) != "string"
      fail("TypeError", what + ": categories must be strings, got " + typeof(c))
    end
  end
  return v
end

# clim checked: nothing, or [lo, hi] as a real vector with lo < hi.
function color_limits(clim, where)
  if typeof(clim) == "nothing"
    return nothing
  end
  c = real_vector(clim, where + ": clim")
  if length(c) != 2 or not (c[1] < c[2]) or abs(c[1]) == 1.0 / 0.0 or abs(c[2]) == 1.0 / 0.0
    fail("ArgumentError", where + ": clim must be [lo, hi] with lo < hi, both finite")
  end
  return c
end

# The distance between neighbouring bar centres: the smallest gap between
# distinct values of v, or 1 when there is none (one row or column).
function bar_spacing(v)
  s = sort(v)
  d = 0.0
  for k in 2:length(s)
    g = s[k] - s[k - 1]
    if g > 0 and (d == 0 or g < d)
      d = g
    end
  end
  if d == 0
    return 1.0
  end
  return d
end

## Adds a curve through the points (x[k], y[k], z[k]) in 3D, such as a
## trajectory. A NaN in any coordinate leaves a gap. Keywords: label, color,
## width (points), and marker (a marker shape at each point, with
## marker_size).
export function line3(x, y, z; label = nothing, color = nothing, width = 1.5, marker = nothing,
                      marker_size = 5.0)
  [xs, ys, zs] = xyz(x, y, z, "plot.line3")
  check_marker(marker, "plot.line3")
  fig = figure_now()
  if typeof(color) == "nothing" color = next_color(fig) end
  add_series({type: "line3", three_d: true, x: xs, y: ys, z: zs, label: label, color: color,
              width: width + 0.0, marker: marker, marker_size: marker_size + 0.0})
end

## Adds a marker at each point (x[k], y[k], z[k]) in 3D. Keywords: label,
## color, size (points) and marker ("circle", "square", "diamond",
## "triangle", "plus", "cross").
export function scatter3(x, y, z; label = nothing, color = nothing, size = 6.0,
                         marker = "circle")
  [xs, ys, zs] = xyz(x, y, z, "plot.scatter3")
  check_marker(marker, "plot.scatter3")
  fig = figure_now()
  if typeof(color) == "nothing" color = next_color(fig) end
  add_series({type: "scatter3", three_d: true, x: xs, y: ys, z: zs, label: label, color: color,
              size: size + 0.0, marker: marker})
end

## Sets the viewing direction of a 3D figure: azimuth and elevation in
## degrees (as MATLAB's view; the default is azim = -60, elev = 30).
export function view(azim, elev)
  global current
  figure_now()
  current.azim = azim + 0.0
  current.elev = elev + 0.0
end

# Three real vectors of one length, for line3 and scatter3.
function xyz(x, y, z, where)
  xs = real_vector(x, where + ": x")
  ys = real_vector(y, where + ": y")
  zs = real_vector(z, where + ": z")
  if length(xs) != length(ys) or length(xs) != length(zs)
    fail("DimensionError", where + ": x, y and z have " + string(length(xs)) + ", " +
      string(length(ys)) + " and " + string(length(zs)) + " values")
  end
  return xs, ys, zs
end

# A title or axis label: a string, or nothing to remove it.
function label_text(text, what)
  t = typeof(text)
  if t != "string" and t != "nothing"
    fail("TypeError", what + " must be a string, got " + t)
  end
  return text
end

## Sets the title of the current figure; nothing removes it. size is the
## font size in points (13 by default, bold).
export function title(text; size = nothing)
  global current
  label_text(text, "plot.title: the title")
  size = font_size(size, "plot.title")
  figure_now()
  current = sized(current)
  current.title = text
  current.title_size = size
end

## Sets the x-axis label; nothing removes it. size is the font size in
## points (11 by default; 10 on a 3D figure).
export function xlabel(text; size = nothing)
  global current
  label_text(text, "plot.xlabel: the label")
  size = font_size(size, "plot.xlabel")
  figure_now()
  current = sized(current)
  current.xlabel = text
  current.xlabel_size = size
end

## Sets the y-axis label; nothing removes it. size as for xlabel.
export function ylabel(text; size = nothing)
  global current
  label_text(text, "plot.ylabel: the label")
  size = font_size(size, "plot.ylabel")
  figure_now()
  current = sized(current)
  current.ylabel = text
  current.ylabel_size = size
end

## Sets the z-axis label (surfaces); nothing removes it. size as for xlabel.
export function zlabel(text; size = nothing)
  global current
  label_text(text, "plot.zlabel: the label")
  size = font_size(size, "plot.zlabel")
  figure_now()
  current = sized(current)
  current.zlabel = text
  current.zlabel_size = size
end

## Puts the x-axis ticks at the given positions, labelled with the given
## strings, in place of round numbers (and of bar categories).
export function xticks(positions, labels)
  global current
  ps = real_vector(positions, "plot.xticks: positions")
  if typeof(labels) != "list"
    fail("TypeError", "plot.xticks: labels must be a list of strings, got " + typeof(labels))
  end
  for t in labels
    if typeof(t) != "string"
      fail("TypeError", "plot.xticks: labels must be strings, got " + typeof(t))
    end
  end
  if length(ps) != length(labels)
    fail("DimensionError", "plot.xticks: " + string(length(ps)) + " positions but " +
      string(length(labels)) + " labels")
  end
  figure_now()
  current.xticks = {positions: ps, labels: labels}
end

## Fixes the x-axis range to [lo, hi].
export function xlim(lo, hi)
  global current
  if not (hi > lo) fail("ArgumentError", "plot.xlim needs lo < hi") end
  figure_now()
  current.xlim = [lo + 0.0, hi + 0.0]
end

## Fixes the y-axis range to [lo, hi].
export function ylim(lo, hi)
  global current
  if not (hi > lo) fail("ArgumentError", "plot.ylim needs lo < hi") end
  figure_now()
  current.ylim = [lo + 0.0, hi + 0.0]
end

## Turns the grid lines on or off.
export function grid(on)
  global current
  figure_now()
  current.grid = on
end

## Where the legend goes: "best" (the default: the corner of the plot area
## that covers the least data), "top right", "top left", "bottom right",
## "bottom left", or "outside" (to the right of the plot area, which is
## narrowed to make room).
export function legend_position(where)
  global current
  if typeof(where) != "string"
    fail("TypeError", "plot.legend_position needs a string, got " + typeof(where))
  end
  ok = false
  for w in {"best", "top right", "top left", "bottom right", "bottom left", "outside"}
    if where == w ok = true end
  end
  if not ok
    fail("ArgumentError", "plot.legend_position: unknown position \"" + where +
      "\" (best, top right, top left, bottom right, bottom left, outside)")
  end
  figure_now()
  current.legend_position = where
end

## Turns the legend (of labelled series) on or off.
export function legend(on)
  global current
  figure_now()
  current.legend = on
end

## Shows the current figure: in the IDE's plot pane when run from the IDE,
## otherwise in the system's image viewer. scale sets the pixels per point.
export function show(; scale = 2.0)
  global changed
  if typeof(current) == "nothing"
    fail("ArgumentError", "plot.show: there is no figure; plot something first")
  end
  scene = figure_scene()
  scene.scale = scale + 0.0
  if typeof(layout) != "nothing"
    # A grid: the IDE draws each cell in an interactive chart of its own.
    graphics.show(scene, whole_figure())
  elseif interactive(current)
    # The IDE also gets the figure itself, which it draws in its interactive
    # chart (zoom, pan, editing) instead of the image.
    graphics.show(scene, current)
  else
    graphics.show(scene)
  end
  changed = false
end

# Whether the IDE's interactive charts can draw the figure: every 2-D figure
# goes to the 2-D chart and every 3-D figure (surfaces, bar3, line3, scatter3) to
# the 3-D chart. A figure with subplots goes to a grid of such charts.
function interactive(fig)
  return length(fig.series) > 0
end

## The current figure, as a record (nothing before the first plotting call).
## For a figure divided by plot.subplot, a record of the grid: width, height,
## title, rows, cols, cells (each a figure record, or nothing) and index, the
## number of the current cell.
export function gcf()
  return whole_figure()
end

## Writes the current figure to a .png, .svg or .pdf file. scale sets the
## pixels per point of a PNG. figure, a figure record such as plot.gcf()
## returns (or one read back with io.read_json from a figure written as
## JSON), is saved instead of the current figure when given.
export function save(path; scale = 2.0, figure = nothing)
  global changed
  if typeof(figure) != "nothing"
    if typeof(figure) != "record"
      fail("TypeError", "plot.save: figure must be a figure record, got " + typeof(figure))
    end
    scene = scene_of(figure)
    scene.scale = scale + 0.0
    graphics.save(scene, path)
    return
  end
  if typeof(current) == "nothing"
    fail("ArgumentError", "plot.save: there is no figure; plot something first")
  end
  scene = figure_scene()
  scene.scale = scale + 0.0
  graphics.save(scene, path)
  changed = false
end

# ---------------------------------------------------------------- ticks

# About n "nice" tick values (1, 2 or 5 times a power of ten) covering [lo, hi].
function nice_ticks(lo, hi, n)
  span = hi - lo
  raw = span / n
  p = 10.0 ^ floor(log(raw) / log(10.0))
  m = raw / p
  if m < 1.5
    step = p
  elseif m < 3.5
    step = 2 * p
  elseif m < 7.5
    step = 5 * p
  else
    step = 10 * p
  end
  first = ceil(lo / step - 1e-9)
  last = floor(hi / step + 1e-9)
  ticks = zeros(last - first + 1)
  for k in first:last
    v = k * step
    if abs(v) < step * 1e-9 v = 0.0 end
    ticks[k - first + 1] = v
  end
  return ticks, step
end

function tick_label(v, step)
  if step >= 1 and abs(v) < 1e15
    return string(round(v))
  end
  # As many decimals as the step needs (format, so fmt.set_decimals does
  # not change the labels).
  d = -floor(log(step) / log(10.0) + 1e-9)
  if d <= 0
    # Huge values (1e15 and up): the exponent form of the display.
    scale = 10.0 ^ d
    return string(round(v * scale) / scale)
  end
  return format(v, d)
end

# The data range of the 2-D series, padded by 5%, or the limits set.
function data_range(values, lim)
  if typeof(lim) != "nothing"
    return lim[1], lim[2]
  end
  lo = 1.0 / 0.0
  hi = -1.0 / 0.0
  for v in values
    if v == v and abs(v) < 1.0 / 0.0
      if v < lo lo = v end
      if v > hi hi = v end
    end
  end
  if lo > hi return 0.0, 1.0 end
  if lo == hi
    d = max(abs(lo) * 0.1, 0.5)
    return lo - d, hi + d
  end
  pad = 0.05 * (hi - lo)
  return lo - pad, hi + pad
end

function has_bars(series)
  for s in series
    if s.type == "bars" return true end
  end
  return false
end

# Whether the figure has bars and every series is bars centred on whole
# numbers.
function bars_on_integers(series)
  if length(series) == 0 return false end
  for s in series
    if s.type != "bars" return false end
    c = (s.left + s.right) / 2
    for v in c
      if abs(v - round(v)) > 1e-9 return false end
    end
  end
  return true
end

function all_x(series)
  v = zeros(0)
  for s in series
    v = [v; s.x]
  end
  return v
end

function all_y(series)
  v = zeros(0)
  for s in series
    v = [v; s.y]
  end
  return v
end

# ---------------------------------------------------------------- rendering

function dash_for(style, width)
  if style == "--" return [6.0 * width, 3.0 * width] / 1.5 end
  if style == ":" return [1.0 * width, 2.0 * width] end
  if style == "-." return [6.0 * width, 2.5 * width, 1.0 * width, 2.5 * width] / 1.5 end
  return nothing
end

function text_item(x, y, s, size, anchor, baseline)
  return {kind: "text", x: x + 0.0, y: y + 0.0, text: s, size: size, anchor: anchor,
          baseline: baseline, color: "black"}
end

function render(fig)
  fig = sized(fig)
  if fig.three_d
    return render_3d(fig)
  end
  return render_2d(fig)
end

function render_2d(fig)
  W = fig.width
  H = fig.height
  items = {}
  [x0, x1] = data_range(all_x(fig.series), fig.xlim)
  [y0, y1] = data_range(all_y(fig.series), fig.ylim)
  # Bars stand on the x axis: no padding below a baseline at 0.
  if typeof(fig.ylim) == "nothing" and has_bars(fig.series)
    if min(all_y(fig.series)) >= 0 y0 = 0.0 end
    if max(all_y(fig.series)) <= 0 y1 = 0.0 end
  end
  # Fewer ticks in a small figure (a subplot cell); 7 and 6 from about 500 by 420.
  nx = min(7, max(3, round(W / 70)))
  ny = min(6, max(3, round(H / 70)))
  [yt, ystep] = nice_ticks(y0, y1, ny)
  # Ticks set by xticks (those inside the range), category names at 1, 2, ...,
  # or round numbers.
  if typeof(fig.xticks) != "nothing"
    xt = zeros(0)
    xlabels = {}
    for k in 1:length(fig.xticks.positions)
      v = fig.xticks.positions[k]
      if v >= x0 and v <= x1
        xt = [xt; v]
        xlabels = append(xlabels, fig.xticks.labels[k])
      end
    end
  elseif typeof(fig.xcategories) != "nothing"
    xt = zeros(length(fig.xcategories))
    for k in 1:length(xt) xt[k] = k end
    xlabels = fig.xcategories
  else
    [xt, xstep] = nice_ticks(x0, x1, nx)
    # Bars that all stand on whole numbers (plot.bar(y)) get whole-number ticks.
    if xstep < 1 and bars_on_integers(fig.series)
      xt = zeros(0)
      for v in ceil(x0):floor(x1) xt = [xt; v + 0.0] end
      xstep = 1.0
    end
    xlabels = {}
    for v in xt xlabels = append(xlabels, tick_label(v, xstep)) end
  end
  ylabels = {}
  wmax = 0.0
  for v in yt
    s = tick_label(v, ystep)
    ylabels = append(ylabels, s)
    wmax = max(wmax, graphics.text_width(s, TICK_SIZE))
  end

  # Margins around the plot area, from the title's and labels' sizes.
  ts = size_or(fig.title_size, TITLE_SIZE)
  xs = size_or(fig.xlabel_size, LABEL_SIZE)
  ys = size_or(fig.ylabel_size, LABEL_SIZE)
  top = 12.0
  if typeof(fig.title) != "nothing" top = ts * 2.2 end
  left = 12.0 + wmax + 8.0
  if typeof(fig.ylabel) != "nothing" left = left + ys * 1.8 end
  bottom = 12.0 + TICK_SIZE * 1.6
  if typeof(fig.xlabel) != "nothing" bottom = bottom + xs * 1.8 end
  right = 20.0
  [labelled, lw, lh] = legend_size(fig.series)
  show_legend = fig.legend and length(labelled) > 0
  if show_legend and fig.legend_position == "outside"
    right = right + lw + 12.0
  end
  px0 = left
  px1 = W - right
  py0 = top
  py1 = H - bottom
  sx = (px1 - px0) / (x1 - x0)
  sy = (py1 - py0) / (y1 - y0)
  X = function(x) return px0 + (x - x0) * sx end
  Y = function(y) return py1 - (y - y0) * sy end

  items = append(items, {kind: "rect", x: px0, y: py0, w: px1 - px0, h: py1 - py0,
                         fill: "white"})
  # Grid lines and ticks.
  for k in 1:length(xt)
    px = X(xt[k])
    if fig.grid
      items = append(items, {kind: "line", x: [px, px], y: [py0, py1], color: "#e0e0e0",
                             width: 0.8})
    end
    items = append(items, {kind: "line", x: [px, px], y: [py1, py1 + 4.0], color: "black",
                           width: 0.8})
    items = append(items, text_item(px, py1 + 6.0, xlabels[k], TICK_SIZE, "middle", "top"))
  end
  for k in 1:length(yt)
    py = Y(yt[k])
    if fig.grid
      items = append(items, {kind: "line", x: [px0, px1], y: [py, py], color: "#e0e0e0",
                             width: 0.8})
    end
    items = append(items, {kind: "line", x: [px0 - 4.0, px0], y: [py, py], color: "black",
                           width: 0.8})
    items = append(items, text_item(px0 - 6.0, py, ylabels[k], TICK_SIZE, "end", "middle"))
  end

  # The series, clipped to the plot area.
  drawn = {}
  for s in fig.series
    px = px0 + (s.x - x0) * sx
    py = py1 - (s.y - y0) * sy
    if s.type == "bars"
      base = py1 - (0.0 - y0) * sy
      for k in 1:length(s.heights)
        ytop = py1 - (s.heights[k] - y0) * sy
        xl = px0 + (s.left[k] - x0) * sx
        xr = px0 + (s.right[k] - x0) * sx
        drawn = append(drawn, {kind: "rect", x: xl, y: min(ytop, base),
                               w: xr - xl, h: abs(base - ytop), fill: s.color,
                               color: "white", width: 0.6})
      end
    elseif s.type == "line"
      drawn = append(drawn, {kind: "line", x: px, y: py, color: s.color, width: s.width,
                             dash: dash_for(s.style, s.width)})
      if typeof(s.marker) != "nothing"
        drawn = append(drawn, {kind: "markers", x: px, y: py, shape: s.marker,
                               size: s.marker_size, color: s.color})
      end
    else
      drawn = append(drawn, {kind: "markers", x: px, y: py, shape: s.marker, size: s.size,
                             color: s.color})
    end
  end
  items = append(items, {kind: "group", clip: {x: px0, y: py0, w: px1 - px0, h: py1 - py0},
                         items: drawn})
  items = append(items, {kind: "rect", x: px0, y: py0, w: px1 - px0, h: py1 - py0,
                         color: "black", width: 0.8})

  # Labels and title.
  if typeof(fig.xlabel) != "nothing"
    items = append(items, text_item((px0 + px1) / 2, H - 10.0, fig.xlabel, xs,
                                    "middle", "bottom"))
  end
  if typeof(fig.ylabel) != "nothing"
    items = append(items, {kind: "text", x: 10.0 + ys, y: (py0 + py1) / 2,
                           text: fig.ylabel, size: ys, anchor: "middle",
                           baseline: "alphabetic", angle: 90.0, color: "black"})
  end
  if typeof(fig.title) != "nothing"
    items = append(items, {kind: "text", x: (px0 + px1) / 2, y: top / 2, text: fig.title,
                           size: ts, anchor: "middle", baseline: "middle",
                           bold: true, color: "black"})
  end
  if show_legend
    view = {px0: px0, px1: px1, py0: py0, py1: py1, x0: x0, y0: y0, sx: sx, sy: sy}
    [bx, by] = legend_place(fig.legend_position, fig.series, lw, lh, view)
    items = append(items, legend_items(labelled, bx, by, lw, lh))
  end
  return {width: W, height: H, background: "white", items: items}
end

# The labelled series and the size of their legend box.
function legend_size(series)
  labelled = {}
  for s in series
    if typeof(s.label) != "nothing" labelled = append(labelled, s) end
  end
  wmax = 0.0
  for s in labelled
    wmax = max(wmax, graphics.text_width(s.label, TICK_SIZE))
  end
  return labelled, wmax + 40.0, TICK_SIZE * 1.6 * length(labelled) + 8.0
end

# The top-left corner of the legend box for a position; "best" tries the
# corners in turn and keeps the first that covers the least data.
function legend_place(where, series, bw, bh, v)
  if where == "outside"
    return v.px1 + 12.0, v.py0
  end
  corners = {"top right", "top left", "bottom left", "bottom right"}
  if where != "best"
    corners = {where}
  end
  best = 1.0 / 0.0
  rx = v.px1 - bw - 8.0
  ry = v.py0 + 8.0
  for c in corners
    bx = v.px1 - bw - 8.0
    if c == "top left" or c == "bottom left" bx = v.px0 + 8.0 end
    by = v.py0 + 8.0
    if c == "bottom left" or c == "bottom right" by = v.py1 - bh - 8.0 end
    if length(corners) == 1
      return bx, by
    end
    cost = legend_cost(series, bx, by, bx + bw, by + bh, v)
    if cost < best
      best = cost
      rx = bx
      ry = by
    end
  end
  return rx, ry
end

# How much data the box [x0, x1] x [y0, y1] (in points) would hide: points
# inside it, line segments crossing it, and the fraction of it under bars
# (a box covered by bars counts as 100 points).
function legend_cost(series, x0, y0, x1, y1, v)
  cost = 0.0
  for s in series
    if s.type == "bars"
      for k in 1:length(s.heights)
        bl = v.px0 + (s.left[k] - v.x0) * v.sx
        br = v.px0 + (s.right[k] - v.x0) * v.sx
        bt = v.py1 - (max(s.heights[k], 0.0) - v.y0) * v.sy
        bb = v.py1 - (min(s.heights[k], 0.0) - v.y0) * v.sy
        w = min(br, x1) - max(bl, x0)
        h = min(bb, y1) - max(bt, y0)
        if w > 0 and h > 0
          cost = cost + 100.0 * w * h / ((x1 - x0) * (y1 - y0))
        end
      end
    else
      px = v.px0 + (s.x - v.x0) * v.sx
      py = v.py1 - (s.y - v.y0) * v.sy
      cost = cost + sum((px >= x0) and (px <= x1) and (py >= y0) and (py <= y1))
      if s.type == "line"
        cost = cost + segments_crossing(px, py, x0, y0, x1, y1)
      end
    end
  end
  return cost
end

# The number of segments of the polyline (px, py) that cross the box.
function segments_crossing(px, py, x0, y0, x1, y1)
  n = 0
  for k in 1:length(px) - 1
    ax = px[k]
    ay = py[k]
    bx = px[k + 1]
    by = py[k + 1]
    # Both ends on one side of the box: no crossing.
    if not ((ax < x0 and bx < x0) or (ax > x1 and bx > x1) or
            (ay < y0 and by < y0) or (ay > y1 and by > y1))
      # Otherwise it crosses unless all four corners are on one side of it.
      c1 = (bx - ax) * (y0 - ay) - (by - ay) * (x0 - ax)
      c2 = (bx - ax) * (y0 - ay) - (by - ay) * (x1 - ax)
      c3 = (bx - ax) * (y1 - ay) - (by - ay) * (x0 - ax)
      c4 = (bx - ax) * (y1 - ay) - (by - ay) * (x1 - ax)
      if not ((c1 > 0 and c2 > 0 and c3 > 0 and c4 > 0) or
              (c1 < 0 and c2 < 0 and c3 < 0 and c4 < 0))
        n = n + 1
      end
    end
  end
  return n
end

# The legend box at (bx, by), bw by bh points, for the labelled series.
function legend_items(labelled, bx, by, bw, bh)
  rowh = TICK_SIZE * 1.6
  items = {{kind: "rect", x: bx, y: by, w: bw, h: bh, fill: "#ffffffe6", color: "#c0c0c0",
            width: 0.8}}
  for k in 1:length(labelled)
    s = labelled[k]
    cy = by + 4.0 + rowh * (k - 0.5)
    if s.type == "bars"
      items = append(items, {kind: "rect", x: bx + 9.0, y: cy - 5.0, w: 16.0, h: 10.0,
                             fill: s.color})
    elseif s.type == "surface"
      items = append(items, {kind: "rect", x: bx + 9.0, y: cy - 5.0, w: 16.0, h: 10.0,
                             fill: colormap_at(s.colormap, 0.5)})
    elseif s.type == "bar3"
      fill = s.color
      if typeof(fill) == "nothing" fill = colormap_at(s.colormap, 0.5) end
      items = append(items, {kind: "rect", x: bx + 9.0, y: cy - 5.0, w: 16.0, h: 10.0,
                             fill: fill})
    elseif s.type == "line3"
      items = append(items, {kind: "line", x: [bx + 6.0, bx + 28.0], y: [cy, cy],
                             color: s.color, width: s.width})
      if typeof(s.marker) != "nothing"
        items = append(items, {kind: "markers", x: [bx + 17.0], y: [cy], shape: s.marker,
                               size: s.marker_size, color: s.color})
      end
    elseif s.type == "line"
      items = append(items, {kind: "line", x: [bx + 6.0, bx + 28.0], y: [cy, cy],
                             color: s.color, width: s.width, dash: dash_for(s.style, s.width)})
      if typeof(s.marker) != "nothing"
        items = append(items, {kind: "markers", x: [bx + 17.0], y: [cy], shape: s.marker,
                               size: s.marker_size, color: s.color})
      end
    else
      items = append(items, {kind: "markers", x: [bx + 17.0], y: [cy], shape: s.marker,
                             size: s.size, color: s.color})
    end
    items = append(items, text_item(bx + 34.0, cy, s.label, TICK_SIZE, "start", "middle"))
  end
  return {kind: "group", items: items}
end

# ---------------------------------------------------------------- surfaces

function contains_name(names, name)
  for k in names
    if k == name
      return true
    end
  end
  return false
end

# The colour at u (0 to 1) of a colour map: between its two nearest anchors.
function colormap_at(name, u)
  u = min(max(u, 0.0), 1.0)
  if name == "gray"
    g = 0.15 + 0.8 * u
    return [g, g, g]
  end
  T = VIRIDIS
  if name == "plasma"
    T = PLASMA
  elseif name == "coolwarm"
    T = COOLWARM
  elseif name == "jet"
    T = JET
  end
  last = size(T, 1) - 1
  pos = u * last
  k = min(floor(pos), last - 1)
  f = pos - k
  return (1 - f) * T[k + 1, :] + f * T[k + 2, :]
end

# A surface's clim, or nothing for one saved before clim existed (a figure
# record read back with io.read_json).
function clim_of(s)
  try
    return s.clim
  catch err
    return nothing
  end
end

# The finite range of the values (lo > hi when there are none).
function finite_range(v, lo, hi)
  for t in v
    if t == t and abs(t) < 1.0 / 0.0
      if t < lo lo = t end
      if t > hi hi = t end
    end
  end
  return lo, hi
end

# A 3D figure as a picture (plot.save, and plot.show outside the IDE). Every
# series shares one box, scaled to the data of all of them; surfaces are
# drawn back to front, then bars, then curves and markers over them. (The
# IDE's 3D chart sorts everything together, so curves also pass behind
# surfaces and bars.)
function render_3d(fig)
  W = fig.width
  H = fig.height
  inf = 1.0 / 0.0
  xmin = inf
  xmax = -inf
  ymin = inf
  ymax = -inf
  zmin = inf
  zmax = -inf
  for s in fig.series
    if s.type == "bar3"
      # The whole bars: their widths about the centres, and 0, where they start.
      hx = s.width * bar_spacing(s.x) / 2
      hy = s.width * bar_spacing(s.y) / 2
      [xmin, xmax] = finite_range([s.x - hx; s.x + hx], xmin, xmax)
      [ymin, ymax] = finite_range([s.y - hy; s.y + hy], ymin, ymax)
      [zmin, zmax] = finite_range([0.0; reshape(s.z, length(s.z))], zmin, zmax)
    else
      [xmin, xmax] = finite_range(s.x, xmin, xmax)
      [ymin, ymax] = finite_range(s.y, ymin, ymax)
      [zmin, zmax] = finite_range(s.z, zmin, zmax)
    end
  end
  if xmin > xmax
    xmin = 0.0
    xmax = 1.0
  end
  if ymin > ymax
    ymin = 0.0
    ymax = 1.0
  end
  if zmin > zmax
    zmin = 0.0
    zmax = 1.0
  end
  if xmax == xmin xmax = xmin + 1 end
  if ymax == ymin ymax = ymin + 1 end
  if zmax == zmin zmax = zmin + 1 end

  # Orthographic view of the cube [-1, 1]^3 (z squashed a little).
  az = fig.azim * pi / 180
  el = fig.elev * pi / 180
  ca = cos(az)
  sa = sin(az)
  ce = cos(el)
  se = sin(el)
  ts = size_or(fig.title_size, TITLE_SIZE)
  top = 12.0
  if typeof(fig.title) != "nothing" top = ts * 2.2 end
  cx = W / 2
  cy = top + (H - top) / 2
  scale = min(W, H - top) * 0.3
  # Projection of a normalised point (u, v, w): screen x, screen y and depth
  # (larger is farther). The view is MATLAB's view(azim, elev), as in the
  # IDE's 3D chart: at azim 0 the viewer looks along +v with u to the right,
  # at azim 90 along -u with v to the right; heights are squashed to 0.8.
  proj = function(u, v, w)
    rx = ca * u + sa * v
    ry = -sa * u + ca * v
    wz = 0.8 * w
    return cx + scale * rx, cy - scale * (se * ry + ce * wz), ce * ry - se * wz
  end
  nx = function(x) return 2 * (x - xmin) / (xmax - xmin) - 1 end
  ny = function(y) return 2 * (y - ymin) / (ymax - ymin) - 1 end
  nz = function(z) return 2 * (z - zmin) / (zmax - zmin) - 1 end

  items = {}
  # The three back faces' edges, as a frame.
  corners = {[-1, -1], [1, -1], [1, 1], [-1, 1]}
  for c in corners
    [a1, b1, d1] = proj(c[1], c[2], -1)
    [a2, b2, d2] = proj(c[1], c[2], 1)
    items = append(items, {kind: "line", x: [a1, a2], y: [b1, b2], color: "#d0d0d0", width: 0.6})
  end
  for k in 1:4
    c = corners[k]
    e = corners[mod(k, 4) + 1]
    [a1, b1, d1] = proj(c[1], c[2], -1)
    [a2, b2, d2] = proj(e[1], e[2], -1)
    items = append(items, {kind: "line", x: [a1, a2], y: [b1, b2], color: "#909090", width: 0.8})
  end

  # Surfaces: faces back to front (the loops run away from the viewer first).
  [vx, vy, vd] = proj(1, 0, 0)
  [ux, uy, ud] = proj(0, 1, 0)
  [ox, oy, od] = proj(0, 0, 0)
  for s in fig.series
    if s.type == "surface"
      xs = s.x
      ys = s.y
      Z = s.z
      [m, n] = size(Z)
      # Colours from color_by when given, else from the heights.
      C = Z
      cmin = zmin
      cmax = zmax
      if typeof(s.c) != "nothing"
        C = s.c
        [cmin, cmax] = finite_range(C, 1.0 / 0.0, -1.0 / 0.0)
        if not (cmax > cmin)
          cmax = cmin + 1
        end
      end
      lims = clim_of(s)
      if typeof(lims) != "nothing"
        cmin = lims[1]
        cmax = lims[2]
      end
      irange = 1:m - 1
      jrange = 1:n - 1
      if ud - od > 0 irange = m - 1:-1:1 end
      if vd - od > 0 jrange = n - 1:-1:1 end
      for i in irange
        for j in jrange
          zc = (Z[i, j] + Z[i, j + 1] + Z[i + 1, j + 1] + Z[i + 1, j]) / 4
          cc = (C[i, j] + C[i, j + 1] + C[i + 1, j + 1] + C[i + 1, j]) / 4
          if zc == zc and cc == cc
            col = colormap_at(s.colormap, (cc - cmin) / (cmax - cmin))
            [p1x, p1y, q1] = proj(nx(xs[j]), ny(ys[i]), nz(Z[i, j]))
            [p2x, p2y, q2] = proj(nx(xs[j + 1]), ny(ys[i]), nz(Z[i, j + 1]))
            [p3x, p3y, q3] = proj(nx(xs[j + 1]), ny(ys[i + 1]), nz(Z[i + 1, j + 1]))
            [p4x, p4y, q4] = proj(nx(xs[j]), ny(ys[i + 1]), nz(Z[i + 1, j]))
            edge = "none"
            if s.edges edge = "#00000040" end
            items = append(items, {kind: "polygon", x: [p1x, p2x, p3x, p4x],
                                   y: [p1y, p2y, p3y, p4y], fill: col, color: edge, width: 0.4})
          end
        end
      end
    end
  end

  # Bars: whole bars, far to near by where they stand (they never overlap
  # there, so that hides them correctly), each drawn as the faces that look
  # towards the viewer, the sides darkened a little so the bars read as
  # solid. In (u, v, w), towards the viewer is (ce sa, -ce ca, se).
  for s in fig.series
    if s.type == "bar3"
      [m, n] = size(s.z)
      hx = s.width * bar_spacing(s.x) / 2
      hy = s.width * bar_spacing(s.y) / 2
      C = s.z
      if typeof(s.c) != "nothing" C = s.c end
      [cmin, cmax] = finite_range(C, inf, -inf)
      if not (cmax > cmin) cmax = cmin + 1 end
      if typeof(s.clim) != "nothing"
        cmin = s.clim[1]
        cmax = s.clim[2]
      end
      edge = "none"
      if s.edges edge = "#00000059" end
      # The items of one face through the corners (us[k], vs[k], ws[k]):
      # the face in its colour, then shade (0 to 1) of black over it.
      face = function(us, vs, ws, col, shade)
        px = zeros(4)
        py = zeros(4)
        for k in 1:4
          [px[k], py[k], d] = proj(us[k], vs[k], ws[k])
        end
        if shade > 0
          return {{kind: "polygon", x: px, y: py, fill: col, color: "none", width: 0.5},
                  {kind: "polygon", x: px, y: py, fill: [0.0, 0.0, 0.0, shade], color: edge,
                   width: 0.5}}
        end
        return {{kind: "polygon", x: px, y: py, fill: col, color: edge, width: 0.5}}
      end
      # Far to near: by the depth of the bar's foot along the ground.
      keys = zeros(m * n)
      for i in 1:m
        for j in 1:n
          keys[(i - 1) * n + j] = -(-sa * nx(s.x[j]) + ca * ny(s.y[i]))
        end
      end
      w0 = nz(0.0)
      for k in sortperm(keys)
        i = div(k - 1, n) + 1
        j = mod(k - 1, n) + 1
        z = s.z[i, j]
        if z == z and abs(z) < inf
          if typeof(s.color) != "nothing"
            col = s.color
          else
            col = "gray"
            cc = C[i, j]
            if cc == cc
              col = colormap_at(s.colormap, (cc - cmin) / (cmax - cmin))
            end
          end
          u0 = nx(s.x[j] - hx)
          u1 = nx(s.x[j] + hx)
          v0 = ny(s.y[i] - hy)
          v1 = ny(s.y[i] + hy)
          wlo = min(w0, nz(z))
          whi = max(w0, nz(z))
          faces = {}
          if sa != 0
            uf = u0
            if sa > 0 uf = u1 end
            faces = append(faces, face([uf, uf, uf, uf], [v0, v1, v1, v0], [wlo, wlo, whi, whi],
                                       col, 0.3))
          end
          if ca != 0
            vf = v0
            if ca < 0 vf = v1 end
            faces = append(faces, face([u0, u1, u1, u0], [vf, vf, vf, vf], [wlo, wlo, whi, whi],
                                       col, 0.15))
          end
          if se != 0
            wf = wlo
            if se > 0 wf = whi end
            faces = append(faces, face([u0, u1, u1, u0], [v0, v0, v1, v1], [wf, wf, wf, wf],
                                       col, 0.0))
          end
          for f in faces
            for it in f
              items = append(items, it)
            end
          end
        end
      end
    end
  end

  # Curves (a NaN starts a new run) and markers, over the surfaces.
  for s in fig.series
    if s.type == "line3" or s.type == "scatter3"
      n = length(s.x)
      px = zeros(n)
      py = zeros(n)
      for k in 1:n
        [px[k], py[k], d] = proj(nx(s.x[k]), ny(s.y[k]), nz(s.z[k]))
      end
      if s.type == "line3"
        k = 1
        while k <= n
          while k <= n and not (px[k] == px[k] and py[k] == py[k])
            k = k + 1
          end
          j = k
          while j <= n and px[j] == px[j] and py[j] == py[j]
            j = j + 1
          end
          if j - k >= 2
            items = append(items, {kind: "line", x: px[k:j - 1], y: py[k:j - 1], color: s.color,
                                   width: s.width})
          end
          k = j
        end
        if typeof(s.marker) != "nothing"
          items = append(items, {kind: "markers", x: px, y: py, shape: s.marker,
                                 size: s.marker_size, color: s.color})
        end
      else
        items = append(items, {kind: "markers", x: px, y: py, shape: s.marker, size: s.size,
                               color: s.color})
      end
    end
  end

  # Axis labels at the front edges: x's along v = vf and y's along u = uf,
  # the sides nearer the viewer, and z's above the corner furthest left.
  # Bars with names (bar3 given lists for x or y) put the names along the
  # edge instead of the range, and the label, if there is one, beyond them.
  [t1, t2, dlo] = proj(0, -1, -1)
  [t1, t2, dhi] = proj(0, 1, -1)
  vf = -1
  if dhi < dlo vf = 1 end
  [t1, t2, dlo] = proj(-1, 0, -1)
  [t1, t2, dhi] = proj(1, 0, -1)
  uf = -1
  if dhi < dlo uf = 1 end
  xnames = nothing
  ynames = nothing
  for s in fig.series
    if s.type == "bar3"
      if typeof(xnames) == "nothing" xnames = s.xnames end
      if typeof(ynames) == "nothing" ynames = s.ynames end
    end
  end
  if typeof(xnames) == "nothing"
    [ax, ay, ad] = proj(0, 1.25 * vf, -1)
    items = append(items, text_item(ax, ay, axis_text(fig.xlabel, "x", xmin, xmax),
                                    size_or(fig.xlabel_size, TICK_SIZE), "middle", "top"))
  else
    nn = length(xnames)
    epx = zeros(nn)
    epy = zeros(nn)
    eqx = zeros(nn)
    eqy = zeros(nn)
    for k in 1:nn
      [epx[k], epy[k], ed] = proj(nx(k), vf, -1)
      [eqx[k], eqy[k], ed] = proj(nx(k), 1.12 * vf, -1)
    end
    [lx, ly, ld] = proj(0, 1.8 * vf, -1)
    for it in edge_names(xnames, epx, epy, eqx, eqy, TICK_SIZE, fig.xlabel,
                         size_or(fig.xlabel_size, TICK_SIZE), lx, ly)
      items = append(items, it)
    end
  end
  if typeof(ynames) == "nothing"
    [bx, by, bd] = proj(1.25 * uf, 0, -1)
    items = append(items, text_item(bx, by, axis_text(fig.ylabel, "y", ymin, ymax),
                                    size_or(fig.ylabel_size, TICK_SIZE), "middle", "top"))
  else
    nn = length(ynames)
    epx = zeros(nn)
    epy = zeros(nn)
    eqx = zeros(nn)
    eqy = zeros(nn)
    for k in 1:nn
      [epx[k], epy[k], ed] = proj(uf, ny(k), -1)
      [eqx[k], eqy[k], ed] = proj(1.12 * uf, ny(k), -1)
    end
    [lx, ly, ld] = proj(1.8 * uf, 0, -1)
    for it in edge_names(ynames, epx, epy, eqx, eqy, TICK_SIZE, fig.ylabel,
                         size_or(fig.ylabel_size, TICK_SIZE), lx, ly)
      items = append(items, it)
    end
  end
  zx = 1.0 / 0.0
  for c in corners
    [cxp, cyp, cd] = proj(c[1], c[2], 1.15)
    if cxp < zx
      zx = cxp
      zy = cyp
    end
  end
  items = append(items, text_item(zx, zy, axis_text(fig.zlabel, "z", zmin, zmax),
                                  size_or(fig.zlabel_size, TICK_SIZE), "middle", "bottom"))
  if typeof(fig.title) != "nothing"
    items = append(items, {kind: "text", x: W / 2, y: top / 2, text: fig.title,
                           size: ts, anchor: "middle", baseline: "middle",
                           bold: true, color: "black"})
  end
  # A legend of the labelled series, top right.
  [labelled, lw, lh] = legend_size(fig.series)
  if fig.legend and length(labelled) > 0
    items = append(items, legend_items(labelled, W - lw - 12.0, top + 8.0, lw, lh))
  end
  return {width: W, height: H, background: "white", items: items}
end

# The text items naming the bars along one edge of a 3D picture, and the
# axis label: the names stand at (qx[k], qy[k]), just outside the edge's
# points (px[k], py[k]), written flat when they all fit, with the label at
# (lx, ly). When they would overlap they are turned to run out from the
# edge, across it, where each needs only its height, so many more fit; one
# pointing left is turned round so that it reads towards the edge rather
# than upside down. Every so many are then left out if even that is not
# enough, and the label goes beyond the longest.
function edge_names(names, px, py, qx, qy, size, label, label_size, lx, ly)
  out = {}
  n = length(names)
  dx = 0.0
  dy = 0.0
  if n > 1
    dx = px[2] - px[1]
    dy = py[2] - py[1]
  end
  if name_step(names, dx, dy, size) == 1
    for k in 1:n
      out = append(out, text_item(qx[k], qy[k], names[k], size, "middle", "top"))
    end
    if typeof(label) != "nothing"
      out = append(out, text_item(lx, ly, label, label_size, "middle", "top"))
    end
    return out
  end
  # The unit direction out from the edge on the page, square to it.
  el = sqrt(dx * dx + dy * dy)
  ex = dx / el
  ey = dy / el
  rx = qx[1] - px[1]
  ry = qy[1] - py[1]
  along = rx * ex + ry * ey
  ux = rx - along * ex
  uy = ry - along * ey
  ul = sqrt(ux * ux + uy * uy)
  ux = ux / ul
  uy = uy / ul
  step = max(1, int(ceil(size * 1.3 / el)))
  # The page's y runs down, and a text's angle is anticlockwise.
  angle = -atan2(uy, ux) * 180 / pi
  anchor = "start"
  if ux < 0
    angle = angle + 180
    anchor = "end"
  end
  widest = 0.0
  for k in 1:step:n
    out = append(out, {kind: "text", x: px[k] + 6 * ux, y: py[k] + 6 * uy, text: names[k],
                       size: size + 0.0, anchor: anchor, baseline: "middle", angle: angle,
                       color: "black"})
    widest = max(widest, graphics.text_width(names[k], size))
  end
  if typeof(label) != "nothing"
    reach = 12 + widest + label_size
    out = append(out, text_item((px[1] + px[n]) / 2 + reach * ux, (py[1] + py[n]) / 2 + reach * uy,
                                label, label_size, "middle", "middle"))
  end
  return out
end

# Every how many names to write along an edge so that they do not overlap:
# neighbouring names are (dx, dy) apart on the page, and written size points
# high; one far enough apart either across or down is enough.
function name_step(names, dx, dy, size)
  n = length(names)
  if n < 2
    return 1
  end
  w = 0.0
  for name in names
    w = max(w, graphics.text_width(name, size))
  end
  across = n
  down = n
  if abs(dx) > 0
    across = ceil((w + 4) / abs(dx))
  end
  if abs(dy) > 0
    down = ceil(size * 1.3 / abs(dy))
  end
  return max(1, int(min(across, down)))
end

function axis_text(label, name, lo, hi)
  if typeof(label) != "nothing" name = label end
  [t, step] = nice_ticks(lo, hi, 2)
  return name + " [" + tick_label(lo, (hi - lo) / 4) + ", " + tick_label(hi, (hi - lo) / 4) + "]"
end
