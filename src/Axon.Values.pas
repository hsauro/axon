unit Axon.Values;

(* Run-time values.

   TAxValue is a small tagged record. Scalars (bool, int, real, complex) live in
   the record itself. Every other kind keeps its payload in a reference-counted
   heap object held through the interface field Obj, so copying a TAxValue
   shares the payload. Payloads that can be written in place (matrices, lists,
   records, from M6) copy themselves first when shared: copy-on-write, as the
   reference requires.

   Display forms follow the reference's Display table. *)

interface

uses
  System.SysUtils,
  Axon.Complex, Axon.Errors;

type
  TValueKind = (vkNothing, vkBool, vkInt, vkReal, vkComplex, vkString, vkRange,
    vkBuiltin, vkFunction, vkList, vkRecord);

  TAxValue = record
    Kind: TValueKind;
    Obj: IInterface;            // payload of non-scalar kinds
    case Integer of
      0: (B: Boolean);
      1: (I: Int64);
      2: (R: Double);
      3: (C: TComplex);
  end;

  TAxValues = TArray<TAxValue>;

  TStringObj = class(TInterfacedObject)
  public
    Value: string;
    constructor Create(const S: string);
  end;

  { A lazy arithmetic sequence. Int ranges have int bounds and step; any real
    bound or step makes a real range. }
  TRangeObj = class(TInterfacedObject)
  public
    IsInt: Boolean;
    IStart, IStep, IStop: Int64;
    RStart, RStep, RStop: Double;
    Count: Int64;
    function ItemAt(K: Int64): TAxValue;   // 0-based
  end;

  TBuiltinFn = function(const Args: TAxValues): TAxValue;

  { Anything callable: a builtin, or a function written in Axon (whose class,
    TFunctionObj, lives in Axon.Interp). Name is empty for a lambda. }
  TCallableObj = class(TInterfacedObject)
  public
    Name: string;
  end;

  TBuiltinObj = class(TCallableObj)
  public
    Fn: TBuiltinFn;
    MinArgs, MaxArgs: Integer;   // MaxArgs = -1: no limit
  end;

  { An ordered, heterogeneous list. Read-only until M7 adds list operations. }
  TListObj = class(TInterfacedObject)
  public
    Items: TAxValues;
  end;

  { A record: named fields in definition order. Read-only until M7. }
  TRecordObj = class(TInterfacedObject)
  public
    Names: TArray<string>;
    Values: TAxValues;
    function IndexOf(const Name: string): Integer;
  end;

function NothingValue: TAxValue; inline;
function BoolValue(B: Boolean): TAxValue; inline;
function IntValue(I: Int64): TAxValue; inline;
function RealValue(R: Double): TAxValue; inline;
function ComplexValue(const C: TComplex): TAxValue; inline;
function ComplexValue2(Re, Im: Double): TAxValue; inline;
function StringValue(const S: string): TAxValue;

function AsString(const V: TAxValue): string; inline;
function AsRange(const V: TAxValue): TRangeObj; inline;
function AsBuiltin(const V: TAxValue): TBuiltinObj; inline;
function AsList(const V: TAxValue): TListObj; inline;
function AsRecord(const V: TAxValue): TRecordObj; inline;
function ListValue(const Items: TAxValues): TAxValue;
function RecordValue(const Names: TArray<string>; const Values: TAxValues): TAxValue;

{ The err record for a caught error: kind, message and trace (a list of
  records with file, line and function). }
function ErrorToValue(E: EAxonError): TAxValue;
{ The error that error(err) re-raises: same kind, message and trace. Returns
  nil if V is not an error record. }
function ErrorFromValue(const V: TAxValue): EAxonError;

{ Type name as used in messages and by typeof: "int", "real", ... }
function TypeName(const V: TAxValue): string;

{ Real number display: up to 15 significant digits, always with a decimal
  point, exponent form below 1e-4 or from 1e15 in magnitude. }
function FormatReal(X: Double): string;

{ The display form of a value. Strings are quoted when Quoted is True (the
  REPL) and bare otherwise (print, string()). }
function Display(const V: TAxValue; Quoted: Boolean = False): string;

implementation

uses
  System.Math,
  Axon.Tokens;

constructor TStringObj.Create(const S: string);
begin
  inherited Create;
  Value := S;
end;

function TRangeObj.ItemAt(K: Int64): TAxValue;
begin
  if IsInt then
    Result := IntValue(IStart + K * IStep)
  else
    Result := RealValue(RStart + K * RStep);
end;

function NothingValue: TAxValue;
begin
  Result.Kind := vkNothing;
  Result.Obj := nil;
  Result.I := 0;
end;

function BoolValue(B: Boolean): TAxValue;
begin
  Result.Kind := vkBool;
  Result.Obj := nil;
  Result.I := 0;
  Result.B := B;
end;

function IntValue(I: Int64): TAxValue;
begin
  Result.Kind := vkInt;
  Result.Obj := nil;
  Result.I := I;
end;

function RealValue(R: Double): TAxValue;
begin
  Result.Kind := vkReal;
  Result.Obj := nil;
  Result.R := R;
end;

function ComplexValue(const C: TComplex): TAxValue;
begin
  Result.Kind := vkComplex;
  Result.Obj := nil;
  Result.C := C;
end;

function ComplexValue2(Re, Im: Double): TAxValue;
begin
  Result.Kind := vkComplex;
  Result.Obj := nil;
  Result.C.Re := Re;
  Result.C.Im := Im;
end;

function StringValue(const S: string): TAxValue;
begin
  Result.Kind := vkString;
  Result.I := 0;
  Result.Obj := TStringObj.Create(S);
end;

function AsString(const V: TAxValue): string;
begin
  Result := TStringObj(V.Obj).Value;
end;

function AsRange(const V: TAxValue): TRangeObj;
begin
  Result := TRangeObj(V.Obj);
end;

function AsBuiltin(const V: TAxValue): TBuiltinObj;
begin
  Result := TBuiltinObj(V.Obj);
end;

function AsList(const V: TAxValue): TListObj;
begin
  Result := TListObj(V.Obj);
end;

function AsRecord(const V: TAxValue): TRecordObj;
begin
  Result := TRecordObj(V.Obj);
end;

function TRecordObj.IndexOf(const Name: string): Integer;
begin
  for Result := 0 to High(Names) do
    if Names[Result] = Name then
      Exit;
  Result := -1;
end;

function ListValue(const Items: TAxValues): TAxValue;
var
  L: TListObj;
begin
  L := TListObj.Create;
  L.Items := Items;
  Result := NothingValue;
  Result.Kind := vkList;
  Result.Obj := L;
end;

function RecordValue(const Names: TArray<string>; const Values: TAxValues): TAxValue;
var
  R: TRecordObj;
begin
  R := TRecordObj.Create;
  R.Names := Names;
  R.Values := Values;
  Result := NothingValue;
  Result.Kind := vkRecord;
  Result.Obj := R;
end;

function ErrorToValue(E: EAxonError): TAxValue;
var
  Frames: TAxValues;
  I: Integer;
  T: TTraceEntry;
  Tr: TArray<TTraceEntry>;
begin
  Tr := E.Trace;
  SetLength(Frames, Length(Tr));
  for I := 0 to High(Tr) do
  begin
    T := Tr[I];
    Frames[I] := RecordValue(['file', 'line', 'col', 'function'],
      [StringValue(T.FileName), IntValue(T.Line), IntValue(T.Col), StringValue(T.FunctionName)]);
  end;
  Result := RecordValue(['kind', 'message', 'trace'],
    [StringValue(E.Kind), StringValue(E.Message), ListValue(Frames)]);
end;

function ErrorFromValue(const V: TAxValue): EAxonError;
var
  R, F: TRecordObj;
  K, M, T, I: Integer;
  Frames: TListObj;
  Trace: TArray<TTraceEntry>;
  Fi: Integer;
begin
  Result := nil;
  if V.Kind <> vkRecord then
    Exit;
  R := AsRecord(V);
  K := R.IndexOf('kind');
  M := R.IndexOf('message');
  T := R.IndexOf('trace');
  if (K < 0) or (M < 0) or (R.Values[K].Kind <> vkString) or
     (R.Values[M].Kind <> vkString) then
    Exit;
  if (T >= 0) and (R.Values[T].Kind = vkList) then
  begin
    Frames := AsList(R.Values[T]);
    for I := 0 to High(Frames.Items) do
      if Frames.Items[I].Kind = vkRecord then
      begin
        F := AsRecord(Frames.Items[I]);
        SetLength(Trace, Length(Trace) + 1);
        Fi := F.IndexOf('file');
        if (Fi >= 0) and (F.Values[Fi].Kind = vkString) then
          Trace[High(Trace)].FileName := AsString(F.Values[Fi]);
        Fi := F.IndexOf('line');
        if (Fi >= 0) and (F.Values[Fi].Kind = vkInt) then
          Trace[High(Trace)].Line := F.Values[Fi].I;
        Fi := F.IndexOf('col');
        if (Fi >= 0) and (F.Values[Fi].Kind = vkInt) then
          Trace[High(Trace)].Col := F.Values[Fi].I;
        Fi := F.IndexOf('function');
        if (Fi >= 0) and (F.Values[Fi].Kind = vkString) then
          Trace[High(Trace)].FunctionName := AsString(F.Values[Fi]);
      end;
  end;
  Result := EAxonError.CreateFrozen(AsString(R.Values[K]), AsString(R.Values[M]), Trace);
end;

function TypeName(const V: TAxValue): string;
const
  Names: array[TValueKind] of string = ('nothing', 'bool', 'int', 'real',
    'complex', 'string', 'range', 'function', 'function', 'list', 'record');
begin
  Result := Names[V.Kind];
end;

function FormatReal(X: Double): string;
var
  S, Mantissa, Digits: string;
  P, E: Integer;
  Neg: Boolean;
begin
  if IsNan(X) then
    Exit('NaN');
  if IsInfinite(X) then
    if X > 0 then Exit('Inf') else Exit('-Inf');

  E := 0;
  Neg := (X < 0) or ((X = 0) and (PUInt64(@X)^ shr 63 = 1));
  X := Abs(X);
  if X = 0 then
    Digits := '0'
  else
  begin
    // Round to 15 significant digits: d.dddddddddddddd E+xxx
    S := FormatFloat('0.00000000000000E+000', X, TFormatSettings.Invariant);
    P := Pos('E', S);
    Mantissa := Copy(S, 1, P - 1);
    E := StrToInt(Copy(S, P + 1, MaxInt));
    Digits := Mantissa.Replace('.', '');
    // Drop trailing zeros, keeping at least one digit.
    while (Length(Digits) > 1) and (Digits[Length(Digits)] = '0') do
      Delete(Digits, Length(Digits), 1);
  end;

  if X = 0 then
    Result := '0.0'
  else if (E < -4) or (E >= 15) then
  begin
    Result := Digits[1] + '.';
    if Length(Digits) > 1 then
      Result := Result + Copy(Digits, 2, MaxInt)
    else
      Result := Result + '0';
    Result := Result + 'e' + IntToStr(E);
  end
  else if E >= 0 then
  begin
    // E + 1 digits before the point.
    if Length(Digits) <= E + 1 then
      Result := Digits + StringOfChar('0', E + 1 - Length(Digits)) + '.0'
    else
      Result := Copy(Digits, 1, E + 1) + '.' + Copy(Digits, E + 2, MaxInt);
  end
  else
    Result := '0.' + StringOfChar('0', -E - 1) + Digits;

  if Neg then
    Result := '-' + Result;
end;

function FormatComplex(const C: TComplex): string;
var
  ImNeg: Boolean;
begin
  ImNeg := (not IsNan(C.Im)) and ((C.Im < 0) or ((C.Im = 0) and (PUInt64(@C.Im)^ shr 63 = 1)));
  Result := FormatReal(C.Re);
  if ImNeg then
    Result := Result + ' - ' + FormatReal(-C.Im) + 'i'
  else
    Result := Result + ' + ' + FormatReal(C.Im) + 'i';
end;

function FormatRange(R: TRangeObj): string;
begin
  if R.IsInt then
  begin
    if R.IStep = 1 then
      Result := Format('%d:%d', [R.IStart, R.IStop])
    else
      Result := Format('%d:%d:%d', [R.IStart, R.IStep, R.IStop]);
  end
  else
    Result := FormatReal(R.RStart) + ':' + FormatReal(R.RStep) + ':' + FormatReal(R.RStop);
end;

function FormatList(L: TListObj): string;
var
  I: Integer;
begin
  Result := '{';
  for I := 0 to High(L.Items) do
  begin
    if I > 0 then
      Result := Result + ', ';
    // Strings inside containers are always quoted.
    Result := Result + Display(L.Items[I], True);
  end;
  Result := Result + '}';
end;

function FormatRecord(R: TRecordObj): string;
var
  I: Integer;
begin
  Result := '{';
  for I := 0 to High(R.Names) do
  begin
    if I > 0 then
      Result := Result + ', ';
    Result := Result + R.Names[I] + ': ' + Display(R.Values[I], True);
  end;
  Result := Result + '}';
end;

function Display(const V: TAxValue; Quoted: Boolean): string;
begin
  case V.Kind of
    vkNothing: Result := 'nothing';
    vkBool:    if V.B then Result := 'true' else Result := 'false';
    vkInt:     Result := IntToStr(V.I);
    vkReal:    Result := FormatReal(V.R);
    vkComplex: Result := FormatComplex(V.C);
    vkString:
      if Quoted then
        Result := EscapeString(AsString(V))
      else
        Result := AsString(V);
    vkRange:   Result := FormatRange(AsRange(V));
    vkBuiltin, vkFunction:
      if TCallableObj(V.Obj).Name <> '' then
        Result := 'function ' + TCallableObj(V.Obj).Name
      else
        Result := 'function';
    vkList:    Result := FormatList(AsList(V));
    vkRecord:  Result := FormatRecord(AsRecord(V));
  else
    Result := '<value>';
  end;
end;

end.
