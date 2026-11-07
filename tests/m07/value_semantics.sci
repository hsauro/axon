a = {1, {2, 3}}
b = a
b[2][1] = 20
print(a, b)
r = {m: [1, 2; 3, 4]}
s = r
c0 = __copies()
s.m[1, 1] = 100
print(r.m[1, 1], s.m[1, 1], __copies() - c0)
d = dict("k" => {1, 2})
e = d
e["k"][1] = "x"
print(d, e)
function modify(lst)
  lst[1] = "inside"
  return lst
end
orig = {1, 2}
mod = modify(orig)
print(orig, mod)
function rename(rec)
  rec.name = "new"
  return rec
end
x = {name: "old"}
y = rename(x)
print(x.name, y.name)
