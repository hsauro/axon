unit Axon.Complex;

(* Complex arithmetic and elementary functions on pairs of doubles, with the
   C99 `double _Complex` layout (real part first).

   Multi-valued functions return principal values:
     sqrt   branch cut on the negative real axis, Re(result) >= 0
     log    imaginary part in (-pi, pi]
     asin, acos, atan, asinh, acosh, atanh  standard principal branches
   Real arithmetic follows IEEE 754; callers mask floating-point exceptions. *)

interface

type
  TComplex = record
    Re, Im: Double;
  end;

function Cx(Re, Im: Double): TComplex; inline;

function CAdd(const A, B: TComplex): TComplex; inline;
function CSub(const A, B: TComplex): TComplex; inline;
function CMul(const A, B: TComplex): TComplex; inline;
function CDiv(const A, B: TComplex): TComplex;
function CNeg(const A: TComplex): TComplex; inline;
function CConj(const A: TComplex): TComplex; inline;
function CEqual(const A, B: TComplex): Boolean; inline;

function CAbs(const A: TComplex): Double;
function CArg(const A: TComplex): Double;

function CSqrt(const A: TComplex): TComplex;
function CExp(const A: TComplex): TComplex;
function CLog(const A: TComplex): TComplex;
function CPow(const A, B: TComplex): TComplex;
function CSin(const A: TComplex): TComplex;
function CCos(const A: TComplex): TComplex;
function CTan(const A: TComplex): TComplex;
function CSinh(const A: TComplex): TComplex;
function CCosh(const A: TComplex): TComplex;
function CTanh(const A: TComplex): TComplex;
function CAsin(const A: TComplex): TComplex;
function CAcos(const A: TComplex): TComplex;
function CAtan(const A: TComplex): TComplex;
function CAsinh(const A: TComplex): TComplex;
function CAcosh(const A: TComplex): TComplex;
function CAtanh(const A: TComplex): TComplex;

implementation

uses
  System.Math;

function Cx(Re, Im: Double): TComplex;
begin
  Result.Re := Re;
  Result.Im := Im;
end;

function CAdd(const A, B: TComplex): TComplex;
begin
  Result.Re := A.Re + B.Re;
  Result.Im := A.Im + B.Im;
end;

function CSub(const A, B: TComplex): TComplex;
begin
  Result.Re := A.Re - B.Re;
  Result.Im := A.Im - B.Im;
end;

function CMul(const A, B: TComplex): TComplex;
begin
  Result.Re := A.Re * B.Re - A.Im * B.Im;
  Result.Im := A.Re * B.Im + A.Im * B.Re;
end;

{ Smith's algorithm, which avoids overflow in the intermediate products. }
function CDiv(const A, B: TComplex): TComplex;
var
  R, D: Double;
begin
  if Abs(B.Re) >= Abs(B.Im) then
  begin
    if B.Re = 0 then
    begin
      // B is zero: IEEE division of each part.
      Result.Re := A.Re / B.Re;
      Result.Im := A.Im / B.Re;
      Exit;
    end;
    R := B.Im / B.Re;
    D := B.Re + B.Im * R;
    Result.Re := (A.Re + A.Im * R) / D;
    Result.Im := (A.Im - A.Re * R) / D;
  end
  else
  begin
    R := B.Re / B.Im;
    D := B.Re * R + B.Im;
    Result.Re := (A.Re * R + A.Im) / D;
    Result.Im := (A.Im * R - A.Re) / D;
  end;
end;

function CNeg(const A: TComplex): TComplex;
begin
  Result.Re := -A.Re;
  Result.Im := -A.Im;
end;

function CConj(const A: TComplex): TComplex;
begin
  Result.Re := A.Re;
  Result.Im := -A.Im;
end;

function CEqual(const A, B: TComplex): Boolean;
begin
  Result := (A.Re = B.Re) and (A.Im = B.Im);
end;

function CAbs(const A: TComplex): Double;
begin
  Result := Hypot(A.Re, A.Im);
end;

function CArg(const A: TComplex): Double;
begin
  Result := ArcTan2(A.Im, A.Re);
end;

function CSqrt(const A: TComplex): TComplex;
var
  R, T: Double;
begin
  if (A.Re = 0) and (A.Im = 0) then
    Exit(Cx(0, A.Im));
  R := CAbs(A);
  T := Sqrt((R + Abs(A.Re)) / 2);
  if A.Re >= 0 then
    Result := Cx(T, A.Im / (2 * T))
  else if A.Im < 0 then
    Result := Cx(Abs(A.Im) / (2 * T), -T)
  else
    Result := Cx(Abs(A.Im) / (2 * T), T);
end;

function CExp(const A: TComplex): TComplex;
var
  E: Double;
begin
  E := Exp(A.Re);
  if A.Im = 0 then
    Exit(Cx(E, A.Im));
  Result := Cx(E * Cos(A.Im), E * Sin(A.Im));
end;

function CLog(const A: TComplex): TComplex;
begin
  Result := Cx(Ln(CAbs(A)), CArg(A));
end;

function CPow(const A, B: TComplex): TComplex;
begin
  if (A.Re = 0) and (A.Im = 0) then
  begin
    if (B.Re = 0) and (B.Im = 0) then
      Exit(Cx(1, 0));
    if (B.Im = 0) and (B.Re > 0) then
      Exit(Cx(0, 0));
  end;
  Result := CExp(CMul(B, CLog(A)));
end;

function CSin(const A: TComplex): TComplex;
begin
  Result := Cx(Sin(A.Re) * Cosh(A.Im), Cos(A.Re) * Sinh(A.Im));
end;

function CCos(const A: TComplex): TComplex;
begin
  Result := Cx(Cos(A.Re) * Cosh(A.Im), -Sin(A.Re) * Sinh(A.Im));
end;

function CTan(const A: TComplex): TComplex;
begin
  Result := CDiv(CSin(A), CCos(A));
end;

function CSinh(const A: TComplex): TComplex;
begin
  Result := Cx(Sinh(A.Re) * Cos(A.Im), Cosh(A.Re) * Sin(A.Im));
end;

function CCosh(const A: TComplex): TComplex;
begin
  Result := Cx(Cosh(A.Re) * Cos(A.Im), Sinh(A.Re) * Sin(A.Im));
end;

function CTanh(const A: TComplex): TComplex;
begin
  Result := CDiv(CSinh(A), CCosh(A));
end;

const
  CI: TComplex = (Re: 0; Im: 1);
  COne: TComplex = (Re: 1; Im: 0);

{ asin z = -i log(iz + sqrt(1 - z^2)) }
function CAsin(const A: TComplex): TComplex;
var
  W: TComplex;
begin
  W := CLog(CAdd(CMul(CI, A), CSqrt(CSub(COne, CMul(A, A)))));
  Result := Cx(W.Im, -W.Re);
end;

{ acos z = pi/2 - asin z }
function CAcos(const A: TComplex): TComplex;
var
  S: TComplex;
begin
  S := CAsin(A);
  Result := Cx(Pi / 2 - S.Re, -S.Im);
end;

{ atan z = (i/2) (log(1 - iz) - log(1 + iz)) }
function CAtan(const A: TComplex): TComplex;
var
  IZ, D: TComplex;
begin
  IZ := CMul(CI, A);
  D := CSub(CLog(CSub(COne, IZ)), CLog(CAdd(COne, IZ)));
  Result := Cx(-D.Im / 2, D.Re / 2);
end;

{ asinh z = log(z + sqrt(z^2 + 1)) }
function CAsinh(const A: TComplex): TComplex;
begin
  Result := CLog(CAdd(A, CSqrt(CAdd(CMul(A, A), COne))));
end;

{ acosh z = log(z + sqrt(z + 1) sqrt(z - 1)) }
function CAcosh(const A: TComplex): TComplex;
begin
  Result := CLog(CAdd(A, CMul(CSqrt(CAdd(A, COne)), CSqrt(CSub(A, COne)))));
end;

{ atanh z = (log(1 + z) - log(1 - z)) / 2 }
function CAtanh(const A: TComplex): TComplex;
var
  D: TComplex;
begin
  D := CSub(CLog(CAdd(COne, A)), CLog(CSub(COne, A)));
  Result := Cx(D.Re / 2, D.Im / 2);
end;

end.
