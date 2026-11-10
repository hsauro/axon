#! error: ArgumentError
import antimony
m = antimony.load("A -> B; k*A; A = 1; k = 1")
s = antimony.steady_state(m, method = "simulate")
