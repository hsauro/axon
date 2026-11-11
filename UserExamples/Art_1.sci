## Art_1: a BASIC-256 artwork (https://www.imaginary.org/gallery/basic-256-artworks)
##
## Each colour component is the distance to a point, wrapped round at 255.
## The picture is computed as red, green and blue matrices and drawn as one
## image (drawing every pixel as a tiny square leaves seams between them).

## Original BASIC256 program from https://www.imaginary.org/gallery/basic-256-artworks

import draw

w = 530
h = 870
draw.canvas(width = w, height = h)
draw.text (20, h-28, "The image is computing...", size=28)
draw.show()

# The colours, worked out in a function so that the JIT compiles the loops.
# Each pixel is the average of n x n samples spread over it, which smooths  
# the edges where a colour wraps round from 255 to 0.
function colours(w, h, n)
  k1 = h * 0.25
  k2 = h * 0.5
  k3 = h * 0.75
  red = zeros(h, w)
  green = zeros(h, w)
  blue = zeros(h, w)
  for x1 in 0:w - 1
    for y1 in 0:h - 1
      r = 0.0
      g = 0.0
      b = 0.0
      for a in 1:n
        x = x1 + (a - 0.5) / n - 0.5
        for c in 1:n
          y = y1 + (c - 0.5) / n - 0.5
          x12 = (x - (w * 0.25 + 0.5 * (y + 1)))^2
          r = r + mod(sqrt(x12 + (y - k1)^2), 255.0)
          g = g + mod(sqrt(x12 + (y - k2)^2), 255.0)
          b = b + mod(sqrt(x12 + (y - k3)^2), 255.0)
        end
      end
      # Row 1 is the top of the picture, so (x1, y1) is row h - y1, column x1 + 1.
      red[h - y1, x1 + 1] = r / (255.0 * n * n)
      green[h - y1, x1 + 1] = g / (255.0 * n * n)
      blue[h - y1, x1 + 1] = b / (255.0 * n * n)
    end
  end
  return {red: red, green: green, blue: blue}
end

c = colours(w, h, 3)
draw.image_rgb(c.red, c.green, c.blue, smooth = true)
draw.show()

# One sample per pixel (n = 1) takes 0.8 s but leaves jagged edges where a
# colour wraps; 2 x 2 samples take 2.8 s, 3 x 3 6.1 s, 4 x 4 10.9 s.
