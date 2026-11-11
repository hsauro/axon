## Colours, line widths and fills.
import draw

draw.canvas(width = 400, height = 220)

# Line widths from 1 to 6 points.
for k in 1:6
  draw.line(20, 205 - 15 * k, 160, 205 - 15 * k, width = k)
end

# Three ways to give a colour: a name, "#rrggbb", or [red, green, blue]
# with each part from 0 to 1; then a dashed line, and one with round ends.
draw.line(20, 95, 160, 95, color = "red", width = 3)
draw.line(20, 75, 160, 75, color = "#2ca02c", width = 3)
draw.line(20, 55, 160, 55, color = [0.2, 0.4, 1.0], width = 3)
draw.line(20, 35, 160, 35, width = 3, dash = [8, 4])
draw.line(30, 15, 150, 15, width = 10, cap = "round", color = "purple")

# fill colours the inside and color the outline; "none" leaves one out.
draw.rect(200, 120, 80, 70, fill = "yellow", color = "black", width = 2)
draw.circle(340, 155, 35, fill = "orange", color = "none")

# A fourth number makes a colour see-through: 0.5 is half transparent.
draw.circle(250, 60, 40, fill = [1, 0, 0, 0.5], color = "none")
draw.circle(300, 60, 40, fill = [0, 0, 1, 0.5], color = "none")
draw.circle(350, 60, 40, fill = [0, 0.7, 0, 0.5], color = "none")

draw.save("../figures/canvas_style.pdf")
