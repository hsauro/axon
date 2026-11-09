# atexit: functions run when the program ends, the last registered first.
atexit(function()
  println("registered first, runs last")
end)
count = 0
note = function()
  println("count at exit:", count)
end
atexit(note)
count = 3
println("end of the program")
