# io.read_lines, io.write_csv and io.read_csv.
import io

io.write_file("_tmp_lines.txt", "first\u{D}\nsecond\n\nfourth\n")
println(io.read_lines("_tmp_lines.txt"))
io.delete_file("_tmp_lines.txt")

# A table with a header; values read back exactly, NaN included.
A = [1.0, 2.5; 3.0, 0.0 / 0.0; 0.1, 1e-20]
io.write_csv("_tmp_t.csv", A, {"time", "conc, mM"})
println(io.read_lines("_tmp_t.csv"))
t = io.read_csv("_tmp_t.csv")
println(t.names)
[m, n] = size(t.data)
println(m, n, t.data[1, 2], t.data[3, 1] == 0.1, t.data[3, 2] == 1e-20, t.data[2, 2] == t.data[2, 2])
io.delete_file("_tmp_t.csv")

# No header; a vector is written as one column; ints stay ints in the file.
io.write_csv("_tmp_n.csv", [1; 2; 3])
println(io.read_lines("_tmp_n.csv"))
t = io.read_csv("_tmp_n.csv")
println(typeof(t.names), size(t.data, 1), size(t.data, 2), t.data[3, 1])
io.delete_file("_tmp_n.csv")

# Another separator, blank lines, quoted fields and an empty field (NaN).
io.write_file("_tmp_s.csv", "\"a;1\";b\n1;2\n\n3;\n")
t = io.read_csv("_tmp_s.csv", ";")
println(t.names, t.data[1, 2], t.data[2, 1], t.data[2, 2] == t.data[2, 2])
io.write_csv("_tmp_s.csv", t.data, t.names, ";")
println(io.read_lines("_tmp_s.csv"))
io.delete_file("_tmp_s.csv")
