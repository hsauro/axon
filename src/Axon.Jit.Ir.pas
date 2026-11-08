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
   b2i, b2r and i2r. A move prints as `dst = src`. *)

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections;

type
  TJType = (jtNothing, jtBool, jtInt, jtReal);

  TJOperandKind = (jkReg, jkInt, jkReal, jkBool, jkLabel);

  TJOperand = record
    Kind: TJOperandKind;
    Reg: Integer;      // jkReg
    I: Int64;          // jkInt; jkLabel: the label number
    R: Double;         // jkReal
    B: Boolean;        // jkBool
    function IsImm: Boolean;
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
    joRet                         // Ops: the results
  );

  TJInsn = class
  public
    Op: TJOp;
    Typ: TJType;       // the type the operation works in
    Dst: Integer;      // a register, or -1
    Ops: TArray<TJOperand>;
    Site: Integer;     // index into TJFunction.Sites, or -1 when it cannot fail
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

function JTypeName(T: TJType): string;

implementation

uses
  Axon.Values;

function TJOperand.IsImm: Boolean;
begin
  Result := Kind in [jkInt, jkReal, jkBool];
end;

function Blank(Kind: TJOperandKind): TJOperand;
begin
  FillChar(Result, SizeOf(Result), 0);
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

function LabelOperand(L: Integer): TJOperand;
begin
  Result := Blank(jkLabel);
  Result.I := L;
end;

function JTypeName(T: TJType): string;
const
  Names: array[TJType] of string = ('nothing', 'bool', 'int', 'real');
begin
  Result := Names[T];
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
end;

destructor TJFunction.Destroy;
begin
  Params.Free;
  ResultTypes.Free;
  Regs.Free;
  Insns.Free;
  Sites.Free;
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
    'not', 'jmp', 'bt', 'bf', 'count', 'elem', 'ret');

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
      if Insn.Dst >= 0 then
        Line := RegText(Insn.Dst) + ' = '
      else
        Line := '';
      case Insn.Op of
        joMov:
          Line := Line + OperandText(Insn.Ops[0]);
        joB2I, joB2R, joI2R, joJmp, joBrTrue, joBrFalse, joNot:
          Line := Line + OpNames[Insn.Op] + ' ' + OperandList(Insn.Ops);
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
      Lines.Add('  ' + Line);
    end;
  finally
    TempNumbers.Free;
  end;
end;

end.
