# Triple-quoted strings: across lines, as written, shared indentation removed.
source = """2 A + 3 B -> C; k1*A*B;
C -> A + B; k2*C;
k2 = 0.05;"""
println(source)
println(length(split(source, "\n")), contains(source, "\n"))

# A line break right after the opening quotes is dropped, and so is the
# indentation the lines share; the closing quotes' own line counts too.
function text()
  return """
    first
      second
    third
    """
end
t = text()
println(startswith(t, "first"), endswith(t, "third\n"), contains(t, "\n  second\n"))

# Quotes need no escape; escapes still work.
q = """She said "yes" \u{3B1}\t."""
println(q)
println("""""" == "", """a""" == "a", """\"""" == "\"")

# Blank lines inside do not limit the indentation.
b = """
  a

  b"""
println(b == "a\n\nb")
