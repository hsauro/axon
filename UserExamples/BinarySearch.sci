

# Looks for the value in the list, and returns its location

function doBinarySearch(list, value)
    low = 0;
    high = length (list) - 1;
    while 0 <= high 
        mid = div (low+high, 2)
        if list[mid] > value 
           high = mid - 1
        else
           if list[mid] < value
              low = mid + 1
          else
             return mid
          end;
        end;
    end;
    return -1;
end;

function binarySearch(list, x)
    low = 0
    high = length (list)
    # Repeat until the pointers low and high meet each other
    while low <= high 
        mid = low + div(high - low, 2)
        if x == list[mid]
            return mid
        else
           if x > list[mid]
              low = mid + 1
           else
              high = mid - 1
           end;
        end;
    end;
    return -1
end

println ("5 is located at position", doBinarySearch ([2,3,5,8,10], 5))

println ("6 is located a postion:", binarySearch ([3, 4, 5, 6, 7, 8, 9], 6))
