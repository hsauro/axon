## Line, scatter, bar, histogram and surface plots, saved as PNG, SVG or PDF. Plotting calls
## add to the current figure; plot.save writes it. See the Language
## Reference, "The plot module".

import graphics

# The figure that plotting calls add to (nothing until the first call).
current = nothing

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
          xcategories: nothing}
end

function figure_now()
  global current
  if typeof(current) == "nothing"
    current = new_figure(640, 480, nothing)
  end
  return current
end

function next_color(fig)
  return CYCLE[mod(length(fig.series), length(CYCLE)) + 1]
end

function add_series(s)
  global current
  figure_now()
  if s.three_d != current.three_d and length(current.series) > 0
    fail("ArgumentError", "a figure cannot mix surfaces with line and scatter plots")
  end
  current.three_d = s.three_d
  current.series = append(current.series, s)
end

# ---------------------------------------------------------------- public API

## Starts a new current figure of the given size in points (1/72 inch).
export function figure(; width = 640, height = 480, title = nothing)
  global current
  if not (width > 0 and height > 0)
    fail("ArgumentError", "plot.figure: width and height must be positive")
  end
  current = new_figure(width, height, title)
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
## places the bars at 1, 2, ... and labels the x axis with the names. Bars
## rise from 0, or fall for negative heights. Keywords: width (of each bar,
## in x units), label, color.
export function bar(x, heights; width = 0.8, label = nothing, color = nothing)
  global current
  categories = nothing
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
## Keywords: label, colormap ("viridis" or "gray"), edges (draw the mesh),
## elev and azim (viewing angles in degrees).
export function surface(x, y, Z; label = nothing, colormap = "viridis", edges = true,
                        elev = 30.0, azim = -60.0)
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
  if colormap != "viridis" and colormap != "gray"
    fail("ArgumentError", "plot.surface: colormap must be \"viridis\" or \"gray\"")
  end
  add_series({type: "surface", three_d: true, x: xs, y: ys, z: reshape([Z] + 0.0, m, n),
              label: label, colormap: colormap, edges: edges})
  current.elev = elev + 0.0
  current.azim = azim + 0.0
end

## Sets the title of the current figure.
export function title(text)
  global current
  figure_now()
  current.title = text
end

## Sets the x-axis label.
export function xlabel(text)
  global current
  figure_now()
  current.xlabel = text
end

## Sets the y-axis label.
export function ylabel(text)
  global current
  figure_now()
  current.ylabel = text
end

## Sets the z-axis label (surfaces).
export function zlabel(text)
  global current
  figure_now()
  current.zlabel = text
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

## Turns the legend (of labelled series) on or off.
export function legend(on)
  global current
  figure_now()
  current.legend = on
end

## Shows the current figure: in the IDE's plot pane when run from the IDE,
## otherwise in the system's image viewer. scale sets the pixels per point.
export function show(; scale = 2.0)
  if typeof(current) == "nothing"
    fail("ArgumentError", "plot.show: there is no figure; plot something first")
  end
  scene = render(current)
  scene.scale = scale + 0.0
  graphics.show(scene)
end

## The current figure, as a record (nothing before the first plotting call).
export function gcf()
  return current
end

## Writes the current figure to a .png, .svg or .pdf file. scale sets the
## pixels per point of a PNG.
export function save(path; scale = 2.0)
  if typeof(current) == "nothing"
    fail("ArgumentError", "plot.save: there is no figure; plot something first")
  end
  scene = render(current)
  scene.scale = scale + 0.0
  graphics.save(scene, path)
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
  d = -floor(log(step) / log(10.0) + 1e-9)
  scale = 10.0 ^ d
  return string(round(v * scale) / scale)
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
  [yt, ystep] = nice_ticks(y0, y1, 6)
  # Category names label their positions 1, 2, ...; otherwise round numbers.
  if typeof(fig.xcategories) != "nothing"
    xt = zeros(length(fig.xcategories))
    for k in 1:length(xt) xt[k] = k end
    xlabels = fig.xcategories
  else
    [xt, xstep] = nice_ticks(x0, x1, 7)
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

  # Margins around the plot area.
  top = 12.0
  if typeof(fig.title) != "nothing" top = TITLE_SIZE * 2.2 end
  left = 12.0 + wmax + 8.0
  if typeof(fig.ylabel) != "nothing" left = left + LABEL_SIZE * 1.8 end
  bottom = 12.0 + TICK_SIZE * 1.6
  if typeof(fig.xlabel) != "nothing" bottom = bottom + LABEL_SIZE * 1.8 end
  right = 20.0
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
    items = append(items, text_item((px0 + px1) / 2, H - 10.0, fig.xlabel, LABEL_SIZE,
                                    "middle", "bottom"))
  end
  if typeof(fig.ylabel) != "nothing"
    items = append(items, {kind: "text", x: 10.0 + LABEL_SIZE, y: (py0 + py1) / 2,
                           text: fig.ylabel, size: LABEL_SIZE, anchor: "middle",
                           baseline: "alphabetic", angle: 90.0, color: "black"})
  end
  if typeof(fig.title) != "nothing"
    items = append(items, {kind: "text", x: (px0 + px1) / 2, y: top / 2, text: fig.title,
                           size: TITLE_SIZE, anchor: "middle", baseline: "middle",
                           bold: true, color: "black"})
  end
  if fig.legend
    items = append(items, legend_items(fig.series, px1, py0))
  end
  return {width: W, height: H, background: "white", items: items}
end

# A legend box in the top-right corner of the plot area, or an empty group.
function legend_items(series, xr, yt)
  labelled = {}
  for s in series
    if typeof(s.label) != "nothing" labelled = append(labelled, s) end
  end
  if length(labelled) == 0
    return {kind: "group", items: {}}
  end
  wmax = 0.0
  for s in labelled
    wmax = max(wmax, graphics.text_width(s.label, TICK_SIZE))
  end
  rowh = TICK_SIZE * 1.6
  bw = wmax + 40.0
  bh = rowh * length(labelled) + 8.0
  bx = xr - bw - 8.0
  by = yt + 8.0
  items = {{kind: "rect", x: bx, y: by, w: bw, h: bh, fill: "#ffffffe6", color: "#c0c0c0",
            width: 0.8}}
  for k in 1:length(labelled)
    s = labelled[k]
    cy = by + 4.0 + rowh * (k - 0.5)
    if s.type == "bars"
      items = append(items, {kind: "rect", x: bx + 9.0, y: cy - 5.0, w: 16.0, h: 10.0,
                             fill: s.color})
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

function colormap_at(name, u)
  u = min(max(u, 0.0), 1.0)
  if name == "gray"
    g = 0.15 + 0.8 * u
    return [g, g, g]
  end
  pos = u * 10.0
  k = min(floor(pos), 9)
  f = pos - k
  return (1 - f) * VIRIDIS[k + 1, :] + f * VIRIDIS[k + 2, :]
end

function render_3d(fig)
  W = fig.width
  H = fig.height
  s = fig.series[1]
  xs = s.x
  ys = s.y
  Z = s.z
  [m, n] = size(Z)
  xmin = min(xs)
  xmax = max(xs)
  ymin = min(ys)
  ymax = max(ys)
  zmin = min(Z)
  zmax = max(Z)
  if xmax == xmin xmax = xmin + 1 end
  if ymax == ymin ymax = ymin + 1 end
  if zmax == zmin zmax = zmin + 1 end

  # Orthographic view of the cube [-1, 1]^3 (z squashed a little).
  az = fig.azim * 3.141592653589793 / 180
  el = fig.elev * 3.141592653589793 / 180
  ca = cos(az)
  sa = sin(az)
  ce = cos(el)
  se = sin(el)
  top = 12.0
  if typeof(fig.title) != "nothing" top = TITLE_SIZE * 2.2 end
  cx = W / 2
  cy = top + (H - top) / 2
  scale = min(W, H - top) * 0.3
  # Projection of a normalised point (u, v, w): screen x, screen y and depth
  # (larger is farther). The viewer is at elevation el above the rotated
  # u-v plane, looking towards +v; heights are squashed to 0.8.
  proj = function(u, v, w)
    rx = ca * u - sa * v
    ry = sa * u + ca * v
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

  # Faces, back to front: the loops run away from the viewer first.
  [vx, vy, vd] = proj(1, 0, 0)
  [ux, uy, ud] = proj(0, 1, 0)
  [ox, oy, od] = proj(0, 0, 0)
  irange = 1:m - 1
  jrange = 1:n - 1
  if ud - od > 0 irange = m - 1:-1:1 end
  if vd - od > 0 jrange = n - 1:-1:1 end
  for i in irange
    for j in jrange
      zc = (Z[i, j] + Z[i, j + 1] + Z[i + 1, j + 1] + Z[i + 1, j]) / 4
      col = colormap_at(s.colormap, (zc - zmin) / (zmax - zmin))
      [p1x, p1y, q1] = proj(nx(xs[j]), ny(ys[i]), nz(Z[i, j]))
      [p2x, p2y, q2] = proj(nx(xs[j + 1]), ny(ys[i]), nz(Z[i, j + 1]))
      [p3x, p3y, q3] = proj(nx(xs[j + 1]), ny(ys[i + 1]), nz(Z[i + 1, j + 1]))
      [p4x, p4y, q4] = proj(nx(xs[j]), ny(ys[i + 1]), nz(Z[i + 1, j]))
      edge = "none"
      if s.edges edge = "#00000040" end
      items = append(items, {kind: "polygon", x: [p1x, p2x, p3x, p4x], y: [p1y, p2y, p3y, p4y],
                             fill: col, color: edge, width: 0.4})
    end
  end

  # Axis labels at the front edges.
  [ax, ay, ad] = proj(0, -1.25, -1)
  items = append(items, text_item(ax, ay, axis_text(fig.xlabel, "x", xmin, xmax), TICK_SIZE,
                                  "middle", "top"))
  [bx, by, bd] = proj(1.25, 0, -1)
  items = append(items, text_item(bx, by, axis_text(fig.ylabel, "y", ymin, ymax), TICK_SIZE,
                                  "middle", "top"))
  [zx, zy, zd] = proj(-1, -1, 1.15)
  items = append(items, text_item(zx, zy, axis_text(fig.zlabel, "z", zmin, zmax), TICK_SIZE,
                                  "middle", "bottom"))
  if typeof(fig.title) != "nothing"
    items = append(items, {kind: "text", x: W / 2, y: top / 2, text: fig.title,
                           size: TITLE_SIZE, anchor: "middle", baseline: "middle",
                           bold: true, color: "black"})
  end
  return {width: W, height: H, background: "white", items: items}
end

function axis_text(label, name, lo, hi)
  if typeof(label) != "nothing" name = label end
  [t, step] = nice_ticks(lo, hi, 2)
  return name + " [" + tick_label(lo, (hi - lo) / 4) + ", " + tick_label(hi, (hi - lo) / 4) + "]"
end
