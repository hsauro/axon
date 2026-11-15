#! error: UserError
# A statement with "=" that is not "name = number" is an error, not a
# parameter with a strange name: here an event missing the colon after its
# name.
import antimony
m = antimony.load("J1: -> S1; k1; k1 = 1; S1 = 0; E1 at (time > 1): k1 = 0")
