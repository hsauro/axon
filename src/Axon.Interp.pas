unit Axon.Interp;

(* Tree-walking evaluator.

   Scopes (reference, "Scopes" and "Closures"). Every scope is reference
   counted, because a closure keeps the scope it was created in alive after
   the block that made it has finished. Scope kinds:

     rkModule         the top level of a script or module
     rkNamedFunction  the body of a named top-level function (rule 6)
     rkClosure        the body of a lambda or a nested named function
     rkNone           the body of an if, while, for (per iteration) or try

   Reads walk the whole chain up to the prelude. A plain assignment updates
   the nearest existing variable; the search passes through closure roots into
   the enclosing scopes but stops at a module root or a named-function root
   (rule 6). If nothing is found the variable is created in the first function
   root met, which is the current function's outermost scope.

   Variables are cells holding the value, the type annotation (if any) and a
   `global` marker. A cell marked global redirects reads and writes to the
   module's variable of the same name. *)

interface

uses
  System.SysUtils, System.Generics.Collections,
  Axon.Ast, Axon.Values, Axon.Ffi, Axon.Jit.Ir;

type
  { A construct that a later milestone implements. }
  ENotImplemented = class(Exception)
  public
    Milestone: string;
    FileName: string;
    Line, Col: Integer;
  end;

  TRootKind = (rkNone, rkModule, rkNamedFunction, rkClosure);

  TVarCell = class
  public
    Value: TAxValue;
    TypeRef: TTypeRef;        // annotation (owned by the AST); nil if untyped
    IsGlobalAlias: Boolean;   // declared `global` inside a function
    ReadOnly: Boolean;        // an imported name
  end;

  TScope = class
  private
    FRefCount: Integer;
    FVars: TObjectDictionary<string, TVarCell>;   // created on first use
  public
    CTypes: TCTypeAliases;    // named C types from extern blocks (module roots)
    Parent: TScope;
    Root: TRootKind;
    Module: TScope;           // the module root this scope belongs to
    constructor Create(AParent: TScope; ARoot: TRootKind);
    destructor Destroy; override;
    procedure AddRef; inline;
    procedure Release;
    function Find(const Name: string): TVarCell; inline;
    function VarCount: Integer;           // grows only: a name, once defined, stays
    function Define(const Name: string): TVarCell;
  end;

  { A function written in Axon: its declaration and the scope it closes over. }
  TFunctionObj = class(TCallableObj)
  public
    Decl: TFunctionDecl;
    Closure: TScope;
    IsClosure: Boolean;       // lambda or nested function: rule 5 reaches outward
    FileName: string;         // the module file it was defined in (for errors)
    FilePath: string;         // its full path (for imports made while it runs)
    // The JIT (Axon.Jit): compiled at the first call with each set of
    // argument types, when the mode is on. The codes are TJitCode, owned by
    // the JIT's registry; nil for a set that is not compiled.
    JitCodes: TDictionary<string, TObject>;
    JitLastTypes: TArray<TJType>;   // the last set of argument types, and its code
    JitLastCode: TObject;
    JitHaveLast: Boolean;
    JitReason: string;        // why it was not compiled
    HasKeywordParams: Boolean;
    // The cells the captured values of JitCapFor (a TJitCode) were found in,
    // valid while no scope of the defining chain has gained a name.
    JitCapFor: TObject;
    JitCapCells: TArray<TVarCell>;
    JitCapScopes: TArray<TScope>;
    JitCapCounts: TArray<Integer>;
    constructor Create(ADecl: TFunctionDecl; AClosure: TScope; AIsClosure: Boolean);
    destructor Destroy; override;
  end;

  { A module loaded from a file, or a namespace made by import a.b.c. Globals
    is nil for a namespace. }
  TModuleObj = class(TModuleBase)
  public
    FilePath: string;
    Globals: TScope;
    ExportNames: TList<string>;
    Children: TDictionary<string, TAxValue>;
    Loading: Boolean;
    Doc: TArray<string>;      // the module docstring (help)
    constructor Create(const AName: string);
    destructor Destroy; override;
  end;

  TSignal = (sigNone, sigBreak, sigContinue, sigReturn);

  { The elements an index list selects. A single index gives Lin (linear
    positions); two give RowPos and ColPos. A scalar index drops its
    dimension. }
  TSelection = record
    Two: Boolean;
    Lin, RowPos, ColPos: TArray<Integer>;
    ScalarA, ScalarB: Boolean;
  end;

  TInterpreter = class
  private
    FPrelude: TScope;
    FGlobals: TScope;
    FFile: string;
    FCurrentPath: string;                     // full path of the running module's file
    FModules: TDictionary<string, TAxValue>;  // file key -> loaded module
    FLoadStack: TList<string>;                // modules being loaded, for cycle reports
    FPrograms: TObjectList<TProgram>;         // syntax trees of imported modules
    FCallDepth: Integer;
    FReturn: TAxValues;                       // values of the last `return`
    FHoisted: TDictionary<TFunctionDecl, Boolean>;
    FHoistedRecords: TDictionary<TRecordStmt, Boolean>;
    FHoistedExterns: TDictionary<TExternStmt, Boolean>;
    FEndStack: TList<Int64>;                  // values of `end` in nested indexing
    procedure NotYet(const What, Milestone: string; Node: TNode);
    function ParseFunction(const Args: TAxValues): TAxValue;
    function FunctionValue(Decl: TFunctionDecl; Scope: TScope; IsClosure: Boolean): TAxValue;
    function FunctionRootOf(Scope: TScope): TScope;
    function Lookup(const Name: string; Scope: TScope; Node: TNode): TAxValue;
    procedure Assign(const Name: string; const V: TAxValue; Scope: TScope);
    procedure Store(Cell: TVarCell; const V: TAxValue; const Name: string; Scope: TScope);
    procedure CheckCondition(const V: TAxValue; const Construct: string);
    function ExecBody(Stmts: TStmtList; Scope: TScope): TSignal;
    function ExecBlock(Stmts: TStmtList; Parent: TScope): TSignal;
    function ExecStmt(S: TStmt; Scope: TScope): TSignal;
    function ExecFor(S: TForStmt; Scope: TScope): TSignal;
    procedure ExecDecl(S: TDeclStmt; Scope: TScope);
    procedure ExecDestructure(S: TDestructureStmt; Scope: TScope);
    function ExecTry(S: TTryStmt; Scope: TScope): TSignal;
    function EvalField(E: TFieldExpr; Scope: TScope): TAxValue;
    function EvalIndex(E: TIndexExpr; Scope: TScope): TAxValue;
    function EvalMatrix(E: TMatrixExpr; Scope: TScope): TAxValue;
    procedure EvalIndexItem(Item: TExpr; Len: Integer; Scope: TScope;
      out Positions: TArray<Integer>; out Scalar: Boolean);
    function ResolveSelection(Rows, Cols: Integer; IsVector: Boolean;
      E: TIndexExpr; Scope: TScope): TSelection;
    function IndexList(const T: TAxValue; E: TIndexExpr; Scope: TScope): TAxValue;
    function FindCellForWrite(const Name: string; Scope: TScope): TVarCell;
    procedure AssignArraySlot(var Slot: TAxValue; Target: TIndexExpr; const V: TAxValue;
      TypeRef: TTypeRef; const Name: string; Scope: TScope);
    procedure SetIn(var Slot: TAxValue; const Steps: TArray<TExpr>; I: Integer;
      const V: TAxValue; RootCell: TVarCell; const Name: string; Scope: TScope);
    procedure AssignPath(Target: TExpr; const V: TAxValue; Scope: TScope);
    function Coerce(const V: TAxValue; T: TTypeRef; const What: string; Scope: TScope): TAxValue;
    function CoerceRecord(const V, RTValue: TAxValue; const What: string; Scope: TScope): TAxValue;
    function RecordTypeValue(S: TRecordStmt): TAxValue;
    function ConstructRecord(const RTValue: TAxValue; E: TCallExpr; Scope: TScope): TAxValue;
    function BuildDict(E: TCallExpr; Scope: TScope): TAxValue;
    function EvalList(E: TListExpr; Scope: TScope): TAxValue;
    function EvalRecord(E: TRecordExpr; Scope: TScope): TAxValue;
    function IndexString(const T: TAxValue; E: TIndexExpr; Scope: TScope): TAxValue;
    function IndexDict(const T: TAxValue; E: TIndexExpr; Scope: TScope): TAxValue;
    function IndexSparse(const T: TAxValue; E: TIndexExpr; Scope: TScope): TAxValue;
    procedure AssignSparseSlot(var Slot: TAxValue; Target: TIndexExpr; const V: TAxValue;
      Scope: TScope);
    function ResolveModule(const Name: string): string;
    function LoadModule(const Name: string; Node: TNode): TAxValue;
    procedure ExecImport(S: TImportStmt; Scope: TScope);
    function ModuleMember(const V: TAxValue; E: TFieldExpr): TAxValue;
    function NativeLibraryHook(E: TCallExpr; Scope: TScope): TAxValue;
    procedure ExecExtern(S: TExternStmt; Scope: TScope);
    function CallExternValue(F: TExternFuncObj; E: TCallExpr; Scope: TScope): TAxValue;
  public
    { Calls any function value with positional arguments (used for callbacks). }
    function CallValue(const Fn: TAxValue; const Args: TAxValues): TAxValue;
    function RunCompiled(Code: TObject; const Args, Caps: TAxValues): TAxValues;
    function FastCall(F: TFunctionObj; const Pos: TAxValues; out Res: TAxValues): Boolean;
    function InvokeSlow(F: TFunctionObj; const Pos: TAxValues;
      const KwNames: TArray<string>; const KwValues: TAxValues): TAxValues;
    function CompiledFor(F: TFunctionObj; const Args: TAxValues): TObject;
    function CapturesFor(F: TFunctionObj; Code: TObject; out Caps: TAxValues): Boolean;
  private
    function MakeRange(E: TRangeExpr; Scope: TScope): TAxValue;
    function EvalLogical(E: TBinaryExpr; Scope: TScope): TAxValue;
    function EvalMulti(E: TExpr; Scope: TScope): TAxValues;
    function EvalCallMulti(E: TCallExpr; Scope: TScope): TAxValues;
    function CallBuiltin(B: TBuiltinObj; E: TCallExpr; Scope: TScope): TAxValues;
    function Invoke(F: TFunctionObj; const Pos: TAxValues;
      const KwNames: TArray<string>; const KwValues: TAxValues): TAxValues;
  public
    constructor Create(const FileName: string);
    destructor Destroy; override;
    function Eval(E: TExpr; Scope: TScope): TAxValue;
    { Binds a program's top-level named functions, so they can be called
      before their definition. Run does this itself. }
    procedure Hoist(P: TProgram); overload;
    procedure Hoist(P: TProgram; Globals: TScope); overload;
    procedure Run(P: TProgram);
    { Runs a parsed file in this session's global scope, as a program runs
      (nothing is displayed), for the REPL's run command. Its definitions
      stay; errors and the functions it defines name FileName, and its
      imports resolve from that file's folder. }
    procedure RunInSession(P: TProgram; const FileName: string);
    { Runs one top-level statement (the REPL). Shown receives the values to
      display: an expression's values, or the new value of an assigned name
      (then ShownName is that name). }
    function ExecTopLevel(S: TStmt; out Shown: TAxValues; out ShownNames: TArray<string>): Boolean;
  end;

const
  MaxCallDepth = 10000;

{ Checks V against an annotation and widens it along bool -> int -> real ->
  complex. Raises TypeError naming What (for example 'argument "x" of f'). }
function CoerceToType(const V: TAxValue; T: TTypeRef; const What: string): TAxValue;

implementation

uses
  System.Math, System.Character, System.IOUtils,
  Axon.Packages, Axon.Source, Axon.Lexer, Axon.Parser,
  Axon.Sparse, Axon.NativeModules,
  Axon.Errors, Axon.Tokens, Axon.Ops, Axon.Builtins, Axon.Complex, Axon.Arrays,
  Axon.Jit, Axon.Jit.Lower;

function StringChars(const S: string): TArray<string>; forward;
function BJitCompiled(const Args: TAxValues): TAxValue; forward;
function BJitReason(const Args: TAxValues): TAxValue; forward;
function BJitMode(const Args: TAxValues): TAxValue; forward;
function BParseFunction(const Args: TAxValues): TAxValue; forward;

var
  // The interpreter of this process, for built-ins that need it
  // (parse_function); set when it is created.
  GInterp: TInterpreter;

{ ===================== type annotations ===================== }

function ValueKindOfName(const N: string): TValueKind;
begin
  if N = 'list' then Result := vkList else Result := vkRecord;
end;

(* matrix{T} / vector{T}: the elements must be T or widen to it. Widening
   makes a converted copy; the original array is never changed. *)
function CoerceElements(const V: TAxValue; T: TTypeRef; const What: string): TAxValue;
var
  Want: TElemType;
  A, W: TArrayObj;
  P: string;
begin
  P := T.Param.Name;
  if P = 'bool' then Want := etBool
  else if P = 'int' then Want := etInt
  else if P = 'real' then Want := etReal
  else if P = 'complex' then Want := etComplex
  else
  begin
    RaiseFmt(TypeError, 'the element type of %s must be bool, int, real or complex', [T.ToString]);
    Want := etReal;
  end;
  A := AsArray(V);
  if A.ElemType = Want then
    Exit(V);
  if A.ElemType > Want then
    RaiseFmt(TypeError, '%s must be %s, got %s{%s}',
      [What, T.ToString, TypeName(V), ElemTypeName(A.ElemType)]);
  W := A.Clone;
  Result := ArrayValue(W);
  W.Widen(Want);
end;

function CoerceToType(const V: TAxValue; T: TTypeRef; const What: string): TAxValue;
var
  Ok: Boolean;
  N: string;
begin
  N := T.Name;
  if (T.Param <> nil) and not ((N = 'vector') or (N = 'matrix') or (N = 'sparse')) then
    RaiseFmt(TypeError, 'type %s takes no parameter', [N]);
  Result := V;
  Ok := False;
  if N = 'bool' then
    Ok := V.Kind = vkBool
  else if N = 'int' then
  begin
    Ok := V.Kind in [vkBool, vkInt];
    if Ok and (V.Kind = vkBool) then
      Result := IntValue(Ord(V.B));
  end
  else if N = 'real' then
  begin
    Ok := V.Kind in [vkBool, vkInt, vkReal];
    if Ok then
      Result := RealValue(ToReal(V));
  end
  else if N = 'complex' then
  begin
    Ok := NumRank(V) >= 0;
    if Ok then
      Result := ComplexValue(ToComplex(V));
  end
  else if N = 'string' then
    Ok := V.Kind = vkString
  else if N = 'nothing' then
    Ok := V.Kind = vkNothing
  else if N = 'range' then
    Ok := V.Kind = vkRange
  else if N = 'function' then
    Ok := V.Kind in [vkBuiltin, vkFunction, vkExtern]
  else if N = 'pointer' then
    Ok := V.Kind = vkPointer
  else if (N = 'vector') or (N = 'matrix') then
  begin
    // A range is accepted where a vector is annotated, and becomes one.
    if (N = 'vector') and (V.Kind = vkRange) then
      Result := ArrayValue(RangeToArray(AsRange(V)));
    Ok := (Result.Kind = vkArray) and (AsArray(Result).IsVector = (N = 'vector'));
    if Ok and (T.Param <> nil) then
      Result := CoerceElements(Result, T, What);
  end
  else if (N = 'list') or (N = 'record') then
    Ok := V.Kind = ValueKindOfName(N)
  else if N = 'sparse' then
  begin
    Ok := V.Kind = vkSparse;
    if Ok and (T.Param <> nil) then
    begin
      if T.Param.Name = 'complex' then
      begin
        if not AsSparse(V).IsComplex then
        begin
          Result := SparseValue(AsSparse(V).Clone);
          AsSparse(Result).IsComplex := True;
        end;
      end
      else if T.Param.Name = 'real' then
        Ok := not AsSparse(V).IsComplex
      else
        RaiseFmt(TypeError, 'the element type of %s must be real or complex', [T.ToString]);
    end;
  end
  else if N = 'dict' then
    Ok := V.Kind = vkDict
  else
    RaiseFmt(TypeError, 'unknown type "%s"', [T.ToString]);
  if not Ok then
    RaiseFmt(TypeError, '%s must be %s, got %s', [What, T.ToString, TypeName(V)]);
end;

{ ===================== TScope ===================== }

constructor TScope.Create(AParent: TScope; ARoot: TRootKind);
begin
  inherited Create;
  FRefCount := 1;
  Parent := AParent;
  Root := ARoot;
  if Parent <> nil then
    Parent.AddRef;
  if Root = rkModule then
    Module := Self
  else if Parent <> nil then
    Module := Parent.Module;
end;

destructor TScope.Destroy;
begin
  FVars.Free;
  CTypes.Free;
  if Parent <> nil then
    Parent.Release;
  inherited;
end;

procedure TScope.AddRef;
begin
  Inc(FRefCount);
end;

procedure TScope.Release;
begin
  Dec(FRefCount);
  if FRefCount = 0 then
    Free;
end;

function TScope.Find(const Name: string): TVarCell;
begin
  if (FVars = nil) or not FVars.TryGetValue(Name, Result) then
    Result := nil;
end;

function TScope.VarCount: Integer;
begin
  if FVars = nil then
    Result := 0
  else
    Result := FVars.Count;
end;

function TScope.Define(const Name: string): TVarCell;
begin
  if FVars = nil then
    FVars := TObjectDictionary<string, TVarCell>.Create([doOwnsValues]);
  if not FVars.TryGetValue(Name, Result) then
  begin
    Result := TVarCell.Create;
    Result.Value := NothingValue;
    FVars.Add(Name, Result);
  end;
end;

{ ===================== TFunctionObj ===================== }

constructor TFunctionObj.Create(ADecl: TFunctionDecl; AClosure: TScope; AIsClosure: Boolean);
begin
  inherited Create;
  Decl := ADecl;
  Name := ADecl.Name;
  Closure := AClosure;
  Closure.AddRef;
  IsClosure := AIsClosure;
  for var P in ADecl.Params do
    if P.IsKeyword then
      HasKeywordParams := True;
end;

destructor TFunctionObj.Destroy;
begin
  JitCodes.Free;
  Closure.Release;
  inherited;
end;

{ ===================== TInterpreter ===================== }

constructor TInterpreter.Create(const FileName: string);
var
  Prelude: TScope;
begin
  inherited Create;
  FFile := FileName;
  FPrelude := TScope.Create(nil, rkNone);
  Prelude := FPrelude;
  DefineBuiltins(
    procedure(Name: string; V: TAxValue)
    begin
      Prelude.Define(Name).Value := V;
    end);
  Prelude.Define('__jit_compiled').Value := BuiltinValue('__jit_compiled', BJitCompiled, 1, 1);
  Prelude.Define('__jit_reason').Value := BuiltinValue('__jit_reason', BJitReason, 1, 1);
  Prelude.Define('__jit_mode').Value := BuiltinValue('__jit_mode', BJitMode, 0, 1);
  Prelude.Define('parse_function').Value := BuiltinValue('parse_function', BParseFunction, 1, 2);
  GInterp := Self;
  FGlobals := TScope.Create(FPrelude, rkModule);
  FHoisted := TDictionary<TFunctionDecl, Boolean>.Create;
  FHoistedRecords := TDictionary<TRecordStmt, Boolean>.Create;
  FHoistedExterns := TDictionary<TExternStmt, Boolean>.Create;
  FEndStack := TList<Int64>.Create;
  // A pseudo-file such as <repl> stands for the working directory, so that
  // imports made at the REPL resolve from there.
  if FileName.StartsWith('<') then
    FCurrentPath := IncludeTrailingPathDelimiter(GetCurrentDir) + FileName
  else
    FCurrentPath := TPath.GetFullPath(FileName);
  FModules := TDictionary<string, TAxValue>.Create;
  FLoadStack := TList<string>.Create;
  FPrograms := TObjectList<TProgram>.Create;
  // Native modules call functions through the latest interpreter.
  CallAxon :=
    function(const Fn: TAxValue; const Args: TAxValues): TAxValue
    begin
      Result := CallValue(Fn, Args);
    end;
  // The JIT resolves a called name as a call in a top-level function would:
  // through the function's defining scope, up to the prelude.
  JitSetup(
    function(Context: TObject; const Name: string): TJResolved
    var
      S: TScope;
      Cell: TVarCell;
      V: TAxValue;
      Fo: TFunctionObj;
    begin
      Result := Default(TJResolved);
      if Context = nil then
        Exit;
      S := TFunctionObj(Context).Closure;
      Cell := nil;
      while (S <> nil) and (Cell = nil) do
      begin
        Cell := S.Find(Name);
        S := S.Parent;
      end;
      if Cell = nil then
        Exit;
      V := Cell.Value;
      Result.Value := V;
      Result.ValuePtr := @Cell.Value;
      case V.Kind of
        vkFunction:
          begin
            Fo := TFunctionObj(V.Obj);
            Result.Kind := rkFunction;
            Result.Decl := Fo.Decl;
            Result.FuncObj := Fo;
            Result.FileName := Fo.FileName;
            Result.IsClosure := Fo.IsClosure;
          end;
        vkBuiltin:
          begin
            Result.Kind := rkBuiltin;
            Result.Name := AsBuiltin(V).Name;
          end;
      else
        Result.Kind := rkOther;
      end;
    end, @FCallDepth, MaxCallDepth);
end;

destructor TInterpreter.Destroy;
begin
  ClearAtExit;
  CallAxon := nil;
  FHoisted.Free;
  FHoistedRecords.Free;
  FHoistedExterns.Free;
  FEndStack.Free;
  FModules.Free;
  FLoadStack.Free;
  // Functions stored in the globals refer back to them, so the globals may
  // stay alive in a cycle; that memory goes when the process ends.
  FGlobals.Release;
  FPrelude.Release;
  FPrograms.Free;
  inherited;
end;

procedure TInterpreter.NotYet(const What, Milestone: string; Node: TNode);
var
  E: ENotImplemented;
begin
  E := ENotImplemented.CreateFmt('%s is not implemented yet (arrives in %s)',
    [What, Milestone]);
  E.Milestone := Milestone;
  E.FileName := FFile;
  if Node <> nil then
  begin
    E.Line := Node.Line;
    E.Col := Node.Col;
  end;
  raise E;
end;

function TInterpreter.FunctionValue(Decl: TFunctionDecl; Scope: TScope;
  IsClosure: Boolean): TAxValue;
var
  F: TFunctionObj;
begin
  Result := NothingValue;
  Result.Kind := vkFunction;
  F := TFunctionObj.Create(Decl, Scope, IsClosure);
  F.FileName := FFile;
  F.FilePath := FCurrentPath;
  Result.Obj := F;
end;

{ The outermost scope of the function (or module) that Scope is in. }
function TInterpreter.FunctionRootOf(Scope: TScope): TScope;
begin
  Result := Scope;
  while Result.Root = rkNone do
    Result := Result.Parent;
end;

function TInterpreter.Lookup(const Name: string; Scope: TScope; Node: TNode): TAxValue;
var
  S: TScope;
  C: TVarCell;
begin
  S := Scope;
  while S <> nil do
  begin
    C := S.Find(Name);
    if C <> nil then
    begin
      if C.IsGlobalAlias then
      begin
        C := S.Module.Find(Name);
        if C = nil then
          Break;
      end;
      Exit(C.Value);
    end;
    S := S.Parent;
  end;
  raise EAxonError.CreateAt(NameError, Format('"%s" is not defined', [Name]),
    FFile, Node.Line, Node.Col);
end;

procedure TInterpreter.Store(Cell: TVarCell; const V: TAxValue; const Name: string; Scope: TScope);
begin
  if Cell.ReadOnly then
    RaiseFmt(NameError, '"%s" is imported and cannot be assigned', [Name]);
  if Cell.TypeRef <> nil then
    Cell.Value := Coerce(V, Cell.TypeRef, Format('variable "%s"', [Name]), Scope)
  else
    Cell.Value := V;
end;

procedure TInterpreter.Assign(const Name: string; const V: TAxValue; Scope: TScope);
var
  S, FirstRoot: TScope;
  C: TVarCell;
begin
  S := Scope;
  FirstRoot := nil;
  while S <> nil do
  begin
    C := S.Find(Name);
    if C <> nil then
    begin
      if C.IsGlobalAlias then
        C := S.Module.Define(Name);
      Store(C, V, Name, Scope);
      Exit;
    end;
    if S.Root <> rkNone then
    begin
      if FirstRoot = nil then
        FirstRoot := S;
      // Rule 6: the search stops at a module or named-function root; it
      // continues through a closure root into the enclosing scopes.
      if S.Root in [rkModule, rkNamedFunction] then
        Break;
    end;
    S := S.Parent;
  end;
  Store(FirstRoot.Define(Name), V, Name, Scope);
end;

procedure TInterpreter.CheckCondition(const V: TAxValue; const Construct: string);
begin
  if V.Kind <> vkBool then
    RaiseFmt(TypeError, 'the condition of "%s" must be a bool, got %s',
      [Construct, TypeName(V)]);
end;

{ ---------------- statements ---------------- }

{ Runs statements directly in Scope. }
function TInterpreter.ExecBody(Stmts: TStmtList; Scope: TScope): TSignal;
var
  S: TStmt;
begin
  Result := sigNone;
  for S in Stmts do
  begin
    Result := ExecStmt(S, Scope);
    if Result <> sigNone then
      Exit;
  end;
end;

{ Runs statements in a new block scope under Parent. }
function TInterpreter.ExecBlock(Stmts: TStmtList; Parent: TScope): TSignal;
var
  Scope: TScope;
begin
  if Stmts.Count = 0 then
    Exit(sigNone);
  Scope := TScope.Create(Parent, rkNone);
  try
    Result := ExecBody(Stmts, Scope);
  finally
    Scope.Release;
  end;
end;

function TInterpreter.ExecFor(S: TForStmt; Scope: TScope): TSignal;
var
  Iter: TAxValue;
  R: TRangeObj;
  K: Int64;
  A: TArrayObj;
  N: Int64;
  Items: TAxValues;
  Chars: TArray<string>;
  J: Integer;
  IterScope: TScope;
  Sig: TSignal;
begin
  Result := sigNone;
  // The iterated value is held for the whole loop, so assignments to the
  // array inside the body copy it (copy-on-write) and do not affect the loop.
  Iter := Eval(S.Iter, Scope);
  R := nil;
  A := nil;
  if Iter.Kind = vkRange then
  begin
    R := AsRange(Iter);
    N := R.Count;
  end
  else if Iter.Kind = vkArray then
  begin
    A := AsArray(Iter);
    N := A.Count;
  end
  else if Iter.Kind in [vkList, vkDict, vkString] then
  begin
    // A list's elements, a dictionary's keys, a string's characters.
    case Iter.Kind of
      vkList: Items := AsList(Iter).Items;
      vkDict: Items := Copy(AsDict(Iter).Keys);
    else
      begin
        Chars := StringChars(AsString(Iter));
        SetLength(Items, Length(Chars));
        for J := 0 to High(Chars) do
          Items[J] := StringValue(Chars[J]);
      end;
    end;
    N := Length(Items);
  end
  else
  begin
    RaiseFmt(TypeError, 'cannot iterate over %s', [TypeName(Iter)]);
    N := 0;
  end;
  K := 0;
  while K < N do
  begin
    // A fresh scope, and so a fresh binding of the loop variable, per iteration.
    IterScope := TScope.Create(Scope, rkNone);
    try
      if R <> nil then
        IterScope.Define(S.VarName).Value := R.ItemAt(K)
      else if A <> nil then
        IterScope.Define(S.VarName).Value := A.Get(K)
      else
        IterScope.Define(S.VarName).Value := Items[K];
      Sig := ExecBody(S.Body, IterScope);
    finally
      IterScope.Release;
    end;
    case Sig of
      sigBreak:  Break;
      sigReturn: Exit(sigReturn);
    end;
    Inc(K);
  end;
end;

procedure TInterpreter.ExecDecl(S: TDeclStmt; Scope: TScope);
var
  C, ModCell: TVarCell;
  V: TAxValue;
begin
  if S.Value <> nil then
    V := Eval(S.Value, Scope)
  else
    V := NothingValue;

  if not S.IsGlobal then
  begin
    // local x [: T] [= e]: a new variable in the innermost scope.
    C := Scope.Define(S.Name);
    if C.ReadOnly then
      RaiseFmt(NameError, '"%s" is imported and cannot be redeclared here', [S.Name]);
    C.IsGlobalAlias := False;
    C.TypeRef := S.TypeRef;
    Store(C, V, S.Name, Scope);
    Exit;
  end;

  // global x [: T] [= e]
  if FunctionRootOf(Scope).Root <> rkModule then
  begin
    C := Scope.Define(S.Name);
    C.IsGlobalAlias := True;
    C.TypeRef := nil;
  end;
  if (S.TypeRef <> nil) or (S.Value <> nil) then
  begin
    ModCell := Scope.Module.Define(S.Name);
    if S.TypeRef <> nil then
      ModCell.TypeRef := S.TypeRef;
    Store(ModCell, V, S.Name, Scope);
  end;
end;

{ Evaluates an expression that may produce several values (a call). }
function TInterpreter.EvalMulti(E: TExpr; Scope: TScope): TAxValues;
begin
  if E is TCallExpr then
    Result := EvalCallMulti(TCallExpr(E), Scope)
  else
    Result := [Eval(E, Scope)];
end;

procedure TInterpreter.ExecDestructure(S: TDestructureStmt; Scope: TScope);
var
  Values: TAxValues;
  I: Integer;
begin
  Values := EvalMulti(S.Value, Scope);
  if Length(Values) <> S.Targets.Count then
    RaiseFmt(ArgumentError, 'cannot unpack %d value(s) into %d targets',
      [Length(Values), S.Targets.Count]);
  for I := 0 to S.Targets.Count - 1 do
    if not (S.Targets[I] is TNameExpr) then
      AssignPath(S.Targets[I], Values[I], Scope)
    else
      Assign(TNameExpr(S.Targets[I]).Name, Values[I], Scope);
end;

{ try ... catch [name] ... end. Every Axon error raised in the try block,
  including in functions it calls, is caught. The catch name is local to the
  catch block (scope rule 4). }
function TInterpreter.ExecTry(S: TTryStmt; Scope: TScope): TSignal;
var
  Caught: Boolean;
  ErrValue: TAxValue;
  CatchScope: TScope;
begin
  Result := sigNone;
  Caught := False;
  try
    Result := ExecBlock(S.Body, Scope);
  except
    on E: EAxonError do
    begin
      ErrValue := ErrorToValue(E);
      Caught := True;
    end;
  end;
  if not Caught then
    Exit;
  // The handler runs outside the Delphi except block, so an error it raises
  // propagates normally.
  CatchScope := TScope.Create(Scope, rkNone);
  try
    if S.CatchName <> '' then
      CatchScope.Define(S.CatchName).Value := ErrValue;
    Result := ExecBody(S.CatchBody, CatchScope);
  finally
    CatchScope.Release;
  end;
end;

function TInterpreter.ExecStmt(S: TStmt; Scope: TScope): TSignal;
var
  C: TClass;
  V: TAxValue;
  B: TIfBranch;
  Taken: Boolean;
  Target: TExpr;
  Cell: TVarCell;
  Decl: TFunctionDecl;
  Vals: TAxValues;
  I: Integer;
  Root: TScope;
begin
  Result := sigNone;
  try
    C := S.ClassType;
    if C = TExprStmt then
      // A call used as a statement may return any number of values.
      EvalMulti(TExprStmt(S).Expr, Scope)
    else if C = TAssignStmt then
    begin
      Target := TAssignStmt(S).Target;
      V := Eval(TAssignStmt(S).Value, Scope);
      if not (Target is TNameExpr) then
      begin
        if TAssignStmt(S).TypeRef <> nil then
          RaiseError(TypeError, 'only a plain variable can carry a type annotation');
        AssignPath(Target, V, Scope);
        Exit;
      end;
      if TAssignStmt(S).TypeRef <> nil then
      begin
        // x: T = e declares x in the current scope.
        Cell := Scope.Define(TNameExpr(Target).Name);
        Cell.IsGlobalAlias := False;
        Cell.TypeRef := TAssignStmt(S).TypeRef;
        Store(Cell, V, TNameExpr(Target).Name, Scope);
      end
      else
        Assign(TNameExpr(Target).Name, V, Scope);
    end
    else if C = TIfStmt then
    begin
      Taken := False;
      for B in TIfStmt(S).Branches do
      begin
        V := Eval(B.Cond, Scope);
        if B = TIfStmt(S).Branches[0] then
          CheckCondition(V, 'if')
        else
          CheckCondition(V, 'elseif');
        if V.B then
        begin
          Result := ExecBlock(B.Body, Scope);
          Taken := True;
          Break;
        end;
      end;
      if not Taken and (TIfStmt(S).ElseBody <> nil) then
        Result := ExecBlock(TIfStmt(S).ElseBody, Scope);
    end
    else if C = TWhileStmt then
    begin
      while True do
      begin
        V := Eval(TWhileStmt(S).Cond, Scope);
        CheckCondition(V, 'while');
        if not V.B then
          Break;
        case ExecBlock(TWhileStmt(S).Body, Scope) of
          sigBreak:  Break;
          sigReturn: Exit(sigReturn);
        end;
      end;
    end
    else if C = TForStmt then
      Result := ExecFor(TForStmt(S), Scope)
    else if C = TReturnStmt then
    begin
      SetLength(Vals, TReturnStmt(S).Values.Count);
      for I := 0 to High(Vals) do
        Vals[I] := Eval(TReturnStmt(S).Values[I], Scope);
      if Length(Vals) = 0 then
        Vals := [NothingValue];
      FReturn := Vals;
      Result := sigReturn;
    end
    else if C = TBreakStmt then
      Result := sigBreak
    else if C = TContinueStmt then
      Result := sigContinue
    else if C = TFunctionStmt then
    begin
      Decl := TFunctionStmt(S).Func;
      if not FHoisted.ContainsKey(Decl) then
      begin
        // Bound in the outermost scope of the enclosing function or module.
        Root := FunctionRootOf(Scope);
        V := FunctionValue(Decl, Scope, Root.Root <> rkModule);
        Cell := Root.Define(Decl.Name);
        Cell.IsGlobalAlias := False;
        Store(Cell, V, Decl.Name, Scope);
      end;
    end
    else if C = TDeclStmt then
      ExecDecl(TDeclStmt(S), Scope)
    else if C = TDestructureStmt then
      ExecDestructure(TDestructureStmt(S), Scope)
    else if C = TTryStmt then
      Result := ExecTry(TTryStmt(S), Scope)
    else if C = TRecordStmt then
    begin
      if not FHoistedRecords.ContainsKey(TRecordStmt(S)) then
      begin
        Root := FunctionRootOf(Scope);
        Cell := Root.Define(TRecordStmt(S).Name);
        if Cell.ReadOnly then
          RaiseFmt(NameError, '"%s" is imported and cannot be redefined', [TRecordStmt(S).Name]);
        Cell.IsGlobalAlias := False;
        Cell.TypeRef := nil;
        Cell.Value := RecordTypeValue(TRecordStmt(S));
      end;
    end
    else if C = TImportStmt then
      ExecImport(TImportStmt(S), Scope)
    else if C = TExternStmt then
    begin
      if not FHoistedExterns.ContainsKey(TExternStmt(S)) then
        ExecExtern(TExternStmt(S), Scope);
    end
    else
      NotYet(S.ClassName, 'a later milestone', S);
  except
    on E: EAxonError do
    begin
      E.Locate(FFile, S.Line, S.Col);
      raise;
    end;
  end;
end;

{ ---------------- calls ---------------- }

function TInterpreter.CallBuiltin(B: TBuiltinObj; E: TCallExpr; Scope: TScope): TAxValues;
var
  Args: TAxValues;
  I: Integer;
begin
  SetLength(Args, E.Args.Count);
  for I := 0 to E.Args.Count - 1 do
  begin
    if E.Args[I].Kind = akKeyword then
      RaiseFmt(ArgumentError, '%s takes no keyword arguments (got %s=)',
        [B.Name, E.Args[I].Name]);
    if E.Args[I].Kind = akPair then
      RaiseError(TypeError, '"=>" pairs are only accepted by dict(...)');
    Args[I] := Eval(E.Args[I].Value, Scope);
  end;
  if (Length(Args) < B.MinArgs) or ((B.MaxArgs >= 0) and (Length(Args) > B.MaxArgs)) then
  begin
    if B.MinArgs = B.MaxArgs then
      RaiseFmt(ArgumentError, '%s takes %d argument(s), got %d',
        [B.Name, B.MinArgs, Length(Args)])
    else if B.MaxArgs < 0 then
      RaiseFmt(ArgumentError, '%s takes at least %d argument(s), got %d',
        [B.Name, B.MinArgs, Length(Args)])
    else
      RaiseFmt(ArgumentError, '%s takes %d to %d arguments, got %d',
        [B.Name, B.MinArgs, B.MaxArgs, Length(Args)]);
  end;
  if Assigned(B.MultiFn) then
    Result := B.MultiFn(Args)
  else
    Result := [B.Fn(Args)];
end;

function DescribeFunction(F: TFunctionObj): string;
begin
  if F.Name <> '' then
    Result := F.Name
  else
    Result := 'anonymous function';
end;

{ The compiled code of F for the types of these arguments, compiling it at
  the first call with them; nil when it does not compile. The last set of
  types is checked first, so a function called the same way each time costs
  one comparison per argument. }
function TInterpreter.CompiledFor(F: TFunctionObj; const Args: TAxValues): TObject;
var
  Types: TArray<TJType>;
  K: Integer;
  Same: Boolean;
  Key: string;
begin
  if F.JitHaveLast and (Length(Args) = Length(F.JitLastTypes)) then
  begin
    Same := True;
    for K := 0 to High(Args) do
      if JitTypeOf(Args[K]) <> F.JitLastTypes[K] then
      begin
        Same := False;
        Break;
      end;
    if Same then
      Exit(F.JitLastCode);
  end;
  SetLength(Types, Length(Args));
  for K := 0 to High(Args) do
    Types[K] := JitTypeOf(Args[K]);
  if F.JitCodes = nil then
    F.JitCodes := TDictionary<string, TObject>.Create;
  Key := '';
  for K := 0 to High(Types) do
    Key := Key + Chr(Ord('a') + Ord(Types[K]));
  if not F.JitCodes.TryGetValue(Key, Result) then
  begin
    Result := JitCompile(F.Decl, F, F.FileName, Types, F.IsClosure, F.JitReason);
    F.JitCodes.Add(Key, Result);
  end;
  F.JitLastTypes := Types;
  F.JitLastCode := Result;
  F.JitHaveLast := True;
end;

{ The values compiled code reads from outside (J7c), resolved now as the
  function's own lookups would resolve them: each path's name through the
  defining scope, then its fields. False when one is missing or has another
  type than the code was compiled for, or when a name a closure creates
  locally now exists outside; the call is then interpreted. }
function TInterpreter.CapturesFor(F: TFunctionObj; Code: TObject; out Caps: TAxValues): Boolean;
var
  C: TJitCode;
  K, J, Idx: Integer;
  Cell: TVarCell;
  V: TAxValue;

  function FindOutside(const Name: string): TVarCell;
  var
    Sc: TScope;
  begin
    Sc := F.Closure;
    Result := nil;
    while (Sc <> nil) and (Result = nil) do
    begin
      Result := Sc.Find(Name);
      Sc := Sc.Parent;
    end;
  end;

  { True when no scope of the chain has gained a name since the cells were
    found, so every name still resolves to the same cell. }
  function ChainUnchanged: Boolean;
  var
    J: Integer;
  begin
    for J := 0 to High(F.JitCapScopes) do
      if F.JitCapScopes[J].VarCount <> F.JitCapCounts[J] then
        Exit(False);
    Result := True;
  end;

  procedure Snapshot;
  var
    Sc: TScope;
  begin
    F.JitCapScopes := nil;
    F.JitCapCounts := nil;
    Sc := F.Closure;
    while Sc <> nil do
    begin
      F.JitCapScopes := F.JitCapScopes + [Sc];
      F.JitCapCounts := F.JitCapCounts + [Sc.VarCount];
      Sc := Sc.Parent;
    end;
  end;

begin
  C := TJitCode(Code);
  Caps := nil;
  if (Length(C.LocalNames) = 0) and (Length(C.Captures) = 0) then
    Exit(True);
  if (F.JitCapFor <> Code) or not ChainUnchanged then
  begin
    // Find the cells again (and check the closure's local names are still
    // absent outside), then remember where.
    F.JitCapFor := nil;
    for K := 0 to High(C.LocalNames) do
      if FindOutside(C.LocalNames[K]) <> nil then
        Exit(False);
    SetLength(F.JitCapCells, Length(C.Captures));
    for K := 0 to High(C.Captures) do
    begin
      F.JitCapCells[K] := FindOutside(C.Captures[K].Path[0]);
      if F.JitCapCells[K] = nil then
        Exit(False);
    end;
    Snapshot;
    F.JitCapFor := Code;
  end;
  if Length(C.Captures) = 0 then
    Exit(True);
  SetLength(Caps, Length(C.Captures));
  for K := 0 to High(C.Captures) do
  begin
    Cell := F.JitCapCells[K];
    V := Cell.Value;
    for J := 1 to High(C.Captures[K].Path) do
    begin
      if V.Kind <> vkRecord then
        Exit(False);
      Idx := AsRecord(V).IndexOf(C.Captures[K].Path[J]);
      if Idx < 0 then
        Exit(False);
      V := AsRecord(V).Values[Idx];
    end;
    if JTypeOfValue(V) <> C.Captures[K].Typ then
      Exit(False);
    Caps[K] := V;
  end;
  Result := True;
end;

type
  TSlots = array[0..MaxInt div 16] of Int64;
  PSlots = ^TSlots;

{ Calls compiled code with the bound arguments and the captured values. An
  error it reports is raised here, at its site, inside Invoke's frame
  handling, so the report and trace match the interpreter's. }
function TInterpreter.RunCompiled(Code: TObject; const Args, Caps: TAxValues): TAxValues;
const
  Small = 16;
var
  C: TJitCode;
  // Slots on the stack for the usual small calls, on the heap beyond.
  ArgBuf, ResBuf: array[0..Small - 1] of Int64;
  ArgHeap, ResHeap: TArray<Int64>;
  ArgSlots, ResSlots: PSlots;
  ResVals: TAxValues;          // only when there are array results
  K, NArgs, NRes: Integer;

  procedure Pack(Slot: Integer; T: TJType; const V: TAxValue);
  begin
    // Arrays go by the address of their value; compiled code shares it.
    case T of
      jtBool: ArgSlots[Slot] := Ord(V.B);
      jtInt:  ArgSlots[Slot] := V.I;
      jtReal: PDouble(@ArgSlots[Slot])^ := V.R;
      jtVecReal, jtVecInt, jtMatReal: ArgSlots[Slot] := NativeInt(@V);
    end;
  end;

begin
  C := TJitCode(Code);
  NArgs := Length(Args) + Length(Caps);
  NRes := Length(C.ResultTypes);
  if NArgs <= Small then
    ArgSlots := @ArgBuf
  else
  begin
    SetLength(ArgHeap, NArgs);
    ArgSlots := @ArgHeap[0];
  end;
  if NRes <= Small then
    ResSlots := @ResBuf
  else
  begin
    SetLength(ResHeap, NRes);
    ResSlots := @ResHeap[0];
  end;
  for K := 0 to High(Args) do
    Pack(K, C.ParamTypes[K], Args[K]);
  for K := 0 to High(Caps) do
    Pack(Length(Args) + K, C.Captures[K].Typ, Caps[K]);
  for K := 0 to NRes - 1 do
    if C.ResultTypes[K] in [jtVecReal, jtVecInt, jtMatReal] then
    begin
      if ResVals = nil then
        SetLength(ResVals, NRes);
      ResSlots[K] := NativeInt(@ResVals[K]);
    end;
  if C.Entry(ArgSlots, ResSlots) <> 0 then
    raise TakeJitError;
  if Length(C.ResultTypes) = 0 then
  begin
    Result := [NothingValue];
    Exit;
  end;
  SetLength(Result, Length(C.ResultTypes));
  for K := 0 to High(C.ResultTypes) do
    case C.ResultTypes[K] of
      jtBool: Result[K] := BoolValue(ResSlots[K] <> 0);
      jtInt:  Result[K] := IntValue(ResSlots[K]);
      jtReal: Result[K] := RealValue(PDouble(@ResSlots[K])^);
      jtVecReal, jtVecInt, jtMatReal: Result[K] := ResVals[K];
    end;
end;

{ __jit_compiled(f): true once f has compiled code. }
function BParseFunction(const Args: TAxValues): TAxValue;
begin
  Result := GInterp.ParseFunction(Args);
end;

(* parse_function(params, expr) and parse_function(text): a function made
   from text at run time. With two strings, params lists the parameter names
   ("x, y") and expr is the expression it returns ("2*sin(x) + y^2"); with
   one, text is a whole lambda, "function(x) ... end". The function sees only
   its parameters and the prelude (built-in functions and constants): it gets
   a module scope of its own, empty, so it reads no variable of the program
   and can reach no module. For the expression form, every name is checked
   when the function is made; a syntax error or unknown name is reported with
   its position in the expression. *)
function TInterpreter.ParseFunction(const Args: TAxValues): TAxValue;
const
  Src = '<parse_function>';
var
  Text, Params, Expr, Prefix: string;
  IsExpr: Boolean;
  Prog: TProgram;
  Lambda: TLambdaExpr;
  P: TParam;
  Names: TList<string>;
  Scope: TScope;

  function Where(Col: Integer): string;
  begin
    if IsExpr and (Col > Length(Prefix)) and (Col <= Length(Prefix) + Length(Expr) + 1) then
      Result := Format(' at character %d of "%s"', [Col - Length(Prefix), Expr])
    else
      Result := Format(' in "%s"', [Text]);
  end;

  // Every name the expression reads must be a parameter or a prelude name.
  procedure CheckNames(E: TExpr);
  var
    K, J: Integer;
  begin
    if E = nil then
      Exit;
    if E is TNameExpr then
    begin
      if not Names.Contains(TNameExpr(E).Name) and
        (FPrelude.Find(TNameExpr(E).Name) = nil) then
        raise EAxonError.Create(NameError, Format('parse_function: unknown name "%s"%s',
          [TNameExpr(E).Name, Where(E.Col)]));
    end
    else if E is TUnaryExpr then
      CheckNames(TUnaryExpr(E).Operand)
    else if E is TBinaryExpr then
    begin
      CheckNames(TBinaryExpr(E).Left);
      CheckNames(TBinaryExpr(E).Right);
    end
    else if E is TRangeExpr then
    begin
      CheckNames(TRangeExpr(E).Start);
      CheckNames(TRangeExpr(E).Step);
      CheckNames(TRangeExpr(E).Stop);
    end
    else if E is TCallExpr then
    begin
      CheckNames(TCallExpr(E).Callee);
      for K := 0 to TCallExpr(E).Args.Count - 1 do
        CheckNames(TCallExpr(E).Args[K].Value);
    end
    else if E is TIndexExpr then
    begin
      CheckNames(TIndexExpr(E).Target);
      for K := 0 to TIndexExpr(E).Items.Count - 1 do
        CheckNames(TIndexExpr(E).Items[K]);
    end
    else if E is TFieldExpr then
      CheckNames(TFieldExpr(E).Target)
    else if E is TMatrixExpr then
    begin
      for K := 0 to TMatrixExpr(E).Rows.Count - 1 do
        for J := 0 to TMatrixExpr(E).Rows[K].Count - 1 do
          CheckNames(TMatrixExpr(E).Rows[K][J]);
    end
    else if E is TListExpr then
    begin
      for K := 0 to TListExpr(E).Items.Count - 1 do
        CheckNames(TListExpr(E).Items[K]);
    end
    else if E is TRecordExpr then
    begin
      for K := 0 to TRecordExpr(E).Values.Count - 1 do
        CheckNames(TRecordExpr(E).Values[K]);
    end;
    // Literals, end and : read no name; a nested lambda is checked when called.
  end;

begin
  if Args[0].Kind <> vkString then
    RaiseFmt(TypeError, 'parse_function needs a string, got %s', [TypeName(Args[0])]);
  IsExpr := Length(Args) = 2;
  if IsExpr then
  begin
    if Args[1].Kind <> vkString then
      RaiseFmt(TypeError, 'parse_function: the expression must be a string, got %s',
        [TypeName(Args[1])]);
    Params := AsString(Args[0]);
    Expr := AsString(Args[1]);
    if (Expr.IndexOfAny([#10, #13]) >= 0) or (Params.IndexOfAny([#10, #13]) >= 0) then
      RaiseError(ArgumentError, 'parse_function: the parameters and the expression must ' +
        'each be one line; use parse_function("function(x) ... end") for more');
    if Expr.Trim = '' then
      RaiseError(ArgumentError, 'parse_function: the expression is empty');
    Prefix := 'function(' + Params + ') return ';
    Text := Prefix + Expr + ' end';
  end
  else
  begin
    Text := AsString(Args[0]);
    Prefix := '';
  end;

  try
    Prog := ParseSource(Text, Src);
  except
    on E: EAxonError do
      // Past the expression, the parser meets the "end" added after it: the
      // expression stopped too early, such as an unclosed bracket.
      if IsExpr and (E.Col > Length(Prefix) + Length(Expr)) then
        raise EAxonError.Create(E.Kind, Format('parse_function: the expression "%s" is ' +
          'incomplete (an unclosed bracket, or an operator with nothing after it?)', [Expr]))
      else
        raise EAxonError.Create(E.Kind, 'parse_function: ' + E.Message + Where(E.Col));
  end;
  FPrograms.Add(Prog);    // the function's syntax tree lives as long as the run
  if (Prog.Body.Count <> 1) or not (Prog.Body[0] is TExprStmt) or
    not (TExprStmt(Prog.Body[0]).Expr is TLambdaExpr) then
    RaiseError(ArgumentError, 'parse_function: the text must be one function, ' +
      'function(x) ... end, or give the parameters and the expression separately');
  Lambda := TLambdaExpr(TExprStmt(Prog.Body[0]).Expr);

  if IsExpr then
  begin
    Names := TList<string>.Create;
    try
      for P in Lambda.Func.Params do
        Names.Add(P.Name);
      if (Lambda.Func.Body.Count = 1) and (Lambda.Func.Body[0] is TReturnStmt) and
        (TReturnStmt(Lambda.Func.Body[0]).Values.Count = 1) then
        CheckNames(TReturnStmt(Lambda.Func.Body[0]).Values[0]);
    finally
      Names.Free;
    end;
  end;

  // A module scope of its own, empty, over the prelude.
  Scope := TScope.Create(FPrelude, rkModule);
  try
    Result := FunctionValue(Lambda.Func, Scope, True);
    TFunctionObj(Result.Obj).FileName := Src;
  finally
    Scope.Release;
  end;
end;

function BJitCompiled(const Args: TAxValues): TAxValue;
begin
  Result := BoolValue((Args[0].Kind = vkFunction) and
    (JitCodeOf(TFunctionObj(Args[0].Obj).Decl) <> nil));
end;

{ __jit_reason(f): why f was not compiled ("" when it was, or was not tried). }
function BJitReason(const Args: TAxValues): TAxValue;
begin
  if Args[0].Kind <> vkFunction then
    Result := StringValue('not an Axon function')
  else
    Result := StringValue(TFunctionObj(Args[0].Obj).JitReason);
end;

{ __jit_mode() gives the mode; __jit_mode(m) sets it ("off", "on" or "force")
  and gives the previous one. }
function BJitMode(const Args: TAxValues): TAxValue;
var
  Old: string;
begin
  Old := JitModeName;
  if Length(Args) = 1 then
    if (Args[0].Kind <> vkString) or not SetJitMode(AsString(Args[0])) then
      RaiseError(ArgumentError, '__jit_mode needs "off", "on" or "force"');
  Result := StringValue(Old);
end;

{ The fast path (J7c): compiled code that takes these arguments as they are,
  positional and needing no conversion, with its captured values as
  compiled. Binding would change nothing, so no scope or parameter cells are
  made; the depth check and the trace frame are Invoke's. FFile is not
  switched: compiled code evaluates no Axon source, and what it calls sets
  its own. False when the call must take the ordinary path. }
function TInterpreter.FastCall(F: TFunctionObj; const Pos: TAxValues; out Res: TAxValues): Boolean;
var
  Code: TObject;
  Caps: TAxValues;
  I: Integer;
begin
  Result := False;
  if (Length(Pos) <> F.Decl.Params.Count) or F.HasKeywordParams then
    Exit;
  Code := CompiledFor(F, Pos);
  if Code = nil then
    Exit;
  for I := 0 to High(Pos) do
    if JitTypeOf(Pos[I]) <> TJitCode(Code).ParamTypes[I] then
      Exit;
  if not CapturesFor(F, Code, Caps) then
    Exit;
  Inc(FCallDepth);
  try
    if FCallDepth > MaxCallDepth then
      RaiseFmt(RecursionError, 'calls nested more than %d deep (in %s)',
        [MaxCallDepth, DescribeFunction(F)]);
    try
      Res := RunCompiled(Code, Pos, Caps);
    except
      on E: EAxonError do
      begin
        E.LeaveFunction(DescribeFunction(F));
        raise;
      end;
    end;
  finally
    Dec(FCallDepth);
  end;
  Result := True;
end;

{ Binds arguments (reference, "Argument binding"), runs the body and returns
  its values. }
function TInterpreter.Invoke(F: TFunctionObj; const Pos: TAxValues;
  const KwNames: TArray<string>; const KwValues: TAxValues): TAxValues;
begin
  if (JitMode <> jmOff) and (Length(KwNames) = 0) and FastCall(F, Pos, Result) then
    Exit;
  Result := InvokeSlow(F, Pos, KwNames, KwValues);
end;

function TInterpreter.InvokeSlow(F: TFunctionObj; const Pos: TAxValues;
  const KwNames: TArray<string>; const KwValues: TAxValues): TAxValues;
var
  SavedFile, SavedPath: string;
  D: TFunctionDecl;
  P: TParam;
  Fn: string;
  NPos, NReq, I, J, K: Integer;
  Found: Boolean;
  Supplied: TArray<Integer>;   // per keyword parameter: index into KwValues, or -1
  Root: TScope;
  Kind: TRootKind;
  V: TAxValue;
  Cell: TVarCell;
  Bound: TAxValues;            // the bound parameter values, for compiled code
  JitCode: TObject;
  Caps: TAxValues;
begin
  D := F.Decl;
  Fn := DescribeFunction(F);

  // Keyword names are checked first, so that passing a positional parameter
  // by keyword is reported as such rather than as a missing argument.
  // 2. Keyword arguments, by name.
  SetLength(Supplied, D.Params.Count);
  for I := 0 to High(Supplied) do
    Supplied[I] := -1;
  for K := 0 to High(KwNames) do
  begin
    Found := False;
    for I := 0 to D.Params.Count - 1 do
      if D.Params[I].Name = KwNames[K] then
      begin
        Found := True;
        if not D.Params[I].IsKeyword then
          RaiseFmt(ArgumentError,
            '"%s" is a positional parameter of %s and cannot be passed by keyword',
            [KwNames[K], Fn]);
        if Supplied[I] >= 0 then
          RaiseFmt(ArgumentError, 'keyword argument "%s" given twice in call to %s',
            [KwNames[K], Fn]);
        Supplied[I] := K;
      end;
    if not Found then
      RaiseFmt(ArgumentError, '%s has no keyword parameter "%s"', [Fn, KwNames[K]]);
  end;

  // 1. Positional arguments; optional ones (with a default) may be left out.
  NPos := 0;
  NReq := 0;
  for P in D.Params do
    if not P.IsKeyword then
    begin
      Inc(NPos);
      if P.Default = nil then
        Inc(NReq);
    end;
  if (Length(Pos) < NReq) or (Length(Pos) > NPos) then
    if NReq = NPos then
      RaiseFmt(ArgumentError, '%s takes %d positional argument(s), got %d',
        [Fn, NPos, Length(Pos)])
    else
      RaiseFmt(ArgumentError, '%s takes %d to %d positional arguments, got %d',
        [Fn, NReq, NPos, Length(Pos)]);

  Inc(FCallDepth);
  SavedFile := FFile;
  SavedPath := FCurrentPath;
  FFile := F.FileName;
  FCurrentPath := F.FilePath;
  try
    if FCallDepth > MaxCallDepth then
      RaiseFmt(RecursionError, 'calls nested more than %d deep (in %s)', [MaxCallDepth, Fn]);

    if F.IsClosure then Kind := rkClosure else Kind := rkNamedFunction;
    Root := TScope.Create(F.Closure, Kind);
    try
    try
      // 3 and 4. Bind parameters in order, evaluating defaults in the new
      // scope (whose parent is the defining scope), so a default may refer to
      // earlier parameters. Annotated parameters are checked and widened.
      J := 0;
      SetLength(Bound, D.Params.Count);
      for I := 0 to D.Params.Count - 1 do
      begin
        P := D.Params[I];
        if not P.IsKeyword and (J < Length(Pos)) then
        begin
          V := Pos[J];
          Inc(J);
        end
        else if not P.IsKeyword then
          V := Eval(P.Default, Root)
        else if Supplied[I] >= 0 then
          V := KwValues[Supplied[I]]
        else
          V := Eval(P.Default, Root);
        if P.TypeRef <> nil then
          V := Coerce(V, P.TypeRef, Format('argument "%s" of %s', [P.Name, Fn]), Root);
        Cell := Root.Define(P.Name);
        Cell.TypeRef := P.TypeRef;
        Cell.Value := V;
        Bound[I] := V;
      end;

      // Compiled code, when the JIT is on and the function compiles for
      // these argument types and its captured values are as compiled.
      JitCode := nil;
      if JitMode <> jmOff then
      begin
        JitCode := CompiledFor(F, Bound);
        if (JitCode <> nil) and not CapturesFor(F, JitCode, Caps) then
          JitCode := nil;
      end;
      if JitCode <> nil then
        Result := RunCompiled(JitCode, Bound, Caps)
      else if ExecBody(D.Body, Root) = sigReturn then
      begin
        Result := FReturn;
        FReturn := nil;
      end
      else
        Result := [NothingValue];
    except
      // An error leaving the body closes this function's trace frame. An
      // error with no location yet (a parameter type mismatch) belongs to
      // the call site instead, and LeaveFunction leaves it alone.
      on E: EAxonError do
      begin
        E.LeaveFunction(Fn);
        raise;
      end;
    end;
    finally
      Root.Release;
    end;

    if D.ReturnType <> nil then
    begin
      if Length(Result) <> 1 then
        RaiseFmt(TypeError, '%s is annotated to return %s but returned %d values',
          [Fn, D.ReturnType.ToString, Length(Result)]);
      Result[0] := Coerce(Result[0], D.ReturnType,
        Format('the return value of %s', [Fn]), F.Closure);
    end;
  finally
    Dec(FCallDepth);
    FFile := SavedFile;
    FCurrentPath := SavedPath;
  end;
end;

function TInterpreter.EvalCallMulti(E: TCallExpr; Scope: TScope): TAxValues;
var
  Callee: TAxValue;
  Pos, KwValues: TAxValues;
  KwNames: TArray<string>;
  A: TArg;
begin
  try
    Callee := Eval(E.Callee, Scope);
    case Callee.Kind of
      vkBuiltin:
        if AsBuiltin(Callee).Name = 'dict' then
          Result := [BuildDict(E, Scope)]
        else if AsBuiltin(Callee).Name = '__native_library' then
          Result := [NativeLibraryHook(E, Scope)]
        else
          Result := CallBuiltin(AsBuiltin(Callee), E, Scope);
      vkRecordType:
        Result := [ConstructRecord(Callee, E, Scope)];
      vkExtern:
        Result := [CallExternValue(TExternFuncObj(Callee.Obj), E, Scope)];
      vkFunction:
        begin
          // Arguments are evaluated left to right before the call.
          for A in E.Args do
            case A.Kind of
              akPositional: Pos := Pos + [Eval(A.Value, Scope)];
              akKeyword:
                begin
                  KwNames := KwNames + [A.Name];
                  KwValues := KwValues + [Eval(A.Value, Scope)];
                end;
              akPair: RaiseError(TypeError, '"=>" pairs are only accepted by dict(...)');
            end;
          Result := Invoke(TFunctionObj(Callee.Obj), Pos, KwNames, KwValues);
        end;
    else
      RaiseFmt(TypeError, '%s is not callable', [TypeName(Callee)]);
    end;
  except
    on X: EAxonError do
    begin
      X.Locate(FFile, E.Line, E.Col);
      raise;
    end;
  end;
end;

{ ---------------- expressions ---------------- }

function TInterpreter.MakeRange(E: TRangeExpr; Scope: TScope): TAxValue;
var
  A, H, B: TAxValue;
begin
  A := Eval(E.Start, Scope);
  if E.Step <> nil then
    H := Eval(E.Step, Scope)
  else
    H := IntValue(1);
  B := Eval(E.Stop, Scope);
  Result := NewRange(A, H, B);
end;

function TInterpreter.EvalLogical(E: TBinaryExpr; Scope: TScope): TAxValue;
var
  L, R: TAxValue;
  Word: string;
begin
  Word := TokenSpelling[E.Op];
  L := Eval(E.Left, Scope);
  // An array left operand: both operands are evaluated and combined
  // elementwise with broadcasting.
  if L.Kind = vkArray then
  begin
    R := Eval(E.Right, Scope);
    Exit(BinaryOp(E.Op, L, R));
  end;
  if L.Kind <> vkBool then
    RaiseFmt(TypeError, '"%s" needs bool operands, got %s', [Word, TypeName(L)]);
  // Short-circuit on a scalar left operand.
  if (E.Op = tkAnd) and not L.B then
    Exit(BoolValue(False));
  if (E.Op = tkOr) and L.B then
    Exit(BoolValue(True));
  R := Eval(E.Right, Scope);
  if R.Kind = vkArray then
    Exit(BinaryOp(E.Op, L, R));
  if R.Kind <> vkBool then
    RaiseFmt(TypeError, '"%s" needs bool operands, got %s', [Word, TypeName(R)]);
  Result := R;
end;

{ r.name on a record. A missing field raises FieldError. }
function TInterpreter.EvalField(E: TFieldExpr; Scope: TScope): TAxValue;
var
  T: TAxValue;
  K: Integer;
begin
  T := Eval(E.Target, Scope);
  if T.Kind = vkModule then
    Exit(ModuleMember(T, E));
  if T.Kind <> vkRecord then
    raise EAxonError.CreateAt(TypeError, Format('%s has no fields (accessing ".%s")',
      [TypeName(T), E.Name]), FFile, E.Line, E.Col);
  K := AsRecord(T).IndexOf(E.Name);
  if K < 0 then
    raise EAxonError.CreateAt(FieldError, Format('the record has no field "%s"', [E.Name]),
      FFile, E.Line, E.Col);
  Result := AsRecord(T).Values[K];
end;

function TInterpreter.EvalMatrix(E: TMatrixExpr; Scope: TScope): TAxValue;
var
  Rows: TArray<TAxValues>;
  R, K: Integer;
begin
  SetLength(Rows, E.Rows.Count);
  for R := 0 to E.Rows.Count - 1 do
  begin
    SetLength(Rows[R], E.Rows[R].Count);
    for K := 0 to E.Rows[R].Count - 1 do
      Rows[R][K] := Eval(E.Rows[R][K], Scope);
  end;
  try
    Result := ConcatLiteral(Rows);
  except
    on X: EAxonError do
    begin
      X.Locate(FFile, E.Line, E.Col);
      raise;
    end;
  end;
end;

{ ---------------- indexing ---------------- }

{ Positions selected by one index item along a dimension of length Len. }
procedure TInterpreter.EvalIndexItem(Item: TExpr; Len: Integer; Scope: TScope;
  out Positions: TArray<Integer>; out Scalar: Boolean);
var
  V: TAxValue;
begin
  if Item is TColonExpr then
  begin
    Positions := AllPositions(Len);
    Scalar := False;
    Exit;
  end;
  // `end` inside this item is the length of this dimension.
  FEndStack.Add(Len);
  try
    V := Eval(Item, Scope);
  finally
    FEndStack.Delete(FEndStack.Count - 1);
  end;
  try
    ResolveIndex(V, Len, Positions, Scalar);
  except
    on X: EAxonError do
    begin
      X.Locate(FFile, Item.Line, Item.Col);
      raise;
    end;
  end;
end;

{ Resolves the index list of E against an array of the given shape. }
function TInterpreter.ResolveSelection(Rows, Cols: Integer; IsVector: Boolean;
  E: TIndexExpr; Scope: TScope): TSelection;
begin
  Result := Default(TSelection);
  case E.Items.Count of
    1:
      EvalIndexItem(E.Items[0], Rows * Cols, Scope, Result.Lin, Result.ScalarA);
    2:
      begin
        if IsVector then
          raise EAxonError.CreateAt(IndexError, 'a vector takes one index, got 2',
            FFile, E.Line, E.Col);
        Result.Two := True;
        EvalIndexItem(E.Items[0], Rows, Scope, Result.RowPos, Result.ScalarA);
        EvalIndexItem(E.Items[1], Cols, Scope, Result.ColPos, Result.ScalarB);
      end;
  else
    raise EAxonError.CreateAt(IndexError, Format('an array takes one or two indices, got %d',
      [E.Items.Count]), FFile, E.Line, E.Col);
  end;
end;

{ The positions of a selection in column-major order of the selection. }
function SelectionPositions(const Sel: TSelection; Rows: Integer): TArray<Integer>;
var
  I, J, K: Integer;
begin
  if not Sel.Two then
    Exit(Sel.Lin);
  SetLength(Result, Length(Sel.RowPos) * Length(Sel.ColPos));
  K := 0;
  for J := 0 to High(Sel.ColPos) do
    for I := 0 to High(Sel.RowPos) do
    begin
      Result[K] := Sel.ColPos[J] * Rows + Sel.RowPos[I];
      Inc(K);
    end;
end;

function ReadSelection(A: TArrayObj; const Sel: TSelection): TAxValue;
var
  Pos: TArray<Integer>;
  Res: TArrayObj;
  K: Integer;
begin
  Pos := SelectionPositions(Sel, A.Rows);
  // A scalar index drops its dimension: all scalar gives an element, one
  // scalar of two gives a vector, a single non-scalar index gives a vector.
  if (not Sel.Two and Sel.ScalarA) or (Sel.Two and Sel.ScalarA and Sel.ScalarB) then
    Exit(A.Get(Pos[0]));
  if not Sel.Two or Sel.ScalarA or Sel.ScalarB then
    Res := TArrayObj.Create(A.ElemType, Length(Pos), 1, True)
  else
    Res := TArrayObj.Create(A.ElemType, Length(Sel.RowPos), Length(Sel.ColPos), False);
  Result := ArrayValue(Res);
  for K := 0 to High(Pos) do
    Res.Put(K, A.Get(Pos[K]));
end;

function TInterpreter.IndexList(const T: TAxValue; E: TIndexExpr; Scope: TScope): TAxValue;
var
  L: TListObj;
  Pos: TArray<Integer>;
  Scalar: Boolean;
  Items: TAxValues;
  K: Integer;
begin
  L := AsList(T);
  if E.Items.Count <> 1 then
    raise EAxonError.CreateAt(IndexError, Format('a list takes one index, got %d',
      [E.Items.Count]), FFile, E.Line, E.Col);
  EvalIndexItem(E.Items[0], Length(L.Items), Scope, Pos, Scalar);
  if Scalar then
    Exit(L.Items[Pos[0]]);
  // A range, index list or mask selects a sublist.
  SetLength(Items, Length(Pos));
  for K := 0 to High(Pos) do
    Items[K] := L.Items[Pos[K]];
  Result := ListValue(Items);
end;

function TInterpreter.EvalIndex(E: TIndexExpr; Scope: TScope): TAxValue;
var
  T: TAxValue;
  A: TArrayObj;
begin
  T := Eval(E.Target, Scope);
  case T.Kind of
    vkList:
      Result := IndexList(T, E, Scope);
    vkArray, vkRange:
      begin
        if T.Kind = vkRange then
          T := ArrayValue(RangeToArray(AsRange(T)));
        A := AsArray(T);
        Result := ReadSelection(A, ResolveSelection(A.Rows, A.Cols, A.IsVector, E, Scope));
      end;
    vkString:
      Result := IndexString(T, E, Scope);
    vkDict:
      Result := IndexDict(T, E, Scope);
    vkSparse:
      Result := IndexSparse(T, E, Scope);
  else
    raise EAxonError.CreateAt(TypeError, Format('%s cannot be indexed', [TypeName(T)]),
      FFile, E.Line, E.Col);
  end;
end;

{ The cell an assignment to Name writes, found as Assign finds it (rule 6
  applies), or nil. }
function TInterpreter.FindCellForWrite(const Name: string; Scope: TScope): TVarCell;
var
  S: TScope;
begin
  S := Scope;
  while S <> nil do
  begin
    Result := S.Find(Name);
    if Result <> nil then
    begin
      if Result.IsGlobalAlias then
        Result := S.Module.Find(Name);
      Exit;
    end;
    if S.Root in [rkModule, rkNamedFunction] then
      Break;
    S := S.Parent;
  end;
  Result := nil;
end;

(* Slot[idx] = V for an array in Slot. The array is copied first if it is
   shared (copy-on-write), its element type widens to hold V, and the
   selection never grows it. TypeRef is the variable's annotation when Slot is
   a variable's own value, so that matrix{real} cannot widen. *)
procedure TInterpreter.AssignArraySlot(var Slot: TAxValue; Target: TIndexExpr;
  const V: TAxValue; TypeRef: TTypeRef; const Name: string; Scope: TScope);
var
  Arr, Src: TArrayObj;
  SrcHolder: TAxValue;
  Sel: TSelection;
  Pos: TArray<Integer>;
  N, K, SelRows, SelCols: Integer;
  NewType, Want: TElemType;
  OneDim, Ok: Boolean;
begin
  // Resolve the selection. Index expressions may call functions, so the
  // array is fetched again afterwards rather than held across the evaluation.
  Arr := AsArray(Slot);
  Sel := ResolveSelection(Arr.Rows, Arr.Cols, Arr.IsVector, Target, Scope);
  Arr := AsArray(Slot);
  Pos := SelectionPositions(Sel, Arr.Rows);
  N := Length(Pos);
  OneDim := not Sel.Two or Sel.ScalarA or Sel.ScalarB;
  SelRows := Length(Sel.RowPos);
  SelCols := Length(Sel.ColPos);

  // The right-hand side: a scalar broadcast, or an array of the selected shape.
  Src := nil;
  if IsArrayLike(V) then
  begin
    if V.Kind = vkRange then SrcHolder := ArrayValue(RangeToArray(AsRange(V))) else SrcHolder := V;
    Src := AsArray(SrcHolder);
    if OneDim then
      Ok := (Src.Count = N) and (Src.IsVector or (Src.Rows = 1) or (Src.Cols = 1))
    else
      Ok := (Src.Rows = SelRows) and (Src.Cols = SelCols);
    if not Ok then
    begin
      if OneDim then
        raise EAxonError.CreateAt(DimensionError, Format(
          'cannot assign %d elements (%d' + #$00D7 + '%d) to a selection of %d',
          [Src.Count, Src.Rows, Src.Cols, N]), FFile, Target.Line, Target.Col)
      else
        raise EAxonError.CreateAt(DimensionError, Format(
          'cannot assign a %d' + #$00D7 + '%d array to a %d' + #$00D7 + '%d selection',
          [Src.Rows, Src.Cols, SelRows, SelCols]), FFile, Target.Line, Target.Col);
    end;
    NewType := Src.ElemType;
  end
  else if NumRank(V) >= 0 then
    NewType := ElemTypeOf(V)
  else
    raise EAxonError.CreateAt(TypeError, Format('cannot store %s in an array', [TypeName(V)]),
      FFile, Target.Line, Target.Col);
  if NewType < Arr.ElemType then
    NewType := Arr.ElemType;

  // A typed variable such as A: matrix{real} cannot widen past its type.
  if (TypeRef <> nil) and (TypeRef.Param <> nil) then
  begin
    Want := Arr.ElemType;
    if TypeRef.Param.Name = 'bool' then Want := etBool
    else if TypeRef.Param.Name = 'int' then Want := etInt
    else if TypeRef.Param.Name = 'real' then Want := etReal
    else if TypeRef.Param.Name = 'complex' then Want := etComplex;
    if NewType > Want then
      raise EAxonError.CreateAt(TypeError, Format('variable "%s" must be %s; cannot store %s elements',
        [Name, TypeRef.ToString, ElemTypeName(NewType)]), FFile, Target.Line, Target.Col);
  end;

  // Copy-on-write: another value shares this array, so write to a copy.
  if Arr.RefCount > 1 then
  begin
    Arr := Arr.Clone;
    Slot := ArrayValue(Arr);
  end;
  Arr.Widen(NewType);
  for K := 0 to N - 1 do
    if Src <> nil then
      Arr.Put(Pos[K], Src.Get(K))
    else
      Arr.Put(Pos[K], V);
end;

{ Writes V at the end of the path Steps[I..] inside Slot. Each level is made
  unique (copy-on-write) before it is changed, so only the assigned variable
  sees the change. }
procedure TInterpreter.SetIn(var Slot: TAxValue; const Steps: TArray<TExpr>; I: Integer;
  const V: TAxValue; RootCell: TVarCell; const Name: string; Scope: TScope);
var
  Step: TExpr;
  Last, Scalar: Boolean;
  FieldName: string;
  R: TRecordObj;
  K: Integer;
  E: TIndexExpr;
  Pos: TArray<Integer>;
  L: TListObj;
  Src: TListObj;
  Key: TAxValue;
  D: TDictObj;
  TypeRef: TTypeRef;
begin
  Step := Steps[I];
  Last := I = High(Steps);

  if Step is TFieldExpr then
  begin
    FieldName := TFieldExpr(Step).Name;
    if Slot.Kind <> vkRecord then
      raise EAxonError.CreateAt(TypeError, Format('%s has no fields (assigning ".%s")',
        [TypeName(Slot), FieldName]), FFile, Step.Line, Step.Col);
    MakeUnique(Slot);
    R := AsRecord(Slot);
    K := R.IndexOf(FieldName);
    if Last then
    begin
      if K < 0 then
      begin
        if R.DeclType <> nil then
          raise EAxonError.CreateAt(FieldError, Format('record type %s has no field "%s"',
            [R.DeclType.Name, FieldName]), FFile, Step.Line, Step.Col);
        // A literal record gains the field.
        R.Names := R.Names + [FieldName];
        R.Values := R.Values + [V];
      end
      else if R.DeclType <> nil then
        R.Values[K] := Coerce(V, R.DeclType.FieldTypes[K],
          Format('field "%s" of %s', [FieldName, R.DeclType.Name]), Scope)
      else
        R.Values[K] := V;
    end
    else
    begin
      if K < 0 then
        raise EAxonError.CreateAt(FieldError, Format('the record has no field "%s"', [FieldName]),
          FFile, Step.Line, Step.Col);
      SetIn(R.Values[K], Steps, I + 1, V, nil, Name, Scope);
      if R.DeclType <> nil then
        R.Values[K] := Coerce(R.Values[K], R.DeclType.FieldTypes[K],
          Format('field "%s" of %s', [FieldName, R.DeclType.Name]), Scope);
    end;
    Exit;
  end;

  E := TIndexExpr(Step);
  case Slot.Kind of
    vkSparse:
      begin
        if not Last then
          raise EAxonError.CreateAt(TypeError,
            'sparse matrix elements are numbers, so they cannot be indexed or have fields',
            FFile, Step.Line, Step.Col);
        AssignSparseSlot(Slot, E, V, Scope);
      end;
    vkRange, vkArray:
      begin
        if not Last then
          raise EAxonError.CreateAt(TypeError,
            'array elements are numbers, so they cannot be indexed or have fields',
            FFile, Step.Line, Step.Col);
        if Slot.Kind = vkRange then
          Slot := ArrayValue(RangeToArray(AsRange(Slot)));
        if (RootCell <> nil) and (I = 0) then TypeRef := RootCell.TypeRef else TypeRef := nil;
        AssignArraySlot(Slot, E, V, TypeRef, Name, Scope);
      end;
    vkList:
      begin
        if E.Items.Count <> 1 then
          raise EAxonError.CreateAt(IndexError, Format('a list takes one index, got %d',
            [E.Items.Count]), FFile, E.Line, E.Col);
        EvalIndexItem(E.Items[0], Length(AsList(Slot).Items), Scope, Pos, Scalar);
        MakeUnique(Slot);
        L := AsList(Slot);
        if Last then
        begin
          if Scalar then
            L.Items[Pos[0]] := V
          else
          begin
            if (V.Kind <> vkList) or (Length(AsList(V).Items) <> Length(Pos)) then
              raise EAxonError.CreateAt(DimensionError, Format(
                'a selection of %d list elements needs a list of %d values', [Length(Pos), Length(Pos)]),
                FFile, E.Line, E.Col);
            Src := AsList(V);
            for K := 0 to High(Pos) do
              L.Items[Pos[K]] := Src.Items[K];
          end;
        end
        else
        begin
          if not Scalar then
            raise EAxonError.CreateAt(TypeError, 'cannot assign through a list slice',
              FFile, E.Line, E.Col);
          SetIn(L.Items[Pos[0]], Steps, I + 1, V, nil, Name, Scope);
        end;
      end;
    vkDict:
      begin
        if E.Items.Count <> 1 then
          raise EAxonError.CreateAt(IndexError, 'a dictionary takes one key', FFile, E.Line, E.Col);
        Key := Eval(E.Items[0], Scope);
        MakeUnique(Slot);
        D := AsDict(Slot);
        try
          if Last then
            D.Put(Key, V)
          else
          begin
            K := D.Find(Key);
            if K < 0 then
              raise EAxonError.CreateAt(KeyError, Format('key %s not found', [Display(Key, True)]),
                FFile, E.Line, E.Col);
            SetIn(D.Values[K], Steps, I + 1, V, nil, Name, Scope);
          end;
        except
          on X: EAxonError do
          begin
            X.Locate(FFile, E.Line, E.Col);
            raise;
          end;
        end;
      end;
    vkString:
      raise EAxonError.CreateAt(TypeError, 'strings are immutable; build a new string instead',
        FFile, E.Line, E.Col);
  else
    raise EAxonError.CreateAt(TypeError, Format('%s cannot be indexed', [TypeName(Slot)]),
      FFile, E.Line, E.Col);
  end;
end;

{ Assignment to a target that indexes or takes fields: x[i] = v, r.f = v,
  species[2].name = v, and so on to any depth. }
procedure TInterpreter.AssignPath(Target: TExpr; const V: TAxValue; Scope: TScope);
var
  Steps: TArray<TExpr>;
  Node: TExpr;
  Name: string;
  Cell: TVarCell;
begin
  Node := Target;
  while not (Node is TNameExpr) do
  begin
    Steps := [Node] + Steps;
    if Node is TIndexExpr then
      Node := TIndexExpr(Node).Target
    else
      Node := TFieldExpr(Node).Target;
  end;
  Name := TNameExpr(Node).Name;
  Cell := FindCellForWrite(Name, Scope);
  if Cell = nil then
    raise EAxonError.CreateAt(NameError, Format('"%s" is not defined here', [Name]),
      FFile, Node.Line, Node.Col);
  if Cell.ReadOnly then
    raise EAxonError.CreateAt(NameError, Format('"%s" is imported and cannot be modified', [Name]),
      FFile, Node.Line, Node.Col);
  SetIn(Cell.Value, Steps, 0, V, Cell, Name, Scope);
  // The variable's own annotation still holds (for example a record type).
  if (Cell.TypeRef <> nil) and not (Cell.Value.Kind = vkArray) then
    Cell.Value := Coerce(Cell.Value, Cell.TypeRef, Format('variable "%s"', [Name]), Scope);
end;

{ ---------------- records, lists and dictionaries ---------------- }

function IsBuiltinTypeName(const N: string): Boolean;
begin
  Result := (N = 'bool') or (N = 'int') or (N = 'real') or (N = 'complex') or
    (N = 'string') or (N = 'nothing') or (N = 'range') or (N = 'function') or
    (N = 'vector') or (N = 'matrix') or (N = 'sparse') or (N = 'list') or
    (N = 'record') or (N = 'dict') or (N = 'pointer');
end;

{ Checks V against an annotation; declared record types are looked up from
  Scope. }
function TInterpreter.Coerce(const V: TAxValue; T: TTypeRef; const What: string;
  Scope: TScope): TAxValue;
var
  S: TScope;
  C: TVarCell;
begin
  if IsBuiltinTypeName(T.Name) then
    Exit(CoerceToType(V, T, What));
  S := Scope;
  while S <> nil do
  begin
    C := S.Find(T.Name);
    if C <> nil then
    begin
      if C.IsGlobalAlias then
        C := S.Module.Find(T.Name);
      if (C <> nil) and (C.Value.Kind = vkRecordType) then
      begin
        if T.Param <> nil then
          RaiseFmt(TypeError, 'type %s takes no parameter', [T.Name]);
        Exit(CoerceRecord(V, C.Value, What, Scope));
      end;
      Break;
    end;
    S := S.Parent;
  end;
  RaiseFmt(TypeError, 'unknown type "%s"', [T.ToString]);
end;

{ A record of the declared type RTValue: the fields must match exactly, and
  each is checked and widened. }
function TInterpreter.CoerceRecord(const V, RTValue: TAxValue; const What: string;
  Scope: TScope): TAxValue;
var
  RT: TRecordTypeObj;
  R, NewR: TRecordObj;
  K, P: Integer;
begin
  RT := AsRecordType(RTValue);
  if V.Kind <> vkRecord then
    RaiseFmt(TypeError, '%s must be %s, got %s', [What, RT.Name, TypeName(V)]);
  R := AsRecord(V);
  if R.DeclType = RT then
    Exit(V);
  for K := 0 to High(R.Names) do
    if RT.IndexOf(R.Names[K]) < 0 then
      RaiseFmt(FieldError, '%s: record type %s has no field "%s"', [What, RT.Name, R.Names[K]]);
  NewR := TRecordObj.Create;
  Result := NothingValue;
  Result.Kind := vkRecord;
  Result.Obj := NewR;
  NewR.DeclType := RT;
  NewR.DeclRef := RTValue.Obj;
  NewR.Names := Copy(RT.FieldNames);
  SetLength(NewR.Values, Length(RT.FieldNames));
  for K := 0 to High(RT.FieldNames) do
  begin
    P := R.IndexOf(RT.FieldNames[K]);
    if P < 0 then
      RaiseFmt(FieldError, '%s: field "%s" of %s is missing', [What, RT.FieldNames[K], RT.Name]);
    NewR.Values[K] := Coerce(R.Values[P], RT.FieldTypes[K],
      Format('field "%s" of %s', [RT.FieldNames[K], RT.Name]), Scope);
  end;
end;

function TInterpreter.RecordTypeValue(S: TRecordStmt): TAxValue;
var
  RT: TRecordTypeObj;
  F: TFieldDecl;
begin
  RT := TRecordTypeObj.Create;
  RT.Name := S.Name;
  RT.Doc := S.Doc.ToArray;
  for F in S.Fields do
  begin
    RT.FieldNames := RT.FieldNames + [F.Name];
    RT.FieldTypes := RT.FieldTypes + [F.TypeRef];
  end;
  Result := NothingValue;
  Result.Kind := vkRecordType;
  Result.Obj := RT;
end;

{ T(...) for a declared record type: fields by position, then by keyword. }
function TInterpreter.ConstructRecord(const RTValue: TAxValue; E: TCallExpr;
  Scope: TScope): TAxValue;
var
  RT: TRecordTypeObj;
  Names: TArray<string>;
  Values: TAxValues;
  A: TArg;
  NPos, K: Integer;
begin
  RT := AsRecordType(RTValue);
  NPos := 0;
  for A in E.Args do
    case A.Kind of
      akPositional:
        begin
          if NPos >= Length(RT.FieldNames) then
            RaiseFmt(ArgumentError, '%s has %d fields, got more positional arguments',
              [RT.Name, Length(RT.FieldNames)]);
          Names := Names + [RT.FieldNames[NPos]];
          Values := Values + [Eval(A.Value, Scope)];
          Inc(NPos);
        end;
      akKeyword:
        begin
          for K := 0 to High(Names) do
            if Names[K] = A.Name then
              RaiseFmt(ArgumentError, 'field "%s" of %s given twice', [A.Name, RT.Name]);
          Names := Names + [A.Name];
          Values := Values + [Eval(A.Value, Scope)];
        end;
      akPair:
        RaiseError(TypeError, '"=>" pairs are only accepted by dict(...)');
    end;
  Result := CoerceRecord(RecordValue(Names, Values), RTValue,
    Format('constructing %s', [RT.Name]), Scope);
end;

{ dict(k1 => v1, k2 => v2, ...). }
function TInterpreter.BuildDict(E: TCallExpr; Scope: TScope): TAxValue;
var
  D: TDictObj;
  A: TArg;
begin
  D := TDictObj.Create;
  Result := DictValue(D);
  for A in E.Args do
  begin
    if A.Kind <> akPair then
      raise EAxonError.CreateAt(ArgumentError, 'dict(...) takes "key => value" pairs',
        FFile, A.Line, A.Col);
    D.Put(Eval(A.Key, Scope), Eval(A.Value, Scope));
  end;
end;

function TInterpreter.EvalList(E: TListExpr; Scope: TScope): TAxValue;
var
  Items: TAxValues;
  K: Integer;
begin
  SetLength(Items, E.Items.Count);
  for K := 0 to E.Items.Count - 1 do
    Items[K] := Eval(E.Items[K], Scope);
  Result := ListValue(Items);
end;

function TInterpreter.EvalRecord(E: TRecordExpr; Scope: TScope): TAxValue;
var
  Values: TAxValues;
  K: Integer;
begin
  SetLength(Values, E.Values.Count);
  for K := 0 to E.Values.Count - 1 do
    Values[K] := Eval(E.Values[K], Scope);
  Result := RecordValue(E.Names.ToArray, Values);
end;

{ The characters (code points) of a string, each as a string. }
function StringChars(const S: string): TArray<string>;
var
  I, N: Integer;
begin
  SetLength(Result, Length(S));
  N := 0;
  I := 1;
  while I <= Length(S) do
  begin
    if S[I].IsHighSurrogate and (I < Length(S)) then
    begin
      Result[N] := Copy(S, I, 2);
      Inc(I, 2);
    end
    else
    begin
      Result[N] := S[I];
      Inc(I);
    end;
    Inc(N);
  end;
  SetLength(Result, N);
end;

function TInterpreter.IndexString(const T: TAxValue; E: TIndexExpr; Scope: TScope): TAxValue;
var
  S, Direct: string;
  Chars: TArray<string>;
  Pos: TArray<Integer>;
  Scalar: Boolean;
  SB: TStringBuilder;
  K: Integer;
begin
  if E.Items.Count <> 1 then
    raise EAxonError.CreateAt(IndexError, Format('a string takes one index, got %d',
      [E.Items.Count]), FFile, E.Line, E.Col);
  // Without surrogate pairs, characters are UTF-16 units: index directly.
  if not TStringObj(T.Obj).HasSurrogates then
  begin
    S := AsString(T);
    EvalIndexItem(E.Items[0], Length(S), Scope, Pos, Scalar);
    if Scalar then
      Exit(StringValue(S[Pos[0] + 1]));
    SetLength(Direct, Length(Pos));
    for K := 0 to High(Pos) do
      Direct[K + 1] := S[Pos[K] + 1];
    Exit(StringValue(Direct));
  end;
  Chars := StringChars(AsString(T));
  EvalIndexItem(E.Items[0], Length(Chars), Scope, Pos, Scalar);
  if Scalar then
    Exit(StringValue(Chars[Pos[0]]));
  SB := TStringBuilder.Create;
  try
    for K := 0 to High(Pos) do
      SB.Append(Chars[Pos[K]]);
    Result := StringValue(SB.ToString);
  finally
    SB.Free;
  end;
end;

function TInterpreter.IndexDict(const T: TAxValue; E: TIndexExpr; Scope: TScope): TAxValue;
var
  D: TDictObj;
  Key: TAxValue;
  P: Integer;
begin
  if E.Items.Count <> 1 then
    raise EAxonError.CreateAt(IndexError, 'a dictionary takes one key', FFile, E.Line, E.Col);
  D := AsDict(T);
  Key := Eval(E.Items[0], Scope);
  try
    P := D.Find(Key);
  except
    on X: EAxonError do
    begin
      X.Locate(FFile, E.Line, E.Col);
      raise;
    end;
  end;
  if P < 0 then
    raise EAxonError.CreateAt(KeyError, Format('key %s not found', [Display(Key, True)]),
      FFile, E.Line, E.Col);
  Result := D.Values[P];
end;

function TInterpreter.Eval(E: TExpr; Scope: TScope): TAxValue;
var
  C: TClass;
  Vals: TAxValues;
begin
  C := E.ClassType;
  if C = TIntLit then
    Result := IntValue(TIntLit(E).Value)
  else if C = TNameExpr then
    Result := Lookup(TNameExpr(E).Name, Scope, E)
  else if C = TBinaryExpr then
  begin
    if TBinaryExpr(E).Op in [tkAnd, tkOr] then
      Result := EvalLogical(TBinaryExpr(E), Scope)
    else
      Result := BinaryOp(TBinaryExpr(E).Op, Eval(TBinaryExpr(E).Left, Scope),
        Eval(TBinaryExpr(E).Right, Scope));
  end
  else if C = TRealLit then
    Result := RealValue(TRealLit(E).Value)
  else if C = TCallExpr then
  begin
    Vals := EvalCallMulti(TCallExpr(E), Scope);
    if Length(Vals) <> 1 then
      raise EAxonError.CreateAt(ArgumentError,
        Format('the call returns %d values where one is expected; unpack them with [a, b, ...] = ...',
          [Length(Vals)]), FFile, E.Line, E.Col);
    Result := Vals[0];
  end
  else if C = TUnaryExpr then
    Result := UnaryOp(TUnaryExpr(E).Op, Eval(TUnaryExpr(E).Operand, Scope))
  else if C = TStringLit then
    Result := StringValue(TStringLit(E).Value)
  else if C = TImagLit then
    Result := ComplexValue2(0, TImagLit(E).Value)
  else if C = TBoolLit then
    Result := BoolValue(TBoolLit(E).Value)
  else if C = TNothingLit then
    Result := NothingValue
  else if C = TRangeExpr then
    Result := MakeRange(TRangeExpr(E), Scope)
  else if C = TLambdaExpr then
    Result := FunctionValue(TLambdaExpr(E).Func, Scope, True)
  else if C = TFieldExpr then
    Result := EvalField(TFieldExpr(E), Scope)
  else if C = TIndexExpr then
    Result := EvalIndex(TIndexExpr(E), Scope)
  else if C = TEndExpr then
  begin
    if FEndStack.Count = 0 then
      NotYet('"end" in this kind of index', 'M6', E);
    Result := IntValue(FEndStack.Last);
  end
  else if C = TMatrixExpr then
    Result := EvalMatrix(TMatrixExpr(E), Scope)
  else if C = TColonExpr then
    NotYet('":" outside an index', 'M6', E)
  else if C = TListExpr then
    Result := EvalList(TListExpr(E), Scope)
  else if C = TRecordExpr then
    Result := EvalRecord(TRecordExpr(E), Scope)
  else
    NotYet(E.ClassName, 'a later milestone', E);
end;

{ ---------------- modules ---------------- }

constructor TModuleObj.Create(const AName: string);
begin
  inherited Create;
  Name := AName;
  ExportNames := TList<string>.Create;
  Children := TDictionary<string, TAxValue>.Create;
end;

destructor TModuleObj.Destroy;
begin
  ExportNames.Free;
  Children.Free;
  if Globals <> nil then
    Globals.Release;
  inherited;
end;

function ModuleValue(M: TModuleObj): TAxValue;
begin
  Result := NothingValue;
  Result.Kind := vkModule;
  Result.Obj := M;
end;

{ The file for module Name, searched in the importing file's directory, then
  the packages of the nearest package.toml, then the standard library. }
function TInterpreter.ResolveModule(const Name: string): string;
var
  Dir, First, Rest, Root, StdLib: string;
  Manifest: TManifest;
  P: Integer;
begin
  Dir := ExtractFileDir(FCurrentPath);
  Result := ModuleFileIn(Dir, Name);
  if Result <> '' then
    Exit;

  Manifest := FindManifest(Dir);
  if Manifest <> nil then
  begin
    P := Pos('.', Name);
    if P > 0 then
    begin
      First := Copy(Name, 1, P - 1);
      Rest := Copy(Name, P + 1, MaxInt);
    end
    else
    begin
      First := Name;
      Rest := Name;   // a package's main module is named after the package
    end;
    if Manifest.Dependencies.TryGetValue(First, Root) then
    begin
      Result := ModuleFileIn(Root, Rest);
      if Result <> '' then
        Exit;
    end;
  end;

  StdLib := GetEnvironmentVariable('AXON_STDLIB');
  if StdLib = '' then
    StdLib := ExtractFilePath(ParamStr(0)) + 'stdlib';
  Result := ModuleFileIn(StdLib, Name);
end;

{ Loads module Name once per program and returns it. }
function TInterpreter.LoadModule(const Name: string; Node: TNode): TAxValue;
var
  Path, Key, Display, Chain, SavedFile, SavedPath: string;
  M: TModuleObj;
  Prog: TProgram;
  S: TStmt;
  I, Start: Integer;
  Definer: TModuleDefiner;
  NativeDoc: TArray<string>;
begin
  Path := ResolveModule(Name);
  if Path = '' then
  begin
    // No file: a core module written in Delphi (io, graphics), if any.
    if FindNativeModule(Name, Definer, NativeDoc) then
    begin
      Key := 'native:' + Name;
      if FModules.TryGetValue(Key, Result) then
        Exit;
      M := TModuleObj.Create(Name);
      Result := ModuleValue(M);
      M.Doc := NativeDoc;
      M.Globals := TScope.Create(FPrelude, rkModule);
      Definer(
        procedure(Fn: string; V: TAxValue)
        begin
          M.Globals.Define(Fn).Value := V;
          M.ExportNames.Add(Fn);
        end);
      FModules.Add(Key, Result);
      Exit;
    end;
    raise EAxonError.CreateAt(ImportError, Format('module "%s" not found', [Name]),
      FFile, Node.Line, Node.Col);
  end;
  Key := FileKey(Path);
  if FModules.TryGetValue(Key, Result) then
  begin
    M := TModuleObj(Result.Obj);
    if M.Loading then
    begin
      // An import cycle: report the chain from the module's first appearance.
      Start := FLoadStack.IndexOf(M.Name);
      Chain := '';
      for I := Start to FLoadStack.Count - 1 do
        Chain := Chain + FLoadStack[I] + ' -> ';
      raise EAxonError.CreateAt(ImportError, 'import cycle: ' + Chain + M.Name,
        FFile, Node.Line, Node.Col);
    end;
    Exit;
  end;

  M := TModuleObj.Create(Name);
  Result := ModuleValue(M);
  M.FilePath := Path;
  M.Loading := True;
  Display := DisplayPath(Path);
  FModules.Add(Key, Result);
  FLoadStack.Add(Name);
  SavedFile := FFile;
  SavedPath := FCurrentPath;
  try
    try
      Prog := ParseSource(LoadSourceFile(Path), Display);
      FPrograms.Add(Prog);
      M.Doc := Prog.Doc.ToArray;
      for S in Prog.Body do
        if (S is TFunctionStmt) and TFunctionStmt(S).Func.Exported then
          M.ExportNames.Add(TFunctionStmt(S).Func.Name)
        else if (S is TRecordStmt) and TRecordStmt(S).Exported then
          M.ExportNames.Add(TRecordStmt(S).Name);
      M.Globals := TScope.Create(FPrelude, rkModule);
      FFile := Display;
      FCurrentPath := Path;
      Hoist(Prog, M.Globals);
      for S in Prog.Body do
        ExecStmt(S, M.Globals);
      M.Loading := False;
    except
      on E: Exception do
      begin
        // A module that failed to load is forgotten, so it is not half-used.
        FModules.Remove(Key);
        // Close the module's trace frame, so the import site is reported too.
        if E is EAxonError then
          EAxonError(E).LeaveFunction('');
        raise;
      end;
    end;
  finally
    FFile := SavedFile;
    FCurrentPath := SavedPath;
    FLoadStack.Delete(FLoadStack.Count - 1);
  end;
end;

{ Binds an imported value: read-only in the importing scope. }
procedure BindImport(Root: TScope; const Name: string; const V: TAxValue);
var
  C: TVarCell;
begin
  C := Root.Define(Name);
  C.Value := V;
  C.TypeRef := nil;
  C.IsGlobalAlias := False;
  C.ReadOnly := True;
end;

procedure TInterpreter.ExecImport(S: TImportStmt; Scope: TScope);
var
  ModV, NsV, ChildV: TAxValue;
  M, Ns, Child: TModuleObj;
  Root: TScope;
  Parts: TArray<string>;
  Name: string;
  C: TVarCell;
  I: Integer;
begin
  ModV := LoadModule(S.Module, S);
  M := TModuleObj(ModV.Obj);
  Root := FunctionRootOf(Scope);

  if S.IsFrom then
  begin
    for Name in S.Names do
    begin
      if not M.ExportNames.Contains(Name) then
        raise EAxonError.CreateAt(ImportError, Format('module "%s" does not export "%s"',
          [S.Module, Name]), FFile, S.Line, S.Col);
      BindImport(Root, Name, M.Globals.Find(Name).Value);
    end;
    Exit;
  end;

  if S.Alias <> '' then
  begin
    BindImport(Root, S.Alias, ModV);
    Exit;
  end;

  Parts := S.Module.Split(['.']);
  if Length(Parts) = 1 then
  begin
    BindImport(Root, Parts[0], ModV);
    Exit;
  end;

  // import a.b.c binds a, through which the module is a.b.c.
  C := Root.Find(Parts[0]);
  if (C <> nil) and (C.Value.Kind = vkModule) then
    NsV := C.Value
  else
    NsV := ModuleValue(TModuleObj.Create(Parts[0]));
  Ns := TModuleObj(NsV.Obj);
  for I := 1 to High(Parts) - 1 do
  begin
    if not (Ns.Children.TryGetValue(Parts[I], ChildV) and (ChildV.Kind = vkModule)) then
    begin
      ChildV := ModuleValue(TModuleObj.Create(Ns.Name + '.' + Parts[I]));
      Ns.Children.AddOrSetValue(Parts[I], ChildV);
    end;
    Child := TModuleObj(ChildV.Obj);
    Ns := Child;
  end;
  Ns.Children.AddOrSetValue(Parts[High(Parts)], ModV);
  BindImport(Root, Parts[0], NsV);
end;

{ m.name: a sub-module, or an exported function or record type. }
function TInterpreter.ModuleMember(const V: TAxValue; E: TFieldExpr): TAxValue;
var
  M: TModuleObj;
begin
  M := TModuleObj(V.Obj);
  if M.Children.TryGetValue(E.Name, Result) then
    Exit;
  if (M.Globals <> nil) and M.ExportNames.Contains(E.Name) then
    Exit(M.Globals.Find(E.Name).Value);
  raise EAxonError.CreateAt(ImportError, Format('module "%s" has no exported name "%s"',
    [M.Name, E.Name]), FFile, E.Line, E.Col);
end;

{ __native_library(name): test hook for M8, the file a native library
  resolves to through the nearest package.toml, or nothing. }
function TInterpreter.NativeLibraryHook(E: TCallExpr; Scope: TScope): TAxValue;
var
  V: TAxValue;
  Manifest: TManifest;
  Path: string;
begin
  if (E.Args.Count <> 1) or (E.Args[0].Kind <> akPositional) then
    RaiseError(ArgumentError, '__native_library takes one library name');
  V := Eval(E.Args[0].Value, Scope);
  if V.Kind <> vkString then
    RaiseError(TypeError, '__native_library needs a string');
  Manifest := FindManifest(ExtractFileDir(FCurrentPath));
  Path := '';
  if Manifest <> nil then
    Path := Manifest.NativePath(AsString(V));
  if Path = '' then
    Result := NothingValue
  else
    Result := StringValue(DisplayPath(Path));
end;

{ ---------------- sparse indexing ---------------- }

{ S[i, j] is an element; other two-index selections are sparse submatrices;
  a single non-scalar index gives a dense vector. }
function TInterpreter.IndexSparse(const T: TAxValue; E: TIndexExpr; Scope: TScope): TAxValue;
var
  S: TSparseObj;
  Sel: TSelection;
  Pos: TArray<Integer>;
  Values: TAxValues;
  RI, CI, K, P: Integer;
  TI, TJ: TArray<Integer>;
  TV: TArray<TComplex>;
begin
  S := AsSparse(T);
  Sel := ResolveSelection(S.Rows, S.Cols, False, E, Scope);
  if not Sel.Two then
  begin
    if Sel.ScalarA then
      Exit(S.Get(Sel.Lin[0] mod S.Rows, Sel.Lin[0] div S.Rows));
    SetLength(Values, Length(Sel.Lin));
    for K := 0 to High(Sel.Lin) do
      Values[K] := S.Get(Sel.Lin[K] mod S.Rows, Sel.Lin[K] div S.Rows);
    if S.IsComplex then
      Exit(BuildArray(Length(Values), 1, True, Values, etComplex));
    Exit(BuildArray(Length(Values), 1, True, Values, etReal));
  end;
  if Sel.ScalarA and Sel.ScalarB then
    Exit(S.Get(Sel.RowPos[0], Sel.ColPos[0]));
  Pos := nil;
  for CI := 0 to High(Sel.ColPos) do
    for RI := 0 to High(Sel.RowPos) do
    begin
      P := S.Find(Sel.RowPos[RI], Sel.ColPos[CI]);
      if P >= 0 then
      begin
        TI := TI + [RI];
        TJ := TJ + [CI];
        TV := TV + [S.V[P]];
      end;
    end;
  Result := SparseValue(FromTriplets(Length(Sel.RowPos), Length(Sel.ColPos), TI, TJ, TV,
    S.IsComplex));
end;

{ S[idx] = V for a sparse matrix in Slot: rebuilt with the new values;
  assigned zeros disappear and a complex value makes S complex. }
procedure TInterpreter.AssignSparseSlot(var Slot: TAxValue; Target: TIndexExpr;
  const V: TAxValue; Scope: TScope);
var
  S: TSparseObj;
  Sel: TSelection;
  Pos: TArray<Integer>;
  Src: TArrayObj;
  SrcHolder: TAxValue;
  N, K, C, P, Idx, SelRows, SelCols, Count: Integer;
  OneDim, Ok, Cplx: Boolean;
  TI, TJ: TArray<Integer>;
  TV: TArray<TComplex>;
  Where: TDictionary<Int64, Integer>;
  Key: Int64;
  X: TComplex;
begin
  S := AsSparse(Slot);
  Sel := ResolveSelection(S.Rows, S.Cols, False, Target, Scope);
  S := AsSparse(Slot);
  Pos := SelectionPositions(Sel, S.Rows);
  N := Length(Pos);
  OneDim := not Sel.Two or Sel.ScalarA or Sel.ScalarB;
  SelRows := Length(Sel.RowPos);
  SelCols := Length(Sel.ColPos);

  Src := nil;
  if V.Kind in [vkArray, vkRange, vkSparse] then
  begin
    SrcHolder := Densify(V);
    if SrcHolder.Kind = vkRange then
      SrcHolder := ArrayValue(RangeToArray(AsRange(SrcHolder)));
    Src := AsArray(SrcHolder);
    if OneDim then
      Ok := (Src.Count = N) and (Src.IsVector or (Src.Rows = 1) or (Src.Cols = 1))
    else
      Ok := (Src.Rows = SelRows) and (Src.Cols = SelCols);
    if not Ok then
      raise EAxonError.CreateAt(DimensionError, Format(
        'cannot assign %d elements to a selection of %d', [Src.Count, N]),
        FFile, Target.Line, Target.Col);
    Cplx := S.IsComplex or (Src.ElemType = etComplex);
  end
  else if NumRank(V) >= 0 then
    Cplx := S.IsComplex or (V.Kind = vkComplex)
  else
    raise EAxonError.CreateAt(TypeError, Format('cannot store %s in a sparse matrix', [TypeName(V)]),
      FFile, Target.Line, Target.Col);

  // One nonzero value over an existing entry is written in place, after
  // copy-on-write. Values are stored as complex either way, so a complex
  // value only sets the flag.
  if (N = 1) and (Src = nil) then
  begin
    X := ToComplex(V);
    P := S.Find(Pos[0] mod S.Rows, Pos[0] div S.Rows);
    if (P >= 0) and ((X.Re <> 0) or (X.Im <> 0)) then
    begin
      MakeUnique(Slot);
      S := AsSparse(Slot);
      S.V[P] := X;
      if Cplx then
        S.IsComplex := True;
      Exit;
    end;
  end;

  // Otherwise the matrix is rebuilt: the existing entries, then the new
  // values on top (zeros are dropped by FromTriplets).
  SetLength(TI, S.Nnz + N);
  SetLength(TJ, S.Nnz + N);
  SetLength(TV, S.Nnz + N);
  Count := 0;
  Where := TDictionary<Int64, Integer>.Create;
  try
    for C := 0 to S.Cols - 1 do
      for P := S.ColPtr[C] to S.ColPtr[C + 1] - 1 do
      begin
        Where.Add(Int64(C) * S.Rows + S.RowIdx[P], Count);
        TI[Count] := S.RowIdx[P];
        TJ[Count] := C;
        TV[Count] := S.V[P];
        Inc(Count);
      end;
    for K := 0 to N - 1 do
    begin
      if Src <> nil then X := ToComplex(Src.Get(K)) else X := ToComplex(V);
      Key := Pos[K];
      if Where.TryGetValue(Key, Idx) then
        TV[Idx] := X
      else
      begin
        Where.Add(Key, Count);
        TI[Count] := Pos[K] mod S.Rows;
        TJ[Count] := Pos[K] div S.Rows;
        TV[Count] := X;
        Inc(Count);
      end;
    end;
  finally
    Where.Free;
  end;
  SetLength(TI, Count);
  SetLength(TJ, Count);
  SetLength(TV, Count);
  Slot := SparseValue(FromTriplets(S.Rows, S.Cols, TI, TJ, TV, Cplx));
end;

{ ---------------- foreign functions ---------------- }

{ An extern block: its named C types go into the module's alias table, and
  each function is bound in the outermost scope of the enclosing function or
  module. The library itself loads at the first call. }
procedure TInterpreter.ExecExtern(S: TExternStmt; Scope: TScope);
var
  Item: TExternItem;
  Root, Module: TScope;
  Cell: TVarCell;
begin
  Root := FunctionRootOf(Scope);
  Module := Scope.Module;
  if Module.CTypes = nil then
    Module.CTypes := TCTypeAliases.Create;
  for Item in S.Items do
    try
      if Item is TExternType then
        Module.CTypes.AddOrSetValue(TExternType(Item).Name,
          ResolveCType(TExternType(Item).CType, Module.CTypes,
            Format('extern type %s', [TExternType(Item).Name])))
      else
      begin
        Cell := Root.Define(TExternFunc(Item).Name);
        if Cell.ReadOnly then
          RaiseFmt(NameError, '"%s" is imported and cannot be redefined', [TExternFunc(Item).Name]);
        Cell.TypeRef := nil;
        Cell.IsGlobalAlias := False;
        Cell.Value := ExternFunctionValue(TExternFunc(Item), S.LibName,
          ExtractFileDir(FCurrentPath), Module.CTypes);
      end;
    except
      on E: EAxonError do
      begin
        E.Locate(FFile, Item.Line, Item.Col);
        raise;
      end;
    end;
end;

function TInterpreter.CallValue(const Fn: TAxValue; const Args: TAxValues): TAxValue;
var
  Vals, RefOut: TAxValues;
  B: TBuiltinObj;
begin
  case Fn.Kind of
    vkFunction:
      begin
        Vals := Invoke(TFunctionObj(Fn.Obj), Args, nil, nil);
        if Length(Vals) = 0 then Result := NothingValue else Result := Vals[0];
      end;
    vkBuiltin:
      begin
        B := AsBuiltin(Fn);
        if (Length(Args) < B.MinArgs) or ((B.MaxArgs >= 0) and (Length(Args) > B.MaxArgs)) then
          RaiseFmt(ArgumentError, '%s cannot take %d argument(s)', [B.Name, Length(Args)]);
        if Assigned(B.MultiFn) then
        begin
          Vals := B.MultiFn(Args);
          if Length(Vals) = 0 then Result := NothingValue else Result := Vals[0];
        end
        else
          Result := B.Fn(Args);
      end;
    vkExtern:
      Result := CallExtern(TExternFuncObj(Fn.Obj), Args, RefOut,
        function(const F: TAxValue; const A: TAxValues): TAxValue
        begin
          Result := CallValue(F, A);
        end);
  else
    RaiseFmt(TypeError, '%s is not callable', [TypeName(Fn)]);
    Result := NothingValue;
  end;
end;

{ A call to an extern function. ref arguments must be variables, which get
  the new values afterwards; an array variable passed to a ptr parameter is
  made unique first, so native writes reach only that variable. }
function TInterpreter.CallExternValue(F: TExternFuncObj; E: TCallExpr; Scope: TScope): TAxValue;
var
  Args, RefOut: TAxValues;
  RefNames: TArray<string>;
  K: Integer;
  A: TArg;
  Cell: TVarCell;
  Name: string;
begin
  if E.Args.Count <> Length(F.Params) then
    RaiseFmt(ArgumentError, '%s takes %d argument(s), got %d',
      [F.Name, Length(F.Params), E.Args.Count]);
  SetLength(Args, E.Args.Count);
  SetLength(RefNames, E.Args.Count);
  for K := 0 to E.Args.Count - 1 do
  begin
    A := E.Args[K];
    if A.Kind <> akPositional then
      RaiseFmt(ArgumentError, 'extern function %s takes positional arguments only', [F.Name]);
    case F.Params[K].Kind of
      ckRef:
        begin
          if not (A.Value is TNameExpr) then
            RaiseFmt(TypeError, 'argument "%s" of %s is a ref, so it must be a variable',
              [F.ParamNames[K], F.Name]);
          RefNames[K] := TNameExpr(A.Value).Name;
          Args[K] := Eval(A.Value, Scope);
        end;
      ckPtr:
        begin
          Cell := nil;
          if A.Value is TNameExpr then
            Cell := FindCellForWrite(TNameExpr(A.Value).Name, Scope);
          if (Cell <> nil) and (Cell.Value.Kind in [vkArray, vkRange]) then
          begin
            if Cell.ReadOnly then
              RaiseFmt(NameError, '"%s" is imported and cannot be passed to a ptr parameter',
                [TNameExpr(A.Value).Name]);
            if Cell.Value.Kind = vkRange then
              Cell.Value := ArrayValue(RangeToArray(AsRange(Cell.Value)));
            MakeUnique(Cell.Value);
            Args[K] := Cell.Value;
          end
          else
            Args[K] := Eval(A.Value, Scope);
        end;
    else
      Args[K] := Eval(A.Value, Scope);
    end;
  end;
  Result := CallExtern(F, Args, RefOut,
    function(const Fn: TAxValue; const CallArgs: TAxValues): TAxValue
    begin
      Result := CallValue(Fn, CallArgs);
    end);
  for K := 0 to High(RefNames) do
    if RefNames[K] <> '' then
    begin
      Name := RefNames[K];
      Assign(Name, RefOut[K], Scope);
    end;
end;

{ ---------------- entry points ---------------- }

procedure TInterpreter.Hoist(P: TProgram);
begin
  Hoist(P, FGlobals);
end;

procedure TInterpreter.Hoist(P: TProgram; Globals: TScope);
var
  S: TStmt;
  Decl: TFunctionDecl;
begin
  // Named functions at the top level are bound before any statement runs.
  // Later definitions of the same name replace earlier ones.
  for S in P.Body do
    if S is TFunctionStmt then
    begin
      Decl := TFunctionStmt(S).Func;
      Globals.Define(Decl.Name).Value := FunctionValue(Decl, Globals, False);
      FHoisted.AddOrSetValue(Decl, True);
    end
    else if S is TRecordStmt then
    begin
      Globals.Define(TRecordStmt(S).Name).Value := RecordTypeValue(TRecordStmt(S));
      FHoistedRecords.AddOrSetValue(TRecordStmt(S), True);
    end
    else if S is TExternStmt then
    begin
      ExecExtern(TExternStmt(S), Globals);
      FHoistedExterns.AddOrSetValue(TExternStmt(S), True);
    end;
end;

procedure TInterpreter.Run(P: TProgram);
var
  S: TStmt;
  M: TModuleObj;
  Key: string;
begin
  // Register the main program as a module being loaded, so that a module
  // importing it is reported as a cycle.
  M := TModuleObj.Create(ChangeFileExt(ExtractFileName(FCurrentPath), ''));
  M.FilePath := FCurrentPath;
  M.Loading := True;
  M.Globals := FGlobals;
  FGlobals.AddRef;
  Key := FileKey(FCurrentPath);
  FModules.AddOrSetValue(Key, ModuleValue(M));
  FLoadStack.Add(M.Name);
  Hoist(P);
  for S in P.Body do
    ExecStmt(S, FGlobals);
  M.Loading := False;
  // The program ran to its end: the functions registered with atexit.
  RunAtExit;
end;

procedure TInterpreter.RunInSession(P: TProgram; const FileName: string);
var
  S: TStmt;
  SavedFile, SavedPath: string;
begin
  SavedFile := FFile;
  SavedPath := FCurrentPath;
  FFile := FileName;
  FCurrentPath := TPath.GetFullPath(FileName);
  try
    Hoist(P);
    for S in P.Body do
      ExecStmt(S, FGlobals);
  finally
    FFile := SavedFile;
    FCurrentPath := SavedPath;
  end;
end;

function TInterpreter.ExecTopLevel(S: TStmt; out Shown: TAxValues;
  out ShownNames: TArray<string>): Boolean;
var
  T: TExpr;
  Name: string;
begin
  Shown := nil;
  ShownNames := nil;
  if S is TExprStmt then
  begin
    try
      Shown := EvalMulti(TExprStmt(S).Expr, FGlobals);
    except
      on E: EAxonError do
      begin
        E.Locate(FFile, S.Line, S.Col);
        raise;
      end;
    end;
    // A lone nothing is not displayed.
    Result := not ((Length(Shown) = 1) and (Shown[0].Kind = vkNothing));
    Exit;
  end;
  ExecStmt(S, FGlobals);
  // Assignments to plain names show "name = value", one line per name.
  if (S is TAssignStmt) and (TAssignStmt(S).Target is TNameExpr) then
    ShownNames := [TNameExpr(TAssignStmt(S).Target).Name]
  else if S is TDestructureStmt then
    for T in TDestructureStmt(S).Targets do
      if T is TNameExpr then
        ShownNames := ShownNames + [TNameExpr(T).Name];
  for Name in ShownNames do
    Shown := Shown + [Lookup(Name, FGlobals, S)];
  Result := Length(ShownNames) > 0;
end;

end.
