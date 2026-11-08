# graphics.show(scene, data): under a front end (the test runner sets
# AXON_SHOW_DIR) the data is written as JSON next to the PNG, under the same
# name with the extension .json, for the IDE's interactive chart.
import graphics
import io

scene = {width: 60.0, height: 40.0, items: {}}
p = graphics.show(scene, {title: "t", series: {{type: "line", x: [1.0; 2.0], y: [3.0; 4.0]}}})
j = p[1:length(p) - 4] + ".json"
println(io.file_exists(p), io.file_exists(j))
d = io.read_json(j)
println(d.title, d.series[1].type, d.series[1].y')
io.delete_file(p)
io.delete_file(j)

# Without data, only the PNG.
p = graphics.show(scene)
println(io.file_exists(p[1:length(p) - 4] + ".json"))
io.delete_file(p)
