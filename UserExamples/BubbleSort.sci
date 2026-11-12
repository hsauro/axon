
import random

function bubbleSort (list: vector)
 sorted = false;
 len = length (list)
 while not sorted 
      sorted = true
      len = len - 1;
      for i in 1:len
          if list[i+1] < list[i] 
              temp = list[i];
              list[i] = list[i + 1]
              list[i + 1] = temp;
              sorted = false
           end
      end
 end
 return list
end


function printNumbers (numbers)
  for i in 1:length (numbers)
      print (numbers[i], " ")
      if mod (i, 20) == 0
         println()
      end
  end
end


 
numbers = vector ([12, 7, 13, 5, 6])
println (numbers)
numbers = bubbleSort (numbers) 
# Sorted is [5, 6, 7, 12, 13]

# Bigger example
numbers = random.randint (1, 100, 100)
println ("List before sorting:");
printNumbers (numbers)

numbers = bubbleSort(numbers)
println ("List after sorting:");
printNumbers (numbers)

