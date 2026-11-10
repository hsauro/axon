unit Axon.Jit.Mir;

(* JIR to MIR to machine code (doc/Axon-JIT-Plan.md, J2 and J3).

   Each compiled function becomes a MIR module with two functions:

     f<id>(res: p, params...) -> i64   the typed body; 0 = ok, 1 = error
     e<id>(args: p, res: p) -> i64     the entry thunk the interpreter calls

   f<id> is exported, so other modules call it directly. Registers map one
   to one: bool and int to i64 (bools are 0 or 1), real to double. Results
   are stored in 8-byte slots at res. All modules live in one MIR context for
   the life of the process; a group of modules is generated, then linked
   together (LinkModules).

   Errors (decision D4): checked int arithmetic uses MIR's overflow
   instructions (addo, subo, mulo with bo); an overflow branches to an error
   block at the end of the function that calls rt_error(fid, site, code) and
   returns 1. Helpers that can fail record the error themselves.

   Calls (J3):
   - Compiled callee: a guard checks that the variable the name resolved to
     still holds the same function (else the call goes through rt_call); the
     interpreter's call depth is raised and checked as Invoke does, the body
     called directly, the depth lowered, and a failure passed on after
     rt_frame records this caller's call site.
   - Elementary built-in with a real argument: the interpreter's own routine
     (Axon.Builtins), called directly.
   - Anything else (other built-ins, print, error, functions that run
     interpreted): rt_call, with the arguments in 8-byte slots.

   Arrays (J4): each array register is a TAxValue slot in a frame the
   function allocates (alloca, zeroed) and releases at its single exit
   (rt_leave), on every path, errors included. Array arguments and results
   are passed as slot addresses; a body takes its own reference to each
   array parameter, as Invoke's parameter cell does, so reference counts,
   and with them every copy-on-write decision and the __copies() count, are
   the interpreter's. Elements are read and written inline from the
   TArrayObj's fields (offsets measured at start-up); a write first checks
   the reference count and copies through rt_make_unique when the array is
   shared. Operators on arrays go to Axon.Ops through rt_call. *)

interface

uses
  Axon.Jit.Ir, Axon.Jit, Axon.Native.Mir;

{ Generates the module of J (not linked yet) and returns its entry item.
  Call descriptors are added to Code.CallSites. }
function GenerateModule(J: TJFunction; Code: TJitCode): TMirItem;

{ Links the modules generated since the last call. }
procedure LinkModules;

function MirFunctionAddress(Item: TMirItem): Pointer;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  Axon.Errors, Axon.Values, Axon.Builtins;

var
  Ctx: TMirContext;
  // Layout of values, arrays and records, measured in ComputeLayout.
  LSlotSize, LObjOff, LIntfDelta, LRowsOff, LColsOff, LROff, LIOff, LRcOff: NativeInt;
  LRecDelta, LValuesOff, LPayOff: NativeInt;
  LListDelta, LItemsOff, LDynLenOff: NativeInt;

type
  TRefCountAccess = class(TInterfacedObject);   // reaches the protected FRefCount

procedure ComputeLayout;
var
  A: TArrayObj;
  R: TRecordObj;
  L: TListObj;
  I: IInterface;
  V: TAxValue;
begin
  A := TArrayObj.Create(etReal, 1, 1, True);
  I := A;
  LIntfDelta := NativeInt(Pointer(A)) - NativeInt(Pointer(I));
  LRowsOff := NativeInt(@A.Rows) - NativeInt(Pointer(A));
  LColsOff := NativeInt(@A.Cols) - NativeInt(Pointer(A));
  LROff := NativeInt(@A.R) - NativeInt(Pointer(A));
  LIOff := NativeInt(@A.I) - NativeInt(Pointer(A));
  LRcOff := NativeInt(@TRefCountAccess(A).FRefCount) - NativeInt(Pointer(A));
  LObjOff := NativeInt(@V.Obj) - NativeInt(@V);
  LSlotSize := SizeOf(TAxValue);
  I := nil;
  // Records (J9): the object behind the interface, its field values, and
  // where a value keeps a bool, int or real (one variant part).
  R := TRecordObj.Create;
  I := R;
  LRecDelta := NativeInt(Pointer(R)) - NativeInt(Pointer(I));
  LValuesOff := NativeInt(@R.Values) - NativeInt(Pointer(R));
  LPayOff := NativeInt(@V.I) - NativeInt(@V);
  Assert((NativeInt(@V.R) - NativeInt(@V) = LPayOff) and (NativeInt(@V.B) - NativeInt(@V) = LPayOff));
  I := nil;
  // Lists (J10): the object, its items, and the length a dynamic array keeps
  // before its first element.
  L := TListObj.Create;
  I := L;
  LListDelta := NativeInt(Pointer(L)) - NativeInt(Pointer(I));
  LItemsOff := NativeInt(@L.Items) - NativeInt(Pointer(L));
  SetLength(L.Items, 3);
  LDynLenOff := -SizeOf(NativeInt);
  Assert(PNativeInt(NativeInt(Pointer(L.Items)) + LDynLenOff)^ = 3);
  I := nil;
end;

{ MIR found invalid IR: a bug in the JIT. MIR expects this not to return. }
procedure MirFailed(ErrorType: Int32; Message: PAnsiChar); cdecl;
begin
  Writeln(ErrOutput, 'InternalError: MIR: ', string(AnsiString(Message)));
  Flush(Output);
  Halt(ExitInternal);
end;

const
  ElementaryNames: array[0..18] of string = ('sqrt', 'exp', 'log', 'sin', 'cos', 'tan',
    'asin', 'acos', 'atan', 'sinh', 'cosh', 'tanh', 'asinh', 'acosh', 'atanh', 'log10', 'log2',
    'deg2rad', 'rad2deg');

procedure EnsureContext;
var
  H: TJitHelpers;
  N: string;
begin
  if Ctx <> nil then
    Exit;
  axmir_set_error_handler(MirFailed);
  Ctx := axmir_init(2);
  ComputeLayout;
  H := JitHelpers;
  MIR_load_external(Ctx, 'rt_error', H.Error);
  MIR_load_external(Ctx, 'rt_count_int', H.CountInt);
  MIR_load_external(Ctx, 'rt_count_real', H.CountReal);
  MIR_load_external(Ctx, 'rt_pow_real', H.PowReal);
  MIR_load_external(Ctx, 'rt_call', H.Call);
  MIR_load_external(Ctx, 'rt_frame', H.Frame);
  MIR_load_external(Ctx, 'rt_recursion', H.Recursion);
  MIR_load_external(Ctx, 'rt_assign', H.Assign);
  MIR_load_external(Ctx, 'rt_move', H.Move);
  MIR_load_external(Ctx, 'rt_clear', H.Clear);
  MIR_load_external(Ctx, 'rt_make_unique', H.MakeUnique);
  MIR_load_external(Ctx, 'rt_leave', H.Leave);
  MIR_load_external(Ctx, 'rt_index_error', H.IndexError);
  MIR_load_external(Ctx, 'rt_new_array', H.NewArray);
  MIR_load_external(Ctx, 'rt_new_record', H.NewRecord);
  MIR_load_external(Ctx, 'rt_record_unique', H.RecordUnique);
  MIR_load_external(Ctx, 'rt_new_list', H.NewList);
  MIR_load_external(Ctx, 'rt_list_append', H.ListAppend);
  MIR_load_external(Ctx, 'rt_list_unique', H.ListUnique);
  for N in ElementaryNames do
    MIR_load_external(Ctx, PAnsiChar(AnsiString('rt_' + N)), ElementaryRealFunction(N));
  MIR_load_external(Ctx, 'rt_atan2', ElementaryRealFunction('atan2'));
end;

procedure LinkModules;
begin
  axmir_link(Ctx);
end;

function MirFunctionAddress(Item: TMirItem): Pointer;
begin
  Result := axmir_func_addr(Item);
end;

type
  TErrorBlock = record
    Lbl: TMirInsn;
    Site, Code: Integer;
  end;

  { Per call instruction: its prototype and callee item. }
  TCallInfo = record
    Proto, Callee: TMirItem;
  end;

  TGen = class
  private
    J: TJFunction;
    Code: TJitCode;
    Fid: Integer;
    Body: TMirItem;
    Regs: TArray<TMirReg>;
    Labels: TArray<TMirInsn>;
    ErrorBlocks: TList<TErrorBlock>;
    Deferred: TList<TProc>;           // out-of-line blocks, emitted after the body
    Calls: TDictionary<TJInsn, TCallInfo>;
    FailLabel: TMirInsn;
    ResPtr: TMirReg;
    ArgBuf, ResBuf, DepthAddr: TMirReg;
    TempCount, ProtoCount: Integer;
    ErrProto, ErrImport, CountIntProto, CountIntImport,
    CountRealProto, CountRealImport, PowProto, PowImport,
    CallProto, CallImport, FrameProto, FrameImport, RecProto, RecImport, D1Proto, D2Proto: TMirItem;
    PtrProto, PtrPtrProto, AssignImport, MoveImport, ClearImport, UniqueImport,
    LeaveProto, LeaveImport, IndexErrProto, IndexErrImport, NewArrayProto, NewArrayImport: TMirItem;
    NewRecordProto, NewRecordImport, RecUniqueImport: TMirItem;
    NewListProto, NewListImport, AppendProto, AppendImport, ListUniqueImport: TMirItem;
    // Arrays: the frame of value slots, and the single exit that releases it.
    SlotOf: TArray<Integer>;          // per JIR register: its slot, or -1
    NSlots, JunkSlot: Integer;
    FrameReg, StatusReg: TMirReg;
    ExitLabel: TMirInsn;
    function SlotAddr(Slot: Integer): TMirReg;
    function ObjOf(R: Integer): TMirReg;
    procedure RetFail;
    procedure GenArrayMov(I: TJInsn);
    procedure GenLen(I: TJInsn);
    procedure GenBound(I: TJInsn);
    procedure GenElem(I: TJInsn; IsStore: Boolean);
    procedure GenOp(I: TJInsn);
    procedure GenArray(I: TJInsn);
    // records (J9)
    function ObjAt(Addr: TMirReg; Delta: NativeInt): TMirReg;
    procedure UniqueAt(Addr: TMirReg; Delta: NativeInt; Import: TMirItem);
    function PathAddr(I: TJInsn; Unique: Boolean): TMirReg;
    function ValueOf(I: TJInsn; Unique: Boolean): TMirReg;
    procedure GenField(I: TJInsn);
    procedure GenSetField(I: TJInsn);
    procedure GenRecord(I: TJInsn);
    // lists (J10)
    function BaseType(I: TJInsn): TJType;
    function OperandType(const O: TJOperand): TJType;
    procedure PutArg(K: Integer; const O: TJOperand);
    procedure GenListLen(I: TJInsn);
    procedure GenListElem(I: TJInsn; IsStore: Boolean);
    procedure GenList(I: TJInsn);
    procedure GenAppend(I: TJInsn);
    procedure SetupResultDests(I: TJInsn; const ResultTypes: TArray<TJType>);
    procedure ClearJunk(I: TJInsn; const ResultTypes: TArray<TJType>);
    function C(const Name: AnsiString): Int32;
    procedure E(const Name: AnsiString; const Ops: array of TAxMirOp);
    function Opnd(const O: TJOperand): TAxMirOp;
    function Reg(R: Integer): TAxMirOp;
    function Scratch(Typ: Int32): TMirReg;
    function ErrorLabel(Site, ErrCode: Integer): TMirInsn;
    procedure DeclareCalls;
    procedure GenInsn(I: TJInsn);
    procedure GenPowInt(I: TJInsn);
    procedure GenCall(I: TJInsn);
    procedure GenCallThroughInterp(I: TJInsn; CS: TJitCallSite; Join: TMirInsn);
    procedure LoadResults(I: TJInsn);
    function NewCallSite(I: TJInsn): TJitCallSite;
  public
    constructor Create(AJ: TJFunction; ACode: TJitCode);
    destructor Destroy; override;
    function Run: TMirItem;
  end;

function MirType(T: TJType): Int32;
begin
  if T = jtReal then
    Result := MIR_T_D
  else
    Result := MIR_T_I64;
end;

function Vars(const Types: array of Int32; const Names: array of AnsiString): TArray<TMirVar>;
var
  K: Integer;
begin
  SetLength(Result, Length(Types));
  for K := 0 to High(Types) do
  begin
    Result[K].Typ := Types[K];
    Result[K].Name := PAnsiChar(Names[K]);
    Result[K].Size := 0;
  end;
end;

{ The bits of a value's object pointer, which the guard compares. }
function ObjBits(const V: TAxValue): NativeInt;
begin
  Result := NativeInt(PPointer(@V.Obj)^);
end;

function ObjOffset: NativeInt;
var
  V: TAxValue;
begin
  Result := NativeInt(@V.Obj) - NativeInt(@V);
end;

constructor TGen.Create(AJ: TJFunction; ACode: TJitCode);
begin
  inherited Create;
  J := AJ;
  Code := ACode;
  Fid := ACode.Id;
  ErrorBlocks := TList<TErrorBlock>.Create;
  Deferred := TList<TProc>.Create;
  Calls := TDictionary<TJInsn, TCallInfo>.Create;
end;

destructor TGen.Destroy;
begin
  Calls.Free;
  Deferred.Free;
  ErrorBlocks.Free;
  inherited;
end;

function TGen.C(const Name: AnsiString): Int32;
begin
  Result := MirCode(Ctx, Name);
end;

procedure TGen.E(const Name: AnsiString; const Ops: array of TAxMirOp);
begin
  Emit(Ctx, Body, C(Name), Ops);
end;

function TGen.Reg(R: Integer): TAxMirOp;
begin
  Result := RegOp(Regs[R]);
end;

function TGen.Opnd(const O: TJOperand): TAxMirOp;
begin
  case O.Kind of
    jkReg:
      if SlotOf[O.Reg] >= 0 then
        Result := RegOp(SlotAddr(SlotOf[O.Reg]))     // an array: its slot's address
      else
        Result := RegOp(Regs[O.Reg]);
    jkInt:  Result := IntOp(O.I);
    jkReal: Result := DoubleOp(O.R);
    jkBool: Result := IntOp(Ord(O.B));
  else
    raise EMirError.Create('JIT: a label or string used as a value');
  end;
end;

function TGen.Scratch(Typ: Int32): TMirReg;
var
  Name: AnsiString;
begin
  Inc(TempCount);
  Name := AnsiString('t' + IntToStr(TempCount));
  Result := axmir_new_reg(Ctx, Body, Typ, PAnsiChar(Name));
end;

{ The block that reports error ErrCode at Site; one per pair. }
function TGen.ErrorLabel(Site, ErrCode: Integer): TMirInsn;
var
  B: TErrorBlock;
begin
  for B in ErrorBlocks do
    if (B.Site = Site) and (B.Code = ErrCode) then
      Exit(B.Lbl);
  B.Lbl := MIR_new_label(Ctx);
  B.Site := Site;
  B.Code := ErrCode;
  ErrorBlocks.Add(B);
  Result := B.Lbl;
end;

const
  // rt_error codes (Axon.Jit.RtError)
  ErrAdd = 1; ErrSub = 2; ErrMul = 3; ErrNeg = 4; ErrPow = 5;

{ Prototypes and imports for the calls, which MIR wants before the function. }
procedure TGen.DeclareCalls;
var
  Insn: TJInsn;
  Info: TCallInfo;
  V: TArray<TMirVar>;
  Types: TArray<Int32>;
  Names: TArray<AnsiString>;
  K: Integer;
  ResI64: Int32;
  ProtoName, ImportName: AnsiString;
begin
  ResI64 := MIR_T_I64;
  for Insn in J.Insns do
  begin
    if Insn.Op <> joCall then
      Continue;
    Info.Proto := nil;
    Info.Callee := nil;
    if Insn.Target.Kind = ckCompiled then
    begin
      // (res, params) -> i64, as the callee's body.
      SetLength(Types, Length(Insn.Target.ParamTypes) + 1);
      SetLength(Names, Length(Types));
      Types[0] := MIR_T_P;
      Names[0] := 'res';
      for K := 0 to High(Insn.Target.ParamTypes) do
      begin
        Types[K + 1] := MirType(Insn.Target.ParamTypes[K]);
        Names[K + 1] := AnsiString('a' + IntToStr(K));
      end;
      V := Vars(Types, Names);
      Inc(ProtoCount);
      ProtoName := AnsiString('cp' + IntToStr(ProtoCount));
      Info.Proto := MIR_new_proto_arr(Ctx, PAnsiChar(ProtoName), 1, @ResI64, Length(V), @V[0]);
      if Insn.Target.CalleeId <> Fid then
      begin
        ImportName := AnsiString('f' + IntToStr(Insn.Target.CalleeId));
        Info.Callee := MIR_new_import(Ctx, PAnsiChar(ImportName));
      end;
    end
    else if (Insn.Target.Kind = ckBuiltin) and Insn.Target.Direct then
    begin
      if Length(Insn.Ops) = 2 then
        Info.Proto := D2Proto
      else
        Info.Proto := D1Proto;
      ImportName := AnsiString('rt_' + Insn.Target.Name);
      Info.Callee := MIR_new_import(Ctx, PAnsiChar(ImportName));
    end;
    Calls.AddOrSetValue(Insn, Info);
  end;
end;

{ ---- arrays ---- }

function TGen.SlotAddr(Slot: Integer): TMirReg;
begin
  Result := Scratch(MIR_T_I64);
  E('add', [RegOp(Result), RegOp(FrameReg), IntOp(Slot * LSlotSize)]);
end;

{ The TArrayObj held by an array register's slot. }
function TGen.ObjOf(R: Integer): TMirReg;
begin
  Result := Scratch(MIR_T_I64);
  E('mov', [RegOp(Result), MemOp(MIR_T_I64, SlotOf[R] * LSlotSize + LObjOff, FrameReg)]);
  E('add', [RegOp(Result), RegOp(Result), IntOp(LIntfDelta)]);
end;

{ Returns failure, through the exit that releases the frame. }
procedure TGen.RetFail;
begin
  if NSlots > 0 then
  begin
    E('mov', [RegOp(StatusReg), IntOp(1)]);
    E('jmp', [LabelOp(ExitLabel)]);
  end
  else
    E('ret', [IntOp(1)]);
end;

{ An array register := another: a temporary's reference moves, a
  variable's is shared. }
procedure TGen.GenArrayMov(I: TJInsn);
var
  Src: Integer;
begin
  Src := I.Ops[0].Reg;
  if J.Regs[Src].Name = '' then
    E('call', [RefOp(PtrPtrProto), RefOp(MoveImport), RegOp(SlotAddr(SlotOf[I.Dst])),
      RegOp(SlotAddr(SlotOf[Src]))])
  else
    E('call', [RefOp(PtrPtrProto), RefOp(AssignImport), RegOp(SlotAddr(SlotOf[I.Dst])),
      RegOp(SlotAddr(SlotOf[Src]))]);
end;

procedure TGen.GenLen(I: TJInsn);
var
  Obj, T: TMirReg;
begin
  if IsListType(BaseType(I)) then
  begin
    GenListLen(I);
    Exit;
  end;
  Obj := ObjAt(ValueOf(I, False), LIntfDelta);
  case I.Ops[1].I of
    1: E('mov', [Reg(I.Dst), MemOp(MIR_T_I32, LRowsOff, Obj)]);
    2: E('mov', [Reg(I.Dst), MemOp(MIR_T_I32, LColsOff, Obj)]);
  else
    begin
      T := Scratch(MIR_T_I64);
      E('mov', [Reg(I.Dst), MemOp(MIR_T_I32, LRowsOff, Obj)]);
      E('mov', [RegOp(T), MemOp(MIR_T_I32, LColsOff, Obj)]);
      E('mul', [Reg(I.Dst), Reg(I.Dst), RegOp(T)]);
    end;
  end;
end;

{ IndexError unless 1 <= index <= len, reported at the index. }
procedure TGen.GenBound(I: TJInsn);
var
  Idx, Len: TMirReg;
  LErr: TMirInsn;
  Site: Integer;
begin
  Idx := Scratch(MIR_T_I64);
  Len := Scratch(MIR_T_I64);
  E('mov', [RegOp(Idx), Opnd(I.Ops[0])]);
  E('mov', [RegOp(Len), Opnd(I.Ops[1])]);
  LErr := MIR_new_label(Ctx);
  E('blt', [LabelOp(LErr), RegOp(Idx), IntOp(1)]);
  E('bgt', [LabelOp(LErr), RegOp(Idx), RegOp(Len)]);
  Site := I.Site;
  Deferred.Add(
    procedure
    begin
      MIR_append_insn(Ctx, Body, LErr);
      E('call', [RefOp(IndexErrProto), RefOp(IndexErrImport), IntOp(Fid), IntOp(Site),
        RegOp(Idx), RegOp(Len)]);
      RetFail;
    end);
end;

{ v[i], A[k] or A[i, j], read or written. The indices are already checked.
  A write first makes the array unique (copy-on-write). }
procedure TGen.GenElem(I: TJInsn; IsStore: Boolean);
var
  Arr, NIdx: Integer;
  Obj, Data, Pos, Rows, Addr: TMirReg;
  Typ: Int32;
  Off: NativeInt;
  Elem: TAxMirOp;
begin
  if IsListType(BaseType(I)) then
  begin
    GenListElem(I, IsStore);
    Exit;
  end;
  Arr := I.Ops[0].Reg;
  if IsStore then
    NIdx := Length(I.Ops) - 2
  else
    NIdx := Length(I.Ops) - 1;
  // The array's value: its register's slot, or the field at the path (each
  // record on the way made unique first for a store).
  Addr := ValueOf(I, IsStore);
  if IsStore then
    // Copy-on-write, as AssignArraySlot: only when another value shares it.
    UniqueAt(Addr, LIntfDelta, UniqueImport);
  Obj := ObjAt(Addr, LIntfDelta);
  if I.Typ = jtReal then
  begin
    Typ := MIR_T_D;
    Off := LROff;
  end
  else
  begin
    Typ := MIR_T_I64;
    Off := LIOff;
  end;
  Data := Scratch(MIR_T_I64);
  E('mov', [RegOp(Data), MemOp(MIR_T_I64, Off, Obj)]);
  Pos := Scratch(MIR_T_I64);
  if NIdx = 1 then
    E('mov', [RegOp(Pos), Opnd(I.Ops[1])])
  else
  begin
    // (j - 1)*rows + i, column-major
    Rows := Scratch(MIR_T_I64);
    E('mov', [RegOp(Rows), MemOp(MIR_T_I32, LRowsOff, Obj)]);
    E('sub', [RegOp(Pos), Opnd(I.Ops[2]), IntOp(1)]);
    E('mul', [RegOp(Pos), RegOp(Pos), RegOp(Rows)]);
    E('add', [RegOp(Pos), RegOp(Pos), Opnd(I.Ops[1])]);
  end;
  Elem := MemOp(Typ, -8, Data, Pos, 8);         // 1-based position
  if IsStore then
  begin
    if Typ = MIR_T_D then
      E('dmov', [Elem, Opnd(I.Ops[High(I.Ops)])])
    else
      E('mov', [Elem, Opnd(I.Ops[High(I.Ops)])]);
  end
  else if Typ = MIR_T_D then
    E('dmov', [Reg(I.Dst), Elem])
  else
    E('mov', [Reg(I.Dst), Elem]);
end;

{ ---- records (J9) ---- }

{ The object a value at Addr holds (Delta: from its interface to it). }
function TGen.ObjAt(Addr: TMirReg; Delta: NativeInt): TMirReg;
begin
  Result := Scratch(MIR_T_I64);
  E('mov', [RegOp(Result), MemOp(MIR_T_I64, LObjOff, Addr)]);
  E('add', [RegOp(Result), RegOp(Result), IntOp(Delta)]);
end;

{ Copy-on-write of the value at Addr: Import (rt_make_unique for an array,
  rt_record_unique for a record) when another value shares its object. }
procedure TGen.UniqueAt(Addr: TMirReg; Delta: NativeInt; Import: TMirItem);
var
  Obj, Rc: TMirReg;
  LShared, LReady: TMirInsn;
begin
  LShared := MIR_new_label(Ctx);
  LReady := MIR_new_label(Ctx);
  Obj := ObjAt(Addr, Delta);
  Rc := Scratch(MIR_T_I64);
  E('mov', [RegOp(Rc), MemOp(MIR_T_I32, LRcOff, Obj)]);
  E('bgt', [LabelOp(LShared), RegOp(Rc), IntOp(1)]);
  MIR_append_insn(Ctx, Body, LReady);
  Deferred.Add(
    procedure
    begin
      MIR_append_insn(Ctx, Body, LShared);
      E('call', [RefOp(PtrProto), RefOp(Import), RegOp(Addr)]);
      E('jmp', [LabelOp(LReady)]);
    end);
end;

{ The address of the value at the end of I's path, from the slot of its
  first operand; with Unique, each record on the path is made unique before
  it is entered, as SetIn does. }
function TGen.PathAddr(I: TJInsn; Unique: Boolean): TMirReg;
var
  P, Obj, Vals, Next: TMirReg;
  K: Integer;
begin
  P := SlotAddr(SlotOf[I.Ops[0].Reg]);
  for K := 0 to High(I.Path) do
  begin
    if Unique then
      UniqueAt(P, LRecDelta, RecUniqueImport);
    Obj := ObjAt(P, LRecDelta);
    Vals := Scratch(MIR_T_I64);
    E('mov', [RegOp(Vals), MemOp(MIR_T_I64, LValuesOff, Obj)]);
    Next := Scratch(MIR_T_I64);
    E('add', [RegOp(Next), RegOp(Vals), IntOp(I.Path[K] * LSlotSize)]);
    P := Next;
  end;
  Result := P;
end;

{ The array value an element or length instruction works on. }
function TGen.ValueOf(I: TJInsn; Unique: Boolean): TMirReg;
begin
  if Length(I.Path) > 0 then
    Result := PathAddr(I, Unique)
  else
    Result := SlotAddr(SlotOf[I.Ops[0].Reg]);
end;

{ Dst := the field at the path: an array or record shared into Dst's slot, a
  number read from the value's variant part. }
procedure TGen.GenField(I: TJInsn);
var
  P: TMirReg;
begin
  P := PathAddr(I, False);
  if IsBoxedType(I.Typ) then
    E('call', [RefOp(PtrPtrProto), RefOp(AssignImport), RegOp(SlotAddr(SlotOf[I.Dst])), RegOp(P)])
  else if I.Typ = jtReal then
    E('dmov', [Reg(I.Dst), MemOp(MIR_T_D, LPayOff, P)])
  else if I.Typ = jtInt then
    E('mov', [Reg(I.Dst), MemOp(MIR_T_I64, LPayOff, P)])
  else
    E('mov', [Reg(I.Dst), MemOp(MIR_T_U8, LPayOff, P)]);
end;

{ The field at the path := the value, after making each record on the path
  unique. The field keeps its kind: only its value changes. }
procedure TGen.GenSetField(I: TJInsn);
var
  P: TMirReg;
begin
  P := PathAddr(I, True);
  if IsBoxedType(I.Typ) then
    E('call', [RefOp(PtrPtrProto), RefOp(AssignImport), RegOp(P), Opnd(I.Ops[1])])
  else if I.Typ = jtReal then
    E('dmov', [MemOp(MIR_T_D, LPayOff, P), Opnd(I.Ops[1])])
  else if I.Typ = jtInt then
    E('mov', [MemOp(MIR_T_I64, LPayOff, P), Opnd(I.Ops[1])])
  else
    E('mov', [MemOp(MIR_T_U8, LPayOff, P), Opnd(I.Ops[1])]);
end;

{ A record literal or constructor: the fields in the argument slots, then
  rt_new_record builds it in the destination slot. }
procedure TGen.GenRecord(I: TJInsn);
var
  K, Site: Integer;
  T: TJType;
  St: TMirReg;
  Guard: NativeInt;
begin
  for K := 0 to High(I.Ops) do
  begin
    case I.Ops[K].Kind of
      jkReg:  T := J.Regs[I.Ops[K].Reg].Typ;
      jkReal: T := jtReal;
    else
      T := jtInt;
    end;
    if T = jtReal then
      E('dmov', [MemOp(MIR_T_D, 8 * K, ArgBuf), Opnd(I.Ops[K])])
    else
      E('mov', [MemOp(MIR_T_I64, 8 * K, ArgBuf), Opnd(I.Ops[K])]);
  end;
  Guard := 0;
  if (I.Target <> nil) and (I.Target.ValuePtr <> nil) then
    Guard := NativeInt(I.Target.ValuePtr);
  Site := I.Site;
  if Site < 0 then
    Site := 0;
  St := Scratch(MIR_T_I64);
  E('call', [RefOp(NewRecordProto), RefOp(NewRecordImport), RegOp(St),
    RegOp(SlotAddr(SlotOf[I.Dst])), IntOp(I.Typ), RegOp(ArgBuf), IntOp(Guard), IntOp(Fid), IntOp(Site)]);
  E('bne', [LabelOp(FailLabel), RegOp(St), IntOp(0)]);
end;

{ ---- lists (J10) ---- }

{ The type of the value an instruction's path leads to (its first operand's
  type when it has no path). }
function TGen.BaseType(I: TJInsn): TJType;
var
  K: Integer;
begin
  Result := J.Regs[I.Ops[0].Reg].Typ;
  for K := 0 to High(I.Path) do
    Result := ShapeOf(Result).Types[I.Path[K]];
end;

function TGen.OperandType(const O: TJOperand): TJType;
begin
  case O.Kind of
    jkReg:  Result := J.Regs[O.Reg].Typ;
    jkReal: Result := jtReal;
    jkBool: Result := jtBool;
  else
    Result := jtInt;
  end;
end;

{ Argument slot K := O: a number as itself, an array, record or list by its
  slot's address. }
procedure TGen.PutArg(K: Integer; const O: TJOperand);
begin
  if OperandType(O) = jtReal then
    E('dmov', [MemOp(MIR_T_D, 8 * K, ArgBuf), Opnd(O)])
  else
    E('mov', [MemOp(MIR_T_I64, 8 * K, ArgBuf), Opnd(O)]);
end;

{ length(l): the length a dynamic array keeps before its first element, or
  0 when it has none (a nil array). }
procedure TGen.GenListLen(I: TJInsn);
var
  Obj, Items: TMirReg;
  LDone: TMirInsn;
begin
  Obj := ObjAt(ValueOf(I, False), LListDelta);
  Items := Scratch(MIR_T_I64);
  E('mov', [RegOp(Items), MemOp(MIR_T_I64, LItemsOff, Obj)]);
  LDone := MIR_new_label(Ctx);
  E('mov', [Reg(I.Dst), IntOp(0)]);
  E('beq', [LabelOp(LDone), RegOp(Items), IntOp(0)]);
  E('mov', [Reg(I.Dst), MemOp(MIR_T_I64, LDynLenOff, Items)]);
  MIR_append_insn(Ctx, Body, LDone);
end;

{ l[i], read or written; the index is already checked. A write makes the
  list unique first. An element is a value: a number in its variant part, an
  array, record or list shared. }
procedure TGen.GenListElem(I: TJInsn; IsStore: Boolean);
var
  Addr, Obj, Items, P: TMirReg;
begin
  Addr := ValueOf(I, IsStore);
  if IsStore then
    UniqueAt(Addr, LListDelta, ListUniqueImport);
  Obj := ObjAt(Addr, LListDelta);
  Items := Scratch(MIR_T_I64);
  E('mov', [RegOp(Items), MemOp(MIR_T_I64, LItemsOff, Obj)]);
  // The element's value: items + (i - 1) * slot size.
  P := Scratch(MIR_T_I64);
  E('sub', [RegOp(P), Opnd(I.Ops[1]), IntOp(1)]);
  E('mul', [RegOp(P), RegOp(P), IntOp(LSlotSize)]);
  E('add', [RegOp(P), RegOp(P), RegOp(Items)]);
  if IsStore then
  begin
    if IsBoxedType(I.Typ) then
      E('call', [RefOp(PtrPtrProto), RefOp(AssignImport), RegOp(P), Opnd(I.Ops[2])])
    else if I.Typ = jtReal then
      E('dmov', [MemOp(MIR_T_D, LPayOff, P), Opnd(I.Ops[2])])
    else if I.Typ = jtInt then
      E('mov', [MemOp(MIR_T_I64, LPayOff, P), Opnd(I.Ops[2])])
    else
      E('mov', [MemOp(MIR_T_U8, LPayOff, P), Opnd(I.Ops[2])]);
  end
  else if IsBoxedType(I.Typ) then
    E('call', [RefOp(PtrPtrProto), RefOp(AssignImport), RegOp(SlotAddr(SlotOf[I.Dst])), RegOp(P)])
  else if I.Typ = jtReal then
    E('dmov', [Reg(I.Dst), MemOp(MIR_T_D, LPayOff, P)])
  else if I.Typ = jtInt then
    E('mov', [Reg(I.Dst), MemOp(MIR_T_I64, LPayOff, P)])
  else
    E('mov', [Reg(I.Dst), MemOp(MIR_T_U8, LPayOff, P)]);
end;

{ A list literal: the elements in the argument slots, then rt_new_list. }
procedure TGen.GenList(I: TJInsn);
var
  K: Integer;
begin
  for K := 0 to High(I.Ops) do
    PutArg(K, I.Ops[K]);
  E('call', [RefOp(NewListProto), RefOp(NewListImport), RegOp(SlotAddr(SlotOf[I.Dst])),
    IntOp(ListElem(I.Typ)), RegOp(ArgBuf), IntOp(Length(I.Ops))]);
end;

{ append: the value in the first argument slot, then rt_list_append. }
procedure TGen.GenAppend(I: TJInsn);
begin
  PutArg(0, I.Ops[1]);
  E('call', [RefOp(AppendProto), RefOp(AppendImport), RegOp(SlotAddr(SlotOf[I.Dst])),
    Opnd(I.Ops[0]), RegOp(ArgBuf), IntOp(OperandType(I.Ops[1])), IntOp(I.Ops[2].I)]);
end;

{ An operator on arrays: Axon.Ops through rt_call. }
procedure TGen.GenOp(I: TJInsn);
var
  CS: TJitCallSite;
  St: TMirReg;
  K, N: Integer;
  Args: TArray<TJOperand>;
begin
  CS := TJitCallSite.Create;
  Code.CallSites.Add(CS);
  CS.IsOp := True;
  CS.Op := I.Ops[1].I;
  CS.Name := 'operator ' + I.Ops[1].S;
  if Length(I.Ops) > 2 then
    Args := [I.Ops[0], I.Ops[2]]
  else
    Args := [I.Ops[0]];
  N := Length(Args);
  SetLength(CS.ArgTypes, N);
  for K := 0 to N - 1 do
  begin
    if Args[K].Kind = jkReg then
      CS.ArgTypes[K] := J.Regs[Args[K].Reg].Typ
    else if Args[K].Kind = jkReal then
      CS.ArgTypes[K] := jtReal
    else if Args[K].Kind = jkBool then
      CS.ArgTypes[K] := jtBool
    else
      CS.ArgTypes[K] := jtInt;
    if CS.ArgTypes[K] = jtReal then
      E('dmov', [MemOp(MIR_T_D, 8 * K, ArgBuf), Opnd(Args[K])])
    else
      E('mov', [MemOp(MIR_T_I64, 8 * K, ArgBuf), Opnd(Args[K])]);
  end;
  CS.ResultTypes := [I.Typ];
  E('mov', [MemOp(MIR_T_I64, 0, ResBuf), RegOp(SlotAddr(SlotOf[I.Dst]))]);
  St := Scratch(MIR_T_I64);
  E('call', [RefOp(CallProto), RefOp(CallImport), RegOp(St), IntOp(NativeInt(CS)),
    IntOp(Fid), IntOp(I.Site), RegOp(ArgBuf), RegOp(ResBuf)]);
  E('bne', [LabelOp(FailLabel), RegOp(St), IntOp(0)]);
end;

{ A vector or matrix literal: the entries in the argument slots, then
  rt_new_array builds it in the destination slot. }
procedure TGen.GenArray(I: TJInsn);
var
  K: Integer;
  IsReal: Boolean;
begin
  IsReal := ElemOf(I.Typ) = jtReal;
  for K := 2 to High(I.Ops) do
    if IsReal then
      E('dmov', [MemOp(MIR_T_D, 8 * (K - 2), ArgBuf), Opnd(I.Ops[K])])
    else
      E('mov', [MemOp(MIR_T_I64, 8 * (K - 2), ArgBuf), Opnd(I.Ops[K])]);
  E('call', [RefOp(NewArrayProto), RefOp(NewArrayImport), RegOp(SlotAddr(SlotOf[I.Dst])),
    Opnd(I.Ops[0]), Opnd(I.Ops[1]), IntOp(Ord(IsReal)), RegOp(ArgBuf)]);
end;

{ Array results are written by the callee into slots whose addresses the
  caller puts in the result buffer; a result not used goes to the junk slot. }
procedure TGen.SetupResultDests(I: TJInsn; const ResultTypes: TArray<TJType>);
var
  K, Slot: Integer;
begin
  for K := 0 to High(ResultTypes) do
    if IsBoxedType(ResultTypes[K]) then
    begin
      if (K <= High(I.Dsts)) and (I.Dsts[K] >= 0) then
        Slot := SlotOf[I.Dsts[K]]
      else
        Slot := JunkSlot;
      E('mov', [MemOp(MIR_T_I64, 8 * K, ResBuf), RegOp(SlotAddr(Slot))]);
    end;
end;

procedure TGen.ClearJunk(I: TJInsn; const ResultTypes: TArray<TJType>);
var
  K: Integer;
begin
  for K := 0 to High(ResultTypes) do
    if IsBoxedType(ResultTypes[K]) and ((K > High(I.Dsts)) or (I.Dsts[K] < 0)) then
      E('call', [RefOp(PtrProto), RefOp(ClearImport), RegOp(SlotAddr(JunkSlot))]);
end;

{ int ^ int with a non-negative exponent: IntPow's square-and-multiply with
  checked products, so it overflows exactly when the interpreter does. }
procedure TGen.GenPowInt(I: TJInsn);
var
  Res, Base, Ex, T: TMirReg;
  LLoop, LSkip, LDone, LErr: TMirInsn;
begin
  Res := Scratch(MIR_T_I64);
  Base := Scratch(MIR_T_I64);
  Ex := Scratch(MIR_T_I64);
  T := Scratch(MIR_T_I64);
  LLoop := MIR_new_label(Ctx);
  LSkip := MIR_new_label(Ctx);
  LDone := MIR_new_label(Ctx);
  LErr := ErrorLabel(I.Site, ErrPow);
  E('mov', [RegOp(Res), IntOp(1)]);
  E('mov', [RegOp(Base), Opnd(I.Ops[0])]);
  E('mov', [RegOp(Ex), Opnd(I.Ops[1])]);
  MIR_append_insn(Ctx, Body, LLoop);
  E('ble', [LabelOp(LDone), RegOp(Ex), IntOp(0)]);
  E('and', [RegOp(T), RegOp(Ex), IntOp(1)]);
  E('beq', [LabelOp(LSkip), RegOp(T), IntOp(0)]);
  E('mulo', [RegOp(Res), RegOp(Res), RegOp(Base)]);
  E('bo', [LabelOp(LErr)]);
  MIR_append_insn(Ctx, Body, LSkip);
  E('rsh', [RegOp(Ex), RegOp(Ex), IntOp(1)]);
  E('ble', [LabelOp(LDone), RegOp(Ex), IntOp(0)]);
  E('mulo', [RegOp(Base), RegOp(Base), RegOp(Base)]);
  E('bo', [LabelOp(LErr)]);
  E('jmp', [LabelOp(LLoop)]);
  MIR_append_insn(Ctx, Body, LDone);
  E('mov', [Reg(I.Dst), RegOp(Res)]);
end;

function TGen.NewCallSite(I: TJInsn): TJitCallSite;
var
  K: Integer;
  Used: Boolean;
begin
  Result := TJitCallSite.Create;
  Code.CallSites.Add(Result);
  Result.Name := I.Target.Name;
  Result.Value := I.Target.Value;
  Result.ValuePtr := I.Target.ValuePtr;
  Result.ArgTypes := I.Target.ArgTypes;
  SetLength(Result.Strings, Length(I.Ops));
  for K := 0 to High(I.Ops) do
    if I.Ops[K].Kind = jkString then
      Result.Strings[K] := I.Ops[K].S;
  // The results the caller loads (none for a statement).
  Used := False;
  for K := 0 to High(I.Dsts) do
    if I.Dsts[K] >= 0 then
      Used := True;
  if Used then
    Result.ResultTypes := I.Target.ResultTypes;
end;

{ Results from the result buffer into the registers that use them. }
procedure TGen.LoadResults(I: TJInsn);
var
  K: Integer;
begin
  for K := 0 to High(I.Dsts) do
    if (I.Dsts[K] >= 0) and (SlotOf[I.Dsts[K]] < 0) then
      if J.Regs[I.Dsts[K]].Typ = jtReal then
        E('dmov', [Reg(I.Dsts[K]), MemOp(MIR_T_D, 8 * K, ResBuf)])
      else
        E('mov', [Reg(I.Dsts[K]), MemOp(MIR_T_I64, 8 * K, ResBuf)]);
end;

{ rt_call(site, fid, siteindex, args, res), the arguments stored in slots.
  Join, when not nil, is where the call continues (an out-of-line path). }
procedure TGen.GenCallThroughInterp(I: TJInsn; CS: TJitCallSite; Join: TMirInsn);
var
  K: Integer;
  St: TMirReg;
begin
  for K := 0 to High(I.Ops) do
    case I.Ops[K].Kind of
      jkString: ;
      jkReal:
        E('dmov', [MemOp(MIR_T_D, 8 * K, ArgBuf), Opnd(I.Ops[K])]);
      jkReg:
        if J.Regs[I.Ops[K].Reg].Typ = jtReal then
          E('dmov', [MemOp(MIR_T_D, 8 * K, ArgBuf), Opnd(I.Ops[K])])
        else
          E('mov', [MemOp(MIR_T_I64, 8 * K, ArgBuf), Opnd(I.Ops[K])]);
    else
      E('mov', [MemOp(MIR_T_I64, 8 * K, ArgBuf), Opnd(I.Ops[K])]);
    end;
  SetupResultDests(I, CS.ResultTypes);
  St := Scratch(MIR_T_I64);
  E('call', [RefOp(CallProto), RefOp(CallImport), RegOp(St), IntOp(NativeInt(CS)),
    IntOp(Fid), IntOp(I.Site), RegOp(ArgBuf), RegOp(ResBuf)]);
  E('bne', [LabelOp(FailLabel), RegOp(St), IntOp(0)]);
  if Join <> nil then
    E('jmp', [LabelOp(Join)]);
end;

procedure TGen.GenCall(I: TJInsn);
var
  Info: TCallInfo;
  T: TJCallTarget;
  CS: TJitCallSite;
  G, D, St, Dst: TMirReg;
  LSlow, LJoin, LRec, LProp: TMirInsn;
  Ops: TArray<TAxMirOp>;
  K: Integer;
begin
  T := I.Target;
  Info := Calls[I];
  CS := NewCallSite(I);

  if (T.Kind = ckBuiltin) and T.Direct then
  begin
    // RF(x): the interpreter's own routine.
    if I.Dsts[0] >= 0 then
      Dst := Regs[I.Dsts[0]]
    else
      Dst := Scratch(MIR_T_D);
    if Length(I.Ops) = 2 then
      E('call', [RefOp(Info.Proto), RefOp(Info.Callee), RegOp(Dst), Opnd(I.Ops[0]), Opnd(I.Ops[1])])
    else
      E('call', [RefOp(Info.Proto), RefOp(Info.Callee), RegOp(Dst), Opnd(I.Ops[0])]);
    Exit;
  end;

  if T.Kind <> ckCompiled then
  begin
    GenCallThroughInterp(I, CS, nil);
    LoadResults(I);
    Exit;
  end;

  // A compiled callee.
  LJoin := MIR_new_label(Ctx);
  LRec := MIR_new_label(Ctx);
  LProp := MIR_new_label(Ctx);
  if T.ValuePtr <> nil then
  begin
    // The guard: the variable still holds the function compiled against.
    LSlow := MIR_new_label(Ctx);
    G := Scratch(MIR_T_I64);
    E('mov', [RegOp(G), IntOp(NativeInt(T.ValuePtr))]);
    E('mov', [RegOp(G), MemOp(MIR_T_I64, ObjOffset, G)]);
    E('bne', [LabelOp(LSlow), RegOp(G), IntOp(ObjBits(T.Value))]);
  end
  else
    LSlow := nil;
  // Invoke's depth check: raise, check, and lower again after the call.
  D := Scratch(MIR_T_I64);
  E('mov', [RegOp(D), MemOp(MIR_T_I32, 0, DepthAddr)]);
  E('add', [RegOp(D), RegOp(D), IntOp(1)]);
  E('mov', [MemOp(MIR_T_I32, 0, DepthAddr), RegOp(D)]);
  E('bgt', [LabelOp(LRec), RegOp(D), IntOp(JitMaxDepth)]);
  SetupResultDests(I, T.ResultTypes);
  SetLength(Ops, 4 + Length(I.Ops));
  St := Scratch(MIR_T_I64);
  Ops[0] := RefOp(Info.Proto);
  if Info.Callee <> nil then
    Ops[1] := RefOp(Info.Callee)
  else
    Ops[1] := RefOp(Body);         // recursion: this function
  Ops[2] := RegOp(St);
  Ops[3] := RegOp(ResBuf);
  for K := 0 to High(I.Ops) do
    Ops[4 + K] := Opnd(I.Ops[K]);
  E('call', Ops);
  E('mov', [RegOp(D), MemOp(MIR_T_I32, 0, DepthAddr)]);
  E('sub', [RegOp(D), RegOp(D), IntOp(1)]);
  E('mov', [MemOp(MIR_T_I32, 0, DepthAddr), RegOp(D)]);
  E('bne', [LabelOp(LProp), RegOp(St), IntOp(0)]);
  ClearJunk(I, T.ResultTypes);
  MIR_append_insn(Ctx, Body, LJoin);
  LoadResults(I);

  Deferred.Add(
    procedure
    var
      D2: TMirReg;
    begin
      // Too deep: lower the depth again, as Invoke's finally does.
      MIR_append_insn(Ctx, Body, LRec);
      D2 := Scratch(MIR_T_I64);
      E('mov', [RegOp(D2), MemOp(MIR_T_I32, 0, DepthAddr)]);
      E('sub', [RegOp(D2), RegOp(D2), IntOp(1)]);
      E('mov', [MemOp(MIR_T_I32, 0, DepthAddr), RegOp(D2)]);
      E('call', [RefOp(RecProto), RefOp(RecImport), IntOp(NativeInt(CS)), IntOp(Fid), IntOp(I.Site)]);
      RetFail;
      // The callee failed: this frame is at the call.
      MIR_append_insn(Ctx, Body, LProp);
      E('call', [RefOp(FrameProto), RefOp(FrameImport), IntOp(Fid), IntOp(I.Site)]);
      RetFail;
      if LSlow <> nil then
      begin
        // The variable now holds something else: call that through the interpreter.
        MIR_append_insn(Ctx, Body, LSlow);
        GenCallThroughInterp(I, CS, LJoin);
      end;
    end);
end;

procedure TGen.GenInsn(I: TJInsn);
const
  IntCmp: array[joEq..joGe] of AnsiString = ('eq', 'ne', 'lt', 'le', 'gt', 'ge');
  RealCmp: array[joEq..joGe] of AnsiString = ('deq', 'dne', 'dlt', 'dle', 'dgt', 'dge');
var
  IsReal: Boolean;
  T: TMirReg;
  K: Integer;
  Name: AnsiString;
begin
  IsReal := I.Typ = jtReal;
  case I.Op of
    joLabel:
      MIR_append_insn(Ctx, Body, Labels[I.Ops[0].I]);
    joMov:
      if SlotOf[I.Dst] >= 0 then
        GenArrayMov(I)
      else if J.Regs[I.Dst].Typ = jtReal then
        E('dmov', [Reg(I.Dst), Opnd(I.Ops[0])])
      else
        E('mov', [Reg(I.Dst), Opnd(I.Ops[0])]);
    joB2I:
      E('mov', [Reg(I.Dst), Opnd(I.Ops[0])]);
    joB2R, joI2R:
      if I.Ops[0].IsImm then
        E('dmov', [Reg(I.Dst), DoubleOp(Opnd(I.Ops[0]).I)])
      else
        E('i2d', [Reg(I.Dst), Opnd(I.Ops[0])]);
    joAdd, joSub, joMul:
      if IsReal then
      begin
        case I.Op of
          joAdd: Name := 'dadd';
          joSub: Name := 'dsub';
        else
          Name := 'dmul';
        end;
        E(Name, [Reg(I.Dst), Opnd(I.Ops[0]), Opnd(I.Ops[1])]);
      end
      else if I.Site < 0 then
      begin
        case I.Op of
          joAdd: Name := 'add';
          joSub: Name := 'sub';
        else
          Name := 'mul';
        end;
        E(Name, [Reg(I.Dst), Opnd(I.Ops[0]), Opnd(I.Ops[1])]);
      end
      else
      begin
        case I.Op of
          joAdd: begin Name := 'addo'; K := ErrAdd; end;
          joSub: begin Name := 'subo'; K := ErrSub; end;
        else
          begin Name := 'mulo'; K := ErrMul; end;
        end;
        E(Name, [Reg(I.Dst), Opnd(I.Ops[0]), Opnd(I.Ops[1])]);
        E('bo', [LabelOp(ErrorLabel(I.Site, K))]);
      end;
    joNeg:
      if IsReal then
        E('dneg', [Reg(I.Dst), Opnd(I.Ops[0])])
      else if I.Site < 0 then
        E('neg', [Reg(I.Dst), Opnd(I.Ops[0])])
      else
      begin
        // -x overflows only for the most negative int: 0 - x with subo.
        E('subo', [Reg(I.Dst), IntOp(0), Opnd(I.Ops[0])]);
        E('bo', [LabelOp(ErrorLabel(I.Site, ErrNeg))]);
      end;
    joDiv:
      E('ddiv', [Reg(I.Dst), Opnd(I.Ops[0]), Opnd(I.Ops[1])]);
    joPow:
      if IsReal then
        E('call', [RefOp(PowProto), RefOp(PowImport), Reg(I.Dst), Opnd(I.Ops[0]), Opnd(I.Ops[1])])
      else
        GenPowInt(I);
    joEq..joGe:
      if IsReal then
        E(RealCmp[I.Op], [Reg(I.Dst), Opnd(I.Ops[0]), Opnd(I.Ops[1])])
      else
        E(IntCmp[I.Op], [Reg(I.Dst), Opnd(I.Ops[0]), Opnd(I.Ops[1])]);
    joNot:
      E('eq', [Reg(I.Dst), Opnd(I.Ops[0]), IntOp(0)]);
    joJmp:
      E('jmp', [LabelOp(Labels[I.Ops[0].I])]);
    joBrTrue, joBrFalse:
      if I.Ops[0].Kind = jkBool then
      begin
        // A constant condition: always or never.
        if I.Ops[0].B = (I.Op = joBrTrue) then
          E('jmp', [LabelOp(Labels[I.Ops[1].I])]);
      end
      else if I.Op = joBrTrue then
        E('bt', [LabelOp(Labels[I.Ops[1].I]), Opnd(I.Ops[0])])
      else
        E('bf', [LabelOp(Labels[I.Ops[1].I]), Opnd(I.Ops[0])]);
    joCount:
      begin
        if IsReal then
          E('call', [RefOp(CountRealProto), RefOp(CountRealImport), Reg(I.Dst),
            Opnd(I.Ops[0]), Opnd(I.Ops[1]), Opnd(I.Ops[2]), IntOp(Fid), IntOp(I.Site)])
        else
          E('call', [RefOp(CountIntProto), RefOp(CountIntImport), Reg(I.Dst),
            Opnd(I.Ops[0]), Opnd(I.Ops[1]), Opnd(I.Ops[2]), IntOp(Fid), IntOp(I.Site)]);
        // The helper has recorded the error.
        E('blt', [LabelOp(FailLabel), Reg(I.Dst), IntOp(0)]);
      end;
    joElem:
      if IsReal then
      begin
        // start + k*step, with k converted first, as TRangeObj.ItemAt.
        T := Scratch(MIR_T_D);
        E('i2d', [RegOp(T), Opnd(I.Ops[2])]);
        E('dmul', [RegOp(T), RegOp(T), Opnd(I.Ops[1])]);
        E('dadd', [Reg(I.Dst), Opnd(I.Ops[0]), RegOp(T)]);
      end
      else
      begin
        T := Scratch(MIR_T_I64);
        E('mul', [RegOp(T), Opnd(I.Ops[2]), Opnd(I.Ops[1])]);
        E('add', [Reg(I.Dst), Opnd(I.Ops[0]), RegOp(T)]);
      end;
    joRet:
      begin
        for K := 0 to High(I.Ops) do
          if IsBoxedType(J.ResultTypes[K]) then
          begin
            // The caller's slot, whose address is in the result slot.
            T := Scratch(MIR_T_I64);
            E('mov', [RegOp(T), MemOp(MIR_T_I64, 8 * K, ResPtr)]);
            E('call', [RefOp(PtrPtrProto), RefOp(AssignImport), RegOp(T), Opnd(I.Ops[K])]);
          end
          else if J.ResultTypes[K] = jtReal then
            E('dmov', [MemOp(MIR_T_D, 8 * K, ResPtr), Opnd(I.Ops[K])])
          else
            E('mov', [MemOp(MIR_T_I64, 8 * K, ResPtr), Opnd(I.Ops[K])]);
        if NSlots > 0 then
        begin
          E('mov', [RegOp(StatusReg), IntOp(0)]);
          E('jmp', [LabelOp(ExitLabel)]);
        end
        else
          E('ret', [IntOp(0)]);
      end;
    joCall:
      GenCall(I);
    joLen:
      GenLen(I);
    joBound:
      GenBound(I);
    joLoad:
      GenElem(I, False);
    joStore:
      GenElem(I, True);
    joOp:
      GenOp(I);
    joClear:
      E('call', [RefOp(PtrProto), RefOp(ClearImport), RegOp(SlotAddr(SlotOf[I.Ops[0].Reg]))]);
    joArray:
      GenArray(I);
    joField:
      GenField(I);
    joSetField:
      GenSetField(I);
    joRecord:
      GenRecord(I);
    joList:
      GenList(I);
    joAppend:
      GenAppend(I);
  else
    raise EMirError.CreateFmt('JIT: no code for JIR op %d', [Ord(I.Op)]);
  end;
end;

function TGen.Run: TMirItem;
var
  Module: TMirModule;
  V, EV: TArray<TMirVar>;
  Types: TArray<Int32>;
  Names: TArray<AnsiString>;
  ResI64, ResD: Int32;
  BodyProto, BodyItem, Entry: TMirItem;
  K, P, MaxArgs, MaxRes: Integer;
  ModName, BodyName, EntryName, ProtoName: AnsiString;
  Insn: TJInsn;
  B: TErrorBlock;
  ArgsReg, EntryRes, Status: TMirReg;
  CallOps: TArray<TAxMirOp>;
  Loaded: TArray<TMirReg>;
  RegName: AnsiString;
  Block: TProc;
  HasCalls: Boolean;
begin
  ResI64 := MIR_T_I64;
  ResD := MIR_T_D;
  ModName := AnsiString('m' + IntToStr(Fid));
  BodyName := AnsiString('f' + IntToStr(Fid));
  EntryName := AnsiString('e' + IntToStr(Fid));
  ProtoName := AnsiString('p' + IntToStr(Fid));
  Module := MIR_new_module(Ctx, PAnsiChar(ModName));
  MIR_new_export(Ctx, PAnsiChar(BodyName));

  // Prototypes and imports of the helpers.
  V := Vars([MIR_T_I64, MIR_T_I64, MIR_T_I64], ['fid', 'site', 'code']);
  ErrProto := MIR_new_proto_arr(Ctx, 'rt_error_p', 0, nil, 3, @V[0]);
  ErrImport := MIR_new_import(Ctx, 'rt_error');
  V := Vars([MIR_T_I64, MIR_T_I64, MIR_T_I64, MIR_T_I64, MIR_T_I64], ['a', 'h', 'b', 'fid', 'site']);
  CountIntProto := MIR_new_proto_arr(Ctx, 'rt_count_int_p', 1, @ResI64, 5, @V[0]);
  CountIntImport := MIR_new_import(Ctx, 'rt_count_int');
  V := Vars([MIR_T_D, MIR_T_D, MIR_T_D, MIR_T_I64, MIR_T_I64], ['a', 'h', 'b', 'fid', 'site']);
  CountRealProto := MIR_new_proto_arr(Ctx, 'rt_count_real_p', 1, @ResI64, 5, @V[0]);
  CountRealImport := MIR_new_import(Ctx, 'rt_count_real');
  V := Vars([MIR_T_D, MIR_T_D], ['x', 'y']);
  PowProto := MIR_new_proto_arr(Ctx, 'rt_pow_real_p', 1, @ResD, 2, @V[0]);
  PowImport := MIR_new_import(Ctx, 'rt_pow_real');
  V := Vars([MIR_T_P, MIR_T_I64, MIR_T_I64, MIR_T_P, MIR_T_P], ['cs', 'fid', 'site', 'args', 'res']);
  CallProto := MIR_new_proto_arr(Ctx, 'rt_call_p', 1, @ResI64, 5, @V[0]);
  CallImport := MIR_new_import(Ctx, 'rt_call');
  V := Vars([MIR_T_I64, MIR_T_I64], ['fid', 'site']);
  FrameProto := MIR_new_proto_arr(Ctx, 'rt_frame_p', 0, nil, 2, @V[0]);
  FrameImport := MIR_new_import(Ctx, 'rt_frame');
  V := Vars([MIR_T_P, MIR_T_I64, MIR_T_I64], ['cs', 'fid', 'site']);
  RecProto := MIR_new_proto_arr(Ctx, 'rt_recursion_p', 0, nil, 3, @V[0]);
  RecImport := MIR_new_import(Ctx, 'rt_recursion');
  V := Vars([MIR_T_D], ['x']);
  D1Proto := MIR_new_proto_arr(Ctx, 'rt_d1_p', 1, @ResD, 1, @V[0]);
  V := Vars([MIR_T_D, MIR_T_D], ['y', 'x']);
  D2Proto := MIR_new_proto_arr(Ctx, 'rt_d2_p', 1, @ResD, 2, @V[0]);
  V := Vars([MIR_T_P], ['p']);
  PtrProto := MIR_new_proto_arr(Ctx, 'rt_p_p', 0, nil, 1, @V[0]);
  V := Vars([MIR_T_P, MIR_T_P], ['dst', 'src']);
  PtrPtrProto := MIR_new_proto_arr(Ctx, 'rt_pp_p', 0, nil, 2, @V[0]);
  AssignImport := MIR_new_import(Ctx, 'rt_assign');
  MoveImport := MIR_new_import(Ctx, 'rt_move');
  ClearImport := MIR_new_import(Ctx, 'rt_clear');
  UniqueImport := MIR_new_import(Ctx, 'rt_make_unique');
  V := Vars([MIR_T_P, MIR_T_I64], ['frame', 'n']);
  LeaveProto := MIR_new_proto_arr(Ctx, 'rt_leave_p', 0, nil, 2, @V[0]);
  LeaveImport := MIR_new_import(Ctx, 'rt_leave');
  V := Vars([MIR_T_I64, MIR_T_I64, MIR_T_I64, MIR_T_I64], ['fid', 'site', 'index', 'len']);
  IndexErrProto := MIR_new_proto_arr(Ctx, 'rt_index_error_p', 0, nil, 4, @V[0]);
  IndexErrImport := MIR_new_import(Ctx, 'rt_index_error');
  V := Vars([MIR_T_P, MIR_T_I64, MIR_T_I64, MIR_T_I64, MIR_T_P], ['dst', 'rows', 'cols', 'isreal', 'args']);
  NewArrayProto := MIR_new_proto_arr(Ctx, 'rt_new_array_p', 0, nil, 5, @V[0]);
  NewArrayImport := MIR_new_import(Ctx, 'rt_new_array');
  V := Vars([MIR_T_P, MIR_T_I64, MIR_T_P, MIR_T_P, MIR_T_I64, MIR_T_I64],
    ['dst', 'shape', 'args', 'guard', 'fid', 'site']);
  NewRecordProto := MIR_new_proto_arr(Ctx, 'rt_new_record_p', 1, @ResI64, 6, @V[0]);
  NewRecordImport := MIR_new_import(Ctx, 'rt_new_record');
  RecUniqueImport := MIR_new_import(Ctx, 'rt_record_unique');
  V := Vars([MIR_T_P, MIR_T_I64, MIR_T_P, MIR_T_I64], ['dst', 'elem', 'args', 'n']);
  NewListProto := MIR_new_proto_arr(Ctx, 'rt_new_list_p', 0, nil, 4, @V[0]);
  NewListImport := MIR_new_import(Ctx, 'rt_new_list');
  V := Vars([MIR_T_P, MIR_T_P, MIR_T_P, MIR_T_I64, MIR_T_I64], ['dst', 'src', 'arg', 't', 'inplace']);
  AppendProto := MIR_new_proto_arr(Ctx, 'rt_list_append_p', 0, nil, 5, @V[0]);
  AppendImport := MIR_new_import(Ctx, 'rt_list_append');
  ListUniqueImport := MIR_new_import(Ctx, 'rt_list_unique');
  DeclareCalls;

  // A slot for every array register, and a junk slot for array results that
  // are not used.
  SetLength(SlotOf, J.Regs.Count);
  NSlots := 0;
  for K := 0 to J.Regs.Count - 1 do
    if IsBoxedType(J.Regs[K].Typ) then
    begin
      SlotOf[K] := NSlots;
      Inc(NSlots);
    end
    else
      SlotOf[K] := -1;
  JunkSlot := NSlots;
  for Insn in J.Insns do
    if Insn.Op = joCall then
      for K := 0 to High(Insn.Target.ResultTypes) do
        if IsBoxedType(Insn.Target.ResultTypes[K]) then
          JunkSlot := -2;
  if (NSlots > 0) or (JunkSlot = -2) then
  begin
    JunkSlot := NSlots;
    Inc(NSlots);
  end;

  // The body's parameters: the result pointer, then the JIR parameters, each
  // named after its register.
  SetLength(Types, J.Params.Count + 1);
  SetLength(Names, J.Params.Count + 1);
  Types[0] := MIR_T_P;
  Names[0] := 'res';
  for K := 0 to J.Params.Count - 1 do
  begin
    Types[K + 1] := MirType(J.Regs[J.Params[K]].Typ);
    Names[K + 1] := AnsiString('r' + IntToStr(J.Params[K]));
  end;
  V := Vars(Types, Names);
  BodyProto := MIR_new_proto_arr(Ctx, PAnsiChar(ProtoName), 1, @ResI64, Length(V), @V[0]);

  Body := MIR_new_func_arr(Ctx, PAnsiChar(BodyName), 1, @ResI64, Length(V), @V[0]);
  ResPtr := axmir_reg(Ctx, Body, 'res');
  SetLength(Regs, J.Regs.Count);
  for K := 0 to J.Regs.Count - 1 do
  begin
    RegName := AnsiString('r' + IntToStr(K));
    if J.Regs[K].IsParam then
      Regs[K] := axmir_reg(Ctx, Body, PAnsiChar(RegName))   // an array parameter: its pointer
    else if SlotOf[K] < 0 then
      Regs[K] := axmir_new_reg(Ctx, Body, MirType(J.Regs[K].Typ), PAnsiChar(RegName));
  end;
  SetLength(Labels, J.LabelCount);
  for K := 0 to J.LabelCount - 1 do
    Labels[K] := MIR_new_label(Ctx);
  FailLabel := MIR_new_label(Ctx);

  // Calls need slots for arguments and results, and the depth counter.
  MaxArgs := 0;
  MaxRes := 0;
  HasCalls := False;
  for Insn in J.Insns do
    if Insn.Op = joCall then
    begin
      HasCalls := True;
      if Length(Insn.Ops) > MaxArgs then MaxArgs := Length(Insn.Ops);
      if Length(Insn.Dsts) > MaxRes then MaxRes := Length(Insn.Dsts);
    end;
  for Insn in J.Insns do
    if Insn.Op = joOp then
    begin
      HasCalls := True;
      if MaxArgs < 2 then MaxArgs := 2;
      if MaxRes < 1 then MaxRes := 1;
    end
    else if Insn.Op = joArray then
    begin
      HasCalls := True;
      if MaxArgs < Length(Insn.Ops) - 2 then MaxArgs := Length(Insn.Ops) - 2;
    end
    else if Insn.Op in [joRecord, joList] then
    begin
      HasCalls := True;
      if MaxArgs < Length(Insn.Ops) then MaxArgs := Length(Insn.Ops);
    end
    else if Insn.Op = joAppend then
    begin
      HasCalls := True;
      if MaxArgs < 1 then MaxArgs := 1;
    end;
  if NSlots > 0 then
  begin
    // The frame: zeroed slots, released at the exit.
    FrameReg := axmir_new_reg(Ctx, Body, MIR_T_I64, 'frame');
    StatusReg := axmir_new_reg(Ctx, Body, MIR_T_I64, 'status');
    ExitLabel := MIR_new_label(Ctx);
    E('alloca', [RegOp(FrameReg), IntOp(NSlots * LSlotSize)]);
    for K := 0 to (NSlots * LSlotSize) div 8 - 1 do
      E('mov', [MemOp(MIR_T_I64, 8 * K, FrameReg), IntOp(0)]);
  end;
  if HasCalls then
  begin
    ArgBuf := axmir_new_reg(Ctx, Body, MIR_T_I64, 'argbuf');
    ResBuf := axmir_new_reg(Ctx, Body, MIR_T_I64, 'resbuf');
    DepthAddr := axmir_new_reg(Ctx, Body, MIR_T_I64, 'depth');
    E('alloca', [RegOp(ArgBuf), IntOp(8 * (MaxArgs + MaxRes + 1))]);
    E('add', [RegOp(ResBuf), RegOp(ArgBuf), IntOp(8 * MaxArgs)]);
    E('mov', [RegOp(DepthAddr), IntOp(NativeInt(JitDepth))]);
  end;
  // Array parameters: this function's own reference, as a parameter cell holds.
  for K := 0 to J.Params.Count - 1 do
    if SlotOf[J.Params[K]] >= 0 then
      E('call', [RefOp(PtrPtrProto), RefOp(AssignImport), RegOp(SlotAddr(SlotOf[J.Params[K]])),
        RegOp(Regs[J.Params[K]])]);

  for Insn in J.Insns do
    GenInsn(Insn);

  // Out-of-line blocks, error blocks, then the common failure return.
  for Block in Deferred do
    Block();
  for B in ErrorBlocks do
  begin
    MIR_append_insn(Ctx, Body, B.Lbl);
    E('call', [RefOp(ErrProto), RefOp(ErrImport), IntOp(Fid), IntOp(B.Site), IntOp(B.Code)]);
    RetFail;
  end;
  MIR_append_insn(Ctx, Body, FailLabel);
  RetFail;
  if NSlots > 0 then
  begin
    // The single exit: release the frame's values.
    MIR_append_insn(Ctx, Body, ExitLabel);
    E('call', [RefOp(LeaveProto), RefOp(LeaveImport), RegOp(FrameReg), IntOp(NSlots)]);
    E('ret', [RegOp(StatusReg)]);
  end;
  MIR_finish_func(Ctx);
  BodyItem := Body;

  // The entry thunk: e(args, res) loads the parameters and calls the body.
  EV := Vars([MIR_T_P, MIR_T_P], ['args', 'res']);
  Entry := MIR_new_func_arr(Ctx, PAnsiChar(EntryName), 1, @ResI64, 2, @EV[0]);
  Body := Entry;   // E() appends to Body
  ArgsReg := axmir_reg(Ctx, Entry, 'args');
  EntryRes := axmir_reg(Ctx, Entry, 'res');
  Status := axmir_new_reg(Ctx, Entry, MIR_T_I64, 'status');
  SetLength(Loaded, J.Params.Count);
  for K := 0 to J.Params.Count - 1 do
  begin
    P := J.Params[K];
    RegName := AnsiString('a' + IntToStr(K));
    Loaded[K] := axmir_new_reg(Ctx, Entry, MirType(J.Regs[P].Typ), PAnsiChar(RegName));
    if J.Regs[P].Typ = jtReal then
      E('dmov', [RegOp(Loaded[K]), MemOp(MIR_T_D, 8 * K, ArgsReg)])
    else
      E('mov', [RegOp(Loaded[K]), MemOp(MIR_T_I64, 8 * K, ArgsReg)]);
  end;
  SetLength(CallOps, 4 + J.Params.Count);
  CallOps[0] := RefOp(BodyProto);
  CallOps[1] := RefOp(BodyItem);
  CallOps[2] := RegOp(Status);
  CallOps[3] := RegOp(EntryRes);
  for K := 0 to J.Params.Count - 1 do
    CallOps[4 + K] := RegOp(Loaded[K]);
  E('call', CallOps);
  E('ret', [RegOp(Status)]);
  MIR_finish_func(Ctx);

  MIR_finish_module(Ctx);
  MIR_load_module(Ctx, Module);
  Result := Entry;
end;

function GenerateModule(J: TJFunction; Code: TJitCode): TMirItem;
var
  G: TGen;
begin
  EnsureContext;
  G := TGen.Create(J, Code);
  try
    Result := G.Run;
  finally
    G.Free;
  end;
end;

initialization

finalization
  if Ctx <> nil then
    axmir_finish(Ctx);

end.
