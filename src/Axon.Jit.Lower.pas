unit Axon.Jit.Lower;

(* Lowers the syntax tree of one named function to JIR (Axon.Jit.Ir), with
   type inference, or rejects it with a reason (doc/Axon-JIT-Plan.md, J1).

   The rule is that compiled code must behave exactly like the interpreter,
   so anything whose behaviour cannot be fixed statically is rejected and the
   function stays interpreted:

   - Types. Every expression has one static type: bool, int or real (more in
     later milestones). Parameters and the result must be annotated with one
     of these, or the result inferred from the returns. An untyped variable
     keeps the type of its first assignment; a later assignment of another
     type is rejected, because the interpreter would let the type change. An
     annotated variable (a parameter, `x: T = e`, `local x: T = e`) widens
     what is assigned to it (bool → int → real), as the interpreter coerces;
     an assignment that would raise TypeError there is rejected here.
   - Value-dependent types. `int ^ int` is an int for a non-negative
     exponent and a real otherwise, so it compiles only when the exponent is
     a literal (or a bool).
   - Names. Resolution in the interpreter is dynamic: a plain assignment
     creates a variable in the function's outermost scope when it runs, and a
     read of a name with no local variable goes to the module. So a read is
     accepted only where the variable is definitely assigned on every path to
     it (tracked structurally through if, while and for); a read that might
     reach the module is rejected. Block scopes (`local`, `x: T = e`, the
     loop variable of a for) follow the reference's rules 2 and 3.
   - Errors. Instructions that can fail carry the position of the innermost
     statement around them, where the interpreter locates such errors.

   - Calls (J3). A called name resolves, through the session's resolver,
     in the function's defining scope, as the interpreter would at the call.
     A function that compiles is called directly with its parameter types;
     one that does not runs interpreted, and its result type must then be
     declared (or the result unused). Built-ins with scalar arguments and a
     known result type are compiled (elementary functions, abs, floor, ceil,
     round, int, real, min, max, div, mod), and so are print and error with
     numbers and string literals. Recursion is compiled when the result type
     is known before the recursive call (declared, or fixed by an earlier
     return); mutual recursion goes through the interpreter in one direction.

   - Arrays (J4): vector{real}, vector{int} and matrix{real}, with the
     element type declared (plain vector or matrix could hold anything).
     Elements are read and written with scalar int indices and `end`, each
     index checked as soon as it is evaluated, as the interpreter does; a
     write never widens the array. length and size are inline; zeros, ones,
     sum and print take arrays through the interpreter's own routines, and
     so do +, -, *, / and the dotted operators on real arrays, for the
     shapes in LowerArrayOp. for x in v visits the elements of an array.

   - Specialisation (J6). A parameter without an annotation, or annotated
     plain vector or matrix, takes the type of the argument at a call: from
     the bound value when the interpreter calls the function, from the
     static type when compiled code does. The session keeps one lowering per
     function and parameter types (at most MaxSpecialisations). An
     unannotated parameter is an untyped variable: it starts with the
     argument's type and must keep it, as any untyped variable must.

   - Captures and closures (J7c). A read of a name that is not local, or of
     a field path on one (p.a), whose value has a type that compiles, is a
     capture: a hidden parameter read when the function is entered. That is
     exact because nothing the compiled code runs can change it: a function
     with captures may not call anything through the interpreter (or itself,
     directly). A name both read from outside and assigned locally is
     rejected. Lambdas and nested functions compile too; one that assigns a
     variable of an enclosing scope (rule 5 reaching outward) does not, and
     the names a closure creates locally are checked at each call to still be
     absent outside (TJFunction.LocalNames).
   - Vector and matrix literals whose entries are all numbers.

   Not compiled yet, and rejected: ranges, masks and colons as indices,
   fields of local records, strings other than print and error arguments,
   complex numbers, ranges as values, nested function definitions, try,
   global and keyword arguments.

   A TJSession lowers functions on demand and keeps the results, so a call
   can ask for its callee's types; the JIT keeps one session for the
   process, and --jir makes one per file. *)

interface

uses
  System.SysUtils, System.Generics.Collections,
  Axon.Ast, Axon.Values, Axon.Jit.Ir;

type
  EJitReject = class(Exception)
  public
    Line, Col: Integer;
    constructor Create(const Msg: string; ALine, ACol: Integer);
  end;

  TJResolvedKind = (rkNone, rkFunction, rkBuiltin, rkOther);

  { What a called name refers to. }
  TJResolved = record
    Kind: TJResolvedKind;
    Name: string;            // rkBuiltin: the built-in's own name
    Decl: TFunctionDecl;     // rkFunction
    FuncObj: TObject;        // rkFunction at run time; nil for --jir
    FileName: string;        // rkFunction: the file it was defined in
    IsClosure: Boolean;      // rkFunction: a lambda or nested function
    Value: TAxValue;         // the value, for calls through the interpreter
    ValuePtr: PAxValue;      // the variable holding it (for the guard); nil if none
  end;

  { Resolves Name as a call in Context (the calling function's FuncObj). }
  TJResolver = reference to function(Context: TObject; const Name: string): TJResolved;

  TJEntryState = (esLowering, esLowered, esRejected);

const
  MaxSpecialisations = 8;      // per function; calls beyond run interpreted

type

  { A function the session has lowered, or is lowering, for one list of
    parameter types. }
  TJEntry = class
  public
    Decl: TFunctionDecl;
    ParamTypes: TArray<TJType>;
    FuncObj: TObject;
    FileName: string;
    State: TJEntryState;
    Func: TJFunction;        // esLowered; owned
    Reason: string;          // esRejected
    RejectLine, RejectCol: Integer;
    Code: TObject;           // set by the JIT once generated (a TJitCode, not owned)
    IsClosure: Boolean;      // a lambda or nested function: rule 5 reaches outward
    destructor Destroy; override;
  end;

  TJSession = class
  public
    Resolver: TJResolver;
    Entries: TObjectDictionary<string, TJEntry>;   // by SignatureKey
    Order: TList<TJEntry>;                         // in the order lowered
    Counts: TDictionary<TFunctionDecl, Integer>;   // specialisations per function
    constructor Create(const AResolver: TJResolver);
    destructor Destroy; override;
    { Lowers Decl for the parameter types, or returns what an earlier call
      found. Never raises for a rejection: the entry's State says. }
    function Lower(Decl: TFunctionDecl; FuncObj: TObject; const FileName: string;
      const ParamTypes: TArray<TJType>; IsClosure: Boolean = False): TJEntry;
    function Resolve(Context: TObject; const Name: string): TJResolved;
  end;

{ The parameter types of Decl for a call with these argument types: an
  annotation that compiles gives its own type (the argument is converted to
  it); an unannotated parameter, or one annotated plain vector or matrix,
  takes the argument's type. False, with the reason, when a parameter cannot
  be typed. jtNothing in ArgTypes is an argument of a type that does not
  compile. }
function SignatureFor(Decl: TFunctionDecl; const ArgTypes: TArray<TJType>;
  out ParamTypes: TArray<TJType>; out Reason: string): Boolean;

(* The parameter types as text: "int, vector{real}". *)
function TypesText(const Types: TArray<TJType>): string;

{ Whether Decl has a parameter whose type comes from its arguments. }
function IsSpecialised(Decl: TFunctionDecl): Boolean;

{ The parameter types from the annotations alone, jtNothing where a type
  comes from the arguments or does not compile (for --jir). }
function AnnotatedTypes(Decl: TFunctionDecl): TArray<TJType>;

implementation

uses
  System.Math,
  Axon.Tokens;

constructor EJitReject.Create(const Msg: string; ALine, ACol: Integer);
begin
  inherited Create(Msg);
  Line := ALine;
  Col := ACol;
end;

type
  TJValue = record
    Typ: TJType;
    Opnd: TJOperand;
  end;

  TJVar = class
  public
    Id: Integer;
    Name: string;
    Reg: Integer;
    Typ: TJType;
    Declared: Boolean;       // annotated: assignments widen to Typ
    Line, Col: Integer;      // where the type was fixed
  end;

  TScopeMap = TDictionary<string, TJVar>;

  TLoop = record
    ContinueLabel, BreakLabel, Breaks: Integer;
  end;

  TLowerer = class
  private
    F: TJFunction;
    Decl: TFunctionDecl;
    Session: TJSession;
    Entry: TJEntry;
    Context: TObject;
    LastCallRaises: Boolean;            // the last call lowered was error(...)
    EndStack: TList<TJValue>;           // the value of `end` in the index being lowered
    CaptureRegs: TDictionary<string, Integer>;   // by path text: its hidden parameter
    OutsideNames: TList<string>;        // names read from outside (captured)
    Vars: TObjectList<TJVar>;
    Scopes: TObjectList<TScopeMap>;     // [0] is the function's outermost scope
    Assigned: TArray<Boolean>;           // by TJVar.Id: definitely assigned here
    Reachable: Boolean;
    Loops: TList<TLoop>;
    StmtLine, StmtCol: Integer;          // the innermost statement, for sites
    ReturnFixed, ReturnDeclared: Boolean;
    ReturnLine, ReturnCol: Integer;      // the return that fixed the result types
    procedure Reject(const Msg: string; N: TNode); overload;
    procedure Reject(const Fmt: string; const Args: array of const; N: TNode); overload;
    function Site: Integer;
    // variables
    function NewVar(const Name: string; Typ: TJType; Declared: Boolean; N: TNode;
      ScopeIndex: Integer; IsParam: Boolean = False): TJVar;
    function Lookup(const Name: string): TJVar;
    procedure MarkAssigned(V: TJVar);
    function IsAssigned(V: TJVar): Boolean;
    procedure StoreVar(V: TJVar; const Val: TJValue; N: TNode);
    procedure Move(Dst: Integer; const Val: TJValue);
    function Temp(Typ: TJType): Integer;
    // values
    function Convert(const Val: TJValue; Target: TJType): TJValue;
    function Coerce(const Val: TJValue; Target: TJType; const What: string; N: TNode): TJValue;
    function Copied(const Val: TJValue): TJValue;
    // expressions
    function LowerExpr(E: TExpr): TJValue;
    function LowerName(E: TNameExpr): TJValue;
    function LowerUnary(E: TUnaryExpr): TJValue;
    function LowerBinary(E: TBinaryExpr): TJValue;
    function LowerLogical(E: TBinaryExpr): TJValue;
    function LowerCompare(E: TBinaryExpr; const L, R: TJValue): TJValue;
    function LowerArith(E: TBinaryExpr; const L, R: TJValue): TJValue;
    function LowerCond(E: TExpr): TJOperand;
    function LowerCall(E: TCallExpr; Want: Integer): TArray<TJValue>;
    function LowerBuiltin(E: TCallExpr; const Name: string; var Args: TArray<TJValue>;
      T: TJCallTarget; Want: Integer): TArray<TJType>;
    function LowerFunctionCall(E: TCallExpr; const R: TJResolved; var Args: TArray<TJValue>;
      T: TJCallTarget; Want: Integer): TArray<TJType>;
    procedure AssignName(const Name: string; const Val: TJValue; N: TNode);
    function ArrayLen(const A: TJValue; Dim: Integer): TJValue;
    function LowerIndexItem(Item: TExpr; const Len: TJValue): TJValue;
    function LowerIndex(E: TIndexExpr): TJValue;
    procedure LowerIndexAssign(S: TAssignStmt);
    function LowerArrayOp(E: TExpr; Op: TTokenKind; const L, R: TJValue; Unary: Boolean): TJValue;
    function TryInlineBuiltin(E: TCallExpr; const Name: string; const Args: TArray<TJValue>;
      Want: Integer; out Vals: TArray<TJValue>): Boolean;
    procedure LowerForEach(S: TForStmt);
    function Capture(E: TExpr; const Path: TArray<string>): TJValue;
    function LowerField(E: TFieldExpr): TJValue;
    function LowerMatrix(E: TMatrixExpr): TJValue;
    procedure CheckCaptures;
    procedure LowerDestructure(S: TDestructureStmt);
    // statements
    procedure LowerBody(Body: TStmtList; NewScope: Boolean);
    procedure LowerStmt(S: TStmt);
    procedure LowerAssign(S: TAssignStmt);
    procedure LowerDecl(S: TDeclStmt);
    procedure LowerReturn(S: TReturnStmt);
    procedure LowerIf(S: TIfStmt);
    procedure LowerWhile(S: TWhileStmt);
    procedure LowerFor(S: TForStmt);
    procedure EmitReturn(const Vals: TArray<TJValue>; N: TNode);
    procedure CheckBodyShape(Body: TStmtList);
  public
    ParamTypes: TArray<TJType>;        // from the entry
    constructor Create(ADecl: TFunctionDecl; ASession: TJSession; AEntry: TJEntry; AContext: TObject);
    destructor Destroy; override;
    function Run: TJFunction;
  end;

function Numeric(T: TJType): Boolean;
begin
  Result := T in [jtBool, jtInt, jtReal];
end;

{ A type a variable, parameter or result can have. }
function Storable(T: TJType): Boolean;
begin
  Result := Numeric(T) or IsArrayType(T);
end;

function Rank(T: TJType): Integer;
begin
  case T of
    jtBool: Result := 0;
    jtInt:  Result := 1;
    jtReal: Result := 2;
  else
    Result := -1;
  end;
end;

{ The JIR type of an annotation, if it is one that compiles. }
function TypeOfRef(T: TTypeRef; out JT: TJType): Boolean;
begin
  Result := True;
  if T.Param <> nil then
  begin
    if (T.Name = 'vector') and (T.Param.Param = nil) and (T.Param.Name = 'real') then JT := jtVecReal
    else if (T.Name = 'vector') and (T.Param.Param = nil) and (T.Param.Name = 'int') then JT := jtVecInt
    else if (T.Name = 'matrix') and (T.Param.Param = nil) and (T.Param.Name = 'real') then JT := jtMatReal
    else Result := False;
    Exit;
  end;
  if T.Name = 'bool' then JT := jtBool
  else if T.Name = 'int' then JT := jtInt
  else if T.Name = 'real' then JT := jtReal
  else Result := False;
end;

{ Why an annotation does not compile, for messages. }
function TypeHint(T: TTypeRef): string;
begin
  if (T.Param = nil) and ((T.Name = 'vector') or (T.Name = 'matrix')) then
    Result := Format('type %s needs its element type to compile, as %s{real}', [T.Name, T.Name])
  else
    Result := Format('type %s is not compiled yet', [T.ToString]);
end;

function MakeValue(Typ: TJType; const Opnd: TJOperand): TJValue;
begin
  Result.Typ := Typ;
  Result.Opnd := Opnd;
end;

function TypeList(const Ts: TArray<TJType>): string;
var
  K: Integer;
begin
  if Length(Ts) = 0 then
    Exit('nothing');
  Result := '';
  for K := 0 to High(Ts) do
  begin
    if K > 0 then
      Result := Result + ', ';
    Result := Result + JTypeName(Ts[K]);
  end;
end;

{ TLowerer }

constructor TLowerer.Create(ADecl: TFunctionDecl; ASession: TJSession; AEntry: TJEntry;
  AContext: TObject);
begin
  inherited Create;
  Decl := ADecl;
  Session := ASession;
  Entry := AEntry;
  Context := AContext;
  EndStack := TList<TJValue>.Create;
  CaptureRegs := TDictionary<string, Integer>.Create;
  OutsideNames := TList<string>.Create;
  Vars := TObjectList<TJVar>.Create(True);
  Scopes := TObjectList<TScopeMap>.Create(True);
  Loops := TList<TLoop>.Create;
end;

destructor TLowerer.Destroy;
begin
  OutsideNames.Free;
  CaptureRegs.Free;
  EndStack.Free;
  Loops.Free;
  Scopes.Free;
  Vars.Free;
  F.Free;           // nil once Run has handed it over
  inherited;
end;

procedure TLowerer.Reject(const Msg: string; N: TNode);
begin
  raise EJitReject.Create(Msg, N.Line, N.Col);
end;

procedure TLowerer.Reject(const Fmt: string; const Args: array of const; N: TNode);
begin
  Reject(Format(Fmt, Args), N);
end;

function TLowerer.Site: Integer;
begin
  Result := F.AddSite(StmtLine, StmtCol);
end;

{ ---- variables ---- }

function TLowerer.NewVar(const Name: string; Typ: TJType; Declared: Boolean; N: TNode;
  ScopeIndex: Integer; IsParam: Boolean): TJVar;
begin
  Result := TJVar.Create;
  Result.Id := Vars.Add(Result);
  Result.Name := Name;
  Result.Typ := Typ;
  Result.Declared := Declared;
  Result.Line := N.Line;
  Result.Col := N.Col;
  Result.Reg := F.NewReg(Typ, Name, IsParam);
  Scopes[ScopeIndex].AddOrSetValue(Name, Result);
end;

function TLowerer.Lookup(const Name: string): TJVar;
var
  K: Integer;
begin
  for K := Scopes.Count - 1 downto 0 do
    if Scopes[K].TryGetValue(Name, Result) then
      Exit;
  Result := nil;
end;

procedure TLowerer.MarkAssigned(V: TJVar);
begin
  if V.Id >= Length(Assigned) then
    SetLength(Assigned, V.Id + 1);
  Assigned[V.Id] := True;
end;

function TLowerer.IsAssigned(V: TJVar): Boolean;
begin
  Result := (V.Id < Length(Assigned)) and Assigned[V.Id];
end;

function TLowerer.Temp(Typ: TJType): Integer;
begin
  Result := F.NewReg(Typ);
end;

{ Dst := Val. When Val is the temporary that the last instruction just
  computed, that instruction writes Dst directly instead. }
procedure TLowerer.Move(Dst: Integer; const Val: TJValue);
var
  Last: TJInsn;
begin
  if (Val.Opnd.Kind = jkReg) and (F.Regs[Val.Opnd.Reg].Name = '') and (F.Insns.Count > 0) then
  begin
    Last := F.Insns.Last;
    if (Last.Op <> joLabel) and (Last.Dst = Val.Opnd.Reg) then
    begin
      Last.Dst := Dst;
      Exit;
    end;
  end;
  F.Emit(joMov, F.Regs[Dst].Typ, Dst, [Val.Opnd]);
end;

procedure TLowerer.StoreVar(V: TJVar; const Val: TJValue; N: TNode);
var
  W: TJValue;
begin
  if V.Declared then
    W := Coerce(Val, V.Typ, Format('assigns %s to %s, declared %s',
      [JTypeName(Val.Typ), V.Name, JTypeName(V.Typ)]), N)
  else
  begin
    if Val.Typ <> V.Typ then
      Reject('%s is %s at %d:%d and %s at %d:%d', [V.Name, JTypeName(V.Typ), V.Line, V.Col,
        JTypeName(Val.Typ), N.Line, N.Col], N);
    W := Val;
  end;
  Move(V.Reg, W);
  MarkAssigned(V);
end;

{ ---- values ---- }

{ Val promoted to Target (bool → int → real); immediates are folded. }
function TLowerer.Convert(const Val: TJValue; Target: TJType): TJValue;
var
  R: Integer;
  Op: TJOp;
begin
  if Val.Typ = Target then
    Exit(Val);
  Assert(Rank(Val.Typ) < Rank(Target));
  if Val.Opnd.IsImm then
  begin
    if Target = jtInt then
      Exit(MakeValue(jtInt, IntOperand(Ord(Val.Opnd.B))));
    if Val.Typ = jtBool then
      Exit(MakeValue(jtReal, RealOperand(Ord(Val.Opnd.B))))
    else
      Exit(MakeValue(jtReal, RealOperand(Val.Opnd.I)));
  end;
  if Target = jtInt then
    Op := joB2I
  else if Val.Typ = jtBool then
    Op := joB2R
  else
    Op := joI2R;
  R := Temp(Target);
  F.Emit(Op, Target, R, [Val.Opnd]);
  Result := MakeValue(Target, RegOperand(R));
end;

{ Val as an annotated Target, as the interpreter's CoerceToType does: equal
  or wider types only. }
function TLowerer.Coerce(const Val: TJValue; Target: TJType; const What: string; N: TNode): TJValue;
begin
  if (Val.Typ = Target) then
    Exit(Val);
  if not Numeric(Val.Typ) or not Numeric(Target) or (Rank(Val.Typ) > Rank(Target)) then
    Reject(What + ', a TypeError', N);
  Result := Convert(Val, Target);
end;

{ A register operand copied into a fresh temporary, so later assignments to
  the variable do not change it (range bounds). Immediates stay as they are. }
function TLowerer.Copied(const Val: TJValue): TJValue;
var
  R: Integer;
begin
  if Val.Opnd.IsImm or (F.Regs[Val.Opnd.Reg].Name = '') then
    Exit(Val);
  R := Temp(Val.Typ);
  F.Emit(joMov, Val.Typ, R, [Val.Opnd]);
  Result := MakeValue(Val.Typ, RegOperand(R));
end;

{ ---- expressions ---- }

function TLowerer.LowerExpr(E: TExpr): TJValue;
var
  C: TClass;
begin
  C := E.ClassType;
  if C = TIntLit then
    Result := MakeValue(jtInt, IntOperand(TIntLit(E).Value))
  else if C = TRealLit then
    Result := MakeValue(jtReal, RealOperand(TRealLit(E).Value))
  else if C = TBoolLit then
    Result := MakeValue(jtBool, BoolOperand(TBoolLit(E).Value))
  else if C = TNameExpr then
    Result := LowerName(TNameExpr(E))
  else if C = TUnaryExpr then
    Result := LowerUnary(TUnaryExpr(E))
  else if C = TBinaryExpr then
    Result := LowerBinary(TBinaryExpr(E))
  else
  begin
    Result := Default(TJValue);
    if C = TCallExpr then
      Result := LowerCall(TCallExpr(E), 1)[0]
    else if C = TIndexExpr then
      Result := LowerIndex(TIndexExpr(E))
    else if C = TEndExpr then
    begin
      if EndStack.Count = 0 then
        Reject('end outside an index', E);
      Result := EndStack.Last;
    end
    else if C = TFieldExpr then
      Result := LowerField(TFieldExpr(E))
    else if C = TMatrixExpr then
      Result := LowerMatrix(TMatrixExpr(E))
    else if (C = TListExpr) or (C = TRecordExpr) then
      Reject('list and record literals are not compiled', E)
    else if C = TStringLit then
      Reject('strings are not compiled', E)
    else if C = TImagLit then
      Reject('complex numbers are not compiled', E)
    else if C = TNothingLit then
      Reject('nothing is not compiled', E)
    else if C = TLambdaExpr then
      Reject('a lambda inside a function is not compiled', E)
    else if C = TRangeExpr then
      Reject('a range used as a value is not compiled', E)
    else
      Reject('this expression is not compiled', E);
  end;
end;

function TLowerer.LowerName(E: TNameExpr): TJValue;
var
  V: TJVar;
begin
  V := Lookup(E.Name);
  if V = nil then
    Exit(Capture(E, [E.Name]));
  if not IsAssigned(V) then
    Reject('%s may be read before it is assigned', [E.Name], E);
  Result := MakeValue(V.Typ, RegOperand(V.Reg));
end;

function TLowerer.LowerUnary(E: TUnaryExpr): TJValue;
var
  A: TJValue;
  R: Integer;
begin
  A := LowerExpr(E.Operand);
  case E.Op of
    tkNot:
      begin
        if A.Typ <> jtBool then
          Reject('operator not on %s, a TypeError', [JTypeName(A.Typ)], E);
        if A.Opnd.IsImm then
          Exit(MakeValue(jtBool, BoolOperand(not A.Opnd.B)));
        R := Temp(jtBool);
        F.Emit(joNot, jtBool, R, [A.Opnd]);
        Result := MakeValue(jtBool, RegOperand(R));
      end;
    tkMinus:
      begin
        if A.Typ in [jtVecReal, jtMatReal] then
          Exit(LowerArrayOp(E, tkMinus, A, A, True));
        if not Numeric(A.Typ) then
          Reject('unary - on %s, a TypeError', [JTypeName(A.Typ)], E);
        if A.Typ = jtBool then
          A := Convert(A, jtInt);
        if A.Opnd.IsImm then
        begin
          if A.Typ = jtInt then
            Exit(MakeValue(jtInt, IntOperand(-A.Opnd.I)))
          else
            Exit(MakeValue(jtReal, RealOperand(-A.Opnd.R)));
        end;
        R := Temp(A.Typ);
        // -x overflows for the most negative int.
        if A.Typ = jtInt then
          F.Emit(joNeg, jtInt, R, [A.Opnd], Site)
        else
          F.Emit(joNeg, jtReal, R, [A.Opnd]);
        Result := MakeValue(A.Typ, RegOperand(R));
      end;
    tkPlus:
      begin
        if not Numeric(A.Typ) then
          Reject('unary + on %s, a TypeError', [JTypeName(A.Typ)], E);
        if A.Typ = jtBool then
          A := Convert(A, jtInt);
        Result := A;
      end;
    tkQuote:
      begin
        // The transpose of a scalar is the scalar.
        if not Numeric(A.Typ) then
          Reject('transpose of %s, a TypeError', [JTypeName(A.Typ)], E);
        Result := A;
      end;
  else
    Reject('operator %s is not compiled', [TokenSpelling[E.Op]], E);
  end;
end;

function TLowerer.LowerBinary(E: TBinaryExpr): TJValue;
var
  L, R: TJValue;
begin
  if E.Op in [tkAnd, tkOr] then
    Exit(LowerLogical(E));
  // Operands are evaluated left to right.
  L := LowerExpr(E.Left);
  R := LowerExpr(E.Right);
  case E.Op of
    tkEqEq, tkNotEq, tkLess, tkLessEq, tkGreater, tkGreaterEq:
      Result := LowerCompare(E, L, R);
    tkPlus, tkMinus, tkStar, tkSlash, tkBackslash, tkCaret,
    tkDotStar, tkDotSlash, tkDotBackslash, tkDotCaret:
      Result := LowerArith(E, L, R);
  else
    Reject('operator %s is not compiled', [TokenSpelling[E.Op]], E);
  end;
end;

{ a and b, a or b: the right operand only when the left does not decide. }
function TLowerer.LowerLogical(E: TBinaryExpr): TJValue;
var
  L, R: TJValue;
  Dst, LEnd: Integer;
begin
  L := LowerExpr(E.Left);
  if L.Typ <> jtBool then
    Reject('operator %s on %s, a TypeError', [TokenSpelling[E.Op], JTypeName(L.Typ)], E);
  Dst := Temp(jtBool);
  Move(Dst, L);
  LEnd := F.NewLabel;
  if E.Op = tkAnd then
    F.Emit(joBrFalse, jtNothing, -1, [RegOperand(Dst), LabelOperand(LEnd)])
  else
    F.Emit(joBrTrue, jtNothing, -1, [RegOperand(Dst), LabelOperand(LEnd)]);
  R := LowerExpr(E.Right);
  if R.Typ <> jtBool then
    Reject('operator %s on %s, a TypeError', [TokenSpelling[E.Op], JTypeName(R.Typ)], E);
  Move(Dst, R);
  F.PlaceLabel(LEnd);
  Result := MakeValue(jtBool, RegOperand(Dst));
end;

{ Numbers compare after promotion: exactly as ints when neither is real
  (bools count as 0 and 1), as reals otherwise, where NaN is unequal and
  unordered. }
function TLowerer.LowerCompare(E: TBinaryExpr; const L, R: TJValue): TJValue;
var
  T: TJType;
  Op: TJOp;
  Dst: Integer;
begin
  if not Numeric(L.Typ) or not Numeric(R.Typ) then
    Reject('comparison of %s and %s is not compiled', [JTypeName(L.Typ), JTypeName(R.Typ)], E);
  if Max(Rank(L.Typ), Rank(R.Typ)) <= 1 then T := jtInt else T := jtReal;
  case E.Op of
    tkEqEq:    Op := joEq;
    tkNotEq:   Op := joNe;
    tkLess:    Op := joLt;
    tkLessEq:  Op := joLe;
    tkGreater: Op := joGt;
  else
    Op := joGe;
  end;
  Dst := Temp(jtBool);
  F.Emit(Op, T, Dst, [Convert(L, T).Opnd, Convert(R, T).Opnd]);
  Result := MakeValue(jtBool, RegOperand(Dst));
end;

{ Arithmetic as the interpreter's IntArith and RealArith: bools and ints in
  checked int arithmetic, anything with a real in real arithmetic; / and \
  always give a real. }
function TLowerer.LowerArith(E: TBinaryExpr; const L, R: TJValue): TJValue;
var
  T: TJType;
  A, B: TJValue;
  Op: TJOp;
  Dst, S: Integer;
begin
  if IsArrayType(L.Typ) or IsArrayType(R.Typ) then
    Exit(LowerArrayOp(E, E.Op, L, R, False));
  if not Numeric(L.Typ) or not Numeric(R.Typ) then
    Reject('operator %s on %s and %s, a TypeError',
      [TokenSpelling[E.Op], JTypeName(L.Typ), JTypeName(R.Typ)], E);
  if Max(Rank(L.Typ), Rank(R.Typ)) <= 1 then T := jtInt else T := jtReal;
  S := -1;
  case E.Op of
    tkPlus:  Op := joAdd;
    tkMinus: Op := joSub;
    tkStar, tkDotStar: Op := joMul;
    tkSlash, tkDotSlash, tkBackslash, tkDotBackslash:
      begin
        Op := joDiv;
        T := jtReal;
      end;
  else
    begin
      Op := joPow;
      // int ^ int: an int for an exponent >= 0, a real for a negative one.
      if T = jtInt then
      begin
        if R.Typ = jtBool then
          // false or true: never negative
        else if R.Opnd.Kind = jkInt then
        begin
          if R.Opnd.I < 0 then
            T := jtReal;
        end
        else
          Reject('int ^ int with a variable exponent is an int or a real depending on ' +
            'the exponent''s sign; use a literal exponent, or make an operand real', E);
      end;
    end;
  end;
  if (T = jtInt) and (Op in [joAdd, joSub, joMul, joPow]) then
    S := Site;
  A := Convert(L, T);
  B := Convert(R, T);
  Dst := Temp(T);
  if E.Op in [tkBackslash, tkDotBackslash] then
    F.Emit(Op, T, Dst, [B.Opnd, A.Opnd], S)       // a \ b is b / a
  else
    F.Emit(Op, T, Dst, [A.Opnd, B.Opnd], S);
  Result := MakeValue(T, RegOperand(Dst));
end;

function TLowerer.LowerCond(E: TExpr): TJOperand;
var
  V: TJValue;
begin
  V := LowerExpr(E);
  if V.Typ <> jtBool then
    Reject('the condition is %s, not bool, a TypeError', [JTypeName(V.Typ)], E);
  Result := V.Opnd;
end;

{ ---- calls ---- }

const
  ElementaryNames: array[0..14] of string = ('sqrt', 'exp', 'log', 'sin', 'cos', 'tan',
    'asin', 'acos', 'atan', 'sinh', 'cosh', 'tanh', 'asinh', 'acosh', 'atanh');

function IsElementary(const Name: string): Boolean;
var
  N: string;
begin
  for N in ElementaryNames do
    if N = Name then
      Exit(True);
  Result := False;
end;

{ A call f(args). Want is the number of values used (1 in an expression,
  the target count in a multiple assignment), or -1 for a statement, whose
  values are discarded. }
function TLowerer.LowerCall(E: TCallExpr; Want: Integer): TArray<TJValue>;
var
  Name: string;
  R: TJResolved;
  Args: TArray<TJValue>;
  A: TArg;
  K: Integer;
  T: TJCallTarget;
  Results: TArray<TJType>;
  Ops: TArray<TJOperand>;
  Insn: TJInsn;
  Literal: Boolean;
begin
  if not (E.Callee is TNameExpr) then
    Reject('calls through an expression are not compiled', E);
  Name := TNameExpr(E.Callee).Name;
  if Lookup(Name) <> nil then
    Reject('calls the local variable %s; calls of function values are not compiled', [Name], E);
  for A in E.Args do
    if A.Kind <> akPositional then
      Reject('keyword arguments are not compiled yet', E);
  R := Session.Resolve(Context, Name);
  if R.Kind = rkNone then
    Reject('calls %s, which is not defined', [Name], E);
  if R.Kind = rkOther then
    Reject('calls %s, which is not a function', [Name], E);

  // Arguments, left to right. String literals only for print and error.
  SetLength(Args, E.Args.Count);
  for K := 0 to E.Args.Count - 1 do
  begin
    Literal := (R.Kind = rkBuiltin) and ((R.Name = 'print') or (R.Name = 'println') or
      (R.Name = 'error')) and
      (E.Args[K].Value is TStringLit);
    if Literal then
      Args[K] := MakeValue(jtString, StringOperand(TStringLit(E.Args[K].Value).Value))
    else
      Args[K] := LowerExpr(E.Args[K].Value);
  end;

  if (R.Kind = rkBuiltin) and TryInlineBuiltin(E, R.Name, Args, Want, Result) then
    Exit;

  T := TJCallTarget.Create;
  F.Targets.Add(T);
  T.Name := Name;
  T.Value := R.Value;
  T.ValuePtr := R.ValuePtr;
  if R.Kind = rkBuiltin then
    Results := LowerBuiltin(E, R.Name, Args, T, Want)
  else
    Results := LowerFunctionCall(E, R, Args, T, Want);
  T.ResultTypes := Results;

  if Want >= 0 then
  begin
    if Length(Results) <> Want then
    begin
      if Length(Results) = 0 then
        Reject('uses the result of %s, which is nothing', [Name], E)
      else
        Reject('uses %s, which returns %d values, where %d are wanted',
          [Name, Length(Results), Want], E);
    end;
  end;

  SetLength(Ops, Length(Args));
  SetLength(T.ArgTypes, Length(Args));
  for K := 0 to High(Args) do
  begin
    Ops[K] := Args[K].Opnd;
    T.ArgTypes[K] := Args[K].Typ;
  end;
  Insn := F.Emit(joCall, jtNothing, -1, Ops, F.AddSite(E.Line, E.Col));
  Insn.Target := T;
  SetLength(Insn.Dsts, Length(Results));
  SetLength(Result, 0);
  for K := 0 to High(Results) do
    if Want >= 0 then
    begin
      Insn.Dsts[K] := Temp(Results[K]);
      Result := Result + [MakeValue(Results[K], RegOperand(Insn.Dsts[K]))];
    end
    else
      Insn.Dsts[K] := -1;
end;

{ A built-in with scalar arguments, as the interpreter's own routine
  computes it (Axon.Builtins). Gives the result types. }
function TLowerer.LowerBuiltin(E: TCallExpr; const Name: string; var Args: TArray<TJValue>;
  T: TJCallTarget; Want: Integer): TArray<TJType>;
var
  N: Integer;
  A: TJValue;

  procedure NeedArgs(Count: Integer);
  begin
    if N <> Count then
      Reject('calls %s with %d argument(s), an ArgumentError', [Name, N], E);
  end;

  procedure NeedNumbers;
  var
    V: TJValue;
  begin
    for V in Args do
      if not Numeric(V.Typ) then
        Reject('passes %s to %s, which is not compiled', [JTypeName(V.Typ), Name], E);
  end;

  function Wider: TJType;
  begin
    if Max(Rank(Args[0].Typ), Rank(Args[1].Typ)) <= 1 then Result := jtInt else Result := jtReal;
  end;

begin
  T.Kind := ckBuiltin;
  N := Length(Args);
  if (Name = 'print') or (Name = 'println') then
  begin
    for A in Args do
      if not (Storable(A.Typ) or (A.Typ = jtString)) then
        Reject('prints %s, which is not compiled', [JTypeName(A.Typ)], E);
    Result := [];
  end
  else if (Name = 'zeros') or (Name = 'ones') then
  begin
    NeedNumbers;
    if N = 1 then
      Result := [jtVecReal]
    else
    begin
      NeedArgs(2);
      Result := [jtMatReal];
    end;
  end
  else if Name = 'sum' then
  begin
    NeedArgs(1);
    if not IsArrayType(Args[0].Typ) then
      Reject('sum of %s is not compiled', [JTypeName(Args[0].Typ)], E);
    Result := [ElemOf(Args[0].Typ)];
  end
  else if Name = 'error' then
  begin
    if (N < 1) or (N > 2) then
      NeedArgs(1);
    for A in Args do
      if A.Typ <> jtString then
        Reject('error with anything but string literals is not compiled', E);
    LastCallRaises := True;
    Result := [];
  end
  else if IsElementary(Name) then
  begin
    // RF(ToReal(x)), as ApplyElementary: called directly with a real.
    NeedArgs(1);
    NeedNumbers;
    Args[0] := Convert(Args[0], jtReal);
    T.Direct := True;
    Result := [jtReal];
  end
  else if Name = 'abs' then
  begin
    NeedArgs(1);
    NeedNumbers;
    if Args[0].Typ = jtReal then Result := [jtReal] else Result := [jtInt];
  end
  else if (Name = 'floor') or (Name = 'ceil') or (Name = 'round') or (Name = 'int') then
  begin
    NeedArgs(1);
    NeedNumbers;
    Result := [jtInt];
  end
  else if Name = 'real' then
  begin
    NeedArgs(1);
    NeedNumbers;
    Result := [jtReal];
  end
  else if (Name = 'min') or (Name = 'max') then
  begin
    NeedNumbers;
    if N = 1 then
      Result := [Args[0].Typ]           // min(x) of a number is x
    else
    begin
      NeedArgs(2);
      Result := [Wider];
    end;
  end
  else if (Name = 'div') or (Name = 'mod') then
  begin
    NeedArgs(2);
    NeedNumbers;
    Result := [Wider];
  end
  else
    Reject('calls the built-in %s, which is not compiled yet', [Name], E);
end;

function ArgTypesOf(const Args: TArray<TJValue>): TArray<TJType>;
var
  K: Integer;
begin
  SetLength(Result, Length(Args));
  for K := 0 to High(Args) do
    if Storable(Args[K].Typ) then
      Result[K] := Args[K].Typ
    else
      Result[K] := jtNothing;
end;

{ A call of an Axon function: direct when the callee compiles, through the
  interpreter otherwise. The callee is specialised on the argument types. }
function TLowerer.LowerFunctionCall(E: TCallExpr; const R: TJResolved; var Args: TArray<TJValue>;
  T: TJCallTarget; Want: Integer): TArray<TJType>;
var
  Callee: TJEntry;
  Compiled, Positional: Boolean;
  P: TParam;
  K: Integer;
  Why: string;
  RT: TJType;
  Params: TArray<TJType>;
begin
  Compiled := False;
  Why := '';
  Positional := True;
  for P in R.Decl.Params do
    if P.IsKeyword or (P.Default <> nil) then
      Positional := False;
  if R.IsClosure then
    Why := 'it is a closure'
  else if not Positional then
    Why := 'it has keyword or optional parameters'
  else if not SignatureFor(R.Decl, ArgTypesOf(Args), Params, Why) then
    // through the interpreter, with the reason
  else
  begin
    Callee := Session.Lower(R.Decl, R.FuncObj, R.FileName, Params);
    case Callee.State of
      esLowered:
        if Callee.Func.Captures.Count > 0 then
          Why := 'it reads values from outside'
        else
        begin
          Compiled := True;
          SetLength(Params, Callee.Func.Params.Count);
          for K := 0 to High(Params) do
            Params[K] := Callee.Func.Regs[Callee.Func.Params[K]].Typ;
          Result := Callee.Func.ResultTypes.ToArray;
        end;
      esLowering:
        if Callee = Entry then
        begin
          // Recursion: the result type must be known by now.
          if not ReturnFixed then
            Reject('calls itself before its result type is known; declare the result ' +
              'type, or return a value before the recursive call', E);
          Compiled := True;
          SetLength(Params, F.Params.Count - F.Captures.Count);
          for K := 0 to High(Params) do
            Params[K] := F.Regs[F.Params[K]].Typ;
          Result := F.ResultTypes.ToArray;
        end
        else
          Why := 'it is being compiled (mutual recursion)';
    else
      Why := Callee.Reason;
    end;
  end;

  if Compiled then
  begin
    if Length(Args) <> Length(Params) then
      Reject('passes %d argument(s) to %s, which takes %d, an ArgumentError',
        [Length(Args), R.Decl.Name, Length(Params)], E);
    for K := 0 to High(Args) do
      Args[K] := Coerce(Args[K], Params[K], Format('passes %s to parameter %s of %s, declared %s',
        [JTypeName(Args[K].Typ), R.Decl.Params[K].Name, R.Decl.Name, JTypeName(Params[K])]), E);
    T.Kind := ckCompiled;
    T.Callee := Callee;
    T.ParamTypes := Params;
    Exit;
  end;

  // Through the interpreter: the result type must be declared, or unused.
  T.Kind := ckInterp;
  for K := 0 to High(Args) do
    if not Storable(Args[K].Typ) then
      Reject('passes %s to %s, which is not compiled', [JTypeName(Args[K].Typ), R.Decl.Name], E);
  if (R.Decl.ReturnType <> nil) and TypeOfRef(R.Decl.ReturnType, RT) then
    Result := [RT]
  else if Want < 0 then
    Result := []
  else
    Reject('calls %s, which is not compiled (%s), and whose result type is not declared',
      [R.Decl.Name, Why], E);
end;

{ ---- arrays ---- }

{ The element count (Dim 0), rows (1) or columns (2) of an array. }
function TLowerer.ArrayLen(const A: TJValue; Dim: Integer): TJValue;
var
  R: Integer;
begin
  R := Temp(jtInt);
  F.Emit(joLen, jtInt, R, [A.Opnd, IntOperand(Dim)]);
  Result := MakeValue(jtInt, RegOperand(R));
end;

{ One index: an int, with `end` the length of its dimension, checked at once
  (EvalIndexItem resolves each index before the next is evaluated). }
function TLowerer.LowerIndexItem(Item: TExpr; const Len: TJValue): TJValue;
begin
  if Item is TColonExpr then
    Reject('a colon index is not compiled yet', Item);
  if Item is TRangeExpr then
    Reject('a range index is not compiled yet', Item);
  EndStack.Add(Len);
  try
    Result := LowerExpr(Item);
  finally
    EndStack.Delete(EndStack.Count - 1);
  end;
  if Result.Typ <> jtInt then
    Reject('an index of type %s is not compiled (only int)', [JTypeName(Result.Typ)], Item);
  F.Emit(joBound, jtInt, -1, [Result.Opnd, Len.Opnd], F.AddSite(Item.Line, Item.Col));
end;

{ v[i], A[k] (linear) or A[i, j]. }
function TLowerer.LowerIndex(E: TIndexExpr): TJValue;
var
  A, I, J: TJValue;
  Dst: Integer;
begin
  A := LowerExpr(E.Target);
  if not IsArrayType(A.Typ) then
    Reject('indexing %s is not compiled', [JTypeName(A.Typ)], E);
  Dst := Temp(ElemOf(A.Typ));
  if E.Items.Count = 1 then
  begin
    I := LowerIndexItem(E.Items[0], ArrayLen(A, 0));
    F.Emit(joLoad, ElemOf(A.Typ), Dst, [A.Opnd, I.Opnd]);
  end
  else if (E.Items.Count = 2) and (A.Typ = jtMatReal) then
  begin
    I := LowerIndexItem(E.Items[0], ArrayLen(A, 1));
    J := LowerIndexItem(E.Items[1], ArrayLen(A, 2));
    F.Emit(joLoad, ElemOf(A.Typ), Dst, [A.Opnd, I.Opnd, J.Opnd]);
  end
  else
    Reject('%s with %d indices, an IndexError', [JTypeName(A.Typ), E.Items.Count], E);
  Result := MakeValue(ElemOf(A.Typ), RegOperand(Dst));
end;

{ v[i] = x: the value first, then the indices, then the write, which never
  widens the array. }
procedure TLowerer.LowerIndexAssign(S: TAssignStmt);
var
  T: TIndexExpr;
  Val, A, I, J: TJValue;
  V: TJVar;
  Elem: TJType;
begin
  T := TIndexExpr(S.Target);
  Val := LowerExpr(S.Value);
  if not (T.Target is TNameExpr) then
    Reject('assignment into a nested element or field is not compiled yet', S);
  V := Lookup(TNameExpr(T.Target).Name);
  if (V = nil) or not IsAssigned(V) then
    Reject('assigns an element of %s, which is not a local array here', [TNameExpr(T.Target).Name], S);
  if not IsArrayType(V.Typ) then
    Reject('assigns an element of %s, which is %s', [V.Name, JTypeName(V.Typ)], S);
  Elem := ElemOf(V.Typ);
  if not Numeric(Val.Typ) then
    Reject('assigning %s to elements of an array is not compiled yet', [JTypeName(Val.Typ)], S);
  if Rank(Val.Typ) > Rank(Elem) then
    Reject('stores %s in %s, which would change its element type', [JTypeName(Val.Typ),
      JTypeName(V.Typ)], S);
  Val := Convert(Val, Elem);
  A := MakeValue(V.Typ, RegOperand(V.Reg));
  if T.Items.Count = 1 then
  begin
    I := LowerIndexItem(T.Items[0], ArrayLen(A, 0));
    F.Emit(joStore, Elem, -1, [A.Opnd, I.Opnd, Val.Opnd]);
  end
  else if (T.Items.Count = 2) and (V.Typ = jtMatReal) then
  begin
    I := LowerIndexItem(T.Items[0], ArrayLen(A, 1));
    J := LowerIndexItem(T.Items[1], ArrayLen(A, 2));
    F.Emit(joStore, Elem, -1, [A.Opnd, I.Opnd, J.Opnd, Val.Opnd]);
  end
  else
    Reject('%s with %d indices, an IndexError', [JTypeName(V.Typ), T.Items.Count], S);
end;

{ Operators on real arrays, computed by Axon.Ops as the interpreter does.
  The shapes that compile, and their result types:
    array op array (same type), op in + - .* ./
    array op number, number op array, op in + - * .* ./ (and / with the
      number on the right)
    matrix * matrix, matrix * vector
    -array }
function TLowerer.LowerArrayOp(E: TExpr; Op: TTokenKind; const L, R: TJValue; Unary: Boolean): TJValue;
var
  Res: TJType;
  Ok: Boolean;
  Dst: Integer;
  Tok: TJOperand;
begin
  Ok := False;
  Res := jtNothing;
  if Unary then
  begin
    Ok := L.Typ in [jtVecReal, jtMatReal];
    Res := L.Typ;
  end
  else if (L.Typ in [jtVecReal, jtMatReal]) and (L.Typ = R.Typ) and
    (Op in [tkPlus, tkMinus, tkDotStar, tkDotSlash]) then
  begin
    Ok := True;
    Res := L.Typ;
  end
  else if (L.Typ in [jtVecReal, jtMatReal]) and Numeric(R.Typ) and
    (Op in [tkPlus, tkMinus, tkStar, tkSlash, tkDotStar, tkDotSlash]) then
  begin
    Ok := True;
    Res := L.Typ;
  end
  else if Numeric(L.Typ) and (R.Typ in [jtVecReal, jtMatReal]) and
    (Op in [tkPlus, tkMinus, tkStar, tkDotStar, tkDotSlash]) then
  begin
    Ok := True;
    Res := R.Typ;
  end
  else if (L.Typ = jtMatReal) and (Op = tkStar) and (R.Typ in [jtMatReal, jtVecReal]) then
  begin
    Ok := True;
    Res := R.Typ;
  end;
  if not Ok then
    Reject('operator %s on %s and %s is not compiled', [TokenSpelling[Op], JTypeName(L.Typ),
      JTypeName(R.Typ)], E);
  Dst := Temp(Res);
  Tok := StringOperand(TokenSpelling[Op]);
  Tok.I := Ord(Op);
  if Unary then
    F.Emit(joOp, Res, Dst, [L.Opnd, Tok], Site)
  else
    F.Emit(joOp, Res, Dst, [L.Opnd, Tok, R.Opnd], Site);
  Result := MakeValue(Res, RegOperand(Dst));
end;

{ length(a), size(a, 1), size(a, 2) and [m, n] = size(a), from the array's
  shape (a vector is n×1). False when the call is not one of these. }
function TLowerer.TryInlineBuiltin(E: TCallExpr; const Name: string; const Args: TArray<TJValue>;
  Want: Integer; out Vals: TArray<TJValue>): Boolean;
var
  D: Int64;
begin
  Result := False;
  if (Length(Args) = 0) or not IsArrayType(Args[0].Typ) then
    Exit;
  if (Name = 'length') and (Length(Args) = 1) then
    Vals := [ArrayLen(Args[0], 0)]
  else if (Name = 'size') and (Length(Args) = 1) then
    Vals := [ArrayLen(Args[0], 1), ArrayLen(Args[0], 2)]
  else if (Name = 'size') and (Length(Args) = 2) and (Args[1].Opnd.Kind = jkInt) then
  begin
    D := Args[1].Opnd.I;
    if (D <> 1) and (D <> 2) then
      Exit;
    Vals := [ArrayLen(Args[0], D)];
  end
  else
    Exit;
  if (Want >= 0) and (Length(Vals) <> Want) then
    Reject('uses %s, which returns %d values, where %d are wanted', [Name, Length(Vals), Want], E);
  Result := True;
end;

{ for x in a: the elements of an array, in column-major order. The array is
  held in a hidden register for the loop, as the interpreter holds the value
  it iterates, so writes to the variable in the body copy it. }
procedure TLowerer.LowerForEach(S: TForStmt);
var
  A, N: TJValue;
  Hidden, K, K1, Cmp, LHead, LCont, LExit: Integer;
  V: TJVar;
  Before: TArray<Boolean>;
  Lp: TLoop;
  Elem: TJType;
begin
  A := LowerExpr(S.Iter);
  if not IsArrayType(A.Typ) then
    Reject('for over %s is not compiled', [JTypeName(A.Typ)], S);
  Elem := ElemOf(A.Typ);
  Hidden := Temp(A.Typ);
  F.Emit(joMov, A.Typ, Hidden, [A.Opnd]);
  A := MakeValue(A.Typ, RegOperand(Hidden));
  N := ArrayLen(A, 0);
  K := Temp(jtInt);
  F.Emit(joMov, jtInt, K, [IntOperand(0)]);
  LHead := F.NewLabel;
  LCont := F.NewLabel;
  LExit := F.NewLabel;
  F.PlaceLabel(LHead);
  Cmp := Temp(jtBool);
  F.Emit(joGe, jtInt, Cmp, [RegOperand(K), N.Opnd]);
  F.Emit(joBrTrue, jtNothing, -1, [RegOperand(Cmp), LabelOperand(LExit)]);

  Before := Copy(Assigned);
  Scopes.Add(TScopeMap.Create);
  V := NewVar(S.VarName, Elem, False, S, Scopes.Count - 1);
  MarkAssigned(V);
  K1 := Temp(jtInt);
  F.Emit(joAdd, jtInt, K1, [RegOperand(K), IntOperand(1)]);    // k < n: cannot overflow
  F.Emit(joLoad, Elem, V.Reg, [A.Opnd, RegOperand(K1)]);
  Lp.ContinueLabel := LCont;
  Lp.BreakLabel := LExit;
  Lp.Breaks := 0;
  Loops.Add(Lp);
  LowerBody(S.Body, False);
  Loops.Delete(Loops.Count - 1);
  Scopes.Delete(Scopes.Count - 1);

  F.PlaceLabel(LCont);
  F.Emit(joAdd, jtInt, K, [RegOperand(K), IntOperand(1)]);
  F.Emit(joJmp, jtNothing, -1, [LabelOperand(LHead)]);
  F.PlaceLabel(LExit);
  F.Emit(joClear, jtNothing, -1, [A.Opnd]);
  Assigned := Before;
  Reachable := True;
end;

{ ---- captures and literals ---- }

{ A value read from outside: Path[0] resolved as a call in this function
  would resolve it, then each field. Its current type is the type the code
  is compiled for; the JIT checks it again at each call. }
function TLowerer.Capture(E: TExpr; const Path: TArray<string>): TJValue;
var
  R: TJResolved;
  V: TAxValue;
  K, Idx, Reg: Integer;
  Key: string;
  T: TJType;
  C: TJCapture;
begin
  Key := string.Join('.', Path);
  if CaptureRegs.TryGetValue(Key, Reg) then
    Exit(MakeValue(F.Regs[Reg].Typ, RegOperand(Reg)));
  R := Session.Resolve(Context, Path[0]);
  if R.Kind = rkNone then
    Reject('reads %s, which is not a local variable', [Path[0]], E);
  V := R.Value;
  for K := 1 to High(Path) do
  begin
    if V.Kind <> vkRecord then
      Reject('reads %s, but %s is not a record', [Key, string.Join('.', Copy(Path, 0, K))], E);
    Idx := AsRecord(V).IndexOf(Path[K]);
    if Idx < 0 then
      Reject('reads %s, which has no field %s', [string.Join('.', Copy(Path, 0, K)), Path[K]], E);
    V := AsRecord(V).Values[Idx];
  end;
  T := JTypeOfValue(V);
  if T = jtNothing then
    Reject('reads %s, which holds %s, a type that is not compiled', [Key, TypeName(V)], E);
  if not OutsideNames.Contains(Path[0]) then
    OutsideNames.Add(Path[0]);
  Reg := F.NewReg(T, Key, True);
  F.Params.Add(Reg);
  C.Path := Path;
  C.Reg := Reg;
  C.Typ := T;
  F.Captures.Add(C);
  CaptureRegs.Add(Key, Reg);
  Result := MakeValue(T, RegOperand(Reg));
end;

{ p.a.b: a capture when p is not local; fields of local values do not compile. }
function TLowerer.LowerField(E: TFieldExpr): TJValue;
var
  Path: TArray<string>;
  X: TExpr;
begin
  Path := [E.Name];
  X := E.Target;
  while X is TFieldExpr do
  begin
    Path := [TFieldExpr(X).Name] + Path;
    X := TFieldExpr(X).Target;
  end;
  if not (X is TNameExpr) or (Lookup(TNameExpr(X).Name) <> nil) then
    Reject('field access on a local value is not compiled', E);
  Result := Capture(E, [TNameExpr(X).Name] + Path);
end;

{ [a; b], [a, b; c, d]: entries that are numbers, evaluated row by row, of
  the widest type. One entry per row gives a vector; anything else a matrix,
  which compiles when it is real. }
function TLowerer.LowerMatrix(E: TMatrixExpr): TJValue;
var
  Rows, Cols, R, C: Integer;
  Vals: TArray<TJValue>;
  V: TJValue;
  Widest, T, Elem: TJType;
  Ops: TArray<TJOperand>;
  Dst, K: Integer;
begin
  Rows := E.Rows.Count;
  if Rows = 0 then
    Reject('an empty matrix literal is not compiled', E);
  Cols := E.Rows[0].Count;
  Widest := jtBool;
  Vals := nil;
  for R := 0 to Rows - 1 do
  begin
    if E.Rows[R].Count <> Cols then
      Reject('rows of different widths, a DimensionError', E);
    for C := 0 to Cols - 1 do
    begin
      V := LowerExpr(E.Rows[R][C]);
      if not Numeric(V.Typ) then
        Reject('a matrix literal of %s entries is not compiled', [JTypeName(V.Typ)], E);
      if Rank(V.Typ) > Rank(Widest) then
        Widest := V.Typ;
      Vals := Vals + [V];
    end;
  end;
  if Cols = 1 then
  begin
    if Widest = jtReal then T := jtVecReal
    else if Widest = jtInt then T := jtVecInt
    else T := jtNothing;
  end
  else if Widest = jtReal then
    T := jtMatReal
  else
    T := jtNothing;
  if T = jtNothing then
    Reject('a literal of %s entries in %d column(s) is not compiled', [JTypeName(Widest), Cols], E);
  Elem := ElemOf(T);
  SetLength(Ops, 2 + Length(Vals));
  Ops[0] := IntOperand(Rows);
  Ops[1] := IntOperand(Cols);
  for K := 0 to High(Vals) do
    Ops[2 + K] := Convert(Vals[K], Elem).Opnd;
  Dst := Temp(T);
  F.Emit(joArray, T, Dst, Ops);
  Result := MakeValue(T, RegOperand(Dst));
end;

{ A function with captures runs nothing that could change them: no call
  through the interpreter, and no direct call to itself (which would need
  them passed on). }
procedure TLowerer.CheckCaptures;
var
  Insn: TJInsn;
  S: TJSite;
begin
  if F.Captures.Count = 0 then
    Exit;
  for Insn in F.Insns do
    if Insn.Op = joCall then
    begin
      S := F.Sites[Insn.Site];
      if Insn.Target.Kind = ckInterp then
        raise EJitReject.Create(Format('reads %s from outside and calls %s through the ' +
          'interpreter, which could change it', [F.Captures[0].Text, Insn.Target.Name]), S.Line, S.Col);
      if (Insn.Target.Kind = ckCompiled) and (Insn.Target.Callee = Entry) then
        raise EJitReject.Create(Format('reads %s from outside and calls itself', [F.Captures[0].Text]),
          S.Line, S.Col);
    end;
end;

{ ---- statements ---- }

{ Constructs anywhere in the body that change name resolution for the whole
  function are rejected before lowering. }
procedure TLowerer.CheckBodyShape(Body: TStmtList);
var
  S: TStmt;
  B: TIfBranch;
begin
  for S in Body do
  begin
    if S is TFunctionStmt then
      Reject('defines the nested function %s; nested functions are not compiled',
        [TFunctionStmt(S).Func.Name], S)
    else if (S is TDeclStmt) and TDeclStmt(S).IsGlobal then
      Reject('declares global %s; global variables are not compiled', [TDeclStmt(S).Name], S)
    else if S is TIfStmt then
    begin
      for B in TIfStmt(S).Branches do
        CheckBodyShape(B.Body);
      if TIfStmt(S).ElseBody <> nil then
        CheckBodyShape(TIfStmt(S).ElseBody);
    end
    else if S is TWhileStmt then
      CheckBodyShape(TWhileStmt(S).Body)
    else if S is TForStmt then
      CheckBodyShape(TForStmt(S).Body)
    else if S is TTryStmt then
    begin
      CheckBodyShape(TTryStmt(S).Body);
      CheckBodyShape(TTryStmt(S).CatchBody);
    end;
  end;
end;

procedure TLowerer.LowerBody(Body: TStmtList; NewScope: Boolean);
var
  S: TStmt;
begin
  if NewScope then
    Scopes.Add(TScopeMap.Create);
  for S in Body do
  begin
    // Statements after a return, break or continue never run.
    if not Reachable then
      Break;
    LowerStmt(S);
  end;
  if NewScope then
    Scopes.Delete(Scopes.Count - 1);
end;

procedure TLowerer.LowerStmt(S: TStmt);
var
  SaveLine, SaveCol: Integer;
  C: TClass;
  Lp: TLoop;
begin
  SaveLine := StmtLine;
  SaveCol := StmtCol;
  StmtLine := S.Line;
  StmtCol := S.Col;
  C := S.ClassType;
  if C = TExprStmt then
  begin
    if TExprStmt(S).Expr is TCallExpr then
    begin
      // A call as a statement: its values are discarded.
      LastCallRaises := False;
      LowerCall(TCallExpr(TExprStmt(S).Expr), -1);
      if LastCallRaises then
        Reachable := False;      // error(...) never returns
    end
    else
      LowerExpr(TExprStmt(S).Expr);
  end
  else if C = TAssignStmt then
    LowerAssign(TAssignStmt(S))
  else if C = TDeclStmt then
    LowerDecl(TDeclStmt(S))
  else if C = TReturnStmt then
    LowerReturn(TReturnStmt(S))
  else if C = TIfStmt then
    LowerIf(TIfStmt(S))
  else if C = TWhileStmt then
    LowerWhile(TWhileStmt(S))
  else if C = TForStmt then
    LowerFor(TForStmt(S))
  else if (C = TBreakStmt) or (C = TContinueStmt) then
  begin
    Lp := Loops.Last;
    if C = TBreakStmt then
    begin
      F.Emit(joJmp, jtNothing, -1, [LabelOperand(Lp.BreakLabel)]);
      Inc(Lp.Breaks);
      Loops[Loops.Count - 1] := Lp;
    end
    else
      F.Emit(joJmp, jtNothing, -1, [LabelOperand(Lp.ContinueLabel)]);
    Reachable := False;
  end
  else if C = TDestructureStmt then
    LowerDestructure(TDestructureStmt(S))
  else if C = TTryStmt then
    Reject('try is not compiled', S)
  else
    Reject('this statement is not compiled', S);
  StmtLine := SaveLine;
  StmtCol := SaveCol;
end;

procedure TLowerer.LowerAssign(S: TAssignStmt);
var
  Val: TJValue;
  Name: string;
  V: TJVar;
  T: TJType;
begin
  if S.Target is TIndexExpr then
  begin
    if S.TypeRef <> nil then
      Reject('only a plain variable can carry a type annotation, a TypeError', S);
    LowerIndexAssign(S);
    Exit;
  end;
  if not (S.Target is TNameExpr) then
    Reject('assignment to a field is not compiled yet', S);
  Name := TNameExpr(S.Target).Name;
  // The value is evaluated before the target is resolved.
  Val := LowerExpr(S.Value);
  if S.TypeRef <> nil then
  begin
    // x: T = e declares x in the current scope.
    if not TypeOfRef(S.TypeRef, T) then
      Reject('variable %s: %s', [Name, TypeHint(S.TypeRef)], S);
    if OutsideNames.Contains(Name) then
      Reject('%s is read from outside the function and declared in it', [Name], S);
    if Scopes.Last.TryGetValue(Name, V) and V.Declared and (V.Typ = T) then
      // the same declaration again: the same variable
    else if (Scopes.Count = 1) and Scopes.Last.ContainsKey(Name) then
      Reject('%s is redeclared as %s', [Name, JTypeName(T)], S)
    else
      V := NewVar(Name, T, True, S, Scopes.Count - 1);
  end
  else
  begin
    AssignName(Name, Val, S);
    Exit;
  end;
  StoreVar(V, Val, S);
end;

{ name = value: rule 5, the nearest name, or a new one in the function's
  outermost scope. }
procedure TLowerer.AssignName(const Name: string; const Val: TJValue; N: TNode);
var
  V: TJVar;
begin
  V := Lookup(Name);
  if V = nil then
  begin
    if OutsideNames.Contains(Name) then
      Reject('%s is read from outside the function and assigned in it', [Name], N);
    if Entry.IsClosure then
    begin
      // Rule 5 in a closure: an existing variable outside is assigned there.
      if Session.Resolve(Context, Name).Kind <> rkNone then
        Reject('assigns %s, a variable of an enclosing scope', [Name], N);
      F.LocalNames.Add(Name);
    end;
    V := NewVar(Name, Val.Typ, False, N, 0);
  end;
  StoreVar(V, Val, N);
end;

{ [a, b] = f(...): the call's values assigned in order, as plain assignments. }
procedure TLowerer.LowerDestructure(S: TDestructureStmt);
var
  T: TExpr;
  Vals: TArray<TJValue>;
  K: Integer;
begin
  if not (S.Value is TCallExpr) then
    Reject('multiple assignment from anything but a call is not compiled', S);
  for T in S.Targets do
    if not (T is TNameExpr) then
      Reject('multiple assignment to an element or field is not compiled yet', S);
  Vals := LowerCall(TCallExpr(S.Value), S.Targets.Count);
  for K := 0 to S.Targets.Count - 1 do
    AssignName(TNameExpr(S.Targets[K]).Name, Vals[K], S);
end;

procedure TLowerer.LowerDecl(S: TDeclStmt);
var
  Val: TJValue;
  T: TJType;
  V: TJVar;
begin
  // global is rejected by CheckBodyShape.
  if S.Value = nil then
    Reject('local %s without a value holds nothing, which is not compiled', [S.Name], S);
  Val := LowerExpr(S.Value);
  if S.TypeRef <> nil then
  begin
    if not TypeOfRef(S.TypeRef, T) then
      Reject('variable %s: %s', [S.Name, TypeHint(S.TypeRef)], S);
    V := NewVar(S.Name, T, True, S, Scopes.Count - 1);
  end
  else
  begin
    if not Storable(Val.Typ) then
      Reject('local %s holds %s, which is not compiled', [S.Name, JTypeName(Val.Typ)], S);
    V := NewVar(S.Name, Val.Typ, False, S, Scopes.Count - 1);
  end;
  StoreVar(V, Val, S);
end;

procedure TLowerer.EmitReturn(const Vals: TArray<TJValue>; N: TNode);
var
  Ops: TArray<TJOperand>;
  Types: TArray<TJType>;
  K: Integer;
  V: TJValue;
begin
  SetLength(Ops, Length(Vals));
  SetLength(Types, Length(Vals));
  if ReturnDeclared then
  begin
    if Length(Vals) <> 1 then
    begin
      if N = Decl then
        Reject('can reach the end without returning a %s', [JTypeName(F.ResultTypes[0])], N)
      else if Length(Vals) = 0 then
        Reject('returns nothing, but the result is declared %s, a TypeError',
          [JTypeName(F.ResultTypes[0])], N)
      else
        Reject('returns several values, but the result is declared %s', [JTypeName(F.ResultTypes[0])], N);
    end;
    V := Coerce(Vals[0], F.ResultTypes[0], Format('returns %s, but the result is declared %s',
      [JTypeName(Vals[0].Typ), JTypeName(F.ResultTypes[0])]), N);
    Ops[0] := V.Opnd;
  end
  else
  begin
    for K := 0 to High(Vals) do
    begin
      Ops[K] := Vals[K].Opnd;
      Types[K] := Vals[K].Typ;
    end;
    if not ReturnFixed then
    begin
      ReturnFixed := True;
      ReturnLine := N.Line;
      ReturnCol := N.Col;
      F.ResultTypes.Clear;
      F.ResultTypes.AddRange(Types);
    end
    else if TypeList(Types) <> TypeList(F.ResultTypes.ToArray) then
    begin
      if N = Decl then
        Reject('returns %s at %d:%d but can also reach the end and return nothing',
          [TypeList(F.ResultTypes.ToArray), ReturnLine, ReturnCol], N);
      Reject('returns %s at %d:%d and %s at %d:%d', [TypeList(F.ResultTypes.ToArray),
        ReturnLine, ReturnCol, TypeList(Types), N.Line, N.Col], N);
    end;
  end;
  F.Emit(joRet, jtNothing, -1, Ops);
  Reachable := False;
end;

procedure TLowerer.LowerReturn(S: TReturnStmt);
var
  Vals: TArray<TJValue>;
  K: Integer;
begin
  SetLength(Vals, S.Values.Count);
  for K := 0 to S.Values.Count - 1 do
  begin
    Vals[K] := LowerExpr(S.Values[K]);
    if not Storable(Vals[K].Typ) then
      Reject('returns %s, which is not compiled', [JTypeName(Vals[K].Typ)], S);
  end;
  EmitReturn(Vals, S);
end;

{ Definitely-assigned sets: the intersection over the paths that reach the
  end of the if. }
procedure TLowerer.LowerIf(S: TIfStmt);
var
  Before, Out: TArray<Boolean>;
  AnyOut: Boolean;
  LEnd, LNext: Integer;
  Br: TIfBranch;
  Cond: TJOperand;

  procedure MergeOut;
  var
    K: Integer;
  begin
    if not AnyOut then
      Out := Copy(Assigned)
    else
    begin
      if Length(Assigned) < Length(Out) then
        SetLength(Out, Length(Assigned));
      for K := 0 to High(Out) do
        Out[K] := Out[K] and Assigned[K];
    end;
    AnyOut := True;
  end;

begin
  LEnd := F.NewLabel;
  AnyOut := False;
  for Br in S.Branches do
  begin
    Cond := LowerCond(Br.Cond);
    Before := Copy(Assigned);
    LNext := F.NewLabel;
    F.Emit(joBrFalse, jtNothing, -1, [Cond, LabelOperand(LNext)]);
    LowerBody(Br.Body, True);
    if Reachable then
    begin
      F.Emit(joJmp, jtNothing, -1, [LabelOperand(LEnd)]);
      MergeOut;
    end;
    F.PlaceLabel(LNext);
    Reachable := True;
    Assigned := Before;
  end;
  if S.ElseBody <> nil then
  begin
    LowerBody(S.ElseBody, True);
    if Reachable then
      MergeOut;
  end
  else
    MergeOut;     // no branch taken
  F.PlaceLabel(LEnd);
  Reachable := AnyOut;
  if AnyOut then
    Assigned := Out;
end;

procedure TLowerer.LowerWhile(S: TWhileStmt);
var
  LHead, LExit: Integer;
  Cond: TJOperand;
  Before: TArray<Boolean>;
  Lp: TLoop;
  Forever: Boolean;
begin
  LHead := F.NewLabel;
  LExit := F.NewLabel;
  F.PlaceLabel(LHead);
  Cond := LowerCond(S.Cond);
  Forever := (Cond.Kind = jkBool) and Cond.B;
  F.Emit(joBrFalse, jtNothing, -1, [Cond, LabelOperand(LExit)]);
  Before := Copy(Assigned);
  Lp.ContinueLabel := LHead;
  Lp.BreakLabel := LExit;
  Lp.Breaks := 0;
  Loops.Add(Lp);
  LowerBody(S.Body, True);
  if Reachable then
    F.Emit(joJmp, jtNothing, -1, [LabelOperand(LHead)]);
  Lp := Loops.Last;
  Loops.Delete(Loops.Count - 1);
  F.PlaceLabel(LExit);
  Assigned := Before;
  // `while true` without a break never falls through.
  Reachable := not Forever or (Lp.Breaks > 0);
end;

{ for v in a:h:b. The bounds are evaluated once, in the order start, step,
  stop, and the element count fixed then, as MakeRange does; element k is
  start + k*step, as TRangeObj.ItemAt computes it. The loop variable is a
  fresh variable of the body's scope. }
procedure TLowerer.LowerFor(S: TForStmt);
var
  StartE, StepE, StopE: TExpr;
  C: TCallExpr;
  Res: TJResolved;
  A, H, B: TJValue;
  T: TJType;
  N, K, Cmp, LHead, LCont, LExit: Integer;
  V: TJVar;
  Before: TArray<Boolean>;
  Lp: TLoop;
begin
  // a:h:b, or the built-in range(a, b) / range(a, b, h), which is the same.
  StartE := nil;
  StepE := nil;
  StopE := nil;
  if S.Iter is TRangeExpr then
  begin
    StartE := TRangeExpr(S.Iter).Start;
    StepE := TRangeExpr(S.Iter).Step;
    StopE := TRangeExpr(S.Iter).Stop;
  end
  else if S.Iter is TCallExpr then
  begin
    C := TCallExpr(S.Iter);
    if (C.Callee is TNameExpr) and (TNameExpr(C.Callee).Name = 'range') and
      (Lookup('range') = nil) and (C.Args.Count in [1, 2, 3]) and
      (C.Args[0].Kind = akPositional) and
      ((C.Args.Count < 2) or (C.Args[1].Kind = akPositional)) and
      ((C.Args.Count < 3) or (C.Args[2].Kind = akPositional)) then
    begin
      Res := Session.Resolve(Context, 'range');
      if (Res.Kind = rkBuiltin) and (Res.Name = 'range') then
        if C.Args.Count = 1 then
        begin
          StartE := nil;                  // 1, set below
          StopE := C.Args[0].Value;
        end
        else
        begin
          StartE := C.Args[0].Value;
          StopE := C.Args[1].Value;
          if C.Args.Count = 3 then
            StepE := C.Args[2].Value;
        end;
    end;
  end;
  if (StartE = nil) and (StopE = nil) then
  begin
    LowerForEach(S);
    Exit;
  end;
  // Evaluated left to right as written: range(a, b, h) evaluates b before h;
  // range(n) starts at 1.
  if StartE = nil then
    A := MakeValue(jtInt, IntOperand(1))
  else
    A := LowerExpr(StartE);
  if S.Iter is TRangeExpr then
  begin
    if StepE <> nil then
      H := LowerExpr(StepE)
    else
      H := MakeValue(jtInt, IntOperand(1));
    B := LowerExpr(StopE);
  end
  else
  begin
    B := LowerExpr(StopE);
    if StepE <> nil then
      H := LowerExpr(StepE)
    else
      H := MakeValue(jtInt, IntOperand(1));
  end;
  if not Numeric(A.Typ) or not Numeric(H.Typ) or not Numeric(B.Typ) then
    Reject('range bounds must be numbers, a TypeError', S);
  if Max(Rank(A.Typ), Max(Rank(H.Typ), Rank(B.Typ))) <= 1 then T := jtInt else T := jtReal;
  A := Copied(Convert(A, T));
  H := Copied(Convert(H, T));
  B := Convert(B, T);

  N := Temp(jtInt);
  F.Emit(joCount, T, N, [A.Opnd, H.Opnd, B.Opnd], Site);
  K := Temp(jtInt);
  F.Emit(joMov, jtInt, K, [IntOperand(0)]);
  LHead := F.NewLabel;
  LCont := F.NewLabel;
  LExit := F.NewLabel;
  F.PlaceLabel(LHead);
  Cmp := Temp(jtBool);
  F.Emit(joGe, jtInt, Cmp, [RegOperand(K), RegOperand(N)]);
  F.Emit(joBrTrue, jtNothing, -1, [RegOperand(Cmp), LabelOperand(LExit)]);

  Before := Copy(Assigned);
  Scopes.Add(TScopeMap.Create);
  V := NewVar(S.VarName, T, False, S, Scopes.Count - 1);
  MarkAssigned(V);
  F.Emit(joElem, T, V.Reg, [A.Opnd, H.Opnd, RegOperand(K)]);
  Lp.ContinueLabel := LCont;
  Lp.BreakLabel := LExit;
  Lp.Breaks := 0;
  Loops.Add(Lp);
  LowerBody(S.Body, False);
  Loops.Delete(Loops.Count - 1);
  Scopes.Delete(Scopes.Count - 1);

  F.PlaceLabel(LCont);
  F.Emit(joAdd, jtInt, K, [RegOperand(K), IntOperand(1)]);    // k < n: cannot overflow
  F.Emit(joJmp, jtNothing, -1, [LabelOperand(LHead)]);
  F.PlaceLabel(LExit);
  Assigned := Before;
  Reachable := True;
end;

function TLowerer.Run: TJFunction;
var
  P: TParam;
  T: TJType;
  V: TJVar;
  K: Integer;
begin
  F := TJFunction.Create(Decl.Name);
  Scopes.Add(TScopeMap.Create);
  for K := 0 to Decl.Params.Count - 1 do
  begin
    P := Decl.Params[K];
    // The types come from SignatureFor; jtNothing when none was given.
    if (K > High(ParamTypes)) or (ParamTypes[K] = jtNothing) then
    begin
      if P.TypeRef = nil then
        Reject('parameter %s has no type annotation (it is compiled when called, for the ' +
          'argument types)', [P.Name], P);
      Reject('parameter %s: %s', [P.Name, TypeHint(P.TypeRef)], P);
    end;
    T := ParamTypes[K];
    // An unannotated parameter is an untyped variable.
    V := NewVar(P.Name, T, P.TypeRef <> nil, P, 0, True);
    MarkAssigned(V);
    F.Params.Add(V.Reg);
  end;
  if Decl.ReturnType <> nil then
  begin
    if not TypeOfRef(Decl.ReturnType, T) then
      Reject('result: %s', [TypeHint(Decl.ReturnType)], Decl.ReturnType);
    F.ResultTypes.Add(T);
    ReturnDeclared := True;
    ReturnFixed := True;
  end;
  CheckBodyShape(Decl.Body);
  StmtLine := Decl.Line;
  StmtCol := Decl.Col;
  Reachable := True;
  LowerBody(Decl.Body, False);
  // Reaching the final end returns nothing.
  if Reachable then
    EmitReturn([], Decl);
  CheckCaptures;
  Result := F;
  F := nil;
end;

{ TJEntry }

destructor TJEntry.Destroy;
begin
  Func.Free;
  inherited;
end;

{ TJSession }

constructor TJSession.Create(const AResolver: TJResolver);
begin
  inherited Create;
  Resolver := AResolver;
  Entries := TObjectDictionary<string, TJEntry>.Create([doOwnsValues]);
  Order := TList<TJEntry>.Create;
  Counts := TDictionary<TFunctionDecl, Integer>.Create;
end;

destructor TJSession.Destroy;
begin
  Counts.Free;
  Order.Free;
  Entries.Free;
  inherited;
end;

function TypesText(const Types: TArray<TJType>): string;
var
  K: Integer;
begin
  Result := '';
  for K := 0 to High(Types) do
  begin
    if K > 0 then
      Result := Result + ', ';
    Result := Result + JTypeName(Types[K]);
  end;
end;

function SignatureKey(Decl: TFunctionDecl; const Types: TArray<TJType>): string;
begin
  Result := IntToHex(NativeInt(Decl), 16) + '(' + TypesText(Types) + ')';
end;

function AnnotatedTypes(Decl: TFunctionDecl): TArray<TJType>;
var
  K: Integer;
  T: TJType;
begin
  SetLength(Result, Decl.Params.Count);
  for K := 0 to Decl.Params.Count - 1 do
    if (Decl.Params[K].TypeRef <> nil) and TypeOfRef(Decl.Params[K].TypeRef, T) then
      Result[K] := T
    else
      Result[K] := jtNothing;
end;

function IsSpecialised(Decl: TFunctionDecl): Boolean;
var
  P: TParam;
begin
  for P in Decl.Params do
    if (P.TypeRef = nil) or ((P.TypeRef.Param = nil) and
      ((P.TypeRef.Name = 'vector') or (P.TypeRef.Name = 'matrix'))) then
      Exit(True);
  Result := False;
end;

function SignatureFor(Decl: TFunctionDecl; const ArgTypes: TArray<TJType>;
  out ParamTypes: TArray<TJType>; out Reason: string): Boolean;
var
  K: Integer;
  P: TParam;
  T, A: TJType;
begin
  Reason := '';
  SetLength(ParamTypes, Decl.Params.Count);
  if Length(ArgTypes) <> Decl.Params.Count then
  begin
    Reason := Format('it takes %d argument(s), not %d', [Decl.Params.Count, Length(ArgTypes)]);
    Exit(False);
  end;
  for K := 0 to Decl.Params.Count - 1 do
  begin
    P := Decl.Params[K];
    A := ArgTypes[K];
    if (P.TypeRef <> nil) and TypeOfRef(P.TypeRef, T) then
      ParamTypes[K] := T
    else if (P.TypeRef <> nil) and (P.TypeRef.Param = nil) and (P.TypeRef.Name = 'vector') and
      (A in [jtVecReal, jtVecInt]) then
      ParamTypes[K] := A
    else if (P.TypeRef <> nil) and (P.TypeRef.Param = nil) and (P.TypeRef.Name = 'matrix') and
      (A = jtMatReal) then
      ParamTypes[K] := A
    else if (P.TypeRef = nil) and (A <> jtNothing) then
      ParamTypes[K] := A
    else
    begin
      if P.TypeRef <> nil then
        Reason := Format('parameter %s: %s', [P.Name, TypeHint(P.TypeRef)])
      else
        Reason := Format('parameter %s is passed a value of a type that is not compiled', [P.Name]);
      Exit(False);
    end;
  end;
  Result := True;
end;

function TJSession.Resolve(Context: TObject; const Name: string): TJResolved;
var
  F: TJResolver;
begin
  F := Resolver;
  if Assigned(F) then
    Result := F(Context, Name)
  else
    Result := Default(TJResolved);
end;

function TJSession.Lower(Decl: TFunctionDecl; FuncObj: TObject; const FileName: string;
  const ParamTypes: TArray<TJType>; IsClosure: Boolean): TJEntry;
var
  L: TLowerer;
  Key: string;
  N: Integer;
begin
  Key := SignatureKey(Decl, ParamTypes);
  if Entries.TryGetValue(Key, Result) then
    Exit;
  Result := TJEntry.Create;
  Result.Decl := Decl;
  Result.ParamTypes := ParamTypes;
  Result.FuncObj := FuncObj;
  Result.FileName := FileName;
  Result.IsClosure := IsClosure;
  Result.State := esLowering;
  Entries.Add(Key, Result);
  Order.Add(Result);
  if not Counts.TryGetValue(Decl, N) then
    N := 0;
  Inc(N);
  Counts.AddOrSetValue(Decl, N);
  if N > MaxSpecialisations then
  begin
    Result.State := esRejected;
    Result.Reason := Format('more than %d sets of argument types', [MaxSpecialisations]);
    Result.RejectLine := Decl.Line;
    Result.RejectCol := Decl.Col;
    Exit;
  end;
  L := TLowerer.Create(Decl, Self, Result, FuncObj);
  L.ParamTypes := ParamTypes;
  try
    try
      Result.Func := L.Run;
      Result.State := esLowered;
    except
      on E: EJitReject do
      begin
        Result.State := esRejected;
        Result.Reason := E.Message;
        Result.RejectLine := E.Line;
        Result.RejectCol := E.Col;
      end;
    end;
  finally
    L.Free;
  end;
end;

end.
