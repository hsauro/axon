unit Axon.Jit;

(* The JIT's runtime (doc/Axon-JIT-Plan.md): the mode, the session that
   lowers functions, code generation in groups (Axon.Jit.Mir), and the
   helpers that generated code calls.

   Compiling. JitCompile lowers a function through the process-wide
   session, which lowers the functions it calls as well, then generates
   every function lowered so far that has no code yet, as one group, and
   links them together, so calls within the group (recursion included) are
   resolved at once.

   Errors leave compiled code by status, never by exception (decision D4).
   The function where an error starts records it, as a kind and message
   (RtError, the range helpers), or as the exception a call through the
   interpreter raised (RtCall). Each compiled caller it passes through adds
   its call site (RtFrame). TakeJitError then builds the exception with
   these frames, exactly as the interpreter's trace would have them, and the
   interpreter raises it inside Invoke's frame handling. Helpers are cdecl
   and never let an exception escape into generated code, which has no
   unwind information. *)

interface

uses
  System.SysUtils, System.Generics.Collections,
  Axon.Ast, Axon.Values, Axon.Jit.Ir, Axon.Jit.Lower;

type
  TJitMode = (jmOff, jmOn, jmForce);

  TJitEntry = function(Args, Results: Pointer): Int64; cdecl;

  { A compiled function. Arguments and results are passed in 8-byte slots:
    bool and int as Int64, real as Double. }
  TJitCode = class
  public
    Id: Integer;
    Name: string;
    FileName: string;
    Entry: TJitEntry;
    ParamTypes: TArray<TJType>;
    ResultTypes: TArray<TJType>;
    Sites: TArray<TJSite>;
    CallSites: TObjectList<TObject>;   // TJitCallSite, owned
    // J7c: values read from outside, passed after the parameters (whose
    // types are the first NParams of ParamTypes); and, for a closure, the
    // names it creates locally, which must not exist outside when it runs.
    NParams: Integer;
    Captures: TArray<TJCapture>;
    LocalNames: TArray<string>;
    // J11: the string constants the code copies into its registers.
    Consts: TList<PAxValue>;
    // J12, a top-level loop: its variables from outside, in the order of the
    // out slots.
    Outers: TArray<TJOuter>;
    constructor Create;
    destructor Destroy; override;
  end;

  { What RtCall needs to call a callee through the interpreter, or (IsOp)
    to apply an operator with Axon.Ops. Array arguments and results are
    passed as pointers to value slots. }
  TJitCallSite = class
  public
    IsOp: Boolean;
    Op: Integer;                  // IsOp: the TTokenKind
    Name: string;
    Value: TAxValue;              // the callee, when nothing can rebind it
    ValuePtr: PAxValue;           // else the variable holding it
    ArgTypes: TArray<TJType>;
    Strings: TArray<string>;      // string literal arguments, by position
    IsLit: TArray<Boolean>;       // which arguments are those literals (others: registers)
    ResultTypes: TArray<TJType>;  // the values the caller uses
  end;

  { Addresses of the helpers, for the code generator. }
  TJitHelpers = record
    Error, CountInt, CountReal, PowReal, Call, Frame, Recursion: Pointer;
    Assign, Move, Clear, MakeUnique, Leave, IndexError, NewArray: Pointer;
    NewRecord, RecordUnique: Pointer;
    NewList, ListAppend, ListUnique: Pointer;
    StrConcat, StrCmp, StrOfInt, StrOfReal, StrLen: Pointer;
    GetInt, GetReal, SetInt, SetReal, SetBool: Pointer;
  end;

var
  JitMode: TJitMode = jmOn;    // J5: on by default; --jit=off or AXON_JIT=off turns it off
  JitDepth: PInteger;           // the interpreter's call depth
  JitMaxDepth: Integer = 10000;

{ Sets the mode from a name: off, on or force. False for another name. }
function SetJitMode(const Name: string): Boolean;
function JitModeName: string;

{ Called by the interpreter: how calls resolve, and its call-depth counter. }
procedure JitSetup(const Resolver: TJResolver; DepthPtr: PInteger; MaxDepth: Integer);

{ The JIR type of a value, for specialisation; jtNothing for one that does
  not compile. }
function JitTypeOf(const V: TAxValue): TJType;

{ Compiles a function (FuncObj is its TFunctionObj) for the types of the
  arguments it is called with, or returns nil, with the reason, when it is
  rejected or MIR is unavailable. }
function JitCompile(Decl: TFunctionDecl; FuncObj: TObject; const FileName: string;
  const ArgTypes: TArray<TJType>; IsClosure: Boolean; out Reason: string;
  const ArgValues: TAxValues = nil): TJitCode;

{ Compiles a top-level loop (J12): Decl is the declaration made for it, its
  body the loop; FuncObj resolves calls in the module root; Outer looks up
  names in the scopes around the loop now. Key tells this compilation apart
  from earlier ones of the same loop. nil, with the reason, when rejected. }
function JitCompileLoop(Decl: TFunctionDecl; FuncObj: TObject; const FileName, Key: string;
  const Outer: TJOuterLookup; out Reason: string): TJitCode;

{ The compiled code of a function, or nil: also for a function compiled
  only as a callee, which the interpreter has not called yet. }
function JitCodeOf(Decl: TFunctionDecl): TJitCode;

{ The error compiled code reported, as the exception to raise. }
function TakeJitError: Exception;

function JitHelpers: TJitHelpers;

implementation

uses
  System.Math,
  Axon.Errors, Axon.Ops, Axon.Tokens, Axon.NativeModules, Axon.Builtins, Axon.Jit.Mir,
  Axon.Native.Mir;

type
  TJitFrame = record
    Code: TJitCode;
    Site: Integer;
  end;

var
  Codes: TObjectList<TJitCode>;
  Session: TJSession;
  // The pending error
  PendExc: Exception;
  PendKind, PendMsg: string;
  PendCode: TJitCode;
  PendSite: Integer;
  PendFrames: TList<TJitFrame>;

constructor TJitCode.Create;
begin
  inherited Create;
  CallSites := TObjectList<TObject>.Create(True);
  Consts := TList<PAxValue>.Create;
end;

destructor TJitCode.Destroy;
var
  P: PAxValue;
begin
  for P in Consts do
    Dispose(P);
  Consts.Free;
  CallSites.Free;
  inherited;
end;

function SetJitMode(const Name: string): Boolean;
begin
  Result := True;
  if Name = 'off' then JitMode := jmOff
  else if Name = 'on' then JitMode := jmOn
  else if Name = 'force' then JitMode := jmForce
  else Result := False;
end;

function JitModeName: string;
const
  Names: array[TJitMode] of string = ('off', 'on', 'force');
begin
  Result := Names[JitMode];
end;

procedure JitSetup(const Resolver: TJResolver; DepthPtr: PInteger; MaxDepth: Integer);
begin
  Session.Resolver := Resolver;
  JitDepth := DepthPtr;
  JitMaxDepth := MaxDepth;
end;

{ ---- the pending error ---- }

procedure Pending(Fid, Site: Int64; const Kind, Msg: string);
begin
  PendExc := nil;
  PendKind := Kind;
  PendMsg := Msg;
  PendCode := Codes[Fid];
  PendSite := Site;
  PendFrames.Clear;
end;

function TakeJitError: Exception;
var
  E: Exception;
  Prev: TJitCode;
  Fr: TJitFrame;
  S: TJSite;
begin
  S := PendCode.Sites[PendSite];
  if PendExc <> nil then
  begin
    E := PendExc;
    if E is EAxonError then
      EAxonError(E).Locate(PendCode.FileName, S.Line, S.Col);
  end
  else
    E := EAxonError.CreateAt(PendKind, PendMsg, PendCode.FileName, S.Line, S.Col);
  // Each compiled caller the error passed through: close the callee's frame
  // and locate the caller's at its call.
  Prev := PendCode;
  for Fr in PendFrames do
    if E is EAxonError then
    begin
      EAxonError(E).LeaveFunction(Prev.Name);
      S := Fr.Code.Sites[Fr.Site];
      EAxonError(E).Locate(Fr.Code.FileName, S.Line, S.Col);
      Prev := Fr.Code;
    end;
  PendExc := nil;
  PendFrames.Clear;
  Result := E;
end;

{ ---- helpers called from generated code (cdecl, never raise) ---- }

{ Codes of the errors generated code raises itself. }
procedure RtError(Fid, Site, Code: Int64); cdecl;
const
  Ops: array[1..5] of string = ('+', '-', '*', 'unary -', '^');
begin
  if (Code >= 1) and (Code <= 5) then
    Pending(Fid, Site, OverflowError, 'integer overflow in ' + Ops[Code])
  else
    Pending(Fid, Site, 'InternalError', Format('unknown JIT error code %d', [Code]));
end;

{ A compiled callee failed: this caller's frame is at its call. }
procedure RtFrame(Fid, Site: Int64); cdecl;
var
  Fr: TJitFrame;
begin
  Fr.Code := Codes[Fid];
  Fr.Site := Site;
  PendFrames.Add(Fr);
end;

{ The call depth went over the limit at a call, as in Invoke. }
procedure RtRecursion(CS: TJitCallSite; Fid, Site: Int64); cdecl;
begin
  Pending(Fid, Site, RecursionError, Format('calls nested more than %d deep (in %s)',
    [JitMaxDepth, CS.Name]));
end;

{ The element count of an int range, as TInterpreter.MakeRange computes it;
  -1 after recording an error. }
function RtCountInt(A, H, B, Fid, Site: Int64): Int64; cdecl;
var
  Span: Int64;
begin
  if H = 0 then
  begin
    Pending(Fid, Site, ArgumentError, 'the step of a range cannot be zero');
    Exit(-1);
  end;
  if ((H > 0) and (B < A)) or ((H < 0) and (B > A)) then
    Exit(0);
  // CheckedSub's test, without raising.
  Span := B - A;
  if ((B xor A) and (B xor Span)) < 0 then
  begin
    Pending(Fid, Site, OverflowError, 'integer overflow in -');
    Exit(-1);
  end;
  Result := Span div H + 1;
end;

{ The element count of a real range, with MakeRange's expression. }
function RtCountReal(A, H, B: Double; Fid, Site: Int64): Int64; cdecl;
var
  N: Double;
begin
  try
    if H = 0 then
    begin
      Pending(Fid, Site, ArgumentError, 'the step of a range cannot be zero');
      Exit(-1);
    end;
    if IsNan(A) or IsNan(H) or IsNan(B) then
    begin
      Pending(Fid, Site, ArgumentError, 'range bounds and step cannot be NaN');
      Exit(-1);
    end;
    // Reference, "Ranges": the length is floor((b - a)/h + 1e-10) + 1.
    N := Floor((B - A) / H + 1e-10) + 1;
    if IsInfinite(N) or (N > 4.0e18) then
    begin
      Pending(Fid, Site, ArgumentError, 'range has too many elements');
      Exit(-1);
    end;
    if N < 0 then
      N := 0;
    Result := Trunc(N);
  except
    on E: Exception do
    begin
      Pending(Fid, Site, 'InternalError', E.Message);
      Result := -1;
    end;
  end;
end;

{ real ^ real, as RealArith: a negative base with a non-integer exponent is
  NaN, otherwise Power. }
function RtPowReal(X, Y: Double): Double; cdecl;
begin
  if (X < 0) and (Frac(Y) <> 0) then
    Result := NaN
  else
    Result := Power(X, Y);
end;

{ ---- array values in frame slots ---- }

{ Dst := Src, sharing the value (the reference count goes up). }
procedure RtAssign(Dst, Src: PAxValue); cdecl;
begin
  Dst^ := Src^;
end;

{ Dst := Src and Src := nothing: the reference moves, its count unchanged. }
procedure RtMove(Dst, Src: PAxValue); cdecl;
begin
  Dst^ := Src^;
  Src^ := Default(TAxValue);
end;

procedure RtClear(P: PAxValue); cdecl;
begin
  P^ := Default(TAxValue);
end;

{ Copy-on-write before a write, as AssignArraySlot: the array is copied
  when another value shares it. }
procedure RtMakeUnique(P: PAxValue); cdecl;
var
  A: TArrayObj;
begin
  A := AsArray(P^);
  if A.RefCount > 1 then
    P^ := ArrayValue(A.Clone);
end;

{ Releases a frame's N value slots when the function returns. }
procedure RtLeave(Frame: PAxValue; N: Int64); cdecl;
var
  K: Integer;
begin
  for K := 0 to N - 1 do
  begin
    Frame^ := Default(TAxValue);
    Inc(Frame);
  end;
end;

{ A vector or matrix literal: Rows×Cols entries in the argument slots, row
  by row, as reals (IsReal) or ints. A single column is a vector. }
procedure RtNewArray(Dst: PAxValue; Rows, Cols, IsReal: Int64; Args: PInt64); cdecl;
var
  A: TArrayObj;
  R, C: Integer;
  Slot: PInt64;
begin
  if IsReal <> 0 then
    A := TArrayObj.Create(etReal, Rows, Cols, Cols = 1)
  else
    A := TArrayObj.Create(etInt, Rows, Cols, Cols = 1);
  Dst^ := ArrayValue(A);
  for R := 0 to Rows - 1 do
    for C := 0 to Cols - 1 do
    begin
      Slot := PInt64(PByte(Args) + 8 * (R * Cols + C));
      if IsReal <> 0 then
        A.R[C * Rows + R] := PDouble(Slot)^
      else
        A.I[C * Rows + R] := Slot^;
    end;
end;

(* A record of shape T from its fields in the argument slots (bool, int and
   real as values, arrays and records by slot address), as EvalRecord builds
   a literal and CoerceRecord a declared record. For a constructor, Guard is
   the variable that held the record type when the code was compiled: it
   must hold it still. 0, or 1 after recording an error. *)
function RtNewRecord(Dst: PAxValue; T: Int64; Args: PInt64; Guard: PAxValue;
  Fid, Site: Int64): Int64; cdecl;
var
  Sh: TJShape;
  R: TRecordObj;
  V: TAxValue;
  K: Integer;
  Slot: PInt64;
begin
  try
    Sh := ShapeOf(TJType(T));
    if (Guard <> nil) and ((Guard^.Kind <> vkRecordType) or (AsRecordType(Guard^) <> Sh.Decl)) then
    begin
      Pending(Fid, Site, TypeError, Format('record type %s was redefined after this function ' +
        'was compiled', [Sh.Decl.Name]));
      Exit(1);
    end;
    R := TRecordObj.Create;
    V := NothingValue;
    V.Kind := vkRecord;
    V.Obj := R;
    R.Names := Sh.Names;
    if Sh.Decl <> nil then
    begin
      R.DeclType := Sh.Decl;
      R.DeclRef := Sh.DeclRef;
    end;
    SetLength(R.Values, Length(Sh.Names));
    for K := 0 to High(Sh.Names) do
    begin
      Slot := PInt64(PByte(Args) + 8 * K);
      case Sh.Types[K] of
        jtBool: R.Values[K] := BoolValue(Slot^ <> 0);
        jtInt:  R.Values[K] := IntValue(Slot^);
        jtReal: R.Values[K] := RealValue(PDouble(Slot)^);
      else
        R.Values[K] := PAxValue(PPointer(Slot)^)^;
      end;
    end;
    Dst^ := V;
    Result := 0;
  except
    on E: Exception do
    begin
      Pending(Fid, Site, '', '');
      PendExc := AcquireExceptionObject as Exception;
      Result := 1;
    end;
  end;
end;

{ Copy-on-write before a field write, as MakeUnique: the record is copied
  (one level) when another value shares it. }
procedure RtRecordUnique(P: PAxValue); cdecl;
begin
  MakeUnique(P^);
end;

{ A value of type T from an 8-byte argument slot: a number as itself, an
  array, record or list by the address of its slot. }
function BoxSlot(Slot: PInt64; T: TJType): TAxValue;
begin
  case T of
    jtBool: Result := BoolValue(Slot^ <> 0);
    jtInt:  Result := IntValue(Slot^);
    jtReal: Result := RealValue(PDouble(Slot)^);
  else
    Result := PAxValue(PPointer(Slot)^)^;
  end;
end;

{ A list literal (J10): N elements of type Elem in the argument slots. }
procedure RtNewList(Dst: PAxValue; Elem: Int64; Args: PInt64; N: Int64); cdecl;
var
  Items: TAxValues;
  K: Integer;
begin
  SetLength(Items, N);
  for K := 0 to N - 1 do
    Items[K] := BoxSlot(PInt64(PByte(Args) + 8 * K), TJType(Elem));
  Dst^ := ListValue(Items);
end;

{ append(src, x), x of type T in the argument slot, into Dst. With InPlace
  (l = append(l, x), Dst = Src), the list grows in place when nothing else
  holds it, as ExecAppendAssign's AppendInPlace does; otherwise a new list,
  as BAppend builds it. }
procedure RtListAppend(Dst, Src: PAxValue; Arg: PInt64; T, InPlace: Int64); cdecl;
var
  X: TAxValue;
  L: TListObj;
  N: Integer;
begin
  X := BoxSlot(Arg, TJType(T));
  L := AsList(Src^);
  if (InPlace <> 0) and (Dst = Src) and (L.RefCount = 1) then
  begin
    N := Length(L.Items);
    SetLength(L.Items, N + 1);
    L.Items[N] := X;
  end
  else
    Dst^ := ListValue(L.Items + [X]);
end;

{ Copy-on-write before an element write, as MakeUnique: a shared list is
  copied (one level). }
procedure RtListUnique(P: PAxValue); cdecl;
begin
  MakeUnique(P^);
end;

{ a + b of two strings (J11), as BinaryOp joins them. }
procedure RtStrConcat(Dst, A, B: PAxValue); cdecl;
begin
  Dst^ := StringValue(AsString(A^) + AsString(B^));
end;

{ -1, 0 or 1: a against b, as CompareOrder and ValuesEqual compare strings. }
function RtStrCmp(A, B: PAxValue): Int64; cdecl;
var
  C: Integer;
begin
  C := CompareStr(AsString(A^), AsString(B^));
  if C < 0 then Result := -1
  else if C > 0 then Result := 1
  else Result := 0;
end;

{ string(x) of an int or bool (IsBool <> 0), as BString: Display of the value. }
procedure RtStrOfInt(Dst: PAxValue; X, IsBool: Int64); cdecl;
begin
  if IsBool <> 0 then
    Dst^ := StringValue(Display(BoolValue(X <> 0)))
  else
    Dst^ := StringValue(Display(IntValue(X)));
end;

{ string(x) of a real, as BString. }
procedure RtStrOfReal(Dst: PAxValue; X: Double); cdecl;
begin
  Dst^ := StringValue(Display(RealValue(X)));
end;

{ length(s) of a string, as BLength: code points, a surrogate pair counted once. }
function RtStrLen(A: PAxValue): Int64; cdecl;
begin
  Result := StringLength(AsString(A^));
end;

{ A loop's outer variables (J12): read from, and written to, its out slots. }
function RtGetInt(P: PAxValue): Int64; cdecl;
begin
  if P^.Kind = vkBool then
    Result := Ord(P^.B)
  else
    Result := P^.I;
end;

function RtGetReal(P: PAxValue): Double; cdecl;
begin
  Result := P^.R;
end;

procedure RtSetInt(P: PAxValue; X: Int64); cdecl;
begin
  P^ := IntValue(X);
end;

procedure RtSetReal(P: PAxValue; X: Double); cdecl;
begin
  P^ := RealValue(X);
end;

procedure RtSetBool(P: PAxValue; X: Int64); cdecl;
begin
  P^ := BoolValue(X <> 0);
end;

procedure RtIndexError(Fid, Site, Index, Len: Int64); cdecl;
begin
  Pending(Fid, Site, IndexError, Format('index %d is out of bounds for a dimension of length %d',
    [Index, Len]));
end;

{ Whether R has the JIR type T. }
function HasType(const R: TAxValue; T: TJType): Boolean;
begin
  Result := JTypeMatches(R, T);
end;

{ A call through the interpreter: a built-in, a function that is not
  compiled, or a compiled one whose variable now holds something else. The
  arguments are boxed from their slots, the callee called as the
  interpreter calls it, and the result checked against the type the
  compiled caller uses. 0, or 1 after recording the error. }
function RtCall(CS: TJitCallSite; Fid, Site: Int64; Args, Res: PInt64): Int64; cdecl;
var
  Callee, R: TAxValue;
  Boxed: TAxValues;
  K: Integer;
  Slot: PInt64;
  Ok: Boolean;
begin
  try
    if CS.ValuePtr <> nil then
      Callee := CS.ValuePtr^
    else
      Callee := CS.Value;
    SetLength(Boxed, Length(CS.ArgTypes));
    for K := 0 to High(Boxed) do
    begin
      Slot := PInt64(PByte(Args) + 8 * K);
      case CS.ArgTypes[K] of
        jtBool:   Boxed[K] := BoolValue(Slot^ <> 0);
        jtInt:    Boxed[K] := IntValue(Slot^);
        jtReal:   Boxed[K] := RealValue(PDouble(Slot)^);
        jtString:
          if (K < Length(CS.IsLit)) and CS.IsLit[K] then
            Boxed[K] := StringValue(CS.Strings[K])
          else
            Boxed[K] := PAxValue(PPointer(Slot)^)^;    // a string register's slot
      else
        if IsBoxedType(CS.ArgTypes[K]) then
          Boxed[K] := PAxValue(PPointer(Slot)^)^     // an array or record: its slot
        else
          Boxed[K] := NothingValue;
      end;
    end;
    if CS.IsOp then
    begin
      if Length(Boxed) = 1 then
        R := UnaryOp(TTokenKind(CS.Op), Boxed[0])
      else
        R := BinaryOp(TTokenKind(CS.Op), Boxed[0], Boxed[1]);
    end
    else
      R := CallAxon(Callee, Boxed);
    if Length(CS.ResultTypes) > 1 then
      RaiseFmt(TypeError, '%s was rebound; a compiled caller cannot use its several results',
        [CS.Name]);
    if Length(CS.ResultTypes) = 1 then
    begin
      Ok := HasType(R, CS.ResultTypes[0]);
      if not Ok then
        RaiseFmt(TypeError, '%s returned %s where compiled code expects %s',
          [CS.Name, TypeName(R), JTypeName(CS.ResultTypes[0])]);
      case CS.ResultTypes[0] of
        jtBool: Res^ := Ord(R.B);
        jtInt:  Res^ := R.I;
        jtReal: PDouble(Res)^ := R.R;
      else
        if IsBoxedType(CS.ResultTypes[0]) then
          PAxValue(PPointer(Res)^)^ := R;
      end;
    end;
    Result := 0;
  except
    on E: Exception do
    begin
      Pending(Fid, Site, '', '');
      PendExc := AcquireExceptionObject as Exception;
      Result := 1;
    end;
  end;
end;

function JitHelpers: TJitHelpers;
begin
  Result.Error := @RtError;
  Result.CountInt := @RtCountInt;
  Result.CountReal := @RtCountReal;
  Result.PowReal := @RtPowReal;
  Result.Call := @RtCall;
  Result.Frame := @RtFrame;
  Result.Recursion := @RtRecursion;
  Result.Assign := @RtAssign;
  Result.Move := @RtMove;
  Result.Clear := @RtClear;
  Result.MakeUnique := @RtMakeUnique;
  Result.Leave := @RtLeave;
  Result.IndexError := @RtIndexError;
  Result.NewArray := @RtNewArray;
  Result.NewRecord := @RtNewRecord;
  Result.RecordUnique := @RtRecordUnique;
  Result.NewList := @RtNewList;
  Result.ListAppend := @RtListAppend;
  Result.ListUnique := @RtListUnique;
  Result.StrConcat := @RtStrConcat;
  Result.StrCmp := @RtStrCmp;
  Result.StrOfInt := @RtStrOfInt;
  Result.StrOfReal := @RtStrOfReal;
  Result.StrLen := @RtStrLen;
  Result.GetInt := @RtGetInt;
  Result.GetReal := @RtGetReal;
  Result.SetInt := @RtSetInt;
  Result.SetReal := @RtSetReal;
  Result.SetBool := @RtSetBool;
end;

{ ---- compiling ---- }

{ With AXON_JIT_LOG set to a file, each decision is appended to it:
  "compiled name" or "rejected name: reason (line:col)", the latter followed
  by a tab and the file, so the IDE can point at the place. It shows which functions a
  program or test run actually compiled. With AXON_JIT_REPORT set, each
  decision is also written to stderr as a line #3"jit compiled name" or
  #3"jit rejected name: reason", which the IDE turns into a report. }
procedure LogDecision(const Line: string);
var
  Path: string;
  F: TextFile;
begin
  if GetEnvironmentVariable('AXON_JIT_REPORT') <> '' then
  begin
    Writeln(ErrOutput, #3'jit ' + Line);
    Flush(ErrOutput);
  end;
  Path := GetEnvironmentVariable('AXON_JIT_LOG');
  if Path = '' then
    Exit;
  try
    AssignFile(F, Path);
    if FileExists(Path) then Append(F) else Rewrite(F);
    try
      Writeln(F, Line);
    finally
      CloseFile(F);
    end;
  except
    // The log is a diagnostic; never let it break a run.
  end;
end;

function DisplayName(E: TJEntry): string; forward;

{ Generates every function the session has lowered and not yet generated,
  and links them together. }
procedure GenerateGroup;
var
  Group: TList<TJEntry>;
  E: TJEntry;
  Code: TJitCode;
  Insn: TJInsn;
  Entries: TArray<TMirItem>;
  K, P: Integer;
begin
  Group := TList<TJEntry>.Create;
  try
    for E in Session.Order do
      if (E.State = esLowered) and (E.Code = nil) then
        Group.Add(E);
    // Codes first, so calls within the group know their callees' ids.
    for E in Group do
    begin
      Code := TJitCode.Create;
      Code.Id := Codes.Add(Code);
      Code.Name := E.Func.Name;
      Code.FileName := E.FileName;
      Code.ResultTypes := E.Func.ResultTypes.ToArray;
      Code.Sites := E.Func.Sites.ToArray;
      Code.Captures := E.Func.Captures.ToArray;
      Code.LocalNames := E.Func.LocalNames.ToArray;
      Code.NParams := E.Func.Params.Count - E.Func.Captures.Count;
      Code.Outers := E.Func.Outers.ToArray;
      SetLength(Code.ParamTypes, E.Func.Params.Count);
      for P := 0 to E.Func.Params.Count - 1 do
        Code.ParamTypes[P] := E.Func.Regs[E.Func.Params[P]].Typ;
      E.Code := Code;
    end;
    for E in Group do
      for Insn in E.Func.Insns do
        if (Insn.Op = joCall) and (Insn.Target.Kind = ckCompiled) then
          Insn.Target.CalleeId := TJitCode(TJEntry(Insn.Target.Callee).Code).Id;
    SetLength(Entries, Group.Count);
    for K := 0 to Group.Count - 1 do
      Entries[K] := GenerateModule(Group[K].Func, TJitCode(Group[K].Code));
    LinkModules;
    for K := 0 to Group.Count - 1 do
    begin
      @TJitCode(Group[K].Code).Entry := MirFunctionAddress(Entries[K]);
      LogDecision('compiled ' + DisplayName(Group[K]));
    end;
  finally
    Group.Free;
  end;
end;

{ Any compiled code of the function, for any argument types. }
function JitCodeOf(Decl: TFunctionDecl): TJitCode;
var
  E: TJEntry;
begin
  for E in Session.Order do
    if (E.Decl = Decl) and (E.Code <> nil) then
      Exit(TJitCode(E.Code));
  Result := nil;
end;

function JitTypeOf(const V: TAxValue): TJType;
begin
  Result := JTypeOfValue(V);
end;

{ The name in logs and reports: with its parameter types when they come
  from the arguments. }
function DisplayName(E: TJEntry): string;
var
  K: Integer;
begin
  if E.IsLoop then
    Exit(Format('loop at %d:%d', [E.Decl.Line, E.Decl.Col]));
  if E.Decl.Name = '' then
    Result := Format('anonymous function at %d:%d', [E.Decl.Line, E.Decl.Col])
  else
    Result := E.Decl.Name;
  if IsSpecialised(E.Decl) then
  begin
    Result := Result + '(';
    for K := 0 to High(E.ParamTypes) do
    begin
      if K > 0 then
        Result := Result + ', ';
      Result := Result + ShortTypeName(E.ParamTypes[K]);
    end;
    Result := Result + ')';
  end;
end;

function JitCompile(Decl: TFunctionDecl; FuncObj: TObject; const FileName: string;
  const ArgTypes: TArray<TJType>; IsClosure: Boolean; out Reason: string;
  const ArgValues: TAxValues): TJitCode;
var
  E: TJEntry;
  Types: TArray<TJType>;
begin
  Result := nil;
  if not MirAvailable then
  begin
    Reason := 'the JIT is unavailable: ' + MirError;
    Exit;
  end;
  // The values, when given, let a rejection say what was passed.
  if not SignatureFor(Decl, ArgTypes, Types, Reason, ArgValues) then
  begin
    LogDecision(Format('rejected %s: %s'#9'%s', [Decl.Name, Reason, FileName]));
    Exit;
  end;
  E := Session.Lower(Decl, FuncObj, FileName, Types, IsClosure);
  if E.State <> esLowered then
  begin
    Reason := Format('%s (%d:%d)', [E.Reason, E.RejectLine, E.RejectCol]);
    LogDecision(Format('rejected %s: %s'#9'%s', [DisplayName(E), Reason, FileName]));
    Exit;
  end;
  if E.Code = nil then
    GenerateGroup;
  Result := TJitCode(E.Code);
end;

function JitCompileLoop(Decl: TFunctionDecl; FuncObj: TObject; const FileName, Key: string;
  const Outer: TJOuterLookup; out Reason: string): TJitCode;
var
  E: TJEntry;
begin
  Result := nil;
  if not MirAvailable then
  begin
    Reason := 'the JIT is unavailable: ' + MirError;
    Exit;
  end;
  E := Session.LowerLoop(Decl, FuncObj, FileName, Key, Outer);
  if E.State <> esLowered then
  begin
    Reason := Format('%s (%d:%d)', [E.Reason, E.RejectLine, E.RejectCol]);
    LogDecision(Format('rejected %s: %s'#9'%s', [DisplayName(E), Reason, FileName]));
    Exit;
  end;
  if E.Code = nil then
    GenerateGroup;
  Result := TJitCode(E.Code);
end;

initialization
  Codes := TObjectList<TJitCode>.Create(True);
  Session := TJSession.Create(nil);
  PendFrames := TList<TJitFrame>.Create;

finalization
  PendFrames.Free;
  Session.Free;
  Codes.Free;

end.
