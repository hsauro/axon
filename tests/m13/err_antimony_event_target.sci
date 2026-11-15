#! error: ArgumentError
# An event may not change the size of a compartment.
import antimony
m = antimony.load("""
  compartment cell; cell = 1
  species S1 in cell
  J1: -> S1; k1
  k1 = 1; S1 = 0
  E1: at (time > 1): cell = 2
""")
