unit Axon.Random;

(* Random numbers: the generator behind the prelude's rand and the core module
   random (reference, "The random module").

   The generator is xoshiro256** (Blackman and Vigna), 256 bits of state,
   period 2^256 - 1, seeded through SplitMix64 as its authors recommend. A
   process starts from a seed taken from the clock, so runs differ; seed(n)
   makes every later draw, the prelude's rand included, reproducible.

   Reals in [0, 1) take the top 53 bits of a draw, so every value is a
   multiple of 2^-53. Normal deviates use Marsaglia's polar method, which
   makes two at a time; the second is kept for the next call and dropped by
   seed. Integers in a range use rejection, so every value is equally likely. *)

interface

// A real in [0, 1).
function RandomUniform: Double;

implementation

{$Q-}  // the generator's arithmetic is modulo 2^64
{$R-}

uses
  System.SysUtils, System.Math, System.Diagnostics, System.DateUtils,
  Axon.Errors, Axon.Values, Axon.Ops, Axon.NativeModules;

var
  S0, S1, S2, S3: UInt64;
  HaveSpare: Boolean;
  Spare: Double;

function SplitMix(var X: UInt64): UInt64;
var
  Z: UInt64;
begin
  X := X + UInt64($9E3779B97F4A7C15);
  Z := X;
  Z := (Z xor (Z shr 30)) * UInt64($BF58476D1CE4E5B9);
  Z := (Z xor (Z shr 27)) * UInt64($94D049BB133111EB);
  Result := Z xor (Z shr 31);
end;

procedure SeedWith(X: UInt64);
begin
  S0 := SplitMix(X);
  S1 := SplitMix(X);
  S2 := SplitMix(X);
  S3 := SplitMix(X);
  HaveSpare := False;
end;

function Rotl(X: UInt64; K: Integer): UInt64; inline;
begin
  Result := (X shl K) or (X shr (64 - K));
end;

function NextU64: UInt64;
var
  T: UInt64;
begin
  Result := Rotl(S1 * 5, 7) * 9;
  T := S1 shl 17;
  S2 := S2 xor S0;
  S3 := S3 xor S1;
  S1 := S1 xor S2;
  S0 := S0 xor S3;
  S2 := S2 xor T;
  S3 := Rotl(S3, 45);
end;

function RandomUniform: Double;
begin
  Result := (NextU64 shr 11) * (1.0 / 9007199254740992.0);   // 2^-53
end;

function RandomNormal: Double;
var
  U, V, S, M: Double;
begin
  if HaveSpare then
  begin
    HaveSpare := False;
    Exit(Spare);
  end;
  repeat
    U := 2 * RandomUniform - 1;
    V := 2 * RandomUniform - 1;
    S := U * U + V * V;
  until (S > 0) and (S < 1);
  M := Sqrt(-2 * Ln(S) / S);
  Spare := V * M;
  HaveSpare := True;
  Result := U * M;
end;

{ An integer in [Lo, Hi], Lo <= Hi, each equally likely. }
function RandomInt(Lo, Hi: Int64): Int64;
var
  Span, Limit, X: UInt64;
begin
  Span := UInt64(Hi) - UInt64(Lo) + 1;     // 0 means all 2^64 values
  if Span = 0 then
    Exit(Int64(NextU64));
  // 2^64 mod Span: draws below it are retried, which leaves a whole number
  // of copies of 0 .. Span - 1 (the method of OpenBSD's arc4random_uniform).
  Limit := (0 - Span) mod Span;
  repeat
    X := NextU64;
  until X >= Limit;
  Result := Int64(UInt64(Lo) + X mod Span);
end;

{ ---- arguments ---- }

function NumberArg(const Fn, What: string; const V: TAxValue): Double;
begin
  case V.Kind of
    vkInt: Result := V.I;
    vkReal: Result := V.R;
    vkBool: Result := Ord(V.B);
  else
    RaiseFmt(TypeError, '%s needs a real number for the %s, got %s', [Fn, What, TypeName(V)]);
    Result := 0;
  end;
  if IsNan(Result) or IsInfinite(Result) then
    RaiseFmt(DomainError, '%s needs a finite %s, got %s', [Fn, What, Display(V)]);
end;

function IntArg(const Fn, What: string; const V: TAxValue): Int64;
begin
  case V.Kind of
    vkInt: Result := V.I;
    vkBool: Result := Ord(V.B);
  else
    RaiseFmt(TypeError, '%s needs an int for the %s, got %s', [Fn, What, TypeName(V)]);
    Result := 0;
  end;
end;

function SizeArg(const Fn: string; const V: TAxValue): Integer;
begin
  if not (V.Kind in [vkInt, vkBool]) then
    RaiseFmt(ArgumentError, '%s needs int sizes, got %s', [Fn, TypeName(V)]);
  if V.Kind = vkBool then
    Result := Ord(V.B)
  else
  begin
    if (V.I < 0) or (V.I > MaxInt div 2) then
      RaiseFmt(ArgumentError, '%s: invalid size %d', [Fn, V.I]);
    Result := V.I;
  end;
end;

{ The result array for the shape arguments from Args[First]: none gives nil
  (a scalar is wanted), n a vector, m, n a matrix. }
function ShapeArray(const Fn: string; const Args: TAxValues; First: Integer;
  T: TElemType): TArrayObj;
begin
  case Length(Args) - First of
    0: Result := nil;
    1: Result := TArrayObj.Create(T, SizeArg(Fn, Args[First]), 1, True);
  else
    Result := TArrayObj.Create(T, SizeArg(Fn, Args[First]), SizeArg(Fn, Args[First + 1]), False);
  end;
end;

{ ---- the module's functions ---- }

function BSeed(const Args: TAxValues): TAxValue;
begin
  SeedWith(UInt64(IntArg('seed', 'seed', Args[0])));
  Result := NothingValue;
end;

function BRand(const Args: TAxValues): TAxValue;
var
  A: TArrayObj;
  K: Integer;
begin
  A := ShapeArray('rand', Args, 0, etReal);
  if A = nil then
    Exit(RealValue(RandomUniform));
  Result := ArrayValue(A);
  for K := 0 to A.Count - 1 do
    A.R[K] := RandomUniform;
end;

function BRandn(const Args: TAxValues): TAxValue;
var
  A: TArrayObj;
  K: Integer;
begin
  A := ShapeArray('randn', Args, 0, etReal);
  if A = nil then
    Exit(RealValue(RandomNormal));
  Result := ArrayValue(A);
  for K := 0 to A.Count - 1 do
    A.R[K] := RandomNormal;
end;

function BUniform(const Args: TAxValues): TAxValue;
var
  Lo, Hi, W: Double;
  A: TArrayObj;
  K: Integer;
begin
  Lo := NumberArg('uniform', 'lower bound', Args[0]);
  Hi := NumberArg('uniform', 'upper bound', Args[1]);
  if Lo > Hi then
    RaiseFmt(DomainError, 'uniform needs a <= b, got %s and %s',
      [Display(Args[0]), Display(Args[1])]);
  W := Hi - Lo;
  A := ShapeArray('uniform', Args, 2, etReal);
  if A = nil then
    Exit(RealValue(Lo + W * RandomUniform));
  Result := ArrayValue(A);
  for K := 0 to A.Count - 1 do
    A.R[K] := Lo + W * RandomUniform;
end;

function BNormal(const Args: TAxValues): TAxValue;
var
  Mu, Sigma: Double;
  A: TArrayObj;
  K: Integer;
begin
  Mu := NumberArg('normal', 'mean', Args[0]);
  Sigma := NumberArg('normal', 'standard deviation', Args[1]);
  if Sigma < 0 then
    RaiseFmt(DomainError, 'normal needs a non-negative standard deviation, got %s',
      [Display(Args[1])]);
  A := ShapeArray('normal', Args, 2, etReal);
  if A = nil then
    Exit(RealValue(Mu + Sigma * RandomNormal));
  Result := ArrayValue(A);
  for K := 0 to A.Count - 1 do
    A.R[K] := Mu + Sigma * RandomNormal;
end;

function BRandint(const Args: TAxValues): TAxValue;
var
  Lo, Hi: Int64;
  A: TArrayObj;
  K: Integer;
begin
  Lo := IntArg('randint', 'lower bound', Args[0]);
  Hi := IntArg('randint', 'upper bound', Args[1]);
  if Lo > Hi then
    RaiseFmt(DomainError, 'randint needs lo <= hi, got %d and %d', [Lo, Hi]);
  A := ShapeArray('randint', Args, 2, etInt);
  if A = nil then
    Exit(IntValue(RandomInt(Lo, Hi)));
  Result := ArrayValue(A);
  for K := 0 to A.Count - 1 do
    A.I[K] := RandomInt(Lo, Hi);
end;

procedure DefineRandom(const Define: TProc<string, TAxValue>);
begin
  Define('seed', BuiltinValue('seed', BSeed, 1, 1));
  Define('rand', BuiltinValue('rand', BRand, 0, 2));
  Define('randn', BuiltinValue('randn', BRandn, 0, 2));
  Define('uniform', BuiltinValue('uniform', BUniform, 2, 4));
  Define('normal', BuiltinValue('normal', BNormal, 2, 4));
  Define('randint', BuiltinValue('randint', BRandint, 2, 4));
end;

procedure SeedFromClock;
var
  Local: Integer;
begin
  // Clock ticks, wall time and a stack address (randomised by the OS), mixed
  // by SplitMix; enough for runs to differ, not for cryptography.
  SeedWith(UInt64(TStopwatch.GetTimeStamp) xor
    (UInt64(DateTimeToUnix(Now, False)) shl 20) xor
    UInt64(NativeUInt(@Local)));
end;

initialization
  SeedFromClock;
  RegisterNativeModule('random', DefineRandom,
    ['Random numbers: uniform, normal and integer, as scalars, vectors or matrices.',
     'seed(n) makes every later draw reproducible, the prelude''s rand included.']);

end.
