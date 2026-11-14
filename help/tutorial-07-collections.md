# Lesson 7: Lists, records and dictionaries

[Tutorial](tutorial.md)

A vector holds numbers, all of one kind, which suits measurements and
calculations. Data is often more mixed: a list of names, a sample described
by its name, its pH and its cell count, a table that gives each element's
atomic mass. This lesson shows three ways to hold such data: *lists*,
*records* and *dictionaries*. You have met each briefly already.

## Lists

A list is written in curly brackets, and can hold values of any kind,
including text. Its elements are counted and picked out as a vector's are:

```repl
> elements = {"H", "He", "Li"}
elements = {"H", "He", "Li"}
> length(elements)
3
> elements[2]
"He"
> elements[end]
"Li"
```

`append` gives a new list with one more element at the end. Store the result
back in the variable to make the list grow:

```repl
> elements = append(elements, "Be")
elements = {"H", "He", "Li", "Be"}
```

`for` runs once for each element of a list:

```repl
> for e in elements
...   println(e)
... end
H
He
Li
Be
```

A list can mix kinds of value, even vectors, and `{}` is the empty list,
which a loop can fill. This program keeps the names of the elements whose
atomic mass is below 10:

```axon
# light.sci: collecting names in a list
names = {"H", "He", "Li", "Be", "B", "C"}
masses = [1.008; 4.003; 6.94; 9.012; 10.81; 12.011]
light = {}
for k in 1:length(names)
  if masses[k] < 10
    light = append(light, names[k])
  end
end
println(light)
```

```output
{"H", "He", "Li", "Be"}
```

Keeping the names in a list and the masses in a vector works, but the two
must be kept in step: the third name belongs with the third mass. Records
and dictionaries keep such values together.

## Records

A *record* holds several values, each under a name of its own, called a
*field*. It is written in curly brackets with each field's name, a colon and
its value; a dot picks out a field:

```repl
> s = {name: "A1", ph: 7.2, cells: 5000}
s = {name: "A1", ph: 7.2, cells: 5000}
> s.name
"A1"
> s.ph
7.2
> s.cells = 5200
> s
{name: "A1", ph: 7.2, cells: 5200}
```

`io.read_csv` in Lesson 6 returned a record with the fields `names` and
`data`.

Storing a record in another variable makes a copy. Changing the copy leaves
the original as it was:

```repl
> t = s
t = {name: "A1", ph: 7.2, cells: 5200}
> t.ph = 6.8
> s.ph
7.2
```

The same is true of vectors, lists and dictionaries: in Axon, `=` always
copies, so a change through one name never surprises you through another.

## Record types

When a program uses many records of the same shape, declare their shape
once, as a *record type*. The declaration names the type, and lists each
field with the kind of value it holds:

```axon
# samples.sci: a record type for samples
record Sample
  name: string
  ph: real
  cells: int
end

a = Sample("A1", 7.2, 5000)
println(a)
println(a.name, "has pH", a.ph)
```

```output
{name: "A1", ph: 7.2, cells: 5000}
A1 has pH 7.2
```

`Sample("A1", 7.2, 5000)` makes a record of that type, with the values in
the order of the fields. Axon checks each value against its declared kind,
so a mistake is caught where it is made:

```axon
# badsample.sci
record Sample
  name: string
  ph: real
  cells: int
end

b = Sample("B2", "high", 3200)
```

```output
TypeError: field "ph" of Sample must be real, got string
  at badsample.sci:8:5
```

## Lists of records

A list of records is a table in which each row is one thing, with its
properties named. Loops then read naturally:

```axon
# experiment.sci: a list of samples
record Sample
  name: string
  ph: real
  cells: int
end

samples = {Sample("A1", 7.2, 5000),
           Sample("B2", 6.4, 3200),
           Sample("C3", 7.9, 6100)}
for s in samples
  println(s.name, "pH", s.ph)
end

total = 0
for s in samples
  total = total + s.cells
end
println("Mean cell count:", total / length(samples))
```

```output
A1 pH 7.2
B2 pH 6.4
C3 pH 7.9
Mean cell count: 4766.66666666667
```

A long list can be written over several lines, like a matrix. `s.cells`
reads the field of each sample in turn.

## Dictionaries

A *dictionary* looks values up by a key, as a printed dictionary looks up
a definition by a word. `dict` makes one from pairs written `key => value`:

```repl
> mass = dict("H" => 1.008, "He" => 4.003)
mass = dict("H" => 1.008, "He" => 4.003)
> mass["He"]
4.003
> mass["Li"] = 6.94
> mass
dict("H" => 1.008, "He" => 4.003, "Li" => 6.94)
```

Storing under a new key adds it. `keys` gives the keys, in the order they
were added; `haskey` asks whether a key is there; and `get` gives a value,
or a default when the key is missing:

```repl
> keys(mass)
{"H", "He", "Li"}
> haskey(mass, "C")
false
> get(mass, "C", 0.0)
0.0
```

## Counting with a dictionary

A dictionary is the natural way to count how often things occur. This
program counts the words of a sentence. `get(counts, w, 0)` is the count
so far, 0 for a word not yet seen, and adding 1 stores the new count:

```axon
# wordcount.sci: how often does each word occur?
text = "the cat sat on the mat and the dog sat on the log"
counts = dict()
for w in split(text)
  counts[w] = get(counts, w, 0) + 1
end
for w in keys(counts)
  println(w, counts[w])
end
```

```output
the 4
cat 1
sat 2
on 2
mat 1
and 1
dog 1
log 1
```

`dict()` with nothing in the brackets is an empty dictionary.

## Which to use

| Kind | Use it for |
| --- | --- |
| Vector or matrix | Numbers to calculate with: measurements, time points, tables of numbers |
| List | A sequence of anything, such as names, or values of mixed kinds |
| Record | One thing with several named properties, such as a sample |
| Dictionary | Values looked up by a key, such as atomic masses by element |

## Mistakes

Each kind of collection has its own error for asking about something that
is not there:

```repl
> elements[5]
IndexError: index 5 is out of bounds for a dimension of length 4
  at <repl>:1:10
> s.colour
FieldError: the record has no field "colour"
  at <repl>:1:1
> mass["C"]
KeyError: key "C" not found
  at <repl>:1:1
```

And `append` does not change a list by itself: `append(elements, "B")` on
its own line makes a longer list and throws it away. Write
`elements = append(elements, "B")`.

## Summary

- A list, `{a, b, c}`, holds values of any kind; `append` adds to it,
  `l[k]` picks an element, and `for x in l` loops over it.
- A record, `{name: value, ...}`, holds named fields, read and changed with
  a dot: `s.ph`.
- `record Name ... end` declares a record type with typed fields;
  `Name(values)` makes one, checking each value.
- A dictionary, `dict(key => value, ...)`, looks values up by key:
  `d[key]`, `keys`, `haskey` and `get`.
- `=` copies, so changing one variable never changes another.

## Exercises

1. Make a list of the first four planets' names, add `"Jupiter"`, and
   print the number of planets and the last name.
2. Write a function `has(items, x)` that returns `true` when the list
   `items` contains `x`, and `false` otherwise.
3. The atomic masses of hydrogen, carbon and oxygen are 1.008, 12.011 and
   15.999. Store them in a dictionary, and the formula of glucose, C6H12O6,
   in another, from element to number of atoms. Work out the molar mass of
   glucose with a loop over the formula's keys.
4. Declare a record type `Planet` with a name, a distance from the sun (in
   astronomical units) and an orbital period (in years). Make a list of
   Earth (1.0, 1.0), Mars (1.524, 1.881) and Jupiter (5.203, 11.86), and
   check Kepler's third law: for each, the period squared divided by the
   distance cubed is about 1.
5. Count how often each letter occurs in "mississippi".

## Answers

**Exercise 1.**

```axon
# planets.sci: a growing list
planets = {"Mercury", "Venus", "Earth", "Mars"}
planets = append(planets, "Jupiter")
println(length(planets), planets[end])
```

```output
5 Jupiter
```

**Exercise 2.** Return `true` as soon as the element is found; only when
the loop has looked at every element is the answer `false`:

```axon
# has.sci: is x in the list?

## True when the list items contains x.
function has(items, x)
  for item in items
    if item == x
      return true
    end
  end
  return false
end

planets = {"Mercury", "Venus", "Earth", "Mars"}
println(has(planets, "Mars"), has(planets, "Pluto"))
```

```output
true false
```

**Exercise 3.** The formula's keys say which masses to look up:

```axon
# glucose.sci: the molar mass of glucose
mass = dict("H" => 1.008, "C" => 12.011, "O" => 15.999)
glucose = dict("C" => 6, "H" => 12, "O" => 6)
total = 0.0
for atom in keys(glucose)
  total = total + glucose[atom] * mass[atom]
end
println("Glucose:", format(total, 3), "g/mol")
```

```output
Glucose: 180.156 g/mol
```

**Exercise 4.**

```axon
# kepler.sci: Kepler's third law
record Planet
  name: string
  distance: real
  period: real
end

planets = {Planet("Earth", 1.0, 1.0),
           Planet("Mars", 1.524, 1.881),
           Planet("Jupiter", 5.203, 11.86)}
for p in planets
  println(p.name, format(p.period^2 / p.distance^3, 3))
end
```

```output
Earth 1.000
Mars 1.000
Jupiter 0.999
```

**Exercise 5.** The counting pattern, with the letters of the word as keys:

```axon
# letters2.sci: letter counts
word = "mississippi"
counts = dict()
for k in 1:length(word)
  letter = word[k]
  counts[letter] = get(counts, letter, 0) + 1
end
for letter in keys(counts)
  println(letter, counts[letter])
end
```

```output
m 1
i 4
s 4
p 2
```

Next: [Lesson 8: Solving equations](tutorial-08-equations.md)
