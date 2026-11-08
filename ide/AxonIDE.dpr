program AxonIDE;

(* The Axon IDE: an editor and runner for Axon programs (FMX, Windows and
   macOS). Programs run in a separate axon process; see uMainForm. The editor
   is TSkiaCodeEditor from RhodyComponents\RhoEditor, and the help viewer
   TRhoMarkdownViewer from RhodyComponents\RhoMarkDownViewer, both found on
   the unit search path. *)

uses
  System.StartUpCopy,
  FMX.Forms,
  FMX.Skia,
  {$IFDEF MACOS}
  Macapi.Foundation,
  Macapi.Helpers,
  {$ENDIF}
  uMainForm in 'uMainForm.pas' {frmMain},
  uProcessRunner in 'uProcessRunner.pas',
  uAxonHighlighter in 'uAxonHighlighter.pas',
  uRunReport in 'uRunReport.pas',
  uAxonMarkdown in 'uAxonMarkdown.pas';

{$R 'AxonIDEStyles.res' 'AxonIDEStyles.rc'}


begin
  GlobalUseSkia := True;
  {$IFDEF MACOS}
  // Let held keys repeat instead of showing the accent picker, as on Windows.
  TNSUserDefaults.Wrap(TNSUserDefaults.OCClass.standardUserDefaults)
    .setBool(False, StrToNSStr('ApplePressAndHoldEnabled'));
  {$ENDIF}
  Application.Initialize;
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
