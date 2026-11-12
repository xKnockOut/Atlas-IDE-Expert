unit Atlas.IDE.Hover.Editor;

// Hover-Tooltip im Editor (#442) über die Code-Editor-API (ToolsAPI.Editor):
//   - Mausbewegung im Editor → Bezeichner unter der Maus (Zeile, Wortgrenzen).
//   - Nach 500 ms Verweilen auf demselben Bezeichner: textDocument/hover (im Hintergrund; die IDE wartet nie auf den
//   Server)
//     (TLspSession.HoverDataAt) und Tooltip unter dem Wort (Kurzform).
//   - Schließen 300 ms nachdem die Maus Bezeichner und Tooltip verlassen hat;
//     sofort bei Taste (außer Umschalt, Strg, Alt allein), Mausklick, Scrollen,
//     Größenänderung, IDE inaktiv (ein Wächter prüft das, solange der Tooltip
//     offen ist, #414).
// Navigation über Typen (#588):
//   - Klick auf einen Typ (Deklaration, Kette, Pfad) zeigt dessen Inhalt im
//     selben Fenster (Hover über den Fundort, TAtlasHoverHistory) und heftet
//     den Tooltip an: Dann schließt er nur mit Esc oder Klick in den Editor.
//   - Strg+Klick springt zur Deklaration und schließt.
//   - Tasten über den gemeinsamen Hook, solange der Tooltip sichtbar ist:
//     Esc schließt; angeheftet Rücktaste bzw. Alt+← zurück; angeheftet oder mit
//     der Maus über dem Tooltip F12, Umschalt+F12, Strg+C und F1 für den
//     angezeigten Typ.
// Probleme (#398): Liegt unter der Maus ein Problem, zeigt der Tooltip es oben
// an, auch ohne Bezeichner (dann nur das Problem). Aktionen unter einem
// uses-Hinweis (#621) gehen über OnProblemAction mit der Kennung der
// Code-Aktion (uses.remove, uses.removeAll, uses.move) an die Befehle.
// Befund-Hover (#909): Die Aktionszeile unter Regelbefunden
// (hover.problemActions) meldet rule.fix, rule.suppressLine und
// rule.configure (öffnet die Einstellungsseite auf der Regel). Angeheftet oder
// mit der Maus über dem Tooltip wendet Alt+Enter die Korrektur an, Tab und
// Umschalt+Tab markieren die Aktionen, Enter löst die markierte aus.
// Debuggen (#891): Ist der Prozess angehalten, wertet Atlas den Ausdruck unter
// der Maus über den Debugger der IDE aus (TAtlasIdeDebugValues) und zeigt den
// Wert ganz oben; ohne Antwort des Servers nur den Wert. Antwortet der Debugger
// verzögert, steht dort „wird ausgewertet …“, bis der Wert kommt. Schalter
// debug.hoverValues (DebugHoverValues). Für Listen, Datenmengen, Farben und
// die anderen Arten aus debug.visualizers.types bereiten die Visualisierer
// (#835) den Wert auf, sobald der Server den Typ gemeldet hat; das gilt auch
// unter Win64, wo die Visualisierer der IDE nicht laufen. Den Ersatztext gibt
// OnVisualize (die Debug-Schicht setzt es, der Tooltip kennt sie nicht).
// debug.hoverValues (DebugHoverValues). Scheitert die Auswertung mit „kein
// Zugriff“, erklärt OnExplain die Ursache (#840; die Debug-Schicht setzt es,
// der Tooltip kennt sie nicht), Klicks auf ihre Korrekturen gehen an
// OnDebugFix.
// Die IDE zeigt dann keinen eigenen Tooltip: GetHintText und GetHelpInsightHtml
// liefern '' (Manager). Bedient Atlas die Datei nicht (Hauptschalter, Server
// fehlt, Sicherung), übernimmt die IDE und der Atlas-Tooltip bleibt zu.
// Delphi 12 (#281): Tastatur-Ereignisse des Code-Editors gibt es erst ab
// Delphi 13 (INTACodeEditorEvents370). Dort schließt der Tooltip über den
// Tastatur-Hook, solange er sichtbar ist.
interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.ExtCtrls,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Hover.Contract,
  Atlas.Core.Editor.CloseRules,
  Atlas.IDE.Foundation.KeyHook,
  Atlas.IDE.Hover.EditorContent;

type
  /// <summary>Stelle unter der Maus im Editor: Zeile (1-basiert), Spalte und sichtbare Zeile des Editors, Index im
  /// Zeilentext (0-basiert).</summary>
  TAtlasHoverMousePos = record
    State: INTACodeEditorState;
    Editor: TWinControl;
    View: IOTAEditView;
    Line: Integer;
    Column: Integer;
    VisibleLine: Integer;
    Index: Integer;
    Text: string;
  end;

  TAtlasEditorHover = class(TAtlasEditorHoverActions)
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
    end;

    THoverKeys = class(TAtlasKeyClient)
    private
      FOwner: TAtlasEditorHover;
    protected
      function WantsKey(AKey: Word; AShift: TShiftState): Boolean; override;
      procedure HandleKey(AKey: Word; AShift: TShiftState); override;
    public
      constructor Create(AOwner: TAtlasEditorHover);
    end;
  public const
    /// <summary>Nach Vervollständigung (0) und Parameter-Hint (10).</summary>
    cKeyPriority = 20;
  private
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FKeys: THoverKeys;
    FShowTimer: TTimer;
    FHideTimer: TTimer;
    FWatchTimer: TTimer;
    // Anfrage an den Server im Hintergrund: Die IDE friert nie ein, auch wenn er langsam ist.
    // FRequest zählt die Anfragen; nur die jüngste wird angezeigt.
    FRequest: Integer;
    FWorkers: TList<TThread>;
    // Fenster beim Anzeigen (Fokus, Datei, oberste Zeile); TAtlasCloseRules vergleicht damit.
    FShown: TAtlasEditorWindowState;
    function WindowState: TAtlasEditorWindowState;
    procedure EditorMouseMove(const Editor: TWinControl; Shift: TShiftState; X, Y: Integer);
    /// <summary>Stelle unter der Maus in einer Datei, die Atlas bedient; False sonst.</summary>
    function MousePos(const AEditor: TWinControl; AX, AY: Integer; out APos: TAtlasHoverMousePos): Boolean;
    /// <summary>Schlüssel des Bezeichners an APos ('' ohne); ein neuer setzt Wort, Ausdruck und Wortrechteck.
    /// </summary>
    function WordKey(const APos: TAtlasHoverMousePos): string;
    /// <summary>Schlüssel eines Problems ohne Bezeichner an APos ('' ohne), etwa ein fehlendes Semikolon.</summary>
    function ProblemKey(const APos: TAtlasHoverMousePos): string;
    /// <summary>Zeitgeber nach dem Schlüssel unter der Maus: anzeigen, offen lassen oder schließen.</summary>
    procedure TrackKey(const AKey: string);
    procedure EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    {$IF CompilerVersion >= 37.0}
    procedure EditorKeyDown(const Editor: TWinControl; Key: Word; Shift: TShiftState; var Handled: Boolean);
    {$ENDIF}
    procedure EditorScrolled(const Editor: TWinControl; const Direction: TCodeEditorScrollDirection);
    procedure EditorResized(const Editor: TWinControl);
    procedure ShowData(const AData: TAtlasHoverData);
    procedure ReapWorkers(AWait: Boolean);
    procedure ShowTimerTick(Sender: TObject);
    /// <summary>textDocument/hover im Hintergrund; das Ergebnis zeigt ShowData im Hauptthread.</summary>
    procedure RequestHover(ASession: TLspSession);
    procedure HideTimerTick(Sender: TObject);
    procedure WatchTimerTick(Sender: TObject);
    function WantsKey(AKey: Word; AShift: TShiftState): Boolean;
    /// <summary>Kürzel, die nur gelten, wenn der Tooltip gemeint ist (angeheftet oder Maus darüber).</summary>
    function WantsTipKey(AKey: Word; AShift: TShiftState): Boolean;
    procedure HandleKey(AKey: Word; AShift: TShiftState);
  public
    constructor Create(const ASession: TAtlasHoverSessionFunc; const ALog: TAtlasHoverLogFunc;
      const AProblemsAt: TAtlasHoverProblemsFunc; const AHandles: TAtlasHoverHandlesFunc); overload;
    /// <summary>Wie oben mit AHandles = nil.</summary>
    constructor Create(const ASession: TAtlasHoverSessionFunc; const ALog: TAtlasHoverLogFunc;
      const AProblemsAt: TAtlasHoverProblemsFunc); overload;
    /// <summary>Wie oben ohne Probleme (AProblemsAt = nil, AHandles = nil).</summary>
    constructor Create(const ASession: TAtlasHoverSessionFunc; const ALog: TAtlasHoverLogFunc); overload;
    destructor Destroy; override;
    procedure Hide; override;
    /// <summary>Laufende Anfragen abwarten, bevor die Sitzung wegfällt (Neustart, Abschalten).
    /// Ihre Ergebnisse zeigt der Tooltip nicht mehr. Nur im Hauptthread.</summary>
    procedure Shutdown;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Winapi.Windows,
  Vcl.Forms,
  Atlas.Core.Completion.Word,
  Atlas.Core.Hover.DebugValue,
  Atlas.Core.Hover.Layout,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Hover.DebugValue;

{ TAtlasEditorHover.TEvents }

function TAtlasEditorHover.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevWindowEvents, cevMouseEvents];
  {$IF CompilerVersion >= 37.0}
  Include(Result, cevKeyboardEvents);
  {$ENDIF}
end;

{ TAtlasEditorHover.THoverKeys }

constructor TAtlasEditorHover.THoverKeys.Create(AOwner: TAtlasEditorHover);
begin
  inherited Create(cKeyPriority);
  FOwner := AOwner;
end;

function TAtlasEditorHover.THoverKeys.WantsKey(AKey: Word; AShift: TShiftState): Boolean;
begin
  Result := FOwner.WantsKey(AKey, AShift);
  {$IF CompilerVersion < 37.0}
  // Ohne Tastatur-Ereignisse des Editors: andere Tasten schließen nach der Verarbeitung (wie EditorKeyDown).
  if not Result and (AKey <> VK_SHIFT) and (AKey <> VK_CONTROL) and (AKey <> VK_MENU) and
    not FOwner.FHistory.Pinned then
  begin
    TAtlasMainThread.ForceQueue(TAtlasFeature.Hover,
      procedure
      begin
        FOwner.Hide;
      end);
  end;
  {$ENDIF}
end;

procedure TAtlasEditorHover.THoverKeys.HandleKey(AKey: Word; AShift: TShiftState);
begin
  try
    FOwner.HandleKey(AKey, AShift);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Hover, E);
  end;
end;

/// <summary>Zurück im angehefteten Tooltip: Rücktaste oder Alt+Links.</summary>
function IsBackKey(AKey: Word; AShift: TShiftState): Boolean;
begin
  Result := ((AKey = VK_BACK) and (AShift = [])) or ((AKey = VK_LEFT) and (AShift = [ssAlt]));
end;

function NoneOrShift(AShift: TShiftState): Boolean;
begin
  Result := (AShift = []) or (AShift = [ssShift]);
end;

/// <summary>Kürzel der Aktionsleiste mit Fundort: F12/Umschalt+F12, Strg+C, F1 nur mit Hilfe.</summary>
function ActionKey(AKey: Word; AShift: TShiftState; AHasHelp: Boolean): Boolean;
begin
  Result := ((AKey = VK_F12) and NoneOrShift(AShift)) or ((AKey = Ord('C')) and (AShift = [ssCtrl])) or
    ((AKey = VK_F1) and (AShift = []) and AHasHelp);
end;

{ TAtlasEditorHover }

constructor TAtlasEditorHover.Create(const ASession: TAtlasHoverSessionFunc; const ALog: TAtlasHoverLogFunc;
  const AProblemsAt: TAtlasHoverProblemsFunc);
begin
  Create(ASession, ALog, AProblemsAt, nil);
end;

constructor TAtlasEditorHover.Create(const ASession: TAtlasHoverSessionFunc; const ALog: TAtlasHoverLogFunc);
begin
  Create(ASession, ALog, nil, nil);
end;

constructor TAtlasEditorHover.Create(const ASession: TAtlasHoverSessionFunc; const ALog: TAtlasHoverLogFunc;
  const AProblemsAt: TAtlasHoverProblemsFunc; const AHandles: TAtlasHoverHandlesFunc);
var
  mServices: INTACodeEditorServices;
begin
  inherited Create(ASession, ALog, AProblemsAt, AHandles);
  FIndex := -1;
  FKeys := THoverKeys.Create(Self);
  FWorkers := TList<TThread>.Create;
  FShowTimer := TTimer.Create(nil);
  FShowTimer.Enabled := False;
  FShowTimer.Interval := TAtlasCloseRules.cTooltipShowDelayMs;
  FShowTimer.OnTimer := ShowTimerTick;
  FHideTimer := TTimer.Create(nil);
  FHideTimer.Enabled := False;
  FHideTimer.Interval := TAtlasCloseRules.cTooltipHideDelayMs;
  FHideTimer.OnTimer := HideTimerTick;
  FWatchTimer := TTimer.Create(nil);
  FWatchTimer.Enabled := False;
  FWatchTimer.Interval := 250;
  FWatchTimer.OnTimer := WatchTimerTick;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorMouseMove := EditorMouseMove;
  FEvents.OnEditorMouseDown := EditorMouseDown;
  {$IF CompilerVersion >= 37.0}
  FEvents.OnEditorKeyDown := EditorKeyDown;
  {$ENDIF}
  FEvents.OnEditorScrolled := EditorScrolled;
  FEvents.OnEditorResized := EditorResized;
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    FIndex := mServices.AddEditorEventsNotifier(FEventsRef);
  end;
end;

destructor TAtlasEditorHover.Destroy;
var
  mServices: INTACodeEditorServices;
begin
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    mServices.RemoveEditorEventsNotifier(FIndex);
  end;
  TAtlasKeyHook.Remove(FKeys);
  if FEvents <> nil then
  begin
    FEvents.OnEditorMouseMove := nil;
    FEvents.OnEditorMouseDown := nil;
    {$IF CompilerVersion >= 37.0}
    FEvents.OnEditorKeyDown := nil;
    {$ENDIF}
    FEvents.OnEditorScrolled := nil;
    FEvents.OnEditorResized := nil;
  end;
  FEventsRef := nil;
  // Laufende Anfragen zeigen nichts mehr; auf sie warten, bevor die Sitzung wegfällt.
  if FAlive <> nil then
  begin
    FAlive.Alive := False;
  end;
  ReapWorkers(True);
  FWorkers.Free;
  FShowTimer.Free;
  FHideTimer.Free;
  FWatchTimer.Free;
  FKeys.Free;
  inherited Destroy;
end;

procedure TAtlasEditorHover.Hide;
begin
  FWatchTimer.Enabled := False;
  FShowTimer.Enabled := False;
  FHideTimer.Enabled := False;
  TAtlasKeyHook.Remove(FKeys);
  inherited Hide;
end;

procedure TAtlasEditorHover.Shutdown;
begin
  // Eingereihte Ergebnisse veralten (Show vergleicht FRequest); die Arbeiter halten die Sitzung als rohen Zeiger.
  // Ohne Hide: Der Tooltip zeigt kopierte Daten, ein Neustart soll ihn nicht schließen.
  Inc(FRequest);
  ReapWorkers(True);
end;

procedure TAtlasEditorHover.EditorMouseMove(const Editor: TWinControl; Shift: TShiftState; X, Y: Integer);
var
  mPos: TAtlasHoverMousePos;
  mKey: string;
begin
  // Durch die Sicherung abgeschaltet (#493).
  if TAtlasGuard.Disabled(TAtlasFeature.Hover) then
  begin
    Exit;
  end;
  try
    if not TAtlasIdeSettings.Current.Enabled or not TAtlasIdeSettings.Current.HoverTooltip then
    begin
      Exit;
    end;
    // Angeheftet: Der Tooltip bleibt, bis Esc oder ein Klick in den Editor ihn schließt (#588).
    if FHistory.Pinned and FTip.IsShown then
    begin
      Exit;
    end;
    mKey := '';
    if MousePos(Editor, X, Y, mPos) then
    begin
      mKey := WordKey(mPos);
      if mKey = '' then
      begin
        mKey := ProblemKey(mPos);
      end;
    end;
    TrackKey(mKey);
  except
    on E: Exception do
    begin
      Log('Hover: ' + E.Message);
      TAtlasGuard.Report(TAtlasFeature.Hover, E);
    end;
  end;
end;

function TAtlasEditorHover.MousePos(const AEditor: TWinControl; AX, AY: Integer; out APos: TAtlasHoverMousePos):
  Boolean;
var
  mServices: INTACodeEditorServices;
begin
  APos := Default(TAtlasHoverMousePos);
  APos.Editor := AEditor;
  Result := Supports(BorlandIDEServices, INTACodeEditorServices, mServices);
  if Result then
  begin
    APos.State := mServices.EditorState[AEditor];
    Result := (APos.State <> nil) and APos.State.PointToCharacterPos(Point(AX, AY), APos.Column, APos.VisibleLine);
  end;
  if not Result then
  begin
    Exit;
  end;
  APos.View := APos.State.View;
  APos.Line := APos.State.LineState[APos.VisibleLine].LogicalLineNum;
  // Nur, wo Atlas die Code Insight übernimmt; sonst zeigt die IDE ihren Tooltip, und es wären zwei.
  Result := (APos.View <> nil) and (APos.View.Buffer <> nil) and (APos.Line > 0) and
    Handles(APos.View.Buffer.FileName);
  if Result then
  begin
    APos.Text := TAtlasEditorBuffer.LineText(APos.View, APos.Line);
    APos.Index := TLspSession.ColumnToIndex(APos.Text, APos.Column, TAtlasEditorBuffer.TabWidth(APos.View.Buffer));
  end;
end;

function TAtlasEditorHover.WordKey(const APos: TAtlasHoverMousePos): string;
var
  mStart, mStop: Integer;
  mFirst, mLast: TRect;
begin
  Result := '';
  if (APos.Index >= Length(APos.Text)) or not TAtlasWord.IsIdentifierChar(APos.Text[APos.Index + 1]) or
    CharInSet(APos.Text[TAtlasWord.StartBefore(APos.Text, APos.Index + 1) + 1], ['0'..'9']) then
  begin
    Exit;
  end;
  mStart := TAtlasWord.StartBefore(APos.Text, APos.Index + 1);
  mStop := TAtlasWord.EndAfter(APos.Text, APos.Index);
  Result := Format('%s|%d|%d', [APos.View.Buffer.FileName, APos.Line, mStart]);
  if Result = FKey then
  begin
    Exit;
  end;
  FEditor := APos.Editor;
  FView := APos.View;
  FLine := APos.Line;
  FStart := mStart;
  FMouseCharacter := APos.Index;
  FProblemsOnly := False;
  FDebugExpression := '';
  if TAtlasIdeSettings.Current.DebugHoverValues and TAtlasIdeDebugValues.Stopped then
  begin
    FDebugExpression := TAtlasDebugExpression.At(APos.Text, mStart, mStop);
  end;
  // Wortrechteck aus der ersten und letzten Spalte des Worts (Bildschirmkoordinaten).
  mFirst := APos.State.GetCharacterPosPx(APos.Column - (APos.Index - mStart), APos.VisibleLine);
  mLast := APos.State.GetCharacterPosPx(APos.Column + (mStop - APos.Index - 1), APos.VisibleLine);
  FWordRect := TRect.Create(APos.Editor.ClientToScreen(mFirst.TopLeft), APos.Editor.ClientToScreen(mLast.BottomRight));
end;

function TAtlasEditorHover.ProblemKey(const APos: TAtlasHoverMousePos): string;
var
  mFirst: TRect;
begin
  Result := '';
  if not Assigned(FProblemsAt) or (Length(FProblemsAt(APos.View.Buffer.FileName, APos.Line - 1, APos.Index)) = 0)
  then
  begin
    Exit;
  end;
  // Kein Bezeichner, aber ein Problem (etwa ein fehlendes Semikolon): nur das Problem zeigen.
  Result := Format('%s|%d|p%d', [APos.View.Buffer.FileName, APos.Line, APos.Index]);
  if Result = FKey then
  begin
    Exit;
  end;
  FEditor := APos.Editor;
  FView := APos.View;
  FLine := APos.Line;
  FStart := APos.Index;
  FMouseCharacter := APos.Index;
  FProblemsOnly := True;
  FDebugExpression := '';
  mFirst := APos.State.GetCharacterPosPx(APos.Column, APos.VisibleLine);
  FWordRect := TRect.Create(APos.Editor.ClientToScreen(mFirst.TopLeft),
    APos.Editor.ClientToScreen(mFirst.BottomRight));
end;

procedure TAtlasEditorHover.TrackKey(const AKey: string);
begin
  if AKey = '' then
  begin
    // Kein Bezeichner: offenen Tooltip nach 300 ms schließen, wartenden verwerfen.
    FShowTimer.Enabled := False;
    FKey := '';
    FHideTimer.Enabled := FHideTimer.Enabled or FTip.IsShown;
  end
  else if AKey = FShownKey then
  begin
    FHideTimer.Enabled := False;
  end
  else if AKey <> FKey then
  begin
    FKey := AKey;
    FShowTimer.Enabled := False;
    FShowTimer.Enabled := True;
    FHideTimer.Enabled := FHideTimer.Enabled or FTip.IsShown;
  end;
end;

procedure TAtlasEditorHover.ReapWorkers(AWait: Boolean);
var
  mIndex: Integer;
begin
  for mIndex := FWorkers.Count - 1 downto 0 do
  begin
    if AWait or FWorkers[mIndex].Finished then
    begin
      FWorkers[mIndex].WaitFor;
      FWorkers[mIndex].Free;
      FWorkers.Delete(mIndex);
    end;
  end;
end;

procedure TAtlasEditorHover.ShowTimerTick(Sender: TObject);
var
  mSession: TLspSession;
begin
  // Durch die Sicherung abgeschaltet (#493).
  if TAtlasGuard.Disabled(TAtlasFeature.Hover) then
  begin
    Exit;
  end;
  FShowTimer.Enabled := False;
  try
    if (FView = nil) or (FKey = '') or not Application.Active then
    begin
      Exit;
    end;
    FProblems := nil;
    if Assigned(FProblemsAt) then
    begin
      FProblems := FProblemsAt(FView.Buffer.FileName, FLine - 1, FMouseCharacter);
    end;
    EvaluateDebugValue;
    mSession := nil;
    if not FProblemsOnly then
    begin
      mSession := CurrentSession;
    end;
    if mSession = nil then
    begin
      ShowData(Default(TAtlasHoverData));
    end
    else
    begin
      RequestHover(mSession);
    end;
  except
    on E: Exception do
    begin
      Log('Hover: ' + E.Message);
      TAtlasGuard.Report(TAtlasFeature.Hover, E);
    end;
  end;
end;

procedure TAtlasEditorHover.RequestHover(ASession: TLspSession);
var
  mText, mFileName, mKey: string;
  mLine, mCharacter, mRequest: Integer;
  mOwner: TAtlasEditorHover;
  mAlive: TAtlasHoverAlive;
  mAliveRef: IInterface;
  mWorker: TThread;
begin
  // Im Hauptthread: Die Sitzung führt ihre Dokumentstände nicht threadsicher.
  mText := TAtlasEditorBuffer.Text(FView.Buffer);
  mFileName := FView.Buffer.FileName;
  ASession.Sync(mFileName, mText);
  ReapWorkers(False);
  Inc(FRequest);
  mRequest := FRequest;
  mKey := FKey;
  mLine := FLine - 1;
  mCharacter := FStart;
  mOwner := Self;
  mAlive := FAlive;
  mAliveRef := FAliveRef;
  mWorker := TThread.CreateAnonymousThread(
    procedure
    var
      mData: TAtlasHoverData;
      mShow: TThreadProcedure;
    begin
      mData := Default(TAtlasHoverData);
      try
        mData := ASession.HoverDataAt(mFileName, mLine, mCharacter, 0);
      except
        // Server langsam oder weg: kein Tooltip, die IDE wartet nie darauf.
        mData := Default(TAtlasHoverData);
      end;
      mShow :=
        procedure
        begin
          // Nur die jüngste Anfrage und nur, solange die Maus noch auf demselben Wort steht.
          if not mAlive.Alive or (mAliveRef = nil) or (mOwner.FRequest <> mRequest) or (mOwner.FKey <> mKey) then
          begin
            Exit;
          end;
          TAtlasGuard.Run(TAtlasFeature.Hover,
            procedure
            begin
              mOwner.ShowData(mData);
            end);
        end;
      // Atlas gehört der Eintrag: beim Entladen verworfen, übersteht aber ReapWorkers.
      TAtlasMainThread.Queue(TAtlasFeature.Hover, mShow);
    end);
  mWorker.FreeOnTerminate := False;
  FWorkers.Add(mWorker);
  mWorker.Start;
end;

procedure TAtlasEditorHover.ShowData(const AData: TAtlasHoverData);
begin
  if (FView = nil) or not Application.Active or not MouseOverEditor then
  begin
    Exit;
  end;
  if not AData.Found and (Length(FProblems) = 0) and not FDebugValue.Visible then
  begin
    Hide;
    Exit;
  end;
  FHistory.Start(AData);
  FUsagesCount := -1;
  TAtlasIdeStyle.Apply(FTip, FWordRect);
  FTip.ProblemActions := TAtlasIdeSettings.Current.HoverProblemActions;
  FTip.HideCompilerCode := not TAtlasIdeSettings.Current.ProblemsShowCompilerCode;
  FTip.MembersMaxLines := TAtlasIdeSettings.Current.HoverMembersMaxLines;
  FTip.SignatureParams := TAtlasIdeSettings.Current.HoverSignatureParams;
  FTip.ShowContent(CurrentView, FWordRect);
  TAtlasKeyHook.Add(FKeys);
  FShownKey := FKey;
  FShown := WindowState;
  FHideTimer.Enabled := False;
  FWatchTimer.Enabled := True;
end;

function TAtlasEditorHover.WindowState: TAtlasEditorWindowState;
var
  mView: IOTAEditView;
begin
  Result := Default(TAtlasEditorWindowState);
  Result.AppActive := Application.Active;
  Result.Focus := GetFocus;
  mView := CurrentEditView;
  if mView = nil then
  begin
    Exit;
  end;
  Result.TopRow := mView.TopRow;
  Result.Rows := mView.ViewSize.cy;
  if mView.Buffer <> nil then
  begin
    Result.FileName := mView.Buffer.FileName;
  end;
end;

procedure TAtlasEditorHover.WatchTimerTick(Sender: TObject);
begin
  try
    // Andere Anwendung im Vordergrund, anderer Editor-Tab, Fokus woanders in der IDE (Objektinspektor,
    // Projektverwaltung …), gescrollt (#414). Größe und Scrollen melden zusätzlich die Editor-Ereignisse.
    if not FTip.IsShown then
    begin
      FWatchTimer.Enabled := False;
    end
    else if TAtlasCloseRules.Tooltip(FShown, WindowState, FHistory.Pinned, MouseOverTip) <>
      TAtlasCloseReason.None then
    begin
      Hide;
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Hover, E);
  end;
end;

procedure TAtlasEditorHover.HideTimerTick(Sender: TObject);
begin
  try
    FHideTimer.Enabled := False;
    // Angeheftet bleibt der Tooltip; sonst darf die Maus in den Tooltip wandern (#442).
    if FTip.IsShown and (FHistory.Pinned or MouseOverTip) and Application.Active then
    begin
      if not FHistory.Pinned then
      begin
        FHideTimer.Enabled := True;
      end;
      Exit;
    end;
    Hide;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Hover, E);
  end;
end;


function TAtlasEditorHover.WantsKey(AKey: Word; AShift: TShiftState): Boolean;
begin
  if not FTip.IsShown then
  begin
    Exit(False);
  end;
  Result := ((AKey = VK_ESCAPE) and (AShift = [])) or
    (FHistory.Pinned and FHistory.CanGoBack and IsBackKey(AKey, AShift));
  // Kürzel der Aktionsleiste nur, wenn der Tooltip gemeint ist: angeheftet oder mit der Maus darüber.
  Result := Result or ((FHistory.Pinned or MouseOverTip) and WantsTipKey(AKey, AShift));
end;

function TAtlasEditorHover.WantsTipKey(AKey: Word; AShift: TShiftState): Boolean;
var
  mData: TAtlasHoverData;
begin
  // Markierter Doku-Text lässt sich auch ohne Fundort kopieren (#654).
  Result := FTip.HasSelection and (AKey = Ord('C')) and (AShift = [ssCtrl]);
  // Aktionen unter Befunden (#909), auch ohne Fundort (Hover nur mit Problem).
  Result := Result or ((AKey = VK_RETURN) and (AShift = [ssAlt]) and FTip.HasFix);
  Result := Result or ((AKey = VK_TAB) and NoneOrShift(AShift) and FTip.HasProblemActions);
  Result := Result or ((AKey = VK_RETURN) and (AShift = []) and FTip.ProblemActionMarked);
  if Result then
  begin
    Exit;
  end;
  mData := FHistory.Current;
  Result := mData.Location.HasLocation and ActionKey(AKey, AShift, mData.DocWiki <> '');
end;

procedure TAtlasEditorHover.HandleKey(AKey: Word; AShift: TShiftState);
begin
  case AKey of
    VK_ESCAPE:
      Hide;
    VK_BACK, VK_LEFT:
      TipBack(nil);
    VK_F12:
      if ssShift in AShift then
      begin
        Execute(TAtlasHoverAction.Usages);
      end
      else
      begin
        Execute(TAtlasHoverAction.Navigate);
      end;
    VK_F1:
      Execute(TAtlasHoverAction.Help);
    VK_TAB:
      FTip.StepProblemAction(not (ssShift in AShift));
    VK_RETURN:
      if ssAlt in AShift then
      begin
        FTip.ApplyFix;
      end
      else
      begin
        FTip.ActivateProblemAction;
      end;
  else
    if AKey = Ord('C') then
    begin
      Execute(TAtlasHoverAction.Copy);
    end;
  end;
end;

procedure TAtlasEditorHover.EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  try
    Hide;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Hover, E);
  end;
end;

{$IF CompilerVersion >= 37.0}
procedure TAtlasEditorHover.EditorKeyDown(const Editor: TWinControl; Key: Word; Shift: TShiftState;
  var Handled: Boolean);
begin
  try
    // Umschalt, Strg und Alt allein schließen nicht: Strg+Klick und die Kürzel brauchen sie.
    if (Key = VK_SHIFT) or (Key = VK_CONTROL) or (Key = VK_MENU) then
    begin
      Exit;
    end;
    Hide;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Hover, E);
  end;
end;
{$ENDIF}

procedure TAtlasEditorHover.EditorScrolled(const Editor: TWinControl; const Direction: TCodeEditorScrollDirection);
begin
  try
    Hide;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Hover, E);
  end;
end;

procedure TAtlasEditorHover.EditorResized(const Editor: TWinControl);
begin
  try
    Hide;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Hover, E);
  end;
end;

end.
