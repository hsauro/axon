import tools.strings
println(tools.strings.shout("hi"))
import tools.deep.inner
println(tools.deep.inner.where(), tools.strings.shout("x"))
import tools.strings as ts
println(ts.shout("alias"))
from tools.deep.inner import where
println(where())
println(tools)
