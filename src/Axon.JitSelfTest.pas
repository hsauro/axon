unit Axon.JitSelfTest;

(* axon --jit-selftest: the J0 check that MIR works on this machine
   (doc/Axon-JIT-Plan.md). It builds a few functions with the MIR API, links
   them, calls them through function pointers, and checks the results:

   - add_checked(a, b, out): int addition with MIR's overflow branch; on
     overflow it calls the Delphi helper rt_error(kind, site) and returns
     status 1, the error protocol of decision D4
   - sum_to(n): a loop summing 1..n in reals
   - fib(n): recursion through MIR calls

   It prints one line per check and returns ExitOk only if all pass. *)

interface

function RunJitSelfTest: Integer;

implementation

uses
  System.SysUtils, System.Diagnostics,
  Axon.Errors, Axon.Native.Mir;

type
  TAddChecked = function(A, B: Int64; Res: PInt64): Int64; cdecl;
  TSumTo = function(N: Int64): Double; cdecl;
  TFib = function(N: Int64): Int64; cdecl;

var
  ErrorKind, ErrorSite: Int64;
  ErrorCalls: Integer;

{ Called from generated code: records a pending error. }
procedure RtError(Kind, Site: Int64); cdecl;
begin
  ErrorKind := Kind;
  ErrorSite := Site;
  Inc(ErrorCalls);
end;

{ MIR found invalid IR: a bug in Axon. Must not return. }
procedure MirFailed(ErrorType: Int32; Message: PAnsiChar); cdecl;
begin
  Writeln(ErrOutput, 'InternalError: MIR: ', string(AnsiString(Message)));
  Flush(Output);
  Halt(ExitInternal);
end;

function Vars(const Types: array of Int32; const Names: array of PAnsiChar): TArray<TMirVar>;
var
  K: Integer;
begin
  SetLength(Result, Length(Types));
  for K := 0 to High(Types) do
  begin
    Result[K].Typ := Types[K];
    Result[K].Name := Names[K];
    Result[K].Size := 0;
  end;
end;

function RunJitSelfTest: Integer;
var
  Ctx: TMirContext;
  Module: TMirModule;
  ErrProto, ErrImport, FibProto, AddFn, SumFn, FibFn: TMirItem;
  ResI64, ResD: Int32;
  V: TArray<TMirVar>;
  RA, RB, ROut, R, N, S, I, T, A1, A2, F1, F2: TMirReg;
  LOver, LLoop, LDone, LSmall: TMirInsn;
  AddChecked: TAddChecked;
  SumTo: TSumTo;
  Fib: TFib;
  Watch: TStopwatch;
  CompileMs: Double;
  Failures: Integer;
  Res, Status: Int64;
  Sum: Double;
  FibN: Int64;

  procedure Check(const What: string; OK: Boolean);
  begin
    if OK then
      Writeln('  ok    ', What)
    else
    begin
      Writeln('  FAIL  ', What);
      Inc(Failures);
    end;
  end;

  function Code(const Name: AnsiString): Int32;
  begin
    Result := MirCode(Ctx, Name);
  end;

begin
  if not MirAvailable then
  begin
    Writeln(ErrOutput, 'axon: the JIT is unavailable: ', MirError);
    Exit(ExitUsage);
  end;
  Failures := 0;
  axmir_set_error_handler(MirFailed);
  ResI64 := MIR_T_I64;
  ResD := MIR_T_D;

  Watch := TStopwatch.StartNew;
  Ctx := axmir_init(2);
  Module := MIR_new_module(Ctx, 'selftest');

  // Prototypes and imports come before the functions.
  V := Vars([MIR_T_I64, MIR_T_I64], ['kind', 'site']);
  ErrProto := MIR_new_proto_arr(Ctx, 'rt_error_p', 0, nil, 2, @V[0]);
  ErrImport := MIR_new_import(Ctx, 'rt_error');
  V := Vars([MIR_T_I64], ['n']);
  FibProto := MIR_new_proto_arr(Ctx, 'fib_p', 1, @ResI64, 1, @V[0]);

  // add_checked(a, b, out): *out = a + b and 0, or rt_error(1, 7) and 1.
  V := Vars([MIR_T_I64, MIR_T_I64, MIR_T_P], ['a', 'b', 'out']);
  AddFn := MIR_new_func_arr(Ctx, 'add_checked', 1, @ResI64, 3, @V[0]);
  RA := axmir_reg(Ctx, AddFn, 'a');
  RB := axmir_reg(Ctx, AddFn, 'b');
  ROut := axmir_reg(Ctx, AddFn, 'out');
  R := axmir_new_reg(Ctx, AddFn, MIR_T_I64, 'r');
  LOver := MIR_new_label(Ctx);
  Emit(Ctx, AddFn, Code('addo'), [RegOp(R), RegOp(RA), RegOp(RB)]);
  Emit(Ctx, AddFn, Code('bo'), [LabelOp(LOver)]);
  Emit(Ctx, AddFn, Code('mov'), [MemOp(MIR_T_I64, 0, ROut), RegOp(R)]);
  Emit(Ctx, AddFn, Code('ret'), [IntOp(0)]);
  MIR_append_insn(Ctx, AddFn, LOver);
  Emit(Ctx, AddFn, Code('call'), [RefOp(ErrProto), RefOp(ErrImport), IntOp(1), IntOp(7)]);
  Emit(Ctx, AddFn, Code('ret'), [IntOp(1)]);
  MIR_finish_func(Ctx);

  // sum_to(n): s = 0.0; for i = 1..n: s += i.
  V := Vars([MIR_T_I64], ['n']);
  SumFn := MIR_new_func_arr(Ctx, 'sum_to', 1, @ResD, 1, @V[0]);
  N := axmir_reg(Ctx, SumFn, 'n');
  S := axmir_new_reg(Ctx, SumFn, MIR_T_D, 's');
  I := axmir_new_reg(Ctx, SumFn, MIR_T_I64, 'i');
  T := axmir_new_reg(Ctx, SumFn, MIR_T_D, 't');
  LLoop := MIR_new_label(Ctx);
  LDone := MIR_new_label(Ctx);
  Emit(Ctx, SumFn, Code('dmov'), [RegOp(S), DoubleOp(0.0)]);
  Emit(Ctx, SumFn, Code('mov'), [RegOp(I), IntOp(1)]);
  MIR_append_insn(Ctx, SumFn, LLoop);
  Emit(Ctx, SumFn, Code('bgt'), [LabelOp(LDone), RegOp(I), RegOp(N)]);
  Emit(Ctx, SumFn, Code('i2d'), [RegOp(T), RegOp(I)]);
  Emit(Ctx, SumFn, Code('dadd'), [RegOp(S), RegOp(S), RegOp(T)]);
  Emit(Ctx, SumFn, Code('add'), [RegOp(I), RegOp(I), IntOp(1)]);
  Emit(Ctx, SumFn, Code('jmp'), [LabelOp(LLoop)]);
  MIR_append_insn(Ctx, SumFn, LDone);
  Emit(Ctx, SumFn, Code('ret'), [RegOp(S)]);
  MIR_finish_func(Ctx);

  // fib(n): n < 2 ? n : fib(n - 1) + fib(n - 2).
  V := Vars([MIR_T_I64], ['n']);
  FibFn := MIR_new_func_arr(Ctx, 'fib', 1, @ResI64, 1, @V[0]);
  N := axmir_reg(Ctx, FibFn, 'n');
  A1 := axmir_new_reg(Ctx, FibFn, MIR_T_I64, 'a1');
  A2 := axmir_new_reg(Ctx, FibFn, MIR_T_I64, 'a2');
  F1 := axmir_new_reg(Ctx, FibFn, MIR_T_I64, 'f1');
  F2 := axmir_new_reg(Ctx, FibFn, MIR_T_I64, 'f2');
  LSmall := MIR_new_label(Ctx);
  Emit(Ctx, FibFn, Code('blt'), [LabelOp(LSmall), RegOp(N), IntOp(2)]);
  Emit(Ctx, FibFn, Code('sub'), [RegOp(A1), RegOp(N), IntOp(1)]);
  Emit(Ctx, FibFn, Code('call'), [RefOp(FibProto), RefOp(FibFn), RegOp(F1), RegOp(A1)]);
  Emit(Ctx, FibFn, Code('sub'), [RegOp(A2), RegOp(N), IntOp(2)]);
  Emit(Ctx, FibFn, Code('call'), [RefOp(FibProto), RefOp(FibFn), RegOp(F2), RegOp(A2)]);
  Emit(Ctx, FibFn, Code('add'), [RegOp(F1), RegOp(F1), RegOp(F2)]);
  Emit(Ctx, FibFn, Code('ret'), [RegOp(F1)]);
  MIR_append_insn(Ctx, FibFn, LSmall);
  Emit(Ctx, FibFn, Code('ret'), [RegOp(N)]);
  MIR_finish_func(Ctx);

  MIR_finish_module(Ctx);
  MIR_load_module(Ctx, Module);
  MIR_load_external(Ctx, 'rt_error', @RtError);
  axmir_link(Ctx);
  @AddChecked := axmir_func_addr(AddFn);
  @SumTo := axmir_func_addr(SumFn);
  @Fib := axmir_func_addr(FibFn);
  CompileMs := Watch.Elapsed.TotalMilliseconds;

  Writeln('MIR self-test (', LibraryName, ')');
  Check('functions built, linked and generated', Assigned(AddChecked) and Assigned(SumTo) and Assigned(Fib));

  Res := 0;
  Status := AddChecked(2, 3, @Res);
  Check('add_checked(2, 3) = 5, status 0', (Status = 0) and (Res = 5) and (ErrorCalls = 0));
  Res := -1;
  Status := AddChecked(High(Int64), 1, @Res);
  Check('add_checked(max, 1) overflows: status 1, rt_error(1, 7), result untouched',
    (Status = 1) and (ErrorCalls = 1) and (ErrorKind = 1) and (ErrorSite = 7) and (Res = -1));
  Status := AddChecked(Low(Int64), -1, @Res);
  Check('add_checked(min, -1) overflows', (Status = 1) and (ErrorCalls = 2));

  Sum := SumTo(100);
  Check('sum_to(100) = 5050.0', Sum = 5050.0);
  Check('sum_to(0) = 0.0', SumTo(0) = 0.0);

  Check('fib(1) = 1, fib(10) = 55', (Fib(1) = 1) and (Fib(10) = 55));
  Watch := TStopwatch.StartNew;
  FibN := Fib(25);
  Check('fib(25) = 75025', FibN = 75025);
  Writeln(Format('  build and generate: %.2f ms; fib(25): %.3f ms',
    [CompileMs, Watch.Elapsed.TotalMilliseconds], TFormatSettings.Invariant));

  axmir_finish(Ctx);
  if Failures = 0 then
  begin
    Writeln('all passed');
    Result := ExitOk;
  end
  else
  begin
    Writeln(Failures, ' failed');
    Result := ExitUncaughtError;   // 1, as for failing tests
  end;
end;

end.
