## Reading a plain-text settings file line by line, and saving results as JSON.

import io

io.write_file("model.txt", "# Model settings\nrate = 0.35\ncapacity = 120\n" +
              "\nname = logistic growth\n")

# One "key = value" pair per line; # starts a comment.
settings = dict()
for line in io.read_lines("model.txt")
  line = trim(line)
  if line == "" or line[1] == "#"
    continue
  end
  parts = split(line, "=")
  settings[trim(parts[1])] = trim(parts[2])
end
rate = real(settings["rate"])
capacity = int(settings["capacity"])
println(settings["name"], "-", "rate:", rate, "capacity:", capacity)

# Results go to JSON, which keeps names, numbers and vectors as they are.
population = capacity ./ (1 + 9 * exp(-rate * [0.0; 5.0; 10.0; 20.0]))
io.write_json("results.json",
              {model: settings["name"], rate: rate, population: population})
back = io.read_json("results.json")
println(back.model, typeof(back.population), length(back.population))

io.delete_file("model.txt")
io.delete_file("results.json")
