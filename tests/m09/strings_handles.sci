extern "axontest"
  function str_len(s: cstring): int32
  function greeting(): cstring
  function null_string(): cstring
  function make_handle(v: int32): ptr void
  function handle_value(h: ptr void): int32
  function free_handle(h: ptr void)
  function null_ptr(): ptr void
end
print(str_len("héllo"), str_len(""), str_len(nothing))
print(greeting(), null_string())
h = make_handle(5)
print(typeof(h), handle_value(h), h == h, null_ptr())
free_handle(h)
