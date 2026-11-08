unit Axon.TimeModule;

(* The core module time (reference, "The time module"): clocks, sleeping and
   timing code.

   clock() reads a monotonic high-resolution counter (TStopwatch: the
   performance counter on Windows, mach_absolute_time on macOS), so differences
   of two readings are elapsed seconds unaffected by changes to the system
   clock. elapsed and bench call the timed function from here, through
   CallAxon, so no Axon loop overhead is included in the measurement. *)

interface

implementation

uses
  System.SysUtils, System.Classes, System.Math, System.DateUtils, System.Diagnostics,
  Axon.Errors, Axon.Values, Axon.Ops, Axon.NativeModules;

const
  BenchRuns = 5;
  BenchMinRun = 0.2;      // seconds a calibrated run should last at least

function Clock: Double;
begin
  Result := TStopwatch.GetTimeStamp / TStopwatch.Frequency;
end;

function SecondsArg(const Fn: string; const V: TAxValue): Double;
begin
  if not (V.Kind in [vkInt, vkReal]) then
    RaiseFmt(TypeError, '%s needs a number of seconds, got %s', [Fn, TypeName(V)]);
  if V.Kind = vkInt then
    Result := V.I
  else
    Result := V.R;
end;

procedure NeedCallable(const Fn: string; const V: TAxValue);
begin
  if not (V.Kind in [vkFunction, vkBuiltin, vkExtern]) then
    RaiseFmt(TypeError, '%s needs a function to time, got %s', [Fn, TypeName(V)]);
  if not Assigned(CallAxon) then
    RaiseFmt(TypeError, '%s cannot call functions here', [Fn]);
end;

{ The arguments after the function. }
function RestArgs(const Args: TAxValues): TAxValues;
begin
  Result := Copy(Args, 1, Length(Args) - 1);
end;

function BClock(const Args: TAxValues): TAxValue;
begin
  Result := RealValue(Clock);
end;

function BNow(const Args: TAxValues): TAxValue;
begin
  // Seconds since 1970-01-01 UTC, with the clock's millisecond resolution.
  Result := RealValue(MilliSecondsBetween(TTimeZone.Local.ToUniversalTime(Now),
    UnixDateDelta) / 1000);
end;

function BSleep(const Args: TAxValues): TAxValue;
var
  S: Double;
begin
  S := SecondsArg('sleep', Args[0]);
  if IsNan(S) or (S < 0) then
    RaiseFmt(DomainError, 'sleep needs a non-negative number of seconds, got %s',
      [Display(Args[0])]);
  if S > 0 then
    TThread.Sleep(Round(Min(S, 1e9) * 1000));
  Result := NothingValue;
end;

function BElapsed(const Args: TAxValues): TAxValue;
var
  Rest: TAxValues;
  T0: Double;
begin
  NeedCallable('elapsed', Args[0]);
  Rest := RestArgs(Args);
  T0 := Clock;
  CallAxon(Args[0], Rest);
  Result := RealValue(Clock - T0);
end;

{ Calls f(args...) Loops times and returns the seconds taken. }
function TimeLoops(const F: TAxValue; const Rest: TAxValues; Loops: Int64): Double;
var
  K: Int64;
  T0: Double;
begin
  T0 := Clock;
  for K := 1 to Loops do
    CallAxon(F, Rest);
  Result := Clock - T0;
end;

{ Like Python's timeit: the number of loops per run doubles until a run lasts
  BenchMinRun seconds, then BenchRuns runs are timed (the calibration run
  counts as the first). Times are per call. }
function BBench(const Args: TAxValues): TAxValue;
var
  Rest: TAxValues;
  Loops: Int64;
  T, Best, Worst, Total: Double;
  K: Integer;
begin
  NeedCallable('bench', Args[0]);
  Rest := RestArgs(Args);
  Loops := 1;
  T := TimeLoops(Args[0], Rest, Loops);
  while (T < BenchMinRun) and (Loops < Int64(1) shl 40) do
  begin
    Loops := Loops * 2;
    T := TimeLoops(Args[0], Rest, Loops);
  end;
  Best := T / Loops;
  Worst := Best;
  Total := Best;
  for K := 2 to BenchRuns do
  begin
    T := TimeLoops(Args[0], Rest, Loops) / Loops;
    Best := Min(Best, T);
    Worst := Max(Worst, T);
    Total := Total + T;
  end;
  Result := RecordValue(['best', 'mean', 'worst', 'loops', 'runs'],
    [RealValue(Best), RealValue(Total / BenchRuns), RealValue(Worst),
     IntValue(Loops), IntValue(BenchRuns)]);
end;

{ Seconds as text in a fitting unit with three significant digits:
  "1.23 s", "45.6 ms", "789 µs", "12.0 ns". }
function BFormat(const Args: TAxValues): TAxValue;
var
  S, A, P, F: Double;
  U: string;
  Digits: Integer;
begin
  S := SecondsArg('format', Args[0]);
  A := Abs(S);
  if IsNan(S) or IsInfinite(S) then
    Exit(StringValue(Display(Args[0]) + ' s'));
  if A = 0 then
    Exit(StringValue('0 s'));
  // The unit is chosen after rounding to three significant digits, so that
  // 0.9996 s reads "1.00 s" rather than "1000 ms".
  // A Double base: IntPower(10, ...) would pick the Single overload.
  P := IntPower(Double(10), Floor(Log10(A)) - 2);
  // The rounded value can land a hair below a unit boundary (1000 * 1e-6 is
  // 0.000999...), so it is nudged up before the comparisons.
  A := Round(A / P) * P * (1 + 1e-12);
  if A >= 1 then begin F := 1; U := 's'; end
  else if A >= 1e-3 then begin F := 1e3; U := 'ms'; end
  else if A >= 1e-6 then begin F := 1e6; U := #$00B5's'; end
  else begin F := 1e9; U := 'ns'; end;
  A := A * F;
  // Decimals for three significant digits (none from 100 up).
  Digits := Max(0, 2 - Floor(Log10(A) + 1e-9));
  if S < 0 then
    A := -A;
  if Digits = 0 then
    Result := StringValue(FormatFloat('0', A, TFormatSettings.Invariant) + ' ' + U)
  else
    Result := StringValue(FormatFloat('0.' + StringOfChar('0', Digits), A,
      TFormatSettings.Invariant) + ' ' + U);
end;

procedure DefineTime(const Define: TProc<string, TAxValue>);
begin
  Define('clock', BuiltinValue('clock', BClock, 0, 0));
  Define('now', BuiltinValue('now', BNow, 0, 0));
  Define('sleep', BuiltinValue('sleep', BSleep, 1, 1));
  Define('elapsed', BuiltinValue('elapsed', BElapsed, 1, -1));
  Define('bench', BuiltinValue('bench', BBench, 1, -1));
  Define('format', BuiltinValue('format', BFormat, 1, 1));
end;

initialization
  RegisterNativeModule('time', DefineTime, ['Clocks, sleeping and timing code.']);

end.
