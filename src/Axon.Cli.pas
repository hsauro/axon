unit Axon.Cli;

{ Command-line front end.

    axon                    REPL (from M3)
    axon file.sci           run a program
    axon --tokens file.sci  print the token stream (M1)
    axon --ast file.sci     print the syntax tree (M2)
    axon test [-v] [path]   run the conformance tests
    axon --version | --help

  Exit codes are defined in Axon.Errors. }

interface

function RunCli: Integer;

implementation

uses
  System.SysUtils, System.IOUtils,
  Axon.Version, Axon.Errors, Axon.Platform, Axon.Source, Axon.TestRunner,
  Axon.Tokens, Axon.Lexer;

procedure PrintUsage;
begin
  Writeln('Axon ', AxonVersion);
  Writeln('usage:');
  Writeln('  axon                    start the REPL');
  Writeln('  axon file.sci           run a program (.sci or .txt)');
  Writeln('  axon --tokens file.sci  print the token stream');
  Writeln('  axon --ast file.sci     print the syntax tree');
  Writeln('  axon test [-v] [path]   run the conformance tests (default path: tests)');
  Writeln('  axon --version          print the version');
end;

function NotYet(const Feature, Milestone: string): Integer;
begin
  Writeln(ErrOutput, Format('axon: %s is not implemented yet (arrives in %s)',
    [Feature, Milestone]));
  Result := ExitUsage;
end;

{ Checks the file exists and has a source extension, and loads it.
  Returns False (after printing a message) if it cannot be used. }
function LoadProgram(const FileName: string; out Source: string): Boolean;
begin
  Result := False;
  if not IsSourceFileName(FileName) then
    Writeln(ErrOutput, Format('axon: %s: source files must end in .sci or .txt', [FileName]))
  else if not TFile.Exists(FileName) then
    Writeln(ErrOutput, Format('axon: %s: file not found', [FileName]))
  else
  begin
    Source := LoadSourceFile(FileName);
    Result := True;
  end;
end;

{ True if the tokens hold no statements: only newlines, docstrings and EOF. }
function OnlyLayout(const Tokens: TArray<TToken>): Boolean;
var
  T: TToken;
begin
  for T in Tokens do
    if not (T.Kind in [tkNewline, tkDocString, tkEOF, tkSemicolon]) then
      Exit(False);
  Result := True;
end;

function RunFile(const FileName: string): Integer;
var
  Source: string;
  Tokens: TArray<TToken>;
begin
  if not LoadProgram(FileName, Source) then
    Exit(ExitUsage);
  // Lexing first means syntax errors are reported even before evaluation exists.
  Tokens := Tokenize(Source, FileName);
  // A program with no statements does nothing, at every milestone.
  if OnlyLayout(Tokens) then
    Exit(ExitOk);
  Result := NotYet('running programs', 'M3');
end;

function FrontEndDump(const Option, FileName: string): Integer;
var
  Source: string;
  T: TToken;
begin
  if FileName = '' then
  begin
    Writeln(ErrOutput, Format('axon: %s needs a source file', [Option]));
    Exit(ExitUsage);
  end;
  if not LoadProgram(FileName, Source) then
    Exit(ExitUsage);
  if Option = '--tokens' then
  begin
    for T in Tokenize(Source, FileName) do
      Writeln(DumpToken(T));
    Result := ExitOk;
  end
  else
    Result := NotYet('--ast', 'M2');
end;

function Dispatch(const Args: TArray<string>): Integer;
var
  Cmd, Arg1: string;
begin
  if Length(Args) = 0 then
    Exit(NotYet('the REPL', 'M3'));

  Cmd := Args[0];
  if Length(Args) > 1 then Arg1 := Args[1] else Arg1 := '';

  if (Cmd = '-h') or (Cmd = '--help') then
  begin
    PrintUsage;
    Result := ExitOk;
  end
  else if Cmd = '--version' then
  begin
    Writeln('Axon ', AxonVersion, ' (', AxonMilestone, ')');
    Result := ExitOk;
  end
  else if Cmd = 'test' then
    Result := RunTestCommand(Copy(Args, 1, MaxInt))
  else if (Cmd = '--tokens') or (Cmd = '--ast') then
    Result := FrontEndDump(Cmd, Arg1)
  else if Cmd.StartsWith('-') then
  begin
    Writeln(ErrOutput, 'axon: unknown option ', Cmd);
    PrintUsage;
    Result := ExitUsage;
  end
  else
    Result := RunFile(Cmd);
end;

function RunCli: Integer;
var
  Args: TArray<string>;
  I: Integer;
begin
  InitConsole;
  SetLength(Args, ParamCount);
  for I := 1 to ParamCount do
    Args[I - 1] := ParamStr(I);
  try
    Result := Dispatch(Args);
  except
    on E: EAxonError do
    begin
      Writeln(ErrOutput, E.Report);
      Result := ExitUncaughtError;
    end;
    on E: EInOutError do
    begin
      Writeln(ErrOutput, 'axon: ', E.Message);
      Result := ExitUsage;
    end;
    on E: Exception do
    begin
      Writeln(ErrOutput, 'axon: internal error: ', E.ClassName, ': ', E.Message);
      Result := ExitInternal;
    end;
  end;
end;

end.
