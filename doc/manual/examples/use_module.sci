## Using a module of your own: mymodels/kinetics.sci next to this file.

import mymodels.kinetics as kin
from mymodels.kinetics import hill

println(kin.mm(0.5), kin.mm(2.0, vmax = 10.0))
println(hill(0.5, 4))
