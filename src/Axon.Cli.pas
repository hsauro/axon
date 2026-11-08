unit Axon.Cli;

{ Command-line front end.

    axon                    REPL (from M3)
    axon file.sci           run a program
    axon --tokens file.sci  print the token stream (M1)
    axon --ast file.sci     print the syntax tree (M2)
    axon --jir file.sci     print the JIT's typed IR of each top-level function (L2)
    axon test [-v] [path]   run the conformance tests
    axon --jit-selftest     check that the MIR JIT works here (L2, J0)
    axon --jit=MODE ...     run with the JIT off, on or force (also AXON_JIT)
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
  Axon.Repl, Axon.JitSelfTest, Axon.Jit, Axon.Jit.Ir, Axon.Jit.Lower, System.Classes,
  System.Generics.Collections, Axon.Values, Axon.Builtins;

procedure PrintUsage;
begin
  Writeln('Axon ', AxonVersion);
  Writeln('usage:');
  Writeln('  axon                    start the REPL');
  Writeln('  axon file.sci           run a program (.sci or .txt)');
  Writeln('  axon --tokens file.sci  print the token stream');
  Writeln('  axon --ast file.sci     print the syntax tree');
  Writeln('  axon --jir file.sci     print the JIT''s typed IR, or why a function is not compiled');
  Writeln('  axon --transcript file  replay the input lines of a REPL transcript');
  Writeln('  axon --repl-protocol    the REPL for front ends such as the IDE');
  Writeln('  axon --check file|-     check the syntax without running (- reads stdin)');
  Writeln('  axon test [-v] [path]   run the conformance tests (default path: tests)');
  Writeln('  axon --jit-selftest     check that the MIR JIT library works');
  Writeln('  axon --jit=MODE ...     run with the JIT off (default), on or force; also AXON_JIT');
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
  Prog := ParseSource(Source, FileName);
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

{ axon --check file (or - for standard input): parses without running.
  Prints nothing and exits 0 when the syntax is valid; otherwise the error
  propagates to RunCli, which prints the report and exits 1. }
function CheckSyntax(const FileName: string): Integer;
var
  Source, Line, Name: string;
  SB: TStringBuilder;
  Prog: TProgram;
begin
  if FileName = '-' then
  begin
    Name := '<stdin>';
    SB := TStringBuilder.Create;
    try
      while not Eof(Input) do
      begin
        Readln(Line);
        SB.Append(Line).Append(#10);
      end;
      Source := SB.ToString;
    finally
      SB.Free;
    end;
    if Source.StartsWith(#$FEFF) then
      Delete(Source, 1, 1);
  end
  else
  begin
    Name := FileName;
    if not LoadProgram(FileName, Source) then
      Exit(ExitUsage);
  end;
  Prog := ParseSource(Source, Name);
  Prog.Free;
  Result := ExitOk;
end;

{ --jir: each named function at the top level of the program, lowered to
  JIR, or the reason it is not compiled. Blank lines separate functions.
  Called names resolve statically: to the program's top-level functions,
  then to the prelude. }
function DumpJir(Prog: TProgram): string;
var
  S: TStmt;
  E: TJEntry;
  Lines: TStringList;
  Funcs: TDictionary<string, TFunctionDecl>;
  Prelude: TDictionary<string, TAxValue>;
  Session: TJSession;
begin
  Lines := TStringList.Create;
  Funcs := TDictionary<string, TFunctionDecl>.Create;
  Prelude := TDictionary<string, TAxValue>.Create;
  try
    for S in Prog.Body do
      if S is TFunctionStmt then
        Funcs.AddOrSetValue(TFunctionStmt(S).Func.Name, TFunctionStmt(S).Func);
    DefineBuiltins(
      procedure(Name: string; V: TAxValue)
      begin
        Prelude.AddOrSetValue(Name, V);
      end);
    Session := TJSession.Create(
      function(Context: TObject; const Name: string): TJResolved
      var
        D: TFunctionDecl;
        V: TAxValue;
      begin
        Result := Default(TJResolved);
        if Funcs.TryGetValue(Name, D) then
        begin
          Result.Kind := rkFunction;
          Result.Decl := D;
          Result.FileName := Prog.FileName;
        end
        else if Prelude.TryGetValue(Name, V) then
        begin
          Result.Kind := rkBuiltin;
          Result.Name := Name;
          Result.Value := V;
        end;
      end);
    try
      for S in Prog.Body do
        if S is TFunctionStmt then
        begin
          if Lines.Count > 0 then
            Lines.Add('');
          E := Session.Lower(TFunctionStmt(S).Func, nil, Prog.FileName);
          if E.State = esLowered then
            E.Func.Dump(Lines)
          else
            Lines.Add(Format('function %s: not compiled: %s (%d:%d)',
              [TFunctionStmt(S).Func.Name, E.Reason, E.RejectLine, E.RejectCol]));
        end;
    finally
      Session.Free;
    end;
    Result := Lines.Text;
  finally
    Prelude.Free;
    Funcs.Free;
    Lines.Free;
  end;
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
  else if Option = '--jir' then
  begin
    Prog := ParseProgram(Tokenize(Source, FileName), FileName);
    try
      Write(DumpJir(Prog));
    finally
      Prog.Free;
    end;
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
  else if (Cmd = '--tokens') or (Cmd = '--ast') or (Cmd = '--jir') then
    Result := FrontEndDump(Cmd, Arg1)
  else if Cmd = '--jit-selftest' then
    Result := RunJitSelfTest
  else if Cmd = '--repl-protocol' then
    Result := RunReplProtocol
  else if Cmd = '--check' then
  begin
    if Arg1 = '' then
    begin
      Writeln(ErrOutput, 'axon: --check needs a source file, or - for standard input');
      Exit(ExitUsage);
    end;
    Result := CheckSyntax(Arg1);
  end
  else if Cmd = '--transcript' then
  begin
    if Arg1 = '' then
    begin
      Writeln(ErrOutput, 'axon: --transcript needs a transcript file');
      Exit(ExitUsage);
    end;
    if not FileExists(Arg1) then
    begin
      Writeln(ErrOutput, 'axon: cannot read ', Arg1);
      Exit(ExitUsage);
    end;
    Result := RunTranscript(Arg1);
  end
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
  // The JIT mode: AXON_JIT, then a leading --jit=MODE.
  if (GetEnvironmentVariable('AXON_JIT') <> '') and
     not SetJitMode(GetEnvironmentVariable('AXON_JIT')) then
  begin
    Writeln(ErrOutput, 'axon: AXON_JIT must be off, on or force');
    Exit(ExitUsage);
  end;
  if (Length(Args) > 0) and Args[0].StartsWith('--jit=') then
  begin
    if not SetJitMode(Args[0].Substring(6)) then
    begin
      Writeln(ErrOutput, 'axon: --jit must be off, on or force');
      Exit(ExitUsage);
    end;
    Args := Copy(Args, 1, MaxInt);
  end;
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
