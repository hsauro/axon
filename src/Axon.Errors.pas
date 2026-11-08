unit Axon.Errors;

(* Axon run-time errors.

   Every error the language can raise is an EAxonError carrying a kind from the
   reference's error table and a trace of frames, innermost first.

   How the trace is built as an error propagates:
   - Locate(pos) records where the error happened in the current frame. Only
     the first (innermost) position in a frame counts.
   - LeaveFunction(name) is called as the error leaves a function body: it
     names the current frame and closes it, so the next Locate (the call site
     in the caller) starts a new frame.
   An error re-raised with error(err) is frozen: its trace is the original one
   and no longer changes.

   Uncaught report (reference, "Errors"):

     Kind: message
       at file:line:col in function
       at file:line:col                (a frame at the top level)            *)

interface

uses
  System.SysUtils;

const
  // Error kinds from the Language Reference, section "Errors".
  ArgumentError  = 'ArgumentError';
  DimensionError = 'DimensionError';
  DomainError    = 'DomainError';
  FieldError     = 'FieldError';
  ForeignError   = 'ForeignError';
  ImportError    = 'ImportError';
  IndexError     = 'IndexError';
  IOError        = 'IOError';
  KeyError       = 'KeyError';
  NameError      = 'NameError';
  OverflowError  = 'OverflowError';
  RecursionError = 'RecursionError';
  SingularMatrix = 'SingularMatrix';
  SolverError    = 'SolverError';
  SyntaxError    = 'SyntaxError';
  TypeError      = 'TypeError';
  UserError      = 'UserError';

  // Process exit codes.
  ExitOk            = 0;
  ExitUncaughtError = 1;   // the program stopped with an uncaught Axon error
  ExitUsage         = 2;   // bad command line, missing file, unimplemented feature
  ExitInternal      = 3;   // a bug in the interpreter (a non-Axon exception)

type
  TTraceEntry = record
    FileName: string;
    Line: Integer;
    Col: Integer;
    FunctionName: string;   // '' at the top level
  end;

  EAxonError = class(Exception)
  private
    FKind: string;
    FTrace: TArray<TTraceEntry>;   // capacity grows by doubling; FCount in use
    FCount: Integer;
    FFrameClosed: Boolean;
    FFrozen: Boolean;
    function GetFileName: string;
    function GetLine: Integer;
    function GetCol: Integer;
  public
    constructor Create(const AKind, AMessage: string);
    constructor CreateAt(const AKind, AMessage, AFileName: string;
      ALine, ACol: Integer);
    { An error with a given trace that no longer changes (error(err)). }
    constructor CreateFrozen(const AKind, AMessage: string;
      const ATrace: TArray<TTraceEntry>);
    { Records where the error happened in the current frame. }
    procedure Locate(const AFileName: string; ALine, ACol: Integer);
    { Names and closes the current frame as the error leaves a function. }
    procedure LeaveFunction(const AFunctionName: string);
    function HasLocation: Boolean;
    function Report: string;
    property Kind: string read FKind;
    function Trace: TArray<TTraceEntry>;
    // Innermost location.
    property FileName: string read GetFileName;
    property Line: Integer read GetLine;
    property Col: Integer read GetCol;
  end;

implementation

constructor EAxonError.Create(const AKind, AMessage: string);
begin
  inherited Create(AMessage);
  FKind := AKind;
end;

constructor EAxonError.CreateAt(const AKind, AMessage, AFileName: string;
  ALine, ACol: Integer);
begin
  Create(AKind, AMessage);
  Locate(AFileName, ALine, ACol);
end;

constructor EAxonError.CreateFrozen(const AKind, AMessage: string;
  const ATrace: TArray<TTraceEntry>);
begin
  Create(AKind, AMessage);
  FTrace := Copy(ATrace);
  FCount := Length(ATrace);
  FFrozen := True;
end;

procedure EAxonError.Locate(const AFileName: string; ALine, ACol: Integer);
var
  E: TTraceEntry;
begin
  if FFrozen then
    Exit;
  if (FCount > 0) and not FFrameClosed then
    Exit;  // this frame already has its (innermost) position
  E.FileName := AFileName;
  E.Line := ALine;
  E.Col := ACol;
  E.FunctionName := '';
  if FCount = Length(FTrace) then
    SetLength(FTrace, 2 * FCount + 4);
  FTrace[FCount] := E;
  Inc(FCount);
  FFrameClosed := False;
end;

procedure EAxonError.LeaveFunction(const AFunctionName: string);
begin
  if FFrozen or (FCount = 0) or FFrameClosed then
    Exit;
  FTrace[FCount - 1].FunctionName := AFunctionName;
  FFrameClosed := True;
end;

function EAxonError.HasLocation: Boolean;
begin
  Result := FCount > 0;
end;

function EAxonError.GetFileName: string;
begin
  if FCount > 0 then Result := FTrace[0].FileName else Result := '';
end;

function EAxonError.GetLine: Integer;
begin
  if FCount > 0 then Result := FTrace[0].Line else Result := 0;
end;

function EAxonError.GetCol: Integer;
begin
  if FCount > 0 then Result := FTrace[0].Col else Result := 0;
end;

function EAxonError.Trace: TArray<TTraceEntry>;
begin
  Result := Copy(FTrace, 0, FCount);
end;

function EAxonError.Report: string;
const
  Shown = 10;   // frames shown at each end of a long trace
var
  SB: TStringBuilder;
  I: Integer;

  procedure AddFrame(const E: TTraceEntry);
  begin
    SB.Append(sLineBreak).AppendFormat('  at %s:%d:%d', [E.FileName, E.Line, E.Col]);
    if E.FunctionName <> '' then
      SB.Append(' in ').Append(E.FunctionName);
  end;

begin
  SB := TStringBuilder.Create;
  try
    SB.Append(FKind).Append(': ').Append(Message);
    if FCount <= 2 * Shown + 1 then
      for I := 0 to FCount - 1 do
        AddFrame(FTrace[I])
    else
    begin
      for I := 0 to Shown - 1 do
        AddFrame(FTrace[I]);
      SB.Append(sLineBreak).AppendFormat('  ... %d more frames ...', [FCount - 2 * Shown]);
      for I := FCount - Shown to FCount - 1 do
        AddFrame(FTrace[I]);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

end.
