#! error: DomainError
import ode
s = ode.solve(function(t, y) return -y end, 1.0, [0, 1])
y = s.at(5.0)
