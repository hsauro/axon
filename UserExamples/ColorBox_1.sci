import draw
import time

t0 = time.clock()

# clg + fastgraphics: start a blank 256x256 canvas. Axon's coordinates start
# at the bottom-left corner with y pointing up, so the picture is BASIC256's
# (top-left origin, y down) upside down.
draw.canvas(width = 256, height = 256, view = [0, 256, 0, 256])

color_blue = 128 / 255.0

for i in 0:255
  for j in 0:255
    # color i, j, color_blue  ->  RGB components scaled to 0..1
    draw.rect(i, j, 2, 2, fill = [i / 255.0, j / 255.0, color_blue], color = "none")
  end
  draw.frame()                 # refresh
end

draw.show()

t1 = time.clock()
println("Elapsed: " + time.format(t1 - t0))

# Old rendering engine:
# Elapsed: 29.7 s
# Display channel, each frame sending only the boxes added since the last:
# Elapsed: 8.6 s, of which 8.5 s is the pacing of 256 frames at the default
# 30 a second; 1.4 s with draw.frame(fps = 1000).