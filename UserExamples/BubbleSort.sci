
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

function outputList (astr, numbers)
  for i in 1:length (numbers)
      astr = astr + string (numbers[i]) + " "
      if mod (i, 30) == 0
         astr = astr + "\n"
      end
  end
  return astr
end
 
numbers = vector ([12, 7, 13, 5, 6])
println (outputList ("Before sorting:\n", numbers))

numbers = bubbleSort (numbers) 
println (outputList ("After sorting:\n", numbers))

println ("Bigger example")
numbers = random.randint (1, 100, 100)
println (outputList ("List before sorting:\n", numbers))

numbers = bubbleSort(numbers)
println (outputList ("List after sorting:\n", numbers))

