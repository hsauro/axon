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
  System.Math,
  Axon.Tokens, Axon.Lexer, Axon.Ast, Axon.Parser, Axon.AstDump, Axon.Interp,
  Axon.Repl;

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

function RunFile(const FileName: string): Integer;
var
  Source: string;
  Prog: TProgram;
  Interp: TInterpreter;
begin
  if not LoadProgram(FileName, Source) then
    Exit(ExitUsage);
  // The whole file is parsed before anything runs, so a syntax error anywhere
  // stops the program before it has any effect.
  Prog := ParseProgram(Tokenize(Source, FileName), FileName);
  try
    Interp := TInterpreter.Create(FileName);
    try
      Interp.Run(Prog);
    finally
      Interp.Free;
    end;
  finally
    Prog.Free;
  end;
  Result := ExitOk;
end;

function FrontEndDump(const Option, FileName: string): Integer;
var
  Source: string;
  T: TToken;
  Prog: TProgram;
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
  begin
    Prog := ParseProgram(Tokenize(Source, FileName), FileName);
    try
      Write(DumpProgram(Prog));
    finally
      Prog.Free;
    end;
    Result := ExitOk;
  end;
end;

function Dispatch(const Args: TArray<string>): Integer;
var
  Cmd, Arg1: string;
begin
  if Length(Args) = 0 then
    Exit(RunRepl);

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
  // IEEE 754 semantics: 1.0/0.0 is Inf and 0.0/0.0 is NaN, never an exception.
  SetExceptionMask(exAllArithmeticExceptions);
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
    on E: ENotImplemented do
    begin
      if E.Line > 0 then
        Writeln(ErrOutput, Format('axon: %s:%d:%d: %s', [E.FileName, E.Line, E.Col, E.Message]))
      else
        Writeln(ErrOutput, 'axon: ', E.Message);
      Result := ExitUsage;
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
