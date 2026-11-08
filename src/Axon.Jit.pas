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
    constructor Create;
    destructor Destroy; override;
  end;

  { What RtCall needs to call a callee through the interpreter. }
  TJitCallSite = class
  public
    Name: string;
    Value: TAxValue;              // the callee, when nothing can rebind it
    ValuePtr: PAxValue;           // else the variable holding it
    ArgTypes: TArray<TJType>;
    Strings: TArray<string>;      // string literal arguments, by position
    ResultTypes: TArray<TJType>;  // the values the caller uses
  end;

  { Addresses of the helpers, for the code generator. }
  TJitHelpers = record
    Error, CountInt, CountReal, PowReal, Call, Frame, Recursion: Pointer;
  end;

var
  JitMode: TJitMode = jmOff;
  JitDepth: PInteger;           // the interpreter's call depth
  JitMaxDepth: Integer = 10000;

{ Sets the mode from a name: off, on or force. False for another name. }
function SetJitMode(const Name: string): Boolean;
function JitModeName: string;

{ Called by the interpreter: how calls resolve, and its call-depth counter. }
procedure JitSetup(const Resolver: TJResolver; DepthPtr: PInteger; MaxDepth: Integer);

{ Compiles a function (FuncObj is its TFunctionObj), or returns nil, with
  the reason, when it is rejected or MIR is unavailable. }
function JitCompile(Decl: TFunctionDecl; FuncObj: TObject; const FileName: string;
  out Reason: string): TJitCode;

{ The compiled code of a function, or nil: also for a function compiled
  only as a callee, which the interpreter has not called yet. }
function JitCodeOf(Decl: TFunctionDecl): TJitCode;

{ The error compiled code reported, as the exception to raise. }
function TakeJitError: Exception;

function JitHelpers: TJitHelpers;

implementation

uses
  System.Math,
  Axon.Errors, Axon.Ops, Axon.NativeModules, Axon.Jit.Mir, Axon.Native.Mir;

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
end;

destructor TJitCode.Destroy;
begin
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
        jtString: Boxed[K] := StringValue(CS.Strings[K]);
      else
        Boxed[K] := NothingValue;
      end;
    end;
    R := CallAxon(Callee, Boxed);
    if Length(CS.ResultTypes) > 1 then
      RaiseFmt(TypeError, '%s was rebound; a compiled caller cannot use its several results',
        [CS.Name]);
    if Length(CS.ResultTypes) = 1 then
    begin
      case CS.ResultTypes[0] of
        jtBool: Ok := R.Kind = vkBool;
        jtInt:  Ok := R.Kind = vkInt;
        jtReal: Ok := R.Kind = vkReal;
      else
        Ok := False;
      end;
      if not Ok then
        RaiseFmt(TypeError, '%s returned %s where compiled code expects %s',
          [CS.Name, TypeName(R), JTypeName(CS.ResultTypes[0])]);
      case CS.ResultTypes[0] of
        jtBool: Res^ := Ord(R.B);
        jtInt:  Res^ := R.I;
        jtReal: PDouble(Res)^ := R.R;
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
end;

{ ---- compiling ---- }

{ With AXON_JIT_LOG set to a file, each decision is appended to it:
  "compiled name" or "rejected name: reason". It shows which functions a
  program or test run actually compiled. }
procedure LogDecision(const Line: string);
var
  Path: string;
  F: TextFile;
begin
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
    for E in Session.Entries.Values do
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
      LogDecision('compiled ' + Group[K].Decl.Name);
    end;
  finally
    Group.Free;
  end;
end;

function JitCodeOf(Decl: TFunctionDecl): TJitCode;
var
  E: TJEntry;
begin
  if Session.Entries.TryGetValue(Decl, E) then
    Result := TJitCode(E.Code)
  else
    Result := nil;
end;

function JitCompile(Decl: TFunctionDecl; FuncObj: TObject; const FileName: string;
  out Reason: string): TJitCode;
var
  E: TJEntry;
begin
  Result := nil;
  if not MirAvailable then
  begin
    Reason := 'the JIT is unavailable: ' + MirError;
    Exit;
  end;
  E := Session.Lower(Decl, FuncObj, FileName);
  if E.State <> esLowered then
  begin
    Reason := Format('%s (%d:%d)', [E.Reason, E.RejectLine, E.RejectCol]);
    LogDecision(Format('rejected %s: %s', [Decl.Name, Reason]));
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
