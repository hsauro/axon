library axontest;

{ Native test library for the M9 foreign-function tests. It is written in
  Delphi rather than C so that no C compiler is needed; every function is
  exported with the C calling convention. build.cmd builds it into
  tests/m09/bin. }

{$POINTERMATH ON}

uses
  System.SysUtils, System.Classes, System.AnsiStrings;

type
  TIntCb = function(X: Int32): Int32; cdecl;
  TDblCb = function(T, Y: Double): Double; cdecl;
  TMixedCb = function(A: Int32; B: Double; C: Pointer; D: Single; E: Int64): Double; cdecl;
  TManyCb = function(A1, A2, A3, A4, A5, A6: Int64; D1: Double): Int64; cdecl;
  TF32Cb = function(X: Single): Single; cdecl;
  TPtrCb = function(P: Pointer): Pointer; cdecl;
  TVoidCb = procedure(X: Int32); cdecl;

var
  Stored: TIntCb;
  GreetingText: UTF8String = 'h'#$00E9'llo from Delphi';   // é as a code: sources are read as ANSI

{ ---- scalars ---- }

function add_i32(A, B: Int32): Int32; cdecl;
begin
  Result := A + B;
end;

function add_i64(A, B: Int64): Int64; cdecl;
begin
  Result := A + B;
end;

function add_u8(A, B: Byte): Byte; cdecl;
begin
  Result := Byte(A + B);
end;

function neg_i8(A: ShortInt): ShortInt; cdecl;
begin
  Result := -A;
end;

function max_u32: Cardinal; cdecl;
begin
  Result := High(Cardinal);
end;

function mul_f64(A, B: Double): Double; cdecl;
begin
  Result := A * B;
end;

function mul_f32(A, B: Single): Single; cdecl;
begin
  Result := A * B;
end;

{ Integer and floating-point arguments in alternating register positions. }
function mixed(A: Int32; B: Double; C: Int64; D: Single; E: Int32; F: Double): Double; cdecl;
begin
  Result := A + B + C + D + E + F;
end;

{ Ten arguments: several are passed on the stack. Weighted so that order matters. }
function many(A1, A2, A3, A4, A5, A6, A7, A8, A9, A10: Int64): Int64; cdecl;
begin
  Result := A1 + 2 * A2 + 3 * A3 + 4 * A4 + 5 * A5 + 6 * A6 + 7 * A7 + 8 * A8 + 9 * A9 + 10 * A10;
end;

function char_code(C: AnsiChar): Int32; cdecl;
begin
  Result := Ord(C);
end;

{ ---- ref ---- }

procedure set_i32(P: PInteger; V: Int32); cdecl;
begin
  P^ := V;
end;

procedure incr_f64(P: PDouble); cdecl;
begin
  P^ := P^ + 1;
end;

procedure swap_i64(A, B: PInt64); cdecl;
var
  T: Int64;
begin
  T := A^;
  A^ := B^;
  B^ := T;
end;

{ ---- ptr ---- }

procedure scale_f64(P: PDouble; N: Int32; F: Double); cdecl;
var
  I: Integer;
begin
  for I := 0 to N - 1 do
    P[I] := P[I] * F;
end;

function sum_i32(P: PInteger; N: Int32): Int32; cdecl;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to N - 1 do
    Inc(Result, P[I]);
end;

procedure double_i32(P: PInteger; N: Int32); cdecl;
var
  I: Integer;
begin
  for I := 0 to N - 1 do
    P[I] := 2 * P[I];
end;

procedure negate_i64(P: PInt64; N: Int32); cdecl;
var
  I: Integer;
begin
  for I := 0 to N - 1 do
    P[I] := -P[I];
end;

{ Complex numbers are pairs of doubles: negate every imaginary part. }
procedure conj_c(P: PDouble; N: Int32); cdecl;
var
  I: Integer;
begin
  for I := 0 to N - 1 do
    P[2 * I + 1] := -P[2 * I + 1];
end;

procedure halve_f32(P: PSingle; N: Int32); cdecl;
var
  I: Integer;
begin
  for I := 0 to N - 1 do
    P[I] := P[I] / 2;
end;

{ ---- strings and pointers ---- }

function str_len(S: PAnsiChar): Int32; cdecl;
begin
  if S = nil then
    Result := -1
  else
    Result := System.AnsiStrings.StrLen(S);
end;

function greeting: PAnsiChar; cdecl;
begin
  Result := PAnsiChar(GreetingText);
end;

function null_string: PAnsiChar; cdecl;
begin
  Result := nil;
end;

function make_handle(V: Int32): Pointer; cdecl;
begin
  GetMem(Result, SizeOf(Int32));
  PInteger(Result)^ := V;
end;

function handle_value(H: Pointer): Int32; cdecl;
begin
  Result := PInteger(H)^;
end;

procedure free_handle(H: Pointer); cdecl;
begin
  FreeMem(H);
end;

function null_ptr: Pointer; cdecl;
begin
  Result := nil;
end;

function is_null(P: Pointer): Int32; cdecl;
begin
  Result := Ord(P = nil);
end;

{ ---- callbacks ---- }

function apply_cb(Cb: TIntCb; X: Int32): Int32; cdecl;
begin
  Result := Cb(X);
end;

function apply_twice(Cb: TIntCb; X: Int32): Int32; cdecl;
begin
  Result := Cb(Cb(X));
end;

function sum_cb(Cb: TDblCb; N: Int32): Double; cdecl;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to N - 1 do
    Result := Result + Cb(I * 0.5, I);
end;

function call_mixed(Cb: TMixedCb): Double; cdecl;
begin
  Result := Cb(7, 0.5, nil, 0.25, 1000);
end;

function call_many(Cb: TManyCb): Int64; cdecl;
begin
  Result := Cb(1, 2, 3, 4, 5, 6, 0.5);
end;

function apply_f32(Cb: TF32Cb; X: Single): Single; cdecl;
begin
  Result := Cb(X);
end;

function apply_ptr(Cb: TPtrCb; P: Pointer): Pointer; cdecl;
begin
  Result := Cb(P);
end;

procedure call_void(Cb: TVoidCb; X: Int32); cdecl;
begin
  Cb(X);
end;

procedure register_cb(Cb: TIntCb); cdecl;
begin
  Stored := Cb;
end;

function fire(X: Int32): Int32; cdecl;
begin
  Result := Stored(X);
end;

{ Calls the callback from a second thread and waits for it. }
function call_in_thread(Cb: TIntCb; X: Int32): Int32; cdecl;
var
  T: TThread;
  R: Int32;
begin
  R := -1;
  T := TThread.CreateAnonymousThread(
    procedure
    begin
      R := Cb(X);
    end);
  T.FreeOnTerminate := False;
  T.Start;
  T.WaitFor;
  T.Free;
  Result := R;
end;

exports
  add_i32, add_i64, add_u8, neg_i8, max_u32, mul_f64, mul_f32, mixed, many, char_code,
  set_i32, incr_f64, swap_i64,
  scale_f64, sum_i32, double_i32, negate_i64, conj_c, halve_f32,
  str_len, greeting, null_string, make_handle, handle_value, free_handle, null_ptr, is_null,
  apply_cb, apply_twice, sum_cb, call_mixed, call_many, apply_f32, apply_ptr, call_void,
  register_cb, fire, call_in_thread;

begin
end.
