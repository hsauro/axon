#! error: ArgumentError
# One grid per figure.
import plot
plot.subplot(2, 1, 1)
plot.subplot(1, 2, 1)
