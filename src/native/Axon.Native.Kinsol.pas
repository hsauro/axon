unit Axon.Native.Kinsol;

{ SUNDIALS KINSOL for nonlincore (Axon.NonlinCore), behind stdlib/nonlin.sci.

  The libraries are sundials_core and sundials_kinsol (which holds the serial
  vector, the dense matrix and the dense linear solver), next to the
  interpreter or on the system search path, loaded on first use
  (KinsolAvailable). The functions are fields of Kin rather than unit-level
  names, because Axon.Native.Cvode binds the same SUNDIALS names from its own
  library. C's long is LongInt, which is 32-bit on Windows and 64-bit on
  macOS and Linux, as in C; sunindextype is 64-bit and sunrealtype double in
  the shipped builds. }

interface

const
  KIN_NONE = 0;                 // Newton
  KIN_LINESEARCH = 1;           // Newton with a line search

  KIN_SUCCESS = 0;
  KIN_INITIAL_GUESS_OK = 1;
  KIN_STEP_LT_STPTOL = 2;

  KIN_LINESEARCH_NONCONV = -5;
  KIN_MAXITER_REACHED = -6;
  KIN_MXNEWT_5X_EXCEEDED = -7;
  KIN_LINESEARCH_BCFAIL = -8;
  KIN_LINSOLV_NO_RECOVERY = -9;
  KIN_LINIT_FAIL = -10;
  KIN_LSETUP_FAIL = -11;
  KIN_LSOLVE_FAIL = -12;
  KIN_SYSFUNC_FAIL = -13;
  KIN_FIRST_SYSFUNC_ERR = -14;
  KIN_REPTD_SYSFUNC_ERR = -15;

type
  // F(u) into fval; 0 on success, > 0 for a recoverable failure (KINSOL
  // tries a shorter step), < 0 to stop.
  TKinSysFn = function(U, FVal, User: Pointer): Integer; cdecl;

  TKinsol = record
    SUNContext_Create: function(Comm: Pointer; var Ctx: Pointer): Integer; cdecl;
    SUNContext_Free: function(var Ctx: Pointer): Integer; cdecl;
    SUNContext_ClearErrHandlers: function(Ctx: Pointer): Integer; cdecl;
    N_VNew_Serial: function(N: Int64; Ctx: Pointer): Pointer; cdecl;
    N_VGetArrayPointer: function(V: Pointer): PDouble; cdecl;
    N_VDestroy: procedure(V: Pointer); cdecl;
    SUNDenseMatrix: function(M, N: Int64; Ctx: Pointer): Pointer; cdecl;
    SUNMatDestroy: procedure(A: Pointer); cdecl;
    SUNLinSol_Dense: function(Y, A, Ctx: Pointer): Pointer; cdecl;
    SUNLinSolFree: function(LS: Pointer): Integer; cdecl;
    KINCreate: function(Ctx: Pointer): Pointer; cdecl;
    KINInit: function(Mem: Pointer; Func: TKinSysFn; Tmpl: Pointer): Integer; cdecl;
    KINSetUserData: function(Mem, Data: Pointer): Integer; cdecl;
    KINSetLinearSolver: function(Mem, LS, A: Pointer): Integer; cdecl;
    KINSetNumMaxIters: function(Mem: Pointer; MxIter: LongInt): Integer; cdecl;
    KINSetMaxSetupCalls: function(Mem: Pointer; MsbSet: LongInt): Integer; cdecl;
    KINSetMaxNewtonStep: function(Mem: Pointer; MxNewtStep: Double): Integer; cdecl;
    KINSetFuncNormTol: function(Mem: Pointer; FNormTol: Double): Integer; cdecl;
    KINSetScaledStepTol: function(Mem: Pointer; ScStepTol: Double): Integer; cdecl;
    KINSol: function(Mem, U: Pointer; Strategy: Integer; UScale, FScale: Pointer): Integer; cdecl;
    KINGetNumNonlinSolvIters: function(Mem: Pointer; var NIters: LongInt): Integer; cdecl;
    KINGetFuncNorm: function(Mem: Pointer; var FNorm: Double): Integer; cdecl;
    KINGetReturnFlagName: function(Flag: LongInt): PAnsiChar; cdecl;
    KINFree: procedure(var Mem: Pointer); cdecl;
  end;

var
  Kin: TKinsol;

{ True when both libraries are loaded and every function bound; otherwise
  KinsolError says why. }
function KinsolAvailable: Boolean;
function KinsolError: string;

implementation

uses
  System.SysUtils,
  Axon.Platform;

var
  Tried, Bound: Boolean;
  LoadError: string;

function LoadLib(const Base: string): NativeUInt;
var
  Names: TArray<string>;
  N: string;
begin
{$IFDEF MSWINDOWS}
  Names := [Base + '.dll'];
{$ENDIF}
{$IFDEF MACOS}
  Names := ['lib' + Base + '.dylib', Base + '.dylib'];
{$ENDIF}
{$IFDEF LINUX}
  Names := ['lib' + Base + '.so'];
{$ENDIF}
  for N in Names do
  begin
    Result := LoadNativeLibrary(ExtractFilePath(ParamStr(0)) + N);
    if Result = 0 then
      Result := LoadNativeLibrary(N);
    if Result <> 0 then
      Exit;
  end;
  Result := 0;
end;

function KinsolAvailable: Boolean;
var
  Core, KinLib: NativeUInt;

  function Bind(var P; const Name: string): Boolean;
  begin
    // A symbol may live in either library.
    Pointer(P) := NativeSymbol(KinLib, Name);
    if Pointer(P) = nil then
      Pointer(P) := NativeSymbol(Core, Name);
    Result := Pointer(P) <> nil;
    if not Result and (LoadError = '') then
      LoadError := 'SUNDIALS lacks ' + Name;
  end;

begin
  if not Tried then
  begin
    Tried := True;
    // The core first, so that on macOS the solver's dependency on it
    // resolves to this copy.
    Core := LoadLib('sundials_core');
    KinLib := LoadLib('sundials_kinsol');
    if (Core = 0) or (KinLib = 0) then
      LoadError := 'cannot load the SUNDIALS libraries (sundials_core, sundials_kinsol)'
    else
      Bound :=
        Bind(Kin.SUNContext_Create, 'SUNContext_Create') and
        Bind(Kin.SUNContext_Free, 'SUNContext_Free') and
        Bind(Kin.SUNContext_ClearErrHandlers, 'SUNContext_ClearErrHandlers') and
        Bind(Kin.N_VNew_Serial, 'N_VNew_Serial') and
        Bind(Kin.N_VGetArrayPointer, 'N_VGetArrayPointer') and
        Bind(Kin.N_VDestroy, 'N_VDestroy') and
        Bind(Kin.SUNDenseMatrix, 'SUNDenseMatrix') and
        Bind(Kin.SUNMatDestroy, 'SUNMatDestroy') and
        Bind(Kin.SUNLinSol_Dense, 'SUNLinSol_Dense') and
        Bind(Kin.SUNLinSolFree, 'SUNLinSolFree') and
        Bind(Kin.KINCreate, 'KINCreate') and
        Bind(Kin.KINInit, 'KINInit') and
        Bind(Kin.KINSetUserData, 'KINSetUserData') and
        Bind(Kin.KINSetLinearSolver, 'KINSetLinearSolver') and
        Bind(Kin.KINSetNumMaxIters, 'KINSetNumMaxIters') and
        Bind(Kin.KINSetMaxSetupCalls, 'KINSetMaxSetupCalls') and
        Bind(Kin.KINSetMaxNewtonStep, 'KINSetMaxNewtonStep') and
        Bind(Kin.KINSetFuncNormTol, 'KINSetFuncNormTol') and
        Bind(Kin.KINSetScaledStepTol, 'KINSetScaledStepTol') and
        Bind(Kin.KINSol, 'KINSol') and
        Bind(Kin.KINGetNumNonlinSolvIters, 'KINGetNumNonlinSolvIters') and
        Bind(Kin.KINGetFuncNorm, 'KINGetFuncNorm') and
        Bind(Kin.KINGetReturnFlagName, 'KINGetReturnFlagName') and
        Bind(Kin.KINFree, 'KINFree');
  end;
  Result := Bound;
end;

function KinsolError: string;
begin
  KinsolAvailable;
  Result := LoadError;
end;

end.
