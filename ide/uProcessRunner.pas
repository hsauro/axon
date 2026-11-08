unit uProcessRunner;

(* Runs a program asynchronously and streams its output to the UI thread.

   stdout and stderr are read by one thread each, decoded as UTF-8 (a
   multi-byte character split across two reads is held back until it is
   complete) and delivered through OnOutput on the main thread. When the
   process has exited and both pipes are drained, OnExit reports its exit
   code. Kill stops the process; Free kills it if it is still running and
   discards events not yet delivered.

   With WithInput, the program's stdin is a pipe that WriteInput writes to
   (the REPL); otherwise stdin is empty.

   Windows uses CreateProcess with pipes; macOS and Linux use fork/exec. *)

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs;

type
  TOutputKind = (okStdOut, okStdErr);
  TOutputEvent = procedure(Kind: TOutputKind; const Text: string) of object;
  TExitEvent = procedure(ExitCode: Integer) of object;

  TProcessRunner = class
  private
    FThreads: TList;             // reader and waiter threads
    FRunning: Boolean;
    FKilled: Boolean;
    FOnOutput: TOutputEvent;
    FOnExit: TExitEvent;
{$IFDEF MSWINDOWS}
    FProcess: THandle;
    FInput: THandle;             // write end of stdin, or 0
{$ELSE}
    FPid: Integer;
    FInput: Integer;             // write end of stdin, or -1
{$ENDIF}
    procedure Deliver(Kind: TOutputKind; const Text: string);
    procedure Finished(Code: Integer);
    procedure WaitForThreads;
  public
    constructor Create;
    destructor Destroy; override;
    { Starts Exe with Args in WorkDir. Raises if the program cannot be started. }
    procedure Start(const Exe: string; const Args: array of string; const WorkDir: string;
      WithInput: Boolean = False);
    { Writes Text to the program's stdin as UTF-8. False if it is not running
      or was started without input. }
    function WriteInput(const Text: string): Boolean;
    { Closes the program's stdin, so it sees the end of its input. }
    procedure CloseInput;
    procedure Kill;
    property Running: Boolean read FRunning;
    property Killed: Boolean read FKilled;
    property OnOutput: TOutputEvent read FOnOutput write FOnOutput;
    property OnExit: TExitEvent read FOnExit write FOnExit;
  end;

implementation

uses
{$IFDEF MSWINDOWS}
  Winapi.Windows,
{$ELSE}
  Posix.Base, Posix.Unistd, Posix.Signal, Posix.SysWait, Posix.Fcntl, Posix.Errno,
{$ENDIF}
  System.Math;

type
  { Reads one pipe to the end, delivering decoded text. }
  TReaderThread = class(TThread)
  private
    FRunner: TProcessRunner;
    FKind: TOutputKind;
    FHandle: NativeInt;
    function ReadChunk(var Buf: TBytes): Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(Runner: TProcessRunner; Kind: TOutputKind; Handle: NativeInt);
  end;

  { Waits for the process to exit, then for the readers, then reports. }
  TWaiterThread = class(TThread)
  private
    FRunner: TProcessRunner;
    FReaders: array[0..1] of TThread;
  protected
    procedure Execute; override;
  public
    constructor Create(Runner: TProcessRunner; R1, R2: TThread);
  end;

{ The number of bytes at the end of Buf[0..Len-1] that start an incomplete
  UTF-8 sequence, to be kept for the next read. }
function IncompleteTail(const Buf: TBytes; Len: Integer): Integer;
var
  K, Need: Integer;
  B: Byte;
begin
  Result := 0;
  for K := 1 to Min(3, Len) do
  begin
    B := Buf[Len - K];
    if (B and $C0) = $80 then
      Continue;                 // a continuation byte: keep looking back
    if (B and $E0) = $C0 then Need := 2
    else if (B and $F0) = $E0 then Need := 3
    else if (B and $F8) = $F0 then Need := 4
    else Need := 1;
    if Need > K then
      Result := K;
    Exit;
  end;
end;

{ ---------------- TReaderThread ---------------- }

constructor TReaderThread.Create(Runner: TProcessRunner; Kind: TOutputKind; Handle: NativeInt);
begin
  FRunner := Runner;
  FKind := Kind;
  FHandle := Handle;
  inherited Create(False);
end;

function TReaderThread.ReadChunk(var Buf: TBytes): Integer;
{$IFDEF MSWINDOWS}
var
  Got: DWORD;
begin
  if not ReadFile(THandle(FHandle), Buf[0], Length(Buf), Got, nil) then
    Exit(0);
  Result := Got;
end;
{$ELSE}
begin
  repeat
    Result := __read(FHandle, @Buf[0], Length(Buf));
  until (Result >= 0) or (GetLastError <> EINTR);
  if Result < 0 then
    Result := 0;
end;
{$ENDIF}

procedure TReaderThread.Execute;
var
  Buf, Pending: TBytes;
  N, Keep, Total: Integer;
  Text: string;
begin
  SetLength(Buf, 8192);
  Pending := nil;
  while True do
  begin
    N := ReadChunk(Buf);
    if N <= 0 then
      Break;
    Total := Length(Pending) + N;
    SetLength(Pending, Total);
    Move(Buf[0], Pending[Total - N], N);
    Keep := IncompleteTail(Pending, Total);
    Text := TEncoding.UTF8.GetString(Pending, 0, Total - Keep);
    Pending := Copy(Pending, Total - Keep, Keep);
    if Text <> '' then
      FRunner.Deliver(FKind, Text);
  end;
  if Length(Pending) > 0 then
    FRunner.Deliver(FKind, TEncoding.UTF8.GetString(Pending));
{$IFDEF MSWINDOWS}
  CloseHandle(THandle(FHandle));
{$ELSE}
  __close(FHandle);
{$ENDIF}
end;

{ ---------------- TWaiterThread ---------------- }

constructor TWaiterThread.Create(Runner: TProcessRunner; R1, R2: TThread);
begin
  FRunner := Runner;
  FReaders[0] := R1;
  FReaders[1] := R2;
  inherited Create(False);
end;

procedure TWaiterThread.Execute;
var
  Code: Integer;
{$IFDEF MSWINDOWS}
  ExitCode: DWORD;
{$ELSE}
  Status: Integer;
{$ENDIF}
begin
{$IFDEF MSWINDOWS}
  WaitForSingleObject(FRunner.FProcess, INFINITE);
  if GetExitCodeProcess(FRunner.FProcess, ExitCode) then
    Code := Integer(ExitCode)
  else
    Code := -1;
{$ELSE}
  Status := 0;
  while (waitpid(FRunner.FPid, @Status, 0) < 0) and (GetLastError = EINTR) do
    ;
  if WIFEXITED(Status) then
    Code := WEXITSTATUS(Status)
  else
    Code := -1;
{$ENDIF}
  FReaders[0].WaitFor;
  FReaders[1].WaitFor;
  FRunner.Finished(Code);
end;

{ ---------------- TProcessRunner ---------------- }

constructor TProcessRunner.Create;
begin
  inherited;
  FThreads := TList.Create;
{$IFDEF MSWINDOWS}
  FInput := 0;
{$ELSE}
  FInput := -1;
{$ENDIF}
end;

procedure TProcessRunner.CloseInput;
begin
{$IFDEF MSWINDOWS}
  if FInput <> 0 then
  begin
    CloseHandle(FInput);
    FInput := 0;
  end;
{$ELSE}
  if FInput >= 0 then
  begin
    __close(FInput);
    FInput := -1;
  end;
{$ENDIF}
end;

function TProcessRunner.WriteInput(const Text: string): Boolean;
var
  Bytes: TBytes;
  Done: Integer;
{$IFDEF MSWINDOWS}
  Wrote: DWORD;
{$ELSE}
  Wrote: Integer;
{$ENDIF}
begin
  Result := False;
  if not FRunning then
    Exit;
  Bytes := TEncoding.UTF8.GetBytes(Text);
  Done := 0;
  while Done < Length(Bytes) do
  begin
{$IFDEF MSWINDOWS}
    if (FInput = 0) or not WriteFile(FInput, Bytes[Done], Length(Bytes) - Done, Wrote, nil) then
      Exit;
{$ELSE}
    if FInput < 0 then
      Exit;
    Wrote := __write(FInput, @Bytes[Done], Length(Bytes) - Done);
    if Wrote <= 0 then
      Exit;
{$ENDIF}
    Inc(Done, Wrote);
  end;
  Result := True;
end;

destructor TProcessRunner.Destroy;
begin
  Kill;
  WaitForThreads;
  CloseInput;
  FThreads.Free;
  inherited;
end;

procedure TProcessRunner.WaitForThreads;
var
  K: Integer;
  T: TThread;
begin
  for K := 0 to FThreads.Count - 1 do
  begin
    T := TThread(FThreads[K]);
    T.WaitFor;
    TThread.RemoveQueuedEvents(T);
    T.Free;
  end;
  FThreads.Clear;
end;

procedure TProcessRunner.Deliver(Kind: TOutputKind; const Text: string);
begin
  TThread.Queue(TThread.CurrentThread,
    procedure
    begin
      if Assigned(FOnOutput) then
        FOnOutput(Kind, Text);
    end);
end;

procedure TProcessRunner.Finished(Code: Integer);
begin
  TThread.Queue(TThread.CurrentThread,
    procedure
    begin
      FRunning := False;
      CloseInput;
{$IFDEF MSWINDOWS}
      CloseHandle(FProcess);
      FProcess := 0;
{$ENDIF}
      if Assigned(FOnExit) then
        FOnExit(Code);
    end);
end;

{$IFDEF MSWINDOWS}

function QuoteArg(const S: string): string;
var
  I, Backslashes: Integer;
begin
  if (S <> '') and (S.IndexOfAny([' ', #9, '"']) < 0) then
    Exit(S);
  Result := '"';
  Backslashes := 0;
  for I := 1 to Length(S) do
    if S[I] = '\' then
      Inc(Backslashes)
    else if S[I] = '"' then
    begin
      Result := Result + StringOfChar('\', Backslashes * 2 + 1) + '"';
      Backslashes := 0;
    end
    else
    begin
      Result := Result + StringOfChar('\', Backslashes) + S[I];
      Backslashes := 0;
    end;
  Result := Result + StringOfChar('\', Backslashes * 2) + '"';
end;

procedure TProcessRunner.Start(const Exe: string; const Args: array of string; const WorkDir: string;
  WithInput: Boolean);
var
  SA: TSecurityAttributes;
  OutRead, OutWrite, ErrRead, ErrWrite, NulIn, InWrite: THandle;
  SI: TStartupInfo;
  PI: TProcessInformation;
  CmdLine, A: string;
  R1, R2: TThread;
begin
  if FRunning then
    raise Exception.Create('a program is already running');
  WaitForThreads;
  FKilled := False;
  SA.nLength := SizeOf(SA);
  SA.lpSecurityDescriptor := nil;
  SA.bInheritHandle := True;
  if not CreatePipe(OutRead, OutWrite, @SA, 0) then RaiseLastOSError;
  if not CreatePipe(ErrRead, ErrWrite, @SA, 0) then RaiseLastOSError;
  SetHandleInformation(OutRead, HANDLE_FLAG_INHERIT, 0);
  SetHandleInformation(ErrRead, HANDLE_FLAG_INHERIT, 0);
  InWrite := 0;
  if WithInput then
  begin
    if not CreatePipe(NulIn, InWrite, @SA, 0) then RaiseLastOSError;
    SetHandleInformation(InWrite, HANDLE_FLAG_INHERIT, 0);
  end
  else
    NulIn := CreateFile('NUL', GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE, @SA,
      OPEN_EXISTING, 0, 0);

  FillChar(SI, SizeOf(SI), 0);
  SI.cb := SizeOf(SI);
  SI.dwFlags := STARTF_USESTDHANDLES;
  SI.hStdInput := NulIn;
  SI.hStdOutput := OutWrite;
  SI.hStdError := ErrWrite;
  CmdLine := QuoteArg(Exe);
  for A in Args do
    CmdLine := CmdLine + ' ' + QuoteArg(A);
  UniqueString(CmdLine);
  if not CreateProcess(nil, PChar(CmdLine), nil, nil, True, CREATE_NO_WINDOW, nil,
    PChar(WorkDir), SI, PI) then
  begin
    CloseHandle(OutRead); CloseHandle(OutWrite);
    CloseHandle(ErrRead); CloseHandle(ErrWrite);
    CloseHandle(NulIn);
    if InWrite <> 0 then CloseHandle(InWrite);
    RaiseLastOSError;
  end;
  // The child owns the write ends now.
  CloseHandle(OutWrite);
  CloseHandle(ErrWrite);
  CloseHandle(NulIn);
  CloseHandle(PI.hThread);
  FProcess := PI.hProcess;
  FInput := InWrite;
  FRunning := True;
  R1 := TReaderThread.Create(Self, okStdOut, NativeInt(OutRead));
  R2 := TReaderThread.Create(Self, okStdErr, NativeInt(ErrRead));
  FThreads.Add(R1);
  FThreads.Add(R2);
  FThreads.Add(TWaiterThread.Create(Self, R1, R2));
end;

procedure TProcessRunner.Kill;
begin
  if FRunning and (FProcess <> 0) then
  begin
    FKilled := True;
    TerminateProcess(FProcess, 1);
  end;
end;

{$ELSE}

procedure TProcessRunner.Start(const Exe: string; const Args: array of string; const WorkDir: string;
  WithInput: Boolean);
var
  OutPipe, ErrPipe, InPipe: array[0..1] of Integer;
  Strings: TArray<UTF8String>;
  Argv: TArray<PAnsiChar>;
  Dir, ExeU: UTF8String;
  K, Null: Integer;
  R1, R2: TThread;
begin
  if FRunning then
    raise Exception.Create('a program is already running');
  WaitForThreads;
  FKilled := False;
  // Everything the child needs is prepared before fork.
  ExeU := UTF8String(Exe);
  Dir := UTF8String(WorkDir);
  SetLength(Strings, Length(Args) + 1);
  Strings[0] := ExeU;
  for K := 0 to High(Args) do
    Strings[K + 1] := UTF8String(Args[K]);
  SetLength(Argv, Length(Strings) + 1);
  for K := 0 to High(Strings) do
    Argv[K] := PAnsiChar(Strings[K]);
  Argv[High(Argv)] := nil;
  if (pipe(@OutPipe[0]) <> 0) or (pipe(@ErrPipe[0]) <> 0) then
    RaiseLastOSError;
  InPipe[0] := -1;
  InPipe[1] := -1;
  if WithInput and (pipe(@InPipe[0]) <> 0) then
    RaiseLastOSError;

  FPid := fork;
  if FPid < 0 then
    RaiseLastOSError;
  if FPid = 0 then
  begin
    // The child: only async-signal-safe calls until exec.
    // POSIX calls only: Delphi names chdir __chdir, and a plain chdir or open
    // would find System.ChDir and friends, which are not safe after fork.
    if InPipe[0] >= 0 then
    begin
      dup2(InPipe[0], 0);
      __close(InPipe[0]);
      __close(InPipe[1]);
    end
    else
    begin
      Null := Posix.Fcntl.open('/dev/null', O_RDONLY);
      dup2(Null, 0);
    end;
    dup2(OutPipe[1], 1);
    dup2(ErrPipe[1], 2);
    __close(OutPipe[0]); __close(ErrPipe[0]);
    __close(OutPipe[1]); __close(ErrPipe[1]);
    __chdir(PAnsiChar(Dir));
    execv(PAnsiChar(ExeU), PPAnsiChar(@Argv[0]));
    _exit(127);
  end;
  __close(OutPipe[1]);
  __close(ErrPipe[1]);
  if InPipe[0] >= 0 then
    __close(InPipe[0]);
  FInput := InPipe[1];
  FRunning := True;
  R1 := TReaderThread.Create(Self, okStdOut, OutPipe[0]);
  R2 := TReaderThread.Create(Self, okStdErr, ErrPipe[0]);
  FThreads.Add(R1);
  FThreads.Add(R2);
  FThreads.Add(TWaiterThread.Create(Self, R1, R2));
end;

procedure TProcessRunner.Kill;
begin
  if FRunning and (FPid > 0) then
  begin
    FKilled := True;
    Posix.Signal.kill(FPid, SIGKILL);
  end;
end;

{$ENDIF}

{$IFNDEF MSWINDOWS}
initialization
  // Writing to the stdin of a program that has exited must fail, not kill us.
  signal(SIGPIPE, TSignalHandler(SIG_IGN));
{$ENDIF}

end.
