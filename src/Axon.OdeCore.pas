unit Axon.OdeCore;

(* odecore: the native loops behind stdlib/ode.sci (doc/Axon-JIT-Plan.md, J7).

   ode.sci keeps the API: it checks the arguments, builds the result record
   and sol.at. The loops run here, because in Axon each step's bookkeeping
   cost far more than the right-hand side.

   odecore.rk45(f, t0, t1, y0, o) is Dormand-Prince 5(4) with Hairer's dense
   output (DOPRI5), as the Axon code before it, operation for operation, so
   step counts and results are unchanged. It returns 14 values:

     t, Y                 the output points (a vector, and an n×k matrix)
     status               "success" or "event"
     t_events, y_events   per event: a vector of times and an n×m matrix
     nfev, nsteps
     T0, H, R1 .. R5      per accepted step: its start, length and the five
                          dense-output coefficient columns (n×steps), from
                          which ode.sci evaluates sol.at

   odecore.bdf(f, t0, t1, y0, o) is the same loop around SUNDIALS CVODE
   (variable-order BDF, dense direct linear solver), one CVODE step at a
   time, with CVODE's own interpolant for t_eval and its root finding for
   events. It returns the same values, with YA, YB, DA, DB (the step's start
   and end states and derivatives, for a cubic Hermite sol.at) in place of
   R1 .. R5. The right-hand side and root callbacks are Delphi functions
   that find their solve through CVODE's user data, so solves nest; they
   never let an exception escape into CVODE, but keep it and return -1, and
   the loop raises it when CVODE returns.

   f and the event functions are called as the interpreter calls them
   (CallAxon), with o.params as a third argument when it is not nothing; f's result is checked as call_rhs checked it, except that a
   scalar is accepted for one equation, as the reference says. *)

interface

implementation

uses
  System.SysUtils, System.Math, System.Generics.Collections,
  Axon.Errors, Axon.Values, Axon.Ops, Axon.Arrays, Axon.NativeModules, Axon.Native.Cvode;

type
  TVec = TArray<Double>;

const
  EPS = 2.220446049250313e-16;

procedure Fail(const Kind, Msg: string);
begin
  raise EAxonError.Create(Kind, 'ode.solve: ' + Msg);
end;

function Str(const V: TAxValue): string;
begin
  Result := Display(V);
end;

function RStr(X: Double): string;
begin
  Result := Display(RealValue(X));
end;

function VectorValue(const X: TVec): TAxValue;
var
  A: TArrayObj;
begin
  A := TArrayObj.Create(etReal, Length(X), 1, True);
  Result := ArrayValue(A);
  if Length(X) > 0 then
    Move(X[0], A.R[0], Length(X) * SizeOf(Double));
end;

{ An n×cols matrix from the first n*cols values of Data (column-major). }
function MatrixValue(N, Cols: Integer; const Data: TVec): TAxValue;
var
  A: TArrayObj;
begin
  A := TArrayObj.Create(etReal, N, Cols, False);
  Result := ArrayValue(A);
  if N * Cols > 0 then
    Move(Data[0], A.R[0], N * Cols * SizeOf(Double));
end;

function Field(const R: TAxValue; const Name: string): TAxValue;
var
  K: Integer;
begin
  K := AsRecord(R).IndexOf(Name);
  if K < 0 then
    raise EAxonError.Create(TypeError, 'odecore: no field ' + Name);
  Result := AsRecord(R).Values[K];
end;

{ A real vector's values (t_eval, y0). }
function RealsOf(const V: TAxValue): TVec;
var
  A: TArrayObj;
  K: Integer;
begin
  A := AsArray(V);
  SetLength(Result, A.Count);
  for K := 0 to A.Count - 1 do
    Result[K] := ToReal(A.Get(K));
end;

{ max and min as the built-ins compute them on reals (MinMax): NaN if
  either is NaN. }
function RMax(X, Y: Double): Double;
begin
  if IsNan(X) or IsNan(Y) then Result := NaN else Result := Max(X, Y);
end;

function RMin(X, Y: Double): Double;
begin
  if IsNan(X) or IsNan(Y) then Result := NaN else Result := Min(X, Y);
end;

{ x ^ y as RealArith. }
function RPow(X, Y: Double): Double;
begin
  if (X < 0) and (Frac(Y) <> 0) then Result := NaN else Result := Power(X, Y);
end;

{ wrms(v, w) = sqrt(sum((v ./ w) .^ 2) / length(v)), summed left to right. }
function Wrms(const V, W: TVec): Double;
var
  K: Integer;
  S: Double;
begin
  S := 0;
  for K := 0 to High(V) do
    S := S + RPow(V[K] / W[K], 2);
  Result := Sqrt(S / Length(V));
end;

type
  { Per-step dense output and the growing output, as columns. }
  TColumns = class
  public
    N, Count: Integer;
    Data: TVec;
    constructor Create(AN: Integer);
    procedure Add(const Col: TVec);
    function Value: TAxValue;
  end;

  TReals = class
  public
    Count: Integer;
    Data: TVec;
    procedure Add(X: Double);
    function Value: TAxValue;
  end;

constructor TColumns.Create(AN: Integer);
begin
  inherited Create;
  N := AN;
  SetLength(Data, 64 * N);
end;

procedure TColumns.Add(const Col: TVec);
begin
  if (Count + 1) * N > Length(Data) then
    SetLength(Data, 2 * Length(Data) + N);
  if N > 0 then
    Move(Col[0], Data[Count * N], N * SizeOf(Double));
  Inc(Count);
end;

function TColumns.Value: TAxValue;
begin
  Result := MatrixValue(N, Count, Data);
end;

procedure TReals.Add(X: Double);
begin
  if Count >= Length(Data) then
    SetLength(Data, 2 * Length(Data) + 64);
  Data[Count] := X;
  Inc(Count);
end;

function TReals.Value: TAxValue;
begin
  Result := VectorValue(Copy(Data, 0, Count));
end;

type
  { What both loops share: the problem, and calling f and the events. }
  TOdeBase = class
  protected
    F: TAxValue;
    // ode.solve's params: when given, f and the event functions are called
    // as f(t, y, params).
    Params: TAxValue;
    HasParams: Boolean;
    N: Integer;
    S: Double;                   // the direction, 1 or -1
    Events: TAxValues;
    Terminal, Direction: TAxValues;
    NFev: Int64;
    // Per accepted step: its start and length
    T0s, Hs: TReals;
    function Rhs(T: Double; const Y: TVec): TVec;
    function Event(K: Integer; T: Double; const Y: TVec): Double;
  public
    constructor Create(N0: Integer);
    destructor Destroy; override;
  end;

  TRk45 = class(TOdeBase)
  private
    R1, R2, R3, R4, R5: TColumns;
    function DenseAt(J: Integer; Tq: Double): TVec;
    function Locate(K, J: Integer; Ta, Ga, Tb, Gb: Double): Double;
  public
    constructor Create(N0: Integer);
    destructor Destroy; override;
    function Run(const Args: TAxValues): TAxValues;
  end;

constructor TOdeBase.Create(N0: Integer);
begin
  inherited Create;
  N := N0;
  T0s := TReals.Create;
  Hs := TReals.Create;
end;

destructor TOdeBase.Destroy;
begin
  T0s.Free;
  Hs.Free;
  inherited;
end;

constructor TRk45.Create(N0: Integer);
begin
  inherited Create(N0);
  R1 := TColumns.Create(N);
  R2 := TColumns.Create(N);
  R3 := TColumns.Create(N);
  R4 := TColumns.Create(N);
  R5 := TColumns.Create(N);
end;

destructor TRk45.Destroy;
begin
  R1.Free;
  R2.Free;
  R3.Free;
  R4.Free;
  R5.Free;
  inherited;
end;

{ f(t, y) as a real vector of length n, checked as call_rhs checked it. }
function TOdeBase.Rhs(T: Double; const Y: TVec): TVec;
var
  D: TAxValue;
  TN: string;
  A: TArrayObj;
  K: Integer;
begin
  if HasParams then
    D := CallAxon(F, [RealValue(T), VectorValue(Y), Params])
  else
    D := CallAxon(F, [RealValue(T), VectorValue(Y)]);
  TN := TypeName(D);
  if (TN <> 'vector') and (TN <> 'matrix') and (TN <> 'real') and (TN <> 'int') then
    Fail(TypeError, 'the right-hand side must return a real vector, got ' + TN);
  if D.Kind <> vkArray then
  begin
    // A scalar, for one equation.
    if N <> 1 then
      Fail(DimensionError, Format('the right-hand side returned 1 values, but y0 has %d', [N]));
    SetLength(Result, 1);
    Result[0] := ToReal(D);
    Exit;
  end;
  A := AsArray(D);
  if A.Count <> N then
    Fail(DimensionError, Format('the right-hand side returned %d values, but y0 has %d', [A.Count, N]));
  if A.ElemType = etComplex then
    Fail(TypeError, 'the right-hand side must return real values');
  if A.ElemType = etReal then
  begin
    Result := Copy(A.R, 0, N);
    Exit;
  end;
  SetLength(Result, N);
  for K := 0 to N - 1 do
    Result[K] := ToReal(A.Get(K));
end;

{ Event function K (1-based) at (t, y), as call_event. }
function TOdeBase.Event(K: Integer; T: Double; const Y: TVec): Double;
var
  V: TAxValue;
begin
  if HasParams then
    V := CallAxon(Events[K - 1], [RealValue(T), VectorValue(Y), Params])
  else
    V := CallAxon(Events[K - 1], [RealValue(T), VectorValue(Y)]);
  if (V.Kind <> vkReal) and (V.Kind <> vkInt) then
    Fail(TypeError, Format('event function %d must return a real number, got %s', [K, TypeName(V)]));
  Result := ToReal(V);
end;

{ y at tq on accepted step J (0-based): DOPRI5's dense output. }
function TRk45.DenseAt(J: Integer; Tq: Double): TVec;
var
  Th, Th1: Double;
  K, B: Integer;
begin
  Th := (Tq - T0s.Data[J]) / Hs.Data[J];
  Th1 := 1 - Th;
  SetLength(Result, N);
  B := J * N;
  for K := 0 to N - 1 do
    Result[K] := R1.Data[B + K] + Th * (R2.Data[B + K] + Th1 * (R3.Data[B + K] +
      Th * (R4.Data[B + K] + Th1 * R5.Data[B + K])));
end;

{ The time in [ta, tb] where event K crosses zero, on step J's dense output
  (Illinois method), as locate. }
function TRk45.Locate(K, J: Integer; Ta, Ga, Tb, Gb: Double): Double;
var
  A, Fa, B, Fb, C, Fc: Double;
  Side, It: Integer;
begin
  A := Ta;
  Fa := Ga;
  B := Tb;
  Fb := Gb;
  if Fb = 0 then
    Exit(B);
  Side := 0;
  for It := 1 to 200 do
  begin
    C := (A * Fb - B * Fa) / (Fb - Fa);
    Fc := Event(K, C, DenseAt(J, C));
    if Fc = 0 then
      Exit(C);
    if (Fc > 0) = (Fb > 0) then
    begin
      B := C;
      Fb := Fc;
      if Side = -1 then Fa := Fa / 2;
      Side := -1;
    end
    else
    begin
      A := C;
      Fa := Fc;
      if Side = 1 then Fb := Fb / 2;
      Side := 1;
    end;
    if Abs(B - A) <= 4 * EPS * RMax(Abs(A), Abs(B)) + 1e-300 then
      Exit(B);
  end;
  Result := B;
end;

{ A condition that must be a bool, as `if` requires. }
function Truth(const V: TAxValue): Boolean;
begin
  if V.Kind <> vkBool then
    RaiseFmt(TypeError, 'the condition of "if" must be a bool, got %s', [TypeName(V)]);
  Result := V.B;
end;

{ crosses(ga, gb, dir): a zero crossing of an event in the given direction. }
function Crosses(Ga, Gb: Double; const Dir: TAxValue): Boolean;
var
  Up, Down: Boolean;
  D: Double;
begin
  if Ga = 0 then
    Exit(False);
  Up := (Ga < 0) and (Gb >= 0);
  Down := (Ga > 0) and (Gb <= 0);
  if NumRank(Dir) < 0 then
    RaiseFmt(TypeError, 'operator > is not defined for %s and int', [TypeName(Dir)]);
  D := ToReal(Dir);
  if D > 0 then Exit(Up);
  if D < 0 then Exit(Down);
  Result := Up or Down;
end;

type
  TFound = record
    K: Integer;
    T: Double;
  end;

function TRk45.Run(const Args: TAxValues): TAxValues;
var
  O, TEvalV, FirstStep, AtolV: TAxValue;
  T0, T1, T, H, H0, H1, D0, D1, D2, Hs_, TNew, Err, Facmax, Fac, Rtol, MaxStep,
    TStop, Te, Ga: Double;
  Y, K1, K2, K3, K4, K5, K6, K7, YNew, ErrV, Sk, Y1, F1, Tmp, YDiff, Bspl, Col, YStop, Ye: TVec;
  AtolK: TVec;   // the absolute tolerance of each component
  TEval: TVec;
  HasTEval, Last, Done: Boolean;
  MaxSteps, NSteps: Int64;
  NextEval, Ng, I, K, A, B: Integer;
  Status: string;
  GOld: TVec;
  TeList: TArray<TReals>;
  YeList: TArray<TColumns>;
  Found: TList<TFound>;
  Fd, Swap: TFound;
  OutT: TReals;
  OutY: TColumns;
  StepIdx: Integer;
  ListT, ListY: TAxValues;

  procedure AddPoint(Tp: Double; const Yp: TVec);
  begin
    OutT.Add(Tp);
    OutY.Add(Yp);
  end;

  { add_step_output: the step end, or the requested times inside the step. }
  procedure AddStepOutput(TEnd: Double; const YEnd: TVec);
  var
    Tq: Double;
  begin
    if not HasTEval then
    begin
      AddPoint(TEnd, YEnd);
      Exit;
    end;
    while (NextEval < Length(TEval)) and (S * (TEval[NextEval] - TEnd) <= 0) do
    begin
      Tq := TEval[NextEval];
      if Tq = TEnd then
        AddPoint(Tq, YEnd)
      else
        AddPoint(Tq, DenseAt(StepIdx, Tq));
      Inc(NextEval);
    end;
  end;

begin
  F := Args[0];
  T0 := ToReal(Args[1]);
  T1 := ToReal(Args[2]);
  Y := RealsOf(Args[3]);
  O := Args[4];
  Rtol := ToReal(Field(O, 'rtol'));
  // atol: one number for every component, or one each (ode.sci checked it).
  AtolV := Field(O, 'atol');
  if AtolV.Kind = vkArray then
    AtolK := RealsOf(AtolV)
  else
  begin
    SetLength(AtolK, Length(Y));
    for I := 0 to High(AtolK) do
      AtolK[I] := ToReal(AtolV);
  end;
  MaxStep := ToReal(Field(O, 'max_step'));
  MaxSteps := Field(O, 'max_steps').I;
  FirstStep := Field(O, 'first_step');
  TEvalV := Field(O, 't_eval');
  HasTEval := TEvalV.Kind <> vkNothing;
  if HasTEval then
    TEval := RealsOf(TEvalV);
  Events := AsList(Field(O, 'events')).Items;
  Terminal := AsList(Field(O, 'terminal')).Items;
  Direction := AsList(Field(O, 'direction')).Items;
  Params := Field(O, 'params');
  HasParams := Params.Kind <> vkNothing;
  Ng := Length(Events);

  S := 1.0;
  if T1 < T0 then S := -1.0;
  OutT := TReals.Create;
  OutY := TColumns.Create(N);
  Found := TList<TFound>.Create;
  SetLength(TeList, Ng);
  SetLength(YeList, Ng);
  for K := 0 to Ng - 1 do
  begin
    TeList[K] := TReals.Create;
    YeList[K] := TColumns.Create(N);
  end;
  try
    NextEval := 0;
    if not HasTEval then
      AddPoint(T0, Y)
    else
      while (NextEval < Length(TEval)) and (TEval[NextEval] = T0) do
      begin
        AddPoint(T0, Y);
        Inc(NextEval);
      end;

    T := T0;
    K1 := Rhs(T, Y);
    NFev := 1;
    SetLength(Sk, N);
    SetLength(Tmp, N);

    // Initial step (Hairer and Wanner, II.4).
    if FirstStep.Kind = vkNothing then
    begin
      for I := 0 to N - 1 do
        Sk[I] := AtolK[I] + Rtol * Abs(Y[I]);
      D0 := Wrms(Y, Sk);
      D1 := Wrms(K1, Sk);
      if (D0 < 1e-5) or (D1 < 1e-5) then
        H0 := 1e-6
      else
        H0 := 0.01 * D0 / D1;
      H0 := RMin(H0, Abs(T1 - T0));
      SetLength(Y1, N);
      for I := 0 to N - 1 do
        Y1[I] := Y[I] + S * H0 * K1[I];
      F1 := Rhs(T + S * H0, Y1);
      Inc(NFev);
      for I := 0 to N - 1 do
        Tmp[I] := F1[I] - K1[I];
      D2 := Wrms(Tmp, Sk) / H0;
      if RMax(D1, D2) <= 1e-15 then
        H1 := RMax(1e-6, H0 * 1e-3)
      else
        H1 := RPow(0.01 / RMax(D1, D2), 0.2);
      H := RMin(100 * H0, H1);
    end
    else
      H := ToReal(FirstStep);
    H := RMin(RMin(Abs(H), MaxStep), Abs(T1 - T0));

    SetLength(GOld, Max(Ng, 1));
    for K := 1 to Ng do
      GOld[K - 1] := Event(K, T, Y);

    Status := 'success';
    Facmax := 10.0;
    Done := False;
    NSteps := 0;
    SetLength(ErrV, N);
    SetLength(YNew, N);
    SetLength(YDiff, N);
    SetLength(Bspl, N);
    SetLength(Col, N);
    while not Done do
    begin
      if NSteps >= MaxSteps then
        Fail('SolverError', 'more than ' + Str(IntValue(MaxSteps)) + ' steps before t = ' +
          RStr(T1) + ' (stopped at t = ' + RStr(T) + ')');
      if H < 16 * EPS * RMax(Abs(T), 1e-300) then
        Fail('SolverError', 'the step size became too small at t = ' + RStr(T));
      Last := False;
      if H >= Abs(T1 - T) then
      begin
        H := Abs(T1 - T);
        Last := True;
      end;
      Hs_ := S * H;

      for I := 0 to N - 1 do
        Tmp[I] := Y[I] + Hs_ * (K1[I] / 5);
      K2 := Rhs(T + Hs_ / 5, Tmp);
      for I := 0 to N - 1 do
        Tmp[I] := Y[I] + Hs_ * (3 / 40 * K1[I] + 9 / 40 * K2[I]);
      K3 := Rhs(T + 3 * Hs_ / 10, Tmp);
      for I := 0 to N - 1 do
        Tmp[I] := Y[I] + Hs_ * (44 / 45 * K1[I] - 56 / 15 * K2[I] + 32 / 9 * K3[I]);
      K4 := Rhs(T + 4 * Hs_ / 5, Tmp);
      for I := 0 to N - 1 do
        Tmp[I] := Y[I] + Hs_ * (19372 / 6561 * K1[I] - 25360 / 2187 * K2[I] +
          64448 / 6561 * K3[I] - 212 / 729 * K4[I]);
      K5 := Rhs(T + 8 * Hs_ / 9, Tmp);
      for I := 0 to N - 1 do
        Tmp[I] := Y[I] + Hs_ * (9017 / 3168 * K1[I] - 355 / 33 * K2[I] + 46732 / 5247 * K3[I] +
          49 / 176 * K4[I] - 5103 / 18656 * K5[I]);
      K6 := Rhs(T + Hs_, Tmp);
      for I := 0 to N - 1 do
        YNew[I] := Y[I] + Hs_ * (35 / 384 * K1[I] + 500 / 1113 * K3[I] + 125 / 192 * K4[I] -
          2187 / 6784 * K5[I] + 11 / 84 * K6[I]);
      TNew := T + Hs_;
      if Last then TNew := T1;
      K7 := Rhs(TNew, YNew);
      Inc(NFev, 6);
      for I := 0 to N - 1 do
      begin
        ErrV[I] := Hs_ * (71 / 57600 * K1[I] - 71 / 16695 * K3[I] + 71 / 1920 * K4[I] -
          17253 / 339200 * K5[I] + 22 / 525 * K6[I] - 1 / 40 * K7[I]);
        Sk[I] := AtolK[I] + Rtol * RMax(Abs(Y[I]), Abs(YNew[I]));
      end;
      Err := Wrms(ErrV, Sk);
      if Err <> Err then
        Fail('SolverError', 'the solution is not finite at t = ' + RStr(T));

      if Err > 1 then
      begin
        // Rejected: retry with a smaller step.
        H := H * RMax(0.2, 0.9 * RPow(Err, -0.2));
        Facmax := 1.0;
        Continue;
      end;

      // Accepted.
      Inc(NSteps);
      for I := 0 to N - 1 do
      begin
        YDiff[I] := YNew[I] - Y[I];
        Bspl[I] := Hs_ * K1[I] - YDiff[I];
      end;
      T0s.Add(T);
      Hs.Add(TNew - T);
      R1.Add(Y);
      R2.Add(YDiff);
      R3.Add(Bspl);
      for I := 0 to N - 1 do
        Col[I] := YDiff[I] - Hs_ * K7[I] - Bspl[I];
      R4.Add(Col);
      for I := 0 to N - 1 do
        Col[I] := Hs_ * (-12715105075 / 11282082432 * K1[I] + 87487479700 / 32700410799 * K3[I] -
          10690763975 / 1880347072 * K4[I] + 701980252875 / 199316789632 * K5[I] -
          1453857185 / 822651844 * K6[I] + 69997945 / 29380423 * K7[I]);
      R5.Add(Col);
      StepIdx := T0s.Count - 1;

      // Events in this step, earliest first.
      TStop := TNew;
      YStop := YNew;
      Found.Clear;
      for K := 1 to Ng do
      begin
        Ga := Event(K, TNew, YNew);
        if Crosses(GOld[K - 1], Ga, Direction[K - 1]) then
        begin
          Fd.K := K;
          Fd.T := Locate(K, StepIdx, T, GOld[K - 1], TNew, Ga);
          Found.Add(Fd);
        end;
        GOld[K - 1] := Ga;
      end;
      if Found.Count > 0 then
      begin
        // Sort by time in the direction of integration (insertion sort).
        for A := 1 to Found.Count - 1 do
        begin
          B := A;
          while (B > 0) and (S * (Found[B].T - Found[B - 1].T) < 0) do
          begin
            Swap := Found[B];
            Found[B] := Found[B - 1];
            Found[B - 1] := Swap;
            Dec(B);
          end;
        end;
        for Fd in Found do
        begin
          Te := Fd.T;
          Ye := DenseAt(StepIdx, Te);
          TeList[Fd.K - 1].Add(Te);
          YeList[Fd.K - 1].Add(Ye);
          if Truth(Terminal[Fd.K - 1]) then
          begin
            TStop := Te;
            YStop := Ye;
            Status := 'event';
            Break;
          end;
        end;
      end;

      AddStepOutput(TStop, YStop);
      if Status = 'event' then
      begin
        Hs.Data[StepIdx] := TStop - T;
        Break;
      end;

      T := TNew;
      Y := Copy(YNew);
      K1 := K7;
      if Last then
        Done := True
      else
      begin
        Fac := RMin(Facmax, RMax(0.2, 0.9 * RPow(Err, -0.2)));
        if Err = 0 then Fac := Facmax;
        H := RMin(H * Fac, MaxStep);
        Facmax := 10.0;
      end;
    end;

    SetLength(ListT, Ng);
    SetLength(ListY, Ng);
    for K := 0 to Ng - 1 do
    begin
      ListT[K] := TeList[K].Value;
      ListY[K] := YeList[K].Value;
    end;
    Result := [OutT.Value, OutY.Value, StringValue(Status), ListValue(ListT), ListValue(ListY),
      IntValue(NFev), IntValue(NSteps), T0s.Value, Hs.Value, R1.Value, R2.Value, R3.Value,
      R4.Value, R5.Value];
  finally
    for K := 0 to Ng - 1 do
    begin
      TeList[K].Free;
      YeList[K].Free;
    end;
    Found.Free;
    OutT.Free;
    OutY.Free;
  end;
end;

function BRk45(const Args: TAxValues): TAxValues;
var
  R: TRk45;
begin
  R := TRk45.Create(AsArray(Args[3]).Count);
  try
    Result := R.Run(Args);
  finally
    R.Free;
  end;
end;

{ ---------------------------------------------------------------- BDF }

type
  TBdf = class(TOdeBase)
  private
    YA, YB, DA, DB: TColumns;
    Mem: Pointer;
    Dky: Pointer;
    Pending: Exception;          // raised in a callback, re-raised by the loop
    procedure Check(Flag: Integer; const What: string);
    function NativeVector(V: Pointer): TVec;
    function Interpolant(Tq: Double): TVec;
  public
    constructor Create(N0: Integer);
    destructor Destroy; override;
    function Run(const Args: TAxValues): TAxValues;
  end;

function FlagName(Flag: Integer): string;
begin
  Result := string(AnsiString(CVodeGetReturnFlagName(Flag)));
end;

{ y' = f(t, y) for CVODE. }
function CvRhs(T: Double; Y, YDot, User: Pointer): Integer; cdecl;
var
  B: TBdf;
  D: TVec;
begin
  B := TBdf(User);
  try
    D := B.Rhs(T, B.NativeVector(Y));
    if B.N > 0 then
      Move(D[0], N_VGetArrayPointer(YDot)^, B.N * SizeOf(Double));
    Inc(B.NFev);
    Result := 0;
  except
    B.Pending := AcquireExceptionObject as Exception;
    Result := -1;
  end;
end;

{ The event functions for CVODE's root finding. }
function CvRoots(T: Double; Y: Pointer; GOut: PDouble; User: Pointer): Integer; cdecl;
var
  B: TBdf;
  Yv: TVec;
  K: Integer;
begin
  B := TBdf(User);
  try
    Yv := B.NativeVector(Y);
    for K := 1 to Length(B.Events) do
    begin
      GOut^ := B.Event(K, T, Yv);
      Inc(GOut);
    end;
    Result := 0;
  except
    B.Pending := AcquireExceptionObject as Exception;
    Result := -1;
  end;
end;

constructor TBdf.Create(N0: Integer);
begin
  inherited Create(N0);
  YA := TColumns.Create(N);
  YB := TColumns.Create(N);
  DA := TColumns.Create(N);
  DB := TColumns.Create(N);
end;

destructor TBdf.Destroy;
begin
  YA.Free;
  YB.Free;
  DA.Free;
  DB.Free;
  inherited;
end;

{ cvode_check: a negative flag is a SolverError naming the call. }
procedure TBdf.Check(Flag: Integer; const What: string);
begin
  if Flag < 0 then
    Fail('SolverError', 'CVODE ' + What + ' failed (' + FlagName(Flag) + ')');
end;

function TBdf.NativeVector(V: Pointer): TVec;
begin
  SetLength(Result, N);
  if N > 0 then
    Move(N_VGetArrayPointer(V)^, Result[0], N * SizeOf(Double));
end;

{ y at tq from CVODE's interpolant over the last step. }
function TBdf.Interpolant(Tq: Double): TVec;
begin
  Check(CVodeGetDky(Mem, Tq, 0, Dky), 'CVodeGetDky');
  Result := NativeVector(Dky);
end;

function TBdf.Run(const Args: TAxValues): TAxValues;
var
  O, TEvalV, FirstStep, AtolV: TAxValue;
  T0, T1, T, TRet, Rtol, MaxStep: Double;
  Y, Dy, YNew, DNew, AtolK: TVec;
  AtolN: Pointer;     // CVODE's vector of per-component tolerances, or nil
  TEval: TVec;
  HasTEval: Boolean;
  MaxSteps, NSteps: Int64;
  NextEval, Ng, K, Flag, Dir: Integer;
  Status: string;
  Roots: TArray<Integer>;
  TeList: TArray<TReals>;
  YeList: TArray<TColumns>;
  OutT: TReals;
  OutY: TColumns;
  Ctx, Yv, A, LS: Pointer;
  ListT, ListY: TAxValues;
  E: Exception;

  procedure AddPoint(Tp: Double; const Yp: TVec);
  begin
    OutT.Add(Tp);
    OutY.Add(Yp);
  end;

  procedure AddStepOutput(TEnd: Double; const YEnd: TVec);
  var
    Tq: Double;
  begin
    if not HasTEval then
    begin
      AddPoint(TEnd, YEnd);
      Exit;
    end;
    while (NextEval < Length(TEval)) and (S * (TEval[NextEval] - TEnd) <= 0) do
    begin
      Tq := TEval[NextEval];
      if Tq = TEnd then
        AddPoint(Tq, YEnd)
      else
        AddPoint(Tq, Interpolant(Tq));
      Inc(NextEval);
    end;
  end;

begin
  if not CvodeAvailable then
    RaiseError(ForeignError, CvodeError);
  F := Args[0];
  T0 := ToReal(Args[1]);
  T1 := ToReal(Args[2]);
  Y := RealsOf(Args[3]);
  O := Args[4];
  Rtol := ToReal(Field(O, 'rtol'));
  AtolV := Field(O, 'atol');
  MaxStep := ToReal(Field(O, 'max_step'));
  MaxSteps := Field(O, 'max_steps').I;
  FirstStep := Field(O, 'first_step');
  TEvalV := Field(O, 't_eval');
  HasTEval := TEvalV.Kind <> vkNothing;
  if HasTEval then
    TEval := RealsOf(TEvalV);
  Events := AsList(Field(O, 'events')).Items;
  Terminal := AsList(Field(O, 'terminal')).Items;
  Direction := AsList(Field(O, 'direction')).Items;
  Params := Field(O, 'params');
  HasParams := Params.Kind <> vkNothing;
  Ng := Length(Events);
  S := 1.0;
  if T1 < T0 then S := -1.0;

  Ctx := nil;
  Mem := nil;
  AtolN := nil;
  Yv := nil;
  Dky := nil;
  A := nil;
  LS := nil;
  OutT := TReals.Create;
  OutY := TColumns.Create(N);
  SetLength(TeList, Ng);
  SetLength(YeList, Ng);
  for K := 0 to Ng - 1 do
  begin
    TeList[K] := TReals.Create;
    YeList[K] := TColumns.Create(N);
  end;
  try
    Check(SUNContext_Create(nil, Ctx), 'SUNContext_Create');
    // Failures come back as return codes; SUNDIALS should not also print them.
    SUNContext_ClearErrHandlers(Ctx);
    Yv := N_VNew_Serial(N, Ctx);
    Dky := N_VNew_Serial(N, Ctx);
    A := SUNDenseMatrix(N, N, Ctx);
    LS := SUNLinSol_Dense(Yv, A, Ctx);
    Move(Y[0], N_VGetArrayPointer(Yv)^, N * SizeOf(Double));
    Mem := CVodeCreate(CV_BDF, Ctx);
    Check(CVodeInit(Mem, CvRhs, T0, Yv), 'CVodeInit');
    Check(CVodeSetUserData(Mem, Self), 'CVodeSetUserData');
    // One absolute tolerance, or one per component (CVodeSVtolerances).
    if AtolV.Kind = vkArray then
    begin
      AtolK := RealsOf(AtolV);
      AtolN := N_VNew_Serial(N, Ctx);
      Move(AtolK[0], N_VGetArrayPointer(AtolN)^, N * SizeOf(Double));
      Check(CVodeSVtolerances(Mem, Rtol, AtolN), 'CVodeSVtolerances');
    end
    else
      Check(CVodeSStolerances(Mem, Rtol, ToReal(AtolV)), 'CVodeSStolerances');
    Check(CVodeSetLinearSolver(Mem, LS, A), 'CVodeSetLinearSolver');
    Check(CVodeSetMaxNumSteps(Mem, MaxSteps), 'CVodeSetMaxNumSteps');
    Check(CVodeSetStopTime(Mem, T1), 'CVodeSetStopTime');
    if MaxStep < Infinity then
      Check(CVodeSetMaxStep(Mem, MaxStep), 'CVodeSetMaxStep');
    if FirstStep.Kind <> vkNothing then
      Check(CVodeSetInitStep(Mem, S * Abs(ToReal(FirstStep))), 'CVodeSetInitStep');
    if Ng > 0 then
      Check(CVodeRootInit(Mem, Ng, CvRoots), 'CVodeRootInit');

    NextEval := 0;
    if not HasTEval then
      AddPoint(T0, Y)
    else
      while (NextEval < Length(TEval)) and (TEval[NextEval] = T0) do
      begin
        AddPoint(T0, Y);
        Inc(NextEval);
      end;

    T := T0;
    Dy := Rhs(T0, Y);
    Status := 'success';
    TRet := T0;
    SetLength(Roots, Max(Ng, 1));
    NSteps := 0;
    while S * (T1 - T) > 0 do
    begin
      Flag := CVode(Mem, T1, Yv, TRet, CV_ONE_STEP);
      if Pending <> nil then
      begin
        E := Pending;
        Pending := nil;
        raise E;
      end;
      if Flag < 0 then
        Fail('SolverError', 'CVODE failed at t = ' + RStr(TRet) + ' (' + FlagName(Flag) + ')');
      Inc(NSteps);
      if NSteps > MaxSteps then
        Fail('SolverError', 'more than ' + Str(IntValue(MaxSteps)) + ' steps before t = ' +
          RStr(T1) + ' (stopped at t = ' + RStr(TRet) + ')');
      YNew := NativeVector(Yv);
      Check(CVodeGetDky(Mem, TRet, 1, Dky), 'CVodeGetDky');
      DNew := NativeVector(Dky);
      T0s.Add(T);
      Hs.Add(TRet - T);
      YA.Add(Y);
      YB.Add(YNew);
      DA.Add(Dy);
      DB.Add(DNew);
      if Flag = CV_ROOT_RETURN then
      begin
        Check(CVodeGetRootInfo(Mem, @Roots[0]), 'CVodeGetRootInfo');
        for K := 1 to Ng do
        begin
          Dir := Roots[K - 1];
          if (Dir <> 0) and (ValuesEqual(Direction[K - 1], IntValue(0)) or
            ValuesEqual(Direction[K - 1], IntValue(Dir))) then
          begin
            TeList[K - 1].Add(TRet);
            YeList[K - 1].Add(YNew);
            if Truth(Terminal[K - 1]) then
              Status := 'event';
          end;
        end;
      end;
      AddStepOutput(TRet, YNew);
      T := TRet;
      Y := YNew;
      Dy := DNew;
      if Status = 'event' then
        Break;
    end;

    SetLength(ListT, Ng);
    SetLength(ListY, Ng);
    for K := 0 to Ng - 1 do
    begin
      ListT[K] := TeList[K].Value;
      ListY[K] := YeList[K].Value;
    end;
    Result := [OutT.Value, OutY.Value, StringValue(Status), ListValue(ListT), ListValue(ListY),
      IntValue(NFev), IntValue(NSteps), T0s.Value, Hs.Value, YA.Value, YB.Value, DA.Value,
      DB.Value];
  finally
    if Mem <> nil then CVodeFree(Mem);
    if LS <> nil then SUNLinSolFree(LS);
    if A <> nil then SUNMatDestroy(A);
    if Yv <> nil then N_VDestroy(Yv);
    if AtolN <> nil then N_VDestroy(AtolN);
    if Dky <> nil then N_VDestroy(Dky);
    if Ctx <> nil then SUNContext_Free(Ctx);
    Pending.Free;
    Pending := nil;
    for K := 0 to Ng - 1 do
    begin
      TeList[K].Free;
      YeList[K].Free;
    end;
    OutT.Free;
    OutY.Free;
  end;
end;

function BBdf(const Args: TAxValues): TAxValues;
var
  B: TBdf;
begin
  B := TBdf.Create(AsArray(Args[3]).Count);
  try
    Result := B.Run(Args);
  finally
    B.Free;
  end;
end;

{ ---------------------------------------------------------------- integrators }

(* odecore.integrator(f, method, rtol, atol) and odecore.advance(s, t, y, p, t1),
   behind ode.integrator and ode.advance: a solver that keeps its state
   between calls, so that advancing a solution in many short intervals costs
   about what one solve costs.

   advance returns y at t1. It continues from the solver's state when t, y and
   p are exactly the time, state and params it last returned and was given;
   otherwise (the first call, a changed state or changed params, or a copy of
   the caller's record used out of turn) it starts afresh from (t, y), as a
   new solve would: RK45 picks a new first step, CVODE is reinitialized. The
   solver steps past t1 as its step sizes dictate and interpolates y(t1), so
   a short interval does not shorten its steps. Integration runs forward
   only. *)

type
  TStepEngine = class(TOdeBase)
  protected
    Rtol: Double;
    AtolK: TVec;
    Started: Boolean;      // the solver's state continues the last result
    LastT: Double;
    LastY: TVec;
    LastP: TAxValue;
    procedure Reset(T0: Double; const Y0: TVec); virtual; abstract;
    function AdvanceTo(Target: Double): TVec; virtual; abstract;
  public
    function Advance(T0: Double; const Y0: TVec; const P: TAxValue; Target: Double): TVec;
  end;

  { DOPRI5, as TRk45, one accepted step at a time. }
  TRk45Engine = class(TStepEngine)
  private
    T, TPrev, H, Facmax: Double;
    Y, K1: TVec;
    // The dense output of the last accepted step, [TPrev, T].
    D1, D2, D3, D4, D5: TVec;
    procedure TakeStep;
    function Dense(Tq: Double): TVec;
  protected
    procedure Reset(T0: Double; const Y0: TVec); override;
    function AdvanceTo(Target: Double): TVec; override;
  end;

  { CVODE's BDF, kept between calls. }
  TBdfEngine = class(TStepEngine)
  private
    Ctx, Mem, Yv, A, LS, AtolN: Pointer;
    Pending: Exception;
    function NativeVector(V: Pointer): TVec;
    procedure Check(Flag: Integer; const What: string);
  protected
    procedure Reset(T0: Double; const Y0: TVec); override;
    function AdvanceTo(Target: Double): TVec; override;
  public
    destructor Destroy; override;
  end;

  { The value odecore.integrator returns: a pointer value whose payload keeps
    the solver alive while any copy of it exists. The engine is made at the
    first advance, when the number of components is known. }
  TIntegratorObj = class(TInterfacedObject)
  public
    F: TAxValue;
    Method: string;
    Rtol: Double;
    Atol: TAxValue;
    Engine: TStepEngine;
    destructor Destroy; override;
  end;

const
  MaxAdvanceSteps = 100000;

function SameVec(const A, B: TVec): Boolean;
var
  K: Integer;
begin
  Result := Length(A) = Length(B);
  if Result then
    for K := 0 to High(A) do
      if A[K] <> B[K] then
        Exit(False);
end;

function TStepEngine.Advance(T0: Double; const Y0: TVec; const P: TAxValue; Target: Double): TVec;
begin
  if not (Started and (T0 = LastT) and SameVec(Y0, LastY) and ValuesIdentical(P, LastP)) then
  begin
    Started := False;
    Params := P;
    HasParams := P.Kind <> vkNothing;
    Reset(T0, Y0);
  end;
  try
    Result := AdvanceTo(Target);
  except
    Started := False;
    raise;
  end;
  Started := True;
  LastT := Target;
  LastY := Copy(Result);
  LastP := P;
end;

procedure TRk45Engine.Reset(T0: Double; const Y0: TVec);
begin
  T := T0;
  TPrev := T0;
  Y := Copy(Y0);
  K1 := Rhs(T, Y);
  Inc(NFev);
  H := 0;            // chosen at the first step, from the first interval
  Facmax := 10.0;
end;

{ One accepted step from (T, Y), as TRk45.Run's loop takes it, with no end
  time to stop at. }
procedure TRk45Engine.TakeStep;
var
  K2, K3, K4, K5, K6, K7, YNew, ErrV, Sk, Tmp: TVec;
  TNew, Err, Fac: Double;
  I: Integer;
begin
  SetLength(Tmp, N);
  SetLength(YNew, N);
  SetLength(ErrV, N);
  SetLength(Sk, N);
  repeat
    if H < 16 * EPS * RMax(Abs(T), 1e-300) then
      Fail('SolverError', 'the step size became too small at t = ' + RStr(T));
    for I := 0 to N - 1 do
      Tmp[I] := Y[I] + H * (K1[I] / 5);
    K2 := Rhs(T + H / 5, Tmp);
    for I := 0 to N - 1 do
      Tmp[I] := Y[I] + H * (3 / 40 * K1[I] + 9 / 40 * K2[I]);
    K3 := Rhs(T + 3 * H / 10, Tmp);
    for I := 0 to N - 1 do
      Tmp[I] := Y[I] + H * (44 / 45 * K1[I] - 56 / 15 * K2[I] + 32 / 9 * K3[I]);
    K4 := Rhs(T + 4 * H / 5, Tmp);
    for I := 0 to N - 1 do
      Tmp[I] := Y[I] + H * (19372 / 6561 * K1[I] - 25360 / 2187 * K2[I] +
        64448 / 6561 * K3[I] - 212 / 729 * K4[I]);
    K5 := Rhs(T + 8 * H / 9, Tmp);
    for I := 0 to N - 1 do
      Tmp[I] := Y[I] + H * (9017 / 3168 * K1[I] - 355 / 33 * K2[I] + 46732 / 5247 * K3[I] +
        49 / 176 * K4[I] - 5103 / 18656 * K5[I]);
    K6 := Rhs(T + H, Tmp);
    for I := 0 to N - 1 do
      YNew[I] := Y[I] + H * (35 / 384 * K1[I] + 500 / 1113 * K3[I] + 125 / 192 * K4[I] -
        2187 / 6784 * K5[I] + 11 / 84 * K6[I]);
    TNew := T + H;
    K7 := Rhs(TNew, YNew);
    Inc(NFev, 6);
    for I := 0 to N - 1 do
    begin
      ErrV[I] := H * (71 / 57600 * K1[I] - 71 / 16695 * K3[I] + 71 / 1920 * K4[I] -
        17253 / 339200 * K5[I] + 22 / 525 * K6[I] - 1 / 40 * K7[I]);
      Sk[I] := AtolK[I] + Rtol * RMax(Abs(Y[I]), Abs(YNew[I]));
    end;
    Err := Wrms(ErrV, Sk);
    if Err <> Err then
      Fail('SolverError', 'the solution is not finite at t = ' + RStr(T));
    if Err > 1 then
    begin
      // Rejected: retry with a smaller step.
      H := H * RMax(0.2, 0.9 * RPow(Err, -0.2));
      Facmax := 1.0;
    end;
  until Err <= 1;

  // Accepted: keep the dense output of [T, TNew], then move on.
  SetLength(D1, N);
  SetLength(D2, N);
  SetLength(D3, N);
  SetLength(D4, N);
  SetLength(D5, N);
  for I := 0 to N - 1 do
  begin
    D1[I] := Y[I];
    D2[I] := YNew[I] - Y[I];
    D3[I] := H * K1[I] - D2[I];
    D4[I] := D2[I] - H * K7[I] - D3[I];
    D5[I] := H * (-12715105075 / 11282082432 * K1[I] + 87487479700 / 32700410799 * K3[I] -
      10690763975 / 1880347072 * K4[I] + 701980252875 / 199316789632 * K5[I] -
      1453857185 / 822651844 * K6[I] + 69997945 / 29380423 * K7[I]);
  end;
  TPrev := T;
  T := TNew;
  Y := YNew;
  K1 := K7;
  Fac := RMin(Facmax, RMax(0.2, 0.9 * RPow(Err, -0.2)));
  if Err = 0 then Fac := Facmax;
  H := H * Fac;
  Facmax := 10.0;
end;

function TRk45Engine.Dense(Tq: Double): TVec;
var
  Th, Th1: Double;
  K: Integer;
begin
  Th := (Tq - TPrev) / (T - TPrev);
  Th1 := 1 - Th;
  SetLength(Result, N);
  for K := 0 to N - 1 do
    Result[K] := D1[K] + Th * (D2[K] + Th1 * (D3[K] + Th * (D4[K] + Th1 * D5[K])));
end;

function TRk45Engine.AdvanceTo(Target: Double): TVec;
var
  Sk, Y1, F1, Tmp: TVec;
  D0, Dd1, D2_, H0, H1: Double;
  I: Integer;
  Steps: Int64;
begin
  if H = 0 then
  begin
    // The first step after a start (Hairer and Wanner, II.4), with the
    // first interval in place of the whole span.
    SetLength(Sk, N);
    SetLength(Y1, N);
    SetLength(Tmp, N);
    for I := 0 to N - 1 do
      Sk[I] := AtolK[I] + Rtol * Abs(Y[I]);
    D0 := Wrms(Y, Sk);
    Dd1 := Wrms(K1, Sk);
    if (D0 < 1e-5) or (Dd1 < 1e-5) then
      H0 := 1e-6
    else
      H0 := 0.01 * D0 / Dd1;
    H0 := RMin(H0, Target - T);
    for I := 0 to N - 1 do
      Y1[I] := Y[I] + H0 * K1[I];
    F1 := Rhs(T + H0, Y1);
    Inc(NFev);
    for I := 0 to N - 1 do
      Tmp[I] := F1[I] - K1[I];
    D2_ := Wrms(Tmp, Sk) / H0;
    if RMax(Dd1, D2_) <= 1e-15 then
      H1 := RMax(1e-6, H0 * 1e-3)
    else
      H1 := RPow(0.01 / RMax(Dd1, D2_), 0.2);
    H := RMin(100 * H0, H1);
  end;
  Steps := 0;
  while T < Target do
  begin
    Inc(Steps);
    if Steps > MaxAdvanceSteps then
      Fail('SolverError', 'more than ' + IntToStr(MaxAdvanceSteps) + ' steps before t = ' +
        RStr(Target) + ' (stopped at t = ' + RStr(T) + ')');
    TakeStep;
  end;
  if T = Target then
    Result := Copy(Y)
  else
    Result := Dense(Target);
end;

{ y' = f(t, y) for CVODE, for an integrator. }
function CvEngineRhs(T: Double; Y, YDot, User: Pointer): Integer; cdecl;
var
  B: TBdfEngine;
  D: TVec;
begin
  B := TBdfEngine(User);
  try
    D := B.Rhs(T, B.NativeVector(Y));
    if B.N > 0 then
      Move(D[0], N_VGetArrayPointer(YDot)^, B.N * SizeOf(Double));
    Inc(B.NFev);
    Result := 0;
  except
    B.Pending := AcquireExceptionObject as Exception;
    Result := -1;
  end;
end;

function TBdfEngine.NativeVector(V: Pointer): TVec;
begin
  SetLength(Result, N);
  if N > 0 then
    Move(N_VGetArrayPointer(V)^, Result[0], N * SizeOf(Double));
end;

procedure TBdfEngine.Check(Flag: Integer; const What: string);
begin
  if Flag < 0 then
    Fail('SolverError', 'CVODE ' + What + ' failed (' + FlagName(Flag) + ')');
end;

procedure TBdfEngine.Reset(T0: Double; const Y0: TVec);
begin
  if Mem = nil then
  begin
    if not CvodeAvailable then
      RaiseError(ForeignError, CvodeError);
    Check(SUNContext_Create(nil, Ctx), 'SUNContext_Create');
    SUNContext_ClearErrHandlers(Ctx);
    Yv := N_VNew_Serial(N, Ctx);
    A := SUNDenseMatrix(N, N, Ctx);
    LS := SUNLinSol_Dense(Yv, A, Ctx);
    Move(Y0[0], N_VGetArrayPointer(Yv)^, N * SizeOf(Double));
    Mem := CVodeCreate(CV_BDF, Ctx);
    Check(CVodeInit(Mem, CvEngineRhs, T0, Yv), 'CVodeInit');
    Check(CVodeSetUserData(Mem, Self), 'CVodeSetUserData');
    AtolN := N_VNew_Serial(N, Ctx);
    Move(AtolK[0], N_VGetArrayPointer(AtolN)^, N * SizeOf(Double));
    Check(CVodeSVtolerances(Mem, Rtol, AtolN), 'CVodeSVtolerances');
    Check(CVodeSetLinearSolver(Mem, LS, A), 'CVodeSetLinearSolver');
    Check(CVodeSetMaxNumSteps(Mem, MaxAdvanceSteps), 'CVodeSetMaxNumSteps');
  end
  else
  begin
    Move(Y0[0], N_VGetArrayPointer(Yv)^, N * SizeOf(Double));
    Check(CVodeReInit(Mem, T0, Yv), 'CVodeReInit');
  end;
end;

function TBdfEngine.AdvanceTo(Target: Double): TVec;
var
  Flag: Integer;
  TRet: Double;
  E: Exception;
begin
  Flag := CVode(Mem, Target, Yv, TRet, CV_NORMAL);
  if Pending <> nil then
  begin
    E := Pending;
    Pending := nil;
    raise E;
  end;
  if Flag < 0 then
    Fail('SolverError', 'CVODE failed at t = ' + RStr(TRet) + ' (' + FlagName(Flag) + ')');
  Result := NativeVector(Yv);
end;

destructor TBdfEngine.Destroy;
begin
  if Mem <> nil then CVodeFree(Mem);
  if LS <> nil then SUNLinSolFree(LS);
  if A <> nil then SUNMatDestroy(A);
  if Yv <> nil then N_VDestroy(Yv);
  if AtolN <> nil then N_VDestroy(AtolN);
  if Ctx <> nil then SUNContext_Free(Ctx);
  Pending.Free;
  inherited;
end;

destructor TIntegratorObj.Destroy;
begin
  Engine.Free;
  inherited;
end;

{ odecore.integrator(f, method, rtol, atol): ode.integrator checked them. }
function BIntegrator(const Args: TAxValues): TAxValues;
var
  Obj: TIntegratorObj;
  V: TAxValue;
begin
  Obj := TIntegratorObj.Create;
  Obj.F := Args[0];
  Obj.Method := AsString(Args[1]);
  Obj.Rtol := ToReal(Args[2]);
  Obj.Atol := Args[3];
  V := NothingValue;
  V.Kind := vkPointer;
  V.I := Int64(NativeUInt(Obj));
  V.Obj := Obj;
  Result := [V];
end;

{ odecore.advance(s, t, y, p, t1): y at t1 as a vector, and the right-hand
  side evaluations so far. }
function BAdvance(const Args: TAxValues): TAxValues;
var
  Obj: TIntegratorObj;
  Y0, AtolK: TVec;
  N, K: Integer;
begin
  if (Args[0].Kind <> vkPointer) or (Args[0].Obj = nil) or
    not ((Args[0].Obj as TObject) is TIntegratorObj) then
    Fail(TypeError, 'advance needs an integrator from ode.integrator');
  Obj := TIntegratorObj(Args[0].Obj as TObject);
  Y0 := RealsOf(Args[2]);
  N := Length(Y0);
  if (Obj.Engine <> nil) and (Obj.Engine.N <> N) then
    FreeAndNil(Obj.Engine);
  if Obj.Engine = nil then
  begin
    if Obj.Atol.Kind = vkArray then
    begin
      AtolK := RealsOf(Obj.Atol);
      if Length(AtolK) <> N then
        Fail(DimensionError, Format('atol has %d values but y has %d components', [Length(AtolK), N]));
    end
    else
    begin
      SetLength(AtolK, N);
      for K := 0 to N - 1 do
        AtolK[K] := ToReal(Obj.Atol);
    end;
    if Obj.Method = 'bdf' then
      Obj.Engine := TBdfEngine.Create(N)
    else
      Obj.Engine := TRk45Engine.Create(N);
    Obj.Engine.F := Obj.F;
    Obj.Engine.S := 1.0;
    Obj.Engine.Rtol := Obj.Rtol;
    Obj.Engine.AtolK := AtolK;
  end;
  Result := [VectorValue(Obj.Engine.Advance(ToReal(Args[1]), Y0, Args[3], ToReal(Args[4]))),
    IntValue(Obj.Engine.NFev)];
end;

function MultiBuiltin(const Name: string; Fn: TBuiltinMultiFn; MinArgs, MaxArgs: Integer): TAxValue;
var
  B: TBuiltinObj;
begin
  B := TBuiltinObj.Create;
  B.Name := Name;
  B.MultiFn := Fn;
  B.MinArgs := MinArgs;
  B.MaxArgs := MaxArgs;
  Result := NothingValue;
  Result.Kind := vkBuiltin;
  Result.Obj := B;
end;

procedure DefineOdeCore(const Define: TProc<string, TAxValue>);
begin
  Define('rk45', MultiBuiltin('rk45', BRk45, 5, 5));
  Define('bdf', MultiBuiltin('bdf', BBdf, 5, 5));
  Define('integrator', MultiBuiltin('integrator', BIntegrator, 4, 4));
  Define('advance', MultiBuiltin('advance', BAdvance, 5, 5));
end;

initialization
  RegisterNativeModule('odecore', DefineOdeCore,
    ['The native loops behind the ode module: rk45 and bdf, and integrator and advance.']);

end.
