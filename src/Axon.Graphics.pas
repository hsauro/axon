unit Axon.Graphics;

(* The core module graphics (reference, "The graphics module"): renders a
   scene, described as ordinary Axon data, to PNG, SVG or PDF through Skia.

   A scene is a record {width, height, background, scale, items}; items is a
   list of item records, each with a field kind: "polyline", "polygon",
   "rect", "markers", "text" or "group". Coordinates are in points (1/72 inch)
   from the top-left corner, with y pointing down.

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
  Axon.Errors, Axon.Values, Axon.Ops, Axon.Arrays, Axon.NativeModules;

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

function MakePaint(Color: TColor32; Stroke: Boolean; Width: Double): sk_paint_t;
begin
  Result := sk4d_paint_create();
  sk4d_paint_set_antialias(Result, True);
  sk4d_paint_set_color(Result, Color);
  if Stroke then
  begin
    sk4d_paint_set_style(Result, STROKE_SK_PAINTSTYLE);
    sk4d_paint_set_stroke_width(Result, Width);
    sk4d_paint_set_stroke_join(Result, ROUND_SK_STROKEJOIN);
    sk4d_paint_set_stroke_cap(Result, BUTT_SK_STROKECAP);
  end
  else
    sk4d_paint_set_style(Result, FILL_SK_PAINTSTYLE);
end;

procedure DrawPathWith(C: sk_canvas_t; Path: sk_path_t; Fill, Stroke: TColor32;
  Width: Double; const Dash: TArray<Double>);
var
  P: sk_paint_t;
  Effect: sk_patheffect_t;
  Intervals: TArray<Single>;
  K: Integer;
begin
  if (Fill shr 24) <> 0 then
  begin
    P := MakePaint(Fill, False, 0);
    sk4d_canvas_draw_path(C, Path, P);
    sk4d_paint_destroy(P);
  end;
  if ((Stroke shr 24) <> 0) and (Width > 0) then
  begin
    P := MakePaint(Stroke, True, Width);
    Effect := 0;
    if Length(Dash) >= 2 then
    begin
      SetLength(Intervals, Length(Dash) - Length(Dash) mod 2);
      for K := 0 to High(Intervals) do
        Intervals[K] := Dash[K];
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

procedure DrawPolyline(C: sk_canvas_t; R: TRecordObj; const Ctx: string);
var
  X, Y: TArray<Double>;
  Path: sk_path_t;
begin
  X := VecField(R, 'x', Ctx);
  Y := VecField(R, 'y', Ctx);
  CheckSameLength(X, Y, Ctx);
  Path := PolyPath(X, Y, False);
  DrawPathWith(C, Path, 0, ColorField(R, 'color', 'black', Ctx),
    NumField(R, 'width', 1, Ctx), DashField(R, Ctx));
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
    ColorField(R, 'color', 'none', Ctx), NumField(R, 'width', 1, Ctx),
    DashField(R, Ctx));
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
    ColorField(R, 'color', 'none', Ctx), NumField(R, 'width', 1, Ctx),
    DashField(R, Ctx));
  sk4d_path_destroy(Path);
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
    DrawPathWith(C, Path, 0, Stroke, NumField(R, 'width', 1.5, Ctx), nil)
  else
    DrawPathWith(C, Path, Fill, Stroke, NumField(R, 'width', 0, Ctx), nil);
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
    Paint := MakePaint(ColorField(R, 'color', 'black', Ctx), False, 0);
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

procedure DrawItems(C: sk_canvas_t; const Items: TAxValue; const Ctx: string); forward;

procedure DrawGroup(C: sk_canvas_t; R: TRecordObj; const Ctx: string);
var
  V: TAxValue;
  Clip: TRecordObj;
  Rect: sk_rect_t;
begin
  sk4d_canvas_save(C);
  try
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
    Paint := MakePaint(Bg, False, 0);
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
