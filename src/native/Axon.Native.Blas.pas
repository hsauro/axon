unit Axon.Native.Blas;

{ OpenBLAS: the CBLAS matrix products used by the core * operator.

  The library is loaded on first use rather than linked statically, so the
  interpreter starts (and falls back to a plain loop for *) when OpenBLAS is
  not installed. It is looked for next to the interpreter first, then on the
  system search path. Axon.Native.Lapack shares the same library handle. }

interface

uses
  Axon.Complex;

const
{$IFDEF MSWINDOWS}
  LibraryName = 'libopenblas.dll';
{$ENDIF}
{$IFDEF MACOS}
  LibraryName = 'libopenblas.dylib';
{$ENDIF}
{$IFDEF LINUX}
  LibraryName = 'libopenblas.so.0';
{$ENDIF}

  CblasColMajor = 102;
  CblasNoTrans = 111;

type
  Tcblas_dgemm = procedure(Order, TransA, TransB, M, N, K: Int32; Alpha: Double;
    A: PDouble; LdA: Int32; B: PDouble; LdB: Int32; Beta: Double; C: PDouble;
    LdC: Int32); cdecl;
  Tcblas_zgemm = procedure(Order, TransA, TransB, M, N, K: Int32; Alpha: Pointer;
    A: Pointer; LdA: Int32; B: Pointer; LdB: Int32; Beta: Pointer; C: Pointer;
    LdC: Int32); cdecl;

var
  cblas_dgemm: Tcblas_dgemm;
  cblas_zgemm: Tcblas_zgemm;

{ The OpenBLAS handle, loading it on the first call; 0 if it is unavailable. }
function OpenBlasHandle: NativeUInt;
{ True when the CBLAS products are available. }
function BlasAvailable: Boolean;
{ A symbol of OpenBLAS, or nil. }
function OpenBlasSymbol(const Name: string): Pointer;

(* Sets the thread count of a library just loaded, if it is OpenBLAS (it
   exports openblas_set_num_threads); both OpenBlasHandle and extern's
   library loading call it. OpenBLAS starts one thread per logical CPU, but
   its LAPACK factorisations (LU, eigenvalues, SVD) slow down badly with many
   threads, while the matrix product gains little beyond a few: measured on
   a 10-core i9-9900X, LU of 500x500 took 47 ms on 20 threads and 6 ms on 4.
   So the count is capped at DefaultBlasThreads, unless the user chose one
   with OPENBLAS_NUM_THREADS or OMP_NUM_THREADS; linalg.set_threads changes
   it from a program. *)
procedure ConfigureOpenBlas(Lib: NativeUInt);

const
  DefaultBlasThreads = 4;

implementation

uses
  System.SysUtils,
  Axon.Platform;

var
  Handle: NativeUInt;
  Tried: Boolean;
  BlasBound: Boolean;

function OpenBlasHandle: NativeUInt;
begin
  if not Tried then
  begin
    Tried := True;
    Handle := LoadNativeLibrary(ExtractFilePath(ParamStr(0)) + LibraryName);
    if Handle = 0 then
      Handle := LoadNativeLibrary(LibraryName);
    if Handle <> 0 then
      ConfigureOpenBlas(Handle);
  end;
  Result := Handle;
end;

function OpenBlasSymbol(const Name: string): Pointer;
begin
  if OpenBlasHandle = 0 then
    Exit(nil);
  Result := NativeSymbol(Handle, Name);
end;

procedure ConfigureOpenBlas(Lib: NativeUInt);
type
  TGetThreads = function: Int32; cdecl;
  TSetThreads = procedure(N: Int32); cdecl;
var
  GetThreads: TGetThreads;
  SetThreads: TSetThreads;
begin
  if (GetEnvironmentVariable('OPENBLAS_NUM_THREADS') <> '') or
    (GetEnvironmentVariable('OMP_NUM_THREADS') <> '') then
    Exit;
  @GetThreads := NativeSymbol(Lib, 'openblas_get_num_threads');
  @SetThreads := NativeSymbol(Lib, 'openblas_set_num_threads');
  if Assigned(GetThreads) and Assigned(SetThreads) and (GetThreads() > DefaultBlasThreads) then
    SetThreads(DefaultBlasThreads);
end;

function BlasAvailable: Boolean;
begin
  if not BlasBound then
  begin
    BlasBound := True;
    @cblas_dgemm := OpenBlasSymbol('cblas_dgemm');
    @cblas_zgemm := OpenBlasSymbol('cblas_zgemm');
  end;
  Result := Assigned(cblas_dgemm) and Assigned(cblas_zgemm);
end;

end.
