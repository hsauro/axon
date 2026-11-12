# Every named colour of the colors module, in alphabetical order: five
# columns, each cell a swatch and its name.
import colors
import draw

names = colors.names()
cols = 5
rows = div(length(names) + cols - 1, cols)
draw.canvas(width = 900, height = rows * 22 + 10, view = [0, cols, 0, rows])
for k in 1:length(names)
  c = mod(k - 1, cols)
  r = rows - 1 - div(k - 1, cols)   # the first row at the top
  draw.rect(c + 0.02, r + 0.15, 0.2, 0.7, fill = colors.rgb(names[k]),
            color = "gray")
  draw.text(c + 0.25, r + 0.5, names[k], size = 11)
end
draw.save("../figures/colors_chart.pdf")
