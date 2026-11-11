#! error: DimensionError
# The colour channels of an image must have the same size.
import graphics
graphics.save({items: {{kind: "image", red: zeros(2, 2), green: zeros(2, 3), blue: zeros(2, 2)}}}, "_tmp_none.svg")
