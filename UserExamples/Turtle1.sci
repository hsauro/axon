
import draw

# Customize these two values:
points = 19    # Use an odd number (e.g., 5, 7, 9, 15)
radius = 200  # Max 240 to stay inside the 500x500 canvas

# Setup canvas
draw.canvas(width = 500, height = 500)
draw.clear()

# Calculate geometry to center the star
turn_angle = 180 - (180 / points)
half_tip_angle = 90 / points
step_length = 2 * radius * cos(deg2rad(half_tip_angle))

# Position turtle at the first tip so the center sits at (250, 250)
draw.penup()
draw.turtle(x = 250 - radius, y = 250, heading = -half_tip_angle)
draw.pendown()

# Draw the star
for i in 1:points
  draw.forward(step_length)
  draw.left(turn_angle)
end

draw.show()
