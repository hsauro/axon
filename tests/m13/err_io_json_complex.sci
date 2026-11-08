#! error: TypeError
import io
io.write_json("_tmp_never.json", {z: 1 + 2i})
