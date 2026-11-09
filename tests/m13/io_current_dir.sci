# io.current_dir and io.set_current_dir: relative paths follow the working
# directory, which a test starts in its own folder.
import io
start = io.current_dir()
println(endswith(start, "m13"), io.file_exists("io_current_dir.sci"))
io.set_current_dir("..")
println(endswith(io.current_dir(), "tests"), io.file_exists("m13/io_current_dir.sci"))
io.set_current_dir("m13")
println(io.current_dir() == start)
io.set_current_dir(start)
println(io.file_exists("io_current_dir.sci"))
