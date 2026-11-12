unit Axon.Help;

(* The REPL's help command (reference, "The REPL").

   help name shows, for
   - a function: its header as written, then its docstring indented by two
     spaces;
   - a record type: record T(field: type, ...), then its docstring;
   - a module: module m, its docstring and its exported names;
   - a built-in: its parameters and a one-line description, from the table
     below (built-ins have no source to read docstrings from);
   - a keyword (help for): its form, what it does and examples (KeywordHelp),
     since a keyword is not a value to look up.
   Anything without a docstring shows "  (no documentation)"; any other value
   shows "name is a T". *)

interface

uses
  Axon.Values;

{ The help text for the value V found under Name, as lines without a final
  line break. }
function HelpText(const Name: string; const V: TAxValue): TArray<string>;

{ The help on a keyword such as for or while, or nil when Name is not one. }
function KeywordHelp(const Name: string): TArray<string>;

{ What "help" alone shows. }
function HelpUsage: TArray<string>;

implementation

uses
  System.SysUtils, System.Math,
  Axon.Ast, Axon.Interp, Axon.Ffi;

type
  TBuiltinDoc = record
    Name, Params, Text: string;
  end;

const
  NoDoc = '  (no documentation)';

  BuiltinDocs: array[0..123] of TBuiltinDoc = (
    (Name: 'zeros';    Params: '(m, n)';  Text: 'A real m' + #$00D7 + 'n matrix of zeros; zeros(n) is an n-vector'),
    (Name: 'ones';     Params: '(m, n)';  Text: 'A real m' + #$00D7 + 'n matrix of ones; ones(n) is an n-vector'),
    (Name: 'eye';      Params: '(m, n)';  Text: 'The m' + #$00D7 + 'n identity matrix; eye(n) is n' + #$00D7 + 'n'),
    (Name: 'rand';     Params: '(m, n)';  Text: 'Uniform random numbers in [0, 1): a scalar, an n-vector or an m' + #$00D7 + 'n matrix'),
    (Name: 'linspace'; Params: '(a, b, n)'; Text: 'n equally spaced values from a to b, as a vector'),
    (Name: 'range';    Params: '(start, stop, step)'; Text: 'The range start:step:stop (step 1 if left out): range(0, 1, 0.1) is 0:0.1:1; range(n) is 1:n'),
    (Name: 'size';     Params: '(A, dim)'; Text: 'The number of rows and columns of A, as two values, or the size along dim'),
    (Name: 'sum';      Params: '(A, dim)'; Text: 'The sum of all elements, or the sums along dim'),
    (Name: 'prod';     Params: '(A, dim)'; Text: 'The product of all elements, or the products along dim'),
    (Name: 'mean';     Params: '(A, dim)'; Text: 'The mean of all elements, or the means along dim'),
    (Name: 'all';      Params: '(A)';     Text: 'True when every element of a bool array is true'),
    (Name: 'any';      Params: '(A)';     Text: 'True when some element of a bool array is true'),
    (Name: 'dot';      Params: '(u, v)';  Text: 'The inner product, with u conjugated'),
    (Name: 'adjoint';  Params: '(A)';     Text: 'The conjugate transpose'),
    (Name: 'tr';       Params: '(A)';     Text: 'The transpose, the same as A'''),
    (Name: 'trace';    Params: '(A)';     Text: 'The sum of the diagonal of a square matrix'),
    (Name: 'isequal';  Params: '(a, b)';  Text: 'True when two values are equal as whole values'),
    (Name: 'isa';      Params: '(x, T)';  Text: 'True when x is exactly of type T: a name such as "int" or "vector{real}", or a record type'),
    (Name: 'keep';     Params: '(f)';     Text: 'Keeps a callback valid after the extern call that received it'),
    (Name: 'parse_function'; Params: '(params, expr)'; Text: 'A function made from text: parse_function("x, y", "2*sin(x) + y^2"), or parse_function("function(x) ... end")'),
    (Name: 'atexit';   Params: '(f)';     Text: 'Calls f() when the program ends normally; the last registered runs first'),
    (Name: 'eltype';   Params: '(A)';     Text: 'The element type of an array, as a string'),
    (Name: 'reshape';  Params: '(A, m, n)'; Text: 'The elements of A in column-major order, as an m' + #$00D7 + 'n matrix or an m-vector'),
    (Name: 'sparse';   Params: '(i, j, v, m, n)'; Text: 'A sparse matrix from index vectors and values, or sparse(A) from a dense matrix'),
    (Name: 'speye';    Params: '(m, n)';  Text: 'The sparse identity; speye(n) is n' + #$00D7 + 'n'),
    (Name: 'nnz';      Params: '(A)';     Text: 'The number of stored entries of a sparse matrix, or of nonzeros of an array'),
    (Name: 'full';     Params: '(S)';     Text: 'A sparse matrix as a dense matrix'),
    (Name: 'splu';     Params: '(S)';     Text: 'Two sparse values L, U with S = L*U'),
    (Name: 'vector';   Params: '(x)';     Text: 'x as a vector: a list of numbers, a range, a matrix (column by column) or a number; vector() is an empty real vector'),
    (Name: 'append';   Params: '(l, x)';  Text: 'A new list or vector with x added at the end'),
    (Name: 'sort';     Params: '(x, order)'; Text: 'A vector or list in order, smallest first; sort(x, "descend") largest first'),
    (Name: 'sortperm'; Params: '(x, order)'; Text: 'The positions p that put x in order, so x[p] is sorted; order "ascend" or "descend"'),
    (Name: 'get';      Params: '(d, key, default)'; Text: 'd[key], or default when the key is missing'),
    (Name: 'keys';     Params: '(d)';     Text: 'The keys of a dictionary, as a list in insertion order'),
    (Name: 'haskey';   Params: '(d, key)'; Text: 'True when the dictionary has the key'),
    (Name: 'dict';     Params: '(key => value, ...)'; Text: 'A dictionary with the given entries'),
    (Name: 'print';    Params: '(a, b, ...)'; Text: 'Writes the values separated by spaces, without a newline'),
    (Name: 'println';  Params: '(a, b, ...)'; Text: 'Writes the values separated by spaces, then a newline'),
    (Name: 'format';   Params: '(x, decimals)'; Text: 'x as text with exactly that many decimals, rounded: format(3.14159, 2) is "3.14"'),
    (Name: 'error';    Params: '(kind, message)'; Text: 'Raises an error; error("text") raises a UserError'),
    (Name: 'string';   Params: '(x)';     Text: 'The display form of a value, as a string'),
    (Name: 'split';    Params: '(s, sep)'; Text: 'The words of s (split at spaces), or with sep the pieces between each sep, as a list'),
    (Name: 'join';     Params: '(parts, sep)'; Text: 'The strings of a list joined into one, with sep between them'),
    (Name: 'trim';     Params: '(s)';     Text: 's without spaces, tabs and line breaks at either end'),
    (Name: 'ltrim';    Params: '(s)';     Text: 's without spaces, tabs and line breaks at the start'),
    (Name: 'rtrim';    Params: '(s)';     Text: 's without spaces, tabs and line breaks at the end'),
    (Name: 'upper';    Params: '(s)';     Text: 's in capital letters'),
    (Name: 'lower';    Params: '(s)';     Text: 's in small letters'),
    (Name: 'contains'; Params: '(s, part)'; Text: 'True when part occurs in s'),
    (Name: 'startswith'; Params: '(s, part)'; Text: 'True when s begins with part'),
    (Name: 'endswith'; Params: '(s, part)'; Text: 'True when s ends with part'),
    (Name: 'find';     Params: '(s, part, start)'; Text: 'The position of the first part in s (from start), or 0'),
    (Name: 'replace';  Params: '(s, old, new)'; Text: 's with every old replaced by new'),
    (Name: 'repeat';   Params: '(s, n)';  Text: 's repeated n times'),
    (Name: 'length';   Params: '(x)';     Text: 'The number of elements of an array, list, string or dictionary'),
    (Name: 'typeof';   Params: '(x)';     Text: 'The type of a value, as a string'),
    (Name: 'sqrt';     Params: '(x)';     Text: 'The square root (NaN for a negative real; use a complex argument)'),
    (Name: 'exp';      Params: '(x)';     Text: 'The exponential'),
    (Name: 'log';      Params: '(x)';     Text: 'The natural logarithm (NaN for a negative real)'),
    (Name: 'sin';      Params: '(x)';     Text: 'The sine'),
    (Name: 'cos';      Params: '(x)';     Text: 'The cosine'),
    (Name: 'tan';      Params: '(x)';     Text: 'The tangent'),
    (Name: 'asin';     Params: '(x)';     Text: 'The inverse sine'),
    (Name: 'acos';     Params: '(x)';     Text: 'The inverse cosine'),
    (Name: 'atan';     Params: '(x)';     Text: 'The inverse tangent'),
    (Name: 'sinh';     Params: '(x)';     Text: 'The hyperbolic sine'),
    (Name: 'cosh';     Params: '(x)';     Text: 'The hyperbolic cosine'),
    (Name: 'tanh';     Params: '(x)';     Text: 'The hyperbolic tangent'),
    (Name: 'asinh';    Params: '(x)';     Text: 'The inverse hyperbolic sine'),
    (Name: 'acosh';    Params: '(x)';     Text: 'The inverse hyperbolic cosine'),
    (Name: 'atanh';    Params: '(x)';     Text: 'The inverse hyperbolic tangent'),
    (Name: 'log10';    Params: '(x)';     Text: 'The base-10 logarithm (exact for powers of 10)'),
    (Name: 'log2';     Params: '(x)';     Text: 'The base-2 logarithm (exact for powers of 2)'),
    (Name: 'atan2';    Params: '(y, x)';  Text: 'The angle of the point (x, y), in (-pi, pi]; elementwise for arrays'),
    (Name: 'deg2rad';  Params: '(x)';     Text: 'An angle in degrees converted to radians, x * pi / 180'),
    (Name: 'rad2deg';  Params: '(x)';     Text: 'An angle in radians converted to degrees, x * 180 / pi'),
    (Name: 'abs';      Params: '(x)';     Text: 'The absolute value, or the modulus of a complex number'),
    (Name: 'int';      Params: '(x)';     Text: 'Converts to int, truncating toward zero; int("42") reads a string'),
    (Name: 'floor';    Params: '(x)';     Text: 'The largest integer not above x'),
    (Name: 'ceil';     Params: '(x)';     Text: 'The smallest integer not below x'),
    (Name: 'round';    Params: '(x)';     Text: 'The nearest integer, halves away from zero'),
    (Name: 'real';     Params: '(z)';     Text: 'The real part; real("2.5") reads a number from a string'),
    (Name: 'imag';     Params: '(z)';     Text: 'The imaginary part'),
    (Name: 'conj';     Params: '(z)';     Text: 'The complex conjugate'),
    (Name: 'arg';      Params: '(z)';     Text: 'The argument (phase angle) of a complex number'),
    (Name: 'complex';  Params: '(re, im)'; Text: 'A complex number from its parts'),
    (Name: 'div';      Params: '(a, b)';  Text: 'Integer division, rounding toward minus infinity'),
    (Name: 'mod';      Params: '(a, b)';  Text: 'The remainder of div, with the sign of b'),
    (Name: 'min';      Params: '(a, b)';  Text: 'The smaller of two values, or the smallest element of an array'),
    (Name: 'max';      Params: '(a, b)';  Text: 'The larger of two values, or the largest element of an array'),
    (Name: 'factorial'; Params: '(n)';    Text: 'n! for an int n >= 0'),
    (Name: '__copies'; Params: '()';      Text: 'The number of array copies made so far (for tests)'),
    (Name: '__native_library'; Params: '(name)'; Text: 'The path a native library name resolves to (for tests)'),
    (Name: '__jit_compiled'; Params: '(f)'; Text: 'True once f has compiled code (JIT; for tests)'),
    (Name: '__jit_reason'; Params: '(f)'; Text: 'Why f was not compiled (JIT; for tests)'),
    (Name: '__jit_mode'; Params: '([mode])'; Text: 'The JIT mode; with "off", "on" or "force", sets it and returns the old one'),
    (Name: '__jit_loops'; Params: '()'; Text: 'How many times a top-level loop has run compiled (JIT; for tests)'),
    // io
    (Name: 'read_file';   Params: '(path)'; Text: 'The contents of a UTF-8 text file, as a string'),
    (Name: 'read_bytes';  Params: '(path)'; Text: 'The bytes of a file, as an int vector'),
    (Name: 'write_file';  Params: '(path, text)'; Text: 'Writes a string to a file as UTF-8, replacing it'),
    (Name: 'file_exists'; Params: '(path)'; Text: 'True when the file exists'),
    (Name: 'current_dir'; Params: '()'; Text: 'The working directory, which relative paths are read from, as a full path'),
    (Name: 'set_current_dir'; Params: '(path)'; Text: 'Makes path (full, or relative such as "data" or "..") the working directory'),
    (Name: 'delete_file'; Params: '(path)'; Text: 'Deletes a file; false when there was no such file'),
    (Name: 'write_json'; Params: '(path, value)'; Text: 'Writes a value as JSON (records and string-keyed dictionaries as objects, arrays as numbers)'),
    (Name: 'read_json'; Params: '(path)'; Text: 'Reads a JSON file: objects as records, number arrays as vectors or matrices'),
    (Name: 'read_lines'; Params: '(path)'; Text: 'The lines of a text file, as a list of strings'),
    (Name: 'read_csv'; Params: '(path, sep)'; Text: 'A CSV table of numbers, as a record {names, data}: column names (or nothing) and a real matrix'),
    (Name: 'write_csv'; Params: '(path, A, names, sep)'; Text: 'Writes a matrix (or a vector as one column) as CSV, optionally under a header of column names'),
    // time
    (Name: 'clock';   Params: '()'; Text: 'Seconds on a monotonic high-resolution clock; subtract two readings'),
    (Name: 'now';     Params: '()'; Text: 'Wall-clock seconds since 1970-01-01 UTC'),
    (Name: 'sleep';   Params: '(seconds)'; Text: 'Pauses for the given number of seconds'),
    (Name: 'elapsed'; Params: '(f, args...)'; Text: 'Seconds taken by one call f(args...)'),
    (Name: 'bench';   Params: '(f, args...)'; Text: 'Times repeated calls of f(args...): a record of per-call seconds best, mean and worst, with loops and runs'),
    (Name: 'time.format'; Params: '(seconds)'; Text: 'Seconds as text in a fitting unit, such as "12.3 ms"'),
    // random (rand shares the prelude's row)
    (Name: 'seed';    Params: '(n)'; Text: 'Seeds the random generator with an int, so later draws (rand included) repeat'),
    (Name: 'randn';   Params: '(m, n)'; Text: 'Standard normal random numbers: a scalar, an n-vector or an m' + #$00D7 + 'n matrix'),
    (Name: 'uniform'; Params: '(a, b, m, n)'; Text: 'Uniform random reals in [a, b): a scalar, or an n-vector or m' + #$00D7 + 'n matrix'),
    (Name: 'normal';  Params: '(mu, sigma, m, n)'; Text: 'Normal random numbers with mean mu and standard deviation sigma: a scalar, an n-vector or an m' + #$00D7 + 'n matrix'),
    (Name: 'randint'; Params: '(lo, hi, m, n)'; Text: 'Random ints from lo to hi inclusive, each equally likely: a scalar, an n-vector or an m' + #$00D7 + 'n matrix'),
    // graphics
    (Name: 'save';       Params: '(scene, path)'; Text: 'Renders a scene to a .png, .svg or .pdf file'),
    (Name: 'text_width'; Params: '(text, size, font)'; Text: 'The width of text in points, for layout'),
    (Name: 'show';       Params: '(scene)'; Text: 'Renders a scene to a PNG and shows it (in the IDE, or a viewer); returns the path'),
    (Name: 'frame';      Params: '(scene, sent)'; Text: 'Shows a scene as the next frame of an animation, in place of the last (in the IDE); with sent, only the items after the first sent are new')
  );

function DocLines(const Doc: TArray<string>): TArray<string>;
var
  L: string;
begin
  Result := nil;
  if Length(Doc) = 0 then
  begin
    Result := [NoDoc];
    Exit;
  end;
  for L in Doc do
    if L = '' then
      Result := Result + ['']
    else
      Result := Result + ['  ' + L];
end;

{ A header built from the parameters, for functions whose source text is not
  at hand (nested functions and lambdas). }
function FallbackHeader(D: TFunctionDecl): string;
var
  P: TParam;
  Pos, Kw: string;
  First: Boolean;
begin
  Pos := '';
  Kw := '';
  First := True;
  for P in D.Params do
    if P.IsKeyword then
    begin
      if Kw <> '' then Kw := Kw + ', ';
      Kw := Kw + P.Name;
      if P.TypeRef <> nil then Kw := Kw + ': ' + P.TypeRef.ToString;
      Kw := Kw + ' = ' + #$2026;
    end
    else
    begin
      if not First then Pos := Pos + ', ';
      First := False;
      Pos := Pos + P.Name;
      if P.TypeRef <> nil then Pos := Pos + ': ' + P.TypeRef.ToString;
      if P.Default <> nil then Pos := Pos + ' = ' + #$2026;
    end;
  if Kw <> '' then
    Pos := Pos + '; ' + Kw;
  if D.Name <> '' then
    Result := D.Name + '(' + Pos + ')'
  else
    Result := 'anonymous function(' + Pos + ')';
  if D.ReturnType <> nil then
    Result := Result + ': ' + D.ReturnType.ToString;
end;

function FunctionHelp(F: TFunctionObj): TArray<string>;
var
  D: TFunctionDecl;
  Header: string;
begin
  D := F.Decl;
  Header := D.Header;
  if Header = '' then
    Header := FallbackHeader(D);
  Result := [Header] + DocLines(D.Doc.ToArray);
end;

function RecordTypeHelp(RT: TRecordTypeObj): TArray<string>;
var
  K: Integer;
  S: string;
begin
  S := '';
  for K := 0 to High(RT.FieldNames) do
  begin
    if K > 0 then S := S + ', ';
    S := S + RT.FieldNames[K];
    if (K <= High(RT.FieldTypes)) and (RT.FieldTypes[K] <> nil) then
      S := S + ': ' + RT.FieldTypes[K].ToString;
  end;
  Result := ['record ' + RT.Name + '(' + S + ')'] + DocLines(RT.Doc);
end;

function ModuleHelp(M: TModuleObj): TArray<string>;
var
  Names: string;
  N: string;
begin
  Result := ['module ' + M.Name] + DocLines(M.Doc);
  if (M.ExportNames <> nil) and (M.ExportNames.Count > 0) then
  begin
    Names := '';
    for N in M.ExportNames do
    begin
      if Names <> '' then Names := Names + ', ';
      Names := Names + N;
    end;
    Result := Result + ['  exports: ' + Names];
  end;
end;

function BuiltinHelp(const Name: string): TArray<string>;
var
  D: TBuiltinDoc;
begin
  // A module built-in may be registered as m.f to tell it from a prelude
  // function of the same name; its header shows f, as for other modules.
  for D in BuiltinDocs do
    if D.Name = Name then
    begin
      Result := [D.Name.Substring(D.Name.LastIndexOf('.') + 1) + D.Params, '  ' + D.Text];
      Exit;
    end;
  Result := [Name + '(...)', NoDoc];
end;

function ExternHelp(F: TExternFuncObj): TArray<string>;
var
  S: string;
  K: Integer;
begin
  S := '';
  for K := 0 to High(F.ParamNames) do
  begin
    if K > 0 then S := S + ', ';
    S := S + F.ParamNames[K];
  end;
  Result := [F.Name + '(' + S + ')',
    Format('  foreign function %s from "%s"', [F.Symbol, F.LibName])];
end;

{ ---- keywords ---- }

type
  { Help on a keyword: the names it covers (separated by spaces), then its
    lines: the form (unindented), a description (indented by two spaces), and
    examples (indented by four, which the IDE shows as code). }
  TKeywordDoc = record
    Names: string;
    Lines: TArray<string>;
  end;

function KeywordDocs: TArray<TKeywordDoc>;

  function K(const Names: string; const Lines: array of string): TKeywordDoc;
  var
    I: Integer;
  begin
    Result.Names := ' ' + Names + ' ';
    SetLength(Result.Lines, Length(Lines));
    for I := 0 to High(Lines) do
      Result.Lines[I] := Lines[I];
  end;

begin
  Result := [
    K('for in', [
      'for v in values ... end',
      '  Runs the body once for each element of values: a range (a:b, or a:h:b with',
      '  step h), the elements of a vector or matrix (column by column), the items',
      '  of a list, the keys of a dictionary, or the characters of a string. v is a',
      '  new variable on each turn and does not exist after the loop. break leaves',
      '  the loop; continue goes on to the next element. For example:',
      '    for i in 1:2:9',
      '      print(i, "")',
      '    end',
      '    for i in 1:length(v)       # positions as well as values',
      '      println(i, v[i])',
      '    end',
      '    for name in {"Ann", "Bo"}',
      '      println("hello", name)',
      '    end',
      '  The manual''s section "Loops" shows each form.']),
    K('while', [
      'while condition ... end',
      '  Runs the body as long as condition, a bool, is true; it is tested before',
      '  each turn. break leaves the loop, continue starts the next turn. For',
      '  example:',
      '    n = 1',
      '    while n < 100',
      '      n = n * 2',
      '    end',
      '    while true                  # the end is decided in the middle',
      '      x = x / 2',
      '      if x < 0.01',
      '        break',
      '      end',
      '    end']),
    K('break continue', [
      'break',
      'continue',
      '  Inside a for or while loop: break leaves the loop, continue goes on to the',
      '  next turn. In nested loops both act on the innermost loop. For example:',
      '    for k in 1:100',
      '      if mod(k, 7) != 0',
      '        continue',
      '      end',
      '      if k > 50',
      '        break',
      '      end',
      '      println(k)',
      '    end']),
    K('if elseif else', [
      'if condition ... elseif condition ... else ... end',
      '  Runs the first branch whose condition is true, or else the else branch.',
      '  Conditions must be bools: numbers, strings and arrays are not true or',
      '  false (use all or any for a bool array). A short if fits on one line.',
      '  For example:',
      '    if x > 0',
      '      println("positive")',
      '    elseif x < 0',
      '      println("negative")',
      '    else',
      '      println("zero")',
      '    end',
      '    if x > 0 println("positive") end']),
    K('function return', [
      'function name(a, b; key = default) ... return value ... end',
      '  Defines a function. Parameters after ";" are keyword parameters with',
      '  defaults. return gives the result (several values: return a, b) and ends',
      '  the call; a function that reaches end returns nothing. A type after a',
      '  parameter or after the ")" is checked. function(x) ... end without a',
      '  name is an anonymous function. For example:',
      '    function area(r: real): real',
      '      return pi * r^2',
      '    end',
      '    function scale(x; by = 2.0)',
      '      return x * by',
      '    end',
      '    function minmax(v)',
      '      return min(v), max(v)',
      '    end',
      '    [lo, hi] = minmax([3, 1, 4])']),
    K('local global', [
      'local x = value',
      'global x',
      '  local makes a new variable in the current block, hiding any outer one of',
      '  the same name. global, inside a function, makes x refer to the script''s',
      '  (module''s) variable x, so the function can assign it; without it, an',
      '  assignment in a function makes a local variable. For example:',
      '    count = 0',
      '    function tick()',
      '      global count',
      '      count = count + 1',
      '    end',
      '  Passing the value in and returning the new one is often clearer, and',
      '  such a function can be compiled: count = tick(count).']),
    K('try catch', [
      'try ... catch err ... end',
      '  Runs the try block; if an error is raised in it, the catch block runs',
      '  with err, a record with fields kind, message and trace. error("text")',
      '  raises an error. For example:',
      '    try',
      '      x = int("12x")',
      '    catch err',
      '      println(err.kind, err.message)',
      '    end']),
    K('import from as export', [
      'import m',
      'import m as a',
      'from m import f, g',
      'export function f(...)',
      '  import loads the module m (a standard module, or m.sci) and names it m',
      '  (or a); from m import f binds f itself. In a module, export marks what',
      '  importers may use. For example:',
      '    import linalg',
      '    import plot as p',
      '    from stats import mean']),
    K('record', [
      'record Name  field: type ... end',
      '  Declares a record type; Name(...) makes one, by position or by field',
      '  name, checking the field types. A literal {a: 1, b: 2.0} makes a record',
      '  without a declared type. For example:',
      '    record Point',
      '      x: real',
      '      y: real',
      '    end',
      '    p = Point(1.0, 2.0)',
      '    q = Point(y = 5.0, x = 0.0)',
      '    println(p.x + q.y)']),
    K('and or not', [
      'a and b',
      'a or b',
      'not a',
      '  Logical operators on bools. and and or evaluate b only when it is needed.',
      '  For example:',
      '    if x > 0 and x < 10',
      '      println("a digit")',
      '    end']),
    K('true false nothing', [
      'true',
      'false',
      'nothing',
      '  true and false are the two bools. nothing is the value of a function',
      '  that returns no value, and of a variable declared without one.']),
    K('end', [
      'end',
      '  Closes a block: if, for, while, function, try, record. Inside the',
      '  brackets of an index it means the last position: v[end], A[end, 1].']),
    K('extern', [
      'extern "library"  function name(a: type, ...): type ... end',
      '  Declares functions of a C library so Axon can call them. See the',
      '  Language Reference, "Foreign functions".'])];
end;

{ The help on a keyword, or nil when Name is not one. }
function KeywordHelp(const Name: string): TArray<string>;
var
  D: TKeywordDoc;
begin
  for D in KeywordDocs do
    if D.Names.Contains(' ' + Name + ' ') then
      Exit(D.Lines);
  Result := nil;
end;

function HelpText(const Name: string; const V: TAxValue): TArray<string>;
var
  T: string;
begin
  // The prelude's constants, unless the name has been reassigned.
  if (V.Kind = vkReal) and (Name = 'pi') and (V.R = Pi) then
  begin
    Result := ['pi', '  The ratio of a circle''s circumference to its diameter, 3.14159265358979'];
    Exit;
  end;
  if (V.Kind = vkReal) and (Name = 'e') and (V.R = Exp(1.0)) then
  begin
    Result := ['e', '  The base of the natural logarithm, 2.71828182845905'];
    Exit;
  end;
  case V.Kind of
    vkFunction:   Result := FunctionHelp(TFunctionObj(V.Obj));
    vkBuiltin:    Result := BuiltinHelp(TCallableObj(V.Obj).Name);
    vkExtern:     Result := ExternHelp(TExternFuncObj(V.Obj));
    vkRecordType: Result := RecordTypeHelp(AsRecordType(V));
    vkModule:     Result := ModuleHelp(TModuleObj(V.Obj));
  else
    T := TypeName(V);
    if CharInSet(T[1], ['a', 'e', 'i', 'o', 'u']) then
      Result := [Format('%s is an %s', [Name, T])]
    else
      Result := [Format('%s is a %s', [Name, T])];
  end;
end;

function HelpUsage: TArray<string>;
begin
  Result := [
    'Type a statement or expression to run it; its value is displayed.',
    'A trailing ";" suppresses the display.',
    'help name   shows the documentation of a function, record type or module, or of a keyword (help for)',
    'run "file.sci"   runs a file in this session; the names it defines stay',
    'Ctrl+D (Ctrl+Z then Enter on Windows) ends the session.'];
end;

end.
