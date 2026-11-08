#! error: UserError
import time
function boom(x)
  error("bad")
end
time.elapsed(boom, 7)
