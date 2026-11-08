# io.write_json and io.read_json: values to JSON text and back.
import io

v = {name: "S1", n: 3, x: 0.1, whole: 2.0, ok: true, none: nothing,
     v: [1.0; 2.5; 0.0 / 0.0], m: [1, 2; 3, 4], l: {1, "a b", [1; 2]},
     d: dict("a b" => 1, "c" => 2.5), r: 1:3, s: "say \"hi\"\n"}
io.write_json("_tmp_json.json", v)
println(io.read_file("_tmp_json.json"))

# Read back: records stay records, numbers keep int or real, arrays of
# numbers become vectors (null as NaN) and rows of them matrices; a
# dictionary with a key that is not a name stays a dictionary.
w = io.read_json("_tmp_json.json")
println(typeof(w), w.name, w.n, typeof(w.n), w.x == 0.1, w.whole, typeof(w.whole))
println(w.ok, w.none, w.v', w.m, w.l, w.d, w.r', w.s == "say \"hi\"\n")
io.delete_file("_tmp_json.json")

# Reals read back exactly.
io.write_json("_tmp_json.json", [1e300; 5e-324; 0.30000000000000004; -1.5e-7])
println(isequal(io.read_json("_tmp_json.json"), [1e300; 5e-324; 0.30000000000000004; -1.5e-7]))
io.delete_file("_tmp_json.json")

# Plain JSON from elsewhere: mixed arrays are lists, empty ones too.
io.write_file("_tmp_json.json", "{\"a\": [1, \"x\", null], \"b\": [], \"c\": {\"k\": -2}}")
u = io.read_json("_tmp_json.json")
println(u.a, u.b, u.c.k)
io.delete_file("_tmp_json.json")
