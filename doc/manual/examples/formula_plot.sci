## Plotting formulas given as text, such as typed by a user or read from a file.

import plot

formulas = {"sin(x)", "x .^ 2 / 10", "exp(-x) .* cos(3 * x)"}
x = linspace(0.0, 2 * pi, 200)

plot.figure(width = 460, height = 300, title = "Formulas from text")
for text in formulas
  f = parse_function("x", text)
  plot.line(x, f(x), label = text)
end
plot.legend_position("outside")
plot.save("../figures/formulas.pdf")

# A bad formula is reported clearly, and the program can carry on.
for text in {"2 * sinn(x)", "(x + 1"}
  try
    parse_function("x", text)
  catch err
    println(err.kind + ": " + err.message)
  end
end
