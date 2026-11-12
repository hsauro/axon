


function addNumbers (n) : int
    if (n != 0) 
       return n + addNumbers(n - 1)
    else
       return n
    end
end

num = int (input ("Enter a positive integer: "))
println ("Sum = ", addNumbers(num))