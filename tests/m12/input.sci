# input: a line typed by the user (here read from input.in), without its
# line ending; nothing at the end of the input. The prompts go to the
# output; the answers are not echoed when they come from a file.
name = input("Your name: ")
println("Hello, " + name + "!")
n = int(input("How many? "))
println(n * 2)
x = real(input())
println(x / 2)

# Reading every remaining line: an empty line is "", the end is nothing.
count = 0
while true
  line = input()
  if line == nothing
    break
  end
  count = count + 1
  println("[" + upper(line) + "]")
end
println(count)
println(input("past the end: ") == nothing)
