# Events in antimony.simulate, against values worked out by hand.
import antimony
from testing import approx

# A parameter changed at t = 10. S1' = k1 - k2 S1 from 0 gives
# S1(10) = 10 (1 - e^-1), and after k1 becomes 5,
# S1(t) = 50 + (S1(10) - 50) e^(-0.1 (t - 10)).
m = antimony.load("""
  J1: -> S1; k1
  J2: S1 -> ; k2*S1
  k1 = 1; k2 = 0.1; S1 = 0
  E1: at (time > 10): k1 = 5
""")
e = m.events[1]
println(length(m.events), e.name, e.trigger, e.assignments)
sol = antimony.simulate(m, 20, points = 5)
s10 = 10 * (1 - exp(-1))
println(sol.status, approx(sol.t_events[1][1], 10.0, tol = 1e-9))
println(approx(sol.at(20.0)[1], 50 + (s10 - 50) * exp(-1), tol = 1e-6))
# The five times, and the event's time twice: before and after.
println(length(sol.t), approx(sol.t[4], 10.0, tol = 1e-9), approx(sol.y[1, 4], s10, tol = 1e-6))

# A species reset to 0 each time it passes 2: it rises at 1 per unit time,
# so the (unnamed) event fires at t = 2 and t = 4.
saw = antimony.load("J1: -> S1; k1; k1 = 1; S1 = 0; at (S1 > 2): S1 = 0")
s = antimony.simulate(saw, 5, points = 6)
println(saw.events[1].name, approx(s.t_events[1], [2.0; 4.0], tol = 1e-9))
println(approx(s.at(5.0)[1], 1.0, tol = 1e-9), approx(s.y_events[1][1, :], [2.0; 2.0], tol = 1e-9))

# A trigger that is already true at the start does not fire then.
start = antimony.load("J1: -> S1; k1; k1 = 1; S1 = 0; at (S1 > -1): k1 = 100")
r = antimony.simulate(start, 5, points = 2)
println(length(r.t_events[1]), approx(r.y[1, end], 5.0, tol = 1e-9))

# Two conditions: S1 rises at 1 per unit time and is halved whenever it
# passes 2.5 after t = 1: at t = 2.5 (to 1.25) and t = 3.75.
both = antimony.load("J1: -> S1; k1; k1 = 1; S1 = 0; at (time > 1 && S1 > 2.5): S1 = S1 / 2")
b = antimony.simulate(both, 4, points = 5)
println(approx(b.t_events[1], [2.5; 3.75], tol = 1e-9), approx(b.at(4.0)[1], 1.5, tol = 1e-9))

# One event's assignment fires another at the same time, with the stiff
# solver: at t = 2, E1 stops S1 at 2 and sets A to 10, and E2 copies S1 to B.
cascade = antimony.load("""
  J1: -> S1; k1
  J2: A -> ; 0*A
  J3: B -> ; 0*B
  k1 = 1; S1 = 0; A = 0; B = 0
  E1: at (time > 2): k1 = 0, A = 10
  E2: at (A > 5): B = S1
""")
c = antimony.simulate(cascade, 4, points = 3, method = "bdf")
println(c.names, approx(c.y[:, end], [2.0; 10.0; 2.0], tol = 1e-6))
println(approx(c.t_events[1][1], 2.0, tol = 1e-6), approx(c.t_events[2][1], 2.0, tol = 1e-6))

# Events that fire together all use the values from before any of their
# assignments: E2 copies k1's old value, 1.
together = antimony.load("""
  J1: -> S1; k1
  J2: S2 -> ; 0*S2
  k1 = 1; S1 = 0; S2 = 0
  E1: at (time > 1): k1 = 0
  E2: at (time > 1): S2 = k1
""")
t = antimony.simulate(together, 2, points = 3)
println(approx(t.y[:, end], [1.0; 1.0], tol = 1e-6))

# A boundary species changed by an event: the inflow doubles at t = 1.
pulse = antimony.load("$X0 -> S1; X0; X0 = 1; S1 = 0; at (time > 1): X0 = 2")
println(approx(antimony.simulate(pulse, 3, points = 4).y[1, end], 5.0, tol = 1e-6))

# In steps: the sawtooth in steps of 0.5. The event fires in the steps that
# reach t = 2 and t = 4, and sim.fired lists it there.
sim = antimony.simulator(saw)
seen = {}
for k in 1:10
  sim = antimony.step(sim, 0.5)
  for f in sim.fired
    seen = append(seen, f.name + " at " + format(f.t, 3))
  end
end
println(seen, approx(antimony.value(sim, "S1"), 1.0, tol = 1e-9))

# A value set between steps that makes a trigger true fires its event at the
# start of the next step: S1 set to 3 at t = 0.5 is emptied at once.
sim = antimony.simulator(saw)
sim = antimony.step(sim, 0.5)
sim = antimony.set(sim, "S1", 3.0)
sim = antimony.step(sim, 0.5)
println(length(sim.fired), sim.fired[1].t, approx(antimony.value(sim, "S1"), 0.5, tol = 1e-9))

# The parameter switched at t = 10, in steps of 5 with the stiff solver,
# reaches the value simulate gave.
sim = antimony.simulator(m, method = "bdf")
for k in 1:4
  sim = antimony.step(sim, 5.0)
end
println(sim.t, approx(antimony.value(sim, "S1"), 50 + (s10 - 50) * exp(-1), tol = 1e-5))
