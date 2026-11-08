#! error: IOError
import io
io.write_file("_tmp_bad.json", "{oops")
try
  io.read_json("_tmp_bad.json")
catch e
  io.delete_file("_tmp_bad.json")
  error(e.kind, e.message)
end
