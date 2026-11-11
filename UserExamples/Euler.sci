
# Euler method solver applied to Newton's law of cooling.
# Integrates dT/dt = -k*(T - T_env) from t=a to t=b with fixed step h,
# printing and plotting the temperature T(t) over time.

import plot

function newtoncooling(time, temp)
  return -0.07 * (temp - 20)
end

function euler(f, y0, a, b, h)
  ts = vector()
  ys = vector()

  t = a
  y = y0
  while t <= b
    println(format(t, 3), format(y, 3))
    ts = append(ts, t)
    ys = append(ys, y)

    t = t + h
    y = y + h * f(t, y)
  end

  return ts, ys
end


[ts, ys] = euler(newtoncooling, 100, 0, 100, 10)

plot.line(ts, ys, label="Euler approximation")
plot.xlabel("time")
plot.ylabel("temperature")
plot.title("Newton's Law of Cooling - Euler Method")
