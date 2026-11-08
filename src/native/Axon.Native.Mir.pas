unit Axon.Native.Mir;

(* MIR: the in-process JIT compiler (doc/Axon-JIT-Plan.md).

   mir.dll / libmir.dylib is MIR's core (mir.c, mir-gen.c) plus Axon's shim,
   src/native/axmir.c, built by tools/build_mir.cmd. Like OpenBLAS, it is
   loaded on first use, so the interpreter starts and runs everything without
   it; MirAvailable says whether it could be loaded.

   MIR functions that take and return only pointers and integers are bound
   directly. Operands go through the shim as TAxMirOp, a plain record, because
   MIR_op_t's bitfield layout differs between compilers. Instruction codes are
   looked up by name (MirCode) rather than copied from MIR's enum. *)

interface

uses
  System.SysUtils;

const
{$IFDEF MSWINDOWS}
  LibraryName = 'mir.dll';
{$ENDIF}
{$IFDEF MACOS}
  LibraryName = 'libmir.dylib';
{$ENDIF}
{$IFDEF LINUX}
  LibraryName = 'libmir.so';
{$ENDIF}

  { MIR_type_t (mir.h). These ordinals have been stable across MIR releases. }
  MIR_T_I8 = 0;  MIR_T_U8 = 1;  MIR_T_I16 = 2; MIR_T_U16 = 3;
  MIR_T_I32 = 4; MIR_T_U32 = 5; MIR_T_I64 = 6; MIR_T_U64 = 7;
  MIR_T_F = 8;   MIR_T_D = 9;   MIR_T_LD = 10; MIR_T_P = 11;

  { TAxMirOp.Kind (axmir.c). }
  AXOP_REG = 0; AXOP_INT = 1; AXOP_DOUBLE = 2; AXOP_REF = 3; AXOP_LABEL = 4; AXOP_MEM = 5;

type
  TMirContext = Pointer;
  TMirModule = Pointer;
  TMirItem = Pointer;
  TMirInsn = Pointer;
  TMirReg = UInt32;

  { axmir_op: 48 bytes, the same layout on every target. }
  TAxMirOp = record
    Kind: Int32;
    Typ: Int32;        // AXOP_MEM: MIR type of the memory
    I: Int64;          // AXOP_INT: value; AXOP_MEM: displacement
    D: Double;         // AXOP_DOUBLE
    P: Pointer;        // AXOP_REF: item; AXOP_LABEL: label
    Reg: UInt32;       // AXOP_REG: register; AXOP_MEM: base (0 = none)
    Index: UInt32;     // AXOP_MEM: index register (0 = none)
    Scale: UInt32;     // AXOP_MEM: 1, 2, 4 or 8
    Pad: UInt32;
  end;
  PAxMirOp = ^TAxMirOp;

  { MIR_var_t: a parameter of a function or prototype. }
  TMirVar = record
    Typ: Int32;
    Name: PAnsiChar;
    Size: NativeUInt;  // only for block types
  end;
  PMirVar = ^TMirVar;

  TAxMirErrorHandler = procedure(ErrorType: Int32; Message: PAnsiChar); cdecl;

var
  // The shim
  axmir_op_size: function: Int32; cdecl;
  axmir_set_error_handler: procedure(Handler: TAxMirErrorHandler); cdecl;
  axmir_init: function(OptimizeLevel: UInt32): TMirContext; cdecl;
  axmir_finish: procedure(Ctx: TMirContext); cdecl;
  axmir_insn_code: function(Ctx: TMirContext; Name: PAnsiChar): Int32; cdecl;
  axmir_new_reg: function(Ctx: TMirContext; Func: TMirItem; Typ: Int32; Name: PAnsiChar): TMirReg; cdecl;
  axmir_reg: function(Ctx: TMirContext; Func: TMirItem; Name: PAnsiChar): TMirReg; cdecl;
  axmir_new_insn: function(Ctx: TMirContext; Code: Int32; NOps: NativeUInt; Ops: PAxMirOp): TMirInsn; cdecl;
  axmir_link: procedure(Ctx: TMirContext); cdecl;
  axmir_func_addr: function(Func: TMirItem): Pointer; cdecl;
  axmir_dump: procedure(Ctx: TMirContext); cdecl;
  // MIR itself
  MIR_new_module: function(Ctx: TMirContext; Name: PAnsiChar): TMirModule; cdecl;
  MIR_finish_module: procedure(Ctx: TMirContext); cdecl;
  MIR_new_func_arr: function(Ctx: TMirContext; Name: PAnsiChar; NRes: NativeUInt;
    ResTypes: PInteger; NArgs: NativeUInt; Vars: PMirVar): TMirItem; cdecl;
  MIR_new_proto_arr: function(Ctx: TMirContext; Name: PAnsiChar; NRes: NativeUInt;
    ResTypes: PInteger; NArgs: NativeUInt; Vars: PMirVar): TMirItem; cdecl;
  MIR_new_import: function(Ctx: TMirContext; Name: PAnsiChar): TMirItem; cdecl;
  MIR_new_export: function(Ctx: TMirContext; Name: PAnsiChar): TMirItem; cdecl;
  MIR_new_forward: function(Ctx: TMirContext; Name: PAnsiChar): TMirItem; cdecl;
  MIR_new_label: function(Ctx: TMirContext): TMirInsn; cdecl;
  MIR_append_insn: procedure(Ctx: TMirContext; Func: TMirItem; Insn: TMirInsn); cdecl;
  MIR_finish_func: procedure(Ctx: TMirContext); cdecl;
  MIR_load_module: procedure(Ctx: TMirContext; Module: TMirModule); cdecl;
  MIR_load_external: procedure(Ctx: TMirContext; Name: PAnsiChar; Addr: Pointer); cdecl;

{ True when the library is loaded and every symbol bound; otherwise MirError
  says why. }
function MirAvailable: Boolean;
function MirError: string;

{ The code of a MIR instruction by its name in MIR's text form ("add",
  "dadd", "bgt", "ret" …). Raises EMirError for an unknown name. }
function MirCode(Ctx: TMirContext; const Name: AnsiString): Int32;

{ Operands. }
function RegOp(R: TMirReg): TAxMirOp;
function IntOp(V: Int64): TAxMirOp;
function DoubleOp(V: Double): TAxMirOp;
function RefOp(Item: TMirItem): TAxMirOp;
function LabelOp(L: TMirInsn): TAxMirOp;
function MemOp(Typ: Int32; Disp: Int64; Base: TMirReg; Index: TMirReg = 0; Scale: UInt32 = 1): TAxMirOp;

{ Builds an instruction and appends it to Func. }
procedure Emit(Ctx: TMirContext; Func: TMirItem; Code: Int32; const Ops: array of TAxMirOp);

type
  EMirError = class(Exception);

implementation

uses
  System.Generics.Collections,
  Axon.Platform;

var
  Handle: NativeUInt;
  Tried, Bound: Boolean;
  LoadError: string;
  Codes: TDictionary<AnsiString, Int32>;

function MirAvailable: Boolean;

  function Bind(var P; const Name: string): Boolean;
  begin
    Pointer(P) := NativeSymbol(Handle, Name);
    Result := Pointer(P) <> nil;
    if not Result and (LoadError = '') then
      LoadError := Format('%s lacks %s', [LibraryName, Name]);
  end;

begin
  if not Tried then
  begin
    Tried := True;
    Handle := LoadNativeLibrary(ExtractFilePath(ParamStr(0)) + LibraryName);
    if Handle = 0 then
      Handle := LoadNativeLibrary(LibraryName);
    if Handle = 0 then
      LoadError := Format('cannot load %s', [LibraryName])
    else
    begin
      Bound :=
        Bind(axmir_op_size, 'axmir_op_size') and
        Bind(axmir_set_error_handler, 'axmir_set_error_handler') and
        Bind(axmir_init, 'axmir_init') and
        Bind(axmir_finish, 'axmir_finish') and
        Bind(axmir_insn_code, 'axmir_insn_code') and
        Bind(axmir_new_reg, 'axmir_new_reg') and
        Bind(axmir_reg, 'axmir_reg') and
        Bind(axmir_new_insn, 'axmir_new_insn') and
        Bind(axmir_link, 'axmir_link') and
        Bind(axmir_func_addr, 'axmir_func_addr') and
        Bind(axmir_dump, 'axmir_dump') and
        Bind(MIR_new_module, 'MIR_new_module') and
        Bind(MIR_finish_module, 'MIR_finish_module') and
        Bind(MIR_new_func_arr, 'MIR_new_func_arr') and
        Bind(MIR_new_proto_arr, 'MIR_new_proto_arr') and
        Bind(MIR_new_import, 'MIR_new_import') and
        Bind(MIR_new_export, 'MIR_new_export') and
        Bind(MIR_new_forward, 'MIR_new_forward') and
        Bind(MIR_new_label, 'MIR_new_label') and
        Bind(MIR_append_insn, 'MIR_append_insn') and
        Bind(MIR_finish_func, 'MIR_finish_func') and
        Bind(MIR_load_module, 'MIR_load_module') and
        Bind(MIR_load_external, 'MIR_load_external');
      if Bound and (axmir_op_size() <> SizeOf(TAxMirOp)) then
      begin
        Bound := False;
        LoadError := Format('%s has an axmir_op of %d bytes; Axon expects %d',
          [LibraryName, axmir_op_size(), SizeOf(TAxMirOp)]);
      end;
    end;
  end;
  Result := Bound;
end;

function MirError: string;
begin
  MirAvailable;
  Result := LoadError;
end;

function MirCode(Ctx: TMirContext; const Name: AnsiString): Int32;
begin
  if Codes = nil then
    Codes := TDictionary<AnsiString, Int32>.Create;
  if not Codes.TryGetValue(Name, Result) then
  begin
    Result := axmir_insn_code(Ctx, PAnsiChar(Name));
    if Result < 0 then
      raise EMirError.CreateFmt('MIR has no instruction "%s"', [string(Name)]);
    Codes.Add(Name, Result);
  end;
end;

function BlankOp(Kind: Int32): TAxMirOp;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Kind := Kind;
end;

function RegOp(R: TMirReg): TAxMirOp;
begin
  Result := BlankOp(AXOP_REG);
  Result.Reg := R;
end;

function IntOp(V: Int64): TAxMirOp;
begin
  Result := BlankOp(AXOP_INT);
  Result.I := V;
end;

function DoubleOp(V: Double): TAxMirOp;
begin
  Result := BlankOp(AXOP_DOUBLE);
  Result.D := V;
end;

function RefOp(Item: TMirItem): TAxMirOp;
begin
  Result := BlankOp(AXOP_REF);
  Result.P := Item;
end;

function LabelOp(L: TMirInsn): TAxMirOp;
begin
  Result := BlankOp(AXOP_LABEL);
  Result.P := L;
end;

function MemOp(Typ: Int32; Disp: Int64; Base: TMirReg; Index: TMirReg; Scale: UInt32): TAxMirOp;
begin
  Result := BlankOp(AXOP_MEM);
  Result.Typ := Typ;
  Result.I := Disp;
  Result.Reg := Base;
  Result.Index := Index;
  Result.Scale := Scale;
end;

procedure Emit(Ctx: TMirContext; Func: TMirItem; Code: Int32; const Ops: array of TAxMirOp);
var
  P: PAxMirOp;
begin
  if Length(Ops) = 0 then
    P := nil
  else
    P := @Ops[0];
  MIR_append_insn(Ctx, Func, axmir_new_insn(Ctx, Code, Length(Ops), P));
end;

initialization

finalization
  Codes.Free;

end.
