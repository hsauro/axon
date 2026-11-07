unit Axon.Errors;

{ Axon run-time errors.

  Every error the language can raise is an EAxonError carrying a kind from the
  reference's error table. An uncaught error is printed to stderr by Axon.Cli
  using Report, and the process exits with ExitUncaughtError.

  Report format (first line is what the test runner inspects):

    Kind: message
      at file:line:col

  The trace lines are completed in M5. }

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
  KeyError       = 'KeyError';
  NameError      = 'NameError';
  OverflowError  = 'OverflowError';
  SingularMatrix = 'SingularMatrix';
  SyntaxError    = 'SyntaxError';
  TypeError      = 'TypeError';
  UserError      = 'UserError';

  // Process exit codes.
  ExitOk            = 0;
  ExitUncaughtError = 1;   // the program stopped with an uncaught Axon error
  ExitUsage         = 2;   // bad command line, missing file, unimplemented feature
  ExitInternal      = 3;   // a bug in the interpreter (a non-Axon exception)

type
  EAxonError = class(Exception)
  private
    FKind: string;
    FFileName: string;
    FLine: Integer;
    FCol: Integer;
  public
    constructor Create(const AKind, AMessage: string);
    constructor CreateAt(const AKind, AMessage, AFileName: string;
      ALine, ACol: Integer);
    function Report: string;
    { Records where the error happened, unless a location is already set
      (the innermost location wins). }
    procedure Locate(const AFileName: string; ALine, ACol: Integer);
    function HasLocation: Boolean;
    property Kind: string read FKind;
    property FileName: string read FFileName;
    property Line: Integer read FLine;
    property Col: Integer read FCol;
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
  FFileName := AFileName;
  FLine := ALine;
  FCol := ACol;
end;

procedure EAxonError.Locate(const AFileName: string; ALine, ACol: Integer);
begin
  if HasLocation then
    Exit;
  FFileName := AFileName;
  FLine := ALine;
  FCol := ACol;
end;

function EAxonError.HasLocation: Boolean;
begin
  Result := FLine > 0;
end;

function EAxonError.Report: string;
begin
  Result := FKind + ': ' + Message;
  if FFileName <> '' then
    Result := Result + sLineBreak + Format('  at %s:%d:%d', [FFileName, FLine, FCol]);
end;

end.
