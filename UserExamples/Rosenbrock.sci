
import plot

a = 1.0
b = 100.0

xs=linspace(-1.5, 2.0,50)
ys=linspace(-0.5, 2.6, 50)
Z=zeros(50, 50)

for i in 1:50
  for j in 1:50
     Z[i,j] = (a - xs[i])^2 + b*(ys[j]- xs[i]^2)^2
  end
end

#plot.surface(xs, ys, Z, color_by = log10(1 + Z))                      # true heights, log colours
plot.surface(xs, ys, Z, color_by = log10(1 + Z), colormap = "plasma")

#plot.surface(xs,ys,  log10(1 + Z))