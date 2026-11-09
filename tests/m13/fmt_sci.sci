# fmt.set_sci: the limits of scientific notation in displayed reals.
import fmt
println(0.0001, 0.00009999, 1e14, 1e15)
fmt.set_sci(1e-6, 1e9)
println(0.00001, 0.0000001, 123456789.0, 1e9, -2e9)
println([0.00002; 5e10])
println(fmt.number(0.00001), fmt.number(2e9))
fmt.set_sci(1, 1)
println(2.5, 0.5, 1.0)
fmt.set_sci(5e-3, 1e15)
println(0.004, 0.006, 0.0)
# With fixed decimals only the upper limit applies.
fmt.set_sci(1e-8, 1e6)
fmt.set_decimals(3)
println(0.00001, 2e6)
fmt.set_decimals()
fmt.set_sci()
println(0.00001, 1e15)
# string(x) follows the setting, as every display form does.
fmt.set_sci(1, 1)
try
  error("x is " + string(2.5))
catch err
  println(err.message)
end
fmt.set_sci()
