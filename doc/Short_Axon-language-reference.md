# Axon Language Reference (AI-friendly summary)

Axon is a numerical/scientific scripting language (syntax resembling a mix of Julia/MATLAB/Python). Files end in `.sci`. This is a condensed reference distilled from the full user manual.

## 1. Syntax basics

- One statement per line; `;` separates multiple statements on one line.
- Expressions continue on the next line after a binary operator, comma, or `=`; line breaks are ignored inside brackets.
- Line comments: `# ...`. Block comments: `#= ... =#` (can nest).
- Blocks close with `end`: `if`, `for`, `while`, `try`, `function`, `record`.
- Case-sensitive names. Indexing is **1-based**.

**Reserved words:** `function end return if elseif else for in while break continue local global try catch import from as export extern record true false nothing and or not`

## 2. Types

| Type | Examples | Notes |
|---|---|---|
| `int` | `42`, `-7`, `1_000_000` | 64-bit; overflow is an error (no wraparound) |
| `real` | `2.5`, `1.0e-3` | double precision; must have digit both sides of `.` (`0.5` not `.5`) |
| `complex` | `3 + 4i`, `2.5i` | |
| `bool` | `true`, `false` | no truthiness for numbers/strings/collections |
| `string` | `"text"` | double-quoted |
| `nothing` | `nothing` | no value |
| `vector`/`matrix` | `[1;2;3]`, `[1,2;3,4]` | dense arrays, column-major storage |
| `range` | `1:10`, `0:0.1:1` | lazy: start:step(optional):stop |
| `list` | `{1, "two", 3.0}` | mixed-type, indexable like a vector |
| `record` | `{a: 1.0, b: "x"}` | named fields, dot access |
| `dict` | `dict("Km" => 0.5)` | key→value, insertion order preserved |
| `sparse` | `sparse(i,j,v,m,n)` | sparse matrix |
| `function` | `function(x) return 2*x end` | first-class value |

`typeof(x)` returns the type name as a string.

**Value semantics:** assignment/pass-by-value with copy-on-write — `B = A; B[1,1] = ...` never mutates `A`.

**Type annotations:** `x: real = 0` checks/widens type on assignment (`int → real` auto-widens; narrowing is a `TypeError`). Function params/returns can also be annotated: `fmt.matrix(A; decimals: int, digits: int = 6)`.

## 3. Numbers & operators

- `/` always returns `real`; `div(a,b)` = floored integer division; `mod(a,b)` = remainder with sign of `b`.
- Promotion: `bool → int → real → complex` (never reverse).
- IEEE 754 semantics: `1.0/0.0 = Inf`, `0.0/0.0 = NaN`; real math functions return `NaN` outside domain (e.g. `sqrt(-4.0)` is `NaN`, but `sqrt(-4+0i)` is `2i`).
- Display: reals show up to 15 significant digits by default.
- Constants: `pi`, `e` (can be reassigned, shadowing the constant).

### Rounding/misc
`abs`, `floor`, `ceil`, `round` (half away from zero), `int` (trunc toward zero), `div`, `mod`, `min`/`max` (scalar or elementwise w/ broadcasting), `factorial(n)`.

### Elementary functions (built-in, no import, elementwise on arrays)
`sqrt exp log log10 log2 sin cos tan asin acos atan atan2(y,x) deg2rad rad2deg sinh cosh tanh asinh acosh atanh`
Complex argument ⇒ principal value in complex plane.

## 4. Arrays (vectors & matrices)

- `[1;2;3]` = column vector (semicolons = rows); `[1,2,3]` = 1×3 row matrix (commas = columns in a row).
- Operators: `*  /  \  ^` are matrix ops; `.*  ./  .\  .^` are elementwise; `+ -` always elementwise.
- `A \ b` solves `Ax=b` (LU for square, least-squares otherwise); singular ⇒ `SingularMatrix` error.
- `A'` transpose (no conjugate); `adjoint(A)` conjugate transpose; `dot(u,v)` inner product (conjugates u).
- Construction: `zeros(m,n)`, `ones(m,n)`, `eye(n)`, `linspace(a,b,n)`, `rand(m,n)`, `range(a,b,h)`.
- Block literals: `[I, 2*I; zeros(1,4)]` composes blocks.
- Reductions: `sum prod mean min max` — whole array, or `sum(A,1)` cols / `sum(A,2)` rows.
- `sort(x)`, `sort(x,"descend")`, `sortperm(x)`.
- Broadcasting: size-1 dimensions stretch to match (scalar↔array, row↔matrix).
- `size(A)` → `(rows, cols)`, `size(A,d)`; `length(A)` total elements; `reshape(A,m,n)` (column-major).
- Append: `append(v, x)` (amortized O(1) in place if `v` unshared) or `[v; x]` (always copies — slower in a loop).

### Indexing
- `v[2]`, `w[end]`, `w[end-1]`, `w[2:4]` (range slice).
- `A[2,:]` row, `A[:,end]` last col, `A[A > 5]` boolean mask (column-major order).
- Index out of bounds ⇒ `IndexError` (never wraps, never auto-grows).
- Assignment to slice/element only mutates that variable; scalar RHS broadcasts into selection.

## 5. Strings

- Double-quoted, concatenate with `+`, index by character (`name[1]`, `name[2:3]`).
- `string(x)` → display form of any value as string.
- Immutable (build new strings instead of mutating).
- Compare `==`, order `<`.
- Escapes: `\t`, `\"`, etc.

Key string functions: `split(s)` / `split(s,sep)`, `trim/ltrim/rtrim`, `join(list,sep)`, `upper/lower`, `contains/startswith/endswith`, `find(s,p[,start])`, `replace(s,old,new)`, `repeat(s,n)`, `int(s)`/`real(s)` (parse numbers; accepts `NaN`/`Inf`/`-Inf`), `parse_function(params,expr)` (builds a function from text).

## 6. Printing/formatting

- `println(a,b,...)` — space-separated + newline; `print` — no newline.
- `format(x, d)` → string with exactly `d` decimal digits.
- `fmt` module (`import fmt`): `fmt.set_decimals(n)`, `fmt.set_size(rows,cols)`, `fmt.set_header(false)`, `fmt.set_sci(small,large)` — all reset with no args.

## 7. Control flow

```
if cond
  ...
elseif cond2
  ...
else
  ...
end

for x in iterable      # range, array (col-major), list, string chars, or dict keys
  ...
end

while cond
  ...
end
```
`break`, `continue`. Conditions must be strict `bool` (no truthiness; use `all`/`any` for bool arrays). Boolean words: `and`, `or`, `not`. One-liner allowed: `if x > 0 return 1 end`.

## 8. Functions

```axon
function name(a, b = default; kw1 = v1, kw2 = v2)
  return result
end
```

- Params after `;` are **keyword-only**, passed by name at call site (no `;` in the call): `f(2.0, rate=0.1)`.
- Positional params with defaults must come after all required ones; default `nothing` is a common "optional" sentinel checked via `typeof(x) == "nothing"`.
- Multiple returns: `return a, b` unpacked as `[lo, hi] = f(...)`.
- Named functions are hoisted (usable before their definition in the file).
- Anonymous functions (lambdas): `function(x) return 2*x end` — captures enclosing variables **by reference** (can read/mutate them later).
- Scope: vars first assigned in a function are local; `global x` to assign an outer var from inside a function; `local x` forces a fresh local. Recursion limit: 10,000 deep (`RecursionError` beyond that).

## 9. Collections

- **List** `{1, "two", 3.0}` — mixed types, vector-like indexing, `append(l, x)`.
- **Record** `{a: 1.0, b: "x"}` — dot access/assignment (`p.c = 0.075` adds a field).
  - Declared record type:
    ```axon
    record Species
      name: string
      init: real
    end
    s = Species("glucose", 10)       # fields type-checked/widened
    t = Species(name="ATP", init=2.5)
    ```
- **Dict** `dict("Km"=>0.5, "Vm"=>10.0)` — `d[key]` read/write (missing key ⇒ `KeyError`), `get(d,key,default)`, `haskey(d,key)`, `keys(d)` (insertion order), iterable with `for k in d`.

## 10. Errors

```axon
try
  ...
catch err
  # err.kind (string), err.message, err.trace
end
```
Raise with `error("msg")` (→ `UserError`), `error(kind, msg)`, or re-raise a caught error with `error(err)`.

**Error kinds:** `ArgumentError DimensionError DomainError FieldError ForeignError ImportError IndexError IOError KeyError NameError OverflowError RecursionError SingularMatrix SolverError SyntaxError TypeError UserError`

## 11. Modules

```axon
import linalg                 # linalg.det(...)
import random as rnd          # rnd.seed(1)
from linalg import eig, det   # direct names
```
- A `.sci` file is a module named after the file; a folder is a namespace (`mymodels/kinetics.sci` → `mymodels.kinetics`).
- `export` marks definitions visible to importers; a `##` doc block at file top documents the module.
- Lookup order: importing file's folder → packages in nearest `package.toml` → standard library.

**Standard library modules:**

| Module | Contents |
|---|---|
| `linalg` | solve, det, inv, eig, svd, qr, lu, chol, rank, null, norm, expm, threads |
| `ode` | `ode.solve` — ODE integration (RK45 explicit, BDF stiff), events, dense output |
| `nonlin` | `nonlin.solve` — nonlinear root-finding (Newton/KINSOL) |
| `plot` | line/scatter/bar/histogram/surface/3D plots, subplots; PNG/SVG/PDF |
| `random` | seeded uniform/normal/int random draws |
| `time` | clocks and benchmarking |
| `io` | file/CSV/JSON read-write |
| `fmt` | display/formatting settings |
| `graphics` | low-level drawing layer under `plot` |

## 12. Linear algebra (`linalg` + built-ins)

Built-in (no import): `tr(A)` (=`A'`), `trace(A)`.
`linalg` module: `solve(A,b)`, `lstsq(A,b)`, `det(A)`, `inv(A)`, `eig(A; vectors=false)`, `svd(A)` → `U,s,V`, `qr(A)` → `Q,R`, `lu(A)` → `L,U`, `chol(A)` → `R` (upper, `A=R'R`), `rank(A; tol)`, `null(A; tol)`, `norm(x; p=2)` (`"inf"`/`"fro"` for matrices), `expm(A)`, `threads()`/`set_threads(n)`.

**Sparse:** `sparse(i,j,v,m,n)`, `sparse(A)`, `speye(n)`, `nnz(S)`, `full(S)`, `splu(S)`.

## 13. ODEs & nonlinear solving

```axon
sol = ode.solve(f, y0, tspan; method="rk45"|"bdf", rtol=1e-6, atol=1e-9,
                t_eval=..., events=g, terminal=false, direction=0,
                names=[...], max_step=, first_step=, max_steps=100000, params=p)
# f(t, y) or f(t, y, params) -> derivative vector
```
Result record fields: `t`, `y` (matrix, one col/time), `at(t)` (interpolate), `status` (`"success"`/`"event"`), `t_events`/`y_events`, `names`, `nsteps`, `nfev`, `method`.

Stepwise: `s = ode.integrator(f, method="bdf"); y = ode.advance(s, t, y, t+h, params=p)`.

```axon
res = nonlin.solve(f, x0; method="linesearch"|"newton", ftol=1e-10, xtol=1e-12,
                    max_iters=200, params=p)
# f(x) or f(x, params) -> residual vector; solves f(x) = 0
```
Result: `x`, `status`, `fnorm`, `nfev`, `niters`. Failure ⇒ `SolverError`.

## 14. Random numbers

`random.seed(n)`; `rand(...)` uniform [0,1); `randn(...)` std normal; `uniform(a,b,...)`; `normal(mu,sigma,...)`; `randint(lo,hi,...)`. Trailing args give shape: none=scalar, `n`=vector, `m,n`=matrix.

## 15. Files & data (`io` module)

`io.read_file/write_file(path,text)`, `io.read_lines(path)` → list of strings, `io.read_csv(path[,sep])` → `{data, names}`, `io.write_csv(path,A,names[,sep])`, `io.write_json/read_json(path,value)`, `io.file_exists`, `io.delete_file` (→ bool), `io.current_dir()`/`set_current_dir(path)`, `io.read_bytes(path)`. Failures raise `IOError`.

CSV: empty field → `NaN`; test NaN via `x != x`. JSON: round-trips records/lists/vectors/matrices/numbers/strings (not complex, sparse, or functions).

## 16. Plotting (`plot` module)

`import plot` first. All plotting calls add to the **current figure**. There is no "axes object" to pass around — every function is called as `plot.xxx(...)`, operating on whatever figure/subplot cell is currently selected.

### Figure lifecycle
- `plot.figure(title = "...", width = 640, height = 480)` — starts a **new** figure. Sizes are in points (1/72 inch); default 640×480. (`plot.new(...)` is an identical alias, same keyword args — "figure" for matplotlib/MATLAB users, "new" otherwise.)
- `plot.clear()` — clears the data from the current figure but **keeps the frame** (size, title, labels, axis limits). Nothing is shown. Use this to redraw in a loop.
- `plot.show()` — displays the current figure (IDE plot pane, or system image viewer if run standalone). **You rarely need to call it**: a figure that changed since it was last shown/saved is shown automatically when the program ends or when `plot.figure()`/`plot.new()` starts the next one. It does **not** clear the figure — plotting after `show()` adds to the same figure and re-shows everything.
- `plot.save(path)` — writes the current figure to `.png`, `.svg`, or `.pdf` (format from the extension). `plot.save(path, scale = 3)` sets PNG pixels-per-point. `plot.save(path, figure = f)` saves a figure record saved earlier via `plot.gcf()`, even after other figures have since been drawn.
- `plot.gcf()` — returns the current figure as a **record**: size, title, axis labels, and a `series` list (each series itself a record with its data/style, e.g. `.type`, `.label`). Save it to a variable to re-save later.

```axon
import plot
plot.figure(title = "Growth", width = 500, height = 300)
plot.xlabel("t")
plot.ylim(0, 3)
t = linspace(0.0, 1.0, 50)
for rate in {0.5, 1.0}
  plot.clear()                                   # same frame, no data
  plot.line(t, exp(rate * t), label = "rate " + string(rate))
  plot.show()                                    # one picture per rate
end
```

### Line plots
`plot.line(x, y, label=, color=, width=, style=, marker=)`
- `style`: `"-"` (solid, default), `"--"`, `":"`, `"-."`
- `marker`: `"circle"`, `"square"`, `"diamond"`, `"triangle"`, `"plus"`, `"cross"`
- Series without an explicit `color` get the next of 10 default colors in rotation (see palette below).

### Scatter plots
`plot.scatter(x, y, label=, color=, size=, marker=)`

### Bar charts
`plot.bar(x, heights, width=0.8)` — bar of each height centered at each `x` position.
- `plot.bar(y)` (heights only) → bars placed at 1, 2, 3, …
- If `x` is a list of **strings**, bars go at 1, 2, 3, … and the axis is labeled with those names automatically.
- For grouped/side-by-side bars: shift the `x` values for each group, narrow `width`, then label with `plot.xticks(positions, labels)`.

### Histograms
`plot.hist(x, bins=10)` — equal-width bins by default; `bins` can also be a vector of explicit edges. `plot.hist_density(x, bins=10)` — same but scaled so total bar area = 1 (for comparing against a density curve). Both **return a record**: `.counts`, `.edges`, `.heights`.

### Surfaces & 3D
- `plot.surface(x, y, Z, colormap="viridis"|"plasma"|"coolwarm"|"gray"|"jet")` — height `Z[i,j]` above point `(x[j], y[i])` (note index order), colored by height (or by `color_by`, a matrix the shape of `Z`).
- `plot.bar3(x, y, Z, ...)` or `plot.bar3(Z)` — 3D bars: a bar at `(x[j], y[i])` from 0 to `Z[i,j]` (down for negative values), colored by height through `colormap`, or all one `color`; `width` is a fraction of the grid spacing (default 0.8).
- `plot.line3(x, y, z, ...)` — 3D curve (e.g. a trajectory); same style/color/width keywords as `line`.
- `plot.scatter3(x, y, z, ...)` — 3D markers.
- `plot.view(azim, elev)` — viewing direction in degrees (like MATLAB's `view`).
- `plot.zlabel("...")` — labels the vertical axis (in addition to `xlabel`/`ylabel`).
- **A single figure cannot mix 3D series with 2D series.** 3D and 2D plots must be separate figures (or separate subplot cells).
- In the IDE, 3D figures are interactive (drag to rotate).

### Labels, limits, legend, grid
- `plot.title("...")`, `plot.xlabel("...")`, `plot.ylabel("...")`, `plot.zlabel("...")` (3D only).
- `plot.xlim(lo, hi)`, `plot.ylim(lo, hi)` — fix axis range; otherwise each axis defaults to the data range padded by 5%.
- `plot.xticks(positions, labels)` — custom tick positions + names (mainly for grouped bar charts).
- `plot.grid(false)` — hide grid (default shown). `plot.grid(true)` to re-show.
- `plot.legend(false)` — hide legend. The legend only lists series that were given a `label=`.
- `plot.legend_position("best"|"top right"|"top left"|"bottom right"|"bottom left"|"outside")` — `"best"` (default) picks the corner hiding least data; `"outside"` places it to the right of the plot.

### Colors
A color is one of: a **name** (below), a hex string `"#rrggbb"` (or `"#rrggbbaa"` for opacity), or a vector `[r, g, b]` with components 0–1.

Default rotation order (series with no explicit `color` cycle through these 10, in order — so `color = "blue"` matches the first default):
`"blue" "orange" "green" "red" "purple" "brown" "pink" "gray"(or "grey") "olive" "cyan"`

Other named colors: `"yellow" "black" "white" "lightgray" "darkgray"`.

### Subplots
`plot.subplot(rows, cols, k)` — splits the current figure into a `rows × cols` grid and makes cell `k` current; subsequent plotting calls (`line`, `scatter`, labels, limits, etc.) target that cell only. Cells are numbered **along each row from the top-left** (MATLAB order): in a 2×2 grid, cells 1,2 are the top row. Each cell has its own axes/labels/legend/limits. 2D and 3D cells **can** be mixed within the same subplot grid (just not within one cell). The `title` passed to `plot.figure()` labels the whole grid. Re-selecting a cell (`plot.subplot(r,c,k)` again) resumes adding to what's already drawn there. The whole grid saves/shows as one figure.

```axon
import plot
plot.figure(title = "Two waves")
x = linspace(0.0, 2*pi, 100)
plot.line(x, sin(x), label = "sin")
plot.line(x, cos(x), label = "cos", style = "--")
plot.save("waves.png")        # .png, .svg or .pdf
plot.save("waves.pdf")
```

```axon
import plot
plot.figure(title = "Grid", width = 800, height = 600)
plot.subplot(2, 2, 1)
plot.line(x, sin(x))
plot.subplot(2, 2, 2)
plot.scatter(x, cos(x))
plot.subplot(2, 2, 3)
plot.bar([1,2,3], [4,5,6])
plot.subplot(2, 2, 4)
plot.hist(randn(1000))
plot.show()
```

### Common AI mistakes to avoid
- Do **not** invent an object-oriented/axes API (no `ax = plot.axes()`, no `fig, ax = plot.subplots()`). Everything is a direct `plot.xxx(...)` call acting on the current figure/cell.
- `plot.figure()`/`plot.new()` start a figure — they do **not** display it; `plot.show()` displays, but is usually unnecessary since display is automatic at figure-end/program-end.
- `plot.show()` does not clear the figure — call `plot.clear()` (keeps frame) if you want to redraw fresh in a loop.
- Bar/line/scatter take **plain vectors**, not a dict of options; keyword args (`label=`, `color=`, etc.) are passed directly in the call, not in a separate styling step.
- A figure cannot contain both 2D and 3D series together — put 3D plots in their own figure or subplot cell.
- Subplot cells are numbered row-major from the top-left, like MATLAB, not column-major.
- `plot.hist`/`plot.hist_density` **return a record** (`counts`, `edges`, `heights`) — don't discard the return value if you need the bin stats.

## 17. Performance notes

- Hot loops / numeric functions are JIT-compiled to native code automatically.
- `time.bench(f, args...)` benchmarks reliably; `time.elapsed(f,args...)` times one call; `time.clock()` high-res timer.
- Building arrays: prefer `v = append(v, x)` in a loop (in-place when unshared) over `v = [v; x]` (always copies).

## 18. Quick built-in function index

- **Arrays:** `zeros ones eye rand linspace range size length reshape eltype sum prod mean min max all any dot tr trace adjoint sort sortperm`
- **Sparse:** `sparse speye nnz full splu`
- **Math:** `sqrt exp log log10 log2 sin cos tan asin acos atan atan2 deg2rad rad2deg sinh cosh tanh asinh acosh atanh abs factorial`
- **Rounding/int:** `int floor ceil round div mod`
- **Complex:** `complex real imag conj arg`
- **Text/output:** `print println format string split join trim ltrim rtrim upper lower contains startswith endswith find replace repeat parse_function int(s) real(s)`
- **Collections:** `append dict get haskey keys`
- **Other:** `typeof isequal isa error keep atexit`
- **Constants:** `pi e`

---
*Condensed from the Axon User Manual (LaTeX source). Covers core language, numeric computing, text, files, plotting, and performance chapters; omits IDE/editor-specific and tutorial/case-study walkthroughs.*
