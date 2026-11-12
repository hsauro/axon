

import linalg

a =  [1,2; 3,4]
x = linalg.inv (a)

if isapprox (x, [-2,1; 1.5,-0.5])
   println ("Pass")
else
   println ("Fail")
end

a = [3,2,-1; 1,6,3; 2,-4,0]
x = linalg.inv (a)


if isapprox(x, [0.1875, 0.0625, 0.1875;
               0.0938, 0.0313, -0.1563;
               -0.2500, 0.2500, 0.2500], atol = 1E-4)
   println ("Pass")
else
   println ("Fail")
end  