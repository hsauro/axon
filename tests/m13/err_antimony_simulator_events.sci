#! error: NameError
# A simulation in steps of a model with events: set still rejects a name the
# model does not have.
import antimony
m = antimony.load("J1: -> S1; k1; k1 = 1; S1 = 0; at (time > 1): k1 = 0")
sim = antimony.simulator(m)
sim = antimony.step(sim, 2.0)
sim = antimony.set(sim, "k2", 1.0)
