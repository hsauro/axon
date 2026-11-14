unit uOutputPane;

(* The Output and REPL panes: lines of text in a read-only TSkiaCodeEditor
   (RhoEditor with ReadOnly set), so any span can be selected with the mouse
   or the keyboard, copied (Ctrl+C, the right-click menu) and searched
   (Ctrl+F).

   Each line has a role, which gives its colour through the editor's
   OnLineColor: the program's output, an error (standard error), a note from
   the IDE, a link, a line the host can go to when it is clicked (a trace
   line, a JIT note), underlined with a hand pointer and its tooltip, or what
   the user typed (the REPL's echo), in the link colour but not a link. At most
   MaxLines lines are kept; the oldest are dropped. Lines added between
   BeginUpdate and EndUpdate go in as one append, and the view follows new
   lines only while it shows the last one, so scrolling up to read is not
   undone by more output. *)

interface

uses
  System.SysUtils, System.Classes, System.UITypes, System.Generics.Collections,
  FMX.Types, FMX.Controls, uSkiaCodeEditor, uCodeEditorTypes;

type
  TOutputRole = (orText, orError, orNote, orLink, orInput);

  TOutputLinkEvent = procedure(Sender: TObject; ATag: Integer) of object;

  TOutputPane = class
  private type
    TLineInfo = record
      Role: TOutputRole;
      Tag: Integer;       // a link's tag, passed to OnLink
      Hint: string;       // a link's tooltip
    end;
  private
    FEditor: TSkiaCodeEditor;
    FLines: TList<TLineInfo>;     // one per line, the pending ones included
    FColors: array[TOutputRole] of TAlphaColor;
    FMaxLines: Integer;
    FUpdating: Integer;
    FPending: TStringBuilder;     // text added since the last flush
    FPendingFrom: Integer;        // FLines index of the first line in it, or -1
    FAdded: Integer;              // lines added since Clear
    FOnLink: TOutputLinkEvent;
    procedure LineColor(Sender: TObject; ALine: Integer; var AColor: TAlphaColor);
    procedure LineClick(Sender: TObject; ALine, ACol: Integer);
    procedure Flush;
    procedure MarkLinks(AFrom: Integer);
  public
    // The editor goes into AParent, aligned to fill it, owned by AOwner.
    constructor Create(AOwner: TComponent; AParent: TFmxObject);
    destructor Destroy; override;
    procedure Clear;
    // Adds a line with a role (and, for a link, its tag and tooltip); returns
    // its number, from 1.
    function Add(const AText: string; ARole: TOutputRole; ATag: Integer = 0;
      const AHint: string = ''): Integer;
    // Appends text to the last line, such as the answer after input()'s
    // prompt.
    procedure AppendToLast(const AText: string);
    function Count: Integer;
    procedure BeginUpdate;
    procedure EndUpdate;
    procedure ScrollToEnd;
    procedure SetColors(AText, AError, ANote, ALink: TAlphaColor);
    property Editor: TSkiaCodeEditor read FEditor;
    property MaxLines: Integer read FMaxLines write FMaxLines;
    // The number of lines added since Clear, which, unlike line numbers, old
    // lines being dropped does not change: a line was the last one added
    // while Added is what it was just after that line's Add.
    property Added: Integer read FAdded;
    property OnLink: TOutputLinkEvent read FOnLink write FOnLink;
  end;

implementation

constructor TOutputPane.Create(AOwner: TComponent; AParent: TFmxObject);
begin
  inherited Create;
  FLines := TList<TLineInfo>.Create;
  FPending := TStringBuilder.Create;
  FPendingFrom := -1;
  FMaxLines := 10000;
  FColors[orText] := TAlphaColors.Black;
  FColors[orError] := $FFC62828;
  FColors[orNote] := $FF606060;
  FColors[orLink] := $FF1565C0;
  FColors[orInput] := $FF1565C0;
  FEditor :=TSkiaCodeEditor.Create(AOwner);
  FEditor.Parent := AParent;
  FEditor.Align := TAlignLayout.Client;
  FEditor.ReadOnly := True;
  FEditor.GutterVisible := False;
  FEditor.HighlightCurrentLine := False;
  FEditor.BracketMatching := False;
  FEditor.MarkersClearOnEdit := False;
  FEditor.WordWrap := False;
  FEditor.Monospace := True;
  FEditor.FontFamily := {$IFDEF MSWINDOWS}'Consolas'{$ELSE}'Menlo'{$ENDIF};
  FEditor.OnLineColor := LineColor;
  FEditor.OnLineClick := LineClick;
end;

destructor TOutputPane.Destroy;
begin
  // The editor belongs to its owner and may paint after this goes.
  FEditor.OnLineColor := nil;
  FEditor.OnLineClick := nil;
  FPending.Free;
  FLines.Free;
  inherited;
end;

procedure TOutputPane.Clear;
begin
  FPending.Clear;
  FPendingFrom := -1;
  FAdded := 0;
  FLines.Clear;
  FEditor.ClearMarkers;
  FEditor.SetText('');
end;

function TOutputPane.Count: Integer;
begin
  Result := FLines.Count;
end;

function TOutputPane.Add(const AText: string; ARole: TOutputRole; ATag: Integer;
  const AHint: string): Integer;
var
  Info: TLineInfo;
begin
  Info.Role := ARole;
  Info.Tag := ATag;
  Info.Hint := AHint;
  if FPendingFrom < 0 then
    FPendingFrom := FLines.Count;
  // Lines are joined by newlines, with none after the last, so the last line
  // is the latest output and AppendToLast can extend it.
  if FLines.Count > 0 then
    FPending.Append(#10);
  FPending.Append(AText);
  FLines.Add(Info);
  Inc(FAdded);
  Result := FLines.Count;
  if FUpdating = 0 then
    Flush;
end;

procedure TOutputPane.AppendToLast(const AText: string);
var
  Follow: Boolean;
begin
  Flush;
  if (AText = '') or (FLines.Count = 0) then
    Exit;
  Follow := FEditor.IsScrolledToEnd;
  FEditor.AppendText(AText);
  if Follow then
    FEditor.ScrollToEnd;
end;

procedure TOutputPane.BeginUpdate;
begin
  Inc(FUpdating);
end;

procedure TOutputPane.EndUpdate;
begin
  if FUpdating > 0 then
    Dec(FUpdating);
  if FUpdating = 0 then
    Flush;
end;

procedure TOutputPane.Flush;
var
  Follow: Boolean;
  Extra, From: Integer;
begin
  if FPendingFrom < 0 then
    Exit;
  From := FPendingFrom;
  FPendingFrom := -1;
  Follow := FEditor.IsScrolledToEnd;
  if FPending.Length > 0 then
    FEditor.AppendText(FPending.ToString);
  FPending.Clear;
  MarkLinks(From);
  Extra := FLines.Count - FMaxLines;
  if Extra > 0 then
  begin
    FEditor.DeleteLines(1, Extra);
    FLines.DeleteRange(0, Extra);
  end;
  if Follow then
    FEditor.ScrollToEnd;
end;

procedure TOutputPane.MarkLinks(AFrom: Integer);
var
  K: Integer;
begin
  for K := AFrom to FLines.Count - 1 do
    if FLines[K].Role = orLink then
      FEditor.AddMarker(K + 1, 1, 0, TMarkerKind.mkUnderline, FColors[orLink],
        FLines[K].Hint);
end;

procedure TOutputPane.ScrollToEnd;
begin
  Flush;
  FEditor.ScrollToEnd;
end;

procedure TOutputPane.SetColors(AText, AError, ANote, ALink: TAlphaColor);
begin
  FColors[orText] := AText;
  FColors[orError] := AError;
  FColors[orNote] := ANote;
  FColors[orLink] := ALink;
  FColors[orInput] := ALink;
  // The links' underlines take the new colour; setting the text colour
  // repaints, and the lines take theirs from LineColor.
  Flush;
  FEditor.ClearMarkers;
  MarkLinks(0);
  FEditor.TextColor := AText;
end;

procedure TOutputPane.LineColor(Sender: TObject; ALine: Integer; var AColor: TAlphaColor);
begin
  if (ALine >= 1) and (ALine <= FLines.Count) then
    AColor := FColors[FLines[ALine - 1].Role];
end;

procedure TOutputPane.LineClick(Sender: TObject; ALine, ACol: Integer);
begin
  if (ALine >= 1) and (ALine <= FLines.Count) and (FLines[ALine - 1].Role = orLink) and
     Assigned(FOnLink) then
    FOnLink(Self, FLines[ALine - 1].Tag);
end;

end.
