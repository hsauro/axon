#! error: ArgumentError
# A figure with plots outside a grid cannot be divided afterwards.
import plot
plot.line([1; 2], [1; 2])
plot.subplot(2, 1, 1)
