#! error: ForeignError
extern "no_such_library"
  function f()
end
f()
