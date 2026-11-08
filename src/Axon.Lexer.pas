unit Axon.Lexer;

{ Lexer: source text to tokens, following the Language Reference section
  "Lexical structure".

  - A NEWLINE token is emitted at every line end, including line ends inside a
    block comment. The parser decides which newlines matter.
  - '##' at the start of a line (after optional spaces) gives a DOCSTRING token
    holding the rest of the line, minus one leading space.
  - The words type, ref, ptr, callback and name are keywords from 'extern' up
    to the next 'end'. That 'end' always closes the extern block, because
    extern items are declarations without bodies.
  - Columns count Unicode code points, starting at 1.
  - Errors raise EAxonError of kind SyntaxError with file, line and column. }

interface

uses
  Axon.Tokens;

function Tokenize(const Source, FileName: string): TArray<TToken>;

implementation

uses
  System.SysUtils, System.Character, System.Generics.Collections,
  Axon.Errors, Axon.FloatParse;

type
  TLexer = class
  private
    FSrc: string;
    FFile: string;
    FPos: Integer;          // 1-based index of the current char in FSrc
    FLine: Integer;
    FCol: Integer;
    FAtLineStart: Boolean;  // only spaces seen since the start of the line
    FInExtern: Boolean;
    FTokens: TList<TToken>;
    function AtEnd: Boolean; inline;
    function Peek(Offset: Integer = 0): Char; inline;
    function CharLen: Integer;
    procedure Advance;
    procedure Error(const Msg: string; ALine, ACol: Integer);
    procedure Add(Kind: TTokenKind; const Text: string; ALine, ACol: Integer);
    procedure LineBreak;
    procedure LexComment;
    procedure LexBlockComment;
    procedure LexNumber;
    procedure LexIdent;
    procedure LexString;
    procedure LexOperator;
  public
    constructor Create(const Source, FileName: string);
    destructor Destroy; override;
    function Run: TArray<TToken>;
  end;

var
  KeywordTable: TDictionary<string, TTokenKind>;

function IsDigit(C: Char): Boolean; inline;
begin
  Result := (C >= '0') and (C <= '9');
end;

function IsIdentStart(C: Char): Boolean; inline;
begin
  Result := ((C >= 'a') and (C <= 'z')) or ((C >= 'A') and (C <= 'Z')) or (C = '_');
end;

function IsIdentChar(C: Char): Boolean; inline;
begin
  Result := IsIdentStart(C) or IsDigit(C);
end;

function IsHexDigit(C: Char): Boolean; inline;
begin
  Result := IsDigit(C) or ((C >= 'a') and (C <= 'f')) or ((C >= 'A') and (C <= 'F'));
end;

{ ---- TLexer ---- }

constructor TLexer.Create(const Source, FileName: string);
begin
  inherited Create;
  FSrc := Source;
  FFile := FileName;
  FPos := 1;
  FLine := 1;
  FCol := 1;
  FAtLineStart := True;
  FTokens := TList<TToken>.Create;
end;

destructor TLexer.Destroy;
begin
  FTokens.Free;
  inherited;
end;

function TLexer.AtEnd: Boolean;
begin
  Result := FPos > Length(FSrc);
end;

function TLexer.Peek(Offset: Integer): Char;
begin
  if FPos + Offset <= Length(FSrc) then
    Result := FSrc[FPos + Offset]
  else
    Result := #0;
end;

{ Number of UTF-16 units in the current code point. }
function TLexer.CharLen: Integer;
begin
  if Peek.IsHighSurrogate and Peek(1).IsLowSurrogate then
    Result := 2
  else
    Result := 1;
end;

{ Moves past the current code point on the same line. }
procedure TLexer.Advance;
begin
  Inc(FPos, CharLen);
  Inc(FCol);
end;

procedure TLexer.Error(const Msg: string; ALine, ACol: Integer);
begin
  raise EAxonError.CreateAt(SyntaxError, Msg, FFile, ALine, ACol);
end;

procedure TLexer.Add(Kind: TTokenKind; const Text: string; ALine, ACol: Integer);
var
  T: TToken;
begin
  T := Default(TToken);
  T.Kind := Kind;
  T.Text := Text;
  T.Line := ALine;
  T.Col := ACol;
  FTokens.Add(T);
  if Kind <> tkNewline then
    FAtLineStart := False;
end;

{ Emits NEWLINE for the line end at the current position (LF, CRLF or CR). }
procedure TLexer.LineBreak;
begin
  Add(tkNewline, '', FLine, FCol);
  if (Peek = #13) and (Peek(1) = #10) then
    Inc(FPos, 2)
  else
    Inc(FPos);
  Inc(FLine);
  FCol := 1;
  FAtLineStart := True;
end;

procedure TLexer.LexComment;
var
  StartLine, StartCol, StartPos: Integer;
  Text: string;
begin
  if Peek(1) = '#' then
  begin
    if FAtLineStart then
    begin
      // Documentation comment: the rest of the line.
      StartLine := FLine;
      StartCol := FCol;
      Advance;
      Advance;
      StartPos := FPos;
      while not AtEnd and (Peek <> #10) and (Peek <> #13) do
        Advance;
      Text := Copy(FSrc, StartPos, FPos - StartPos);
      if Text.StartsWith(' ') then
        Delete(Text, 1, 1);
      Add(tkDocString, Text.TrimRight, StartLine, StartCol);
      Exit;
    end;
  end
  else if Peek(1) = '=' then
  begin
    LexBlockComment;
    Exit;
  end;
  // Line comment.
  while not AtEnd and (Peek <> #10) and (Peek <> #13) do
    Advance;
end;

procedure TLexer.LexBlockComment;
var
  StartLine, StartCol, Depth: Integer;
begin
  StartLine := FLine;
  StartCol := FCol;
  Advance;
  Advance;
  Depth := 1;
  while Depth > 0 do
  begin
    if AtEnd then
      Error('unterminated block comment (missing =#)', StartLine, StartCol);
    if (Peek = '#') and (Peek(1) = '=') then
    begin
      Inc(Depth);
      Advance;
      Advance;
    end
    else if (Peek = '=') and (Peek(1) = '#') then
    begin
      Dec(Depth);
      Advance;
      Advance;
    end
    else if (Peek = #10) or (Peek = #13) then
      LineBreak
    else
      Advance;
  end;
  FAtLineStart := False;
end;

procedure TLexer.LexNumber;
var
  StartLine, StartCol, StartPos: Integer;
  IsReal: Boolean;
  Clean: string;
  IntVal: Int64;
  RealVal: Double;

  procedure ScanDigits;
  begin
    while IsDigit(Peek) or ((Peek = '_') and IsDigit(Peek(1))) do
      Advance;
  end;

begin
  StartLine := FLine;
  StartCol := FCol;
  StartPos := FPos;
  IsReal := False;
  ScanDigits;

  if Peek = '.' then
  begin
    if IsDigit(Peek(1)) then
    begin
      Advance;
      ScanDigits;
      IsReal := True;
    end
    else if not CharInSet(Peek(1), ['*', '/', '\', '^']) then
      Error(Format('a real literal needs a digit after the decimal point (write %0:s.0, not %0:s.)',
        [Copy(FSrc, StartPos, FPos - StartPos)]), FLine, FCol);
    // Otherwise the '.' starts a dot operator: 1.*x is 1 .* x.
  end;

  if CharInSet(Peek, ['e', 'E']) and
     (IsDigit(Peek(1)) or (CharInSet(Peek(1), ['+', '-']) and IsDigit(Peek(2)))) then
  begin
    Advance;
    if CharInSet(Peek, ['+', '-']) then
      Advance;
    ScanDigits;
    IsReal := True;
  end;

  Clean := Copy(FSrc, StartPos, FPos - StartPos).Replace('_', '');

  if (Peek = 'i') and not IsIdentChar(Peek(1)) then
  begin
    Advance;
    if not TryDecimalToDouble(Clean, RealVal) or
       RealVal.IsInfinity then
      Error('imaginary literal is out of range', StartLine, StartCol);
    Add(tkImag, Clean + 'i', StartLine, StartCol);
    FTokens.List[FTokens.Count - 1].RealValue := RealVal;
  end
  else if IsReal then
  begin
    if not TryDecimalToDouble(Clean, RealVal) or
       RealVal.IsInfinity then
      Error('real literal is out of range', StartLine, StartCol);
    Add(tkReal, Clean, StartLine, StartCol);
    FTokens.List[FTokens.Count - 1].RealValue := RealVal;
  end
  else
  begin
    if not TryStrToInt64(Clean, IntVal) then
      Error('integer literal is too large for a 64-bit int', StartLine, StartCol);
    Add(tkInt, Clean, StartLine, StartCol);
    FTokens.List[FTokens.Count - 1].IntValue := IntVal;
  end;
end;

procedure TLexer.LexIdent;
var
  StartCol, StartPos: Integer;
  Word: string;
  Kind: TTokenKind;
begin
  StartCol := FCol;
  StartPos := FPos;
  while IsIdentChar(Peek) do
    Advance;
  Word := Copy(FSrc, StartPos, FPos - StartPos);

  if KeywordTable.TryGetValue(Word, Kind) and
     ((Kind <= LastReservedKeyword) or FInExtern) then
  begin
    Add(Kind, Word, FLine, StartCol);
    if Kind = tkExtern then
      FInExtern := True
    else if Kind = tkEnd then
      FInExtern := False;
  end
  else
    Add(tkIdent, Word, FLine, StartCol);
end;

procedure TLexer.LexString;
var
  StartLine, StartCol, EscLine, EscCol, Digits: Integer;
  SB: TStringBuilder;
  Code: Cardinal;
begin
  StartLine := FLine;
  StartCol := FCol;
  Advance;  // opening quote
  SB := TStringBuilder.Create;
  try
    while True do
    begin
      if AtEnd or (Peek = #10) or (Peek = #13) then
        Error('unterminated string (strings cannot span lines)', StartLine, StartCol);
      if Peek = '"' then
      begin
        Advance;
        Break;
      end;
      if Peek = '\' then
      begin
        EscLine := FLine;
        EscCol := FCol;
        Advance;
        case Peek of
          'n': begin SB.Append(#10); Advance; end;
          't': begin SB.Append(#9); Advance; end;
          '"': begin SB.Append('"'); Advance; end;
          '\': begin SB.Append('\'); Advance; end;
          'u':
            begin
              Advance;
              if Peek <> '{' then
                Error('\u must be followed by {hex digits}', EscLine, EscCol);
              Advance;
              Code := 0;
              Digits := 0;
              while IsHexDigit(Peek) do
              begin
                if Digits = 6 then
                  Error('\u{...} takes at most 6 hex digits', EscLine, EscCol);
                Code := Code * 16 + Cardinal(StrToInt('$' + Peek));
                Inc(Digits);
                Advance;
              end;
              if (Digits = 0) or (Peek <> '}') then
                Error('\u{...} needs 1 to 6 hex digits and a closing }', EscLine, EscCol);
              Advance;
              if (Code > $10FFFF) or ((Code >= $D800) and (Code <= $DFFF)) then
                Error(Format('\u{%X} is not a valid Unicode code point', [Code]),
                  EscLine, EscCol);
              SB.Append(Char.ConvertFromUtf32(Code));
            end;
        else
          if AtEnd or (Peek = #10) or (Peek = #13) then
            Error('unterminated string (strings cannot span lines)', StartLine, StartCol);
          Error(Format('unknown escape \%s in string', [Copy(FSrc, FPos, CharLen)]),
            EscLine, EscCol);
        end;
      end
      else
      begin
        SB.Append(FSrc, FPos - 1, CharLen);
        Advance;
      end;
    end;
    Add(tkString, SB.ToString, StartLine, StartCol);
  finally
    SB.Free;
  end;
end;

procedure TLexer.LexOperator;
var
  StartCol: Integer;
  C, N: Char;
  Kind: TTokenKind;
  Two: Boolean;
  Shown: string;
begin
  StartCol := FCol;
  C := Peek;
  N := Peek(1);
  Two := True;
  Kind := tkEOF;
  case C of
    '.':
      case N of
        '*': Kind := tkDotStar;
        '/': Kind := tkDotSlash;
        '\': Kind := tkDotBackslash;
        '^': Kind := tkDotCaret;
        '0'..'9':
          Error('a real literal needs a digit before the decimal point (write 0.5, not .5)',
            FLine, FCol);
      else
        Two := False;
        Kind := tkDot;
      end;
    '=':
      case N of
        '=': Kind := tkEqEq;
        '>': Kind := tkArrow;
      else
        Two := False;
        Kind := tkAssign;
      end;
    '!':
      if N = '=' then
        Kind := tkNotEq
      else
        Error('unexpected "!"; negation is written "not"', FLine, FCol);
    '<':
      if N = '=' then Kind := tkLessEq else begin Two := False; Kind := tkLess; end;
    '>':
      if N = '=' then Kind := tkGreaterEq else begin Two := False; Kind := tkGreater; end;
  else
    Two := False;
    case C of
      '+': Kind := tkPlus;
      '-': Kind := tkMinus;
      '*': Kind := tkStar;
      '/': Kind := tkSlash;
      '\': Kind := tkBackslash;
      '^': Kind := tkCaret;
      '''': Kind := tkQuote;
      ':': Kind := tkColon;
      ',': Kind := tkComma;
      ';': Kind := tkSemicolon;
      '(': Kind := tkLParen;
      ')': Kind := tkRParen;
      '[': Kind := tkLBracket;
      ']': Kind := tkRBracket;
      '{': Kind := tkLBrace;
      '}': Kind := tkRBrace;
    else
      Shown := Copy(FSrc, FPos, CharLen);
      if (Shown < ' ') or (Shown = #$7F) then
        Shown := Format('U+%.4X', [Ord(C)])
      else
        Shown := Format('"%s" (U+%.4X)', [Shown, Char.ConvertToUtf32(FSrc, FPos - 1)]);
      Error('unexpected character ' + Shown, FLine, FCol);
    end;
  end;
  Advance;
  if Two then
    Advance;
  Add(Kind, TokenSpelling[Kind], FLine, StartCol);
end;

function TLexer.Run: TArray<TToken>;
var
  C: Char;
begin
  while not AtEnd do
  begin
    C := Peek;
    case C of
      ' ', #9:
        Advance;
      #10, #13:
        LineBreak;
      '#':
        LexComment;
      '"':
        LexString;
      '0'..'9':
        LexNumber;
      'a'..'z', 'A'..'Z', '_':
        LexIdent;
    else
      LexOperator;
    end;
  end;
  Add(tkEOF, '', FLine, FCol);
  Result := FTokens.ToArray;
end;

function Tokenize(const Source, FileName: string): TArray<TToken>;
var
  Lexer: TLexer;
begin
  Lexer := TLexer.Create(Source, FileName);
  try
    Result := Lexer.Run;
  finally
    Lexer.Free;
  end;
end;

procedure BuildKeywordTable;
var
  K: TTokenKind;
begin
  KeywordTable := TDictionary<string, TTokenKind>.Create;
  for K := FirstKeyword to LastKeyword do
    KeywordTable.Add(TokenSpelling[K], K);
end;

initialization
  BuildKeywordTable;

finalization
  KeywordTable.Free;

end.
