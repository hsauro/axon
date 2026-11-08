unit uPreferences;

(* The IDE's preferences and the dialog that edits them (Edit > Preferences).

   The dialog is built in code and shown modally. Each size has a spin box and
   a preview line in the font that follows it as it changes. Two
   checkboxes choose which of the IDE's own notes (the grey lines) a run
   writes to the Output pane. Reset restores the defaults. The caller applies
   the result and saves it. *)

interface

type
  TIdePreferences = record
    EditorFontSize: Single;
    OutputFontSize: Single;     // Output, REPL and Help panes
    DocsFontSize: Single;       // the Documentation tab's pages
    ShowRunNotes: Boolean;      // "Running ..." and "Finished in ..."
    ShowJitReport: Boolean;     // "JIT compiled: ..." and "Interpreted: ..."
    class function Defaults: TIdePreferences; static;
  end;

const
  MinFontSize = 8;
  MaxFontSize = 36;

{ Shows the dialog; True (and Prefs updated) when the user pressed OK. }
function EditPreferences(var Prefs: TIdePreferences; const MonoFamily: string): Boolean;

implementation

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Math,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.StdCtrls, FMX.SpinBox, FMX.EditBox,
  FMX.Layouts, FMX.Controls.Presentation;

class function TIdePreferences.Defaults: TIdePreferences;
begin
  Result.EditorFontSize := 13;
  Result.OutputFontSize := 12;
  Result.DocsFontSize := 14;
  Result.ShowRunNotes := True;
  Result.ShowJitReport := True;
end;

type
  { Owns the dialog's controls and their event handlers. }
  TPreferencesDialog = class(TComponent)
  private
    FForm: TForm;
    FEditorSize, FOutputSize, FDocsSize: TSpinBox;
    FEditorPreview, FOutputPreview, FDocsPreview: TLabel;
    FRunNotes, FJitReport: TCheckBox;
    FMono: string;
    FNextRowY: Single;          // Top-aligned rows keep the order of their Position.Y
    function AddRow(const Caption, Sample: string; Value: Single;
      out Preview: TLabel; const Family: string = ''): TSpinBox;
    function AddCheck(const Caption: string; Value: Boolean): TCheckBox;
    procedure SizeChanged(Sender: TObject);
    procedure ResetClick(Sender: TObject);
  public
    constructor Create(const Prefs: TIdePreferences; const MonoFamily: string); reintroduce;
    destructor Destroy; override;
    function Execute(var Prefs: TIdePreferences): Boolean;
  end;

constructor TPreferencesDialog.Create(const Prefs: TIdePreferences; const MonoFamily: string);
var
  Buttons: TLayout;
  B: TButton;
  Note: TLabel;
begin
  inherited Create(nil);
  FMono := MonoFamily;
  FForm := TForm.CreateNew(nil);
  FForm.Caption := 'Preferences';
  FForm.ClientWidth := 560;
  FForm.ClientHeight := 340;
  FForm.Position := TFormPosition.MainFormCenter;
  FForm.BorderStyle := TFmxFormBorderStyle.Single;
  FForm.BorderIcons := [TBorderIcon.biSystemMenu];
  FForm.Padding.Rect := TRectF.Create(16, 16, 16, 12);

  FEditorSize := AddRow('Editor font size', 'x = sin(2.5)  # editor', Prefs.EditorFontSize,
    FEditorPreview);
  FOutputSize := AddRow('Output font size', 'NameError: output', Prefs.OutputFontSize,
    FOutputPreview);
  FDocsSize := AddRow('Documentation font size', 'Help pages and the reference',
    Prefs.DocsFontSize, FDocsPreview, {$IFDEF MSWINDOWS}'Segoe UI'{$ELSE}'Helvetica Neue'{$ENDIF});

  Note := TLabel.Create(FForm);
  Note.Parent := FForm;
  Note.Align := TAlignLayout.Top;
  Note.Position.Y := FNextRowY;
  Note.Height := 30;
  Note.Margins.Top := 6;
  Note.Text := 'The output size applies to the Output, REPL and Help panes.';
  FNextRowY := FNextRowY + 1000;

  // Which of the IDE's own notes (grey) a run writes to the Output pane.
  FRunNotes := AddCheck('Show run notes ("Running ...", "Finished in ...")', Prefs.ShowRunNotes);
  FJitReport := AddCheck('Show JIT report (functions compiled, and why others ran interpreted)',
    Prefs.ShowJitReport);

  Buttons := TLayout.Create(FForm);
  Buttons.Parent := FForm;
  Buttons.Align := TAlignLayout.Bottom;
  Buttons.Height := 34;
  B := TButton.Create(FForm);
  B.Parent := Buttons;
  B.Align := TAlignLayout.Left;
  B.Width := 140;
  B.Text := 'Reset to defaults';
  B.OnClick := ResetClick;
  B := TButton.Create(FForm);
  B.Parent := Buttons;
  B.Align := TAlignLayout.Right;
  B.Width := 90;
  B.Text := 'Cancel';
  B.Cancel := True;
  B.ModalResult := mrCancel;
  B := TButton.Create(FForm);
  B.Parent := Buttons;
  B.Align := TAlignLayout.Right;
  B.Position.X := 0;              // left of Cancel
  B.Width := 90;
  B.Margins.Right := 8;
  B.Text := 'OK';
  B.Default := True;
  B.ModalResult := mrOk;
end;

{ A checkbox on its own row, below the rows before it. }
function TPreferencesDialog.AddCheck(const Caption: string; Value: Boolean): TCheckBox;
begin
  Result := TCheckBox.Create(FForm);
  Result.Parent := FForm;
  Result.Position.Y := FNextRowY;
  FNextRowY := FNextRowY + 1000;
  Result.Align := TAlignLayout.Top;
  Result.Height := 28;
  Result.Text := Caption;
  Result.IsChecked := Value;
end;

destructor TPreferencesDialog.Destroy;
begin
  FForm.Free;
  inherited;
end;

{ A row: caption, spin box and a preview in the monospace font. }
function TPreferencesDialog.AddRow(const Caption, Sample: string; Value: Single;
  out Preview: TLabel; const Family: string): TSpinBox;
var
  Row: TLayout;
  L: TLabel;
begin
  Row := TLayout.Create(FForm);
  Row.Parent := FForm;
  Row.Position.Y := FNextRowY;
  FNextRowY := FNextRowY + 1000;
  Row.Align := TAlignLayout.Top;
  Row.Height := 48;
  L := TLabel.Create(FForm);
  L.Parent := Row;
  L.Align := TAlignLayout.Left;
  L.Width := 160;
  L.Text := Caption;
  Result := TSpinBox.Create(FForm);
  Result.Parent := Row;
  Result.Align := TAlignLayout.Left;
  Result.Position.X := 1000;
  Result.Width := 90;
  Result.Margins.Rect := TRectF.Create(0, 9, 0, 9);
  Result.Min := MinFontSize;
  Result.Max := MaxFontSize;
  Result.Value := Round(Value);
  Result.OnChange := SizeChanged;
  Preview := TLabel.Create(FForm);
  Preview.Parent := Row;
  Preview.Align := TAlignLayout.Client;
  Preview.Margins.Left := 16;
  Preview.StyledSettings := Preview.StyledSettings - [TStyledSetting.Family, TStyledSetting.Size];
  if Family <> '' then
    Preview.TextSettings.Font.Family := Family
  else
    Preview.TextSettings.Font.Family := FMono;
  Preview.TextSettings.Font.Size := Round(Value);
  Preview.TextSettings.WordWrap := False;
  Preview.Text := Sample;
end;

procedure TPreferencesDialog.SizeChanged(Sender: TObject);
begin
  FEditorPreview.TextSettings.Font.Size := FEditorSize.Value;
  FOutputPreview.TextSettings.Font.Size := FOutputSize.Value;
  FDocsPreview.TextSettings.Font.Size := FDocsSize.Value;
end;

procedure TPreferencesDialog.ResetClick(Sender: TObject);
var
  D: TIdePreferences;
begin
  D := TIdePreferences.Defaults;
  FEditorSize.Value := D.EditorFontSize;
  FOutputSize.Value := D.OutputFontSize;
  FDocsSize.Value := D.DocsFontSize;
  FRunNotes.IsChecked := D.ShowRunNotes;
  FJitReport.IsChecked := D.ShowJitReport;
end;

function TPreferencesDialog.Execute(var Prefs: TIdePreferences): Boolean;
begin
  Result := FForm.ShowModal = mrOk;
  if Result then
  begin
    Prefs.EditorFontSize := EnsureRange(FEditorSize.Value, MinFontSize, MaxFontSize);
    Prefs.OutputFontSize := EnsureRange(FOutputSize.Value, MinFontSize, MaxFontSize);
    Prefs.DocsFontSize := EnsureRange(FDocsSize.Value, MinFontSize, MaxFontSize);
    Prefs.ShowRunNotes := FRunNotes.IsChecked;
    Prefs.ShowJitReport := FJitReport.IsChecked;
  end;
end;

function EditPreferences(var Prefs: TIdePreferences; const MonoFamily: string): Boolean;
var
  D: TPreferencesDialog;
begin
  D := TPreferencesDialog.Create(Prefs, MonoFamily);
  try
    Result := D.Execute(Prefs);
  finally
    D.Free;
  end;
end;

end.
