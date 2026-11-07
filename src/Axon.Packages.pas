unit Axon.Packages;

(* package.toml manifests and module file resolution (reference, "Modules").

   The manifest format is a small subset of TOML: [section] and [section.sub]
   headers, key = value lines whose value is a double-quoted string (with the
   usual escapes), a number or true/false, and # comments. Anything else is an
   ImportError naming the file and line. *)

interface

uses
  System.SysUtils, System.Generics.Collections;

type
  TManifest = class
  public
    FileName: string;            // full path of package.toml
    Dir: string;                 // its directory, with a trailing separator
    Name, Version: string;
    Dependencies: TDictionary<string, string>;               // name -> full root path
    Natives: TObjectDictionary<string, TDictionary<string, string>>;  // lib -> platform -> file
    constructor Create;
    destructor Destroy; override;
    { The full path of a native library for this platform, or '' if the
      manifest has no entry for it. }
    function NativePath(const Lib: string): string;
  end;

{ The nearest package.toml at or above Dir, or nil. Manifests are parsed
  once and cached. }
function FindManifest(const Dir: string): TManifest;

{ The file for module Name (dotted) below Root, or '' if there is none. }
function ModuleFileIn(const Root, Name: string): string;

{ The platform key used in [native.*] tables: windows, macos or linux. }
function PlatformKey: string;

{ A path for messages: relative to the working directory when below it, with
  / as the separator. }
function DisplayPath(const Path: string): string;

{ A key that identifies a file: the full path, case-folded on Windows. }
function FileKey(const Path: string): string;

implementation

uses
  System.IOUtils, System.StrUtils,
  Axon.Errors, Axon.Source;

var
  Cache: TObjectDictionary<string, TManifest>;   // directory key -> manifest (or nil)

constructor TManifest.Create;
begin
  inherited;
  Dependencies := TDictionary<string, string>.Create;
  Natives := TObjectDictionary<string, TDictionary<string, string>>.Create([doOwnsValues]);
end;

destructor TManifest.Destroy;
begin
  Dependencies.Free;
  Natives.Free;
  inherited;
end;

function PlatformKey: string;
begin
{$IFDEF MSWINDOWS}
  Result := 'windows';
{$ENDIF}
{$IFDEF MACOS}
  Result := 'macos';
{$ENDIF}
{$IFDEF LINUX}
  Result := 'linux';
{$ENDIF}
end;

function TManifest.NativePath(const Lib: string): string;
var
  Table: TDictionary<string, string>;
  F: string;
begin
  Result := '';
  if Natives.TryGetValue(Lib, Table) and Table.TryGetValue(PlatformKey, F) then
    Result := TPath.GetFullPath(TPath.Combine(Dir, F));
end;

function FileKey(const Path: string): string;
begin
  Result := TPath.GetFullPath(Path);
{$IFDEF MSWINDOWS}
  Result := LowerCase(Result);
{$ENDIF}
end;

function DisplayPath(const Path: string): string;
var
  Cwd, Full: string;
begin
  Full := TPath.GetFullPath(Path);
  Cwd := IncludeTrailingPathDelimiter(GetCurrentDir);
  if StartsText(Cwd, Full) then
    Result := Copy(Full, Length(Cwd) + 1, MaxInt)
  else
    Result := Full;
  Result := Result.Replace('\', '/');
end;

{ ---- TOML subset ---- }

procedure ManifestError(const FileName: string; Line: Integer; const Msg: string);
begin
  raise EAxonError.Create(ImportError, Format('%s:%d: %s', [DisplayPath(FileName), Line, Msg]));
end;

{ Parses a value: "string", a number, true or false. Returns its text. }
function ParseValue(const FileName: string; LineNo: Integer; const S: string): string;
var
  I: Integer;
  SB: TStringBuilder;
  C: Char;
begin
  if S = '' then
    ManifestError(FileName, LineNo, 'missing value after "="');
  if S[1] = '"' then
  begin
    SB := TStringBuilder.Create;
    try
      I := 2;
      while True do
      begin
        if I > Length(S) then
          ManifestError(FileName, LineNo, 'unterminated string');
        C := S[I];
        if C = '"' then
          Break;
        if C = '\' then
        begin
          Inc(I);
          if I > Length(S) then
            ManifestError(FileName, LineNo, 'unterminated string');
          case S[I] of
            'n': SB.Append(#10);
            't': SB.Append(#9);
            '"': SB.Append('"');
            '\': SB.Append('\');
          else
            ManifestError(FileName, LineNo, 'unknown escape \' + S[I]);
          end;
        end
        else
          SB.Append(C);
        Inc(I);
      end;
      // Only a comment may follow the closing quote.
      if Trim(Copy(S, I + 1, MaxInt)) <> '' then
        if not StartsStr('#', Trim(Copy(S, I + 1, MaxInt))) then
          ManifestError(FileName, LineNo, 'unexpected text after the value');
      Exit(SB.ToString);
    finally
      SB.Free;
    end;
  end;
  Result := Trim(S);
  I := Pos('#', Result);
  if I > 0 then
    Result := Trim(Copy(Result, 1, I - 1));
  if (Result = 'true') or (Result = 'false') then
    Exit;
  for C in Result do
    if not CharInSet(C, ['0'..'9', '.', '-', '+', 'e', 'E', '_']) then
      ManifestError(FileName, LineNo, Format('invalid value "%s" (use a "string", a number, true or false)',
        [Result]));
end;

function ParseManifest(const FileName: string): TManifest;
var
  Lines: TArray<string>;
  LineNo, P: Integer;
  Line, Section, Key, Value: string;
  Table: TDictionary<string, string>;
begin
  Result := TManifest.Create;
  try
    Result.FileName := TPath.GetFullPath(FileName);
    Result.Dir := IncludeTrailingPathDelimiter(ExtractFileDir(Result.FileName));
    Lines := LoadUtf8File(FileName).Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
    Section := '';
    for LineNo := 1 to Length(Lines) do
    begin
      Line := Trim(Lines[LineNo - 1]);
      if (Line = '') or StartsStr('#', Line) then
        Continue;
      if StartsStr('[', Line) then
      begin
        P := Pos(']', Line);
        if P = 0 then
          ManifestError(FileName, LineNo, 'missing "]" in section header');
        Section := Trim(Copy(Line, 2, P - 2));
        if Section = '' then
          ManifestError(FileName, LineNo, 'empty section name');
        if StartsStr('native.', Section) and not Result.Natives.ContainsKey(Copy(Section, 8, MaxInt)) then
          Result.Natives.Add(Copy(Section, 8, MaxInt), TDictionary<string, string>.Create);
        Continue;
      end;
      P := Pos('=', Line);
      if P = 0 then
        ManifestError(FileName, LineNo, 'expected "key = value"');
      Key := Trim(Copy(Line, 1, P - 1));
      if Key = '' then
        ManifestError(FileName, LineNo, 'missing key before "="');
      Value := ParseValue(FileName, LineNo, Trim(Copy(Line, P + 1, MaxInt)));
      if Section = 'package' then
      begin
        if Key = 'name' then Result.Name := Value
        else if Key = 'version' then Result.Version := Value;
      end
      else if Section = 'dependencies' then
        Result.Dependencies.AddOrSetValue(Key,
          ExcludeTrailingPathDelimiter(TPath.GetFullPath(TPath.Combine(Result.Dir, Value))))
      else if StartsStr('native.', Section) then
      begin
        Table := Result.Natives[Copy(Section, 8, MaxInt)];
        Table.AddOrSetValue(Key, Value);
      end;
      // Other sections are allowed and ignored.
    end;
  except
    Result.Free;
    raise;
  end;
end;

function FindManifest(const Dir: string): TManifest;
var
  D, Key, Candidate, Parent: string;
begin
  D := ExcludeTrailingPathDelimiter(TPath.GetFullPath(Dir));
  while D <> '' do
  begin
    Key := FileKey(D);
    if Cache.TryGetValue(Key, Result) then
    begin
      if Result <> nil then
        Exit;
    end
    else
    begin
      Candidate := TPath.Combine(D, 'package.toml');
      if TFile.Exists(Candidate) then
      begin
        Result := ParseManifest(Candidate);
        Cache.Add(Key, Result);
        Exit;
      end;
      Cache.Add(Key, nil);
    end;
    Parent := ExtractFileDir(D);
    if (Parent = D) or (Parent = '') then
      Break;
    D := Parent;
  end;
  Result := nil;
end;

function ModuleFileIn(const Root, Name: string): string;
var
  Base: string;
begin
  Base := TPath.Combine(Root, Name.Replace('.', PathDelim));
  if TFile.Exists(Base + '.sci') then
    Result := Base + '.sci'
  else if TFile.Exists(Base + '.txt') then
    Result := Base + '.txt'
  else
    Result := '';
end;

initialization
  Cache := TObjectDictionary<string, TManifest>.Create([doOwnsValues]);

finalization
  Cache.Free;

end.
