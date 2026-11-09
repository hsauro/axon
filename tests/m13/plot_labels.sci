# Titles and labels are strings, and nothing removes one.
import plot
plot.figure(title = "Start")
plot.line([1; 2], [1; 2])
plot.title("Waves")
plot.xlabel("t")
plot.ylabel("y")
println(plot.gcf().title, plot.gcf().xlabel, plot.gcf().ylabel)
plot.title(nothing)
plot.ylabel(nothing)
println(typeof(plot.gcf().title), plot.gcf().xlabel, typeof(plot.gcf().ylabel))
plot.figure()
println(typeof(plot.gcf().title))
