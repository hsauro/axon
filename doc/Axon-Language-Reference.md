# Axon Language Reference

Nov 7, 2026 · Herbert Sauro

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

### Strings

Strings are enclosed in double quotes, with the escapes `\n`, `\t`, `\"`, `\\` and `\u{X…}`, where `X…` is one to six hex digits naming a Unicode code point. Any other escape is a `SyntaxError`, and so is a line break before the closing quote: a string cannot span lines. There is no single-quoted string form, so `'` is always the transpose operator.

### Comments

- `#` starts a comment that runs to the end of the line.
- `#=` … `=#` encloses a block comment, which may span lines and may be nested.
- `##` at the start of a line (after optional spaces) begins a documentation comment, which the lexer keeps as a `DOCSTRING` token. Consecutive `##` lines directly above a `function` or `record` form its docstring. Elsewhere on a line, `##` is an ordinary comment.
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
- **Constructors.** `zeros(m, n)` and `ones(m, n)` give m×n `real` matrices, and `zeros(n)` and `ones(n)` give vectors of length n. `eye(n)` is the n×n identity and `eye(m, n)` its m×n form. `rand()`, `rand(n)` and `rand(m, n)` give uniform reals in [0, 1). `linspace(a, b, n)` gives a `real` vector of n points from a to b inclusive. A negative or non-integer size raises `ArgumentError`.
- **Size.** `size(A)` returns two values, the row and column counts, so it is used as `[m, n] = size(A)`; a vector has n rows and 1 column, and a scalar is 1×1. `size(A, 1)` and `size(A, 2)` return one count. `length(A)` is the total number of elements, which is also the value of `end` in a single (linear) index.
- **Reductions.** `sum`, `prod`, `mean`, `min`, `max`, `all` and `any` on one array reduce over every element to a scalar. `sum(A, d)`, `prod(A, d)` and `mean(A, d)` reduce along dimension `d`: `mean(A, 1)` is the 1×n row of column means and `mean(A, 2)` the m×1 column of row means. `min(a, b)` and `max(a, b)` with two arguments work elementwise with broadcasting. `min` and `max` of an empty array raise `ArgumentError`; `all` of an empty array is `true` and `any` is `false`. `all` and `any` need `bool` elements.
- **Iteration.** `for x in A` visits the elements of an array in column-major order.
- **Not yet.** Matrix division (`A \ b`, `A / B`) and matrix powers (`A ^ k`) with a non-scalar matrix are part of the `linalg` milestone; until then they raise `TypeError` naming the operation.

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
| `string` | Without quotes from `print`; with quotes at the REPL | `S1` / `"S1"` |
| `list` | Elements in braces, separated by ", " | `{1, "S1", 2.5}`, `{}` |
| `record` | Fields in braces as `name: value`, in definition order | `{name: "S1", init: 10.0}` |

Because reals are rounded to 15 significant digits, `0.1 + 0.2` displays as `0.3`. `print(a, b, …)` writes its arguments separated by one space and ends with a newline. Inside a list or record, strings are always quoted, so `{"a b"}` and `{"a", "b"}` stay distinguishable. Display of dictionaries is fixed in M7.

Arrays display as a header line, then one line per row with each entry right-aligned in its column and preceded by two spaces. The header is `R×C matrix{T}` or `N-vector{T}`. Elements show up to 6 significant digits, following the same rules as scalars, and complex elements show both parts that way. Above 10 rows, only the first and last 5 are shown, with a `  ⋮` line between; above 8 columns, only the first and last 4, with a `…` column between. An empty array shows only its header. At the REPL an assignment shows `A = ` before the header:

```
A = 2×2 matrix{int}
  1  2
  3  4
```

Inside a list or record, an array is shown inline in literal form, as in `{[1, 2; 3, 4], [1; 2]}`.

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

### Broadcasting

Four operators carry a leading dot: `.*`, `./`, `.\` and `.^`. Each is the element-by-element form of an operator whose plain form means the matrix operation. Broadcasting applies to these four, to `+` and `-`, to the comparisons, and to `and`, `or` and `not` on `bool` arrays:

1. A scalar combines with every element.
2. Two arrays are compatible if, in each dimension, their sizes are equal or one of them is 1. A vector counts as n×1.
3. The result's size in each dimension is the larger of the two sizes.

For example, `A - mean(A, 1)` subtracts each column's mean, because `mean(A, 1)` is 1×n. Incompatible sizes raise `DimensionError`. Prefix `-`, `not` and the elementary functions (`sin`, `exp` and so on) always apply elementwise.

### Sparse operands

A result is sparse when both operands are sparse, or when one is a scalar and the operation is `*` or `/`. Any other mix with a dense operand gives a dense result. `S'` is sparse.

### Comparison

- On scalars, `==`, `!=`, `<`, `<=`, `>` and `>=` return a `bool`. On arrays they apply elementwise with broadcasting and return a `bool` array.
- `==` and `!=` accept values of any two types. Values of unrelated types (a string and a number, or `nothing` and anything else) are unequal, so `"1" == 1` is `false`. Numbers of different types compare after promotion, so `1 == 1.0` and `1 == 1.0 + 0i` are `true`.
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

- **Lists** index like vectors. A range index returns a sublist, and a scalar index returns the element.
- **Records** use only `.` field access. Assigning to a field that does not exist raises `FieldError` for a declared record type and adds the field for a literal record.
- **Dictionaries** use `d[key]`. A missing key raises `KeyError`, and `get(d, key, default)` avoids that.

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
| `KeyError` | A dictionary key is missing |
| `NameError` | A name is read before it is bound |
| `OverflowError` | Integer arithmetic exceeds 64 bits |
| `RecursionError` | Function calls nest more than 10,000 deep |
| `SingularMatrix` | A solve or inverse meets a singular matrix |
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

## Modules and foreign functions

### Modules

- **Naming.** Each source file is a module named after its file stem. A directory of files is a namespace, so `ode/stiff.sci` is imported as `ode.stiff`.
- **Search path.** `import m` looks first in the importing file's directory, then in the packages listed in the nearest `package.toml`, then in the installed standard library. If none contains `m`, it raises `ImportError`.
- **Loading.** A module is loaded at most once per program. Loading binds all its named functions and records, then runs its top-level statements in order. Later imports reuse the loaded module.
- **Cycles.** An import cycle raises `ImportError` that names the chain.
- **Exports.** Only names declared with `export` are visible to importers. `from m import x` with an unexported `x` raises `ImportError`.
- **Imported names.** Imported names are read-only in the importing module. Assigning to one raises `NameError`.

### Foreign functions

- **Library resolution.** `extern "lib"` resolves `lib` through `package.toml` (the `[native.lib]` entry for the current platform), then through the system's library search path. The library loads at the first call into it, and a failure raises `ForeignError`.
- **C types.** Parameters and results use the fixed-width numerics `int8` … `int64`, `uint8` … `uint64`, `float32` and `float64`, the platform-sized integers `clong` and `csize`, and `char`, `cstring`, `ref T`, `ptr T` and `callback(…)`.
- **Platform-sized integers.** `clong` is C `long`, which is 32 bits on Windows and 64 bits on macOS and Linux. `csize` is C `size_t`, which is 64 bits on every supported platform. Both convert to and from Axon `int`, so a binding such as CVODE's `long int` counters works unchanged on every platform.
- **Argument conversion.** Each argument is converted to its declared C type before the call. A value that does not fit, such as `3.5` for `int32` or `2^40` for `int32`, raises `TypeError`.
- **`ref T`.** The runtime passes a pointer to a temporary holding the converted value. After the call, it converts the temporary back and assigns it to the argument variable, which must therefore be a variable, not an expression.
- **`ptr T`.** The value must be an array whose element type matches `T` exactly: `ptr float64` needs a real array and `ptr complex` a complex one. Its buffer is passed directly, after being made unique if it is shared, so native writes affect only that variable. A mismatch raises `TypeError`.
- **`callback`.** An Axon function passed for a callback parameter gets a native trampoline with the declared signature. The trampoline stays alive until the extern function returns, and longer if it is stored with `keep(cb)`. An error inside the callback is recorded, the callback returns 0 (or a null pointer), and the error is re-raised in Axon once the outer native call returns.
- **Threads.** Native code must not call a trampoline from another thread. Doing so raises `ForeignError` and does not run the Axon function.

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
