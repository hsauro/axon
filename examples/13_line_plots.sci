## Line plots: sin(x) and its Taylor polynomials, in several line styles.
## Shows dashed and dotted lines, markers on a line, and fixed axis ranges.

import plot

# The Taylor polynomial of sin of the given odd order about 0:
# x - x^3/3! + x^5/5! - ...
function taylor_sin(x, order)
  term = x
  total = x
  for k in 3:2:order
    term = -term .* x .* x / ((k - 1) * k)
    total = total + term
  end
  return total
end

x = linspace(-2 * pi, 2 * pi, 400)
exact = sin(x)

# How far each polynomial is from sin over one period, [-pi, pi].
p = linspace(-pi, pi, 200)
println("order  largest error on [-pi, pi]")
for order in 1:2:9
  err = max(abs(taylor_sin(p, order) - sin(p)))
  println("  " + string(order) + "    " + format(err, 6))
end

# Every line style, plus markers on the order-9 curve at 25 points.
x9 = linspace(-2 * pi, 2 * pi, 25)
plot.figure(title = "sin(x) and its Taylor polynomials", width = 720)
plot.line(x, exact, label = "sin(x)", color = "black", width = 2.5)
plot.line(x, taylor_sin(x, 1), label = "order 1", style = "--")
plot.line(x, taylor_sin(x, 3), label = "order 3", style = ":", width = 2.0)
plot.line(x, taylor_sin(x, 5), label = "order 5", style = "-.")
plot.line(x9, taylor_sin(x9, 9), label = "order 9", marker = "circle", marker_size = 4)
plot.ylim(-2.5, 2.5)          # the polynomials grow fast away from 0
plot.xlabel("x")
plot.ylabel("y")
plot.legend_position("outside")
plot.show()
