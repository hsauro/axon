unit Axon.TestRunner;

{ `axon test [-v] [path]`

  Runs the conformance tests described in doc/Axon-Milestones.md, section
  "How the tests work". Each test runs the interpreter (this same executable)
  as a child process, so a crash or a hang in one test cannot take down the
  runner.

  Layout: tests/mNN/ holds the tests of milestone NN. Only .sci files directly
  inside a milestone folder are tests; subfolders are fixtures (modules,
  packages). A .sci file with no expectation is also treated as a fixture.

  Kinds of expectation for name.sci:
    first line "#! error: Kind"  - must stop with an uncaught error of that kind
                                   (if name.out exists, stdout is compared too,
                                   and if name.err exists, so is stderr)
    name.out                     - must exit normally with exactly this stdout
    name.tokens                  - output of `axon --tokens name.sci`
    name.ast                     - output of `axon --ast name.sci`

  A name.repl file is a REPL transcript: `axon --transcript name.repl` must
  reproduce it, ignoring trailing spaces and trailing blank lines.

  Line endings are normalised to LF before comparison. }

interface

{ Args are the command-line arguments after "test". Returns the exit code. }
function RunTestCommand(const Args: TArray<string>): Integer;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.StrUtils,
  System.Generics.Collections, System.Generics.Defaults,
  Axon.Errors, Axon.Platform, Axon.Source;

const
  TestTimeoutMs = 10000;
  ErrorDirective = '#! error:';

type
  TTestKind = (tkOutput, tkError, tkTokens, tkAst, tkTranscript);

  TTestCase = record
    Source: string;          // full path of the .sci (or .repl) file
    Kind: TTestKind;
    ExpectedFile: string;    // .out / .tokens / .ast, or '' for none
    ExpectedKind: string;    // for tkError
    ExpectedErrFile: string; // for tkError: optional .err, compared with stderr
  end;

  TGroup = record
    Name: string;
    Cases: TArray<TTestCase>;
    Fixtures: Integer;
  end;

const
  KindNames: array[TTestKind] of string = ('output', 'error', 'tokens', 'ast', 'transcript');

function Normalize(const S: string): string;
begin
  Result := S.Replace(#13#10, #10).Replace(#13, #10);
end;

{ A transcript compares without trailing spaces or trailing blank lines. }
function NormalizeTranscript(const S: string): string;
var
  L: string;
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    for L in Normalize(S).Split([#10]) do
      SB.Append(L.TrimRight).Append(#10);
    Result := SB.ToString.TrimRight + #10;
  finally
    SB.Free;
  end;
end;

function QuoteLine(const S: string): string;
begin
  Result := '"' + S.Replace('\', '\\').Replace('"', '\"').Replace(#9, '\t') + '"';
end;

{ Describes the first difference between two normalised texts. }
function DescribeDiff(const Expected, Actual: string): string;
var
  E, A: TArray<string>;
  I, N: Integer;
  ELine, ALine: string;
begin
  E := Expected.Split([#10]);
  A := Actual.Split([#10]);
  N := Length(E);
  if Length(A) > N then N := Length(A);
  for I := 0 to N - 1 do
    if (I >= Length(E)) or (I >= Length(A)) or (E[I] <> A[I]) then
    begin
      if I >= Length(E) then ELine := '<end of output>' else ELine := QuoteLine(E[I]);
      if I >= Length(A) then ALine := '<end of output>' else ALine := QuoteLine(A[I]);
      Exit(Format('line %d: expected %s' + sLineBreak + '%s actual   %s',
        [I + 1, ELine, StringOfChar(' ', Length(Format('line %d:', [I + 1]))), ALine]));
    end;
  Result := 'outputs differ';
end;

function FirstLineOf(const Text: string): string;
var
  P: Integer;
begin
  P := Pos(#10, Text);
  if P > 0 then Result := Copy(Text, 1, P - 1) else Result := Text;
  Result := Result.TrimRight([#13]);
end;

{ Kind named in the first line of an uncaught-error report "Kind: message". }
function ReportedKind(const StdErr: string): string;
var
  Line: string;
  P: Integer;
begin
  Line := Trim(FirstLineOf(Normalize(StdErr)));
  P := Pos(':', Line);
  if P > 0 then Result := Copy(Line, 1, P - 1) else Result := Line;
end;

function IndentLines(const S, Prefix: string): string;
begin
  Result := Prefix + Normalize(S).TrimRight([#10]).Replace(#10, sLineBreak + Prefix);
end;

{ ---- Collecting tests ---- }

function IsMilestoneDir(const Name: string): Boolean;
var
  I: Integer;
begin
  Result := (Length(Name) >= 2) and (Name[1] = 'm');
  if Result then
    for I := 2 to Length(Name) do
      if not CharInSet(Name[I], ['0'..'9']) then
        Exit(False);
end;

procedure AddCasesForFile(const SciFile: string; List: TList<TTestCase>;
  var Fixtures: Integer);
var
  Base, Line, Expected: string;
  C: TTestCase;
  Found: Boolean;
begin
  Base := ChangeFileExt(SciFile, '');
  Found := False;

  // A .repl file is a REPL transcript that must reproduce itself.
  if SameText(ExtractFileExt(SciFile), '.repl') then
  begin
    C := Default(TTestCase);
    C.Source := SciFile;
    C.Kind := tkTranscript;
    C.ExpectedFile := SciFile;
    List.Add(C);
    Exit;
  end;

  Line := Trim(FirstLineOf(LoadSourceFile(SciFile)));
  if StartsText(ErrorDirective, Line) then
  begin
    C := Default(TTestCase);
    C.Source := SciFile;
    C.Kind := tkError;
    C.ExpectedKind := Trim(Copy(Line, Length(ErrorDirective) + 1, MaxInt));
    if TFile.Exists(Base + '.out') then
      C.ExpectedFile := Base + '.out';
    if TFile.Exists(Base + '.err') then
      C.ExpectedErrFile := Base + '.err';
    List.Add(C);
    Found := True;
  end
  else if TFile.Exists(Base + '.out') then
  begin
    C := Default(TTestCase);
    C.Source := SciFile;
    C.Kind := tkOutput;
    C.ExpectedFile := Base + '.out';
    List.Add(C);
    Found := True;
  end;

  for Expected in ['.tokens', '.ast'] do
    if TFile.Exists(Base + Expected) then
    begin
      C := Default(TTestCase);
      C.Source := SciFile;
      if Expected = '.tokens' then C.Kind := tkTokens else C.Kind := tkAst;
      C.ExpectedFile := Base + Expected;
      List.Add(C);
      Found := True;
    end;

  if not Found then
    Inc(Fixtures);
end;

function CollectGroup(const Dir, Name: string): TGroup;
var
  Files: TArray<string>;
  F: string;
  List: TList<TTestCase>;
begin
  Result.Name := Name;
  Result.Fixtures := 0;
  Files := TDirectory.GetFiles(Dir, '*.sci', TSearchOption.soTopDirectoryOnly) +
    TDirectory.GetFiles(Dir, '*.repl', TSearchOption.soTopDirectoryOnly);
  TArray.Sort<string>(Files, TStringComparer.Ordinal);
  List := TList<TTestCase>.Create;
  try
    for F in Files do
      AddCasesForFile(F, List, Result.Fixtures);
    Result.Cases := List.ToArray;
  finally
    List.Free;
  end;
end;

function CollectGroups(const Path: string): TArray<TGroup>;
var
  Dirs: TArray<string>;
  D, FullPath: string;
  Groups: TList<TGroup>;
  G: TGroup;
  List: TList<TTestCase>;
begin
  FullPath := ExcludeTrailingPathDelimiter(TPath.GetFullPath(Path));
  Groups := TList<TGroup>.Create;
  try
    if TFile.Exists(FullPath) then
    begin
      // A single test file.
      G.Name := ExtractFileName(ExtractFileDir(FullPath));
      G.Fixtures := 0;
      List := TList<TTestCase>.Create;
      try
        AddCasesForFile(FullPath, List, G.Fixtures);
        G.Cases := List.ToArray;
      finally
        List.Free;
      end;
      Groups.Add(G);
    end
    else if TDirectory.Exists(FullPath) then
    begin
      Dirs := TDirectory.GetDirectories(FullPath);
      TArray.Sort<string>(Dirs, TStringComparer.Ordinal);
      for D in Dirs do
        if IsMilestoneDir(ExtractFileName(D)) then
          Groups.Add(CollectGroup(D, ExtractFileName(D)));
      if Groups.Count = 0 then
        // The path is itself a milestone folder (or any folder of tests).
        Groups.Add(CollectGroup(FullPath, ExtractFileName(FullPath)));
    end
    else
      raise EInOutError.CreateFmt('test path not found: %s', [Path]);
    Result := Groups.ToArray;
  finally
    Groups.Free;
  end;
end;

{ ---- Running tests ---- }

function RunCase(const C: TTestCase; out Detail: string): Boolean;
var
  StdLib: string;
  Args: TArray<string>;
  StdOut, StdErr, Expected, Actual, Kind: string;
  Code: Integer;
  TimedOut: Boolean;
begin
  Detail := '';
  case C.Kind of
    tkTokens: Args := ['--tokens', ExtractFileName(C.Source)];
    tkAst:    Args := ['--ast', ExtractFileName(C.Source)];
    tkTranscript: Args := ['--transcript', ExtractFileName(C.Source)];
  else
    Args := [ExtractFileName(C.Source)];
  end;

  // A milestone folder with a stdlib subfolder stands in for the standard
  // library, so the module search order can be tested.
  StdLib := TPath.Combine(ExtractFileDir(C.Source), 'stdlib');
  if TDirectory.Exists(StdLib) then
    SetEnv('AXON_STDLIB', StdLib)
  else
    SetEnv('AXON_STDLIB', '');
  // graphics.show writes here instead of opening a viewer.
  SetEnv('AXON_SHOW_DIR', TPath.Combine(TPath.GetTempPath, 'axon-test-figures'));
  Code := RunProcess(ParamStr(0), Args, ExtractFileDir(C.Source), TestTimeoutMs,
    StdOut, StdErr, TimedOut);
  if TimedOut then
  begin
    Detail := Format('timed out after %d ms', [TestTimeoutMs]);
    Exit(False);
  end;

  if C.Kind = tkError then
  begin
    if Code <> ExitUncaughtError then
    begin
      Detail := Format('expected an uncaught %s, but the program exited with code %d',
        [C.ExpectedKind, Code]);
      if StdErr <> '' then
        Detail := Detail + sLineBreak + IndentLines(StdErr, '  stderr: ');
      Exit(False);
    end;
    Kind := ReportedKind(StdErr);
    if Kind <> C.ExpectedKind then
    begin
      Detail := Format('expected error %s, got %s', [C.ExpectedKind, Kind]) +
        sLineBreak + IndentLines(StdErr, '  stderr: ');
      Exit(False);
    end;
  end
  else if Code <> ExitOk then
  begin
    Detail := Format('exited with code %d', [Code]);
    if StdErr <> '' then
      Detail := Detail + sLineBreak + IndentLines(StdErr, '  stderr: ');
    Exit(False);
  end;

  if C.ExpectedErrFile <> '' then
  begin
    Expected := Normalize(LoadUtf8File(C.ExpectedErrFile));
    Actual := Normalize(StdErr);
    if Expected <> Actual then
    begin
      Detail := 'stderr ' + DescribeDiff(Expected, Actual);
      Exit(False);
    end;
  end;

  if C.ExpectedFile <> '' then
  begin
    if C.Kind = tkTranscript then
    begin
      Expected := NormalizeTranscript(LoadUtf8File(C.ExpectedFile));
      Actual := NormalizeTranscript(StdOut);
    end
    else
    begin
      Expected := Normalize(LoadUtf8File(C.ExpectedFile));
      Actual := Normalize(StdOut);
    end;
    if Expected <> Actual then
    begin
      Detail := DescribeDiff(Expected, Actual);
      Exit(False);
    end;
  end;
  Result := True;
end;

procedure PrintUsage;
begin
  Writeln('usage: axon test [-v] [path]');
  Writeln('  path     tests root (default "tests"), a milestone folder, or one .sci or .repl file');
  Writeln('  -v       list passing tests as well as failures');
end;

function RunTestCommand(const Args: TArray<string>): Integer;
var
  Verbose: Boolean;
  Path, A, Detail, Name: string;
  Groups: TArray<TGroup>;
  G: TGroup;
  C: TTestCase;
  Passed, Failed, TotalPassed, TotalFailed, TotalFixtures: Integer;
  Failures: TStringList;
begin
  Verbose := False;
  Path := 'tests';
  for A in Args do
    if (A = '-v') or (A = '--verbose') then
      Verbose := True
    else if (A = '-h') or (A = '--help') then
    begin
      PrintUsage;
      Exit(ExitOk);
    end
    else if StartsStr('-', A) then
    begin
      Writeln(ErrOutput, 'axon test: unknown option ', A);
      PrintUsage;
      Exit(ExitUsage);
    end
    else
      Path := A;

  try
    Groups := CollectGroups(Path);
  except
    on E: EInOutError do
    begin
      Writeln(ErrOutput, 'axon test: ', E.Message);
      Exit(ExitUsage);
    end;
  end;

  TotalPassed := 0;
  TotalFailed := 0;
  TotalFixtures := 0;
  Failures := TStringList.Create;
  try
    for G in Groups do
    begin
      Passed := 0;
      Failed := 0;
      Failures.Clear;
      for C in G.Cases do
      begin
        Name := Format('%s [%s]', [ExtractFileName(C.Source), KindNames[C.Kind]]);
        if RunCase(C, Detail) then
        begin
          Inc(Passed);
          if Verbose then
            Failures.Add('  ok    ' + Name);
        end
        else
        begin
          Inc(Failed);
          Failures.Add('  FAIL  ' + Name);
          Failures.Add(IndentLines(Detail, '        '));
        end;
      end;

      if Failed = 0 then
        Writeln(Format('%-6s %d passed', [G.Name, Passed]))
      else
        Writeln(Format('%-6s %d passed, %d failed', [G.Name, Passed, Failed]));
      if Failures.Count > 0 then
        Write(Failures.Text);

      Inc(TotalPassed, Passed);
      Inc(TotalFailed, Failed);
      Inc(TotalFixtures, G.Fixtures);
    end;
  finally
    Failures.Free;
  end;

  Writeln;
  Write(Format('Total: %d passed, %d failed', [TotalPassed, TotalFailed]));
  if TotalFixtures > 0 then
    Write(Format(' (%d fixture files without expectations)', [TotalFixtures]));
  Writeln;

  if TotalFailed > 0 then
    Result := ExitUncaughtError
  else
    Result := ExitOk;
end;

end.
