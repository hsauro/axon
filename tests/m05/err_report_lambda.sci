#! error: TypeError
apply = function(f) return f() end
apply(function() return "a" + 1 end)
