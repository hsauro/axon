unit Axon.Repl;

(* Basic REPL (M3). M12 brings it to the white paper's standard.

   Reads a line, keeps reading while the input ends inside an open block or
   bracket (the parser reports "found end of file"), then runs each statement.
   An expression's value is displayed, and an assignment to a name displays
   "name = value"; a trailing ";" suppresses both. After an uncaught error the
   report is printed and the session continues with its variables intact. *)

interface

function RunRepl: Integer;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  Axon.Version, Axon.Errors, Axon.Values, Axon.Ast, Axon.Lexer, Axon.Parser,
  Axon.Interp;

const
  ReplName = '<repl>';

{ True if the error means the input stopped in the middle of a construct. }
function NeedsMoreInput(E: EAxonError): Boolean;
begin
  Result := (E.Kind = SyntaxError) and E.Message.EndsWith('found end of file');
end;

function RunRepl: Integer;
var
  Interp: TInterpreter;
  Programs: TObjectList<TProgram>;   // kept alive: later milestones refer back to them
  Prog: TProgram;
  Line, Buffer, Name: string;
  S: TStmt;
  Shown: TAxValue;
  FirstLine: Boolean;
begin
  FirstLine := True;
  Writeln('Axon ', AxonVersion, '. End input with Ctrl+Z (Windows) or Ctrl+D.');
  Interp := TInterpreter.Create(ReplName);
  Programs := TObjectList<TProgram>.Create;
  try
    while True do
    begin
      Write('> ');
      if Eof(Input) then
        Break;
      Readln(Line);
      // Piped input may start with a byte-order mark (PowerShell adds one).
      if FirstLine and Line.StartsWith(#$FEFF) then
        Delete(Line, 1, 1);
      FirstLine := False;
      Buffer := Line;

      // Parse, reading continuation lines while the input is incomplete.
      Prog := nil;
      while True do
        try
          Prog := ParseProgram(Tokenize(Buffer, ReplName), ReplName);
          Break;
        except
          on E: EAxonError do
          begin
            if NeedsMoreInput(E) and not Eof(Input) then
            begin
              Write('  ');
              Readln(Line);
              Buffer := Buffer + #10 + Line;
            end
            else
            begin
              Writeln(ErrOutput, E.Report);
              Break;
            end;
          end;
        end;
      if Prog = nil then
        Continue;
      Programs.Add(Prog);

      for S in Prog.Body do
        try
          if Interp.ExecTopLevel(S, Shown, Name) and not S.Silent then
            if Name <> '' then
              Writeln(Name, ' = ', Display(Shown, True))
            else
              Writeln(Display(Shown, True));
        except
          on E: EAxonError do
          begin
            Writeln(ErrOutput, E.Report);
            Break;
          end;
          on E: ENotImplemented do
          begin
            Writeln(ErrOutput, 'axon: ', E.Message);
            Break;
          end;
        end;
    end;
    Writeln;
  finally
    Programs.Free;
    Interp.Free;
  end;
  Result := ExitOk;
end;

end.
