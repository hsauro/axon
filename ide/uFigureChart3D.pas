unit uFigureChart3D;

(* Loads a 3-D figure from plot.show into the interactive 3-D chart
   (TRho3DPlot, from ..\RhodyComponents\Rho3DPlotter, repository Rho3DPlotter),
   where it can be rotated, zoomed, panned and edited.

   graphics.show writes the figure record of the plot module as JSON next to
   the PNG it shows (same name, .json). A 3-D figure has three_d = true and
   series of these types: "surface" (x, y, the matrix z over the grid
   (x[j], y[i]), colormap "viridis" or "gray", edges), "line3" (x, y, z, with
   null for a gap, color, width, marker, marker_size) and "scatter3" (x, y,
   z, color, size, marker); each may have a label. The figure's title,
   xlabel, ylabel, zlabel, xlim, ylim, legend, azim and elev (degrees, the
   MATLAB convention, as the chart's) are used too. Kept apart from
   uFigureChart because the two charts' units declare enumerations with the
   same names (llTopRight, ...). *)

interface

uses
  Rho3DPlot;

// Replaces the chart's contents with the 3-D figure in FileName. False (with
// the chart unchanged) when the file cannot be read as a 3-D figure.
function LoadFigure3D(Plot: TRho3DPlot; const FileName: string): Boolean;

implementation

uses
  System.SysUtils, System.Math, System.JSON, System.IOUtils, System.UITypes,
  System.Generics.Collections, uFigureChart;

function Vector(J: TJSONValue): TArray<Double>;
var
  K: Integer;
begin
  Result := nil;
  if not (J is TJSONArray) then
    Exit;
  SetLength(Result, TJSONArray(J).Count);
  for K := 0 to High(Result) do
    Result[K] := Num(TJSONArray(J).Items[K], NaN);   // null is a gap (NaN)
end;

function Matrix(J: TJSONValue): TRho3DMatrix;
var
  K: Integer;
begin
  Result := nil;
  if not (J is TJSONArray) then
    Exit;
  SetLength(Result, TJSONArray(J).Count);
  for K := 0 to High(Result) do
    Result[K] := Vector(TJSONArray(J).Items[K]);
end;

function MarkerOf(const S: string; out Shape: TRho3DMarker): Boolean;
begin
  Result := True;
  if S = 'circle' then Shape := mkCircle
  else if S = 'square' then Shape := mkSquare
  else if S = 'diamond' then Shape := mkDiamond
  else if S = 'triangle' then Shape := mkTriangle
  else if (S = 'plus') or (S = 'cross') then Shape := mkCross
  else Result := False;
end;

procedure Label_(Series: TRho3DSeries; S: TJSONObject);
begin
  Series.Title := Str(S.GetValue('label'));
  Series.ShowInLegend := Series.Title <> '';
end;

procedure AddSeries(Plot: TRho3DPlot; S: TJSONObject; var HasSurface: Boolean);
var
  Kind: string;
  Series: TRho3DSeries;
  Shape: TRho3DMarker;
  X, Y, Z: TArray<Double>;
begin
  Kind := Str(S.GetValue('type'));
  if Kind = 'surface' then
  begin
    Series := Plot.AddSurface(Vector(S.GetValue('x')), Vector(S.GetValue('y')),
      Matrix(S.GetValue('z')));
    if Str(S.GetValue('colormap')) = 'gray' then
      Series.ColorMap := cmGray
    else
      Series.ColorMap := cmViridis;
    if Bool(S.GetValue('edges'), True) then
      Series.FillMode := fmFilledWithEdges
    else
      Series.FillMode := fmFilled;
    Label_(Series, S);
    HasSurface := True;
  end
  else if (Kind = 'line3') or (Kind = 'scatter3') then
  begin
    X := Vector(S.GetValue('x'));
    Y := Vector(S.GetValue('y'));
    Z := Vector(S.GetValue('z'));
    if Kind = 'line3' then
    begin
      Series := Plot.AddCurve(X, Y, Z);
      Series.UseGradient := False;   // one colour, as in the image
      Series.Thickness := Num(S.GetValue('width'), 1.5);
      Series.ShowLine := True;
      Series.ShowPoints := MarkerOf(Str(S.GetValue('marker')), Shape);
      if Series.ShowPoints then
      begin
        Series.MarkerShape := Shape;
        Series.PointSize := Num(S.GetValue('marker_size'), 5);   // a diameter, as in Axon
      end;
    end
    else
    begin
      Series := Plot.AddScatter(X, Y, Z);
      Series.PointSize := Num(S.GetValue('size'), 6);
      if MarkerOf(Str(S.GetValue('marker')), Shape) then
        Series.MarkerShape := Shape;
    end;
    Series.Color := ParseColor(S.GetValue('color'), TAlphaColors.Steelblue);
    Label_(Series, S);
  end;
end;

function LoadFigure3D(Plot: TRho3DPlot; const FileName: string): Boolean;
var
  Root: TJSONValue;
  Fig: TJSONObject;
  Series, Lim: TJSONArray;
  K: Integer;
  HasSurface: Boolean;
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
    if not Bool(Fig.GetValue('three_d'), False) or not (Fig.GetValue('series') is TJSONArray) then
      Exit;
    Series := TJSONArray(Fig.GetValue('series'));

    Plot.Clear;
    Plot.UseGradient := False;          // series take their own colours
    HasSurface := False;
    for K := 0 to Series.Count - 1 do
      if Series.Items[K] is TJSONObject then
        AddSeries(Plot, TJSONObject(Series.Items[K]), HasSurface);

    Plot.ChartTitle := Str(Fig.GetValue('title'));
    Plot.AxisTitleX := Str(Fig.GetValue('xlabel'));
    Plot.AxisTitleY := Str(Fig.GetValue('ylabel'));
    Plot.AxisTitleZ := Str(Fig.GetValue('zlabel'));
    Plot.LegendVisible := Bool(Fig.GetValue('legend'), True);
    Plot.ShowColorBar := HasSurface;

    // Fixed limits, or automatic (NaN).
    Plot.AutoScale;
    if (Fig.GetValue('xlim') is TJSONArray) and (TJSONArray(Fig.GetValue('xlim')).Count = 2) then
    begin
      Lim := TJSONArray(Fig.GetValue('xlim'));
      Plot.XMin := Num(Lim.Items[0], NaN);
      Plot.XMax := Num(Lim.Items[1], NaN);
    end;
    if (Fig.GetValue('ylim') is TJSONArray) and (TJSONArray(Fig.GetValue('ylim')).Count = 2) then
    begin
      Lim := TJSONArray(Fig.GetValue('ylim'));
      Plot.YMin := Num(Lim.Items[0], NaN);
      Plot.YMax := Num(Lim.Items[1], NaN);
    end;

    Plot.ResetView;
    Plot.SetView(Num(Fig.GetValue('azim'), -60), Num(Fig.GetValue('elev'), 30));
    Result := True;
  finally
    Root.Free;
  end;
end;

end.
