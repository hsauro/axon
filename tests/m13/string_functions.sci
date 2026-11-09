# upper, lower, ltrim, rtrim, contains, startswith, endswith, find, replace, repeat.
println("[" + ltrim("  a b  ") + "]", "[" + rtrim("  a b  ") + "]", "[" + ltrim("\t\nx") + "]")
println(upper("Hello, world 1"), lower("MiXeD"))
println(contains("abc", "bc"), contains("abc", "x"), contains("abc", ""), contains("", "a"))
println(startswith("data.csv", "data"), startswith("data.csv", "csv"), startswith("a", ""))
println(endswith("data.csv", ".csv"), endswith("a", "ab"), endswith("a", ""))
println(find("banana", "an"), find("banana", "an", 3), find("banana", "an", 5), find("banana", "x"))
println(find("abc", ""), find("abc", "", 3), find("abc", "", 4), find("abc", "", 5), find("abc", "c", 10))
# Positions count characters, as indexing does, beyond the basic plane too.
s = "a\u{1F600}bc"
println(find(s, "b"), s[find(s, "b")], find(s, "c", 4))
println(replace("a-b-c", "-", ", "), replace("aaa", "a", "bb"), replace("abc", "x", "y"))
println(repeat("ab", 3), "[" + repeat("x", 0) + "]", length(repeat("-", 40)))

# Finding every occurrence with the start position.
k = find("abracadabra", "a")
hits = {}
while k > 0
  hits = append(hits, k)
  k = find("abracadabra", "a", k + 1)
end
println(hits)
