# fmt.matrix with row and column names: tables such as control coefficients.
import fmt

A = [1.5, -2.0, 300.25; 0.5, 0.0, -1.0]
println(fmt.matrix(A, rows = {"J0", "Reaction1"}, cols = {"S1", "S2", "S3"}))
# A name wider than its column widens it; header still comes first.
println(fmt.matrix(A, cols = {"a", "bbbbbbbbbb", "c"}, header = true))
println(fmt.matrix(A, rows = {"J0", "J1"}, decimals = 2))
# A vector is a column.
println(fmt.matrix([1.0; 2.0], rows = {"x", "y"}, cols = {"value"}))
# Unaligned, the names are fields like the entries (CSV).
println(fmt.matrix(A, rows = {"J0", "J1"}, cols = {"S1", "S2", "S3"}, align = false, sep = ","))

try
  fmt.matrix(A, rows = {"J0"})
catch err
  println(err.kind, err.message)
end
try
  fmt.matrix(A, cols = "S1")
catch err
  println(err.kind, err.message)
end
try
  fmt.matrix(A, cols = {"S1", 2, "S3"})
catch err
  println(err.kind, err.message)
end
