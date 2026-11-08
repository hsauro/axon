unit Axon.IoModule;

(* The core module io (reference, "The io module"): whole-file reading and
   writing. Text is UTF-8; relative paths are relative to the working
   directory. Failures raise IOError. *)

interface

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils,
  Axon.Errors, Axon.Values, Axon.Ops, Axon.NativeModules, Axon.Json;

function PathArg(const Fn: string; const V: TAxValue): string;
begin
  if V.Kind <> vkString then
    RaiseFmt(TypeError, '%s needs a file path string, got %s', [Fn, TypeName(V)]);
  Result := AsString(V);
end;

procedure IoFail(const Fn, Path: string; E: Exception);
begin
  RaiseFmt(IOError, '%s: cannot access "%s": %s', [Fn, Path, E.Message]);
end;

function BReadFile(const Args: TAxValues): TAxValue;
var
  Path: string;
  Bytes: TBytes;
  Start: Integer;
begin
  Path := PathArg('read_file', Args[0]);
  if not TFile.Exists(Path) then
    RaiseFmt(IOError, 'read_file: no file "%s"', [Path]);
  try
    Bytes := TFile.ReadAllBytes(Path);
  except
    on E: Exception do
      IoFail('read_file', Path, E);
  end;
  Start := 0;
  if (Length(Bytes) >= 3) and (Bytes[0] = $EF) and (Bytes[1] = $BB) and (Bytes[2] = $BF) then
    Start := 3;
  try
    Result := StringValue(TEncoding.UTF8.GetString(Bytes, Start, Length(Bytes) - Start));
  except
    on EEncodingError do
      RaiseFmt(IOError, 'read_file: "%s" is not valid UTF-8 text; use read_bytes', [Path]);
  end;
end;

function BReadBytes(const Args: TAxValues): TAxValue;
var
  Path: string;
  Bytes: TBytes;
  A: TArrayObj;
  K: Integer;
begin
  Path := PathArg('read_bytes', Args[0]);
  if not TFile.Exists(Path) then
    RaiseFmt(IOError, 'read_bytes: no file "%s"', [Path]);
  try
    Bytes := TFile.ReadAllBytes(Path);
  except
    on E: Exception do
      IoFail('read_bytes', Path, E);
  end;
  A := TArrayObj.Create(etInt, Length(Bytes), 1, True);
  Result := ArrayValue(A);
  for K := 0 to High(Bytes) do
    A.I[K] := Bytes[K];
end;

function BWriteFile(const Args: TAxValues): TAxValue;
var
  Path: string;
begin
  Path := PathArg('write_file', Args[0]);
  if Args[1].Kind <> vkString then
    RaiseFmt(TypeError, 'write_file needs a string to write, got %s', [TypeName(Args[1])]);
  try
    TFile.WriteAllBytes(Path, TEncoding.UTF8.GetBytes(AsString(Args[1])));
  except
    on E: Exception do
      IoFail('write_file', Path, E);
  end;
  Result := NothingValue;
end;

function BFileExists(const Args: TAxValues): TAxValue;
begin
  Result := BoolValue(TFile.Exists(PathArg('file_exists', Args[0])));
end;

function BDeleteFile(const Args: TAxValues): TAxValue;
var
  Path: string;
begin
  Path := PathArg('delete_file', Args[0]);
  if not TFile.Exists(Path) then
    Exit(BoolValue(False));
  try
    TFile.Delete(Path);
  except
    on E: Exception do
      IoFail('delete_file', Path, E);
  end;
  Result := BoolValue(True);
end;

{ io.write_json(path, value): the value as JSON text (Axon.Json says how
  each kind of value is written). }
function BWriteJson(const Args: TAxValues): TAxValue;
var
  Path, Text: string;
begin
  Path := PathArg('write_json', Args[0]);
  Text := ValueToJson(Args[1], 'write_json');
  try
    TFile.WriteAllBytes(Path, TEncoding.UTF8.GetBytes(Text));
  except
    on E: Exception do
      IoFail('write_json', Path, E);
  end;
  Result := NothingValue;
end;

{ io.read_json(path): the value the JSON text in the file describes. }
function BReadJson(const Args: TAxValues): TAxValue;
var
  Path, Text: string;
begin
  Path := PathArg('read_json', Args[0]);
  try
    Text := TEncoding.UTF8.GetString(TFile.ReadAllBytes(Path));
  except
    on E: Exception do
      IoFail('read_json', Path, E);
  end;
  Result := JsonToValue(Text, 'read_json');
end;

procedure DefineIo(const Define: TProc<string, TAxValue>);
begin
  Define('read_file', BuiltinValue('read_file', BReadFile, 1, 1));
  Define('read_bytes', BuiltinValue('read_bytes', BReadBytes, 1, 1));
  Define('write_file', BuiltinValue('write_file', BWriteFile, 2, 2));
  Define('file_exists', BuiltinValue('file_exists', BFileExists, 1, 1));
  Define('delete_file', BuiltinValue('delete_file', BDeleteFile, 1, 1));
  Define('write_json', BuiltinValue('write_json', BWriteJson, 2, 2));
  Define('read_json', BuiltinValue('read_json', BReadJson, 1, 1));
end;

initialization
  RegisterNativeModule('io', DefineIo, ['Whole-file reading and writing (UTF-8 text, or bytes).']);

end.
