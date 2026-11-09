unit uFigureExport;

(* Draws a figure as it is on screen, with the zooming, panning, rotating and
   editing done in its charts, to a PNG, a PDF, an SVG or a bitmap.

   The view is a chart (TSkPlotPaintBox or TRho3DPlot) or a grid of them from
   uFigureGrid (title label and charts). Each chart draws itself onto the
   target canvas with RenderTo, in its place within the view, so a PDF or SVG
   holds vectors and a PNG can be drawn at any scale. *)

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Skia,
  FMX.Types, FMX.Controls, FMX.Graphics;

// True when View is a chart, or holds charts, that can be drawn this way.
function CanExportView(View: TControl): Boolean;
// PNG at Scale pixels per point.
procedure SaveViewPng(View: TControl; const FileName: string; Scale: Single = 2);
procedure SaveViewPdf(View: TControl; const FileName: string);
procedure SaveViewSvg(View: TControl; const FileName: string);
// A bitmap at Scale pixels per point; the caller frees it.
function ViewBitmap(View: TControl; Scale: Single = 2): TBitmap;

implementation

uses
  System.Math, FMX.StdCtrls, FMX.Skia, SkPlotPaintBox, Rho3DPlot;

procedure FindCharts(Parent: TFmxObject; List: TList);
var
  K: Integer;
  C: TFmxObject;
begin
  for K := 0 to Parent.ChildrenCount - 1 do
  begin
    C := Parent.Children[K];
    if (C is TSkPlotPaintBox) or (C is TRho3DPlot) then
      List.Add(C)
    else
      FindCharts(C, List);
  end;
end;

function FindTitle(View: TControl): TLabel;
var
  K: Integer;
begin
  Result := nil;
  for K := 0 to View.ChildrenCount - 1 do
    if View.Children[K] is TLabel then
      Exit(TLabel(View.Children[K]));
end;

function CanExportView(View: TControl): Boolean;
var
  List: TList;
begin
  if View = nil then
    Exit(False);
  if (View is TSkPlotPaintBox) or (View is TRho3DPlot) then
    Exit(True);
  List := TList.Create;
  try
    FindCharts(View, List);
    Result := List.Count > 0;
  finally
    List.Free;
  end;
end;

// Draws the view onto ACanvas, its top left at (0, 0), in points.
procedure DrawView(View: TControl; const ACanvas: ISkCanvas);
var
  List: TList;
  K: Integer;
  C: TControl;
  Origin, P: TPointF;
  R: TRectF;
  Paint: ISkPaint;
  Font: ISkFont;
  Title: TLabel;
  W: Single;
begin
  if View is TSkPlotPaintBox then
  begin
    TSkPlotPaintBox(View).RenderTo(ACanvas, TRectF.Create(0, 0, View.Width, View.Height));
    Exit;
  end;
  if View is TRho3DPlot then
  begin
    TRho3DPlot(View).RenderTo(ACanvas, TRectF.Create(0, 0, View.Width, View.Height));
    Exit;
  end;
  // A grid: white behind it, the title, then every chart in its place.
  Paint := TSkPaint.Create;
  Paint.Color := TAlphaColors.White;
  ACanvas.DrawRect(TRectF.Create(0, 0, View.Width, View.Height), Paint);
  Origin := View.LocalToAbsolute(TPointF.Zero);
  Title := FindTitle(View);
  if (Title <> nil) and (Title.Text <> '') then
  begin
    Font := TSkFont.Create(TSkTypeface.MakeFromName(Title.TextSettings.Font.Family,
      TSkFontStyle.Bold), 13);
    Paint := TSkPaint.Create;
    Paint.Color := TAlphaColors.Black;
    W := Font.MeasureText(Title.Text, Paint);
    P := Title.LocalToAbsolute(TPointF.Zero) - Origin;
    ACanvas.DrawSimpleText(Title.Text, Max(0, (View.Width - W) / 2),
      P.Y + Title.Height / 2 + 13 * 0.35, Font, Paint);
  end;
  List := TList.Create;
  try
    FindCharts(View, List);
    for K := 0 to List.Count - 1 do
    begin
      C := TControl(List[K]);
      P := C.LocalToAbsolute(TPointF.Zero) - Origin;
      R := TRectF.Create(P.X, P.Y, P.X + C.Width, P.Y + C.Height);
      if C is TSkPlotPaintBox then
        TSkPlotPaintBox(C).RenderTo(ACanvas, R)
      else
        TRho3DPlot(C).RenderTo(ACanvas, R);
    end;
  finally
    List.Free;
  end;
end;

function MakeImage(View: TControl; Scale: Single): ISkImage;
var
  Surface: ISkSurface;
begin
  Result := nil;
  Surface := TSkSurface.MakeRaster(Max(1, Round(View.Width * Scale)),
    Max(1, Round(View.Height * Scale)));
  if Surface = nil then
    Exit;
  Surface.Canvas.Clear(TAlphaColors.White);
  Surface.Canvas.Scale(Scale, Scale);
  DrawView(View, Surface.Canvas);
  Result := Surface.MakeImageSnapshot;
end;

procedure SaveViewPng(View: TControl; const FileName: string; Scale: Single);
var
  Image: ISkImage;
begin
  Image := MakeImage(View, Scale);
  if Image = nil then
    raise Exception.Create('cannot draw the figure');
  Image.EncodeToFile(FileName);
end;

function ViewBitmap(View: TControl; Scale: Single): TBitmap;
var
  Image: ISkImage;
begin
  Image := MakeImage(View, Scale);
  if Image = nil then
    raise Exception.Create('cannot draw the figure');
  Result := SkImageToBitmap(Image);
end;

procedure SaveViewPdf(View: TControl; const FileName: string);
var
  Stream: TFileStream;
  Document: ISkDocument;
begin
  Stream := TFileStream.Create(FileName, fmCreate);
  try
    Document := TSkDocument.MakePDF(Stream);
    DrawView(View, Document.BeginPage(View.Width, View.Height));
    Document.EndPage;
    Document.Close;
    Document := nil;
  finally
    Stream.Free;
  end;
end;

procedure SaveViewSvg(View: TControl; const FileName: string);
var
  Stream: TFileStream;
  Canvas: ISkCanvas;
begin
  Stream := TFileStream.Create(FileName, fmCreate);
  try
    Canvas := TSkSVGCanvas.Make(TRectF.Create(0, 0, View.Width, View.Height), Stream);
    DrawView(View, Canvas);
    Canvas := nil;      // writes the SVG
  finally
    Stream.Free;
  end;
end;

end.
