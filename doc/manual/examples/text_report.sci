## Tidying messy text and printing an aligned report.

# Species names typed in by hand: stray spaces, mixed case, a note or two.
raw = {"  e. COLI ", "Bacillus subtilis", " yeast (S. cerevisiae)", "e. coli",
       "BACILLUS SUBTILIS  ", "Pseudomonas"}

# The same name always written the same way: trimmed, first letter capital.
function tidy(name)
  s = lower(trim(name))
  # Drop a note in brackets, if any.
  k = find(s, "(")
  if k > 0
    s = rtrim(s[1:k - 1])
  end
  return upper(s[1]) + s[2:end]
end

# Count each tidied name.
counts = dict()
for name in raw
  key = tidy(name)
  counts[key] = get(counts, key, 0) + 1
end

# A name padded with spaces to a given width, so columns line up.
function pad(s, width)
  return s + repeat(" ", width - length(s))
end

names = sort(keys(counts))
width = 0
for n in names
  width = max(width, length(n))
end
println(pad("Organism", width) + "  Count")
println(repeat("-", width + 7))
for n in names
  println(pad(n, width) + "  " + string(counts[n]))
end

# Searching: which names mention a genus, and where.
for n in names
  if startswith(n, "B") or contains(n, "coli")
    println(n, "matches; \"i\" first at", find(n, "i"))
  end
end
println(replace("E. coli K-12", "K-12", "MG1655"))
