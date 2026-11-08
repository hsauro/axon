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
     clear %5                            releases a hidden reference *)

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  Axon.Values;

type
  { jtString only for string literals passed to print and error. The
    array types follow the scalars. }
  TJType = (jtNothing, jtBool, jtInt, jtReal, jtString, jtVecReal, jtVecInt, jtMatReal);

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
    joBound                       // IndexError unless 1 <= Ops[0] <= Ops[1]
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
  end;

  TJReg = record
    Name: string;      // '' for a temporary
    Typ: TJType;
    IsParam: Boolean;
  end;

  TJSite = record
    Line, Col: Integer;
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

function JTypeName(T: TJType): string;
function IsArrayType(T: TJType): Boolean; inline;
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

function JTypeName(T: TJType): string;
const
  Names: array[TJType] of string = ('nothing', 'bool', 'int', 'real', 'string',
    'vector{real}', 'vector{int}', 'matrix{real}');
begin
  Result := Names[T];
end;

function IsArrayType(T: TJType): Boolean;
begin
  Result := T in [jtVecReal, jtVecInt, jtMatReal];
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
end;

destructor TJFunction.Destroy;
begin
  Params.Free;
  ResultTypes.Free;
  Regs.Free;
  Insns.Free;
  Sites.Free;
  Targets.Free;
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
    'clear', 'bound');

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
  for K := 0 to Params.Count - 1 do
  begin
    if K > 0 then
      Header := Header + ', ';
    Header := Header + Regs[Params[K]].Name + ': ' + JTypeName(Regs[Params[K]].Typ);
  end;
  Header := Header + '): ';
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

end.
