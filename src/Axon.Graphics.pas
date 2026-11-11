unit Axon.Graphics;

(* The core module graphics (reference, "The graphics module"): renders a
   scene, described as ordinary Axon data, to PNG, SVG or PDF through Skia.

   This unit checks a scene record and converts it into a TScene
   (Axon.Scene), which does the drawing, saving and encoding and is shared
   with the IDE. The checks keep the order of the fields as they are read,
   so the first problem in an item is the one reported.

   A scene is a record {width, height, background, scale, items}; items is a
   list of item records, each with a field kind: "polyline", "polygon",
   "rect", "circle", "ellipse", "arc", "markers", "text", "image" or "group".
   Coordinates are in points (1/72 inch) from the top-left corner, with y
   pointing down; angles count anticlockwise as seen on the page.

   Skia is called through its flat C API (System.Skia.API), not System.Skia:
   the high-level unit loads sk4d.dll when the program starts and aborts if
   it is missing, while here the library is loaded at the first call, so
   axon runs without it until something is drawn. On macOS Skia is linked
   statically. *)

interface

{ Width of Text in points at the given size and font family (for layout). }
function TextWidth(const Text: string; Size: Double; const Family: string): Double;

implementation

uses
  System.SysUtils, System.Classes, System.Math, System.Generics.Collections,
  System.Skia.API,
  System.IOUtils,
  Axon.Errors, Axon.Values, Axon.Ops, Axon.Arrays, Axon.NativeModules, Axon.Platform,
  Axon.Json, Axon.Scene;

var
  SkiaState: (ssNotLoaded, ssLoaded, ssFailed) = ssNotLoaded;

procedure EnsureSkia;
begin
  case SkiaState of
    ssLoaded: Exit;
    ssFailed:
      RaiseError(ForeignError, 'graphics needs the Skia library (sk4d), which could not be loaded');
  end;
  try
    SkInitialize;
    SkiaState := ssLoaded;
  except
    SkiaState := ssFailed;
    RaiseError(ForeignError, 'graphics needs the Skia library (sk4d), which could not be loaded');
  end;
end;

{ ---------------- reading the scene ---------------- }

function Field(R: TRecordObj; const Name: string; out V: TAxValue): Boolean;
var
  K: Integer;
begin
  K := R.IndexOf(Name);
  Result := K >= 0;
  if Result then
    V := R.Values[K];
end;

function NumField(R: TRecordObj; const Name: string; Default: Double; const Ctx: string): Double;
var
  V: TAxValue;
begin
  if not Field(R, Name, V) or (V.Kind = vkNothing) then
    Exit(Default);
  if not (V.Kind in [vkBool, vkInt, vkReal]) then
    RaiseFmt(TypeError, '%s: field "%s" must be a real number, got %s', [Ctx, Name, TypeName(V)]);
  Result := ToReal(V);
end;

function StrField(R: TRecordObj; const Name, Default, Ctx: string): string;
var
  V: TAxValue;
begin
  if not Field(R, Name, V) or (V.Kind = vkNothing) then
    Exit(Default);
  if V.Kind <> vkString then
    RaiseFmt(TypeError, '%s: field "%s" must be a string, got %s', [Ctx, Name, TypeName(V)]);
  Result := AsString(V);
end;

function BoolField(R: TRecordObj; const Name: string; Default: Boolean; const Ctx: string): Boolean;
var
  V: TAxValue;
begin
  if not Field(R, Name, V) or (V.Kind = vkNothing) then
    Exit(Default);
  if V.Kind <> vkBool then
    RaiseFmt(TypeError, '%s: field "%s" must be a bool, got %s', [Ctx, Name, TypeName(V)]);
  Result := V.B;
end;

function NumbersOf(const V: TAxValue; const Name, Ctx: string): TArray<Double>;
var
  A: TArrayObj;
  K: Integer;
begin
  if V.Kind in [vkBool, vkInt, vkReal] then
  begin
    Result := [ToReal(V)];
    Exit;
  end;
  if not IsArrayLike(V) then
    RaiseFmt(TypeError, '%s: field "%s" must be a real vector, got %s', [Ctx, Name, TypeName(V)]);
  A := ToArray(V);
  if A.ElemType = etComplex then
    RaiseFmt(TypeError, '%s: field "%s" must be real, got complex values', [Ctx, Name]);
  SetLength(Result, A.Count);
  for K := 0 to A.Count - 1 do
    Result[K] := ToReal(A.Get(K));
end;

function VecField(R: TRecordObj; const Name, Ctx: string): TArray<Double>;
var
  V: TAxValue;
begin
  if not Field(R, Name, V) then
    RaiseFmt(FieldError, '%s: field "%s" is missing', [Ctx, Name]);
  Result := NumbersOf(V, Name, Ctx);
end;

const
  NamedColors: array[0..15] of record Name: string; C: TColor32; end = (
    (Name: 'black';   C: $FF000000), (Name: 'white';  C: $FFFFFFFF),
    (Name: 'red';     C: $FFD62728), (Name: 'green';  C: $FF2CA02C),
    (Name: 'blue';    C: $FF1F77B4), (Name: 'orange'; C: $FFFF7F0E),
    (Name: 'purple';  C: $FF9467BD), (Name: 'brown';  C: $FF8C564B),
    (Name: 'pink';    C: $FFE377C2), (Name: 'gray';   C: $FF7F7F7F),
    (Name: 'grey';    C: $FF7F7F7F), (Name: 'olive';  C: $FFBCBD22),
    (Name: 'cyan';    C: $FF17BECF), (Name: 'yellow'; C: $FFFFD700),
    (Name: 'lightgray'; C: $FFD3D3D3), (Name: 'darkgray'; C: $FF404040));

{ A colour: a name, "#rrggbb", "#rrggbbaa" or "none" (fully transparent). }
function ParseColor(const S, Ctx: string): TColor32;
var
  T: string;
  N: Cardinal;
  K: Integer;
begin
  T := LowerCase(Trim(S));
  if T = 'none' then
    Exit(0);
  for K := Low(NamedColors) to High(NamedColors) do
    if NamedColors[K].Name = T then
      Exit(NamedColors[K].C);
  if T.StartsWith('#') and (Length(T) in [7, 9]) then
  begin
    N := 0;
    for K := 2 to Length(T) do
    begin
      case T[K] of
        '0'..'9': N := N * 16 + Cardinal(Ord(T[K]) - Ord('0'));
        'a'..'f': N := N * 16 + Cardinal(Ord(T[K]) - Ord('a') + 10);
      else
        RaiseFmt(ArgumentError, '%s: invalid colour "%s"', [Ctx, S]);
      end;
    end;
    if Length(T) = 7 then
      Exit($FF000000 or N);
    // #rrggbbaa: move alpha to the top byte
    Exit(((N and $FF) shl 24) or (N shr 8));
  end;
  RaiseFmt(ArgumentError, '%s: invalid colour "%s" (use a name, "#rrggbb" or "#rrggbbaa")', [Ctx, S]);
  Result := 0;
end;

{ A colour field: a string as for ParseColor, or a real vector [r, g, b] or
  [r, g, b, a] with components between 0 and 1. }
function ColorField(R: TRecordObj; const Name, Default, Ctx: string): TColor32;
var
  V: TAxValue;
  C: TArray<Double>;
  K: Integer;
  Parts: array[0..3] of Cardinal;
begin
  if not Field(R, Name, V) or (V.Kind = vkNothing) then
    Exit(ParseColor(Default, Ctx));
  if V.Kind = vkString then
    Exit(ParseColor(AsString(V), Ctx));
  if not IsArrayLike(V) then
    RaiseFmt(TypeError, '%s: field "%s" must be a colour string or an [r, g, b] vector, got %s',
      [Ctx, Name, TypeName(V)]);
  C := NumbersOf(V, Name, Ctx);
  if not (Length(C) in [3, 4]) then
    RaiseFmt(DimensionError, '%s: a colour vector needs 3 or 4 values, got %d', [Ctx, Length(C)]);
  Parts[3] := 255;
  for K := 0 to High(C) do
  begin
    if not ((C[K] >= 0) and (C[K] <= 1)) then
      RaiseFmt(ArgumentError, '%s: colour components must lie between 0 and 1', [Ctx]);
    Parts[K] := Round(C[K] * 255);
  end;
  Result := (Parts[3] shl 24) or (Parts[0] shl 16) or (Parts[1] shl 8) or Parts[2];
end;

{ ---------------- converting a scene record ---------------- }

function IsFinite(X: Double): Boolean; inline;
begin
  Result := not (IsNan(X) or IsInfinite(X));
end;

procedure CheckSameLength(const X, Y: TArray<Double>; const Ctx: string);
begin
  if Length(X) <> Length(Y) then
    RaiseFmt(DimensionError, '%s: x has %d values but y has %d', [Ctx, Length(X), Length(Y)]);
end;

function DashField(R: TRecordObj; const Ctx: string): TArray<Double>;
var
  V: TAxValue;
begin
  Result := nil;
  if Field(R, 'dash', V) and (V.Kind <> vkNothing) then
    Result := NumbersOf(V, 'dash', Ctx);
end;

{ An item's stroke: width (default DefaultWidth), dash, cap ("butt",
  "round" or "square") and join ("round", "miter" or "bevel"). }
function StrokeField(R: TRecordObj; DefaultWidth: Double; const Ctx: string): TStroke;
var
  S: string;
begin
  Result.Width := NumField(R, 'width', DefaultWidth, Ctx);
  Result.Dash := DashField(R, Ctx);
  S := StrField(R, 'cap', 'butt', Ctx);
  if S = 'butt' then Result.Cap := BUTT_SK_STROKECAP
  else if S = 'round' then Result.Cap := ROUND_SK_STROKECAP
  else if S = 'square' then Result.Cap := SQUARE_SK_STROKECAP
  else
    RaiseFmt(ArgumentError, '%s: unknown cap "%s" (butt, round, square)', [Ctx, S]);
  S := StrField(R, 'join', 'round', Ctx);
  if S = 'round' then Result.Join := ROUND_SK_STROKEJOIN
  else if S = 'miter' then Result.Join := MITER_SK_STROKEJOIN
  else if S = 'bevel' then Result.Join := BEVEL_SK_STROKEJOIN
  else
    RaiseFmt(ArgumentError, '%s: unknown join "%s" (round, miter, bevel)', [Ctx, S]);
end;

{ A "line"/"polyline" or a "polygon". }
function PolyItem(R: TRecordObj; Closed: Boolean; const Ctx: string): TSceneItem;
var
  X, Y: TArray<Double>;
begin
  X := VecField(R, 'x', Ctx);
  Y := VecField(R, 'y', Ctx);
  CheckSameLength(X, Y, Ctx);
  if Closed then
    Result := TSceneItem.Create(skPolygon)
  else
    Result := TSceneItem.Create(skPolyline);
  try
    Result.X := X;
    Result.Y := Y;
    if Closed then
    begin
      Result.Fill := ColorField(R, 'fill', 'none', Ctx);
      Result.Color := ColorField(R, 'color', 'none', Ctx);
    end
    else
      Result.Color := ColorField(R, 'color', 'black', Ctx);
    Result.Stroke := StrokeField(R, 1, Ctx);
  except
    Result.Free;
    raise;
  end;
end;

{ A "rect": the closed path through its corners. }
function RectItem(R: TRecordObj; const Ctx: string): TSceneItem;
var
  X, Y, W, H: Double;
begin
  X := NumField(R, 'x', 0, Ctx);
  Y := NumField(R, 'y', 0, Ctx);
  W := NumField(R, 'w', 0, Ctx);
  H := NumField(R, 'h', 0, Ctx);
  Result := TSceneItem.Create(skPolygon);
  try
    Result.X := [X, X + W, X + W, X];
    Result.Y := [Y, Y, Y + H, Y + H];
    Result.Fill := ColorField(R, 'fill', 'none', Ctx);
    Result.Color := ColorField(R, 'color', 'none', Ctx);
    Result.Stroke := StrokeField(R, 1, Ctx);
  except
    Result.Free;
    raise;
  end;
end;

{ Circles, ellipses and arcs: outline "black" and no fill by default, so a
  bare shape is visible. An ellipse may be turned by angle (degrees,
  anticlockwise); an arc runs from start through sweep degrees,
  anticlockwise from the positive x axis as seen on the page, and with
  wedge = true is closed through the centre (a pie slice). }
function RoundItem(R: TRecordObj; const Kind, Ctx: string): TSceneItem;
var
  X, Y, RX, RY: Double;
begin
  X := NumField(R, 'x', 0, Ctx);
  Y := NumField(R, 'y', 0, Ctx);
  if Kind = 'ellipse' then
  begin
    RX := NumField(R, 'rx', 0, Ctx);
    RY := NumField(R, 'ry', 0, Ctx);
  end
  else
  begin
    if R.IndexOf('r') < 0 then
      RaiseFmt(FieldError, '%s: field "r" is missing', [Ctx]);
    RX := NumField(R, 'r', 0, Ctx);
    RY := RX;
  end;
  if (RX < 0) or (RY < 0) then
    RaiseFmt(ArgumentError, '%s: a radius must not be negative', [Ctx]);
  if Kind = 'arc' then
    Result := TSceneItem.Create(skArc)
  else
    Result := TSceneItem.Create(skEllipse);
  try
    Result.CX := X;
    Result.CY := Y;
    Result.RX := RX;
    Result.RY := RY;
    if Kind = 'arc' then
    begin
      Result.Start := NumField(R, 'start', 0, Ctx);
      Result.Sweep := NumField(R, 'sweep', 360, Ctx);
      Result.Wedge := BoolField(R, 'wedge', False, Ctx);
    end
    else if Kind = 'ellipse' then
      Result.Angle := NumField(R, 'angle', 0, Ctx);
    if (Kind = 'arc') and not Result.Wedge then
      Result.Color := ColorField(R, 'color', 'black', Ctx)
    else
    begin
      Result.Fill := ColorField(R, 'fill', 'none', Ctx);
      Result.Color := ColorField(R, 'color', 'black', Ctx);
    end;
    Result.Stroke := StrokeField(R, 1, Ctx);
  except
    Result.Free;
    raise;
  end;
end;

{ "markers"; nil when an unknown shape has no point to draw. }
function MarkersItem(R: TRecordObj; const Ctx: string): TSceneItem;
var
  X, Y: TArray<Double>;
  Shape: string;
  Size: Double;
  Fill, Stroke: TColor32;
  M: TMarkerShape;
  K: Integer;
begin
  X := VecField(R, 'x', Ctx);
  Y := VecField(R, 'y', Ctx);
  CheckSameLength(X, Y, Ctx);
  Shape := StrField(R, 'shape', 'circle', Ctx);
  Size := NumField(R, 'size', 6, Ctx);
  Stroke := ColorField(R, 'color', 'black', Ctx);
  if R.IndexOf('fill') >= 0 then
    Fill := ColorField(R, 'fill', 'none', Ctx)
  else
    Fill := Stroke;
  if Shape = 'circle' then M := msCircle
  else if Shape = 'square' then M := msSquare
  else if Shape = 'diamond' then M := msDiamond
  else if Shape = 'triangle' then M := msTriangle
  else if Shape = 'plus' then M := msPlus
  else if Shape = 'cross' then M := msCross
  else
  begin
    // As drawn before: the shape matters only when there is a point.
    for K := 0 to High(X) do
      if IsFinite(X[K]) and IsFinite(Y[K]) then
        RaiseFmt(ArgumentError, '%s: unknown marker shape "%s" (circle, square, diamond, triangle, plus, cross)',
          [Ctx, Shape]);
    Exit(nil);
  end;
  Result := TSceneItem.Create(skMarkers);
  try
    Result.X := X;
    Result.Y := Y;
    Result.Shape := M;
    Result.Size := Size;
    Result.Color := Stroke;
    Result.Fill := Fill;
    if M in [msPlus, msCross] then
      Result.Stroke := PlainStroke(NumField(R, 'width', 1.5, Ctx))
    else
      Result.Stroke := PlainStroke(NumField(R, 'width', 0, Ctx));
  except
    Result.Free;
    raise;
  end;
end;

{ "text"; nil for empty text, whose other fields are not looked at. }
function TextItem(R: TRecordObj; const Ctx: string): TSceneItem;
var
  Text, Anchor, Baseline, Family: string;
  X, Y, Size, Angle: Double;
  Bold: Boolean;
begin
  Text := StrField(R, 'text', '', Ctx);
  if Text = '' then
    Exit(nil);
  X := NumField(R, 'x', 0, Ctx);
  Y := NumField(R, 'y', 0, Ctx);
  Size := NumField(R, 'size', 10, Ctx);
  Angle := NumField(R, 'angle', 0, Ctx);
  Anchor := StrField(R, 'anchor', 'start', Ctx);
  Baseline := StrField(R, 'baseline', 'alphabetic', Ctx);
  Family := StrField(R, 'font', 'sans-serif', Ctx);
  Bold := BoolField(R, 'bold', False, Ctx);
  Result := TSceneItem.Create(skText);
  try
    Result.Text := Text;
    Result.CX := X;
    Result.CY := Y;
    Result.Size := Size;
    Result.Angle := Angle;
    Result.Font := Family;
    Result.Bold := Bold;
    if Anchor = 'start' then Result.Anchor := taStart
    else if Anchor = 'middle' then Result.Anchor := taMiddle
    else if Anchor = 'end' then Result.Anchor := taEnd
    else
      RaiseFmt(ArgumentError, '%s: anchor must be "start", "middle" or "end", got "%s"', [Ctx, Anchor]);
    if Baseline = 'alphabetic' then Result.Baseline := tbAlphabetic
    else if Baseline = 'middle' then Result.Baseline := tbMiddle
    else if Baseline = 'top' then Result.Baseline := tbTop
    else if Baseline = 'bottom' then Result.Baseline := tbBottom
    else
      RaiseFmt(ArgumentError, '%s: baseline must be "alphabetic", "middle", "top" or "bottom", got "%s"',
        [Ctx, Baseline]);
    Result.Color := ColorField(R, 'color', 'black', Ctx);
  except
    Result.Free;
    raise;
  end;
end;

{ ---- images ---- }

const
  // viridis at eleven evenly spaced points, as plot.sci has it.
  Viridis: array[0..10, 0..2] of Double = (
    (0.267, 0.005, 0.329), (0.283, 0.141, 0.458), (0.254, 0.265, 0.530),
    (0.207, 0.372, 0.553), (0.164, 0.471, 0.558), (0.128, 0.567, 0.551),
    (0.135, 0.659, 0.518), (0.267, 0.749, 0.441), (0.478, 0.821, 0.318),
    (0.741, 0.873, 0.150), (0.993, 0.906, 0.144));

type
  TRgba = array[0..3] of Double;

{ A pixel of RGBA8888 (bytes R, G, B, A in memory) from components in [0, 1],
  unpremultiplied. }
function PackPixel(const C: TRgba): Cardinal;
var
  K: Integer;
  B: array[0..3] of Cardinal;
begin
  for K := 0 to 3 do
    B[K] := Round(EnsureRange(C[K], 0, 1) * 255);
  Result := B[0] or (B[1] shl 8) or (B[2] shl 16) or (B[3] shl 24);
end;

{ The colour at u in [0, 1] of a colour map: "viridis", "gray", "hsv" (the
  hues once round, cyclic) or a table of rows [r, g, b] or [r, g, b, a],
  evenly spaced and interpolated linearly. }
function MapColor(const Name: string; const Table: TArray<TArray<Double>>; U: Double): TRgba;
var
  Pos, F, H, X: Double;
  K, N, J, Sector: Integer;
begin
  U := EnsureRange(U, 0, 1);
  Result[3] := 1;
  if Table <> nil then
  begin
    N := Length(Table);
    if N = 1 then
      Pos := 0
    else
      Pos := U * (N - 1);
    K := Min(Trunc(Pos), Max(N - 2, 0));
    F := Pos - K;
    for J := 0 to High(Table[0]) do
      if N = 1 then
        Result[J] := Table[0][J]
      else
        Result[J] := (1 - F) * Table[K][J] + F * Table[K + 1][J];
  end
  else if Name = 'gray' then
  begin
    Result[0] := U;
    Result[1] := U;
    Result[2] := U;
  end
  else if Name = 'hsv' then
  begin
    // Hue U (0 and 1 both red), full saturation and value.
    H := Frac(U) * 6;
    Sector := Trunc(H) mod 6;
    X := H - Trunc(H);
    case Sector of
      0: begin Result[0] := 1; Result[1] := X; Result[2] := 0; end;
      1: begin Result[0] := 1 - X; Result[1] := 1; Result[2] := 0; end;
      2: begin Result[0] := 0; Result[1] := 1; Result[2] := X; end;
      3: begin Result[0] := 0; Result[1] := 1 - X; Result[2] := 1; end;
      4: begin Result[0] := X; Result[1] := 0; Result[2] := 1; end;
    else
      begin Result[0] := 1; Result[1] := 0; Result[2] := 1 - X; end;
    end;
  end
  else
  begin
    Pos := U * 10;
    K := Min(Trunc(Pos), 9);
    F := Pos - K;
    for J := 0 to 2 do
      Result[J] := (1 - F) * Viridis[K][J] + F * Viridis[K + 1][J];
  end;
end;

{ A matrix field of an image: its array, checked to be real. }
function MatrixField(R: TRecordObj; const Name, Ctx: string; out A: TArrayObj): Boolean;
var
  V: TAxValue;
begin
  Result := Field(R, Name, V) and (V.Kind <> vkNothing);
  if not Result then
    Exit;
  if V.Kind <> vkArray then
    RaiseFmt(TypeError, '%s: field "%s" must be a real matrix, got %s', [Ctx, Name, TypeName(V)]);
  A := AsArray(V);
  if A.ElemType = etComplex then
    RaiseFmt(TypeError, '%s: field "%s" must be real, got complex values', [Ctx, Name]);
end;

(* An "image": a matrix of values as pixels, row 1 at the top, in the
   rectangle {x, y, w, h} (default: one point per pixel at the origin).
   Either values, mapped through colormap from vmin to vmax (by default the
   finite values' range; NaN and infinite values get nan_color, default
   "none"), or red, green and blue (and optionally alpha) matrices with
   components from 0 to 1. The colours are worked out here; the scene holds
   the pixels. nil for an empty matrix. *)
function ImageItem(R: TRecordObj; const Ctx: string): TSceneItem;
var
  A, Red, Green, Blue, Alpha: TArrayObj;
  V: TAxValue;
  Rows, Cols, I, J, K: Integer;
  MapName: string;
  Table: TArray<TArray<Double>>;
  T: TArrayObj;
  Lo, Hi, X, Span: Double;
  NanColor: TColor32;
  NanPixel: Cardinal;
  Pixels: TArray<Cardinal>;
  Rgba: TRgba;
  HasValues: Boolean;

  procedure SameShape(M: TArrayObj; const Name: string);
  begin
    if (M.Rows <> Rows) or (M.Cols <> Cols) then
      RaiseFmt(DimensionError, '%s: %s is %d' + #$00D7 + '%d but red is %d' + #$00D7 + '%d',
        [Ctx, Name, M.Rows, M.Cols, Rows, Cols]);
  end;

begin
  HasValues := MatrixField(R, 'values', Ctx, A);
  if HasValues then
  begin
    Rows := A.Rows;
    Cols := A.Cols;
  end
  else
  begin
    if not MatrixField(R, 'red', Ctx, Red) then
      RaiseFmt(FieldError, '%s: an image needs "values", or "red", "green" and "blue"', [Ctx]);
    Rows := Red.Rows;
    Cols := Red.Cols;
    if not MatrixField(R, 'green', Ctx, Green) then
      RaiseFmt(FieldError, '%s: field "green" is missing', [Ctx]);
    if not MatrixField(R, 'blue', Ctx, Blue) then
      RaiseFmt(FieldError, '%s: field "blue" is missing', [Ctx]);
    SameShape(Green, 'green');
    SameShape(Blue, 'blue');
    if MatrixField(R, 'alpha', Ctx, Alpha) then
      SameShape(Alpha, 'alpha')
    else
      Alpha := nil;
  end;
  if (Rows = 0) or (Cols = 0) then
    Exit(nil);
  SetLength(Pixels, Rows * Cols);

  if HasValues then
  begin
    // The colour map: a name, or a table of colours.
    MapName := 'viridis';
    Table := nil;
    if Field(R, 'colormap', V) and (V.Kind <> vkNothing) then
    begin
      if V.Kind = vkString then
      begin
        MapName := AsString(V);
        if (MapName <> 'viridis') and (MapName <> 'gray') and (MapName <> 'hsv') then
          RaiseFmt(ArgumentError, '%s: unknown colormap "%s" (viridis, gray, hsv, or a matrix ' +
            'of [r, g, b] rows)', [Ctx, MapName]);
      end
      else if V.Kind = vkArray then
      begin
        T := AsArray(V);
        if (T.IsVector) or not (T.Cols in [3, 4]) or (T.Rows = 0) then
          RaiseFmt(DimensionError, '%s: a colormap matrix needs rows of [r, g, b] or [r, g, b, a]', [Ctx]);
        SetLength(Table, T.Rows);
        for I := 0 to T.Rows - 1 do
        begin
          SetLength(Table[I], 4);
          Table[I][3] := 1;
          for J := 0 to T.Cols - 1 do
            Table[I][J] := ToReal(T.Get(I + J * T.Rows));
        end;
      end
      else
        RaiseFmt(TypeError, '%s: colormap must be a name or a matrix, got %s', [Ctx, TypeName(V)]);
    end;
    // The range: vmin and vmax, by default the finite values' extremes.
    Lo := Infinity;
    Hi := -Infinity;
    for K := 0 to A.Count - 1 do
    begin
      X := ToReal(A.Get(K));
      if IsFinite(X) then
      begin
        if X < Lo then Lo := X;
        if X > Hi then Hi := X;
      end;
    end;
    Lo := NumField(R, 'vmin', Lo, Ctx);
    Hi := NumField(R, 'vmax', Hi, Ctx);
    Span := Hi - Lo;
    NanColor := ColorField(R, 'nan_color', 'none', Ctx);
    // ARGB to the RGBA8888 byte order.
    NanPixel := ((NanColor shr 16) and $FF) or (((NanColor shr 8) and $FF) shl 8) or
      ((NanColor and $FF) shl 16) or ((NanColor shr 24) shl 24);
    for I := 0 to Rows - 1 do
      for J := 0 to Cols - 1 do
      begin
        X := ToReal(A.Get(I + J * Rows));
        if not IsFinite(X) then
          Pixels[I * Cols + J] := NanPixel
        else
        begin
          if Span > 0 then
            X := (X - Lo) / Span
          else
            X := 0.5;
          Pixels[I * Cols + J] := PackPixel(MapColor(MapName, Table, X));
        end;
      end;
  end
  else
    for I := 0 to Rows - 1 do
      for J := 0 to Cols - 1 do
      begin
        K := I + J * Rows;
        Rgba[0] := ToReal(Red.Get(K));
        Rgba[1] := ToReal(Green.Get(K));
        Rgba[2] := ToReal(Blue.Get(K));
        if Alpha <> nil then
          Rgba[3] := ToReal(Alpha.Get(K))
        else
          Rgba[3] := 1;
        Pixels[I * Cols + J] := PackPixel(Rgba);
      end;

  Result := TSceneItem.Create(skImage);
  try
    Result.ImageWidth := Cols;
    Result.ImageHeight := Rows;
    Result.Pixels := Pixels;
    Result.CX := NumField(R, 'x', 0, Ctx);
    Result.CY := NumField(R, 'y', 0, Ctx);
    Result.W := NumField(R, 'w', Cols, Ctx);
    Result.H := NumField(R, 'h', Rows, Ctx);
    Result.Smooth := BoolField(R, 'smooth', False, Ctx);
  except
    Result.Free;
    raise;
  end;
end;

procedure AddItems(Into: TSceneItems; const Items: TAxValue; const Ctx: string;
  First: Integer = 0); forward;

{ A "group": dx, dy shift it, angle turns it (degrees, anticlockwise on the
  page) and scale sizes it (a number or [sx, sy]), in that order seen from
  the page: an item point p is drawn at (dx, dy) + R(angle) S p. The clip
  and the items are in the group's own coordinates. }
function GroupItem(R: TRecordObj; const Ctx: string): TSceneItem;
var
  V: TAxValue;
  Clip: TRecordObj;
  S: TArray<Double>;
begin
  Result := TSceneItem.Create(skGroup);
  try
    Result.CX := NumField(R, 'dx', 0, Ctx);
    Result.CY := NumField(R, 'dy', 0, Ctx);
    Result.Angle := NumField(R, 'angle', 0, Ctx);
    if Field(R, 'scale', V) and (V.Kind <> vkNothing) then
    begin
      S := NumbersOf(V, 'scale', Ctx);
      Result.HasScale := True;
      if Length(S) = 1 then
      begin
        Result.SX := S[0];
        Result.SY := S[0];
      end
      else if Length(S) = 2 then
      begin
        Result.SX := S[0];
        Result.SY := S[1];
      end
      else
        RaiseFmt(DimensionError, '%s: scale must be a number or [sx, sy], got %d values',
          [Ctx, Length(S)]);
    end;
    if Field(R, 'clip', V) and (V.Kind <> vkNothing) then
    begin
      if V.Kind <> vkRecord then
        RaiseFmt(TypeError, '%s: clip must be a record {x, y, w, h}, got %s', [Ctx, TypeName(V)]);
      Clip := AsRecord(V);
      Result.HasClip := True;
      Result.ClipX := NumField(Clip, 'x', 0, Ctx);
      Result.ClipY := NumField(Clip, 'y', 0, Ctx);
      Result.ClipW := NumField(Clip, 'w', 0, Ctx);
      Result.ClipH := NumField(Clip, 'h', 0, Ctx);
    end;
    if not Field(R, 'items', V) then
      RaiseFmt(FieldError, '%s: field "items" is missing', [Ctx]);
    AddItems(Result.Items, V, Ctx);
  except
    Result.Free;
    raise;
  end;
end;

{ Converts the items of the list from the one at position First (0-based)
  on; the ones before are skipped (sent before, for graphics.frame). }
procedure AddItems(Into: TSceneItems; const Items: TAxValue; const Ctx: string;
  First: Integer);
var
  K: Integer;
  Item: TAxValue;
  R: TRecordObj;
  Kind, ItemCtx: string;
  It: TSceneItem;
begin
  if Items.Kind <> vkList then
    RaiseFmt(TypeError, '%s: items must be a list, got %s', [Ctx, TypeName(Items)]);
  for K := First to High(AsList(Items).Items) do
  begin
    Item := AsList(Items).Items[K];
    ItemCtx := Format('%s, item %d', [Ctx, K + 1]);
    if Item.Kind <> vkRecord then
      RaiseFmt(TypeError, '%s must be a record, got %s', [ItemCtx, TypeName(Item)]);
    R := AsRecord(Item);
    Kind := StrField(R, 'kind', '', ItemCtx);
    if (Kind = 'polyline') or (Kind = 'line') then It := PolyItem(R, False, ItemCtx)
    else if Kind = 'polygon' then It := PolyItem(R, True, ItemCtx)
    else if Kind = 'rect' then It := RectItem(R, ItemCtx)
    else if (Kind = 'circle') or (Kind = 'ellipse') or (Kind = 'arc') then
      It := RoundItem(R, Kind, ItemCtx)
    else if Kind = 'image' then It := ImageItem(R, ItemCtx)
    else if Kind = 'markers' then It := MarkersItem(R, ItemCtx)
    else if Kind = 'text' then It := TextItem(R, ItemCtx)
    else if Kind = 'group' then It := GroupItem(R, ItemCtx)
    else
    begin
      RaiseFmt(ArgumentError, '%s: unknown kind "%s"', [ItemCtx, Kind]);
      It := nil;
    end;
    if It <> nil then
      Into.Add(It);
  end;
end;

{ The scene record as a TScene of size W x H: its background (white by
  default), then its items. With the environment variable
  AXON_SCENE_ROUNDTRIP set, the scene is encoded and decoded before it is
  drawn, which checks the encoding against every saved picture. }
function MakeScene(Scene: TRecordObj; W, H: Double; First: Integer = 0): TScene;
var
  Items: TAxValue;
  Copy: TScene;
begin
  Result := TScene.Create;
  try
    Result.Width := W;
    Result.Height := H;
    Result.Background := ColorField(Scene, 'background', 'white', 'graphics.save');
    if not Field(Scene, 'items', Items) then
      RaiseError(FieldError, 'graphics.save: the scene has no field "items"');
    AddItems(Result.Items, Items, 'graphics.save', First);
  except
    Result.Free;
    raise;
  end;
  if GetEnvironmentVariable('AXON_SCENE_ROUNDTRIP') <> '' then
  begin
    Copy := DecodeScene(EncodeScene(Result));
    Result.Free;
    Result := Copy;
  end;
end;

{ The scene record's scale, pixels per point for PNG (1 by default). }
function ScaleOf(Scene: TRecordObj): Double;
begin
  Result := NumField(Scene, 'scale', 1, 'graphics.save');
  if Result <= 0 then
    RaiseError(ArgumentError, 'graphics.save: scale must be positive');
end;

{ ---------------- output ---------------- }

{ Runs a drawing step, turning a failure of Skia into an Axon error: a file
  that cannot be written is an IOError, anything else a ForeignError. }
procedure Render(const What: string; const Step: TProc);
begin
  try
    Step();
  except
    on E: EScene do
      if E.Message.StartsWith('cannot write') then
        RaiseFmt(IOError, '%s: %s', [What, E.Message])
      else
        RaiseFmt(ForeignError, '%s: %s', [What, E.Message]);
  end;
end;

{ The scene record as a PNG file. }
procedure WritePng(SceneRec: TRecordObj; W, H: Double; const Path: string);
var
  Scale: Double;
  Scene: TScene;
begin
  Scale := ScaleOf(SceneRec);
  Scene := MakeScene(SceneRec, W, H);
  try
    Render('graphics.save', procedure begin SavePng(Scene, Scale, Path); end);
  finally
    Scene.Free;
  end;
end;

function OpenOutput(const Path: string): TFileStream;
begin
  try
    Result := TFileStream.Create(Path, fmCreate);
  except
    on E: Exception do
    begin
      RaiseFmt(IOError, 'graphics.save: cannot write "%s": %s', [Path, E.Message]);
      Result := nil;
    end;
  end;
end;

{ The scene record as an SVG or PDF file. }
procedure WriteVector(SceneRec: TRecordObj; W, H: Double; const Path: string; Pdf: Boolean);
var
  Stream: TFileStream;
  Scene: TScene;
begin
  Stream := OpenOutput(Path);
  try
    Scene := MakeScene(SceneRec, W, H);
    try
      Render('graphics.save',
        procedure
        begin
          if Pdf then SavePdf(Scene, Stream) else SaveSvg(Scene, Stream);
        end);
    finally
      Scene.Free;
    end;
  finally
    Stream.Free;
  end;
end;

{ ---------------- the module ---------------- }

function BSave(const Args: TAxValues): TAxValue;
var
  Scene: TRecordObj;
  Path, Ext: string;
  W, H: Double;
begin
  if Args[0].Kind <> vkRecord then
    RaiseFmt(TypeError, 'graphics.save needs a scene record, got %s', [TypeName(Args[0])]);
  if Args[1].Kind <> vkString then
    RaiseFmt(TypeError, 'graphics.save needs a file path string, got %s', [TypeName(Args[1])]);
  Scene := AsRecord(Args[0]);
  Path := AsString(Args[1]);
  W := NumField(Scene, 'width', 640, 'graphics.save');
  H := NumField(Scene, 'height', 480, 'graphics.save');
  if (W <= 0) or (H <= 0) or (W > 20000) or (H > 20000) then
    RaiseError(ArgumentError, 'graphics.save: width and height must be between 0 and 20000');
  Ext := LowerCase(ExtractFileExt(Path));
  if (Ext <> '.png') and (Ext <> '.svg') and (Ext <> '.pdf') then
    RaiseFmt(ArgumentError, 'graphics.save: the file name must end in .png, .svg or .pdf, got "%s"', [Path]);
  EnsureSkia;
  try
    if Ext = '.png' then WritePng(Scene, W, H, Path)
    else WriteVector(Scene, W, H, Path, Ext = '.pdf');
  except
    // An invalid scene is found while drawing: leave no partial file.
    if FileExists(Path) then
      DeleteFile(Path);
    raise;
  end;
  Result := NothingValue;
end;

function TextWidth(const Text: string; Size: Double; const Family: string): Double;
begin
  EnsureSkia;
  Result := MeasureText(Text, Size, Family, False);
end;

var
  ShowCount: Integer;

(* graphics.show(scene) or graphics.show(scene, data): shows the scene.

   With a display channel (the IDE), the scene is sent on it as a message,
   with data (plot's figure record) as JSON in a figure message, for the
   IDE's interactive charts; nothing is written to disk, and the result is
   nothing. Otherwise, with AXON_SHOW_DIR set (the test runner), the scene is
   rendered to a PNG there, the data written next to it as .json, and a line
   #3"show <path>" goes to stderr; without either, the PNG goes to a
   temporary folder and opens in the system's viewer. Then the result is the
   PNG's path. *)

{ Sends a scene record on the display channel as a show, frame or figure
  message, with Data (a figure record) for a figure. }
procedure SendScene(SceneRec: TRecordObj; W, H: Double; Kind: Byte; const Data: TAxValue;
  const What: string; First: Integer = 0);
var
  Scene: TScene;
  Bytes, Json, Payload: TBytes;
  N: Cardinal;
begin
  ScaleOf(SceneRec);                 // checked as for a PNG, though not used
  Scene := MakeScene(SceneRec, W, H, First);
  try
    // Nothing new since the last frame: nothing to send.
    if (Kind = DisplayAdd) and (Scene.Items.Count = 0) then
      Exit;
    Bytes := EncodeScene(Scene);
  finally
    Scene.Free;
  end;
  if Kind = DisplayFigure then
  begin
    Json := TEncoding.UTF8.GetBytes(ValueToJson(Data, What));
    N := Length(Bytes);
    SetLength(Payload, 4 + Length(Bytes) + Length(Json));
    Move(N, Payload[0], 4);
    Move(Bytes[0], Payload[4], Length(Bytes));
    if Length(Json) > 0 then
      Move(Json[0], Payload[4 + Length(Bytes)], Length(Json));
    DisplaySend(Kind, Payload);
  end
  else
    DisplaySend(Kind, Bytes);
end;
function BShow(const Args: TAxValues): TAxValue;
var
  Scene: TRecordObj;
  Dir, Path: string;
  FrontEnd: Boolean;
  W, H: Double;
begin
  if Args[0].Kind <> vkRecord then
    RaiseFmt(TypeError, 'graphics.show needs a scene record, got %s', [TypeName(Args[0])]);
  Scene := AsRecord(Args[0]);
  W := NumField(Scene, 'width', 640, 'graphics.show');
  H := NumField(Scene, 'height', 480, 'graphics.show');
  if (W <= 0) or (H <= 0) or (W > 20000) or (H > 20000) then
    RaiseError(ArgumentError, 'graphics.show: width and height must be between 0 and 20000');
  if DisplayChannel then
  begin
    if (Length(Args) > 1) and (Args[1].Kind <> vkNothing) then
      SendScene(Scene, W, H, DisplayFigure, Args[1], 'graphics.show')
    else
      SendScene(Scene, W, H, DisplayShow, NothingValue, 'graphics.show');
    Exit(NothingValue);
  end;
  Dir := GetEnvironmentVariable('AXON_SHOW_DIR');
  FrontEnd := Dir <> '';
  if not FrontEnd then
    Dir := TPath.Combine(TPath.GetTempPath, 'axon-figures');
  try
    ForceDirectories(Dir);
  except
    on E: Exception do
      RaiseFmt(IOError, 'graphics.show: cannot create "%s": %s', [Dir, E.Message]);
  end;
  Inc(ShowCount);
  Path := TPath.Combine(Dir, Format('figure-%d-%d-%d.png',
    [MainThreadID, ShowCount, TThread.GetTickCount64 mod 1000000]));
  EnsureSkia;
  WritePng(Scene, W, H, Path);
  if FrontEnd and (Length(Args) > 1) and (Args[1].Kind <> vkNothing) then
    try
      TFile.WriteAllBytes(TPath.ChangeExtension(Path, '.json'),
        TEncoding.UTF8.GetBytes(ValueToJson(Args[1], 'graphics.show')));
    except
      on E: EAxonError do
        raise;
      on E: Exception do
        RaiseFmt(IOError, 'graphics.show: cannot write the figure data: %s', [E.Message]);
    end;
  if FrontEnd then
  begin
    Writeln(ErrOutput, #3'show ' + Path);
    Flush(ErrOutput);
  end
  else if not OpenWithDefaultApp(Path) then
    RaiseFmt(ForeignError, 'graphics.show: cannot open a viewer for "%s"', [Path]);
  Result := StringValue(Path);
end;

var
  FrameCount: Integer;

const
  // Frames are written to this many files in turn, so an animation leaves
  // only this many behind; the front end shows the newest one.
  FrameFiles = 8;

{ graphics.frame(scene) or graphics.frame(scene, sent): one frame of an
  animation. With a display channel (the IDE) the scene is sent as a frame
  message, which the IDE shows in place of the previous frame, without
  adding it to the figure history. With sent, a count of items that the
  previous frames already sent (the scene grew since, as when a picture is
  built up gradually), only the items after those are sent, and the IDE adds
  them to the frame it has.
  Otherwise, with AXON_SHOW_DIR set (the test runner), it is rendered to a
  PNG there, one of a small ring of files reused in turn, and a line
  #3"frame <path>" goes to stderr. Without either it does nothing, rather
  than open a viewer for every frame. Returns the path, or nothing. }
function BFrame(const Args: TAxValues): TAxValue;
var
  Scene: TRecordObj;
  Dir, Path: string;
  W, H: Double;
  First: Int64;
begin
  if Args[0].Kind <> vkRecord then
    RaiseFmt(TypeError, 'graphics.frame needs a scene record, got %s', [TypeName(Args[0])]);
  Scene := AsRecord(Args[0]);
  W := NumField(Scene, 'width', 640, 'graphics.frame');
  H := NumField(Scene, 'height', 480, 'graphics.frame');
  if (W <= 0) or (H <= 0) or (W > 20000) or (H > 20000) then
    RaiseError(ArgumentError, 'graphics.frame: width and height must be between 0 and 20000');
  First := 0;
  if (Length(Args) > 1) and (Args[1].Kind <> vkNothing) then
  begin
    if Args[1].Kind <> vkInt then
      RaiseFmt(TypeError, 'graphics.frame: the count of items sent must be an int, got %s',
        [TypeName(Args[1])]);
    if Args[1].I < 0 then
      RaiseError(ArgumentError, 'graphics.frame: the count of items sent must not be negative');
    First := Args[1].I;
  end;
  if DisplayChannel then
  begin
    if First > 0 then
      SendScene(Scene, W, H, DisplayAdd, NothingValue, 'graphics.frame', First)
    else
      SendScene(Scene, W, H, DisplayFrame, NothingValue, 'graphics.frame');
    Exit(NothingValue);
  end;
  Dir := GetEnvironmentVariable('AXON_SHOW_DIR');
  if Dir = '' then
    Exit(NothingValue);
  try
    ForceDirectories(Dir);
  except
    on E: Exception do
      RaiseFmt(IOError, 'graphics.frame: cannot create "%s": %s', [Dir, E.Message]);
  end;
  Path := TPath.Combine(Dir, Format('frame-%d-%d.png', [MainThreadID, FrameCount mod FrameFiles]));
  Inc(FrameCount);
  EnsureSkia;
  WritePng(Scene, W, H, Path);
  Writeln(ErrOutput, #3'frame ' + Path);
  Flush(ErrOutput);
  Result := StringValue(Path);
end;

function BTextWidth(const Args: TAxValues): TAxValue;
var
  Family: string;
begin
  if Args[0].Kind <> vkString then
    RaiseFmt(TypeError, 'graphics.text_width needs a string, got %s', [TypeName(Args[0])]);
  if not (Args[1].Kind in [vkInt, vkReal]) then
    RaiseFmt(TypeError, 'graphics.text_width needs a font size, got %s', [TypeName(Args[1])]);
  Family := 'sans-serif';
  if Length(Args) > 2 then
  begin
    if Args[2].Kind <> vkString then
      RaiseFmt(TypeError, 'graphics.text_width needs a font family string, got %s', [TypeName(Args[2])]);
    Family := AsString(Args[2]);
  end;
  Result := RealValue(TextWidth(AsString(Args[0]), ToReal(Args[1]), Family));
end;

procedure DefineGraphics(const Define: TProc<string, TAxValue>);
begin
  Define('save', BuiltinValue('save', BSave, 2, 2));
  Define('show', BuiltinValue('show', BShow, 1, 2));
  Define('frame', BuiltinValue('frame', BFrame, 1, 2));
  Define('text_width', BuiltinValue('text_width', BTextWidth, 2, 3));
end;

initialization
  RegisterNativeModule('graphics', DefineGraphics,
    ['Renders a scene (a record of drawing items) to PNG, SVG or PDF through Skia.']);

finalization
  if SkiaState = ssLoaded then
  begin
    ReleaseTypefaces;
    SkFinalize;
  end;

end.
