import geometry
println(geometry.area(2))
println(typeof(geometry), geometry)
import geometry as g
println(g.area(1), g == geometry)
from geometry import area, Point
println(area(3))
p = Point(1, 2)
println(p, typeof(p))
