# A tour of Axon

[Contents](index.md)

This page shows the main parts of the language with short examples. Each example
runs as it stands, and later ones build on earlier ones; paste them into a file
or the REPL. The [Language Reference](Axon-Language-Reference.md) has the exact
rules.

## Numbers

Integers and reals are distinct, and arithmetic between them gives a real.
Integer overflow is an error, never a silent wrap-around.

```axon
a = 7
b = 2
println(a / b, div(a, b), mod(a, b))     # 3.5 3 1
println(2^10, 1.5e3, 0.1 + 0.2)          # 1024 1500.0 0.3
```

Complex numbers are written with an `i` suffix. Real functions stay real:
`sqrt(-4.0)` is NaN, while `sqrt(-4 + 0i)` is `2i`.

```axon
z = 3 + 4i
println(abs(z), conj(z), real(z), imag(z))
println(sqrt(-4.0), sqrt(-4 + 0i))
```

## Text

Strings use double quotes, join with `+`, and `string(x)` turns any value into
text.

```axon
name = "Axon"
println("Hello, " + name + "! " + string(length(name)) + " letters")
```

## Vectors and matrices

`[1; 2; 3]` is a vector (a column); `[1, 2, 3]` is a 1×3 matrix (a row); rows of
a matrix are separated by `;`. `*` is the matrix product and `.*` the
elementwise one; `'` transposes (so does `tr(A)`), and `trace(A)` sums the
diagonal.

```axon
v = [1.0; 2.0; 3.0]
A = [2.0, 1.0, 0.0;
     1.0, 3.0, 1.0;
     0.0, 1.0, 4.0]
println(A * v)          # matrix times vector
println(v .* v)         # elementwise
println(v' * v)         # inner product: a scalar
println(trace(A))       # sum of the diagonal: 9.0
x = A \ v             # solve A x = v
println(x)
```

Functions such as `sin` and `exp` apply to each element, and `sum`, `mean`,
`min` and `max` reduce an array.

```axon
t = linspace(0.0, 1.0, 5)
println(sum(t), mean(t), max(exp(t)))
```

## Indexing and ranges

Indices start at 1. A range `a:b` or `a:step:b` selects several elements, `:`
selects a whole row or column, and `end` is the last index.

```axon
w = [10, 20, 30, 40, 50]
println(w[2], w[end], w[2:4])
println(A[1, :], A[:, end])
for k in 1:2:5
  println(k)
end
```

Assigning to an element or a slice changes only that variable: Axon has value
semantics, so `B = A` makes an independent copy (copied lazily, only when one
of them changes).

```axon
B = A
B[1, 1] = 100.0
println(A[1, 1], B[1, 1])     # 2.0 100.0
```

## Functions

```axon
## The norm of a vector.
function norm2(v)
  return sqrt(sum(v .^ 2))
end

# Keyword arguments come after a ";" and have defaults.
function damped(t; rate = 0.5, amplitude = 1.0)
  return amplitude * exp(-rate * t)
end

println(norm2([3.0; 4.0]), damped(2.0), damped(2.0, rate = 0.1))
```

A function can return several values, and functions are values: a lambda
captures the variables around it.

```axon
function minmax(v)
  return min(v), max(v)
end
[lo, hi] = minmax([3, 1, 4, 1, 5])
println(lo, hi)

k = 3.0
scale = function(x) return k * x end
println(scale(2.0))
```

## Lists, records and dictionaries

```axon
items = {1, "two", 3.0}            # a list
items = append(items, [4; 5])
p = {a: 1.0, b: 0.1}               # a record
p.c = 0.075
d = dict("Km" => 0.5, "Vm" => 10.0) # a dictionary
d["kcat"] = 2.0
println(length(items), p.b, d["Km"], keys(d))
```

## Control flow

`if`, `for` and `while` end with `end`. Conditions must be `true` or `false`;
there is no truthiness.

```axon
total = 0
n = 1
while total < 20
  total = total + n
  n = n + 1
end
if total > 30
  println("big")
elseif total > 15
  println("medium", total)
else
  println("small")
end
```

## Errors

Errors have a kind and a message. `try` / `catch` handles them, and
`error(kind, message)` raises one.

```axon
function checked_sqrt(x)
  if x < 0 error("DomainError", "negative input: " + string(x)) end
  return sqrt(x)
end
try
  checked_sqrt(-1.0)
catch err
  println(err.kind, "-", err.message)
end
```

## Modules

`import m` makes a module's functions available as `m.name`; `from m import a,
b` brings names in directly. A file `mymodel.sci` next to your program is the
module `mymodel`, and its `export function` definitions are what it offers.

```axon
import linalg
from linalg import eig
println(linalg.det(A), eig([2.0, 0.0; 0.0, 3.0]))
```

## Differential equations

`ode.solve(f, y0, [t0, t1])` solves y' = f(t, y). The result `sol` holds the
times `sol.t`, the states `sol.y` (one column per time) and `sol.at(t)` for any
time in between. Use `method = "bdf"` for stiff problems.

```axon
import ode
decay = function(t, y) return -0.5 * y end
sol = ode.solve(decay, 2.0, [0, 10], rtol = 1e-8)
println(sol.status, sol.at(3.0)[1], 2 * exp(-1.5))
```

## Plots

```axon
import plot
plot.figure(title = "Exponential decay")
plot.line(sol.t, sol.y[1, :], label = "numerical")
plot.scatter(sol.t, 2 * exp(-0.5 * sol.t), label = "exact", size = 4.0)
plot.xlabel("t")
plot.show()
```

`plot.save("decay.pdf")` writes the same figure to a file; PNG and SVG work
too.
