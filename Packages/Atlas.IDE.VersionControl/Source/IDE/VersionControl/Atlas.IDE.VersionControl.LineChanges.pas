unit Atlas.IDE.VersionControl.LineChanges;

// Änderungsmarken und Zeilenhistorie (#507) im Editor:
// - Ein Zeitgeber (150 ms) beobachtet die Datei im oberen Editor. Liegt sie
//   in einer Arbeitskopie (TAtlasIdeVcs, #571; Git oder SVN), holt Atlas im
//   Hintergrund ihren Stand im Repository (FileAt, Git HEAD, SVN BASE) und
//   vergleicht ihn nach einer Tipp-Pause (QuietMs) ebenfalls im Hintergrund
//   zeilenweise mit dem Puffer (TAtlasLineChanges). Ein Commit (andere
//   ChangeMarker) lädt den Stand neu. Ohne Arbeitskopie, ohne git bzw. svn
//   oder bei einer nicht versionierten Datei bleibt alles still.
// - Rinne (editor.gitGutter): am rechten Rand ein Balken je Zeile, grün
//   hinzugefügt, blau geändert, ein rotes Dreieck an der Zeile unter einer
//   Löschung (am Dateiende an der letzten Zeile). Farben aus dem Grund der
//   Rinne (TAtlasColors.ForBackground, passt zu hellem und dunklem Thema).
// - Klick auf eine Marke zeigt den alten Stand in einem kleinen Fenster
//   (TAtlasTitledTip) mit „Zurücksetzen“: Die Änderung geht über
//   TAtlasIdeWorkspaceEdit (#397) in den Puffer, Strg+Z nimmt sie zurück.
// - GoToChange springt reihum zur nächsten bzw. vorigen Änderung
//   (keys.nextChange, keys.previousChange).
// - Zeilenhistorie (editor.gitBlame): blame der Datei auf der Platte im
//   Hintergrund, neu nach dem Speichern und nach einem Commit. Am Ende der
//   Cursorzeile gedimmt „Autor, vor 3 Tagen · Betreff“; ungespeicherte Zeilen
//   ordnet der Vergleich Platte → Puffer zu („Noch nicht gespeichert“).
//   Überfahren zeigt den Commit mit Revision, Autor, Datum und Betreff.
//   Den Platz hinter dem Zeilenende teilt der Text mit Inlay-Hints,
//   Blockende-Beschriftungen und Fehlertext (TAtlasLineTail).
// - Beide Elemente lassen sich je Datei in .atlas ausblenden (#628).
// - Issues in der Zeilenhistorie (#1275) kommen über TAtlasBlameHooks aus der
//   Komposition (Atlas.IDE.Tracker.BlameLinks; der Editor kennt den Tracker
//   nicht): Messages lädt im Hintergrund nach jedem blame die ganzen
//   Nachrichten, Suffix hängt die Kennungen an die Randanzeige, Describe und
//   Link ergänzen den Hover. BlameAt sagt, welcher Commit unter der Maus
//   steht (Strg+Klick und Rechtsklick fängt der Tracker ab). Beim Zeichnen
//   fragt niemand den Tracker.
// Seit #1905 im Modul Versionsverwaltung: Der Teil des Moduls installiert die Marken und meldet sie über
// TAtlasLineChangesAdapter bei TAtlasLineChangeMarks (Atlas.IDE.Contracts.LineChanges) an; die Haken des Trackers
// liegen dort und kommen über BlameHooksChanged. Gezeichnet wird weiter hier (Balken am Rand der Rinne, Dreieck,
// Text hinter dem Zeilenende): IAtlasGutterLayer zeichnet nur Marken in der Rinne je Zeile.
// Gesichert über TAtlasFeature.LineChanges. Nur im Hauptthread.

interface

uses
  Winapi.Windows,
  System.SysUtils,
  Atlas.Core.Editor.LineChanges,
  Atlas.IDE.Contracts.LineChanges;

type
  TAtlasIdeLineChanges = class
  private class var
    FState: TObject;
    FMessage: TProc<string>;
    FHooks: TAtlasBlameHooks;
  public
    /// <summary>AMessage zeigt eine Zeile in der Meldungsansicht (etwa, wenn Zurücksetzen scheitert).</summary>
    class procedure Install(const AMessage: TProc<string>); static;
    class procedure Uninstall; static;
    class procedure ApplySettings; static;
    class procedure ThemeChanged; static;
    /// <summary>Cursor auf die erste Zeile der nächsten (AForward) bzw. vorigen Änderung, reihum.</summary>
    class procedure GoToChange(AForward: Boolean); static;
    /// <summary>Sind die Änderungsmarken eingeschaltet (für Palette und Tastenkürzel)?</summary>
    class function Enabled: Boolean; static;
    /// <summary>Letzter Vergleich für AFileName (Übersichtsleiste #519); False ohne (aus, andere Datei, keine
    /// Arbeitskopie).</summary>
    class function Snapshot(const AFileName: string; out AChanges: TAtlasLineChangeList;
      out ALineCount: Integer): Boolean; static;
    /// <summary>Ergänzungen der Zeilenhistorie (#1275) setzen bzw. mit Default(TAtlasBlameHooks) entfernen; lädt
    /// blame neu.</summary>
    class procedure SetBlameHooks(const AHooks: TAtlasBlameHooks); static;
    /// <summary>Commit der Randanzeige unter X, Y (Fensterkoordinaten von AWnd); False ohne, bei einer nicht
    /// gespeicherten oder nicht übernommenen Zeile und nach dem Scrollen.</summary>
    class function BlameAt(AWnd: HWND; AX, AY: Integer; out ACommit: TAtlasBlameCommit): Boolean; static;
    /// <summary>Hover der Zeilenhistorie neu aufbauen, falls er offen ist (Daten nachgeladen).</summary>
    class procedure RefreshBlameTip; static;
    class procedure HideBlameTip; static;
  end;

  /// <summary>Die Marken für Base und Tracker (IAtlasLineChanges, #1905).</summary>
  TAtlasLineChangesAdapter = class(TInterfacedObject, IAtlasLineChanges)
  public
    function Enabled: Boolean;
    procedure GoToChange(AForward: Boolean);
    function Snapshot(const AFileName: string; out AChanges: TAtlasLineChangeList; out ALineCount: Integer): Boolean;
    function BlameAt(AWnd: HWND; AX, AY: Integer; out ACommit: TAtlasBlameCommit): Boolean;
    procedure RefreshBlameTip;
    procedure HideBlameTip;
    procedure BlameHooksChanged;
  end;

implementation

uses
  Atlas.Core.VersionControl.Contract,
  System.Classes,
  System.Types,
  System.Math,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.ExtCtrls,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Style.Palette,
  Atlas.Core.Editor.Elements,
  Atlas.Core.Editor.LineTail,
  Atlas.UI.Strings,
  Atlas.UI.VersionControl.Strings,
  Atlas.UI.Popup.TitledTip,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Elements,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.VersionControl.LineChangesData,
  Atlas.IDE.VersionControl.LineChangesPaint,
  Atlas.UI.Foundation.EditorFont;

const
  cTickMs = 150;
  cHoverMs = 400;
  /// <summary>Abstand des Hinweises zum alten Text hinter dem Zeilenende, in Spalten.</summary>
  cTipColumnGap = 3;
  /// <summary>Abstand des Hinweises zur Markierung am Rand, in Pixeln.</summary>
  cTipGap = 4;

type
  TEvents = class(TNTACodeEditorNotifier)
  protected
    function AllowedEvents: TCodeEditorEvents; override;
    function AllowedGutterStages: TPaintGutterStages; override;
    function AllowedLineStages: TPaintLineStages; override;
  end;

  /// <summary>Gezeichnete Marke einer Rinnenzeile (Koordinaten des Editors).</summary>
  TMarkRow = record
    FileName: string;
    Line: Integer;
    Change: Integer;
    Rect: TRect;
    TopRow: Integer;
  end;

  /// <summary>Gezeichnete Randanzeige der Zeilenhistorie.</summary>
  TBlameMark = record
    Rect: TRect;
    TopRow: Integer;
    /// <summary>Eintrag von blame; -1 ohne.</summary>
    Entry: Integer;
    Unsaved: Boolean;
    Wnd: HWND;
    /// <summary>Zeile im Puffer, 0-basiert.</summary>
    Line: Integer;
  end;

  TLineChangesState = class
  private
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FTimer: TTimer;
    FTip: TAtlasTitledTip;
    FFont: TAtlasEditorFont;
    FGutterOn: Boolean;
    FBlameOn: Boolean;
    FData: TAtlasIdeLineChangesData;
    // Gezeichnete Marken je Bildschirmzeile und der Text der Historie.
    FRows: TDictionary<Integer, TMarkRow>;
    FBlame: TBlameMark;
    // Überfahren der Historie.
    FHovering: Boolean;
    FHoverSince: UInt64;
    FHoverScreen: TRect;
    // Fenster „alter Stand“: offen für diesen Block.
    FTipChange: Integer;
    FTipEntered: Boolean;
    procedure Tick(Sender: TObject);
    procedure Reset;
    procedure CheckHover;
    procedure ShowChange(AChange: Integer; const AScreen: TRect);
    procedure ShowCommit;
    procedure HideTip;
    procedure RevertChange(AChange: Integer);
    function CommitOf(AEntry, ALine: Integer): TAtlasBlameCommit;
    procedure PaintGutter(const Rect: TRect; const Stage: TPaintGutterStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    /// <summary>Balken und Dreieck der Zeile zeichnen und die Marke für den Klick merken.</summary>
    procedure PaintMarks(const ARect: TRect; const AContext: INTACodeEditorPaintContext; AMark: TAtlasLineMark;
      AChange, ADeleted: Integer);
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    /// <summary>Zeigt die Zeile von AContext die Zeilenhistorie (Cursorzeile, aktueller Vergleich)?</summary>
    function BlameWanted(AStage: TPaintLineStage; ABeforeEvent: Boolean;
      const AContext: INTACodeEditorPaintContext): Boolean;
    /// <summary>ACaption hinter das Zeilenende schreiben; liefert die belegte Fläche.</summary>
    function PaintBlame(const ARect: TRect; const AContext: INTACodeEditorPaintContext;
      const ACaption, ALineText: string): TRect;
    /// <summary>Marke unter X, Y, die noch dort steht (gleiche Datei, nicht gescrollt).</summary>
    function MarkAt(AX, AY: Integer; out ARow: TMarkRow): Boolean;
    procedure EditorMouseMove(const Editor: TWinControl; Shift: TShiftState; X, Y: Integer);
    procedure EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
  public
    constructor Create;
    destructor Destroy; override;
    procedure GoToChange(AForward: Boolean);
  end;

function Active: Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := (mSettings.GitGutter or mSettings.GitBlame) and not TAtlasGuard.Disabled(TAtlasFeature.LineChanges);
end;

function Current: TLineChangesState;
begin
  Result := TLineChangesState(TAtlasIdeLineChanges.FState);
end;

function TopView: IOTAEditView;
var
  mEditors: IOTAEditorServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    Result := mEditors.TopView;
  end;
end;

/// <summary>Ergänzungen der Zeilenhistorie für den Stand; lesen die Haken der Komposition erst beim Aufruf.</summary>
function DataHooks: TAtlasLineChangesHooks;
begin
  Result.Wanted :=
    function: Boolean
    var
      mHooks: TAtlasBlameHooks;
    begin
      mHooks := TAtlasIdeLineChanges.FHooks;
      Result := Assigned(mHooks.Wanted) and Assigned(mHooks.Messages) and mHooks.Wanted();
    end;
  Result.Loader :=
    function: TAtlasLineMessagesFunc
    var
      mHook: TAtlasBlameMessagesHook;
    begin
      // Im Hauptthread festhalten; der Lader läuft im Hintergrund.
      mHook := TAtlasIdeLineChanges.FHooks.Messages;
      Result :=
        function(const AVcs: IAtlasVersionControl; const AFileName: string;
          const ALines: TArray<TAtlasVcsBlameLine>): TArray<TAtlasVcsRevisionMessage>
        begin
          Result := nil;
          if Assigned(mHook) then
          begin
            Result := mHook(AVcs, AFileName, ALines);
          end;
        end;
    end;
  Result.Suffix :=
    function(AMessage: string): string
    begin
      Result := '';
      if Assigned(TAtlasIdeLineChanges.FHooks.Suffix) then
      begin
        Result := TAtlasIdeLineChanges.FHooks.Suffix(AMessage);
      end;
    end;
end;

{ TEvents }

function TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintGutterEvents, cevPaintLineEvents, cevMouseEvents];
end;

function TEvents.AllowedGutterStages: TPaintGutterStages;
begin
  // Nur die letzte Stufe: Die Marken liegen über dem, was die IDE gezeichnet hat.
  Result := [High(TPaintGutterStage)];
end;

function TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TLineChangesState }

constructor TLineChangesState.Create;
var
  mServices: INTACodeEditorServices;
begin
  inherited Create;
  FIndex := -1;
  FTipChange := -1;
  FBlame.Entry := -1;
  FData := TAtlasIdeLineChangesData.Create(DataHooks());
  FRows := TDictionary<Integer, TMarkRow>.Create;
  FFont := TAtlasEditorFont.Create([fsItalic]);
  FTip := TAtlasTitledTip.Create(nil);
  FTip.GuardFeature := TAtlasFeature.LineChanges;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintGutter := PaintGutter;
  FEvents.OnEditorPaintLine := PaintLine;
  FEvents.OnEditorMouseMove := EditorMouseMove;
  FEvents.OnEditorMouseDown := EditorMouseDown;
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    FIndex := mServices.AddEditorEventsNotifier(FEventsRef);
  end;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := cTickMs;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TLineChangesState.Destroy;
var
  mServices: INTACodeEditorServices;
begin
  FTimer.Free;
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    mServices.RemoveEditorEventsNotifier(FIndex);
  end;
  FEvents.OnEditorPaintGutter := nil;
  FEvents.OnEditorPaintLine := nil;
  FEvents.OnEditorMouseMove := nil;
  FEvents.OnEditorMouseDown := nil;
  FEventsRef := nil;
  FTip.OnLink := nil;
  FTip.Free;
  FFont.Free;
  FRows.Free;
  // Ergebnisse, die noch unterwegs sind, verfallen.
  FData.Free;
  TAtlasLineChangesPaint.Invalidate;
  inherited Destroy;
end;

procedure TLineChangesState.Reset;
begin
  FData.Reset;
  HideTip;
  FHovering := False;
  FBlame.Entry := -1;
  FRows.Clear;
end;

procedure TLineChangesState.Tick(Sender: TObject);
var
  mSettings: TAtlasPluginSettings;
  mView: IOTAEditView;
begin
  try
    mSettings := TAtlasIdeSettings.Current;
    FGutterOn := mSettings.GitGutter;
    FBlameOn := mSettings.GitBlame;
    mView := TopView;
    if (mView = nil) or (mView.Buffer = nil) or (mView.Buffer.FileName = '') then
    begin
      Exit;
    end;
    // Andere Datei vorn: neu beginnen.
    if not SameText(FData.FileName, mView.Buffer.FileName) then
    begin
      Reset;
      FData.Start(mView);
    end;
    // Der alte Stand im Fenster passt nicht mehr zum Puffer.
    if FData.Track(mView, FGutterOn, FBlameOn) and (FTipChange >= 0) then
    begin
      HideTip;
    end;
    CheckHover;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.LineChanges, E);
  end;
end;

function TLineChangesState.CommitOf(AEntry, ALine: Integer): TAtlasBlameCommit;
var
  mEntry: TAtlasVcsBlameLine;
begin
  mEntry := FData.Entry(AEntry);
  Result := Default(TAtlasBlameCommit);
  Result.FileName := FData.FileName;
  Result.Kind := FData.VcsKind;
  Result.Revision := mEntry.Revision;
  Result.Author := mEntry.Author;
  Result.Date := mEntry.Date;
  Result.Message := FData.MessageOf(mEntry);
  Result.Line := ALine;
end;

procedure TLineChangesState.PaintGutter(const Rect: TRect; const Stage: TPaintGutterStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  mLine, mIndex, mDeleted: Integer;
  mMark: TAtlasLineMark;
begin
  if BeforeEvent or (Stage <> High(TPaintGutterStage)) or (Context = nil) or (Context.EditView = nil) then
  begin
    Exit;
  end;
  if not FGutterOn or (FData.Changes = nil) or TAtlasGuard.Disabled(TAtlasFeature.LineChanges) or
    not SameText(Context.FileName, FData.FileName) then
  begin
    Exit;
  end;
  try
    mLine := Context.LogicalLineNum - 1;
    mMark := TAtlasLineChanges.MarkAt(FData.Changes, mLine, mIndex);
    mDeleted := TAtlasLineChanges.DeletedAt(FData.Changes, mLine, FData.LineCount);
    if (mMark = TAtlasLineMark.None) and (mDeleted < 0) then
    begin
      FRows.Remove(Context.EditorLineNum);
    end
    // In .atlas für diese Datei ausgeblendet (#628).
    else if not TAtlasIdeElements.FileHidden(TAtlasDrawnElement.GitGutter, Context.FileName) then
    begin
      PaintMarks(Rect, Context, mMark, mIndex, mDeleted);
    end;
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.LineChanges, E);
  end;
end;

procedure TLineChangesState.PaintMarks(const ARect: TRect; const AContext: INTACodeEditorPaintContext;
  AMark: TAtlasLineMark; AChange, ADeleted: Integer);
var
  mColors: TAtlasColors;
  mWidth, mLeft, mSize, mSaved: Integer;
  mBar: TRect;
  mDC: HDC;
  mRow: TMarkRow;
  mLineText: string;
begin
  mColors := TAtlasColors.ForBackground(TAtlasIdeStyle.SampleBack(AContext.Canvas, ARect.Left + 1, ARect.Top + 1));
  mWidth := Max(3, MulDiv(3, ARect.Height, 16));
  // Rechts in der Rinne, mit einem Pixel Abstand zum Code.
  mLeft := ARect.Right - mWidth - 2;
  mBar := TRect.Create(mLeft, ARect.Top, mLeft + mWidth, ARect.Bottom);
  mRow.Change := AChange;
  mDC := AContext.Canvas.Handle;
  mSaved := SaveDC(mDC);
  try
    if AMark = TAtlasLineMark.Added then
    begin
      TAtlasLineChangesPaint.FillBar(mDC, mBar, mColors.Add);
    end
    else if AMark <> TAtlasLineMark.None then
    begin
      TAtlasLineChangesPaint.FillBar(mDC, mBar, mColors.Accent);
    end;
    if ADeleted >= 0 then
    begin
      // Über der Zeile, am Dateiende unter der letzten Zeile.
      mSize := Max(4, ARect.Height div 3);
      TAtlasLineChangesPaint.PaintDeleted(mDC, mLeft, mSize, ARect,
        FData.Changes[ADeleted].Line >= FData.LineCount, mColors.Error);
      mBar.Right := Max(mBar.Right, mLeft + mSize);
      if AMark = TAtlasLineMark.None then
      begin
        mRow.Change := ADeleted;
      end;
    end;
  finally
    RestoreDC(mDC, mSaved);
  end;
  mRow.FileName := AContext.FileName;
  mRow.Line := AContext.LogicalLineNum - 1;
  // Etwas breiter als gezeichnet, damit der Klick leicht trifft.
  mRow.Rect := TRect.Create(mBar.Left - 2, ARect.Top, mBar.Right + 2, ARect.Bottom);
  mRow.TopRow := AContext.EditView.TopRow;
  FRows.AddOrSetValue(AContext.EditorLineNum, mRow);
  mLineText := '';
  if AContext.LineState <> nil then
  begin
    mLineText := AContext.LineState.Text;
  end;
  TAtlasIdeElements.Painted(TAtlasIdeElements.Target(TAtlasDrawnElement.GitGutter, AContext.FileName,
    mRow.Line, mLineText), mRow.Rect, mRow.TopRow, ARect.Height);
end;

function TLineChangesState.BlameWanted(AStage: TPaintLineStage; ABeforeEvent: Boolean;
  const AContext: INTACodeEditorPaintContext): Boolean;
begin
  // Nur die Cursorzeile, nur zum aktuellen Vergleich.
  Result := not ABeforeEvent and (AStage = plsEndPaint) and (AContext <> nil) and (AContext.EditView <> nil) and
    FBlameOn and FData.BlameOk and (AContext.EditView.CursorPos.Line = AContext.LogicalLineNum) and
    not TAtlasGuard.Disabled(TAtlasFeature.LineChanges) and SameText(AContext.FileName, FData.FileName) and
    FData.Fresh;
end;

function TLineChangesState.PaintBlame(const ARect: TRect; const AContext: INTACodeEditorPaintContext;
  const ACaption, ALineText: string): TRect;
var
  mCell: TRect;
  mKey: string;
  mX: Integer;
begin
  mCell := AContext.EditorState.GetCharacterPosPx(
    TAtlasLineChangesPaint.EndColumn(ALineText, TAtlasEditorBuffer.TabWidth(AContext.EditView.Buffer)) + cTipColumnGap,
    AContext.EditorLineNum);
  mKey := TAtlasLineTail.KeyOf(AContext.FileName, AContext.LogicalLineNum, AContext.EditorLineNum, ARect.Top);
  mX := TAtlasLineTail.Start(Self, mKey, mCell.Left);
  FFont.Follow(AContext.Canvas.Font);
  // Hintergrund des Editor-Farbschemas am rechten Rand (dort steht nichts).
  Result := TAtlasLineChangesPaint.PaintCaption(AContext.Canvas.Handle, ARect, mX, ACaption, FFont.Font.Handle,
    TAtlasIdeStyle.SampleBack(AContext.Canvas, ARect.Right - 2, ARect.Top + 1));
  TAtlasLineTail.Finish(Self, mKey, Result.Right);
end;

procedure TLineChangesState.PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
  var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  mLineText, mCaption: string;
  mEntry: Integer;
  mUnsaved: Boolean;
begin
  try
    if not BlameWanted(Stage, BeforeEvent, Context) or (Context.LineState = nil) or
      TAtlasIdeElements.FileHidden(TAtlasDrawnElement.GitBlame, Context.FileName) then
    begin
      Exit;
    end;
    mLineText := Context.LineState.Text;
    mCaption := FData.BlameCaption(Context.LogicalLineNum - 1, mEntry, mUnsaved);
    if mCaption = '' then
    begin
      Exit;
    end;
    FBlame.Rect := PaintBlame(Rect, Context, mCaption, mLineText);
    FBlame.TopRow := Context.EditView.TopRow;
    FBlame.Entry := mEntry;
    FBlame.Unsaved := mUnsaved;
    FBlame.Line := Context.LogicalLineNum - 1;
    FBlame.Wnd := 0;
    if Context.EditControl <> nil then
    begin
      FBlame.Wnd := Context.EditControl.Handle;
    end;
    TAtlasIdeElements.Painted(TAtlasIdeElements.Target(TAtlasDrawnElement.GitBlame, Context.FileName,
      FBlame.Line, mLineText), FBlame.Rect, FBlame.TopRow, Rect.Height);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.LineChanges, E);
  end;
end;

procedure TLineChangesState.EditorMouseMove(const Editor: TWinControl; Shift: TShiftState; X, Y: Integer);
var
  mView: IOTAEditView;
  mInside: Boolean;
begin
  try
    mView := TopView;
    mInside := FBlameOn and (FBlame.Entry >= 0) and not FBlame.Rect.IsEmpty and PtInRect(FBlame.Rect, Point(X, Y)) and
      (mView <> nil) and (mView.TopRow = FBlame.TopRow);
    if not mInside then
    begin
      if FHovering then
      begin
        FHovering := False;
        if FTipChange < 0 then
        begin
          HideTip;
        end;
      end;
      Exit;
    end;
    if FHovering then
    begin
      Exit;
    end;
    FHovering := True;
    FHoverSince := TThread.GetTickCount64;
    FHoverScreen := TRect.Create(Editor.ClientToScreen(FBlame.Rect.TopLeft),
      Editor.ClientToScreen(FBlame.Rect.BottomRight));
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.LineChanges, E);
  end;
end;

function TLineChangesState.MarkAt(AX, AY: Integer; out ARow: TMarkRow): Boolean;
var
  mRow: TMarkRow;
  mView: IOTAEditView;
begin
  ARow := Default(TMarkRow);
  Result := False;
  mView := TopView;
  if (mView = nil) or (mView.Buffer = nil) then
  begin
    Exit;
  end;
  for mRow in FRows.Values do
  begin
    if not Result and PtInRect(mRow.Rect, Point(AX, AY)) then
    begin
      ARow := mRow;
      Result := True;
    end;
  end;
  // Nur, wenn die Marke noch dort steht: gleiche Datei, nicht gescrollt.
  Result := Result and SameText(ARow.FileName, mView.Buffer.FileName) and (ARow.TopRow = mView.TopRow) and
    (ARow.Change >= 0) and (ARow.Change <= High(FData.Changes));
end;

procedure TLineChangesState.EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  mRow: TMarkRow;
  mScreen: TRect;
  mGen, mChange: Integer;
begin
  try
    HideTip;
    FHovering := False;
    if (Button <> mbLeft) or (Shift * [ssShift, ssCtrl, ssAlt] <> []) or not FGutterOn or not FData.Fresh or
      not MarkAt(X, Y, mRow) then
    begin
      Exit;
    end;
    mScreen := TRect.Create(Editor.ClientToScreen(mRow.Rect.TopLeft), Editor.ClientToScreen(mRow.Rect.BottomRight));
    mGen := TAtlasIdeLineChangesData.Generation;
    mChange := mRow.Change;
    // Erst nach dem Mausereignis: Der Editor setzt sonst danach den Cursor und schließt das Fenster.
    TAtlasMainThread.ForceQueue(TAtlasFeature.LineChanges,
      procedure
      var
        mState: TLineChangesState;
      begin
        mState := Current;
        if (mState <> nil) and (mGen = TAtlasIdeLineChangesData.Generation) and mState.FData.Fresh and
          (mChange <= High(mState.FData.Changes)) then
        begin
          mState.ShowChange(mChange, mScreen);
        end;
      end);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.LineChanges, E);
  end;
end;

procedure TLineChangesState.CheckHover;
var
  mInside: Boolean;
begin
  if FTip.IsShown and (FTipChange >= 0) then
  begin
    // Fenster „alter Stand“: zu, sobald die Maus es nach dem Betreten wieder verlässt.
    mInside := PtInRect(FTip.BoundsRect, Mouse.CursorPos);
    if mInside then
    begin
      FTipEntered := True;
    end
    else if FTipEntered then
    begin
      HideTip;
    end;
    Exit;
  end;
  if not FHovering then
  begin
    Exit;
  end;
  mInside := PtInRect(FHoverScreen, Mouse.CursorPos) or
    (FTip.IsShown and PtInRect(FTip.BoundsRect, Mouse.CursorPos));
  if not mInside then
  begin
    FHovering := False;
    HideTip;
  end
  else if not FTip.IsShown and (TThread.GetTickCount64 - FHoverSince >= cHoverMs) then
  begin
    ShowCommit;
  end;
end;

procedure TLineChangesState.ShowChange(AChange: Integer; const AScreen: TRect);
var
  mGen: Integer;
begin
  mGen := TAtlasIdeLineChangesData.Generation;
  FTip.OnLink :=
    procedure(AIndex: Integer)
    var
      mState: TLineChangesState;
    begin
      mState := Current;
      if (mState <> nil) and (mGen = TAtlasIdeLineChangesData.Generation) then
      begin
        mState.HideTip;
        mState.RevertChange(AChange);
      end;
    end;
  FTipChange := AChange;
  FTipEntered := False;
  TAtlasIdeStyle.Apply(FTip, AScreen);
  FTip.ShowNote(TAtlasVcsStrings.Text(TAtlasVcsTextId.ChangeOldTitle),
    TAtlasLineChangesPaint.OldText(FData.Changes[AChange]), [TAtlasVcsStrings.Text(TAtlasVcsTextId.ChangeRevert)],
    Point(AScreen.Right + cTipGap, AScreen.Top));
end;

procedure TLineChangesState.ShowCommit;
var
  mEntry: TAtlasVcsBlameLine;
  mTitle, mText: string;
  mLinks: TArray<string>;
  mCommit: TAtlasBlameCommit;
  mLink: TAtlasBlameLinkHook;
  mGen: Integer;
begin
  FHovering := not FBlame.Unsaved and FData.HasEntry(FBlame.Entry) and not FData.Entry(FBlame.Entry).Uncommitted;
  if not FHovering then
  begin
    Exit;
  end;
  mEntry := FData.Entry(FBlame.Entry);
  mTitle := TAtlasVcsStrings.Fmt(TAtlasVcsTextId.BlameCommitTitle, [mEntry.Revision]);
  mText := TAtlasIdeLineChangesData.CommitText(mEntry);
  FTipChange := -1;
  FTip.OnLink := nil;
  mLinks := nil;
  // Issues zur Nachricht (#1275): Zeilen mit Titel und Zustand, Links zu Vorschau und „Issues zu dieser Methode“.
  mCommit := CommitOf(FBlame.Entry, FBlame.Line);
  if Assigned(TAtlasIdeLineChanges.FHooks.Describe) and
    TAtlasIdeLineChanges.FHooks.Describe(mCommit, mText, mLinks) and (Length(mLinks) > 0) then
  begin
    mLink := TAtlasIdeLineChanges.FHooks.Link;
    mGen := TAtlasIdeLineChangesData.Generation;
    FTip.OnLink :=
      procedure(AIndex: Integer)
      var
        mState: TLineChangesState;
      begin
        mState := Current;
        if (mState = nil) or (mGen <> TAtlasIdeLineChangesData.Generation) then
        begin
          Exit;
        end;
        mState.FHovering := False;
        mState.HideTip;
        if Assigned(mLink) then
        begin
          mLink(mCommit, AIndex);
        end;
      end;
  end;
  TAtlasIdeStyle.Apply(FTip, FHoverScreen);
  FTip.ShowNote(mTitle, TrimRight(mText), mLinks, Point(FHoverScreen.Left, FHoverScreen.Bottom + 2));
end;

procedure TLineChangesState.HideTip;
begin
  FTipChange := -1;
  FTipEntered := False;
  if (FTip <> nil) and FTip.IsShown then
  begin
    FTip.HidePopup;
  end;
end;

procedure TLineChangesState.RevertChange(AChange: Integer);
var
  mError: string;
begin
  if FData.Revert(AChange, mError) and (mError <> '') and Assigned(TAtlasIdeLineChanges.FMessage) then
  begin
    TAtlasIdeLineChanges.FMessage(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [mError]));
  end;
end;

procedure TLineChangesState.GoToChange(AForward: Boolean);
var
  mView: IOTAEditView;
  mTarget: Integer;
begin
  mView := TopView;
  if not FGutterOn or (mView = nil) or (mView.Buffer = nil) or not SameText(mView.Buffer.FileName, FData.FileName) or
    not FData.Fresh then
  begin
    Exit;
  end;
  if TAtlasLineChanges.Next(FData.Changes, mView.CursorPos.Line - 1, FData.LineCount, AForward, mTarget) then
  begin
    TAtlasLineChangesPaint.GoToLine(FData.FileName, mTarget, FData.LineCount);
  end;
end;

{ TAtlasIdeLineChanges }

class function TAtlasIdeLineChanges.Enabled: Boolean;
begin
  Result := TAtlasIdeSettings.Current.GitGutter;
end;

class procedure TAtlasIdeLineChanges.Install(const AMessage: TProc<string>);
begin
  FMessage := AMessage;
  FreeAndNil(FState);
  if Active then
  begin
    FState := TLineChangesState.Create;
  end;
end;

class procedure TAtlasIdeLineChanges.Uninstall;
begin
  FreeAndNil(FState);
  FMessage := nil;
  // Danach hält das Modul keinen Haken des Trackers mehr.
  FHooks := Default(TAtlasBlameHooks);
end;

class procedure TAtlasIdeLineChanges.ApplySettings;
begin
  // Beide aus: kein Zeitgeber, kein Prozess, nichts gezeichnet.
  if not Active then
  begin
    FreeAndNil(FState);
    Exit;
  end;
  if FState = nil then
  begin
    FState := TLineChangesState.Create;
  end
  else
  begin
    TLineChangesState(FState).Reset;
    TAtlasLineChangesPaint.Invalidate;
  end;
end;

class procedure TAtlasIdeLineChanges.ThemeChanged;
begin
  // Die Farben kommen beim Zeichnen aus dem Grund der Rinne.
  if FState <> nil then
  begin
    TAtlasLineChangesPaint.Invalidate;
  end;
end;

class function TAtlasIdeLineChanges.Snapshot(const AFileName: string; out AChanges: TAtlasLineChangeList;
  out ALineCount: Integer): Boolean;
var
  mState: TLineChangesState;
begin
  AChanges := nil;
  ALineCount := 0;
  mState := Current;
  Result := (mState <> nil) and mState.FGutterOn and mState.FData.HeadOk and (mState.FData.LineCount > 0) and
    SameText(mState.FData.FileName, AFileName);
  if Result then
  begin
    AChanges := mState.FData.Changes;
    ALineCount := mState.FData.LineCount;
  end;
end;

class procedure TAtlasIdeLineChanges.SetBlameHooks(const AHooks: TAtlasBlameHooks);
begin
  FHooks := AHooks;
  // Randanzeige und Nachrichten passen zu den neuen Haken erst nach einem neuen blame.
  if FState <> nil then
  begin
    TLineChangesState(FState).Reset;
    TAtlasLineChangesPaint.Invalidate;
  end;
end;

class function TAtlasIdeLineChanges.BlameAt(AWnd: HWND; AX, AY: Integer; out ACommit: TAtlasBlameCommit): Boolean;
var
  mState: TLineChangesState;
  mView: IOTAEditView;
begin
  ACommit := Default(TAtlasBlameCommit);
  mState := Current;
  Result := (mState <> nil) and mState.FBlameOn and mState.FData.BlameOk and
    mState.FData.HasEntry(mState.FBlame.Entry) and not mState.FBlame.Unsaved and (AWnd <> 0) and
    (mState.FBlame.Wnd = AWnd) and not mState.FBlame.Rect.IsEmpty and PtInRect(mState.FBlame.Rect, Point(AX, AY));
  if not Result then
  begin
    Exit;
  end;
  // Nur, solange die Anzeige dort steht: gleiche Datei, nicht gescrollt, übernommene Zeile.
  mView := TopView;
  Result := (mView <> nil) and (mView.Buffer <> nil) and SameText(mView.Buffer.FileName, mState.FData.FileName) and
    (mView.TopRow = mState.FBlame.TopRow) and not mState.FData.Entry(mState.FBlame.Entry).Uncommitted;
  if Result then
  begin
    ACommit := mState.CommitOf(mState.FBlame.Entry, mState.FBlame.Line);
  end;
end;

class procedure TAtlasIdeLineChanges.RefreshBlameTip;
var
  mState: TLineChangesState;
begin
  mState := Current;
  if (mState <> nil) and mState.FHovering and mState.FTip.IsShown and (mState.FTipChange < 0) then
  begin
    mState.ShowCommit;
  end;
end;

class procedure TAtlasIdeLineChanges.HideBlameTip;
var
  mState: TLineChangesState;
begin
  mState := Current;
  if (mState <> nil) and (mState.FTipChange < 0) then
  begin
    mState.FHovering := False;
    mState.HideTip;
  end;
end;

class procedure TAtlasIdeLineChanges.GoToChange(AForward: Boolean);
begin
  if FState <> nil then
  begin
    TLineChangesState(FState).GoToChange(AForward);
  end;
end;

{ TAtlasLineChangesAdapter }

function TAtlasLineChangesAdapter.Enabled: Boolean;
begin
  Result := TAtlasIdeLineChanges.Enabled;
end;

procedure TAtlasLineChangesAdapter.GoToChange(AForward: Boolean);
begin
  TAtlasIdeLineChanges.GoToChange(AForward);
end;

function TAtlasLineChangesAdapter.Snapshot(const AFileName: string; out AChanges: TAtlasLineChangeList;
  out ALineCount: Integer): Boolean;
begin
  Result := TAtlasIdeLineChanges.Snapshot(AFileName, AChanges, ALineCount);
end;

function TAtlasLineChangesAdapter.BlameAt(AWnd: HWND; AX, AY: Integer; out ACommit: TAtlasBlameCommit): Boolean;
begin
  Result := TAtlasIdeLineChanges.BlameAt(AWnd, AX, AY, ACommit);
end;

procedure TAtlasLineChangesAdapter.RefreshBlameTip;
begin
  TAtlasIdeLineChanges.RefreshBlameTip;
end;

procedure TAtlasLineChangesAdapter.HideBlameTip;
begin
  TAtlasIdeLineChanges.HideBlameTip;
end;

procedure TAtlasLineChangesAdapter.BlameHooksChanged;
begin
  TAtlasIdeLineChanges.SetBlameHooks(TAtlasLineChangeMarks.BlameHooks);
end;

end.
