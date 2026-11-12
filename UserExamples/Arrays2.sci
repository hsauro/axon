
import random

a = random.rand (4,2)

for i in 1:2
   for j in 1:2
       a[i,j] = 0.0
   end
end
println (a)
a = random.rand (2,4)

for i in 1:2
   for j in 1:4
       a[i,j] = 0.0
   end
end
println(a)