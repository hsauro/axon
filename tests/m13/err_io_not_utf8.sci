#! error: IOError
# A PNG is not UTF-8 text.
import io
import graphics
graphics.save({width: 10.0, height: 10.0, items: {}}, "_tmp_bin.png")
try
  s = io.read_file("_tmp_bin.png")
catch e
  io.delete_file("_tmp_bin.png")
  error(e)
end
