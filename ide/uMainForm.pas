unit uMainForm;

(* The Axon IDE's main window.

   - Tabs of TSkiaCodeEditor documents with Axon highlighting, and a
     Welcome tab (at start-up, from Help > Welcome, and when the last file
     closes) with New, Open, the main shortcuts, the recent files and the
     examples. An example opens as a copy in Documents/Axon Examples, so it
     can be edited and run without touching the installed originals.
   - Run (F9) saves the current file and runs axon on it as a separate
     process, in the file's directory, so imports and package.toml resolve
     exactly as on the command line. Stop (Ctrl+F2) kills it.
   - The output pane shows stdout and stderr (red) as they arrive. Error and
     trace lines are links: clicking one opens the file at that line. After a
     failed run, the error location gets a wavy underline whose tooltip is
     the error.
   - The plot pane shows figures from plot.show() as they appear: the IDE
     sets AXON_SHOW_DIR for the programs it starts, and graphics.show then
     writes a line #3"show <path>" to stderr. Without one, the pane shows
     the newest PNG the run saved in its directory.
   - The REPL tab drives "axon --repl-protocol" through pipes: a session
     starts on first use in the current file's directory and keeps its
     variables until it is restarted. Send to REPL (Ctrl+Enter) sends the
     editor's selection, or the current line.
   - Syntax is checked as you type: 0.6 s after the last edit, the text is
     piped to "axon --check -", and a syntax error gets a wavy underline.
   - The Documentation tab shows the markdown help pages (help folder next to
     the IDE) in a TRhoMarkdownViewer: links to pages, #anchors, web links
     (browser) and examples (a copy opens in the editor), with Back.
   - On Windows the menu is an FMX TMenuBar, so it is styled with the rest;
     on macOS it is the native menu bar.
   - Run > Use JIT Compiler (and the JIT button) runs programs and the REPL
     with axon's JIT on or off (AXON_JIT), so the same program can be timed
     both ways; saved in settings.ini. With AXON_JIT_REPORT, axon reports each
     compile decision as a #3"jit ..." line on stderr, and the Output pane
     ends a run with the functions compiled and those left interpreted.
   - Edit > Preferences sets the font size of the editors and of the output
     panes (Output, REPL, Help); saved in settings.ini.
   - View > Dark Theme switches the whole window live: the embedded FMX
     MineShaft style (RCDATA DARKSTYLE), the editors' colours and syntax palette, the help viewer
     and the output panes. The choice is kept in settings.ini.
   - Help (F1) shows the documentation of the name under the caret in the
     Help tab: from the editor text for a function or record defined in the
     file, otherwise from "help name" in a short-lived axon session that
     first runs the file's import lines, so module names resolve.

   The layout is built in code; the .fmx holds only the empty form. *)

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes,
  System.Generics.Collections, System.IniFiles,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.StdCtrls,
  FMX.Layouts, FMX.ListBox, FMX.TabControl, FMX.Menus, FMX.Objects,
  FMX.Controls.Presentation, FMX.Edit, FMX.Memo,
  uSkiaCodeEditor, uCodeEditorTypes, uFindBar, uProcessRunner, uRunReport,
  uRhoMarkdownViewer, uPreferences, uRefSections, Axon.Version, SkPlotPaintBox,
  uFigureChart, Rho3DPlot, uFigureChart3D, uFigureGrid, uFigureExport,
  System.Skia, FMX.Skia, Axon.Scene;

type
  { A figure in the history: a scene from the display channel (with the
    plot figure record as JSON, for the interactive charts, when it came
    from plot.show), or a PNG file (one a run saved, or from an axon that
    reported figures by file). }
  TFigureEntry = class
  public
    Scene: TScene;           // owned, or nil
    Json: string;
    Path: string;
    destructor Destroy; override;
  end;

  { Text colours of the output panes, per theme. }
  TPanePalette = record
    Text, Error, Note, Link: TAlphaColor;
  end;

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
    procedure FormActivate(Sender: TObject);
    procedure FullScreenTimerFired(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
  private
    FDocs: TObjectList<TDocument>;
    FTabs: TTabControl;
    FOutput: TListBox;
    FPlotImage: TImage;
    FPlotChart: TSkPlotPaintBox;   // 2-D figures, interactive
    FPlot3D: TRho3DPlot;           // 3-D figures, interactive
    FPlotGrid: TControl;           // figures with subplots: a grid of charts, or nil
    FPlotScene: TSkPaintBox;       // scenes from the display channel, drawn to fit
    FShownScene: TScene;           // the scene FPlotScene draws (an entry's), or nil
    FPlotCaption: TLabel;
    // Figure history: every figure shown or picked up, oldest first; the
    // pane shows FFigureIndex, which the arrow buttons move.
    FFigures: TObjectList<TFigureEntry>;
    FFigureIndex: Integer;
    FFigurePrev, FFigureNext, FFigureClear, FFigureSave, FFigureCopy: TSpeedButton;
    FFigurePos: TLabel;
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
    FJitWhere: TList<TFrame>;        // per entry of FJitRejected: where, from its reason
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
    FReplPartial: array[TOutputKind] of string;  // per stream: a print may leave stdout open
    FReplDir: string;
    FReplRestart: Boolean;
    FReplHistory: TStringList;
    FReplHistoryPos: Integer;
    FReplSince: TDateTime;
    // Help
    FHelpTab: TTabItem;
    FHelpViewer: TRhoMarkdownViewer;  // help on a name, as markdown
    FHelpRefName: string;   // F1 name for the reference lookup, alias resolved
    FHelpRunner: TProcessRunner;
    FHelpName: string;
    FHelpSkip: Integer;        // ready markers to pass before the help output
    FHelpPartial: string;
    FHelpLines: TStringList;
    // Syntax check as you type
    FCheckTimer: TTimer;
    FCheckRunner: TProcessRunner;
    FCheckDoc: TDocument;
    FCheckText: string;
    FCheckOutput: string;
    FCheckAgain: Boolean;
    // Figures from plot.show()
    FShowDir: string;
    // Layout remembered between sessions
    FPlotPane: TLayout;
    FNormalBounds: TRect;      // the window's bounds when last not maximized
    FSettingsSaved: Boolean;   // saved when closing was agreed (FormCloseQuery)
    FPendingFullScreen: Boolean; // macOS: go full screen once the window is active
    FPendingMaximize: Boolean; // macOS: maximize (zoom) once the window is active
    FWasFullScreen: Boolean;   // macOS: full screen at the last resize (what is saved)
    // Welcome tab (nil when closed)
    FWelcomeTab: TTabItem;
    FWelcomeList: TListBox;
    FExamplesList: TListBox;
    // Documentation tab (nil when closed)
    FDocsTab: TTabItem;
    FDocsViewer: TRhoMarkdownViewer;
    FDocsTitle: TLabel;
    FDocsBack: TButton;
    FDocsFindBar: TFindBar;      // RhoEditor's find bar, find-only (Ctrl+F)
    FDocsPage: string;           // full path of the page shown
    FDocsHistory: TStringList;   // earlier pages as "path|scroll", for Back
    // Theme
    FDark: Boolean;
    FPal: TPanePalette;
    FDarkItem: TMenuItem;
    // JIT
    FJit: Boolean;
    FJitItem: TMenuItem;
    FJitButton: TSpeedButton;
    FJitCompiled, FJitRejected: TStringList;
    // Preferences
    FPrefs: TIdePreferences;
    FFigureShown: Boolean;     // since the current run or REPL command started
    // Animation frames (graphics.frame): the newest frame's file, whether a
    // display of it is queued, and whether the last history entry is the
    // current animation (updated in place by each frame).
    FAnimPending: string;          // a frame's file (marker lines), or ''
    FAnimBytes: TBytes;            // a frame's scene (display channel), or nil
    FAnimQueued: Boolean;
    FAnimActive: Boolean;
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
    procedure MakeCopyable(List: TListBox);
    procedure CopyPaneLines(List: TListBox; All: Boolean);
    procedure PaneKeyDown(Sender: TObject; var Key: Word; var KeyChar: WideChar;
      Shift: TShiftState);
    procedure PaneCopyClick(Sender: TObject);
    procedure PaneCopyAllClick(Sender: TObject);
    procedure AddFigure(const Path: string);
    procedure DisplayFigure(Index: Integer);
    procedure UpdateFigureBar;
    procedure FigurePrevClick(Sender: TObject);
    procedure FigureNextClick(Sender: TObject);
    procedure FigureClearClick(Sender: TObject);
    procedure FigureSaveClick(Sender: TObject);
    procedure FigureCopyClick(Sender: TObject);
    function FigureViewBitmap: FMX.Graphics.TBitmap;
    function FigureView: TControl;
    procedure ScrollToEnd(List: TListBox);
    function WordAtCaret(Doc: TDocument): string;
    function LocalHelp(Doc: TDocument; const Name: string; out Text: string): Boolean;
    procedure ShowHelp(const Text: string);
    procedure HelpOutput(Kind: TOutputKind; const Text: string);
    procedure HelpExit(ExitCode: Integer);
    procedure CheckTimerFired(Sender: TObject);
    procedure StartCheck(Doc: TDocument);
    procedure CheckOutput(Kind: TOutputKind; const Text: string);
    procedure CheckExit(ExitCode: Integer);
    procedure SetupShowDir;
    procedure RecordNormalBounds;
    procedure ShowWelcome;
    procedure CloseWelcome;
    procedure RefreshWelcome;
    procedure WelcomeItemClick(const Sender: TCustomListBox; const Item: TListBoxItem);
    procedure ExampleItemClick(const Sender: TCustomListBox; const Item: TListBoxItem);
    procedure RefreshExamples;
    function ExamplesDir: string;
    procedure CmdWelcome(Sender: TObject);
    procedure OpenExampleCopy(const Source: string);
    function HelpDir: string;
    procedure ShowDocs(const Target: string);
    procedure NavigateDocs(const Path, Anchor: string; AddToHistory: Boolean;
      ScrollTo: Single = -1);
    procedure DocsLinkClick(Sender: TObject; const AUrl: string);
    procedure HelpLinkClick(Sender: TObject; const AUrl: string);
    procedure ShowHelpFor(const RefName, Text: string);
    procedure OpenExternal(const Target: string);
    procedure CmdDocs(Sender: TObject);
    procedure CmdBuiltins(Sender: TObject);
    procedure CmdReference(Sender: TObject);
    procedure CmdDocsBack(Sender: TObject);
    procedure CmdDocsHome(Sender: TObject);
    procedure DocsSearch(const S: string; O: TFindOptions);
    procedure DocsSearchChange(Sender: TObject);
    procedure ThemeDocsFindBar;
    procedure EditorGotoLine(Sender: TObject);
    procedure ApplyTheme(Dark: Boolean);
    procedure ApplyEditorTheme(Editor: TSkiaCodeEditor);
    procedure RecolorList(List: TListBox; const Old: TPanePalette);
    procedure CmdDarkTheme(Sender: TObject);
    procedure CmdToggleJit(Sender: TObject);
    procedure ApplyJit(On: Boolean);
    function TryJitReport(const Line: string): Boolean;
    procedure ReportJit;
    procedure CmdPreferences(Sender: TObject);
    procedure ApplyPreferences;
    procedure SizePaneItem(Item: TListBoxItem);
    function IsFullScreen: Boolean;
    procedure LoadLayout(Ini: TCustomIniFile);
    procedure SaveLayout(Ini: TCustomIniFile);
    function TryShowFigure(const Line: string): Boolean;
    function TryShowFrame(const Line: string): Boolean;
    procedure ShowPendingFrame;
    function AnimEntry(Make: Boolean): TFigureEntry;
    procedure ApplyPendingFrame;
    procedure AddToFrame(const Payload: TBytes);
    procedure DisplayMessage(Kind: Byte; const Payload: TBytes);
    procedure AddEntry(Entry: TFigureEntry);
    procedure ShowOnly(View: TControl);
    procedure PlotSceneDraw(ASender: TObject; const ACanvas: ISkCanvas; const ADest: TRectF;
      const AOpacity: Single);
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
    procedure SetTabTitle(Tab: TTabItem; const Title: string);
    procedure TabMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
      X, Y: Single);
    procedure CloseTab(Tab: TTabItem);
    procedure FreeEditorTab(Tab: TTabItem);
{$IFNDEF MACOS}
    procedure CmdExit(Sender: TObject);
{$ENDIF}
    procedure CmdUndo(Sender: TObject);
    procedure CmdRedo(Sender: TObject);
    procedure CmdCut(Sender: TObject);
    procedure CmdCopy(Sender: TObject);
    function FocusedViewer: TRhoMarkdownViewer;
    procedure CmdPaste(Sender: TObject);
    procedure CmdSelectAll(Sender: TObject);
    procedure CmdFind(Sender: TObject);
    procedure CmdToggleComment(Sender: TObject);
    procedure CmdRun(Sender: TObject);
    procedure CmdStop(Sender: TObject);
    procedure CmdClearOutput(Sender: TObject);
    procedure CmdAbout(Sender: TObject);
    procedure CmdSendToRepl(Sender: TObject);
    procedure CmdRunInRepl(Sender: TObject);
    procedure CmdReplRestart(Sender: TObject);
    procedure CmdReplClear(Sender: TObject);
    procedure CmdHelpWord(Sender: TObject);
  public
    { Every move and resize of the window arrives here (FMX has no move
      event), so the normal bounds are recorded from it. }
    procedure SetBoundsF(const ALeft, ATop, AWidth, AHeight: Single); override;
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.fmx}

uses
  FMX.Styles, System.Hash,
{$IFDEF MSWINDOWS}
  Winapi.Windows, Winapi.ShellAPI,
{$ELSE}
  Posix.Stdlib,
{$ENDIF}
  System.IOUtils, System.DateUtils, System.Math,
  FMX.ActnList, FMX.DialogService.Sync, FMX.Platform,
  uAxonHighlighter;

var
  // Set first thing in FormDestroy. Work deferred with TThread.ForceQueue(nil,
  // ...) is not removed when the form goes, and may run after it is freed
  // (the REPL list's ScrollToEnd did, on quit), so each such job checks this
  // first; it is a unit variable because the form may no longer exist.
  GClosing: Boolean = False;

const
  MaxOutputLines = 10000;
  MaxRecent = 8;
  // Error squiggles, readable on both themes.
  ColorError = $FFE53935;
  ColorJit = $FFE53935;      // the squiggle under a line that runs interpreted (as errors')
  FileFilter = 'Axon files (*.sci)|*.sci|All files (*.*)|*.*';

{ ---------------- menu shortcut labels ---------------- }

{$IFDEF MSWINDOWS}
type
  { The Windows menu service labels Ctrl+, and Ctrl+/ as Ctrl+',' and
    Ctrl+'/'. This wrapper labels those two plainly and passes everything
    else to the platform's service. }
  TShortCutLabels = class(TInterfacedObject, IFMXMenuService)
  private
    FInner: IFMXMenuService;
  public
    constructor Create(const Inner: IFMXMenuService);
    procedure StartMenuLoop(const AView: IMenuView);
    function ShortCutToText(ShortCut: TShortCut): string;
    procedure ShortCutToKey(ShortCut: TShortCut; var Key: Word; var Shift: TShiftState);
    function TextToShortCut(Text: string): Integer;
    procedure CreateOSMenu(AForm: TCommonCustomForm; const AMenu: IItemsContainer);
    procedure UpdateMenuItem(const AItem: IItemsContainer; AChange: TMenuItemChanges);
    procedure DestroyMenuItem(const AItem: IItemsContainer);
    function IsMenuBarOnWindowBorder: Boolean;
    procedure UpdateMenuBar;
  end;

constructor TShortCutLabels.Create(const Inner: IFMXMenuService);
begin
  inherited Create;
  FInner := Inner;
end;

procedure TShortCutLabels.StartMenuLoop(const AView: IMenuView);
begin
  FInner.StartMenuLoop(AView);
end;

function TShortCutLabels.ShortCutToText(ShortCut: TShortCut): string;
begin
  if ShortCut = scCtrl or vkComma then
    Result := 'Ctrl+,'
  else if ShortCut = scCtrl or vkSlash then
    Result := 'Ctrl+/'
  else
    Result := FInner.ShortCutToText(ShortCut);
end;

procedure TShortCutLabels.ShortCutToKey(ShortCut: TShortCut; var Key: Word; var Shift: TShiftState);
begin
  FInner.ShortCutToKey(ShortCut, Key, Shift);
end;

function TShortCutLabels.TextToShortCut(Text: string): Integer;
begin
  Result := FInner.TextToShortCut(Text);
end;

procedure TShortCutLabels.CreateOSMenu(AForm: TCommonCustomForm; const AMenu: IItemsContainer);
begin
  FInner.CreateOSMenu(AForm, AMenu);
end;

procedure TShortCutLabels.UpdateMenuItem(const AItem: IItemsContainer; AChange: TMenuItemChanges);
begin
  FInner.UpdateMenuItem(AItem, AChange);
end;

procedure TShortCutLabels.DestroyMenuItem(const AItem: IItemsContainer);
begin
  FInner.DestroyMenuItem(AItem);
end;

function TShortCutLabels.IsMenuBarOnWindowBorder: Boolean;
begin
  Result := FInner.IsMenuBarOnWindowBorder;
end;

procedure TShortCutLabels.UpdateMenuBar;
begin
  FInner.UpdateMenuBar;
end;

{ Installed once, before any menu item is created (items look the service up
  when they are made). }
procedure InstallShortCutLabels;
var
  Inner: IFMXMenuService;
begin
  if TPlatformServices.Current.SupportsPlatformService(IFMXMenuService, Inner) and
    not ((Inner as TObject) is TShortCutLabels) then
  begin
    TPlatformServices.Current.RemovePlatformService(IFMXMenuService);
    TPlatformServices.Current.AddPlatformService(IFMXMenuService, TShortCutLabels.Create(Inner));
  end;
end;
{$ENDIF}

{ ---------------- TDocument ---------------- }

function TDocument.DisplayName: string;
begin
  if FilePath <> '' then
    Result := ExtractFileName(FilePath)
  else
    Result := Format('untitled%d.sci', [UntitledNumber]);
end;

{ ---------------- set-up ---------------- }

function PanePalette(Dark: Boolean): TPanePalette; forward;

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  FDocs := TObjectList<TDocument>.Create(True);
  FFrames := TList<TFrame>.Create;
  FJitWhere := TList<TFrame>.Create;
  FRecent := TStringList.Create;
  FFigures := TObjectList<TFigureEntry>.Create(True);
  FFigureIndex := -1;
  FRunner := TProcessRunner.Create;
  FRunner.OnOutput := RunOutput;
  FRunner.OnExit := RunExit;
  FRunner.OnDisplay := DisplayMessage;
  FRepl := TProcessRunner.Create;
  FRepl.OnOutput := ReplOutput;
  FRepl.OnExit := ReplExit;
  FRepl.OnDisplay := DisplayMessage;
  FReplHistory := TStringList.Create;
  FHelpRunner := TProcessRunner.Create;
  FHelpRunner.OnOutput := HelpOutput;
  FHelpRunner.OnExit := HelpExit;
  FHelpLines := TStringList.Create;
  FCheckRunner := TProcessRunner.Create;
  FCheckRunner.OnOutput := CheckOutput;
  FCheckRunner.OnExit := CheckExit;
  FCheckTimer := TTimer.Create(Self);
  FCheckTimer.Enabled := False;
  FCheckTimer.Interval := 600;
  FCheckTimer.OnTimer := CheckTimerFired;
  FDocsHistory := TStringList.Create;
  FPal := PanePalette(False);
  FPrefs := TIdePreferences.Defaults;
  SetupShowDir;
  FJitCompiled := TStringList.Create;
  FJitRejected := TStringList.Create;
  BuildUI;
  BuildMenu;
  ApplyJit(True);
  FNormalBounds := TRect.Create(Left, Top, Left + Width, Top + Height);
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
    ShowWelcome;
  SetRunning(False);
  UpdateTitle;
end;

{ macOS: a window that was maximized (zoomed) or full screen when the IDE
  last closed becomes so again, shortly after it first becomes active (the
  window has to be on screen for macOS to change it). }
procedure TfrmMain.FormActivate(Sender: TObject);
var
  T: TTimer;
begin
  if not (FPendingFullScreen or FPendingMaximize) then
    Exit;
  T := TTimer.Create(Self);
  T.Interval := 300;
  T.OnTimer := FullScreenTimerFired;
  T.Enabled := True;
end;

procedure TfrmMain.FullScreenTimerFired(Sender: TObject);
begin
  TTimer(Sender).Enabled := False;
  if FPendingMaximize then
    WindowState := TWindowState.wsMaximized;
  if FPendingFullScreen then
    FullScreen := True;
  FPendingMaximize := False;
  FPendingFullScreen := False;
  // Freed after this event returns.
  TThread.ForceQueue(nil,
    procedure
    begin
      if not GClosing then
        Sender.Free;
    end);
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  GClosing := True;
  FRunner.Free;          // kills a running program
  FRepl.Free;            // and the REPL session
  FReplHistory.Free;
  FHelpRunner.Free;
  FHelpLines.Free;
  FCheckTimer.Enabled := False;
  FCheckRunner.Free;
  FDocsHistory.Free;
  FJitCompiled.Free;
  FJitRejected.Free;
  FJitWhere.Free;
  // The figures of this session are temporary.
  if (FShowDir <> '') and TDirectory.Exists(FShowDir) then
    try
      TDirectory.Delete(FShowDir, True);
    except
    end;
  if not FSettingsSaved then
    SaveSettings;
  FRecent.Free;
  FShownScene := nil;
  FFigures.Free;
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
  // Save the layout now: on macOS, Quit asks the main form whether it may
  // close and then ends the application without destroying the form, so
  // FormDestroy never runs; and by then the window, whose state is saved,
  // is gone.
  SaveSettings;
  FSettingsSaved := True;
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
  Body, Right, FigBar: TLayout;
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
  AddButton(Bar, #$25B6' REPL', 'Run the current file in the REPL, keeping its variables there (Shift+F9)',
    CmdRunInRepl).Width := 72;
  FStopButton := AddButton(Bar, #$25A0' Stop', 'Stop the running program (Ctrl+F2)', CmdStop);
  FJitButton := AddButton(Bar, 'JIT on', 'Compile functions to native code (Run > Use JIT Compiler); ' +
    'click to switch, then run again to compare', CmdToggleJit);
  FJitButton.Width := 72;
  FJitButton.Margins.Left := 16;
  FJitButton.StaysPressed := True;

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
  FPlotPane := Right;
  Right.Parent := Body;
  Right.Align := TAlignLayout.Right;
  Right.Width := 380;
  // The header: "Plot", then the figure history's arrows, position and Clear.
  FigBar := TLayout.Create(Self);
  FigBar.Parent := Right;
  FigBar.Align := TAlignLayout.Top;
  FigBar.Height := 24;
  FFigureClear := TSpeedButton.Create(Self);
  FFigureClear.Parent := FigBar;
  FFigureClear.Align := TAlignLayout.Right;
  FFigureClear.Width := 44;
  FFigureClear.Text := 'Clear';
  FFigureClear.Hint := 'Forget all figures';
  FFigureClear.ShowHint := True;
  FFigureClear.OnClick := FigureClearClick;
  FFigureSave := TSpeedButton.Create(Self);
  FFigureSave.Parent := FigBar;
  FFigureSave.Align := TAlignLayout.Right;
  FFigureSave.Position.X := 0;          // left of Clear
  FFigureSave.Width := 48;
  FFigureSave.Text := 'Save' + #$2026;
  FFigureSave.Hint := 'Save this figure, all of it, as PNG, PDF or SVG';
  FFigureSave.ShowHint := True;
  FFigureSave.OnClick := FigureSaveClick;
  FFigureCopy := TSpeedButton.Create(Self);
  FFigureCopy.Parent := FigBar;
  FFigureCopy.Align := TAlignLayout.Right;
  FFigureCopy.Position.X := 0;          // left of Save
  FFigureCopy.Width := 44;
  FFigureCopy.Text := 'Copy';
  FFigureCopy.Hint := 'Copy this figure, all of it, as an image';
  FFigureCopy.ShowHint := True;
  FFigureCopy.OnClick := FigureCopyClick;
  FFigureNext := TSpeedButton.Create(Self);
  FFigureNext.Parent := FigBar;
  FFigureNext.Align := TAlignLayout.Right;
  FFigureNext.Position.X := 0;          // left of Copy
  FFigureNext.Width := 26;
  FFigureNext.Text := #$25B6;
  FFigureNext.Hint := 'Next figure';
  FFigureNext.ShowHint := True;
  FFigureNext.OnClick := FigureNextClick;
  FFigurePos := TLabel.Create(Self);
  FFigurePos.Parent := FigBar;
  FFigurePos.Align := TAlignLayout.Right;
  FFigurePos.Position.X := 0;           // left of the next button
  FFigurePos.Width := 56;
  FFigurePos.TextSettings.HorzAlign := TTextAlign.Center;
  FFigurePrev := TSpeedButton.Create(Self);
  FFigurePrev.Parent := FigBar;
  FFigurePrev.Align := TAlignLayout.Right;
  FFigurePrev.Position.X := 0;          // left of the position
  FFigurePrev.Width := 26;
  FFigurePrev.Text := #$25C0;
  FFigurePrev.Hint := 'Previous figure';
  FFigurePrev.ShowHint := True;
  FFigurePrev.OnClick := FigurePrevClick;
  Header := TLabel.Create(Self);
  Header.Parent := FigBar;
  Header.Align := TAlignLayout.Client;
  Header.Margins.Left := 6;
  Header.Text := 'Plot';
  Header.StyledSettings := Header.StyledSettings - [TStyledSetting.Style];
  Header.TextSettings.Font.Style := [TFontStyle.fsBold];
  FPlotCaption := TLabel.Create(Self);
  FPlotCaption.Parent := Right;
  FPlotCaption.Align := TAlignLayout.Bottom;
  FPlotCaption.Height := 20;
  FPlotCaption.Margins.Left := 6;
  FPlotCaption.Text := 'Figures from plot.show, and PNGs a run saves, appear here.';
  FPlotImage := TImage.Create(Self);
  FPlotImage.Parent := Right;
  FPlotImage.Align := TAlignLayout.Client;
  FPlotImage.WrapMode := TImageWrapMode.Fit;
  FPlotImage.Margins.Rect := TRectF.Create(4, 4, 4, 4);
  // Line and scatter figures from plot.show are drawn here instead, where
  // they can be zoomed (wheel, Shift-drag), panned (drag), reset
  // (Ctrl+double-click) and edited (double-click); see uFigureChart.
  FPlotChart := TSkPlotPaintBox.Create(Self);
  FPlotChart.Parent := Right;
  FPlotChart.Align := TAlignLayout.Client;
  FPlotChart.Margins.Rect := TRectF.Create(4, 4, 4, 4);
  FPlotChart.ZoomPanEnabled := True;
  FPlotChart.Visible := False;
  // 3-D figures (surfaces, line3, scatter3): drag rotates, right-drag pans,
  // wheel zooms, double-click edits; see uFigureChart3D.
  FPlot3D := TRho3DPlot.Create(Self);
  FPlot3D.Parent := Right;
  FPlot3D.Align := TAlignLayout.Client;
  FPlot3D.Margins.Rect := TRectF.Create(4, 4, 4, 4);
  FPlot3D.Visible := False;
  // Scenes from graphics.show, draw.show and draw.frame (the display
  // channel), drawn with Axon.Scene, the code axon saves pictures with.
  FPlotScene := TSkPaintBox.Create(Self);
  FPlotScene.Parent := Right;
  FPlotScene.Align := TAlignLayout.Client;
  FPlotScene.Margins.Rect := TRectF.Create(4, 4, 4, 4);
  FPlotScene.OnDraw := PlotSceneDraw;
  FPlotScene.Visible := False;
  UpdateFigureBar;
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
  FHelpTab := FBottomTabs.Add;
  FHelpTab.Text := 'Help';
  FHelpViewer := TRhoMarkdownViewer.Create(Self);
  FHelpViewer.Parent := FHelpTab;
  FHelpViewer.Align := TAlignLayout.Client;
  FHelpViewer.OnLinkClick := HelpLinkClick;
  FHelpViewer.MarkdownText := 'Put the caret on a name in the editor and press F1.';
  FOutput := TListBox.Create(Self);
  FOutput.Parent := FOutputTab;
  FOutput.Align := TAlignLayout.Client;
  FOutput.ItemHeight := 18;
  FOutput.OnItemClick := OutputClick;
  MakeCopyable(FOutput);
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
  // TextToShortCut cannot read "," or "/" (it returns 0), so those two are
  // built from key codes.
  if ShortCut = 'Ctrl+,' then
    Result.ShortCut := scCtrl or vkComma
  else if ShortCut = 'Ctrl+/' then
    Result.ShortCut := scCtrl or vkSlash
  else if ShortCut <> '' then
    Result.ShortCut := TextToShortCut(ShortCut);
  Result.OnClick := Handler;
end;

procedure TfrmMain.BuildMenu;
var
  Menu: TFmxObject;
  M: TMenuItem;
{$IFDEF MSWINDOWS}
  Bar: TMenuBar;
{$ENDIF}
begin
{$IFDEF MSWINDOWS}
  InstallShortCutLabels;
  // A menu bar FMX draws itself, so it follows the style (dark with the dark
  // theme); a native Windows menu cannot be restyled. Shortcuts still work:
  // the form passes keys the focused control does not use to the items.
  Bar := TMenuBar.Create(Self);
  Bar.Parent := Self;
  Bar.Position.Y := -100;          // above the toolbar
  Bar.Align := TAlignLayout.Top;
  Menu := Bar;
{$ELSE}
  // macOS: the native menu at the top of the screen, which follows the
  // system appearance.
  Menu := TMainMenu.Create(Self);
  Menu.Parent := Self;
{$ENDIF}

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
  AddMenuItem(M, '-', '', nil);
  AddMenuItem(M, 'Pr&eferences...', 'Ctrl+,', CmdPreferences);

  M := AddMenuItem(Menu, '&View', '', nil);
  FDarkItem := AddMenuItem(M, '&Dark Theme', '', CmdDarkTheme);

  M := AddMenuItem(Menu, '&Run', '', nil);
  FRunItem := AddMenuItem(M, '&Run', 'F9', CmdRun);
  FStopItem := AddMenuItem(M, '&Stop', 'Ctrl+F2', CmdStop);
  FJitItem := AddMenuItem(M, 'Use &JIT Compiler', '', CmdToggleJit);
  AddMenuItem(M, '-', '', nil);
  AddMenuItem(M, 'Run in REP&L', 'Shift+F9', CmdRunInRepl);
  AddMenuItem(M, 'Send to RE&PL', 'Ctrl+Enter', CmdSendToRepl);
  AddMenuItem(M, 'Restart R&EPL', '', CmdReplRestart);
  AddMenuItem(M, '-', '', nil);
  AddMenuItem(M, 'C&lear Output', '', CmdClearOutput);

  M := AddMenuItem(Menu, '&Help', '', nil);
  AddMenuItem(M, '&Documentation', 'Ctrl+F1', CmdDocs);
  AddMenuItem(M, '&Language Reference', '', CmdReference);
  AddMenuItem(M, '&Built-in Functions', '', CmdBuiltins);
  AddMenuItem(M, '&Welcome', '', CmdWelcome);
  AddMenuItem(M, '&Help on Word', 'F1', CmdHelpWord);
  AddMenuItem(M, '-', '', nil);
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
  ApplyEditorTheme(Doc.Editor);
  Doc.Editor.FontSize := FPrefs.EditorFontSize;
  Doc.Editor.LineCommentPrefix := '#';
  Doc.Editor.HighlightCurrentLine := True;
  Doc.Editor.SetText(Text);
  Doc.Editor.OnChange := EditorChange;
  Doc.Editor.OnCaretChange := EditorCaretChange;
  Doc.Editor.OnRequestGotoLine := EditorGotoLine;
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
    StartCheck(Result);
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
  if FCheckDoc = Doc then
    FCheckDoc := nil;
  FDocs.Extract(Doc);
  FreeEditorTab(Doc.Tab);
  Doc.Free;
  if FDocs.Count = 0 then
    ShowWelcome;
  UpdateTitle;
end;

procedure TfrmMain.UpdateTabCaption(Doc: TDocument);
begin
  if Doc.Editor.Modified then
    SetTabTitle(Doc.Tab, Doc.DisplayName + ' *')
  else
    SetTabTitle(Doc.Tab, Doc.DisplayName);
end;

const
  // The close mark at the end of every editor-area tab's title, and how much
  // of the tab's right end a click closes it in (points).
  TabCloseMark = '   ' + #$00D7;
  TabCloseZone = 20;

{ An editor-area tab shows its title followed by a close mark (x): a click on
  the right end of the tab, or a middle-click anywhere on it, closes it. The
  mark is part of the text, so it takes the theme's text colour. }
procedure TfrmMain.SetTabTitle(Tab: TTabItem; const Title: string);
begin
  Tab.Text := Title + TabCloseMark;
  Tab.OnMouseUp := TabMouseUp;
end;

procedure TfrmMain.TabMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Single);
var
  Tab: TTabItem;
begin
  Tab := Sender as TTabItem;
  if (Button = TMouseButton.mbMiddle) or
    ((Button = TMouseButton.mbLeft) and (X >= Tab.Width - TabCloseZone)) then
    // After this event returns: the tab is freed when it closes.
    TThread.ForceQueue(nil,
      procedure
      begin
        if not GClosing then
          CloseTab(Tab);
      end);
end;

{ Frees an editor-area tab. When it is the active one, its neighbour (the
  tab to the left, else the one to the right) is activated first: freeing the
  active tab moves TTabControl's index without showing that tab's content. }
procedure TfrmMain.FreeEditorTab(Tab: TTabItem);
var
  K: Integer;
begin
  if Tab = nil then
    Exit;
  if (FTabs.ActiveTab = Tab) and (FTabs.TabCount > 1) then
  begin
    K := Tab.Index;
    if K > 0 then
      FTabs.ActiveTab := FTabs.Tabs[K - 1]
    else
      FTabs.ActiveTab := FTabs.Tabs[K + 1];
  end;
  Tab.Free;
end;

{ Closes an editor-area tab: a file (asking to save it), the Documentation
  tab, or the Welcome tab. }
procedure TfrmMain.CloseTab(Tab: TTabItem);
var
  Doc: TDocument;
begin
  if Tab = nil then
    Exit;
  if Tab = FDocsTab then
  begin
    FDocsViewer := nil;
    FreeEditorTab(FDocsTab);
    FDocsTab := nil;
    if FDocs.Count = 0 then
      ShowWelcome;
    UpdateTitle;
  end
  else if Tab = FWelcomeTab then
  begin
    CloseWelcome;
    if FDocs.Count = 0 then
      NewDocument('', '');
  end
  else
    for Doc in FDocs do
      if Doc.Tab = Tab then
      begin
        CloseDoc(Doc);
        Exit;
      end;
end;

procedure TfrmMain.UpdateTitle;
var
  Doc: TDocument;
begin
  Doc := CurrentDoc;
  if (Doc = nil) and (FWelcomeTab <> nil) and (FTabs.ActiveTab = FWelcomeTab) then
    Caption := 'Welcome - Axon'
  else if (Doc = nil) and (FDocsTab <> nil) and (FTabs.ActiveTab = FDocsTab) then
    Caption := 'Documentation - Axon'
  else if Doc = nil then
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
  // Restart the pause timer: the check runs once typing stops.
  FCheckTimer.Enabled := False;
  FCheckTimer.Enabled := True;
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
    LoadLayout(Ini);
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
      SaveLayout(Ini);
      Ini.UpdateFile;
    finally
      Ini.Free;
    end;
  except
    // Settings are a convenience; failing to save them is not an error.
  end;
end;

procedure TfrmMain.SetBoundsF(const ALeft, ATop, AWidth, AHeight: Single);
begin
  inherited;
  if not (csDestroying in ComponentState) then
    RecordNormalBounds;
end;

{ Keeps the bounds of the normal (not maximized) window, which is what a
  maximized window returns to and what is saved. The change of bounds that
  maximizes a window arrives before WindowState changes, so the state is
  read once the change has been handled. }
procedure TfrmMain.RecordNormalBounds;
begin
  TThread.ForceQueue(nil,
    procedure
    var
      Full: Boolean;
    begin
      if GClosing then
        Exit;
      Full := IsFullScreen;
      if (WindowState = TWindowState.wsNormal) and not Full then
        FNormalBounds := TRect.Create(Left, Top, Left + Width, Top + Height);
      // macOS full screen is tracked as it changes (entering or leaving it
      // resizes the window) and saved at once: by the time the application
      // quits, the window may already have left full screen.
      if Full <> FWasFullScreen then
      begin
        FWasFullScreen := Full;
        if not (csDestroying in ComponentState) and not FSettingsSaved then
          SaveSettings;
      end;
    end);
end;

{ macOS full screen (the green button), which FMX reports through FullScreen
  rather than WindowState. Windows maximizes instead, so this is False there.
  Safe while the window is being destroyed. }
function TfrmMain.IsFullScreen: Boolean;
begin
  Result := False;
{$IFDEF MACOS}
  try
    Result := (Handle <> nil) and FullScreen;
  except
    Result := False;
  end;
{$ENDIF}
end;

procedure TfrmMain.LoadLayout(Ini: TCustomIniFile);
var
  R: TRect;
  K, W, H: Integer;
  Visible: Boolean;
  Area: TRectF;
begin
  if not Ini.SectionExists('Window') then
  begin
    FPrefs.EditorFontSize := EnsureRange(Ini.ReadInteger('Preferences', 'EditorFontSize',
      Round(FPrefs.EditorFontSize)), MinFontSize, MaxFontSize);
    FPrefs.OutputFontSize := EnsureRange(Ini.ReadInteger('Preferences', 'OutputFontSize',
      Round(FPrefs.OutputFontSize)), MinFontSize, MaxFontSize);
    FPrefs.DocsFontSize := EnsureRange(Ini.ReadInteger('Preferences', 'DocsFontSize',
      Round(FPrefs.DocsFontSize)), MinFontSize, MaxFontSize);
    FPrefs.ShowRunNotes := Ini.ReadBool('Preferences', 'ShowRunNotes', True);
    FPrefs.ShowJitReport := Ini.ReadBool('Preferences', 'ShowJitReport', True);
    ApplyPreferences;
    ApplyJit(Ini.ReadBool('Preferences', 'Jit', True));
    Exit;
  end;
  W := Ini.ReadInteger('Window', 'Width', Width);
  H := Ini.ReadInteger('Window', 'Height', Height);
  R := TRect.Create(Ini.ReadInteger('Window', 'Left', Left), Ini.ReadInteger('Window', 'Top', Top),
    0, 0);
  R.Right := R.Left + Max(W, 500);
  R.Bottom := R.Top + Max(H, 360);
  // Restore the position only if the title bar is on a display now (a
  // monitor may have been disconnected); otherwise keep the window centred.
  Visible := False;
  for K := 0 to Screen.DisplayCount - 1 do
  begin
    Area := Screen.Displays[K].Workarea;
    if (R.Top >= Area.Top) and (R.Top < Area.Bottom - 20) and
      (R.Left < Area.Right - 50) and (R.Right > Area.Left + 50) then
      Visible := True;
  end;
  if Visible then
  begin
    Position := TFormPosition.Designed;
    SetBounds(R.Left, R.Top, R.Width, R.Height);
  end
  else
    SetBounds(Left, Top, R.Width, R.Height);
  FNormalBounds := TRect.Create(Left, Top, Left + Width, Top + Height);
{$IFDEF MACOS}
  // Maximized (zoomed, the green button) once the window is active, as for
  // full screen below: set while the form is created, it does not survive
  // the window being shown.
  FPendingMaximize := Ini.ReadBool('Window', 'Maximized', False);
{$ELSE}
  if Ini.ReadBool('Window', 'Maximized', False) then
    WindowState := TWindowState.wsMaximized;
{$ENDIF}
{$IFDEF MACOS}
  // Full screen after the window first becomes active (FormActivate): macOS
  // ignores a full-screen request for a window that is not on screen yet.
  FPendingFullScreen := Ini.ReadBool('Window', 'FullScreen', False);
{$ENDIF}

  // Pane sizes, kept within what the window can hold.
  FPlotPane.Width := EnsureRange(Ini.ReadInteger('Window', 'PlotWidth', Round(FPlotPane.Width)),
    150, Max(150, Width - 300));
  FBottomTabs.Height := EnsureRange(Ini.ReadInteger('Window', 'BottomHeight',
    Round(FBottomTabs.Height)), 80, Max(80, Height - 220));
  ApplyTheme(Ini.ReadString('Window', 'Theme', 'light') = 'dark');
  FPrefs.EditorFontSize := EnsureRange(Ini.ReadInteger('Preferences', 'EditorFontSize',
    Round(FPrefs.EditorFontSize)), MinFontSize, MaxFontSize);
  FPrefs.OutputFontSize := EnsureRange(Ini.ReadInteger('Preferences', 'OutputFontSize',
    Round(FPrefs.OutputFontSize)), MinFontSize, MaxFontSize);
  FPrefs.DocsFontSize := EnsureRange(Ini.ReadInteger('Preferences', 'DocsFontSize',
    Round(FPrefs.DocsFontSize)), MinFontSize, MaxFontSize);
  FPrefs.ShowRunNotes := Ini.ReadBool('Preferences', 'ShowRunNotes', True);
  FPrefs.ShowJitReport := Ini.ReadBool('Preferences', 'ShowJitReport', True);
  ApplyPreferences;
  ApplyJit(Ini.ReadBool('Preferences', 'Jit', True));
  K := Ini.ReadInteger('Window', 'BottomTab', 0);
  if (K >= 0) and (K < FBottomTabs.TabCount) then
    FBottomTabs.TabIndex := K;
end;

procedure TfrmMain.SaveLayout(Ini: TCustomIniFile);
begin
  // A window that is not maximized or full screen saves where it is now:
  // moving a window may not go through SetBoundsF on every platform. A full
  // screen window keeps the normal bounds it returns to.
  if (WindowState = TWindowState.wsNormal) and not IsFullScreen and not FWasFullScreen then
    FNormalBounds := TRect.Create(Left, Top, Left + Width, Top + Height);
  Ini.WriteInteger('Window', 'Left', FNormalBounds.Left);
  Ini.WriteInteger('Window', 'Top', FNormalBounds.Top);
  Ini.WriteInteger('Window', 'Width', FNormalBounds.Width);
  Ini.WriteInteger('Window', 'Height', FNormalBounds.Height);
  Ini.WriteBool('Window', 'Maximized', WindowState = TWindowState.wsMaximized);
{$IFDEF MACOS}
  Ini.WriteBool('Window', 'FullScreen', FWasFullScreen or IsFullScreen);
{$ENDIF}
  Ini.WriteInteger('Window', 'PlotWidth', Round(FPlotPane.Width));
  Ini.WriteInteger('Window', 'BottomHeight', Round(FBottomTabs.Height));
  Ini.WriteInteger('Window', 'BottomTab', FBottomTabs.TabIndex);
  if FDark then
    Ini.WriteString('Window', 'Theme', 'dark')
  else
    Ini.WriteString('Window', 'Theme', 'light');
  Ini.WriteInteger('Preferences', 'EditorFontSize', Round(FPrefs.EditorFontSize));
  Ini.WriteInteger('Preferences', 'OutputFontSize', Round(FPrefs.OutputFontSize));
  Ini.WriteInteger('Preferences', 'DocsFontSize', Round(FPrefs.DocsFontSize));
  Ini.WriteBool('Preferences', 'ShowRunNotes', FPrefs.ShowRunNotes);
  Ini.WriteBool('Preferences', 'ShowJitReport', FPrefs.ShowJitReport);
  Ini.WriteBool('Preferences', 'Jit', FJit);
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
  RefreshWelcome;
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
      ExtractFilePath(ParamStr(0)) + ').', FPal.Error);
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
  FFigureShown := False;
  FAnimActive := False;
  FBottomTabs.ActiveTab := FOutputTab;
  FJitCompiled.Clear;
  FJitRejected.Clear;
  FJitWhere.Clear;
  if FPrefs.ShowRunNotes then
    if FJit then
      AddNote(Format('Running %s (JIT on)', [Doc.FilePath]), FPal.Note)
    else
      AddNote(Format('Running %s (JIT off: interpreted)', [Doc.FilePath]), FPal.Note);
  try
    FRunner.Start(Exe, [ExtractFileName(Doc.FilePath)], FRunDir, False, True);
  except
    on E: Exception do
    begin
      AddNote('Cannot start axon: ' + E.Message, FPal.Error);
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
  ReportJit;
  if FRunner.Killed then
  begin
    AddNote(Format('Stopped after %.2f s', [Secs]), FPal.Error);
    FStatus.Text := 'Stopped';
  end
  else if ExitCode = 0 then
  begin
    if FPrefs.ShowRunNotes then
      AddNote(Format('Finished in %.2f s', [Secs]), FPal.Note);
    FStatus.Text := 'Finished';
  end
  else
  begin
    AddNote(Format('Exited with code %d after %.2f s', [ExitCode, Secs]), FPal.Error);
    if FErrorKind <> '' then
      FStatus.Text := FErrorKind + ': ' + FErrorMessage
    else
      FStatus.Text := Format('Exited with code %d', [ExitCode]);
    MarkError;
  end;
  ScrollToEnd(FOutput);
  // A figure shown with plot.show() takes precedence over saved files.
  if not FFigureShown then
    ShowNewestPlotIn(FRunDir, FRunStart);
end;

procedure TfrmMain.AddOutputLine(Kind: TOutputKind; const Line: string);
var
  Item: TListBoxItem;
  Frame: TFrame;
  Head, Msg: string;
begin
  if (Kind = okStdErr) and (TryShowFrame(Line) or TryShowFigure(Line) or TryJitReport(Line)) then
    Exit;
  while FOutput.Count >= MaxOutputLines do
    FOutput.ListItems[0].Free;
  Item := TListBoxItem.Create(FOutput);
  Item.Parent := FOutput;
  Item.Text := Line;
  Item.StyledSettings := Item.StyledSettings - [TStyledSetting.FontColor, TStyledSetting.Family];
  Item.TextSettings.Font.Family := {$IFDEF MSWINDOWS}'Consolas'{$ELSE}'Menlo'{$ENDIF};
  SizePaneItem(Item);
  Item.TextSettings.FontColor := FPal.Text;
  if Kind = okStdErr then
  begin
    Item.TextSettings.FontColor := FPal.Error;
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
      Item.TextSettings.FontColor := FPal.Link;
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
  SizePaneItem(Item);
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
    GoToFrame(FFrames[Item.Tag - 1])
  // A JIT note: minus one more than its index into FJitWhere.
  else if (Item <> nil) and (Item.Tag < 0) and (-Item.Tag <= FJitWhere.Count) then
    GoToFrame(FJitWhere[-Item.Tag - 1]);
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
  if Newest <> '' then
    AddFigure(Newest);
end;

const
  MaxFigures = 50;    // the history keeps the newest ones

{ Adds a figure (a PNG, with its data next to it as .json when plot.show
  wrote it) to the history and shows it. }
procedure TfrmMain.AddFigure(const Path: string);
var
  E: TFigureEntry;
begin
  E := TFigureEntry.Create;
  E.Path := Path;
  AddEntry(E);
end;

{ Adds an entry to the history (which keeps the newest MaxFigures) and
  shows it. }
procedure TfrmMain.AddEntry(Entry: TFigureEntry);
begin
  FAnimActive := False;        // a new figure ends any animation's entry
  FShownScene := nil;          // its entry may be about to go
  FFigures.Add(Entry);
  while FFigures.Count > MaxFigures do
    FFigures.Delete(0);
  DisplayFigure(FFigures.Count - 1);
end;

{ Makes View the one visible control of the plot pane (nil: none). }
procedure TfrmMain.ShowOnly(View: TControl);
begin
  FPlotImage.Visible := View = FPlotImage;
  FPlotChart.Visible := View = FPlotChart;
  FPlot3D.Visible := View = FPlot3D;
  FPlotScene.Visible := View = FPlotScene;
end;

{ Draws the shown scene, as large as fits, centred. }
procedure TfrmMain.PlotSceneDraw(ASender: TObject; const ACanvas: ISkCanvas;
  const ADest: TRectF; const AOpacity: Single);
var
  Sc: TScene;
  F: Double;
begin
  Sc := FShownScene;
  if (Sc = nil) or (Sc.Width <= 0) or (Sc.Height <= 0) then
    Exit;
  F := Min(ADest.Width / Sc.Width, ADest.Height / Sc.Height);
  if F <= 0 then
    Exit;
  ACanvas.Save;
  try
    ACanvas.Translate(ADest.Left + (ADest.Width - Sc.Width * F) / 2,
      ADest.Top + (ADest.Height - Sc.Height * F) / 2);
    ACanvas.Scale(F, F);
    try
      DrawScene(ACanvas.Handle, Sc);
    except
      // A scene that cannot be drawn (an image too large) leaves the pane blank.
    end;
  finally
    ACanvas.Restore;
  end;
end;

{ A message on the display channel: a scene to show, a frame, or a plot
  figure (its scene and its record as JSON). A message that cannot be read
  is reported in the pane's caption and otherwise ignored. }
procedure TfrmMain.DisplayMessage(Kind: Byte; const Payload: TBytes);
var
  E: TFigureEntry;
  N: Cardinal;
begin
  FFigureShown := True;
  if (Kind = Axon.Scene.DisplayFrame) or (Kind = Axon.Scene.DisplayAdd) then
  begin
    if Kind = Axon.Scene.DisplayFrame then
    begin
      // Only the newest full frame is decoded and drawn; see TryShowFrame.
      FAnimBytes := Payload;
      FAnimPending := '';
    end
    else
      AddToFrame(Payload);
    if not FAnimQueued then
    begin
      FAnimQueued := True;
      TThread.ForceQueue(nil, ShowPendingFrame);
    end;
    Exit;
  end;
  E := TFigureEntry.Create;
  try
    if Kind = Axon.Scene.DisplayShow then
      E.Scene := DecodeScene(Payload)
    else if (Kind = Axon.Scene.DisplayFigure) and (Length(Payload) >= 4) then
    begin
      Move(Payload[0], N, 4);
      if Int64(N) + 4 > Length(Payload) then
        raise EScene.Create('figure message cut short');
      E.Scene := DecodeScene(Copy(Payload, 4, N));
      E.Json := TEncoding.UTF8.GetString(Payload, 4 + N, Length(Payload) - 4 - Integer(N));
    end
    else
      raise EScene.CreateFmt('unknown display message %d', [Kind]);
  except
    on Ex: Exception do
    begin
      E.Free;
      FPlotCaption.Text := 'Cannot show a figure: ' + Ex.Message;
      Exit;
    end;
  end;
  AddEntry(E);
end;

{ Shows figure Index of the history. A figure with its data goes to the
  interactive 3-D or 2-D chart (reloaded, so edits made in the chart are not
  kept when moving away); any other is shown as the image. }
procedure TfrmMain.DisplayFigure(Index: Integer);
var
  E: TFigureEntry;
  Path, Json, What: string;
  HasJson: Boolean;
begin
  FFigureIndex := Index;
  UpdateFigureBar;
  if (Index < 0) or (Index >= FFigures.Count) then
    Exit;
  E := FFigures[Index];
  FreeAndNil(FPlotGrid);
  FShownScene := nil;
  // The figure record: from the message, or a .json file beside the PNG.
  Path := E.Path;
  Json := '';
  HasJson := E.Json <> '';
  if (not HasJson) and (Path <> '') then
  begin
    Json := TPath.ChangeExtension(Path, '.json');
    HasJson := TFile.Exists(Json);
  end;
  if HasJson then
  begin
    if E.Json <> '' then
      FPlotGrid := LoadFigureGridText(Self, FPlotPane, E.Json)
    else
      FPlotGrid := LoadFigureGrid(Self, FPlotPane, Json);
  end;
  if FPlotGrid <> nil then
  begin
    ShowOnly(nil);
    What := 'subplots: wheel zooms, drag pans (rotates in 3D), double-click edits';
  end
  else if HasJson and ((E.Json <> '') and LoadFigure3DText(FPlot3D, E.Json) or
    (E.Json = '') and LoadFigure3D(FPlot3D, Json)) then
  begin
    ShowOnly(FPlot3D);
    What := 'drag rotates, wheel zooms, double-click edits';
  end
  else if HasJson and ((E.Json <> '') and LoadFigureText(FPlotChart, E.Json) or
    (E.Json = '') and LoadFigure(FPlotChart, Json)) then
  begin
    ShowOnly(FPlotChart);
    What := 'wheel zooms, drag pans, double-click edits';
  end
  else if E.Scene <> nil then
  begin
    FShownScene := E.Scene;
    ShowOnly(FPlotScene);
    FPlotScene.Redraw;
    if FAnimActive and (Index = FFigures.Count - 1) then
      What := 'animation'
    else
      What := 'drawing';
  end
  else
    try
      FPlotImage.Bitmap.LoadFromFile(Path);
      ShowOnly(FPlotImage);
      if SameFileName(ExtractFileDir(Path), FShowDir) then
        What := 'plot.show'
      else
        What := ExtractFileName(Path);
    except
      FPlotCaption.Text := 'Cannot show ' + ExtractFileName(Path);
      Exit;
    end;
  FPlotCaption.Text := Format('Figure %d: %s', [Index + 1, What]);
end;

procedure TfrmMain.UpdateFigureBar;
begin
  if FFigures.Count = 0 then
    FFigurePos.Text := ''
  else
    FFigurePos.Text := Format('%d / %d', [FFigureIndex + 1, FFigures.Count]);
  FFigurePrev.Enabled := FFigureIndex > 0;
  FFigureNext.Enabled := FFigureIndex < FFigures.Count - 1;
  FFigureClear.Enabled := FFigures.Count > 0;
  FFigureSave.Enabled := (FFigureIndex >= 0) and (FFigureIndex < FFigures.Count);
  FFigureCopy.Enabled := FFigureSave.Enabled;
end;

{ The control showing the current figure: a chart or a grid of charts, or
  nil for a figure shown as an image. }
function TfrmMain.FigureView: TControl;
begin
  Result := nil;
  if FPlotGrid <> nil then
    Result := FPlotGrid
  else if FPlotChart.Visible then
    Result := FPlotChart
  else if FPlot3D.Visible then
    Result := FPlot3D;
  if not CanExportView(Result) then
    Result := nil;
end;

{ The scene drawn at Scale pixels per point, as a bitmap. }
function SceneBitmap(Scene: TScene; Scale: Single): FMX.Graphics.TBitmap;
var
  Surface: ISkSurface;
begin
  Surface := TSkSurface.MakeRaster(Max(1, Round(Scene.Width * Scale)),
    Max(1, Round(Scene.Height * Scale)));
  if Surface = nil then
    raise Exception.Create('cannot draw the figure');
  Surface.Canvas.Clear(TAlphaColors.Null);
  Surface.Canvas.Scale(Scale, Scale);
  DrawScene(Surface.Canvas.Handle, Scene);
  Result := SkImageToBitmap(Surface.MakeImageSnapshot);
end;

{ The figure as it is on screen, with any zooming, panning, rotating and
  editing done in its charts (every cell of a grid), drawn at 2 pixels per
  point; a scene drawn at 2 pixels per point; for a figure shown as an
  image, that image. The caller frees it. }
function TfrmMain.FigureViewBitmap: FMX.Graphics.TBitmap;
begin
  if FigureView <> nil then
    Exit(ViewBitmap(FigureView, 2));
  if FShownScene <> nil then
    Exit(SceneBitmap(FShownScene, 2));
  Result := FMX.Graphics.TBitmap.Create;
  try
    Result.LoadFromFile(FFigures[FFigureIndex].Path);
  except
    Result.Free;
    raise;
  end;
end;

{ Copy: the figure on screen, all of it (every cell of a grid), as it looks
  now. }
procedure TfrmMain.FigureCopyClick(Sender: TObject);
var
  Bmp: FMX.Graphics.TBitmap;
  Svc: IFMXClipboardService;
begin
  if (FFigureIndex < 0) or (FFigureIndex >= FFigures.Count) then
    Exit;
  if not TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService, Svc) then
    Exit;
  Bmp := nil;
  try
    try
      Bmp := FigureViewBitmap;
      Svc.SetClipboard(Bmp);
      FPlotCaption.Text := 'Copied figure ' + IntToStr(FFigureIndex + 1);
    except
      on E: Exception do
        FPlotCaption.Text := 'Cannot copy: ' + E.Message;
    end;
  finally
    Bmp.Free;
  end;
end;

{ A scene to a PNG (2 pixels per point), PDF or SVG file, by its extension. }
procedure SaveSceneFile(Scene: TScene; const Target, Ext: string);
var
  Stream: TFileStream;
begin
  if (Ext = '.pdf') or (Ext = '.svg') then
  begin
    Stream := TFileStream.Create(Target, fmCreate);
    try
      if Ext = '.pdf' then
        SavePdf(Scene, Stream)
      else
        SaveSvg(Scene, Stream);
    finally
      Stream.Free;
    end;
  end
  else
    SavePng(Scene, 2, Target);
end;

{ Save...: the figure on screen, all of it (every cell of a grid), as it looks
  now, to a PNG (2 pixels per point), PDF or SVG (vectors) the user picks;
  see uFigureExport. A scene is saved the same ways; a figure shown as an
  image is saved as that PNG. }
procedure TfrmMain.FigureSaveClick(Sender: TObject);
var
  Dlg: TSaveDialog;
  Target, Ext: string;
  View: TControl;
begin
  if (FFigureIndex < 0) or (FFigureIndex >= FFigures.Count) then
    Exit;
  View := FigureView;
  Dlg := TSaveDialog.Create(nil);
  try
    if (View <> nil) or (FShownScene <> nil) then
      Dlg.Filter := 'PNG image (*.png)|*.png|PDF document (*.pdf)|*.pdf|SVG image (*.svg)|*.svg'
    else
      Dlg.Filter := 'PNG image (*.png)|*.png';
    Dlg.DefaultExt := 'png';
    Dlg.FileName := 'figure';
    if FRunDir <> '' then
      Dlg.InitialDir := FRunDir;
    if not Dlg.Execute then
      Exit;
    Target := Dlg.FileName;
    Ext := LowerCase(ExtractFileExt(Target));
    if Ext = '' then
    begin
      case Dlg.FilterIndex of
        2: Ext := '.pdf';
        3: Ext := '.svg';
      else
        Ext := '.png';
      end;
      Target := Target + Ext;
    end;
  finally
    Dlg.Free;
  end;
  if ((View = nil) and (FShownScene = nil)) or ((Ext <> '.pdf') and (Ext <> '.svg')) then
    Target := TPath.ChangeExtension(Target, '.png');
  try
    if (View = nil) and (FShownScene <> nil) then
      SaveSceneFile(FShownScene, Target, Ext)
    else if View = nil then
      TFile.Copy(FFigures[FFigureIndex].Path, Target, True)
    else if Ext = '.pdf' then
      SaveViewPdf(View, Target)
    else if Ext = '.svg' then
      SaveViewSvg(View, Target)
    else
      SaveViewPng(View, Target, 2);
    FPlotCaption.Text := 'Saved ' + ExtractFileName(Target);
  except
    on E: Exception do
      FPlotCaption.Text := 'Cannot save: ' + E.Message;
  end;
end;

procedure TfrmMain.FigurePrevClick(Sender: TObject);
begin
  if FFigureIndex > 0 then
    DisplayFigure(FFigureIndex - 1);
end;

procedure TfrmMain.FigureNextClick(Sender: TObject);
begin
  if FFigureIndex < FFigures.Count - 1 then
    DisplayFigure(FFigureIndex + 1);
end;

procedure TfrmMain.FigureClearClick(Sender: TObject);
begin
  FreeAndNil(FPlotGrid);
  FShownScene := nil;
  FFigures.Clear;
  FAnimActive := False;
  FFigureIndex := -1;
  UpdateFigureBar;
  FPlotChart.Visible := False;
  FPlot3D.Visible := False;
  FPlotScene.Visible := False;
  FPlotImage.Bitmap.SetSize(0, 0);
  FPlotImage.Visible := True;
  FPlotCaption.Text := 'Figures from plot.show, and PNGs a run saves, appear here.';
end;

{ Scrolls a list to its last item once FMX has laid out new items (scrolling
  straight away, or inside BeginUpdate, stops short). }
procedure TfrmMain.ScrollToEnd(List: TListBox);
begin
  TThread.ForceQueue(nil,
    procedure
    begin
      if GClosing then
        Exit;
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
  MakeCopyable(FReplList);
end;

{ The Output and REPL panes are lists of lines: a click selects one, Shift-
  and Ctrl-click select more, and Ctrl+C (Cmd+C) or the right-click menu
  copies them; with nothing selected, Copy takes every line. }
procedure TfrmMain.MakeCopyable(List: TListBox);
var
  Menu: TPopupMenu;
  Item: TMenuItem;
begin
  List.MultiSelectStyle := TMultiSelectStyle.Extended;
  List.OnKeyDown := PaneKeyDown;
  Menu := TPopupMenu.Create(Self);
  Menu.Parent := Self;
  Item := TMenuItem.Create(Self);
  Item.Text := 'Copy';
  Item.TagObject := List;
  Item.OnClick := PaneCopyClick;
  Menu.AddObject(Item);
  Item := TMenuItem.Create(Self);
  Item.Text := 'Copy All';
  Item.TagObject := List;
  Item.OnClick := PaneCopyAllClick;
  Menu.AddObject(Item);
  List.PopupMenu := Menu;
end;

procedure TfrmMain.CopyPaneLines(List: TListBox; All: Boolean);
var
  Lines: TStringList;
  K: Integer;
  Any: Boolean;
  Svc: IFMXClipboardService;
begin
  Any := False;
  if not All then
    for K := 0 to List.Count - 1 do
      if List.ListItems[K].IsSelected then
        Any := True;
  Lines := TStringList.Create;
  try
    for K := 0 to List.Count - 1 do
      if not Any or List.ListItems[K].IsSelected then
        Lines.Add(List.ListItems[K].Text);
    if TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService, Svc) then
      Svc.SetClipboard(Lines.Text.TrimRight);
  finally
    Lines.Free;
  end;
end;

procedure TfrmMain.PaneKeyDown(Sender: TObject; var Key: Word; var KeyChar: WideChar;
  Shift: TShiftState);
begin
  if ((Key = vkC) or (KeyChar = 'c') or (KeyChar = 'C')) and
    ((ssCtrl in Shift) or (ssCommand in Shift)) then
  begin
    CopyPaneLines(Sender as TListBox, False);
    Key := 0;
    KeyChar := #0;
  end;
end;

procedure TfrmMain.PaneCopyClick(Sender: TObject);
begin
  CopyPaneLines((Sender as TMenuItem).TagObject as TListBox, False);
end;

procedure TfrmMain.PaneCopyAllClick(Sender: TObject);
begin
  CopyPaneLines((Sender as TMenuItem).TagObject as TListBox, True);
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
    ReplAddLine('Cannot find the axon interpreter next to the IDE.', FPal.Error, True);
    Exit;
  end;
  FReplDir := ReplWorkDir;
  FReplPartial[okStdOut] := '';
  FReplPartial[okStdErr] := '';
  try
    FRepl.Start(Exe, ['--repl-protocol'], FReplDir, True, True);
  except
    on E: Exception do
    begin
      ReplAddLine('Cannot start the REPL: ' + E.Message, FPal.Error, True);
      Exit;
    end;
  end;
  FReplDirLabel.Text := 'Session in ' + FReplDir;
  ReplAddLine('New session in ' + FReplDir, FPal.Note, True);
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
  SizePaneItem(Item);
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
  S := FReplPartial[Kind] + Text.Replace(#13#10, #10).Replace(#13, #10);
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
          if not FFigureShown then
            ShowNewestPlotIn(FReplDir, FReplSince);
        end;
      end
      else if L.StartsWith(#2) then
        ReplAddLine(L.Substring(1), FPal.Error)
      else if TryShowFrame(L) or TryShowFigure(L) then
        // shown in the plot pane
      else if L.StartsWith(#3'jit ') then
        // a JIT report line: not shown in the REPL
      else if Kind = okStdErr then
        ReplAddLine(L, FPal.Error)
      else
        ReplAddLine(L, FPal.Text);
    end;
  finally
    FReplList.EndUpdate;
  end;
  ScrollToEnd(FReplList);
  FReplPartial[Kind] := S;
end;

procedure TfrmMain.ReplExit(ExitCode: Integer);
begin
  if FReplRestart then
  begin
    FReplRestart := False;
    ReplAddLine('Session ended.', FPal.Note, True);
    EnsureRepl;
    Exit;
  end;
  if FRepl.Killed then
    ReplAddLine('Session stopped.', FPal.Note, True)
  else
    ReplAddLine(Format('Session ended (exit code %d). Enter a line to start a new one.',
      [ExitCode]), FPal.Note, True);
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
  FFigureShown := False;
  FAnimActive := False;
  Shown := FReplPrompt.Text;
  for L in Lines do
  begin
    // The echo uses the prompt the REPL last showed; later lines continue it.
    ReplAddLine(Shown + ' ' + L, FPal.Link);
    if Shown = '>' then
      Shown := '...';
    if not FRepl.WriteInput(L + #10) then
    begin
      ReplAddLine('The REPL is not accepting input.', FPal.Error, True);
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

{ Runs the whole file in the REPL session with its run command, so the
  variables it creates can be inspected there afterwards. The file is saved
  first, as for Run. }
procedure TfrmMain.CmdRunInRepl(Sender: TObject);
var
  Doc: TDocument;
begin
  Doc := CurrentDoc;
  if Doc = nil then
    Exit;
  if (Doc.FilePath = '') or Doc.Editor.Modified then
    if not SaveDoc(Doc, False) then
      Exit;
  for var D in FDocs do
    D.Editor.ClearMarkers;
  ReplSend(['run "' + Doc.FilePath + '"']);
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

{ ---------------- help on the word under the caret ---------------- }

function IsNameChar(C: Char): Boolean;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

{ The (possibly dotted) name at the caret, as in linalg.solve; '' if none. }
function TfrmMain.WordAtCaret(Doc: TDocument): string;
var
  Line: string;
  Col, A, B: Integer;
begin
  Result := '';
  Line := Doc.Editor.LineText(Doc.Editor.CaretLine);
  Col := Doc.Editor.CaretColumn;            // 1-based; the caret is before Line[Col]
  if (Col > Length(Line)) or ((Col >= 1) and not IsNameChar(Line[Col])) then
    Dec(Col);                               // just after a word
  if (Col < 1) or (Col > Length(Line)) or not IsNameChar(Line[Col]) then
    Exit;
  A := Col;
  while (A > 1) and (IsNameChar(Line[A - 1]) or
    ((Line[A - 1] = '.') and (A > 2) and IsNameChar(Line[A - 2]))) do
    Dec(A);
  B := Col;
  while (B < Length(Line)) and IsNameChar(Line[B + 1]) do
    Inc(B);
  Result := Copy(Line, A, B - A + 1);
  if CharInSet(Result[1], ['0'..'9']) then
    Result := '';
end;

{ Help for a function or record defined in the document itself, read from
  the text: the header as written and the ## lines directly above it. }
function TfrmMain.LocalHelp(Doc: TDocument; const Name: string; out Text: string): Boolean;
var
  K, J, Depth, N: Integer;
  L, T, Header: string;
  Docs, Fields: TStringList;
  IsRecord: Boolean;
  C: Char;
begin
  Result := False;
  if Name.Contains('.') then
    Exit;
  N := Doc.Editor.LineCount;
  for K := 1 to N do
  begin
    T := Doc.Editor.LineText(K).Trim;
    if T.StartsWith('export ') then
      T := Copy(T, 8, MaxInt).TrimLeft;
    IsRecord := T.StartsWith('record ') and (Copy(T, 8, MaxInt).Trim = Name);
    if not (IsRecord or T.StartsWith('function ' + Name + '(') or
      T.StartsWith('function ' + Name + ' (')) then
      Continue;
    Docs := TStringList.Create;
    Fields := TStringList.Create;
    try
      // The ## lines directly above.
      J := K - 1;
      while (J >= 1) and Doc.Editor.LineText(J).TrimLeft.StartsWith('##') do
      begin
        L := Doc.Editor.LineText(J).TrimLeft.Substring(2);
        if L.StartsWith(' ') then
          L := L.Substring(1);
        Docs.Insert(0, L);
        Dec(J);
      end;
      if IsRecord then
      begin
        // record Name(field: type, ...), from the field lines up to "end".
        J := K + 1;
        while (J <= N) and (Doc.Editor.LineText(J).Trim <> 'end') do
        begin
          L := Doc.Editor.LineText(J).Trim;
          if (L <> '') and not L.StartsWith('#') then
            Fields.Add(L);
          Inc(J);
        end;
        Header := 'record ' + Name + '(' + string.Join(', ', Fields.ToStringArray) + ')';
      end
      else
      begin
        // The header through the closing parenthesis, joining lines.
        Header := Copy(T, Length('function ') + 1, MaxInt);
        J := K;
        Depth := 0;
        for C in Header do
          if C = '(' then Inc(Depth) else if C = ')' then Dec(Depth);
        while (Depth > 0) and (J < N) do
        begin
          Inc(J);
          L := Doc.Editor.LineText(J).Trim;
          Header := Header + ' ' + L;
          for C in L do
            if C = '(' then Inc(Depth) else if C = ')' then Dec(Depth);
        end;
        // Drop a comment after the header.
        J := Header.IndexOf(' #');
        if J > 0 then
          Header := Header.Substring(0, J).TrimRight;
      end;
      Text := Header;
      if Docs.Count = 0 then
        Text := Text + sLineBreak + '  (no documentation)'
      else
        for L in Docs do
          Text := Text + sLineBreak + '  ' + L;
      Result := True;
      Exit;
    finally
      Docs.Free;
      Fields.Free;
    end;
  end;
end;

{ Markdown for plain text: punctuation that markdown would read is escaped. }
function MdEscape(const S: string): string;
var
  C: Char;
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    for C in S do
    begin
      if CharInSet(C, ['\', '`', '*', '_', '[', ']', '<', '>', '#', '|']) then
        SB.Append('\');
      SB.Append(C);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

{ The text of "help name" as markdown: unindented lines (headers such as
  "solve(f, y0, ...)" or "module ode") and lines indented by four spaces or
  more (examples, as in a keyword's help; four removed) become an axon code
  block, lines indented less (the description) a paragraph. }
function HelpMarkdown(const Text: string): string;
var
  Lines: TStringList;
  L: string;
  InCode: Boolean;
  SB: TStringBuilder;
begin
  Lines := TStringList.Create;
  SB := TStringBuilder.Create;
  try
    Lines.Text := Text;
    InCode := False;
    for L in Lines do
    begin
      if (L <> '') and (not L.StartsWith(' ') or L.StartsWith('    ')) then
      begin
        if not InCode then
          SB.Append(#10'```axon'#10);
        InCode := True;
        if L.StartsWith('    ') then
          SB.Append(L.Substring(4)).Append(#10)
        else
          SB.Append(L).Append(#10);
      end
      else
      begin
        if InCode then
          SB.Append('```'#10#10);
        InCode := False;
        if L.Trim.StartsWith('exports:') then
          SB.Append(#10);   // its own paragraph
        SB.Append(MdEscape(L.Trim)).Append(#10);
      end;
    end;
    if InCode then
      SB.Append('```'#10);
    Result := SB.ToString;
  finally
    SB.Free;
    Lines.Free;
  end;
end;

{ A message in the Help pane (no lookup result). }
procedure TfrmMain.ShowHelp(const Text: string);
var
  First: string;
  P: Integer;
begin
  FHelpViewer.MarkdownText := MdEscape(Text);
  FHelpViewer.SetScrollPos(0);
  FBottomTabs.ActiveTab := FHelpTab;
  First := Text;
  P := First.IndexOf(#10);
  if P >= 0 then
    First := First.Substring(0, P);
  FStatus.Text := First.Trim;
end;

{ Help on a name: the text of "help name", then the Language Reference
  section that documents RefName, if there is one ('' for none). }
procedure TfrmMain.ShowHelpFor(const RefName, Text: string);
var
  Md, RefPath, RefText, Anchor, Section, First: string;
  P: Integer;
begin
  Md := HelpMarkdown(Text);
  if RefName <> '' then
  begin
    RefPath := TPath.Combine(HelpDir, 'Axon-Language-Reference.md');
    if TFile.Exists(RefPath) then
    begin
      RefText := TFile.ReadAllText(RefPath, TEncoding.UTF8);
      Anchor := SectionAnchorFor(RefText, RefName);
      Section := SectionMarkdown(RefText, Anchor);
      if Section <> '' then
        Md := Md + #10'---'#10#10 + Section + #10#10 +
          '[Open this section in the Language Reference](#' + Anchor + ')'#10;
    end;
  end;
  FHelpViewer.MarkdownText := Md;
  FHelpViewer.SetScrollPos(0);
  // Again after the new text is laid out, which may restore the old position.
  TThread.ForceQueue(nil,
    procedure
    begin
      if not GClosing then
        FHelpViewer.SetScrollPos(0);
    end);
  FBottomTabs.ActiveTab := FHelpTab;
  First := Text;
  P := First.IndexOf(#10);
  if P >= 0 then
    First := First.Substring(0, P);
  FStatus.Text := First.Trim;
end;

{ Links in the Help pane open in the Documentation tab; an #anchor is a
  section of the Language Reference, where the section shown came from. }
procedure TfrmMain.HelpLinkClick(Sender: TObject; const AUrl: string);
var
  Url: string;
begin
  Url := AUrl.Trim;
  if Url.Contains('://') or Url.StartsWith('mailto:') or Url.StartsWith('www.') then
    OpenExternal(Url)
  else if Url.StartsWith('#') then
    ShowDocs('Axon-Language-Reference.md' + Url)
  else
    ShowDocs(Url);
end;

procedure TfrmMain.CmdHelpWord(Sender: TObject);
var
  Doc: TDocument;
  Name, Text, Exe, Dir, T, Alias, ModName: string;
  K: Integer;
  Imports: TStringList;
begin
  Doc := CurrentDoc;
  if Doc = nil then
    Exit;
  Name := WordAtCaret(Doc);
  if Name = '' then
  begin
    ShowHelp('Put the caret on a name, such as sin or ode.solve, and press F1.');
    Exit;
  end;
  if LocalHelp(Doc, Name, Text) then
  begin
    ShowHelpFor('', Text);   // defined in this file: no reference section
    Exit;
  end;
  Exe := AxonExecutable;
  if Exe = '' then
  begin
    ShowHelp('Cannot find the axon interpreter next to the IDE.');
    Exit;
  end;
  // A short session: the file's imports, then help. Its output after the
  // last ready marker before "help" is the answer.
  FHelpRunner.Kill;
  Imports := TStringList.Create;
  try
    for K := 1 to Doc.Editor.LineCount do
    begin
      T := Doc.Editor.LineText(K).Trim;
      if T.StartsWith('import ') or (T.StartsWith('from ') and T.Contains(' import ')) then
        Imports.Add(T);
    end;
    // F1 on the module in "from m import f" or "import m as a" (or any
    // import of m): those lines do not bind m itself, so import it too.
    for K := 0 to Imports.Count - 1 do
    begin
      T := Imports[K];
      if T.StartsWith('from ') then
        ModName := T.Substring(5, T.IndexOf(' import ') - 5).Trim
      else
      begin
        ModName := T.Substring(7);
        if ModName.Contains(' as ') then
          ModName := ModName.Substring(0, ModName.IndexOf(' as '));
        if ModName.Contains('#') then
          ModName := ModName.Substring(0, ModName.IndexOf('#'));
        ModName := ModName.Trim;
      end;
      if ModName = Name then
      begin
        Imports.Add('import ' + Name);
        Break;
      end;
    end;
    // The reference names modules by their real name: undo "import m as a".
    FHelpRefName := Name;
    for T in Imports do
      if T.StartsWith('import ') and T.Contains(' as ') then
      begin
        K := T.IndexOf(' as ');
        Alias := T.Substring(K + 4).Trim;
        ModName := T.Substring(7, K - 7).Trim;
        if (Name = Alias) or Name.StartsWith(Alias + '.') then
          FHelpRefName := ModName + Name.Substring(Alias.Length);
      end;
    if Doc.FilePath <> '' then
      Dir := ExtractFileDir(Doc.FilePath)
    else
      Dir := TPath.GetDocumentsPath;
    FHelpName := Name;
    FHelpSkip := Imports.Count + 1;
    FHelpPartial := '';
    FHelpLines.Clear;
    FHelpViewer.MarkdownText := MdEscape('Looking up ' + Name + '...');
    FBottomTabs.ActiveTab := FHelpTab;
    if FHelpRunner.Running then
      Exit;   // the previous lookup is still being stopped; F1 again
    try
      FHelpRunner.Start(Exe, ['--repl-protocol'], Dir, True);
    except
      on E: Exception do
      begin
        ShowHelp('Cannot start axon: ' + E.Message);
        Exit;
      end;
    end;
    for T in Imports do
      FHelpRunner.WriteInput(T + #10);
    FHelpRunner.WriteInput('help ' + Name + #10);
    FHelpRunner.CloseInput;
  finally
    Imports.Free;
  end;
end;

procedure TfrmMain.HelpOutput(Kind: TOutputKind; const Text: string);
var
  S, L: string;
  P: Integer;
begin
  S := FHelpPartial + Text.Replace(#13#10, #10).Replace(#13, #10);
  P := S.IndexOf(#10);
  while P >= 0 do
  begin
    L := S.Substring(0, P);
    S := S.Substring(P + 1);
    P := S.IndexOf(#10);
    if L.StartsWith(#1) then
      Dec(FHelpSkip)                 // one more line read
    else if FHelpSkip = 0 then       // output of "help name"
    begin
      if L.StartsWith(#2) then
        L := L.Substring(1);
      FHelpLines.Add(L);
    end;
  end;
  FHelpPartial := S;
end;

procedure TfrmMain.HelpExit(ExitCode: Integer);
var
  Text: string;
begin
  if FHelpRunner.Killed then
    Exit;
  Text := FHelpLines.Text.TrimRight;
  // An undefined name answers with a NameError report.
  if (Text = '') or Text.StartsWith('NameError') then
    Text := 'No help for ' + FHelpName + ': it is not a built-in, an imported name, or ' +
      'a function or record defined at the top of this file.'
  else
  begin
    ShowHelpFor(FHelpRefName, Text);
    Exit;
  end;
  ShowHelp(Text);
end;

{ ---------------- figures from plot.show() ---------------- }

{ A folder for this IDE's figures, passed to every axon it starts through
  the environment (child processes inherit it). }
procedure TfrmMain.SetupShowDir;
var
  D: string;
begin
  // Folders left by an IDE that did not close normally, after a day.
  try
    for D in TDirectory.GetDirectories(TPath.GetTempPath, 'AxonIDE-*') do
      if TDirectory.GetLastWriteTime(D) < IncDay(Now, -1) then
        TDirectory.Delete(D, True);
  except
  end;
  FShowDir := TPath.Combine(TPath.GetTempPath, Format('AxonIDE-%d', [MainThreadID]));
  try
    ForceDirectories(FShowDir);
  except
    FShowDir := '';
    Exit;
  end;
{$IFDEF MSWINDOWS}
  SetEnvironmentVariable('AXON_SHOW_DIR', PChar(FShowDir));
{$ELSE}
  setenv('AXON_SHOW_DIR', PAnsiChar(UTF8String(FShowDir)), 1);
{$ENDIF}
end;

{ True (and the figure shown) for a line #3"show <path>". }
function TfrmMain.TryShowFigure(const Line: string): Boolean;
const
  Marker = #3'show ';
begin
  Result := Line.StartsWith(Marker);
  if not Result then
    Exit;
  AddFigure(Line.Substring(Length(Marker)).Trim);
  FFigureShown := True;
end;

(* A frame of an animation (graphics.frame): remember it as the newest and
   queue one display, unless one is already queued. Lines arrive faster than
   images can be loaded when the IDE is busy; the queued display then shows
   only the newest frame, so the animation skips frames rather than falling
   behind and playing in bursts. *)
function TfrmMain.TryShowFrame(const Line: string): Boolean;
const
  Marker = #3'frame ';
begin
  Result := Line.StartsWith(Marker);
  if not Result then
    Exit;
  FAnimPending := Line.Substring(Length(Marker)).Trim;
  FAnimBytes := nil;
  FFigureShown := True;
  if not FAnimQueued then
  begin
    FAnimQueued := True;
    TThread.ForceQueue(nil, ShowPendingFrame);
  end;
end;

(* The animation's entry in the figure history: the last, which each frame
   replaces or adds to. With Make, one is added when there is none. *)
function TfrmMain.AnimEntry(Make: Boolean): TFigureEntry;
begin
  if FAnimActive and (FFigures.Count > 0) then
    Exit(FFigures[FFigures.Count - 1]);
  if not Make then
    Exit(nil);
  FShownScene := nil;
  FFigures.Add(TFigureEntry.Create);
  while FFigures.Count > MaxFigures do
    FFigures.Delete(0);
  FAnimActive := True;
  Result := FFigures[FFigures.Count - 1];
end;

{ Decodes the newest full frame, if one is waiting, into the animation's
  entry. }
procedure TfrmMain.ApplyPendingFrame;
var
  Scene: TScene;
  E: TFigureEntry;
begin
  if FAnimBytes = nil then
    Exit;
  try
    Scene := DecodeScene(FAnimBytes);
  except
    on Ex: Exception do
    begin
      FAnimBytes := nil;
      FPlotCaption.Text := 'Cannot show a frame: ' + Ex.Message;
      Exit;
    end;
  end;
  FAnimBytes := nil;
  E := AnimEntry(True);
  if FShownScene = E.Scene then
    FShownScene := nil;
  E.Scene.Free;
  E.Scene := Scene;
  E.Path := '';
  E.Json := '';
end;

{ Items to add to the current frame (DisplayAdd): after any full frame still
  waiting, since they belong on top of it. They are applied at once, as
  they cannot be skipped; the drawing waits for the queued display. }
procedure TfrmMain.AddToFrame(const Payload: TBytes);
var
  Added: TScene;
  E: TFigureEntry;
  It: TSceneItem;
begin
  try
    Added := DecodeScene(Payload);
  except
    on Ex: Exception do
    begin
      FPlotCaption.Text := 'Cannot show a frame: ' + Ex.Message;
      Exit;
    end;
  end;
  ApplyPendingFrame;
  FAnimPending := '';
  E := AnimEntry(True);
  if E.Scene = nil then
  begin
    E.Scene := Added;            // the first frame: it stands alone
    E.Path := '';
    Exit;
  end;
  try
    Added.Items.OwnsObjects := False;
    for It in Added.Items do
      E.Scene.Items.Add(It);
    Added.Items.Clear;
  finally
    Added.Free;
  end;
end;

(* Shows the animation's current frame. The animation has one entry in the
   figure history, the last, which each frame replaces (or adds to); the
   newest full frame waiting is decoded first, and older ones never are.
   A frame reported as a file (marker lines) is loaded into the image, and
   skipped if it cannot be read (being rewritten). *)
procedure TfrmMain.ShowPendingFrame;
var
  Path: string;
  E: TFigureEntry;
begin
  FAnimQueued := False;
  Path := FAnimPending;
  FAnimPending := '';
  ApplyPendingFrame;
  E := AnimEntry(Path <> '');
  if E = nil then
    Exit;
  if FFigureIndex <> FFigures.Count - 1 then
  begin
    FFigureIndex := FFigures.Count - 1;
    UpdateFigureBar;
  end;
  if FPlotGrid <> nil then
    FreeAndNil(FPlotGrid);
  if Path <> '' then
  begin
    FreeAndNil(E.Scene);
    FShownScene := nil;
    E.Path := Path;
    try
      FPlotImage.Bitmap.LoadFromFile(Path);
    except
      Exit;
    end;
    if not FPlotImage.Visible then
      ShowOnly(FPlotImage);
  end
  else if E.Scene <> nil then
  begin
    FShownScene := E.Scene;
    if not FPlotScene.Visible then
      ShowOnly(FPlotScene);
    FPlotScene.Redraw;
  end;
  FPlotCaption.Text := Format('Figure %d: animation', [FFigureIndex + 1]);
end;

{ ---------------- TFigureEntry ---------------- }

destructor TFigureEntry.Destroy;
begin
  Scene.Free;
  inherited;
end;

{ ---------------- syntax check as you type ---------------- }

procedure TfrmMain.CheckTimerFired(Sender: TObject);
begin
  FCheckTimer.Enabled := False;
  StartCheck(CurrentDoc);
end;

procedure TfrmMain.StartCheck(Doc: TDocument);
var
  Exe, Dir: string;
begin
  if Doc = nil then
    Exit;
  if FCheckRunner.Running then
  begin
    FCheckAgain := True;     // check again when this one finishes
    Exit;
  end;
  Exe := AxonExecutable;
  if Exe = '' then
    Exit;
  FCheckDoc := Doc;
  FCheckText := Doc.Editor.GetText;
  FCheckOutput := '';
  if Doc.FilePath <> '' then
    Dir := ExtractFileDir(Doc.FilePath)
  else
    Dir := TPath.GetDocumentsPath;
  try
    FCheckRunner.Start(Exe, ['--check', '-'], Dir, True);
  except
    Exit;                    // checking is a convenience; never an error
  end;
  FCheckRunner.WriteInput(FCheckText);
  FCheckRunner.CloseInput;
end;

procedure TfrmMain.CheckOutput(Kind: TOutputKind; const Text: string);
begin
  FCheckOutput := FCheckOutput + Text;
end;

procedure TfrmMain.CheckExit(ExitCode: Integer);
var
  Doc: TDocument;
  Lines: TArray<string>;
  Kind, Msg: string;
  Frame: TFrame;
begin
  Doc := FCheckDoc;
  FCheckDoc := nil;
  if FCheckAgain then
  begin
    FCheckAgain := False;
    StartCheck(CurrentDoc);
    Exit;
  end;
  if (Doc = nil) or not FDocs.Contains(Doc) then
    Exit;
  // Text changed while checking: this result is stale.
  if Doc.Editor.GetText <> FCheckText then
  begin
    StartCheck(Doc);
    Exit;
  end;
  if FStatus.Text.StartsWith('Syntax error') then
    FStatus.Text := 'Ready';
  if ExitCode <> 1 then
    Exit;
  Lines := FCheckOutput.Replace(#13#10, #10).Split([#10]);
  if (Length(Lines) < 2) or not ParseErrorHead(Lines[0], Kind, Msg) or
    not ParseFrame(Lines[1], Frame) then
    Exit;
  Doc.Editor.MarkWordAt(Frame.Line, Frame.Col, TMarkerKind.mkSquiggle, ColorError,
    Kind + ': ' + Msg);
  if Doc = CurrentDoc then
    FStatus.Text := Format('Syntax error at line %d: %s', [Frame.Line, Msg]);
end;

{ ---------------- welcome tab ---------------- }

procedure TfrmMain.ShowWelcome;
var
  Page, Head, Buttons: TLayout;
  Title, Sub, Ver, Keys, RecentHead: TLabel;
  B: TButton;
  Columns: TGridPanelLayout;
  Column: TLayout;
begin
  if FWelcomeTab <> nil then
  begin
    FTabs.ActiveTab := FWelcomeTab;
    RefreshWelcome;
    UpdateTitle;
    Exit;
  end;
  FWelcomeTab := FTabs.Add;
  SetTabTitle(FWelcomeTab, 'Welcome');
  FWelcomeTab.Index := 0;

  Page := TLayout.Create(Self);
  Page.Parent := FWelcomeTab;
  Page.Align := TAlignLayout.Client;
  Page.Padding.Rect := TRectF.Create(32, 24, 32, 16);

  Head := TLayout.Create(Self);
  Head.Parent := Page;
  Head.Align := TAlignLayout.Top;
  Head.Height := 196;

  Title := TLabel.Create(Self);
  Title.Parent := Head;
  Title.Align := TAlignLayout.Top;
  Title.Height := 40;
  Title.StyledSettings := Title.StyledSettings - [TStyledSetting.Size, TStyledSetting.Style];
  Title.TextSettings.Font.Size := 26;
  Title.TextSettings.Font.Style := [TFontStyle.fsBold];
  Title.Text := 'Axon';

  Sub := TLabel.Create(Self);
  Sub.Parent := Head;
  Sub.Align := TAlignLayout.Top;
  Sub.Position.Y := 100;
  Sub.Height := 22;
  Sub.Text := 'A language for scientific computing.';

  // The exact build, to check that a deployment (on the Mac) is current.
  Ver := TLabel.Create(Self);
  Ver.Parent := Head;
  Ver.Align := TAlignLayout.Top;
  Ver.Position.Y := 130;
  Ver.Height := 20;
  Ver.Text := 'Version ' + AxonVersionText;
  Ver.Opacity := 0.6;

  Buttons := TLayout.Create(Self);
  Buttons.Parent := Head;
  Buttons.Align := TAlignLayout.Top;
  Buttons.Position.Y := 200;
  Buttons.Height := 44;
  Buttons.Margins.Top := 10;
  B := TButton.Create(Self);
  B.Parent := Buttons;
  B.Align := TAlignLayout.Left;
  B.Width := 120;
  B.Text := 'New file';
  B.OnClick := CmdNew;
  B := TButton.Create(Self);
  B.Parent := Buttons;
  B.Position.X := 1000;
  B.Align := TAlignLayout.Left;
  B.Width := 120;
  B.Margins.Left := 10;
  B.Text := 'Open file...';
  B.OnClick := CmdOpen;
  B := TButton.Create(Self);
  B.Parent := Buttons;
  B.Position.X := 2000;
  B.Align := TAlignLayout.Left;
  B.Width := 120;
  B.Margins.Left := 10;
  B.Text := 'Documentation';
  B.OnClick := CmdDocs;

  Keys := TLabel.Create(Self);
  Keys.Parent := Head;
  Keys.Align := TAlignLayout.Top;
  Keys.Position.Y := 300;
  Keys.Height := 40;
  Keys.Margins.Top := 8;
  Keys.TextSettings.WordWrap := True;
  Keys.Text := 'F9 runs the current file. F1 shows help on the word under the caret. ' +
    'Ctrl+Enter sends the current line or selection to the REPL.';

  Columns := TGridPanelLayout.Create(Self);
  Columns.Parent := Page;
  Columns.Align := TAlignLayout.Client;
  Columns.RowCollection.BeginUpdate;
  Columns.ColumnCollection.BeginUpdate;
  Columns.RowCollection.Clear;
  Columns.ColumnCollection.Clear;
  Columns.RowCollection.Add.Value := 100;
  Columns.ColumnCollection.Add.Value := 50;
  Columns.ColumnCollection.Add.Value := 50;
  Columns.RowCollection.EndUpdate;
  Columns.ColumnCollection.EndUpdate;

  Column := TLayout.Create(Self);
  Column.Parent := Columns;
  Column.Align := TAlignLayout.Client;
  Column.Margins.Right := 8;
  RecentHead := TLabel.Create(Self);
  RecentHead.Parent := Column;
  RecentHead.Align := TAlignLayout.Top;
  RecentHead.Height := 26;
  RecentHead.StyledSettings := RecentHead.StyledSettings - [TStyledSetting.Style];
  RecentHead.TextSettings.Font.Style := [TFontStyle.fsBold];
  RecentHead.Text := 'Recent files';
  FWelcomeList := TListBox.Create(Self);
  FWelcomeList.Parent := Column;
  FWelcomeList.Align := TAlignLayout.Client;
  FWelcomeList.ItemHeight := 40;
  FWelcomeList.OnItemClick := WelcomeItemClick;

  Column := TLayout.Create(Self);
  Column.Parent := Columns;
  Column.Align := TAlignLayout.Client;
  Column.Margins.Left := 8;
  RecentHead := TLabel.Create(Self);
  RecentHead.Parent := Column;
  RecentHead.Align := TAlignLayout.Top;
  RecentHead.Height := 26;
  RecentHead.StyledSettings := RecentHead.StyledSettings - [TStyledSetting.Style];
  RecentHead.TextSettings.Font.Style := [TFontStyle.fsBold];
  RecentHead.Text := 'Examples';
  FExamplesList := TListBox.Create(Self);
  FExamplesList.Parent := Column;
  FExamplesList.Align := TAlignLayout.Client;
  FExamplesList.ItemHeight := 40;
  FExamplesList.OnItemClick := ExampleItemClick;

  RefreshWelcome;
  RefreshExamples;
  FTabs.ActiveTab := FWelcomeTab;
  UpdateTitle;
end;

procedure TfrmMain.CloseWelcome;
begin
  if FWelcomeTab = nil then
    Exit;
  FWelcomeList := nil;
  FExamplesList := nil;
  FreeEditorTab(FWelcomeTab);
  FWelcomeTab := nil;
  UpdateTitle;
end;

{ One item per recent file: its name, with the folder as the detail line. }
procedure TfrmMain.RefreshWelcome;
var
  Item: TListBoxItem;
  Path: string;
begin
  if FWelcomeList = nil then
    Exit;
  FWelcomeList.BeginUpdate;
  try
    FWelcomeList.Clear;
    for Path in FRecent do
    begin
      Item := TListBoxItem.Create(FWelcomeList);
      Item.Parent := FWelcomeList;
      Item.StyleLookup := 'listboxitembottomdetail';
      Item.TagString := Path;
      Item.Text := ExtractFileName(Path);
      if TFile.Exists(Path) then
        Item.ItemData.Detail := ExtractFileDir(Path)
      else
        Item.ItemData.Detail := ExtractFileDir(Path) + '   (missing: click to remove)';
    end;
    if FRecent.Count = 0 then
    begin
      Item := TListBoxItem.Create(FWelcomeList);
      Item.Parent := FWelcomeList;
      Item.Text := 'No recent files yet.';
      Item.Enabled := False;
    end;
  finally
    FWelcomeList.EndUpdate;
  end;
end;

procedure TfrmMain.WelcomeItemClick(const Sender: TCustomListBox; const Item: TListBoxItem);
var
  Path: string;
  K: Integer;
begin
  if (Item = nil) or (Item.TagString = '') then
    Exit;
  Path := Item.TagString;
  if TFile.Exists(Path) then
    // Deferred: opening a file rebuilds this list, which owns Item.
    TThread.ForceQueue(nil,
      procedure
      begin
        if not GClosing then
          OpenFile(Path);
      end)
  else
  begin
    K := FRecent.IndexOf(Path);
    if K >= 0 then
      FRecent.Delete(K);
    TThread.ForceQueue(nil,
      procedure
      begin
        if not GClosing then
          RebuildRecentMenu;
      end);
  end;
end;

{ The installed examples: an examples folder next to the IDE. }
function TfrmMain.ExamplesDir: string;
begin
  Result := TPath.Combine(ExtractFilePath(ParamStr(0)), 'examples');
end;

{ One item per example, titled by the first line of its ## docstring. }
procedure TfrmMain.RefreshExamples;
var
  Files: TArray<string>;
  F, Title, L: string;
  Lines: TArray<string>;
  Item: TListBoxItem;
begin
  if FExamplesList = nil then
    Exit;
  FExamplesList.BeginUpdate;
  try
    FExamplesList.Clear;
    if TDirectory.Exists(ExamplesDir) then
      Files := TDirectory.GetFiles(ExamplesDir, '*.sci')
    else
      Files := nil;
    TArray.Sort<string>(Files);
    for F in Files do
    begin
      Title := ChangeFileExt(ExtractFileName(F), '');
      try
        Lines := TFile.ReadAllLines(F, TEncoding.UTF8);
        for L in Lines do
          if L.TrimLeft.StartsWith('##') then
          begin
            Title := L.TrimLeft.Substring(2).Trim;
            Break;
          end;
      except
      end;
      Item := TListBoxItem.Create(FExamplesList);
      Item.Parent := FExamplesList;
      Item.StyleLookup := 'listboxitembottomdetail';
      Item.TagString := F;
      Item.Text := Title;
      Item.ItemData.Detail := ExtractFileName(F);
    end;
    if Length(Files) = 0 then
    begin
      Item := TListBoxItem.Create(FExamplesList);
      Item.Parent := FExamplesList;
      Item.Text := 'No examples installed.';
      Item.Enabled := False;
    end;
  finally
    FExamplesList.EndUpdate;
  end;
end;

{ Opens a copy of the example in Documents/Axon Examples (made once, so
  later edits are kept), leaving the installed file untouched. }
procedure TfrmMain.ExampleItemClick(const Sender: TCustomListBox; const Item: TListBoxItem);
begin
  if (Item <> nil) and (Item.TagString <> '') then
    OpenExampleCopy(Item.TagString);
end;

{ The copy of an example the user opens lives in Documents/Axon Examples, so
  the original next to the IDE stays unchanged. A record there (examples.ini)
  keeps a hash of each example as it was copied. When the shipped example has
  changed since: a copy still as copied is replaced with the new version; a
  copy the user has edited (or one copied before the record existed) is
  replaced only if the user agrees. }
procedure TfrmMain.OpenExampleCopy(const Source: string);
var
  Dir, Copy_, Name, SourceHash, CopyHash, Recorded: string;
  Record_: TMemIniFile;
  Replace: Boolean;

  function HashOf(const Path: string): string;
  begin
    Result := THashMD5.GetHashString(TEncoding.UTF8.GetString(TFile.ReadAllBytes(Path)));
  end;

begin
  Dir := TPath.Combine(TPath.GetDocumentsPath, 'Axon Examples');
  Name := ExtractFileName(Source);
  Copy_ := TPath.Combine(Dir, Name);
  try
    ForceDirectories(Dir);
    Record_ := TMemIniFile.Create(TPath.Combine(Dir, 'examples.ini'), TEncoding.UTF8);
    try
      SourceHash := HashOf(Source);
      if not TFile.Exists(Copy_) then
        TFile.Copy(Source, Copy_)
      else
      begin
        CopyHash := HashOf(Copy_);
        Recorded := Record_.ReadString('Copied', Name, '');
        if CopyHash <> SourceHash then
        begin
          // The shipped example has changed since the copy was made.
          Replace := CopyHash = Recorded;   // untouched since it was copied
          // Asked once per new version: a "no" is remembered until the
          // shipped example changes again.
          if not Replace and (Record_.ReadString('Declined', Name, '') <> SourceHash) then
            Replace := TDialogServiceSync.MessageDialog(Format(
              'The example %s has been updated since your copy was made.'#10 +
              'Replace your copy with the new version? Any changes you made ' +
              'to it will be lost.', [Name]),
              TMsgDlgType.mtConfirmation, [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo],
              TMsgDlgBtn.mbYes, 0) = mrYes;
          if Replace then
            TFile.Copy(Source, Copy_, True)
          else
          begin
            Record_.WriteString('Declined', Name, SourceHash);
            SourceHash := Recorded;          // keep the user's copy as it is
          end;
        end;
      end;
      Record_.WriteString('Copied', Name, SourceHash);
      Record_.UpdateFile;
    finally
      Record_.Free;
    end;
  except
    on E: Exception do
    begin
      TDialogServiceSync.MessageDialog(Format('Cannot copy the example to %s:'#10'%s',
        [Dir, E.Message]), TMsgDlgType.mtError, [TMsgDlgBtn.mbOK], TMsgDlgBtn.mbOK, 0);
      Exit;
    end;
  end;
  TThread.ForceQueue(nil,
    procedure
    begin
      if not GClosing then
        OpenFile(Copy_);
    end);
end;

procedure TfrmMain.CmdWelcome(Sender: TObject);
begin
  ShowWelcome;
end;

{ ---------------- documentation ---------------- }

{ The help pages: a help folder next to the IDE. }
function TfrmMain.HelpDir: string;
begin
  Result := TPath.Combine(ExtractFilePath(ParamStr(0)), 'help');
end;

{ Shows a help page, given as "page.md" or "page.md#anchor" in the help
  folder, in the Documentation tab (made on first use). }
procedure TfrmMain.ShowDocs(const Target: string);
var
  Bar: TLayout;
  B: TButton;
  P: Integer;
  Page, Anchor: string;
begin
  if FDocsTab = nil then
  begin
    FDocsTab := FTabs.Add;
    SetTabTitle(FDocsTab, 'Documentation');
    Bar := TLayout.Create(Self);
    Bar.Parent := FDocsTab;
    Bar.Align := TAlignLayout.Top;
    Bar.Height := 34;
    Bar.Padding.Rect := TRectF.Create(4, 4, 4, 4);
    FDocsBack := TButton.Create(Self);
    FDocsBack.Parent := Bar;
    FDocsBack.Align := TAlignLayout.Left;
    FDocsBack.Width := 70;
    FDocsBack.Text := #$2190' Back';
    FDocsBack.OnClick := CmdDocsBack;
    B := TButton.Create(Self);
    B.Parent := Bar;
    B.Position.X := 1000;
    B.Align := TAlignLayout.Left;
    B.Width := 80;
    B.Margins.Left := 6;
    B.Text := 'Contents';
    B.OnClick := CmdDocsHome;
    FDocsTitle := TLabel.Create(Self);
    FDocsTitle.Parent := Bar;
    FDocsTitle.Align := TAlignLayout.Client;
    FDocsTitle.Margins.Left := 12;
    FDocsViewer := TRhoMarkdownViewer.Create(Self);
    FDocsViewer.Parent := FDocsTab;
    FDocsViewer.Align := TAlignLayout.Client;
    FDocsViewer.OnLinkClick := DocsLinkClick;
    FDocsViewer.OnSearchChange := DocsSearchChange;
    FDocsViewer.FontSize := FPrefs.DocsFontSize;
    // Find (Ctrl+F): the editor's find bar without its replace row, below the
    // toolbar. Typing highlights; Enter / Shift+Enter or Next / Prev move
    // (F3 / Shift+F3 in the page too); Escape or Close clears.
    FDocsFindBar := TFindBar.Create(Self);
    FDocsFindBar.Parent := FDocsTab;
    FDocsFindBar.ShowReplace := False;
    FDocsFindBar.Position.Y := Bar.Height + 1;
    FDocsFindBar.Align := TAlignLayout.Top;
    FDocsFindBar.OnSearchChanged :=
      procedure(const S: string; O: TFindOptions)
      begin
        DocsSearch(S, O);
      end;
    FDocsFindBar.OnFindNext :=
      function(const S: string; O: TFindOptions): Boolean
      begin
        DocsSearch(S, O);
        Result := FDocsViewer.FindNext;
      end;
    FDocsFindBar.OnFindPrev :=
      function(const S: string; O: TFindOptions): Boolean
      begin
        DocsSearch(S, O);
        Result := FDocsViewer.FindPrevious;
      end;
    FDocsFindBar.OnClosed :=
      procedure
      begin
        FDocsViewer.ClearSearch;
        FDocsViewer.SetFocus;
      end;
    if FDark then
      FDocsViewer.ApplyTheme(rtDark);
    ThemeDocsFindBar;
  end;
  FTabs.ActiveTab := FDocsTab;
  P := Target.IndexOf('#');
  if P >= 0 then
  begin
    Page := Target.Substring(0, P);
    Anchor := Target.Substring(P + 1);
  end
  else
  begin
    Page := Target;
    Anchor := '';
  end;
  NavigateDocs(TPath.Combine(HelpDir, Page), Anchor, FDocsPage <> '');
  UpdateTitle;
end;

{ Shows a page, at an anchor or at a scroll position (a negative ScrollTo
  means the top for a new page). The page left behind goes on the Back list
  with its scroll position. }
procedure TfrmMain.NavigateDocs(const Path, Anchor: string; AddToHistory: Boolean;
  ScrollTo: Single);
var
  Full: string;
  NewPage: Boolean;
begin
  Full := TPath.GetFullPath(Path);
  if not TFile.Exists(Full) then
  begin
    FStatus.Text := 'No help page ' + ExtractFileName(Full);
    Exit;
  end;
  NewPage := not SameFileName(FDocsPage, Full);
  if AddToHistory and (FDocsPage <> '') and NewPage then
    FDocsHistory.Add(FDocsPage + '|' + FloatToStr(FDocsViewer.ScrollY));
  if NewPage then
  begin
    FDocsViewer.BasePath := ExtractFileDir(Full);
    FDocsViewer.LoadFromFile(Full);
    FDocsPage := Full;
  end;
  FDocsTitle.Text := ChangeFileExt(ExtractFileName(Full), '');
  FDocsBack.Enabled := FDocsHistory.Count > 0;
  // After the page is laid out: an anchor, a remembered position, or the top.
  TThread.ForceQueue(nil,
    procedure
    begin
      if GClosing or (FDocsViewer = nil) then
        Exit;
      if Anchor <> '' then
        FDocsViewer.ScrollToAnchor('#' + Anchor)
      else if ScrollTo >= 0 then
        FDocsViewer.SetScrollPos(ScrollTo)
      else if NewPage then
        FDocsViewer.SetScrollPos(0);
      DocsSearchChange(nil);   // the find term carries over to the new page
    end);
end;

{ Links in a help page: #anchors scroll, web links open in the browser, other
  pages open here, and examples open as a copy in the editor. }
procedure TfrmMain.DocsLinkClick(Sender: TObject; const AUrl: string);
var
  Url, Page, Anchor, Path: string;
  P: Integer;
begin
  Url := AUrl.Trim;
  if Url.StartsWith('#') then
  begin
    FDocsViewer.ScrollToAnchor(Url);
    Exit;
  end;
  if Url.Contains('://') or Url.StartsWith('mailto:') or Url.StartsWith('www.') then
  begin
    OpenExternal(Url);
    Exit;
  end;
  P := Url.IndexOf('#');
  if P >= 0 then
  begin
    Page := Url.Substring(0, P);
    Anchor := Url.Substring(P + 1);
  end
  else
  begin
    Page := Url;
    Anchor := '';
  end;
  Path := TPath.GetFullPath(TPath.Combine(ExtractFileDir(FDocsPage),
    Page.Replace('/', PathDelim)));
  if SameText(ExtractFileExt(Path), '.md') then
    NavigateDocs(Path, Anchor, True)
  else if SameText(ExtractFileExt(Path), '.sci') and TFile.Exists(Path) then
  begin
    if SameFileName(ExtractFileDir(Path), TPath.GetFullPath(ExamplesDir)) then
      OpenExampleCopy(Path)
    else
      OpenFile(Path);
  end
  else if TFile.Exists(Path) then
    OpenExternal(Path)
  else
    FStatus.Text := 'Not found: ' + Page;
end;

procedure TfrmMain.OpenExternal(const Target: string);
begin
{$IFDEF MSWINDOWS}
  ShellExecute(0, 'open', PChar(Target), nil, nil, SW_SHOWNORMAL);
{$ELSE}
  _system(PAnsiChar(UTF8String('open ''' + Target.Replace('''', '''\''''') + ''' &')));
{$ENDIF}
end;

procedure TfrmMain.CmdDocs(Sender: TObject);
begin
  if (FDocsTab <> nil) and (FDocsPage <> '') then
    FTabs.ActiveTab := FDocsTab
  else
    ShowDocs('index.md');
  UpdateTitle;
end;

procedure TfrmMain.CmdReference(Sender: TObject);
begin
  ShowDocs('Axon-Language-Reference.md');
end;

{ The reference's list of every built-in function and constant. }
procedure TfrmMain.CmdBuiltins(Sender: TObject);
begin
  ShowDocs('Axon-Language-Reference.md#built-in-functions');
end;

procedure TfrmMain.CmdDocsBack(Sender: TObject);
var
  Entry: string;
  P: Integer;
  Y: Single;
begin
  if FDocsHistory.Count = 0 then
    Exit;
  Entry := FDocsHistory[FDocsHistory.Count - 1];
  FDocsHistory.Delete(FDocsHistory.Count - 1);
  P := Entry.LastIndexOf('|');
  Y := StrToFloatDef(Entry.Substring(P + 1), 0);
  NavigateDocs(Entry.Substring(0, P), '', False, Y);
end;

procedure TfrmMain.CmdDocsHome(Sender: TObject);
begin
  NavigateDocs(TPath.Combine(HelpDir, 'index.md'), '', True);
end;

procedure TfrmMain.EditorGotoLine(Sender: TObject);
var
  Values: TArray<string>;
  N: Integer;
begin
  if CurrentDoc = nil then
    Exit;
  Values := [IntToStr(CurrentDoc.Editor.CaretLine)];
  if TDialogServiceSync.InputQuery('Go to line', ['Line number'], Values) and
    TryStrToInt(Values[0].Trim, N) then
    CurrentDoc.Editor.GoToLine(N);
end;

{ ---------------- preferences ---------------- }

{ A line in the Output or REPL pane at the output font size. }
procedure TfrmMain.SizePaneItem(Item: TListBoxItem);
begin
  Item.StyledSettings := Item.StyledSettings - [TStyledSetting.Size];
  Item.TextSettings.Font.Size := FPrefs.OutputFontSize;
end;

procedure TfrmMain.ApplyPreferences;
var
  Doc: TDocument;
  K: Integer;
  RowHeight: Single;
begin
  for Doc in FDocs do
    Doc.Editor.FontSize := FPrefs.EditorFontSize;
  // Rows tall enough for the font, with a little space.
  RowHeight := Round(FPrefs.OutputFontSize * 1.5) + 2;
  FOutput.ItemHeight := RowHeight;
  for K := 0 to FOutput.Count - 1 do
    SizePaneItem(FOutput.ListItems[K]);
  FReplList.ItemHeight := RowHeight;
  for K := 0 to FReplList.Count - 1 do
    SizePaneItem(FReplList.ListItems[K]);
  FReplEdit.StyledSettings := FReplEdit.StyledSettings - [TStyledSetting.Size];
  FReplEdit.TextSettings.Font.Size := FPrefs.OutputFontSize;
  FReplPrompt.StyledSettings := FReplPrompt.StyledSettings - [TStyledSetting.Size];
  FReplPrompt.TextSettings.Font.Size := FPrefs.OutputFontSize;
  FHelpViewer.FontSize := FPrefs.OutputFontSize;
  if FDocsViewer <> nil then
    FDocsViewer.FontSize := FPrefs.DocsFontSize;
end;

procedure TfrmMain.CmdPreferences(Sender: TObject);
begin
  if EditPreferences(FPrefs, {$IFDEF MSWINDOWS}'Consolas'{$ELSE}'Menlo'{$ENDIF}) then
  begin
    ApplyPreferences;
    SaveSettings;
  end;
end;

{ ---------------- JIT ---------------- }

procedure SetProcessEnv(const Name, Value: string);
begin
{$IFDEF MSWINDOWS}
  SetEnvironmentVariable(PChar(Name), PChar(Value));
{$ELSE}
  setenv(PAnsiChar(UTF8String(Name)), PAnsiChar(UTF8String(Value)), 1);
{$ENDIF}
end;

{ The programs and REPLs the IDE starts inherit AXON_JIT; AXON_JIT_REPORT
  makes axon report its compile decisions. }
procedure TfrmMain.ApplyJit(On: Boolean);
begin
  FJit := On;
  if On then
    SetProcessEnv('AXON_JIT', 'on')
  else
    SetProcessEnv('AXON_JIT', 'off');
  SetProcessEnv('AXON_JIT_REPORT', '1');
  if FJitItem <> nil then
    FJitItem.IsChecked := On;
  if FJitButton <> nil then
  begin
    FJitButton.IsPressed := On;
    if On then FJitButton.Text := 'JIT on' else FJitButton.Text := 'JIT off';
  end;
end;

procedure TfrmMain.CmdToggleJit(Sender: TObject);
begin
  ApplyJit(not FJit);
  SaveSettings;
  if FJit then
    AddNote('JIT compiler on: the next run compiles functions to native code.', FPal.Note)
  else
    AddNote('JIT compiler off: the next run is interpreted.', FPal.Note);
  if FRepl.Running then
    AddNote('Restart the REPL (Run > Restart REPL) for it to use this too.', FPal.Note);
  ScrollToEnd(FOutput);
end;

{ A line #3"jit compiled name", or #3"jit rejected name: reason (line:col)"
  followed by a tab and the file. }
function TfrmMain.TryJitReport(const Line: string): Boolean;
const
  Marker = #3'jit ';
var
  Rest, Pos: string;
  Where: TFrame;
  Tab, Open, Colon: Integer;
begin
  Result := Line.StartsWith(Marker);
  if not Result then
    Exit;
  Rest := Line.Substring(Length(Marker));
  if Rest.StartsWith('compiled ') then
  begin
    Rest := Rest.Substring(Length('compiled '));
    if FJitCompiled.IndexOf(Rest) < 0 then
      FJitCompiled.Add(Rest);
  end
  else if Rest.StartsWith('rejected ') then
  begin
    Rest := Rest.Substring(Length('rejected '));
    Where := Default(TFrame);
    Tab := Rest.IndexOf(#9);
    if Tab >= 0 then
    begin
      Where.FileName := Rest.Substring(Tab + 1).Trim;
      Rest := Rest.Substring(0, Tab);
    end;
    // The place is the "(line:col)" that ends the reason.
    Open := Rest.LastIndexOf('(');
    if Rest.EndsWith(')') and (Open >= 0) then
    begin
      Pos := Rest.Substring(Open + 1, Rest.Length - Open - 2);
      Colon := Pos.IndexOf(':');
      if (Colon > 0) and TryStrToInt(Pos.Substring(0, Colon), Where.Line) and
        TryStrToInt(Pos.Substring(Colon + 1), Where.Col) then
        Rest := Rest.Substring(0, Open).TrimRight
      else
        Where.Line := 0;
    end;
    // A loop compiled for other types later can be rejected again alike.
    if FJitRejected.IndexOf(Rest) < 0 then
    begin
      FJitRejected.Add(Rest);
      FJitWhere.Add(Where);
    end;
  end;
end;

{ After a run: the functions and loops compiled, and why others in the
  user's own files ran interpreted, each a link to the place, which is also
  marked in the editor (with the reason as its tip) when the file is open.
  Those in the standard library, which the user cannot change, are only
  counted. }
procedure TfrmMain.ReportJit;
const
  MaxShown = 8;
var
  K, Shown, InLibrary, First: Integer;
  Lib, Path, Text: string;
  Where: TFrame;
  Doc: TDocument;
  Item: TListBoxItem;
begin
  if not FJit or not FPrefs.ShowJitReport or
    ((FJitCompiled.Count = 0) and (FJitRejected.Count = 0)) then
    Exit;
  if FJitCompiled.Count > 0 then
    AddNote('JIT compiled: ' + string.Join(', ', FJitCompiled.ToStringArray), FPal.Note);
  Lib := IncludeTrailingPathDelimiter(TPath.Combine(ExtractFilePath(AxonExecutable), 'stdlib'));
  Shown := 0;
  InLibrary := 0;
  for K := 0 to FJitRejected.Count - 1 do
  begin
    Where := FJitWhere[K];
    if Where.FileName <> '' then
      Path := ResolveRunPath(Where.FileName)
    else
      Path := '';
    if (Path <> '') and Path.StartsWith(Lib, True) then
    begin
      Inc(InLibrary);
      Continue;
    end;
    if (Path <> '') and (Where.Line > 0) then
    begin
      // The whole line, from its first character, so it is hard to miss.
      Doc := FindDocument(Path);
      if Doc <> nil then
      begin
        Text := Doc.Editor.LineText(Where.Line);
        First := Length(Text) - Length(Text.TrimLeft) + 1;
        if Text.Trim <> '' then
          Doc.Editor.AddMarker(Where.Line, First, Length(Text.TrimRight) - First + 1,
            TMarkerKind.mkSquiggle, ColorJit, 'Runs interpreted: ' + FJitRejected[K]);
      end;
    end;
    Inc(Shown);
    if Shown > MaxShown then
      Continue;
    if Shown = 1 then
      AddNote('Interpreted (click a line to see where):', FPal.Note);
    AddNote('  ' + FJitRejected[K], FPal.Note);
    if (Path <> '') and (Where.Line > 0) then
    begin
      Item := FOutput.ListItems[FOutput.Count - 1];
      Item.Tag := -(K + 1);
      Item.TextSettings.FontColor := FPal.Link;
      Item.Hint := Format('Click to go to %s line %d', [ExtractFileName(Path), Where.Line]);
      Item.ShowHint := True;
    end;
  end;
  if Shown > MaxShown then
    AddNote(Format('  ... and %d more', [Shown - MaxShown]), FPal.Note);
  if InLibrary > 0 then
    AddNote(Format('(%d in the standard library also run interpreted)', [InLibrary]), FPal.Note);
end;

{ ---------------- theme ---------------- }

function PanePalette(Dark: Boolean): TPanePalette;
begin
  if Dark then
  begin
    Result.Text := $FFD4D4D4;
    Result.Error := $FFF48771;
    Result.Note := $FF9D9D9D;
    Result.Link := $FF4FC1FF;
  end
  else
  begin
    Result.Text := TAlphaColors.Black;
    Result.Error := $FFC62828;
    Result.Note := $FF606060;
    Result.Link := $FF1565C0;
  end;
end;

procedure TfrmMain.ApplyEditorTheme(Editor: TSkiaCodeEditor);
begin
  if FDark then
  begin
    Editor.BackgroundColor := $FF1E1E1E;
    Editor.TextColor := $FFD4D4D4;
    Editor.GutterColor := $FF252526;
    Editor.GutterTextColor := $FF858585;
    Editor.CaretColor := $FFAEAFAD;
    Editor.SelectionColor := $80264F78;
    Editor.CurrentLineColor := $14FFFFFF;
    Editor.FindMatchColor := $A0B16A00;
    Editor.FindHighlightColor := $40B16A00;
    Editor.BracketMatchColor := $A0808080;
    Editor.SetTokenizer(AxonTokenizer(DarkAxonColors));
  end
  else
  begin
    Editor.BackgroundColor := TAlphaColors.White;
    Editor.TextColor := TAlphaColors.Black;
    Editor.GutterColor := $FFF0F0F0;
    Editor.GutterTextColor := $FF808080;
    Editor.CaretColor := TAlphaColors.Black;
    Editor.SelectionColor := $400078D7;
    Editor.CurrentLineColor := $18808080;
    Editor.FindMatchColor := $A0FF9800;
    Editor.FindHighlightColor := $40FFC107;
    Editor.BracketMatchColor := $A0A0A0A0;
    Editor.SetTokenizer(AxonTokenizer(DefaultAxonColors));
  end;
end;

{ Lines already in a pane take the new theme's colours, by role. }
procedure TfrmMain.RecolorList(List: TListBox; const Old: TPanePalette);
var
  K: Integer;
  Item: TListBoxItem;
  C: TAlphaColor;
begin
  for K := 0 to List.Count - 1 do
  begin
    Item := List.ListItems[K];
    if TStyledSetting.FontColor in Item.StyledSettings then
      Continue;
    C := Item.TextSettings.FontColor;
    if C = Old.Text then Item.TextSettings.FontColor := FPal.Text
    else if C = Old.Error then Item.TextSettings.FontColor := FPal.Error
    else if C = Old.Note then Item.TextSettings.FontColor := FPal.Note
    else if C = Old.Link then Item.TextSettings.FontColor := FPal.Link;
  end;
end;

procedure TfrmMain.ApplyTheme(Dark: Boolean);
var
  Old: TPanePalette;
  Doc: TDocument;
begin
  if Dark then
  begin
    if not TStyleManager.TrySetStyleFromResource('DARKSTYLE') then
      Dark := False;            // no style: stay light rather than half-dark
  end
  else
    TStyleManager.SetStyle(nil);  // the platform's own style
  Old := FPal;
  FDark := Dark;
  FPal := PanePalette(Dark);
  for Doc in FDocs do
    ApplyEditorTheme(Doc.Editor);
  if FDocsViewer <> nil then
  begin
    if Dark then FDocsViewer.ApplyTheme(rtDark) else FDocsViewer.ApplyTheme(rtLight);
    ThemeDocsFindBar;
  end;
  if Dark then FHelpViewer.ApplyTheme(rtDark) else FHelpViewer.ApplyTheme(rtLight);
  RecolorList(FOutput, Old);
  RecolorList(FReplList, Old);
  FDarkItem.IsChecked := Dark;
end;

procedure TfrmMain.CmdDarkTheme(Sender: TObject);
begin
  ApplyTheme(not FDark);
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
  CloseTab(FTabs.ActiveTab);
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

{ The Help or Documentation viewer when it has the focus (the user clicked
  or selected in it), else nil: Copy and Select All then act on it. }
function TfrmMain.FocusedViewer: TRhoMarkdownViewer;
begin
  if (FHelpViewer <> nil) and FHelpViewer.IsFocused then
    Result := FHelpViewer
  else if (FDocsViewer <> nil) and FDocsViewer.IsFocused then
    Result := FDocsViewer
  else
    Result := nil;
end;

procedure TfrmMain.CmdCopy(Sender: TObject);
begin
  // From a viewer, the text as shown (not its markdown).
  if FocusedViewer <> nil then
    FocusedViewer.CopySelection(True)
  else if CurrentDoc <> nil then
    CurrentDoc.Editor.CopySelection;
end;

procedure TfrmMain.CmdPaste(Sender: TObject);
begin
  if CurrentDoc <> nil then CurrentDoc.Editor.PasteClipboard;
end;

procedure TfrmMain.CmdSelectAll(Sender: TObject);
begin
  if FocusedViewer <> nil then
    FocusedViewer.SelectAll
  else if CurrentDoc <> nil then
    CurrentDoc.Editor.SelectAll;
end;

procedure TfrmMain.CmdFind(Sender: TObject);
begin
  if (FDocsTab <> nil) and (FTabs.ActiveTab = FDocsTab) then
    FDocsFindBar.Activate('')
  else if CurrentDoc <> nil then
    CurrentDoc.Editor.ShowBuiltInFindBar;
end;

{ The Documentation tab's find bar drives the viewer's search. }
procedure TfrmMain.DocsSearch(const S: string; O: TFindOptions);
begin
  FDocsViewer.SearchCaseSensitive := foMatchCase in O;
  FDocsViewer.SearchWholeWords := foWholeWord in O;
  FDocsViewer.SearchText := S;
end;

{ The viewer's search state changed (typing, Next/Prev, F3, a new page):
  show "N of M" in the bar. }
procedure TfrmMain.DocsSearchChange(Sender: TObject);
begin
  if (FDocsFindBar = nil) or not FDocsFindBar.Visible then
    Exit;
  if FDocsViewer.SearchText = '' then
    FDocsFindBar.SetMatchInfo(0, -1)
  else
    FDocsFindBar.SetMatchInfo(FDocsViewer.SearchMatchIndex + 1,
      FDocsViewer.SearchMatchCount);
end;

procedure TfrmMain.ThemeDocsFindBar;
begin
  if FDocsFindBar <> nil then
    FDocsFindBar.ApplyTheme(FDocsViewer.CodeBackgroundColor, FDocsViewer.TextColor);
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
  TDialogServiceSync.MessageDialog('Axon IDE'#10'Version ' + AxonVersionText + #10#10 +
    'An editor and runner for the Axon language.',
    TMsgDlgType.mtInformation, [TMsgDlgBtn.mbOK], TMsgDlgBtn.mbOK, 0);
end;

end.
