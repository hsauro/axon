## Bar charts: named categories, side-by-side groups, and values below zero.
## Two figures are saved as PNG files; the second is shown in the plot pane.

import plot

# ---------------------------------------------------------------- data
# Monthly rainfall in mm for two towns (illustrative numbers).
months = {"Jan", "Feb", "Mar", "Apr", "May", "Jun",
          "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"}
north = [142; 110; 98; 71; 58; 42; 30; 35; 61; 104; 150; 160]
south = [ 81;  69; 60; 45; 40; 22; 12; 15; 33;  58;  86;  92]

# Summary: the wettest month and the yearly totals.
wettest = 1
for k in 2:12
  if north[k] > north[wettest] wettest = k end
end
println("wettest month in the north:", months[wettest], north[wettest], "mm")
println("yearly totals:", sum(north), "mm north,", sum(south), "mm south")

# ---------------------------------------------------------------- figure 1
# Values below zero: each month's difference from the yearly average. A bar
# can only have one colour, so the wetter and drier months are drawn as two
# series, each with zero for the other months.
diff = south - mean(south)
wet = zeros(12)
dry = zeros(12)
for k in 1:12
  if diff[k] >= 0
    wet[k] = diff[k]
  else
    dry[k] = diff[k]
  end
end
plot.figure(title = "South: rainfall above and below the monthly average")
plot.bar(months, wet, label = "wetter", color = "#1f77b4")
plot.bar(months, dry, label = "drier", color = "#d62728")
plot.ylabel("mm from average")
plot.save("rainfall_difference.png")

# ---------------------------------------------------------------- figure 2
# Two towns side by side: each month at 1, 2, ..., 12, the bars narrowed and
# shifted either side of it, and the months named with xticks.
x = linspace(1.0, 12.0, 12)
plot.figure(title = "Monthly rainfall", width = 760)
plot.bar(x - 0.2, north, width = 0.4, label = "north")
plot.bar(x + 0.2, south, width = 0.4, label = "south")
plot.xticks(x, months)
plot.ylabel("mm")
plot.save("rainfall.png")
println("saved rainfall_difference.png and rainfall.png")
plot.show()
