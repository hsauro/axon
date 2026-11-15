# antimony.simulate with events against libRoadRunner: the models of
# tools/tellurium_events_check.py (a parameter changed at a time, a species
# reset at a threshold again and again, a boundary species raised for a
# while, a trigger of two conditions, and one event firing another), which
# wrote tellurium/events_reference.json with Tellurium's values at evenly
# spaced times, none of them the moment of an event. Both sides solve to a
# relative tolerance of 1e-6, so they agree to about 1e-6.
import antimony
import io

function index(names, name)
  for k in 1:length(names)
    if names[k] == name return k end
  end
  error("NameError", "no species " + name)
end

ref = io.read_json("tellurium/events_reference.json")
for r in ref.models
  sol = antimony.simulate(antimony.load(r.text), r.t_end, points = r.points)
  times = linspace(0, r.t_end, r.points)
  worst = 0.0
  for i in 1:length(times)
    y = sol.at(times[i])
    for j in 1:length(r.species)
      want = r.values[i, j]
      got = y[index(sol.names, r.species[j])]
      worst = max(worst, abs(got - want) / max(1.0, abs(want)))
    end
  end
  println(r.name, worst < 2e-5)
end
