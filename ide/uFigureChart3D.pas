unit uFigureChart3D;

(* Loads a 3-D figure from plot.show into the interactive 3-D chart
   (TRho3DPlot, from ..\RhodyComponents\Rho3DPlotter, repository Rho3DPlotter),
   where it can be rotated, zoomed, panned and edited.

   graphics.show writes the figure record of the plot module as JSON next to
   the PNG it shows (same name, .json). A 3-D figure has three_d = true and
   series of these types: "surface" (x, y, the matrix z over the grid
   (x[j], y[i]), colormap by name, c from color_by, edges), "bar3" (the same,
   a bar from 0 to z[i][j] at each grid point, width a fraction of the grid
   spacing, color for bars in one colour, xnames and ynames for named
   axes), "line3" (x, y, z, with
   null for a gap, color, width, marker, marker_size) and "scatter3" (x, y,
   z, color, size, marker); each may have a label. The figure's title,
   xlabel, ylabel, zlabel, xlim, ylim, legend, azim and elev (degrees, the
   MATLAB convention, as the chart's) are used too. Kept apart from
   uFigureChart because the two charts' units declare enumerations with the
   same names (llTopRight, ...). *)

interface

uses
  System.JSON, Rho3DPlot;

// Replaces the chart's contents with the 3-D figure in FileName. False (with
// the chart unchanged) when the file cannot be read as a 3-D figure.
function LoadFigure3D(Plot: TRho3DPlot; const FileName: string): Boolean;
// The same from a parsed figure record (a cell of a grid, see uFigureGrid).
function LoadFigure3DObj(Plot: TRho3DPlot; Fig: TJSONObject): Boolean;
// The same for a figure given as JSON text (from the display channel).
function LoadFigure3DText(Plot: TRho3DPlot; const Json: string): Boolean;

implementation

uses
  System.SysUtils, System.Math, System.IOUtils, System.UITypes, Rho3DColorMaps,
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

// Names along axis Axis at 1, 2, ..., when J is a list of strings.
procedure NamedTicks(Plot: TRho3DPlot; Axis: Integer; J: TJSONValue);
var
  Pos: TArray<Double>;
  Names: TArray<string>;
  K: Integer;
begin
  if not (J is TJSONArray) then
    Exit;
  SetLength(Pos, TJSONArray(J).Count);
  SetLength(Names, TJSONArray(J).Count);
  for K := 0 to High(Pos) do
  begin
    Pos[K] := K + 1;
    Names[K] := Str(TJSONArray(J).Items[K]);
  end;
  Plot.SetTickLabels(Axis, Pos, Names);
end;

// The colour range, when J is clim, [lo, hi]: the chart has one for all
// its series.
procedure ColorLimits(Plot: TRho3DPlot; J: TJSONValue);
begin
  if (J is TJSONArray) and (TJSONArray(J).Count = 2) then
  begin
    Plot.ColorMin := Num(TJSONArray(J).Items[0], NaN);
    Plot.ColorMax := Num(TJSONArray(J).Items[1], NaN);
  end;
end;

procedure Label_(Series: TRho3DSeries; S: TJSONObject);
begin
  Series.Title := Str(S.GetValue('label'));
  Series.ShowInLegend := Series.Title <> '';
end;

procedure AddSeries(Plot: TRho3DPlot; S: TJSONObject; var HasColorBar: Boolean);
var
  Kind: string;
  Series: TRho3DSeries;
  Shape: TRho3DMarker;
  X, Y, Z: TArray<Double>;
begin
  Kind := Str(S.GetValue('type'));
  if (Kind = 'surface') or (Kind = 'bar3') then
  begin
    if Kind = 'surface' then
      Series := Plot.AddSurface(Vector(S.GetValue('x')), Vector(S.GetValue('y')),
        Matrix(S.GetValue('z')))
    else
      // A bar at (x[j], y[i]) from 0 to z[i][j], width a fraction of the spacing.
      Series := Plot.AddBars(Vector(S.GetValue('x')), Vector(S.GetValue('y')),
        Matrix(S.GetValue('z')), Num(S.GetValue('width'), 0.8));
    // Any of the component's maps, by name (viridis, plasma, coolwarm, gray,
    // jet), and colour values other than the heights (color_by), if given.
    Series.ColorMap := ColorMapFromName(Str(S.GetValue('colormap')), cmViridis);
    if S.GetValue('c') is TJSONArray then
      Series.SetValues(Matrix(S.GetValue('c')));
    ColorLimits(Plot, S.GetValue('clim'));
    if Kind = 'bar3' then
    begin
      NamedTicks(Plot, 0, S.GetValue('xnames'));
      NamedTicks(Plot, 1, S.GetValue('ynames'));
    end;
    // Bars in one colour (bar3's color) instead of the colour map.
    if (Kind = 'bar3') and ((S.GetValue('color') is TJSONString) or
       (S.GetValue('color') is TJSONArray)) then
    begin
      Series.Color := ParseColor(S.GetValue('color'), TAlphaColors.Steelblue);
      Series.ColorByValue := False;
    end
    else
      HasColorBar := True;
    if Bool(S.GetValue('edges'), True) then
      Series.FillMode := fmFilledWithEdges
    else
      Series.FillMode := fmFilled;
    Label_(Series, S);
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
begin
  Root := ReadJson(FileName);
  try
    Result := (Root is TJSONObject) and LoadFigure3DObj(Plot, TJSONObject(Root));
  finally
    Root.Free;
  end;
end;

function LoadFigure3DText(Plot: TRho3DPlot; const Json: string): Boolean;
var
  Root: TJSONValue;
begin
  Root := TJSONObject.ParseJSONValue(Json);
  try
    Result := (Root is TJSONObject) and LoadFigure3DObj(Plot, TJSONObject(Root));
  finally
    Root.Free;
  end;
end;

function LoadFigure3DObj(Plot: TRho3DPlot; Fig: TJSONObject): Boolean;
var
  Series, Lim: TJSONArray;
  K: Integer;
  HasColorBar: Boolean;
begin
  Result := False;
  begin
    if not Bool(Fig.GetValue('three_d'), False) or not (Fig.GetValue('series') is TJSONArray) then
      Exit;
    Series := TJSONArray(Fig.GetValue('series'));

    Plot.Clear;
    Plot.UseGradient := False;          // series take their own colours
    // No named ticks or fixed colour range unless a series sets them.
    for K := 0 to 2 do
      Plot.SetTickLabels(K, [], []);
    Plot.ColorMin := NaN;
    Plot.ColorMax := NaN;
    HasColorBar := False;
    for K := 0 to Series.Count - 1 do
      if Series.Items[K] is TJSONObject then
        AddSeries(Plot, TJSONObject(Series.Items[K]), HasColorBar);

    Plot.ChartTitle := Str(Fig.GetValue('title'));
    Plot.AxisTitleX := Str(Fig.GetValue('xlabel'));
    Plot.AxisTitleY := Str(Fig.GetValue('ylabel'));
    Plot.AxisTitleZ := Str(Fig.GetValue('zlabel'));
    // Font sizes from plot.title and the labels, else the chart's defaults.
    Plot.ChartTitleFontSize := Num(Fig.GetValue('title_size'), 15);
    Plot.AxisTitleFontSizeX := Num(Fig.GetValue('xlabel_size'), 12.5);
    Plot.AxisTitleFontSizeY := Num(Fig.GetValue('ylabel_size'), 12.5);
    Plot.AxisTitleFontSizeZ := Num(Fig.GetValue('zlabel_size'), 12.5);
    Plot.LegendVisible := Bool(Fig.GetValue('legend'), True);
    Plot.ShowColorBar := HasColorBar;

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
  end;
end;

end.
