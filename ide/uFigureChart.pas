unit uFigureChart;

{ Loads a figure from plot.show into the interactive chart (TSkPlotPaintBox,
  from ..\RhodyComponents\PlottingComponent).

  graphics.show writes the figure record of the plot module as JSON next to
  the PNG it shows (same name, .json) when the figure has only line and
  scatter series in 2-D (plot's interactive); the IDE draws such a figure in
  the chart, where it can be zoomed, panned and edited, and shows the PNG
  for anything else. The record's fields: title, xlabel, ylabel, xlim and
  ylim ([lo, hi] or null), grid, legend, legend_position, and series, each
  with type ("line" or "scatter"), x, y (null for NaN, a gap in the line),
  label, color and, for a line, width, style, marker and marker_size, or for
  a scatter, size and marker. Colours are "#rrggbb", "#rrggbbaa", a CSS-like
  name, or [r, g, b] / [r, g, b, a] with components from 0 to 1. }

interface

uses
  SkPlotPaintBox;

// Replaces the chart's contents with the figure in FileName. False (with the
// chart unchanged) when the file cannot be read as a figure.
function LoadFigure(Plot: TSkPlotPaintBox; const FileName: string): Boolean;

implementation

uses
  System.SysUtils, System.Math, System.JSON, System.IOUtils, System.UITypes,
  System.UIConsts,
  uPlotSeries, uPlotMapper;

function ByteOf(V: Double): Cardinal;
begin
  Result := Round(EnsureRange(V, 0, 1) * 255);
end;

function ParseColor(J: TJSONValue; Default: TAlphaColor): TAlphaColor;
var
  S: string;
  A: TJSONArray;
  R, G, B, Alpha: Cardinal;
begin
  Result := Default;
  if J is TJSONString then
  begin
    S := J.Value.Trim;
    if S.StartsWith('#') and ((S.Length = 7) or (S.Length = 9)) then
    begin
      R := StrToIntDef('$' + S.Substring(1, 2), 0);
      G := StrToIntDef('$' + S.Substring(3, 2), 0);
      B := StrToIntDef('$' + S.Substring(5, 2), 0);
      Alpha := 255;
      if S.Length = 9 then
        Alpha := StrToIntDef('$' + S.Substring(7, 2), 255);
      Result := (Alpha shl 24) or (R shl 16) or (G shl 8) or B;
    end
    else
      try
        // Names such as "black" or "red" (FMX's colour names).
        Result := StringToAlphaColor(S);
      except
        Result := Default;
      end;
  end
  else if (J is TJSONArray) and (TJSONArray(J).Count >= 3) then
  begin
    A := TJSONArray(J);
    Alpha := 255;
    if A.Count >= 4 then
      Alpha := ByteOf(A.Items[3].AsType<Double>);
    Result := (Alpha shl 24) or (ByteOf(A.Items[0].AsType<Double>) shl 16) or
      (ByteOf(A.Items[1].AsType<Double>) shl 8) or ByteOf(A.Items[2].AsType<Double>);
  end;
end;

function Num(J: TJSONValue; Default: Double): Double;
begin
  if J is TJSONNumber then
    Result := TJSONNumber(J).AsDouble
  else
    Result := Default;
end;

function Str(J: TJSONValue): string;
begin
  if J is TJSONString then
    Result := J.Value
  else
    Result := '';
end;

function Bool(J: TJSONValue; Default: Boolean): Boolean;
begin
  if J is TJSONTrue then
    Result := True
  else if J is TJSONFalse then
    Result := False
  else
    Result := Default;
end;

function MarkerShapeOf(const S: string; out Shape: TMarkerShape): Boolean;
begin
  Result := True;
  if S = 'circle' then Shape := symCircle
  else if S = 'square' then Shape := symSquare
  else if S = 'diamond' then Shape := symDiamond
  else if S = 'triangle' then Shape := symTriangle
  else if S = 'plus' then Shape := symCross
  else if S = 'cross' then Shape := symTimes
  else Result := False;
end;

function LineStyleOf(const S: string): TLineStyle;
begin
  if S = '--' then Result := ltDashDash
  else if S = ':' then Result := ltDotDot
  else if S = '-.' then Result := ltDashDot
  else Result := ltSolid;
end;

function LegendLocationOf(const S: string): TLegendLocation;
begin
  if S = 'top left' then Result := llTopLeft
  else if S = 'bottom left' then Result := llBottomLeft
  else if S = 'bottom right' then Result := llBottomRight
  else if S = 'top right' then Result := llTopRight
  // "outside" has no counterpart in the chart yet.
  else if S = 'outside' then Result := llTopRight
  else Result := llBest;
end;

function NewSeries(S: TJSONObject): TPlotSeries;
var
  Color: TAlphaColor;
  Kind, Lbl: string;
  Shape: TMarkerShape;
  XA, YA: TJSONArray;
  K: Integer;
begin
  Kind := Str(S.GetValue('type'));
  Color := ParseColor(S.GetValue('color'), TAlphaColors.Steelblue);
  Lbl := Str(S.GetValue('label'));
  Result := TPlotSeries.Create(Lbl, Color, False);
  Result.ShowInLegend := Lbl <> '';
  Result.MarkerFillColor := Color;
  Result.MarkerStrokeColor := Color;
  if Kind = 'scatter' then
  begin
    Result.LineVisible := False;
    Result.MarkerVisible := True;
    Result.MarkerSize := Num(S.GetValue('size'), 6) / 2;   // a diameter in Axon
    if MarkerShapeOf(Str(S.GetValue('marker')), Shape) then
      Result.MarkerShape := Shape;
  end
  else
  begin
    Result.LineVisible := True;
    Result.LineWidth := Num(S.GetValue('width'), 1.5);
    Result.LineStyle := LineStyleOf(Str(S.GetValue('style')));
    Result.MarkerVisible := MarkerShapeOf(Str(S.GetValue('marker')), Shape);
    if Result.MarkerVisible then
    begin
      Result.MarkerShape := Shape;
      Result.MarkerSize := Num(S.GetValue('marker_size'), 5) / 2;
    end;
  end;
  if (S.GetValue('x') is TJSONArray) and (S.GetValue('y') is TJSONArray) then
  begin
    XA := TJSONArray(S.GetValue('x'));
    YA := TJSONArray(S.GetValue('y'));
    // null (NaN in Axon) is a pen lift in the chart.
    for K := 0 to Min(XA.Count, YA.Count) - 1 do
      Result.AddXY(Num(XA.Items[K], NaN), Num(YA.Items[K], NaN));
  end;
end;

procedure SetTitle(T: TTextProperty; J: TJSONValue);
begin
  T.Text := Str(J);
  T.Visible := T.Text <> '';
end;

function LoadFigure(Plot: TSkPlotPaintBox; const FileName: string): Boolean;
var
  Root: TJSONValue;
  Fig: TJSONObject;
  Series: TJSONArray;
  Lim: TJSONArray;
  K: Integer;
begin
  Result := False;
  try
    Root := TJSONObject.ParseJSONValue(TEncoding.UTF8.GetString(TFile.ReadAllBytes(FileName)));
  except
    Exit;
  end;
  try
    if not (Root is TJSONObject) then
      Exit;
    Fig := TJSONObject(Root);
    if not (Fig.GetValue('series') is TJSONArray) then
      Exit;
    Series := TJSONArray(Fig.GetValue('series'));

    Plot.ClearSeries;
    Plot.ClearAnnotations;
    Plot.ResetZoom;
    Plot.ResetLegendPosition;
    for K := 0 to Series.Count - 1 do
      if Series.Items[K] is TJSONObject then
        Plot.AddSeries(NewSeries(TJSONObject(Series.Items[K])));

    SetTitle(Plot.ChartTitle, Fig.GetValue('title'));
    SetTitle(Plot.XAxisTitle, Fig.GetValue('xlabel'));
    SetTitle(Plot.YAxisTitle, Fig.GetValue('ylabel'));

    // Fixed limits, or the chart's autoscale.
    Plot.AutoXScaling := True;
    Plot.AutoYScaling := True;
    if (Fig.GetValue('xlim') is TJSONArray) and (TJSONArray(Fig.GetValue('xlim')).Count = 2) then
    begin
      Lim := TJSONArray(Fig.GetValue('xlim'));
      Plot.AutoXScaling := False;
      Plot.AxisLimits.MinX := Num(Lim.Items[0], 0);
      Plot.AxisLimits.MaxX := Num(Lim.Items[1], 1);
    end;
    if (Fig.GetValue('ylim') is TJSONArray) and (TJSONArray(Fig.GetValue('ylim')).Count = 2) then
    begin
      Lim := TJSONArray(Fig.GetValue('ylim'));
      Plot.AutoYScaling := False;
      Plot.AxisLimits.MinY := Num(Lim.Items[0], 0);
      Plot.AxisLimits.MaxY := Num(Lim.Items[1], 1);
    end;

    Plot.GridStyle.XMajorVisible := Bool(Fig.GetValue('grid'), True);
    Plot.GridStyle.YMajorVisible := Plot.GridStyle.XMajorVisible;
    Plot.LegendStyle.Visible := Bool(Fig.GetValue('legend'), True);
    Plot.LegendStyle.Location := LegendLocationOf(Str(Fig.GetValue('legend_position')));
    Plot.Redraw;
    Result := True;
  finally
    Root.Free;
  end;
end;

end.
