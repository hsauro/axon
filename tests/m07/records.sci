p = {a: 1.0, b: 0.1}
print(p.a, p.b, typeof(p))
p.c = 0.075
print(p)
p.a = "changed"
print(p.a)
r = {name: "S1", pos: {x: 1, y: 2}}
print(r.pos.y)
r.pos.y = 20
print(r)
e = {end: 3, function: "f", if: true}
print(e.end, e.function, e.if)
print({a: 1, b: 2} == {a: 1, b: 2}, {a: 1, b: 2} == {b: 2, a: 1}, {a: 1} == {a: 1.0}, {a: 1} == {a: 1, b: 2})
