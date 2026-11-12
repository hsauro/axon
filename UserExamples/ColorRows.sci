

import draw
import colors


draw.clear()
#graphics.penwidth (9)
y = 10
names = colors.names()
for k in 1:50
  draw.line (20, y, 200, y, color = colors.rgb(names[k]), width = 3)
  y = y + 9
end

y = 10
for k in 51:100
  draw.line (210, y, 360, y, color = colors.rgb(names[k]), width = 3)
  y = y + 9
end

y = 10
for k in 101:139
  draw.line (370, y, 510, y, color = colors.rgb(names[k]), width = 3)
  y = y + 9
end
