unit Axon.Builtins;

(* Prelude functions on scalars (M3).

   Elementary functions are type-stable: a real argument gives a real result
   (NaN outside the real domain), and only a complex argument gives a complex
   result. Array forms arrive in M6. *)

interface

uses
  System.SysUtils,
  Axon.Values;

{ Calls Define once for every prelude function. }
procedure DefineBuiltins(const Define: TProc<string, TAxValue>);

implementation

uses
  System.Math, System.Character,
  Axon.Errors, Axon.Complex, Axon.Ops, Axon.Arrays, Axon.Tokens, Axon.Ffi, Axon.Sparse;

type
  TRealFn = function(X: Double): Double;
  TComplexFn = function(const Z: TComplex): TComplex;

{ ---- argument helpers ---- }

procedure NeedNumber(const Fn: string; const V: TAxValue);
begin
  if NumRank(V) < 0 then
    RaiseFmt(TypeError, '%s needs a number, got %s', [Fn, TypeName(V)]);
end;

procedure NeedRealNumber(const Fn: string; const V: TAxValue);
begin
  NeedNumber(Fn, V);
  if V.Kind = vkComplex then
    RaiseFmt(TypeError, '%s needs a real number, got complex', [Fn]);
end;

function ApplyElementary(const Fn: string; const V: TAxValue; RF: TRealFn;
  CF: TComplexFn): TAxValue;
begin
  if IsArrayLike(V) then
    Exit(MapArray(V,
      function(const X: TAxValue): TAxValue
      begin
        Result := ApplyElementary(Fn, X, RF, CF);
      end));
  NeedNumber(Fn, V);
  if V.Kind = vkComplex then
    Result := ComplexValue(CF(V.C))
  else
    Result := RealValue(RF(ToReal(V)));
end;

{ Converts a whole-valued double to Int64, raising on NaN or overflow. }
function DoubleToInt(const Fn: string; X: Double): Int64;
const
  TwoPow63 = 9223372036854775808.0;
begin
  if IsNan(X) then
    RaiseFmt(DomainError, '%s of NaN has no int value', [Fn]);
  if (X >= TwoPow63) or (X < -TwoPow63) then
    RaiseFmt(OverflowError, '%s: %s is outside the int range', [Fn, FormatReal(X)]);
  Result := Trunc(X);
end;

{ ---- real versions of the elementary functions ---- }

function RSqrt(X: Double): Double; begin Result := Sqrt(X); end;
function RExp(X: Double): Double; begin Result := Exp(X); end;
function RLog(X: Double): Double;
begin
  if X < 0 then Result := NaN else Result := Ln(X);
end;
function RSin(X: Double): Double; begin Result := Sin(X); end;
function RCos(X: Double): Double; begin Result := Cos(X); end;
function RTan(X: Double): Double; begin Result := Tan(X); end;
function RAsin(X: Double): Double;
begin
  if Abs(X) > 1 then Result := NaN else Result := ArcSin(X);
end;
function RAcos(X: Double): Double;
begin
  if Abs(X) > 1 then Result := NaN else Result := ArcCos(X);
end;
function RAtan(X: Double): Double; begin Result := ArcTan(X); end;
function RSinh(X: Double): Double; begin Result := Sinh(X); end;
function RCosh(X: Double): Double; begin Result := Cosh(X); end;
function RTanh(X: Double): Double;
begin
  // Math.Tanh overflows for large |X|; the limit is +-1.
  if X > 20 then Result := 1
  else if X < -20 then Result := -1
  else Result := Tanh(X);
end;
function RAsinh(X: Double): Double; begin Result := ArcSinh(X); end;
function RAcosh(X: Double): Double;
begin
  if X < 1 then Result := NaN else Result := ArcCosh(X);
end;
function RAtanh(X: Double): Double;
begin
  if Abs(X) > 1 then Result := NaN
  else if X = 1 then Result := Infinity
  else if X = -1 then Result := NegInfinity
  else Result := ArcTanh(X);
end;

{ ---- the builtins ---- }

function BPrint(const Args: TAxValues): TAxValue;
var
  I: Integer;
  S: string;
begin
  S := '';
  for I := 0 to High(Args) do
  begin
    if I > 0 then
      S := S + ' ';
    S := S + Display(Args[I]);
  end;
  Writeln(S);
  Result := NothingValue;
end;

function BError(const Args: TAxValues): TAxValue;
var
  Reraised: EAxonError;
begin
  if Length(Args) = 1 then
  begin
    // error(err): re-raise a caught error with its kind, message and trace.
    if Args[0].Kind = vkRecord then
    begin
      Reraised := ErrorFromValue(Args[0]);
      if Reraised = nil then
        RaiseError(TypeError, 'error(err) needs an error record with kind and message fields');
      raise Reraised;
    end;
    if Args[0].Kind <> vkString then
      RaiseFmt(TypeError, 'error needs a message string or an error record, got %s',
        [TypeName(Args[0])]);
    RaiseError(UserError, AsString(Args[0]));
  end;
  if (Args[0].Kind <> vkString) or (Args[1].Kind <> vkString) then
    RaiseError(TypeError, 'error(kind, message) needs two strings');
  RaiseError(AsString(Args[0]), AsString(Args[1]));
  Result := NothingValue;
end;

{ length of a list, a string (in characters, i.e. Unicode code points), a
  range or an array (all its elements). }
function BLength(const Args: TAxValues): TAxValue;
var
  S: string;
  I, N: Integer;
begin
  case Args[0].Kind of
    vkList:  Result := IntValue(Length(AsList(Args[0]).Items));
    vkRange: Result := IntValue(AsRange(Args[0]).Count);
    vkArray: Result := IntValue(AsArray(Args[0]).Count);
    vkDict:  Result := IntValue(Length(AsDict(Args[0]).Keys));
    vkSparse: Result := IntValue(AsSparse(Args[0]).Rows * AsSparse(Args[0]).Cols);
    vkString:
      begin
        S := AsString(Args[0]);
        N := 0;
        I := 1;
        while I <= Length(S) do
        begin
          if S[I].IsHighSurrogate and (I < Length(S)) then
            Inc(I);
          Inc(I);
          Inc(N);
        end;
        Result := IntValue(N);
      end;
  else
    RaiseFmt(TypeError, 'length is not defined for %s', [TypeName(Args[0])]);
  end;
end;

function BString(const Args: TAxValues): TAxValue;
begin
  Result := StringValue(Display(Args[0]));
end;

function BTypeof(const Args: TAxValues): TAxValue;
begin
  Result := StringValue(TypeName(Args[0]));
end;

function BSqrt(const Args: TAxValues): TAxValue;
begin Result := ApplyElementary('sqrt', Args[0], RSqrt, CSqrt); end;
function BExp(const Args: TAxValues): TAxValue;
begin Result := ApplyElementary('exp', Args[0], RExp, CExp); end;
function BLog(const Args: TAxValues): TAxValue;
begin Result := ApplyElementary('log', Args[0], RLog, CLog); end;
function BSin(const Args: TAxValues): TAxValue;
begin Result := ApplyElementary('sin', Args[0], RSin, CSin); end;
function BCos(const Args: TAxValues): TAxValue;
begin Result := ApplyElementary('cos', Args[0], RCos, CCos); end;
function BTan(const Args: TAxValues): TAxValue;
begin Result := ApplyElementary('tan', Args[0], RTan, CTan); end;
function BAsin(const Args: TAxValues): TAxValue;
begin Result := ApplyElementary('asin', Args[0], RAsin, CAsin); end;
function BAcos(const Args: TAxValues): TAxValue;
begin Result := ApplyElementary('acos', Args[0], RAcos, CAcos); end;
function BAtan(const Args: TAxValues): TAxValue;
begin Result := ApplyElementary('atan', Args[0], RAtan, CAtan); end;
function BSinh(const Args: TAxValues): TAxValue;
begin Result := ApplyElementary('sinh', Args[0], RSinh, CSinh); end;
function BCosh(const Args: TAxValues): TAxValue;
begin Result := ApplyElementary('cosh', Args[0], RCosh, CCosh); end;
function BTanh(const Args: TAxValues): TAxValue;
begin Result := ApplyElementary('tanh', Args[0], RTanh, CTanh); end;
function BAsinh(const Args: TAxValues): TAxValue;
begin Result := ApplyElementary('asinh', Args[0], RAsinh, CAsinh); end;
function BAcosh(const Args: TAxValues): TAxValue;
begin Result := ApplyElementary('acosh', Args[0], RAcosh, CAcosh); end;
function BAtanh(const Args: TAxValues): TAxValue;
begin Result := ApplyElementary('atanh', Args[0], RAtanh, CAtanh); end;

function AbsValue(const V: TAxValue): TAxValue;
begin
  if IsArrayLike(V) then
    Exit(MapArray(V, AbsValue));
  NeedNumber('abs', V);
  case V.Kind of
    vkBool:    Result := IntValue(Ord(V.B));
    vkInt:     if V.I < 0 then Result := IntValue(CheckedNeg(V.I, 'abs')) else Result := V;
    vkReal:    Result := RealValue(Abs(V.R));
  else
    Result := RealValue(CAbs(V.C));
  end;
end;

function BAbs(const Args: TAxValues): TAxValue;
begin
  Result := AbsValue(Args[0]);
end;

function RoundingFn(const Fn: string; const V: TAxValue; Mode: Integer): TAxValue;
var
  X, F, D: Double;
begin
  if IsArrayLike(V) then
    Exit(MapArray(V,
      function(const E: TAxValue): TAxValue
      begin
        Result := RoundingFn(Fn, E, Mode);
      end));
  NeedRealNumber(Fn, V);
  if V.Kind = vkBool then
    Exit(IntValue(Ord(V.B)));
  if V.Kind = vkInt then
    Exit(V);
  X := V.R;
  F := Int(X);  // truncated toward zero, as a double
  case Mode of
    0: ; // int: truncate
    1: if F > X then F := F - 1;                        // floor
    2: if F < X then F := F + 1;                        // ceil
    3: begin                                            // round, halves away from zero
         D := X - F;
         if D >= 0.5 then F := F + 1
         else if D <= -0.5 then F := F - 1;
       end;
  end;
  Result := IntValue(DoubleToInt(Fn, F));
end;

function BInt(const Args: TAxValues): TAxValue;
begin Result := RoundingFn('int', Args[0], 0); end;
function BFloor(const Args: TAxValues): TAxValue;
begin Result := RoundingFn('floor', Args[0], 1); end;
function BCeil(const Args: TAxValues): TAxValue;
begin Result := RoundingFn('ceil', Args[0], 2); end;
function BRound(const Args: TAxValues): TAxValue;
begin Result := RoundingFn('round', Args[0], 3); end;

function BReal(const Args: TAxValues): TAxValue;
begin
  if IsArrayLike(Args[0]) then
    Exit(MapArray(Args[0], function(const X: TAxValue): TAxValue begin Result := BReal([X]) end));
  NeedNumber('real', Args[0]);
  if Args[0].Kind = vkComplex then
    Result := RealValue(Args[0].C.Re)
  else
    Result := RealValue(ToReal(Args[0]));
end;

function BImag(const Args: TAxValues): TAxValue;
begin
  if IsArrayLike(Args[0]) then
    Exit(MapArray(Args[0], function(const X: TAxValue): TAxValue begin Result := BImag([X]) end));
  NeedNumber('imag', Args[0]);
  if Args[0].Kind = vkComplex then
    Result := RealValue(Args[0].C.Im)
  else
    Result := RealValue(0);
end;

function BConj(const Args: TAxValues): TAxValue;
begin
  if IsArrayLike(Args[0]) then
    Exit(MapArray(Args[0], function(const X: TAxValue): TAxValue begin Result := BConj([X]) end));
  NeedNumber('conj', Args[0]);
  if Args[0].Kind = vkComplex then
    Result := ComplexValue(CConj(Args[0].C))
  else
    Result := Args[0];
end;

function BArg(const Args: TAxValues): TAxValue;
begin
  if IsArrayLike(Args[0]) then
    Exit(MapArray(Args[0], function(const X: TAxValue): TAxValue begin Result := BArg([X]) end));
  NeedNumber('arg', Args[0]);
  Result := RealValue(CArg(ToComplex(Args[0])));
end;

function BComplex(const Args: TAxValues): TAxValue;
begin
  if (Length(Args) = 1) and IsArrayLike(Args[0]) then
    Exit(MapArray(Args[0], function(const X: TAxValue): TAxValue begin Result := BComplex([X]) end));
  if (Length(Args) = 2) and (IsArrayLike(Args[0]) or IsArrayLike(Args[1])) then
    Exit(Broadcast2(Args[0], Args[1],
      function(const X, Y: TAxValue): TAxValue begin Result := BComplex([X, Y]) end, 'complex'));
  NeedNumber('complex', Args[0]);
  if Length(Args) = 1 then
    Exit(ComplexValue(ToComplex(Args[0])));
  NeedRealNumber('complex', Args[0]);
  NeedRealNumber('complex', Args[1]);
  Result := ComplexValue2(ToReal(Args[0]), ToReal(Args[1]));
end;

{ Floored division and modulo. Mode 0: div, 1: mod. }
function DivMod(const Fn: string; const A, B: TAxValue; Mode: Integer): TAxValue;
var
  X, Y, Q, R: Int64;
  RX, RY, RQ: Double;
begin
  if IsArrayLike(A) or IsArrayLike(B) then
    Exit(Broadcast2(A, B,
      function(const X1, Y1: TAxValue): TAxValue
      begin
        Result := DivMod(Fn, X1, Y1, Mode);
      end, Fn));
  NeedRealNumber(Fn, A);
  NeedRealNumber(Fn, B);
  if (NumRank(A) <= 1) and (NumRank(B) <= 1) then
  begin
    if A.Kind = vkBool then X := Ord(A.B) else X := A.I;
    if B.Kind = vkBool then Y := Ord(B.B) else Y := B.I;
    if Y = 0 then
      RaiseFmt(DomainError, '%s by zero', [Fn]);
    if (X = Low(Int64)) and (Y = -1) then
    begin
      if Mode = 1 then Exit(IntValue(0));
      RaiseFmt(OverflowError, 'integer overflow in %s', [Fn]);
    end;
    Q := X div Y;
    R := X mod Y;
    if (R <> 0) and ((R < 0) <> (Y < 0)) then
    begin
      Dec(Q);
      R := R + Y;
    end;
    if Mode = 0 then Result := IntValue(Q) else Result := IntValue(R);
    Exit;
  end;
  RX := ToReal(A);
  RY := ToReal(B);
  if RY = 0 then
    Exit(RealValue(NaN));
  RQ := Floor(RX / RY);
  if Mode = 0 then
    Result := RealValue(RQ)
  else
    Result := RealValue(RX - RQ * RY);
end;

function BDiv(const Args: TAxValues): TAxValue;
begin Result := DivMod('div', Args[0], Args[1], 0); end;
function BMod(const Args: TAxValues): TAxValue;
begin Result := DivMod('mod', Args[0], Args[1], 1); end;

function MinMax(const Fn: string; const A, B: TAxValue; WantMax: Boolean): TAxValue;
var
  X, Y: Double;
  IA, IB: Int64;
  TakeB: Boolean;
begin
  if IsArrayLike(A) or IsArrayLike(B) then
    Exit(Broadcast2(A, B,
      function(const X1, Y1: TAxValue): TAxValue
      begin
        Result := MinMax(Fn, X1, Y1, WantMax);
      end, Fn));
  NeedRealNumber(Fn, A);
  NeedRealNumber(Fn, B);
  if (NumRank(A) <= 1) and (NumRank(B) <= 1) then
  begin
    // Both bool or int: compare exactly as ints.
    if A.Kind = vkBool then IA := Ord(A.B) else IA := A.I;
    if B.Kind = vkBool then IB := Ord(B.B) else IB := B.I;
    if WantMax then TakeB := IB > IA else TakeB := IB < IA;
    if TakeB then Result := IntValue(IB) else Result := IntValue(IA);
    Exit;
  end;
  X := ToReal(A);
  Y := ToReal(B);
  if IsNan(X) or IsNan(Y) then
    Exit(RealValue(NaN));
  if WantMax then Result := RealValue(Max(X, Y)) else Result := RealValue(Min(X, Y));
end;

function ReduceMinMax(const Fn: string; const V: TAxValue; WantMax: Boolean): TAxValue;
var
  Holder: TAxValue;
  A: TArrayObj;
  K: Integer;
begin
  if not IsArrayLike(V) then
  begin
    NeedRealNumber(Fn, V);
    Exit(V);
  end;
  A := ToArray(V);
  Holder := ArrayValue(A);
  if A.Count = 0 then
    RaiseFmt(ArgumentError, '%s of an empty array', [Fn]);
  Result := A.Get(0);
  NeedRealNumber(Fn, Result);
  for K := 1 to A.Count - 1 do
    Result := MinMax(Fn, Result, A.Get(K), WantMax);
end;

function BMin(const Args: TAxValues): TAxValue;
begin
  if Length(Args) = 1 then
    Result := ReduceMinMax('min', Args[0], False)
  else
    Result := MinMax('min', Args[0], Args[1], False);
end;

function BMax(const Args: TAxValues): TAxValue;
begin
  if Length(Args) = 1 then
    Result := ReduceMinMax('max', Args[0], True)
  else
    Result := MinMax('max', Args[0], Args[1], True);
end;

function BFactorial(const Args: TAxValues): TAxValue;
var
  N, I, F: Int64;
begin
  if not (Args[0].Kind in [vkInt, vkBool]) then
    RaiseFmt(TypeError, 'factorial needs an int, got %s', [TypeName(Args[0])]);
  if Args[0].Kind = vkBool then N := Ord(Args[0].B) else N := Args[0].I;
  if N < 0 then
    RaiseFmt(DomainError, 'factorial of a negative number (%d)', [N]);
  F := 1;
  for I := 2 to N do
    F := CheckedMul(F, I, 'factorial');
  Result := IntValue(F);
end;

{ ---- array constructors and reductions (M6) ---- }

function SizeArg(const Fn: string; const V: TAxValue): Integer;
begin
  if not (V.Kind in [vkInt, vkBool]) then
    RaiseFmt(ArgumentError, '%s needs int sizes, got %s', [Fn, TypeName(V)]);
  if V.Kind = vkBool then Result := Ord(V.B)
  else
  begin
    if (V.I < 0) or (V.I > MaxInt div 2) then
      RaiseFmt(ArgumentError, '%s: invalid size %d', [Fn, V.I]);
    Result := V.I;
  end;
end;

function Filled(const Fn: string; const Args: TAxValues; Value: Double): TAxValue;
var
  A: TArrayObj;
  K: Integer;
begin
  if Length(Args) = 1 then
    A := TArrayObj.Create(etReal, SizeArg(Fn, Args[0]), 1, True)
  else
    A := TArrayObj.Create(etReal, SizeArg(Fn, Args[0]), SizeArg(Fn, Args[1]), False);
  Result := ArrayValue(A);
  if Value <> 0 then
    for K := 0 to A.Count - 1 do
      A.R[K] := Value;
end;

function BZeros(const Args: TAxValues): TAxValue;
begin Result := Filled('zeros', Args, 0); end;
function BOnes(const Args: TAxValues): TAxValue;
begin Result := Filled('ones', Args, 1); end;

function BEye(const Args: TAxValues): TAxValue;
var
  A: TArrayObj;
  M, N, K: Integer;
begin
  M := SizeArg('eye', Args[0]);
  if Length(Args) = 2 then N := SizeArg('eye', Args[1]) else N := M;
  A := TArrayObj.Create(etReal, M, N, False);
  Result := ArrayValue(A);
  for K := 0 to Min(M, N) - 1 do
    A.R[K * M + K] := 1;
end;

function BRand(const Args: TAxValues): TAxValue;
var
  A: TArrayObj;
  K: Integer;
begin
  if Length(Args) = 0 then
    Exit(RealValue(Random));
  if Length(Args) = 1 then
    A := TArrayObj.Create(etReal, SizeArg('rand', Args[0]), 1, True)
  else
    A := TArrayObj.Create(etReal, SizeArg('rand', Args[0]), SizeArg('rand', Args[1]), False);
  Result := ArrayValue(A);
  for K := 0 to A.Count - 1 do
    A.R[K] := Random;
end;

function BLinspace(const Args: TAxValues): TAxValue;
var
  A: TArrayObj;
  Lo, Hi: Double;
  N, K: Integer;
begin
  NeedRealNumber('linspace', Args[0]);
  NeedRealNumber('linspace', Args[1]);
  Lo := ToReal(Args[0]);
  Hi := ToReal(Args[1]);
  N := SizeArg('linspace', Args[2]);
  A := TArrayObj.Create(etReal, N, 1, True);
  Result := ArrayValue(A);
  for K := 0 to N - 1 do
    // The last point is exactly Hi.
    if K = N - 1 then
      A.R[K] := Hi
    else
      A.R[K] := Lo + (Hi - Lo) * K / (N - 1);
end;

{ size(A) returns two values; size(A, d) one. }
function BSize(const Args: TAxValues): TAxValues;
var
  R, C: Integer;
begin
  R := 1;
  C := 1;
  if Args[0].Kind = vkArray then
  begin
    R := AsArray(Args[0]).Rows;
    C := AsArray(Args[0]).Cols;
  end
  else if Args[0].Kind = vkRange then
    R := AsRange(Args[0]).Count
  else if Args[0].Kind = vkSparse then
  begin
    R := AsSparse(Args[0]).Rows;
    C := AsSparse(Args[0]).Cols;
  end
  else if NumRank(Args[0]) < 0 then
    RaiseFmt(TypeError, 'size is not defined for %s', [TypeName(Args[0])]);
  if Length(Args) = 1 then
  begin
    Result := [IntValue(R), IntValue(C)];
    Exit;
  end;
  if (Args[1].Kind <> vkInt) or (Args[1].I < 1) or (Args[1].I > 2) then
    RaiseError(ArgumentError, 'size(A, d) needs d = 1 or 2');
  if Args[1].I = 1 then Result := [IntValue(R)] else Result := [IntValue(C)];
end;

function DimArg(const Fn: string; const V: TAxValue): Integer;
begin
  if (V.Kind <> vkInt) or (V.I < 1) or (V.I > 2) then
    RaiseFmt(ArgumentError, '%s: the dimension must be 1 or 2', [Fn]);
  Result := V.I;
end;

function BSum(const Args: TAxValues): TAxValue;
begin
  if Length(Args) = 1 then
    Result := ReduceSum(Args[0])
  else
    Result := ReduceDim(Args[0], DimArg('sum', Args[1]), tkPlus);
end;

function BProd(const Args: TAxValues): TAxValue;
begin
  if Length(Args) = 1 then
    Result := ReduceProd(Args[0])
  else
    Result := ReduceDim(Args[0], DimArg('prod', Args[1]), tkStar);
end;

function BMean(const Args: TAxValues): TAxValue;
var
  N, D: Integer;
  A: TArrayObj;
  Holder: TAxValue;
begin
  if not IsArrayLike(Args[0]) then
  begin
    NeedNumber('mean', Args[0]);
    Exit(BinaryOp(tkSlash, Args[0], IntValue(1)));
  end;
  A := ToArray(Args[0]);
  Holder := ArrayValue(A);
  if Length(Args) = 1 then
    Exit(BinaryOp(tkSlash, ReduceSum(Holder), IntValue(A.Count)));
  D := DimArg('mean', Args[1]);
  if D = 1 then N := A.Rows else N := A.Cols;
  Result := BinaryOp(tkSlash, ReduceDim(Holder, D, tkPlus), IntValue(N));
end;

function AllAny(const Fn: string; const V: TAxValue; WantAll: Boolean): TAxValue;
var
  A: TArrayObj;
  K: Integer;
begin
  if V.Kind = vkBool then
    Exit(V);
  if V.Kind <> vkArray then
    RaiseFmt(TypeError, '%s needs a bool or a bool array, got %s', [Fn, TypeName(V)]);
  A := AsArray(V);
  if (A.ElemType <> etBool) and (A.Count > 0) then
    RaiseFmt(TypeError, '%s needs bool elements, got %s', [Fn, ElemTypeName(A.ElemType)]);
  for K := 0 to A.Count - 1 do
    if A.B[K] <> WantAll then
      Exit(BoolValue(not WantAll));
  Result := BoolValue(WantAll);
end;

function BAll(const Args: TAxValues): TAxValue;
begin Result := AllAny('all', Args[0], True); end;
function BAny(const Args: TAxValues): TAxValue;
begin Result := AllAny('any', Args[0], False); end;

{ dot(u, v): the sum of conj(u[k]) * v[k] over two vectors of equal length. }
function BDot(const Args: TAxValues): TAxValue;
var
  U, V: TArrayObj;
  HU, HV, X: TAxValue;
  K: Integer;
begin
  if not (IsArrayLike(Args[0]) and IsArrayLike(Args[1])) then
    RaiseError(TypeError, 'dot needs two vectors');
  U := ToArray(Args[0]);
  HU := ArrayValue(U);
  V := ToArray(Args[1]);
  HV := ArrayValue(V);
  if U.Count <> V.Count then
    RaiseFmt(DimensionError, 'dot: lengths %d and %d differ', [U.Count, V.Count]);
  if (U.ElemType = etComplex) or (V.ElemType = etComplex) then
    Result := ComplexValue2(0, 0)
  else if (U.ElemType = etReal) or (V.ElemType = etReal) then
    Result := RealValue(0)
  else
    Result := IntValue(0);
  for K := 0 to U.Count - 1 do
  begin
    X := U.Get(K);
    if X.Kind = vkComplex then
      X := ComplexValue(CConj(X.C));
    Result := BinaryOp(tkPlus, Result, BinaryOp(tkStar, X, V.Get(K)));
  end;
end;

{ adjoint(A): the conjugate transpose. }
function BAdjoint(const Args: TAxValues): TAxValue;
var
  A: TArrayObj;
  Holder: TAxValue;
begin
  if Args[0].Kind = vkSparse then
    Exit(SparseTranspose(AsSparse(Args[0]), True));
  if not IsArrayLike(Args[0]) then
    Exit(BConj(Args));
  A := ToArray(Args[0]);
  Holder := ArrayValue(A);
  Result := Transpose(A, True);
end;

function BIsequal(const Args: TAxValues): TAxValue;
begin
  Result := BoolValue(ValuesIdentical(Args[0], Args[1]));
end;

{ ---- sparse matrices (M11) ---- }

{ 1-based index values (an int, or an int vector or range) as 0-based ints. }
function IndexList(const Fn: string; const V: TAxValue): TArray<Integer>;
var
  A: TArrayObj;
  Holder: TAxValue;
  K: Integer;
begin
  if V.Kind = vkInt then
  begin
    Result := [V.I - 1];
    Exit;
  end;
  if not IsArrayLike(V) then
    RaiseFmt(TypeError, '%s needs int indices, got %s', [Fn, TypeName(V)]);
  A := ToArray(V);
  Holder := ArrayValue(A);
  if (A.ElemType <> etInt) and (A.Count > 0) then
    RaiseFmt(TypeError, '%s needs int indices, got %s elements', [Fn, ElemTypeName(A.ElemType)]);
  SetLength(Result, A.Count);
  for K := 0 to A.Count - 1 do
  begin
    if A.I[K] < 1 then
      RaiseFmt(IndexError, '%s: index %d is below 1', [Fn, A.I[K]]);
    Result[K] := A.I[K] - 1;
  end;
end;

{ sparse(A), sparse(i, j, v) or sparse(i, j, v, m, n). }
function BSparse(const Args: TAxValues): TAxValue;
var
  I, J: TArray<Integer>;
  V: TArray<TComplex>;
  Vals: TArrayObj;
  Holder: TAxValue;
  M, N, K: Integer;
  Cplx: Boolean;
begin
  if Length(Args) = 1 then
  begin
    case Args[0].Kind of
      vkSparse: Exit(Args[0]);
      vkArray, vkRange:
        begin
          Vals := ToArray(Args[0]);
          Holder := ArrayValue(Vals);
          Exit(SparseValue(SparseFromDense(Vals)));
        end;
    else
      RaiseFmt(TypeError, 'sparse needs a matrix, got %s', [TypeName(Args[0])]);
    end;
  end;
  if not (Length(Args) in [3, 5]) then
    RaiseError(ArgumentError, 'sparse takes A, (i, j, v) or (i, j, v, m, n)');
  I := IndexList('sparse', Args[0]);
  J := IndexList('sparse', Args[1]);
  if Length(I) <> Length(J) then
    RaiseFmt(DimensionError, 'sparse: %d row indices but %d column indices', [Length(I), Length(J)]);
  SetLength(V, Length(I));
  if IsArrayLike(Args[2]) then
  begin
    Vals := ToArray(Args[2]);
    Holder := ArrayValue(Vals);
    if Vals.Count <> Length(I) then
      RaiseFmt(DimensionError, 'sparse: %d indices but %d values', [Length(I), Vals.Count]);
    Cplx := Vals.ElemType = etComplex;
    for K := 0 to Vals.Count - 1 do
      V[K] := ToComplex(Vals.Get(K));
  end
  else
  begin
    NeedNumber('sparse', Args[2]);
    Cplx := Args[2].Kind = vkComplex;
    for K := 0 to High(V) do
      V[K] := ToComplex(Args[2]);
  end;
  if Length(Args) = 5 then
  begin
    M := SizeArg('sparse', Args[3]);
    N := SizeArg('sparse', Args[4]);
  end
  else
  begin
    M := 0;
    N := 0;
    for K := 0 to High(I) do
    begin
      M := Max(M, I[K] + 1);
      N := Max(N, J[K] + 1);
    end;
  end;
  for K := 0 to High(I) do
    if (I[K] >= M) or (J[K] >= N) then
      RaiseFmt(IndexError, 'sparse: index (%d, %d) is outside a %d' + #$00D7 + '%d matrix',
        [I[K] + 1, J[K] + 1, M, N]);
  Result := SparseValue(FromTriplets(M, N, I, J, V, Cplx));
end;

function BSpeye(const Args: TAxValues): TAxValue;
var
  M, N: Integer;
begin
  M := SizeArg('speye', Args[0]);
  if Length(Args) = 2 then N := SizeArg('speye', Args[1]) else N := M;
  Result := SparseIdentity(M, N);
end;

function BNnz(const Args: TAxValues): TAxValue;
var
  A: TArrayObj;
  Holder: TAxValue;
  K, N: Integer;
  X: TComplex;
begin
  if Args[0].Kind = vkSparse then
    Exit(IntValue(AsSparse(Args[0]).Nnz));
  if NumRank(Args[0]) >= 0 then
  begin
    X := ToComplex(Args[0]);
    Exit(IntValue(Ord((X.Re <> 0) or (X.Im <> 0))));
  end;
  if not IsArrayLike(Args[0]) then
    RaiseFmt(TypeError, 'nnz needs a matrix, got %s', [TypeName(Args[0])]);
  A := ToArray(Args[0]);
  Holder := ArrayValue(A);
  N := 0;
  for K := 0 to A.Count - 1 do
  begin
    X := ToComplex(A.Get(K));
    if (X.Re <> 0) or (X.Im <> 0) then
      Inc(N);
  end;
  Result := IntValue(N);
end;

function BFull(const Args: TAxValues): TAxValue;
begin
  Result := Densify(Args[0]);
end;

{ splu(S): the sparse factors [L, U] with S = L * U. }
function BSplu(const Args: TAxValues): TAxValues;
begin
  if Args[0].Kind <> vkSparse then
    RaiseFmt(TypeError, 'splu needs a sparse matrix, got %s', [TypeName(Args[0])]);
  Result := SparseLUFactors(AsSparse(Args[0]));
end;

{ ---- shape helpers (M10) ---- }

function BEltype(const Args: TAxValues): TAxValue;
begin
  case Args[0].Kind of
    vkArray: Result := StringValue(ElemTypeName(AsArray(Args[0]).ElemType));
    vkSparse:
      if AsSparse(Args[0]).IsComplex then Result := StringValue('complex') else Result := StringValue('real');
    vkRange:
      if AsRange(Args[0]).IsInt then Result := StringValue('int') else Result := StringValue('real');
  else
    if NumRank(Args[0]) < 0 then
      RaiseFmt(TypeError, 'eltype needs an array or a number, got %s', [TypeName(Args[0])]);
    Result := StringValue(TypeName(Args[0]));
  end;
end;

{ reshape(A, m, n) and reshape(A, n): the same elements, column-major. }
function BReshape(const Args: TAxValues): TAxValue;
var
  A, R: TArrayObj;
  Holder: TAxValue;
  M, N, K: Integer;
  IsVec: Boolean;
begin
  if not IsArrayLike(Args[0]) then
    RaiseFmt(TypeError, 'reshape needs an array, got %s', [TypeName(Args[0])]);
  A := ToArray(Args[0]);
  Holder := ArrayValue(A);
  M := SizeArg('reshape', Args[1]);
  IsVec := Length(Args) = 2;
  if IsVec then N := 1 else N := SizeArg('reshape', Args[2]);
  if M * N <> A.Count then
    RaiseFmt(DimensionError, 'reshape: cannot arrange %d elements as %d' + #$00D7 + '%d',
      [A.Count, M, N]);
  R := TArrayObj.Create(A.ElemType, M, N, IsVec);
  Result := ArrayValue(R);
  for K := 0 to A.Count - 1 do
    R.Put(K, A.Get(K));
end;

{ ---- collections (M7) ---- }

{ append(list, x) and append(vector, x): a new value with x added. }
function BAppend(const Args: TAxValues): TAxValue;
var
  A, X: TArrayObj;
  HA, HX: TAxValue;
  Values: TAxValues;
  K: Integer;
begin
  case Args[0].Kind of
    vkList:
      Exit(ListValue(AsList(Args[0]).Items + [Args[1]]));
    vkArray, vkRange:
      begin
        A := ToArray(Args[0]);
        HA := ArrayValue(A);
        if not A.IsVector then
          RaiseError(TypeError, 'append works on lists and vectors, not matrices');
        SetLength(Values, A.Count);
        for K := 0 to A.Count - 1 do
          Values[K] := A.Get(K);
        if IsArrayLike(Args[1]) then
        begin
          X := ToArray(Args[1]);
          HX := ArrayValue(X);
          for K := 0 to X.Count - 1 do
            Values := Values + [X.Get(K)];
        end
        else
          Values := Values + [Args[1]];
        Result := BuildArray(Length(Values), 1, True, Values, A.ElemType);
      end;
  else
    RaiseFmt(TypeError, 'append works on lists and vectors, got %s', [TypeName(Args[0])]);
  end;
end;

function NeedDict(const Fn: string; const V: TAxValue): TDictObj;
begin
  if V.Kind <> vkDict then
    RaiseFmt(TypeError, '%s needs a dictionary, got %s', [Fn, TypeName(V)]);
  Result := AsDict(V);
end;

function BGet(const Args: TAxValues): TAxValue;
var
  D: TDictObj;
  P: Integer;
begin
  D := NeedDict('get', Args[0]);
  P := D.Find(Args[1]);
  if P >= 0 then
    Result := D.Values[P]
  else
    Result := Args[2];
end;

function BKeys(const Args: TAxValues): TAxValue;
begin
  Result := ListValue(Copy(NeedDict('keys', Args[0]).Keys));
end;

function BHaskey(const Args: TAxValues): TAxValue;
begin
  Result := BoolValue(NeedDict('haskey', Args[0]).Find(Args[1]) >= 0);
end;

{ dict() with no entries. Calls with => pairs are built by the interpreter. }
function BDictEmpty(const Args: TAxValues): TAxValue;
begin
  Result := DictValue(TDictObj.Create);
end;

{ keep(f): f's callback trampolines outlive the extern call (M9). }
function BKeep(const Args: TAxValues): TAxValue;
begin
  Result := KeepCallback(Args[0]);
end;

{ Test hook: the number of copy-on-write array copies made so far. }
function BCopies(const Args: TAxValues): TAxValue;
begin
  Result := IntValue(ArrayCopies);
end;

procedure DefineBuiltins(const Define: TProc<string, TAxValue>);

  procedure AddMulti(const Name: string; Fn: TBuiltinMultiFn; MinArgs, MaxArgs: Integer);
  var
    B: TBuiltinObj;
    V: TAxValue;
  begin
    B := TBuiltinObj.Create;
    B.Name := Name;
    B.MultiFn := Fn;
    B.MinArgs := MinArgs;
    B.MaxArgs := MaxArgs;
    V := NothingValue;
    V.Kind := vkBuiltin;
    V.Obj := B;
    Define(Name, V);
  end;

  procedure Add(const Name: string; Fn: TBuiltinFn; MinArgs, MaxArgs: Integer);
  var
    B: TBuiltinObj;
    V: TAxValue;
  begin
    B := TBuiltinObj.Create;
    B.Name := Name;
    B.Fn := Fn;
    B.MinArgs := MinArgs;
    B.MaxArgs := MaxArgs;
    V := NothingValue;
    V.Kind := vkBuiltin;
    V.Obj := B;
    Define(Name, V);
  end;

begin
  Add('zeros', BZeros, 1, 2);
  Add('ones', BOnes, 1, 2);
  Add('eye', BEye, 1, 2);
  Add('rand', BRand, 0, 2);
  Add('linspace', BLinspace, 3, 3);
  AddMulti('size', BSize, 1, 2);
  Add('sum', BSum, 1, 2);
  Add('prod', BProd, 1, 2);
  Add('mean', BMean, 1, 2);
  Add('all', BAll, 1, 1);
  Add('any', BAny, 1, 1);
  Add('dot', BDot, 2, 2);
  Add('adjoint', BAdjoint, 1, 1);
  Add('isequal', BIsequal, 2, 2);
  Add('__copies', BCopies, 0, 0);
  Add('__native_library', BCopies, 1, 1);   // handled by the interpreter
  Add('keep', BKeep, 1, 1);
  Add('eltype', BEltype, 1, 1);
  Add('reshape', BReshape, 2, 3);
  Add('sparse', BSparse, 1, 5);
  Add('speye', BSpeye, 1, 2);
  Add('nnz', BNnz, 1, 1);
  Add('full', BFull, 1, 1);
  AddMulti('splu', BSplu, 1, 1);
  Add('append', BAppend, 2, 2);
  Add('get', BGet, 3, 3);
  Add('keys', BKeys, 1, 1);
  Add('haskey', BHaskey, 2, 2);
  Add('dict', BDictEmpty, 0, 0);
  Add('print', BPrint, 0, -1);
  Add('error', BError, 1, 2);
  Add('string', BString, 1, 1);
  Add('length', BLength, 1, 1);
  Add('typeof', BTypeof, 1, 1);
  Add('sqrt', BSqrt, 1, 1);
  Add('exp', BExp, 1, 1);
  Add('log', BLog, 1, 1);
  Add('sin', BSin, 1, 1);
  Add('cos', BCos, 1, 1);
  Add('tan', BTan, 1, 1);
  Add('asin', BAsin, 1, 1);
  Add('acos', BAcos, 1, 1);
  Add('atan', BAtan, 1, 1);
  Add('sinh', BSinh, 1, 1);
  Add('cosh', BCosh, 1, 1);
  Add('tanh', BTanh, 1, 1);
  Add('asinh', BAsinh, 1, 1);
  Add('acosh', BAcosh, 1, 1);
  Add('atanh', BAtanh, 1, 1);
  Add('abs', BAbs, 1, 1);
  Add('int', BInt, 1, 1);
  Add('floor', BFloor, 1, 1);
  Add('ceil', BCeil, 1, 1);
  Add('round', BRound, 1, 1);
  Add('real', BReal, 1, 1);
  Add('imag', BImag, 1, 1);
  Add('conj', BConj, 1, 1);
  Add('arg', BArg, 1, 1);
  Add('complex', BComplex, 1, 2);
  Add('div', BDiv, 2, 2);
  Add('mod', BMod, 2, 2);
  Add('min', BMin, 1, 2);
  Add('max', BMax, 1, 2);
  Add('factorial', BFactorial, 1, 1);
end;

end.
