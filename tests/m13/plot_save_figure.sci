# plot.save(path, figure = f): a figure record other than the current one,
# such as a grid kept from plot.gcf(), or one read back from JSON.
import plot
import io

plot.figure(title = "Kept")
plot.subplot(1, 2, 1)
plot.line([1; 2; 3], [3; 1; 2])
plot.title("Left")
plot.subplot(1, 2, 2)
plot.bar([2; 4])
plot.title("Right")
kept = plot.gcf()

plot.figure()
plot.scatter([1; 2], [1; 2])
plot.title("Current")

# Saving the kept grid leaves the current figure as it is.
plot.save("_tmp_kept.svg", figure = kept)
svg = io.read_file("_tmp_kept.svg")
println(length(svg) > 1000, plot.gcf().title)

# Through JSON and back, as the IDE's Save... does.
io.write_json("_tmp_kept.json", kept)
plot.save("_tmp_kept2.svg", figure = io.read_json("_tmp_kept.json"))
# The same drawing (only the numbering of SVG clip ids may differ).
println(length(io.read_file("_tmp_kept2.svg")) == length(svg))

# A single figure works too.
single = plot.gcf()
plot.save("_tmp_single.svg", figure = single)
println(io.file_exists("_tmp_single.svg"))

for f in {"_tmp_kept.svg", "_tmp_kept2.svg", "_tmp_kept.json", "_tmp_single.svg"}
  io.delete_file(f)
end
plot.save("_tmp_current.svg")
io.delete_file("_tmp_current.svg")
