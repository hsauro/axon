

# Create an ASCII circle

radius = 5
aspect_ratio = 3  # Adjust this number: lower makes it narrower, higher makes it wider

max_x = round(radius * aspect_ratio)

for y in -radius:radius
    for x in -max_x:max_x
        # + 0.5 smooths out the single-pixel bumps on the top, bottom, and sides
        if (x / aspect_ratio)^2 + y^2 <= (radius + 0.5)^2
            print("*")
        else
            print(" ")
        end
    end
    println()
end