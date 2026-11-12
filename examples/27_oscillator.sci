## A chemical oscillator: time course and phase plot
##
## The Brusselator, a classic model of an oscillating reaction, written in
## Antimony and simulated with the antimony module. X is made at a constant
## rate, turned into Y, and Y is turned back into X in a step that X itself
## speeds up (autocatalysis, rate X^2 Y). For b > 1 + a^2 the concentrations
## never settle: they approach a limit cycle. The figure shows the time
## course above and the phase plot, Y against X, below, where the limit
## cycle is the closed loop the path winds onto. Inside it lies the steady
## state (X = a, Y = b/a), which antimony.steady_state finds; it is
## unstable, so the path moves away from it.

import antimony
import plot

model = antimony.load("""
    J0: -> X;      a          // X is made at a constant rate
    J1: X -> Y;    b*X        // X turns into Y
    J2: Y -> X;    X^2*Y      // autocatalysis: X speeds up its own making
    J3: X -> ;     X          // X is removed

    X = 1; Y = 1
    a = 1; b = 3""")

sol = antimony.simulate(model, 40.0, points = 4001)
x = sol.y[1, :]
y = sol.y[2, :]

plot.figure(width = 640, height = 720, title = "The Brusselator, a = 1, b = 3")

plot.subplot(2, 1, 1)
plot.line(sol.t, x, label = "X")
plot.line(sol.t, y, label = "Y")
plot.title("Time course")
plot.xlabel("time")
plot.ylabel("concentration")

# The steady state, where every rate balances: X = 1, Y = 3 here.
ss = antimony.steady_state(model)
println("steady state: X =", format(ss.y[1], 4), "Y =", format(ss.y[2], 4))

plot.subplot(2, 1, 2)
plot.line(x, y, label = "path")
plot.scatter([x[1]], [y[1]], label = "start")
plot.scatter([ss.y[1]], [ss.y[2]], label = "steady state (unstable)")
plot.title("Phase plot")
plot.xlabel("X")
plot.ylabel("Y")

plot.show()
