p0 = make()
function make() return Point(1, 2) end
record Point
  x: real
  y: real
end
print(p0, typeof(p0))
p = Point(x = 3, y = 4)
print(p.x + p.y)
p.x = 10
print(p, typeof(p.x))
q: Point = {y: 1, x: 2}
print(q)
record Segment
  a: Point; b: Point
  label: string
end
s = Segment(p, q, "s1")
print(s.b.x, typeof(s.b))
s.b.y = 7
print(s.b)
function len2(seg: Segment): real
  return (seg.b.x - seg.a.x)^2 + (seg.b.y - seg.a.y)^2
end
print(len2(s))
print(Point, typeof(Point))
