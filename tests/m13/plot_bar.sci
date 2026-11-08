import plot
import io

function contains(s, t)
  n = length(t)
  for k in 1:length(s) - n + 1
    if s[k:k + n - 1] == t return true end
  end
  return false
end

# Numeric positions: each bar is width wide, centred on its x.
plot.figure()
plot.bar([1.0; 3.0], [2.0; -1.0], width = 0.5)
s = plot.gcf().series[1]
println(s.type, s.left', s.right', s.heights')
println(typeof(plot.gcf().xcategories))

# Categories: bars at 1, 2, 3 (default width 0.8), named on the x axis.
plot.figure(title = "Fruit")
plot.bar({"apples", "pears", "plums"}, [12, 7, 9], label = "sold")
f = plot.gcf()
println(f.xcategories, f.series[1].left')
# A second series over the same categories is allowed.
plot.bar({"apples", "pears", "plums"}, [1, 2, 3])
plot.save("_tmp_bar.svg")
t = io.read_file("_tmp_bar.svg")
println(contains(t, "apples"), contains(t, "plums"), contains(t, "sold"))
println(io.delete_file("_tmp_bar.svg"))

# xticks: labels at chosen positions, replacing round numbers and categories;
# ticks outside the axis range are left out when drawing.
plot.figure()
plot.bar([1.0; 2.0] - 0.2, [3.0; 4.0], width = 0.4)
plot.bar([1.0; 2.0] + 0.2, [1.0; 2.0], width = 0.4)
plot.xticks([1.0; 2.0; 99.0], {"first", "second", "far"})
f = plot.gcf()
println(f.xticks.positions', f.xticks.labels)
plot.save("_tmp_ticks.svg")
t = io.read_file("_tmp_ticks.svg")
println(contains(t, "second"), contains(t, "far"))
println(io.delete_file("_tmp_ticks.svg"))
