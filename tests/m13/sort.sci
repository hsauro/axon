# sort and sortperm: vectors, rows, ranges, lists, order, stability, NaN.
println(isequal(sort([3; 1; 2]), [1; 2; 3]))
println(isequal(sort([3; 1; 2], "descend"), [3; 2; 1]))
println(isequal(sort([3; 1; 2], "ascend"), [1; 2; 3]))
println(eltype(sort([3; 1; 2])), eltype(sort([2.5; 1.0])), eltype(sort([true; false])))
println(isequal(sort([true; false; true]), [false; true; true]))
println(isequal(sort(5:-1:1), [1; 2; 3; 4; 5]))
r = sort([3, 1, 2])
[m, n] = size(r)
println(m, n, r[1], r[3])
println(length(sort([])))

# The argument is not changed, and nothing is copied in place.
v = [4.0; -1.0; 2.0]
w = sort(v)
println(v[1], w[1])

# NaN goes last, ascending and descending.
nan = 0.0 / 0.0
s = sort([2.0; nan; -1.0])
println(s[1], s[2], s[3])
s = sort([2.0; nan; -1.0], "descend")
println(s[1], s[2], s[3])

# Lists: all numbers, or all strings (character-code order).
println(sort({3, 1.5, true}))
println(sort({"pear", "Apple", "fig"}))
println(sort({"pear", "Apple", "fig"}, "descend"))
println(sort({}))

# sortperm: positions that put x in order; stable for equal values.
println(isequal(sortperm([30; 10; 20]), [2; 3; 1]))
println(isequal(sortperm([30; 10; 20], "descend"), [1; 3; 2]))
println(isequal(sortperm([1; 0; 1; 0]), [2; 4; 1; 3]))
println(isequal(sortperm([1; 0; 1; 0], "descend"), [1; 3; 2; 4]))
ages = [41; 29; 35]
println(isequal(ages[sortperm(ages)], sort(ages)))
println(isequal(sortperm({"b", "c", "a"}), [3; 1; 2]))
