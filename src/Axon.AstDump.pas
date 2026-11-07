unit Axon.AstDump;

(* `axon --ast` output: S-expressions.

  Each statement is on its own line. A statement with a body prints its header,
  then its body statements on the following lines indented by two more spaces,
  and the closing ")" at the end of the last line. Expressions print inline,
  except that a lambda's body goes on indented lines in the same way.

  Statements
    x = e                 (= x e)            typed: (= x:real e)
    [a, b] = e            (= [a b] e)
    local x: T = e        (local x:T e)      global likewise
    return a, b           (return a b)
    break / continue      (break) (continue)
    if / elseif / else    (if c ... (elseif c ...) (else ...))
    for i in e            (for i e ...)
    while c               (while c ...)
    try ... catch err     (try ... (catch err ...))
    function f(x; k=1): T (function f (x ; k=1) :T ...)   exported: (export function ...)
                          a docstring is a first child (doc "line" ...)
    record R              (record R a:real ...)
    import m.n as x       (import m.n as x)
    from m import a, b    (from m import a b)
    extern "lib"          (extern "lib" (function f (n:(ref int32)) :float64 name "f_") (type T ...))
    expression            printed as the expression itself

  Expressions
    literals              42  2.5  2i  "s"  true  false  nothing
    names, end, :         x  end  :
    unary                 (- x)  (+ x)  (not x)  (' A)
    binary                (+ a b)  (.* a b)  (== a b)  (and a b) ...
    range                 (: a b)  (: a h b)
    call                  (call f a k=1 (=> "key" v))
    index, field          (index A i j)  (. r name)
    matrix                (matrix (1 2) (3 4))  []: (matrix)
    list, record          (list 1 2)  (rec a:1 b:2)
    lambda                (lambda (x) ...) *)

interface

uses
  Axon.Ast;

function DumpProgram(P: TProgram): string;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  Axon.Tokens;

type
  TDumper = class
  private
    SB: TStringBuilder;
    Indent: Integer;
    procedure NewLine;
    procedure W(const S: string);
    procedure Expr(E: TExpr);
    procedure Exprs(L: TExprList);
    procedure TypeSuffix(T: TTypeRef);
    procedure Params(F: TFunctionDecl);
    procedure Body(L: TStmtList);
    procedure Docs(L: TList<string>);
    procedure CType(C: TCType);
    procedure CParams(L: TObjectList<TCParam>);
    procedure Stmt(S: TStmt);
  public
    constructor Create;
    destructor Destroy; override;
  end;

constructor TDumper.Create;
begin
  inherited;
  SB := TStringBuilder.Create;
end;

destructor TDumper.Destroy;
begin
  SB.Free;
  inherited;
end;

procedure TDumper.NewLine;
begin
  SB.Append(#10).Append(StringOfChar(' ', Indent));
end;

procedure TDumper.W(const S: string);
begin
  SB.Append(S);
end;

procedure TDumper.TypeSuffix(T: TTypeRef);
begin
  if T <> nil then
    W(':' + T.ToString);
end;

procedure TDumper.Exprs(L: TExprList);
var
  E: TExpr;
begin
  for E in L do
  begin
    W(' ');
    Expr(E);
  end;
end;

(* Statements of a body, each on a new line two spaces further in. *)
procedure TDumper.Body(L: TStmtList);
var
  S: TStmt;
begin
  Inc(Indent, 2);
  for S in L do
  begin
    NewLine;
    Stmt(S);
  end;
  Dec(Indent, 2);
end;

procedure TDumper.Docs(L: TList<string>);
var
  S: string;
begin
  if L.Count = 0 then
    Exit;
  Inc(Indent, 2);
  NewLine;
  W('(doc');
  for S in L do
    W(' ' + EscapeString(S));
  W(')');
  Dec(Indent, 2);
end;

procedure TDumper.Params(F: TFunctionDecl);
var
  P: TParam;
  First, InKeywords: Boolean;
begin
  W('(');
  First := True;
  InKeywords := False;
  for P in F.Params do
  begin
    if P.IsKeyword and not InKeywords then
    begin
      if not First then W(' ');
      W(';');
      InKeywords := True;
      First := False;
    end;
    if not First then W(' ');
    First := False;
    W(P.Name);
    TypeSuffix(P.TypeRef);
    if P.Default <> nil then
    begin
      W('=');
      Expr(P.Default);
    end;
  end;
  W(')');
  if F.ReturnType <> nil then
    W(' :' + F.ReturnType.ToString);
end;

procedure TDumper.Expr(E: TExpr);
var
  A: TArg;
  Row: TExprList;
  I: Integer;
begin
  if E is TIntLit then
    W(IntToStr(TIntLit(E).Value))
  else if E is TRealLit then
    W(TRealLit(E).Text)
  else if E is TImagLit then
    W(TImagLit(E).Text)
  else if E is TStringLit then
    W(EscapeString(TStringLit(E).Value))
  else if E is TBoolLit then
    W(BoolToStr(TBoolLit(E).Value, True).ToLower)
  else if E is TNothingLit then
    W('nothing')
  else if E is TNameExpr then
    W(TNameExpr(E).Name)
  else if E is TEndExpr then
    W('end')
  else if E is TColonExpr then
    W(':')
  else if E is TUnaryExpr then
  begin
    W('(' + TokenSpelling[TUnaryExpr(E).Op] + ' ');
    Expr(TUnaryExpr(E).Operand);
    W(')');
  end
  else if E is TBinaryExpr then
  begin
    W('(' + TokenSpelling[TBinaryExpr(E).Op] + ' ');
    Expr(TBinaryExpr(E).Left);
    W(' ');
    Expr(TBinaryExpr(E).Right);
    W(')');
  end
  else if E is TRangeExpr then
  begin
    W('(: ');
    Expr(TRangeExpr(E).Start);
    if TRangeExpr(E).Step <> nil then
    begin
      W(' ');
      Expr(TRangeExpr(E).Step);
    end;
    W(' ');
    Expr(TRangeExpr(E).Stop);
    W(')');
  end
  else if E is TCallExpr then
  begin
    W('(call ');
    Expr(TCallExpr(E).Callee);
    for A in TCallExpr(E).Args do
    begin
      W(' ');
      case A.Kind of
        akPositional: Expr(A.Value);
        akKeyword:
          begin
            W(A.Name + '=');
            Expr(A.Value);
          end;
        akPair:
          begin
            W('(=> ');
            Expr(A.Key);
            W(' ');
            Expr(A.Value);
            W(')');
          end;
      end;
    end;
    W(')');
  end
  else if E is TIndexExpr then
  begin
    W('(index ');
    Expr(TIndexExpr(E).Target);
    Exprs(TIndexExpr(E).Items);
    W(')');
  end
  else if E is TFieldExpr then
  begin
    W('(. ');
    Expr(TFieldExpr(E).Target);
    W(' ' + TFieldExpr(E).Name + ')');
  end
  else if E is TMatrixExpr then
  begin
    W('(matrix');
    for Row in TMatrixExpr(E).Rows do
    begin
      W(' (');
      for I := 0 to Row.Count - 1 do
      begin
        if I > 0 then W(' ');
        Expr(Row[I]);
      end;
      W(')');
    end;
    W(')');
  end
  else if E is TListExpr then
  begin
    W('(list');
    Exprs(TListExpr(E).Items);
    W(')');
  end
  else if E is TRecordExpr then
  begin
    W('(rec');
    for I := 0 to TRecordExpr(E).Names.Count - 1 do
    begin
      W(' ' + TRecordExpr(E).Names[I] + ':');
      Expr(TRecordExpr(E).Values[I]);
    end;
    W(')');
  end
  else if E is TLambdaExpr then
  begin
    W('(lambda ');
    Params(TLambdaExpr(E).Func);
    Body(TLambdaExpr(E).Func.Body);
    W(')');
  end
  else
    W('<' + E.ClassName + '>');
end;

procedure TDumper.CParams(L: TObjectList<TCParam>);
var
  I: Integer;
begin
  W('(');
  for I := 0 to L.Count - 1 do
  begin
    if I > 0 then W(' ');
    W(L[I].Name + ':');
    CType(L[I].CType);
  end;
  W(')');
end;

procedure TDumper.CType(C: TCType);
begin
  case C.Kind of
    ctNamed: W(C.Name);
    ctRef:
      begin
        W('(ref ');
        CType(C.Inner);
        W(')');
      end;
    ctPtr:
      begin
        W('(ptr ');
        CType(C.Inner);
        W(')');
      end;
    ctCallback:
      begin
        W('(callback ');
        CParams(C.Params);
        if C.ResultType <> nil then
        begin
          W(' :');
          CType(C.ResultType);
        end;
        W(')');
      end;
  end;
end;

procedure TDumper.Stmt(S: TStmt);
var
  I: Integer;
  B: TIfBranch;
  F: TFunctionDecl;
  Fld: TFieldDecl;
  Item: TExternItem;
  Name: string;
begin
  if S is TExprStmt then
    Expr(TExprStmt(S).Expr)
  else if S is TAssignStmt then
  begin
    W('(= ');
    Expr(TAssignStmt(S).Target);
    TypeSuffix(TAssignStmt(S).TypeRef);
    W(' ');
    Expr(TAssignStmt(S).Value);
    W(')');
  end
  else if S is TDestructureStmt then
  begin
    W('(= [');
    for I := 0 to TDestructureStmt(S).Targets.Count - 1 do
    begin
      if I > 0 then W(' ');
      Expr(TDestructureStmt(S).Targets[I]);
    end;
    W('] ');
    Expr(TDestructureStmt(S).Value);
    W(')');
  end
  else if S is TDeclStmt then
  begin
    if TDeclStmt(S).IsGlobal then W('(global ') else W('(local ');
    W(TDeclStmt(S).Name);
    TypeSuffix(TDeclStmt(S).TypeRef);
    if TDeclStmt(S).Value <> nil then
    begin
      W(' ');
      Expr(TDeclStmt(S).Value);
    end;
    W(')');
  end
  else if S is TReturnStmt then
  begin
    W('(return');
    Exprs(TReturnStmt(S).Values);
    W(')');
  end
  else if S is TBreakStmt then
    W('(break)')
  else if S is TContinueStmt then
    W('(continue)')
  else if S is TIfStmt then
  begin
    for I := 0 to TIfStmt(S).Branches.Count - 1 do
    begin
      B := TIfStmt(S).Branches[I];
      if I = 0 then
        W('(if ')
      else
      begin
        Inc(Indent, 2);
        NewLine;
        W('(elseif ');
      end;
      Expr(B.Cond);
      Body(B.Body);
      if I > 0 then
      begin
        W(')');
        Dec(Indent, 2);
      end;
    end;
    if TIfStmt(S).ElseBody <> nil then
    begin
      Inc(Indent, 2);
      NewLine;
      W('(else');
      Body(TIfStmt(S).ElseBody);
      W(')');
      Dec(Indent, 2);
    end;
    W(')');
  end
  else if S is TForStmt then
  begin
    W('(for ' + TForStmt(S).VarName + ' ');
    Expr(TForStmt(S).Iter);
    Body(TForStmt(S).Body);
    W(')');
  end
  else if S is TWhileStmt then
  begin
    W('(while ');
    Expr(TWhileStmt(S).Cond);
    Body(TWhileStmt(S).Body);
    W(')');
  end
  else if S is TTryStmt then
  begin
    W('(try');
    Body(TTryStmt(S).Body);
    Inc(Indent, 2);
    NewLine;
    W('(catch');
    if TTryStmt(S).CatchName <> '' then
      W(' ' + TTryStmt(S).CatchName);
    Body(TTryStmt(S).CatchBody);
    W(')');
    Dec(Indent, 2);
    W(')');
  end
  else if S is TFunctionStmt then
  begin
    F := TFunctionStmt(S).Func;
    if F.Exported then W('(export function ') else W('(function ');
    W(F.Name + ' ');
    Params(F);
    Docs(F.Doc);
    Body(F.Body);
    W(')');
  end
  else if S is TRecordStmt then
  begin
    if TRecordStmt(S).Exported then W('(export record ') else W('(record ');
    W(TRecordStmt(S).Name);
    Docs(TRecordStmt(S).Doc);
    Inc(Indent, 2);
    for Fld in TRecordStmt(S).Fields do
    begin
      NewLine;
      W(Fld.Name);
      TypeSuffix(Fld.TypeRef);
    end;
    Dec(Indent, 2);
    W(')');
  end
  else if S is TImportStmt then
  begin
    if TImportStmt(S).IsFrom then
    begin
      W('(from ' + TImportStmt(S).Module + ' import');
      for Name in TImportStmt(S).Names do
        W(' ' + Name);
    end
    else
    begin
      W('(import ' + TImportStmt(S).Module);
      if TImportStmt(S).Alias <> '' then
        W(' as ' + TImportStmt(S).Alias);
    end;
    W(')');
  end
  else if S is TExternStmt then
  begin
    W('(extern ' + EscapeString(TExternStmt(S).LibName));
    Inc(Indent, 2);
    for Item in TExternStmt(S).Items do
    begin
      NewLine;
      if Item is TExternFunc then
      begin
        W('(function ' + TExternFunc(Item).Name + ' ');
        CParams(TExternFunc(Item).Params);
        if TExternFunc(Item).ResultType <> nil then
        begin
          W(' :');
          CType(TExternFunc(Item).ResultType);
        end;
        if TExternFunc(Item).Symbol <> '' then
          W(' name ' + EscapeString(TExternFunc(Item).Symbol));
        W(')');
      end
      else
      begin
        W('(type ' + TExternType(Item).Name + ' ');
        CType(TExternType(Item).CType);
        W(')');
      end;
    end;
    Dec(Indent, 2);
    W(')');
  end
  else
    W('<' + S.ClassName + '>');
end;

function DumpProgram(P: TProgram): string;
var
  D: TDumper;
  S: TStmt;
begin
  D := TDumper.Create;
  try
    for S in P.Body do
    begin
      D.Indent := 0;
      D.Stmt(S);
      D.SB.Append(#10);
    end;
    Result := D.SB.ToString;
  finally
    D.Free;
  end;
end;

end.
