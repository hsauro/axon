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

{ Runs the functions registered with atexit, last registered first (and any
  they register in turn), through CallAxon. The interpreter calls it when the
  main program has run to its end. }
procedure RunAtExit;

{ Forgets the registered functions without running them. }
procedure ClearAtExit;

{ The range Start:Step:Stop (reference, "Ranges"), for a:h:b and range(). }
function NewRange(const A, H, B: TAxValue): TAxValue;

{ print leaves its line open; println, and anything that writes a whole line
  of its own (the REPL's prompts and results, an error report), ends an open
  line first with EndOpenLine. }
var
  OutputLineOpen: Boolean;

procedure EndOpenLine;

{ The real routine behind an elementary function ("sqrt" … "atanh"): a
  function(X: Double): Double in the platform's calling convention, which
  the JIT calls directly, so compiled and interpreted results are the same
  bits. nil for another name. }
function ElementaryRealFunction(const Name: string): Pointer;

{ append(V, X) for the statement `v = append(v, x)`. AppendInPlace adds X to
  V's own list or vector when V holds the only reference to it and X needs
  no wider element type, and returns True; otherwise it changes nothing and
  returns False, and the caller uses AppendValue, which builds a new value.
  Growing in place is what makes building a list or vector by appending
  cost time in proportion to its length rather than its square. }
function AppendInPlace(var V: TAxValue; const X: TAxValue): Boolean;
function AppendValue(const V, X: TAxValue): TAxValue;

implementation

uses
  System.Math, System.Character,
  Axon.Errors, Axon.Complex, Axon.Ops, Axon.Arrays, Axon.Tokens, Axon.Ffi, Axon.Sparse,
  Axon.Random, Axon.FloatParse, Axon.NativeModules;

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

function ElementaryRealFunction(const Name: string): Pointer;
begin
  if Name = 'sqrt' then Result := @RSqrt
  else if Name = 'exp' then Result := @RExp
  else if Name = 'log' then Result := @RLog
  else if Name = 'sin' then Result := @RSin
  else if Name = 'cos' then Result := @RCos
  else if Name = 'tan' then Result := @RTan
  else if Name = 'asin' then Result := @RAsin
  else if Name = 'acos' then Result := @RAcos
  else if Name = 'atan' then Result := @RAtan
  else if Name = 'sinh' then Result := @RSinh
  else if Name = 'cosh' then Result := @RCosh
  else if Name = 'tanh' then Result := @RTanh
  else if Name = 'asinh' then Result := @RAsinh
  else if Name = 'acosh' then Result := @RAcosh
  else if Name = 'atanh' then Result := @RAtanh
  else Result := nil;
end;

{ ---- the builtins ---- }

procedure EndOpenLine;
begin
  if OutputLineOpen then
  begin
    Writeln;
    Flush(Output);
    OutputLineOpen := False;
  end;
end;

{ The values as print and println write them: separated by one space. }
function PrintText(const Args: TAxValues): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(Args) do
  begin
    if I > 0 then
      Result := Result + ' ';
    Result := Result + Display(Args[I]);
  end;
end;

{ print(a, b, ...): the values, and no newline. }
function BPrint(const Args: TAxValues): TAxValue;
var
  S: string;
begin
  S := PrintText(Args);
  if S <> '' then
  begin
    Write(S);
    OutputLineOpen := True;
  end;
  // Flushed at once, so a program's output appears as it runs when stdout
  // is a pipe (the IDE), not only when the program ends.
  Flush(Output);
  Result := NothingValue;
end;

{ println(a, b, ...): the values, then a newline. }
{ ---- display settings and number formatting ---- }

{ format(x, decimals): x as text with exactly that many decimals. }
function BFormat(const Args: TAxValues): TAxValue;
var
  X: Double;
begin
  case Args[0].Kind of
    vkInt: X := Args[0].I;
    vkReal: X := Args[0].R;
  else
    RaiseFmt(TypeError, 'format needs an int or real number, got %s', [TypeName(Args[0])]);
    X := 0;
  end;
  if Args[1].Kind <> vkInt then
    RaiseFmt(TypeError, 'format needs an int number of decimals, got %s', [TypeName(Args[1])]);
  if (Args[1].I < 0) or (Args[1].I > 100) then
    RaiseFmt(ArgumentError, 'format needs 0 to 100 decimals, got %d', [Args[1].I]);
  Result := StringValue(FormatFixed(X, Args[1].I));
end;

function BPrintln(const Args: TAxValues): TAxValue;
begin
  Writeln(PrintText(Args));
  OutputLineOpen := False;
  Flush(Output);
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
var
  I: Int64;
begin
  // A string is read as an integer written in decimal: int("42").
  if Args[0].Kind = vkString then
  begin
    if not TryParseInt(AsString(Args[0]), I) then
      RaiseFmt(ArgumentError, 'int: cannot read "%s" as an integer', [AsString(Args[0])]);
    Exit(IntValue(I));
  end;
  Result := RoundingFn('int', Args[0], 0);
end;
function BFloor(const Args: TAxValues): TAxValue;
begin Result := RoundingFn('floor', Args[0], 1); end;
function BCeil(const Args: TAxValues): TAxValue;
begin Result := RoundingFn('ceil', Args[0], 2); end;
function BRound(const Args: TAxValues): TAxValue;
begin Result := RoundingFn('round', Args[0], 3); end;

function BReal(const Args: TAxValues): TAxValue;
var
  D: Double;
begin
  // A string is read as a decimal number, correctly rounded: real("2.5").
  if Args[0].Kind = vkString then
  begin
    if not TryParseReal(AsString(Args[0]), D) then
      RaiseFmt(ArgumentError, 'real: cannot read "%s" as a number', [AsString(Args[0])]);
    Exit(RealValue(D));
  end;
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
    Exit(RealValue(RandomUniform));
  if Length(Args) = 1 then
    A := TArrayObj.Create(etReal, SizeArg('rand', Args[0]), 1, True)
  else
    A := TArrayObj.Create(etReal, SizeArg('rand', Args[0]), SizeArg('rand', Args[1]), False);
  Result := ArrayValue(A);
  for K := 0 to A.Count - 1 do
    A.R[K] := RandomUniform;
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

{ tr(A): the transpose, exactly A' (no conjugation; see adjoint). }
function BTr(const Args: TAxValues): TAxValue;
begin
  Result := UnaryOp(tkQuote, Args[0]);
end;

{ trace(A): the sum of the diagonal of a square matrix, of its element type;
  a number is its own trace. }
function BTrace(const Args: TAxValues): TAxValue;
var
  A: TArrayObj;
  S: TSparseObj;
  Holder: TAxValue;
  K, N: Integer;
begin
  if Args[0].Kind = vkSparse then
  begin
    S := AsSparse(Args[0]);
    if S.Rows <> S.Cols then
      RaiseFmt(DimensionError, 'trace needs a square matrix, got %d' + #$00D7 + '%d',
        [S.Rows, S.Cols]);
    if S.IsComplex then Result := ComplexValue2(0, 0) else Result := RealValue(0);
    for K := 0 to S.Rows - 1 do
      Result := BinaryOp(tkPlus, Result, S.Get(K, K));
    Exit;
  end;
  if (Args[0].Kind <> vkArray) and (NumRank(Args[0]) >= 0) and (Args[0].Kind <> vkRange) then
    Exit(BinaryOp(tkPlus, IntValue(0), Args[0]));
  if not IsArrayLike(Args[0]) then
    RaiseFmt(TypeError, 'trace needs a square matrix, got %s', [TypeName(Args[0])]);
  A := ToArray(Args[0]);
  Holder := ArrayValue(A);
  if (A.Rows <> A.Cols) then
    RaiseFmt(DimensionError, 'trace needs a square matrix, got %d' + #$00D7 + '%d',
      [A.Rows, A.Cols]);
  N := A.Rows;
  case A.ElemType of
    etBool, etInt: Result := IntValue(0);
    etReal: Result := RealValue(0);
  else
    Result := ComplexValue2(0, 0);
  end;
  for K := 0 to N - 1 do
    Result := BinaryOp(tkPlus, Result, A.Get(K + K * N));
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

{ ---- sorting ---- }

type
  // What sort and sortperm order: the items of a vector or a list, all
  // numbers (bool, int, real) or all strings.
  TSortItems = record
    Values: TAxValues;
    Strings: Boolean;
  end;

function SortItems(const Fn: string; const X: TAxValue): TSortItems;
var
  A: TArrayObj;
  Holder: TAxValue;
  K: Integer;
  Nums, Strs: Boolean;
begin
  Result := Default(TSortItems);
  if X.Kind = vkList then
  begin
    Result.Values := Copy(AsList(X).Items);
    Nums := False;
    Strs := False;
    for K := 0 to High(Result.Values) do
      case Result.Values[K].Kind of
        vkBool, vkInt, vkReal: Nums := True;
        vkString: Strs := True;
      else
        RaiseFmt(TypeError, '%s: cannot order a list holding %s; its items must be all ' +
          'numbers or all strings', [Fn, TypeName(Result.Values[K])]);
      end;
    if Nums and Strs then
      RaiseFmt(TypeError, '%s: cannot order a list that mixes numbers and strings', [Fn]);
    Result.Strings := Strs;
    Exit;
  end;
  if not IsArrayLike(X) then
    RaiseFmt(TypeError, '%s needs a vector or a list, got %s', [Fn, TypeName(X)]);
  A := ToArray(X);
  Holder := ArrayValue(A);
  if not (A.IsVector or (A.Rows <= 1) or (A.Cols <= 1)) then
    RaiseFmt(TypeError, '%s works on vectors, single rows or columns, and lists, not ' +
      'matrices; sort a column with ' +
      '%s(A[:, j])', [Fn, Fn]);
  if A.ElemType = etComplex then
    RaiseFmt(TypeError, '%s: complex numbers have no order', [Fn]);
  SetLength(Result.Values, A.Count);
  for K := 0 to A.Count - 1 do
    Result.Values[K] := A.Get(K);
end;

{ True for "descend", False for "ascend" (the default). }
function SortDescending(const Fn: string; const Args: TAxValues): Boolean;
var
  S: string;
begin
  if Length(Args) < 2 then
    Exit(False);
  if Args[1].Kind <> vkString then
    RaiseFmt(TypeError, '%s: the order must be "ascend" or "descend", got %s',
      [Fn, TypeName(Args[1])]);
  S := AsString(Args[1]);
  Result := S = 'descend';
  if not Result and (S <> 'ascend') then
    RaiseFmt(ArgumentError, '%s: the order must be "ascend" or "descend", got "%s"', [Fn, S]);
end;

function SortIsNaN(const V: TAxValue): Boolean; inline;
begin
  Result := (V.Kind = vkReal) and IsNan(V.R);
end;

function SortInt(const V: TAxValue): Int64; inline;
begin
  if V.Kind = vkBool then Result := Ord(V.B) else Result := V.I;
end;

function SortReal(const V: TAxValue): Double; inline;
begin
  if V.Kind = vkReal then Result := V.R else Result := SortInt(V);
end;

{ The order of two items, -1, 0 or 1, ascending; NaN after every number. }
function SortCompare(const A, B: TAxValue; Strings: Boolean): Integer;
var
  X, Y: Double;
  NA, NB: Boolean;
begin
  if Strings then
    Exit(CompareStr(AsString(A), AsString(B)));
  NA := SortIsNaN(A);
  NB := SortIsNaN(B);
  if NA or NB then
    Exit(Ord(NA) - Ord(NB));
  if (A.Kind <> vkReal) and (B.Kind <> vkReal) then
  begin
    if SortInt(A) < SortInt(B) then Exit(-1);
    if SortInt(A) > SortInt(B) then Exit(1);
    Exit(0);
  end;
  X := SortReal(A);
  Y := SortReal(B);
  if X < Y then Result := -1 else if X > Y then Result := 1 else Result := 0;
end;

{ The 0-based positions of the items in sorted order: a stable merge sort,
  so equal items keep their order. NaN stays last when descending too. }
function SortOrder(const Items: TSortItems; Descending: Boolean): TArray<Integer>;
var
  Tmp: TArray<Integer>;

  function Before(P, Q: Integer): Boolean;  // item P strictly before item Q
  var
    C: Integer;
  begin
    if Descending and not Items.Strings and
      (SortIsNaN(Items.Values[P]) or SortIsNaN(Items.Values[Q])) then
      C := SortCompare(Items.Values[P], Items.Values[Q], False)
    else
    begin
      C := SortCompare(Items.Values[P], Items.Values[Q], Items.Strings);
      if Descending then C := -C;
    end;
    Result := C < 0;
  end;

  procedure MergeSort(Lo, Hi: Integer);    // sorts Result[Lo..Hi-1]
  var
    Mid, I, J, K: Integer;
  begin
    if Hi - Lo < 2 then
      Exit;
    Mid := (Lo + Hi) div 2;
    MergeSort(Lo, Mid);
    MergeSort(Mid, Hi);
    I := Lo;
    J := Mid;
    K := Lo;
    while (I < Mid) and (J < Hi) do
    begin
      if Before(Result[J], Result[I]) then
      begin
        Tmp[K] := Result[J];
        Inc(J);
      end
      else
      begin
        Tmp[K] := Result[I];
        Inc(I);
      end;
      Inc(K);
    end;
    while I < Mid do
    begin
      Tmp[K] := Result[I];
      Inc(I);
      Inc(K);
    end;
    while J < Hi do
    begin
      Tmp[K] := Result[J];
      Inc(J);
      Inc(K);
    end;
    for K := Lo to Hi - 1 do
      Result[K] := Tmp[K];
  end;

var
  K: Integer;
begin
  SetLength(Result, Length(Items.Values));
  for K := 0 to High(Result) do
    Result[K] := K;
  SetLength(Tmp, Length(Result));
  MergeSort(0, Length(Result));
end;

{ sort(x) and sort(x, "descend"): a vector or list in order, as a new value
  of the same kind, shape and element type. }
function BSort(const Args: TAxValues): TAxValue;
var
  Items: TSortItems;
  Order: TArray<Integer>;
  Sorted: TAxValues;
  A, R: TArrayObj;
  K: Integer;
begin
  Items := SortItems('sort', Args[0]);
  Order := SortOrder(Items, SortDescending('sort', Args));
  SetLength(Sorted, Length(Order));
  for K := 0 to High(Order) do
    Sorted[K] := Items.Values[Order[K]];
  if Args[0].Kind = vkList then
    Exit(ListValue(Sorted));
  A := ToArray(Args[0]);
  Result := ArrayValue(A);    // holds A while its element type is read
  R := TArrayObj.Create(A.ElemType, A.Rows, A.Cols, A.IsVector);
  Result := ArrayValue(R);
  for K := 0 to High(Sorted) do
    R.Put(K, Sorted[K]);
end;

{ sortperm(x) and sortperm(x, "descend"): the int vector of 1-based
  positions p with x[p] in order. }
function BSortperm(const Args: TAxValues): TAxValue;
var
  Order: TArray<Integer>;
  R: TArrayObj;
  K: Integer;
begin
  Order := SortOrder(SortItems('sortperm', Args[0]), SortDescending('sortperm', Args));
  R := TArrayObj.Create(etInt, Length(Order), 1, True);
  Result := ArrayValue(R);
  for K := 0 to High(Order) do
    R.Put(K, IntValue(Order[K] + 1));
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

function AppendValue(const V, X: TAxValue): TAxValue;
begin
  Result := BAppend([V, X]);
end;

function AppendInPlace(var V: TAxValue; const X: TAxValue): Boolean;
var
  L: TListObj;
  A, XA: TArrayObj;
  HX: TAxValue;
  XType: TElemType;
  N, M, K: Integer;
begin
  Result := False;
  case V.Kind of
    vkList:
      begin
        L := AsList(V);
        if L.RefCount <> 1 then
          Exit;
        // SetLength copies Items first if another list shares them.
        N := Length(L.Items);
        SetLength(L.Items, N + 1);
        L.Items[N] := X;
      end;
    vkArray:
      begin
        A := AsArray(V);
        if (A.RefCount <> 1) or not A.IsVector or (A.Cols <> 1) then
          Exit;
        XA := nil;
        if IsArrayLike(X) then
        begin
          XA := ToArray(X);
          HX := ArrayValue(XA);
          XType := XA.ElemType;
          M := XA.Count;
        end
        else if NumRank(X) >= 0 then
        begin
          XType := ElemTypeOf(X);
          M := 1;
        end
        else
          Exit;
        // A wider X changes the element type: leave that to AppendValue.
        if XType > A.ElemType then
          Exit;
        N := A.Count;
        case A.ElemType of
          etBool:    SetLength(A.B, N + M);
          etInt:     SetLength(A.I, N + M);
          etReal:    SetLength(A.R, N + M);
          etComplex: SetLength(A.C, N + M);
        end;
        A.Rows := N + M;
        if XA = nil then
          A.Put(N, X)
        else
          for K := 0 to M - 1 do
            A.Put(N + K, XA.Get(K));
      end;
  else
    Exit;
  end;
  Result := True;
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

{ ---- ranges ---- }

function NewRange(const A, H, B: TAxValue): TAxValue;
var
  R: TRangeObj;
  N: Double;
  Span: Int64;

  procedure CheckBound(const V: TAxValue);
  begin
    if (NumRank(V) < 0) or (V.Kind = vkComplex) then
      RaiseFmt(TypeError, 'range bounds and step must be real numbers, got %s',
        [TypeName(V)]);
  end;

  function AsInt(const V: TAxValue): Int64;
  begin
    if V.Kind = vkBool then Result := Ord(V.B) else Result := V.I;
  end;

begin
  CheckBound(A);
  CheckBound(H);
  CheckBound(B);

  R := TRangeObj.Create;
  Result := NothingValue;
  Result.Kind := vkRange;
  Result.Obj := R;
  R.IsInt := (NumRank(A) <= 1) and (NumRank(H) <= 1) and (NumRank(B) <= 1);
  if R.IsInt then
  begin
    R.IStart := AsInt(A);
    R.IStep := AsInt(H);
    R.IStop := AsInt(B);
    if R.IStep = 0 then
      RaiseError(ArgumentError, 'the step of a range cannot be zero');
    if ((R.IStep > 0) and (R.IStop < R.IStart)) or
       ((R.IStep < 0) and (R.IStop > R.IStart)) then
      R.Count := 0
    else
    begin
      Span := CheckedSub(R.IStop, R.IStart);
      R.Count := Span div R.IStep + 1;
    end;
  end
  else
  begin
    R.RStart := ToReal(A);
    R.RStep := ToReal(H);
    R.RStop := ToReal(B);
    if R.RStep = 0 then
      RaiseError(ArgumentError, 'the step of a range cannot be zero');
    if IsNan(R.RStart) or IsNan(R.RStep) or IsNan(R.RStop) then
      RaiseError(ArgumentError, 'range bounds and step cannot be NaN');
    // Reference, "Ranges": the length is floor((b - a)/h + 1e-10) + 1.
    N := Floor((R.RStop - R.RStart) / R.RStep + 1e-10) + 1;
    if IsInfinite(N) or (N > 4.0e18) then
      RaiseError(ArgumentError, 'range has too many elements');
    if N < 0 then
      N := 0;
    R.Count := Trunc(N);
  end;
end;

{ range(n), range(start, stop) and range(start, stop, step): 1:n and
  start:step:stop, with the numbers in the order they are read. }
function BRange(const Args: TAxValues): TAxValue;
begin
  case Length(Args) of
    1: Result := NewRange(IntValue(1), IntValue(1), Args[0]);
    3: Result := NewRange(Args[0], Args[2], Args[1]);
  else
    Result := NewRange(Args[0], IntValue(1), Args[1]);
  end;
end;

{ ---- strings ---- }

function NeedString(const Fn: string; const V: TAxValue; const What: string): string;
begin
  if V.Kind <> vkString then
    RaiseFmt(TypeError, '%s needs %s, got %s', [Fn, What, TypeName(V)]);
  Result := AsString(V);
end;

{ split(s): the words of s, separated by runs of spaces, tabs and line
  breaks, with no empty words. split(s, sep): the pieces between each
  occurrence of sep, empty ones included ("a,,b" gives "a", "", "b"). }
function BSplit(const Args: TAxValues): TAxValue;
var
  S, Sep: string;
  Items: TAxValues;
  K, Start, P: Integer;
begin
  S := NeedString('split', Args[0], 'a string to split');
  Items := nil;
  if Length(Args) = 1 then
  begin
    K := 1;
    while K <= Length(S) do
    begin
      while (K <= Length(S)) and CharInSet(S[K], [' ', #9, #10, #13]) do
        Inc(K);
      Start := K;
      while (K <= Length(S)) and not CharInSet(S[K], [' ', #9, #10, #13]) do
        Inc(K);
      if K > Start then
        Items := Items + [StringValue(Copy(S, Start, K - Start))];
    end;
    Exit(ListValue(Items));
  end;
  Sep := NeedString('split', Args[1], 'a separator string');
  if Sep = '' then
    RaiseError(ArgumentError, 'split: the separator cannot be empty');
  Start := 1;
  repeat
    P := Pos(Sep, S, Start);
    if P = 0 then
      Break;
    Items := Items + [StringValue(Copy(S, Start, P - Start))];
    Start := P + Length(Sep);
  until False;
  Items := Items + [StringValue(Copy(S, Start, MaxInt))];
  Result := ListValue(Items);
end;

{ join(parts) and join(parts, sep): the strings of a list, with sep (default
  none) between them. }
function BJoin(const Args: TAxValues): TAxValue;
var
  Items: TAxValues;
  Sep: string;
  SB: TStringBuilder;
  K: Integer;
begin
  if Args[0].Kind <> vkList then
    RaiseFmt(TypeError, 'join needs a list of strings, got %s', [TypeName(Args[0])]);
  Items := AsList(Args[0]).Items;
  Sep := '';
  if Length(Args) = 2 then
    Sep := NeedString('join', Args[1], 'a separator string');
  SB := TStringBuilder.Create;
  try
    for K := 0 to High(Items) do
    begin
      if Items[K].Kind <> vkString then
        RaiseFmt(TypeError, 'join: item %d is %s, not a string; convert it with string(x)',
          [K + 1, TypeName(Items[K])]);
      if K > 0 then
        SB.Append(Sep);
      SB.Append(AsString(Items[K]));
    end;
    Result := StringValue(SB.ToString);
  finally
    SB.Free;
  end;
end;

{ trim(s): s without the spaces, tabs and line breaks at either end;
  ltrim and rtrim trim only the start or the end. }
function BTrim(const Args: TAxValues): TAxValue;
begin
  Result := StringValue(NeedString('trim', Args[0], 'a string').Trim([' ', #9, #10, #13]));
end;

function BLtrim(const Args: TAxValues): TAxValue;
begin
  Result := StringValue(NeedString('ltrim', Args[0], 'a string').TrimLeft([' ', #9, #10, #13]));
end;

function BRtrim(const Args: TAxValues): TAxValue;
begin
  Result := StringValue(NeedString('rtrim', Args[0], 'a string').TrimRight([' ', #9, #10, #13]));
end;

{ upper(s), lower(s): s in capitals or small letters (Unicode-aware). }
function BUpper(const Args: TAxValues): TAxValue;
begin
  Result := StringValue(NeedString('upper', Args[0], 'a string').ToUpper);
end;

function BLower(const Args: TAxValues): TAxValue;
begin
  Result := StringValue(NeedString('lower', Args[0], 'a string').ToLower);
end;

{ contains(s, part), startswith(s, part), endswith(s, part). An empty part
  is found everywhere. }
function BContains(const Args: TAxValues): TAxValue;
var
  S, Part: string;
begin
  S := NeedString('contains', Args[0], 'a string');
  Part := NeedString('contains', Args[1], 'a string to look for');
  Result := BoolValue((Part = '') or S.Contains(Part));
end;

function BStartsWith(const Args: TAxValues): TAxValue;
var
  S, Part: string;
begin
  S := NeedString('startswith', Args[0], 'a string');
  Part := NeedString('startswith', Args[1], 'a string to look for');
  Result := BoolValue((Part = '') or S.StartsWith(Part));
end;

function BEndsWith(const Args: TAxValues): TAxValue;
var
  S, Part: string;
begin
  S := NeedString('endswith', Args[0], 'a string');
  Part := NeedString('endswith', Args[1], 'a string to look for');
  Result := BoolValue((Part = '') or S.EndsWith(Part));
end;

{ The number of characters (code points) in the first N UTF-16 units of S:
  string positions count characters, as indexing does. }
function CharsBefore(const S: string; N: Integer): Integer;
var
  K: Integer;
begin
  Result := 0;
  for K := 1 to N do
    if not ((Ord(S[K]) >= $DC00) and (Ord(S[K]) <= $DFFF)) then
      Inc(Result);
end;

{ The UTF-16 index (1-based) of character C (1-based) of S, or Length(S) + 1
  past the end. }
function UnitOfChar(const S: string; C: Integer): Integer;
var
  N: Integer;
begin
  Result := 1;
  N := 1;
  while (Result <= Length(S)) and (N < C) do
  begin
    if (Ord(S[Result]) >= $D800) and (Ord(S[Result]) <= $DBFF) and (Result < Length(S)) then
      Inc(Result, 2)
    else
      Inc(Result);
    Inc(N);
  end;
end;

{ find(s, part) and find(s, part, start): the position (in characters) of
  the first occurrence of part in s, at or after position start (default 1),
  or 0 when there is none. }
function BFind(const Args: TAxValues): TAxValue;
var
  S, Part: string;
  Start, From, P: Integer;
begin
  S := NeedString('find', Args[0], 'a string');
  Part := NeedString('find', Args[1], 'a string to look for');
  Start := 1;
  if Length(Args) = 3 then
  begin
    if Args[2].Kind <> vkInt then
      RaiseFmt(TypeError, 'find: the start position must be an int, got %s',
        [TypeName(Args[2])]);
    if Args[2].I < 1 then
      RaiseFmt(ArgumentError, 'find: the start position must be at least 1, got %d',
        [Args[2].I]);
    if Args[2].I > MaxInt then
      Exit(IntValue(0));
    Start := Args[2].I;
  end;
  From := UnitOfChar(S, Start);
  if From > Length(S) + 1 then
    Exit(IntValue(0));
  if Part = '' then
  begin
    if Start > CharsBefore(S, Length(S)) + 1 then
      Exit(IntValue(0));
    Exit(IntValue(Start));
  end;
  P := Pos(Part, S, From);
  if P = 0 then
    Result := IntValue(0)
  else
    Result := IntValue(CharsBefore(S, P - 1) + 1);
end;

{ replace(s, old, new): s with every occurrence of old replaced by new. }
function BReplace(const Args: TAxValues): TAxValue;
var
  Old: string;
begin
  Old := NeedString('replace', Args[1], 'the string to replace');
  if Old = '' then
    RaiseError(ArgumentError, 'replace: the string to replace cannot be empty');
  Result := StringValue(NeedString('replace', Args[0], 'a string').Replace(Old,
    NeedString('replace', Args[2], 'a replacement string'), [rfReplaceAll]));
end;

{ repeat(s, n): s repeated n times (n >= 0). }
function BRepeat(const Args: TAxValues): TAxValue;
var
  S: string;
  N, K: Int64;
  SB: TStringBuilder;
begin
  S := NeedString('repeat', Args[0], 'a string');
  if Args[1].Kind <> vkInt then
    RaiseFmt(TypeError, 'repeat: the count must be an int, got %s', [TypeName(Args[1])]);
  N := Args[1].I;
  if N < 0 then
    RaiseFmt(ArgumentError, 'repeat: the count cannot be negative, got %d', [N]);
  if N * Length(S) > 100000000 then
    RaiseError(ArgumentError, 'repeat: the result would be too long');
  SB := TStringBuilder.Create;
  try
    for K := 1 to N do
      SB.Append(S);
    Result := StringValue(SB.ToString);
  finally
    SB.Free;
  end;
end;

{ ---- isa ---- }

(* isa(x, T): whether x is exactly of type T (no widening: isa(1, "real") is
  false). T is a declared record type, or a string: a built-in type name as
  in annotations ("int", "vector", "vector{real}", "record", ...) or the
  name of a declared record type. *)
function BIsa(const Args: TAxValues): TAxValue;
var
  X: TAxValue;
  T, Name, Elem: string;
  P: Integer;
  Ok: Boolean;
begin
  X := Args[0];
  if Args[1].Kind = vkRecordType then
    Exit(BoolValue((X.Kind = vkRecord) and
      (AsRecord(X).DeclType = TRecordTypeObj(Args[1].Obj))));
  if Args[1].Kind <> vkString then
    RaiseFmt(TypeError, 'isa: the type must be a string such as "int" or a record type, ' +
      'got %s', [TypeName(Args[1])]);
  T := AsString(Args[1]).Trim;
  Name := T;
  Elem := '';
  P := T.IndexOf('{');
  if (P > 0) and T.EndsWith('}') then
  begin
    Name := T.Substring(0, P).Trim;
    Elem := T.Substring(P + 1, T.Length - P - 2).Trim;
  end;
  if (Name = 'bool') or (Name = 'int') or (Name = 'real') or (Name = 'complex') or
    (Name = 'string') or (Name = 'nothing') or (Name = 'range') or (Name = 'list') or
    (Name = 'dict') or (Name = 'sparse') or (Name = 'pointer') then
    Ok := TypeName(X) = Name
  else if Name = 'function' then
    Ok := X.Kind in [vkFunction, vkBuiltin, vkExtern]
  else if Name = 'record' then
    Ok := X.Kind = vkRecord
  else if (Name = 'vector') or (Name = 'matrix') then
  begin
    Ok := (X.Kind = vkArray) and (AsArray(X).IsVector = (Name = 'vector'));
    if Ok and (Elem <> '') then
      Ok := ElemTypeName(AsArray(X).ElemType) = Elem;
  end
  else
    // A declared record type, by name.
    Ok := (X.Kind = vkRecord) and (AsRecord(X).DeclType <> nil) and
      (AsRecord(X).DeclType.Name = T);
  Result := BoolValue(Ok);
end;

{ ---- atexit ---- }

var
  AtExitFns: TAxValues;

{ atexit(f): f() runs when the program ends normally (not after an uncaught
  error), after everything else; the last registered runs first. }
function BAtExit(const Args: TAxValues): TAxValue;
begin
  if not (Args[0].Kind in [vkFunction, vkBuiltin, vkExtern]) then
    RaiseFmt(TypeError, 'atexit needs a function, got %s', [TypeName(Args[0])]);
  AtExitFns := AtExitFns + [Args[0]];
  Result := NothingValue;
end;

procedure RunAtExit;
var
  F: TAxValue;
begin
  while Length(AtExitFns) > 0 do
  begin
    F := AtExitFns[High(AtExitFns)];
    SetLength(AtExitFns, Length(AtExitFns) - 1);
    CallAxon(F, []);
  end;
end;

procedure ClearAtExit;
begin
  AtExitFns := nil;
end;

{ Test hook: the number of copy-on-write array copies made so far. }
function BCopies(const Args: TAxValues): TAxValue;
begin
  Result := IntValue(ArrayCopies);
end;

procedure DefineBuiltins(const Define: TProc<string, TAxValue>);
const
  PiBits: UInt64 = $400921FB54442D18;
  EBits: UInt64 = $4005BF0A8B145769;

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
  Add('sort', BSort, 1, 2);
  Add('sortperm', BSortperm, 1, 2);
  Add('get', BGet, 3, 3);
  Add('keys', BKeys, 1, 1);
  Add('haskey', BHaskey, 2, 2);
  Add('dict', BDictEmpty, 0, 0);
  Add('print', BPrint, 0, -1);
  Add('println', BPrintln, 0, -1);
  Add('format', BFormat, 2, 2);
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
  Add('atexit', BAtExit, 1, 1);
  Add('range', BRange, 1, 3);
  Add('isa', BIsa, 2, 2);
  Add('tr', BTr, 1, 1);
  Add('split', BSplit, 1, 2);
  Add('join', BJoin, 1, 2);
  Add('trim', BTrim, 1, 1);
  Add('ltrim', BLtrim, 1, 1);
  Add('rtrim', BRtrim, 1, 1);
  Add('upper', BUpper, 1, 1);
  Add('lower', BLower, 1, 1);
  Add('contains', BContains, 2, 2);
  Add('startswith', BStartsWith, 2, 2);
  Add('endswith', BEndsWith, 2, 2);
  Add('find', BFind, 2, 3);
  Add('replace', BReplace, 3, 3);
  Add('repeat', BRepeat, 2, 2);
  Add('trace', BTrace, 1, 1);
  // Constants: the doubles nearest to pi and e, given by their bits so that
  // no conversion can be off by one unit in the last place.
  Define('pi', RealValue(PDouble(@PiBits)^));
  Define('e', RealValue(PDouble(@EBits)^));
end;

end.
