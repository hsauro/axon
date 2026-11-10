unit Axon.Arrays;

(* Operations on dense arrays (M6): matrix literals, broadcasting, the matrix
   product (a plain triple loop until BLAS arrives in M10), transpose, index
   resolution and reductions.

   Elementwise work goes through the scalar operators in Axon.Ops one element
   at a time, so overflow checks, promotion and NaN rules are exactly the
   scalar ones. The result's element type is the widest of the element
   results. Ranges take part as vectors. The common cases (operators on bool,
   int and real elements, sums and products) run in typed loops that compute
   the same results without boxing each element (see "fast paths"). *)

interface

uses
  System.SysUtils,
  Axon.Values, Axon.Tokens;

type
  TValueFn = reference to function(const X: TAxValue): TAxValue;
  TValueFn2 = reference to function(const X, Y: TAxValue): TAxValue;

{ True for arrays and ranges, which behave as arrays in operations. }
function IsArrayLike(const V: TAxValue): Boolean; inline;
{ The array for an array or range value. A range gives a new vector; an
  array gives itself, which the caller must not modify. }
function ToArray(const V: TAxValue): TArrayObj;
function RangeToArray(R: TRangeObj): TArrayObj;

{ Builds an array from element values (column-major), with the widest
  element type. Non-numeric elements raise TypeError. An empty array takes
  EmptyType. }
function BuildArray(Rows, Cols: Integer; IsVector: Boolean; const Values: TAxValues;
  EmptyType: TElemType = etReal): TAxValue;

{ A matrix literal from its rows of evaluated entries. }
function ConcatLiteral(const Rows: TArray<TAxValues>): TAxValue;

{ Binary operator with at least one array or range operand. }
function ArrayBinaryOp(Op: TTokenKind; const A, B: TAxValue): TAxValue;
{ Unary -, +, not and ' on an array or range. }
function ArrayUnaryOp(Op: TTokenKind; const A: TAxValue): TAxValue;

{ Applies F to every element of an array or range. }
function MapArray(const V: TAxValue; const F: TValueFn): TAxValue;
{ Applies F elementwise to two operands with broadcasting; either may be a
  scalar. What names the operation in a DimensionError. }
function Broadcast2(const A, B: TAxValue; const F: TValueFn2; const What: string;
  EmptyType: TElemType = etReal): TAxValue;

function MatMul(const A, B: TAxValue): TAxValue;
function Transpose(A: TArrayObj; Conjugate: Boolean): TAxValue;

{ Whole-value equality (isequal). }
function ValuesIdentical(const A, B: TAxValue): Boolean;

{ Resolves one index value against a dimension of length Len into 0-based
  positions. Scalar is set for a single int index, which drops the dimension. }
procedure ResolveIndex(const V: TAxValue; Len: Integer; out Positions: TArray<Integer>;
  out Scalar: Boolean);
function AllPositions(Len: Integer): TArray<Integer>;

{ Reductions over every element. }
function ReduceSum(const V: TAxValue): TAxValue;
function ReduceProd(const V: TAxValue): TAxValue;
{ Reduction along dimension Dim (1 or 2), with Op tkPlus (sum) or tkStar (prod). }
function ReduceDim(const V: TAxValue; Dim: Integer; Op: TTokenKind): TAxValue;
function CountAsValue(N: Integer): TAxValue;

implementation

uses
  System.Math,
  Axon.Errors, Axon.Complex, Axon.Ops, Axon.Linalg, Axon.Sparse;

function IsArrayLike(const V: TAxValue): Boolean;
begin
  Result := V.Kind in [vkArray, vkRange];
end;

function RangeToArray(R: TRangeObj): TArrayObj;
var
  K: Integer;
begin
  if R.Count > MaxInt then
    RaiseError(ArgumentError, 'range is too long to become a vector');
  if R.IsInt then
  begin
    Result := TArrayObj.Create(etInt, R.Count, 1, True);
    for K := 0 to R.Count - 1 do
      Result.I[K] := R.IStart + K * R.IStep;
  end
  else
  begin
    Result := TArrayObj.Create(etReal, R.Count, 1, True);
    for K := 0 to R.Count - 1 do
      Result.R[K] := R.RStart + K * R.RStep;
  end;
end;

function ToArray(const V: TAxValue): TArrayObj;
begin
  if V.Kind = vkRange then
    Result := RangeToArray(AsRange(V))
  else
    Result := AsArray(V);
end;

{ Keeps the array alive while the caller works with it: ranges produce a new
  object that nothing else references. }
function ArrayHold(const V: TAxValue; out Holder: TAxValue): TArrayObj;
begin
  if V.Kind = vkRange then
  begin
    Holder := ArrayValue(RangeToArray(AsRange(V)));
    Result := AsArray(Holder);
  end
  else
  begin
    Holder := V;
    Result := AsArray(V);
  end;
end;

function BuildArray(Rows, Cols: Integer; IsVector: Boolean; const Values: TAxValues;
  EmptyType: TElemType): TAxValue;
var
  T: TElemType;
  K: Integer;
  A: TArrayObj;
begin
  if Length(Values) = 0 then
    T := EmptyType
  else
    T := etBool;
  for K := 0 to High(Values) do
  begin
    if NumRank(Values[K]) < 0 then
      RaiseFmt(TypeError, 'arrays hold numbers and bools only, got %s', [TypeName(Values[K])]);
    if ElemTypeOf(Values[K]) > T then
      T := ElemTypeOf(Values[K]);
  end;
  A := TArrayObj.Create(T, Rows, Cols, IsVector);
  Result := ArrayValue(A);
  for K := 0 to High(Values) do
    A.Put(K, Values[K]);
end;

function CountAsValue(N: Integer): TAxValue;
begin
  Result := IntValue(N);
end;

{ ---------------- literals ---------------- }

function ConcatLiteral(const Rows: TArray<TAxValues>): TAxValue;
var
  Entries: array of array of TAxValue;
  RI, EI, K, RowH, RowW, TotalW, TotalH, R0, C0, Rr, Cc: Integer;
  AllSingle: Boolean;
  V: TAxValue;
  A, Blk: TArrayObj;
  T: TElemType;
  Values: TAxValues;
  BlockH, BlockW: Integer;

  procedure BlockDims(const X: TAxValue; out H, W: Integer);
  begin
    if X.Kind = vkArray then
    begin
      H := AsArray(X).Rows;
      W := AsArray(X).Cols;
    end
    else
    begin
      H := 1;
      W := 1;
    end;
  end;

  function IsEmptyBlock(const X: TAxValue): Boolean;
  begin
    Result := (X.Kind = vkArray) and (AsArray(X).Rows = 0) and (AsArray(X).Cols = 0);
  end;

begin
  if Length(Rows) = 0 then
    Exit(ArrayValue(TArrayObj.Create(etReal, 0, 0, False)));

  // Ranges become vectors; entries must be numbers, bools or arrays.
  SetLength(Entries, Length(Rows));
  for RI := 0 to High(Rows) do
  begin
    SetLength(Entries[RI], Length(Rows[RI]));
    for EI := 0 to High(Rows[RI]) do
    begin
      V := Rows[RI][EI];
      if V.Kind = vkRange then
        V := ArrayValue(RangeToArray(AsRange(V)))
      else if (V.Kind <> vkArray) and (NumRank(V) < 0) then
        RaiseFmt(TypeError, 'a matrix literal holds numbers, bools and arrays, got %s',
          [TypeName(V)]);
      Entries[RI][EI] := V;
    end;
  end;

  // A literal whose rows each hold one scalar or vector is a vector.
  AllSingle := True;
  for RI := 0 to High(Entries) do
    if (Length(Entries[RI]) <> 1) or
       ((Entries[RI][0].Kind = vkArray) and not AsArray(Entries[RI][0]).IsVector and
        not IsEmptyBlock(Entries[RI][0])) then
      AllSingle := False;
  if AllSingle then
  begin
    Values := nil;
    // The widest element type of the entries, counting the type of a vector
    // with no elements too ([zeros(0); 5] is real), but not of a skipped
    // empty [] block.
    T := etBool;
    for RI := 0 to High(Entries) do
    begin
      V := Entries[RI][0];
      if V.Kind = vkArray then
      begin
        A := AsArray(V);
        if not IsEmptyBlock(V) and (A.ElemType > T) then
          T := A.ElemType;
        for K := 0 to A.Count - 1 do
          Values := Values + [A.Get(K)];
      end
      else
        Values := Values + [V];
    end;
    // An all-empty literal such as [[]] stays the empty matrix.
    if (Length(Values) = 0) then
      Exit(ArrayValue(TArrayObj.Create(etReal, 0, 0, False)));
    Result := BuildArray(Length(Values), 1, True, Values);
    if AsArray(Result).ElemType < T then
      AsArray(Result).Widen(T);
    Exit;
  end;

  // Block concatenation. Empty 0×0 blocks are skipped.
  TotalW := -1;
  TotalH := 0;
  T := etBool;
  for RI := 0 to High(Entries) do
  begin
    RowH := -1;
    RowW := 0;
    for EI := 0 to High(Entries[RI]) do
    begin
      V := Entries[RI][EI];
      if IsEmptyBlock(V) then
        Continue;
      BlockDims(V, BlockH, BlockW);
      if RowH < 0 then
        RowH := BlockH
      else if BlockH <> RowH then
        RaiseFmt(DimensionError,
          'matrix literal: blocks in row %d have different heights (%d and %d)',
          [RI + 1, RowH, BlockH]);
      Inc(RowW, BlockW);
      if V.Kind = vkArray then
      begin
        if AsArray(V).ElemType > T then T := AsArray(V).ElemType;
      end
      else if ElemTypeOf(V) > T then
        T := ElemTypeOf(V);
    end;
    if RowH < 0 then
      Continue;  // only empty blocks
    if TotalW < 0 then
      TotalW := RowW
    else if RowW <> TotalW then
      RaiseFmt(DimensionError, 'matrix literal: row %d has width %d, expected %d',
        [RI + 1, RowW, TotalW]);
    Inc(TotalH, RowH);
  end;
  if TotalW < 0 then
    Exit(ArrayValue(TArrayObj.Create(etReal, 0, 0, False)));

  A := TArrayObj.Create(T, TotalH, TotalW, False);
  Result := ArrayValue(A);
  R0 := 0;
  for RI := 0 to High(Entries) do
  begin
    C0 := 0;
    RowH := 0;
    for EI := 0 to High(Entries[RI]) do
    begin
      V := Entries[RI][EI];
      if IsEmptyBlock(V) then
        Continue;
      BlockDims(V, BlockH, BlockW);
      RowH := BlockH;
      if V.Kind = vkArray then
      begin
        Blk := AsArray(V);
        for Cc := 0 to BlockW - 1 do
          for Rr := 0 to BlockH - 1 do
            A.Put((C0 + Cc) * TotalH + R0 + Rr, Blk.Get(Cc * BlockH + Rr));
      end
      else
        A.Put(C0 * TotalH + R0, V);
      Inc(C0, BlockW);
    end;
    Inc(R0, RowH);
  end;
end;

{ ---------------- elementwise ---------------- }

function MapArray(const V: TAxValue; const F: TValueFn): TAxValue;
var
  Holder: TAxValue;
  A: TArrayObj;
  Values: TAxValues;
  K: Integer;
begin
  A := ArrayHold(V, Holder);
  SetLength(Values, A.Count);
  for K := 0 to A.Count - 1 do
    Values[K] := F(A.Get(K));
  Result := BuildArray(A.Rows, A.Cols, A.IsVector, Values, A.ElemType);
end;

{ Shape of an operand for broadcasting: scalars are 1×1, vectors n×1. }
procedure ShapeOf(const V: TAxValue; out R, C: Integer; out IsArr, IsVec: Boolean);
begin
  IsArr := V.Kind = vkArray;
  if IsArr then
  begin
    R := AsArray(V).Rows;
    C := AsArray(V).Cols;
    IsVec := AsArray(V).IsVector;
  end
  else
  begin
    R := 1;
    C := 1;
    IsVec := False;
  end;
end;

function ShapeText(const V: TAxValue): string;
begin
  if V.Kind <> vkArray then
    Result := 'a scalar'
  else if AsArray(V).IsVector then
    Result := Format('a %d-vector', [AsArray(V).Rows])
  else
    Result := Format('a %d' + #$00D7 + '%d matrix', [AsArray(V).Rows, AsArray(V).Cols]);
end;

function Broadcast2(const A, B: TAxValue; const F: TValueFn2; const What: string;
  EmptyType: TElemType): TAxValue;
var
  HA, HB, X, Y: TAxValue;
  RA, CA, RB, CB, R, C, I, J: Integer;
  ArrA, ArrB, VecA, VecB: Boolean;
  AA, AB: TArrayObj;
  Values: TAxValues;
  IsVec: Boolean;
begin
  if A.Kind = vkRange then HA := ArrayValue(RangeToArray(AsRange(A))) else HA := A;
  if B.Kind = vkRange then HB := ArrayValue(RangeToArray(AsRange(B))) else HB := B;
  ShapeOf(HA, RA, CA, ArrA, VecA);
  ShapeOf(HB, RB, CB, ArrB, VecB);
  if ((RA <> RB) and (RA <> 1) and (RB <> 1)) or ((CA <> CB) and (CA <> 1) and (CB <> 1)) then
    RaiseFmt(DimensionError, '%s: cannot broadcast %s with %s',
      [What, ShapeText(HA), ShapeText(HB)]);
  // A size-1 dimension stretches to the other operand's size (including 0).
  if RA = 1 then R := RB else R := RA;
  if CA = 1 then C := CB else C := CA;
  // A vector result needs every array operand to be a vector.
  IsVec := (not ArrA or VecA) and (not ArrB or VecB) and (ArrA or ArrB);
  if ArrA then AA := AsArray(HA) else AA := nil;
  if ArrB then AB := AsArray(HB) else AB := nil;
  SetLength(Values, R * C);
  for J := 0 to C - 1 do
    for I := 0 to R - 1 do
    begin
      if AA = nil then
        X := HA
      else
        X := AA.Get(IfThen(CA = 1, 0, J) * RA + IfThen(RA = 1, 0, I));
      if AB = nil then
        Y := HB
      else
        Y := AB.Get(IfThen(CB = 1, 0, J) * RB + IfThen(RB = 1, 0, I));
      Values[J * R + I] := F(X, Y);
    end;
  Result := BuildArray(R, C, IsVec, Values, EmptyType);
end;

{ ---------------- fast paths ---------------- }

(* Typed loops for the common cases of elementwise operators and reductions
   on bool, int and real operands. They compute exactly what the scalar
   operators compute element by element (RealArith, IntArith with its
   overflow checks, CompareOrder, ValuesEqual), in the same order, so results
   and errors are identical; they only skip boxing each element into a
   TAxValue and rebuilding the array. Anything else (complex elements, empty
   results, and, or, integer powers) returns False, and the general code
   runs. *)

type
  { One operand of a fast elementwise operation: an array, or a scalar
    standing for an array of one element. }
  TFastOperand = record
    Arr: TArrayObj;          // nil for a scalar
    Holder: TAxValue;        // keeps a range's array alive
    T: TElemType;
    SR: Double;              // the scalar's value
    SI: Int64;
    Rows, Cols: Integer;
    IsVec: Boolean;
  end;

function FastOperand(const V: TAxValue; out O: TFastOperand): Boolean;
begin
  Result := True;
  O.Arr := nil;
  O.SR := 0;
  O.SI := 0;
  case V.Kind of
    vkArray, vkRange:
      begin
        O.Arr := ArrayHold(V, O.Holder);
        O.T := O.Arr.ElemType;
        if O.T = etComplex then
          Exit(False);
        O.Rows := O.Arr.Rows;
        O.Cols := O.Arr.Cols;
        O.IsVec := O.Arr.IsVector;
      end;
    vkBool, vkInt, vkReal:
      begin
        O.T := ElemTypeOf(V);
        O.SI := 0;
        case V.Kind of
          vkBool: begin O.SI := Ord(V.B); O.SR := Ord(V.B); end;
          vkInt:  begin O.SI := V.I; O.SR := V.I; end;
        else
          O.SR := V.R;
        end;
        O.Rows := 1;
        O.Cols := 1;
        O.IsVec := False;
      end;
  else
    Result := False;
  end;
end;

{ Element K of an operand as a real (ToReal) or an int (ToInt). }
function RealAt(const O: TFastOperand; K: Integer): Double; inline;
begin
  if O.Arr = nil then
    Result := O.SR
  else
    case O.T of
      etReal: Result := O.Arr.R[K];
      etInt:  Result := O.Arr.I[K];
    else
      Result := Ord(O.Arr.B[K]);
    end;
end;

function IntAtOf(const O: TFastOperand; K: Integer): Int64; inline;
begin
  if O.Arr = nil then
    Result := O.SI
  else if O.T = etInt then
    Result := O.Arr.I[K]
  else
    Result := Ord(O.Arr.B[K]);
end;

(* Out := A op B for + - * / when each operand is a real array of Out's
   shape or a real-valued scalar; False otherwise. *)
function RealLoop(Op: TTokenKind; const OA, OB: TFastOperand; Out: TArrayObj): Boolean;
var
  N, K: Integer;
  X, Y: Double;
  PA, PB, PO: PDouble;
begin
  N := Out.Count;
  Result := False;
  if (OA.Arr <> nil) and ((OA.T <> etReal) or (OA.Arr.Count <> N)) then Exit;
  if (OB.Arr <> nil) and ((OB.T <> etReal) or (OB.Arr.Count <> N)) then Exit;
  if (OA.Arr = nil) and (OB.Arr = nil) then Exit;
  PO := @Out.R[0];
  if (OA.Arr <> nil) and (OB.Arr <> nil) then
  begin
    PA := @OA.Arr.R[0];
    PB := @OB.Arr.R[0];
    case Op of
      tkPlus:  for K := 0 to N - 1 do begin PO^ := PA^ + PB^; Inc(PA); Inc(PB); Inc(PO); end;
      tkMinus: for K := 0 to N - 1 do begin PO^ := PA^ - PB^; Inc(PA); Inc(PB); Inc(PO); end;
      tkStar, tkDotStar:
        for K := 0 to N - 1 do begin PO^ := PA^ * PB^; Inc(PA); Inc(PB); Inc(PO); end;
    else
      for K := 0 to N - 1 do begin PO^ := PA^ / PB^; Inc(PA); Inc(PB); Inc(PO); end;
    end;
  end
  else if OB.Arr = nil then
  begin
    PA := @OA.Arr.R[0];
    Y := OB.SR;
    case Op of
      tkPlus:  for K := 0 to N - 1 do begin PO^ := PA^ + Y; Inc(PA); Inc(PO); end;
      tkMinus: for K := 0 to N - 1 do begin PO^ := PA^ - Y; Inc(PA); Inc(PO); end;
      tkStar, tkDotStar:
        for K := 0 to N - 1 do begin PO^ := PA^ * Y; Inc(PA); Inc(PO); end;
    else
      for K := 0 to N - 1 do begin PO^ := PA^ / Y; Inc(PA); Inc(PO); end;
    end;
  end
  else
  begin
    PB := @OB.Arr.R[0];
    X := OA.SR;
    case Op of
      tkPlus:  for K := 0 to N - 1 do begin PO^ := X + PB^; Inc(PB); Inc(PO); end;
      tkMinus: for K := 0 to N - 1 do begin PO^ := X - PB^; Inc(PB); Inc(PO); end;
      tkStar, tkDotStar:
        for K := 0 to N - 1 do begin PO^ := X * PB^; Inc(PB); Inc(PO); end;
    else
      for K := 0 to N - 1 do begin PO^ := X / PB^; Inc(PB); Inc(PO); end;
    end;
  end;
  Result := True;
end;

function FastBinaryOp(Op: TTokenKind; const A, B: TAxValue; out Res: TAxValue): Boolean;
var
  OA, OB: TFastOperand;
  R, C, I, J, KA, KB, K, RowA, ColA, RowB, ColB: Integer;
  IsVec, RealMode, Compare: Boolean;
  Out: TArrayObj;
  X, Y: Double;
  P, Q: Int64;
begin
  Result := False;
  if not (Op in [tkPlus, tkMinus, tkStar, tkDotStar, tkSlash, tkDotSlash, tkBackslash,
    tkDotBackslash, tkDotCaret, tkCaret, tkEqEq, tkNotEq, tkLess, tkLessEq, tkGreater,
    tkGreaterEq]) then
    Exit;
  if not FastOperand(A, OA) or not FastOperand(B, OB) then
    Exit;
  // Shapes as Broadcast2; a mismatch, or an empty result, is left to it.
  if ((OA.Rows <> OB.Rows) and (OA.Rows <> 1) and (OB.Rows <> 1)) or
    ((OA.Cols <> OB.Cols) and (OA.Cols <> 1) and (OB.Cols <> 1)) then
    Exit;
  if OA.Rows = 1 then R := OB.Rows else R := OA.Rows;
  if OA.Cols = 1 then C := OB.Cols else C := OA.Cols;
  if (R = 0) or (C = 0) then
    Exit;
  RealMode := (OA.T = etReal) or (OB.T = etReal);
  Compare := Op in [tkEqEq, tkNotEq, tkLess, tkLessEq, tkGreater, tkGreaterEq];
  // Integer powers can give ints or reals element by element: general code.
  if not RealMode and (Op in [tkDotCaret, tkCaret]) then
    Exit;
  IsVec := ((OA.Arr = nil) or OA.IsVec) and ((OB.Arr = nil) or OB.IsVec);

  if Compare then
    Out := TArrayObj.Create(etBool, R, C, IsVec)
  else if RealMode or (Op in [tkSlash, tkDotSlash, tkBackslash, tkDotBackslash]) then
    Out := TArrayObj.Create(etReal, R, C, IsVec)
  else
    Out := TArrayObj.Create(etInt, R, C, IsVec);
  Res := ArrayValue(Out);

  // The commonest cases, two real arrays of one shape or a real array and a
  // number, with + - * /: straight loops over the buffers.
  if RealMode and (Op in [tkPlus, tkMinus, tkStar, tkDotStar, tkSlash, tkDotSlash]) and
    RealLoop(Op, OA, OB, Out) then
    Exit(True);

  // Element (I, J) of an operand is at J * Col + I * Row (0 for a size-1 dimension).
  if OA.Rows = 1 then RowA := 0 else RowA := 1;
  if OA.Cols = 1 then ColA := 0 else ColA := OA.Rows;
  if OB.Rows = 1 then RowB := 0 else RowB := 1;
  if OB.Cols = 1 then ColB := 0 else ColB := OB.Rows;

  K := 0;
  for J := 0 to C - 1 do
    for I := 0 to R - 1 do
    begin
      KA := J * ColA + I * RowA;
      KB := J * ColB + I * RowB;
      if Compare then
      begin
        if RealMode then
        begin
          // CompareOrder and ValuesEqual on reals: NaN is unordered and unequal.
          X := RealAt(OA, KA);
          Y := RealAt(OB, KB);
          if IsNan(X) or IsNan(Y) then
            Out.B[K] := Op = tkNotEq
          else
            case Op of
              tkEqEq:      Out.B[K] := X = Y;
              tkNotEq:     Out.B[K] := X <> Y;
              tkLess:      Out.B[K] := X < Y;
              tkLessEq:    Out.B[K] := X <= Y;
              tkGreater:   Out.B[K] := X > Y;
            else
              Out.B[K] := X >= Y;
            end;
        end
        else
        begin
          P := IntAtOf(OA, KA);
          Q := IntAtOf(OB, KB);
          case Op of
            tkEqEq:      Out.B[K] := P = Q;
            tkNotEq:     Out.B[K] := P <> Q;
            tkLess:      Out.B[K] := P < Q;
            tkLessEq:    Out.B[K] := P <= Q;
            tkGreater:   Out.B[K] := P > Q;
          else
            Out.B[K] := P >= Q;
          end;
        end;
      end
      else if RealMode then
      begin
        X := RealAt(OA, KA);
        Y := RealAt(OB, KB);
        case Op of
          tkPlus:  Out.R[K] := X + Y;
          tkMinus: Out.R[K] := X - Y;
          tkStar, tkDotStar: Out.R[K] := X * Y;
          tkSlash, tkDotSlash: Out.R[K] := X / Y;
          tkBackslash, tkDotBackslash: Out.R[K] := Y / X;
        else
          // RealArith's power: a negative base with a non-integer exponent is NaN.
          if (X < 0) and (Frac(Y) <> 0) then
            Out.R[K] := NaN
          else
            Out.R[K] := Power(X, Y);
        end;
      end
      else
      begin
        P := IntAtOf(OA, KA);
        Q := IntAtOf(OB, KB);
        case Op of
          tkPlus:  Out.I[K] := CheckedAdd(P, Q);
          tkMinus: Out.I[K] := CheckedSub(P, Q);
          tkStar, tkDotStar: Out.I[K] := CheckedMul(P, Q);
          tkSlash, tkDotSlash: Out.R[K] := P / Q;
        else
          Out.R[K] := Q / P;
        end;
      end;
      Inc(K);
    end;
  Result := True;
end;

{ -x on a bool, int or real array, as UnaryOp element by element. }
function FastNegate(const V: TAxValue; out Res: TAxValue): Boolean;
var
  Holder: TAxValue;
  A, Out: TArrayObj;
  K: Integer;
begin
  A := ArrayHold(V, Holder);
  Result := (A.ElemType <> etComplex) and (A.Count > 0);
  if not Result then
    Exit;
  if A.ElemType = etReal then
  begin
    Out := TArrayObj.Create(etReal, A.Rows, A.Cols, A.IsVector);
    Res := ArrayValue(Out);
    for K := 0 to A.Count - 1 do
      Out.R[K] := -A.R[K];
  end
  else
  begin
    Out := TArrayObj.Create(etInt, A.Rows, A.Cols, A.IsVector);
    Res := ArrayValue(Out);
    for K := 0 to A.Count - 1 do
      if A.ElemType = etInt then
        Out.I[K] := CheckedNeg(A.I[K])
      else
        Out.I[K] := -Ord(A.B[K]);
  end;
end;

{ Fold of + or * over an int, bool or real array from Start (NeutralFor),
  as Fold computes it: the same order and the same checks. }
function FastFold(A: TArrayObj; Op: TTokenKind; Lo, Count, Stride: Integer;
  out Res: TAxValue): Boolean;
var
  K, P: Integer;
  S: Double;
  N, Q: Int64;
begin
  Result := A.ElemType <> etComplex;
  if not Result then
    Exit;
  P := Lo;
  if A.ElemType = etReal then
  begin
    if Op = tkPlus then S := 0 else S := 1;
    for K := 1 to Count do
    begin
      if Op = tkPlus then S := S + A.R[P] else S := S * A.R[P];
      Inc(P, Stride);
    end;
    Res := RealValue(S);
  end
  else
  begin
    if Op = tkPlus then N := 0 else N := 1;
    for K := 1 to Count do
    begin
      if A.ElemType = etInt then Q := A.I[P] else Q := Ord(A.B[P]);
      if Op = tkPlus then
        N := CheckedAdd(N, Q)
      else
        N := CheckedMul(N, Q);
      Inc(P, Stride);
    end;
    Res := IntValue(N);
  end;
end;

function ArrayBinaryOp(Op: TTokenKind; const A, B: TAxValue): TAxValue;
var
  ScalarA, ScalarB: Boolean;
  EmptyType: TElemType;
begin
  ScalarA := not IsArrayLike(A);
  ScalarB := not IsArrayLike(B);
  case Op of
    tkStar:
      if not (ScalarA or ScalarB) then
        Exit(MatMul(A, B));
    tkSlash:
      if not ScalarB then
        Exit(SolveRight(A, B));
    tkBackslash:
      if not ScalarA then
        Exit(SolveLeft(A, B));
    tkCaret:
      begin
        if ScalarA or not ScalarB then
          RaiseError(TypeError,
            '^ raises a square matrix to a scalar power; use .^ for elementwise powers');
        Exit(MatrixPower(A, B));
      end;
  end;
  if FastBinaryOp(Op, A, B, Result) then
    Exit;
  if Op in [tkEqEq, tkNotEq, tkLess, tkLessEq, tkGreater, tkGreaterEq, tkAnd, tkOr] then
    EmptyType := etBool
  else
    EmptyType := etReal;
  Result := Broadcast2(A, B,
    function(const X, Y: TAxValue): TAxValue
    begin
      Result := BinaryOp(Op, X, Y);
    end,
    'operator ' + TokenSpelling[Op], EmptyType);
end;

function ArrayUnaryOp(Op: TTokenKind; const A: TAxValue): TAxValue;
var
  Holder: TAxValue;
begin
  if Op = tkQuote then
    Exit(Transpose(ArrayHold(A, Holder), False));
  if (Op = tkMinus) and FastNegate(A, Result) then
    Exit;
  Result := MapArray(A,
    function(const X: TAxValue): TAxValue
    begin
      Result := UnaryOp(Op, X);
    end);
end;

{ ---------------- matrix product and transpose ---------------- }

{ Element K of a bool or int array as an int. }
function IntAt(A: TArrayObj; K: Integer): Int64; inline;
begin
  if A.ElemType = etBool then Result := Ord(A.B[K]) else Result := A.I[K];
end;

function MatMul(const A, B: TAxValue): TAxValue;
var
  HA, HB: TAxValue;
  X, Y, Res: TArrayObj;
  RA, CA, RB, CB, I, J, K: Integer;
  T: TElemType;
  SumI: Int64;
  SumR: Double;
  SumC: TComplex;
begin
  X := ArrayHold(A, HA);
  Y := ArrayHold(B, HB);
  RA := X.Rows; CA := X.Cols;
  RB := Y.Rows; CB := Y.Cols;
  if CA <> RB then
    RaiseFmt(DimensionError, 'matrix product: %s times %s (inner sizes %d and %d differ)',
      [ShapeText(HA), ShapeText(HB), CA, RB]);
  T := X.ElemType;
  if Y.ElemType > T then T := Y.ElemType;
  if T = etBool then T := etInt;

  if Y.IsVector and not X.IsVector and (RA = 1) then
    // A row times a vector: v' * w is a scalar.
    Res := TArrayObj.Create(T, 1, 1, False)
  else
    Res := TArrayObj.Create(T, RA, CB, Y.IsVector);
  Result := ArrayValue(Res);

  // Real and complex products go to BLAS (dgemm/zgemm) when it is available.
  if BlasProduct(X, Y, T, Res) then
  begin
    if Y.IsVector and not X.IsVector and (RA = 1) then
      Result := Res.Get(0);
    Exit;
  end;


  for J := 0 to CB - 1 do
    for I := 0 to RA - 1 do
      case T of
        etInt:
          begin
            SumI := 0;
            for K := 0 to CA - 1 do
              SumI := CheckedAdd(SumI, CheckedMul(IntAt(X, K * RA + I), IntAt(Y, J * RB + K)));
            Res.I[J * RA + I] := SumI;
          end;
        etReal:
          begin
            SumR := 0;
            for K := 0 to CA - 1 do
              SumR := SumR + ToReal(X.Get(K * RA + I)) * ToReal(Y.Get(J * RB + K));
            Res.R[J * RA + I] := SumR;
          end;
        etComplex:
          begin
            SumC := Cx(0, 0);
            for K := 0 to CA - 1 do
              SumC := CAdd(SumC, CMul(ToComplex(X.Get(K * RA + I)), ToComplex(Y.Get(J * RB + K))));
            Res.C[J * RA + I] := SumC;
          end;
      end;

  if Y.IsVector and not X.IsVector and (RA = 1) then
    Result := Res.Get(0);
end;

function Transpose(A: TArrayObj; Conjugate: Boolean): TAxValue;
var
  Res: TArrayObj;
  I, J: Integer;
  V: TAxValue;
begin
  // A vector (n×1) becomes a 1×n matrix; an r×c matrix becomes c×r.
  Res := TArrayObj.Create(A.ElemType, A.Cols, A.Rows, False);
  Result := ArrayValue(Res);
  for J := 0 to A.Cols - 1 do
    for I := 0 to A.Rows - 1 do
    begin
      V := A.Get(J * A.Rows + I);
      if Conjugate and (V.Kind = vkComplex) then
        V := ComplexValue(CConj(V.C));
      Res.Put(I * A.Cols + J, V);
    end;
end;

{ ---------------- equality ---------------- }

function ValuesIdentical(const A, B: TAxValue): Boolean;
var
  HA, HB: TAxValue;
  X, Y: TArrayObj;
  K: Integer;
  RA, RB: TRecordObj;
  LA, LB: TListObj;
  DA, DB: TDictObj;
  P: Integer;
begin
  if (A.Kind = vkSparse) or (B.Kind = vkSparse) then
    Exit(ValuesIdentical(Densify(A), Densify(B)));
  if IsArrayLike(A) and IsArrayLike(B) then
  begin
    X := ArrayHold(A, HA);
    Y := ArrayHold(B, HB);
    if (X.IsVector <> Y.IsVector) or (X.Rows <> Y.Rows) or (X.Cols <> Y.Cols) then
      Exit(False);
    for K := 0 to X.Count - 1 do
      if not ValuesEqual(X.Get(K), Y.Get(K)) then
        Exit(False);
    Exit(True);
  end;
  if IsArrayLike(A) or IsArrayLike(B) then
    Exit(False);
  if (A.Kind = vkList) and (B.Kind = vkList) then
  begin
    LA := AsList(A);
    LB := AsList(B);
    if Length(LA.Items) <> Length(LB.Items) then
      Exit(False);
    for K := 0 to High(LA.Items) do
      if not ValuesIdentical(LA.Items[K], LB.Items[K]) then
        Exit(False);
    Exit(True);
  end;
  if (A.Kind = vkDict) and (B.Kind = vkDict) then
  begin
    DA := AsDict(A);
    DB := AsDict(B);
    if Length(DA.Keys) <> Length(DB.Keys) then
      Exit(False);
    for K := 0 to High(DA.Keys) do
    begin
      P := DB.Find(DA.Keys[K]);
      if (P < 0) or not ValuesIdentical(DA.Values[K], DB.Values[P]) then
        Exit(False);
    end;
    Exit(True);
  end;
  if (A.Kind = vkRecord) and (B.Kind = vkRecord) then
  begin
    RA := AsRecord(A);
    RB := AsRecord(B);
    if Length(RA.Names) <> Length(RB.Names) then
      Exit(False);
    // Fields match by name, in any order.
    for K := 0 to High(RA.Names) do
    begin
      P := RB.IndexOf(RA.Names[K]);
      if (P < 0) or not ValuesIdentical(RA.Values[K], RB.Values[P]) then
        Exit(False);
    end;
    Exit(True);
  end;
  Result := ValuesEqual(A, B);
end;

{ ---------------- indexing ---------------- }

function AllPositions(Len: Integer): TArray<Integer>;
var
  K: Integer;
begin
  SetLength(Result, Len);
  for K := 0 to Len - 1 do
    Result[K] := K;
end;

procedure CheckBound(K: Int64; Len: Integer);
begin
  if (K < 1) or (K > Len) then
    RaiseFmt(IndexError, 'index %d is out of bounds for a dimension of length %d', [K, Len]);
end;

procedure ResolveIndex(const V: TAxValue; Len: Integer; out Positions: TArray<Integer>;
  out Scalar: Boolean);
var
  R: TRangeObj;
  A: TArrayObj;
  K, N: Integer;
  Item: Int64;
begin
  Scalar := False;
  Positions := nil;
  case V.Kind of
    vkInt:
      begin
        CheckBound(V.I, Len);
        Positions := [V.I - 1];
        Scalar := True;
      end;
    vkRange:
      begin
        R := AsRange(V);
        if not R.IsInt then
          RaiseError(IndexError, 'an index range must have int bounds and step');
        SetLength(Positions, R.Count);
        for K := 0 to R.Count - 1 do
        begin
          Item := R.IStart + K * R.IStep;
          CheckBound(Item, Len);
          Positions[K] := Item - 1;
        end;
      end;
    vkArray:
      begin
        A := AsArray(V);
        case A.ElemType of
          etInt:
            begin
              SetLength(Positions, A.Count);
              for K := 0 to A.Count - 1 do
              begin
                CheckBound(A.I[K], Len);
                Positions[K] := A.I[K] - 1;
              end;
            end;
          etBool:
            begin
              if A.Count <> Len then
                RaiseFmt(IndexError, 'a bool index has %d elements but the dimension has %d',
                  [A.Count, Len]);
              N := 0;
              SetLength(Positions, Len);
              for K := 0 to Len - 1 do
                if A.B[K] then
                begin
                  Positions[N] := K;
                  Inc(N);
                end;
              SetLength(Positions, N);
            end;
        else
          RaiseFmt(IndexError, 'an index must hold ints or bools, got %s elements',
            [ElemTypeName(A.ElemType)]);
        end;
      end;
  else
    RaiseFmt(IndexError, 'an index must be an int, a range, an int array or a bool array, got %s',
      [TypeName(V)]);
  end;
end;

{ ---------------- reductions ---------------- }

function Fold(const V: TAxValue; Op: TTokenKind; const Start: TAxValue): TAxValue;
var
  Holder: TAxValue;
  A: TArrayObj;
  K: Integer;
begin
  if not IsArrayLike(V) then
  begin
    if NumRank(V) < 0 then
      RaiseFmt(TypeError, 'cannot reduce %s', [TypeName(V)]);
    Exit(BinaryOp(Op, Start, V));
  end;
  A := ArrayHold(V, Holder);
  if FastFold(A, Op, 0, A.Count, 1, Result) then
    Exit;
  Result := Start;
  for K := 0 to A.Count - 1 do
    Result := BinaryOp(Op, Result, A.Get(K));
end;

function NeutralFor(const V: TAxValue; One: Boolean): TAxValue;
var
  T: TElemType;
begin
  if V.Kind = vkArray then T := AsArray(V).ElemType
  else if V.Kind = vkRange then
  begin
    if AsRange(V).IsInt then T := etInt else T := etReal;
  end
  else T := ElemTypeOf(V);
  case T of
    etBool, etInt: Result := IntValue(Ord(One));
    etReal:        Result := RealValue(Ord(One));
  else
    Result := ComplexValue2(Ord(One), 0);
  end;
end;

function ReduceSum(const V: TAxValue): TAxValue;
begin
  Result := Fold(V, tkPlus, NeutralFor(V, False));
end;

function ReduceProd(const V: TAxValue): TAxValue;
begin
  Result := Fold(V, tkStar, NeutralFor(V, True));
end;

function ReduceDim(const V: TAxValue; Dim: Integer; Op: TTokenKind): TAxValue;
var
  Holder, Acc, Start: TAxValue;
  A: TArrayObj;
  I, J: Integer;
  Values: TAxValues;
begin
  if (Dim <> 1) and (Dim <> 2) then
    RaiseFmt(ArgumentError, 'dimension must be 1 or 2, got %d', [Dim]);
  if not IsArrayLike(V) then
    Exit(Fold(V, Op, NeutralFor(V, Op = tkStar)));
  A := ArrayHold(V, Holder);
  Start := NeutralFor(V, Op = tkStar);
  if Dim = 1 then
  begin
    // Down each column: a 1×Cols matrix.
    SetLength(Values, A.Cols);
    for J := 0 to A.Cols - 1 do
      if not FastFold(A, Op, J * A.Rows, A.Rows, 1, Values[J]) then
      begin
        Acc := Start;
        for I := 0 to A.Rows - 1 do
          Acc := BinaryOp(Op, Acc, A.Get(J * A.Rows + I));
        Values[J] := Acc;
      end;
    Result := BuildArray(1, A.Cols, False, Values, ElemTypeOf(Start));
  end
  else
  begin
    // Along each row: Rows×1 (a vector stays a vector).
    SetLength(Values, A.Rows);
    for I := 0 to A.Rows - 1 do
      if not FastFold(A, Op, I, A.Cols, A.Rows, Values[I]) then
      begin
        Acc := Start;
        for J := 0 to A.Cols - 1 do
          Acc := BinaryOp(Op, Acc, A.Get(J * A.Rows + I));
        Values[I] := Acc;
      end;
    Result := BuildArray(A.Rows, 1, A.IsVector, Values, ElemTypeOf(Start));
  end;
end;

end.
