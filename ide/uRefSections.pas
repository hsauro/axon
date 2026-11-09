unit uRefSections;

{ Finds the Language Reference section that documents a name, for the Help
  pane (F1). A module function m.f, and a module m, use the section "The m
  module"; other names use the table below. Sections are cut from the
  reference's markdown text: from the heading to the next heading of the
  same or a higher level. Anchors are GitHub's (RhoHeadingSlug, with -1, -2
  for repeated headings), as in the reference's Contents. }

interface

// The anchor (without '#') of the section documenting Name, or ''. A
// qualified Name must use the real module name (any import alias resolved).
function SectionAnchorFor(const RefText, Name: string): string;
// The markdown of the section with that anchor, heading included, or ''.
function SectionMarkdown(const RefText, Anchor: string): string;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uRhoMarkdownViewer;

const
  // Anchor, then the built-ins it documents. Keep in step with the
  // reference's headings: a stale anchor only means no section is shown.
  Sections: array[0..16] of string = (
    'printing: print println display_size display_decimals format',
    'output-and-text-functions: split join trim ltrim rtrim upper lower contains ' +
      'startswith endswith find replace repeat',
    'strings-1: string',
    'vectors-and-matrices: zeros ones eye rand linspace size length reshape ' +
      'eltype sum prod mean min max all any',
    'numeric-promotion: int floor ceil round real complex div mod',
    'elementary-functions: sqrt exp log sin cos tan asin acos atan sinh cosh tanh ' +
      'asinh acosh atanh abs factorial',
    'complex-number-functions: imag conj arg',
    'constants: pi e',
    'ranges: range',
    'array-functions: sort sortperm',
    'other-built-in-functions: atexit isa',
    'sparse-operands: sparse speye nnz full splu',
    'lists-records-and-dictionaries: append get keys haskey dict typeof',
    'comparison: isequal',
    'errors: error',
    'linear-algebra-operators: dot adjoint tr trace',
    'foreign-functions: keep');

type
  THeading = record
    Line: Integer;     // index into the line list
    Level: Integer;    // number of #
    Anchor: string;
  end;

{ The headings of a markdown text, outside code fences, with their anchors. }
function Headings(Lines: TStrings): TArray<THeading>;
var
  I, Level, N: Integer;
  L, Title, Slug: string;
  InFence: Boolean;
  Counts: TDictionary<string, Integer>;
  H: THeading;
  List: TList<THeading>;
begin
  List := TList<THeading>.Create;
  Counts := TDictionary<string, Integer>.Create;
  try
    InFence := False;
    for I := 0 to Lines.Count - 1 do
    begin
      L := Lines[I];
      if L.TrimLeft.StartsWith('```') then
      begin
        InFence := not InFence;
        Continue;
      end;
      if InFence or not L.StartsWith('#') then
        Continue;
      Level := 0;
      while (Level < L.Length) and (L.Chars[Level] = '#') do
        Inc(Level);
      if (Level > 6) or (Level >= L.Length) or (L.Chars[Level] <> ' ') then
        Continue;
      Title := L.Substring(Level).Trim.Replace('`', '').Replace('*', '');
      Slug := RhoHeadingSlug(Title);
      if Counts.TryGetValue(Slug, N) then
      begin
        Counts[Slug] := N + 1;
        Slug := Slug + '-' + IntToStr(N);
      end
      else
        Counts.Add(Slug, 1);
      H.Line := I;
      H.Level := Level;
      H.Anchor := Slug;
      List.Add(H);
    end;
    Result := List.ToArray;
  finally
    Counts.Free;
    List.Free;
  end;
end;

function HasAnchor(const RefText, Anchor: string): Boolean;
var
  Lines: TStringList;
  H: THeading;
begin
  Result := False;
  Lines := TStringList.Create;
  try
    Lines.Text := RefText;
    for H in Headings(Lines) do
      if H.Anchor = Anchor then
        Exit(True);
  finally
    Lines.Free;
  end;
end;

function SectionAnchorFor(const RefText, Name: string): string;
var
  P: Integer;
  Module, Entry, Names: string;
  Parts: TArray<string>;
  S: string;
begin
  Result := '';
  // m.f, or a module m on its own.
  P := Name.IndexOf('.');
  if P >= 0 then
    Module := Name.Substring(0, P)
  else
    Module := Name;
  if HasAnchor(RefText, 'the-' + LowerCase(Module) + '-module') then
    Exit('the-' + LowerCase(Module) + '-module');
  if P >= 0 then
    Exit;
  for Entry in Sections do
  begin
    P := Entry.IndexOf(':');
    Names := ' ' + Entry.Substring(P + 1).Trim + ' ';
    Parts := Names.Split([' '], TStringSplitOptions.ExcludeEmpty);
    for S in Parts do
      if S = Name then
        Exit(Entry.Substring(0, P));
  end;
end;

function SectionMarkdown(const RefText, Anchor: string): string;
var
  Lines: TStringList;
  Hs: TArray<THeading>;
  I, Last, K: Integer;
  SB: TStringBuilder;
begin
  Result := '';
  if Anchor = '' then
    Exit;
  Lines := TStringList.Create;
  SB := TStringBuilder.Create;
  try
    Lines.Text := RefText;
    Hs := Headings(Lines);
    for I := 0 to High(Hs) do
      if Hs[I].Anchor = Anchor then
      begin
        Last := Lines.Count - 1;
        for K := I + 1 to High(Hs) do
          if Hs[K].Level <= Hs[I].Level then
          begin
            Last := Hs[K].Line - 1;
            Break;
          end;
        for K := Hs[I].Line to Last do
          SB.Append(Lines[K]).Append(#10);
        Exit(SB.ToString.TrimRight);
      end;
  finally
    SB.Free;
    Lines.Free;
  end;
end;

end.
