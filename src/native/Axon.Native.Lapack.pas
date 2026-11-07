unit Axon.Native.Lapack;

{ LAPACK through OpenBLAS's LAPACKE interface, for the core \, / and ^
  operators. The linalg module binds the rest of LAPACK itself, from Axon,
  with extern declarations.

  lapack_int is 32 bits in the OpenBLAS builds shipped with Axon. Complex
  arrays are pairs of doubles (C99 double _Complex), matching TComplex. }

interface

uses
  Axon.Complex;

const
  LapackColMajor = 102;

type
  PComplexArr = ^TComplex;

  TLAPACKE_dgetrf = function(Layout, M, N: Int32; A: PDouble; LdA: Int32; IPiv: PInteger): Int32; cdecl;
  TLAPACKE_zgetrf = function(Layout, M, N: Int32; A: PComplexArr; LdA: Int32; IPiv: PInteger): Int32; cdecl;
  TLAPACKE_dgetrs = function(Layout: Int32; Trans: AnsiChar; N, NRhs: Int32; A: PDouble; LdA: Int32;
    IPiv: PInteger; B: PDouble; LdB: Int32): Int32; cdecl;
  TLAPACKE_zgetrs = function(Layout: Int32; Trans: AnsiChar; N, NRhs: Int32; A: PComplexArr; LdA: Int32;
    IPiv: PInteger; B: PComplexArr; LdB: Int32): Int32; cdecl;
  TLAPACKE_dgecon = function(Layout: Int32; Norm: AnsiChar; N: Int32; A: PDouble; LdA: Int32;
    ANorm: Double; RCond: PDouble): Int32; cdecl;
  TLAPACKE_zgecon = function(Layout: Int32; Norm: AnsiChar; N: Int32; A: PComplexArr; LdA: Int32;
    ANorm: Double; RCond: PDouble): Int32; cdecl;
  TLAPACKE_dlange = function(Layout: Int32; Norm: AnsiChar; M, N: Int32; A: PDouble; LdA: Int32): Double; cdecl;
  TLAPACKE_zlange = function(Layout: Int32; Norm: AnsiChar; M, N: Int32; A: PComplexArr; LdA: Int32): Double; cdecl;
  TLAPACKE_dgelsd = function(Layout, M, N, NRhs: Int32; A: PDouble; LdA: Int32; B: PDouble; LdB: Int32;
    S: PDouble; RCond: Double; Rank: PInteger): Int32; cdecl;
  TLAPACKE_zgelsd = function(Layout, M, N, NRhs: Int32; A: PComplexArr; LdA: Int32; B: PComplexArr;
    LdB: Int32; S: PDouble; RCond: Double; Rank: PInteger): Int32; cdecl;
  TLAPACKE_zgeev = function(Layout: Int32; JobVL, JobVR: AnsiChar; N: Int32; A: PComplexArr; LdA: Int32;
    W: PComplexArr; VL: PComplexArr; LdVL: Int32; VR: PComplexArr; LdVR: Int32): Int32; cdecl;

var
  LAPACKE_dgetrf: TLAPACKE_dgetrf;
  LAPACKE_zgetrf: TLAPACKE_zgetrf;
  LAPACKE_dgetrs: TLAPACKE_dgetrs;
  LAPACKE_zgetrs: TLAPACKE_zgetrs;
  LAPACKE_dgecon: TLAPACKE_dgecon;
  LAPACKE_zgecon: TLAPACKE_zgecon;
  LAPACKE_dlange: TLAPACKE_dlange;
  LAPACKE_zlange: TLAPACKE_zlange;
  LAPACKE_dgelsd: TLAPACKE_dgelsd;
  LAPACKE_zgelsd: TLAPACKE_zgelsd;
  LAPACKE_zgeev: TLAPACKE_zgeev;

{ Binds the functions above, raising ForeignError if OpenBLAS (or one of
  them) is missing. }
procedure NeedLapack;

implementation

uses
  System.SysUtils,
  Axon.Errors, Axon.Native.Blas;

var
  Bound: Boolean;

procedure NeedLapack;

  function Sym(const Name: string): Pointer;
  begin
    Result := OpenBlasSymbol(Name);
    if Result = nil then
      raise EAxonError.Create(ForeignError, Format(
        'linear algebra needs OpenBLAS (%s), which could not be loaded or lacks %s',
        [LibraryName, Name]));
  end;

begin
  if Bound then
    Exit;
  @LAPACKE_dgetrf := Sym('LAPACKE_dgetrf');
  @LAPACKE_zgetrf := Sym('LAPACKE_zgetrf');
  @LAPACKE_dgetrs := Sym('LAPACKE_dgetrs');
  @LAPACKE_zgetrs := Sym('LAPACKE_zgetrs');
  @LAPACKE_dgecon := Sym('LAPACKE_dgecon');
  @LAPACKE_zgecon := Sym('LAPACKE_zgecon');
  @LAPACKE_dlange := Sym('LAPACKE_dlange');
  @LAPACKE_zlange := Sym('LAPACKE_zlange');
  @LAPACKE_dgelsd := Sym('LAPACKE_dgelsd');
  @LAPACKE_zgelsd := Sym('LAPACKE_zgelsd');
  @LAPACKE_zgeev := Sym('LAPACKE_zgeev');
  Bound := True;
end;

end.
