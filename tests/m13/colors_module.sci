# The colors module: the 140 web colour names as RGB, found ignoring case,
# spaces and underscores, with "grey" for "gray".
import colors

c = colors.rgb("AliceBlue")             # 240, 248, 255 over 255
println(c[1] == 240 / 255.0, c[3], size(c, 1), size(c, 2))
v = colors.rgb255("alice blue")
println(v[1], v[2], v[3])
println(colors.hex("light_grey"), colors.hex("LightGray"), colors.hex("cornflowerblue"))
println(colors.has("Cyan"), colors.has("Bluish"), colors.has(3))
n = colors.names()
println(length(n), n[1], n[end])
a = colors.rgb("Red", alpha = 0.5)
println(length(a), a[1], a[2], a[4])

# hsv2rgb: red, green, blue at hues 0, 1/3, 2/3; hue wraps round; grey when s = 0
for h in {0, 1 / 3, 2 / 3, 1.0, -0.5}
  c = colors.hsv2rgb(h, 1, 1)
  println(c[1], c[2], c[3])
end
c = colors.hsv2rgb(0.25, 0.5, 0.8)          # k = 1, f = 0.5: [q, v, p]
println(c[1], c[2], c[3], size(c, 1), size(c, 2))
c = colors.hsv2rgb(0.7, 0, 0.5)
println(c[1], c[2], c[3])
a = colors.hsv2rgb(0, 1, 1, alpha = 0.25)
println(length(a), a[4])
try
  colors.hsv2rgb("red", 1, 1)
catch err
  println(err.kind, err.message)
end
try
  colors.hsv2rgb(0.5, 2, 1)
catch err
  println(err.kind, err.message)
end

try
  colors.rgb("Bluish")
catch err
  println(err.kind, err.message)
end
try
  colors.hex(42)
catch err
  println(err.kind, err.message)
end
try
  colors.rgb("Red", alpha = 2)
catch err
  println(err.kind, err.message)
end
