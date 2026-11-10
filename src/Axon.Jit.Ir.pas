unit Axon.Jit.Ir;

(* JIR: the typed IR between the syntax tree and MIR (doc/Axon-JIT-Plan.md,
   decision D3).

   A function is a linear list of three-address instructions over typed
   virtual registers, with labels and branches, close to MIR's own shape.
   Every register has one static type. Operands are registers or immediates.

   An instruction that can raise an error carries a site: the line and
   column of the innermost statement around it, which is where the
   interpreter locates errors raised without a position. Checked int
   arithmetic (add, sub, mul, neg, pow) raises OverflowError; count raises
   ArgumentError (zero step, NaN bound, too many elements) or OverflowError.
   The same opcode without a site cannot fail (a loop counter, say).

   Dump writes the text form that `axon --jir` prints and the .jir tests
   compare against:

     function harmonic(n: int): real
       var s: real
       var k: int
       s = 0.0
       %0 = count.int 1, 1, n  @3:3
       ...
     L0:
       bt %2, L2

   Opcodes carry the type they work in (add.int, lt.real). Conversions are
   b2i, b2r and i2r. A move prints as `dst = src`.

   A call (J3) has a target describing the callee and any number of result
   registers, and its site is the position of the call expression, where the
   interpreter locates errors from a call:

     %3 = call fib(%2)  @8:10           another compiled function
     %1 = call.builtin sqrt(%0)         a built-in
     call.builtin print("x =", x)  @4:3
     [a, b] = call.interp pair(x)  @6:3 a function that runs interpreted

   Arrays (J4) are vector{real}, vector{int} and matrix{real}. An array
   register holds a value slot (a TAxValue in the call's frame), so arrays
   are reference-counted exactly as the interpreter's variables hold them:

     bound i, %0  @3:12                  IndexError unless 1 <= i <= %0, at the index
     %1 = load.real v, i                 v[i] (or A[i, j]), after its bounds checks
     store.real v, i, x                  v[i] = x (copy-on-write first)
     %3 = len.int v, 0                   0: the element count, 1: rows, 2: cols
     %4 = op.vector{real} .*(v, w)  @6:3 an operator on arrays, by Axon.Ops
     clear %5                            releases a hidden reference

   Captures (J7c): a value the function reads from an enclosing scope or the
   module (a name, or a field path such as p.a) is a hidden parameter after
   the real ones, read when the function is entered. The header lists them
   in brackets:

     function anonymous(t: real, y: vector{real}) [p.a: real, g: real]: vector{real}

   A vector or matrix literal of scalar entries builds an array:

     %3 = array.vector{real} 2, 1 (%1, %2)  rows, columns, then the entries row by row

   Records (J9) are typed by their shape: the field names in order, each
   field's type, and the declared record type, if any. Each shape is entered
   once in a process-wide table and gets its own TJType, from jtFirstRecord
   up, so equal shapes are equal types. A field of a type that does not
   compile is typed jtNothing (shown as "other"): the record compiles, but
   the field cannot be used. A record register is a value slot, as an array
   register is. An instruction can reach into a record through a path of
   field positions, which the text form shows by name:

     %1 = field.real p.k1                p.k1 (any depth: p.a.b)
     setfield.real s.t, %2               s.t = %2 (each record on the path made unique first)
     %3 = load.real s.y, i               s.y[i]: load, store and len take a path too
     %4 = record record{a: real, b: int} (%1, 2)   a record literal or constructor

   Lists (J10) of one element type are list{T}, entered in the same table;
   list{?} is the empty list, whose element type is not known. A list
   register is a value slot. load, store and len work on lists as on
   vectors:

     %5 = list list{real} (%1, 2.5)      a list literal
     l = append l, x, 1                  append; 1: in place when nothing else holds l

   Strings (J11) are values in slots too. A literal is a constant copied in:

     %6 = const "x = "                   a string literal as a value
     %7 = concat %6, s                   a + b
     %8 = strcmp a, b                    -1, 0 or 1, as CompareStr
     %9 = strof k                        string(k) of a bool, int or real
     %10 = strlen s                      length(s), in code points *)

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  Axon.Values;

type
  { jtString only for string literals passed to print and error. The
    array types follow the scalars; record shapes (J9) take the numbers from
    jtFirstRecord up, one per shape (RecordType). }
  TJType = type Word;

const
  jtNothing = TJType(0);
  jtBool = TJType(1);
  jtInt = TJType(2);
  jtReal = TJType(3);
  jtString = TJType(4);
  jtVecReal = TJType(5);
  jtVecInt = TJType(6);
  jtMatReal = TJType(7);
  jtFirstRecord = TJType(16);

type

  TJOperandKind = (jkReg, jkInt, jkReal, jkBool, jkLabel, jkString);

  TJOperand = record
    Kind: TJOperandKind;
    Reg: Integer;      // jkReg
    I: Int64;          // jkInt; jkLabel: the label number
    R: Double;         // jkReal
    B: Boolean;        // jkBool
    S: string;         // jkString
    function IsImm: Boolean;
  end;

  PAxValue = ^TAxValue;

  TJCallKind = (
    ckCompiled,        // a compiled Axon function: a direct call
    ckInterp,          // an Axon function that runs interpreted, called through the interpreter
    ckBuiltin          // a built-in
  );

  { The callee of a call instruction. }
  TJCallTarget = class
  public
    Kind: TJCallKind;
    Name: string;
    Callee: TObject;              // ckCompiled: the callee's TJEntry (Axon.Jit.Lower)
    CalleeId: Integer;            // ckCompiled: the callee's code id, set before generation
    ParamTypes: TArray<TJType>;   // ckCompiled: the callee's parameter types
    ArgTypes: TArray<TJType>;     // the types of the operands passed
    ResultTypes: TArray<TJType>;  // what the call yields (empty when nothing is used)
    Direct: Boolean;              // ckBuiltin: an elementary function called directly
    // Run time: the callee value, and the variable holding it (a guard
    // checks it still holds the function; nil when nothing can rebind it).
    Value: TAxValue;
    ValuePtr: PAxValue;
  end;

  TJOp = (
    joLabel,                      // Ops[0]: the label
    joMov,                        // Dst := Ops[0]
    joB2I, joB2R, joI2R,          // conversions
    joAdd, joSub, joMul, joNeg,   // .int (checked when Site >= 0) or .real
    joDiv,                        // .real only
    joPow,                        // .int: checked, exponent >= 0; .real: interpreter's rule
    joEq, joNe, joLt, joLe, joGt, joGe,   // compare in Typ (int or real); Dst is bool
    joNot,                        // bool
    joJmp,                        // Ops[0]: label
    joBrTrue, joBrFalse,          // Ops[0]: condition, Ops[1]: label
    joCount,                      // Dst := element count of the range Ops[0]:Ops[1]:Ops[2]
    joElem,                       // Dst := Ops[0] + Ops[2] * Ops[1] (start + k*step)
    joRet,                        // Ops: the results
    joCall,                       // Dsts := Target(Ops)
    joLoad,                       // Dst := Ops[0][Ops[1]] or Ops[0][Ops[1], Ops[2]]
    joStore,                      // Ops[0][Ops[1] (, Ops[2])] := last operand
    joLen,                        // Dst := element count (Ops[1] = 0), rows (1) or cols (2) of Ops[0]
    joOp,                         // Dst := Ops.Ops[1] applied to Ops[0] (and Ops[2]) by Axon.Ops; Ops[1] is the token
    joClear,                      // Ops[0] (an array register) := nothing
    joBound,                      // IndexError unless 1 <= Ops[0] <= Ops[1]
    joArray,                      // Dst := a Typ array of Ops[0] rows and Ops[1] columns from Ops[2..] (row by row)
    joField,                      // Dst := the field at Path of the record Ops[0]
    joSetField,                   // the field at Path of the record Ops[0] := Ops[1]
    joRecord,                     // Dst := a record of shape Typ from Ops (its fields in order)
    joList,                       // Dst := a list of type Typ from Ops
    joAppend,                     // Dst := append(Ops[0], Ops[1]); Ops[2] = 1: in place if unique
    joConst,                      // Dst := the string Ops[0] (a jkString operand)
    joConcat,                     // Dst := Ops[0] + Ops[1], two strings
    joStrCmp,                     // Dst (int) := -1, 0 or 1: Ops[0] against Ops[1], as CompareStr
    joStrOf,                      // Dst := string(Ops[0]), a bool, int or real
    joStrLen                      // Dst (int) := length(Ops[0]), a string, in code points
  );

  TJInsn = class
  public
    Op: TJOp;
    Typ: TJType;       // the type the operation works in
    Dst: Integer;      // a register, or -1
    Ops: TArray<TJOperand>;
    Site: Integer;     // index into TJFunction.Sites, or -1 when it cannot fail
    Dsts: TArray<Integer>;        // joCall: result registers (-1 for one not used)
    Target: TJCallTarget;         // joCall
    Site2: Integer;               // joLoad/joStore with two indices: the second index's site
    // J9: field positions from the record Ops[0] (joField, joSetField; and
    // joLoad, joStore and joLen, whose array is then that field).
    Path: TArray<Integer>;
  end;

  TJReg = record
    Name: string;      // '' for a temporary
    Typ: TJType;
    IsParam: Boolean;
  end;

  TJSite = record
    Line, Col: Integer;
  end;

  { A captured value: Path[0] is a name in an enclosing scope or the module,
    the rest field names. }
  TJCapture = record
    Path: TArray<string>;
    Reg: Integer;
    Typ: TJType;
    function Text: string;
  end;

  TJFunction = class
  public
    Name: string;
    Params: TList<Integer>;         // registers, in parameter order
    ResultTypes: TList<TJType>;     // empty for a function returning nothing
    Regs: TList<TJReg>;
    Insns: TObjectList<TJInsn>;
    Sites: TList<TJSite>;
    Targets: TObjectList<TJCallTarget>;   // owned
    Captures: TList<TJCapture>;           // hidden parameters, after the real ones
    LocalNames: TList<string>;            // closures: names a plain assignment creates locally
    LabelCount: Integer;
    constructor Create(const AName: string);
    destructor Destroy; override;
    function NewReg(Typ: TJType; const Name: string = ''; IsParam: Boolean = False): Integer;
    function NewLabel: Integer;
    function AddSite(Line, Col: Integer): Integer;
    function Emit(Op: TJOp; Typ: TJType; Dst: Integer; const Ops: array of TJOperand;
      Site: Integer = -1): TJInsn;
    procedure PlaceLabel(L: Integer);
    procedure Dump(Lines: TStrings);
  end;

function RegOperand(R: Integer): TJOperand;
function IntOperand(V: Int64): TJOperand;
function RealOperand(V: Double): TJOperand;
function BoolOperand(V: Boolean): TJOperand;
function LabelOperand(L: Integer): TJOperand;
function StringOperand(const V: string): TJOperand;

type
  (* A record shape: its fields in order, and the declared type, if any; or
     (IsList) a list type: its element type, jtNothing for list{?}. *)
  TJShape = class
  public
    Names: TArray<string>;
    Types: TArray<TJType>;
    Decl: TRecordTypeObj;       // nil for a record literal's shape
    DeclRef: IInterface;        // keeps the declared type alive
    IsList: Boolean;
    Elem: TJType;
    function IndexOf(const Name: string): Integer;
  end;

function JTypeName(T: TJType): string;
(* As JTypeName, but a record type is only its declared type's name, or its
   field names (record{t, y}), for logs and reports. *)
function ShortTypeName(T: TJType): string;
function IsArrayType(T: TJType): Boolean; inline;
function IsRecordType(T: TJType): Boolean;
function IsListType(T: TJType): Boolean;
(* The element type of a list type; jtNothing for list{?}. *)
function ListElem(T: TJType): TJType;
(* The list type with elements of type Elem (jtNothing: list{?}). *)
function ListType(Elem: TJType): TJType;
{ An array, a record or a list: a value slot in compiled code. }
function IsBoxedType(T: TJType): Boolean;
{ The shape of a record type. }
function ShapeOf(T: TJType): TJShape;
{ The type of a shape, entering it in the table the first time;
  jtNothing when the table is full. }
function RecordType(const Names: TArray<string>; const Types: TArray<TJType>;
  Decl: TRecordTypeObj): TJType;
{ The JIR type of a value; jtNothing for one that does not compile. }
function JTypeOfValue(const V: TAxValue): TJType;
{ Whether V has type T, as JTypeOfValue(V) = T, checked without building a
  shape; a field of T typed jtNothing accepts any value. }
function JTypeMatches(const V: TAxValue; T: TJType): Boolean;
{ The element type of an array type. }
function ElemOf(T: TJType): TJType;

implementation

function TJOperand.IsImm: Boolean;
begin
  Result := Kind in [jkInt, jkReal, jkBool, jkString];
end;

function Blank(Kind: TJOperandKind): TJOperand;
begin
  Result := Default(TJOperand);
  Result.Kind := Kind;
end;

function RegOperand(R: Integer): TJOperand;
begin
  Result := Blank(jkReg);
  Result.Reg := R;
end;

function IntOperand(V: Int64): TJOperand;
begin
  Result := Blank(jkInt);
  Result.I := V;
end;

function RealOperand(V: Double): TJOperand;
begin
  Result := Blank(jkReal);
  Result.R := V;
end;

function BoolOperand(V: Boolean): TJOperand;
begin
  Result := Blank(jkBool);
  Result.B := V;
end;

function StringOperand(const V: string): TJOperand;
begin
  Result := Blank(jkString);
  Result.S := V;
end;

function LabelOperand(L: Integer): TJOperand;
begin
  Result := Blank(jkLabel);
  Result.I := L;
end;

var
  Shapes: TObjectList<TJShape>;
  ShapeIndex: TDictionary<string, Integer>;

function TJShape.IndexOf(const Name: string): Integer;
begin
  for Result := 0 to High(Names) do
    if Names[Result] = Name then
      Exit;
  Result := -1;
end;

function JTypeName(T: TJType): string;
var
  Sh: TJShape;
  K: Integer;
begin
  case T of
    jtNothing: Result := 'nothing';
    jtBool:    Result := 'bool';
    jtInt:     Result := 'int';
    jtReal:    Result := 'real';
    jtString:  Result := 'string';
    jtVecReal: Result := 'vector{real}';
    jtVecInt:  Result := 'vector{int}';
    jtMatReal: Result := 'matrix{real}';
  else
    if IsListType(T) then
    begin
      if ListElem(T) = jtNothing then
        Exit('list{?}');
      Exit('list{' + JTypeName(ListElem(T)) + '}');
    end;
    if not IsRecordType(T) then
      Exit('?');
    Sh := ShapeOf(T);
    if Sh.Decl <> nil then
      Result := Sh.Decl.Name + '{'
    else
      Result := 'record{';
    for K := 0 to High(Sh.Names) do
    begin
      if K > 0 then
        Result := Result + ', ';
      if Sh.Types[K] = jtNothing then
        Result := Result + Sh.Names[K] + ': other'
      else
        Result := Result + Sh.Names[K] + ': ' + JTypeName(Sh.Types[K]);
    end;
    Result := Result + '}';
  end;
end;

function ShortTypeName(T: TJType): string;
var
  Sh: TJShape;
begin
  if IsListType(T) then
  begin
    if ListElem(T) = jtNothing then
      Exit('list{?}');
    Exit('list{' + ShortTypeName(ListElem(T)) + '}');
  end;
  if not IsRecordType(T) then
    Exit(JTypeName(T));
  Sh := ShapeOf(T);
  if Sh.Decl <> nil then
    Result := Sh.Decl.Name
  else
    Result := 'record{' + string.Join(', ', Sh.Names) + '}';
end;

function IsArrayType(T: TJType): Boolean;
begin
  Result := T in [jtVecReal, jtVecInt, jtMatReal];
end;

function IsRecordType(T: TJType): Boolean;
begin
  Result := (T >= jtFirstRecord) and (T - jtFirstRecord < Shapes.Count) and
    not Shapes[T - jtFirstRecord].IsList;
end;

function IsListType(T: TJType): Boolean;
begin
  Result := (T >= jtFirstRecord) and (T - jtFirstRecord < Shapes.Count) and
    Shapes[T - jtFirstRecord].IsList;
end;

function ListElem(T: TJType): TJType;
begin
  Result := Shapes[T - jtFirstRecord].Elem;
end;

function ListType(Elem: TJType): TJType;
var
  Key: string;
  Idx: Integer;
  Sh: TJShape;
begin
  Key := 'list|' + IntToStr(Elem);
  if not ShapeIndex.TryGetValue(Key, Idx) then
  begin
    if Shapes.Count >= High(TJType) - jtFirstRecord then
      Exit(jtNothing);
    Sh := TJShape.Create;
    Sh.IsList := True;
    Sh.Elem := Elem;
    Idx := Shapes.Add(Sh);
    ShapeIndex.Add(Key, Idx);
  end;
  Result := jtFirstRecord + Idx;
end;

function IsBoxedType(T: TJType): Boolean;
begin
  Result := IsArrayType(T) or IsRecordType(T) or IsListType(T) or (T = jtString);
end;

function ShapeOf(T: TJType): TJShape;
begin
  Result := Shapes[T - jtFirstRecord];
end;

function RecordType(const Names: TArray<string>; const Types: TArray<TJType>;
  Decl: TRecordTypeObj): TJType;
var
  Key: string;
  K, Idx: Integer;
  Sh: TJShape;
begin
  Key := IntToHex(NativeInt(Decl), 16);
  for K := 0 to High(Names) do
    Key := Key + '|' + Names[K] + ':' + IntToStr(Types[K]);
  if not ShapeIndex.TryGetValue(Key, Idx) then
  begin
    if Shapes.Count >= High(TJType) - jtFirstRecord then
      Exit(jtNothing);
    Sh := TJShape.Create;
    Sh.Names := Copy(Names);
    Sh.Types := Copy(Types);
    Sh.Decl := Decl;
    if Decl <> nil then
      Sh.DeclRef := Decl;
    Idx := Shapes.Add(Sh);
    ShapeIndex.Add(Key, Idx);
  end;
  Result := jtFirstRecord + Idx;
end;

function JTypeOfValue(const V: TAxValue): TJType;
var
  A: TArrayObj;
  R: TRecordObj;
  Types: TArray<TJType>;
  K: Integer;
  Items: TAxValues;
  E: TJType;
begin
  case V.Kind of
    vkBool: Result := jtBool;
    vkInt:  Result := jtInt;
    vkReal: Result := jtReal;
    vkString: Result := jtString;
    vkArray:
      begin
        A := AsArray(V);
        if A.IsVector and (A.ElemType = etReal) then Result := jtVecReal
        else if A.IsVector and (A.ElemType = etInt) then Result := jtVecInt
        else if not A.IsVector and (A.ElemType = etReal) then Result := jtMatReal
        else Result := jtNothing;
      end;
    vkRecord:
      begin
        R := AsRecord(V);
        SetLength(Types, Length(R.Values));
        for K := 0 to High(Types) do
          Types[K] := JTypeOfValue(R.Values[K]);
        Result := RecordType(R.Names, Types, R.DeclType);
      end;
    vkList:
      begin
        // One element type for all, or the list does not compile.
        Items := AsList(V).Items;
        if Length(Items) = 0 then
          Exit(ListType(jtNothing));
        E := JTypeOfValue(Items[0]);
        if E = jtNothing then
          Exit(jtNothing);
        for K := 1 to High(Items) do
          if not JTypeMatches(Items[K], E) then
            Exit(jtNothing);
        Result := ListType(E);
      end;
  else
    Result := jtNothing;
  end;
end;

function JTypeMatches(const V: TAxValue; T: TJType): Boolean;
var
  R: TRecordObj;
  Sh: TJShape;
  K: Integer;
  Items: TAxValues;
  E: TJType;
  Kind: TValueKind;
begin
  if IsListType(T) then
  begin
    // Every element of the element type; an empty list matches any list type.
    if V.Kind <> vkList then
      Exit(False);
    Items := AsList(V).Items;
    if Length(Items) = 0 then
      Exit(True);
    E := ListElem(T);
    if E = jtNothing then
      Exit(False);
    // Numbers: a tight loop over the elements' kinds.
    case E of
      jtBool: Kind := vkBool;
      jtInt:  Kind := vkInt;
      jtReal: Kind := vkReal;
    else
      Kind := vkNothing;
    end;
    if Kind <> vkNothing then
    begin
      for K := 0 to High(Items) do
        if Items[K].Kind <> Kind then
          Exit(False);
      Exit(True);
    end;
    for K := 0 to High(Items) do
      if not JTypeMatches(Items[K], E) then
        Exit(False);
    Exit(True);
  end;
  if IsRecordType(T) then
  begin
    if V.Kind <> vkRecord then
      Exit(False);
    R := AsRecord(V);
    Sh := ShapeOf(T);
    if (R.DeclType <> Sh.Decl) or (Length(R.Names) <> Length(Sh.Names)) then
      Exit(False);
    for K := 0 to High(Sh.Names) do
    begin
      if R.Names[K] <> Sh.Names[K] then
        Exit(False);
      if (Sh.Types[K] <> jtNothing) and not JTypeMatches(R.Values[K], Sh.Types[K]) then
        Exit(False);
    end;
    Exit(True);
  end;
  Result := (T <> jtNothing) and (JTypeOfValue(V) = T);
end;

function TJCapture.Text: string;
begin
  Result := string.Join('.', Path);
end;

function ElemOf(T: TJType): TJType;
begin
  if T = jtVecInt then
    Result := jtInt
  else
    Result := jtReal;
end;

{ TJFunction }

constructor TJFunction.Create(const AName: string);
begin
  inherited Create;
  Name := AName;
  Params := TList<Integer>.Create;
  ResultTypes := TList<TJType>.Create;
  Regs := TList<TJReg>.Create;
  Insns := TObjectList<TJInsn>.Create(True);
  Sites := TList<TJSite>.Create;
  Targets := TObjectList<TJCallTarget>.Create(True);
  Captures := TList<TJCapture>.Create;
  LocalNames := TList<string>.Create;
end;

destructor TJFunction.Destroy;
begin
  Params.Free;
  ResultTypes.Free;
  Regs.Free;
  Insns.Free;
  Sites.Free;
  Targets.Free;
  Captures.Free;
  LocalNames.Free;
  inherited;
end;

function TJFunction.NewReg(Typ: TJType; const Name: string; IsParam: Boolean): Integer;
var
  R: TJReg;
begin
  R.Name := Name;
  R.Typ := Typ;
  R.IsParam := IsParam;
  Result := Regs.Add(R);
end;

function TJFunction.NewLabel: Integer;
begin
  Result := LabelCount;
  Inc(LabelCount);
end;

function TJFunction.AddSite(Line, Col: Integer): Integer;
var
  S: TJSite;
begin
  S.Line := Line;
  S.Col := Col;
  Result := Sites.Add(S);
end;

function TJFunction.Emit(Op: TJOp; Typ: TJType; Dst: Integer; const Ops: array of TJOperand;
  Site: Integer): TJInsn;
var
  K: Integer;
begin
  Result := TJInsn.Create;
  Result.Op := Op;
  Result.Typ := Typ;
  Result.Dst := Dst;
  SetLength(Result.Ops, Length(Ops));
  for K := 0 to High(Ops) do
    Result.Ops[K] := Ops[K];
  Result.Site := Site;
  Result.Site2 := -1;
  Insns.Add(Result);
end;

procedure TJFunction.PlaceLabel(L: Integer);
begin
  Emit(joLabel, jtNothing, -1, [LabelOperand(L)]);
end;

{ ---- text form ---- }

const
  OpNames: array[TJOp] of string = (
    '', '', 'b2i', 'b2r', 'i2r',
    'add', 'sub', 'mul', 'neg', 'div', 'pow',
    'eq', 'ne', 'lt', 'le', 'gt', 'ge',
    'not', 'jmp', 'bt', 'bf', 'count', 'elem', 'ret', 'call', 'load', 'store', 'len', 'op',
    'clear', 'bound', 'array', 'field', 'setfield', 'record', 'list', 'append', 'const', 'concat',
    'strcmp', 'strof', 'strlen');

procedure TJFunction.Dump(Lines: TStrings);
var
  TempNumbers: TDictionary<Integer, Integer>;

  function RegText(R: Integer): string;
  var
    K, Same: Integer;
  begin
    // Temporaries are numbered in order of first appearance, so the text
    // does not depend on registers the lowering allocated and then dropped.
    if Regs[R].Name = '' then
    begin
      if not TempNumbers.TryGetValue(R, K) then
      begin
        K := TempNumbers.Count;
        TempNumbers.Add(R, K);
      end;
      Exit('%' + IntToStr(K));
    end;
    // A shadowing variable of the same name is name.2, name.3 and so on.
    Same := 0;
    for K := 0 to R do
      if Regs[K].Name = Regs[R].Name then
        Inc(Same);
    if Same = 1 then
      Result := Regs[R].Name
    else
      Result := Regs[R].Name + '.' + IntToStr(Same);
  end;

  function OperandText(const O: TJOperand): string;
  begin
    case O.Kind of
      jkReg:   Result := RegText(O.Reg);
      jkInt:   Result := IntToStr(O.I);
      jkReal:  Result := Display(RealValue(O.R));
      jkBool:  if O.B then Result := 'true' else Result := 'false';
      jkString: Result := Display(StringValue(O.S), True);
    else
      Result := 'L' + IntToStr(O.I);
    end;
  end;

  function OperandList(const Ops: TArray<TJOperand>): string;
  var
    K: Integer;
  begin
    Result := '';
    for K := 0 to High(Ops) do
    begin
      if K > 0 then
        Result := Result + ', ';
      Result := Result + OperandText(Ops[K]);
    end;
  end;

  // The first operand with the instruction's field path: s.y, p.a.b.
  function PathText(I: TJInsn): string;
  var
    K: Integer;
    T: TJType;
  begin
    Result := OperandText(I.Ops[0]);
    T := Regs[I.Ops[0].Reg].Typ;
    for K := 0 to High(I.Path) do
    begin
      Result := Result + '.' + ShapeOf(T).Names[I.Path[K]];
      T := ShapeOf(T).Types[I.Path[K]];
    end;
  end;

  // The operands, the first one with its path.
  function PathOperands(I: TJInsn): string;
  var
    K: Integer;
  begin
    Result := PathText(I);
    for K := 1 to High(I.Ops) do
      Result := Result + ', ' + OperandText(I.Ops[K]);
  end;

  function CallText(I: TJInsn): string;
  const
    KindNames: array[TJCallKind] of string = ('call', 'call.interp', 'call.builtin');
  var
    K: Integer;
    Used: Integer;
  begin
    Result := '';
    Used := 0;
    for K := 0 to High(I.Dsts) do
      if I.Dsts[K] >= 0 then
        Inc(Used);
    if Length(I.Dsts) = 1 then
    begin
      if I.Dsts[0] >= 0 then
        Result := RegText(I.Dsts[0]) + ' = ';
    end
    else if Used > 0 then
    begin
      Result := '[';
      for K := 0 to High(I.Dsts) do
      begin
        if K > 0 then
          Result := Result + ', ';
        if I.Dsts[K] >= 0 then
          Result := Result + RegText(I.Dsts[K])
        else
          Result := Result + '_';
      end;
      Result := Result + '] = ';
    end;
    Result := Result + KindNames[I.Target.Kind] + ' ' + I.Target.Name + '(' +
      OperandList(I.Ops) + ')';
  end;

var
  Header, Line: string;
  K: Integer;
  Insn: TJInsn;
  S: TJSite;
begin
  Header := 'function ' + Name + '(';
  for K := 0 to Params.Count - Captures.Count - 1 do
  begin
    if K > 0 then
      Header := Header + ', ';
    Header := Header + Regs[Params[K]].Name + ': ' + JTypeName(Regs[Params[K]].Typ);
  end;
  Header := Header + ')';
  if Captures.Count > 0 then
  begin
    Header := Header + ' [';
    for K := 0 to Captures.Count - 1 do
    begin
      if K > 0 then
        Header := Header + ', ';
      Header := Header + Captures[K].Text + ': ' + JTypeName(Captures[K].Typ);
    end;
    Header := Header + ']';
  end;
  Header := Header + ': ';
  if ResultTypes.Count = 0 then
    Header := Header + 'nothing'
  else
    for K := 0 to ResultTypes.Count - 1 do
    begin
      if K > 0 then
        Header := Header + ', ';
      Header := Header + JTypeName(ResultTypes[K]);
    end;
  Lines.Add(Header);
  for K := 0 to Regs.Count - 1 do
    if (Regs[K].Name <> '') and not Regs[K].IsParam then
      Lines.Add('  var ' + RegText(K) + ': ' + JTypeName(Regs[K].Typ));

  TempNumbers := TDictionary<Integer, Integer>.Create;
  try
    for Insn in Insns do
    begin
      if Insn.Op = joLabel then
      begin
        Lines.Add(OperandText(Insn.Ops[0]) + ':');
        Continue;
      end;
      // Built in reading order, so temporaries are numbered left to right.
      if Insn.Op = joCall then
        Line := CallText(Insn)
      else if Insn.Dst >= 0 then
        Line := RegText(Insn.Dst) + ' = '
      else
        Line := '';
      case Insn.Op of
        joCall: ;
        joMov:
          Line := Line + OperandText(Insn.Ops[0]);
        joB2I, joB2R, joI2R, joJmp, joBrTrue, joBrFalse, joNot, joClear, joBound:
          Line := Line + OpNames[Insn.Op] + ' ' + OperandList(Insn.Ops);
        joArray:
          begin
            Line := Line + 'array.' + JTypeName(Insn.Typ) + ' ' + OperandText(Insn.Ops[0]) + ', ' +
              OperandText(Insn.Ops[1]) + ' (';
            for K := 2 to High(Insn.Ops) do
            begin
              if K > 2 then
                Line := Line + ', ';
              Line := Line + OperandText(Insn.Ops[K]);
            end;
            Line := Line + ')';
          end;
        joOp:
          begin
            Line := Line + 'op.' + JTypeName(Insn.Typ) + ' ' + Insn.Ops[1].S + '(' +
              OperandText(Insn.Ops[0]);
            if Length(Insn.Ops) > 2 then
              Line := Line + ', ' + OperandText(Insn.Ops[2]);
            Line := Line + ')';
          end;
        joRet:
          if Length(Insn.Ops) = 0 then
            Line := 'ret'
          else
            Line := 'ret ' + OperandList(Insn.Ops);
        joRecord:
          Line := Line + 'record ' + JTypeName(Insn.Typ) + ' (' + OperandList(Insn.Ops) + ')';
        joList:
          Line := Line + 'list ' + JTypeName(Insn.Typ) + ' (' + OperandList(Insn.Ops) + ')';
        joAppend:
          Line := Line + 'append ' + OperandList(Insn.Ops);
        joConst, joConcat, joStrCmp, joStrOf, joStrLen:
          Line := Line + OpNames[Insn.Op] + ' ' + OperandList(Insn.Ops);
        joField, joSetField:
          Line := Line + OpNames[Insn.Op] + '.' + JTypeName(Insn.Typ) + ' ' + PathOperands(Insn);
        joLoad, joStore, joLen:
          if Length(Insn.Path) > 0 then
            Line := Line + OpNames[Insn.Op] + '.' + JTypeName(Insn.Typ) + ' ' + PathOperands(Insn)
          else
            Line := Line + OpNames[Insn.Op] + '.' + JTypeName(Insn.Typ) + ' ' + OperandList(Insn.Ops);
      else
        Line := Line + OpNames[Insn.Op] + '.' + JTypeName(Insn.Typ) + ' ' + OperandList(Insn.Ops);
      end;
      if Insn.Site >= 0 then
      begin
        S := Sites[Insn.Site];
        Line := Line + '  @' + IntToStr(S.Line) + ':' + IntToStr(S.Col);
      end;
      if Insn.Site2 >= 0 then
      begin
        S := Sites[Insn.Site2];
        Line := Line + ' @' + IntToStr(S.Line) + ':' + IntToStr(S.Col);
      end;
      Lines.Add('  ' + Line);
    end;
  finally
    TempNumbers.Free;
  end;
end;

initialization
  Shapes := TObjectList<TJShape>.Create(True);
  ShapeIndex := TDictionary<string, Integer>.Create;

finalization
  ShapeIndex.Free;
  Shapes.Free;

end.
