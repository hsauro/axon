unit uAxonHighlighter;

(* Syntax highlighting for Axon, as a TTokenizeLineProc for TSkiaCodeEditor.

   Axon's comments do not fit the editor's ready-made TSimpleHighlighter:
   #= ... =# block comments nest, "#=" must win over the "#" line comment,
   and "##" at the start of a line is a docstring. So this is a small
   hand-written scanner. The lexical rules follow the Language Reference,
   "Lexical structure".

   Lex state: 0 outside a block comment, N > 0 inside N nested block
   comments. Strings cannot span lines, so they need no state. *)

interface

uses
  System.SysUtils, System.UITypes, uCodeEditorTypes;

type
  TAxonColors = record
    Keyword, Builtin, Str, Number, Comment, DocString: TAlphaColor;
  end;

function DefaultAxonColors: TAxonColors;
{ The same roles for a dark background. }
function DarkAxonColors: TAxonColors;

{ The tokenizer for TSkiaCodeEditor.SetTokenizer. }
function AxonTokenizer(const Colors: TAxonColors): TTokenizeLineProc;

implementation

uses
  System.Generics.Collections;

const
  // The reserved keywords. type, ref, ptr, callback and name are keywords
  // only inside extern blocks, and ordinary names elsewhere, so they are left
  // plain.
  Keywords: array[0..26] of string = (
    'function', 'end', 'return', 'if', 'elseif', 'else', 'for', 'in', 'while',
    'break', 'continue', 'local', 'global', 'try', 'catch', 'import', 'from',
    'as', 'export', 'extern', 'record', 'true', 'false', 'nothing', 'and',
    'or', 'not');

  // The prelude functions (available without import), and the constant pi
  // (not e, which is often a variable of the program's own).
  Builtins: array[0..76] of string = (
    'zeros', 'ones', 'eye', 'rand', 'linspace', 'size', 'sum', 'prod', 'mean',
    'all', 'any', 'dot', 'adjoint', 'isequal', 'keep', 'eltype', 'reshape',
    'sparse', 'speye', 'nnz', 'full', 'splu', 'append', 'get', 'keys', 'haskey',
    'dict', 'print', 'error', 'string', 'length', 'typeof', 'sqrt', 'exp', 'log',
    'sin', 'cos', 'tan', 'asin', 'acos', 'atan', 'sinh', 'cosh', 'tanh', 'asinh',
    'acosh', 'atanh', 'abs', 'int', 'floor', 'ceil', 'round', 'real', 'imag',
    'conj', 'arg', 'complex', 'div', 'mod', 'min', 'max', 'factorial',
    'println', 'format', 'display_size', 'display_decimals', 'pi',
    'sort', 'sortperm', 'atexit', 'range', 'isa', 'tr', 'trace', 'split', 'join',
    'trim');

var
  KeywordSet, BuiltinSet: TDictionary<string, Boolean>;

function DefaultAxonColors: TAxonColors;
begin
  Result.Keyword := $FF0033B3;    // blue
  Result.Builtin := $FF00796B;    // teal
  Result.Str := $FFA31515;        // dark red
  Result.Number := $FF098658;     // green
  Result.Comment := $FF6A737D;    // grey
  Result.DocString := $FF8A5A00;  // brown, so docstrings stand out from comments
end;

function DarkAxonColors: TAxonColors;
begin
  Result.Keyword := $FF569CD6;    // blue
  Result.Builtin := $FF4EC9B0;    // teal
  Result.Str := $FFCE9178;        // orange
  Result.Number := $FFB5CEA8;     // pale green
  Result.Comment := $FF6A9955;    // green
  Result.DocString := $FFD7BA7D;  // gold
end;

function IsIdentStart(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '_']);
end;

function IsIdentChar(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

function IsDigit(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['0'..'9']);
end;

function AxonTokenizer(const Colors: TAxonColors): TTokenizeLineProc;
begin
  Result :=
    function(const ALine: string; AStateIn: TLexState; out ARuns: TTokenRunArray): TLexState
    var
      Runs: TList<TTokenRun>;
      N, I, Start, Depth: Integer;
      Word: string;
      AtLineStart: Boolean;

      procedure Add(AStart, ALength: Integer; AColor: TAlphaColor);
      var
        R: TTokenRun;
      begin
        if ALength <= 0 then
          Exit;
        R.StartCol := AStart - 1;   // 0-based
        R.Length := ALength;
        R.Color := AColor;
        R.Bold := False;
        R.Italic := False;
        Runs.Add(R);
      end;

      { Scans a block comment body from I until its depth reaches 0 or the
        line ends; I is left after the closing "=#". }
      procedure ScanBlock;
      begin
        while I <= N do
        begin
          if (ALine[I] = '#') and (I < N) and (ALine[I + 1] = '=') then
          begin
            Inc(Depth);
            Inc(I, 2);
          end
          else if (ALine[I] = '=') and (I < N) and (ALine[I + 1] = '#') then
          begin
            Dec(Depth);
            Inc(I, 2);
            if Depth = 0 then
              Exit;
          end
          else
            Inc(I);
        end;
      end;

    begin
      Runs := TList<TTokenRun>.Create;
      try
        N := Length(ALine);
        I := 1;
        Depth := AStateIn;
        if Depth > 0 then
        begin
          Start := I;
          ScanBlock;
          Add(Start, I - Start, Colors.Comment);
        end;
        AtLineStart := True;    // only spaces so far (for "##" docstrings)
        while I <= N do
        begin
          if ALine[I] = '#' then
          begin
            Start := I;
            if (I < N) and (ALine[I + 1] = '=') then
            begin
              Depth := 1;
              Inc(I, 2);
              ScanBlock;
              Add(Start, I - Start, Colors.Comment);
            end
            else
            begin
              if AtLineStart and (I < N) and (ALine[I + 1] = '#') then
                Add(Start, N - Start + 1, Colors.DocString)
              else
                Add(Start, N - Start + 1, Colors.Comment);
              I := N + 1;
            end;
          end
          else if ALine[I] = '"' then
          begin
            Start := I;
            Inc(I);
            while (I <= N) and (ALine[I] <> '"') do
            begin
              if (ALine[I] = '\') and (I < N) then
                Inc(I);
              Inc(I);
            end;
            if I <= N then
              Inc(I);   // the closing quote
            Add(Start, I - Start, Colors.Str);
          end
          else if IsDigit(ALine[I]) then
          begin
            // INT, REAL (a digit on both sides of the point) or IMAG.
            Start := I;
            while (I <= N) and (IsDigit(ALine[I]) or (ALine[I] = '_')) do
              Inc(I);
            if (I < N) and (ALine[I] = '.') and IsDigit(ALine[I + 1]) then
            begin
              Inc(I);
              while (I <= N) and (IsDigit(ALine[I]) or (ALine[I] = '_')) do
                Inc(I);
            end;
            if (I <= N) and CharInSet(ALine[I], ['e', 'E']) then
            begin
              if (I < N) and IsDigit(ALine[I + 1]) then
                Inc(I)
              else if (I + 1 < N) and CharInSet(ALine[I + 1], ['+', '-']) and IsDigit(ALine[I + 2]) then
                Inc(I, 2);
              while (I <= N) and IsDigit(ALine[I]) do
                Inc(I);
            end;
            if (I <= N) and (ALine[I] = 'i') and ((I = N) or not IsIdentChar(ALine[I + 1])) then
              Inc(I);
            Add(Start, I - Start, Colors.Number);
          end
          else if IsIdentStart(ALine[I]) then
          begin
            Start := I;
            while (I <= N) and IsIdentChar(ALine[I]) do
              Inc(I);
            Word := Copy(ALine, Start, I - Start);
            if KeywordSet.ContainsKey(Word) then
              Add(Start, I - Start, Colors.Keyword)
            else if BuiltinSet.ContainsKey(Word) then
              Add(Start, I - Start, Colors.Builtin);
          end
          else
            Inc(I);
          if (I > 1) and (ALine[I - 1] <> ' ') and (ALine[I - 1] <> #9) then
            AtLineStart := False;
        end;
        ARuns := Runs.ToArray;
        Result := Depth;
      finally
        Runs.Free;
      end;
    end;
end;

procedure BuildSets;
var
  W: string;
begin
  KeywordSet := TDictionary<string, Boolean>.Create;
  for W in Keywords do
    KeywordSet.Add(W, True);
  BuiltinSet := TDictionary<string, Boolean>.Create;
  for W in Builtins do
    BuiltinSet.Add(W, True);
end;

initialization
  BuildSets;

finalization
  KeywordSet.Free;
  BuiltinSet.Free;

end.
