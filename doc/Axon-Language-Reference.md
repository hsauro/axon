# Axon Language Reference

Nov 7, 2026 · Herbert Sauro

## Contents

- [Scope and notation](#scope-and-notation)
- [Lexical structure](#lexical-structure)
  - [Identifiers and keywords](#identifiers-and-keywords)
  - [Numeric literals](#numeric-literals)
  - [Strings](#strings)
  - [Comments](#comments)
  - [Characters outside tokens](#characters-outside-tokens)
  - [Newlines and continuation](#newlines-and-continuation)
- [Grammar](#grammar)
  - [Programs and statements](#programs-and-statements)
  - [Control flow](#control-flow)
  - [Functions, records and modules](#functions-records-and-modules)
  - [Expressions](#expressions)
  - [Parsing notes](#parsing-notes)
- [Operator precedence](#operator-precedence)
- [Values, types and conversions](#values-types-and-conversions)
  - [Numeric promotion](#numeric-promotion)
  - [Vectors and matrices](#vectors-and-matrices)
  - [Strings](#strings-1)
  - [Truth values](#truth-values)
  - [Display](#display)
  - [Printing](#printing)
- [Arithmetic, broadcasting and comparison](#arithmetic-broadcasting-and-comparison)
  - [Linear-algebra operators](#linear-algebra-operators)
  - [Broadcasting](#broadcasting)
  - [Sparse operands](#sparse-operands)
  - [Comparison](#comparison)
  - [Logical operators](#logical-operators)
- [Indexing and ranges](#indexing-and-ranges)
  - [Ranges](#ranges)
  - [Index forms](#index-forms)
  - [Indexed assignment](#indexed-assignment)
  - [Lists, records and dictionaries](#lists-records-and-dictionaries)
- [Assignment, copy semantics and scoping](#assignment-copy-semantics-and-scoping)
  - [Value semantics](#value-semantics)
  - [Typed variables](#typed-variables)
  - [Scopes](#scopes)
  - [Closures](#closures)
- [Functions and calls](#functions-and-calls)
  - [Argument binding](#argument-binding)
  - [Argument passing and returns](#argument-passing-and-returns)
  - [Overloading](#overloading)
  - [Recursion and evaluation order](#recursion-and-evaluation-order)
- [Errors](#errors)
- [Standard modules](#standard-modules)
  - [The linalg module](#the-linalg-module)
  - [The io module](#the-io-module)
  - [The time module](#the-time-module)
  - [The random module](#the-random-module)
  - [The graphics module](#the-graphics-module)
  - [The ode module](#the-ode-module)
  - [The plot module](#the-plot-module)
- [Modules and foreign functions](#modules-and-foreign-functions)
  - [Modules](#modules)
  - [Foreign functions](#foreign-functions)
- [Compilation](#compilation)
- [The REPL](#the-repl)
- [Decisions made in this draft](#decisions-made-in-this-draft)

## Scope and notation

This reference defines the syntax and semantics of Axon precisely enough to implement the interpreter and to write conformance tests against. The [Axon White Paper](Axon-White-Paper.md) gives the rationale; this document gives the rules, and [Axon Milestones](Axon-Milestones.md) sets the order in which they are implemented.

- **Grammar notation.** The grammar uses EBNF: `{ x }` means zero or more repetitions, `[ x ]` means optional, `|` separates alternatives, and quoted text is a literal token.
- **Token names.** Upper-case names such as `IDENT`, `NUMBER` and `NEWLINE` are tokens produced by the lexer.
- **Normative words.** "Error" means the implementation must raise the named error kind (see Errors). "Undefined" is never used, because every construct either has a defined result or raises an error.

## Lexical structure

Source text is UTF-8. Files use the `.sci` extension, and `.txt` files are also accepted as source.

### Identifiers and keywords

```
IDENT = letter { letter | digit | "_" } ;     letter = "A"…"Z" | "a"…"z" | "_"
```

Identifiers are case-sensitive. The reserved keywords are:

`function` `end` `return` `if` `elseif` `else` `for` `in` `while` `break` `continue` `local` `global` `try` `catch` `import` `from` `as` `export` `extern` `record` `true` `false` `nothing` `and` `or` `not`

The words `type`, `ref`, `ptr`, `callback` and `name` are keywords only inside an `extern` block.

### Numeric literals

```
INT    = digit { [ "_" ] digit } ;
REAL   = INT "." INT [ exponent ] | INT exponent ;
exponent = ( "e" | "E" ) [ "+" | "-" ] INT ;
IMAG   = ( INT | REAL ) "i" ;
```

- A real literal needs a digit on both sides of the point: `0.5` and `1.0` are valid, while `.5` and `1.` are a `SyntaxError`. A number followed by `.*`, `./`, `.\` or `.^` is an integer followed by that operator, so `1.*x` is `1 .* x`. These rules keep `1.+x` and `A.*B` unambiguous.
- `_` may separate digits for readability, as in `1_000_000`. It must sit between two digits.
- `IMAG` applies only when `i` follows the number directly and is not followed by an identifier character. `2i` and `2.5e-3i` are imaginary literals. `i` on its own is an ordinary identifier, and `2in` is the integer `2` followed by the keyword `in`.
- An integer literal must fit in a 64-bit `int` and a real literal in a finite `real`; otherwise it is a `SyntaxError`.
- A real literal (and the number in an imaginary one) denotes the double nearest to its exact decimal value, with ties going to the double whose last bit is 0. Any number of digits may be written, and every digit counts, so the 17 significant digits that identify a double always read back as that double. A literal too small for a subnormal is `0.0`.

### Strings

Strings are enclosed in double quotes, with the escapes `\n`, `\t`, `\"`, `\\` and `\u{X…}`, where `X…` is one to six hex digits naming a Unicode code point. Any other escape is a `SyntaxError`, and so is a line break before the closing quote: a string cannot span lines. There is no single-quoted string form, so `'` is always the transpose operator.

### Comments

- `#` starts a comment that runs to the end of the line.
- `#=` … `=#` encloses a block comment, which may span lines and may be nested.
- `##` at the start of a line (after optional spaces) begins a documentation comment, which the lexer keeps as a `DOCSTRING` token. Consecutive `##` lines directly above a `function` or `record` form its docstring. A `##` block at the very start of a file, before any statement and followed by a blank line, is the module's docstring. Elsewhere on a line, `##` is an ordinary comment.
- A block comment that spans lines still ends those lines: the lexer emits a `NEWLINE` for each line end inside it.

### Characters outside tokens

Spaces and tabs separate tokens. Outside strings and comments, any character that does not begin a token is a `SyntaxError`, including non-ASCII letters and a lone `!` (negation is written `not`).

### Newlines and continuation

The lexer emits a `NEWLINE` token at every line end and makes no decisions about it. The parser decides what a `NEWLINE` means, because it already knows which construct it is in:

1. Inside `( )`, `[ ]` or `{ }`, the parser skips `NEWLINE` tokens, so matrix rows must be separated with `;`.
2. Inside the body of any block (`function`, `if`, `for`, `while`, `try`, `record`, `extern`), `NEWLINE` terminates statements again, even when the block itself sits inside brackets, as with an anonymous function passed as an argument.
3. After a binary operator or a comma, the parser skips `NEWLINE` tokens, so the expression continues on the next line.
4. The terminator before `end`, `elseif`, `else` and `catch` is optional, so `function(x) return x^2 end` is valid on one line.

A `;` outside brackets also terminates a statement. At the REPL, an expression statement ending in `;` does not display its value.

## Grammar

### Programs and statements

```
program      = { [ statement ] terminator } [ statement ] ;
terminator   = NEWLINE | ";" ;
block        = { [ statement ] terminator } [ statement ] ;

statement    = declaration | assignment | expression
             | if_stmt | for_stmt | while_stmt | try_stmt
             | function_def | record_def | import_stmt | extern_block
             | "return" [ expression { "," expression } ]
             | "break" | "continue" ;

declaration  = ( "local" | "global" ) IDENT [ ":" type ] [ "=" expression ] ;
assignment   = target [ ":" type ] "=" expression
             | "[" target { "," target } "]" "=" expression ;
target       = IDENT { "[" index_list "]" | "." IDENT } ;
```

### Control flow

```
if_stmt      = "if" expression [ terminator ] block
               { "elseif" expression [ terminator ] block }
               [ "else" block ] "end" ;
for_stmt     = "for" IDENT "in" expression [ terminator ] block "end" ;
while_stmt   = "while" expression [ terminator ] block "end" ;
try_stmt     = "try" block "catch" [ IDENT ] terminator block "end" ;
```

### Functions, records and modules

```
function_def = [ "export" ] "function" IDENT "(" params ")" [ ":" type ] block "end" ;
lambda       = "function" "(" params ")" [ ":" type ] block "end" ;
params       = [ param { "," param } ] [ ";" kwparam { "," kwparam } ] ;
param        = IDENT [ ":" type ] ;
kwparam      = IDENT [ ":" type ] "=" expression ;

record_def   = [ "export" ] "record" IDENT terminator { field_decl terminator } "end" ;
field_decl   = IDENT ":" type ;
type         = IDENT [ "{" type "}" ] ;

import_stmt  = "import" dotted [ "as" IDENT ]
             | "from" dotted "import" IDENT { "," IDENT } ;
dotted       = IDENT { "." IDENT } ;

extern_block = "extern" STRING terminator { [ extern_item ] terminator } "end" ;
extern_item  = "function" IDENT "(" [ cparam { "," cparam } ] ")" [ ":" ctype ] [ "name" STRING ]
             | "type" IDENT "=" ctype ;
cparam       = IDENT ":" ctype ;
ctype        = IDENT | "ref" ctype | "ptr" ctype
             | "callback" "(" [ cparam { "," cparam } ] ")" [ ":" ctype ] ;
```

### Expressions

Each rule binds more tightly than the one above it (see Operator precedence).

```
expression   = or_expr ;
or_expr      = and_expr { "or" and_expr } ;
and_expr     = not_expr { "and" not_expr } ;
not_expr     = "not" not_expr | cmp_expr ;
cmp_expr     = range_expr [ cmp_op range_expr ] ;
cmp_op       = "==" | "!=" | "<" | "<=" | ">" | ">=" ;
range_expr   = add_expr [ ":" add_expr [ ":" add_expr ] ] ;
add_expr     = mul_expr { ( "+" | "-" ) mul_expr } ;
mul_expr     = unary { ( "*" | "/" | "\" | ".*" | "./" | ".\" ) unary } ;
unary        = ( "-" | "+" ) unary | power ;
power        = postfix [ ( "^" | ".^" ) unary ] ;
postfix      = primary { "(" [ args ] ")" | "[" index_list "]" | "." IDENT | "'" } ;

args         = arg { "," arg } ;
arg          = expression | IDENT "=" expression | expression "=>" expression ;
index_list   = index_item { "," index_item } ;
index_item   = ":" | expression ;

primary      = INT | REAL | IMAG | STRING | "true" | "false" | "nothing" | IDENT
             | "end"                       (* only inside an index_list *)
             | "(" expression ")" | matrix_lit | brace_lit | lambda ;
matrix_lit   = "[" [ row { ";" row } ] "]" ;
row          = expression { "," expression } ;
brace_lit    = "{" [ expression { "," expression } ] "}"
             | "{" IDENT ":" expression { "," IDENT ":" expression } "}" ;
```

### Parsing notes

- **Destructuring.** A statement starting with `[` is a destructuring assignment if the matching `]` is followed by `=`. Otherwise it is a matrix literal expression.
- **Field names.** Wherever the grammar takes a field name (after `.`, before `:` in a record literal, and in a `record` declaration), any keyword is accepted as well as an identifier, so `err.trace[1].function` and `{end: 3}` are valid. A `record` declaration cannot have a field named `end`, which would close it.
- **Braces.** A brace literal is a record if its first element has the form `name ":"` (a field name, see above), and a list otherwise. `{}` is the empty list. So `{a:b}` is a record with field `a`; a list holding the range `a:b` is written `{(a:b)}`.
- **Typed assignment.** A statement starting with `IDENT ":"` may be a typed assignment (`x: real = 0.0`) or an expression (`x:n`). The parser first tries to read a type followed by `=`; if that fails, it rewinds and parses an expression.
- **Optional terminator.** The last statement of a block needs no terminator before `end`, `elseif`, `else` or `catch`, as the final `[ statement ]` in `block` shows.
- **One-line headers.** The terminator after an `if`, `elseif`, `while` or `for` header is optional, so `if x > 0 return 1 end` is valid. The condition is the longest expression that parses, so a body that begins with `(`, `[`, `-`, `+` or `'` continues the condition. In `if f (x) end`, `f (x)` is a call; write `if f; (x) end` or use a new line. `catch` still needs a terminator after its name, because in `catch err x = 1` the name and the statement could not be told apart.
- **Keyword arguments.** In an argument list, `IDENT "="` begins a keyword argument. Keyword arguments must follow all positional arguments.
- **Pairs.** `=>` forms a key–value pair and is valid only as a function argument, as in `dict("Km" => 0.5)`.
- **`end` in indices.** Inside `[ ]` index brackets, `end` is an expression, not a block terminator. This context resets inside any block body. The parser makes this decision; the lexer emits `end` as a keyword in both cases.

## Operator precedence

The table runs from tightest binding (level 1) to loosest (level 10).

| Level | Operators | Associativity | Notes |
| --- | --- | --- | --- |
| 1 | `f(…)` `A[…]` `r.x` `A'` | Left | Calls, indexing, field access, transpose |
| 2 | `^` `.^` | Right | The exponent may carry a unary sign: `2^-1` |
| 3 | `-x` `+x` | Prefix |  |
| 4 | `*` `/` `\` `.*` `./` `.\` | Left |  |
| 5 | `+` `-` | Left | Elementwise, with broadcasting |
| 6 | `a:b` `a:h:b` | None | Range; chained `a:b:c:d` is an error |
| 7 | `==` `!=` `<` `<=` `>` `>=` | None | Elementwise on arrays; chained `a < b < c` is an error |
| 8 | `not` | Prefix |  |
| 9 | `and` | Left | Short-circuits on scalars |
| 10 | `or` | Left | Short-circuits on scalars |

Worked cases:

| Expression | Parses as | Value |
| --- | --- | --- |
| `-2^2` | `-(2^2)` | `-4` |
| `2^3^2` | `2^(3^2)` | `512` |
| `2^-1` | `2^(-1)` | `0.5` |
| `A'*B` | `(A')*B` |  |
| `a:b+1` | `a:(b+1)` |  |
| `1:n-1` | `1:(n-1)` |  |
| `A > 0 and A < 5` | `(A > 0) and (A < 5)` | Logical mask |
| `not x == y` | `not (x == y)` |  |
| `x = y == z` | `x = (y == z)` | `=` is a statement, not an operator |

`=`, `=>` and the keyword-argument `=` are not operators. They appear only where the grammar places them.

## Values, types and conversions

The data types and their literals are listed in the white paper's [Data types](Axon-White-Paper.md#data-types) table. This section fixes the rules that table leaves open.

### Numeric promotion

Mixed arithmetic promotes along `bool` → `int` → `real` → `complex`. Nothing is ever demoted implicitly. Assigning a `real` to a variable annotated `int` is an error; explicit conversion uses `int(x)` (which truncates toward zero), `round(x)`, `real(z)` or `complex(x)`.

- **Division.** `/` on two `int` values gives a `real`: `5/2` is `2.5`. Integer division is `div(a, b)` and the remainder is `mod(a, b)`.
- **Overflow.** `int` arithmetic that overflows 64 bits raises `OverflowError`.
- **Domain errors.** Real-valued functions outside their domain return NaN: `sqrt(-1.0)` and `log(-1.0)` are NaN, never complex. A complex argument gives the principal value.
- **Integer powers.** `int ^ int` with a non-negative exponent is `int`. A negative exponent gives a `real`.
- **Floored division.** `div(a, b)` is `floor(a / b)` and `mod(a, b)` is `a - div(a, b)*b`, so `mod` takes the sign of `b` and `a == div(a, b)*b + mod(a, b)` always holds: `div(-7, 2)` is `-4` and `mod(-7, 2)` is `1`. Both give an `int` for `int` arguments and a `real` otherwise. An `int` divisor of zero raises `DomainError`; a `real` divisor of zero gives NaN.
- **Rounding to integers.** `floor`, `ceil`, `round` and `int` return an `int`. `round` rounds halves away from zero, so `round(2.5)` is `3` and `round(-2.5)` is `-3`, and `int` truncates toward zero. A NaN argument raises `DomainError`, and a value outside the 64-bit range raises `OverflowError`.
- **Minimum and maximum.** `min(a, b)` and `max(a, b)` on scalars promote like arithmetic and return NaN if either argument is NaN. Complex arguments raise `TypeError`.
- **Floating-point exceptions.** Real arithmetic follows IEEE 754 and never raises: `1.0/0.0` is `Inf`, `0.0/0.0` is NaN, and overflow gives `Inf`.

### Vectors and matrices

- **Shapes.** `[1; 2; 3]` is a `vector` of length 3. `[1, 2, 3]` is a 1×3 `matrix`. A vector behaves as an n×1 column wherever a shape is needed.
- **Products.** `A * v` with an m×n matrix and a vector of length n gives a vector of length m. `v'` is a 1×n matrix, and `v' * w` gives a scalar.
- **Element types.** A matrix literal takes the widest element type of its entries. Any complex entry makes the whole matrix complex.
- **Concatenation.** Entries of a matrix literal may themselves be matrices, which are concatenated as blocks. Every row must have the same total width, and each block within a row the same height, or a `DimensionError` is raised.
- **Empty matrix.** `[]` is a 0×0 `real` matrix.
- **Vector literals.** A literal whose rows each hold exactly one entry, every entry a scalar, a vector or a range, is a vector made by stacking them: `[5]` is a vector of length 1 and `[v; 7]` appends 7 to the vector `v`. Any other literal is a matrix built by block concatenation, in which a vector or range counts as an n×1 block and an empty `[]` block is skipped. Entries must be numbers or `bool`s; anything else raises `TypeError`.
- **Constructors.** `zeros(m, n)` and `ones(m, n)` give m×n `real` matrices, and `zeros(n)` and `ones(n)` give vectors of length n. `eye(n)` is the n×n identity and `eye(m, n)` its m×n form. `rand()`, `rand(n)` and `rand(m, n)` give uniform reals in [0, 1), from the generator of the random module, so `random.seed` makes them repeat. `linspace(a, b, n)` gives a `real` vector of n points from a to b inclusive. A negative or non-integer size raises `ArgumentError`.
- **Size.** `size(A)` returns two values, the row and column counts, so it is used as `[m, n] = size(A)`; a vector has n rows and 1 column, and a scalar is 1×1. `size(A, 1)` and `size(A, 2)` return one count. `length(A)` is the total number of elements, which is also the value of `end` in a single (linear) index.
- **Shape helpers.** `reshape(A, m, n)` returns an m×n matrix holding the elements of `A` in column-major order, and `reshape(A, n)` a vector; the element count must match, or `DimensionError` is raised. `eltype(A)` gives the element type of an array (`"bool"`, `"int"`, `"real"` or `"complex"`), or the type of a scalar number.
- **Reductions.** `sum`, `prod`, `mean`, `min`, `max`, `all` and `any` on one array reduce over every element to a scalar. `sum(A, d)`, `prod(A, d)` and `mean(A, d)` reduce along dimension `d`: `mean(A, 1)` is the 1×n row of column means and `mean(A, 2)` the m×1 column of row means. `min(a, b)` and `max(a, b)` with two arguments work elementwise with broadcasting. `min` and `max` of an empty array raise `ArgumentError`; `all` of an empty array is `true` and `any` is `false`. `all` and `any` need `bool` elements.
- **Iteration.** `for x in A` visits the elements of an array in column-major order.

### Strings

`+` concatenates two strings. `string(x)` converts any value to its display form. Strings are immutable, and indexing a string returns a one-character string.

### Truth values

Conditions in `if` and `while` must be a scalar `bool`. A `bool` array in a condition is a `TypeError`; use `all(M)` or `any(M)`. There is no truthiness for numbers, strings or empty collections.

### Display

Output tests compare text exactly, so every value has one display form.

| Value | Display | Examples |
| --- | --- | --- |
| `int` | Plain digits | `5`, `-42` |
| `real` | Up to 15 significant digits, always with a decimal point; exponent form below 1e-4 or from 1e15 in magnitude | `5.0`, `0.1`, `2.5`, `1.0e-10`, `6.02e23` |
| Special reals | Words | `NaN`, `Inf`, `-Inf` |
| `complex` | Each part as a `real`, joined by `+` or `-` | `3.0 + 4.0i`, `0.0 - 2.0i` |
| `bool` | Words | `true`, `false` |
| `nothing` | Word | `nothing` |
| `string` | Without quotes from `print` and `println`; with quotes at the REPL | `S1` / `"S1"` |
| `list` | Elements in braces, separated by ", " | `{1, "S1", 2.5}`, `{}` |
| `record` | Fields in braces as `name: value`, in definition order | `{name: "S1", init: 10.0}` |
| `range` | As written, with the step only when it is not 1 | `1:5`, `1:2:9`, `0.0:0.5:1.0` |
| function | `function` and its name; a lambda is anonymous | `function solve`, `anonymous function` |
| record type | `record type` and its name | `record type LVParams` |
| `module` | `module` and its name | `module linalg` |

Because reals are rounded to 15 significant digits, `0.1 + 0.2` displays as `0.3`. `print` and `println` write values in these forms; see [Printing](#printing). Inside a list or record, strings are always quoted, so `{"a b"}` and `{"a", "b"}` stay distinguishable. A dictionary displays as the call that builds it, `dict("Km" => 0.5, "Vm" => 10.0)`, with entries in insertion order; an empty one is `dict()`.

Arrays display as a header line, then one line per row with each entry right-aligned in its column and preceded by two spaces. The header is `R×C matrix{T}` or `N-vector{T}`. Elements show up to 6 significant digits, following the same rules as scalars, and complex elements show both parts that way. Above 10 rows, only the first and last 5 are shown, with a `  ⋮` line between; above 8 columns, only the first and last 4, with a `…` column between. An empty array shows only its header. At the REPL an assignment shows `A = ` before the header:

```
A = 2×2 matrix{int}
  1  2
  3  4
```

Inside a list or record, an array is shown inline in literal form, as in `{[1, 2; 3, 4], [1; 2]}`.

### Printing

Two prelude functions write to standard output:

| Call | Effect |
| --- | --- |
| `println(a, b, …)` | Writes the arguments separated by one space, then ends the line |
| `print(a, b, …)` | Writes the arguments separated by one space and leaves the line open |
| `println()` | Ends the current line without writing anything |

Each argument is written in its display form (see Display), with strings unquoted; any number of arguments of any type may be given, and both functions return `nothing`. Neither takes keyword arguments: the choice between ending the line or not is the choice of function. Output from `print` is continued by the next `print` or `println`, so a line can be built up in a loop:

```axon
println("x =", 3, 2.5, true)          # x = 3 2.5 true
for k in 1:3
  print(string(k) + " ")
end
println()                             # 1 2 3
println("Total: " + string(42))       # Total: 42
```

To control spacing exactly, build one string with `+` and `string(x)` and print that. An array argument is written in its full display form, header and rows, starting where the line is; inside a list or record it is written inline. At the REPL, and before an error report, a line that `print` left open is ended first, so prompts and messages always start on a new line. Error reports go to standard error, not standard output.

## Arithmetic, broadcasting and comparison

### Linear-algebra operators

| Expression | Requirement | Result |
| --- | --- | --- |
| `A + B`, `A - B` | Broadcast-compatible shapes (see Broadcasting) | Elementwise sum or difference |
| `A * B` | Columns of `A` equal rows of `B`, or either a scalar | Matrix product: each entry is a row of `A` dotted with a column of `B` |
| `A \ b` | Rows of `A` equal rows of `b` | Solution of `A x = b`; least squares if `A` is not square |
| `A / B` | Columns of `A` equal columns of `B` | `A * inv(B)`, computed as a solve |
| `A ^ k` | `A` square; `k` an integer, or any scalar for diagonalisable `A` | Matrix power |
| `A'` | Any | Plain transpose; no conjugation |

For complex data, `adjoint(A)` gives the conjugate transpose and `dot(u, v)` gives the inner product with `u` conjugated. For real vectors `u' * v` and `dot(u, v)` are equal.

A shape mismatch raises `DimensionError`. A singular or near-singular system in `\` or `/` raises `SingularMatrix`.

- **Implementation.** `*`, `\`, `/` and `^` are core operators that call BLAS and LAPACK (OpenBLAS) directly. Real and complex products use `dgemm` and `zgemm`. A product of `int` (or `bool`) matrices stays an exact, overflow-checked `int` computation. When OpenBLAS cannot be loaded, `*` falls back to a plain loop, and `\`, `/` and non-integer powers raise `ForeignError`.
- **Solving.** For square `A`, `A \ b` factorises `A` and raises `SingularMatrix` when it is singular or when its reciprocal condition number is below machine epsilon. For non-square `A` it returns the minimum-norm least-squares solution. The result is a vector when `b` is a vector and a matrix otherwise, and it is `real` unless either operand is complex. `A / B` is computed as `(B' \ A')'`.
- **Powers.** For an integer `k`, `A ^ k` multiplies by repeated squaring; `A ^ 0` is the identity and a negative `k` uses the inverse. An `int` matrix with `k >= 0` gives an `int` result. For any other scalar `k`, `A ^ k` is computed as `V diag(λ^k) V⁻¹` from the eigendecomposition. It raises `SingularMatrix` when `A` is not diagonalisable, and the result is real when `A` is real and the imaginary parts are negligible. A scalar raised to a matrix power raises `TypeError`.

### Broadcasting

Four operators carry a leading dot: `.*`, `./`, `.\` and `.^`. Each is the element-by-element form of an operator whose plain form means the matrix operation. Broadcasting applies to these four, to `+` and `-`, to the comparisons, and to `and`, `or` and `not` on `bool` arrays:

1. A scalar combines with every element.
2. Two arrays are compatible if, in each dimension, their sizes are equal or one of them is 1. A vector counts as n×1.
3. The result's size in each dimension is the larger of the two sizes.

For example, `A - mean(A, 1)` subtracts each column's mean, because `mean(A, 1)` is 1×n. Incompatible sizes raise `DimensionError`. Prefix `-`, `not` and the elementary functions (`sin`, `exp` and so on) always apply elementwise.

### Sparse operands

A result is sparse when both operands are sparse, or when one is a scalar and the operation is `*` or `/`. Any other mix with a dense operand gives a dense result. `S'` is sparse.

- **Element types.** A sparse matrix holds `real` or `complex` values; `int` and `bool` values are stored as `real`. Stored entries are never exactly zero: a construction or an operation that produces a zero drops it.
- **Construction.** `sparse(i, j, v, m, n)` builds an m×n matrix from index vectors `i` and `j` and values `v` (a vector of the same length, or a scalar for every entry), summing the values of repeated `(i, j)` pairs. `sparse(i, j, v)` takes m and n from the largest indices, and `sparse(A)` converts a dense matrix. `speye(n)` and `speye(m, n)` are sparse identities, `nnz(S)` counts the stored entries (or the nonzeros of a dense array), and `full(S)` converts to a dense matrix.
- **Sparse results, precisely.** `+`, `-`, `.*` and `*` between two sparse matrices, `*`, `/`, `.*` and `./` with a scalar on the appropriate side (`2*S`, `S*2`, `S/2`), unary `-`, `'` and `adjoint` give sparse results. Elementwise `./`, `.\` and `.^` between two sparse matrices, and comparisons, give dense results, since they turn zeros into other values. Elementwise functions such as `sqrt` need `full(S)`.
- **Indexing.** `S[i, j]` with two scalars is an element and `S[k]` a linear element. Other selections with two indices give a sparse submatrix, and a single non-scalar index gives a dense vector. Indexed assignment works as for dense matrices; assigning zero removes an entry, and a complex value makes the matrix complex.
- **Solving.** `S \ b` factorises S with a sparse LU built into the interpreter and returns a dense result shaped like `b`. The factorisation uses a minimum-degree ordering on the pattern of `S + S'` to limit fill-in, and partial pivoting with a preference for the diagonal. `S / B`, `B / S` and `S ^ k` work as for dense matrices; `S ^ k` with an integer `k >= 0` stays sparse. A singular matrix raises `SingularMatrix`.
- **Display.** A sparse matrix displays its size, element type and number of stored entries (`3×3 sparse{real} with 4 stored entries`, or `1 stored entry`), then one line per entry in column-major order, `(i, j)  value`, with values shown as in dense arrays. Above 20 entries only the first and last 10 are shown, with `  ⋮` between. Inside a list or record it shows as `sparse(m×n, k stored)`.

### Comparison

- On scalars, `==`, `!=`, `<`, `<=`, `>` and `>=` return a `bool`. On arrays they apply elementwise with broadcasting and return a `bool` array.
- `==` and `!=` accept values of any two types. Values of unrelated types (a string and a number, or `nothing` and anything else) are unequal, so `"1" == 1` is `false`. Numbers of different types compare after promotion, so `1 == 1.0` and `1 == 1.0 + 0i` are `true`. Lists, records and dictionaries compare as whole values and give one `bool`.
- `isequal(a, b)` compares whole values and returns one `bool`. Arrays are equal when shapes and all elements are equal, and records when field names and values are equal.
- The order comparisons apply to real numbers and strings. Complex numbers have no ordering and raise `TypeError`.
- Comparisons involving NaN are false, except `!=`, which is true.

### Logical operators

`and`, `or` and `not` take `bool` operands; any other type raises `TypeError`.

- **Scalar left operand.** `and` and `or` short-circuit: in `a and b` the right operand is evaluated only when `a` is `true`, and in `a or b` only when `a` is `false`.
- **Array left operand.** Both operands are evaluated and combined elementwise with broadcasting, so `A[A > 0 and A < 5]` selects the elements between 0 and 5.
- **`not`** negates a scalar, or every element of an array.

## Indexing and ranges

### Ranges

- `a:b` is the sequence a, a+1, … up to and including b. It is empty when b < a.
- `a:h:b` steps by h, which may be negative or non-integer: `0:0.1:1` has 11 elements and `5:-1:1` counts down. A zero step raises `ArgumentError`.
- For real steps, the length is `floor((b - a)/h + 1e-10) + 1`, so `0:0.1:1` includes 1.0 despite rounding.
- A range is lazy and stores only its endpoints and step. It converts to a vector wherever a vector is required.

### Index forms

Indices are 1-based. Each position in an index list accepts one of these forms:

| Form | Selects |
| --- | --- |
| Integer `k` | Element k of that dimension |
| `:` | The whole dimension |
| Range or integer vector | Those elements, in the order given; repeats allowed |
| `bool` array of the same size | Elements where it is `true` |
| `end` | The size of that dimension, usable in expressions such as `end-1` |

- **Dimensions.** A vector takes one index and a matrix takes two. A single index on a matrix is linear and runs in column-major order.
- **Result shape.** Scalar indices drop their dimension: `A[2, :]` is a vector, `A[2, 3]` a scalar and `A[1:2, 3:4]` a 2×2 matrix. `A[mask]` is always a vector.
- **`end` binding.** `end` refers to the innermost object being indexed: in `A[B[end], end]` the first `end` is `length(B)` and the second is the column count of `A`.
- **Bounds.** An index below 1 or above the size raises `IndexError`. Reading never wraps or clips, and assignment never grows an array.

### Indexed assignment

`A[idx] = x` requires `x` to be a scalar, which is broadcast to every selected element, or an array with exactly the selected shape. When the selection is one-dimensional (a vector result, such as `A[2, :]` or `v[1:3]`), `x` may be any vector, 1×n matrix or n×1 matrix with the right number of elements. Anything else raises `DimensionError`. The element type of `A` may widen, so assigning `1i` into a real matrix makes it complex. Arrays grow only through `append(v, x)` or concatenation, both of which return a new value.

### Lists, records and dictionaries

- **Lists** index like vectors. A range index returns a sublist, and a scalar index returns the element. `l[k] = x` replaces an element, and a range or index-list selection can be assigned a list of the same length. `append(l, x)` returns a new list with `x` added at the end; `append(v, x)` does the same for a vector, with `x` a scalar or a vector.
- **Records** use only `.` field access. Reading a field that does not exist raises `FieldError`. Assigning to a field that does not exist raises `FieldError` for a declared record type and adds the field for a literal record.
- **Declared record types.** `record T … end` binds `T` in the outermost scope of the enclosing function or module, like a named function. A value of type `T` is made either by calling `T` with every field, by position in declaration order or by keyword (`LVParams(a = 1.0, b = 0.1, c = 0.075, d = 1.5)`), or by checking a literal record against the annotation `T` (`p: LVParams = {a: 1.0, …}`). Either way the fields must match the declaration exactly, missing or extra fields raise `FieldError`, and each field is checked and widened against its type. Assigning to a field of a declared record checks the new value against the field's type. `typeof` of such a record is the type's name.
- **Dictionaries** use `d[key]`. A missing key raises `KeyError`, and `get(d, key, default)` avoids that. `d[key] = x` adds or replaces an entry. Keys are strings or real numbers (`int`, `real` or `bool`); numeric keys compare by value, so `1` and `1.0` are the same key, and any other key raises `TypeError`. Entries keep their insertion order. `keys(d)` returns the keys as a list, `haskey(d, key)` tests for one, and `length(d)` counts entries. `=>` pairs are accepted only by `dict(...)`; anywhere else they raise `TypeError`.
- **Strings** index by character (Unicode code point): `s[k]` is a one-character string and a range gives a substring. Strings are immutable, so assigning through an index raises `TypeError`.
- **Iteration.** `for x in l` visits a list's elements, `for c in s` a string's characters, and `for k in d` a dictionary's keys in insertion order.
- **Equality.** `==` and `isequal` compare lists, records and dictionaries as whole values: lists elementwise in order, records by field names and values regardless of field order, and dictionaries by their sets of entries regardless of order.
- **Nested assignment.** An assignment target may chain indexing and fields to any depth, as in `species[2].name = "S3"` or `p.m[1, 2] = 0`. Value semantics hold at every level: only the variable assigned to changes, whatever other names share its parts.

## Assignment, copy semantics and scoping

### Value semantics

Every value has value semantics. After `B = A`, or after passing `A` as an argument, no write through one name is ever visible through the other. This holds for every type except functions, which are immutable.

The implementation uses copy-on-write. Each heap value carries a reference count, and a write to a value whose count is greater than 1 first copies it. Reads never copy. Returning a value transfers it without copying. The builtin `__copies()` returns the number of array copies made so far; it exists so that tests can check that reads and argument passing never copy.

### Typed variables

`x: T = e` declares `x` with type `T` in the current scope. Every later assignment to `x` is checked against `T`, and a mismatch raises `TypeError`. An untyped variable may hold values of any type over its lifetime.

- **Widening.** Wherever an annotation is checked (variables, parameters and return values), a value of type `T` is accepted, and so is a value that promotes to `T` along `bool` → `int` → `real` → `complex`, which is then converted. `x: real = 0` stores `0.0`, and `f(2)` is accepted by `function f(x: real)`. Narrowing is never implicit: a `real` where `int` is annotated raises `TypeError`.
- **Type names.** The annotation types are those of the data-types table (`bool`, `int`, `real`, `complex`, `string`, `nothing`, `range`, `function`, `vector`, `matrix`, `sparse`, `list`, `record`, `dict`) and declared record types. Any other name raises `TypeError`.
- **Declarations without a value.** `local x` binds `x` to `nothing`. `local x: T` without a value raises `TypeError` unless `nothing` satisfies `T`.

### Scopes

Scopes are created by function bodies and by the bodies of `if`, `for`, `while` and `try` blocks. Name resolution follows these rules, in order:

1. Parameters are local to their function.
2. `local x` creates `x` in the innermost scope, shadowing any outer `x`.
3. The loop variable of a `for` is local to the loop body, and a fresh binding is made on each iteration.
4. The name bound by `catch err` is local to the catch block.
5. Plain assignment `x = e` refers to the nearest enclosing `x` within the same function, or within enclosing functions for a closure. If none exists, it creates `x` in the function's outermost scope, so a variable first assigned inside an `if` is still visible after the `end`.
6. A named top-level function cannot assign script or module variables through rule 5: there, rule 5 stops at the function's own outermost scope, so a plain assignment creates a local. The function can still read every module-level name (variables, functions, imported modules), and it must declare `global x` to assign to a module variable. After `global x`, both reads and assignments of `x` in that function refer to the module variable, which an assignment creates if needed.
7. A name that resolves nowhere raises `NameError` when read.

A named function definition binds its name in the outermost scope of the function or module that contains it, even when it appears inside an `if` or a loop. A named function nested inside another function, and every anonymous function, is a closure and follows rule 5 into its enclosing scopes. Named functions at the top level of a module, including inside a top-level `if` or loop, follow rule 6.

### Closures

A `lambda` or a nested `function` captures the variables it uses from enclosing function scopes, or from the script's top level, by reference. Assignments through a capture are visible outside the closure, and later changes outside it are visible inside. A captured variable stays alive as long as any closure that captured it.

```
count = 0
tick = function() count = count + 1 end
tick(); tick()
count              # 2
```

## Functions and calls

### Argument binding

A call binds arguments in four steps:

1. Positional arguments bind to positional parameters left to right. Too many or too few raises `ArgumentError`.
2. Keyword arguments bind by name to keyword parameters. An unknown name, or a name given twice, raises `ArgumentError`.
3. Keyword parameters not supplied take their default. Defaults are evaluated at each call, in the function's defining scope, left to right, and may refer to earlier parameters.
4. Annotated parameters are checked against their types, and a mismatch raises `TypeError` naming the parameter.

Positional parameters cannot be passed by keyword, and keyword parameters cannot be passed by position.

### Argument passing and returns

Arguments have value semantics (see Assignment, copy semantics and scoping), and there are no out parameters.

- `return` with no value returns `nothing`, as does reaching the final `end`.
- `return a, b` returns several values. The caller must unpack them with `[x, y] = f()`, and the number of targets must match the number of values, or `ArgumentError` is raised. Using such a call where one value is expected, as in `x = f()` or `f() + 1`, also raises `ArgumentError`. A call used as a statement on its own discards its values.
- A function annotated `: T` has its return value checked against `T`; a function that returns several values cannot carry a return annotation.
- Calls may nest up to 10,000 deep. A deeper call raises `RecursionError`.

### Overloading

Axon has no overloading by type. A name refers to one function, and redefining it in the same scope replaces it. Generic behaviour comes from functions that inspect argument types with `typeof(x)` or `isa(x, T)`.

### Recursion and evaluation order

- Functions may call themselves and each other. Named functions in a module are bound before its top-level statements run, so they may be called before their definition in the file.
- `return` outside a function, and `break` or `continue` outside a loop, is a `SyntaxError`. A function body starts a new context, so a `break` inside a function inside a loop is still an error.
- Arguments are evaluated left to right before the call. Operands of binary operators are evaluated left to right, except that `and` and `or` skip their right operand when a scalar left operand decides the result.

## Errors

An error is a record with the fields `kind` (a string), `message` (a string) and `trace` (a list of records holding `file`, `line`, `col` and `function`). The trace runs from the innermost frame, where the error was raised, outward to the top level. `function` is the name of the function the frame is in, `"anonymous function"` for a lambda, or `""` at the top level. `error("text")` raises an error of kind `"UserError"`, `error(kind, "text")` raises one of the given kind, and `error(err)` re-raises a caught error unchanged.

`try … catch err … end` catches every error raised in the `try` block, including errors raised in functions it calls and in FFI callbacks. Code that handles only some kinds re-raises the rest:

```
try
  x = A \ b
catch err
  if err.kind != "SingularMatrix"
    error(err)
  end
  x = linalg.lstsq(A, b)
end
```

| Kind | Raised when |
| --- | --- |
| `ArgumentError` | Wrong number of arguments, unknown keyword, invalid argument value |
| `DimensionError` | Incompatible shapes in an operation, literal or indexed assignment |
| `DomainError` | A function argument is outside its domain and no NaN result is defined, such as `factorial(-1)` |
| `FieldError` | Access to or assignment of a missing field on a declared record |
| `ForeignError` | A native library cannot be loaded, a symbol is missing, or a native call reports failure |
| `ImportError` | A module cannot be found, or imports form a cycle |
| `IndexError` | An index is out of bounds or not an integer |
| `IOError` | A file cannot be read, written or deleted |
| `KeyError` | A dictionary key is missing |
| `NameError` | A name is read before it is bound |
| `OverflowError` | Integer arithmetic exceeds 64 bits |
| `RecursionError` | Function calls nest more than 10,000 deep |
| `SingularMatrix` | A solve or inverse meets a singular matrix |
| `SolverError` | A numerical solver fails, such as an ODE integration whose step size falls below the limit |
| `SyntaxError` | Source text cannot be lexed or parsed; the message gives the file, line and column and what was expected |
| `TypeError` | A value has the wrong type for an operation, annotation or condition |
| `UserError` | Raised by `error("text")` |

An uncaught error stops the program and prints its kind, message and trace to standard error, then exits with status 1:

```
IndexError: index 5 is out of bounds for a list of length 3
  at prog.sci:3:10 in lookup
  at prog.sci:7:1
```

The first line is `Kind: message`. Each further line is one trace frame, innermost first, giving the file, line and column, followed by `in name` for a frame inside a function. `error(err)` keeps the original trace. At the REPL it prints the same report and returns to the prompt with the session's variables intact.

## Standard modules

These modules come with Axon and are imported by name (`import linalg`, `from ode import solve`). `io`, `time` and `graphics` are core modules written in the interpreter; `linalg`, `ode` and `plot` are standard-library modules written in Axon.

### The linalg module

`linalg` is a standard-library module written in Axon over OpenBLAS's LAPACKE interface. Every function accepts `bool`, `int`, `real` or `complex` matrices, works in `real` arithmetic unless the input is complex, and raises `DimensionError` when it needs a square matrix and gets another shape.

| Function | Result |
| --- | --- |
| `solve(A, b)` | `A \ b` for square `A` |
| `lstsq(A, b)` | The minimum-norm least-squares solution, for any shape, including rank-deficient `A` |
| `det(A)` | The determinant, from the LU factorisation |
| `inv(A)` | The inverse; `SingularMatrix` when singular |
| `eig(A)` | The eigenvalues: a `real` vector when all are real, a `complex` vector otherwise. `eig(A, vectors=true)` returns two values, the eigenvalues and a matrix of eigenvectors |
| `svd(A)` | Three values `U, s, V` with `A = U*S*V'` (`adjoint` for complex), `s` the vector of singular values in decreasing order and `U`, `V` square |
| `qr(A)` | Two values `Q, R`: the thin factorisation, `Q` m×k with orthonormal columns and `R` k×n upper triangular, `k = min(m, n)` |
| `lu(A)` | Two values `L, U` with `A = L*U`, `U` upper triangular and `L` a row permutation of a unit lower-triangular matrix. For a sparse `A`, which must be square, both are sparse, and the fill-reducing column order is folded into `U`, which is then a column permutation of an upper-triangular matrix |
| `chol(A)` | Upper-triangular `R` with `A = R'*R` (`adjoint(R)*R` for complex); `DomainError` when `A` is not positive definite |
| `rank(A; tol)` | The number of singular values above `tol`, by default `max(m, n) * eps * max(s)` with `eps = 2.220446049250313e-16` |
| `null(A; tol)` | An orthonormal basis of the null space, as the columns of a matrix |
| `norm(x; p=2)` | For a vector the p-norm, with `p` a positive number or `"inf"`; for a matrix the 2-norm (largest singular value), `p=1` (largest column sum), `"inf"` (largest row sum) or `"fro"` (Frobenius) |
| `expm(A)` | The matrix exponential, by scaling and squaring with a degree-13 Padé approximant |

Decompositions that fail to converge raise `DomainError`. Apart from `lu` and `solve`, the functions accept a sparse matrix by working on `full(A)`.

### The io module

`io` is a core module, written in the interpreter, for whole-file reading and writing. Relative paths are relative to the working directory, and a failure raises `IOError`.

| Function | Result |
| --- | --- |
| `read_file(path)` | The contents of a UTF-8 text file, as a string; a leading byte-order mark is dropped, and a file that is not valid UTF-8 raises `IOError` |
| `read_bytes(path)` | The bytes of a file, as an `int` vector of values 0 to 255 |
| `write_file(path, text)` | Writes the string as UTF-8, replacing the file; returns `nothing` |
| `file_exists(path)` | `true` when the file exists |
| `delete_file(path)` | Deletes the file and returns `true`, or returns `false` when there was no such file |

### The time module

`time` is a core module, written in the interpreter, for clocks and for timing code.

| Function | Result |
| --- | --- |
| `clock()` | Seconds, as a `real`, on a monotonic high-resolution clock with an arbitrary origin. Only differences of two readings are meaningful; they are not affected by changes to the system clock |
| `now()` | Wall-clock time as `real` seconds since 1970-01-01 00:00 UTC, with millisecond resolution |
| `sleep(seconds)` | Pauses for at least the given number of seconds (`int` or `real`) and returns `nothing`; a negative or NaN value raises `DomainError` |
| `elapsed(f, args…)` | Calls `f(args…)` once and returns the seconds it took. The result of `f` is discarded, and an error inside `f` propagates |
| `bench(f, args…)` | Times repeated calls of `f(args…)` and returns a record `{best, mean, worst, loops, runs}`. The number of calls per run, `loops`, doubles from 1 until a run lasts at least 0.2 s; then `runs` = 5 runs of `loops` calls are timed, the calibrating run counting as the first. `best`, `mean` and `worst` are seconds per call over those runs. A call that takes longer than 0.2 s is therefore made 5 times |
| `format(seconds)` | The time as text with three significant digits in the largest unit that keeps it at 1 or above: `"1.50 s"`, `"12.3 ms"`, `"45.6 µs"`, `"7.00 ns"`. Rounding happens before the unit is chosen, so `0.99996` gives `"1.00 s"`; zero gives `"0 s"` |

`elapsed` and `bench` call `f` from the interpreter itself, so the timings include no loop overhead from Axon code. `f` may be any function value, including a built-in or a lambda: `time.bench(function() return A * A end)`. Report `best` when comparing implementations; it is the measurement least disturbed by other activity on the machine.

### The random module

`random` is a core module, written in the interpreter, for random numbers. Every function draws from one generator, xoshiro256**, which the prelude's `rand` shares. A program starts from a seed taken from the clock, so each run differs; `seed(n)` sets the state from an `int`, after which every draw, `rand` included, is the same in every run on every platform.

Each distribution takes its parameters first, then an optional shape: no shape gives a scalar, `n` a vector of length n, and `m, n` an m×n matrix. There are no keyword arguments.

| Function | Result |
| --- | --- |
| `seed(n)` | Seeds the generator with the `int` n and returns `nothing` |
| `rand()`, `rand(n)`, `rand(m, n)` | Uniform reals in [0, 1), multiples of 2^-53 |
| `randn()`, `randn(n)`, `randn(m, n)` | Standard normal reals (mean 0, standard deviation 1) |
| `uniform(a, b)`, `uniform(a, b, n)`, `uniform(a, b, m, n)` | Uniform reals `a + (b - a)*u` with `u` from `rand`, so in [a, b) up to rounding; `a == b` gives `a` |
| `normal(mu, sigma)`, `normal(mu, sigma, n)`, `normal(mu, sigma, m, n)` | Normal reals with mean `mu` and standard deviation `sigma`: `mu + sigma*z` with `z` from `randn` |
| `randint(lo, hi)`, `randint(lo, hi, n)`, `randint(lo, hi, m, n)` | `int`s from `lo` to `hi` inclusive, each equally likely; arrays have element type `int` |

```axon
import random
random.seed(1)
x = random.normal(10.0, 2.0, 1000)     # 1000 samples
println(mean(x))                        # close to 10
dice = random.randint(1, 6, 5)          # five dice rolls
```

- **Arguments.** Bounds, `mu` and `sigma` may be `int` or `real` and must be finite, or `DomainError` is raised; other types raise `TypeError`. `randint` and `seed` need `int`s. `uniform` with `a > b`, `normal` with `sigma < 0` and `randint` with `lo > hi` raise `DomainError`. Sizes follow `zeros`: a negative or non-`int` size raises `ArgumentError`.
- **Method.** The state is 256 bits, expanded from the seed with SplitMix64. A real takes the top 53 bits of a draw. Normal deviates come from Marsaglia's polar method, which makes them in pairs; the second is kept for the next call, and `seed` discards it. `randint` rejects the few draws that would favour some values. The generator is fast and statistically strong but not cryptographic.

### The graphics module

`graphics` is a core module that renders a scene to a file through the Skia library. It is the drawing layer under `plot`. Skia loads at the first call that needs it; when it cannot be loaded, that call raises `ForeignError` and the rest of the language is unaffected. On Windows Skia is the shipped `sk4d.dll`; on macOS it is linked into the interpreter.

- **`save(scene, path)`** writes the scene to `path`, whose extension chooses the format: `.png` (raster), `.svg` or `.pdf` (vector, with text kept as text). Any other extension raises `ArgumentError`, and a file that cannot be written raises `IOError`.
- **`show(scene)`** renders the scene to a PNG and shows it, and returns the file's path. When the environment variable `AXON_SHOW_DIR` is set, as it is for programs run from the IDE, the file is written there and a line holding U+0003, `show `, and the path is written to standard error, so the front end can display it while the program runs. Otherwise the file goes to a temporary folder and opens in the system's image viewer; if no viewer can be started, it raises `ForeignError`.
- **`text_width(text, size)`** and **`text_width(text, size, font)`** return the width in points of the text as drawn, for layout.
- **Scenes.** A scene is a record with `width` and `height` in points (1/72 inch; default 640 by 480), `background` (a colour, default `"white"`), `scale` (pixels per point for PNG, default 1) and `items`, a list of item records drawn in order. Coordinates run from the top-left corner with y pointing down.
- **Items.** Each item has a `kind`:

| Kind | Fields (defaults) |
| --- | --- |
| `"line"` or `"polyline"` | `x`, `y` (vectors of equal length), `color` (`"black"`), `width` (1), `dash` (a vector of on and off lengths, or `nothing`); a non-finite point breaks the line |
| `"polygon"` | `x`, `y`, `fill` (`"none"`), `color` (`"none"`, the outline), `width` (1), `dash` |
| `"rect"` | `x`, `y`, `w`, `h`, and `fill`, `color`, `width` and `dash` as for a polygon |
| `"markers"` | `x`, `y`, `shape` (`"circle"`, `"square"`, `"diamond"`, `"triangle"`, `"plus"` or `"cross"`), `size` (6, the width), `color` (`"black"`), `fill` (the colour) |
| `"text"` | `x`, `y`, `text`, `size` (10), `color`, `font` (`"sans-serif"`; also `"serif"`, `"monospace"` or a family name), `bold` (`false`), `anchor` (`"start"`, `"middle"` or `"end"`), `baseline` (`"alphabetic"`, `"middle"`, `"top"` or `"bottom"`), `angle` (degrees anticlockwise) |
| `"group"` | `items`, and `clip` (a record `{x, y, w, h}` or `nothing`) that limits drawing to a rectangle |

- **Colours** are names (`"black"`, `"white"`, `"red"`, `"green"`, `"blue"`, `"orange"`, `"purple"`, `"brown"`, `"pink"`, `"gray"`, `"olive"`, `"cyan"`, `"yellow"`, `"lightgray"`, `"darkgray"`), `"#rrggbb"`, `"#rrggbbaa"`, `"none"`, or a real vector `[r, g, b]` or `[r, g, b, a]` with components from 0 to 1. Anything else raises `ArgumentError`.
- **Checks.** A field of the wrong type raises `TypeError`, a missing required field `FieldError`, `x` and `y` of different lengths `DimensionError`, and an unknown kind, shape, anchor or baseline `ArgumentError`. Each message names the item by its position.

### The ode module

`ode` is a standard-library module. Its interface is written in Axon, and its stepping loops run natively in the interpreter's core module `odecore`. `ode.solve(f, y0, tspan; …)` solves y' = f(t, y) from `tspan[1]` to `tspan[2]` with y(`tspan[1]`) = `y0` and returns a result record.

- **Problem.** `f(t, y)` receives a real `t` and a real vector `y` and returns the derivative as a real vector of the same length (a scalar for one equation). `y0` is a real scalar or vector. `tspan` holds two different times; integration may run backwards.
- **Methods.** `method = "rk45"` (the default) is the explicit Dormand–Prince 5(4) pair with step-size control and its fourth-order dense output. `method = "bdf"` uses the variable-order BDF method of SUNDIALS CVODE with a dense direct linear solver, for stiff problems. `f` and the event functions are called as ordinary Axon functions, so a right-hand side that compiles (see Compilation) runs as native code.
- **Keywords.**

| Keyword | Meaning (default) |
| --- | --- |
| `rtol`, `atol` | Relative and absolute error tolerances (`1e-6`, `1e-9`) |
| `t_eval` | Times at which to report the solution, within `tspan` and strictly increasing in the direction of integration; by default every step is reported, starting with `tspan[1]` |
| `events` | An event function `g(t, y)` returning a real number, or a list of them (`nothing`) |
| `terminal` | Whether an event stops the integration: a `bool` for all, or a list with one per event (`false`) |
| `direction` | Which zero crossings count: `0` both, `1` rising, `-1` falling; a number or a list (`0`) |
| `names` | The names of the components, a list of strings (`{"y1", "y2", …}`) |
| `max_step` | The largest step (unlimited) |
| `first_step` | The first step size (chosen automatically) |
| `max_steps` | The most steps before giving up (`100000`) |

- **Result.** A record with fields `t` (a vector of the reported times), `y` (a matrix with one column per reported time, so `sol.y[1, :]` is the first component over time), `names`, `status` (`"success"`, or `"event"` when a terminal event stopped the integration), `t_events` and `y_events` (lists with one entry per event function: a vector of the times and a matrix of the states at which it occurred), `nfev` (right-hand-side evaluations), `nsteps` (accepted steps), `method`, and `at`, the dense output: `sol.at(t)` returns the state at any time in the solved range, and `sol.at(v)` for a vector of times returns a matrix with one column per time. A time outside the range raises `DomainError`.
- **Events.** An event occurs where an event function changes sign in the counted direction; a function that starts at exactly zero does not trigger at the start. RK45 locates the crossing on the dense output; BDF uses CVODE's root finding. A terminal event ends the solution at the event time, which becomes the last reported time when `t_eval` is not given.
- **Errors.** A right-hand side of the wrong length raises `DimensionError`, and one of the wrong type `TypeError`. An error raised inside `f` or an event function propagates unchanged. A step size that falls below what the precision allows, too many steps, a non-finite solution or a CVODE failure raises `SolverError`. Invalid keywords raise `ArgumentError` or `TypeError`.

### The plot module

`plot` is a standard-library module written in Axon over `graphics`. Plotting calls add to the current figure, which `plot.save` writes. A script can therefore build a figure without writing anything, as the white paper's worked example does.

| Function | Effect |
| --- | --- |
| `figure(; width = 640, height = 480, title)` | Starts a new current figure, sized in points |
| `line(x, y; label, color, width = 1.5, style = "-", marker, marker_size = 5)` | Adds a line; `style` is `"-"`, `"--"`, `":"` or `"-."`, and `marker` draws a marker of that shape at each point |
| `scatter(x, y; label, color, size = 6, marker = "circle")` | Adds markers at the points |
| `hist(x; bins = 10, label, color)` | Adds a histogram of the values `x`: one bar per bin, as high as the number of values in it. Returns `{counts, edges, heights}` |
| `hist_density(x; bins = 10, label, color)` | As `hist`, with heights scaled so the bars' total area is 1, for comparison with a probability density |
| `surface(x, y, Z; label, colormap = "viridis", edges = true, elev = 30, azim = -60)` | Adds the surface with height `Z[i, j]` over `(x[j], y[i])`, coloured by height (`"viridis"` or `"gray"`), seen from the given elevation and azimuth in degrees |
| `title(s)`, `xlabel(s)`, `ylabel(s)`, `zlabel(s)` | Set the title and axis labels |
| `xlim(lo, hi)`, `ylim(lo, hi)` | Fix an axis range; otherwise it is the data range padded by 5% |
| `grid(on)`, `legend(on)` | Show or hide the grid and the legend (both shown by default) |
| `save(path; scale = 2)` | Writes the current figure as PNG, SVG or PDF, chosen by the extension; `scale` sets PNG pixels per point |
| `show(; scale = 2)` | Shows the current figure through `graphics.show`: in the IDE's plot pane, or in the system's image viewer |
| `gcf()` | The current figure as a record, or `nothing` before the first plotting call |

- **Histograms.** `bins` is a number of equal-width bins spanning the smallest to the largest finite value of `x` (a single distinct value gets one unit around it), or a vector of strictly increasing bin edges. A value belongs to the bin `[e[k], e[k + 1])`, and the last bin also includes its right edge; values outside the edges and NaN are not counted. In the result, `counts` is a `vector{int}`, `edges` a `real` vector one longer, and `heights` the bar heights drawn (the counts as reals, or the densities `counts[k] / (sum(counts) * width[k])`). With bars in a figure and no `ylim`, the y axis starts at 0 unless some value is negative.
- **Defaults.** Series without a `color` take the next colour of a ten-colour cycle. A legend lists the series that have a `label`. Axis ticks are round numbers (1, 2 or 5 times a power of ten). Colours are given as for `graphics`.
- **Errors.** `x` and `y` of different lengths raise `DimensionError`, and so does a `Z` that is not `length(y)` by `length(x)`. Non-real data raises `TypeError`. An unknown style, colour map or marker, a figure that mixes a surface with lines or markers, and `save` or `show` with no figure raise `ArgumentError`, as do fewer than 1 bin, fewer than two edges and edges that do not increase; `bins` of another type raises `TypeError`.

## Modules and foreign functions

### Modules

- **Naming.** Each source file is a module named after its file stem. A directory of files is a namespace, so `ode/stiff.sci` is imported as `ode.stiff`.
- **Files.** A module name `a.b.c` stands for the file `a/b/c.sci` (or `a/b/c.txt`) below a search root.
- **Search path.** `import m` looks first in the importing file's directory, then in the packages listed in the nearest `package.toml`, then in the installed standard library. If none contains `m`, it raises `ImportError`.
  - **Packages.** The nearest `package.toml` is found by searching upward from the importing file's directory. Its `[dependencies]` table maps package names to package root directories, relative to the manifest's own directory: `ode = "../packages/ode"`. When the first part of a module name is a dependency, `import ode` loads `<root>/ode.sci`, the package's main module, and `import ode.stiff` loads `<root>/stiff.sci`.
  - **Standard library.** The standard library is the `stdlib` directory next to the interpreter, or the directory named by the environment variable `AXON_STDLIB` when it is set.
- **Bindings.** `import a.b.c` binds `a`, through which the module is reached as `a.b.c`. `import a.b.c as x` binds `x` to the module itself. `from m import f, g` binds `f` and `g` to the exported values. Imports bind in the outermost scope of the enclosing function or module, like a named function definition.
- **Loading.** A module is loaded at most once per program. Loading binds all its named functions and records, then runs its top-level statements in order. Later imports reuse the loaded module.
- **Cycles.** An import cycle raises `ImportError` that names the chain.
- **Exports.** Only names declared with `export` (functions and record types) are visible to importers. `from m import x` with an unexported `x` raises `ImportError`, and so does reading `m.x`. A module value displays as `module m` and its `typeof` is `"module"`.
- **Imported names.** Imported names are read-only in the importing module. Assigning to one raises `NameError`. This covers the module name bound by `import` as well as names bound by `from … import`.
- **File names in errors.** Errors in a module report its path relative to the working directory, with `/` as the separator, so reports read the same on every platform.
- **Manifests.** `package.toml` uses a subset of TOML: `[section]` and `[section.sub]` headers, `key = value` lines where the value is a double-quoted string, a number or `true`/`false`, and `#` comments. Anything else raises `ImportError` naming the file and line. `[package]` holds `name` and `version`, `[dependencies]` the package paths, and each `[native.lib]` table the library file for each platform under the keys `windows`, `macos` and `linux`, relative to the manifest's directory.

### Foreign functions

- **Library resolution.** `extern "lib"` resolves `lib` through `package.toml` (the `[native.lib]` entry for the current platform), then through the system's library search path. A manifest entry that names no existing file next to the manifest is looked up by its file name on the system search path, so system libraries can be listed per platform (`windows = "msvcrt.dll"`, `macos = "libSystem.B.dylib"`). The library loads at the first call into it, and a failure raises `ForeignError`.
- **C types.** Parameters and results use the fixed-width numerics `int8` … `int64`, `uint8` … `uint64`, `float32` and `float64`, the platform-sized integers `clong` and `csize`, and `char`, `cstring`, `ref T`, `ptr T` and `callback(…)`.
- **Platform-sized integers.** `clong` is C `long`, which is 32 bits on Windows and 64 bits on macOS and Linux. `csize` is C `size_t`, which is 64 bits on every supported platform. Both convert to and from Axon `int`, so a binding such as CVODE's `long int` counters works unchanged on every platform.
- **Argument conversion.** Each argument is converted to its declared C type before the call. A value that does not fit, such as `3.5` for `int32` or `2^40` for `int32`, raises `TypeError`.
- **`ref T`.** The runtime passes a pointer to a temporary holding the converted value. After the call, it converts the temporary back and assigns it to the argument variable, which must therefore be a variable, not an expression. `T` is a number type, or a `ptr` type for a C out-parameter such as `void**`: the variable then holds a pointer value or `nothing`, as in `ctx = nothing; SUNContext_Create(0, ctx)`.
- **`ptr T`.** The value must be an array whose element type matches `T` exactly: `ptr float64` needs a real array and `ptr complex` a complex one. Its buffer is passed directly, after being made unique if it is shared, so native writes affect only that variable. A mismatch raises `TypeError`.
- **`callback`.** An Axon function passed for a callback parameter gets a native trampoline with the declared signature. The trampoline stays alive until the extern function returns, and longer if it is stored with `keep(cb)`. An error inside the callback is recorded, the callback returns 0 (or a null pointer), and the error is re-raised in Axon once the outer native call returns.
- **Threads.** Native code must not call a trampoline from another thread. Doing so raises `ForeignError` and does not run the Axon function. The error is raised once the outer native call returns.
- **Kept callbacks.** `keep(f)` returns `f` and marks it so that the trampoline made for it stays valid after the extern call returns, for libraries that store a callback and call it later. A kept function keeps its trampoline for the rest of the program. A trampoline that native code calls after its extern call has returned, without `keep`, does not run the Axon function: it returns 0 and the next extern call that returns raises `ForeignError`.
- **Callback limits.** Trampolines come from a fixed pool of 32 per return kind built into the interpreter, so at most 32 callbacks can be live at once; one more raises `ForeignError`. On macOS a callback may take at most 8 integer or pointer arguments (6 on x86-64) and 8 floating-point arguments. Variadic callbacks and structures passed by value are not supported.
- **Pointers.** A `ptr T` result, or a callback argument, that is not an array is an opaque pointer value: `typeof` gives `"pointer"`, it displays as `pointer 0x…`, it compares equal to the same address, and it can be passed back to any `ptr` parameter. A null pointer is `nothing`, and `nothing` passed to a `ptr` or `cstring` parameter is null. `ptr void` also accepts any array, whose buffer is passed as is.
- **Element widths.** `ptr float64`, `ptr complex` and `ptr int64` pass a `real`, `complex` or `int` array's own buffer. `ptr int32`, `ptr int16`, `ptr int8`, the unsigned widths and `ptr float32` take an `int` or `real` array through a temporary buffer of that width: values are converted in before the call, checked to fit, and converted back into the (unique) array after it.
- **Results.** Integer results become `int` (a `uint64` above the `int` range raises `OverflowError`), floating-point results `real`, `cstring` results a copied `string` (or `nothing` for null), and a function with no result type returns `nothing`. `char` is an 8-bit integer; a one-character ASCII string is also accepted for it.

## Compilation

The interpreter compiles functions to native code at their first call (a just-in-time compiler built on MIR). Compilation changes only speed: a compiled function gives the same results, prints the same output, raises the same errors with the same traces, and makes the same array copies (`__copies()`) as when it is interpreted. A function that cannot be compiled with these guarantees runs interpreted, silently.

- **What compiles.**
  - **Functions.** Named top-level functions, lambdas and nested functions.
  - **Parameters.** A parameter annotated `bool`, `int`, `real`, `vector{real}`, `vector{int}` or `matrix{real}` has that type. A parameter without an annotation, or annotated plain `vector` or `matrix`, takes the type of the argument it is called with. Such a function is compiled separately for each set of argument types it meets, up to eight; further calls run interpreted. An unannotated parameter is an untyped variable, so a function that assigns it a value of another type stays interpreted for that call.
  - **Bodies.** Arithmetic and comparisons, `and`/`or`/`not`, `if`, `while`, `for` over ranges and arrays, `break`, `continue` and `return` (with several values).
  - **Variables.** Local and typed variables.
  - **Arrays.** Element reads and writes with int indices and `end`, operators on real arrays, and vector and matrix literals of numbers.
  - **Values from outside.** Reads of module variables and captured variables, and of their record fields (`p.a`), when the values are numbers or arrays that compile. They are read when the function is entered, and a function that reads them does not call anything that runs interpreted, so it sees exactly the values the interpreter would.
  - **Calls.** Calls to other functions, recursion included, and the scalar built-ins: the elementary functions, `abs`, `floor`, `ceil`, `round`, `int`, `real`, `min`, `max`, `div`, `mod`, `length`, `size`, `zeros`, `ones`, `sum`, `print`, `println` and `error`.
- **What stays interpreted.**
  - **Types.** A function whose variable changes type, or whose result type depends on a value: `n ^ k` with `int` operands and a variable exponent is an `int` for `k >= 0` and a `real` otherwise. A call whose arguments include a string, list, record, dictionary, complex number, range, or an array other than a real vector, int vector or real matrix.
  - **Names.** A function that reads a variable that may be unassigned on some path, that both reads a variable from outside and assigns it, or (a closure) that assigns a variable of an enclosing scope.
  - **Constructs.** `try`, `global`, strings beyond `print`, `println` and `error` arguments, complex numbers, lists, record and dictionary literals, and indexing with ranges, colons or masks.

  A compiled function may still call one that runs interpreted, as long as the callee's result type is declared or its result is unused.
- **Control.** `axon --jit=off file.sci`, or the environment variable `AXON_JIT=off`, turns compilation off; `on` is the default. `axon --jir file.sci` prints the compiled form of each function, or the reason it is not compiled.
- **Rebinding.** A compiled call checks that the name still refers to the function it was compiled against, so rebinding a module-level function name takes effect. A built-in that is later shadowed by a new module variable of the same name is still called by code compiled before the shadowing.

## The REPL

`axon` with no arguments starts an interactive session. The prompt is `> `. Input that ends inside an open block or bracket continues on further lines, each with the prompt `... `, until the construct closes. Statements run in the session's top-level scope, as in a script, and imports resolve from the working directory.

- **Display.** After an expression statement the REPL displays its value as described under Display, with strings quoted; a value of `nothing` is not displayed, so `println(x)` shows only its own output. An assignment to a plain name shows `name = ` followed by the value, and a destructuring assignment shows one such line per name. Other statements show nothing. A trailing `;` suppresses the display.
- **Errors.** An uncaught error prints the report described under Errors and returns to the prompt. Statements that completed before the error keep their effects, so the session's variables stay intact; the rest of that input is skipped.
- **`help`.** A line of the form `help name` (where `name` may be dotted, as in `help linalg.solve`) is a REPL command, not a statement. For a function it shows the function's header as written in the source, without `export` and `function`, followed by its docstring indented by two spaces. A record type shows as `record T(field: type, …)` and a module as `module m`, each followed by its docstring; a module then lists its exported names on a line `  exports: a, b, …`. A built-in function shows its parameters and a one-line description. A name without a docstring shows `  (no documentation)`, and any other value shows `name is a T`, with `T` its `typeof` and `an` before a vowel, as in `x is an int`. A name that is not defined raises `NameError` as an expression would. `help` alone lists the REPL commands.
- **Front ends.** `axon --repl-protocol` runs the REPL for programs that drive it through pipes, such as the IDE. It writes no banner, prompts or echo. Before each line it reads, it writes a marker line holding the character U+0001 followed by `>` when it is ready for a statement or `.` when it is waiting for the rest of a construct, and flushes its output. Error reports go to standard output, in order with the rest, with each line prefixed by U+0002.
- **Syntax checks.** `axon --check file` parses the file without running it, and `axon --check -` parses standard input, reported as `<stdin>`. It prints nothing and exits with 0 when the syntax is valid, and otherwise prints the `SyntaxError` report and exits with 1. Editors use it to check as the user types.
- **Transcripts.** `axon --transcript file` runs a recorded session: it takes as input the lines of the file that begin with `> ` or `... ` (the prompt is removed), runs them as the REPL would, and writes the transcript to standard output: each input line after its prompt, then its output, with error reports in place. Lines of the file that are not input are ignored, so a transcript file reproduces itself when the REPL's behaviour matches it. Trailing spaces are not written.

## Decisions made in this draft

The white paper did not settle these points, so this draft decided them. Each is open to change.

| Topic | Decision |
| --- | --- |
| Real literals | A digit is required on both sides of the point (`0.5`, `1.0`), so `A.*B` and `1.+x` lex unambiguously |
| Digit separators | `_` is allowed inside numbers, as in `1_000_000` |
| Newlines in brackets | Ignored, so matrix rows always need `;` |
| Vector or row | `[1; 2; 3]` is a vector and `[1, 2, 3]` a 1×3 matrix; `v' * w` is a scalar |
| Empty literals | `{}` is the empty list and `[]` a 0×0 real matrix |
| Integer division | `int / int` gives a `real`; `div` and `mod` give integer results |
| Integer overflow | Raises `OverflowError` rather than wrapping |
| Real-domain functions | `sqrt(-1.0)` and `log(-1.0)` return NaN rather than raising |
| String concatenation | `+` |
| Statement terminator | Optional before `end`, `elseif`, `else` and `catch` |
| Newline handling | The lexer always emits `NEWLINE`; the parser decides when to skip it |
| `{a:b}` | A record; a list holding a range is `{(a:b)}` |
| Number display | 15 significant digits, reals always show a decimal point, complex as `3.0 + 4.0i` |
| Conditions | Must be a scalar `bool`; there is no truthiness |
| Dot operators | Only `.*`, `./`, `.\` and `.^`; `+` and `-` broadcast without a dot |
| Transpose | `A'` is the plain transpose; `adjoint(A)` gives the conjugate transpose and `dot(u, v)` the complex inner product |
| Comparisons | Elementwise on arrays; `isequal(A, B)` compares whole values |
| Logical operators | The words `and`, `or` and `not`; short-circuit on scalars, elementwise on `bool` arrays |
| Chained comparison | `a < b < c` is an error |
| Block scopes | `if`, `for`, `while` and `try` bodies are scopes for `local`, loop variables and `catch` names; a plain first assignment still lands at function level |
| Overloading | None; one function per name |
| No return value | A function without a `return` value returns `nothing` |
| `nothing` | A reserved keyword like `true` and `false`, so it cannot be rebound |
| Compound assignment | `+=` and its relatives are left out of the first version |
| Imported names | Read-only in the importing module |
| Platform-sized C integers | `clong` (C `long`) and `csize` (C `size_t`) cover types whose width differs between platforms |
| Callbacks | Valid only for the duration of the extern call unless retained with `keep(cb)`, and only on the calling thread |
