import io
p = "_tmp_io.txt"
io.write_file(p, "line 1\nλ = 2π\n")
println(io.file_exists(p))
println(io.read_file(p))
# "line 1\n" is 7 bytes; "λ = 2π\n" is 9 (λ and π take two bytes each).
b = io.read_bytes(p)
println(length(b), b[1], b[length(b)], b[8], b[9])
println(io.delete_file(p), io.delete_file(p), io.file_exists(p))
from io import read_file
println(typeof(read_file))
