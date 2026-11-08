import plot
import io

# Counts per bin: each bin holds its left edge, the last also its right;
# values outside the edges and NaN are not counted.
plot.figure()
r = plot.hist([1.0; 2.0; 2.0; 3.0; 0.0 / 0.0; 9.0; 0.5], bins = [1.0, 2.0, 3.0])
println(r.counts')
println(r.edges')
println(typeof(r.counts), eltype(r.counts), isequal(r.heights, [1.0; 3.0]))

# A number of bins spans the data in equal widths.
r = plot.hist([0; 1; 2; 3; 4; 5; 6; 7; 8; 10], bins = 5)
println(r.counts')
println(r.edges')
# One distinct value: a bin of width 1 around it.
println(plot.hist([3.0; 3.0], bins = 2).edges')

# hist_density: the bars' total area is 1.
d = plot.hist_density([0.0; 0.5; 1.0; 1.5; 3.0], bins = [0.0, 1.0, 2.0, 4.0])
println(d.counts')
println(d.heights')

# A figure with bars renders, and its legend names them.
plot.figure(title = "Histogram")
plot.hist(linspace(0.0, 1.0, 50), bins = 10, label = "values")
plot.save("_tmp_hist.svg")
s = io.read_file("_tmp_hist.svg")
println(length(s) > 0, io.delete_file("_tmp_hist.svg"))
