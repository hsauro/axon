#! error: OverflowError
__jit_mode("on")
big = 4611686018427387904
sq = function(x) return x * big end
print(sq(1) > 0)
sq(3)
