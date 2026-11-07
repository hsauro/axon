unit Axon.Tokens;

{ Token kinds and the `axon --tokens` dump format.

  Dump format, one token per line:

    LINE:COL KIND [VALUE]

  KIND is EOF, NEWLINE, IDENT, INT, REAL, IMAG, STRING, DOCSTRING, KEYWORD or
  OP. VALUE is:
    IDENT, KEYWORD, OP  the spelling
    INT                 the decimal value
    REAL, IMAG          the literal with any '_' removed (IMAG keeps its 'i')
    STRING, DOCSTRING   the decoded text, quoted and re-escaped }

interface

type
  TTokenKind = (
    tkEOF, tkNewline, tkIdent, tkInt, tkReal, tkImag, tkString, tkDocString,

    // Reserved keywords
    tkFunction, tkEnd, tkReturn, tkIf, tkElseif, tkElse, tkFor, tkIn, tkWhile,
    tkBreak, tkContinue, tkLocal, tkGlobal, tkTry, tkCatch, tkImport, tkFrom,
    tkAs, tkExport, tkExtern, tkRecord, tkTrue, tkFalse, tkNothing, tkAnd,
    tkOr, tkNot,

    // Keywords only inside an extern block
    tkType, tkRef, tkPtr, tkCallback, tkName,

    // Operators and punctuation
    tkPlus, tkMinus, tkStar, tkSlash, tkBackslash, tkCaret,
    tkDotStar, tkDotSlash, tkDotBackslash, tkDotCaret, tkQuote,
    tkEqEq, tkNotEq, tkLess, tkLessEq, tkGreater, tkGreaterEq,
    tkAssign, tkArrow, tkColon, tkComma, tkSemicolon,
    tkLParen, tkRParen, tkLBracket, tkRBracket, tkLBrace, tkRBrace, tkDot);

const
  FirstKeyword = tkFunction;
  LastReservedKeyword = tkNot;
  FirstExternKeyword = tkType;
  LastKeyword = tkName;
  FirstOperator = tkPlus;
  LastOperator = tkDot;

  TokenSpelling: array[TTokenKind] of string = (
    '<end of file>', '<newline>', '<identifier>', '<integer>', '<real>',
    '<imaginary>', '<string>', '<docstring>',
    'function', 'end', 'return', 'if', 'elseif', 'else', 'for', 'in', 'while',
    'break', 'continue', 'local', 'global', 'try', 'catch', 'import', 'from',
    'as', 'export', 'extern', 'record', 'true', 'false', 'nothing', 'and',
    'or', 'not',
    'type', 'ref', 'ptr', 'callback', 'name',
    '+', '-', '*', '/', '\', '^',
    '.*', './', '.\', '.^', '''',
    '==', '!=', '<', '<=', '>', '>=',
    '=', '=>', ':', ',', ';',
    '(', ')', '[', ']', '{', '}', '.');

type
  TToken = record
    Kind: TTokenKind;
    Text: string;        // spelling, cleaned literal text, or decoded string
    IntValue: Int64;     // tkInt
    RealValue: Double;   // tkReal; tkImag (the imaginary part)
    Line: Integer;
    Col: Integer;
  end;

function IsKeyword(Kind: TTokenKind): Boolean; inline;
function IsOperator(Kind: TTokenKind): Boolean; inline;

{ Quotes S and escapes \, ", newline, tab and other control characters. }
function EscapeString(const S: string): string;

{ One line of the --tokens dump, without the line break. }
function DumpToken(const T: TToken): string;

implementation

uses
  System.SysUtils;

function IsKeyword(Kind: TTokenKind): Boolean;
begin
  Result := (Kind >= FirstKeyword) and (Kind <= LastKeyword);
end;

function IsOperator(Kind: TTokenKind): Boolean;
begin
  Result := (Kind >= FirstOperator) and (Kind <= LastOperator);
end;

function EscapeString(const S: string): string;
var
  SB: TStringBuilder;
  C: Char;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('"');
    for C in S do
      case C of
        '"': SB.Append('\"');
        '\': SB.Append('\\');
        #10: SB.Append('\n');
        #9:  SB.Append('\t');
      else
        if C < ' ' then
          SB.Append('\u{').Append(IntToHex(Ord(C), 1)).Append('}')
        else
          SB.Append(C);
      end;
    SB.Append('"');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function DumpToken(const T: TToken): string;
var
  Body: string;
begin
  case T.Kind of
    tkEOF:       Body := 'EOF';
    tkNewline:   Body := 'NEWLINE';
    tkIdent:     Body := 'IDENT ' + T.Text;
    tkInt:       Body := 'INT ' + IntToStr(T.IntValue);
    tkReal:      Body := 'REAL ' + T.Text;
    tkImag:      Body := 'IMAG ' + T.Text;
    tkString:    Body := 'STRING ' + EscapeString(T.Text);
    tkDocString: Body := 'DOCSTRING ' + EscapeString(T.Text);
  else
    if IsKeyword(T.Kind) then
      Body := 'KEYWORD ' + TokenSpelling[T.Kind]
    else
      Body := 'OP ' + TokenSpelling[T.Kind];
  end;
  Result := Format('%d:%d %s', [T.Line, T.Col, Body]);
end;

end.
