unit Axon.NonlinCore;

(* nonlincore: the native solver behind stdlib/nonlin.sci.

   nonlincore.kinsol(f, x0, o) solves f(x) = 0 with SUNDIALS KINSOL: Newton's
   method with a dense direct linear solver and a Jacobian from difference
   quotients, recomputed at every iteration, with a line search (o.method = "linesearch") or without
   ("newton"). x0 is a real vector; o is a record with fields method, ftol,
   xtol, max_iters and params, which nonlin.sci has checked. It returns five
   values: x (a real vector), status ("success", or "small_step" when KINSOL
   stopped because a step no longer changed x, which may or may not be a
   root), fnorm (the Euclidean norm of f(x)), nfev (calls of f, those for the
   Jacobian included) and niters (Newton iterations).

   f is called as the interpreter calls it (CallAxon), as f(x) or, when
   o.params is not nothing, f(x, params). Its result is checked as ode's
   right-hand side is: a real vector of x's length, or a number for one
   equation. A result that is not finite is a recoverable failure for KINSOL,
   which then tries a shorter step. The system function is a Delphi function
   that finds its solve through KINSOL's user data, so solves nest; it never
   lets an exception escape into KINSOL, but keeps it and returns -1, and the
   solve raises it when KINSOL returns. Any other failure is a SolverError. *)

interface

implementation

uses
  System.SysUtils, System.Math,
  Axon.Errors, Axon.Values, Axon.Ops, Axon.NativeModules, Axon.Native.Kinsol;

type
  TVec = TArray<Double>;

procedure Fail(const Kind, Msg: string);
begin
  raise EAxonError.Create(Kind, 'nonlin.solve: ' + Msg);
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

function Field(const R: TAxValue; const Name: string): TAxValue;
var
  K: Integer;
begin
  K := AsRecord(R).IndexOf(Name);
  if K < 0 then
    raise EAxonError.Create(TypeError, 'nonlincore: no field ' + Name);
  Result := AsRecord(R).Values[K];
end;

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

type
  TKinSolve = class
  private
    F, Params: TAxValue;
    HasParams: Boolean;
    N: Integer;
    NFev: Int64;
    Pending: Exception;          // raised in the callback, re-raised by Run
    function NativeVector(V: Pointer): TVec;
    function Residual(const X: TVec): TVec;
  public
    function Run(const Args: TAxValues): TAxValues;
  end;

function TKinSolve.NativeVector(V: Pointer): TVec;
begin
  SetLength(Result, N);
  if N > 0 then
    Move(Kin.N_VGetArrayPointer(V)^, Result[0], N * SizeOf(Double));
end;

{ f(x) as a real vector of length n, checked as ode checks its right-hand side. }
function TKinSolve.Residual(const X: TVec): TVec;
var
  D: TAxValue;
  TN: string;
  A: TArrayObj;
  K: Integer;
begin
  if HasParams then
    D := CallAxon(F, [VectorValue(X), Params])
  else
    D := CallAxon(F, [VectorValue(X)]);
  TN := TypeName(D);
  if (TN <> 'vector') and (TN <> 'matrix') and (TN <> 'real') and (TN <> 'int') then
    Fail(TypeError, 'f must return a real vector, got ' + TN);
  if D.Kind <> vkArray then
  begin
    // A number, for one equation.
    if N <> 1 then
      Fail(DimensionError, Format('f returned 1 value, but x0 has %d', [N]));
    SetLength(Result, 1);
    Result[0] := ToReal(D);
    Exit;
  end;
  A := AsArray(D);
  if A.Count <> N then
    Fail(DimensionError, Format('f returned %d values, but x0 has %d', [A.Count, N]));
  if A.ElemType = etComplex then
    Fail(TypeError, 'f must return real values');
  if A.ElemType = etReal then
  begin
    Result := Copy(A.R, 0, N);
    Exit;
  end;
  SetLength(Result, N);
  for K := 0 to N - 1 do
    Result[K] := ToReal(A.Get(K));
end;

{ F(u) for KINSOL. }
function KinSys(U, FVal, User: Pointer): Integer; cdecl;
var
  S: TKinSolve;
  D: TVec;
  K: Integer;
begin
  S := TKinSolve(User);
  try
    Inc(S.NFev);
    D := S.Residual(S.NativeVector(U));
    Move(D[0], Kin.N_VGetArrayPointer(FVal)^, S.N * SizeOf(Double));
    Result := 0;
    for K := 0 to S.N - 1 do
      if IsNan(D[K]) or IsInfinite(D[K]) then
        Exit(1);              // recoverable: KINSOL tries a shorter step
  except
    S.Pending := AcquireExceptionObject as Exception;
    Result := -1;
  end;
end;

function FlagName(Flag: Integer): string;
begin
  Result := string(AnsiString(Kin.KINGetReturnFlagName(Flag)));
end;

function TKinSolve.Run(const Args: TAxValues): TAxValues;
var
  O: TAxValue;
  X0, Ones: TVec;
  Ctx, Mem, U, Scale, A, LS: Pointer;
  Strategy, Flag, K: Integer;
  MaxIters: Int64;
  NIters: LongInt;
  FNorm: Double;
  Status, Why: string;
  E: Exception;

  procedure Check(Fl: Integer; const What: string);
  begin
    if Fl < 0 then
      Fail('SolverError', 'KINSOL ' + What + ' failed (' + FlagName(Fl) + ')');
  end;

begin
  if not KinsolAvailable then
    RaiseError(ForeignError, KinsolError);
  F := Args[0];
  X0 := RealsOf(Args[1]);
  N := Length(X0);
  O := Args[2];
  if AsString(Field(O, 'method')) = 'newton' then
    Strategy := KIN_NONE
  else
    Strategy := KIN_LINESEARCH;
  MaxIters := Field(O, 'max_iters').I;
  Params := Field(O, 'params');
  HasParams := Params.Kind <> vkNothing;

  Ctx := nil;
  Mem := nil;
  U := nil;
  Scale := nil;
  A := nil;
  LS := nil;
  try
    Check(Kin.SUNContext_Create(nil, Ctx), 'SUNContext_Create');
    // Failures come back as return codes; SUNDIALS should not also print them.
    Kin.SUNContext_ClearErrHandlers(Ctx);
    U := Kin.N_VNew_Serial(N, Ctx);
    Scale := Kin.N_VNew_Serial(N, Ctx);
    A := Kin.SUNDenseMatrix(N, N, Ctx);
    LS := Kin.SUNLinSol_Dense(U, A, Ctx);
    if (U = nil) or (Scale = nil) or (A = nil) or (LS = nil) then
      Fail('SolverError', 'KINSOL could not allocate its vectors');
    Move(X0[0], Kin.N_VGetArrayPointer(U)^, N * SizeOf(Double));
    // No scaling: every component of x and f counts alike.
    SetLength(Ones, N);
    for K := 0 to N - 1 do
      Ones[K] := 1.0;
    Move(Ones[0], Kin.N_VGetArrayPointer(Scale)^, N * SizeOf(Double));

    Mem := Kin.KINCreate(Ctx);
    if Mem = nil then
      Fail('SolverError', 'KINSOL could not allocate its memory');
    Check(Kin.KINInit(Mem, KinSys, U), 'KINInit');
    Check(Kin.KINSetUserData(Mem, Self), 'KINSetUserData');
    Check(Kin.KINSetLinearSolver(Mem, LS, A), 'KINSetLinearSolver');
    Check(Kin.KINSetNumMaxIters(Mem, MaxIters), 'KINSetNumMaxIters');
    // A new Jacobian at every iteration (Newton's method, not KINSOL's default
    // modified Newton, which keeps one for ten): fewer iterations, and more
    // robust from a poor guess, at n extra calls of f per iteration.
    Check(Kin.KINSetMaxSetupCalls(Mem, 1), 'KINSetMaxSetupCalls');
    // No cap on a Newton step's length. KINSOL's default is 1000 |x0|, but at
    // least 1, so from x0 = 0 (species that start at zero) every step was
    // cut to length 1 and a linear problem took many iterations. The line
    // search still shortens a step that does not reduce |f(x)|.
    Check(Kin.KINSetMaxNewtonStep(Mem, 1e150), 'KINSetMaxNewtonStep');
    Check(Kin.KINSetFuncNormTol(Mem, ToReal(Field(O, 'ftol'))), 'KINSetFuncNormTol');
    Check(Kin.KINSetScaledStepTol(Mem, ToReal(Field(O, 'xtol'))), 'KINSetScaledStepTol');

    Flag := Kin.KINSol(Mem, U, Strategy, Scale, Scale);
    if Pending <> nil then
    begin
      E := Pending;
      Pending := nil;
      raise E;
    end;
    NIters := 0;
    FNorm := NaN;
    Kin.KINGetNumNonlinSolvIters(Mem, NIters);
    Kin.KINGetFuncNorm(Mem, FNorm);
    if Flag < 0 then
    begin
      case Flag of
        KIN_MAXITER_REACHED:
          Why := Format('no solution after %d iterations', [MaxIters]);
        KIN_LINESEARCH_NONCONV, KIN_LINESEARCH_BCFAIL:
          Why := 'the line search could not reduce |f(x)|';
        KIN_MXNEWT_5X_EXCEEDED:
          Why := 'the Newton steps keep growing; there may be no root nearby';
        KIN_LSETUP_FAIL, KIN_LSOLVE_FAIL, KIN_LINSOLV_NO_RECOVERY:
          Why := 'the Jacobian is singular';
        KIN_FIRST_SYSFUNC_ERR:
          Why := 'f(x0) is not finite';
        KIN_REPTD_SYSFUNC_ERR:
          Why := 'f is not finite at the points tried';
      else
        Why := 'KINSOL failed';
      end;
      Fail('SolverError', Why + ' (' + FlagName(Flag) + ')');
    end;
    if Flag = KIN_STEP_LT_STPTOL then
      Status := 'small_step'
    else
      Status := 'success';
    Result := [VectorValue(NativeVector(U)), StringValue(Status), RealValue(FNorm),
      IntValue(NFev), IntValue(NIters)];
  finally
    if Mem <> nil then Kin.KINFree(Mem);
    if LS <> nil then Kin.SUNLinSolFree(LS);
    if A <> nil then Kin.SUNMatDestroy(A);
    if U <> nil then Kin.N_VDestroy(U);
    if Scale <> nil then Kin.N_VDestroy(Scale);
    if Ctx <> nil then Kin.SUNContext_Free(Ctx);
    Pending.Free;
    Pending := nil;
  end;
end;

function BKinsol(const Args: TAxValues): TAxValues;
var
  S: TKinSolve;
begin
  S := TKinSolve.Create;
  try
    Result := S.Run(Args);
  finally
    S.Free;
  end;
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

procedure DefineNonlinCore(const Define: TProc<string, TAxValue>);
begin
  Define('kinsol', MultiBuiltin('kinsol', BKinsol, 3, 3));
end;

initialization
  RegisterNativeModule('nonlincore', DefineNonlinCore,
    ['The native solver behind the nonlin module: kinsol.']);

end.
