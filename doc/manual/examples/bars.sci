## Bar charts: heights alone, named categories, and groups side by side.

import plot

plot.figure(width = 760, height = 280)

# Heights alone: the bars go at 1, 2, 3, ...
plot.subplot(1, 3, 1)
plot.bar([3; 5; 2; 6])
plot.title("bar(y)")

# Named categories label the x axis.
plot.subplot(1, 3, 2)
plot.bar({"A", "C", "G", "T"}, [12; 7; 9; 15], color = "#2ca02c")
plot.title("Categories")

# Two groups side by side: shift x and narrow the bars, then name the ticks.
plot.subplot(1, 3, 3)
x = [1; 2; 3]
plot.bar(x - 0.2, [4; 6; 5], width = 0.4, label = "2024")
plot.bar(x + 0.2, [5; 7; 3], width = 0.4, label = "2025")
plot.xticks(x, {"North", "South", "West"})
plot.title("Groups")

plot.save("../figures/bars.pdf")
