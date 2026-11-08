# graphics.show and plot.show. The test runner sets AXON_SHOW_DIR, so the
# figures are written there (and announced on stderr) instead of opening a
# viewer.
import graphics
import plot
import io

p = graphics.show({width: 120.0, height: 80.0, items: {
  {kind: "rect", x: 10.0, y: 10.0, w: 50.0, h: 30.0, fill: "blue"}}})
println(typeof(p), io.file_exists(p))
b = io.read_bytes(p)
println(b[2:4]', b[17:24]')
io.delete_file(p)

plot.line([1.0; 2.0; 3.0], [3.0; 1.0; 2.0])
println(plot.show())
println("done")
