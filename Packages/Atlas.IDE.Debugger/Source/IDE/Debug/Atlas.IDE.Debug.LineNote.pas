unit Atlas.IDE.Debug.LineNote;

// Gemeinsame Basis der Anzeigen am Zeilenende mit Verlauf auf Klick (Laufzeit seit dem letzten Halt #579,
// Rückgabewerte #844):
//   - Zeichnen: am Ende der Zeile, die NoteText nennt, hinter den übrigen Anzeigen am Zeilenende
//     (TAtlasDebugLineEnd), gedimmt wie die Werte im Editor; nur solange der Zeilentext noch dem beim Halt
//     entspricht.
//   - Klick auf den Text: Menü mit Hinweis, Überschrift und den Zeilen von HistoryItems, erst nach dem Mausereignis
//     (sonst setzt der Editor den Cursor danach). Ist die Anzeige bis dahin abgebaut, entfällt das Menü.
// Die Basis meldet den Zeichner beim Editor an und vor den Destruktoren der Anzeigen wieder ab (BeforeDestruction,
// #493). Nur im Hauptthread verwenden.

interface

uses
  System.Types,
  System.Classes,
  Vcl.Controls,
  Vcl.Menus,
  ToolsAPI.Editor,
  Atlas.IDE.Debug.StopView,
  Atlas.UI.Debug.InlineValuePainter;

type
  TAtlasIdeDebugLineNote = class abstract(TAtlasIdeDebugStopView)
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedLineStages: TPaintLineStages; override;
    end;
  private class var
    /// <summary>Lebende Anzeigen: Ein eingereihtes Menü erreicht nur diese.</summary>
    FNotes: TArray<TAtlasIdeDebugLineNote>;
  private
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FStyle: TAtlasInlineValuePainter;
    FMenu: TPopupMenu;
    /// <summary>Gezeichneter Text, für den Klick; leer ohne.</summary>
    FHit: TRect;
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    procedure EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure ShowHistory(const APoint: TPoint);
    class function Alive(ANote: TAtlasIdeDebugLineNote): Boolean; static;
    class procedure QueueHistory(ANote: TAtlasIdeDebugLineNote; const APoint: TPoint); static;
  protected
    /// <summary>Text am Ende der Zeile ALine (ab 0) von AFileName, dazu der Text dieser Zeile beim Halt (ALineText);
    /// '' ohne.</summary>
    function NoteText(const AFileName: string; ALine: Integer; out ALineText: string): string; virtual; abstract;
    /// <summary>Steht gerade etwas am Zeilenende?</summary>
    function NoteShown: Boolean; virtual; abstract;
    /// <summary>Menü beim Klick: Hinweis (AHint, '' ohne), Überschrift und Zeilen des Verlaufs.</summary>
    procedure HistoryItems(out AHint, AHeader: string; out ALines: TArray<string>); virtual; abstract;
    /// <summary>Anzeige weg: Klickfläche vergessen.</summary>
    procedure ForgetHit;
  public
    constructor Create;
    destructor Destroy; override;
    procedure BeforeDestruction; override;
  end;

implementation

uses
  System.SysUtils,
  Atlas.IDE.Foundation.EditorCover,
  ToolsAPI,
  Atlas.Plugin.Diagnostics.Guard,
  Atlas.Plugin.Diagnostics.MainThread,
  Atlas.IDE.Debug.LineEnd;

{ TAtlasIdeDebugLineNote.TEvents }

function TAtlasIdeDebugLineNote.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintLineEvents, cevMouseEvents];
end;

function TAtlasIdeDebugLineNote.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TAtlasIdeDebugLineNote }

constructor TAtlasIdeDebugLineNote.Create;
var
  mServices: INTACodeEditorServices;
begin
  inherited Create;
  FIndex := -1;
  FStyle := TAtlasInlineValuePainter.Create;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintLine := PaintLine;
  FEvents.OnEditorMouseDown := EditorMouseDown;
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    FIndex := mServices.AddEditorEventsNotifier(FEventsRef);
  end;
  SetLength(FNotes, Length(FNotes) + 1);
  FNotes[High(FNotes)] := Self;
end;

procedure TAtlasIdeDebugLineNote.BeforeDestruction;
var
  mServices: INTACodeEditorServices;
  mIndex: Integer;
begin
  for mIndex := High(FNotes) downto 0 do
  begin
    if FNotes[mIndex] = Self then
    begin
      Delete(FNotes, mIndex, 1);
    end;
  end;
  // Erst abmelden, dann freigeben (#493): Kein Zeichnen erreicht eine halb abgebaute Anzeige.
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    mServices.RemoveEditorEventsNotifier(FIndex);
  end;
  FIndex := -1;
  if FEvents <> nil then
  begin
    FEvents.OnEditorPaintLine := nil;
    FEvents.OnEditorMouseDown := nil;
  end;
  FEventsRef := nil;
  FEvents := nil;
  inherited BeforeDestruction;
end;

destructor TAtlasIdeDebugLineNote.Destroy;
begin
  FreeAndNil(FMenu);
  FreeAndNil(FStyle);
  inherited Destroy;
end;

procedure TAtlasIdeDebugLineNote.ForgetHit;
begin
  FHit := Default(TRect);
end;

procedure TAtlasIdeDebugLineNote.PaintLine(const Rect: TRect; const Stage: TPaintLineStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  mX, mRight: Integer;
  mTailKey, mText, mLineText: string;
begin
  if TAtlasGuard.Disabled(TAtlasFeature.Debugger) or BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) then
  begin
    Exit;
  end;
  // Unter dem mitlaufenden Kopf nicht: Er deckt die Zeile ab, und wer nach ihm zeichnet, läge darüber.
  if TAtlasIdeEditorCover.Covers(Rect, Context) then
  begin
    Exit;
  end;
  try
    mText := NoteText(Context.FileName, Context.LogicalLineNum - 1, mLineText);
    if (mText = '') or not TAtlasDebugLineEnd.Matches(Context, mLineText) then
    begin
      Exit;
    end;
    // Hinter dem letzten Zeichen der Zeile bzw. hinter den übrigen Anzeigen am Zeilenende.
    mX := TAtlasDebugLineEnd.Start(Self, Context, Rect, mLineText, FStyle, mTailKey);
    mRight := FStyle.DrawText(Context.Canvas.Handle, Rect, mX, mText);
    TAtlasDebugLineEnd.Finish(Self, mTailKey, mRight);
    FHit := TRect.Create(mX, Rect.Top, mRight, Rect.Bottom);
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Debugger, E);
  end;
end;

class function TAtlasIdeDebugLineNote.Alive(ANote: TAtlasIdeDebugLineNote): Boolean;
var
  mNote: TAtlasIdeDebugLineNote;
begin
  Result := False;
  for mNote in FNotes do
  begin
    if mNote = ANote then
    begin
      Exit(True);
    end;
  end;
end;

class procedure TAtlasIdeDebugLineNote.QueueHistory(ANote: TAtlasIdeDebugLineNote; const APoint: TPoint);
begin
  TAtlasMainThread.ForceQueue(TAtlasFeature.Debugger,
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Debugger,
        procedure
        begin
          if Alive(ANote) then
          begin
            ANote.ShowHistory(APoint);
          end;
        end);
    end);
end;

procedure TAtlasIdeDebugLineNote.EditorMouseDown(const Editor: TWinControl; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if (Button <> mbLeft) or (Shift * [ssShift, ssCtrl, ssAlt] <> []) or FHit.IsEmpty or not NoteShown then
  begin
    Exit;
  end;
  if FHit.Contains(Point(X, Y)) then
  begin
    QueueHistory(Self, Editor.ClientToScreen(Point(X, Y)));
  end;
end;

/// <summary>Menüeintrag ohne Wirkung mit ACaption an AMenu anhängen.</summary>
procedure AddInfo(AMenu: TPopupMenu; const ACaption: string);
var
  mItem: TMenuItem;
begin
  mItem := TMenuItem.Create(AMenu);
  mItem.Caption := ACaption;
  mItem.Enabled := False;
  AMenu.Items.Add(mItem);
end;

procedure TAtlasIdeDebugLineNote.ShowHistory(const APoint: TPoint);
var
  mHint, mHeader, mLine: string;
  mLines: TArray<string>;
begin
  if FMenu = nil then
  begin
    FMenu := TPopupMenu.Create(nil);
  end;
  FMenu.Items.Clear;
  HistoryItems(mHint, mHeader, mLines);
  if mHint <> '' then
  begin
    AddInfo(FMenu, mHint);
    FMenu.Items.NewBottomLine;
  end;
  AddInfo(FMenu, mHeader);
  for mLine in mLines do
  begin
    AddInfo(FMenu, mLine);
  end;
  FMenu.Popup(APoint.X, APoint.Y);
end;

end.
