import tools.strings
print(tools.strings.shout("hi"))
import tools.deep.inner
print(tools.deep.inner.where(), tools.strings.shout("x"))
import tools.strings as ts
print(ts.shout("alias"))
from tools.deep.inner import where
print(where())
print(tools)
