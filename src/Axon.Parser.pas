unit Axon.Parser;

(* Recursive-descent parser for the grammar in the Language Reference.

  Newline handling (reference, "Newlines and continuation"). The lexer emits
  NEWLINE at every line end, and the parser decides what each one means:

  - FSkipNL is True inside ( ), [ ] and { }. Cur then skips NEWLINE (and
    DOCSTRING) tokens.
  - Every block body (function, lambda, if, for, while, try, record, extern)
    sets FSkipNL to False, even when it sits inside brackets, so NEWLINE ends
    statements again. The caller's mode is restored after the closing `end`.
  - After a binary operator or a comma, SkipLayout drops any NEWLINEs.
  - The terminator before end, elseif, else and catch is optional.

  `end` is an expression only inside index brackets (FInIndex). Block bodies
  reset FInIndex.

  The token array always ends with EOF, and the parser never moves past it. *)

interface

uses
  Axon.Tokens, Axon.Ast;

(* Parses a whole file. Raises EAxonError (SyntaxError) on the first error. *)
function ParseProgram(const Tokens: TArray<TToken>; const FileName: string): TProgram;

(* Tokenizes and parses source text, then records the header text of each
   top-level function (for help). *)
function ParseSource(const Source, FileName: string): TProgram;

implementation

uses
  System.SysUtils, System.Character, System.Generics.Collections,
  Axon.Errors, Axon.Lexer;

type
  TKinds = set of TTokenKind;

  TParser = class
  private
    FTokens: TArray<TToken>;
    FPos: Integer;
    FFile: string;
    FSkipNL: Boolean;
    FInIndex: Boolean;
    FLoopDepth: Integer;   // loops enclosing the current point, within the current function
    FFuncDepth: Integer;   // functions enclosing the current point
    FModuleDoc: TList<string>;   // set by Run: the module docstring goes here

    // ---- token access
    function Cur: TToken;
    function CurKind: TTokenKind; inline;
    function PeekKind(N: Integer): TTokenKind;
    function RawKind(Index: Integer): TTokenKind;
    function Advance: TToken;
    procedure SkipLayout;
    function Accept(Kind: TTokenKind): Boolean;
    function Expect(Kind: TTokenKind; const What: string = ''): TToken;
    function ExpectIdent(const What: string): TToken;
    function ExpectFieldName(const What: string): TToken;
    procedure ExpectTerminator(const After: string);
    procedure Error(const Msg: string; const At: TToken);
    procedure ErrorExpected(const What: string);
    function Describe(const T: TToken): string;

    // ---- blocks and statements
    procedure ParseBlock(Into: TStmtList; Closers: TKinds; const Opener: TToken);
    function ParseStatement(Docs: TList<string>): TStmt;
    function ParseDeclaration: TStmt;
    function ParseReturn: TStmt;
    function ParseIf: TStmt;
    procedure ParseLoopBody(Into: TStmtList; const Opener: TToken);
    function ParseFor: TStmt;
    function ParseWhile: TStmt;
    function ParseTry: TStmt;
    function ParseFunctionStmt(Exported: Boolean; Docs: TList<string>): TStmt;
    function ParseRecordDef(Exported: Boolean; Docs: TList<string>): TStmt;
    function ParseImport: TStmt;
    function ParseFrom: TStmt;
    function ParseDotted: string;
    function ParseExtern: TStmt;
    function ParseExternFunc: TExternItem;
    function ParseExternType: TExternItem;
    function ParseCParams(Into: TObjectList<TCParam>): Boolean;
    function ParseCType: TCType;
    function IsDestructuring: Boolean;
    function ParseDestructuring: TStmt;
    function TryTypedAssignment: TStmt;
    function ParseExprOrAssignment: TStmt;
    procedure CheckTarget(E: TExpr);

    // ---- functions and types
    procedure ParseFunctionRest(F: TFunctionDecl);
    procedure ParseParams(F: TFunctionDecl);
    function IsTypeNameToken(Kind: TTokenKind): Boolean;
    function ParseType: TTypeRef;
    function TryParseType: TTypeRef;

    // ---- expressions
    function ParseExpression: TExpr;
    function ParseOr: TExpr;
    function ParseAnd: TExpr;
    function ParseNot: TExpr;
    function ParseComparison: TExpr;
    function ParseRange: TExpr;
    function ParseAdditive: TExpr;
    function ParseMultiplicative: TExpr;
    function ParseUnary: TExpr;
    function ParsePower: TExpr;
    function ParsePostfix: TExpr;
    function ParsePrimary: TExpr;
    function ParseCallArgs(Callee: TExpr; const At: TToken): TExpr;
    function ParseIndex(Target: TExpr; const At: TToken): TExpr;
    function ParseMatrix: TExpr;
    function ParseBrace: TExpr;
    function ParseLambda: TExpr;
    function MakeBinary(Op: TTokenKind; Left, Right: TExpr; const At: TToken): TExpr;
  public
    constructor Create(const Tokens: TArray<TToken>; const FileName: string);
    function Run: TProgram;
  end;

const
  LayoutKinds: TKinds = [tkNewline, tkDocString];
  Terminators: TKinds = [tkNewline, tkSemicolon];
  CompareOps: TKinds = [tkEqEq, tkNotEq, tkLess, tkLessEq, tkGreater, tkGreaterEq];
  MulOps: TKinds = [tkStar, tkSlash, tkBackslash, tkDotStar, tkDotSlash, tkDotBackslash];

(* ===================== token access ===================== *)

constructor TParser.Create(const Tokens: TArray<TToken>; const FileName: string);
begin
  inherited Create;
  FTokens := Tokens;
  FFile := FileName;
  FPos := 0;
end;

function TParser.Cur: TToken;
begin
  if FSkipNL then
    while FTokens[FPos].Kind in LayoutKinds do
      Inc(FPos);
  Result := FTokens[FPos];
end;

function TParser.CurKind: TTokenKind;
begin
  Result := Cur.Kind;
end;

function TParser.RawKind(Index: Integer): TTokenKind;
begin
  if Index > High(FTokens) then
    Index := High(FTokens);
  Result := FTokens[Index].Kind;
end;

(* Kind of the N-th significant token after the current one, where layout
  tokens count as significant only outside brackets. *)
function TParser.PeekKind(N: Integer): TTokenKind;
var
  I: Integer;
begin
  Cur;  // apply skipping to the current position
  I := FPos;
  while N > 0 do
  begin
    if FTokens[I].Kind = tkEOF then
      Exit(tkEOF);
    Inc(I);
    if FSkipNL then
      while FTokens[I].Kind in LayoutKinds do
        Inc(I);
    Dec(N);
  end;
  Result := FTokens[I].Kind;
end;

function TParser.Advance: TToken;
begin
  Result := Cur;
  if Result.Kind <> tkEOF then
    Inc(FPos);
end;

procedure TParser.SkipLayout;
begin
  while FTokens[FPos].Kind in LayoutKinds do
    Inc(FPos);
end;

function TParser.Accept(Kind: TTokenKind): Boolean;
begin
  Result := CurKind = Kind;
  if Result then
    Advance;
end;

function TParser.Describe(const T: TToken): string;
begin
  case T.Kind of
    tkEOF:       Result := 'end of file';
    tkNewline:   Result := 'end of line';
    tkIdent:     Result := 'identifier "' + T.Text + '"';
    tkInt, tkReal, tkImag: Result := 'number ' + T.Text;
    tkString:    Result := 'string ' + EscapeString(T.Text);
    tkDocString: Result := 'docstring';
  else
    Result := '"' + TokenSpelling[T.Kind] + '"';
  end;
end;

procedure TParser.Error(const Msg: string; const At: TToken);
begin
  raise EAxonError.CreateAt(SyntaxError, Msg, FFile, At.Line, At.Col);
end;

procedure TParser.ErrorExpected(const What: string);
var
  T: TToken;
begin
  T := Cur;
  Error(Format('expected %s, found %s', [What, Describe(T)]), T);
end;

function TParser.Expect(Kind: TTokenKind; const What: string): TToken;
begin
  if CurKind <> Kind then
    if What <> '' then
      ErrorExpected(What)
    else
      ErrorExpected('"' + TokenSpelling[Kind] + '"');
  Result := Advance;
end;

function TParser.ExpectIdent(const What: string): TToken;
begin
  Result := Expect(tkIdent, What);
end;

(* A field name: an identifier or any keyword, so a record can have a field
   such as `function` or `end` (reference, "Field names"). *)
function TParser.ExpectFieldName(const What: string): TToken;
begin
  if not ((CurKind = tkIdent) or IsKeyword(CurKind)) then
    ErrorExpected(What);
  Result := Advance;
end;

procedure TParser.ExpectTerminator(const After: string);
begin
  if not (CurKind in Terminators) then
    ErrorExpected('end of line or ";" after ' + After);
  Advance;
end;

(* ===================== blocks ===================== *)

(* block = { [ statement ] terminator } [ statement ]
  Stops in front of a token in Closers (which is not consumed). An empty
  Closers set means the whole program, which ends at EOF. *)
procedure TParser.ParseBlock(Into: TStmtList; Closers: TKinds; const Opener: TToken);
var
  SavedSkip, SavedIndex, PrevNewline: Boolean;
  Docs: TList<string>;
  T: TToken;
begin
  SavedSkip := FSkipNL;
  SavedIndex := FInIndex;
  FSkipNL := False;
  FInIndex := False;
  Docs := TList<string>.Create;
  try
    PrevNewline := True;
    while True do
    begin
      T := Cur;
      case T.Kind of
        tkNewline:
          begin
            if PrevNewline then
            begin
              // A docstring that opens a file, followed by a blank line,
              // documents the module.
              if (Closers = []) and (Into.Count = 0) and (FModuleDoc <> nil) and
                (FModuleDoc.Count = 0) then
                FModuleDoc.AddRange(Docs);
              Docs.Clear;   // a blank line separates a docstring from what follows
            end;
            PrevNewline := True;
            Advance;
            Continue;
          end;
        tkSemicolon:
          begin
            Advance;
            Continue;
          end;
        tkDocString:
          begin
            Docs.Add(T.Text);
            PrevNewline := False;
            Advance;
            Continue;
          end;
      end;
      if T.Kind in Closers then
        Break;
      if T.Kind = tkEOF then
      begin
        if Closers = [] then
          Break;
        Error(Format('expected "end" to close "%s" from line %d, found end of file',
          [TokenSpelling[Opener.Kind], Opener.Line]), T);
      end;

      Into.Add(ParseStatement(Docs));
      Docs.Clear;
      PrevNewline := False;

      T := Cur;
      // A statement followed by ";" does not display its value at the REPL.
      if T.Kind = tkSemicolon then
        Into.Last.Silent := True;
      if not ((T.Kind in Terminators) or (T.Kind in Closers) or (T.Kind = tkEOF)) then
        ErrorExpected('end of line or ";"');
    end;
  finally
    Docs.Free;
    FSkipNL := SavedSkip;
    FInIndex := SavedIndex;
  end;
end;

(* ===================== statements ===================== *)

function TParser.ParseStatement(Docs: TList<string>): TStmt;
var
  T: TToken;
begin
  T := Cur;
  case T.Kind of
    tkLocal, tkGlobal: Result := ParseDeclaration;
    tkReturn:
      begin
        if FFuncDepth = 0 then
          Error('"return" outside a function', T);
        Result := ParseReturn;
      end;
    tkBreak, tkContinue:
      begin
        if FLoopDepth = 0 then
          Error(Format('"%s" outside a loop', [TokenSpelling[T.Kind]]), T);
        if T.Kind = tkBreak then
          Result := TBreakStmt.Create
        else
          Result := TContinueStmt.Create;
        Result.SetPos(Advance);
      end;
    tkIf:     Result := ParseIf;
    tkFor:    Result := ParseFor;
    tkWhile:  Result := ParseWhile;
    tkTry:    Result := ParseTry;
    tkRecord: Result := ParseRecordDef(False, Docs);
    tkImport: Result := ParseImport;
    tkFrom:   Result := ParseFrom;
    tkExtern: Result := ParseExtern;
    tkExport:
      begin
        Advance;
        case CurKind of
          tkFunction:
            begin
              if PeekKind(1) <> tkIdent then
                Error('an exported function needs a name', Cur);
              Result := ParseFunctionStmt(True, Docs);
            end;
          tkRecord: Result := ParseRecordDef(True, Docs);
        else
          ErrorExpected('"function" or "record" after "export"');
          Result := nil;
        end;
        Result.SetPos(T);
      end;
    tkFunction:
      if PeekKind(1) = tkIdent then
        Result := ParseFunctionStmt(False, Docs)
      else
        Result := ParseExprOrAssignment;   // a lambda used as a statement
    tkLBracket:
      if IsDestructuring then
        Result := ParseDestructuring
      else
        Result := ParseExprOrAssignment;
    tkIdent:
      begin
        Result := nil;
        if PeekKind(1) = tkColon then
          Result := TryTypedAssignment;
        if Result = nil then
          Result := ParseExprOrAssignment;
      end;
  else
    Result := ParseExprOrAssignment;
  end;
end;

function TParser.ParseDeclaration: TStmt;
var
  D: TDeclStmt;
begin
  D := TDeclStmt.Create;
  try
    D.SetPos(Cur);
    D.IsGlobal := Advance.Kind = tkGlobal;
    D.Name := ExpectIdent('a variable name').Text;
    if Accept(tkColon) then
      D.TypeRef := ParseType;
    if Accept(tkAssign) then
      D.Value := ParseExpression;
  except
    D.Free;
    raise;
  end;
  Result := D;
end;

function TParser.ParseReturn: TStmt;
var
  R: TReturnStmt;
begin
  R := TReturnStmt.Create;
  try
    R.SetPos(Advance);
    if not (CurKind in [tkNewline, tkSemicolon, tkEnd, tkElseif, tkElse, tkCatch, tkEOF]) then
    begin
      R.Values.Add(ParseExpression);
      while Accept(tkComma) do
      begin
        SkipLayout;
        R.Values.Add(ParseExpression);
      end;
    end;
  except
    R.Free;
    raise;
  end;
  Result := R;
end;

function TParser.ParseIf: TStmt;
var
  S: TIfStmt;
  B: TIfBranch;
  Opener: TToken;
begin
  S := TIfStmt.Create;
  try
    Opener := Advance;
    S.SetPos(Opener);
    B := TIfBranch.Create;
    S.Branches.Add(B);
    B.SetPos(Opener);
    B.Cond := ParseExpression;
    // A terminator after the header is optional; ParseBlock skips it.
    ParseBlock(B.Body, [tkElseif, tkElse, tkEnd], Opener);
    while CurKind = tkElseif do
    begin
      B := TIfBranch.Create;
      S.Branches.Add(B);
      B.SetPos(Advance);
      B.Cond := ParseExpression;
      // A terminator after the header is optional; ParseBlock skips it.
      ParseBlock(B.Body, [tkElseif, tkElse, tkEnd], Opener);
    end;
    if Accept(tkElse) then
    begin
      S.ElseBody := TStmtList.Create;
      ParseBlock(S.ElseBody, [tkEnd], Opener);
    end;
    Expect(tkEnd, '"end" to close "if"');
  except
    S.Free;
    raise;
  end;
  Result := S;
end;

procedure TParser.ParseLoopBody(Into: TStmtList; const Opener: TToken);
begin
  Inc(FLoopDepth);
  try
    ParseBlock(Into, [tkEnd], Opener);
  finally
    Dec(FLoopDepth);
  end;
end;

function TParser.ParseFor: TStmt;
var
  S: TForStmt;
  Opener: TToken;
begin
  S := TForStmt.Create;
  try
    Opener := Advance;
    S.SetPos(Opener);
    S.VarName := ExpectIdent('a loop variable after "for"').Text;
    Expect(tkIn, '"in"');
    S.Iter := ParseExpression;
    // A terminator after the header is optional; ParseBlock skips it.
    ParseLoopBody(S.Body, Opener);
    Expect(tkEnd, '"end" to close "for"');
  except
    S.Free;
    raise;
  end;
  Result := S;
end;

function TParser.ParseWhile: TStmt;
var
  S: TWhileStmt;
  Opener: TToken;
begin
  S := TWhileStmt.Create;
  try
    Opener := Advance;
    S.SetPos(Opener);
    S.Cond := ParseExpression;
    // A terminator after the header is optional; ParseBlock skips it.
    ParseLoopBody(S.Body, Opener);
    Expect(tkEnd, '"end" to close "while"');
  except
    S.Free;
    raise;
  end;
  Result := S;
end;

function TParser.ParseTry: TStmt;
var
  S: TTryStmt;
  Opener, CatchTok: TToken;
begin
  S := TTryStmt.Create;
  try
    Opener := Advance;
    S.SetPos(Opener);
    ParseBlock(S.Body, [tkCatch], Opener);
    CatchTok := Expect(tkCatch, '"catch"');
    if CurKind = tkIdent then
      S.CatchName := Advance.Text;
    ExpectTerminator('"catch"');
    ParseBlock(S.CatchBody, [tkEnd], CatchTok);
    Expect(tkEnd, '"end" to close "try"');
  except
    S.Free;
    raise;
  end;
  Result := S;
end;

function TParser.ParseFunctionStmt(Exported: Boolean; Docs: TList<string>): TStmt;
var
  S: TFunctionStmt;
begin
  S := TFunctionStmt.Create;
  try
    S.Func := TFunctionDecl.Create;
    S.SetPos(Cur);
    S.Func.SetPos(Cur);
    S.Func.Exported := Exported;
    S.Func.Doc.AddRange(Docs);
    Advance;  // function
    S.Func.Name := ExpectIdent('a function name').Text;
    ParseFunctionRest(S.Func);
  except
    S.Free;
    raise;
  end;
  Result := S;
end;

(* "(" params ")" [ ":" type ] block "end" — shared by functions and lambdas.
  The current token is the opening parenthesis. *)
procedure TParser.ParseFunctionRest(F: TFunctionDecl);
var
  SavedSkip, SavedIndex: Boolean;
  SavedLoops: Integer;
  Opener: TToken;
begin
  Opener := FTokens[FPos - 1];   // the "function" keyword or the name
  if Opener.Kind = tkIdent then
    Opener := FTokens[FPos - 2];
  SavedSkip := FSkipNL;
  SavedIndex := FInIndex;
  try
    Expect(tkLParen, '"(" to start the parameter list');
    FSkipNL := True;
    FInIndex := False;
    ParseParams(F);
    Expect(tkRParen, '"," or ")" in the parameter list');
    // The rest of the header and the body are block context.
    FSkipNL := False;
    if Accept(tkColon) then
      F.ReturnType := ParseType;
    // A function body is a new context: loops outside it do not count.
    SavedLoops := FLoopDepth;
    FLoopDepth := 0;
    Inc(FFuncDepth);
    try
      ParseBlock(F.Body, [tkEnd], Opener);
    finally
      Dec(FFuncDepth);
      FLoopDepth := SavedLoops;
    end;
    Expect(tkEnd, '"end" to close "function"');
  finally
    FSkipNL := SavedSkip;
    FInIndex := SavedIndex;
  end;
end;

(* params = [ param { "," param } ] [ ";" kwparam { "," kwparam } ] *)
procedure TParser.ParseParams(F: TFunctionDecl);
var
  Names: TList<string>;

  function NewParam(IsKeyword: Boolean): TParam;
  var
    T: TToken;
  begin
    T := ExpectIdent('a parameter name');
    if Names.Contains(T.Text) then
      Error(Format('duplicate parameter "%s"', [T.Text]), T);
    Names.Add(T.Text);
    Result := TParam.Create;
    F.Params.Add(Result);
    Result.SetPos(T);
    Result.Name := T.Text;
    Result.IsKeyword := IsKeyword;
    if Accept(tkColon) then
      Result.TypeRef := ParseType;
  end;

  // A positional parameter with "= default" is optional; every positional
  // parameter after it must be optional too.
  procedure Positional(var Optional: Boolean);
  var
    P: TParam;
    T: TToken;
  begin
    T := Cur;
    P := NewParam(False);
    if Accept(tkAssign) then
    begin
      P.Default := ParseExpression;
      Optional := True;
    end
    else if Optional then
      Error(Format('parameter "%s" needs a default value, because a parameter before it ' +
        'has one', [P.Name]), T);
  end;

var
  P: TParam;
  Optional: Boolean;
begin
  Names := TList<string>.Create;
  try
    if CurKind = tkRParen then
      Exit;
    Optional := False;
    if CurKind <> tkSemicolon then
    begin
      Positional(Optional);
      while Accept(tkComma) do
        Positional(Optional);
    end;
    if Accept(tkSemicolon) then
    begin
      repeat
        P := NewParam(True);
        Expect(tkAssign, 'a default value ("=") for keyword parameter "' + P.Name + '"');
        P.Default := ParseExpression;
      until not Accept(tkComma);
    end;
  finally
    Names.Free;
  end;
end;

function TParser.IsTypeNameToken(Kind: TTokenKind): Boolean;
begin
  // Type names are identifiers, plus the keywords that name types.
  Result := Kind in [tkIdent, tkFunction, tkRecord, tkNothing];
end;

(* type = IDENT [ "{" type "}" ] *)
function TParser.ParseType: TTypeRef;
var
  T: TToken;
begin
  T := Cur;
  if not IsTypeNameToken(T.Kind) then
    ErrorExpected('a type name');
  Advance;
  Result := TTypeRef.Create;
  try
    Result.SetPos(T);
    Result.Name := TokenSpelling[T.Kind];
    if T.Kind = tkIdent then
      Result.Name := T.Text;
    if Accept(tkLBrace) then
    begin
      Result.Param := ParseType;
      Expect(tkRBrace, '"}" to close the type parameter');
    end;
  except
    Result.Free;
    raise;
  end;
end;

(* Like ParseType, but returns nil (with the position unchanged) instead of
  raising when the tokens do not form a type. *)
function TParser.TryParseType: TTypeRef;
var
  Saved: Integer;
begin
  Saved := FPos;
  try
    Result := ParseType;
  except
    on EAxonError do
    begin
      FPos := Saved;
      Result := nil;
    end;
  end;
end;

(* record IDENT terminator { field_decl terminator } end *)
function TParser.ParseRecordDef(Exported: Boolean; Docs: TList<string>): TStmt;
var
  S: TRecordStmt;
  Opener, NameTok: TToken;
  F: TFieldDecl;
  SavedSkip: Boolean;
begin
  S := TRecordStmt.Create;
  SavedSkip := FSkipNL;
  try
    Opener := Advance;
    S.SetPos(Opener);
    S.Exported := Exported;
    S.Doc.AddRange(Docs);
    S.Name := ExpectIdent('a record name').Text;
    FSkipNL := False;
    ExpectTerminator('the record name');
    while True do
    begin
      while CurKind in Terminators + [tkDocString] do
        Advance;
      if CurKind = tkEnd then
        Break;
      if CurKind = tkEOF then
        Error(Format('expected "end" to close "record" from line %d, found end of file',
          [Opener.Line]), Cur);
      NameTok := ExpectFieldName('a field name or "end"');
      for F in S.Fields do
        if F.Name = NameTok.Text then
          Error(Format('duplicate field "%s"', [NameTok.Text]), NameTok);
      F := TFieldDecl.Create;
      S.Fields.Add(F);
      F.SetPos(NameTok);
      F.Name := NameTok.Text;
      Expect(tkColon, '":" and a type after the field name');
      F.TypeRef := ParseType;
      if not (CurKind in Terminators + [tkEnd]) then
        ErrorExpected('end of line or ";" after the field');
    end;
    Expect(tkEnd);
  except
    FSkipNL := SavedSkip;
    S.Free;
    raise;
  end;
  FSkipNL := SavedSkip;
  Result := S;
end;

function TParser.ParseDotted: string;
begin
  Result := ExpectIdent('a module name').Text;
  while CurKind = tkDot do
  begin
    Advance;
    Result := Result + '.' + ExpectIdent('a module name after "."').Text;
  end;
end;

function TParser.ParseImport: TStmt;
var
  S: TImportStmt;
begin
  S := TImportStmt.Create;
  try
    S.SetPos(Advance);
    S.Module := ParseDotted;
    if Accept(tkAs) then
      S.Alias := ExpectIdent('a name after "as"').Text;
  except
    S.Free;
    raise;
  end;
  Result := S;
end;

function TParser.ParseFrom: TStmt;
var
  S: TImportStmt;
begin
  S := TImportStmt.Create;
  try
    S.SetPos(Advance);
    S.IsFrom := True;
    S.Module := ParseDotted;
    Expect(tkImport, '"import"');
    repeat
      S.Names.Add(ExpectIdent('a name to import').Text);
    until not Accept(tkComma);
  except
    S.Free;
    raise;
  end;
  Result := S;
end;

(* extern STRING terminator { [ extern_item ] terminator } end *)
function TParser.ParseExtern: TStmt;
var
  S: TExternStmt;
  Opener: TToken;
  SavedSkip: Boolean;
begin
  S := TExternStmt.Create;
  SavedSkip := FSkipNL;
  try
    Opener := Advance;
    S.SetPos(Opener);
    S.LibName := Expect(tkString, 'a library name string after "extern"').Text;
    FSkipNL := False;
    ExpectTerminator('the library name');
    while True do
    begin
      while CurKind in Terminators + [tkDocString] do
        Advance;
      case CurKind of
        tkEnd: Break;
        tkFunction: S.Items.Add(ParseExternFunc);
        tkType: S.Items.Add(ParseExternType);
        tkEOF:
          Error(Format('expected "end" to close "extern" from line %d, found end of file',
            [Opener.Line]), Cur);
      else
        ErrorExpected('"function", "type" or "end" in an extern block');
      end;
      if not (CurKind in Terminators + [tkEnd]) then
        ErrorExpected('end of line or ";"');
    end;
    Expect(tkEnd);
  except
    FSkipNL := SavedSkip;
    S.Free;
    raise;
  end;
  FSkipNL := SavedSkip;
  Result := S;
end;

(* "(" [ cparam { "," cparam } ] ")" — returns True. Newlines are skipped
  inside the parentheses. *)
function TParser.ParseCParams(Into: TObjectList<TCParam>): Boolean;
var
  SavedSkip: Boolean;
  P: TCParam;
  T: TToken;
begin
  Expect(tkLParen, '"("');
  SavedSkip := FSkipNL;
  FSkipNL := True;
  try
    if CurKind <> tkRParen then
      repeat
        T := ExpectIdent('a parameter name');
        P := TCParam.Create;
        Into.Add(P);
        P.SetPos(T);
        P.Name := T.Text;
        Expect(tkColon, '":" and a C type after the parameter name');
        P.CType := ParseCType;
      until not Accept(tkComma);
    Expect(tkRParen, '"," or ")"');
  finally
    FSkipNL := SavedSkip;
  end;
  Result := True;
end;

(* ctype = IDENT | "ref" ctype | "ptr" ctype
        | "callback" "(" [ cparam { "," cparam } ] ")" [ ":" ctype ] *)
function TParser.ParseCType: TCType;
var
  T: TToken;
begin
  T := Cur;
  Result := TCType.Create;
  try
    Result.SetPos(T);
    case T.Kind of
      tkIdent:
        begin
          Advance;
          Result.Kind := ctNamed;
          Result.Name := T.Text;
        end;
      tkRef, tkPtr:
        begin
          Advance;
          if T.Kind = tkRef then Result.Kind := ctRef else Result.Kind := ctPtr;
          Result.Inner := ParseCType;
        end;
      tkCallback:
        begin
          Advance;
          Result.Kind := ctCallback;
          Result.Params := TObjectList<TCParam>.Create;
          ParseCParams(Result.Params);
          if Accept(tkColon) then
            Result.ResultType := ParseCType;
        end;
    else
      ErrorExpected('a C type');
    end;
  except
    Result.Free;
    raise;
  end;
end;

(* "function" IDENT "(" [ cparam { "," cparam } ] ")" [ ":" ctype ] [ "name" STRING ] *)
function TParser.ParseExternFunc: TExternItem;
var
  F: TExternFunc;
begin
  F := TExternFunc.Create;
  try
    F.SetPos(Advance);
    F.Name := ExpectIdent('a function name').Text;
    ParseCParams(F.Params);
    if Accept(tkColon) then
      F.ResultType := ParseCType;
    if Accept(tkName) then
      F.Symbol := Expect(tkString, 'a symbol name string after "name"').Text;
  except
    F.Free;
    raise;
  end;
  Result := F;
end;

(* "type" IDENT "=" ctype *)
function TParser.ParseExternType: TExternItem;
var
  T: TExternType;
begin
  T := TExternType.Create;
  try
    T.SetPos(Advance);
    T.Name := ExpectIdent('a type name').Text;
    Expect(tkAssign, '"="');
    T.CType := ParseCType;
  except
    T.Free;
    raise;
  end;
  Result := T;
end;

(* A statement starting with "[" is a destructuring assignment if the matching
  "]" is followed by "=". *)
function TParser.IsDestructuring: Boolean;
var
  I, Depth: Integer;
begin
  I := FPos;
  Depth := 0;
  repeat
    case FTokens[I].Kind of
      tkLParen, tkLBracket, tkLBrace: Inc(Depth);
      tkRParen, tkRBracket, tkRBrace: Dec(Depth);
      tkEOF: Exit(False);
    end;
    Inc(I);
  until Depth = 0;
  Result := RawKind(I) = tkAssign;
end;

function TParser.ParseDestructuring: TStmt;
var
  S: TDestructureStmt;
  SavedSkip: Boolean;
  E: TExpr;
begin
  S := TDestructureStmt.Create;
  try
    S.SetPos(Advance);  // [
    SavedSkip := FSkipNL;
    FSkipNL := True;
    try
      repeat
        E := ParsePostfix;
        S.Targets.Add(E);
        CheckTarget(E);
      until not Accept(tkComma);
      Expect(tkRBracket, '"," or "]" in the assignment targets');
    finally
      FSkipNL := SavedSkip;
    end;
    Expect(tkAssign);
    S.Value := ParseExpression;
  except
    S.Free;
    raise;
  end;
  Result := S;
end;

(* IDENT ":" type "=" expression, tried before falling back to an expression
  such as x:n. Returns nil, with the position unchanged, if it does not fit. *)
function TParser.TryTypedAssignment: TStmt;
var
  Saved: Integer;
  NameTok: TToken;
  TypeRef: TTypeRef;
  S: TAssignStmt;
  N: TNameExpr;
begin
  Result := nil;
  Saved := FPos;
  NameTok := Advance;
  Advance;  // :
  TypeRef := TryParseType;
  if (TypeRef = nil) or (CurKind <> tkAssign) then
  begin
    TypeRef.Free;
    FPos := Saved;
    Exit;
  end;
  Advance;  // =
  S := TAssignStmt.Create;
  try
    S.SetPos(NameTok);
    N := TNameExpr.Create;
    N.SetPos(NameTok);
    N.Name := NameTok.Text;
    S.Target := N;
    S.TypeRef := TypeRef;
    S.Value := ParseExpression;
  except
    S.Free;
    raise;
  end;
  Result := S;
end;

(* Assignment targets: IDENT { "[" index_list "]" | "." IDENT } *)
procedure TParser.CheckTarget(E: TExpr);
var
  Node: TExpr;
begin
  Node := E;
  while True do
    if Node is TNameExpr then
      Exit
    else if Node is TIndexExpr then
      Node := TIndexExpr(Node).Target
    else if Node is TFieldExpr then
      Node := TFieldExpr(Node).Target
    else
      Break;
  raise EAxonError.CreateAt(SyntaxError,
    'cannot assign to this expression; the target must be a name, an indexed name or a field',
    FFile, E.Line, E.Col);
end;

function TParser.ParseExprOrAssignment: TStmt;
var
  E: TExpr;
  A: TAssignStmt;
  ES: TExprStmt;
begin
  E := ParseExpression;
  try
    if CurKind = tkAssign then
    begin
      CheckTarget(E);
      Advance;
      A := TAssignStmt.Create;
      A.Line := E.Line;
      A.Col := E.Col;
      A.Target := E;
      E := nil;
      try
        A.Value := ParseExpression;
      except
        A.Free;
        raise;
      end;
      Exit(A);
    end;
  except
    E.Free;
    raise;
  end;
  ES := TExprStmt.Create;
  ES.Line := E.Line;
  ES.Col := E.Col;
  ES.Expr := E;
  Result := ES;
end;

(* ===================== expressions ===================== *)

function TParser.MakeBinary(Op: TTokenKind; Left, Right: TExpr; const At: TToken): TExpr;
var
  B: TBinaryExpr;
begin
  B := TBinaryExpr.Create;
  B.Line := Left.Line;
  B.Col := Left.Col;
  B.Op := Op;
  B.Left := Left;
  B.Right := Right;
  Result := B;
end;

function TParser.ParseExpression: TExpr;
begin
  Result := ParseOr;
end;

function TParser.ParseOr: TExpr;
var
  Op: TToken;
  R: TExpr;
begin
  Result := ParseAnd;
  try
    while CurKind = tkOr do
    begin
      Op := Advance;
      SkipLayout;
      R := ParseAnd;
      Result := MakeBinary(tkOr, Result, R, Op);
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TParser.ParseAnd: TExpr;
var
  Op: TToken;
  R: TExpr;
begin
  Result := ParseNot;
  try
    while CurKind = tkAnd do
    begin
      Op := Advance;
      SkipLayout;
      R := ParseNot;
      Result := MakeBinary(tkAnd, Result, R, Op);
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TParser.ParseNot: TExpr;
var
  U: TUnaryExpr;
begin
  if CurKind <> tkNot then
    Exit(ParseComparison);
  U := TUnaryExpr.Create;
  try
    U.SetPos(Advance);
    U.Op := tkNot;
    U.Operand := ParseNot;
  except
    U.Free;
    raise;
  end;
  Result := U;
end;

function TParser.ParseComparison: TExpr;
var
  Op: TToken;
  R: TExpr;
begin
  Result := ParseRange;
  try
    if CurKind in CompareOps then
    begin
      Op := Advance;
      SkipLayout;
      R := ParseRange;
      Result := MakeBinary(Op.Kind, Result, R, Op);
      if CurKind in CompareOps then
        Error('comparisons cannot be chained; combine them with "and"', Cur);
    end;
  except
    Result.Free;
    raise;
  end;
end;

(* range_expr = add_expr [ ":" add_expr [ ":" add_expr ] ]
  a:h:b has the step in the middle. *)
function TParser.ParseRange: TExpr;
var
  R: TRangeExpr;
  Second: TExpr;
begin
  Result := ParseAdditive;
  if CurKind <> tkColon then
    Exit;
  R := TRangeExpr.Create;
  R.Line := Result.Line;
  R.Col := Result.Col;
  R.Start := Result;
  Result := R;
  try
    Advance;
    SkipLayout;
    Second := ParseAdditive;
    if CurKind = tkColon then
    begin
      R.Step := Second;
      Advance;
      SkipLayout;
      R.Stop := ParseAdditive;
      if CurKind = tkColon then
        Error('ranges cannot be chained; a range is a:b or a:h:b', Cur);
    end
    else
      R.Stop := Second;
  except
    Result.Free;
    raise;
  end;
end;

function TParser.ParseAdditive: TExpr;
var
  Op: TToken;
  R: TExpr;
begin
  Result := ParseMultiplicative;
  try
    while CurKind in [tkPlus, tkMinus] do
    begin
      Op := Advance;
      SkipLayout;
      R := ParseMultiplicative;
      Result := MakeBinary(Op.Kind, Result, R, Op);
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TParser.ParseMultiplicative: TExpr;
var
  Op: TToken;
  R: TExpr;
begin
  Result := ParseUnary;
  try
    while CurKind in MulOps do
    begin
      Op := Advance;
      SkipLayout;
      R := ParseUnary;
      Result := MakeBinary(Op.Kind, Result, R, Op);
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TParser.ParseUnary: TExpr;
var
  U: TUnaryExpr;
  T: TToken;
begin
  T := Cur;
  if not (T.Kind in [tkMinus, tkPlus]) then
    Exit(ParsePower);
  U := TUnaryExpr.Create;
  try
    U.SetPos(Advance);
    U.Op := T.Kind;
    U.Operand := ParseUnary;
  except
    U.Free;
    raise;
  end;
  Result := U;
end;

(* power = postfix [ ( "^" | ".^" ) unary ] — right associative through unary. *)
function TParser.ParsePower: TExpr;
var
  Op: TToken;
  R: TExpr;
begin
  Result := ParsePostfix;
  try
    if CurKind in [tkCaret, tkDotCaret] then
    begin
      Op := Advance;
      SkipLayout;
      R := ParseUnary;
      Result := MakeBinary(Op.Kind, Result, R, Op);
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TParser.ParsePostfix: TExpr;
var
  T: TToken;
  F: TFieldExpr;
  U: TUnaryExpr;
  Inner: TExpr;
begin
  Result := ParsePrimary;
  try
    while True do
    begin
      T := Cur;
      case T.Kind of
        // ParseCallArgs and ParseIndex take ownership of their target (and
        // free it on error), so Result is cleared before the call.
        tkLParen:
          begin
            Inner := Result;
            Result := nil;
            Result := ParseCallArgs(Inner, T);
          end;
        tkLBracket:
          begin
            Inner := Result;
            Result := nil;
            Result := ParseIndex(Inner, T);
          end;
        tkDot:
          begin
            Advance;
            F := TFieldExpr.Create;
            F.Line := Result.Line;
            F.Col := Result.Col;
            F.Target := Result;
            Result := F;
            F.Name := ExpectFieldName('a field name after "."').Text;
          end;
        tkQuote:
          begin
            Advance;
            U := TUnaryExpr.Create;
            U.Line := Result.Line;
            U.Col := Result.Col;
            U.Op := tkQuote;
            U.Operand := Result;
            Result := U;
          end;
      else
        Break;
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

(* Called with the current token "(". Takes ownership of Callee. *)
function TParser.ParseCallArgs(Callee: TExpr; const At: TToken): TExpr;
var
  C: TCallExpr;
  A: TArg;
  SavedSkip, SeenKeyword: Boolean;
  T: TToken;
begin
  C := TCallExpr.Create;
  C.Line := Callee.Line;
  C.Col := Callee.Col;
  C.Callee := Callee;
  SavedSkip := FSkipNL;
  try
    Advance;  // (
    FSkipNL := True;
    SeenKeyword := False;
    if CurKind <> tkRParen then
      repeat
        SkipLayout;
        T := Cur;
        A := TArg.Create;
        C.Args.Add(A);
        A.SetPos(T);
        if (T.Kind = tkIdent) and (PeekKind(1) = tkAssign) then
        begin
          // IDENT "=" expression: a keyword argument
          A.Kind := akKeyword;
          A.Name := T.Text;
          Advance;
          Advance;
          A.Value := ParseExpression;
          SeenKeyword := True;
        end
        else
        begin
          A.Value := ParseExpression;
          if CurKind = tkArrow then
          begin
            Advance;
            SkipLayout;
            A.Kind := akPair;
            A.Key := A.Value;
            A.Value := nil;
            A.Value := ParseExpression;
          end
          else
            A.Kind := akPositional;
          if SeenKeyword then
            Error('a positional argument cannot follow a keyword argument', T);
        end;
      until not Accept(tkComma);
    Expect(tkRParen, '"," or ")" in the argument list');
  except
    FSkipNL := SavedSkip;
    C.Free;
    raise;
  end;
  FSkipNL := SavedSkip;
  Result := C;
end;

(* Called with the current token "[". Takes ownership of Target. *)
function TParser.ParseIndex(Target: TExpr; const At: TToken): TExpr;
var
  X: TIndexExpr;
  SavedSkip, SavedIndex: Boolean;
  Colon: TColonExpr;
begin
  X := TIndexExpr.Create;
  X.Line := Target.Line;
  X.Col := Target.Col;
  X.Target := Target;
  SavedSkip := FSkipNL;
  SavedIndex := FInIndex;
  try
    Advance;  // [
    FSkipNL := True;
    FInIndex := True;
    if CurKind = tkRBracket then
      ErrorExpected('an index');
    repeat
      SkipLayout;
      if (CurKind = tkColon) and (PeekKind(1) in [tkComma, tkRBracket]) then
      begin
        Colon := TColonExpr.Create;
        Colon.SetPos(Advance);
        X.Items.Add(Colon);
      end
      else
        X.Items.Add(ParseExpression);
    until not Accept(tkComma);
    Expect(tkRBracket, '"," or "]" in the index');
  except
    FSkipNL := SavedSkip;
    FInIndex := SavedIndex;
    X.Free;
    raise;
  end;
  FSkipNL := SavedSkip;
  FInIndex := SavedIndex;
  Result := X;
end;

(* matrix_lit = "[" [ row { ";" row } ] "]" ; row = expression { "," expression } *)
function TParser.ParseMatrix: TExpr;
var
  M: TMatrixExpr;
  Row: TExprList;
  SavedSkip: Boolean;
begin
  M := TMatrixExpr.Create;
  SavedSkip := FSkipNL;
  try
    M.SetPos(Advance);  // [
    FSkipNL := True;
    if CurKind <> tkRBracket then
      repeat
        SkipLayout;
        Row := TExprList.Create;
        M.Rows.Add(Row);
        repeat
          SkipLayout;
          Row.Add(ParseExpression);
        until not Accept(tkComma);
      until not Accept(tkSemicolon);
    Expect(tkRBracket, '",", ";" or "]" in the matrix');
  except
    FSkipNL := SavedSkip;
    M.Free;
    raise;
  end;
  FSkipNL := SavedSkip;
  Result := M;
end;

(* A record literal if the first element is IDENT ":", a list otherwise. *)
function TParser.ParseBrace: TExpr;
var
  L: TListExpr;
  R: TRecordExpr;
  SavedSkip: Boolean;
  Open, NameTok: TToken;
begin
  SavedSkip := FSkipNL;
  Open := Advance;  // {
  FSkipNL := True;
  Result := nil;
  try
    if ((CurKind = tkIdent) or IsKeyword(CurKind)) and (PeekKind(1) = tkColon) then
    begin
      R := TRecordExpr.Create;
      Result := R;
      R.SetPos(Open);
      repeat
        SkipLayout;
        NameTok := ExpectFieldName('a field name ("name: value") in the record');
        if R.Names.Contains(NameTok.Text) then
          Error(Format('duplicate field "%s"', [NameTok.Text]), NameTok);
        Expect(tkColon, '":" after the field name');
        R.Names.Add(NameTok.Text);
        R.Values.Add(ParseExpression);
      until not Accept(tkComma);
      Expect(tkRBrace, '"," or "}" in the record');
    end
    else
    begin
      L := TListExpr.Create;
      Result := L;
      L.SetPos(Open);
      if CurKind <> tkRBrace then
        repeat
          SkipLayout;
          L.Items.Add(ParseExpression);
        until not Accept(tkComma);
      Expect(tkRBrace, '"," or "}" in the list');
    end;
  except
    FSkipNL := SavedSkip;
    Result.Free;
    raise;
  end;
  FSkipNL := SavedSkip;
end;

function TParser.ParseLambda: TExpr;
var
  L: TLambdaExpr;
begin
  L := TLambdaExpr.Create;
  try
    L.SetPos(Cur);
    L.Func := TFunctionDecl.Create;
    L.Func.SetPos(Advance);  // function
    ParseFunctionRest(L.Func);
  except
    L.Free;
    raise;
  end;
  Result := L;
end;

function TParser.ParsePrimary: TExpr;
var
  T: TToken;
  SavedSkip: Boolean;
begin
  T := Cur;
  case T.Kind of
    tkInt:
      begin
        Result := TIntLit.Create;
        TIntLit(Result).Value := T.IntValue;
      end;
    tkReal:
      begin
        Result := TRealLit.Create;
        TRealLit(Result).Value := T.RealValue;
        TRealLit(Result).Text := T.Text;
      end;
    tkImag:
      begin
        Result := TImagLit.Create;
        TImagLit(Result).Value := T.RealValue;
        TImagLit(Result).Text := T.Text;
      end;
    tkString:
      begin
        Result := TStringLit.Create;
        TStringLit(Result).Value := T.Text;
      end;
    tkTrue, tkFalse:
      begin
        Result := TBoolLit.Create;
        TBoolLit(Result).Value := T.Kind = tkTrue;
      end;
    tkNothing:
      Result := TNothingLit.Create;
    tkIdent:
      begin
        Result := TNameExpr.Create;
        TNameExpr(Result).Name := T.Text;
      end;
    tkEnd:
      begin
        if not FInIndex then
          Error('"end" without a block to close (it is an expression only inside index brackets)', T);
        Result := TEndExpr.Create;
      end;
    tkLParen:
      begin
        SavedSkip := FSkipNL;
        Advance;
        FSkipNL := True;
        try
          Result := ParseExpression;
          try
            Expect(tkRParen, '")"');
          except
            Result.Free;
            raise;
          end;
        finally
          FSkipNL := SavedSkip;
        end;
        Exit;
      end;
    tkLBracket:
      Exit(ParseMatrix);
    tkLBrace:
      Exit(ParseBrace);
    tkFunction:
      Exit(ParseLambda);
  else
    ErrorExpected('an expression');
    Result := nil;
  end;
  Result.SetPos(T);
  Advance;
end;

(* ===================== entry point ===================== *)

function TParser.Run: TProgram;
var
  Start: TToken;
begin
  Result := TProgram.Create;
  try
    Result.FileName := FFile;
    Start := FTokens[0];
    Result.SetPos(Start);
    FModuleDoc := Result.Doc;
    ParseBlock(Result.Body, [], Start);
    FModuleDoc := nil;
    if CurKind <> tkEOF then
      ErrorExpected('a statement');
  except
    Result.Free;
    raise;
  end;
end;

function ParseProgram(const Tokens: TArray<TToken>; const FileName: string): TProgram;
var
  P: TParser;
begin
  P := TParser.Create(Tokens, FileName);
  try
    Result := P.Run;
  finally
    P.Free;
  end;
end;

(* The header of a function as written: from "function" (at Line:Col) through
   the closing ")" of its parameters and an optional ": type", which may
   carry braces (matrix{real}). Parameter lists may span lines; the line
   breaks become single spaces. *)
function HeaderText(const Lines: TArray<string>; Line, Col: Integer): string;
var
  L, I, Depth: Integer;
  Text: string;
  C: Char;
  InString, Closed: Boolean;
  SB: TStringBuilder;

  // Appends the return type after ':' (an identifier with optional braces).
  procedure TakeType(const Text: string; var I: Integer);
  var
    J, D: Integer;
  begin
    J := I;
    while (J <= Length(Text)) and (Text[J] = ' ') do Inc(J);
    if (J > Length(Text)) or (Text[J] <> ':') then
      Exit;
    Inc(J);
    while (J <= Length(Text)) and (Text[J] = ' ') do Inc(J);
    D := 0;
    while J <= Length(Text) do
    begin
      C := Text[J];
      if C = '{' then Inc(D)
      else if C = '}' then Dec(D)
      else if (D = 0) and not (C.IsLetterOrDigit or (C = '_')) then
        Break;
      Inc(J);
      if (D = 0) and (C = '}') then
        Break;
    end;
    SB.Append(Copy(Text, I, J - I));
    I := J;
  end;

begin
  Result := '';
  if (Line < 1) or (Line > Length(Lines)) then
    Exit;
  SB := TStringBuilder.Create;
  try
    Depth := 0;
    InString := False;
    Closed := False;
    L := Line;
    I := Col;
    while (L <= Length(Lines)) and not Closed do
    begin
      Text := Lines[L - 1].TrimRight;
      if L > Line then
      begin
        SB.Append(' ');
        I := 1;
        while (I <= Length(Text)) and (Text[I] = ' ') do Inc(I);
      end;
      while I <= Length(Text) do
      begin
        C := Text[I];
        if InString then
        begin
          SB.Append(C);
          if C = '' then
          begin
            Inc(I);
            if I <= Length(Text) then SB.Append(Text[I]);
          end
          else if C = '"' then
            InString := False;
          Inc(I);
          Continue;
        end;
        if (C = '#') then
          Break;
        SB.Append(C);
        Inc(I);
        case C of
          '"': InString := True;
          '(', '[', '{': Inc(Depth);
          ')', ']', '}':
            begin
              Dec(Depth);
              if (Depth = 0) and (C = ')') then
              begin
                TakeType(Text, I);
                Closed := True;
                Break;
              end;
            end;
        end;
      end;
      Inc(L);
    end;
    Result := SB.ToString.Trim;
  finally
    SB.Free;
  end;
  if Result.StartsWith('function ') then
    Result := Copy(Result, Length('function ') + 1, MaxInt).TrimLeft;
end;

function ParseSource(const Source, FileName: string): TProgram;
var
  Lines: TArray<string>;
  S: TStmt;
  F: TFunctionDecl;
begin
  Result := ParseProgram(Tokenize(Source, FileName), FileName);
  Lines := Source.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
  for S in Result.Body do
    if S is TFunctionStmt then
    begin
      F := TFunctionStmt(S).Func;
      F.Header := HeaderText(Lines, F.Line, F.Col);
    end;
end;

end.
