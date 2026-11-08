unit uMainForm;

(* The Axon IDE's main window.

   - Tabs of TSkiaCodeEditor documents with Axon highlighting.
   - Run (F9) saves the current file and runs axon on it as a separate
     process, in the file's directory, so imports and package.toml resolve
     exactly as on the command line. Stop (Ctrl+F2) kills it.
   - The output pane shows stdout and stderr (red) as they arrive. Error and
     trace lines are links: clicking one opens the file at that line. After a
     failed run, the error location gets a wavy underline whose tooltip is
     the error.
   - The plot pane shows the newest PNG the run wrote in its directory.
   - The REPL tab drives "axon --repl-protocol" through pipes: a session
     starts on first use in the current file's directory and keeps its
     variables until it is restarted. Send to REPL (Ctrl+Enter) sends the
     editor's selection, or the current line.

   The layout is built in code; the .fmx holds only the empty form. *)

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes,
  System.Generics.Collections,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.StdCtrls,
  FMX.Layouts, FMX.ListBox, FMX.TabControl, FMX.Menus, FMX.Objects,
  FMX.Controls.Presentation, FMX.Edit,
  uSkiaCodeEditor, uProcessRunner, uRunReport;

type
  TDocument = class
  public
    Tab: TTabItem;
    Editor: TSkiaCodeEditor;
    FilePath: string;      // '' until saved
    UntitledNumber: Integer;
    function DisplayName: string;
  end;

  TfrmMain = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
  private
    FDocs: TObjectList<TDocument>;
    FTabs: TTabControl;
    FOutput: TListBox;
    FPlotImage: TImage;
    FPlotCaption: TLabel;
    FStatus: TLabel;
    FCaretInfo: TLabel;
    FRunButton, FStopButton: TSpeedButton;
    FRunItem, FStopItem: TMenuItem;
    FRecentMenu: TMenuItem;
    FRecent: TStringList;
    FRunner: TProcessRunner;
    FRunDoc: TDocument;
    FRunDir: string;
    FRunStart: TDateTime;
    FRunTicks: UInt64;
    FPartial: array[TOutputKind] of string;
    FErrorKind, FErrorMessage: string;
    FFrames: TList<TFrame>;
    FFirstStdErr: Boolean;
    FUntitledCount: Integer;
    // REPL
    FBottomTabs: TTabControl;
    FOutputTab, FReplTab: TTabItem;
    FReplList: TListBox;
    FReplEdit: TEdit;
    FReplPrompt: TLabel;
    FReplDirLabel: TLabel;
    FRepl: TProcessRunner;
    FReplPartial: string;
    FReplDir: string;
    FReplRestart: Boolean;
    FReplHistory: TStringList;
    FReplHistoryPos: Integer;
    FReplSince: TDateTime;
    procedure BuildUI;
    procedure BuildReplPane(Parent: TFmxObject);
    function ReplWorkDir: string;
    function EnsureRepl: Boolean;
    procedure ReplOutput(Kind: TOutputKind; const Text: string);
    procedure ReplExit(ExitCode: Integer);
    procedure ReplAddLine(const Text: string; Color: TAlphaColor; Italic: Boolean = False);
    procedure ReplSend(const Lines: TArray<string>);
    procedure ReplEditKeyDown(Sender: TObject; var Key: Word; var KeyChar: WideChar;
      Shift: TShiftState);
    procedure ShowNewestPlotIn(const Dir: string; Since: TDateTime);
    procedure ScrollToEnd(List: TListBox);
    procedure BuildMenu;
    function AddMenuItem(Parent: TFmxObject; const Text, ShortCut: string;
      Handler: TNotifyEvent): TMenuItem;
    function AddButton(Parent: TFmxObject; const Text, Hint: string; Handler: TNotifyEvent): TSpeedButton;
    // documents
    function CurrentDoc: TDocument;
    function NewDocument(const Path, Text: string): TDocument;
    function FindDocument(const Path: string): TDocument;
    function OpenFile(const Path: string): TDocument;
    function SaveDoc(Doc: TDocument; SaveAs: Boolean): Boolean;
    function ConfirmClose(Doc: TDocument): Boolean;
    procedure CloseDoc(Doc: TDocument);
    procedure UpdateTabCaption(Doc: TDocument);
    procedure UpdateTitle;
    procedure EditorChange(Sender: TObject);
    procedure EditorCaretChange(Sender: TObject);
    procedure TabChange(Sender: TObject);
    // recent files
    function SettingsFile: string;
    procedure LoadSettings;
    procedure SaveSettings;
    procedure AddRecent(const Path: string);
    procedure RebuildRecentMenu;
    procedure RecentClick(Sender: TObject);
    // running
    function AxonExecutable: string;
    procedure SetRunning(Value: Boolean);
    procedure RunOutput(Kind: TOutputKind; const Text: string);
    procedure RunExit(ExitCode: Integer);
    procedure AddOutputLine(Kind: TOutputKind; const Line: string);
    procedure AddNote(const Text: string; Color: TAlphaColor);
    procedure OutputClick(const Sender: TCustomListBox; const Item: TListBoxItem);
    procedure GoToFrame(const Frame: TFrame);
    function ResolveRunPath(const FileName: string): string;
    procedure MarkError;
    // commands
    procedure CmdNew(Sender: TObject);
    procedure CmdOpen(Sender: TObject);
    procedure CmdSave(Sender: TObject);
    procedure CmdSaveAs(Sender: TObject);
    procedure CmdClose(Sender: TObject);
{$IFNDEF MACOS}
    procedure CmdExit(Sender: TObject);
{$ENDIF}
    procedure CmdUndo(Sender: TObject);
    procedure CmdRedo(Sender: TObject);
    procedure CmdCut(Sender: TObject);
    procedure CmdCopy(Sender: TObject);
    procedure CmdPaste(Sender: TObject);
    procedure CmdSelectAll(Sender: TObject);
    procedure CmdFind(Sender: TObject);
    procedure CmdToggleComment(Sender: TObject);
    procedure CmdRun(Sender: TObject);
    procedure CmdStop(Sender: TObject);
    procedure CmdClearOutput(Sender: TObject);
    procedure CmdAbout(Sender: TObject);
    procedure CmdSendToRepl(Sender: TObject);
    procedure CmdReplRestart(Sender: TObject);
    procedure CmdReplClear(Sender: TObject);
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.fmx}

uses
  System.IOUtils, System.IniFiles, System.DateUtils, System.Math,
  FMX.ActnList, FMX.DialogService.Sync,
  uAxonHighlighter;

const
  MaxOutputLines = 10000;
  MaxRecent = 8;
  ColorError = $FFC62828;
  ColorNote = $FF606060;
  ColorLink = $FF1565C0;
  FileFilter = 'Axon files (*.sci)|*.sci|All files (*.*)|*.*';

{ ---------------- TDocument ---------------- }

function TDocument.DisplayName: string;
begin
  if FilePath <> '' then
    Result := ExtractFileName(FilePath)
  else
    Result := Format('untitled%d.sci', [UntitledNumber]);
end;

{ ---------------- set-up ---------------- }

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  FDocs := TObjectList<TDocument>.Create(True);
  FFrames := TList<TFrame>.Create;
  FRecent := TStringList.Create;
  FRunner := TProcessRunner.Create;
  FRunner.OnOutput := RunOutput;
  FRunner.OnExit := RunExit;
  FRepl := TProcessRunner.Create;
  FRepl.OnOutput := ReplOutput;
  FRepl.OnExit := ReplExit;
  FReplHistory := TStringList.Create;
  BuildUI;
  BuildMenu;
  LoadSettings;
  RebuildRecentMenu;
  // Files named on the command line, or an empty document.
  if ParamCount > 0 then
  begin
    for var K := 1 to ParamCount do
      if TFile.Exists(ParamStr(K)) then
        OpenFile(TPath.GetFullPath(ParamStr(K)));
  end;
  if FDocs.Count = 0 then
    NewDocument('', '');
  SetRunning(False);
  UpdateTitle;
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  FRunner.Free;          // kills a running program
  FRepl.Free;            // and the REPL session
  FReplHistory.Free;
  SaveSettings;
  FRecent.Free;
  FFrames.Free;
  FDocs.Free;
end;

procedure TfrmMain.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
var
  Doc: TDocument;
begin
  CanClose := True;
  for Doc in FDocs do
    if not ConfirmClose(Doc) then
    begin
      CanClose := False;
      Exit;
    end;
end;

function TfrmMain.AddButton(Parent: TFmxObject; const Text, Hint: string;
  Handler: TNotifyEvent): TSpeedButton;
begin
  Result := TSpeedButton.Create(Self);
  Result.Parent := Parent;
  // Left-aligned controls are ordered by position: place each after the last.
  Result.Position.X := 10000 + Parent.ChildrenCount * 100;
  Result.Align := TAlignLayout.Left;
  Result.Width := 64;
  Result.Margins.Left := 2;
  Result.Text := Text;
  Result.Hint := Hint;
  Result.ShowHint := True;
  Result.OnClick := Handler;
end;

procedure TfrmMain.BuildUI;
var
  Bar: TToolBar;
  Status: TStatusBar;
  Body, Right: TLayout;
  Split: TSplitter;
  Header: TLabel;
begin
  Caption := 'Axon';
  Width := 1200;
  Height := 780;

  Bar := TToolBar.Create(Self);
  Bar.Parent := Self;
  Bar.Height := 36;
  Bar.Padding.Rect := TRectF.Create(4, 4, 4, 4);
  AddButton(Bar, 'New', 'New file (Ctrl+N)', CmdNew);
  AddButton(Bar, 'Open', 'Open a file (Ctrl+O)', CmdOpen);
  AddButton(Bar, 'Save', 'Save (Ctrl+S)', CmdSave);
  FRunButton := AddButton(Bar, #$25B6' Run', 'Run the current file (F9)', CmdRun);
  FRunButton.Margins.Left := 16;
  FStopButton := AddButton(Bar, #$25A0' Stop', 'Stop the running program (Ctrl+F2)', CmdStop);

  Status := TStatusBar.Create(Self);
  Status.Parent := Self;
  Status.Height := 24;
  FStatus := TLabel.Create(Self);
  FStatus.Parent := Status;
  FStatus.Align := TAlignLayout.Client;
  FStatus.Margins.Left := 8;
  FStatus.Text := 'Ready';
  FCaretInfo := TLabel.Create(Self);
  FCaretInfo.Parent := Status;
  FCaretInfo.Align := TAlignLayout.Right;
  FCaretInfo.Width := 140;

  Body := TLayout.Create(Self);
  Body.Parent := Self;
  Body.Align := TAlignLayout.Client;

  // Plot pane on the right.
  Right := TLayout.Create(Self);
  Right.Parent := Body;
  Right.Align := TAlignLayout.Right;
  Right.Width := 380;
  Header := TLabel.Create(Self);
  Header.Parent := Right;
  Header.Align := TAlignLayout.Top;
  Header.Height := 22;
  Header.Margins.Left := 6;
  Header.Text := 'Plot';
  Header.StyledSettings := Header.StyledSettings - [TStyledSetting.Style];
  Header.TextSettings.Font.Style := [TFontStyle.fsBold];
  FPlotCaption := TLabel.Create(Self);
  FPlotCaption.Parent := Right;
  FPlotCaption.Align := TAlignLayout.Bottom;
  FPlotCaption.Height := 20;
  FPlotCaption.Margins.Left := 6;
  FPlotCaption.Text := 'Plots saved with plot.save(".png") appear here.';
  FPlotImage := TImage.Create(Self);
  FPlotImage.Parent := Right;
  FPlotImage.Align := TAlignLayout.Client;
  FPlotImage.WrapMode := TImageWrapMode.Fit;
  FPlotImage.Margins.Rect := TRectF.Create(4, 4, 4, 4);
  Split := TSplitter.Create(Self);
  Split.Parent := Body;
  Split.Align := TAlignLayout.Right;
  Split.Width := 5;

  // Output and REPL tabs at the bottom.
  FBottomTabs := TTabControl.Create(Self);
  FBottomTabs.Parent := Body;
  FBottomTabs.Align := TAlignLayout.Bottom;
  FBottomTabs.Height := 240;
  FOutputTab := FBottomTabs.Add;
  FOutputTab.Text := 'Output';
  FReplTab := FBottomTabs.Add;
  FReplTab.Text := 'REPL';
  FOutput := TListBox.Create(Self);
  FOutput.Parent := FOutputTab;
  FOutput.Align := TAlignLayout.Client;
  FOutput.ItemHeight := 18;
  FOutput.OnItemClick := OutputClick;
  BuildReplPane(FReplTab);
  FBottomTabs.ActiveTab := FOutputTab;
  Split := TSplitter.Create(Self);
  Split.Parent := Body;
  Split.Align := TAlignLayout.Bottom;
  Split.Height := 5;

  // Editors.
  FTabs := TTabControl.Create(Self);
  FTabs.Parent := Body;
  FTabs.Align := TAlignLayout.Client;
  FTabs.OnChange := TabChange;
end;

function TfrmMain.AddMenuItem(Parent: TFmxObject; const Text, ShortCut: string;
  Handler: TNotifyEvent): TMenuItem;
begin
  Result := TMenuItem.Create(Self);
  Result.Parent := Parent;
  Result.Text := Text;
  if ShortCut <> '' then
    Result.ShortCut := TextToShortCut(ShortCut);
  Result.OnClick := Handler;
end;

procedure TfrmMain.BuildMenu;
var
  Menu: TMainMenu;
  M: TMenuItem;
begin
  Menu := TMainMenu.Create(Self);
  Menu.Parent := Self;

  M := AddMenuItem(Menu, '&File', '', nil);
  AddMenuItem(M, '&New', 'Ctrl+N', CmdNew);
  AddMenuItem(M, '&Open...', 'Ctrl+O', CmdOpen);
  FRecentMenu := AddMenuItem(M, 'Open &Recent', '', nil);
  AddMenuItem(M, '-', '', nil);
  AddMenuItem(M, '&Save', 'Ctrl+S', CmdSave);
  AddMenuItem(M, 'Save &As...', 'Shift+Ctrl+S', CmdSaveAs);
  AddMenuItem(M, '&Close', 'Ctrl+W', CmdClose);
{$IFNDEF MACOS}
  AddMenuItem(M, '-', '', nil);
  AddMenuItem(M, 'E&xit', '', CmdExit);
{$ENDIF}

  M := AddMenuItem(Menu, '&Edit', '', nil);
  AddMenuItem(M, '&Undo', 'Ctrl+Z', CmdUndo);
  AddMenuItem(M, '&Redo', 'Ctrl+Y', CmdRedo);
  AddMenuItem(M, '-', '', nil);
  AddMenuItem(M, 'Cu&t', 'Ctrl+X', CmdCut);
  AddMenuItem(M, '&Copy', 'Ctrl+C', CmdCopy);
  AddMenuItem(M, '&Paste', 'Ctrl+V', CmdPaste);
  AddMenuItem(M, 'Select &All', 'Ctrl+A', CmdSelectAll);
  AddMenuItem(M, '-', '', nil);
  AddMenuItem(M, '&Find...', 'Ctrl+F', CmdFind);
  AddMenuItem(M, 'Toggle &Comment', 'Ctrl+/', CmdToggleComment);

  M := AddMenuItem(Menu, '&Run', '', nil);
  FRunItem := AddMenuItem(M, '&Run', 'F9', CmdRun);
  FStopItem := AddMenuItem(M, '&Stop', 'Ctrl+F2', CmdStop);
  AddMenuItem(M, '-', '', nil);
  AddMenuItem(M, 'Send to RE&PL', 'Ctrl+Enter', CmdSendToRepl);
  AddMenuItem(M, 'Restart R&EPL', '', CmdReplRestart);
  AddMenuItem(M, '-', '', nil);
  AddMenuItem(M, 'C&lear Output', '', CmdClearOutput);

  M := AddMenuItem(Menu, '&Help', '', nil);
  AddMenuItem(M, '&About Axon IDE', '', CmdAbout);
end;

{ ---------------- documents ---------------- }

function TfrmMain.CurrentDoc: TDocument;
var
  Doc: TDocument;
begin
  for Doc in FDocs do
    if Doc.Tab = FTabs.ActiveTab then
      Exit(Doc);
  Result := nil;
end;

function TfrmMain.NewDocument(const Path, Text: string): TDocument;
var
  Doc: TDocument;
begin
  Doc := TDocument.Create;
  FDocs.Add(Doc);
  Doc.FilePath := Path;
  if Path = '' then
  begin
    Inc(FUntitledCount);
    Doc.UntitledNumber := FUntitledCount;
  end;
  Doc.Tab := FTabs.Add;
  Doc.Editor := TSkiaCodeEditor.Create(Self);
  Doc.Editor.Parent := Doc.Tab;
  Doc.Editor.Align := TAlignLayout.Client;
  Doc.Editor.SetTokenizer(AxonTokenizer(DefaultAxonColors));
  Doc.Editor.LineCommentPrefix := '#';
  Doc.Editor.HighlightCurrentLine := True;
  Doc.Editor.SetText(Text);
  Doc.Editor.OnChange := EditorChange;
  Doc.Editor.OnCaretChange := EditorCaretChange;
  UpdateTabCaption(Doc);
  FTabs.ActiveTab := Doc.Tab;
  Doc.Editor.SetFocus;
  UpdateTitle;
  Result := Doc;
end;

function TfrmMain.FindDocument(const Path: string): TDocument;
var
  Doc: TDocument;
begin
  for Doc in FDocs do
    if (Doc.FilePath <> '') and SameFileName(Doc.FilePath, Path) then
      Exit(Doc);
  Result := nil;
end;

function TfrmMain.OpenFile(const Path: string): TDocument;
var
  Doc: TDocument;
begin
  Result := FindDocument(Path);
  if Result <> nil then
  begin
    FTabs.ActiveTab := Result.Tab;
    Exit;
  end;
  try
    // Replace a single, untouched untitled document.
    if (FDocs.Count = 1) and (FDocs[0].FilePath = '') and not FDocs[0].Editor.Modified and
      (FDocs[0].Editor.GetText = '') then
    begin
      Doc := FDocs[0];
      FDocs.Extract(Doc);
      Doc.Tab.Free;
      Doc.Free;
    end;
    Result := NewDocument(Path, TFile.ReadAllText(Path, TEncoding.UTF8));
    AddRecent(Path);
  except
    on E: Exception do
    begin
      TDialogServiceSync.MessageDialog(Format('Cannot open %s:'#10'%s', [Path, E.Message]),
        TMsgDlgType.mtError, [TMsgDlgBtn.mbOK], TMsgDlgBtn.mbOK, 0);
      Result := nil;
    end;
  end;
end;

function TfrmMain.SaveDoc(Doc: TDocument; SaveAs: Boolean): Boolean;
var
  Dlg: TSaveDialog;
  Path: string;
begin
  Result := False;
  Path := Doc.FilePath;
  if SaveAs or (Path = '') then
  begin
    Dlg := TSaveDialog.Create(nil);
    try
      Dlg.Filter := FileFilter;
      Dlg.DefaultExt := 'sci';
      Dlg.FileName := Doc.DisplayName;
      if Path <> '' then
        Dlg.InitialDir := ExtractFileDir(Path);
      if not Dlg.Execute then
        Exit;
      Path := Dlg.FileName;
    finally
      Dlg.Free;
    end;
  end;
  try
    // UTF-8 without a byte-order mark, the form axon reads best.
    TFile.WriteAllBytes(Path, TEncoding.UTF8.GetBytes(Doc.Editor.GetText));
  except
    on E: Exception do
    begin
      TDialogServiceSync.MessageDialog(Format('Cannot save %s:'#10'%s', [Path, E.Message]),
        TMsgDlgType.mtError, [TMsgDlgBtn.mbOK], TMsgDlgBtn.mbOK, 0);
      Exit;
    end;
  end;
  Doc.FilePath := Path;
  Doc.Editor.Modified := False;
  UpdateTabCaption(Doc);
  UpdateTitle;
  AddRecent(Path);
  Result := True;
end;

function TfrmMain.ConfirmClose(Doc: TDocument): Boolean;
var
  R: TModalResult;
begin
  if not Doc.Editor.Modified then
    Exit(True);
  FTabs.ActiveTab := Doc.Tab;
  R := TDialogServiceSync.MessageDialog(Format('Save changes to %s?', [Doc.DisplayName]),
    TMsgDlgType.mtConfirmation, [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo, TMsgDlgBtn.mbCancel],
    TMsgDlgBtn.mbYes, 0);
  case R of
    mrYes: Result := SaveDoc(Doc, False);
    mrNo: Result := True;
  else
    Result := False;
  end;
end;

procedure TfrmMain.CloseDoc(Doc: TDocument);
begin
  if not ConfirmClose(Doc) then
    Exit;
  if FRunDoc = Doc then
    FRunDoc := nil;
  FDocs.Extract(Doc);
  Doc.Tab.Free;
  Doc.Free;
  if FDocs.Count = 0 then
    NewDocument('', '');
  UpdateTitle;
end;

procedure TfrmMain.UpdateTabCaption(Doc: TDocument);
begin
  if Doc.Editor.Modified then
    Doc.Tab.Text := Doc.DisplayName + ' *'
  else
    Doc.Tab.Text := Doc.DisplayName;
end;

procedure TfrmMain.UpdateTitle;
var
  Doc: TDocument;
begin
  Doc := CurrentDoc;
  if Doc = nil then
    Caption := 'Axon'
  else if Doc.FilePath <> '' then
    Caption := Doc.DisplayName + ' - ' + ExtractFileDir(Doc.FilePath) + ' - Axon'
  else
    Caption := Doc.DisplayName + ' - Axon';
  EditorCaretChange(nil);
end;

procedure TfrmMain.EditorChange(Sender: TObject);
var
  Doc: TDocument;
begin
  for Doc in FDocs do
    if Doc.Editor = Sender then
      UpdateTabCaption(Doc);
end;

procedure TfrmMain.EditorCaretChange(Sender: TObject);
var
  Doc: TDocument;
begin
  Doc := CurrentDoc;
  if Doc <> nil then
    FCaretInfo.Text := Format('Ln %d, Col %d', [Doc.Editor.CaretLine, Doc.Editor.CaretColumn]);
end;

procedure TfrmMain.TabChange(Sender: TObject);
begin
  UpdateTitle;
end;

{ ---------------- settings and recent files ---------------- }

function TfrmMain.SettingsFile: string;
begin
  Result := TPath.Combine(TPath.Combine(TPath.GetHomePath, 'AxonIDE'), 'settings.ini');
end;

procedure TfrmMain.LoadSettings;
var
  Ini: TMemIniFile;
  K: Integer;
  S: string;
begin
  if not TFile.Exists(SettingsFile) then
    Exit;
  Ini := TMemIniFile.Create(SettingsFile, TEncoding.UTF8);
  try
    for K := 1 to MaxRecent do
    begin
      S := Ini.ReadString('Recent', 'File' + IntToStr(K), '');
      if S <> '' then
        FRecent.Add(S);
    end;
  finally
    Ini.Free;
  end;
end;

procedure TfrmMain.SaveSettings;
var
  Ini: TMemIniFile;
  K: Integer;
begin
  try
    ForceDirectories(ExtractFileDir(SettingsFile));
    Ini := TMemIniFile.Create(SettingsFile, TEncoding.UTF8);
    try
      Ini.EraseSection('Recent');
      for K := 0 to FRecent.Count - 1 do
        Ini.WriteString('Recent', 'File' + IntToStr(K + 1), FRecent[K]);
      Ini.UpdateFile;
    finally
      Ini.Free;
    end;
  except
    // Settings are a convenience; failing to save them is not an error.
  end;
end;

procedure TfrmMain.AddRecent(const Path: string);
var
  K: Integer;
begin
  for K := FRecent.Count - 1 downto 0 do
    if SameFileName(FRecent[K], Path) then
      FRecent.Delete(K);
  FRecent.Insert(0, Path);
  while FRecent.Count > MaxRecent do
    FRecent.Delete(FRecent.Count - 1);
  RebuildRecentMenu;
end;

procedure TfrmMain.RebuildRecentMenu;
var
  K: Integer;
  Item: TMenuItem;
begin
  if FRecentMenu = nil then
    Exit;
  for K := FRecentMenu.ItemsCount - 1 downto 0 do
    FRecentMenu.Items[K].Free;
  for K := 0 to FRecent.Count - 1 do
  begin
    Item := AddMenuItem(FRecentMenu, FRecent[K], '', RecentClick);
    Item.TagString := FRecent[K];
  end;
  FRecentMenu.Enabled := FRecent.Count > 0;
end;

procedure TfrmMain.RecentClick(Sender: TObject);
var
  Path: string;
begin
  Path := TMenuItem(Sender).TagString;
  if TFile.Exists(Path) then
    OpenFile(Path)
  else
  begin
    FRecent.Delete(FRecent.IndexOf(Path));
    RebuildRecentMenu;
  end;
end;

{ ---------------- running ---------------- }

function TfrmMain.AxonExecutable: string;
var
  Dir: string;
begin
  // axon sits next to the IDE (Win64\Debug, or Contents/MacOS in a bundle).
  Dir := ExtractFilePath(ParamStr(0));
{$IFDEF MSWINDOWS}
  Result := Dir + 'axon.exe';
{$ELSE}
  Result := Dir + 'axon';
{$ENDIF}
  if not TFile.Exists(Result) then
    Result := '';
end;

procedure TfrmMain.SetRunning(Value: Boolean);
begin
  FRunButton.Enabled := not Value;
  FRunItem.Enabled := not Value;
  FStopButton.Enabled := Value;
  FStopItem.Enabled := Value;
end;

procedure TfrmMain.CmdRun(Sender: TObject);
var
  Doc: TDocument;
  Exe: string;
  D: TDocument;
begin
  if FRunner.Running then
    Exit;
  Doc := CurrentDoc;
  if Doc = nil then
    Exit;
  if (Doc.FilePath = '') or Doc.Editor.Modified then
    if not SaveDoc(Doc, False) then
      Exit;
  Exe := AxonExecutable;
  FOutput.Clear;
  if Exe = '' then
  begin
    AddNote('Cannot find the axon interpreter next to the IDE (' +
      ExtractFilePath(ParamStr(0)) + ').', ColorError);
    Exit;
  end;
  for D in FDocs do
    D.Editor.ClearMarkers;
  FRunDoc := Doc;
  FRunDir := ExtractFileDir(Doc.FilePath);
  FRunStart := Now;
  FRunTicks := TThread.GetTickCount64;
  FPartial[okStdOut] := '';
  FPartial[okStdErr] := '';
  FErrorKind := '';
  FErrorMessage := '';
  FFrames.Clear;
  FFirstStdErr := True;
  AddNote(Format('Running %s', [Doc.FilePath]), ColorNote);
  try
    FRunner.Start(Exe, [ExtractFileName(Doc.FilePath)], FRunDir);
  except
    on E: Exception do
    begin
      AddNote('Cannot start axon: ' + E.Message, ColorError);
      Exit;
    end;
  end;
  FStatus.Text := 'Running ' + Doc.DisplayName + '...';
  SetRunning(True);
end;

procedure TfrmMain.CmdStop(Sender: TObject);
begin
  FRunner.Kill;
end;

procedure TfrmMain.RunOutput(Kind: TOutputKind; const Text: string);
var
  S: string;
  P: Integer;
begin
  // Complete lines go to the pane; a partial last line waits for the rest.
  S := FPartial[Kind] + Text.Replace(#13#10, #10).Replace(#13, #10);
  P := S.IndexOf(#10);
  FOutput.BeginUpdate;
  try
    while P >= 0 do
    begin
      AddOutputLine(Kind, S.Substring(0, P));
      S := S.Substring(P + 1);
      P := S.IndexOf(#10);
    end;
  finally
    FOutput.EndUpdate;
  end;
  FPartial[Kind] := S;
  ScrollToEnd(FOutput);
end;

procedure TfrmMain.RunExit(ExitCode: Integer);
var
  K: TOutputKind;
  Secs: Double;
begin
  for K := Low(TOutputKind) to High(TOutputKind) do
    if FPartial[K] <> '' then
    begin
      AddOutputLine(K, FPartial[K]);
      FPartial[K] := '';
    end;
  Secs := (TThread.GetTickCount64 - FRunTicks) / 1000;
  SetRunning(False);
  if FRunner.Killed then
  begin
    AddNote(Format('Stopped after %.2f s', [Secs]), ColorError);
    FStatus.Text := 'Stopped';
  end
  else if ExitCode = 0 then
  begin
    AddNote(Format('Finished in %.2f s', [Secs]), ColorNote);
    FStatus.Text := 'Finished';
  end
  else
  begin
    AddNote(Format('Exited with code %d after %.2f s', [ExitCode, Secs]), ColorError);
    if FErrorKind <> '' then
      FStatus.Text := FErrorKind + ': ' + FErrorMessage
    else
      FStatus.Text := Format('Exited with code %d', [ExitCode]);
    MarkError;
  end;
  ScrollToEnd(FOutput);
  ShowNewestPlotIn(FRunDir, FRunStart);
end;

procedure TfrmMain.AddOutputLine(Kind: TOutputKind; const Line: string);
var
  Item: TListBoxItem;
  Frame: TFrame;
  Head, Msg: string;
begin
  while FOutput.Count >= MaxOutputLines do
    FOutput.ListItems[0].Free;
  Item := TListBoxItem.Create(FOutput);
  Item.Parent := FOutput;
  Item.Text := Line;
  Item.StyledSettings := Item.StyledSettings - [TStyledSetting.FontColor, TStyledSetting.Family];
  Item.TextSettings.Font.Family := {$IFDEF MSWINDOWS}'Consolas'{$ELSE}'Menlo'{$ENDIF};
  Item.TextSettings.FontColor := TAlphaColors.Black;
  if Kind = okStdErr then
  begin
    Item.TextSettings.FontColor := ColorError;
    if FFirstStdErr and ParseErrorHead(Line, Head, Msg) then
    begin
      FErrorKind := Head;
      FErrorMessage := Msg;
    end;
    FFirstStdErr := False;
    if ParseFrame(Line, Frame) then
    begin
      FFrames.Add(Frame);
      // A link: the frame's index into FFrames.
      Item.Tag := FFrames.Count;
      Item.TextSettings.FontColor := ColorLink;
      Item.Hint := 'Click to go to ' + Frame.FileName + ' line ' + IntToStr(Frame.Line);
      Item.ShowHint := True;
    end;
  end;
end;

procedure TfrmMain.AddNote(const Text: string; Color: TAlphaColor);
var
  Item: TListBoxItem;
begin
  Item := TListBoxItem.Create(FOutput);
  Item.Parent := FOutput;
  Item.Text := Text;
  Item.StyledSettings := Item.StyledSettings - [TStyledSetting.FontColor, TStyledSetting.Style];
  Item.TextSettings.FontColor := Color;
  Item.TextSettings.Font.Style := [TFontStyle.fsItalic];
end;

function TfrmMain.ResolveRunPath(const FileName: string): string;
begin
  // Reports name files relative to the run's directory, with "/" separators.
  Result := FileName.Replace('/', PathDelim);
  if not TPath.IsPathRooted(Result) then
    Result := TPath.Combine(FRunDir, Result);
  Result := TPath.GetFullPath(Result);
end;

procedure TfrmMain.GoToFrame(const Frame: TFrame);
var
  Path: string;
  Doc: TDocument;
begin
  Path := ResolveRunPath(Frame.FileName);
  if not TFile.Exists(Path) then
    Exit;
  Doc := OpenFile(Path);
  if Doc = nil then
    Exit;
  FTabs.ActiveTab := Doc.Tab;
  Doc.Editor.GoToLine(Frame.Line);
  Doc.Editor.SetFocus;
end;

procedure TfrmMain.OutputClick(const Sender: TCustomListBox; const Item: TListBoxItem);
begin
  if (Item <> nil) and (Item.Tag > 0) and (Item.Tag <= FFrames.Count) then
    GoToFrame(FFrames[Item.Tag - 1]);
end;

{ Underlines the error where it happened: the innermost frame in a file that
  is open, so an error inside a library function also marks the call in the
  user's own file when that file is the one open. }
procedure TfrmMain.MarkError;
var
  Frame: TFrame;
  Doc: TDocument;
  Msg: string;
  Marked: Boolean;
begin
  if (FErrorKind = '') or (FFrames.Count = 0) then
    Exit;
  Msg := FErrorKind + ': ' + FErrorMessage;
  Marked := False;
  for Frame in FFrames do
  begin
    Doc := FindDocument(ResolveRunPath(Frame.FileName));
    if Doc = nil then
      Continue;
    Doc.Editor.MarkWordAt(Frame.Line, Frame.Col, TMarkerKind.mkSquiggle, ColorError, Msg);
    if not Marked then
    begin
      FTabs.ActiveTab := Doc.Tab;
      Doc.Editor.GoToLine(Frame.Line);
      Marked := True;
    end;
  end;
end;

procedure TfrmMain.ShowNewestPlotIn(const Dir: string; Since: TDateTime);
var
  Files: TArray<string>;
  F, Newest: string;
  T, NewestTime: TDateTime;
begin
  if (Dir = '') or not TDirectory.Exists(Dir) then
    Exit;
  Files := TDirectory.GetFiles(Dir, '*.png');
  Newest := '';
  NewestTime := 0;
  for F in Files do
  begin
    T := TFile.GetLastWriteTime(F);
    // Written by this run (allowing for coarse file-time resolution).
    if (T >= IncSecond(Since, -2)) and (T > NewestTime) then
    begin
      Newest := F;
      NewestTime := T;
    end;
  end;
  if Newest = '' then
    Exit;
  try
    FPlotImage.Bitmap.LoadFromFile(Newest);
    FPlotCaption.Text := ExtractFileName(Newest);
  except
    FPlotCaption.Text := 'Cannot show ' + ExtractFileName(Newest);
  end;
end;

{ Scrolls a list to its last item once FMX has laid out new items (scrolling
  straight away, or inside BeginUpdate, stops short). }
procedure TfrmMain.ScrollToEnd(List: TListBox);
begin
  TThread.ForceQueue(nil,
    procedure
    begin
      if List.Count > 0 then
        List.ScrollToItem(List.ListItems[List.Count - 1]);
    end);
end;

{ ---------------- REPL ---------------- }

procedure TfrmMain.BuildReplPane(Parent: TFmxObject);
var
  Top, Bottom: TLayout;
  B: TSpeedButton;
begin
  Top := TLayout.Create(Self);
  Top.Parent := Parent;
  Top.Align := TAlignLayout.Top;
  Top.Height := 28;
  Top.Padding.Rect := TRectF.Create(2, 2, 2, 2);
  B := AddButton(Top, 'Restart', 'Start a fresh REPL session in the current file' + #39 + 's folder',
    CmdReplRestart);
  B.Width := 70;
  B := AddButton(Top, 'Clear', 'Clear the REPL transcript', CmdReplClear);
  B.Width := 60;
  FReplDirLabel := TLabel.Create(Self);
  FReplDirLabel.Parent := Top;
  FReplDirLabel.Align := TAlignLayout.Client;
  FReplDirLabel.Margins.Left := 10;
  FReplDirLabel.Text := 'Type an expression below and press Enter.';

  Bottom := TLayout.Create(Self);
  Bottom.Parent := Parent;
  Bottom.Align := TAlignLayout.Bottom;
  Bottom.Height := 30;
  Bottom.Padding.Rect := TRectF.Create(4, 3, 4, 3);
  FReplPrompt := TLabel.Create(Self);
  FReplPrompt.Parent := Bottom;
  FReplPrompt.Align := TAlignLayout.Left;
  FReplPrompt.Width := 28;
  FReplPrompt.Text := '>';
  FReplPrompt.StyledSettings := FReplPrompt.StyledSettings - [TStyledSetting.Family];
  FReplPrompt.TextSettings.Font.Family := {$IFDEF MSWINDOWS}'Consolas'{$ELSE}'Menlo'{$ENDIF};
  FReplEdit := TEdit.Create(Self);
  FReplEdit.Parent := Bottom;
  FReplEdit.Align := TAlignLayout.Client;
  FReplEdit.StyledSettings := FReplEdit.StyledSettings - [TStyledSetting.Family];
  FReplEdit.TextSettings.Font.Family := {$IFDEF MSWINDOWS}'Consolas'{$ELSE}'Menlo'{$ENDIF};
  FReplEdit.OnKeyDown := ReplEditKeyDown;

  FReplList := TListBox.Create(Self);
  FReplList.Parent := Parent;
  FReplList.Align := TAlignLayout.Client;
  FReplList.ItemHeight := 18;
end;

function TfrmMain.ReplWorkDir: string;
var
  Doc: TDocument;
begin
  Doc := CurrentDoc;
  if (Doc <> nil) and (Doc.FilePath <> '') then
    Result := ExtractFileDir(Doc.FilePath)
  else
    Result := TPath.GetDocumentsPath;
end;

function TfrmMain.EnsureRepl: Boolean;
var
  Exe: string;
begin
  Result := FRepl.Running;
  if Result then
    Exit;
  Exe := AxonExecutable;
  if Exe = '' then
  begin
    ReplAddLine('Cannot find the axon interpreter next to the IDE.', ColorError, True);
    Exit;
  end;
  FReplDir := ReplWorkDir;
  FReplPartial := '';
  try
    FRepl.Start(Exe, ['--repl-protocol'], FReplDir, True);
  except
    on E: Exception do
    begin
      ReplAddLine('Cannot start the REPL: ' + E.Message, ColorError, True);
      Exit;
    end;
  end;
  FReplDirLabel.Text := 'Session in ' + FReplDir;
  ReplAddLine('New session in ' + FReplDir, ColorNote, True);
  FReplPrompt.Text := '>';
  Result := True;
end;

procedure TfrmMain.ReplAddLine(const Text: string; Color: TAlphaColor; Italic: Boolean);
var
  Item: TListBoxItem;
begin
  while FReplList.Count >= MaxOutputLines do
    FReplList.ListItems[0].Free;
  Item := TListBoxItem.Create(FReplList);
  Item.Parent := FReplList;
  Item.Text := Text;
  Item.StyledSettings := Item.StyledSettings -
    [TStyledSetting.FontColor, TStyledSetting.Family, TStyledSetting.Style];
  Item.TextSettings.Font.Family := {$IFDEF MSWINDOWS}'Consolas'{$ELSE}'Menlo'{$ENDIF};
  Item.TextSettings.FontColor := Color;
  if Italic then
    Item.TextSettings.Font.Style := [TFontStyle.fsItalic];
  ScrollToEnd(FReplList);
end;

{ Protocol lines: #1 then ">" or "." is the REPL asking for input; #2 starts
  a line of an error report; anything else is output. }
procedure TfrmMain.ReplOutput(Kind: TOutputKind; const Text: string);
var
  S, L: string;
  P: Integer;
begin
  S := FReplPartial + Text.Replace(#13#10, #10).Replace(#13, #10);
  P := S.IndexOf(#10);
  FReplList.BeginUpdate;
  try
    while P >= 0 do
    begin
      L := S.Substring(0, P);
      S := S.Substring(P + 1);
      P := S.IndexOf(#10);
      if L.StartsWith(#1) then
      begin
        if L = #1'.' then
          FReplPrompt.Text := '...'
        else
        begin
          FReplPrompt.Text := '>';
          ShowNewestPlotIn(FReplDir, FReplSince);
        end;
      end
      else if L.StartsWith(#2) then
        ReplAddLine(L.Substring(1), ColorError)
      else if Kind = okStdErr then
        ReplAddLine(L, ColorError)
      else
        ReplAddLine(L, TAlphaColors.Black);
    end;
  finally
    FReplList.EndUpdate;
  end;
  ScrollToEnd(FReplList);
  FReplPartial := S;
end;

procedure TfrmMain.ReplExit(ExitCode: Integer);
begin
  if FReplRestart then
  begin
    FReplRestart := False;
    ReplAddLine('Session ended.', ColorNote, True);
    EnsureRepl;
    Exit;
  end;
  if FRepl.Killed then
    ReplAddLine('Session stopped.', ColorNote, True)
  else
    ReplAddLine(Format('Session ended (exit code %d). Enter a line to start a new one.',
      [ExitCode]), ColorNote, True);
  FReplDirLabel.Text := 'No session';
  FReplPrompt.Text := '>';
end;

procedure TfrmMain.ReplSend(const Lines: TArray<string>);
var
  L, Shown: string;
begin
  if not EnsureRepl then
    Exit;
  FBottomTabs.ActiveTab := FReplTab;
  FReplSince := Now;
  Shown := FReplPrompt.Text;
  for L in Lines do
  begin
    // The echo uses the prompt the REPL last showed; later lines continue it.
    ReplAddLine(Shown + ' ' + L, ColorLink);
    if Shown = '>' then
      Shown := '...';
    if not FRepl.WriteInput(L + #10) then
    begin
      ReplAddLine('The REPL is not accepting input.', ColorError, True);
      Exit;
    end;
  end;
end;

procedure TfrmMain.ReplEditKeyDown(Sender: TObject; var Key: Word; var KeyChar: WideChar;
  Shift: TShiftState);
var
  Line: string;
begin
  case Key of
    vkReturn:
      begin
        Line := FReplEdit.Text;
        FReplEdit.Text := '';
        if (Line.Trim <> '') and ((FReplHistory.Count = 0) or
          (FReplHistory[FReplHistory.Count - 1] <> Line)) then
          FReplHistory.Add(Line);
        FReplHistoryPos := FReplHistory.Count;
        ReplSend([Line]);
        Key := 0;
      end;
    vkUp:
      begin
        if FReplHistoryPos > 0 then
        begin
          Dec(FReplHistoryPos);
          FReplEdit.Text := FReplHistory[FReplHistoryPos];
          FReplEdit.GoToTextEnd;
        end;
        Key := 0;
      end;
    vkDown:
      begin
        if FReplHistoryPos < FReplHistory.Count - 1 then
        begin
          Inc(FReplHistoryPos);
          FReplEdit.Text := FReplHistory[FReplHistoryPos];
        end
        else
        begin
          FReplHistoryPos := FReplHistory.Count;
          FReplEdit.Text := '';
        end;
        FReplEdit.GoToTextEnd;
        Key := 0;
      end;
  end;
end;

procedure TfrmMain.CmdSendToRepl(Sender: TObject);
var
  Doc: TDocument;
  Text: string;
begin
  Doc := CurrentDoc;
  if Doc = nil then
    Exit;
  Text := Doc.Editor.SelText;
  if Text = '' then
    Text := Doc.Editor.LineText(Doc.Editor.CaretLine);
  ReplSend(Text.Replace(#13#10, #10).Split([#10]));
end;

procedure TfrmMain.CmdReplRestart(Sender: TObject);
begin
  FBottomTabs.ActiveTab := FReplTab;
  if FRepl.Running then
  begin
    FReplRestart := True;
    FRepl.Kill;
  end
  else
    EnsureRepl;
end;

procedure TfrmMain.CmdReplClear(Sender: TObject);
begin
  FReplList.Clear;
end;

{ ---------------- commands ---------------- }

procedure TfrmMain.CmdNew(Sender: TObject);
begin
  NewDocument('', '');
end;

procedure TfrmMain.CmdOpen(Sender: TObject);
var
  Dlg: TOpenDialog;
  Doc: TDocument;
  F: string;
begin
  Dlg := TOpenDialog.Create(nil);
  try
    Dlg.Filter := FileFilter;
    Dlg.Options := Dlg.Options + [TOpenOption.ofAllowMultiSelect, TOpenOption.ofFileMustExist];
    Doc := CurrentDoc;
    if (Doc <> nil) and (Doc.FilePath <> '') then
      Dlg.InitialDir := ExtractFileDir(Doc.FilePath);
    if Dlg.Execute then
      for F in Dlg.Files do
        OpenFile(F);
  finally
    Dlg.Free;
  end;
end;

procedure TfrmMain.CmdSave(Sender: TObject);
begin
  if CurrentDoc <> nil then
    SaveDoc(CurrentDoc, False);
end;

procedure TfrmMain.CmdSaveAs(Sender: TObject);
begin
  if CurrentDoc <> nil then
    SaveDoc(CurrentDoc, True);
end;

procedure TfrmMain.CmdClose(Sender: TObject);
begin
  if CurrentDoc <> nil then
    CloseDoc(CurrentDoc);
end;

{$IFNDEF MACOS}
procedure TfrmMain.CmdExit(Sender: TObject);
begin
  Close;
end;
{$ENDIF}

procedure TfrmMain.CmdUndo(Sender: TObject);
begin
  if CurrentDoc <> nil then CurrentDoc.Editor.Undo;
end;

procedure TfrmMain.CmdRedo(Sender: TObject);
begin
  if CurrentDoc <> nil then CurrentDoc.Editor.Redo;
end;

procedure TfrmMain.CmdCut(Sender: TObject);
begin
  if CurrentDoc <> nil then CurrentDoc.Editor.CutSelection;
end;

procedure TfrmMain.CmdCopy(Sender: TObject);
begin
  if CurrentDoc <> nil then CurrentDoc.Editor.CopySelection;
end;

procedure TfrmMain.CmdPaste(Sender: TObject);
begin
  if CurrentDoc <> nil then CurrentDoc.Editor.PasteClipboard;
end;

procedure TfrmMain.CmdSelectAll(Sender: TObject);
begin
  if CurrentDoc <> nil then CurrentDoc.Editor.SelectAll;
end;

procedure TfrmMain.CmdFind(Sender: TObject);
begin
  if CurrentDoc <> nil then CurrentDoc.Editor.ShowBuiltInFindBar;
end;

procedure TfrmMain.CmdToggleComment(Sender: TObject);
begin
  if CurrentDoc <> nil then CurrentDoc.Editor.ToggleLineComment;
end;

procedure TfrmMain.CmdClearOutput(Sender: TObject);
begin
  FOutput.Clear;
end;

procedure TfrmMain.CmdAbout(Sender: TObject);
begin
  TDialogServiceSync.MessageDialog('Axon IDE'#10'An editor and runner for the Axon language.',
    TMsgDlgType.mtInformation, [TMsgDlgBtn.mbOK], TMsgDlgBtn.mbOK, 0);
end;

end.
