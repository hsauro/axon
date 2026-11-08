species = {
  {name: "S1", init: 10.0, units: "mM"},
  {name: "S2", init: 0.0,  units: "mM"}
}

species[2].name           # "S2"
for s in species
  println(s.name, s.init)
end
println(species[2].name)
