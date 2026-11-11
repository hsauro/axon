unit uFigureGrid;

(* Shows a figure divided by plot.subplot as a grid of interactive charts.

   plot.show writes such a figure as JSON with fields width, height, title
   (above the grid), rows, cols and cells: a list of rows * cols figure
   records, numbered along each row from the top left, null for a cell never
   selected. Each cell becomes its own chart: TSkPlotPaintBox for a 2-D cell
   (uFigureChart) or TRho3DPlot for a 3-D one (uFigureChart3D), so every cell
   can be zoomed, panned and edited as a single figure can. *)

interface

uses
  System.Classes, FMX.Types, FMX.Controls;

// A control holding the title and the grid of charts for the figure in
// FileName, made with Owner and placed in Parent (aligned to fill it); nil
// when the file is not a figure with subplots.
function LoadFigureGrid(Owner: TComponent; Parent: TFmxObject;
  const FileName: string): TControl;
// The same for a figure given as JSON text (from the display channel).
function LoadFigureGridText(Owner: TComponent; Parent: TFmxObject;
  const Json: string): TControl;

implementation

uses
  System.SysUtils, System.Types, System.UITypes, System.JSON, System.Generics.Collections,
  FMX.Layouts, FMX.StdCtrls, FMX.Graphics, FMX.Objects,
  SkPlotPaintBox, Rho3DPlot, uFigureChart, uFigureChart3D;

function LoadFigureGridRoot(Owner: TComponent; Parent: TFmxObject;
  Root: TJSONValue): TControl;
var
  Fig, Cell: TJSONObject;
  Cells: TJSONArray;
  Rows, Cols, K: Integer;
  Box: TRectangle;
  Grid: TGridPanelLayout;
  Title: TLabel;
  Chart: TSkPlotPaintBox;
  Chart3D: TRho3DPlot;
  Spot: TLayout;
begin
  Result := nil;
  begin
    if not (Root is TJSONObject) then
      Exit;
    Fig := TJSONObject(Root);
    if not (Fig.GetValue('cells') is TJSONArray) then
      Exit;
    Cells := TJSONArray(Fig.GetValue('cells'));
    Rows := Round(Num(Fig.GetValue('rows'), 0));
    Cols := Round(Num(Fig.GetValue('cols'), 0));
    if (Rows < 1) or (Cols < 1) or (Cells.Count <> Rows * Cols) then
      Exit;

    // White behind the cells, which sit edge to edge, as in the image.
    Box := TRectangle.Create(Owner);
    Box.Parent := Parent;
    Box.Align := TAlignLayout.Client;
    Box.Fill.Color := TAlphaColors.White;
    Box.Stroke.Kind := TBrushKind.None;
    Result := Box;

    if Str(Fig.GetValue('title')) <> '' then
    begin
      Title := TLabel.Create(Owner);
      Title.Parent := Box;
      Title.Align := TAlignLayout.Top;
      Title.Height := 22;
      Title.Text := Str(Fig.GetValue('title'));
      Title.TextSettings.HorzAlign := TTextAlign.Center;
      Title.StyledSettings := Title.StyledSettings - [TStyledSetting.Style,
        TStyledSetting.FontColor];
      Title.TextSettings.FontColor := TAlphaColors.Black;
      Title.TextSettings.Font.Style := [TFontStyle.fsBold];
    end;

    Grid := TGridPanelLayout.Create(Owner);
    Grid.Parent := Box;
    Grid.Align := TAlignLayout.Client;
    Grid.RowCollection.BeginUpdate;
    Grid.ColumnCollection.BeginUpdate;
    try
      Grid.RowCollection.Clear;
      Grid.ColumnCollection.Clear;
      for K := 1 to Rows do
        with Grid.RowCollection.Add do
        begin
          SizeStyle := TGridPanelLayout.TSizeStyle.Percent;
          Value := 100 / Rows;
        end;
      for K := 1 to Cols do
        with Grid.ColumnCollection.Add do
        begin
          SizeStyle := TGridPanelLayout.TSizeStyle.Percent;
          Value := 100 / Cols;
        end;
    finally
      Grid.ColumnCollection.EndUpdate;
      Grid.RowCollection.EndUpdate;
    end;

    for K := 0 to Cells.Count - 1 do
    begin
      // Every cell gets a place, so the grid keeps its shape; empty cells
      // stay blank.
      Spot := TLayout.Create(Owner);
      Spot.Parent := Grid;
      Grid.ControlCollection.AddControl(Spot, K mod Cols, K div Cols);
      Spot.Align := TAlignLayout.Client;
      if not (Cells.Items[K] is TJSONObject) then
        Continue;
      Cell := TJSONObject(Cells.Items[K]);
      if Bool(Cell.GetValue('three_d'), False) then
      begin
        Chart3D := TRho3DPlot.Create(Owner);
        Chart3D.Parent := Spot;
        Chart3D.Align := TAlignLayout.Client;
        if not LoadFigure3DObj(Chart3D, Cell) then
          Chart3D.Free;
      end
      else
      begin
        Chart := TSkPlotPaintBox.Create(Owner);
        Chart.Parent := Spot;
        Chart.Align := TAlignLayout.Client;
        Chart.ZoomPanEnabled := True;
        if not LoadFigureObj(Chart, Cell) then
          Chart.Free;
      end;
    end;
  end;
end;

function LoadFigureGrid(Owner: TComponent; Parent: TFmxObject;
  const FileName: string): TControl;
var
  Root: TJSONValue;
begin
  Root := ReadJson(FileName);
  try
    Result := LoadFigureGridRoot(Owner, Parent, Root);
  finally
    Root.Free;
  end;
end;

function LoadFigureGridText(Owner: TComponent; Parent: TFmxObject;
  const Json: string): TControl;
var
  Root: TJSONValue;
begin
  Root := TJSONObject.ParseJSONValue(Json);
  try
    Result := LoadFigureGridRoot(Owner, Parent, Root);
  finally
    Root.Free;
  end;
end;

end.
