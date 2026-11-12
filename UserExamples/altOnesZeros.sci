
rows = int(input("Please Enter the total Number of Rows  : "))
columns = int(input("Please Enter the total Number of Columns  : "))

println("Print Number Pattern - 1 and 0 in alternative Columns") 

for i in 1:rows + 1 
    for j in 1:columns + 1 
        if (mod (j, 2) == 0)           
            print("0 ")
        else
            print("1 ")
        end
    end 
    println()
end
