unit Axon.Ffi;

(* The foreign function interface (reference, "Foreign functions").

   extern declarations become TExternFuncObj values. A call converts each
   argument to its declared C type, calls the native function through
   System.Rtti.Invoke (Delphi's own implementation of the platform calling
   conventions, so no libffi), and converts the result back.

   - ref T: the value goes into a temporary; after the call the temporary is
     converted back and returned in RefOut for the interpreter to assign.
   - ptr T: an array's own buffer is passed for float64, complex and int64
     (the interpreter makes a variable's array unique first); other widths go
     through a temporary buffer that is copied back after the call.
   - cstring: a UTF-8 copy that lives for the duration of the call.
   - callback: a trampoline from Axon.Native.Callbacks bound to the Axon
     function, released when the call returns unless the function was kept.

   An error raised inside a callback, and a callback fault (called late or
   from another thread), is held as the pending error and raised once the
   outer native call returns. *)

interface

uses
  System.SysUtils, System.Generics.Collections,
  Axon.Ast, Axon.Values;

type
  TCKind = (ckInt8, ckInt16, ckInt32, ckInt64, ckUInt8, ckUInt16, ckUInt32,
    ckUInt64, ckFloat32, ckFloat64, ckChar, ckCString, ckVoid, ckComplex,
    ckRef, ckPtr, ckCallback);

  { A resolved C type. Instances live for the whole run. }
  TCDesc = class
  public
    Kind: TCKind;
    Text: string;                   // as written, for messages
    Inner: TCDesc;                  // ref, ptr
    Params: TArray<TCDesc>;         // callback
    ParamNames: TArray<string>;
    ResultType: TCDesc;             // callback; nil for void
  end;

  TCTypeAliases = TDictionary<string, TCDesc>;

  TExternFuncObj = class(TCallableObj)
  public
    LibName: string;
    Symbol: string;
    BaseDir: string;                // directory of the declaring file
    Params: TArray<TCDesc>;
    ParamNames: TArray<string>;
    ResultType: TCDesc;             // nil for void
    Address: Pointer;               // resolved at the first call
  end;

  { Calls an Axon function value with arguments; used to run callbacks. }
  TAxonInvoker = reference to function(const Fn: TAxValue; const Args: TAxValues): TAxValue;

{ Resolves a C type from the syntax tree, with named callback types from
  Aliases. Raises TypeError for an unknown or unsupported type. }
function ResolveCType(T: TCType; Aliases: TCTypeAliases; const Context: string): TCDesc;
function ExternFunctionValue(Item: TExternFunc; const LibName, BaseDir: string;
  Aliases: TCTypeAliases): TAxValue;

{ Calls F. Args holds one value per parameter; for ref parameters RefOut
  receives the new value (nothing elsewhere). }
function CallExtern(F: TExternFuncObj; const Args: TAxValues; out RefOut: TAxValues;
  const Invoker: TAxonInvoker): TAxValue;

{ keep(f): f's callback trampolines outlive the extern call. Returns f. }
function KeepCallback(const F: TAxValue): TAxValue;

function PointerValue(P: Pointer): TAxValue;

implementation

uses
  System.Rtti, System.TypInfo, System.SyncObjs,
  Axon.Errors, Axon.Ops, Axon.Complex, Axon.Platform, Axon.Packages,
  Axon.Native.Callbacks, Axon.Native.Blas;

var
  AllDescs: TObjectList<TCDesc>;
  Libraries: TDictionary<string, NativeUInt>;
  KeptFunctions: TDictionary<Pointer, TAxValue>;       // function object -> value (kept alive)
  KeptSlots: TDictionary<string, Integer>;             // function + signature -> slot
  PendingLock: TCriticalSection;
  PendingError: Exception;

function NewDesc(Kind: TCKind; const Text: string): TCDesc;
begin
  Result := TCDesc.Create;
  Result.Kind := Kind;
  Result.Text := Text;
  AllDescs.Add(Result);
end;

function PointerValue(P: Pointer): TAxValue;
begin
  if P = nil then
    Exit(NothingValue);
  Result := NothingValue;
  Result.Kind := vkPointer;
  Result.I := Int64(NativeUInt(P));
end;

{ ---------------- type resolution ---------------- }

function IsScalarNumeric(D: TCDesc): Boolean;
begin
  Result := D.Kind in [ckInt8..ckFloat64, ckChar];
end;

function ResolveCType(T: TCType; Aliases: TCTypeAliases; const Context: string): TCDesc;
var
  N: string;
  P: TCParam;
  Inner: TCDesc;
begin
  case T.Kind of
    ctNamed:
      begin
        N := T.Name;
        if N = 'int8' then Result := NewDesc(ckInt8, N)
        else if N = 'int16' then Result := NewDesc(ckInt16, N)
        else if N = 'int32' then Result := NewDesc(ckInt32, N)
        else if N = 'int64' then Result := NewDesc(ckInt64, N)
        else if N = 'uint8' then Result := NewDesc(ckUInt8, N)
        else if N = 'uint16' then Result := NewDesc(ckUInt16, N)
        else if N = 'uint32' then Result := NewDesc(ckUInt32, N)
        else if N = 'uint64' then Result := NewDesc(ckUInt64, N)
        else if N = 'float32' then Result := NewDesc(ckFloat32, N)
        else if N = 'float64' then Result := NewDesc(ckFloat64, N)
        else if N = 'char' then Result := NewDesc(ckChar, N)
        else if N = 'cstring' then Result := NewDesc(ckCString, N)
        else if N = 'void' then Result := NewDesc(ckVoid, N)
        else if N = 'complex' then Result := NewDesc(ckComplex, N)
        else if N = 'clong' then
        begin
          // C long: 32 bits on Windows (LLP64), 64 bits elsewhere (LP64).
{$IFDEF MSWINDOWS}
          Result := NewDesc(ckInt32, N);
{$ELSE}
          Result := NewDesc(ckInt64, N);
{$ENDIF}
        end
        else if N = 'csize' then Result := NewDesc(ckUInt64, N)
        else if (Aliases <> nil) and Aliases.TryGetValue(N, Result) then
          Exit
        else
        begin
          RaiseFmt(TypeError, '%s: unknown C type "%s"', [Context, N]);
          Result := nil;
        end;
      end;
    ctRef, ctPtr:
      begin
        Inner := ResolveCType(T.Inner, Aliases, Context);
        if T.Kind = ctRef then
        begin
          // ref ptr T is a C out-parameter such as void**.
          if not (IsScalarNumeric(Inner) or (Inner.Kind = ckPtr)) then
            RaiseFmt(TypeError, '%s: ref needs a number or pointer type, got %s', [Context, Inner.Text]);
          Result := NewDesc(ckRef, 'ref ' + Inner.Text);
        end
        else
          Result := NewDesc(ckPtr, 'ptr ' + Inner.Text);
        Result.Inner := Inner;
      end;
  else
    begin
      Result := NewDesc(ckCallback, 'callback');
      for P in T.Params do
      begin
        Inner := ResolveCType(P.CType, Aliases, Context);
        if Inner.Kind in [ckVoid, ckComplex, ckCallback] then
          RaiseFmt(TypeError, '%s: a callback parameter cannot be %s', [Context, Inner.Text]);
        Result.Params := Result.Params + [Inner];
        Result.ParamNames := Result.ParamNames + [P.Name];
      end;
      if T.ResultType <> nil then
      begin
        Result.ResultType := ResolveCType(T.ResultType, Aliases, Context);
        if Result.ResultType.Kind in [ckVoid, ckComplex, ckCallback, ckCString, ckRef] then
          RaiseFmt(TypeError, '%s: a callback cannot return %s', [Context, Result.ResultType.Text]);
      end;
    end;
  end;
end;

function ExternFunctionValue(Item: TExternFunc; const LibName, BaseDir: string;
  Aliases: TCTypeAliases): TAxValue;
var
  F: TExternFuncObj;
  P: TCParam;
  D: TCDesc;
  Ctx: string;
begin
  F := TExternFuncObj.Create;
  Result := NothingValue;
  Result.Kind := vkExtern;
  Result.Obj := F;
  F.Name := Item.Name;
  F.LibName := LibName;
  F.BaseDir := BaseDir;
  if Item.Symbol <> '' then F.Symbol := Item.Symbol else F.Symbol := Item.Name;
  Ctx := Format('extern function %s', [Item.Name]);
  for P in Item.Params do
  begin
    D := ResolveCType(P.CType, Aliases, Ctx);
    if D.Kind in [ckVoid, ckComplex] then
      RaiseFmt(TypeError, '%s: parameter "%s" cannot be %s by value (use ptr %s)',
        [Ctx, P.Name, D.Text, D.Text]);
    F.Params := F.Params + [D];
    F.ParamNames := F.ParamNames + [P.Name];
  end;
  if Item.ResultType <> nil then
  begin
    F.ResultType := ResolveCType(Item.ResultType, Aliases, Ctx);
    if F.ResultType.Kind in [ckComplex, ckRef, ckCallback] then
      RaiseFmt(TypeError, '%s: cannot return %s', [Ctx, F.ResultType.Text]);
    if F.ResultType.Kind = ckVoid then
      F.ResultType := nil;
  end;
end;

{ ---------------- library loading ---------------- }

procedure ResolveAddress(F: TExternFuncObj);
var
  Manifest: TManifest;
  Candidates: TArray<string>;
  C, Tried: string;
  H: NativeUInt;
begin
  if F.Address <> nil then
    Exit;
  Manifest := FindManifest(F.BaseDir);
  Candidates := nil;
  if Manifest <> nil then
  begin
    C := Manifest.NativePath(F.LibName);
    if C <> '' then
    begin
      Candidates := [C];
      // An entry naming no file next to the manifest is a system library,
      // looked up by its file name (msvcrt.dll, libSystem.B.dylib).
      if not FileExists(C) then
        Candidates := Candidates + [ExtractFileName(C)];
    end;
  end;
  if Candidates = nil then
  begin
{$IFDEF MSWINDOWS}
    Candidates := [F.LibName, F.LibName + '.dll'];
{$ENDIF}
{$IFDEF MACOS}
    Candidates := [F.LibName, 'lib' + F.LibName + '.dylib', F.LibName + '.dylib'];
{$ENDIF}
{$IFDEF LINUX}
    Candidates := [F.LibName, 'lib' + F.LibName + '.so'];
{$ENDIF}
  end;
{$IFDEF POSIX}
  // dlopen does not search the executable's folder, which Windows' LoadLibrary
  // does first; libraries shipped next to axon (libopenblas.dylib in the IDE's
  // app bundle) are found there before the system search path.
  for C in Copy(Candidates) do
    if (ExtractFilePath(C) = '') and FileExists(ExtractFilePath(ParamStr(0)) + C) then
      Candidates := [ExtractFilePath(ParamStr(0)) + C] + Candidates;
{$ENDIF}
  H := 0;
  Tried := '';
  for C in Candidates do
  begin
    if Libraries.TryGetValue(C, H) then
      Break;
    H := LoadNativeLibrary(C);
    if H <> 0 then
    begin
      Libraries.Add(C, H);
      ConfigureOpenBlas(H);   // OpenBLAS's thread count, if it is OpenBLAS
      Break;
    end;
    if Tried <> '' then Tried := Tried + ', ';
    Tried := Tried + DisplayPath(C);
  end;
  if H = 0 then
    RaiseFmt(ForeignError, 'cannot load native library "%s" (tried %s)', [F.LibName, Tried]);
  F.Address := NativeSymbol(H, F.Symbol);
  if F.Address = nil then
    RaiseFmt(ForeignError, 'native library "%s" has no symbol "%s"', [F.LibName, F.Symbol]);
end;

{ ---------------- conversions ---------------- }

function IntRange(Kind: TCKind; out Lo, Hi: Int64): Boolean;
begin
  Result := True;
  case Kind of
    ckInt8, ckChar: begin Lo := -128; Hi := 127; end;
    ckInt16:  begin Lo := -32768; Hi := 32767; end;
    ckInt32:  begin Lo := -2147483648; Hi := 2147483647; end;
    ckInt64:  begin Lo := Low(Int64); Hi := High(Int64); end;
    ckUInt8:  begin Lo := 0; Hi := 255; end;
    ckUInt16: begin Lo := 0; Hi := 65535; end;
    ckUInt32: begin Lo := 0; Hi := 4294967295; end;
    ckUInt64: begin Lo := 0; Hi := High(Int64); end;
  else
    Result := False;
  end;
end;

{ An Axon value as a C integer of the given kind. }
function ToCInt(const V: TAxValue; D: TCDesc; const What: string): Int64;
var
  Lo, Hi: Int64;
  S: string;
begin
  IntRange(D.Kind, Lo, Hi);
  if (D.Kind = ckChar) and (V.Kind = vkString) then
  begin
    S := AsString(V);
    if (Length(S) <> 1) or (Ord(S[1]) > 127) then
      RaiseFmt(TypeError, '%s: a char must be one ASCII character, got "%s"', [What, S]);
    Exit(Ord(S[1]));
  end;
  case V.Kind of
    vkBool: Result := Ord(V.B);
    vkInt:  Result := V.I;
  else
    RaiseFmt(TypeError, '%s: %s does not fit %s', [What, Display(V, True), D.Text]);
    Result := 0;
  end;
  if (Result < Lo) or (Result > Hi) then
    RaiseFmt(TypeError, '%s: %d does not fit %s', [What, Result, D.Text]);
end;

function ToCFloat(const V: TAxValue; D: TCDesc; const What: string): Double;
begin
  if not (V.Kind in [vkBool, vkInt, vkReal]) then
    RaiseFmt(TypeError, '%s: %s does not fit %s', [What, Display(V, True), D.Text]);
  Result := ToReal(V);
end;

{ Raw 64-bit register contents (as passed to a callback) to an Axon value. }
function RawToValue(Raw: UInt64; D: TCDesc): TAxValue;
var
  F32: Single;
  F64: Double;
begin
  case D.Kind of
    ckPtr:    Result := PointerValue(Pointer(NativeUInt(Raw)));
    ckInt8, ckChar: Result := IntValue(ShortInt(Byte(Raw)));
    ckInt16:  Result := IntValue(SmallInt(Word(Raw)));
    ckInt32:  Result := IntValue(Integer(Cardinal(Raw)));
    ckInt64:  Result := IntValue(Int64(Raw));
    ckUInt8:  Result := IntValue(Byte(Raw));
    ckUInt16: Result := IntValue(Word(Raw));
    ckUInt32: Result := IntValue(Cardinal(Raw));
    ckUInt64:
      begin
        if Raw > UInt64(High(Int64)) then
          RaiseError(OverflowError, 'a uint64 value is outside the int range');
        Result := IntValue(Int64(Raw));
      end;
    ckFloat32:
      begin
        Move(Raw, F32, SizeOf(F32));
        Result := RealValue(F32);
      end;
    ckFloat64:
      begin
        Move(Raw, F64, SizeOf(F64));
        Result := RealValue(F64);
      end;
    ckCString:
      if Raw = 0 then
        Result := NothingValue
      else
        Result := StringValue(UTF8ToString(PAnsiChar(NativeUInt(Raw))));
  else
    Result := PointerValue(Pointer(NativeUInt(Raw)));
  end;
end;

{ An Axon value to raw 64-bit register contents (a callback's result). }
function ValueToRaw(const V: TAxValue; D: TCDesc; const What: string): UInt64;
var
  F32: Single;
  F64: Double;
begin
  Result := 0;
  case D.Kind of
    ckInt8..ckUInt64, ckChar:
      Result := UInt64(ToCInt(V, D, What));
    ckFloat32:
      begin
        F32 := ToCFloat(V, D, What);
        Move(F32, Result, SizeOf(F32));
      end;
    ckFloat64:
      begin
        F64 := ToCFloat(V, D, What);
        Move(F64, Result, SizeOf(F64));
      end;
    ckPtr:
      case V.Kind of
        vkNothing: Result := 0;
        vkPointer: Result := UInt64(V.I);
      else
        RaiseFmt(TypeError, '%s: a callback can return a pointer or nothing, got %s',
          [What, TypeName(V)]);
      end;
  else
    RaiseFmt(TypeError, '%s: unsupported callback result %s', [What, D.Text]);
  end;
end;

function ArgClass(D: TCDesc): TArgClass;
begin
  case D.Kind of
    ckFloat32: Result := acFloat32;
    ckFloat64: Result := acFloat64;
  else
    Result := acInt;
  end;
end;

function RetKindOf(D: TCDesc): TRetKind;
begin
  if D = nil then Exit(rtInt);
  case D.Kind of
    ckFloat32: Result := rtFloat32;
    ckFloat64: Result := rtFloat64;
  else
    Result := rtInt;
  end;
end;

{ ---------------- pending errors from callbacks ---------------- }

procedure SetPending(E: Exception);
begin
  PendingLock.Enter;
  try
    if PendingError = nil then
      PendingError := E
    else
      E.Free;   // the first error wins
  finally
    PendingLock.Leave;
  end;
end;

function TakePending: Exception;
begin
  PendingLock.Enter;
  try
    Result := PendingError;
    PendingError := nil;
  finally
    PendingLock.Leave;
  end;
end;

{ ---------------- callbacks ---------------- }

function MakeHandler(const Fn: TAxValue; D: TCDesc; const Invoker: TAxonInvoker): TCallbackHandler;
begin
  Result :=
    function(const Raw: TRawArgs): UInt64
    var
      Args: TAxValues;
      K: Integer;
      R: TAxValue;
    begin
      Result := 0;
      try
        SetLength(Args, Length(D.Params));
        for K := 0 to High(D.Params) do
          Args[K] := RawToValue(Raw[K], D.Params[K]);
        R := Invoker(Fn, Args);
        if D.ResultType <> nil then
          Result := ValueToRaw(R, D.ResultType, 'the result of a callback');
      except
        // Held and re-raised once the outer native call returns.
        SetPending(Exception(AcquireExceptionObject));
        Result := 0;
      end;
    end;
end;

function SignatureKey(const Fn: TAxValue; D: TCDesc): string;
begin
  Result := Format('%p/%p', [Pointer(Fn.Obj), Pointer(D)]);
end;

function KeepCallback(const F: TAxValue): TAxValue;
begin
  if not (F.Kind in [vkFunction, vkBuiltin, vkExtern]) then
    RaiseFmt(TypeError, 'keep needs a function, got %s', [TypeName(F)]);
  KeptFunctions.AddOrSetValue(Pointer(F.Obj), F);
  Result := F;
end;

{ A trampoline for callback parameter D running Fn. Kept functions reuse one
  permanent slot per signature; others are listed in Temp for release. }
function CallbackFor(const Fn: TAxValue; D: TCDesc; const Invoker: TAxonInvoker;
  Temp: TList<Integer>; const What: string): Pointer;
var
  Classes: TArray<TArgClass>;
  K, Slot: Integer;
  Key: string;
  Kept: Boolean;
begin
  if not (Fn.Kind in [vkFunction, vkBuiltin]) then
    RaiseFmt(TypeError, '%s: a callback needs an Axon function, got %s', [What, TypeName(Fn)]);
  Kept := KeptFunctions.ContainsKey(Pointer(Fn.Obj));
  Key := SignatureKey(Fn, D);
  if Kept and KeptSlots.TryGetValue(Key, Slot) then
    Exit(CallbackAddress(Slot));
  SetLength(Classes, Length(D.Params));
  for K := 0 to High(D.Params) do
    Classes[K] := ArgClass(D.Params[K]);
  Slot := AllocateCallback(Classes, RetKindOf(D.ResultType), MakeHandler(Fn, D, Invoker));
  if Kept then
    KeptSlots.Add(Key, Slot)
  else
    Temp.Add(Slot);
  Result := CallbackAddress(Slot);
end;

{ ---------------- calls ---------------- }

type
  { A ptr argument passed through a temporary buffer of another width. }
  TWidthBuffer = record
    Arr: TArrayObj;
    Kind: TCKind;
    Data: TBytes;
  end;

function TypeInfoFor(D: TCDesc): PTypeInfo;
begin
  if D = nil then Exit(nil);
  case D.Kind of
    ckInt8, ckChar: Result := TypeInfo(ShortInt);
    ckInt16:  Result := TypeInfo(SmallInt);
    ckInt32:  Result := TypeInfo(Integer);
    ckInt64:  Result := TypeInfo(Int64);
    ckUInt8:  Result := TypeInfo(Byte);
    ckUInt16: Result := TypeInfo(Word);
    ckUInt32: Result := TypeInfo(Cardinal);
    ckUInt64: Result := TypeInfo(UInt64);
    ckFloat32: Result := TypeInfo(Single);
    ckFloat64: Result := TypeInfo(Double);
  else
    Result := TypeInfo(Pointer);
  end;
end;

function IntToTValue(X: Int64; Kind: TCKind): TValue;
begin
  case Kind of
    ckInt8, ckChar: Result := TValue.From<ShortInt>(ShortInt(X));
    ckInt16:  Result := TValue.From<SmallInt>(SmallInt(X));
    ckInt32:  Result := TValue.From<Integer>(Integer(X));
    ckInt64:  Result := TValue.From<Int64>(X);
    ckUInt8:  Result := TValue.From<Byte>(Byte(X));
    ckUInt16: Result := TValue.From<Word>(Word(X));
    ckUInt32: Result := TValue.From<Cardinal>(Cardinal(X));
  else
    Result := TValue.From<UInt64>(UInt64(X));
  end;
end;

function ElementSize(Kind: TCKind): Integer;
begin
  case Kind of
    ckInt8, ckUInt8, ckChar: Result := 1;
    ckInt16, ckUInt16: Result := 2;
    ckInt32, ckUInt32, ckFloat32: Result := 4;
  else
    Result := 8;
  end;
end;

{ The pointer passed for a ptr parameter. }
function PtrArgument(const V: TAxValue; D: TCDesc; const What: string;
  Buffers: TList<TWidthBuffer>): Pointer;
var
  A: TArrayObj;
  Inner: TCKind;
  WB: TWidthBuffer;
  K, Sz: Integer;
  X: Int64;
  F32: Single;
  ElemDesc: TCDesc;

  procedure Mismatch;
  begin
    RaiseFmt(TypeError, '%s: %s needs %s, got %s{%s}', [What, D.Text,
      'a matching array', TypeName(V), ElemTypeName(A.ElemType)]);
  end;

begin
  case V.Kind of
    vkNothing: Exit(nil);
    vkPointer: Exit(Pointer(NativeUInt(V.I)));
    vkArray: ;
  else
    RaiseFmt(TypeError, '%s: %s needs an array, a pointer or nothing, got %s',
      [What, D.Text, TypeName(V)]);
  end;
  A := AsArray(V);
  Inner := D.Inner.Kind;
  if A.Count = 0 then
    Exit(nil);
  case Inner of
    ckVoid:
      case A.ElemType of
        etBool:    Result := @A.B[0];
        etInt:     Result := @A.I[0];
        etReal:    Result := @A.R[0];
      else
        Result := @A.C[0];
      end;
    ckFloat64:
      begin
        if A.ElemType <> etReal then Mismatch;
        Result := @A.R[0];
      end;
    ckComplex:
      begin
        if A.ElemType <> etComplex then Mismatch;
        Result := @A.C[0];
      end;
    ckInt64:
      begin
        if A.ElemType <> etInt then Mismatch;
        Result := @A.I[0];
      end;
    ckInt8, ckInt16, ckInt32, ckUInt8, ckUInt16, ckUInt32, ckUInt64, ckChar:
      begin
        if A.ElemType <> etInt then Mismatch;
        // A temporary buffer of the C width, copied back after the call.
        ElemDesc := D.Inner;
        Sz := ElementSize(Inner);
        WB.Arr := A;
        WB.Kind := Inner;
        SetLength(WB.Data, A.Count * Sz);
        for K := 0 to A.Count - 1 do
        begin
          X := ToCInt(IntValue(A.I[K]), ElemDesc, What);
          Move(X, WB.Data[K * Sz], Sz);   // little-endian: the low bytes
        end;
        Buffers.Add(WB);
        Result := @WB.Data[0];
      end;
    ckFloat32:
      begin
        if A.ElemType <> etReal then Mismatch;
        WB.Arr := A;
        WB.Kind := ckFloat32;
        SetLength(WB.Data, A.Count * 4);
        for K := 0 to A.Count - 1 do
        begin
          F32 := A.R[K];
          Move(F32, WB.Data[K * 4], 4);
        end;
        Buffers.Add(WB);
        Result := @WB.Data[0];
      end;
  else
    RaiseFmt(TypeError, '%s: %s cannot take an array', [What, D.Text]);
    Result := nil;
  end;
end;

procedure CopyBack(const WB: TWidthBuffer);
var
  K, Sz: Integer;
  Raw: UInt64;
  F32: Single;
  D: TCDesc;
begin
  if WB.Kind = ckFloat32 then
  begin
    for K := 0 to WB.Arr.Count - 1 do
    begin
      Move(WB.Data[K * 4], F32, 4);
      WB.Arr.R[K] := F32;
    end;
    Exit;
  end;
  Sz := ElementSize(WB.Kind);
  D := TCDesc.Create;
  try
    D.Kind := WB.Kind;
    for K := 0 to WB.Arr.Count - 1 do
    begin
      Raw := 0;
      Move(WB.Data[K * Sz], Raw, Sz);
      WB.Arr.I[K] := RawToValue(Raw, D).I;
    end;
  finally
    D.Free;
  end;
end;

function CallExtern(F: TExternFuncObj; const Args: TAxValues; out RefOut: TAxValues;
  const Invoker: TAxonInvoker): TAxValue;
var
  TV: TArray<TValue>;
  RefStore: TArray<UInt64>;
  Strings: TList<TBytes>;
  Buffers: TList<TWidthBuffer>;
  Slots: TList<Integer>;
  K, N: Integer;
  D: TCDesc;
  What: string;
  Bytes: TBytes;
  X: Int64;
  F64: Double;
  F32: Single;
  R: TValue;
  Saved, Err: Exception;
  WB: TWidthBuffer;
  Slot: Integer;
  P: Pointer;
begin
  ResolveAddress(F);
  N := Length(F.Params);
  SetLength(TV, N);
  SetLength(RefStore, N);
  SetLength(RefOut, N);
  Strings := TList<TBytes>.Create;
  Buffers := TList<TWidthBuffer>.Create;
  Slots := TList<Integer>.Create;
  try
    for K := 0 to N - 1 do
    begin
      D := F.Params[K];
      What := Format('argument "%s" of %s', [F.ParamNames[K], F.Name]);
      RefOut[K] := NothingValue;
      case D.Kind of
        ckInt8..ckUInt64, ckChar:
          TV[K] := IntToTValue(ToCInt(Args[K], D, What), D.Kind);
        ckFloat32:
          TV[K] := TValue.From<Single>(ToCFloat(Args[K], D, What));
        ckFloat64:
          TV[K] := TValue.From<Double>(ToCFloat(Args[K], D, What));
        ckCString:
          if Args[K].Kind = vkNothing then
            TV[K] := TValue.From<Pointer>(nil)
          else if Args[K].Kind = vkString then
          begin
            Bytes := TEncoding.UTF8.GetBytes(AsString(Args[K])) + [0];
            Strings.Add(Bytes);
            TV[K] := TValue.From<Pointer>(@Bytes[0]);
          end
          else
            RaiseFmt(TypeError, '%s: cstring needs a string, got %s', [What, TypeName(Args[K])]);
        ckRef:
          begin
            // A temporary holding the converted value; read back after the call.
            RefStore[K] := 0;
            case D.Inner.Kind of
              ckPtr:
                case Args[K].Kind of
                  vkNothing: ;
                  vkPointer: RefStore[K] := UInt64(Args[K].I);
                else
                  RaiseFmt(TypeError, '%s: %s needs a pointer or nothing, got %s',
                    [What, D.Text, TypeName(Args[K])]);
                end;
              ckFloat64:
                begin
                  F64 := ToCFloat(Args[K], D.Inner, What);
                  Move(F64, RefStore[K], 8);
                end;
              ckFloat32:
                begin
                  F32 := ToCFloat(Args[K], D.Inner, What);
                  Move(F32, RefStore[K], 4);
                end;
            else
              begin
                X := ToCInt(Args[K], D.Inner, What);
                Move(X, RefStore[K], ElementSize(D.Inner.Kind));
              end;
            end;
            TV[K] := TValue.From<Pointer>(@RefStore[K]);
          end;
        ckPtr:
          TV[K] := TValue.From<Pointer>(PtrArgument(Args[K], D, What, Buffers));
        ckCallback:
          if Args[K].Kind = vkNothing then
            TV[K] := TValue.From<Pointer>(nil)
          else
            TV[K] := TValue.From<Pointer>(CallbackFor(Args[K], D, Invoker, Slots, What));
      end;
    end;

    // Callback errors from an outer call stay aside while this call runs.
    Saved := TakePending;
    try
      try
        R := Invoke(F.Address, TV, ccCdecl, TypeInfoFor(F.ResultType));
      finally
        for Slot in Slots do
          ReleaseCallback(Slot);
      end;
      Err := TakePending;
    finally
      if Saved <> nil then
        SetPending(Saved);
    end;

    for WB in Buffers do
      CopyBack(WB);
    for K := 0 to N - 1 do
      if F.Params[K].Kind = ckRef then
        RefOut[K] := RawToValue(RefStore[K], F.Params[K].Inner);

    if Err <> nil then
      raise Err;

    if F.ResultType = nil then
      Exit(NothingValue);
    case F.ResultType.Kind of
      ckInt8, ckChar: Result := IntValue(R.AsType<ShortInt>);
      ckInt16:  Result := IntValue(R.AsType<SmallInt>);
      ckInt32:  Result := IntValue(R.AsType<Integer>);
      ckInt64:  Result := IntValue(R.AsType<Int64>);
      ckUInt8:  Result := IntValue(R.AsType<Byte>);
      ckUInt16: Result := IntValue(R.AsType<Word>);
      ckUInt32: Result := IntValue(R.AsType<Cardinal>);
      ckUInt64: Result := RawToValue(R.AsType<UInt64>, F.ResultType);
      ckFloat32: Result := RealValue(R.AsType<Single>);
      ckFloat64: Result := RealValue(R.AsType<Double>);
      ckCString:
        begin
          P := R.AsType<Pointer>;
          if P = nil then Result := NothingValue
          else Result := StringValue(UTF8ToString(PAnsiChar(P)));
        end;
    else
      Result := PointerValue(R.AsType<Pointer>);
    end;
  finally
    Strings.Free;
    Buffers.Free;
    Slots.Free;
  end;
end;

initialization
  AllDescs := TObjectList<TCDesc>.Create;
  Libraries := TDictionary<string, NativeUInt>.Create;
  KeptFunctions := TDictionary<Pointer, TAxValue>.Create;
  KeptSlots := TDictionary<string, Integer>.Create;
  PendingLock := TCriticalSection.Create;
  OnCallbackFault :=
    procedure(const Msg: string)
    begin
      SetPending(EAxonError.Create(ForeignError, Msg));
    end;

finalization
  OnCallbackFault := nil;
  PendingError.Free;
  PendingLock.Free;
  KeptSlots.Free;
  KeptFunctions.Free;
  Libraries.Free;
  AllDescs.Free;

end.
