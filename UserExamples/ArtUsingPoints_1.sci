import draw

w = 530.0
h = 870.0

draw.canvas(width = w, height = h, view = [0, w, 0, h])

k1 = h * 0.25
k2 = h * 0.5
k3 = h * 0.75
j = w * 0.25
y2 = k1
y3 = k2
y4 = k3

for x1 in 0.0:w
    x2 = j
    for y1 in 0.0:h
        x2 = x2 + 0.5
        x12 = (x1 - x2)^2.0
        y12 = (y1 - y2)^2.0
        y13 = (y1 - y3)^2.0
        y14 = (y1 - y4)^2.0
        xy1 = (x12 + y12)^0.5
        xy2 = (x12 + y13)^0.5
        xy3 = (x12 + y14)^0.5
        r = mod(xy1, 255.0)
        g = mod(xy2, 255.0)
        b = mod(xy3, 255.0)
        rgb = [r / 255.0, g / 255.0, b / 255.0]
        draw.points(x1, y1, shape = "square", size = 1, fill = rgb, color = "none")
    end
    draw.frame()
end
draw.show()
