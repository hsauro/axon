import draw

## Computes the red, green and blue channel matrices for the field,
## returned as a record {red, green, blue} of real matrices (values 0..1)
## ready for draw.image_rgb.
## Row 1 is y1 = 0 (top row of the image), column 1 is x1 = 0.
## Each pixel is the average of n x n samples spread over it, which smooths
## the edges where a colour wraps round. The fine rings seen with n = 1 come
## from sampling (the blue byte wraps many times between neighbouring
## pixels), so averaging smooths them away as well.

## Original BASIC256 program from https://www.imaginary.org/gallery/basic-256-artworks

function rainbow_colors(w, h, n)
  j = w * 0.5
  k = h * 0.5
  green = 32768.0            # BASIC256 "green" constant: packed RGB(0,128,0); adjust if different

  rows = int(h) + 1         # y1 runs 0..h inclusive
  cols = int(w) + 1         # x1 runs 0..w inclusive
  red = zeros(rows, cols)
  grn = zeros(rows, cols)
  blu = zeros(rows, cols)

  for col in 1:cols
    for row in 1:rows
      r = 0.0
      g = 0.0
      b = 0.0
      for a in 1:n
        x1 = col - 1 + (a - 0.5) / n - 0.5
        xj = (x1 - j)^2.0
        for s in 1:n
          y1 = row - 1 + (s - 0.5) / n - 0.5
          yk = (y1 - k)^2.0
          xy = (xj + yk)^0.5
          c1 = (xy - x1) * (xy - y1)
          c2 = xy * x1 - xy * y1
          c = int(c1 + c2 + green)
          r = r + mod(div(c, 65536), 256)
          g = g + mod(div(c, 256), 256)
          b = b + mod(c, 256)
        end
      end
      red[row, col] = r / (255.0 * n * n)
      grn[row, col] = g / (255.0 * n * n)
      blu[row, col] = b / (255.0 * n * n)
    end
  end

  return {red: red, green: grn, blue: blu}
end

w = 500.0
h = 850.0

# 3 x 3 samples take about 11.5 s; n = 1 (about 1.3 s) gives the textured
# picture with jagged edges.
c = rainbow_colors(w, h, 3)

draw.canvas(width = w, height = h, view = [0, w, 0, h])
draw.image_rgb(c.red, c.green, c.blue, smooth = true)
# Uncomment if you want to save the png
#draw.save("packed_color_field.png")
draw.show()
