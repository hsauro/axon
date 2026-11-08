unit Axon.Native.Cvode;

{ SUNDIALS CVODE for odecore's BDF loop (Axon.OdeCore, J7b).

  The libraries are the ones the ode module used through extern before:
  sundials_core and sundials_cvode, next to the interpreter or on the system
  search path, loaded on first use (CvodeAvailable). C's long is LongInt,
  which is 32-bit on Windows and 64-bit on macOS and Linux, as in C;
  sunindextype is 64-bit and sunrealtype double in the shipped builds. }

interface

const
{$IFDEF MSWINDOWS}
  LibraryName = 'sundials_cvode.dll';
{$ENDIF}
{$IFDEF MACOS}
  LibraryName = 'libsundials_cvode.dylib';
{$ENDIF}
{$IFDEF LINUX}
  LibraryName = 'libsundials_cvode.so';
{$ENDIF}

  CV_BDF = 2;
  CV_ONE_STEP = 2;
  CV_ROOT_RETURN = 2;

type
  TCvRhsFn = function(T: Double; Y, YDot, User: Pointer): Integer; cdecl;
  TCvRootFn = function(T: Double; Y: Pointer; GOut: PDouble; User: Pointer): Integer; cdecl;

var
  SUNContext_Create: function(Comm: Pointer; var Ctx: Pointer): Integer; cdecl;
  SUNContext_Free: function(var Ctx: Pointer): Integer; cdecl;
  SUNContext_ClearErrHandlers: function(Ctx: Pointer): Integer; cdecl;
  N_VGetArrayPointer: function(V: Pointer): PDouble; cdecl;
  N_VDestroy: procedure(V: Pointer); cdecl;
  SUNMatDestroy: procedure(A: Pointer); cdecl;
  SUNLinSolFree: function(LS: Pointer): Integer; cdecl;
  N_VNew_Serial: function(N: Int64; Ctx: Pointer): Pointer; cdecl;
  SUNDenseMatrix: function(M, N: Int64; Ctx: Pointer): Pointer; cdecl;
  SUNLinSol_Dense: function(Y, A, Ctx: Pointer): Pointer; cdecl;
  CVodeCreate: function(Lmm: Integer; Ctx: Pointer): Pointer; cdecl;
  CVodeInit: function(Mem: Pointer; F: TCvRhsFn; T0: Double; Y0: Pointer): Integer; cdecl;
  CVodeSStolerances: function(Mem: Pointer; RTol, ATol: Double): Integer; cdecl;
  CVodeSetLinearSolver: function(Mem, LS, A: Pointer): Integer; cdecl;
  CVodeSetMaxNumSteps: function(Mem: Pointer; MxSteps: LongInt): Integer; cdecl;
  CVodeSetMaxStep: function(Mem: Pointer; HMax: Double): Integer; cdecl;
  CVodeSetInitStep: function(Mem: Pointer; H: Double): Integer; cdecl;
  CVodeSetStopTime: function(Mem: Pointer; TStop: Double): Integer; cdecl;
  CVodeSetUserData: function(Mem, Data: Pointer): Integer; cdecl;
  CVodeRootInit: function(Mem: Pointer; NrtFn: Integer; G: TCvRootFn): Integer; cdecl;
  CVodeGetRootInfo: function(Mem: Pointer; RootsFound: PInteger): Integer; cdecl;
  CVode: function(Mem: Pointer; TOut: Double; YOut: Pointer; var TRet: Double; ITask: Integer): Integer; cdecl;
  CVodeGetDky: function(Mem: Pointer; T: Double; K: Integer; Dky: Pointer): Integer; cdecl;
  CVodeGetReturnFlagName: function(Flag: LongInt): PAnsiChar; cdecl;
  CVodeFree: procedure(var Mem: Pointer); cdecl;

{ True when both libraries are loaded and every function bound; otherwise
  CvodeError says why. }
function CvodeAvailable: Boolean;
function CvodeError: string;

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

function CvodeAvailable: Boolean;
var
  Core, Cv: NativeUInt;

  function Bind(var P; const Name: string): Boolean;
  begin
    // A symbol may live in either library.
    Pointer(P) := NativeSymbol(Cv, Name);
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
    Core := LoadLib('sundials_core');
    Cv := LoadLib('sundials_cvode');
    if (Core = 0) or (Cv = 0) then
      LoadError := 'cannot load the SUNDIALS libraries (sundials_core, sundials_cvode)'
    else
      Bound :=
        Bind(SUNContext_Create, 'SUNContext_Create') and
        Bind(SUNContext_Free, 'SUNContext_Free') and
        Bind(SUNContext_ClearErrHandlers, 'SUNContext_ClearErrHandlers') and
        Bind(N_VGetArrayPointer, 'N_VGetArrayPointer') and
        Bind(N_VDestroy, 'N_VDestroy') and
        Bind(SUNMatDestroy, 'SUNMatDestroy') and
        Bind(SUNLinSolFree, 'SUNLinSolFree') and
        Bind(N_VNew_Serial, 'N_VNew_Serial') and
        Bind(SUNDenseMatrix, 'SUNDenseMatrix') and
        Bind(SUNLinSol_Dense, 'SUNLinSol_Dense') and
        Bind(CVodeCreate, 'CVodeCreate') and
        Bind(CVodeInit, 'CVodeInit') and
        Bind(CVodeSStolerances, 'CVodeSStolerances') and
        Bind(CVodeSetLinearSolver, 'CVodeSetLinearSolver') and
        Bind(CVodeSetMaxNumSteps, 'CVodeSetMaxNumSteps') and
        Bind(CVodeSetMaxStep, 'CVodeSetMaxStep') and
        Bind(CVodeSetInitStep, 'CVodeSetInitStep') and
        Bind(CVodeSetStopTime, 'CVodeSetStopTime') and
        Bind(CVodeSetUserData, 'CVodeSetUserData') and
        Bind(CVodeRootInit, 'CVodeRootInit') and
        Bind(CVodeGetRootInfo, 'CVodeGetRootInfo') and
        Bind(CVode, 'CVode') and
        Bind(CVodeGetDky, 'CVodeGetDky') and
        Bind(CVodeGetReturnFlagName, 'CVodeGetReturnFlagName') and
        Bind(CVodeFree, 'CVodeFree');
  end;
  Result := Bound;
end;

function CvodeError: string;
begin
  CvodeAvailable;
  Result := LoadError;
end;

end.
