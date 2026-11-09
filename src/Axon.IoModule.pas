unit Axon.IoModule;

(* The core module io (reference, "The io module"): whole-file reading and
   writing, lines, CSV tables and JSON. Text is UTF-8; relative paths are
   relative to the working directory. Failures raise IOError. *)

interface

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Math,
  Axon.Errors, Axon.Values, Axon.Ops, Axon.Arrays, Axon.NativeModules, Axon.Json,
  Axon.FloatParse;

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

{ io.current_dir(): the working directory, as a full path; relative paths
  given to io are read from it. }
function BCurrentDir(const Args: TAxValues): TAxValue;
begin
  Result := StringValue(GetCurrentDir);
end;

{ io.set_current_dir(path): makes path (full, or relative to the current
  directory) the working directory. }
function BSetCurrentDir(const Args: TAxValues): TAxValue;
var
  Path: string;
begin
  Path := PathArg('set_current_dir', Args[0]);
  if not TDirectory.Exists(Path) then
    RaiseFmt(IOError, 'set_current_dir: no folder "%s"', [Path]);
  if not SetCurrentDir(Path) then
    RaiseFmt(IOError, 'set_current_dir: cannot change to "%s"', [Path]);
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

{ The text of a UTF-8 file, as read_file reads it. }
function ReadText(const Fn, Path: string): string;
var
  Bytes: TBytes;
  Start: Integer;
begin
  if not TFile.Exists(Path) then
    RaiseFmt(IOError, '%s: no file "%s"', [Fn, Path]);
  try
    Bytes := TFile.ReadAllBytes(Path);
  except
    on E: Exception do
      IoFail(Fn, Path, E);
  end;
  Start := 0;
  if (Length(Bytes) >= 3) and (Bytes[0] = $EF) and (Bytes[1] = $BB) and (Bytes[2] = $BF) then
    Start := 3;
  try
    Result := TEncoding.UTF8.GetString(Bytes, Start, Length(Bytes) - Start);
  except
    on EEncodingError do
      RaiseFmt(IOError, '%s: "%s" is not valid UTF-8 text', [Fn, Path]);
  end;
end;

{ The lines of a text, without their line breaks (LF or CR LF); a final
  line break does not start another line. }
function SplitLines(const Text: string): TArray<string>;
var
  L: TStringList;
  K: Integer;
begin
  L := TStringList.Create;
  try
    L.Text := Text;
    SetLength(Result, L.Count);
    for K := 0 to L.Count - 1 do
      Result[K] := L[K];
  finally
    L.Free;
  end;
end;

{ io.read_lines(path): the lines of a text file, as a list of strings. }
function BReadLines(const Args: TAxValues): TAxValue;
var
  Items: TAxValues;
  Lines: TArray<string>;
  K: Integer;
begin
  Lines := SplitLines(ReadText('read_lines', PathArg('read_lines', Args[0])));
  SetLength(Items, Length(Lines));
  for K := 0 to High(Lines) do
    Items[K] := StringValue(Lines[K]);
  Result := ListValue(Items);
end;

function SepArg(const Fn: string; const Args: TAxValues; Index: Integer): Char;
var
  S: string;
begin
  Result := ',';
  if Length(Args) <= Index then
    Exit;
  if Args[Index].Kind <> vkString then
    RaiseFmt(TypeError, '%s: the separator must be a string, got %s',
      [Fn, TypeName(Args[Index])]);
  S := AsString(Args[Index]);
  if Length(S) <> 1 then
    RaiseFmt(ArgumentError, '%s: the separator must be one character, such as ",", ";" ' +
      'or "\t", got "%s"', [Fn, S]);
  Result := S[1];
end;

{ The fields of one CSV line. A field may be quoted with ", which lets it
  hold the separator; "" inside quotes is one ". Fields are not trimmed
  here. }
function CsvFields(const Line: string; Sep: Char): TArray<string>;
var
  K: Integer;
  Field: TStringBuilder;
  InQuotes: Boolean;
  C: Char;
begin
  Result := nil;
  Field := TStringBuilder.Create;
  try
    InQuotes := False;
    K := 1;
    while K <= Length(Line) do
    begin
      C := Line[K];
      if InQuotes then
      begin
        if C = '"' then
        begin
          if (K < Length(Line)) and (Line[K + 1] = '"') then
          begin
            Field.Append('"');
            Inc(K);
          end
          else
            InQuotes := False;
        end
        else
          Field.Append(C);
      end
      else if C = '"' then
        InQuotes := True
      else if C = Sep then
      begin
        Result := Result + [Field.ToString];
        Field.Clear;
      end
      else
        Field.Append(C);
      Inc(K);
    end;
    Result := Result + [Field.ToString];
  finally
    Field.Free;
  end;
end;

{ A CSV field as a number: empty (or only spaces) is NaN. }
function CsvNumber(const Field: string; out D: Double): Boolean;
begin
  if Field.Trim([' ', #9]) = '' then
  begin
    D := NaN;
    Exit(True);
  end;
  Result := TryParseReal(Field, D);
end;

(* io.read_csv(path) and io.read_csv(path, sep): a table of numbers, as a
  record {names, data}: data is a real matrix with one row per line and one
  column per field; names is the list of column names when the first line
  is a header (a field that is not a number), else nothing. Blank lines
  are skipped; an empty field is NaN. *)
function BReadCsv(const Args: TAxValues): TAxValue;
var
  Path: string;
  Sep: Char;
  Lines, Fields: TArray<string>;
  Rows: TArray<TArray<Double>>;
  Names: TAxValues;
  HasNames: Boolean;
  Cols, K, J, LineNo, First: Integer;
  D: Double;
  Row: TArray<Double>;
  A: TArrayObj;
begin
  Path := PathArg('read_csv', Args[0]);
  Sep := SepArg('read_csv', Args, 1);
  Lines := SplitLines(ReadText('read_csv', Path));
  // The first non-blank line: a header when any field is not a number.
  First := 0;
  while (First <= High(Lines)) and (Lines[First].Trim = '') do
    Inc(First);
  HasNames := False;
  Cols := -1;
  if First <= High(Lines) then
  begin
    Fields := CsvFields(Lines[First], Sep);
    Cols := Length(Fields);
    for J := 0 to High(Fields) do
      if not CsvNumber(Fields[J], D) then
        HasNames := True;
    if HasNames then
    begin
      SetLength(Names, Cols);
      for J := 0 to Cols - 1 do
        Names[J] := StringValue(Fields[J].Trim([' ', #9]));
      Inc(First);
    end;
  end;
  Rows := nil;
  for K := First to High(Lines) do
  begin
    if Lines[K].Trim = '' then
      Continue;
    LineNo := K + 1;
    Fields := CsvFields(Lines[K], Sep);
    if Cols < 0 then
      Cols := Length(Fields);
    if Length(Fields) <> Cols then
      RaiseFmt(IOError, 'read_csv: line %d of "%s" has %d field(s), but the table has %d',
        [LineNo, Path, Length(Fields), Cols]);
    SetLength(Row, Cols);
    for J := 0 to Cols - 1 do
      if not CsvNumber(Fields[J], Row[J]) then
        RaiseFmt(IOError, 'read_csv: line %d of "%s", field %d: "%s" is not a number',
          [LineNo, Path, J + 1, Fields[J].Trim([' ', #9])]);
    Rows := Rows + [Copy(Row)];
  end;
  if Cols < 0 then
    Cols := 0;
  A := TArrayObj.Create(etReal, Length(Rows), Cols, False);
  Result := ArrayValue(A);
  for K := 0 to High(Rows) do
    for J := 0 to Cols - 1 do
      A.R[K + J * Length(Rows)] := Rows[K][J];
  if HasNames then
    Result := RecordValue(['names', 'data'], [ListValue(Names), Result])
  else
    Result := RecordValue(['names', 'data'], [NothingValue, Result]);
end;

{ A number as CSV text that reads back to the same value. }
function CsvText(const V: TAxValue): string;
var
  X, Back: Double;
begin
  case V.Kind of
    vkBool: if V.B then Result := '1' else Result := '0';
    vkInt: Result := IntToStr(V.I);
    vkReal:
      begin
        X := V.R;
        if IsNan(X) then
          Exit('NaN');
        if IsInfinite(X) then
          if X > 0 then Exit('Inf') else Exit('-Inf');
        Result := FloatToStrF(X, ffGeneral, 15, 0, TFormatSettings.Invariant);
        if not TryParseReal(Result, Back) or (Back <> X) then
          Result := FloatToStrF(X, ffGeneral, 17, 0, TFormatSettings.Invariant);
        Result := Result.Replace('E', 'e');
      end;
  else
    RaiseFmt(TypeError, 'write_csv cannot write %s values', [TypeName(V)]);
  end;
end;

{ A column name as a CSV field, quoted when it holds the separator, a quote
  or a line break. }
function CsvName(const S: string; Sep: Char): string;
begin
  if (S.IndexOf(Sep) >= 0) or (S.IndexOf('"') >= 0) or (S.IndexOfAny([#10, #13]) >= 0) then
    Result := '"' + S.Replace('"', '""') + '"'
  else
    Result := S;
end;

{ io.write_csv(path, A), io.write_csv(path, A, names) and
  io.write_csv(path, A, names, sep): a vector (one column) or matrix of
  numbers, one row per line, optionally under a header of column names
  (nothing for none). }
function BWriteCsv(const Args: TAxValues): TAxValue;
var
  Path: string;
  A: TArrayObj;
  Holder: TAxValue;
  Sep: Char;
  SB: TStringBuilder;
  Rows, Cols, I, J: Integer;
  Names: TAxValues;
begin
  Path := PathArg('write_csv', Args[0]);
  if not IsArrayLike(Args[1]) then
    RaiseFmt(TypeError, 'write_csv needs a vector or matrix of numbers, got %s',
      [TypeName(Args[1])]);
  A := ToArray(Args[1]);
  Holder := ArrayValue(A);
  if A.ElemType = etComplex then
    RaiseError(TypeError, 'write_csv cannot write complex numbers');
  Rows := A.Rows;
  Cols := A.Cols;
  Sep := SepArg('write_csv', Args, 3);
  SB := TStringBuilder.Create;
  try
    if (Length(Args) >= 3) and (Args[2].Kind <> vkNothing) then
    begin
      if Args[2].Kind <> vkList then
        RaiseFmt(TypeError, 'write_csv: the column names must be a list of strings, got %s',
          [TypeName(Args[2])]);
      Names := AsList(Args[2]).Items;
      if Length(Names) <> Cols then
        RaiseFmt(DimensionError, 'write_csv: %d column names for %d columns',
          [Length(Names), Cols]);
      for J := 0 to Cols - 1 do
      begin
        if Names[J].Kind <> vkString then
          RaiseFmt(TypeError, 'write_csv: column name %d is %s, not a string',
            [J + 1, TypeName(Names[J])]);
        if J > 0 then
          SB.Append(Sep);
        SB.Append(CsvName(AsString(Names[J]), Sep));
      end;
      SB.Append(#10);
    end;
    for I := 0 to Rows - 1 do
    begin
      for J := 0 to Cols - 1 do
      begin
        if J > 0 then
          SB.Append(Sep);
        SB.Append(CsvText(A.Get(I + J * Rows)));
      end;
      SB.Append(#10);
    end;
    try
      TFile.WriteAllBytes(Path, TEncoding.UTF8.GetBytes(SB.ToString));
    except
      on E: Exception do
        IoFail('write_csv', Path, E);
    end;
  finally
    SB.Free;
  end;
  Result := NothingValue;
end;

procedure DefineIo(const Define: TProc<string, TAxValue>);
begin
  Define('read_file', BuiltinValue('read_file', BReadFile, 1, 1));
  Define('read_bytes', BuiltinValue('read_bytes', BReadBytes, 1, 1));
  Define('write_file', BuiltinValue('write_file', BWriteFile, 2, 2));
  Define('file_exists', BuiltinValue('file_exists', BFileExists, 1, 1));
  Define('current_dir', BuiltinValue('current_dir', BCurrentDir, 0, 0));
  Define('set_current_dir', BuiltinValue('set_current_dir', BSetCurrentDir, 1, 1));
  Define('delete_file', BuiltinValue('delete_file', BDeleteFile, 1, 1));
  Define('write_json', BuiltinValue('write_json', BWriteJson, 2, 2));
  Define('read_json', BuiltinValue('read_json', BReadJson, 1, 1));
  Define('read_lines', BuiltinValue('read_lines', BReadLines, 1, 1));
  Define('read_csv', BuiltinValue('read_csv', BReadCsv, 1, 2));
  Define('write_csv', BuiltinValue('write_csv', BWriteCsv, 2, 4));
end;

initialization
  RegisterNativeModule('io', DefineIo, ['Reading and writing files: text, lines, bytes, CSV tables and JSON.']);

end.
