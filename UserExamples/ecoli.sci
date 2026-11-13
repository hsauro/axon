import antimony
import plot
m = antimony.read("ecoli.txt")
c = antimony.control(m)
plot.bar3(c.reactions, c.reactions, c.flux_control, colormap = "coolwarm",
          clim = [-1, 1], width = 1.0, edges = false)
plot.tick_size (6)