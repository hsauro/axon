unit Axon.Sparse;

(* Sparse matrices (reference, "Sparse operands"): construction, conversion,
   the operations that keep a result sparse (+, -, .* and * between sparse
   matrices, scaling by a scalar, negation and transposes), sparse products
   with dense operands, and solving through Axon.SparseLU. Every other
   operation converts to dense and uses the dense code. *)

interface

uses
  System.SysUtils,
  Axon.Complex, Axon.Values, Axon.Tokens;

function SparseValue(S: TSparseObj): TAxValue;
function AsSparse(const V: TAxValue): TSparseObj; inline;

{ Builds a sparse matrix from (row, column, value) triplets, 0-based,
  summing duplicates and dropping zeros. }
function FromTriplets(M, N: Integer; const I, J: TArray<Integer>;
  const V: TArray<TComplex>; IsComplex: Boolean): TSparseObj;
function SparseFromDense(A: TArrayObj): TSparseObj;
{ A dense m×n matrix with the same values. }
function SparseToDense(S: TSparseObj): TAxValue;
{ The value with sparse operands made dense (other values unchanged). }
function Densify(const V: TAxValue): TAxValue;
function SparseIdentity(M, N: Integer): TAxValue;

{ Binary operator with at least one sparse operand. }
function SparseBinaryOp(Op: TTokenKind; const A, B: TAxValue): TAxValue;
{ Unary operator on a sparse operand. }
function SparseUnaryOp(Op: TTokenKind; const A: TAxValue): TAxValue;
function SparseTranspose(S: TSparseObj; Conjugate: Boolean): TAxValue;

{ S \ B with B dense (or a scalar or range); the result is dense, shaped
  like B. }
function SparseSolve(S: TSparseObj; const B: TAxValue): TAxValue;
{ The sparse factors L and U of S with S = L * U (sparse lu). }
function SparseLUFactors(S: TSparseObj): TAxValues;

implementation

uses
  System.Math, System.Generics.Collections, System.Generics.Defaults,
  Axon.Errors, Axon.Ops, Axon.Arrays, Axon.Linalg, Axon.SparseLU;

function SparseValue(S: TSparseObj): TAxValue;
begin
  Result := NothingValue;
  Result.Kind := vkSparse;
  Result.Obj := S;
end;

function AsSparse(const V: TAxValue): TSparseObj;
begin
  Result := TSparseObj(V.Obj);
end;

function IsZero(const C: TComplex): Boolean; inline;
begin
  Result := (C.Re = 0) and (C.Im = 0);
end;

{ ---------------- construction ---------------- }

procedure SortRows(var Rows: TArray<Integer>; var Vals: TArray<TComplex>; L, R: Integer);
var
  I, J, Pivot, TI: Integer;
  TV: TComplex;
begin
  // Quicksort of the (row, value) pairs of one column by row.
  while L < R do
  begin
    I := L;
    J := R;
    Pivot := Rows[(L + R) div 2];
    repeat
      while Rows[I] < Pivot do Inc(I);
      while Rows[J] > Pivot do Dec(J);
      if I <= J then
      begin
        TI := Rows[I]; Rows[I] := Rows[J]; Rows[J] := TI;
        TV := Vals[I]; Vals[I] := Vals[J]; Vals[J] := TV;
        Inc(I);
        Dec(J);
      end;
    until I > J;
    if L < J then SortRows(Rows, Vals, L, J);
    L := I;
  end;
end;

function FromTriplets(M, N: Integer; const I, J: TArray<Integer>;
  const V: TArray<TComplex>; IsComplex: Boolean): TSparseObj;
var
  Count, Next: TArray<Integer>;
  Rows: TArray<Integer>;
  Vals: TArray<TComplex>;
  K, C, P, Start, Stop, Out: Integer;
  Acc: TComplex;
begin
  Result := TSparseObj.Create;
  Result.Rows := M;
  Result.Cols := N;
  Result.IsComplex := IsComplex;
  SetLength(Count, N + 1);
  for K := 0 to High(J) do
    Inc(Count[J[K] + 1]);
  for C := 0 to N - 1 do
    Inc(Count[C + 1], Count[C]);
  // Scatter into columns.
  SetLength(Rows, Length(J));
  SetLength(Vals, Length(J));
  Next := Copy(Count);
  for K := 0 to High(J) do
  begin
    P := Next[J[K]];
    Rows[P] := I[K];
    Vals[P] := V[K];
    Inc(Next[J[K]]);
  end;
  // Sort each column, sum duplicates and drop zeros.
  SetLength(Result.ColPtr, N + 1);
  SetLength(Result.RowIdx, Length(J));
  SetLength(Result.V, Length(J));
  Out := 0;
  for C := 0 to N - 1 do
  begin
    Result.ColPtr[C] := Out;
    Start := Count[C];
    Stop := Count[C + 1] - 1;
    if Stop > Start then
      SortRows(Rows, Vals, Start, Stop);
    P := Start;
    while P <= Stop do
    begin
      Acc := Vals[P];
      while (P < Stop) and (Rows[P + 1] = Rows[P]) do
      begin
        Inc(P);
        Acc := CAdd(Acc, Vals[P]);
      end;
      if not IsZero(Acc) then
      begin
        Result.RowIdx[Out] := Rows[P];
        Result.V[Out] := Acc;
        Inc(Out);
      end;
      Inc(P);
    end;
  end;
  Result.ColPtr[N] := Out;
  SetLength(Result.RowIdx, Out);
  SetLength(Result.V, Out);
end;

function SparseFromDense(A: TArrayObj): TSparseObj;
var
  I, J: TArray<Integer>;
  V: TArray<TComplex>;
  R, C: Integer;
  X: TComplex;
begin
  for C := 0 to A.Cols - 1 do
    for R := 0 to A.Rows - 1 do
    begin
      X := ToComplex(A.Get(C * A.Rows + R));
      if not IsZero(X) then
      begin
        I := I + [R];
        J := J + [C];
        V := V + [X];
      end;
    end;
  Result := FromTriplets(A.Rows, A.Cols, I, J, V, A.ElemType = etComplex);
end;

function SparseToDense(S: TSparseObj): TAxValue;
var
  A: TArrayObj;
  C, P: Integer;
begin
  if S.IsComplex then
    A := TArrayObj.Create(etComplex, S.Rows, S.Cols, False)
  else
    A := TArrayObj.Create(etReal, S.Rows, S.Cols, False);
  Result := ArrayValue(A);
  for C := 0 to S.Cols - 1 do
    for P := S.ColPtr[C] to S.ColPtr[C + 1] - 1 do
      if S.IsComplex then
        A.C[C * S.Rows + S.RowIdx[P]] := S.V[P]
      else
        A.R[C * S.Rows + S.RowIdx[P]] := S.V[P].Re;
end;

function Densify(const V: TAxValue): TAxValue;
begin
  if V.Kind = vkSparse then
    Result := SparseToDense(AsSparse(V))
  else
    Result := V;
end;

function SparseIdentity(M, N: Integer): TAxValue;
var
  I, J: TArray<Integer>;
  V: TArray<TComplex>;
  K: Integer;
begin
  SetLength(I, Min(M, N));
  SetLength(J, Min(M, N));
  SetLength(V, Min(M, N));
  for K := 0 to Min(M, N) - 1 do
  begin
    I[K] := K;
    J[K] := K;
    V[K] := Cx(1, 0);
  end;
  Result := SparseValue(FromTriplets(M, N, I, J, V, False));
end;

{ ---------------- sparse results ---------------- }

procedure SameSize(A, B: TSparseObj; const What: string);
begin
  if (A.Rows <> B.Rows) or (A.Cols <> B.Cols) then
    RaiseFmt(DimensionError, '%s: sizes %d' + #$00D7 + '%d and %d' + #$00D7 + '%d differ',
      [What, A.Rows, A.Cols, B.Rows, B.Cols]);
end;

{ A + Sign * B, column by column (a merge of sorted rows). }
function SparseAdd(A, B: TSparseObj; Sign: Double; const What: string): TAxValue;
var
  R: TSparseObj;
  C, PA, PB, EA, EB, Out: Integer;
  X: TComplex;
  Row: Integer;

  procedure Emit(Row: Integer; const X: TComplex);
  begin
    if IsZero(X) then
      Exit;
    R.RowIdx[Out] := Row;
    R.V[Out] := X;
    Inc(Out);
  end;

begin
  SameSize(A, B, What);
  R := TSparseObj.Create;
  Result := SparseValue(R);
  R.Rows := A.Rows;
  R.Cols := A.Cols;
  R.IsComplex := A.IsComplex or B.IsComplex;
  SetLength(R.ColPtr, A.Cols + 1);
  SetLength(R.RowIdx, A.Nnz + B.Nnz);
  SetLength(R.V, A.Nnz + B.Nnz);
  Out := 0;
  for C := 0 to A.Cols - 1 do
  begin
    R.ColPtr[C] := Out;
    PA := A.ColPtr[C];
    EA := A.ColPtr[C + 1];
    PB := B.ColPtr[C];
    EB := B.ColPtr[C + 1];
    while (PA < EA) or (PB < EB) do
    begin
      if (PB >= EB) or ((PA < EA) and (A.RowIdx[PA] < B.RowIdx[PB])) then
      begin
        Emit(A.RowIdx[PA], A.V[PA]);
        Inc(PA);
      end
      else if (PA >= EA) or (B.RowIdx[PB] < A.RowIdx[PA]) then
      begin
        Emit(B.RowIdx[PB], Cx(Sign * B.V[PB].Re, Sign * B.V[PB].Im));
        Inc(PB);
      end
      else
      begin
        Row := A.RowIdx[PA];
        X := CAdd(A.V[PA], Cx(Sign * B.V[PB].Re, Sign * B.V[PB].Im));
        Emit(Row, X);
        Inc(PA);
        Inc(PB);
      end;
    end;
  end;
  R.ColPtr[A.Cols] := Out;
  SetLength(R.RowIdx, Out);
  SetLength(R.V, Out);
end;

{ A .* B: only positions stored in both can be nonzero. }
function SparseElemMul(A, B: TSparseObj): TAxValue;
var
  R: TSparseObj;
  C, PA, PB, EA, EB, Out: Integer;
  X: TComplex;
begin
  SameSize(A, B, 'operator .*');
  R := TSparseObj.Create;
  Result := SparseValue(R);
  R.Rows := A.Rows;
  R.Cols := A.Cols;
  R.IsComplex := A.IsComplex or B.IsComplex;
  SetLength(R.ColPtr, A.Cols + 1);
  SetLength(R.RowIdx, Min(A.Nnz, B.Nnz));
  SetLength(R.V, Min(A.Nnz, B.Nnz));
  Out := 0;
  for C := 0 to A.Cols - 1 do
  begin
    R.ColPtr[C] := Out;
    PA := A.ColPtr[C];
    EA := A.ColPtr[C + 1];
    PB := B.ColPtr[C];
    EB := B.ColPtr[C + 1];
    while (PA < EA) and (PB < EB) do
      if A.RowIdx[PA] < B.RowIdx[PB] then
        Inc(PA)
      else if B.RowIdx[PB] < A.RowIdx[PA] then
        Inc(PB)
      else
      begin
        X := CMul(A.V[PA], B.V[PB]);
        if not IsZero(X) then
        begin
          R.RowIdx[Out] := A.RowIdx[PA];
          R.V[Out] := X;
          Inc(Out);
        end;
        Inc(PA);
        Inc(PB);
      end;
  end;
  R.ColPtr[A.Cols] := Out;
  SetLength(R.RowIdx, Out);
  SetLength(R.V, Out);
end;

{ Every stored value combined with a scalar: v * s, v / s or s \ v. }
function SparseScale(S: TSparseObj; const X: TAxValue; Divide: Boolean): TAxValue;
var
  R: TSparseObj;
  K, Out: Integer;
  Z, Y: TComplex;
begin
  if NumRank(X) < 0 then
    RaiseFmt(TypeError, 'cannot scale a sparse matrix by %s', [TypeName(X)]);
  Z := ToComplex(X);
  R := TSparseObj.Create;
  Result := SparseValue(R);
  R.Rows := S.Rows;
  R.Cols := S.Cols;
  R.IsComplex := S.IsComplex or (X.Kind = vkComplex);
  SetLength(R.ColPtr, S.Cols + 1);
  SetLength(R.RowIdx, S.Nnz);
  SetLength(R.V, S.Nnz);
  Out := 0;
  for K := 0 to S.Cols - 1 do
  begin
    R.ColPtr[K] := Out;
    for var P := S.ColPtr[K] to S.ColPtr[K + 1] - 1 do
    begin
      if Divide then Y := CDiv(S.V[P], Z) else Y := CMul(S.V[P], Z);
      // A zero scalar (or an underflow) would store zeros: drop them.
      if not IsZero(Y) then
      begin
        R.RowIdx[Out] := S.RowIdx[P];
        R.V[Out] := Y;
        Inc(Out);
      end;
    end;
  end;
  R.ColPtr[S.Cols] := Out;
  SetLength(R.RowIdx, Out);
  SetLength(R.V, Out);
end;

{ The sparse product A * B (Gustavson's algorithm). }
function SparseMul(A, B: TSparseObj): TAxValue;
var
  R: TSparseObj;
  Work: TArray<TComplex>;
  Mark, Pattern: TArray<Integer>;
  C, P, Q, K, I, NP, Out: Integer;
  Bv: TComplex;
begin
  if A.Cols <> B.Rows then
    RaiseFmt(DimensionError, 'matrix product: inner sizes %d and %d differ', [A.Cols, B.Rows]);
  R := TSparseObj.Create;
  Result := SparseValue(R);
  R.Rows := A.Rows;
  R.Cols := B.Cols;
  R.IsComplex := A.IsComplex or B.IsComplex;
  SetLength(R.ColPtr, B.Cols + 1);
  SetLength(Work, A.Rows);
  SetLength(Mark, A.Rows);
  SetLength(Pattern, A.Rows);
  for I := 0 to A.Rows - 1 do
    Mark[I] := -1;
  Out := 0;
  for C := 0 to B.Cols - 1 do
  begin
    R.ColPtr[C] := Out;
    NP := 0;
    for P := B.ColPtr[C] to B.ColPtr[C + 1] - 1 do
    begin
      K := B.RowIdx[P];
      Bv := B.V[P];
      for Q := A.ColPtr[K] to A.ColPtr[K + 1] - 1 do
      begin
        I := A.RowIdx[Q];
        if Mark[I] <> C then
        begin
          Mark[I] := C;
          Pattern[NP] := I;
          Inc(NP);
          Work[I] := CMul(A.V[Q], Bv);
        end
        else
          Work[I] := CAdd(Work[I], CMul(A.V[Q], Bv));
      end;
    end;
    TArray.Sort<Integer>(Pattern, TComparer<Integer>.Default, 0, NP);
    for P := 0 to NP - 1 do
    begin
      I := Pattern[P];
      if IsZero(Work[I]) then
        Continue;
      if Out >= Length(R.RowIdx) then
      begin
        SetLength(R.RowIdx, 2 * Out + A.Rows);
        SetLength(R.V, Length(R.RowIdx));
      end;
      R.RowIdx[Out] := I;
      R.V[Out] := Work[I];
      Inc(Out);
    end;
  end;
  R.ColPtr[B.Cols] := Out;
  SetLength(R.RowIdx, Out);
  SetLength(R.V, Out);
end;

function SparseTranspose(S: TSparseObj; Conjugate: Boolean): TAxValue;
var
  I, J: TArray<Integer>;
  V: TArray<TComplex>;
  C, P, K: Integer;
begin
  SetLength(I, S.Nnz);
  SetLength(J, S.Nnz);
  SetLength(V, S.Nnz);
  K := 0;
  for C := 0 to S.Cols - 1 do
    for P := S.ColPtr[C] to S.ColPtr[C + 1] - 1 do
    begin
      I[K] := C;
      J[K] := S.RowIdx[P];
      if Conjugate then V[K] := CConj(S.V[P]) else V[K] := S.V[P];
      Inc(K);
    end;
  Result := SparseValue(FromTriplets(S.Cols, S.Rows, I, J, V, S.IsComplex));
end;

{ ---------------- products with dense operands ---------------- }

function DenseOperand(const V: TAxValue; out Holder: TAxValue): TArrayObj;
begin
  if V.Kind = vkRange then
    Holder := ArrayValue(RangeToArray(AsRange(V)))
  else
    Holder := V;
  Result := AsArray(Holder);
end;

{ S * D with D dense: dense, a vector when D is a vector. }
function SparseTimesDense(S: TSparseObj; const D: TAxValue): TAxValue;
var
  H: TAxValue;
  X, R: TArrayObj;
  C, P, K: Integer;
  Cplx: Boolean;
  Acc: TArray<TComplex>;
  Xv: TComplex;
begin
  X := DenseOperand(D, H);
  if S.Cols <> X.Rows then
    RaiseFmt(DimensionError, 'matrix product: inner sizes %d and %d differ', [S.Cols, X.Rows]);
  Cplx := S.IsComplex or (X.ElemType = etComplex);
  if Cplx then
    R := TArrayObj.Create(etComplex, S.Rows, X.Cols, X.IsVector)
  else
    R := TArrayObj.Create(etReal, S.Rows, X.Cols, X.IsVector);
  Result := ArrayValue(R);
  SetLength(Acc, S.Rows);
  for C := 0 to X.Cols - 1 do
  begin
    for K := 0 to S.Rows - 1 do
      Acc[K] := Cx(0, 0);
    for K := 0 to S.Cols - 1 do
    begin
      Xv := ToComplex(X.Get(C * X.Rows + K));
      if IsZero(Xv) then
        Continue;
      for P := S.ColPtr[K] to S.ColPtr[K + 1] - 1 do
        Acc[S.RowIdx[P]] := CAdd(Acc[S.RowIdx[P]], CMul(S.V[P], Xv));
    end;
    for K := 0 to S.Rows - 1 do
      if Cplx then
        R.C[C * S.Rows + K] := Acc[K]
      else
        R.R[C * S.Rows + K] := Acc[K].Re;
  end;
end;

{ D * S with D dense: dense. }
function DenseTimesSparse(const D: TAxValue; S: TSparseObj): TAxValue;
var
  H: TAxValue;
  X, R: TArrayObj;
  C, P, I: Integer;
  Cplx: Boolean;
  Sv, Acc: TComplex;
begin
  X := DenseOperand(D, H);
  if X.Cols <> S.Rows then
    RaiseFmt(DimensionError, 'matrix product: inner sizes %d and %d differ', [X.Cols, S.Rows]);
  Cplx := S.IsComplex or (X.ElemType = etComplex);
  if Cplx then
    R := TArrayObj.Create(etComplex, X.Rows, S.Cols, False)
  else
    R := TArrayObj.Create(etReal, X.Rows, S.Cols, False);
  Result := ArrayValue(R);
  for C := 0 to S.Cols - 1 do
    for I := 0 to X.Rows - 1 do
    begin
      Acc := Cx(0, 0);
      for P := S.ColPtr[C] to S.ColPtr[C + 1] - 1 do
      begin
        Sv := S.V[P];
        Acc := CAdd(Acc, CMul(ToComplex(X.Get(S.RowIdx[P] * X.Rows + I)), Sv));
      end;
      if Cplx then
        R.C[C * X.Rows + I] := Acc
      else
        R.R[C * X.Rows + I] := Acc.Re;
    end;
  // A row vector times a sparse matrix stays a 1×n matrix.
end;

{ ---------------- solving ---------------- }

function SparseSolve(S: TSparseObj; const B: TAxValue): TAxValue;
var
  H: TAxValue;
  X, R: TArrayObj;
  F: TSparseLU;
  Col: TArray<TComplex>;
  C, K: Integer;
  Cplx: Boolean;
begin
  if B.Kind = vkSparse then
    Exit(SparseSolve(S, SparseToDense(AsSparse(B))));
  if NumRank(B) >= 0 then
  begin
    X := TArrayObj.Create(ElemTypeOf(B), 1, 1, False);
    H := ArrayValue(X);
    X.Put(0, B);
  end
  else
    X := DenseOperand(B, H);
  if S.Rows <> X.Rows then
    RaiseFmt(DimensionError, 'S \ b: S is %d' + #$00D7 + '%d but b has %d rows', [S.Rows, S.Cols, X.Rows]);
  // A non-square sparse system is solved in the least-squares sense, densely.
  if S.Rows <> S.Cols then
    Exit(SolveLeft(SparseToDense(S), H));
  Cplx := S.IsComplex or (X.ElemType = etComplex);
  if Cplx then
    R := TArrayObj.Create(etComplex, S.Cols, X.Cols, X.IsVector)
  else
    R := TArrayObj.Create(etReal, S.Cols, X.Cols, X.IsVector);
  Result := ArrayValue(R);
  if S.Rows = 0 then
    Exit;
  F := SparseFactor(S);
  try
    SetLength(Col, S.Rows);
    for C := 0 to X.Cols - 1 do
    begin
      for K := 0 to S.Rows - 1 do
        Col[K] := ToComplex(X.Get(C * X.Rows + K));
      F.Solve(Col);
      for K := 0 to S.Rows - 1 do
        if Cplx then
          R.C[C * S.Rows + K] := Col[K]
        else
          R.R[C * S.Rows + K] := Col[K].Re;
    end;
  finally
    F.Free;
  end;
end;

function SparseLUFactors(S: TSparseObj): TAxValues;
var
  F: TSparseLU;
  Prow: TArray<Integer>;
  LI, LJ, UI, UJ: TArray<Integer>;
  LV, UV: TArray<TComplex>;
  K, P, N: Integer;
begin
  if S.Rows <> S.Cols then
    RaiseFmt(DimensionError, 'lu of a sparse matrix needs a square matrix, got %d' + #$00D7 + '%d',
      [S.Rows, S.Cols]);
  N := S.Rows;
  F := SparseFactor(S);
  try
    // P A Q = L U, so A = (P' L)(U Q'): L's rows go back to A's row order and
    // U's columns to A's column order.
    SetLength(Prow, N);
    for K := 0 to N - 1 do
      Prow[F.Pinv[K]] := K;
    for K := 0 to N - 1 do
    begin
      for P := F.Lp[K] to F.Lp[K + 1] - 1 do
      begin
        LI := LI + [Prow[F.Li[P]]];
        LJ := LJ + [K];
        LV := LV + [F.Lx[P]];
      end;
      for P := F.Up[K] to F.Up[K + 1] - 1 do
      begin
        UI := UI + [F.Ui[P]];
        UJ := UJ + [F.Q[K]];
        UV := UV + [F.Ux[P]];
      end;
    end;
  finally
    F.Free;
  end;
  Result := [SparseValue(FromTriplets(N, N, LI, LJ, LV, S.IsComplex)),
             SparseValue(FromTriplets(N, N, UI, UJ, UV, S.IsComplex))];
end;

{ ---------------- operators ---------------- }

function IsScalarNumber(const V: TAxValue): Boolean; inline;
begin
  Result := NumRank(V) >= 0;
end;

function SparsePower(S: TSparseObj; const K: TAxValue): TAxValue;
var
  N: Int64;
  Base: TAxValue;
begin
  if S.Rows <> S.Cols then
    RaiseFmt(DimensionError, 'A ^ k needs a square matrix, got %d' + #$00D7 + '%d', [S.Rows, S.Cols]);
  // Non-negative integer powers stay sparse; anything else is dense.
  if not ((K.Kind in [vkBool, vkInt]) and (ToReal(K) >= 0)) then
    Exit(MatrixPower(SparseToDense(S), K));
  if K.Kind = vkBool then N := Ord(K.B) else N := K.I;
  Result := SparseIdentity(S.Rows, S.Cols);
  Base := SparseValue(S);
  while N > 0 do
  begin
    if Odd(N) then
      Result := SparseMul(AsSparse(Result), AsSparse(Base));
    N := N shr 1;
    if N > 0 then
      Base := SparseMul(AsSparse(Base), AsSparse(Base));
  end;
end;

function SparseBinaryOp(Op: TTokenKind; const A, B: TAxValue): TAxValue;
var
  SA, SB: Boolean;
begin
  SA := A.Kind = vkSparse;
  SB := B.Kind = vkSparse;

  if SA and SB then
    case Op of
      tkPlus:  Exit(SparseAdd(AsSparse(A), AsSparse(B), 1, 'operator +'));
      tkMinus: Exit(SparseAdd(AsSparse(A), AsSparse(B), -1, 'operator -'));
      tkDotStar: Exit(SparseElemMul(AsSparse(A), AsSparse(B)));
      tkStar:  Exit(SparseMul(AsSparse(A), AsSparse(B)));
      tkBackslash: Exit(SparseSolve(AsSparse(A), B));
      tkSlash:
        // A / B = (B' \ A')'
        Exit(Transpose(AsArray(SparseSolve(AsSparse(SparseTranspose(AsSparse(B), False)),
          SparseToDense(AsSparse(SparseTranspose(AsSparse(A), False))))), False));
    else
      Exit(BinaryOp(Op, SparseToDense(AsSparse(A)), SparseToDense(AsSparse(B))));
    end;

  if SA and IsScalarNumber(B) then
    case Op of
      tkStar, tkDotStar: Exit(SparseScale(AsSparse(A), B, False));
      tkSlash, tkDotSlash: Exit(SparseScale(AsSparse(A), B, True));
      tkCaret: Exit(SparsePower(AsSparse(A), B));
    end;
  if SB and IsScalarNumber(A) then
    case Op of
      tkStar, tkDotStar: Exit(SparseScale(AsSparse(B), A, False));
      tkBackslash, tkDotBackslash: Exit(SparseScale(AsSparse(B), A, True));
      tkCaret:
        RaiseError(TypeError, '^ raises a square matrix to a scalar power; use .^ for elementwise powers');
    end;

  // A sparse operand with a dense matrix, vector or range.
  if SA and (B.Kind in [vkArray, vkRange]) then
    case Op of
      tkStar: Exit(SparseTimesDense(AsSparse(A), B));
      tkBackslash: Exit(SparseSolve(AsSparse(A), B));
    end;
  if SB and (A.Kind in [vkArray, vkRange]) then
    case Op of
      tkStar: Exit(DenseTimesSparse(A, AsSparse(B)));
      tkSlash:
        // D / S = (S' \ D')'
        Exit(Transpose(AsArray(SparseSolve(AsSparse(SparseTranspose(AsSparse(B), False)),
          Transpose(ToArray(A), False))), False));
    end;

  // Everything else works on dense values.
  Result := BinaryOp(Op, Densify(A), Densify(B));
end;

function SparseUnaryOp(Op: TTokenKind; const A: TAxValue): TAxValue;
begin
  case Op of
    tkMinus: Result := SparseScale(AsSparse(A), IntValue(-1), False);
    tkPlus:  Result := A;
    tkQuote: Result := SparseTranspose(AsSparse(A), False);
  else
    Result := UnaryOp(Op, SparseToDense(AsSparse(A)));
  end;
end;

end.
