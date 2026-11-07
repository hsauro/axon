unit Axon.Interp;

(* Tree-walking evaluator.

   M3 scope: scalars, strings, ranges, operators, if/while/for, break and
   continue, builtin calls, and variables. Constructs from later milestones
   raise ENotImplemented, which the command line reports with exit code 2.

   Scopes (reference, "Scopes"). The script's top level is a function-root
   scope whose parent is the prelude. Each execution of an if, while, for or
   try body gets a child scope, and each for-loop iteration gets a fresh one
   holding the loop variable. A plain assignment updates the nearest existing
   variable up to the function root and otherwise creates the variable in the
   function root, so a variable first assigned inside an if is visible after
   the end. Functions and closures arrive in M4. *)

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

  TScope = class
  private
    FVars: TDictionary<string, TAxValue>;   // created on first use
  public
    Parent: TScope;
    IsFunctionRoot: Boolean;
    constructor Create(AParent: TScope; AIsFunctionRoot: Boolean);
    destructor Destroy; override;
    function TryGet(const Name: string; out V: TAxValue): Boolean; inline;
    procedure Put(const Name: string; const V: TAxValue);
    function Has(const Name: string): Boolean; inline;
  end;

  TSignal = (sigNone, sigBreak, sigContinue, sigReturn);

  TInterpreter = class
  private
    FPrelude: TScope;
    FGlobals: TScope;
    FFile: string;
    procedure NotYet(const What, Milestone: string; Node: TNode);
    function Lookup(const Name: string; Scope: TScope; Node: TNode): TAxValue;
    procedure Assign(const Name: string; const V: TAxValue; Scope: TScope);
    procedure CheckCondition(const V: TAxValue; const Construct: string);
    function ExecBlock(Stmts: TStmtList; Parent: TScope): TSignal;
    function ExecStmt(S: TStmt; Scope: TScope): TSignal;
    function ExecFor(S: TForStmt; Scope: TScope): TSignal;
    function MakeRange(E: TRangeExpr; Scope: TScope): TAxValue;
    function EvalCall(E: TCallExpr; Scope: TScope): TAxValue;
    function EvalLogical(E: TBinaryExpr; Scope: TScope): TAxValue;
  public
    constructor Create(const FileName: string);
    destructor Destroy; override;
    function Eval(E: TExpr; Scope: TScope): TAxValue;
    { Runs a whole program at the top level. }
    procedure Run(P: TProgram);
    { Runs one top-level statement (the REPL). If it is an expression, or an
      assignment to a plain name, Shown receives the value to display and
      ShownName the assigned name (empty for an expression). }
    function ExecTopLevel(S: TStmt; out Shown: TAxValue; out ShownName: string): Boolean;
    property Globals: TScope read FGlobals;
  end;

implementation

uses
  System.Math,
  Axon.Errors, Axon.Tokens, Axon.Ops, Axon.Builtins;

{ ===================== TScope ===================== }

constructor TScope.Create(AParent: TScope; AIsFunctionRoot: Boolean);
begin
  inherited Create;
  Parent := AParent;
  IsFunctionRoot := AIsFunctionRoot;
end;

destructor TScope.Destroy;
begin
  FVars.Free;
  inherited;
end;

function TScope.TryGet(const Name: string; out V: TAxValue): Boolean;
begin
  Result := (FVars <> nil) and FVars.TryGetValue(Name, V);
end;

procedure TScope.Put(const Name: string; const V: TAxValue);
begin
  if FVars = nil then
    FVars := TDictionary<string, TAxValue>.Create;
  FVars.AddOrSetValue(Name, V);
end;

function TScope.Has(const Name: string): Boolean;
begin
  Result := (FVars <> nil) and FVars.ContainsKey(Name);
end;

{ ===================== TInterpreter ===================== }

constructor TInterpreter.Create(const FileName: string);
var
  Prelude: TScope;
begin
  inherited Create;
  FFile := FileName;
  FPrelude := TScope.Create(nil, False);
  Prelude := FPrelude;
  DefineBuiltins(
    procedure(Name: string; V: TAxValue)
    begin
      Prelude.Put(Name, V);
    end);
  FGlobals := TScope.Create(FPrelude, True);
end;

destructor TInterpreter.Destroy;
begin
  FGlobals.Free;
  FPrelude.Free;
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

function TInterpreter.Lookup(const Name: string; Scope: TScope; Node: TNode): TAxValue;
var
  S: TScope;
begin
  S := Scope;
  while S <> nil do
  begin
    if S.TryGet(Name, Result) then
      Exit;
    S := S.Parent;
  end;
  raise EAxonError.CreateAt(NameError, Format('"%s" is not defined', [Name]),
    FFile, Node.Line, Node.Col);
end;

procedure TInterpreter.Assign(const Name: string; const V: TAxValue; Scope: TScope);
var
  S: TScope;
begin
  // Nearest existing variable up to and including the function root.
  S := Scope;
  while True do
  begin
    if S.Has(Name) then
    begin
      S.Put(Name, V);
      Exit;
    end;
    if S.IsFunctionRoot then
      Break;
    S := S.Parent;
  end;
  // Not found: create it in the function root.
  S.Put(Name, V);
end;

procedure TInterpreter.CheckCondition(const V: TAxValue; const Construct: string);
begin
  if V.Kind <> vkBool then
    RaiseFmt(TypeError, 'the condition of "%s" must be a bool, got %s',
      [Construct, TypeName(V)]);
end;

{ ---------------- statements ---------------- }

function TInterpreter.ExecBlock(Stmts: TStmtList; Parent: TScope): TSignal;
var
  Scope: TScope;
  S: TStmt;
begin
  Result := sigNone;
  if Stmts.Count = 0 then
    Exit;
  Scope := TScope.Create(Parent, False);
  try
    for S in Stmts do
    begin
      Result := ExecStmt(S, Scope);
      if Result <> sigNone then
        Exit;
    end;
  finally
    Scope.Free;
  end;
end;

function TInterpreter.ExecFor(S: TForStmt; Scope: TScope): TSignal;
var
  Iter: TAxValue;
  R: TRangeObj;
  K: Int64;
  IterScope: TScope;
  Stmt: TStmt;
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
    IterScope := TScope.Create(Scope, False);
    try
      IterScope.Put(S.VarName, R.ItemAt(K));
      Sig := sigNone;
      for Stmt in S.Body do
      begin
        Sig := ExecStmt(Stmt, IterScope);
        if Sig <> sigNone then
          Break;
      end;
    finally
      IterScope.Free;
    end;
    case Sig of
      sigBreak:  Break;
      sigReturn: Exit(sigReturn);
    end;
    Inc(K);
  end;
end;

function TInterpreter.ExecStmt(S: TStmt; Scope: TScope): TSignal;
var
  C: TClass;
  V: TAxValue;
  B: TIfBranch;
  Taken: Boolean;
  Target: TExpr;
begin
  Result := sigNone;
  try
    C := S.ClassType;
    if C = TExprStmt then
      Eval(TExprStmt(S).Expr, Scope)
    else if C = TAssignStmt then
    begin
      if TAssignStmt(S).TypeRef <> nil then
        NotYet('a typed assignment', 'M4', S);
      Target := TAssignStmt(S).Target;
      if not (Target is TNameExpr) then
        NotYet('assignment to an index or field', 'M6', S);
      V := Eval(TAssignStmt(S).Value, Scope);
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
    else if C = TBreakStmt then
      Result := sigBreak
    else if C = TContinueStmt then
      Result := sigContinue
    else if C = TDeclStmt then
    begin
      if TDeclStmt(S).IsGlobal then
        NotYet('"global"', 'M4', S);
      if TDeclStmt(S).TypeRef <> nil then
        NotYet('a typed declaration', 'M4', S);
      if TDeclStmt(S).Value <> nil then
        V := Eval(TDeclStmt(S).Value, Scope)
      else
        V := NothingValue;
      Scope.Put(TDeclStmt(S).Name, V);
    end
    else if C = TFunctionStmt then
      NotYet('function definition', 'M4', S)
    else if C = TReturnStmt then
      NotYet('"return"', 'M4', S)
    else if C = TDestructureStmt then
      NotYet('destructuring assignment', 'M4', S)
    else if C = TTryStmt then
      NotYet('try/catch', 'M5', S)
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

function TInterpreter.EvalCall(E: TCallExpr; Scope: TScope): TAxValue;
var
  Callee: TAxValue;
  B: TBuiltinObj;
  Args: TAxValues;
  I: Integer;
begin
  Callee := Eval(E.Callee, Scope);
  if Callee.Kind <> vkBuiltin then
    RaiseFmt(TypeError, '%s is not callable', [TypeName(Callee)]);
  B := AsBuiltin(Callee);
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
  try
    Result := B.Fn(Args);
  except
    on X: EAxonError do
    begin
      X.Locate(FFile, E.Line, E.Col);
      raise;
    end;
  end;
end;

function TInterpreter.Eval(E: TExpr; Scope: TScope): TAxValue;
var
  C: TClass;
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
    Result := EvalCall(TCallExpr(E), Scope)
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
    NotYet('anonymous functions', 'M4', E)
  else if (C = TMatrixExpr) or (C = TIndexExpr) or (C = TEndExpr) or (C = TColonExpr) then
    NotYet('matrices and indexing', 'M6', E)
  else if (C = TListExpr) or (C = TRecordExpr) or (C = TFieldExpr) then
    NotYet('lists and records', 'M7', E)
  else
    NotYet(E.ClassName, 'a later milestone', E);
end;

{ ---------------- entry points ---------------- }

procedure TInterpreter.Run(P: TProgram);
var
  S: TStmt;
begin
  for S in P.Body do
    ExecStmt(S, FGlobals);
end;

function TInterpreter.ExecTopLevel(S: TStmt; out Shown: TAxValue; out ShownName: string): Boolean;
begin
  Result := False;
  ShownName := '';
  if S is TExprStmt then
  begin
    try
      Shown := Eval(TExprStmt(S).Expr, FGlobals);
    except
      on E: EAxonError do
      begin
        E.Locate(FFile, S.Line, S.Col);
        raise;
      end;
    end;
    Result := Shown.Kind <> vkNothing;
    Exit;
  end;
  ExecStmt(S, FGlobals);
  if (S is TAssignStmt) and (TAssignStmt(S).Target is TNameExpr) then
  begin
    ShownName := TNameExpr(TAssignStmt(S).Target).Name;
    Shown := Lookup(ShownName, FGlobals, S);
    Result := True;
  end;
end;

end.
