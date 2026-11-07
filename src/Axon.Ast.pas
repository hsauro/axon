unit Axon.Ast;

(* Syntax tree produced by Axon.Parser.

  Every node records the line and column of its first token. Parents own
  their children: freeing a node frees its whole subtree. *)

interface

uses
  System.Generics.Collections,
  Axon.Tokens;

type
  TNode = class
  public
    Line: Integer;
    Col: Integer;
    procedure SetPos(const T: TToken);
  end;

  (* ---- Types in annotations: IDENT [ "{" type "}" ] ---- *)

  TTypeRef = class(TNode)
  public
    Name: string;
    Param: TTypeRef;   // nil unless the form is name{param}
    destructor Destroy; override;
    function ToString: string; override;
  end;

  (* ---- Expressions ---- *)

  TExpr = class(TNode);
  TExprList = TObjectList<TExpr>;

  TIntLit = class(TExpr)
  public
    Value: Int64;
  end;

  TRealLit = class(TExpr)
  public
    Value: Double;
    Text: string;      // literal as written, without '_'
  end;

  TImagLit = class(TExpr)
  public
    Value: Double;     // the imaginary part
    Text: string;      // literal as written, without '_', including 'i'
  end;

  TStringLit = class(TExpr)
  public
    Value: string;
  end;

  TBoolLit = class(TExpr)
  public
    Value: Boolean;
  end;

  TNothingLit = class(TExpr);

  TNameExpr = class(TExpr)
  public
    Name: string;
  end;

  (* `end` inside index brackets. *)
  TEndExpr = class(TExpr);

  (* A lone `:` in an index list: the whole dimension. *)
  TColonExpr = class(TExpr);

  (* Prefix -, +, not, and postfix ' (transpose). *)
  TUnaryExpr = class(TExpr)
  public
    Op: TTokenKind;    // tkMinus, tkPlus, tkNot or tkQuote
    Operand: TExpr;
    destructor Destroy; override;
  end;

  (* Arithmetic, comparison, and/or. *)
  TBinaryExpr = class(TExpr)
  public
    Op: TTokenKind;
    Left, Right: TExpr;
    destructor Destroy; override;
  end;

  (* a:b or a:h:b. *)
  TRangeExpr = class(TExpr)
  public
    Start, Step, Stop: TExpr;   // Step is nil for a:b
    destructor Destroy; override;
  end;

  TArgKind = (akPositional, akKeyword, akPair);

  TArg = class(TNode)
  public
    Kind: TArgKind;
    Name: string;      // akKeyword
    Key: TExpr;        // akPair
    Value: TExpr;
    destructor Destroy; override;
  end;

  TCallExpr = class(TExpr)
  public
    Callee: TExpr;
    Args: TObjectList<TArg>;
    constructor Create;
    destructor Destroy; override;
  end;

  TIndexExpr = class(TExpr)
  public
    Target: TExpr;
    Items: TExprList;
    constructor Create;
    destructor Destroy; override;
  end;

  TFieldExpr = class(TExpr)
  public
    Target: TExpr;
    Name: string;
    destructor Destroy; override;
  end;

  TMatrixExpr = class(TExpr)
  public
    Rows: TObjectList<TExprList>;
    constructor Create;
    destructor Destroy; override;
  end;

  TListExpr = class(TExpr)
  public
    Items: TExprList;
    constructor Create;
    destructor Destroy; override;
  end;

  TRecordExpr = class(TExpr)
  public
    Names: TList<string>;
    Values: TExprList;
    constructor Create;
    destructor Destroy; override;
  end;

  (* ---- Statements ---- *)

  TStmt = class(TNode)
  public
    Silent: Boolean;   // followed by ";": the REPL does not display its value
  end;
  TStmtList = TObjectList<TStmt>;

  TParam = class(TNode)
  public
    Name: string;
    TypeRef: TTypeRef;   // nil if unannotated
    Default: TExpr;      // keyword parameters only
    IsKeyword: Boolean;
    destructor Destroy; override;
  end;

  (* Shared by named functions and lambdas. *)
  TFunctionDecl = class(TNode)
  public
    Name: string;        // '' for a lambda
    Params: TObjectList<TParam>;
    ReturnType: TTypeRef;
    Body: TStmtList;
    Exported: Boolean;
    Doc: TList<string>;  // docstring lines
    constructor Create;
    destructor Destroy; override;
  end;

  TLambdaExpr = class(TExpr)
  public
    Func: TFunctionDecl;
    destructor Destroy; override;
  end;

  TExprStmt = class(TStmt)
  public
    Expr: TExpr;
    destructor Destroy; override;
  end;

  (* target [: type] = value, where target is a name, index or field. *)
  TAssignStmt = class(TStmt)
  public
    Target: TExpr;
    TypeRef: TTypeRef;
    Value: TExpr;
    destructor Destroy; override;
  end;

  (* [a, b] = value *)
  TDestructureStmt = class(TStmt)
  public
    Targets: TExprList;
    Value: TExpr;
    constructor Create;
    destructor Destroy; override;
  end;

  (* local x [: T] [= e]  or  global x [: T] [= e] *)
  TDeclStmt = class(TStmt)
  public
    IsGlobal: Boolean;
    Name: string;
    TypeRef: TTypeRef;
    Value: TExpr;        // may be nil
    destructor Destroy; override;
  end;

  TReturnStmt = class(TStmt)
  public
    Values: TExprList;
    constructor Create;
    destructor Destroy; override;
  end;

  TBreakStmt = class(TStmt);
  TContinueStmt = class(TStmt);

  TIfBranch = class(TNode)
  public
    Cond: TExpr;
    Body: TStmtList;
    constructor Create;
    destructor Destroy; override;
  end;

  TIfStmt = class(TStmt)
  public
    Branches: TObjectList<TIfBranch>;  // the if, then each elseif
    ElseBody: TStmtList;               // nil when there is no else
    constructor Create;
    destructor Destroy; override;
  end;

  TForStmt = class(TStmt)
  public
    VarName: string;
    Iter: TExpr;
    Body: TStmtList;
    constructor Create;
    destructor Destroy; override;
  end;

  TWhileStmt = class(TStmt)
  public
    Cond: TExpr;
    Body: TStmtList;
    constructor Create;
    destructor Destroy; override;
  end;

  TTryStmt = class(TStmt)
  public
    Body: TStmtList;
    CatchName: string;     // '' when catch has no name
    CatchBody: TStmtList;
    constructor Create;
    destructor Destroy; override;
  end;

  TFunctionStmt = class(TStmt)
  public
    Func: TFunctionDecl;
    destructor Destroy; override;
  end;

  TFieldDecl = class(TNode)
  public
    Name: string;
    TypeRef: TTypeRef;
    destructor Destroy; override;
  end;

  TRecordStmt = class(TStmt)
  public
    Name: string;
    Fields: TObjectList<TFieldDecl>;
    Exported: Boolean;
    Doc: TList<string>;
    constructor Create;
    destructor Destroy; override;
  end;

  (* import a.b [as x]   or   from a.b import x, y *)
  TImportStmt = class(TStmt)
  public
    Module: string;        // dotted name
    Alias: string;
    IsFrom: Boolean;
    Names: TList<string>;
    constructor Create;
    destructor Destroy; override;
  end;

  (* ---- extern blocks ---- *)

  TCTypeKind = (ctNamed, ctRef, ctPtr, ctCallback);

  TCParam = class;

  TCType = class(TNode)
  public
    Kind: TCTypeKind;
    Name: string;                    // ctNamed
    Inner: TCType;                   // ctRef, ctPtr
    Params: TObjectList<TCParam>;    // ctCallback
    ResultType: TCType;              // ctCallback; may be nil
    destructor Destroy; override;
  end;

  TCParam = class(TNode)
  public
    Name: string;
    CType: TCType;
    destructor Destroy; override;
  end;

  TExternItem = class(TNode);

  TExternFunc = class(TExternItem)
  public
    Name: string;
    Params: TObjectList<TCParam>;
    ResultType: TCType;  // nil for void
    Symbol: string;      // from `name "..."`, '' if absent
    constructor Create;
    destructor Destroy; override;
  end;

  TExternType = class(TExternItem)
  public
    Name: string;
    CType: TCType;
    destructor Destroy; override;
  end;

  TExternStmt = class(TStmt)
  public
    LibName: string;
    Items: TObjectList<TExternItem>;
    constructor Create;
    destructor Destroy; override;
  end;

  TProgram = class(TNode)
  public
    FileName: string;
    Body: TStmtList;
    constructor Create;
    destructor Destroy; override;
  end;

implementation

(* TNode *)

procedure TNode.SetPos(const T: TToken);
begin
  Line := T.Line;
  Col := T.Col;
end;

(* TTypeRef *)

destructor TTypeRef.Destroy;
begin
  Param.Free;
  inherited;
end;

function TTypeRef.ToString: string;
begin
  Result := Name;
  if Param <> nil then
    Result := Result + '{' + Param.ToString + '}';
end;

(* Expressions *)

destructor TUnaryExpr.Destroy;
begin
  Operand.Free;
  inherited;
end;

destructor TBinaryExpr.Destroy;
begin
  Left.Free;
  Right.Free;
  inherited;
end;

destructor TRangeExpr.Destroy;
begin
  Start.Free;
  Step.Free;
  Stop.Free;
  inherited;
end;

destructor TArg.Destroy;
begin
  Key.Free;
  Value.Free;
  inherited;
end;

constructor TCallExpr.Create;
begin
  inherited;
  Args := TObjectList<TArg>.Create;
end;

destructor TCallExpr.Destroy;
begin
  Callee.Free;
  Args.Free;
  inherited;
end;

constructor TIndexExpr.Create;
begin
  inherited;
  Items := TExprList.Create;
end;

destructor TIndexExpr.Destroy;
begin
  Target.Free;
  Items.Free;
  inherited;
end;

destructor TFieldExpr.Destroy;
begin
  Target.Free;
  inherited;
end;

constructor TMatrixExpr.Create;
begin
  inherited;
  Rows := TObjectList<TExprList>.Create;
end;

destructor TMatrixExpr.Destroy;
begin
  Rows.Free;
  inherited;
end;

constructor TListExpr.Create;
begin
  inherited;
  Items := TExprList.Create;
end;

destructor TListExpr.Destroy;
begin
  Items.Free;
  inherited;
end;

constructor TRecordExpr.Create;
begin
  inherited;
  Names := TList<string>.Create;
  Values := TExprList.Create;
end;

destructor TRecordExpr.Destroy;
begin
  Names.Free;
  Values.Free;
  inherited;
end;

(* Functions *)

destructor TParam.Destroy;
begin
  TypeRef.Free;
  Default.Free;
  inherited;
end;

constructor TFunctionDecl.Create;
begin
  inherited;
  Params := TObjectList<TParam>.Create;
  Body := TStmtList.Create;
  Doc := TList<string>.Create;
end;

destructor TFunctionDecl.Destroy;
begin
  Params.Free;
  ReturnType.Free;
  Body.Free;
  Doc.Free;
  inherited;
end;

destructor TLambdaExpr.Destroy;
begin
  Func.Free;
  inherited;
end;

(* Statements *)

destructor TExprStmt.Destroy;
begin
  Expr.Free;
  inherited;
end;

destructor TAssignStmt.Destroy;
begin
  Target.Free;
  TypeRef.Free;
  Value.Free;
  inherited;
end;

constructor TDestructureStmt.Create;
begin
  inherited;
  Targets := TExprList.Create;
end;

destructor TDestructureStmt.Destroy;
begin
  Targets.Free;
  Value.Free;
  inherited;
end;

destructor TDeclStmt.Destroy;
begin
  TypeRef.Free;
  Value.Free;
  inherited;
end;

constructor TReturnStmt.Create;
begin
  inherited;
  Values := TExprList.Create;
end;

destructor TReturnStmt.Destroy;
begin
  Values.Free;
  inherited;
end;

constructor TIfBranch.Create;
begin
  inherited;
  Body := TStmtList.Create;
end;

destructor TIfBranch.Destroy;
begin
  Cond.Free;
  Body.Free;
  inherited;
end;

constructor TIfStmt.Create;
begin
  inherited;
  Branches := TObjectList<TIfBranch>.Create;
end;

destructor TIfStmt.Destroy;
begin
  Branches.Free;
  ElseBody.Free;
  inherited;
end;

constructor TForStmt.Create;
begin
  inherited;
  Body := TStmtList.Create;
end;

destructor TForStmt.Destroy;
begin
  Iter.Free;
  Body.Free;
  inherited;
end;

constructor TWhileStmt.Create;
begin
  inherited;
  Body := TStmtList.Create;
end;

destructor TWhileStmt.Destroy;
begin
  Cond.Free;
  Body.Free;
  inherited;
end;

constructor TTryStmt.Create;
begin
  inherited;
  Body := TStmtList.Create;
  CatchBody := TStmtList.Create;
end;

destructor TTryStmt.Destroy;
begin
  Body.Free;
  CatchBody.Free;
  inherited;
end;

destructor TFunctionStmt.Destroy;
begin
  Func.Free;
  inherited;
end;

destructor TFieldDecl.Destroy;
begin
  TypeRef.Free;
  inherited;
end;

constructor TRecordStmt.Create;
begin
  inherited;
  Fields := TObjectList<TFieldDecl>.Create;
  Doc := TList<string>.Create;
end;

destructor TRecordStmt.Destroy;
begin
  Fields.Free;
  Doc.Free;
  inherited;
end;

constructor TImportStmt.Create;
begin
  inherited;
  Names := TList<string>.Create;
end;

destructor TImportStmt.Destroy;
begin
  Names.Free;
  inherited;
end;

(* extern *)

destructor TCType.Destroy;
begin
  Inner.Free;
  Params.Free;
  ResultType.Free;
  inherited;
end;

destructor TCParam.Destroy;
begin
  CType.Free;
  inherited;
end;

constructor TExternFunc.Create;
begin
  inherited;
  Params := TObjectList<TCParam>.Create;
end;

destructor TExternFunc.Destroy;
begin
  Params.Free;
  ResultType.Free;
  inherited;
end;

destructor TExternType.Destroy;
begin
  CType.Free;
  inherited;
end;

constructor TExternStmt.Create;
begin
  inherited;
  Items := TObjectList<TExternItem>.Create;
end;

destructor TExternStmt.Destroy;
begin
  Items.Free;
  inherited;
end;

(* TProgram *)

constructor TProgram.Create;
begin
  inherited;
  Body := TStmtList.Create;
end;

destructor TProgram.Destroy;
begin
  Body.Free;
  inherited;
end;

end.
