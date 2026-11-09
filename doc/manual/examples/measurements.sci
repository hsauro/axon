## Measurements in a CSV file: write them, read them back, plot them.

import io
import plot
import random

# Simulated readings: the temperature of a cooling cup every 2 minutes.
random.seed(3)
t = [range(0, 30, 2)]
temp = 20.0 + 60.0 * exp(-t / 12.0) + random.normal(0.0, 0.8, length(t))
temp = round(temp * 10) / 10      # to 0.1 degree, as the thermometer reads
io.write_csv("cooling.csv", [t, temp], {"minutes", "celsius"})

# What the file looks like: a header, then one line per reading.
lines = io.read_lines("cooling.csv")
for k in 1:4
  println(lines[k])
end

# Read it back: names from the header, the numbers as a matrix.
table = io.read_csv("cooling.csv")
println(table.names)
[rows, cols] = size(table.data)
println(rows, "rows,", cols, "columns")

x = table.data[:, 1]
y = table.data[:, 2]
println("first:", format(y[1], 1), "last:", format(y[end], 1))

plot.figure(width = 460, height = 300, title = "A cooling cup")
plot.scatter(x, y, label = "measured")
plot.xlabel(table.names[1])
plot.ylabel(table.names[2])
plot.save("../figures/cooling.pdf")
io.delete_file("cooling.csv")
