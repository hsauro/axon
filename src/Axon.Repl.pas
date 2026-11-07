unit Axon.Repl;

(* The REPL (reference, "The REPL").

   Reads a line at the prompt "> " and keeps reading lines at "... " while the
   input ends inside an open block or bracket (the parser reports "found end
   of file"), then runs each statement. An expression's value is displayed
   (nothing is not), an assignment to names displays "name = value" per name,
   and a trailing ";" suppresses both. After an uncaught error the report is
   printed and the session continues with its variables intact. "help name"
   is a command, handled before parsing (Axon.Help).

   A transcript run (axon --transcript file) takes its input from the lines
   of a file that start with "> " or "... ", echoes each one after its prompt
   and writes everything, error reports included, to standard output, so a
   correct transcript file reproduces itself. *)

interface

{ The interactive REPL on standard input. }
function RunRepl: Integer;

{ Replays the input lines of a transcript file. }
function RunTranscript(const FileName: string): Integer;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  Axon.Version, Axon.Errors, Axon.Values, Axon.Ast, Axon.Parser, Axon.Source,
  Axon.Interp, Axon.Help;

const
  ReplName = '<repl>';
  Prompt = '> ';
  MorePrompt = '... ';

type
  TRepl = class
  private
    FInterp: TInterpreter;
    FPrograms: TObjectList<TProgram>;   // kept alive: functions refer to their nodes
    FTranscript: Boolean;
    FInput: TArray<string>;             // transcript input lines
    FNext: Integer;
    FFirstLine: Boolean;
    function ReadInput(const APrompt: string; out Line: string): Boolean;
    procedure Show(const S: string);
    procedure ShowError(const S: string);
    procedure Report(E: Exception);
    function TryHelp(const Line: string): Boolean;
    procedure RunStatements(Prog: TProgram);
    procedure RunEntry(const First: string);
  public
    constructor Create(ATranscript: Boolean; const AInput: TArray<string>);
    destructor Destroy; override;
    procedure Run;
  end;

{ True if the error means the input stopped in the middle of a construct. }
function NeedsMoreInput(E: EAxonError): Boolean;
begin
  Result := (E.Kind = SyntaxError) and E.Message.EndsWith('found end of file');
end;

constructor TRepl.Create(ATranscript: Boolean; const AInput: TArray<string>);
begin
  inherited Create;
  FTranscript := ATranscript;
  FInput := AInput;
  FFirstLine := True;
  FInterp := TInterpreter.Create(ReplName);
  FPrograms := TObjectList<TProgram>.Create;
end;

destructor TRepl.Destroy;
begin
  FPrograms.Free;
  FInterp.Free;
  inherited;
end;

function TRepl.ReadInput(const APrompt: string; out Line: string): Boolean;
begin
  if FTranscript then
  begin
    if FNext >= Length(FInput) then
      Exit(False);
    Line := FInput[FNext];
    Inc(FNext);
    Writeln((APrompt + Line).TrimRight);
    Exit(True);
  end;
  Write(APrompt);
  if Eof(Input) then
    Exit(False);
  Readln(Line);
  // Piped input may start with a byte-order mark (PowerShell adds one).
  if FFirstLine and Line.StartsWith(#$FEFF) then
    Delete(Line, 1, 1);
  FFirstLine := False;
  Result := True;
end;

procedure TRepl.Show(const S: string);
var
  L: string;
begin
  // (Split gives no elements for an empty string, so that case is direct.)
  if not FTranscript or (S = '') then
  begin
    Writeln(S);
    Exit;
  end;
  for L in S.Replace(#13#10, #10).Split([#10]) do
    Writeln(L.TrimRight);
end;

procedure TRepl.ShowError(const S: string);
begin
  if FTranscript then
    Show(S)
  else
    Writeln(ErrOutput, S);
end;

procedure TRepl.Report(E: Exception);
begin
  if E is EAxonError then
    ShowError(EAxonError(E).Report)
  else if E is ENotImplemented then
    ShowError('axon: ' + E.Message)
  else
    ShowError(Format('axon: internal error: %s: %s', [E.ClassName, E.Message]));
end;

{ "help" or "help name" (name possibly dotted). Returns False for any other
  line, which is then run as Axon code. }
function TRepl.TryHelp(const Line: string): Boolean;
var
  S, Name, Part: string;
  Prog: TProgram;
  Shown: TAxValues;
  Names: TArray<string>;
  L: string;
  C: Char;
begin
  S := Line.Trim;
  if S = 'help' then
  begin
    for L in HelpUsage do
      Show(L);
    Exit(True);
  end;
  if not S.StartsWith('help ') then
    Exit(False);
  Name := Copy(S, 6, MaxInt).Trim;
  for Part in Name.Split(['.']) do
  begin
    if (Part = '') or CharInSet(Part[1], ['0'..'9']) then
      Exit(False);
    for C in Part do
      if not (CharInSet(C, ['a'..'z', 'A'..'Z', '0'..'9', '_'])) then
        Exit(False);
  end;

  // The name is evaluated as an expression, so an undefined name or an
  // unexported module member raises the usual error.
  try
    Prog := ParseSource(Name, ReplName);
    FPrograms.Add(Prog);
    if (Prog.Body.Count = 1) and (Prog.Body[0] is TExprStmt) then
    begin
      FInterp.ExecTopLevel(Prog.Body[0], Shown, Names);
      if Length(Shown) = 1 then
        for L in HelpText(Name, Shown[0]) do
          Show(L);
    end;
  except
    on E: Exception do
      Report(E);
  end;
  Result := True;
end;

procedure TRepl.RunStatements(Prog: TProgram);
var
  S: TStmt;
  Shown: TAxValues;
  Names: TArray<string>;
  K: Integer;
begin
  FInterp.Hoist(Prog);
  for S in Prog.Body do
    try
      if FInterp.ExecTopLevel(S, Shown, Names) and not S.Silent then
        if Names <> nil then
          for K := 0 to High(Names) do
            Show(Names[K] + ' = ' + Display(Shown[K], True))
        else
          for K := 0 to High(Shown) do
            Show(Display(Shown[K], True));
    except
      on E: Exception do
      begin
        // The rest of this input is skipped; earlier statements keep their effects.
        Report(E);
        Break;
      end;
    end;
end;

procedure TRepl.RunEntry(const First: string);
var
  Buffer, Line: string;
  Prog: TProgram;
begin
  if TryHelp(First) then
    Exit;
  Buffer := First;
  // Parse, reading continuation lines while the input is incomplete.
  Prog := nil;
  while True do
    try
      Prog := ParseSource(Buffer, ReplName);
      Break;
    except
      on E: EAxonError do
        if NeedsMoreInput(E) and ReadInput(MorePrompt, Line) then
          Buffer := Buffer + #10 + Line
        else
        begin
          Report(E);
          Break;
        end;
      on E: Exception do
      begin
        Report(E);
        Break;
      end;
    end;
  if Prog = nil then
    Exit;
  FPrograms.Add(Prog);
  RunStatements(Prog);
end;

procedure TRepl.Run;
var
  Line: string;
begin
  if not FTranscript then
    Writeln('Axon ', AxonVersion, '. Type "help" for help; end the session with Ctrl+D (Ctrl+Z, Enter on Windows).');
  while ReadInput(Prompt, Line) do
    RunEntry(Line);
  if not FTranscript then
    Writeln;
end;

function RunRepl: Integer;
var
  R: TRepl;
begin
  R := TRepl.Create(False, nil);
  try
    R.Run;
  finally
    R.Free;
  end;
  Result := ExitOk;
end;

function RunTranscript(const FileName: string): Integer;
var
  Lines, Input: TArray<string>;
  L: string;
  R: TRepl;
begin
  Lines := LoadSourceFile(FileName).Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
  Input := nil;
  for L in Lines do
    if L.StartsWith(Prompt) then
      Input := Input + [Copy(L, Length(Prompt) + 1, MaxInt)]
    else if L.StartsWith(MorePrompt) then
      Input := Input + [Copy(L, Length(MorePrompt) + 1, MaxInt)]
    else if (L = Prompt.TrimRight) or (L = MorePrompt.TrimRight) then
      Input := Input + [''];
  R := TRepl.Create(True, Input);
  try
    R.Run;
  finally
    R.Free;
  end;
  Result := ExitOk;
end;

end.
