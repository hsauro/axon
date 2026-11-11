#! error: ArgumentError
import graphics
graphics.save({items: {{kind: "image", values: zeros(2, 2), colormap: "rainbow"}}}, "_tmp_none.svg")
