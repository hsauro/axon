
import plot

a = 1.0
b = 100.0

xs=linspace(-1.75, 2.0, 50)
ys=linspace(-0.5, 2.6,  50)
Z=zeros(50, 50)

for i in 1:50
  for j in 1:50
     Z[i, j] = (a - xs[j])^2 + b*(ys[i] - xs[j]^2)^2
  end
end

# true heights, but log colours
plot.surface(xs, ys, Z, color_by = log10(1 + Z), colormap = "plasma", label="Height of Function")
plot.xlabel("X Axis A long axis this is")
plot.ylabel("Y Axis A long axis is this")
plot.show()

#plot.figure()
#plot.surface(xs, ys, Z, color_by = log10(1 + Z), colormap = "coolwarm", label="Height of Function")
#plot.show()