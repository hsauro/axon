# Rule 6: a named top-level function reads module variables but does not
# assign them without global.
setting = "module"
function reader() return setting end
function writer()
  setting = "local"
  return setting
end
print(reader(), writer(), setting)
function global_writer()
  global setting
  setting = "changed by global"
end
global_writer()
print(setting)
function creator()
  global created = 42
end
creator()
print(created)
# A top-level lambda is a closure, so it does assign the module variable
lam = function() setting = "changed by lambda" end
lam()
print(setting)
# A named function nested in a function is a closure of that function
function host()
  v = 1
  function nested() v = v + 1 end
  nested()
  return v
end
print(host())
