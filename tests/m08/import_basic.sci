import geometry
print(geometry.area(2))
print(typeof(geometry), geometry)
import geometry as g
print(g.area(1), g == geometry)
from geometry import area, Point
print(area(3))
p = Point(1, 2)
print(p, typeof(p))
