# The graphics items for drawing: circles, ellipses, arcs, images, caps and
# joins, and groups turned and scaled. Saved as SVG, PDF and PNG.
import graphics
import io

n = 8
V = zeros(n, n)
for i in 1:n
  for j in 1:n
    V[i, j] = i + j
  end
end
V[1, 1] = 0.0 / 0.0
G = V / 16
G[1, 1] = 0.0
items = {{kind: "circle", x: 20, y: 20, r: 10},
         {kind: "circle", x: 50, y: 20, r: 10, fill: "orange", color: "none"},
         {kind: "ellipse", x: 80, y: 20, rx: 12, ry: 6, angle: 30, fill: [0.2, 0.4, 0.8, 0.5]},
         {kind: "arc", x: 110, y: 20, r: 10, start: 0, sweep: 90, width: 2, cap: "round"},
         {kind: "arc", x: 140, y: 20, r: 10, start: 30, sweep: 300, wedge: true, fill: "yellow"},
         {kind: "polyline", x: [10.0; 20; 30], y: [60.0; 40; 60], width: 6, cap: "square",
          join: "miter"},
         {kind: "polygon", x: [40.0; 50; 60], y: [60.0; 40; 60], color: "red", join: "bevel"},
         {kind: "group", dx: 100, dy: 50, angle: 45, scale: [2, 1],
          items: {{kind: "rect", x: -5, y: -5, w: 10, h: 10, fill: "green"}}},
         {kind: "image", values: V, x: 10, y: 70, w: 40, h: 40},
         {kind: "image", values: V, colormap: "hsv", x: 60, y: 70, w: 40, h: 40, smooth: true},
         {kind: "image", values: V, colormap: [0.0, 0, 0; 1, 1, 1], vmin: 2, vmax: 16,
          nan_color: "red", x: 110, y: 70, w: 40, h: 40},
         {kind: "image", red: G, green: G', blue: 1 - G, alpha: G, x: 160, y: 70}}
scene = {width: 200, height: 120, items: items}
graphics.save(scene, "_tmp_shapes.svg")
graphics.save(scene, "_tmp_shapes.pdf")
graphics.save(scene, "_tmp_shapes.png")
svg = io.read_file("_tmp_shapes.svg")
# Each image is embedded in the SVG as an <image> element.
println(length(split(svg, "<image")) - 1, contains(svg, "<svg"))
println(io.file_exists("_tmp_shapes.pdf"), io.file_exists("_tmp_shapes.png"))
for f in {"_tmp_shapes.svg", "_tmp_shapes.pdf", "_tmp_shapes.png"}
  io.delete_file(f)
end
