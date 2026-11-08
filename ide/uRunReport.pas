unit uRunReport;

(* Reading axon's error reports (reference, "Errors"):

     Kind: message
       at file:line:col in function
       at file:line:col

   The first line names the error; each further line is a trace frame,
   innermost first. File names may contain colons (a Windows drive), so a
   frame is matched from the right. *)

interface

type
  TFrame = record
    FileName: string;   // as printed: relative to the run's directory, or absolute
    Line, Col: Integer;
    FunctionName: string;
  end;

{ True for "Kind: message", where Kind is a capitalised word such as
  TypeError or SingularMatrix. Meant for the first stderr line of a run. }
function ParseErrorHead(const S: string; out Kind, Message: string): Boolean;

{ True for a trace line "  at file:line:col[ in name]". }
function ParseFrame(const S: string; out Frame: TFrame): Boolean;

implementation

uses
  System.SysUtils;

function ParseErrorHead(const S: string; out Kind, Message: string): Boolean;
var
  P, K: Integer;
begin
  Result := False;
  P := Pos(': ', S);
  if (P < 2) or not CharInSet(S[1], ['A'..'Z']) then
    Exit;
  for K := 1 to P - 1 do
    if not CharInSet(S[K], ['A'..'Z', 'a'..'z']) then
      Exit;
  // Built-in kinds (TypeError, SingularMatrix) and user kinds raised with
  // error(kind, text) are all capitalised words.
  Kind := Copy(S, 1, P - 1);
  Message := Copy(S, P + 2, MaxInt);
  Result := True;
end;

function ParseFrame(const S: string; out Frame: TFrame): Boolean;
var
  T, Loc: string;
  P, C2, C1: Integer;
begin
  Result := False;
  T := S.Trim;
  if not T.StartsWith('at ') then
    Exit;
  T := Copy(T, 4, MaxInt);
  Frame.FunctionName := '';
  P := Pos(' in ', T);
  if P > 0 then
  begin
    Frame.FunctionName := Copy(T, P + 4, MaxInt);
    Loc := Copy(T, 1, P - 1);
  end
  else
    Loc := T;
  C2 := Loc.LastDelimiter(':');            // before the column (0-based)
  if C2 < 0 then Exit;
  C1 := Copy(Loc, 1, C2).LastDelimiter(':'); // before the line
  if C1 < 1 then Exit;
  if not TryStrToInt(Copy(Loc, C1 + 2, C2 - C1 - 1), Frame.Line) then Exit;
  if not TryStrToInt(Copy(Loc, C2 + 2, MaxInt), Frame.Col) then Exit;
  Frame.FileName := Copy(Loc, 1, C1);
  Result := Frame.FileName <> '';
end;

end.
