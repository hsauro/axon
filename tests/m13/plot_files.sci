import plot
import graphics
import io

# Does s contain t? (a test helper; there is no string search built in)
function contains(s, t)
  n = length(t)
  for k in 1:length(s) - n + 1
    if s[k:k + n - 1] == t return true end
  end
  return false
end

x = linspace(0.0, 1.0, 20)
plot.figure(title = "Test figure")
plot.line(x, x .^ 2, label = "square", style = "--")
plot.scatter(x, x, label = "identity", marker = "diamond")
plot.xlabel("time")
plot.ylabel("value")
for f in {"_tmp_plot.png", "_tmp_plot.svg", "_tmp_plot.pdf"}
  plot.save(f)
end

# PNG: the signature, then the IHDR size (640 by 480 points at scale 2).
b = io.read_bytes("_tmp_plot.png")
print(b[1:8]')
print(b[17:24]')
# SVG: an XML document whose labels are text.
s = io.read_file("_tmp_plot.svg")
print(s[1:5], contains(s, "<svg"), contains(s, "Test figure"), contains(s, "identity"))
# PDF: the header.
d = io.read_bytes("_tmp_plot.pdf")
print(d[1:5]')
for f in {"_tmp_plot.png", "_tmp_plot.svg", "_tmp_plot.pdf"}
  io.delete_file(f)
end

# graphics directly: a 100 by 50 PNG at scale 1, colours as vectors.
graphics.save({width: 100.0, height: 50.0, scale: 1,
               items: {{kind: "rect", x: 10.0, y: 10.0, w: 20.0, h: 20.0, fill: [1.0, 0.0, 0.0]},
                       {kind: "text", x: 50.0, y: 25.0, text: "Hi", anchor: "middle"}}},
              "_tmp_g.png")
c = io.read_bytes("_tmp_g.png")
print(c[17:24]')
io.delete_file("_tmp_g.png")
print(graphics.text_width("", 10.0), graphics.text_width("abc", 10.0) > 0,
      graphics.text_width("abcabc", 10.0) > graphics.text_width("abc", 10.0))

# A surface figure renders too.
g = linspace(-1.0, 1.0, 8)
Z = zeros(8, 8)
for i in 1:8
  for j in 1:8
    Z[i, j] = g[i] * g[j]
  end
end
plot.figure()
plot.surface(g, g, Z, colormap = "gray")
plot.save("_tmp_surface.svg")
print(io.delete_file("_tmp_surface.svg"))
