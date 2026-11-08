unit uAxonMarkdown;

(* Syntax colouring of Axon code blocks (```axon or ```sci fences) in the
   markdown help viewer, TRhoMarkdownViewer. The viewer asks a registered
   IMarkdownSyntaxHighlighter for tokens; this one runs the IDE's own Axon
   tokenizer (uAxonHighlighter) line by line and maps its colours onto the
   viewer's token kinds, so code reads the same in the help as in the editor. *)

interface

implementation

uses
  System.SysUtils, System.UITypes, System.Generics.Collections,
  uCodeEditorTypes, uAxonHighlighter, uRhoMarkdownHighlight;

type
  TAxonMarkdownHighlighter = class(TInterfacedObject, IMarkdownSyntaxHighlighter)
  private
    FColors: TAxonColors;
    FTokenize: TTokenizeLineProc;
    function KindOf(Color: TAlphaColor): TSourceTokenKind;
  public
    constructor Create;
    function GetLanguageName: string;
    function Highlight(const AText: string): TArray<TSourceToken>;
  end;

constructor TAxonMarkdownHighlighter.Create;
begin
  inherited;
  FColors := DefaultAxonColors;
  FTokenize := AxonTokenizer(FColors);
end;

function TAxonMarkdownHighlighter.GetLanguageName: string;
begin
  Result := 'axon';
end;

function TAxonMarkdownHighlighter.KindOf(Color: TAlphaColor): TSourceTokenKind;
begin
  if Color = FColors.Keyword then Result := stKeyword
  else if Color = FColors.Builtin then Result := stType
  else if Color = FColors.Str then Result := stString
  else if Color = FColors.Number then Result := stNumber
  else if (Color = FColors.Comment) or (Color = FColors.DocString) then Result := stComment
  else Result := stPlain;
end;

function TAxonMarkdownHighlighter.Highlight(const AText: string): TArray<TSourceToken>;
var
  Tokens: TList<TSourceToken>;
  Lines: TArray<string>;
  Line: string;
  Runs: TTokenRunArray;
  Run: TTokenRun;
  State: TLexState;
  LineStart, Pos: Integer;

  procedure Add(Offset, Len: Integer; Kind: TSourceTokenKind);
  var
    T: TSourceToken;
  begin
    if Len <= 0 then
      Exit;
    T.Text := Copy(AText, Offset + 1, Len);
    T.Kind := Kind;
    T.Offset := Offset;
    Tokens.Add(T);
  end;

begin
  Tokens := TList<TSourceToken>.Create;
  try
    Lines := AText.Split([#10]);
    State := lsDefault;
    LineStart := 0;
    for Line in Lines do
    begin
      State := FTokenize(Line.TrimRight([#13]), State, Runs);
      // Plain text between runs, so the tokens cover the whole block.
      Pos := 0;
      for Run in Runs do
      begin
        Add(LineStart + Pos, Run.StartCol - Pos, stPlain);
        Add(LineStart + Run.StartCol, Run.Length, KindOf(Run.Color));
        Pos := Run.StartCol + Run.Length;
      end;
      // The rest of the line and its line break (Copy stops at the end of
      // the text, so the last line needs no special case).
      Add(LineStart + Pos, Length(Line) - Pos + 1, stPlain);
      Inc(LineStart, Length(Line) + 1);
    end;
    Result := Tokens.ToArray;
  finally
    Tokens.Free;
  end;
end;

initialization
  TMarkdownSyntaxHighlighterRegistry.RegisterHighlighter('axon', TAxonMarkdownHighlighter.Create);
  TMarkdownSyntaxHighlighterRegistry.RegisterHighlighter('sci', TAxonMarkdownHighlighter.Create);

end.
