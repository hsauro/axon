p = {a: 1.0, b: 0.1}
println(p.a, p.b, typeof(p))
p.c = 0.075
println(p)
p.a = "changed"
println(p.a)
r = {name: "S1", pos: {x: 1, y: 2}}
println(r.pos.y)
r.pos.y = 20
println(r)
e = {end: 3, function: "f", if: true}
println(e.end, e.function, e.if)
println({a: 1, b: 2} == {a: 1, b: 2}, {a: 1, b: 2} == {b: 2, a: 1}, {a: 1} == {a: 1.0}, {a: 1} == {a: 1, b: 2})
