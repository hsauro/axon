unit Axon.FloatParse;

(* Decimal text to the nearest Double, correctly rounded (ties to even), for
   real and imaginary literals; and the reverse, a Double as text with a
   fixed number of decimals (format, display_decimals), also exact. Delphi's TryStrToFloat is off by one unit in
   the last place for some 17-digit inputs, so a printed value read back could
   change.

   Two paths:
   - Clinger's fast path: when the significant digits fit in 15 decimal digits
     and the power of ten is at most 22, both are exact doubles and one
     multiplication or division rounds correctly.
   - Otherwise the "decimal" algorithm of Go's strconv (atof.go, decimal.go):
     the digits are kept in a buffer and shifted by powers of two until the
     value lies in [1/2, 1), then 53 bits are taken with one rounding. At most
     800 digits are kept; a nonzero digit beyond them sets Trunc, which is
     enough to round halfway cases correctly. *)

interface

// S is digits, an optional '.' and digits, and an optional exponent
// (e or E, an optional sign, digits); at least one digit before the
// exponent. Returns False for anything else. Overflow gives +Inf, and
// underflow 0 or a subnormal.
function TryDecimalToDouble(const S: string; out D: Double): Boolean;

// A number written as text, for real("...") and io.read_csv: surrounding
// spaces and tabs are ignored; an optional sign, then a decimal number as
// TryDecimalToDouble reads it, or NaN, Inf or Infinity in any case.
function TryParseReal(const S: string; out D: Double): Boolean;

// An integer written as text, for int("..."): surrounding spaces and tabs
// ignored, an optional sign, then digits; False beyond the 64-bit range.
function TryParseInt(const S: string; out I: Int64): Boolean;

// X with exactly Decimals digits after the point, rounded from X's exact
// binary value (ties to even): FormatFixed(2.675, 2) is '2.67' because the
// double nearest 2.675 is just below it. Decimals = 0 gives no point. A
// result whose digits are all zero has no minus sign. NaN, Inf and -Inf are
// written as words.
function FormatFixed(X: Double; Decimals: Integer): string;

// X as d.ddd...e<exp> with Decimals digits after the point (exponent form),
// rounded exactly as FormatFixed.
function FormatExponent(X: Double; Decimals: Integer): string;

implementation

{$Q-}
{$R-}

uses
  System.SysUtils, System.Math;

const
  MaxDigits = 800;
  MaxShift = 60;          // a digit shifted by this still fits in UInt64 with the carry
  PowTab: array[0..8] of Integer = (1, 3, 6, 9, 13, 16, 19, 23, 26);

var
  // 10^0 .. 10^22, all exact doubles; made by multiplication (each product is
  // exact) rather than read from literals.
  Pow10: array[0..22] of Double;

type
  // The value is 0.D[0] D[1] ... D[ND-1] * 10^DP, digits as 0..9.
  TDecimal = record
    D: array[0..MaxDigits - 1] of Byte;
    ND: Integer;
    DP: Integer;
    Trunc: Boolean;       // nonzero digits were dropped after D[ND-1]
    procedure Trim;
    procedure RightShift(K: Integer);
    procedure LeftShift(K: Integer);
    procedure Shift(K: Integer);
    function ShouldRoundUp(N: Integer): Boolean;
    function RoundedInteger: UInt64;
  end;

procedure TDecimal.Trim;
begin
  while (ND > 0) and (D[ND - 1] = 0) do
    Dec(ND);
  if ND = 0 then
    DP := 0;
end;

procedure TDecimal.RightShift(K: Integer);
var
  R, W: Integer;
  N, Mask, Dig: UInt64;
begin
  R := 0;
  W := 0;
  N := 0;
  // Read enough leading digits that N >> K is nonzero.
  while (N shr K) = 0 do
  begin
    if R >= ND then
    begin
      if N = 0 then
      begin
        ND := 0;           // a zero value
        DP := 0;
        Exit;
      end;
      while (N shr K) = 0 do
      begin
        N := N * 10;
        Inc(R);
      end;
      Break;
    end;
    N := N * 10 + D[R];
    Inc(R);
  end;
  DP := DP - (R - 1);
  Mask := (UInt64(1) shl K) - 1;
  // Each further digit read, one written.
  while R < ND do
  begin
    Dig := N shr K;
    N := N and Mask;
    D[W] := Byte(Dig);
    Inc(W);
    N := N * 10 + D[R];
    Inc(R);
  end;
  // The remaining bits.
  while N > 0 do
  begin
    Dig := N shr K;
    N := N and Mask;
    if W < MaxDigits then
    begin
      D[W] := Byte(Dig);
      Inc(W);
    end
    else if Dig > 0 then
      Trunc := True;
    N := N * 10;
  end;
  ND := W;
  Trim;
end;

procedure TDecimal.LeftShift(K: Integer);
var
  Rev: array[0..MaxDigits + 40] of Byte;   // the new digits, least significant first
  Count, R, I, NewND: Integer;
  N, Quo, Carry: UInt64;
begin
  Count := 0;
  Carry := 0;
  for R := ND - 1 downto 0 do
  begin
    N := (UInt64(D[R]) shl K) + Carry;
    Quo := N div 10;
    Rev[Count] := Byte(N - 10 * Quo);
    Inc(Count);
    Carry := Quo;
  end;
  while Carry > 0 do
  begin
    Quo := Carry div 10;
    Rev[Count] := Byte(Carry - 10 * Quo);
    Inc(Count);
    Carry := Quo;
  end;
  DP := DP + (Count - ND);
  // Keep the most significant MaxDigits; a dropped nonzero digit sets Trunc.
  NewND := Min(Count, MaxDigits);
  for I := 0 to Count - NewND - 1 do
    if Rev[I] <> 0 then
      Trunc := True;
  for I := 0 to NewND - 1 do
    D[I] := Rev[Count - 1 - I];
  ND := NewND;
  Trim;
end;

procedure TDecimal.Shift(K: Integer);
begin
  if ND = 0 then
    Exit;
  if K > 0 then
  begin
    while K > MaxShift do
    begin
      LeftShift(MaxShift);
      Dec(K, MaxShift);
    end;
    LeftShift(K);
  end
  else if K < 0 then
  begin
    while K < -MaxShift do
    begin
      RightShift(MaxShift);
      Inc(K, MaxShift);
    end;
    RightShift(-K);
  end;
end;

{ Whether rounding to N digits rounds up: above half, or exactly half with an
  odd last kept digit (ties to even); dropped digits count as above half. }
function TDecimal.ShouldRoundUp(N: Integer): Boolean;
begin
  if (N < 0) or (N >= ND) then
    Exit(False);
  if (D[N] = 5) and (N + 1 = ND) then
  begin
    if Trunc then
      Exit(True);
    Exit((N > 0) and Odd(D[N - 1]));
  end;
  Result := D[N] >= 5;
end;

{ The value rounded to an integer; it must be below 2^64. }
function TDecimal.RoundedInteger: UInt64;
var
  I: Integer;
begin
  if DP > 20 then
    Exit(High(UInt64));
  Result := 0;
  I := 0;
  while (I < DP) and (I < ND) do
  begin
    Result := Result * 10 + D[I];
    Inc(I);
  end;
  while I < DP do
  begin
    Result := Result * 10;
    Inc(I);
  end;
  if ShouldRoundUp(DP) then
    Inc(Result);
end;

function BitsToDouble(Bits: UInt64): Double;
begin
  Move(Bits, Result, SizeOf(Result));
end;

{ The slow path: Go's decimal.floatBits for float64. }
function DecimalToDouble(var A: TDecimal): Double;
const
  Bias = -1023;
  MantBits = 52;
  ExpBits = 11;
var
  Exp, N: Integer;
  Mant: UInt64;
begin
  if A.ND = 0 then
    Exit(0);
  // Clearly out of range: the digits start too far from the point.
  if A.DP > 310 then
    Exit(Infinity);
  if A.DP < -330 then
    Exit(0);
  // Scale by powers of two until the value is in [1/2, 1).
  Exp := 0;
  while A.DP > 0 do
  begin
    if A.DP >= Length(PowTab) then
      N := 27
    else
      N := PowTab[A.DP];
    A.Shift(-N);
    Inc(Exp, N);
  end;
  while (A.DP < 0) or ((A.DP = 0) and (A.D[0] < 5)) do
  begin
    if A.DP = 0 then
      N := 1
    else if -A.DP >= Length(PowTab) then
      N := 27
    else
      N := PowTab[-A.DP];
    A.Shift(N);
    Dec(Exp, N);
  end;
  // [1/2, 1) is [1, 2) with one less in the exponent.
  Dec(Exp);
  // Below the smallest normal exponent: shift into the subnormal range.
  if Exp < Bias + 1 then
  begin
    N := Bias + 1 - Exp;
    A.Shift(-N);
    Inc(Exp, N);
  end;
  if Exp - Bias >= (1 shl ExpBits) - 1 then
    Exit(Infinity);
  // 53 bits, rounded once.
  A.Shift(1 + MantBits);
  Mant := A.RoundedInteger;
  if Mant = UInt64(2) shl MantBits then
  begin
    Mant := Mant shr 1;
    Inc(Exp);
    if Exp - Bias >= (1 shl ExpBits) - 1 then
      Exit(Infinity);
  end;
  if Mant and (UInt64(1) shl MantBits) = 0 then
    Exp := Bias;            // subnormal
  Result := BitsToDouble((Mant and ((UInt64(1) shl MantBits) - 1)) or
    (UInt64((Exp - Bias) and ((1 shl ExpBits) - 1)) shl MantBits));
end;

function TryParseReal(const S: string; out D: Double): Boolean;
var
  T, W: string;
  Neg: Boolean;
begin
  T := S.Trim([' ', #9]);
  Neg := False;
  if (T <> '') and ((T[1] = '+') or (T[1] = '-')) then
  begin
    Neg := T[1] = '-';
    T := T.Substring(1);
  end;
  W := LowerCase(T);
  if W = 'nan' then
  begin
    D := NaN;
    Exit(True);
  end;
  if (W = 'inf') or (W = 'infinity') then
    D := Infinity
  else
  begin
    if (T = '') or not CharInSet(T[1], ['0'..'9', '.']) then
      Exit(False);
    if not TryDecimalToDouble(T, D) then
      Exit(False);
  end;
  if Neg then
    D := -D;
  Result := True;
end;

function TryParseInt(const S: string; out I: Int64): Boolean;
var
  T: string;
  K: Integer;
begin
  I := 0;
  T := S.Trim([' ', #9]);
  K := 1;
  if (T <> '') and ((T[1] = '+') or (T[1] = '-')) then
    K := 2;
  if K > Length(T) then
    Exit(False);
  for K := K to Length(T) do
    if not CharInSet(T[K], ['0'..'9']) then
      Exit(False);
  Result := TryStrToInt64(T, I);
end;

function TryDecimalToDouble(const S: string; out D: Double): Boolean;
var
  A: TDecimal;
  I, L, E, ESign, Digits: Integer;
  SawDot, SawDigit: Boolean;
  C: Char;
  Mant: UInt64;
  Exp10: Integer;
begin
  D := 0;
  Result := False;
  A.ND := 0;
  A.DP := 0;
  A.Trunc := False;
  L := Length(S);
  I := 1;
  SawDot := False;
  SawDigit := False;
  // Digits and the point. Leading zeros are not stored; DP counts the
  // digits before the point.
  while I <= L do
  begin
    C := S[I];
    if C = '.' then
    begin
      if SawDot then
        Exit;
      SawDot := True;
    end
    else if CharInSet(C, ['0'..'9']) then
    begin
      SawDigit := True;
      if (C = '0') and (A.ND = 0) then
      begin
        if SawDot then
          Dec(A.DP);       // 0.00ddd: the point moves left
      end
      else
      begin
        if A.ND < MaxDigits then
        begin
          A.D[A.ND] := Ord(C) - Ord('0');
          Inc(A.ND);
        end
        else if C <> '0' then
          A.Trunc := True;
        if not SawDot then
          Inc(A.DP);
      end;
    end
    else
      Break;
    Inc(I);
  end;
  if not SawDigit then
    Exit;
  // The exponent, clamped: anything beyond it is already 0 or Inf.
  if (I <= L) and CharInSet(S[I], ['e', 'E']) then
  begin
    Inc(I);
    ESign := 1;
    if (I <= L) and CharInSet(S[I], ['+', '-']) then
    begin
      if S[I] = '-' then
        ESign := -1;
      Inc(I);
    end;
    if (I > L) or not CharInSet(S[I], ['0'..'9']) then
      Exit;
    E := 0;
    while (I <= L) and CharInSet(S[I], ['0'..'9']) do
    begin
      if E < 100000 then
        E := E * 10 + Ord(S[I]) - Ord('0');
      Inc(I);
    end;
    A.DP := A.DP + ESign * E;
  end;
  if I <= L then
    Exit;
  Result := True;
  A.Trim;
  if A.ND = 0 then
    Exit;                   // zero
  // Fast path: an exact integer of at most 15 digits times or over an exact
  // power of ten.
  if (A.ND <= 15) and not A.Trunc then
  begin
    Mant := 0;
    for Digits := 0 to A.ND - 1 do
      Mant := Mant * 10 + A.D[Digits];
    Exp10 := A.DP - A.ND;
    if (Exp10 >= 0) and (Exp10 <= 22) then
    begin
      D := Mant * Pow10[Exp10];
      Exit;
    end;
    if (Exp10 < 0) and (Exp10 >= -22) then
    begin
      D := Mant / Pow10[-Exp10];
      Exit;
    end;
  end;
  D := DecimalToDouble(A);
end;

{ ---- formatting ---- }

{ The exact decimal value of |X| (finite, nonzero) in A. }
procedure ExactDecimal(X: Double; var A: TDecimal);
var
  Bits, Mant: UInt64;
  E2, I: Integer;
  S: string;
begin
  Move(X, Bits, 8);
  E2 := Integer((Bits shr 52) and $7FF);
  Mant := Bits and ((UInt64(1) shl 52) - 1);
  if E2 = 0 then
    E2 := -1074                       // subnormal: Mant * 2^-1074
  else
  begin
    Mant := Mant or (UInt64(1) shl 52);
    E2 := E2 - 1075;                  // Mant * 2^(E - 1023 - 52)
  end;
  S := UIntToStr(Mant);
  A.ND := Length(S);
  for I := 1 to Length(S) do
    A.D[I - 1] := Ord(S[I]) - Ord('0');
  A.DP := A.ND;
  A.Trunc := False;
  A.Trim;
  A.Shift(E2);                        // exact: at most 767 significant digits
end;

{ Rounds A to its first N digits (N may be 0 or beyond ND), ties to even. }
procedure RoundTo(var A: TDecimal; N: Integer);
var
  I: Integer;
begin
  if N < 0 then
  begin
    A.ND := 0;
    A.DP := 0;
    Exit;
  end;
  if N >= A.ND then
    Exit;
  if A.ShouldRoundUp(N) then
  begin
    I := N - 1;
    while (I >= 0) and (A.D[I] = 9) do
      Dec(I);
    if I < 0 then
    begin
      // All nines: 999 rounds up to 1000.
      A.D[0] := 1;
      A.ND := 1;
      Inc(A.DP);
      Exit;
    end;
    Inc(A.D[I]);
    A.ND := I + 1;
  end
  else
  begin
    A.ND := N;
    A.Trim;
  end;
end;

function Digit(const A: TDecimal; I: Integer): Char;
begin
  if (I >= 0) and (I < A.ND) then
    Result := Char(Ord('0') + A.D[I])
  else
    Result := '0';
end;

function SpecialText(X: Double; out S: string): Boolean;
begin
  Result := True;
  if IsNan(X) then
    S := 'NaN'
  else if IsInfinite(X) then
  begin
    if X > 0 then S := 'Inf' else S := '-Inf';
  end
  else
    Result := False;
end;

function FormatFixed(X: Double; Decimals: Integer): string;
var
  A: TDecimal;
  SB: TStringBuilder;
  I: Integer;
begin
  if SpecialText(X, Result) then
    Exit;
  A.ND := 0;
  A.DP := 0;
  A.Trunc := False;
  if X <> 0 then
  begin
    ExactDecimal(Abs(X), A);
    RoundTo(A, A.DP + Decimals);
  end;
  SB := TStringBuilder.Create;
  try
    if (X < 0) and (A.ND > 0) then
      SB.Append('-');
    if A.DP <= 0 then
      SB.Append('0')
    else
      for I := 0 to A.DP - 1 do
        SB.Append(Digit(A, I));
    if Decimals > 0 then
    begin
      SB.Append('.');
      for I := A.DP to A.DP + Decimals - 1 do
        SB.Append(Digit(A, I));
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function FormatExponent(X: Double; Decimals: Integer): string;
var
  A: TDecimal;
  SB: TStringBuilder;
  I, E: Integer;
begin
  if SpecialText(X, Result) then
    Exit;
  A.ND := 0;
  A.DP := 0;
  A.Trunc := False;
  E := 0;
  if X <> 0 then
  begin
    ExactDecimal(Abs(X), A);
    RoundTo(A, 1 + Decimals);
    E := A.DP - 1;
  end;
  SB := TStringBuilder.Create;
  try
    if (X < 0) and (A.ND > 0) then
      SB.Append('-');
    SB.Append(Digit(A, 0));
    if Decimals > 0 then
    begin
      SB.Append('.');
      for I := 1 to Decimals do
        SB.Append(Digit(A, I));
    end;
    SB.Append('e').Append(E);
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

procedure InitPow10;
var
  K: Integer;
begin
  Pow10[0] := 1;
  for K := 1 to High(Pow10) do
    Pow10[K] := Pow10[K - 1] * 10;
end;

initialization
  InitPow10;

end.
