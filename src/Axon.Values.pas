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
  System.SysUtils, System.Generics.Collections,
  Axon.Complex, Axon.Errors, Axon.Ast;

type
  TValueKind = (vkNothing, vkBool, vkInt, vkReal, vkComplex, vkString, vkRange,
    vkBuiltin, vkFunction, vkList, vkRecord, vkArray, vkDict, vkRecordType);

  TElemType = (etBool, etInt, etReal, etComplex);

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

  TBuiltinMultiFn = function(const Args: TAxValues): TAxValues;

  TBuiltinObj = class(TCallableObj)
  public
    Fn: TBuiltinFn;
    MultiFn: TBuiltinMultiFn;    // set instead of Fn for builtins returning several values
    MinArgs, MaxArgs: Integer;   // MaxArgs = -1: no limit
  end;

  { An ordered, heterogeneous list. Read-only until M7 adds list operations. }
  { A dense vector or matrix, stored column-major in the array matching its
    element type (only that one is allocated), so a real or complex buffer can
    go to BLAS/LAPACK as-is. A vector has Cols = 1 and IsVector = True. }
  TArrayObj = class(TInterfacedObject)
  public
    ElemType: TElemType;
    Rows, Cols: Integer;
    IsVector: Boolean;
    B: TArray<Boolean>;
    I: TArray<Int64>;
    R: TArray<Double>;
    C: TArray<TComplex>;
    constructor Create(AType: TElemType; ARows, ACols: Integer; AIsVector: Boolean);
    function Count: Integer; inline;
    function Get(K: Integer): TAxValue;              // 0-based, column-major
    procedure Put(K: Integer; const V: TAxValue);    // V must fit ElemType
    function Clone: TArrayObj;                       // counts in ArrayCopies
    procedure Widen(T: TElemType);                   // in place, never narrows
  end;

  TListObj = class(TInterfacedObject)
  public
    Items: TAxValues;
  end;

  { A declared record type (`record T … end`). Calling it builds a record. }
  TRecordTypeObj = class(TCallableObj)
  public
    FieldNames: TArray<string>;
    FieldTypes: TArray<TTypeRef>;   // owned by the AST
    function IndexOf(const Field: string): Integer;
  end;

  { A record: named fields in definition order. DeclType is set for a record
    of a declared type (DeclRef keeps the type alive). }
  TRecordObj = class(TInterfacedObject)
  public
    Names: TArray<string>;
    Values: TAxValues;
    DeclType: TRecordTypeObj;
    DeclRef: IInterface;
    function IndexOf(const Name: string): Integer;
    function Clone: TRecordObj;
  end;

  { A dictionary: entries in insertion order, found through a normalised key. }
  TDictObj = class(TInterfacedObject)
  private
    FIndex: TDictionary<string, Integer>;
  public
    Keys: TAxValues;
    Values: TAxValues;
    constructor Create;
    destructor Destroy; override;
    { The lookup form of a key; raises TypeError for an invalid key. }
    class function KeyOf(const K: TAxValue): string; static;
    function Find(const K: TAxValue): Integer;       // -1 if absent
    procedure Put(const K, V: TAxValue);
    function Clone: TDictObj;
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
function AsDict(const V: TAxValue): TDictObj; inline;
function DictValue(D: TDictObj): TAxValue;
function AsRecordType(const V: TAxValue): TRecordTypeObj; inline;

{ Makes V the only reference to its payload, copying it first if it is
  shared (copy-on-write). Containers copy one level: their elements stay
  shared until they are written in turn. }
procedure MakeUnique(var V: TAxValue);

{ The err record for a caught error: kind, message and trace (a list of
  records with file, line and function). }
function ErrorToValue(E: EAxonError): TAxValue;
{ The error that error(err) re-raises: same kind, message and trace. Returns
  nil if V is not an error record. }
function ErrorFromValue(const V: TAxValue): EAxonError;

{ Type name as used in messages and by typeof: "int", "real", ... }
function TypeName(const V: TAxValue): string;

{ Real number display: up to 15 significant digits, always with a decimal
  point, exponent form below 1e-4 or from 1e15 in magnitude. Arrays use
  Digits = 6 for their elements. }
function FormatReal(X: Double; Digits: Integer = 15): string;

var
  { Number of array copies made by copy-on-write (the __copies() test hook). }
  ArrayCopies: Int64;

function AsArray(const V: TAxValue): TArrayObj; inline;
function ArrayValue(A: TArrayObj): TAxValue;
function ElemTypeName(T: TElemType): string;
{ Element type of a scalar bool/int/real/complex value. }
function ElemTypeOf(const V: TAxValue): TElemType;

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

{ ---- arrays ---- }

constructor TArrayObj.Create(AType: TElemType; ARows, ACols: Integer; AIsVector: Boolean);
var
  N: Integer;
begin
  inherited Create;
  ElemType := AType;
  Rows := ARows;
  Cols := ACols;
  IsVector := AIsVector;
  N := ARows * ACols;
  case AType of
    etBool:    SetLength(B, N);
    etInt:     SetLength(I, N);
    etReal:    SetLength(R, N);
    etComplex: SetLength(C, N);
  end;
end;

function TArrayObj.Count: Integer;
begin
  Result := Rows * Cols;
end;

function TArrayObj.Get(K: Integer): TAxValue;
begin
  case ElemType of
    etBool:    Result := BoolValue(B[K]);
    etInt:     Result := IntValue(I[K]);
    etReal:    Result := RealValue(R[K]);
  else
    Result := ComplexValue(C[K]);
  end;
end;

procedure TArrayObj.Put(K: Integer; const V: TAxValue);
begin
  case ElemType of
    etBool: B[K] := V.B;
    etInt:
      if V.Kind = vkBool then I[K] := Ord(V.B) else I[K] := V.I;
    etReal:
      case V.Kind of
        vkBool: R[K] := Ord(V.B);
        vkInt:  R[K] := V.I;
      else
        R[K] := V.R;
      end;
    etComplex:
      case V.Kind of
        vkBool:    C[K] := Cx(Ord(V.B), 0);
        vkInt:     C[K] := Cx(V.I, 0);
        vkReal:    C[K] := Cx(V.R, 0);
      else
        C[K] := V.C;
      end;
  end;
end;

function TArrayObj.Clone: TArrayObj;
begin
  Result := TArrayObj.Create(ElemType, 0, 0, IsVector);
  Result.Rows := Rows;
  Result.Cols := Cols;
  Result.B := Copy(B);
  Result.I := Copy(I);
  Result.R := Copy(R);
  Result.C := Copy(C);
  Inc(ArrayCopies);
end;

procedure TArrayObj.Widen(T: TElemType);
var
  K, N: Integer;
  Old: TArrayObj;
begin
  if T <= ElemType then
    Exit;
  N := Count;
  // Read the old elements through a temporary holder, then switch storage.
  Old := TArrayObj.Create(ElemType, 0, 0, IsVector);
  try
    Old.Rows := Rows;
    Old.Cols := Cols;
    Old.B := B;
    Old.I := I;
    Old.R := R;
    Old.C := C;
    B := nil;
    I := nil;
    R := nil;
    C := nil;
    ElemType := T;
    case T of
      etInt:     SetLength(I, N);
      etReal:    SetLength(R, N);
      etComplex: SetLength(C, N);
    end;
    for K := 0 to N - 1 do
      Put(K, Old.Get(K));
  finally
    Old.Free;
  end;
end;

function AsArray(const V: TAxValue): TArrayObj;
begin
  Result := TArrayObj(V.Obj);
end;

function ArrayValue(A: TArrayObj): TAxValue;
begin
  Result := NothingValue;
  Result.Kind := vkArray;
  Result.Obj := A;
end;

function ElemTypeName(T: TElemType): string;
const
  Names: array[TElemType] of string = ('bool', 'int', 'real', 'complex');
begin
  Result := Names[T];
end;

function ElemTypeOf(const V: TAxValue): TElemType;
begin
  case V.Kind of
    vkBool: Result := etBool;
    vkInt:  Result := etInt;
    vkReal: Result := etReal;
  else
    Result := etComplex;
  end;
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

function TRecordTypeObj.IndexOf(const Field: string): Integer;
begin
  for Result := 0 to High(FieldNames) do
    if FieldNames[Result] = Field then
      Exit;
  Result := -1;
end;

function TRecordObj.Clone: TRecordObj;
begin
  Result := TRecordObj.Create;
  Result.Names := Copy(Names);
  Result.Values := Copy(Values);
  Result.DeclType := DeclType;
  Result.DeclRef := DeclRef;
end;

{ ---- dictionaries ---- }

constructor TDictObj.Create;
begin
  inherited Create;
  FIndex := TDictionary<string, Integer>.Create;
end;

destructor TDictObj.Destroy;
begin
  FIndex.Free;
  inherited;
end;

class function TDictObj.KeyOf(const K: TAxValue): string;
const
  TwoPow63 = 9223372036854775808.0;
var
  X: Double;
begin
  case K.Kind of
    vkString: Result := 's' + AsString(K);
    vkBool:   Result := 'n' + IntToStr(Ord(K.B));
    vkInt:    Result := 'n' + IntToStr(K.I);
    vkReal:
      begin
        X := K.R;
        if IsNan(X) then
          raise EAxonError.Create(TypeError, 'NaN cannot be a dictionary key');
        // A whole real is the same key as the equal int.
        if (Frac(X) = 0) and (X < TwoPow63) and (X >= -TwoPow63) then
          Result := 'n' + IntToStr(Trunc(X))
        else
          Result := 'r' + IntToHex(PInt64(@X)^, 16);
      end;
  else
    raise EAxonError.Create(TypeError, Format(
      'dictionary keys must be strings or real numbers, got %s', [TypeName(K)]));
  end;
end;

function TDictObj.Find(const K: TAxValue): Integer;
begin
  if not FIndex.TryGetValue(KeyOf(K), Result) then
    Result := -1;
end;

procedure TDictObj.Put(const K, V: TAxValue);
var
  Key: string;
  P: Integer;
begin
  Key := KeyOf(K);
  if FIndex.TryGetValue(Key, P) then
    Values[P] := V
  else
  begin
    FIndex.Add(Key, Length(Keys));
    Keys := Keys + [K];
    Values := Values + [V];
  end;
end;

function TDictObj.Clone: TDictObj;
var
  P: TPair<string, Integer>;
begin
  Result := TDictObj.Create;
  Result.Keys := Copy(Keys);
  Result.Values := Copy(Values);
  for P in FIndex do
    Result.FIndex.Add(P.Key, P.Value);
end;

function AsDict(const V: TAxValue): TDictObj;
begin
  Result := TDictObj(V.Obj);
end;

function DictValue(D: TDictObj): TAxValue;
begin
  Result := NothingValue;
  Result.Kind := vkDict;
  Result.Obj := D;
end;

function AsRecordType(const V: TAxValue): TRecordTypeObj;
begin
  Result := TRecordTypeObj(V.Obj);
end;

procedure MakeUnique(var V: TAxValue);
begin
  if (V.Obj = nil) or (TInterfacedObject(V.Obj).RefCount <= 1) then
    Exit;
  case V.Kind of
    vkList:   V := ListValue(Copy(AsList(V).Items));
    vkRecord:
      begin
        V.Obj := AsRecord(V).Clone;
      end;
    vkDict:   V.Obj := AsDict(V).Clone;
    vkArray:  V.Obj := AsArray(V).Clone;
  end;
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
    'complex', 'string', 'range', 'function', 'function', 'list', 'record', '',
    'dict', 'type');
begin
  if V.Kind = vkArray then
  begin
    if AsArray(V).IsVector then Result := 'vector' else Result := 'matrix';
  end
  else if (V.Kind = vkRecord) and (AsRecord(V).DeclType <> nil) then
    Result := AsRecord(V).DeclType.Name
  else
    Result := Names[V.Kind];
end;

function FormatReal(X: Double; Digits: Integer): string;
var
  S, Mantissa, Ds: string;
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
    Ds := '0'
  else
  begin
    // Round to Digits significant digits: d.ddd...E+xxx
    S := FormatFloat('0.' + StringOfChar('0', Digits - 1) + 'E+000', X,
      TFormatSettings.Invariant);
    P := Pos('E', S);
    Mantissa := Copy(S, 1, P - 1);
    E := StrToInt(Copy(S, P + 1, MaxInt));
    Ds := Mantissa.Replace('.', '');
    // Drop trailing zeros, keeping at least one digit.
    while (Length(Ds) > 1) and (Ds[Length(Ds)] = '0') do
      Delete(Ds, Length(Ds), 1);
  end;

  if X = 0 then
    Result := '0.0'
  else if (E < -4) or (E >= 15) then
  begin
    Result := Ds[1] + '.';
    if Length(Ds) > 1 then
      Result := Result + Copy(Ds, 2, MaxInt)
    else
      Result := Result + '0';
    Result := Result + 'e' + IntToStr(E);
  end
  else if E >= 0 then
  begin
    // E + 1 digits before the point.
    if Length(Ds) <= E + 1 then
      Result := Ds + StringOfChar('0', E + 1 - Length(Ds)) + '.0'
    else
      Result := Copy(Ds, 1, E + 1) + '.' + Copy(Ds, E + 2, MaxInt);
  end
  else
    Result := '0.' + StringOfChar('0', -E - 1) + Ds;

  if Neg then
    Result := '-' + Result;
end;

function FormatComplex(const C: TComplex; Digits: Integer = 15): string;
var
  ImNeg: Boolean;
begin
  ImNeg := (not IsNan(C.Im)) and ((C.Im < 0) or ((C.Im = 0) and (PUInt64(@C.Im)^ shr 63 = 1)));
  Result := FormatReal(C.Re, Digits);
  if ImNeg then
    Result := Result + ' - ' + FormatReal(-C.Im, Digits) + 'i'
  else
    Result := Result + ' + ' + FormatReal(C.Im, Digits) + 'i';
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

const
  ArrayDigits = 6;     // significant digits of array elements
  MaxRowsShown = 10;   // more rows than this are elided
  MaxColsShown = 8;    // more columns than this are elided
  EdgeRows = 5;
  EdgeCols = 4;

function ElementText(A: TArrayObj; K: Integer): string;
begin
  case A.ElemType of
    etBool:    if A.B[K] then Result := 'true' else Result := 'false';
    etInt:     Result := IntToStr(A.I[K]);
    etReal:    Result := FormatReal(A.R[K], ArrayDigits);
  else
    Result := FormatComplex(A.C[K], ArrayDigits);
  end;
end;

function ArrayHeader(A: TArrayObj): string;
begin
  if A.IsVector then
    Result := Format('%d-vector{%s}', [A.Rows, ElemTypeName(A.ElemType)])
  else
    Result := Format('%d' + #$00D7 + '%d matrix{%s}', [A.Rows, A.Cols, ElemTypeName(A.ElemType)]);
end;

{ Indices shown along a dimension of length N: all of them, or the first and
  last Edge with -1 marking the elision. }
function ShownIndices(N, MaxShown, Edge: Integer): TArray<Integer>;
var
  K: Integer;
begin
  Result := nil;
  if N <= MaxShown then
  begin
    SetLength(Result, N);
    for K := 0 to N - 1 do
      Result[K] := K;
  end
  else
  begin
    for K := 0 to Edge - 1 do
      Result := Result + [K];
    Result := Result + [-1];
    for K := N - Edge to N - 1 do
      Result := Result + [K];
  end;
end;

{ The multi-line display: header, then right-aligned columns. }
function FormatArrayBlock(A: TArrayObj): string;
var
  RowIdx, ColIdx: TArray<Integer>;
  Cells: array of array of string;
  Widths: TArray<Integer>;
  RI, CI, W: Integer;
  SB: TStringBuilder;
  S: string;
begin
  Result := ArrayHeader(A);
  if A.Count = 0 then
    Exit;
  RowIdx := ShownIndices(A.Rows, MaxRowsShown, EdgeRows);
  ColIdx := ShownIndices(A.Cols, MaxColsShown, EdgeCols);
  SetLength(Cells, Length(RowIdx), Length(ColIdx));
  SetLength(Widths, Length(ColIdx));
  for RI := 0 to High(RowIdx) do
    for CI := 0 to High(ColIdx) do
    begin
      if (RowIdx[RI] < 0) or (ColIdx[CI] < 0) then
        S := '' + #$2026 + ''
      else
        S := ElementText(A, ColIdx[CI] * A.Rows + RowIdx[RI]);
      Cells[RI][CI] := S;
      if (RowIdx[RI] >= 0) and (Length(S) > Widths[CI]) then
        Widths[CI] := Length(S);
    end;
  SB := TStringBuilder.Create;
  try
    SB.Append(Result);
    for RI := 0 to High(RowIdx) do
    begin
      SB.Append(sLineBreak);
      if RowIdx[RI] < 0 then
      begin
        SB.Append('  ' + #$22EE + '');
        Continue;
      end;
      for CI := 0 to High(ColIdx) do
      begin
        W := Widths[CI];
        S := Cells[RI][CI];
        SB.Append('  ').Append(StringOfChar(' ', W - Length(S))).Append(S);
      end;
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

{ The inline display used inside lists and records: literal syntax. }
function FormatArrayInline(A: TArrayObj): string;
var
  RI, CI: Integer;
begin
  Result := '[';
  for RI := 0 to A.Rows - 1 do
  begin
    if RI > 0 then
      Result := Result + '; ';
    for CI := 0 to A.Cols - 1 do
    begin
      if CI > 0 then
        Result := Result + ', ';
      Result := Result + ElementText(A, CI * A.Rows + RI);
    end;
  end;
  Result := Result + ']';
end;

function DisplayValue(const V: TAxValue; Quoted, Nested: Boolean): string; forward;

function FormatList(L: TListObj): string;
var
  I: Integer;
begin
  Result := '{';
  for I := 0 to High(L.Items) do
  begin
    if I > 0 then
      Result := Result + ', ';
    // Strings inside containers are always quoted; arrays are inline.
    Result := Result + DisplayValue(L.Items[I], True, True);
  end;
  Result := Result + '}';
end;

function FormatDict(D: TDictObj): string;
var
  I: Integer;
begin
  Result := 'dict(';
  for I := 0 to High(D.Keys) do
  begin
    if I > 0 then
      Result := Result + ', ';
    Result := Result + DisplayValue(D.Keys[I], True, True) + ' => ' +
      DisplayValue(D.Values[I], True, True);
  end;
  Result := Result + ')';
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
    Result := Result + R.Names[I] + ': ' + DisplayValue(R.Values[I], True, True);
  end;
  Result := Result + '}';
end;

function DisplayValue(const V: TAxValue; Quoted, Nested: Boolean): string;
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
    vkDict:    Result := FormatDict(AsDict(V));
    vkRecordType: Result := 'record type ' + AsRecordType(V).Name;
    vkArray:
      if Nested then
        Result := FormatArrayInline(AsArray(V))
      else
        Result := FormatArrayBlock(AsArray(V));
  else
    Result := '<value>';
  end;
end;

function Display(const V: TAxValue; Quoted: Boolean): string;
begin
  Result := DisplayValue(V, Quoted, False);
end;

end.
