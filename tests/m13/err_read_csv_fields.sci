#! error: IOError
# A line with a different number of fields than the table.
import io
io.write_file("_tmp_bad.csv", "1,2\n3\n")
try
  io.read_csv("_tmp_bad.csv")
catch err
  io.delete_file("_tmp_bad.csv")
  error(err)
end
