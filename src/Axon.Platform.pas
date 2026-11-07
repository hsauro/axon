unit Axon.Platform;

{ Platform-specific code. Everything that needs $IFDEF MSWINDOWS / POSIX lives
  here (and in the src\native units), so a Linux target can be added later by
  filling in the POSIX branches. }

interface

{ Switches stdout and stderr to UTF-8. Call once at start-up. }
procedure InitConsole;

{ Sets an environment variable for this process and the processes it starts;
  an empty Value removes it. }
procedure SetEnv(const Name, Value: string);

{ Loads a native library; returns 0 if it cannot be loaded. }
function LoadNativeLibrary(const Path: string): NativeUInt;
{ The address of a symbol in a loaded library, or nil. }
function NativeSymbol(Lib: NativeUInt; const Name: string): Pointer;

{ Runs Exe with Args in WorkDir, capturing stdout and stderr as UTF-8 text.
  Returns the exit code. If the process runs longer than TimeoutMs it is
  killed, TimedOut is set and the result is -1.
  On POSIX the timeout is not enforced yet. }
function RunProcess(const Exe: string; const Args: array of string;
  const WorkDir: string; TimeoutMs: Cardinal;
  out StdOut, StdErr: string; out TimedOut: Boolean): Integer;

implementation

uses
{$IFDEF MSWINDOWS}
  Winapi.Windows,
{$ENDIF}
{$IFDEF POSIX}
  Posix.Stdlib, Posix.SysWait, Posix.Dlfcn,
{$ENDIF}
  System.SysUtils, System.Classes, System.IOUtils, System.Math;

procedure InitConsole;
begin
{$IFDEF MSWINDOWS}
  SetConsoleOutputCP(CP_UTF8);
  SetConsoleCP(CP_UTF8);
{$ENDIF}
  SetTextCodePage(Input, CP_UTF8);
  SetTextCodePage(Output, CP_UTF8);
  SetTextCodePage(ErrOutput, CP_UTF8);
end;

function LoadNativeLibrary(const Path: string): NativeUInt;
{$IFDEF MSWINDOWS}
begin
  Result := Winapi.Windows.LoadLibrary(PChar(Path));
end;
{$ENDIF}
{$IFDEF POSIX}
var
  M: TMarshaller;
begin
  Result := NativeUInt(dlopen(M.AsUtf8(Path).ToPointer, RTLD_NOW));
end;
{$ENDIF}

function NativeSymbol(Lib: NativeUInt; const Name: string): Pointer;
{$IFDEF MSWINDOWS}
begin
  Result := Winapi.Windows.GetProcAddress(HMODULE(Lib), PChar(Name));
end;
{$ENDIF}
{$IFDEF POSIX}
var
  M: TMarshaller;
begin
  Result := dlsym(Lib, M.AsUtf8(Name).ToPointer);
end;
{$ENDIF}

procedure SetEnv(const Name, Value: string);
{$IFDEF MSWINDOWS}
begin
  if Value = '' then
    SetEnvironmentVariable(PChar(Name), nil)
  else
    SetEnvironmentVariable(PChar(Name), PChar(Value));
end;
{$ENDIF}
{$IFDEF POSIX}
var
  M: TMarshaller;
begin
  if Value = '' then
    Posix.Stdlib.unsetenv(M.AsUtf8(Name).ToPointer)
  else
    Posix.Stdlib.setenv(M.AsUtf8(Name).ToPointer, M.AsUtf8(Value).ToPointer, 1);
end;
{$ENDIF}

{$IFDEF MSWINDOWS}

{ Quotes one argument following the MSVC command-line parsing rules. }
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

procedure DrainPipe(Pipe: THandle; Buffer: TBytesStream);
var
  Available, Got: DWORD;
  Chunk: array[0..65535] of Byte;
begin
  while PeekNamedPipe(Pipe, nil, 0, nil, @Available, nil) and (Available > 0) do
  begin
    if not ReadFile(Pipe, Chunk, Min(Available, SizeOf(Chunk)), Got, nil) or (Got = 0) then
      Break;
    Buffer.WriteBuffer(Chunk, Got);
  end;
end;

function RunProcess(const Exe: string; const Args: array of string;
  const WorkDir: string; TimeoutMs: Cardinal;
  out StdOut, StdErr: string; out TimedOut: Boolean): Integer;
const
  PipeSize = 1 shl 16;
var
  SA: TSecurityAttributes;
  OutRead, OutWrite, ErrRead, ErrWrite: THandle;
  SI: TStartupInfo;
  PI: TProcessInformation;
  CmdLine: string;
  OutBuf, ErrBuf: TBytesStream;
  Started: UInt64;
  Code: DWORD;
  A: string;
  Dir: PChar;
begin
  StdOut := '';
  StdErr := '';
  TimedOut := False;

  SA.nLength := SizeOf(SA);
  SA.lpSecurityDescriptor := nil;
  SA.bInheritHandle := True;
  if not CreatePipe(OutRead, OutWrite, @SA, PipeSize) then
    RaiseLastOSError;
  if not CreatePipe(ErrRead, ErrWrite, @SA, PipeSize) then
    RaiseLastOSError;
  SetHandleInformation(OutRead, HANDLE_FLAG_INHERIT, 0);
  SetHandleInformation(ErrRead, HANDLE_FLAG_INHERIT, 0);

  OutBuf := TBytesStream.Create;
  ErrBuf := TBytesStream.Create;
  try
    FillChar(SI, SizeOf(SI), 0);
    SI.cb := SizeOf(SI);
    SI.dwFlags := STARTF_USESTDHANDLES;
    SI.hStdInput := 0;
    SI.hStdOutput := OutWrite;
    SI.hStdError := ErrWrite;

    CmdLine := QuoteArg(Exe);
    for A in Args do
      CmdLine := CmdLine + ' ' + QuoteArg(A);
    UniqueString(CmdLine);

    if WorkDir <> '' then Dir := PChar(WorkDir) else Dir := nil;
    if not CreateProcess(nil, PChar(CmdLine), nil, nil, True, CREATE_NO_WINDOW,
      nil, Dir, SI, PI) then
    begin
      CloseHandle(OutWrite);
      CloseHandle(ErrWrite);
      CloseHandle(OutRead);
      CloseHandle(ErrRead);
      RaiseLastOSError;
    end;
    // The child owns the write ends now.
    CloseHandle(OutWrite);
    CloseHandle(ErrWrite);

    Started := GetTickCount64;
    while True do
    begin
      DrainPipe(OutRead, OutBuf);
      DrainPipe(ErrRead, ErrBuf);
      if WaitForSingleObject(PI.hProcess, 5) = WAIT_OBJECT_0 then
        Break;
      if GetTickCount64 - Started > TimeoutMs then
      begin
        TerminateProcess(PI.hProcess, 1);
        WaitForSingleObject(PI.hProcess, INFINITE);
        TimedOut := True;
        Break;
      end;
    end;
    DrainPipe(OutRead, OutBuf);
    DrainPipe(ErrRead, ErrBuf);

    if TimedOut then
      Result := -1
    else if GetExitCodeProcess(PI.hProcess, Code) then
      Result := Integer(Code)
    else
      Result := -1;

    CloseHandle(PI.hThread);
    CloseHandle(PI.hProcess);
    CloseHandle(OutRead);
    CloseHandle(ErrRead);

    StdOut := TEncoding.UTF8.GetString(OutBuf.Bytes, 0, OutBuf.Size);
    StdErr := TEncoding.UTF8.GetString(ErrBuf.Bytes, 0, ErrBuf.Size);
  finally
    OutBuf.Free;
    ErrBuf.Free;
  end;
end;

{$ENDIF MSWINDOWS}

{$IFDEF POSIX}

function ShellQuote(const S: string): string;
begin
  Result := '''' + StringReplace(S, '''', '''\''''', [rfReplaceAll]) + '''';
end;

function ReadAndDelete(const FileName: string): string;
begin
  if TFile.Exists(FileName) then
  begin
    Result := TEncoding.UTF8.GetString(TFile.ReadAllBytes(FileName));
    TFile.Delete(FileName);
  end
  else
    Result := '';
end;

{ Simple implementation through the shell, with output redirected to temporary
  files. Good enough for the test runner; a fork/exec version with a timeout
  can replace it when the macOS test run needs one. }
function RunProcess(const Exe: string; const Args: array of string;
  const WorkDir: string; TimeoutMs: Cardinal;
  out StdOut, StdErr: string; out TimedOut: Boolean): Integer;
var
  Cmd, OutFile, ErrFile, A: string;
  Status: Integer;
  M: TMarshaller;
begin
  TimedOut := False;
  OutFile := TPath.GetTempFileName;
  ErrFile := TPath.GetTempFileName;
  Cmd := '';
  if WorkDir <> '' then
    Cmd := 'cd ' + ShellQuote(WorkDir) + ' && ';
  Cmd := Cmd + ShellQuote(Exe);
  for A in Args do
    Cmd := Cmd + ' ' + ShellQuote(A);
  Cmd := Cmd + ' </dev/null >' + ShellQuote(OutFile) + ' 2>' + ShellQuote(ErrFile);
  Status := _system(M.AsUtf8(Cmd).ToPointer);
  if WIFEXITED(Status) then
    Result := WEXITSTATUS(Status)
  else
    Result := -1;
  StdOut := ReadAndDelete(OutFile);
  StdErr := ReadAndDelete(ErrFile);
end;

{$ENDIF POSIX}

end.
