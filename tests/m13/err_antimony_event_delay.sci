#! error: UserError
# Event delays are not read: an event with one says so.
import antimony
m = antimony.load("J1: -> S1; k1; k1 = 1; S1 = 0; E1: at 2 after (time > 1): k1 = 0")
