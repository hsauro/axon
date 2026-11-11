unit Axon.Scene;

(* Scenes: what a picture is made of, how Skia draws it, and how it travels.

   A TScene is the list of items of a picture, in Delphi terms: lines,
   polygons, ellipses, arcs, markers, text, images (already as pixels) and
   groups that shift, turn, scale and clip. It is shared by axon and the IDE
   (doc/Axon-Display-Plan.md): axon's graphics module checks an Axon scene
   record and converts it into a TScene (Axon.Graphics); this unit draws a
   TScene onto any Skia canvas, saves it as PNG, SVG or PDF, and encodes it
   as bytes for the display channel, which the IDE decodes and draws in its
   plot pane with the same code.

   Nothing here depends on the interpreter. Skia must already be loaded
   (axon loads it at the first graphics call; the IDE through System.Skia).
   Coordinates are in points from the top-left corner with y pointing down;
   angles in degrees anticlockwise as seen on the page. *)

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.Skia.API;

type
  TColor32 = Cardinal;   // ARGB; alpha 0 means nothing is drawn

  { How a path's outline is drawn. }
  TStroke = record
    Width: Double;
    Dash: TArray<Double>;
    Cap: sk_strokecap_t;
    Join: sk_strokejoin_t;
  end;

  TSceneKind = (skPolyline, skPolygon, skEllipse, skArc, skMarkers, skText, skImage, skGroup);
  TMarkerShape = (msCircle, msSquare, msDiamond, msTriangle, msPlus, msCross);
  TTextAnchor = (taStart, taMiddle, taEnd);
  TTextBaseline = (tbAlphabetic, tbMiddle, tbTop, tbBottom);

  TSceneItem = class;
  TSceneItems = TObjectList<TSceneItem>;

  (* One item. Which fields count depends on the kind:
       polyline, polygon   X, Y (a NaN breaks the line), Fill (polygon), Color, Stroke
       ellipse             CX, CY, RX, RY, Angle, Fill, Color, Stroke
       arc                 CX, CY, RX, RY, Start, Sweep, Wedge, Fill (wedge), Color, Stroke
       markers             X, Y, Shape, Size, Fill, Color, Stroke.Width
       text                CX, CY, Text, Size, Angle, Anchor, Baseline, Font, Bold, Color
       image               CX, CY (top-left), W, H, ImageWidth, ImageHeight, Pixels, Smooth
       group               CX, CY (the shift), Angle, HasScale, SX, SY, HasClip,
                           ClipX, ClipY, ClipW, ClipH, Items *)
  TSceneItem = class
  public
    Kind: TSceneKind;
    X, Y: TArray<Double>;
    CX, CY, RX, RY, Angle, Start, Sweep, W, H, Size, SX, SY: Double;
    ClipX, ClipY, ClipW, ClipH: Double;
    Wedge, Smooth, Bold, HasScale, HasClip: Boolean;
    Fill, Color: TColor32;
    Stroke: TStroke;
    Shape: TMarkerShape;
    Anchor: TTextAnchor;
    Baseline: TTextBaseline;
    Text, Font: string;
    ImageWidth, ImageHeight: Integer;
    Pixels: TArray<Cardinal>;       // RGBA8888 unpremultiplied (R in the low byte), row by row
    Items: TSceneItems;             // a group's items, owned
    constructor Create(AKind: TSceneKind);
    destructor Destroy; override;
  end;

  TScene = class
  public
    Width, Height: Double;
    Background: TColor32;
    Items: TSceneItems;             // owned
    constructor Create;
    destructor Destroy; override;
  end;

  EScene = class(Exception);

const
  (* The kinds of message on the display channel (Axon.Platform.DisplaySend):
       DisplayShow    an encoded scene, a new figure
       DisplayFrame   an encoded scene, the next frame of an animation
       DisplayFigure  a plot figure: the encoded scene's length (UInt32), the
                      scene, then the figure record as JSON (UTF-8)
       DisplayAdd     an encoded scene whose items are added to the current
                      frame: the next frame of a picture built up
                      gradually, sent without what was sent before. Unlike
                      frames, these cannot be skipped. *)
  DisplayShow = 1;
  DisplayFrame = 2;
  DisplayFigure = 3;
  DisplayAdd = 4;

{ A plain stroke: butt ends, round corners, no dashes. }
function PlainStroke(Width: Double): TStroke;

{ Draws the scene onto a canvas whose units are points (scale it first for
  pixels), background first. }
procedure DrawScene(C: sk_canvas_t; Scene: TScene);

{ Writes the scene as a PNG, Scale pixels per point. EScene if the image
  cannot be made or written. }
procedure SavePng(Scene: TScene; Scale: Double; const Path: string);
{ Writes the scene as SVG or as a one-page PDF to a stream. }
procedure SaveSvg(Scene: TScene; Stream: TStream);
procedure SavePdf(Scene: TScene; Stream: TStream);

{ Releases the typefaces kept for text, while Skia is still loaded. }
procedure ReleaseTypefaces;

{ The width of Text in points at Size in the font Family (for layout). }
function MeasureText(const Text: string; Size: Double; const Family: string;
  Bold: Boolean): Double;

{ The scene as bytes, and back. DecodeScene raises EScene on bytes that are
  not a scene. }
function EncodeScene(Scene: TScene): TBytes;
function DecodeScene(const Data: TBytes): TScene;

implementation

uses
  System.Math;

{ ---------------- the model ---------------- }

constructor TSceneItem.Create(AKind: TSceneKind);
begin
  inherited Create;
  Kind := AKind;
  Stroke := PlainStroke(1);
  SX := 1;
  SY := 1;
  if AKind = skGroup then
    Items := TSceneItems.Create(True);
end;

destructor TSceneItem.Destroy;
begin
  Items.Free;
  inherited;
end;

constructor TScene.Create;
begin
  inherited Create;
  Width := 640;
  Height := 480;
  Background := $FFFFFFFF;
  Items := TSceneItems.Create(True);
end;

destructor TScene.Destroy;
begin
  Items.Free;
  inherited;
end;

function PlainStroke(Width: Double): TStroke;
begin
  Result.Width := Width;
  Result.Dash := nil;
  Result.Cap := BUTT_SK_STROKECAP;
  Result.Join := ROUND_SK_STROKEJOIN;
end;

{ ---------------- drawing ---------------- }

var
  Typefaces: TDictionary<string, sk_typeface_t>;

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

procedure ReleaseTypefaces;
var
  T: sk_typeface_t;
begin
  if Typefaces = nil then
    Exit;
  for T in Typefaces.Values do
    sk4d_refcnt_unref(T);
  FreeAndNil(Typefaces);
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

procedure DrawPoly(C: sk_canvas_t; Item: TSceneItem);
var
  Path: sk_path_t;
begin
  Path := PolyPath(Item.X, Item.Y, Item.Kind = skPolygon);
  try
    if Item.Kind = skPolygon then
      DrawPathWith(C, Path, Item.Fill, Item.Color, Item.Stroke)
    else
      DrawPathWith(C, Path, 0, Item.Color, Item.Stroke);
  finally
    sk4d_path_destroy(Path);
  end;
end;

{ An ellipse (turned by Angle about its centre) or an arc from Start through
  Sweep, open, or with Wedge closed through the centre. }
procedure DrawRound(C: sk_canvas_t; Item: TSceneItem);
var
  B: sk_pathbuilder_t;
  Path: sk_path_t;
  Oval: sk_rect_t;
  Pt: sk_point_t;
begin
  Oval.left := Item.CX - Item.RX;
  Oval.top := Item.CY - Item.RY;
  Oval.right := Item.CX + Item.RX;
  Oval.bottom := Item.CY + Item.RY;
  B := sk4d_pathbuilder_create();
  try
    if Item.Kind = skArc then
    begin
      // Skia's angles run clockwise on the page (y points down).
      if Item.Wedge then
      begin
        Pt.x := Item.CX;
        Pt.y := Item.CY;
        sk4d_pathbuilder_move_to(B, @Pt);
        sk4d_pathbuilder_arc_to2(B, @Oval, -Item.Start, -Item.Sweep, False);
        sk4d_pathbuilder_close(B);
      end
      else
        sk4d_pathbuilder_add_arc(B, @Oval, -Item.Start, -Item.Sweep);
    end
    else
      sk4d_pathbuilder_add_oval(B, @Oval, CW_SK_PATHDIRECTION, 0);
    Path := sk4d_pathbuilder_detach(B);
  finally
    sk4d_pathbuilder_destroy(B);
  end;
  try
    sk4d_canvas_save(C);
    try
      if (Item.Kind = skEllipse) and (Item.Angle <> 0) then
        sk4d_canvas_rotate2(C, -Item.Angle, Item.CX, Item.CY);
      if (Item.Kind = skArc) and not Item.Wedge then
        DrawPathWith(C, Path, 0, Item.Color, Item.Stroke)
      else
        DrawPathWith(C, Path, Item.Fill, Item.Color, Item.Stroke);
    finally
      sk4d_canvas_restore(C);
    end;
  finally
    sk4d_path_destroy(Path);
  end;
end;

procedure DrawMarkers(C: sk_canvas_t; Item: TSceneItem);
var
  H: Double;
  B: sk_pathbuilder_t;
  Path: sk_path_t;
  K: Integer;
  X, Y: Double;

  procedure Pt(PX, PY: Double; Move: Boolean);
  var
    P: sk_point_t;
  begin
    P.x := PX;
    P.y := PY;
    if Move then sk4d_pathbuilder_move_to(B, @P) else sk4d_pathbuilder_line_to(B, @P);
  end;

begin
  H := Item.Size / 2;
  B := sk4d_pathbuilder_create();
  for K := 0 to High(Item.X) do
  begin
    X := Item.X[K];
    Y := Item.Y[K];
    if not (IsFinite(X) and IsFinite(Y)) then
      Continue;
    case Item.Shape of
      msCircle:
        sk4d_pathbuilder_add_circle(B, X, Y, H, CW_SK_PATHDIRECTION);
      msSquare:
        begin
          Pt(X - H, Y - H, True); Pt(X + H, Y - H, False);
          Pt(X + H, Y + H, False); Pt(X - H, Y + H, False);
          sk4d_pathbuilder_close(B);
        end;
      msDiamond:
        begin
          Pt(X, Y - H, True); Pt(X + H, Y, False);
          Pt(X, Y + H, False); Pt(X - H, Y, False);
          sk4d_pathbuilder_close(B);
        end;
      msTriangle:
        begin
          Pt(X, Y - H, True); Pt(X + H, Y + H, False);
          Pt(X - H, Y + H, False);
          sk4d_pathbuilder_close(B);
        end;
      msPlus:
        begin
          Pt(X - H, Y, True); Pt(X + H, Y, False);
          Pt(X, Y - H, True); Pt(X, Y + H, False);
        end;
      msCross:
        begin
          Pt(X - H, Y - H, True); Pt(X + H, Y + H, False);
          Pt(X - H, Y + H, True); Pt(X + H, Y - H, False);
        end;
    end;
  end;
  Path := sk4d_pathbuilder_detach(B);
  sk4d_pathbuilder_destroy(B);
  try
    if Item.Shape in [msPlus, msCross] then
      DrawPathWith(C, Path, 0, Item.Color, PlainStroke(Item.Stroke.Width))
    else
      DrawPathWith(C, Path, Item.Fill, Item.Color, PlainStroke(Item.Stroke.Width));
  finally
    sk4d_path_destroy(Path);
  end;
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

function MeasureText(const Text: string; Size: Double; const Family: string;
  Bold: Boolean): Double;
var
  Font: sk_font_t;
begin
  Font := MakeFont(Family, Bold, Size);
  try
    Result := MeasureWith(Font, Text);
  finally
    sk4d_font_destroy(Font);
  end;
end;

procedure DrawText(C: sk_canvas_t; Item: TSceneItem);
var
  W, DX, DY: Double;
  Font: sk_font_t;
  Paint: sk_paint_t;
  Metrics: sk_fontmetrics_t;
  U: UTF8String;
begin
  if Item.Text = '' then
    Exit;
  Font := MakeFont(Item.Font, Item.Bold, Item.Size);
  try
    W := MeasureWith(Font, Item.Text);
    case Item.Anchor of
      taMiddle: DX := -W / 2;
      taEnd: DX := -W;
    else
      DX := 0;
    end;
    sk4d_font_get_metrics(Font, @Metrics);
    case Item.Baseline of
      tbMiddle: DY := Metrics.cap_height / 2;
      tbTop: DY := Metrics.cap_height;
      tbBottom: DY := -Metrics.descent;
    else
      DY := 0;
    end;
    Paint := MakePaint(Item.Color, False, PlainStroke(0));
    U := UTF8String(Item.Text);
    sk4d_canvas_save(C);
    sk4d_canvas_translate(C, Item.CX, Item.CY);
    if Item.Angle <> 0 then
      sk4d_canvas_rotate(C, -Item.Angle);   // angles count anticlockwise, y points down
    sk4d_canvas_draw_simple_text(C, PAnsiChar(U), Length(U), UTF8_SK_TEXTENCODING, DX, DY, Font, Paint);
    sk4d_canvas_restore(C);
    sk4d_paint_destroy(Paint);
  finally
    sk4d_font_destroy(Font);
  end;
end;

procedure DrawImage(C: sk_canvas_t; Item: TSceneItem);
var
  Info: sk_imageinfo_t;
  Pixmap: sk_pixmap_t;
  Image: sk_image_t;
  Src, Dest: sk_rect_t;
  Sampling: sk_samplingoptions_t;
begin
  if (Item.ImageWidth <= 0) or (Item.ImageHeight <= 0) or
    (Length(Item.Pixels) < Item.ImageWidth * Item.ImageHeight) then
    Exit;
  Info.width := Item.ImageWidth;
  Info.height := Item.ImageHeight;
  Info.color_type := RGBA8888_SK_COLORTYPE;
  Info.alpha_type := UNPREMUL_SK_ALPHATYPE;
  Info.color_space := 0;
  Pixmap := sk4d_pixmap_create(@Info, @Item.Pixels[0], Item.ImageWidth * 4);
  if Pixmap = 0 then
    raise EScene.CreateFmt('cannot make a %d' + #$00D7 + '%d image',
      [Item.ImageWidth, Item.ImageHeight]);
  try
    Image := sk4d_image_make_raster_copy(Pixmap);
  finally
    sk4d_pixmap_destroy(Pixmap);
  end;
  if Image = 0 then
    raise EScene.CreateFmt('cannot make a %d' + #$00D7 + '%d image',
      [Item.ImageWidth, Item.ImageHeight]);
  try
    Src.left := 0;
    Src.top := 0;
    Src.right := Item.ImageWidth;
    Src.bottom := Item.ImageHeight;
    Dest.left := Item.CX;
    Dest.top := Item.CY;
    Dest.right := Item.CX + Item.W;
    Dest.bottom := Item.CY + Item.H;
    FillChar(Sampling, SizeOf(Sampling), 0);
    if Item.Smooth then
      Sampling.filter := LINEAR_SK_FILTERMODE
    else
      Sampling.filter := NEAREST_SK_FILTERMODE;
    Sampling.mipmap := NONE_SK_MIPMAPMODE;
    sk4d_canvas_draw_image_rect(C, Image, @Src, @Dest, @Sampling, 0, FAST_SK_SRCRECTCONSTRAINT);
  finally
    sk4d_refcnt_unref(Image);
  end;
end;

procedure DrawItems(C: sk_canvas_t; Items: TSceneItems); forward;

{ A group: shifted by (CX, CY), turned by Angle and scaled by (SX, SY), in
  that order seen from the page, then clipped in its own coordinates. }
procedure DrawGroup(C: sk_canvas_t; Item: TSceneItem);
var
  Rect: sk_rect_t;
begin
  sk4d_canvas_save(C);
  try
    sk4d_canvas_translate(C, Item.CX, Item.CY);
    if Item.Angle <> 0 then
      sk4d_canvas_rotate(C, -Item.Angle);
    if Item.HasScale then
      sk4d_canvas_scale(C, Item.SX, Item.SY);
    if Item.HasClip then
    begin
      Rect.left := Item.ClipX;
      Rect.top := Item.ClipY;
      Rect.right := Item.ClipX + Item.ClipW;
      Rect.bottom := Item.ClipY + Item.ClipH;
      sk4d_canvas_clip_rect(C, @Rect, INTERSECT_SK_CLIPOP, True);
    end;
    DrawItems(C, Item.Items);
  finally
    sk4d_canvas_restore(C);
  end;
end;

procedure DrawItems(C: sk_canvas_t; Items: TSceneItems);
var
  Item: TSceneItem;
begin
  for Item in Items do
    case Item.Kind of
      skPolyline, skPolygon: DrawPoly(C, Item);
      skEllipse, skArc: DrawRound(C, Item);
      skMarkers: DrawMarkers(C, Item);
      skText: DrawText(C, Item);
      skImage: DrawImage(C, Item);
      skGroup: DrawGroup(C, Item);
    end;
end;

procedure DrawScene(C: sk_canvas_t; Scene: TScene);
var
  Paint: sk_paint_t;
  Rect: sk_rect_t;
begin
  if (Scene.Background shr 24) <> 0 then
  begin
    Rect.left := 0;
    Rect.top := 0;
    Rect.right := Scene.Width;
    Rect.bottom := Scene.Height;
    Paint := MakePaint(Scene.Background, False, PlainStroke(0));
    sk4d_canvas_draw_rect(C, @Rect, Paint);
    sk4d_paint_destroy(Paint);
  end;
  DrawItems(C, Scene.Items);
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

procedure SavePng(Scene: TScene; Scale: Double; const Path: string);
var
  Info: sk_imageinfo_t;
  Surface: sk_surface_t;
  Image: sk_image_t;
  U: UTF8String;
  Ok: Boolean;
begin
  Info.width := Max(1, Round(Scene.Width * Scale));
  Info.height := Max(1, Round(Scene.Height * Scale));
  Info.color_type := RGBA8888_SK_COLORTYPE;
  Info.alpha_type := PREMUL_SK_ALPHATYPE;
  Info.color_space := 0;
  Surface := sk4d_surface_make_raster(@Info, Info.width * 4, nil);
  if Surface = 0 then
    raise EScene.CreateFmt('cannot make a %d' + #$00D7 + '%d image', [Info.width, Info.height]);
  try
    sk4d_canvas_scale(sk4d_surface_get_canvas(Surface), Scale, Scale);
    DrawScene(sk4d_surface_get_canvas(Surface), Scene);
    Image := sk4d_surface_make_image_snapshot(Surface);
    try
      U := UTF8String(Path);
      Ok := sk4d_image_encode_to_file(Image, PAnsiChar(U), PNG_SK_ENCODEDIMAGEFORMAT, 100);
    finally
      sk4d_refcnt_unref(Image);
    end;
    if not Ok then
      raise EScene.CreateFmt('cannot write "%s"', [Path]);
  finally
    sk4d_refcnt_unref(Surface);
  end;
end;

procedure SaveSvg(Scene: TScene; Stream: TStream);
var
  WS: sk_wstreamadapter_t;
  Bounds: sk_rect_t;
  C: sk_canvas_t;
begin
  WS := MakeWStream(Stream);
  try
    Bounds.left := 0;
    Bounds.top := 0;
    Bounds.right := Scene.Width;
    Bounds.bottom := Scene.Height;
    C := sk4d_svgcanvas_make(@Bounds, WS, 0);
    try
      DrawScene(C, Scene);
    finally
      sk4d_canvas_destroy(C);   // writes the closing tags
    end;
  finally
    sk4d_wstreamadapter_destroy(WS);
  end;
end;

procedure SavePdf(Scene: TScene; Stream: TStream);
var
  WS: sk_wstreamadapter_t;
  Doc: sk_document_t;
  C: sk_canvas_t;
begin
  WS := MakeWStream(Stream);
  try
    Doc := sk4d_document_make_pdf(WS);
    if Doc = 0 then
      raise EScene.Create('cannot start a PDF document');
    try
      C := sk4d_document_begin_page(Doc, Scene.Width, Scene.Height, nil);
      try
        DrawScene(C, Scene);
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
end;

{ ---------------- encoding ---------------- }

(* A scene as bytes, little-endian: the magic 'AXS1', width and height
   (doubles), background (UInt32), the items. An item is its kind (a byte)
   and then the fields that kind uses, in the order written below. Numbers
   are doubles, counts and colours UInt32, flags and enumerations bytes,
   strings a UInt32 byte count and UTF-8, number vectors a count and the
   doubles, an image's pixels its width and height (UInt32) and the RGBA
   bytes, a group's items a count and the items. *)

const
  SceneMagic: array[0..3] of Byte = (Ord('A'), Ord('X'), Ord('S'), Ord('1'));

type
  TSceneWriter = class
  private
    FStream: TBytesStream;
  public
    constructor Create;
    destructor Destroy; override;
    procedure U8(V: Byte);
    procedure U32(V: Cardinal);
    procedure F64(V: Double);
    procedure Str(const S: string);
    procedure Vec(const V: TArray<Double>);
    procedure StrokeOf(const S: TStroke);
    procedure Item(It: TSceneItem);
    function Bytes: TBytes;
  end;

  TSceneReader = class
  private
    FData: TBytes;
    FPos: Integer;
    procedure Need(N: Int64);
  public
    constructor Create(const Data: TBytes);
    function U8: Byte;
    function U32: Cardinal;
    function F64: Double;
    function Str: string;
    function Vec: TArray<Double>;
    function StrokeOf: TStroke;
    function Item(Depth: Integer): TSceneItem;
    property Pos: Integer read FPos;
  end;

constructor TSceneWriter.Create;
begin
  inherited Create;
  FStream := TBytesStream.Create;
end;

destructor TSceneWriter.Destroy;
begin
  FStream.Free;
  inherited;
end;

procedure TSceneWriter.U8(V: Byte);
begin
  FStream.WriteBuffer(V, 1);
end;

procedure TSceneWriter.U32(V: Cardinal);
begin
  FStream.WriteBuffer(V, 4);
end;

procedure TSceneWriter.F64(V: Double);
begin
  FStream.WriteBuffer(V, 8);
end;

procedure TSceneWriter.Str(const S: string);
var
  B: TBytes;
begin
  B := TEncoding.UTF8.GetBytes(S);
  U32(Length(B));
  if Length(B) > 0 then
    FStream.WriteBuffer(B[0], Length(B));
end;

procedure TSceneWriter.Vec(const V: TArray<Double>);
begin
  U32(Length(V));
  if Length(V) > 0 then
    FStream.WriteBuffer(V[0], Length(V) * 8);
end;

procedure TSceneWriter.StrokeOf(const S: TStroke);
begin
  F64(S.Width);
  Vec(S.Dash);
  U8(Ord(S.Cap));
  U8(Ord(S.Join));
end;

procedure TSceneWriter.Item(It: TSceneItem);
var
  Child: TSceneItem;
begin
  U8(Ord(It.Kind));
  case It.Kind of
    skPolyline, skPolygon:
      begin
        Vec(It.X);
        Vec(It.Y);
        U32(It.Fill);
        U32(It.Color);
        StrokeOf(It.Stroke);
      end;
    skEllipse, skArc:
      begin
        F64(It.CX); F64(It.CY); F64(It.RX); F64(It.RY);
        F64(It.Angle); F64(It.Start); F64(It.Sweep);
        U8(Ord(It.Wedge));
        U32(It.Fill);
        U32(It.Color);
        StrokeOf(It.Stroke);
      end;
    skMarkers:
      begin
        Vec(It.X);
        Vec(It.Y);
        U8(Ord(It.Shape));
        F64(It.Size);
        U32(It.Fill);
        U32(It.Color);
        F64(It.Stroke.Width);
      end;
    skText:
      begin
        F64(It.CX); F64(It.CY);
        Str(It.Text);
        F64(It.Size); F64(It.Angle);
        U8(Ord(It.Anchor));
        U8(Ord(It.Baseline));
        Str(It.Font);
        U8(Ord(It.Bold));
        U32(It.Color);
      end;
    skImage:
      begin
        F64(It.CX); F64(It.CY); F64(It.W); F64(It.H);
        U32(It.ImageWidth);
        U32(It.ImageHeight);
        if Length(It.Pixels) > 0 then
          FStream.WriteBuffer(It.Pixels[0], Length(It.Pixels) * 4);
        U8(Ord(It.Smooth));
      end;
    skGroup:
      begin
        F64(It.CX); F64(It.CY); F64(It.Angle);
        U8(Ord(It.HasScale));
        F64(It.SX); F64(It.SY);
        U8(Ord(It.HasClip));
        F64(It.ClipX); F64(It.ClipY); F64(It.ClipW); F64(It.ClipH);
        U32(It.Items.Count);
        for Child in It.Items do
          Item(Child);
      end;
  end;
end;

function TSceneWriter.Bytes: TBytes;
begin
  Result := Copy(FStream.Bytes, 0, FStream.Size);
end;

function EncodeScene(Scene: TScene): TBytes;
var
  W: TSceneWriter;
  It: TSceneItem;
begin
  W := TSceneWriter.Create;
  try
    W.FStream.WriteBuffer(SceneMagic[0], 4);
    W.F64(Scene.Width);
    W.F64(Scene.Height);
    W.U32(Scene.Background);
    W.U32(Scene.Items.Count);
    for It in Scene.Items do
      W.Item(It);
    Result := W.Bytes;
  finally
    W.Free;
  end;
end;

constructor TSceneReader.Create(const Data: TBytes);
begin
  inherited Create;
  FData := Data;
end;

procedure TSceneReader.Need(N: Int64);
begin
  if (N < 0) or (FPos + N > Length(FData)) then
    raise EScene.Create('scene data ends early');
end;

function TSceneReader.U8: Byte;
begin
  Need(1);
  Result := FData[FPos];
  Inc(FPos);
end;

function TSceneReader.U32: Cardinal;
begin
  Need(4);
  Move(FData[FPos], Result, 4);
  Inc(FPos, 4);
end;

function TSceneReader.F64: Double;
begin
  Need(8);
  Move(FData[FPos], Result, 8);
  Inc(FPos, 8);
end;

function TSceneReader.Str: string;
var
  N: Cardinal;
begin
  N := U32;
  Need(N);
  Result := TEncoding.UTF8.GetString(FData, FPos, N);
  Inc(FPos, N);
end;

function TSceneReader.Vec: TArray<Double>;
var
  N: Cardinal;
begin
  N := U32;
  Need(Int64(N) * 8);
  SetLength(Result, N);
  if N > 0 then
    Move(FData[FPos], Result[0], N * 8);
  Inc(FPos, N * 8);
end;

function TSceneReader.StrokeOf: TStroke;
var
  B: Integer;
begin
  Result.Width := F64;
  Result.Dash := Vec;
  B := U8;
  if B > Ord(High(sk_strokecap_t)) then
    raise EScene.Create('scene data has an unknown cap');
  Result.Cap := sk_strokecap_t(B);
  B := U8;
  if B > Ord(High(sk_strokejoin_t)) then
    raise EScene.Create('scene data has an unknown join');
  Result.Join := sk_strokejoin_t(B);
end;

function TSceneReader.Item(Depth: Integer): TSceneItem;
var
  K: Integer;
  B: Integer;
  N, I: Cardinal;
begin
  if Depth > 1000 then
    raise EScene.Create('scene data nests too deeply');
  K := U8;
  if K > Ord(High(TSceneKind)) then
    raise EScene.CreateFmt('scene data has an unknown item kind %d', [K]);
  Result := TSceneItem.Create(TSceneKind(K));
  try
    case Result.Kind of
      skPolyline, skPolygon:
        begin
          Result.X := Vec;
          Result.Y := Vec;
          Result.Fill := U32;
          Result.Color := U32;
          Result.Stroke := StrokeOf;
        end;
      skEllipse, skArc:
        begin
          Result.CX := F64; Result.CY := F64; Result.RX := F64; Result.RY := F64;
          Result.Angle := F64; Result.Start := F64; Result.Sweep := F64;
          Result.Wedge := U8 <> 0;
          Result.Fill := U32;
          Result.Color := U32;
          Result.Stroke := StrokeOf;
        end;
      skMarkers:
        begin
          Result.X := Vec;
          Result.Y := Vec;
          B := U8;
          if B > Ord(High(TMarkerShape)) then
            raise EScene.Create('scene data has an unknown marker shape');
          Result.Shape := TMarkerShape(B);
          Result.Size := F64;
          Result.Fill := U32;
          Result.Color := U32;
          Result.Stroke := PlainStroke(F64);
        end;
      skText:
        begin
          Result.CX := F64; Result.CY := F64;
          Result.Text := Str;
          Result.Size := F64; Result.Angle := F64;
          B := U8;
          if B > Ord(High(TTextAnchor)) then
            raise EScene.Create('scene data has an unknown anchor');
          Result.Anchor := TTextAnchor(B);
          B := U8;
          if B > Ord(High(TTextBaseline)) then
            raise EScene.Create('scene data has an unknown baseline');
          Result.Baseline := TTextBaseline(B);
          Result.Font := Str;
          Result.Bold := U8 <> 0;
          Result.Color := U32;
        end;
      skImage:
        begin
          Result.CX := F64; Result.CY := F64; Result.W := F64; Result.H := F64;
          Result.ImageWidth := U32;
          Result.ImageHeight := U32;
          if (Result.ImageWidth < 0) or (Result.ImageHeight < 0) then
            raise EScene.Create('scene data has a bad image size');
          N := Cardinal(Result.ImageWidth) * Cardinal(Result.ImageHeight);
          Need(Int64(N) * 4);
          SetLength(Result.Pixels, N);
          if N > 0 then
            Move(FData[FPos], Result.Pixels[0], N * 4);
          Inc(FPos, N * 4);
          Result.Smooth := U8 <> 0;
        end;
      skGroup:
        begin
          Result.CX := F64; Result.CY := F64; Result.Angle := F64;
          Result.HasScale := U8 <> 0;
          Result.SX := F64; Result.SY := F64;
          Result.HasClip := U8 <> 0;
          Result.ClipX := F64; Result.ClipY := F64; Result.ClipW := F64; Result.ClipH := F64;
          N := U32;
          for I := 1 to N do
            Result.Items.Add(Item(Depth + 1));
        end;
    end;
    if (Result.Kind in [skPolyline, skPolygon, skMarkers]) and
      (Length(Result.X) <> Length(Result.Y)) then
      raise EScene.Create('scene data has x and y of different lengths');
  except
    Result.Free;
    raise;
  end;
end;

function DecodeScene(const Data: TBytes): TScene;
var
  R: TSceneReader;
  N, I: Cardinal;
begin
  if (Length(Data) < 4) or not CompareMem(@Data[0], @SceneMagic[0], 4) then
    raise EScene.Create('not scene data');
  R := TSceneReader.Create(Data);
  try
    R.FPos := 4;
    Result := TScene.Create;
    try
      Result.Width := R.F64;
      Result.Height := R.F64;
      Result.Background := R.U32;
      N := R.U32;
      for I := 1 to N do
        Result.Items.Add(R.Item(0));
      if R.Pos <> Length(Data) then
        raise EScene.Create('scene data has bytes left over');
    except
      Result.Free;
      raise;
    end;
  finally
    R.Free;
  end;
end;

initialization

finalization
  // Without ReleaseTypefaces (Skia may be gone by now): only the dictionary.
  Typefaces.Free;

end.
