unit Axon.FmtCore;

(* The core module fmtcore, under stdlib/fmt.sci: the display settings for
   printed values (how many rows and columns of an array, how many decimals,
   whether arrays have a header line) and the number formatting that fmt's
   functions build on. Programs use fmt; fmtcore is its native part. *)

interface

implementation

uses
  System.SysUtils, System.Math,
  Axon.Errors, Axon.Values, Axon.Ops, Axon.NativeModules, Axon.FloatParse;

function DisplayCount(const Fn, What: string; const V: TAxValue): Integer;
begin
  if V.Kind <> vkInt then
    RaiseFmt(TypeError, '%s needs an int for %s, got %s', [Fn, What, TypeName(V)]);
  if (V.I < 1) or (V.I > 1000000) then
    RaiseFmt(ArgumentError, '%s needs 1 to 1000000 for %s, got %d', [Fn, What, V.I]);
  Result := V.I;
end;

{ set_size(rows, cols): arrays up to rows x cols are displayed in full;
  set_size() restores 10 x 8. }
function BSetSize(const Args: TAxValues): TAxValue;
begin
  if Length(Args) = 0 then
  begin
    DisplayRows := DefaultDisplayRows;
    DisplayCols := DefaultDisplayCols;
  end
  else if Length(Args) = 2 then
  begin
    DisplayRows := DisplayCount('fmt.set_size', 'the rows', Args[0]);
    DisplayCols := DisplayCount('fmt.set_size', 'the columns', Args[1]);
  end
  else
    RaiseError(ArgumentError, 'fmt.set_size takes rows and columns, or nothing to restore ' +
      'the default');
  Result := NothingValue;
end;

{ set_decimals(n): displayed reals show n decimals (1 to 15);
  set_decimals() restores significant digits. }
function BSetDecimals(const Args: TAxValues): TAxValue;
begin
  if Length(Args) = 0 then
    DisplayDecimals := -1
  else
  begin
    if Args[0].Kind <> vkInt then
      RaiseFmt(TypeError, 'fmt.set_decimals needs an int, got %s', [TypeName(Args[0])]);
    if (Args[0].I < 1) or (Args[0].I > 15) then
      RaiseFmt(ArgumentError, 'fmt.set_decimals needs 1 to 15 decimals, got %d', [Args[0].I]);
    DisplayDecimals := Args[0].I;
  end;
  Result := NothingValue;
end;

(* set_header(on): whether displayed arrays start with their header line
  ("2x3 matrix{int}"); without it, rows start at the left margin. *)
function BSetHeader(const Args: TAxValues): TAxValue;
begin
  if Args[0].Kind <> vkBool then
    RaiseFmt(TypeError, 'fmt.set_header needs true or false, got %s', [TypeName(Args[0])]);
  DisplayHeader := Args[0].B;
  Result := NothingValue;
end;

function RealArg(const Fn: string; const V: TAxValue): Double;
begin
  case V.Kind of
    vkInt: Result := V.I;
    vkReal: Result := V.R;
    vkBool: Result := Ord(V.B);
  else
    RaiseFmt(TypeError, '%s needs an int or real number, got %s', [Fn, TypeName(V)]);
    Result := 0;
  end;
end;

function IntArg(const Fn, What: string; const V: TAxValue; Lo, Hi: Integer): Integer;
begin
  if V.Kind <> vkInt then
    RaiseFmt(TypeError, '%s needs an int for %s, got %s', [Fn, What, TypeName(V)]);
  if (V.I < Lo) or (V.I > Hi) then
    RaiseFmt(ArgumentError, '%s needs %d to %d for %s, got %d', [Fn, Lo, Hi, What, V.I]);
  Result := V.I;
end;

{ digits(x, n): a real with up to n significant digits (1 to 17), as arrays
  display their elements (6) and scalars (15), exponent form outside the
  limits of set_sci; an int as it is. }
function BDigits(const Args: TAxValues): TAxValue;
begin
  if Args[0].Kind = vkInt then
    Exit(StringValue(IntToStr(Args[0].I)));
  Result := StringValue(DisplayReal(RealArg('fmt digits', Args[0]),
    IntArg('fmt', 'digits', Args[1], 1, 17)));
end;

{ set_sci(small, large): displayed reals use exponent form below small or
  from large in magnitude; set_sci() restores 1e-4 and 1e15. }
function BSetSci(const Args: TAxValues): TAxValue;
var
  Small, Large: Double;
begin
  if Length(Args) = 0 then
  begin
    SciSmall := DefaultSciSmall;
    SciLarge := DefaultSciLarge;
    Exit(NothingValue);
  end;
  if Length(Args) <> 2 then
    RaiseError(ArgumentError, 'fmt.set_sci takes the small and large limits, or nothing to ' +
      'restore the default');
  Small := RealArg('fmt.set_sci', Args[0]);
  Large := RealArg('fmt.set_sci', Args[1]);
  if IsNan(Small) or IsNan(Large) or (Small < 0) or (Large <= 0) or (Small > Large) then
    RaiseError(ArgumentError, 'fmt.set_sci needs 0 <= small <= large, with large above 0');
  SciSmall := Small;
  SciLarge := Large;
  Result := NothingValue;
end;

{ sci(x, n): x in scientific notation with n digits after the point:
  sci(12345.678, 2) is "1.23e4". }
function BSci(const Args: TAxValues): TAxValue;
begin
  Result := StringValue(FormatExponent(RealArg('fmt sci', Args[0]),
    IntArg('fmt', 'decimals', Args[1], 0, 100)));
end;

procedure DefineFmtCore(const Define: TProc<string, TAxValue>);
begin
  Define('set_size', BuiltinValue('fmt.set_size', BSetSize, 0, 2));
  Define('set_decimals', BuiltinValue('fmt.set_decimals', BSetDecimals, 0, 1));
  Define('set_header', BuiltinValue('fmt.set_header', BSetHeader, 1, 1));
  Define('set_sci', BuiltinValue('fmt.set_sci', BSetSci, 0, 2));
  Define('digits', BuiltinValue('fmtcore.digits', BDigits, 2, 2));
  Define('sci', BuiltinValue('fmtcore.sci', BSci, 2, 2));
end;

initialization
  RegisterNativeModule('fmtcore', DefineFmtCore,
    ['The native part of the fmt module: display settings and number formatting.']);

end.
