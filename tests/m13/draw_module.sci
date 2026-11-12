# The draw module: view coordinates (y up) mapped to the page, shapes, the
# turtle, L-systems, and saving.
import draw
import io

# 200 x 100 points showing x in [-1, 1] and y in [0, 1]: 100 points per unit
# both ways, and y = 1 at the top of the page.
draw.canvas(width = 200, height = 100, view = [-1, 1, 0, 1])
draw.line(-1, 0, 1, 1, color = "red")
draw.circle(0, 0.5, 0.25)
draw.rect(-0.5, 0.25, 0.5, 0.5, fill = "blue")
s = draw.scene()
it = s.items
println(length(it), s.width, s.height)
println(it[1].kind, it[1].x[1], it[1].x[2], it[1].y[1], it[1].y[2])
println(it[2].kind, it[2].x, it[2].y, it[2].rx, it[2].ry)
println(it[3].kind, it[3].x, it[3].y, it[3].w, it[3].h)
draw.save("_tmp_draw.svg")
println(io.file_exists("_tmp_draw.svg"), io.delete_file("_tmp_draw.svg"))

# The turtle: 30 to the right, turn left, 20 up; push, wander, pop back.
draw.canvas(width = 100, height = 100)
draw.turtle(x = 10, y = 10, heading = 0)
draw.forward(30)
draw.left(90)
draw.forward(20)
[x, y, h] = draw.where()
println(format(x, 6), format(y, 6), h)
draw.push()
draw.right(90)
draw.forward(5)
draw.pop()
[x, y, h] = draw.where()
println(format(x, 6), format(y, 6), h)
# One line through four points, flipped onto the page (y down).
s = draw.scene()
println(length(s.items), s.items[1].kind, length(s.items[1].x), s.items[1].y[1])

# L-systems: rewriting, and the points a string traces.
println(draw.lsystem("F", dict("F" => "F+F"), 2))
println(draw.lsystem("AB", dict("A" => "AB", "B" => "A"), 3))
[xs, ys] = draw.lsystem_path("F+F-f", 90, heading = 0)
println(length(xs), xs[2], ys[3], xs[4] == xs[4], xs[5], ys[5])
draw.save("_tmp_draw.png")
println(io.delete_file("_tmp_draw.png"))

# clear: the canvas emptied and shown, its size, view and background kept,
# the turtle back in the middle heading up.
draw.canvas(width = 200, height = 100, view = [-1, 1, 0, 1], background = "black")
draw.circle(0, 0.5, 0.25)
draw.turtle(x = 0.5, y = 0.5, heading = 0)
draw.forward(0.2)
draw.clear()
s = draw.scene()
println(length(s.items), s.width, s.height, s.background)
[x, y, h] = draw.where()
println(x, y, h)
draw.line(-1, 0, 1, 1)
println(length(draw.scene().items))
