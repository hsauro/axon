unit Axon.Help;

(* The REPL's help command (reference, "The REPL").

   help name shows, for
   - a function: its header as written, then its docstring indented by two
     spaces;
   - a record type: record T(field: type, ...), then its docstring;
   - a module: module m, its docstring and its exported names;
   - a built-in: its parameters and a one-line description, from the table
     below (built-ins have no source to read docstrings from).
   Anything without a docstring shows "  (no documentation)"; any other value
   shows "name is a T". *)

interface

uses
  Axon.Values;

{ The help text for the value V found under Name, as lines without a final
  line break. }
function HelpText(const Name: string; const V: TAxValue): TArray<string>;

{ What "help" alone shows. }
function HelpUsage: TArray<string>;

implementation

uses
  System.SysUtils,
  Axon.Ast, Axon.Interp, Axon.Ffi;

type
  TBuiltinDoc = record
    Name, Params, Text: string;
  end;

const
  NoDoc = '  (no documentation)';

  BuiltinDocs: array[0..86] of TBuiltinDoc = (
    (Name: 'zeros';    Params: '(m, n)';  Text: 'A real m' + #$00D7 + 'n matrix of zeros; zeros(n) is an n-vector'),
    (Name: 'ones';     Params: '(m, n)';  Text: 'A real m' + #$00D7 + 'n matrix of ones; ones(n) is an n-vector'),
    (Name: 'eye';      Params: '(m, n)';  Text: 'The m' + #$00D7 + 'n identity matrix; eye(n) is n' + #$00D7 + 'n'),
    (Name: 'rand';     Params: '(m, n)';  Text: 'Uniform random numbers in [0, 1): a scalar, an n-vector or an m' + #$00D7 + 'n matrix'),
    (Name: 'linspace'; Params: '(a, b, n)'; Text: 'n equally spaced values from a to b, as a vector'),
    (Name: 'size';     Params: '(A, dim)'; Text: 'The number of rows and columns of A, as two values, or the size along dim'),
    (Name: 'sum';      Params: '(A, dim)'; Text: 'The sum of all elements, or the sums along dim'),
    (Name: 'prod';     Params: '(A, dim)'; Text: 'The product of all elements, or the products along dim'),
    (Name: 'mean';     Params: '(A, dim)'; Text: 'The mean of all elements, or the means along dim'),
    (Name: 'all';      Params: '(A)';     Text: 'True when every element of a bool array is true'),
    (Name: 'any';      Params: '(A)';     Text: 'True when some element of a bool array is true'),
    (Name: 'dot';      Params: '(u, v)';  Text: 'The inner product, with u conjugated'),
    (Name: 'adjoint';  Params: '(A)';     Text: 'The conjugate transpose'),
    (Name: 'isequal';  Params: '(a, b)';  Text: 'True when two values are equal as whole values'),
    (Name: 'keep';     Params: '(f)';     Text: 'Keeps a callback valid after the extern call that received it'),
    (Name: 'eltype';   Params: '(A)';     Text: 'The element type of an array, as a string'),
    (Name: 'reshape';  Params: '(A, m, n)'; Text: 'The elements of A in column-major order, as an m' + #$00D7 + 'n matrix or an m-vector'),
    (Name: 'sparse';   Params: '(i, j, v, m, n)'; Text: 'A sparse matrix from index vectors and values, or sparse(A) from a dense matrix'),
    (Name: 'speye';    Params: '(m, n)';  Text: 'The sparse identity; speye(n) is n' + #$00D7 + 'n'),
    (Name: 'nnz';      Params: '(A)';     Text: 'The number of stored entries of a sparse matrix, or of nonzeros of an array'),
    (Name: 'full';     Params: '(S)';     Text: 'A sparse matrix as a dense matrix'),
    (Name: 'splu';     Params: '(S)';     Text: 'Two sparse values L, U with S = L*U'),
    (Name: 'append';   Params: '(l, x)';  Text: 'A new list or vector with x added at the end'),
    (Name: 'get';      Params: '(d, key, default)'; Text: 'd[key], or default when the key is missing'),
    (Name: 'keys';     Params: '(d)';     Text: 'The keys of a dictionary, as a list in insertion order'),
    (Name: 'haskey';   Params: '(d, key)'; Text: 'True when the dictionary has the key'),
    (Name: 'dict';     Params: '(key => value, ...)'; Text: 'A dictionary with the given entries'),
    (Name: 'print';    Params: '(a, b, ...)'; Text: 'Writes the values separated by spaces, without a newline'),
    (Name: 'println';  Params: '(a, b, ...)'; Text: 'Writes the values separated by spaces, then a newline'),
    (Name: 'error';    Params: '(kind, message)'; Text: 'Raises an error; error("text") raises a UserError'),
    (Name: 'string';   Params: '(x)';     Text: 'The display form of a value, as a string'),
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
    (Name: 'abs';      Params: '(x)';     Text: 'The absolute value, or the modulus of a complex number'),
    (Name: 'int';      Params: '(x)';     Text: 'Converts to int; a real must be a whole number'),
    (Name: 'floor';    Params: '(x)';     Text: 'The largest integer not above x'),
    (Name: 'ceil';     Params: '(x)';     Text: 'The smallest integer not below x'),
    (Name: 'round';    Params: '(x)';     Text: 'The nearest integer, halves away from zero'),
    (Name: 'real';     Params: '(z)';     Text: 'The real part'),
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
    // io
    (Name: 'read_file';   Params: '(path)'; Text: 'The contents of a UTF-8 text file, as a string'),
    (Name: 'read_bytes';  Params: '(path)'; Text: 'The bytes of a file, as an int vector'),
    (Name: 'write_file';  Params: '(path, text)'; Text: 'Writes a string to a file as UTF-8, replacing it'),
    (Name: 'file_exists'; Params: '(path)'; Text: 'True when the file exists'),
    (Name: 'delete_file'; Params: '(path)'; Text: 'Deletes a file; false when there was no such file'),
    // time
    (Name: 'clock';   Params: '()'; Text: 'Seconds on a monotonic high-resolution clock; subtract two readings'),
    (Name: 'now';     Params: '()'; Text: 'Wall-clock seconds since 1970-01-01 UTC'),
    (Name: 'sleep';   Params: '(seconds)'; Text: 'Pauses for the given number of seconds'),
    (Name: 'elapsed'; Params: '(f, args...)'; Text: 'Seconds taken by one call f(args...)'),
    (Name: 'bench';   Params: '(f, args...)'; Text: 'Times repeated calls of f(args...): a record of per-call seconds best, mean and worst, with loops and runs'),
    (Name: 'format';  Params: '(seconds)'; Text: 'Seconds as text in a fitting unit, such as "12.3 ms"'),
    // random (rand shares the prelude's row)
    (Name: 'seed';    Params: '(n)'; Text: 'Seeds the random generator with an int, so later draws (rand included) repeat'),
    (Name: 'randn';   Params: '(m, n)'; Text: 'Standard normal random numbers: a scalar, an n-vector or an m' + #$00D7 + 'n matrix'),
    (Name: 'uniform'; Params: '(a, b, m, n)'; Text: 'Uniform random reals in [a, b): a scalar, or an n-vector or m' + #$00D7 + 'n matrix'),
    (Name: 'normal';  Params: '(mu, sigma, m, n)'; Text: 'Normal random numbers with mean mu and standard deviation sigma: a scalar, an n-vector or an m' + #$00D7 + 'n matrix'),
    (Name: 'randint'; Params: '(lo, hi, m, n)'; Text: 'Random ints from lo to hi inclusive, each equally likely: a scalar, an n-vector or an m' + #$00D7 + 'n matrix'),
    // graphics
    (Name: 'save';       Params: '(scene, path)'; Text: 'Renders a scene to a .png, .svg or .pdf file'),
    (Name: 'text_width'; Params: '(text, size, font)'; Text: 'The width of text in points, for layout'),
    (Name: 'show';       Params: '(scene)'; Text: 'Renders a scene to a PNG and shows it (in the IDE, or a viewer); returns the path')
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
  for D in BuiltinDocs do
    if D.Name = Name then
    begin
      Result := [D.Name + D.Params, '  ' + D.Text];
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

function HelpText(const Name: string; const V: TAxValue): TArray<string>;
var
  T: string;
begin
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
    'help name   shows the documentation of a function, record type or module',
    'run "file.sci"   runs a file in this session; the names it defines stay',
    'Ctrl+D (Ctrl+Z then Enter on Windows) ends the session.'];
end;

end.
