unit Axon.Ops;

(* Operators on values: arithmetic with promotion along
   bool -> int -> real -> complex, comparison, and the checks behind them.
   Reference sections: "Numeric promotion", "Comparison", "Logical operators".

   On scalars the dot operators (.* ./ .\ .^) are the same as the plain ones.
   Arrays arrive in M6. *)

interface

uses
  Axon.Tokens, Axon.Values, Axon.Complex;

function BinaryOp(Op: TTokenKind; const A, B: TAxValue): TAxValue;
function UnaryOp(Op: TTokenKind; const A: TAxValue): TAxValue;

{ == and != on any two values. }
function ValuesEqual(const A, B: TAxValue): Boolean;

{ Checked 64-bit integer arithmetic: raises OverflowError. }
function CheckedAdd(A, B: Int64): Int64;
function CheckedSub(A, B: Int64): Int64;
function CheckedMul(A, B: Int64; const Op: string = '*'): Int64;
function CheckedNeg(A: Int64; const Op: string = 'unary -'): Int64;
function IntPow(Base, Exp: Int64): Int64;

{ Numeric rank for promotion: 0 bool, 1 int, 2 real, 3 complex; -1 otherwise. }
function NumRank(const V: TAxValue): Integer; inline;
function ToReal(const V: TAxValue): Double;          // bool, int or real
function ToComplex(const V: TAxValue): TComplex;      // any numeric

procedure RaiseError(const Kind, Msg: string);
procedure RaiseFmt(const Kind, Fmt: string; const Args: array of const);

// Integer overflow is detected explicitly below, so compiler checks are off.
{$Q-}

{ S repeated N times, for repeat(s, n) and s * n; What names the operation
  in errors: ArgumentError for a negative N or a result over 100 million
  characters. }
function RepeatText(const S: string; N: Int64; const What: string): string;

implementation

uses
  System.SysUtils, System.Math,
  Axon.Errors, Axon.Arrays, Axon.Sparse;

procedure RaiseError(const Kind, Msg: string);
begin
  raise EAxonError.Create(Kind, Msg);
end;

procedure RaiseFmt(const Kind, Fmt: string; const Args: array of const);
begin
  raise EAxonError.Create(Kind, Format(Fmt, Args));
end;

{ ---- checked integers ---- }

procedure Overflow(const What: string);
begin
  RaiseError(OverflowError, 'integer overflow in ' + What);
end;

function CheckedAdd(A, B: Int64): Int64;
begin
  Result := A + B;
  // Overflow iff both operands have the same sign and the result's differs.
  if ((A xor Result) and (B xor Result)) < 0 then
    Overflow('+');
end;

function CheckedSub(A, B: Int64): Int64;
begin
  Result := A - B;
  if ((A xor B) and (A xor Result)) < 0 then
    Overflow('-');
end;

function CheckedMul(A, B: Int64; const Op: string = '*'): Int64;
begin
  Result := 0;
  if (A = 0) or (B = 0) then
    Exit;
  if ((A = -1) and (B = Low(Int64))) or ((B = -1) and (A = Low(Int64))) then
    Overflow(Op);
  Result := A * B;
  if Result div B <> A then
    Overflow(Op);
end;

function CheckedNeg(A: Int64; const Op: string = 'unary -'): Int64;
begin
  if A = Low(Int64) then
    Overflow(Op);
  Result := -A;
end;

function IntPow(Base, Exp: Int64): Int64;
begin
  // Exp >= 0. Exponentiation by squaring with checked products.
  Result := 1;
  while Exp > 0 do
  begin
    if Odd(Exp) then
      Result := CheckedMul(Result, Base, '^');
    Exp := Exp shr 1;
    if Exp > 0 then
      Base := CheckedMul(Base, Base, '^');
  end;
end;

{ ---- promotion helpers ---- }

function NumRank(const V: TAxValue): Integer;
begin
  case V.Kind of
    vkBool:    Result := 0;
    vkInt:     Result := 1;
    vkReal:    Result := 2;
    vkComplex: Result := 3;
  else
    Result := -1;
  end;
end;

function ToInt(const V: TAxValue): Int64; inline;
begin
  if V.Kind = vkBool then
    Result := Ord(V.B)
  else
    Result := V.I;
end;

function ToReal(const V: TAxValue): Double;
begin
  case V.Kind of
    vkBool: Result := Ord(V.B);
    vkInt:  Result := V.I;
  else
    Result := V.R;
  end;
end;

function ToComplex(const V: TAxValue): TComplex;
begin
  if V.Kind = vkComplex then
    Result := V.C
  else
    Result := Cx(ToReal(V), 0);
end;

{ ---- arithmetic ---- }

procedure OperandError(Op: TTokenKind; const A, B: TAxValue);
begin
  RaiseFmt(TypeError, 'operator %s is not defined for %s and %s',
    [TokenSpelling[Op], TypeName(A), TypeName(B)]);
end;

function IntArith(Op: TTokenKind; X, Y: Int64): TAxValue;
begin
  case Op of
    tkPlus:  Result := IntValue(CheckedAdd(X, Y));
    tkMinus: Result := IntValue(CheckedSub(X, Y));
    tkStar, tkDotStar: Result := IntValue(CheckedMul(X, Y));
    tkSlash, tkDotSlash: Result := RealValue(X / Y);
    tkBackslash, tkDotBackslash: Result := RealValue(Y / X);
    tkCaret, tkDotCaret:
      if Y >= 0 then
        Result := IntValue(IntPow(X, Y))
      else
        Result := RealValue(Power(X, Y));
  else
    Result := NothingValue;
  end;
end;

function RealArith(Op: TTokenKind; X, Y: Double): TAxValue;
begin
  case Op of
    tkPlus:  Result := RealValue(X + Y);
    tkMinus: Result := RealValue(X - Y);
    tkStar, tkDotStar: Result := RealValue(X * Y);
    tkSlash, tkDotSlash: Result := RealValue(X / Y);
    tkBackslash, tkDotBackslash: Result := RealValue(Y / X);
    tkCaret, tkDotCaret:
      // Type-stable: a negative base with a non-integer exponent is NaN.
      if (X < 0) and (Frac(Y) <> 0) then
        Result := RealValue(NaN)
      else
        Result := RealValue(Power(X, Y));
  else
    Result := NothingValue;
  end;
end;

function ComplexArith(Op: TTokenKind; const X, Y: TComplex): TAxValue;
begin
  case Op of
    tkPlus:  Result := ComplexValue(CAdd(X, Y));
    tkMinus: Result := ComplexValue(CSub(X, Y));
    tkStar, tkDotStar: Result := ComplexValue(CMul(X, Y));
    tkSlash, tkDotSlash: Result := ComplexValue(CDiv(X, Y));
    tkBackslash, tkDotBackslash: Result := ComplexValue(CDiv(Y, X));
    tkCaret, tkDotCaret: Result := ComplexValue(CPow(X, Y));
  else
    Result := NothingValue;
  end;
end;

function CompareOrder(Op: TTokenKind; const A, B: TAxValue): TAxValue;
var
  X, Y: Double;
  C: Integer;
begin
  if (A.Kind = vkString) and (B.Kind = vkString) then
  begin
    C := CompareStr(AsString(A), AsString(B));
    case Op of
      tkLess:      Result := BoolValue(C < 0);
      tkLessEq:    Result := BoolValue(C <= 0);
      tkGreater:   Result := BoolValue(C > 0);
    else
      Result := BoolValue(C >= 0);
    end;
    Exit;
  end;
  if (NumRank(A) < 0) or (NumRank(B) < 0) then
    OperandError(Op, A, B);
  if (A.Kind = vkComplex) or (B.Kind = vkComplex) then
    RaiseFmt(TypeError, 'complex numbers have no ordering (operator %s)', [TokenSpelling[Op]]);
  if (NumRank(A) <= 1) and (NumRank(B) <= 1) then
  begin
    // Exact integer comparison.
    case Op of
      tkLess:    Result := BoolValue(ToInt(A) < ToInt(B));
      tkLessEq:  Result := BoolValue(ToInt(A) <= ToInt(B));
      tkGreater: Result := BoolValue(ToInt(A) > ToInt(B));
    else
      Result := BoolValue(ToInt(A) >= ToInt(B));
    end;
    Exit;
  end;
  X := ToReal(A);
  Y := ToReal(B);
  if IsNan(X) or IsNan(Y) then
    Exit(BoolValue(False));
  case Op of
    tkLess:    Result := BoolValue(X < Y);
    tkLessEq:  Result := BoolValue(X <= Y);
    tkGreater: Result := BoolValue(X > Y);
  else
    Result := BoolValue(X >= Y);
  end;
end;

function ValuesEqual(const A, B: TAxValue): Boolean;
var
  RA, RB: Integer;
  X, Y: TComplex;
begin
  RA := NumRank(A);
  RB := NumRank(B);
  if (RA >= 0) and (RB >= 0) then
  begin
    if (RA <= 1) and (RB <= 1) then
      Exit(ToInt(A) = ToInt(B));
    if (RA <= 2) and (RB <= 2) then
      // NaN compares unequal to everything, itself included.
      Exit(not IsNan(ToReal(A)) and not IsNan(ToReal(B)) and (ToReal(A) = ToReal(B)));
    X := ToComplex(A);
    Y := ToComplex(B);
    if IsNan(X.Re) or IsNan(X.Im) or IsNan(Y.Re) or IsNan(Y.Im) then
      Exit(False);
    Exit(CEqual(X, Y));
  end;
  if A.Kind <> B.Kind then
    Exit(False);
  case A.Kind of
    vkNothing: Result := True;
    vkString:  Result := AsString(A) = AsString(B);
    vkRange:
      Result := (AsRange(A).IsInt = AsRange(B).IsInt) and
        (AsRange(A).Count = AsRange(B).Count) and
        (Display(A) = Display(B));
    vkBuiltin, vkFunction: Result := A.Obj = B.Obj;
    vkList, vkRecord, vkDict: Result := ValuesIdentical(A, B);
    vkRecordType, vkModule, vkExtern: Result := A.Obj = B.Obj;
    vkPointer: Result := A.I = B.I;
  else
    Result := False;
  end;
end;

function BinaryOp(Op: TTokenKind; const A, B: TAxValue): TAxValue;
var
  Rank: Integer;
begin
  // Sparse operands first: they stay sparse or become dense (Axon.Sparse).
  if (A.Kind = vkSparse) or (B.Kind = vkSparse) then
    Exit(SparseBinaryOp(Op, A, B));
  // Arrays and ranges: elementwise with broadcasting, or the matrix product.
  if (A.Kind in [vkArray, vkRange]) or (B.Kind in [vkArray, vkRange]) then
    Exit(ArrayBinaryOp(Op, A, B));
  case Op of
    tkEqEq:  Exit(BoolValue(ValuesEqual(A, B)));
    tkNotEq: Exit(BoolValue(not ValuesEqual(A, B)));
    tkLess, tkLessEq, tkGreater, tkGreaterEq:
      Exit(CompareOrder(Op, A, B));
    tkAnd, tkOr:
      begin
        // Reached only for the right operand of a scalar and/or (the
        // interpreter short-circuits) or for array operands (M6).
        if (A.Kind <> vkBool) or (B.Kind <> vkBool) then
          OperandError(Op, A, B);
        if Op = tkAnd then
          Exit(BoolValue(A.B and B.B))
        else
          Exit(BoolValue(A.B or B.B));
      end;
  end;

  if (Op = tkPlus) and (A.Kind = vkString) and (B.Kind = vkString) then
    Exit(StringValue(AsString(A) + AsString(B)));
  // s * n and n * s: the string repeated, as repeat(s, n).
  if (Op = tkStar) and (A.Kind = vkString) and (B.Kind = vkInt) then
    Exit(StringValue(RepeatText(AsString(A), B.I, 'string * int')));
  if (Op = tkStar) and (A.Kind = vkInt) and (B.Kind = vkString) then
    Exit(StringValue(RepeatText(AsString(B), A.I, 'int * string')));

  if (NumRank(A) < 0) or (NumRank(B) < 0) then
    OperandError(Op, A, B);

  Rank := Max(NumRank(A), NumRank(B));
  case Rank of
    0, 1: Result := IntArith(Op, ToInt(A), ToInt(B));
    2:    Result := RealArith(Op, ToReal(A), ToReal(B));
  else
    Result := ComplexArith(Op, ToComplex(A), ToComplex(B));
  end;
end;

function RepeatText(const S: string; N: Int64; const What: string): string;
var
  SB: TStringBuilder;
  K: Int64;
begin
  if N < 0 then
    RaiseFmt(ArgumentError, '%s: the count cannot be negative, got %d', [What, N]);
  if N * Length(S) > 100000000 then
    RaiseFmt(ArgumentError, '%s: the result would be too long', [What]);
  SB := TStringBuilder.Create;
  try
    for K := 1 to N do
      SB.Append(S);
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function UnaryOp(Op: TTokenKind; const A: TAxValue): TAxValue;
begin
  if A.Kind = vkSparse then
    Exit(SparseUnaryOp(Op, A));
  if A.Kind in [vkArray, vkRange] then
    Exit(ArrayUnaryOp(Op, A));
  case Op of
    tkNot:
      begin
        if A.Kind <> vkBool then
          RaiseFmt(TypeError, 'operator not is not defined for %s', [TypeName(A)]);
        Result := BoolValue(not A.B);
      end;
    tkMinus:
      case A.Kind of
        vkBool:    Result := IntValue(-Ord(A.B));
        vkInt:     Result := IntValue(CheckedNeg(A.I));
        vkReal:    Result := RealValue(-A.R);
        vkComplex: Result := ComplexValue(CNeg(A.C));
      else
        RaiseFmt(TypeError, 'unary - is not defined for %s', [TypeName(A)]);
      end;
    tkPlus:
      case A.Kind of
        vkBool:    Result := IntValue(Ord(A.B));
        vkInt, vkReal, vkComplex: Result := A;
      else
        RaiseFmt(TypeError, 'unary + is not defined for %s', [TypeName(A)]);
      end;
    tkQuote:
      // The transpose of a scalar is the scalar itself.
      if NumRank(A) >= 0 then
        Result := A
      else
        RaiseFmt(TypeError, 'transpose is not defined for %s', [TypeName(A)]);
  else
    RaiseFmt(TypeError, 'unknown unary operator %s', [TokenSpelling[Op]]);
  end;
end;

end.
