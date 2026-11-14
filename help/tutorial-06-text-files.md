# Lesson 6: Text and files

[Tutorial](tutorial.md)

So far every number a program used was typed into it, and every result
disappeared when the Output pane was cleared. Real work reads data from
files and writes results to them. This lesson starts with text: how to
build it, look inside it and turn it into numbers. Then it writes and reads
files: plain text, and tables of numbers in the CSV format that
spreadsheets and instruments use.

Save the programs of this lesson in one folder: some of them read files
that earlier ones wrote.

## Text

A piece of text, called a *string*, is written in double quotes. `+` joins
two strings, and `length` counts their characters:

```repl
> name = "Axon"
name = "Axon"
> "Hello, " + name
"Hello, Axon"
> length(name)
4
> upper(name)
"AXON"
```

A number is not text, so it cannot be joined to a string directly.
`string` turns any value into text:

```repl
> "Day " + 3
TypeError: operator + is not defined for string and int
  at <repl>:1:1
> "Day " + string(3)
"Day 3"
```

`format(x, d)`, from Lesson 1, also gives text: the number `x` with `d`
decimals. A string multiplied by a whole number is repeated, which is
handy for lines and spaces:

```repl
> "-" * 20
"--------------------"
```

Inside quotes, `\n` stands for a line break: `"one\ntwo"` is printed on two
lines.

## Looking inside text

`contains`, `startswith` and `endswith` ask about a string's contents, `find`
gives the position where a piece of text starts (0 if it does not occur),
and `replace` swaps one piece for another:

```repl
> s = "the quick brown fox"
s = "the quick brown fox"
> contains(s, "brown")
true
> startswith(s, "the")
true
> find(s, "quick")
5
> replace(s, "fox", "cat")
"the quick brown cat"
```

Square brackets pick out characters, as they pick out the elements of a
vector:

```repl
> s[1]
"t"
> s[5:9]
"quick"
```

## Splitting and joining

`split` cuts a string into words, at the spaces, or at another separator
given as its second argument. The result is a *list* of strings, in curly
brackets, as in Lesson 5:

```repl
> words = split(s)
words = {"the", "quick", "brown", "fox"}
> length(words)
4
> words[2]
"quick"
> join(words, "-")
"the-quick-brown-fox"
```

`join` does the opposite: it puts the strings of a list together, with a
separator between them.

Text that holds a number is still text. `real` and `int` read the number:

```repl
> real("2.5") + 1
3.5
> int("42")
42
```

Together with `split`, they read numbers from a line of text, such as a
line copied from a report:

```axon
# numbers.sci: numbers from a line of text
line = "12.5, 13.1, 11.8, 14.0"
parts = split(line, ",")
values = zeros(length(parts))
for k in 1:length(parts)
  values[k] = real(parts[k])
end
println(values')
println("Mean:", mean(values))
```

```output
1×4 matrix{real}
  12.5  13.1  11.8  14.0
Mean: 12.85
```

Each piece after the first starts with a space, such as `" 13.1"`; `real`
ignores spaces around a number. (`trim(s)` removes them, when you need the
text itself.)

## Writing and reading files

Files are read and written with the `io` module. `io.write_file` writes a
string to a file, replacing whatever the file held, and `io.read_file`
reads a whole file back as one string. `io.read_lines` reads it as a list
of lines:

```axon
# notes.sci: writing a text file and reading it back
import io
text = "First line\nSecond line\nThird line\n"
io.write_file("notes.txt", text)
println("Wrote notes.txt")
lines = io.read_lines("notes.txt")
println(length(lines), "lines")
for line in lines
  println(upper(line))
end
```

```output
Wrote notes.txt
3 lines
FIRST LINE
SECOND LINE
THIRD LINE
```

A file name on its own, such as `"notes.txt"`, means a file in the folder
of the program that is running. Open `notes.txt` with **File > Open** to see
it. `for line in lines` runs the loop once for each line of the list, as
`for k in 1:3` runs it once for each number.

## A report

Results are easier to read in tidy columns. This program builds a small
table in a string, a line at a time, prints it and saves it. `pad` adds
spaces to a name so that every name takes the same width:

```axon
# report.sci: a table of results, written to a file
import io

## The text s, with spaces added on the right to make it n characters long.
function pad(s, n)
  return s + " " * (n - length(s))
end

names = {"Ana", "Ben", "Cleopatra"}
scores = [72.5; 88.0; 64.4]
report = pad("Name", 10) + "Score\n"
report = report + "-" * 15 + "\n"
for k in 1:length(names)
  report = report + pad(names[k], 10) + format(scores[k], 1) + "\n"
end
print(report)
io.write_file("report.txt", report)
```

```output
Name      Score
---------------
Ana       72.5
Ben       88.0
Cleopatra 64.4
```

`report` grows as the loop adds a line to it each time round: the pattern
of Lesson 2's total, with text in place of numbers. `print`, unlike
`println`, does not end the line, because `report` already ends with one.

## Tables of numbers: CSV files

A CSV file (comma-separated values) is a table as text: one row per line,
with the values in a row separated by commas, and often a first line naming
the columns. Spreadsheets save and open it, and most instruments can export
it. `io.write_csv` writes a matrix as a CSV file, with a list of column
names:

```axon
# makecsv.sci: a week of measurements saved as a CSV file
import io
day = [1.0; 2.0; 3.0; 4.0; 5.0; 6.0; 7.0]
temperature = [12.1; 13.4; 12.8; 15.2; 16.0; 14.7; 13.9]
rain = [0.0; 2.5; 8.1; 0.0; 0.0; 1.2; 4.4]
table = [day, temperature, rain]
io.write_csv("weather.csv", table, {"day", "temperature", "rain"})
print(io.read_file("weather.csv"))
```

```output
day,temperature,rain
1,12.1,0
2,13.4,2.5
3,12.8,8.1
4,15.2,0
5,16,0
6,14.7,1.2
7,13.9,4.4
```

`[day, temperature, rain]` puts the three columns side by side, into a
matrix of 7 rows and 3 columns. The program then prints the file it wrote.

`io.read_csv` reads such a file back. It returns a *record*, a value that
holds several values under names (Lesson 7 says more): `names`, the list
of column names, and `data`, the numbers as a matrix. A dot picks out each:

```axon
# readcsv.sci: reading the CSV file back
import io
w = io.read_csv("weather.csv")
println(w.names)
[rows, columns] = size(w.data)
println(rows, "rows and", columns, "columns")
temperature = w.data[:, 2]
rain = w.data[:, 3]
println("Mean temperature:", format(mean(temperature), 1))
println("Total rain:", sum(rain))
```

```output
{"day", "temperature", "rain"}
7 rows and 3 columns
Mean temperature: 14.0
Total rain: 16.2
```

Data from a spreadsheet or an instrument works the same way: save it as
CSV in the program's folder, read it with `io.read_csv`, and work with its
columns as vectors.

## Mistakes

A file name with a spelling mistake, or a file in another folder:

```axon
# missing.sci
import io
w = io.read_csv("wether.csv")
```

```output
IOError: read_csv: no file "wether.csv"
  at missing.sci:3:5
```

Text that is not a number, given to `real` or `int`:

```repl
> real("abc")
ArgumentError: real: cannot read "abc" as a number
  at <repl>:1:1
```

And joining a number to a string without `string` or `format`, which gives
the `TypeError` shown above.

## Summary

- Strings are text in double quotes. `+` joins them, `string(x)` and
  `format(x, d)` turn numbers into text, and `"-" * 20` repeats.
- `length`, `upper`, `lower`, `contains`, `startswith`, `find` and
  `replace` work with text, and `s[k]` picks out characters.
- `split` cuts text into a list of pieces and `join` puts a list back
  together; `real` and `int` read numbers from text.
- `import io` gives `io.write_file`, `io.read_file` and `io.read_lines` for
  text files, and `io.write_csv` and `io.read_csv` for tables of numbers.
- A bare file name means a file in the program's folder.

## Exercises

1. Write a function `initials(first, last)` that returns a person's
   initials: for Ada Lovelace, `"A. L."`.
2. Count how many times the letter e appears in "the quick brown fox jumps
   over the lazy dog", with a loop over the positions of the string.
3. `pad` fails when the text is already longer than `n`, because a string
   cannot be repeated a negative number of times. Change it to return such
   text unchanged, and try it with `pad("Cleopatra", 5)`.
4. Write a CSV file `powers.csv` with columns x, x^2 and x^3 for x from 1
   to 5, and a header. Read it back and print the sum of each column.
5. Read `weather.csv` and plot the temperature against the day, with a
   title and labelled axes.

## Answers

**Exercise 1.** `first[1]` is the first character:

```axon
# initials.sci: a person's initials

## The initials of a person with the given first and last names.
function initials(first, last)
  return first[1] + ". " + last[1] + "."
end

println(initials("Ada", "Lovelace"))
```

```output
A. L.
```

**Exercise 2.** A count, as in Lesson 3, going up when a character is an e:

```axon
# letters.sci: how many e's?
s = "the quick brown fox jumps over the lazy dog"
count = 0
for k in 1:length(s)
  if s[k] == "e"
    count = count + 1
  end
end
println(count)
```

```output
3
```

**Exercise 3.** Return early when there is nothing to add:

```axon
# pad2.sci: pad that accepts long text

## The text s, with spaces added on the right to make it at least n
## characters long.
function pad(s, n)
  if length(s) >= n
    return s
  end
  return s + " " * (n - length(s))
end

println(pad("Cleopatra", 5) + "|")
println(pad("Ana", 5) + "|")
```

```output
Cleopatra|
Ana  |
```

The `|` shows where each padded string ends.

**Exercise 4.** The columns are built from a range, which becomes a
vector when calculated with:

```axon
# powers.sci: a CSV file of powers
import io
x = 1.0 * (1:5)
io.write_csv("powers.csv", [x, x.^2, x.^3], {"x", "x^2", "x^3"})
p = io.read_csv("powers.csv")
for c in 1:3
  println(p.names[c], sum(p.data[:, c]))
end
```

```output
x 15.0
x^2 55.0
x^3 225.0
```

**Exercise 5.** The first column is the day and the second the
temperature:

```axon
# weather_plot.sci: temperature against day
import io
import plot
w = io.read_csv("weather.csv")
plot.line(w.data[:, 1], w.data[:, 2], marker = "circle")
plot.title("A week of temperatures")
plot.xlabel("day")
plot.ylabel("temperature (C)")
plot.show()
```

Next: [Lesson 7: Lists, records and dictionaries](tutorial-07-collections.md)
