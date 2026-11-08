unit Axon.Json;

(* JSON text from Axon values and back, for io.write_json / io.read_json and
   for the figure data graphics.show writes for the IDE.

   Writing: nothing is null; bool, int and real are JSON literals (reals with
   the shortest of 15 or 17 significant digits that reads back exactly; NaN
   and Inf, which JSON lacks, are null); strings are escaped; lists and
   ranges are arrays; records, and dictionaries whose keys are strings, are
   objects (in field or insertion order); a vector is an array of numbers and
   a matrix an array of its rows. Complex numbers, sparse matrices, functions
   and other values raise TypeError.

   Reading: null is nothing, true/false are bools, a number without a point
   or exponent that fits in 64 bits is an int and any other number a real
   (read with TryDecimalToDouble, so exactly); an array of numbers (and
   nulls, as NaN) is a vector, an array of such arrays of one length is a
   matrix, and any other array a list; an object is a record when every key
   is a valid name, and a dictionary otherwise. *)

interface

uses
  Axon.Values;

function ValueToJson(const V: TAxValue; const Fn: string): string;
function JsonToValue(const Text: string; const Fn: string): TAxValue;

implementation

uses
  System.SysUtils, System.Math, System.JSON, System.Character,
  Axon.Errors, Axon.Ops, Axon.FloatParse;

{ ---- writing ---- }

procedure AppendString(SB: TStringBuilder; const S: string);
var
  C: Char;
begin
  SB.Append('"');
  for C in S do
    case C of
      '"': SB.Append('\"');
      '\': SB.Append('\\');
      #8: SB.Append('\b');
      #9: SB.Append('\t');
      #10: SB.Append('\n');
      #12: SB.Append('\f');
      #13: SB.Append('\r');
    else
      if C < ' ' then
        SB.Append('\u').Append(IntToHex(Ord(C), 4))
      else
        SB.Append(C);
    end;
  SB.Append('"');
end;

procedure AppendReal(SB: TStringBuilder; X: Double);
var
  S: string;
  Back: Double;
begin
  if IsNan(X) or IsInfinite(X) then
  begin
    SB.Append('null');
    Exit;
  end;
  // The shortest common precision that reads back to the same double.
  S := FloatToStrF(X, ffGeneral, 15, 0, TFormatSettings.Invariant);
  if not TryDecimalToDouble(S.Replace('E', 'e'), Back) or (Back <> X) then
    S := FloatToStrF(X, ffGeneral, 17, 0, TFormatSettings.Invariant);
  // ffGeneral gives forms such as 1.5E-5, which JSON accepts. A whole number
  // gets ".0", so that it reads back as a real rather than an int.
  if S.IndexOfAny(['.', 'E']) < 0 then
    S := S + '.0';
  SB.Append(S);
end;

procedure AppendValue(SB: TStringBuilder; const V: TAxValue; const Fn: string); forward;

procedure AppendElement(SB: TStringBuilder; A: TArrayObj; K: Integer; const Fn: string);
begin
  case A.ElemType of
    etBool: if A.B[K] then SB.Append('true') else SB.Append('false');
    etInt: SB.Append(A.I[K]);
    etReal: AppendReal(SB, A.R[K]);
  else
    RaiseFmt(TypeError, '%s cannot write complex numbers as JSON', [Fn]);
  end;
end;

procedure AppendArray(SB: TStringBuilder; A: TArrayObj; const Fn: string);
var
  I, J: Integer;
begin
  SB.Append('[');
  if A.IsVector then
    for I := 0 to A.Rows - 1 do
    begin
      if I > 0 then SB.Append(',');
      AppendElement(SB, A, I, Fn);
    end
  else
    for I := 0 to A.Rows - 1 do
    begin
      if I > 0 then SB.Append(',');
      SB.Append('[');
      for J := 0 to A.Cols - 1 do
      begin
        if J > 0 then SB.Append(',');
        AppendElement(SB, A, J * A.Rows + I, Fn);   // column-major storage
      end;
      SB.Append(']');
    end;
  SB.Append(']');
end;

procedure AppendValue(SB: TStringBuilder; const V: TAxValue; const Fn: string);
var
  K: Integer;
  R: TRecordObj;
  D: TDictObj;
  L: TListObj;
  G: TRangeObj;
begin
  case V.Kind of
    vkNothing: SB.Append('null');
    vkBool: if V.B then SB.Append('true') else SB.Append('false');
    vkInt: SB.Append(V.I);
    vkReal: AppendReal(SB, V.R);
    vkString: AppendString(SB, AsString(V));
    vkList:
      begin
        L := AsList(V);
        SB.Append('[');
        for K := 0 to High(L.Items) do
        begin
          if K > 0 then SB.Append(',');
          AppendValue(SB, L.Items[K], Fn);
        end;
        SB.Append(']');
      end;
    vkRecord:
      begin
        R := AsRecord(V);
        SB.Append('{');
        for K := 0 to High(R.Names) do
        begin
          if K > 0 then SB.Append(',');
          AppendString(SB, R.Names[K]);
          SB.Append(':');
          AppendValue(SB, R.Values[K], Fn);
        end;
        SB.Append('}');
      end;
    vkDict:
      begin
        D := AsDict(V);
        SB.Append('{');
        for K := 0 to High(D.Keys) do
        begin
          if D.Keys[K].Kind <> vkString then
            RaiseFmt(TypeError, '%s needs string keys to write a dictionary as JSON, got %s',
              [Fn, TypeName(D.Keys[K])]);
          if K > 0 then SB.Append(',');
          AppendString(SB, AsString(D.Keys[K]));
          SB.Append(':');
          AppendValue(SB, D.Values[K], Fn);
        end;
        SB.Append('}');
      end;
    vkArray: AppendArray(SB, AsArray(V), Fn);
    vkRange:
      begin
        G := AsRange(V);
        SB.Append('[');
        for K := 0 to G.Count - 1 do
        begin
          if K > 0 then SB.Append(',');
          AppendValue(SB, G.ItemAt(K), Fn);
        end;
        SB.Append(']');
      end;
  else
    RaiseFmt(TypeError, '%s cannot write %s as JSON', [Fn, TypeName(V)]);
  end;
end;

function ValueToJson(const V: TAxValue; const Fn: string): string;
var
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    AppendValue(SB, V, Fn);
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

{ ---- reading ---- }

function IsName(const S: string): Boolean;
var
  K: Integer;
begin
  Result := (S <> '') and (S[1].IsLetter or (S[1] = '_')) and (Ord(S[1]) < 128);
  if Result then
    for K := 2 to Length(S) do
      if not ((Ord(S[K]) < 128) and (S[K].IsLetterOrDigit or (S[K] = '_'))) then
        Exit(False);
end;

function NumberValue(const S: string; const Fn: string): TAxValue;
var
  I: Int64;
  D: Double;
begin
  if (S.IndexOfAny(['.', 'e', 'E']) < 0) and TryStrToInt64(S, I) then
    Exit(IntValue(I));
  if not TryDecimalToDouble(S.TrimLeft(['-']), D) then
    RaiseFmt(IOError, '%s: invalid JSON number %s', [Fn, S]);
  if S.StartsWith('-') then
    D := -D;
  Result := RealValue(D);
end;

function FromJson(J: TJSONValue; const Fn: string): TAxValue; forward;

{ An array of numbers (nulls as NaN), or nil. }
function NumberArray(A: TJSONArray; out AllInt: Boolean; const Fn: string): TAxValues;
var
  K: Integer;
  E: TJSONValue;
begin
  Result := nil;
  AllInt := True;
  if A.Count = 0 then
    Exit;
  SetLength(Result, A.Count);
  for K := 0 to A.Count - 1 do
  begin
    E := A.Items[K];
    if E is TJSONNumber then
      Result[K] := NumberValue(E.Value, Fn)
    else if E is TJSONNull then
      Result[K] := RealValue(NaN)
    else
      Exit(nil);
    if Result[K].Kind <> vkInt then
      AllInt := False;
  end;
end;

function ArrayValueOf(A: TJSONArray; const Fn: string): TAxValue;
var
  Nums: TAxValues;
  Rows: array of TAxValues;
  AllInt, RowInt, IsMatrix: Boolean;
  K, J, N: Integer;
  Arr: TArrayObj;
  Items: TAxValues;
begin
  Nums := NumberArray(A, AllInt, Fn);
  if Nums <> nil then
  begin
    if AllInt then
      Arr := TArrayObj.Create(etInt, Length(Nums), 1, True)
    else
      Arr := TArrayObj.Create(etReal, Length(Nums), 1, True);
    for K := 0 to High(Nums) do
      if AllInt then
        Arr.I[K] := Nums[K].I
      else if Nums[K].Kind = vkInt then
        Arr.R[K] := Nums[K].I
      else
        Arr.R[K] := Nums[K].R;
    Exit(ArrayValue(Arr));
  end;
  // Rows of numbers, all of one length: a matrix.
  IsMatrix := A.Count > 0;
  AllInt := True;
  N := -1;
  SetLength(Rows, A.Count);
  for K := 0 to A.Count - 1 do
  begin
    if not (A.Items[K] is TJSONArray) then
    begin
      IsMatrix := False;
      Break;
    end;
    Rows[K] := NumberArray(TJSONArray(A.Items[K]), RowInt, Fn);
    if (Rows[K] = nil) or ((N >= 0) and (Length(Rows[K]) <> N)) then
    begin
      IsMatrix := False;
      Break;
    end;
    N := Length(Rows[K]);
    AllInt := AllInt and RowInt;
  end;
  if IsMatrix then
  begin
    if AllInt then
      Arr := TArrayObj.Create(etInt, A.Count, N, False)
    else
      Arr := TArrayObj.Create(etReal, A.Count, N, False);
    for K := 0 to A.Count - 1 do
      for J := 0 to N - 1 do
        if AllInt then
          Arr.I[J * A.Count + K] := Rows[K][J].I
        else if Rows[K][J].Kind = vkInt then
          Arr.R[J * A.Count + K] := Rows[K][J].I
        else
          Arr.R[J * A.Count + K] := Rows[K][J].R;
    Exit(ArrayValue(Arr));
  end;
  SetLength(Items, A.Count);
  for K := 0 to A.Count - 1 do
    Items[K] := FromJson(A.Items[K], Fn);
  Result := ListValue(Items);
end;

function ObjectValueOf(O: TJSONObject; const Fn: string): TAxValue;
var
  K: Integer;
  Names: TArray<string>;
  Values: TAxValues;
  Records: Boolean;
  D: TDictObj;
begin
  Records := True;
  for K := 0 to O.Count - 1 do
    if not IsName(O.Pairs[K].JsonString.Value) then
      Records := False;
  if Records then
  begin
    SetLength(Names, O.Count);
    SetLength(Values, O.Count);
    for K := 0 to O.Count - 1 do
    begin
      Names[K] := O.Pairs[K].JsonString.Value;
      Values[K] := FromJson(O.Pairs[K].JsonValue, Fn);
    end;
    Exit(RecordValue(Names, Values));
  end;
  D := TDictObj.Create;
  Result := DictValue(D);
  for K := 0 to O.Count - 1 do
    D.Put(StringValue(O.Pairs[K].JsonString.Value), FromJson(O.Pairs[K].JsonValue, Fn));
end;

function FromJson(J: TJSONValue; const Fn: string): TAxValue;
begin
  if (J = nil) or (J is TJSONNull) then
    Result := NothingValue
  else if J is TJSONTrue then
    Result := BoolValue(True)
  else if J is TJSONFalse then
    Result := BoolValue(False)
  else if J is TJSONNumber then
    Result := NumberValue(J.Value, Fn)
  else if J is TJSONString then
    Result := StringValue(J.Value)
  else if J is TJSONArray then
    Result := ArrayValueOf(TJSONArray(J), Fn)
  else if J is TJSONObject then
    Result := ObjectValueOf(TJSONObject(J), Fn)
  else
    RaiseFmt(IOError, '%s: unsupported JSON value', [Fn]);
end;

function JsonToValue(const Text: string; const Fn: string): TAxValue;
var
  J: TJSONValue;
begin
  J := TJSONObject.ParseJSONValue(Text, False, False);
  if J = nil then
    RaiseFmt(IOError, '%s: the text is not valid JSON', [Fn]);
  try
    Result := FromJson(J, Fn);
  finally
    J.Free;
  end;
end;

end.
