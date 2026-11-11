## Drawing on a blank canvas: lines, shapes, text and images, a turtle, and
## L-systems, in coordinates of your choosing with y pointing up. Built on
## the graphics module; see the Language Reference, "The draw module".
##
##   import draw
##   draw.canvas(width = 400, height = 400, view = [-1, 1, -1, 1])
##   draw.circle(0, 0, 0.8, fill = "yellow")
##   draw.line(-1, -1, 1, 1, color = "red", width = 2)
##   draw.show()

import graphics
import time

# The current canvas: its size in points, the view [xmin, xmax, ymin, ymax]
# it shows, and the points per unit along x and y.
current = nothing
# Its items, kept apart so that appending to them grows the list in place.
items = {}
# Whether something was drawn since the last show or save.
changed = false
# Animation: when the last frame was sent (time.clock), how many so far, and
# how many of the canvas's items the frames have sent (0 after a new canvas,
# so the next frame sends the whole picture; otherwise only what was added).
last_frame = nothing
frames = 0
sent = 0

# The turtle: position, heading (degrees anticlockwise from the x axis),
# pen, and the points of the line it is drawing.
tx = 0.0
ty = 0.0
theading = 90.0
tdown = true
tcolor = "black"
twidth = 1.0
path_x = vector()
path_y = vector()
tstack = {}

function fail(kind, message)
  error(kind, message)
end

function is_number(v)
  return typeof(v) == "int" or typeof(v) == "real"
end

# ---------------------------------------------------------------- the canvas

## A new canvas, which the drawing functions then draw on: width and height
## in points (1/72 inch), view = [xmin, xmax, ymin, ymax] the coordinates it
## shows (by default [0, width, 0, height]), with y pointing up, and the
## background colour. A canvas with something drawn that was not shown is
## shown first.
export function canvas(; width = 640, height = 480, view = nothing, background = "white")
  global current
  global items
  global changed
  global sent
  show_unshown()
  if not is_number(width) or not is_number(height)
    fail("TypeError", "draw.canvas: width and height must be numbers")
  end
  if not (width > 0) or not (height > 0)
    fail("ArgumentError", "draw.canvas: width and height must be positive")
  end
  if typeof(view) == "nothing"
    view = [0.0; width; 0.0; height]
  end
  if length(view) != 4
    fail("ArgumentError", "draw.canvas: view must be [xmin, xmax, ymin, ymax]")
  end
  view = vector(view) + 0.0
  if not (view[2] > view[1]) or not (view[4] > view[3])
    fail("ArgumentError", "draw.canvas: view needs xmin < xmax and ymin < ymax")
  end
  # x0 and y0, the view's lower-left corner, and the points per unit sx and sy
  # turn view coordinates into the page's: (x - x0) sx, height - (y - y0) sy.
  current = {width: width + 0.0, height: height + 0.0, view: view, x0: view[1], y0: view[3],
             sx: width / (view[2] - view[1]), sy: height / (view[4] - view[3]),
             background: background}
  items = {}
  changed = false
  sent = 0
  reset_turtle((view[1] + view[2]) / 2, (view[3] + view[4]) / 2, 90.0)
  return nothing
end

# The current canvas, made with the defaults if there is none yet.
function canvas_now()
  if typeof(current) == "nothing"
    canvas()
  end
  return current
end

# Canvas points from view coordinates (numbers or vectors). The shape
# functions, which are called often, work these out inline instead.
function px(x)
  c = canvas_now()
  return (x - c.x0) * c.sx
end

function py(y)
  c = canvas_now()
  return c.height - (y - c.y0) * c.sy
end

# Adds an item to the canvas (made already).
function add(item)
  global items
  global changed
  items = append(items, item)
  changed = true
end

## The canvas as a graphics scene record, with the turtle's line so far.
export function scene(; scale = 2.0)
  c = canvas_now()
  flush()
  return {width: c.width, height: c.height, background: c.background, scale: scale + 0.0,
          items: items}
end

## Shows the canvas: in the IDE's plot pane, or in the system's image viewer.
export function show(; scale = 2.0)
  global changed
  graphics.show(scene(scale = scale))
  changed = false
end

## Writes the canvas to a .png, .svg or .pdf file.
export function save(path; scale = 2.0)
  global changed
  graphics.save(scene(scale = scale), path)
  changed = false
end

## Shows the canvas as one frame of an animation and starts the next one's
## timing: call it at the end of each pass of a loop that redraws the canvas.
## In the IDE each frame replaces the last in the plot pane, which keeps one
## entry for the whole animation in its history. It waits so that frames come
## fps times a second (a program that falls behind just carries on, without
## hurrying to catch up). With save set, each frame is also written to a
## numbered PNG file: save = "frames/swing" gives frames/swing_00001.png,
## frames/swing_00002.png and so on (the folder must exist), for making a
## video; outside the IDE that is the only thing frame does.
export function frame(; fps = 30, scale = 1.0, save = nothing)
  global changed
  global last_frame
  global frames
  global sent
  if not is_number(fps) or not (fps > 0)
    fail("ArgumentError", "draw.frame: fps must be a positive number")
  end
  sc = scene(scale = scale)
  frames = frames + 1
  if typeof(save) != "nothing"
    name = string(frames)
    while length(name) < 5
      name = "0" + name
    end
    graphics.save(sc, save + "_" + name + ".png")
  end
  # Wait for this frame's moment, then send it.
  now = time.clock()
  if typeof(last_frame) != "nothing"
    due = last_frame + 1 / fps
    if now < due
      time.sleep(due - now)
      now = due
    end
  end
  last_frame = now
  # Only the items added since the last frame, unless the canvas is new.
  if sent > 0 and sent <= length(sc.items)
    graphics.frame(sc, sent)
  else
    graphics.frame(sc)
  end
  sent = length(sc.items)
  changed = false
end

function show_unshown()
  flush()
  if changed and length(items) > 0
    show()
  end
end

atexit(show_unshown)

# ---------------------------------------------------------------- shapes

## A line from (x1, y1) to (x2, y2). cap is "butt", "round" or "square".
export function line(x1, y1, x2, y2; color = "black", width = 1.0, dash = nothing, cap = "butt")
  c = canvas_now()
  add({kind: "line", x: ([x1; x2] - c.x0) * c.sx, y: c.height - ([y1; y2] - c.y0) * c.sy,
       color: color, width: width, dash: dash, cap: cap})
end

## A line through the points (x[k], y[k]); a NaN breaks it. join is "round",
## "miter" or "bevel".
export function polyline(x, y; color = "black", width = 1.0, dash = nothing, cap = "butt",
                         join = "round")
  c = canvas_now()
  add({kind: "polyline", x: (vector(x) - c.x0) * c.sx, y: c.height - (vector(y) - c.y0) * c.sy,
       color: color, width: width, dash: dash, cap: cap, join: join})
end

## A closed shape through the points, filled with fill and outlined with
## color ("none" for no outline).
export function polygon(x, y; fill = "none", color = "black", width = 1.0, join = "round")
  c = canvas_now()
  add({kind: "polygon", x: (vector(x) - c.x0) * c.sx, y: c.height - (vector(y) - c.y0) * c.sy,
       fill: fill, color: color, width: width, join: join})
end

## A rectangle with lower-left corner (x, y), width w and height h.
export function rect(x, y, w, h; fill = "none", color = "black", width = 1.0)
  c = canvas_now()
  add({kind: "rect", x: (x - c.x0) * c.sx, y: c.height - (y + h - c.y0) * c.sy, w: w * c.sx,
       h: h * c.sy, fill: fill, color: color, width: width})
end

## A circle of radius r around (x, y). (With different scales along x and y,
## see canvas, it is drawn as the ellipse it becomes.)
export function circle(x, y, r; fill = "none", color = "black", width = 1.0)
  c = canvas_now()
  add({kind: "ellipse", x: (x - c.x0) * c.sx, y: c.height - (y - c.y0) * c.sy, rx: r * c.sx,
       ry: r * c.sy, fill: fill, color: color, width: width})
end

## An ellipse around (x, y) with semi-axes rx and ry, turned by angle degrees
## anticlockwise.
export function ellipse(x, y, rx, ry; angle = 0.0, fill = "none", color = "black", width = 1.0)
  c = canvas_now()
  add({kind: "ellipse", x: (x - c.x0) * c.sx, y: c.height - (y - c.y0) * c.sy, rx: rx * c.sx,
       ry: ry * c.sy, angle: angle, fill: fill, color: color, width: width})
end

## An arc of the circle of radius r around (x, y), from start through sweep
## degrees anticlockwise (start 0 is the positive x direction). wedge = true
## closes it through the centre, a pie slice that fill can fill.
export function arc(x, y, r, start, sweep; color = "black", width = 1.0, wedge = false,
                    fill = "none")
  c = canvas_now()
  add({kind: "arc", x: (x - c.x0) * c.sx, y: c.height - (y - c.y0) * c.sy, r: r * c.sx,
       start: start, sweep: sweep, color: color, width: width, wedge: wedge, fill: fill})
end

## Markers at (x, y), numbers or vectors: shape "circle", "square", "diamond",
## "triangle", "plus" or "cross", size in points.
export function points(x, y; shape = "circle", size = 4.0, color = "black", fill = nothing)
  if typeof(fill) == "nothing"
    fill = color
  end
  c = canvas_now()
  add({kind: "markers", x: (vector(x) - c.x0) * c.sx, y: c.height - (vector(y) - c.y0) * c.sy,
       shape: shape, size: size, color: color, fill: fill})
end

## Text at (x, y): size in points, anchor "start", "middle" or "end", angle in
## degrees anticlockwise.
export function text(x, y, s; size = 12.0, color = "black", anchor = "start", angle = 0.0,
                     font = "sans-serif", bold = false)
  c = canvas_now()
  add({kind: "text", x: (x - c.x0) * c.sx, y: c.height - (y - c.y0) * c.sy, text: string(s),
       size: size, color: color, anchor: anchor, baseline: "middle", angle: angle, font: font,
       bold: bold})
end

## A matrix of values drawn as pixels, row 1 at the top, filling the
## rectangle with lower-left corner (x, y), width w and height h (by default
## the whole view). colormap is "viridis", "gray", "hsv" or a matrix with
## rows [r, g, b]; vmin and vmax set the range (by default the values');
## NaN values take nan_color. smooth = true blends neighbouring pixels.
export function image(values; x = nothing, y = nothing, w = nothing, h = nothing,
                      colormap = "viridis", vmin = nothing, vmax = nothing,
                      nan_color = "none", smooth = false)
  r = place(x, y, w, h)
  add({kind: "image", values: values, x: r[1], y: r[2], w: r[3], h: r[4],
       colormap: colormap, vmin: vmin, vmax: vmax, nan_color: nan_color, smooth: smooth})
end

## An image from red, green and blue matrices (and optionally alpha) with
## components from 0 to 1, placed as image places it.
export function image_rgb(red, green, blue; alpha = nothing, x = nothing, y = nothing,
                          w = nothing, h = nothing, smooth = false)
  r = place(x, y, w, h)
  add({kind: "image", red: red, green: green, blue: blue, alpha: alpha, x: r[1], y: r[2],
       w: r[3], h: r[4], smooth: smooth})
end

# [x, y, w, h] on the canvas for a rectangle in view coordinates, the whole
# view by default.
function place(x, y, w, h)
  c = canvas_now()
  if typeof(x) == "nothing" x = c.view[1] end
  if typeof(y) == "nothing" y = c.view[3] end
  if typeof(w) == "nothing" w = c.view[2] - x end
  if typeof(h) == "nothing" h = c.view[4] - y end
  return [px(x); py(y + h); w * c.sx; h * c.sy]
end

# ---------------------------------------------------------------- the turtle

function reset_turtle(x, y, heading)
  global tx
  global ty
  global theading
  global tdown
  global tcolor
  global twidth
  global path_x
  global path_y
  global tstack
  tx = x + 0.0
  ty = y + 0.0
  theading = heading + 0.0
  tdown = true
  tcolor = "black"
  twidth = 1.0
  path_x = vector()
  path_y = vector()
  tstack = {}
end

# Ends the turtle's current line, adding it to the canvas.
function flush()
  global path_x
  global path_y
  if length(path_x) >= 2
    add({kind: "polyline", x: px(path_x), y: py(path_y), color: tcolor, width: twidth,
         cap: "round", join: "round"})
  end
  path_x = vector()
  path_y = vector()
end

## Puts the turtle at (x, y) facing heading degrees anticlockwise from the
## x axis (90, up, by default), with its pen down, black and 1 point wide.
## By default it starts in the middle of the view, facing up.
export function turtle(; x = nothing, y = nothing, heading = 90.0)
  c = canvas_now()
  flush()
  if typeof(x) == "nothing" x = (c.view[1] + c.view[2]) / 2 end
  if typeof(y) == "nothing" y = (c.view[3] + c.view[4]) / 2 end
  reset_turtle(x, y, heading)
end

## Moves the turtle d units ahead, drawing a line when its pen is down.
export function forward(d)
  global tx
  global ty
  global path_x
  global path_y
  canvas_now()
  if tdown and length(path_x) == 0
    path_x = append(path_x, tx)
    path_y = append(path_y, ty)
  end
  a = theading * pi / 180
  tx = tx + d * cos(a)
  ty = ty + d * sin(a)
  if tdown
    path_x = append(path_x, tx)
    path_y = append(path_y, ty)
  end
end

## Moves the turtle d units backwards.
export function back(d)
  forward(-d)
end

## Turns the turtle a degrees anticlockwise.
export function left(a)
  global theading
  theading = theading + a
end

## Turns the turtle a degrees clockwise.
export function right(a)
  global theading
  theading = theading - a
end

## Lifts the pen: the turtle moves without drawing.
export function penup()
  global tdown
  flush()
  tdown = false
end

## Puts the pen down: the turtle draws as it moves.
export function pendown()
  global tdown
  tdown = true
end

## The pen's colour and width (in points) for what the turtle draws next.
export function pen(; color = nothing, width = nothing)
  global tcolor
  global twidth
  flush()
  if typeof(color) != "nothing" tcolor = color end
  if typeof(width) != "nothing" twidth = width + 0.0 end
end

## Moves the turtle to (x, y), drawing a line when its pen is down.
export function goto(x, y)
  global tx
  global ty
  global path_x
  global path_y
  canvas_now()
  if tdown
    if length(path_x) == 0
      path_x = append(path_x, tx)
      path_y = append(path_y, ty)
    end
    path_x = append(path_x, x + 0.0)
    path_y = append(path_y, y + 0.0)
  end
  tx = x + 0.0
  ty = y + 0.0
end

## Sets the turtle's heading: degrees anticlockwise from the x axis.
export function set_heading(a)
  global theading
  theading = a + 0.0
end

## The turtle's position and heading, as three values: [x, y, h] = draw.where().
export function where()
  return tx, ty, theading
end

## Saves the turtle's position and heading, for pop.
export function push()
  global tstack
  tstack = append(tstack, [tx; ty; theading])
end

## Returns the turtle to the position and heading last saved with push,
## without drawing.
export function pop()
  global tx
  global ty
  global theading
  global tstack
  if length(tstack) == 0
    fail("ArgumentError", "draw.pop: nothing was pushed")
  end
  flush()
  s = tstack[end]
  tstack = tstack[1:(length(tstack) - 1)]
  tx = s[1]
  ty = s[2]
  theading = s[3]
end

# ---------------------------------------------------------------- L-systems

## The string an L-system makes from axiom after n rewritings: rules is a
## dictionary from a character to the string that replaces it at each step
## (characters without a rule stay as they are).
export function lsystem(axiom, rules, n)
  s = axiom
  for k in 1:n
    parts = {}
    for c in s
      if haskey(rules, c)
        parts = append(parts, rules[c])
      else
        parts = append(parts, c)
      end
    end
    s = join(parts, "")
  end
  return s
end

# The points an L-system string traces from (x, y) facing h (degrees):
# characters in draws move forward step units drawing, those in moves move
# forward without drawing (a NaN breaks the line), + and - turn left and
# right by angle degrees, | turns round, [ saves the position and heading
# and ] returns to them (also breaking the line). Returns the points and
# where the walk ends: xs, ys, x, y, h.
function trace(s, x, y, h, step, angle, draws, moves)
  xs = vector()
  ys = vector()
  xs = append(xs, x)
  ys = append(ys, y)
  stack = {}
  nan = 0.0 / 0.0
  for c in s
    if contains(draws, c)
      x = x + step * cos(h * pi / 180)
      y = y + step * sin(h * pi / 180)
      xs = append(xs, x)
      ys = append(ys, y)
    elseif c == "+"
      h = h + angle
    elseif c == "-"
      h = h - angle
    elseif c == "|"
      h = h + 180
    elseif c == "["
      stack = append(stack, [x; y; h])
    elseif c == "]"
      p = stack[end]
      stack = stack[1:(length(stack) - 1)]
      x = p[1]
      y = p[2]
      h = p[3]
      xs = append(xs, nan)
      ys = append(ys, nan)
      xs = append(xs, x)
      ys = append(ys, y)
    elseif contains(moves, c)
      x = x + step * cos(h * pi / 180)
      y = y + step * sin(h * pi / 180)
      xs = append(xs, nan)
      ys = append(ys, nan)
      xs = append(xs, x)
      ys = append(ys, y)
    end
  end
  return xs, ys, x, y, h
end

## The points an L-system string traces, starting at (0, 0) facing heading
## degrees (up by default), as two vectors xs, ys with NaN where the line
## breaks; draw them with polyline, scaled and moved as needed. The
## characters in draw move forward step units drawing, those in move move
## forward without drawing, + and - turn left and right by angle degrees,
## | turns round, and [ and ] save and restore the position and heading.
## Other characters (such as X in many L-systems) do nothing.
export function lsystem_path(s, angle; step = 1.0, heading = 90.0, draw = "FG", move = "f")
  [xs, ys, x, y, h] = trace(s, 0.0, 0.0, heading + 0.0, step + 0.0, angle, draw, move)
  return xs, ys
end

## Draws an L-system string with the turtle, from its position and heading,
## with its pen, as lsystem_path reads the characters.
export function lsystem_draw(s, step, angle; draw = "FG", move = "f")
  global tx
  global ty
  global theading
  global path_x
  global path_y
  canvas_now()
  [xs, ys, x, y, h] = trace(s, tx, ty, theading, step + 0.0, angle, draw, move)
  if tdown
    if length(path_x) == 0
      path_x = xs
      path_y = ys
    elseif length(xs) > 1
      # xs[1] is where the turtle stands, the line's last point already.
      path_x = append(path_x, xs[2:end])
      path_y = append(path_y, ys[2:end])
    end
  end
  tx = x
  ty = y
  theading = h
end
