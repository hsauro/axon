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
  Axon.Ast, Axon.Values;

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
  end;

  TScope = class
  private
    FRefCount: Integer;
    FVars: TObjectDictionary<string, TVarCell>;   // created on first use
  public
    Parent: TScope;
    Root: TRootKind;
    Module: TScope;           // the module root this scope belongs to
    constructor Create(AParent: TScope; ARoot: TRootKind);
    destructor Destroy; override;
    procedure AddRef; inline;
    procedure Release;
    function Find(const Name: string): TVarCell; inline;
    function Define(const Name: string): TVarCell;
  end;

  { A function written in Axon: its declaration and the scope it closes over. }
  TFunctionObj = class(TCallableObj)
  public
    Decl: TFunctionDecl;
    Closure: TScope;
    IsClosure: Boolean;       // lambda or nested function: rule 5 reaches outward
    constructor Create(ADecl: TFunctionDecl; AClosure: TScope; AIsClosure: Boolean);
    destructor Destroy; override;
  end;

  TSignal = (sigNone, sigBreak, sigContinue, sigReturn);

  TInterpreter = class
  private
    FPrelude: TScope;
    FGlobals: TScope;
    FFile: string;
    FCallDepth: Integer;
    FReturn: TAxValues;                       // values of the last `return`
    FHoisted: TDictionary<TFunctionDecl, Boolean>;
    FEndStack: TList<Int64>;                  // values of `end` in nested indexing
    procedure NotYet(const What, Milestone: string; Node: TNode);
    function FunctionValue(Decl: TFunctionDecl; Scope: TScope; IsClosure: Boolean): TAxValue;
    function FunctionRootOf(Scope: TScope): TScope;
    function Lookup(const Name: string; Scope: TScope; Node: TNode): TAxValue;
    procedure Assign(const Name: string; const V: TAxValue; Scope: TScope);
    procedure Store(Cell: TVarCell; const V: TAxValue; const Name: string);
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
    function MakeRange(E: TRangeExpr; Scope: TScope): TAxValue;
    function EvalLogical(E: TBinaryExpr; Scope: TScope): TAxValue;
    function EvalMulti(E: TExpr; Scope: TScope): TAxValues;
    function EvalCallMulti(E: TCallExpr; Scope: TScope): TAxValues;
    function CallBuiltin(B: TBuiltinObj; E: TCallExpr; Scope: TScope): TAxValue;
    function Invoke(F: TFunctionObj; const Pos: TAxValues;
      const KwNames: TArray<string>; const KwValues: TAxValues): TAxValues;
  public
    constructor Create(const FileName: string);
    destructor Destroy; override;
    function Eval(E: TExpr; Scope: TScope): TAxValue;
    { Binds a program's top-level named functions, so they can be called
      before their definition. Run does this itself. }
    procedure Hoist(P: TProgram);
    procedure Run(P: TProgram);
    { Runs one top-level statement (the REPL). Shown receives the values to
      display: an expression's values, or the new value of an assigned name
      (then ShownName is that name). }
    function ExecTopLevel(S: TStmt; out Shown: TAxValues; out ShownName: string): Boolean;
  end;

const
  MaxCallDepth = 10000;

{ Checks V against an annotation and widens it along bool -> int -> real ->
  complex. Raises TypeError naming What (for example 'argument "x" of f'). }
function CoerceToType(const V: TAxValue; T: TTypeRef; const What: string): TAxValue;

implementation

uses
  System.Math,
  Axon.Errors, Axon.Tokens, Axon.Ops, Axon.Builtins, Axon.Complex;

{ ===================== type annotations ===================== }

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
    Ok := V.Kind in [vkBuiltin, vkFunction]
  else if (N = 'vector') or (N = 'matrix') or (N = 'sparse') or (N = 'list') or
          (N = 'record') or (N = 'dict') then
    Ok := False   // no values of these types exist before M6/M7
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
end;

destructor TFunctionObj.Destroy;
begin
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
  FGlobals := TScope.Create(FPrelude, rkModule);
  FHoisted := TDictionary<TFunctionDecl, Boolean>.Create;
  FEndStack := TList<Int64>.Create;
end;

destructor TInterpreter.Destroy;
begin
  FHoisted.Free;
  FEndStack.Free;
  // Functions stored in the globals refer back to them, so the globals may
  // stay alive in a cycle; that memory goes when the process ends.
  FGlobals.Release;
  FPrelude.Release;
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
begin
  Result := NothingValue;
  Result.Kind := vkFunction;
  Result.Obj := TFunctionObj.Create(Decl, Scope, IsClosure);
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

procedure TInterpreter.Store(Cell: TVarCell; const V: TAxValue; const Name: string);
begin
  if Cell.TypeRef <> nil then
    Cell.Value := CoerceToType(V, Cell.TypeRef, Format('variable "%s"', [Name]))
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
      Store(C, V, Name);
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
  Store(FirstRoot.Define(Name), V, Name);
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
  IterScope: TScope;
  Sig: TSignal;
begin
  Result := sigNone;
  Iter := Eval(S.Iter, Scope);
  if Iter.Kind <> vkRange then
    RaiseFmt(TypeError, 'cannot iterate over %s', [TypeName(Iter)]);
  R := AsRange(Iter);
  K := 0;
  while K < R.Count do
  begin
    // A fresh scope, and so a fresh binding of the loop variable, per iteration.
    IterScope := TScope.Create(Scope, rkNone);
    try
      IterScope.Define(S.VarName).Value := R.ItemAt(K);
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
    C.IsGlobalAlias := False;
    C.TypeRef := S.TypeRef;
    Store(C, V, S.Name);
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
    Store(ModCell, V, S.Name);
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
  for I := 0 to S.Targets.Count - 1 do
    if not (S.Targets[I] is TNameExpr) then
      NotYet('assignment to an index or field', 'M6', S.Targets[I]);
  Values := EvalMulti(S.Value, Scope);
  if Length(Values) <> S.Targets.Count then
    RaiseFmt(ArgumentError, 'cannot unpack %d value(s) into %d targets',
      [Length(Values), S.Targets.Count]);
  for I := 0 to S.Targets.Count - 1 do
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
      if not (Target is TNameExpr) then
        NotYet('assignment to an index or field', 'M6', S);
      V := Eval(TAssignStmt(S).Value, Scope);
      if TAssignStmt(S).TypeRef <> nil then
      begin
        // x: T = e declares x in the current scope.
        Cell := Scope.Define(TNameExpr(Target).Name);
        Cell.IsGlobalAlias := False;
        Cell.TypeRef := TAssignStmt(S).TypeRef;
        Store(Cell, V, TNameExpr(Target).Name);
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
        Store(Cell, V, Decl.Name);
      end;
    end
    else if C = TDeclStmt then
      ExecDecl(TDeclStmt(S), Scope)
    else if C = TDestructureStmt then
      ExecDestructure(TDestructureStmt(S), Scope)
    else if C = TTryStmt then
      Result := ExecTry(TTryStmt(S), Scope)
    else if C = TRecordStmt then
      NotYet('record declaration', 'M7', S)
    else if C = TImportStmt then
      NotYet('import', 'M8', S)
    else if C = TExternStmt then
      NotYet('extern', 'M9', S)
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

function TInterpreter.CallBuiltin(B: TBuiltinObj; E: TCallExpr; Scope: TScope): TAxValue;
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
      NotYet('"=>" pairs', 'M7', E.Args[I]);
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
  Result := B.Fn(Args);
end;

function DescribeFunction(F: TFunctionObj): string;
begin
  if F.Name <> '' then
    Result := F.Name
  else
    Result := 'anonymous function';
end;

{ Binds arguments (reference, "Argument binding"), runs the body and returns
  its values. }
function TInterpreter.Invoke(F: TFunctionObj; const Pos: TAxValues;
  const KwNames: TArray<string>; const KwValues: TAxValues): TAxValues;
var
  D: TFunctionDecl;
  P: TParam;
  Fn: string;
  NPos, I, J, K: Integer;
  Found: Boolean;
  Supplied: TArray<Integer>;   // per keyword parameter: index into KwValues, or -1
  Root: TScope;
  Kind: TRootKind;
  V: TAxValue;
  Cell: TVarCell;
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

  // 1. Positional arguments.
  NPos := 0;
  for P in D.Params do
    if not P.IsKeyword then
      Inc(NPos);
  if Length(Pos) <> NPos then
    RaiseFmt(ArgumentError, '%s takes %d positional argument(s), got %d',
      [Fn, NPos, Length(Pos)]);

  Inc(FCallDepth);
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
      for I := 0 to D.Params.Count - 1 do
      begin
        P := D.Params[I];
        if not P.IsKeyword then
        begin
          V := Pos[J];
          Inc(J);
        end
        else if Supplied[I] >= 0 then
          V := KwValues[Supplied[I]]
        else
          V := Eval(P.Default, Root);
        if P.TypeRef <> nil then
          V := CoerceToType(V, P.TypeRef, Format('argument "%s" of %s', [P.Name, Fn]));
        Cell := Root.Define(P.Name);
        Cell.TypeRef := P.TypeRef;
        Cell.Value := V;
      end;

      if ExecBody(D.Body, Root) = sigReturn then
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
      Result[0] := CoerceToType(Result[0], D.ReturnType,
        Format('the return value of %s', [Fn]));
    end;
  finally
    Dec(FCallDepth);
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
        Result := [CallBuiltin(AsBuiltin(Callee), E, Scope)];
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
              akPair: NotYet('"=>" pairs', 'M7', A);
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
  R: TRangeObj;
  N: Double;
  Span: Int64;

  procedure CheckBound(const V: TAxValue);
  begin
    if (NumRank(V) < 0) or (V.Kind = vkComplex) then
      RaiseFmt(TypeError, 'range bounds and step must be real numbers, got %s',
        [TypeName(V)]);
  end;

  function AsInt(const V: TAxValue): Int64;
  begin
    if V.Kind = vkBool then Result := Ord(V.B) else Result := V.I;
  end;

begin
  A := Eval(E.Start, Scope);
  if E.Step <> nil then
    H := Eval(E.Step, Scope)
  else
    H := IntValue(1);
  B := Eval(E.Stop, Scope);
  CheckBound(A);
  CheckBound(H);
  CheckBound(B);

  R := TRangeObj.Create;
  Result := NothingValue;
  Result.Kind := vkRange;
  Result.Obj := R;
  R.IsInt := (NumRank(A) <= 1) and (NumRank(H) <= 1) and (NumRank(B) <= 1);
  if R.IsInt then
  begin
    R.IStart := AsInt(A);
    R.IStep := AsInt(H);
    R.IStop := AsInt(B);
    if R.IStep = 0 then
      RaiseError(ArgumentError, 'the step of a range cannot be zero');
    if ((R.IStep > 0) and (R.IStop < R.IStart)) or
       ((R.IStep < 0) and (R.IStop > R.IStart)) then
      R.Count := 0
    else
    begin
      Span := CheckedSub(R.IStop, R.IStart);
      R.Count := Span div R.IStep + 1;
    end;
  end
  else
  begin
    R.RStart := ToReal(A);
    R.RStep := ToReal(H);
    R.RStop := ToReal(B);
    if R.RStep = 0 then
      RaiseError(ArgumentError, 'the step of a range cannot be zero');
    if IsNan(R.RStart) or IsNan(R.RStep) or IsNan(R.RStop) then
      RaiseError(ArgumentError, 'range bounds and step cannot be NaN');
    // Reference, "Ranges": the length is floor((b - a)/h + 1e-10) + 1.
    N := Floor((R.RStop - R.RStart) / R.RStep + 1e-10) + 1;
    if IsInfinite(N) or (N > 4.0e18) then
      RaiseError(ArgumentError, 'range has too many elements');
    if N < 0 then
      N := 0;
    R.Count := Trunc(N);
  end;
end;

function TInterpreter.EvalLogical(E: TBinaryExpr; Scope: TScope): TAxValue;
var
  L, R: TAxValue;
  Word: string;
begin
  Word := TokenSpelling[E.Op];
  L := Eval(E.Left, Scope);
  if L.Kind <> vkBool then
    RaiseFmt(TypeError, '"%s" needs bool operands, got %s', [Word, TypeName(L)]);
  // Short-circuit on a scalar left operand.
  if (E.Op = tkAnd) and not L.B then
    Exit(BoolValue(False));
  if (E.Op = tkOr) and L.B then
    Exit(BoolValue(True));
  R := Eval(E.Right, Scope);
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
  if T.Kind <> vkRecord then
    raise EAxonError.CreateAt(TypeError, Format('%s has no fields (accessing ".%s")',
      [TypeName(T), E.Name]), FFile, E.Line, E.Col);
  K := AsRecord(T).IndexOf(E.Name);
  if K < 0 then
    raise EAxonError.CreateAt(FieldError, Format('the record has no field "%s"', [E.Name]),
      FFile, E.Line, E.Col);
  Result := AsRecord(T).Values[K];
end;

{ list[k] with one integer index (or an expression using `end`). Ranges,
  arrays and other index forms arrive in M6 and M7. }
function TInterpreter.EvalIndex(E: TIndexExpr; Scope: TScope): TAxValue;
var
  T, Idx: TAxValue;
  L: TListObj;
  N: Int64;
begin
  T := Eval(E.Target, Scope);
  if T.Kind <> vkList then
    NotYet(Format('indexing a %s', [TypeName(T)]), 'M6', E);
  L := AsList(T);
  N := Length(L.Items);
  if E.Items.Count <> 1 then
    raise EAxonError.CreateAt(IndexError, Format('a list takes one index, got %d',
      [E.Items.Count]), FFile, E.Line, E.Col);
  if E.Items[0] is TColonExpr then
    NotYet('list slices', 'M7', E);
  FEndStack.Add(N);
  try
    Idx := Eval(E.Items[0], Scope);
  finally
    FEndStack.Delete(FEndStack.Count - 1);
  end;
  if Idx.Kind = vkRange then
    NotYet('list slices', 'M7', E);
  if Idx.Kind <> vkInt then
    raise EAxonError.CreateAt(IndexError, Format('a list index must be an int, got %s',
      [TypeName(Idx)]), FFile, E.Line, E.Col);
  if (Idx.I < 1) or (Idx.I > N) then
    raise EAxonError.CreateAt(IndexError, Format('index %d is out of bounds for a list of length %d',
      [Idx.I, N]), FFile, E.Line, E.Col);
  Result := L.Items[Idx.I - 1];
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
  else if (C = TMatrixExpr) or (C = TColonExpr) then
    NotYet('matrices and indexing', 'M6', E)
  else if (C = TListExpr) or (C = TRecordExpr) then
    NotYet('lists and records', 'M7', E)
  else
    NotYet(E.ClassName, 'a later milestone', E);
end;

{ ---------------- entry points ---------------- }

procedure TInterpreter.Hoist(P: TProgram);
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
      FGlobals.Define(Decl.Name).Value := FunctionValue(Decl, FGlobals, False);
      FHoisted.AddOrSetValue(Decl, True);
    end;
end;

procedure TInterpreter.Run(P: TProgram);
var
  S: TStmt;
begin
  Hoist(P);
  for S in P.Body do
    ExecStmt(S, FGlobals);
end;

function TInterpreter.ExecTopLevel(S: TStmt; out Shown: TAxValues; out ShownName: string): Boolean;
var
  V: TAxValue;
begin
  Shown := nil;
  ShownName := '';
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
  Result := False;
  if (S is TAssignStmt) and (TAssignStmt(S).Target is TNameExpr) then
  begin
    ShownName := TNameExpr(TAssignStmt(S).Target).Name;
    V := Lookup(ShownName, FGlobals, S);
    Shown := [V];
    Result := True;
  end;
end;

end.
