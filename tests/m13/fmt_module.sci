# The fmt module: set_header, matrix and number.
import fmt

A = [1, 2, 3; 4, 5, 6]
fmt.set_header(false)
println(A)
println([1.5; 2.0])
println(zeros(0))
fmt.set_header()
println(A)

B = [1.5, -22.25; 3.0, 4.125]
println(fmt.matrix(B))
println(fmt.matrix(B, decimals = 2))
println(fmt.matrix(B, decimals = 1, sep = ", ", align = false))
println(fmt.matrix(B, header = true))
println(fmt.matrix([1; 20; 300]))
println(fmt.matrix([1, 2, 3], sep = "\t"))
println(fmt.matrix(1:3))
# Every row and column, whatever set_size says.
fmt.set_size(2, 2)
println(length(split(fmt.matrix(zeros(4, 4)), "\n")))
fmt.set_size()

println(fmt.number(pi), fmt.number(pi, decimals = 3), fmt.number(pi, digits = 4))
println(fmt.number(12345.678, sci = true, decimals = 2), fmt.number(0.00012, sci = true))
println("[" + fmt.number(42, width = 6) + "]", "[" + fmt.number(-1.5, decimals = 2, width = 7) + "]")
println(fmt.number(7), fmt.number(true), fmt.number(2.0))
# Independent of the display settings.
fmt.set_decimals(2)
println(1 / 3, fmt.number(1 / 3))
fmt.set_decimals()
