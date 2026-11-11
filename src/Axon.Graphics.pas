unit Axon.Graphics;

(* The core module graphics (reference, "The graphics module"): renders a
   scene, described as ordinary Axon data, to PNG, SVG or PDF through Skia.

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
  Axon.Json;

type
  TColor32 = Cardinal;   // ARGB

var
  SkiaState: (ssNotLoaded, ssLoaded, ssFailed) = ssNotLoaded;
  Typefaces: TDictionary<string, sk_typeface_t>;

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

{ ---------------- drawing ---------------- }

function IsFinite(X: Double): Boolean; inline;
begin
  Result := not (IsNan(X) or IsInfinite(X));
end;

function Typeface(const Family: string; Bold: Boolean): sk_typeface_t;
var
  Key: string;
  Style: sk_fontstyle_t;
  U: UTF8String;
begin
  if Typefaces = nil then
    Typefaces := TDictionary<string, sk_typeface_t>.Create;
  Key := Family + '|' + BoolToStr(Bold, True);
  if Typefaces.TryGetValue(Key, Result) then
    Exit;
  Style.weight := IfThen(Bold, 700, 400);
  Style.width := 5;
  Style.slant := UPRIGHT_SK_FONTSLANT;
  // Generic names map to fonts every installation has.
  U := UTF8String(Family);
{$IFDEF MSWINDOWS}
  if Family = 'sans-serif' then U := 'Segoe UI'
  else if Family = 'serif' then U := 'Times New Roman'
  else if Family = 'monospace' then U := 'Consolas';
{$ELSE}
  if Family = 'sans-serif' then U := 'Helvetica'
  else if Family = 'serif' then U := 'Times'
  else if Family = 'monospace' then U := 'Menlo';
{$ENDIF}
  Result := sk4d_typeface_make_from_name(PAnsiChar(U), @Style);
  if Result = 0 then
    Result := sk4d_typeface_make_default();
  Typefaces.Add(Key, Result);
end;

type
  { How a path's outline is drawn: from an item's width, dash, cap and join. }
  TStroke = record
    Width: Double;
    Dash: TArray<Double>;
    Cap: sk_strokecap_t;
    Join: sk_strokejoin_t;
  end;

function MakePaint(Color: TColor32; Stroke: Boolean; const S: TStroke): sk_paint_t;
begin
  Result := sk4d_paint_create();
  sk4d_paint_set_antialias(Result, True);
  sk4d_paint_set_color(Result, Color);
  if Stroke then
  begin
    sk4d_paint_set_style(Result, STROKE_SK_PAINTSTYLE);
    sk4d_paint_set_stroke_width(Result, S.Width);
    sk4d_paint_set_stroke_join(Result, S.Join);
    sk4d_paint_set_stroke_cap(Result, S.Cap);
  end
  else
    sk4d_paint_set_style(Result, FILL_SK_PAINTSTYLE);
end;

{ A plain stroke: butt ends, round corners, no dashes. }
function PlainStroke(Width: Double): TStroke;
begin
  Result.Width := Width;
  Result.Dash := nil;
  Result.Cap := BUTT_SK_STROKECAP;
  Result.Join := ROUND_SK_STROKEJOIN;
end;

procedure DrawPathWith(C: sk_canvas_t; Path: sk_path_t; Fill, Stroke: TColor32;
  const S: TStroke);
var
  P: sk_paint_t;
  Effect: sk_patheffect_t;
  Intervals: TArray<Single>;
  K: Integer;
begin
  if (Fill shr 24) <> 0 then
  begin
    P := MakePaint(Fill, False, S);
    sk4d_canvas_draw_path(C, Path, P);
    sk4d_paint_destroy(P);
  end;
  if ((Stroke shr 24) <> 0) and (S.Width > 0) then
  begin
    P := MakePaint(Stroke, True, S);
    Effect := 0;
    if Length(S.Dash) >= 2 then
    begin
      SetLength(Intervals, Length(S.Dash) - Length(S.Dash) mod 2);
      for K := 0 to High(Intervals) do
        Intervals[K] := S.Dash[K];
      Effect := sk4d_patheffect_make_dash(@Intervals[0], Length(Intervals), 0);
      sk4d_paint_set_path_effect(P, Effect);
    end;
    sk4d_canvas_draw_path(C, Path, P);
    sk4d_paint_destroy(P);
    if Effect <> 0 then
      sk4d_refcnt_unref(Effect);
  end;
end;

{ A path through the points; a NaN or infinite coordinate breaks the line. }
function PolyPath(const X, Y: TArray<Double>; Closed: Boolean): sk_path_t;
var
  B: sk_pathbuilder_t;
  K: Integer;
  Pt: sk_point_t;
  PenDown: Boolean;
begin
  B := sk4d_pathbuilder_create();
  PenDown := False;
  for K := 0 to High(X) do
  begin
    if not (IsFinite(X[K]) and IsFinite(Y[K])) then
    begin
      PenDown := False;
      Continue;
    end;
    Pt.x := X[K];
    Pt.y := Y[K];
    if PenDown then
      sk4d_pathbuilder_line_to(B, @Pt)
    else
      sk4d_pathbuilder_move_to(B, @Pt);
    PenDown := True;
  end;
  if Closed then
    sk4d_pathbuilder_close(B);
  Result := sk4d_pathbuilder_detach(B);
  sk4d_pathbuilder_destroy(B);
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

procedure DrawPolyline(C: sk_canvas_t; R: TRecordObj; const Ctx: string);
var
  X, Y: TArray<Double>;
  Path: sk_path_t;
begin
  X := VecField(R, 'x', Ctx);
  Y := VecField(R, 'y', Ctx);
  CheckSameLength(X, Y, Ctx);
  Path := PolyPath(X, Y, False);
  DrawPathWith(C, Path, 0, ColorField(R, 'color', 'black', Ctx), StrokeField(R, 1, Ctx));
  sk4d_path_destroy(Path);
end;

procedure DrawPolygon(C: sk_canvas_t; R: TRecordObj; const Ctx: string);
var
  X, Y: TArray<Double>;
  Path: sk_path_t;
begin
  X := VecField(R, 'x', Ctx);
  Y := VecField(R, 'y', Ctx);
  CheckSameLength(X, Y, Ctx);
  Path := PolyPath(X, Y, True);
  DrawPathWith(C, Path, ColorField(R, 'fill', 'none', Ctx),
    ColorField(R, 'color', 'none', Ctx), StrokeField(R, 1, Ctx));
  sk4d_path_destroy(Path);
end;

procedure DrawRect(C: sk_canvas_t; R: TRecordObj; const Ctx: string);
var
  X, Y, W, H: Double;
  Path: sk_path_t;
begin
  X := NumField(R, 'x', 0, Ctx);
  Y := NumField(R, 'y', 0, Ctx);
  W := NumField(R, 'w', 0, Ctx);
  H := NumField(R, 'h', 0, Ctx);
  Path := PolyPath([X, X + W, X + W, X], [Y, Y, Y + H, Y + H], True);
  DrawPathWith(C, Path, ColorField(R, 'fill', 'none', Ctx),
    ColorField(R, 'color', 'none', Ctx), StrokeField(R, 1, Ctx));
  sk4d_path_destroy(Path);
end;

{ Circles, ellipses and arcs: outline "black" and no fill by default, so a
  bare shape is visible. An ellipse may be turned by angle (degrees,
  anticlockwise); an arc runs from start through sweep degrees,
  anticlockwise from the positive x axis as seen on the page, and with
  wedge = true is closed through the centre (a pie slice). }
procedure DrawRound(C: sk_canvas_t; R: TRecordObj; const Kind, Ctx: string);
var
  X, Y, RX, RY, Angle, Start, Sweep: Double;
  B: sk_pathbuilder_t;
  Path: sk_path_t;
  Oval: sk_rect_t;
  Pt: sk_point_t;
  Wedge: Boolean;
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
  Oval.left := X - RX;
  Oval.top := Y - RY;
  Oval.right := X + RX;
  Oval.bottom := Y + RY;
  Angle := 0;
  Wedge := False;
  B := sk4d_pathbuilder_create();
  try
    if Kind = 'arc' then
    begin
      Start := NumField(R, 'start', 0, Ctx);
      Sweep := NumField(R, 'sweep', 360, Ctx);
      Wedge := BoolField(R, 'wedge', False, Ctx);
      // Skia's angles run clockwise on the page (y points down).
      if Wedge then
      begin
        Pt.x := X;
        Pt.y := Y;
        sk4d_pathbuilder_move_to(B, @Pt);
        sk4d_pathbuilder_arc_to2(B, @Oval, -Start, -Sweep, False);
        sk4d_pathbuilder_close(B);
      end
      else
        sk4d_pathbuilder_add_arc(B, @Oval, -Start, -Sweep);
    end
    else
    begin
      sk4d_pathbuilder_add_oval(B, @Oval, CW_SK_PATHDIRECTION, 0);
      if Kind = 'ellipse' then
        Angle := NumField(R, 'angle', 0, Ctx);
    end;
    Path := sk4d_pathbuilder_detach(B);
  finally
    sk4d_pathbuilder_destroy(B);
  end;
  try
    sk4d_canvas_save(C);
    try
      if Angle <> 0 then
        sk4d_canvas_rotate2(C, -Angle, X, Y);
      if (Kind = 'arc') and not Wedge then
        DrawPathWith(C, Path, 0, ColorField(R, 'color', 'black', Ctx), StrokeField(R, 1, Ctx))
      else
        DrawPathWith(C, Path, ColorField(R, 'fill', 'none', Ctx),
          ColorField(R, 'color', 'black', Ctx), StrokeField(R, 1, Ctx));
    finally
      sk4d_canvas_restore(C);
    end;
  finally
    sk4d_path_destroy(Path);
  end;
end;

procedure DrawMarkers(C: sk_canvas_t; R: TRecordObj; const Ctx: string);
var
  X, Y: TArray<Double>;
  Shape: string;
  Size, H: Double;
  Fill, Stroke: TColor32;
  B: sk_pathbuilder_t;
  Path: sk_path_t;
  K: Integer;

  procedure Pt(PX, PY: Double; Move: Boolean);
  var
    P: sk_point_t;
  begin
    P.x := PX;
    P.y := PY;
    if Move then sk4d_pathbuilder_move_to(B, @P) else sk4d_pathbuilder_line_to(B, @P);
  end;

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
  H := Size / 2;
  B := sk4d_pathbuilder_create();
  for K := 0 to High(X) do
  begin
    if not (IsFinite(X[K]) and IsFinite(Y[K])) then
      Continue;
    if Shape = 'circle' then
      sk4d_pathbuilder_add_circle(B, X[K], Y[K], H, CW_SK_PATHDIRECTION)
    else if Shape = 'square' then
    begin
      Pt(X[K] - H, Y[K] - H, True); Pt(X[K] + H, Y[K] - H, False);
      Pt(X[K] + H, Y[K] + H, False); Pt(X[K] - H, Y[K] + H, False);
      sk4d_pathbuilder_close(B);
    end
    else if Shape = 'diamond' then
    begin
      Pt(X[K], Y[K] - H, True); Pt(X[K] + H, Y[K], False);
      Pt(X[K], Y[K] + H, False); Pt(X[K] - H, Y[K], False);
      sk4d_pathbuilder_close(B);
    end
    else if Shape = 'triangle' then
    begin
      Pt(X[K], Y[K] - H, True); Pt(X[K] + H, Y[K] + H, False);
      Pt(X[K] - H, Y[K] + H, False);
      sk4d_pathbuilder_close(B);
    end
    else if Shape = 'plus' then
    begin
      Pt(X[K] - H, Y[K], True); Pt(X[K] + H, Y[K], False);
      Pt(X[K], Y[K] - H, True); Pt(X[K], Y[K] + H, False);
    end
    else if Shape = 'cross' then
    begin
      Pt(X[K] - H, Y[K] - H, True); Pt(X[K] + H, Y[K] + H, False);
      Pt(X[K] - H, Y[K] + H, True); Pt(X[K] + H, Y[K] - H, False);
    end
    else
    begin
      sk4d_pathbuilder_destroy(B);
      RaiseFmt(ArgumentError, '%s: unknown marker shape "%s" (circle, square, diamond, triangle, plus, cross)',
        [Ctx, Shape]);
    end;
  end;
  Path := sk4d_pathbuilder_detach(B);
  sk4d_pathbuilder_destroy(B);
  if (Shape = 'plus') or (Shape = 'cross') then
    DrawPathWith(C, Path, 0, Stroke, PlainStroke(NumField(R, 'width', 1.5, Ctx)))
  else
    DrawPathWith(C, Path, Fill, Stroke, PlainStroke(NumField(R, 'width', 0, Ctx)));
  sk4d_path_destroy(Path);
end;

function MakeFont(const Family: string; Bold: Boolean; Size: Double): sk_font_t;
var
  T: sk_typeface_t;
begin
  T := Typeface(Family, Bold);
  Result := sk4d_font_create(T, Size, 1, 0);
  // Skia's lookup by name may ignore the weight; embolden synthetically then.
  if Bold and (sk4d_typeface_get_weight(T) < 600) then
    sk4d_font_set_embolden(Result, True);
end;

function MeasureWith(Font: sk_font_t; const Text: string): Double;
var
  U: UTF8String;
begin
  U := UTF8String(Text);
  if U = '' then
    Exit(0);
  Result := sk4d_font_measure_text(Font, PAnsiChar(U), Length(U), UTF8_SK_TEXTENCODING, nil, 0);
end;

procedure DrawText(C: sk_canvas_t; R: TRecordObj; const Ctx: string);
var
  Text, Anchor, Baseline, Family: string;
  X, Y, Size, Angle, W, DX, DY: Double;
  Font: sk_font_t;
  Paint: sk_paint_t;
  Metrics: sk_fontmetrics_t;
  U: UTF8String;
begin
  Text := StrField(R, 'text', '', Ctx);
  if Text = '' then
    Exit;
  X := NumField(R, 'x', 0, Ctx);
  Y := NumField(R, 'y', 0, Ctx);
  Size := NumField(R, 'size', 10, Ctx);
  Angle := NumField(R, 'angle', 0, Ctx);
  Anchor := StrField(R, 'anchor', 'start', Ctx);
  Baseline := StrField(R, 'baseline', 'alphabetic', Ctx);
  Family := StrField(R, 'font', 'sans-serif', Ctx);
  Font := MakeFont(Family, BoolField(R, 'bold', False, Ctx), Size);
  try
    W := MeasureWith(Font, Text);
    DX := 0;
    DY := 0;
    if Anchor = 'start' then DX := 0
    else if Anchor = 'middle' then DX := -W / 2
    else if Anchor = 'end' then DX := -W
    else
      RaiseFmt(ArgumentError, '%s: anchor must be "start", "middle" or "end", got "%s"', [Ctx, Anchor]);
    sk4d_font_get_metrics(Font, @Metrics);
    if Baseline = 'alphabetic' then DY := 0
    else if Baseline = 'middle' then DY := Metrics.cap_height / 2
    else if Baseline = 'top' then DY := Metrics.cap_height
    else if Baseline = 'bottom' then DY := -Metrics.descent
    else
      RaiseFmt(ArgumentError, '%s: baseline must be "alphabetic", "middle", "top" or "bottom", got "%s"',
        [Ctx, Baseline]);
    Paint := MakePaint(ColorField(R, 'color', 'black', Ctx), False, PlainStroke(0));
    U := UTF8String(Text);
    sk4d_canvas_save(C);
    sk4d_canvas_translate(C, X, Y);
    if Angle <> 0 then
      sk4d_canvas_rotate(C, -Angle);   // angles count anticlockwise, y points down
    sk4d_canvas_draw_simple_text(C, PAnsiChar(U), Length(U), UTF8_SK_TEXTENCODING, DX, DY, Font, Paint);
    sk4d_canvas_restore(C);
    sk4d_paint_destroy(Paint);
  finally
    sk4d_font_destroy(Font);
  end;
end;

{ ---------------- images ---------------- }

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

(* An image item: a matrix of values drawn as pixels, row 1 at the top,
   into the rectangle {x, y, w, h} (default: one point per pixel at the
   origin). Either values, mapped through colormap from vmin to vmax (by
   default the finite values' range; NaN and infinite values get
   nan_color, default "none"), or red, green and blue (and optionally
   alpha) matrices with components from 0 to 1. smooth = true interpolates
   between pixels when the image is scaled; by default each pixel is a
   sharp square. *)
procedure DrawImage(C: sk_canvas_t; R: TRecordObj; const Ctx: string);
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
  Info: sk_imageinfo_t;
  Pixmap: sk_pixmap_t;
  Image: sk_image_t;
  Src, Dest: sk_rect_t;
  Sampling: sk_samplingoptions_t;

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
    Exit;
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

  Info.width := Cols;
  Info.height := Rows;
  Info.color_type := RGBA8888_SK_COLORTYPE;
  Info.alpha_type := UNPREMUL_SK_ALPHATYPE;
  Info.color_space := 0;
  Pixmap := sk4d_pixmap_create(@Info, @Pixels[0], Cols * 4);
  if Pixmap = 0 then
    RaiseFmt(ForeignError, '%s: cannot make a %d' + #$00D7 + '%d image', [Ctx, Cols, Rows]);
  try
    Image := sk4d_image_make_raster_copy(Pixmap);
  finally
    sk4d_pixmap_destroy(Pixmap);
  end;
  if Image = 0 then
    RaiseFmt(ForeignError, '%s: cannot make a %d' + #$00D7 + '%d image', [Ctx, Cols, Rows]);
  try
    Src.left := 0;
    Src.top := 0;
    Src.right := Cols;
    Src.bottom := Rows;
    Dest.left := NumField(R, 'x', 0, Ctx);
    Dest.top := NumField(R, 'y', 0, Ctx);
    Dest.right := Dest.left + NumField(R, 'w', Cols, Ctx);
    Dest.bottom := Dest.top + NumField(R, 'h', Rows, Ctx);
    FillChar(Sampling, SizeOf(Sampling), 0);
    if BoolField(R, 'smooth', False, Ctx) then
      Sampling.filter := LINEAR_SK_FILTERMODE
    else
      Sampling.filter := NEAREST_SK_FILTERMODE;
    Sampling.mipmap := NONE_SK_MIPMAPMODE;
    sk4d_canvas_draw_image_rect(C, Image, @Src, @Dest, @Sampling, 0, FAST_SK_SRCRECTCONSTRAINT);
  finally
    sk4d_refcnt_unref(Image);
  end;
end;

procedure DrawItems(C: sk_canvas_t; const Items: TAxValue; const Ctx: string); forward;

procedure DrawGroup(C: sk_canvas_t; R: TRecordObj; const Ctx: string);
var
  V: TAxValue;
  Clip: TRecordObj;
  Rect: sk_rect_t;
  Angle: Double;
  S: TArray<Double>;
begin
  sk4d_canvas_save(C);
  try
    // dx, dy shift the group, angle turns it (degrees, anticlockwise on the
    // page) and scale sizes it (a number or [sx, sy]), in that order seen
    // from the page: an item point p is drawn at (dx, dy) + R(angle) S p.
    // The clip and the items are in the group's own coordinates.
    sk4d_canvas_translate(C, NumField(R, 'dx', 0, Ctx), NumField(R, 'dy', 0, Ctx));
    Angle := NumField(R, 'angle', 0, Ctx);
    if Angle <> 0 then
      sk4d_canvas_rotate(C, -Angle);
    if Field(R, 'scale', V) and (V.Kind <> vkNothing) then
    begin
      S := NumbersOf(V, 'scale', Ctx);
      if Length(S) = 1 then
        sk4d_canvas_scale(C, S[0], S[0])
      else if Length(S) = 2 then
        sk4d_canvas_scale(C, S[0], S[1])
      else
        RaiseFmt(DimensionError, '%s: scale must be a number or [sx, sy], got %d values',
          [Ctx, Length(S)]);
    end;
    if Field(R, 'clip', V) and (V.Kind <> vkNothing) then
    begin
      if V.Kind <> vkRecord then
        RaiseFmt(TypeError, '%s: clip must be a record {x, y, w, h}, got %s', [Ctx, TypeName(V)]);
      Clip := AsRecord(V);
      Rect.left := NumField(Clip, 'x', 0, Ctx);
      Rect.top := NumField(Clip, 'y', 0, Ctx);
      Rect.right := Rect.left + NumField(Clip, 'w', 0, Ctx);
      Rect.bottom := Rect.top + NumField(Clip, 'h', 0, Ctx);
      sk4d_canvas_clip_rect(C, @Rect, INTERSECT_SK_CLIPOP, True);
    end;
    if not Field(R, 'items', V) then
      RaiseFmt(FieldError, '%s: field "items" is missing', [Ctx]);
    DrawItems(C, V, Ctx);
  finally
    sk4d_canvas_restore(C);
  end;
end;

procedure DrawItems(C: sk_canvas_t; const Items: TAxValue; const Ctx: string);
var
  K: Integer;
  Item: TAxValue;
  R: TRecordObj;
  Kind, ItemCtx: string;
begin
  if Items.Kind <> vkList then
    RaiseFmt(TypeError, '%s: items must be a list, got %s', [Ctx, TypeName(Items)]);
  for K := 0 to High(AsList(Items).Items) do
  begin
    Item := AsList(Items).Items[K];
    ItemCtx := Format('%s, item %d', [Ctx, K + 1]);
    if Item.Kind <> vkRecord then
      RaiseFmt(TypeError, '%s must be a record, got %s', [ItemCtx, TypeName(Item)]);
    R := AsRecord(Item);
    Kind := StrField(R, 'kind', '', ItemCtx);
    if (Kind = 'polyline') or (Kind = 'line') then DrawPolyline(C, R, ItemCtx)
    else if Kind = 'polygon' then DrawPolygon(C, R, ItemCtx)
    else if Kind = 'rect' then DrawRect(C, R, ItemCtx)
    else if (Kind = 'circle') or (Kind = 'ellipse') or (Kind = 'arc') then
      DrawRound(C, R, Kind, ItemCtx)
    else if Kind = 'image' then DrawImage(C, R, ItemCtx)
    else if Kind = 'markers' then DrawMarkers(C, R, ItemCtx)
    else if Kind = 'text' then DrawText(C, R, ItemCtx)
    else if Kind = 'group' then DrawGroup(C, R, ItemCtx)
    else
      RaiseFmt(ArgumentError, '%s: unknown kind "%s"', [ItemCtx, Kind]);
  end;
end;

procedure DrawScene(C: sk_canvas_t; Scene: TRecordObj; W, H: Double);
var
  Bg: TColor32;
  Paint: sk_paint_t;
  Rect: sk_rect_t;
  Items: TAxValue;
begin
  Bg := ColorField(Scene, 'background', 'white', 'graphics.save');
  if (Bg shr 24) <> 0 then
  begin
    Rect.left := 0;
    Rect.top := 0;
    Rect.right := W;
    Rect.bottom := H;
    Paint := MakePaint(Bg, False, PlainStroke(0));
    sk4d_canvas_draw_rect(C, @Rect, Paint);
    sk4d_paint_destroy(Paint);
  end;
  if not Field(Scene, 'items', Items) then
    RaiseError(FieldError, 'graphics.save: the scene has no field "items"');
  DrawItems(C, Items, 'graphics.save');
end;

{ ---------------- output ---------------- }

function WriteProc(Context: Pointer; const Buffer: Pointer; Size: size_t): _bool; cdecl;
begin
  TStream(Context).WriteBuffer(Buffer^, Size);
  Result := True;
end;

var
  ProcsSet: Boolean;

function MakeWStream(Stream: TStream): sk_wstreamadapter_t;
var
  Procs: sk_wstreamadapter_procs_t;
begin
  if not ProcsSet then
  begin
    Procs.write := WriteProc;
    sk4d_wstreamadapter_set_procs(@Procs);
    ProcsSet := True;
  end;
  Result := sk4d_wstreamadapter_create(Stream);
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

procedure SavePng(Scene: TRecordObj; W, H: Double; const Path: string);
var
  Scale: Double;
  Info: sk_imageinfo_t;
  Surface: sk_surface_t;
  Image: sk_image_t;
  U: UTF8String;
  Ok: Boolean;
begin
  Scale := NumField(Scene, 'scale', 1, 'graphics.save');
  if Scale <= 0 then
    RaiseError(ArgumentError, 'graphics.save: scale must be positive');
  Info.width := Max(1, Round(W * Scale));
  Info.height := Max(1, Round(H * Scale));
  Info.color_type := RGBA8888_SK_COLORTYPE;
  Info.alpha_type := PREMUL_SK_ALPHATYPE;
  Info.color_space := 0;
  Surface := sk4d_surface_make_raster(@Info, Info.width * 4, nil);
  if Surface = 0 then
    RaiseFmt(ForeignError, 'graphics.save: cannot make a %d' + #$00D7 + '%d image', [Info.width, Info.height]);
  try
    sk4d_canvas_scale(sk4d_surface_get_canvas(Surface), Scale, Scale);
    DrawScene(sk4d_surface_get_canvas(Surface), Scene, W, H);
    Image := sk4d_surface_make_image_snapshot(Surface);
    try
      U := UTF8String(Path);
      Ok := sk4d_image_encode_to_file(Image, PAnsiChar(U), PNG_SK_ENCODEDIMAGEFORMAT, 100);
    finally
      sk4d_refcnt_unref(Image);
    end;
    if not Ok then
      RaiseFmt(IOError, 'graphics.save: cannot write "%s"', [Path]);
  finally
    sk4d_refcnt_unref(Surface);
  end;
end;

procedure SaveSvg(Scene: TRecordObj; W, H: Double; const Path: string);
var
  Stream: TFileStream;
  WS: sk_wstreamadapter_t;
  Bounds: sk_rect_t;
  C: sk_canvas_t;
begin
  Stream := OpenOutput(Path);
  try
    WS := MakeWStream(Stream);
    try
      Bounds.left := 0;
      Bounds.top := 0;
      Bounds.right := W;
      Bounds.bottom := H;
      C := sk4d_svgcanvas_make(@Bounds, WS, 0);
      try
        DrawScene(C, Scene, W, H);
      finally
        sk4d_canvas_destroy(C);   // writes the closing tags
      end;
    finally
      sk4d_wstreamadapter_destroy(WS);
    end;
  finally
    Stream.Free;
  end;
end;

procedure SavePdf(Scene: TRecordObj; W, H: Double; const Path: string);
var
  Stream: TFileStream;
  WS: sk_wstreamadapter_t;
  Doc: sk_document_t;
  C: sk_canvas_t;
begin
  Stream := OpenOutput(Path);
  try
    WS := MakeWStream(Stream);
    try
      Doc := sk4d_document_make_pdf(WS);
      if Doc = 0 then
        RaiseError(ForeignError, 'graphics.save: cannot start a PDF document');
      try
        C := sk4d_document_begin_page(Doc, W, H, nil);
        try
          DrawScene(C, Scene, W, H);
        finally
          sk4d_document_end_page(Doc);
        end;
        sk4d_document_close(Doc);
      finally
        sk4d_refcnt_unref(Doc);
      end;
    finally
      sk4d_wstreamadapter_destroy(WS);
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
    if Ext = '.png' then SavePng(Scene, W, H, Path)
    else if Ext = '.svg' then SaveSvg(Scene, W, H, Path)
    else SavePdf(Scene, W, H, Path);
  except
    // An invalid scene is found while drawing: leave no partial file.
    if FileExists(Path) then
      DeleteFile(Path);
    raise;
  end;
  Result := NothingValue;
end;

function TextWidth(const Text: string; Size: Double; const Family: string): Double;
var
  Font: sk_font_t;
begin
  EnsureSkia;
  Font := MakeFont(Family, False, Size);
  try
    Result := MeasureWith(Font, Text);
  finally
    sk4d_font_destroy(Font);
  end;
end;

var
  ShowCount: Integer;

{ graphics.show(scene) or graphics.show(scene, data): renders the scene to a
  PNG and shows it. Under a front end that sets AXON_SHOW_DIR (the IDE), the
  file goes there and a line #3"show <path>" on stderr tells the front end to
  display it; otherwise it goes to a temporary folder and opens in the
  system viewer. Returns the path. With data (plot's figure record), the
  front end also gets the data as JSON next to the PNG, under the same name
  with the extension .json, written before the #3 line; the IDE draws a
  figure with such a file in its interactive chart instead of the image. }
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
  SavePng(Scene, W, H, Path);
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
  Define('text_width', BuiltinValue('text_width', BTextWidth, 2, 3));
end;

procedure FreeTypefaces;
var
  T: sk_typeface_t;
begin
  if Typefaces = nil then
    Exit;
  if SkiaState = ssLoaded then
    for T in Typefaces.Values do
      sk4d_refcnt_unref(T);
  Typefaces.Free;
end;

initialization
  RegisterNativeModule('graphics', DefineGraphics,
    ['Renders a scene (a record of drawing items) to PNG, SVG or PDF through Skia.']);

finalization
  FreeTypefaces;
  if SkiaState = ssLoaded then
    SkFinalize;

end.
