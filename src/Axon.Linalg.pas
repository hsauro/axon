unit Axon.Linalg;

(* The core linear-algebra operators (reference, "Linear-algebra operators"):
   A \ B and A / B through LAPACK, A ^ k for matrices, and the BLAS matrix
   product behind *. The linalg module (stdlib/linalg.sci) builds the rest in
   Axon on top of these and of its own extern declarations. *)

interface

uses
  Axon.Values;

{ A \ B: the solution of A X = B, least squares when A is not square. }
function SolveLeft(const A, B: TAxValue): TAxValue;
{ A / B, computed as (B' \ A')'. }
function SolveRight(const A, B: TAxValue): TAxValue;
{ A ^ K for a square matrix A and a scalar K. }
function MatrixPower(const A, K: TAxValue): TAxValue;
{ The product X * Y into Res (already sized) with dgemm/zgemm. Returns
  False, leaving Res untouched, when BLAS is unavailable or T is not real or
  complex. }
function BlasProduct(X, Y: TArrayObj; T: TElemType; Res: TArrayObj): Boolean;

implementation

uses
  System.SysUtils, System.Math,
  Axon.Errors, Axon.Complex, Axon.Ops, Axon.Arrays, Axon.Tokens,
  Axon.Native.Blas, Axon.Native.Lapack;

const
  MachineEps = 2.220446049250313e-16;

{ An operand as an array: ranges become vectors, scalars 1×1 matrices. The
  holder keeps a new object alive. }
function OperandArray(const V: TAxValue; out Holder: TAxValue; const What: string): TArrayObj;
var
  A: TArrayObj;
begin
  case V.Kind of
    vkArray:
      Holder := V;
    vkRange:
      Holder := ArrayValue(RangeToArray(AsRange(V)));
  else
    begin
      if NumRank(V) < 0 then
        RaiseFmt(TypeError, '%s: %s is not a matrix', [What, TypeName(V)]);
      A := TArrayObj.Create(ElemTypeOf(V), 1, 1, False);
      Holder := ArrayValue(A);
      A.Put(0, V);
    end;
  end;
  Result := AsArray(Holder);
end;

function RealBuffer(A: TArrayObj): TArray<Double>;
var
  K: Integer;
begin
  SetLength(Result, A.Count);
  for K := 0 to A.Count - 1 do
    Result[K] := ToReal(A.Get(K));
end;

function ComplexBuffer(A: TArrayObj): TArray<TComplex>;
var
  K: Integer;
begin
  SetLength(Result, A.Count);
  for K := 0 to A.Count - 1 do
    Result[K] := ToComplex(A.Get(K));
end;

function ShapeText(A: TArrayObj): string;
begin
  if A.IsVector then
    Result := Format('a %d-vector', [A.Rows])
  else
    Result := Format('a %d' + #$00D7 + '%d matrix', [A.Rows, A.Cols]);
end;

{ ---------------- A \ B ---------------- }

function SolveLeft(const A, B: TAxValue): TAxValue;
var
  HA, HB: TAxValue;
  XA, XB, Res: TArrayObj;
  M, N, NRhs, LdB, Rank, Info, I, J: Integer;
  Cplx, VecResult: Boolean;
  RA, RB, S: TArray<Double>;
  CA, CB: TArray<TComplex>;
  IPiv: TArray<Integer>;
  ANorm, RCond: Double;
begin
  XA := OperandArray(A, HA, 'A \ B');
  XB := OperandArray(B, HB, 'A \ B');
  M := XA.Rows;
  N := XA.Cols;
  NRhs := XB.Cols;
  if XB.Rows <> M then
    RaiseFmt(DimensionError, 'A \ B: A is %s but B has %d rows', [ShapeText(XA), XB.Rows]);
  Cplx := (XA.ElemType = etComplex) or (XB.ElemType = etComplex);
  VecResult := XB.IsVector or (B.Kind = vkRange);
  if Cplx then
    Res := TArrayObj.Create(etComplex, N, NRhs, VecResult)
  else
    Res := TArrayObj.Create(etReal, N, NRhs, VecResult);
  Result := ArrayValue(Res);
  if (M = 0) or (N = 0) or (NRhs = 0) then
    Exit;
  NeedLapack;

  if M = N then
  begin
    SetLength(IPiv, N);
    if Cplx then
    begin
      CA := ComplexBuffer(XA);
      CB := ComplexBuffer(XB);
      ANorm := LAPACKE_zlange(LapackColMajor, '1', N, N, @CA[0], N);
      Info := LAPACKE_zgetrf(LapackColMajor, N, N, @CA[0], N, @IPiv[0]);
      if Info > 0 then
        RaiseError(SingularMatrix, 'A \ B: the matrix is singular');
      LAPACKE_zgecon(LapackColMajor, '1', N, @CA[0], N, ANorm, @RCond);
      if RCond < MachineEps then
        RaiseFmt(SingularMatrix, 'A \ B: the matrix is singular to working precision (reciprocal condition number %s)',
          [FormatReal(RCond)]);
      LAPACKE_zgetrs(LapackColMajor, 'N', N, NRhs, @CA[0], N, @IPiv[0], @CB[0], N);
      for I := 0 to High(CB) do
        Res.C[I] := CB[I];
    end
    else
    begin
      RA := RealBuffer(XA);
      RB := RealBuffer(XB);
      ANorm := LAPACKE_dlange(LapackColMajor, '1', N, N, @RA[0], N);
      Info := LAPACKE_dgetrf(LapackColMajor, N, N, @RA[0], N, @IPiv[0]);
      if Info > 0 then
        RaiseError(SingularMatrix, 'A \ B: the matrix is singular');
      LAPACKE_dgecon(LapackColMajor, '1', N, @RA[0], N, ANorm, @RCond);
      if RCond < MachineEps then
        RaiseFmt(SingularMatrix, 'A \ B: the matrix is singular to working precision (reciprocal condition number %s)',
          [FormatReal(RCond)]);
      LAPACKE_dgetrs(LapackColMajor, 'N', N, NRhs, @RA[0], N, @IPiv[0], @RB[0], N);
      for I := 0 to High(RB) do
        Res.R[I] := RB[I];
    end;
    Exit;
  end;

  // Least squares (minimum norm) for a non-square A. B is padded to max(M, N) rows.
  LdB := Max(M, N);
  SetLength(S, Min(M, N));
  if Cplx then
  begin
    CA := ComplexBuffer(XA);
    SetLength(CB, LdB * NRhs);
    for J := 0 to NRhs - 1 do
      for I := 0 to M - 1 do
        CB[J * LdB + I] := ToComplex(XB.Get(J * M + I));
    Info := LAPACKE_zgelsd(LapackColMajor, M, N, NRhs, @CA[0], M, @CB[0], LdB, @S[0], -1, @Rank);
    if Info > 0 then
      RaiseError(DomainError, 'A \ B: the least-squares SVD did not converge');
    for J := 0 to NRhs - 1 do
      for I := 0 to N - 1 do
        Res.C[J * N + I] := CB[J * LdB + I];
  end
  else
  begin
    RA := RealBuffer(XA);
    SetLength(RB, LdB * NRhs);
    for J := 0 to NRhs - 1 do
      for I := 0 to M - 1 do
        RB[J * LdB + I] := ToReal(XB.Get(J * M + I));
    Info := LAPACKE_dgelsd(LapackColMajor, M, N, NRhs, @RA[0], M, @RB[0], LdB, @S[0], -1, @Rank);
    if Info > 0 then
      RaiseError(DomainError, 'A \ B: the least-squares SVD did not converge');
    for J := 0 to NRhs - 1 do
      for I := 0 to N - 1 do
        Res.R[J * N + I] := RB[J * LdB + I];
  end;
end;

{ ---------------- A / B ---------------- }

function SolveRight(const A, B: TAxValue): TAxValue;
var
  HA, HB: TAxValue;
  XA, XB: TArrayObj;
  X: TAxValue;
begin
  XA := OperandArray(A, HA, 'A / B');
  XB := OperandArray(B, HB, 'A / B');
  if XA.Cols <> XB.Cols then
    RaiseFmt(DimensionError, 'A / B: A is %s but B has %d columns', [ShapeText(XA), XB.Cols]);
  X := SolveLeft(Transpose(XB, False), Transpose(XA, False));
  Result := Transpose(AsArray(X), False);
end;

{ ---------------- A ^ k ---------------- }

function Identity(N: Integer; T: TElemType): TAxValue;
var
  I: Integer;
  A: TArrayObj;
begin
  if T = etBool then T := etInt;
  A := TArrayObj.Create(T, N, N, False);
  Result := ArrayValue(A);
  for I := 0 to N - 1 do
    A.Put(I * N + I, IntValue(1));
end;

function Converted(A: TArrayObj; T: TElemType): TAxValue;
var
  W: TArrayObj;
  K: Integer;
begin
  W := TArrayObj.Create(T, A.Rows, A.Cols, A.IsVector);
  Result := ArrayValue(W);
  for K := 0 to A.Count - 1 do
    W.Put(K, A.Get(K));
end;

function IntegerPower(const Base: TAxValue; N: Integer; K: Int64; T: TElemType): TAxValue;
var
  B: TAxValue;
begin
  // Repeated squaring.
  Result := Identity(N, T);
  B := Base;
  while K > 0 do
  begin
    if Odd(K) then
      Result := BinaryOp(tkStar, Result, B);
    K := K shr 1;
    if K > 0 then
      B := BinaryOp(tkStar, B, B);
  end;
end;

function EigenPower(XA: TArrayObj; const KC: TComplex; RealResult: Boolean): TAxValue;
var
  N, Info, I, J: Integer;
  CA, W, VR: TArray<TComplex>;
  BArr, VArr: TArrayObj;
  BV, VV, X: TAxValue;
  Res: TArrayObj;
  MaxIm, MaxAbs: Double;
begin
  NeedLapack;
  N := XA.Rows;
  CA := ComplexBuffer(XA);
  SetLength(W, N);
  SetLength(VR, N * N);
  Info := LAPACKE_zgeev(LapackColMajor, 'N', 'V', N, @CA[0], N, @W[0], nil, 1, @VR[0], N);
  if Info > 0 then
    RaiseError(DomainError, 'A ^ k: the eigenvalue computation did not converge');
  // X = V diag(w^k) V^-1, computed as (V diag(w^k)) / V.
  BArr := TArrayObj.Create(etComplex, N, N, False);
  BV := ArrayValue(BArr);
  VArr := TArrayObj.Create(etComplex, N, N, False);
  VV := ArrayValue(VArr);
  for J := 0 to N - 1 do
    for I := 0 to N - 1 do
    begin
      VArr.C[J * N + I] := VR[J * N + I];
      BArr.C[J * N + I] := CMul(VR[J * N + I], CPow(W[J], KC));
    end;
  try
    X := SolveRight(BV, VV);
  except
    on E: EAxonError do
      if E.Kind = SingularMatrix then
        RaiseError(SingularMatrix, 'A ^ k: the matrix is not diagonalisable')
      else
        raise;
  end;
  if not RealResult then
    Exit(X);
  // A real matrix to a real power: drop negligible imaginary parts.
  MaxIm := 0;
  MaxAbs := 0;
  for I := 0 to AsArray(X).Count - 1 do
  begin
    MaxIm := Max(MaxIm, Abs(AsArray(X).C[I].Im));
    MaxAbs := Max(MaxAbs, CAbs(AsArray(X).C[I]));
  end;
  if MaxIm > 1e-12 * Max(1.0, MaxAbs) then
    Exit(X);
  Res := TArrayObj.Create(etReal, N, N, False);
  Result := ArrayValue(Res);
  for I := 0 to Res.Count - 1 do
    Res.R[I] := AsArray(X).C[I].Re;
end;

function MatrixPower(const A, K: TAxValue): TAxValue;
var
  HA, Base: TAxValue;
  XA: TArrayObj;
  N: Integer;
  KI: Int64;
  T: TElemType;
begin
  XA := OperandArray(A, HA, 'A ^ k');
  if XA.Rows <> XA.Cols then
    RaiseFmt(DimensionError, 'A ^ k needs a square matrix, got %s', [ShapeText(XA)]);
  N := XA.Rows;
  if NumRank(K) < 0 then
    RaiseFmt(TypeError, 'A ^ k needs a scalar power, got %s', [TypeName(K)]);

  // Integer powers by repeated squaring.
  if (K.Kind in [vkBool, vkInt]) or ((K.Kind = vkReal) and (Frac(K.R) = 0) and (Abs(K.R) < 1e9)) then
  begin
    if K.Kind = vkBool then KI := Ord(K.B)
    else if K.Kind = vkInt then KI := K.I
    else KI := Trunc(K.R);
    T := XA.ElemType;
    if (K.Kind = vkReal) and (T < etReal) then
      T := etReal;
    if (KI < 0) and (T < etReal) then
      T := etReal;
    if T = etBool then
      T := etInt;
    Base := Converted(XA, T);
    if KI < 0 then
    begin
      Base := SolveLeft(Base, Identity(N, T));
      KI := -KI;
    end;
    Exit(IntegerPower(Base, N, KI, T));
  end;

  // Any other power through the eigendecomposition.
  Result := EigenPower(XA, ToComplex(K), (XA.ElemType <> etComplex) and (K.Kind <> vkComplex));
end;

{ ---------------- BLAS product ---------------- }

function BlasProduct(X, Y: TArrayObj; T: TElemType; Res: TArrayObj): Boolean;
var
  BufRX, BufRY: TArray<Double>;
  BufCX, BufCY: TArray<TComplex>;
  PX, PY: Pointer;
  Alpha, Beta: TComplex;
  M, N, K: Integer;
begin
  Result := False;
  if not (T in [etReal, etComplex]) or not BlasAvailable then
    Exit;
  M := X.Rows;
  K := X.Cols;
  N := Y.Cols;
  if (M = 0) or (N = 0) or (K = 0) then
    Exit(True);   // the result is already zero
  if T = etReal then
  begin
    if X.ElemType = etReal then PX := @X.R[0] else begin BufRX := RealBuffer(X); PX := @BufRX[0]; end;
    if Y.ElemType = etReal then PY := @Y.R[0] else begin BufRY := RealBuffer(Y); PY := @BufRY[0]; end;
    cblas_dgemm(CblasColMajor, CblasNoTrans, CblasNoTrans, M, N, K, 1.0,
      PX, M, PY, K, 0.0, @Res.R[0], M);
  end
  else
  begin
    if X.ElemType = etComplex then PX := @X.C[0] else begin BufCX := ComplexBuffer(X); PX := @BufCX[0]; end;
    if Y.ElemType = etComplex then PY := @Y.C[0] else begin BufCY := ComplexBuffer(Y); PY := @BufCY[0]; end;
    Alpha := Cx(1, 0);
    Beta := Cx(0, 0);
    cblas_zgemm(CblasColMajor, CblasNoTrans, CblasNoTrans, M, N, K, @Alpha,
      PX, M, PY, K, @Beta, @Res.C[0], M);
  end;
  Result := True;
end;

end.
