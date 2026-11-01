unit Atlas.IDE.Editor.Minimap;

// Minimap neben der Scrollleiste (#873, experimentell) in der IDE:
// - Jedes Editorfenster bekommt neben dem Editor einen Streifen
//   (TAtlasMinimapView, alRight bzw. alLeft nach editor.minimap.side im
//   Eltern-Steuerelement des Editors „Editor“), wie die Übersichtsleiste
//   (#519); beide können nebeneinander stehen.
// - Ein Zeitgeber (100 ms) führt die Ansicht vorn nach: sichtbarer Bereich
//   und Cursor sofort; den Text aus TAtlasEditorSnapshots (liest den Puffer
//   nur nach Änderungen) erst nach einer Tipp-Pause, zerlegt in Balken im
//   Hintergrund (TAtlasMinimap.Runs), das Ergebnis über TAtlasMainThread.
//   Der Streifen zeichnet danach nur geänderte Zeilen neu.
// - Gliederung (Überschriften, Routine am Cursor) aus TAtlasIdeOutlineCache
//   (gemeinsam mit Gliederung, Brotkrumen und mitlaufendem Kopf), Marken über
//   TAtlasIdeOverviewRuler.CollectMarks (Befunde, Treffer des markierten
//   Texts, Änderungen).
// - Faltung: Die Open Tools API meldet gefaltete Bereiche nicht. PaintLine
//   merkt sich je gemalter Bildschirmzeile die Editorzeile;
//   TAtlasMinimap.Folds erkennt daraus gefaltete und wieder aufgeklappte
//   Bereiche. Ändert sich die Zeilenzahl, gelten die Bereiche als unbekannt.
// - Ziehen setzt die oberste Zeile (SetTopLeft), ein Klick springt
//   (TAtlasIdeNavigation) oder scrollt nur (editor.minimap.clickJumps).
// - Minimap der IDE: Ist neben der Atlas-Minimap ein sichtbares Steuerelement
//   mit „Minimap“ im Klassennamen im Editorfenster, kommt einmal (gemerkt in
//   MinimapNoticeShown) der Hinweis „Zwei Minimaps sichtbar“ mit „IDE-Minimap
//   ausblenden“ (für diese Sitzung) und „Atlas-Minimap aus“. Eine Schnittstelle
//   zum Abfragen oder Abschalten bietet die Open Tools API nicht.
// - Anlegen je Editorfenster, Wächter, Freigabe nach der Sperre durch die
//   IDE und Abbau übernimmt TAtlasEditorBarHost (#1248).
// editor.minimap oder experimental.enabled aus: alle Streifen weg, kein
// Zeichen-Ereignis. Nur im Hauptthread.

interface

type
  TAtlasIdeMinimap = class
  private class var
    FState: TObject;
  public
    class procedure Install; static;
    class procedure Uninstall; static;
    class procedure ApplySettings; static;
    class procedure ThemeChanged; static;
    /// <summary>Minimap an: editor.minimap (wirksam nur mit experimental.enabled) und Sicherung.</summary>
    class function Active: Boolean; static;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Types,
  System.Math,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.ExtCtrls,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Text.Lines,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Notifications.Contract,
  Atlas.Core.Notifications.Center,
  Atlas.Core.Notifications.Sources,
  Atlas.Core.Outline.Model,
  Atlas.Core.Editor.Overview,
  Atlas.Core.Editor.Minimap,
  Atlas.UI.Strings,
  Atlas.UI.Popup.Window,
  Atlas.UI.Notifications.Notice,
  Atlas.UI.Editor.Minimap,
  Atlas.IDE.Foundation.EditorBarHost,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Outline.Cache,
  Atlas.IDE.Editor.OverviewRuler;

const
  TickMs = 100;
  /// <summary>Tipp-Pause, bevor der Text neu zerlegt wird.</summary>
  QuietMs = 300;
  /// <summary>So tief sucht der Hinweis die Minimap der IDE im Editorfenster.</summary>
  MaxSearchDepth = 6;

type
  TEvents = class(TNTACodeEditorNotifier)
  protected
    function AllowedEvents: TCodeEditorEvents; override;
    function AllowedLineStages: TPaintLineStages; override;
  end;

  TMinimapState = class
  private
    FTimer: TTimer;
    FHost: TAtlasEditorBarHost;
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FOptions: TAtlasMinimapOptions;
    FColorsSet: Boolean;
    // Inhalt der Ansicht vorn.
    FFileName: string;
    FVersion: Cardinal;
    FChangedAt: UInt64;
    FAppliedVersion: Cardinal;
    /// <summary>Für die Datei liegt schon ein zerlegter Stand vor.</summary>
    FHasContent: Boolean;
    FLines: TArray<string>;
    FRuns: TAtlasMinimapLines;
    FTabWidth: Integer;
    FWorker: TThread;
    FWorking: Boolean;
    FRequest: Integer;
    FStamp: Cardinal;
    /// <summary>Streifen, der den Inhalt zuletzt bekam (Fensterwechsel).</summary>
    FContentView: TAtlasMinimapView;
    // Treffer des markierten Texts.
    FTerm: string;
    FTermVersion: Cardinal;
    FSearchLines: TArray<Integer>;
    // Faltung aus den gemalten Zeilen.
    FFolds: TAtlasMinimapFolds;
    FFoldLines: Integer;
    FPainted: TArray<TAtlasMinimapPainted>;
    FPaintedTop: Integer;
    FPaintedFile: string;
    FRowHeight: Integer;
    // Hinweis bei sichtbarer IDE-Minimap.
    FNotice: TAtlasNoticeWindow;
    FHideIde: Boolean;
    procedure Tick(Sender: TObject);
    function ActiveMinimap: TAtlasMinimapView;
    function CreateView: TAtlasMinimapView;
    procedure Place(AView: TAtlasMinimapView; AParent: TWinControl);
    procedure PlaceView(AView: TAtlasMinimapView);
    procedure Update;
    procedure UpdateContent(const AView: IOTAEditView; AMinimap: TAtlasMinimapView);
    procedure StartWorker(const AText: string; AVersion: Cardinal; AMaxColumn, ATabWidth: Integer);
    procedure Accept(ARequest: Integer; const AFileName: string; AVersion: Cardinal; const ALines: TArray<string>;
      const ARuns: TAtlasMinimapLines);
    procedure UpdateFolds(AMinimap: TAtlasMinimapView; ALineCount: Integer);
    procedure UpdateMarks(const AView: IOTAEditView; AMinimap: TAtlasMinimapView; ALineCount: Integer);
    procedure Scroll(AMinimap: TAtlasMinimapView; ATopLine: Integer);
    procedure Jump(AMinimap: TAtlasMinimapView; ALine: Integer);
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    function IdeMinimap(AParent: TWinControl): TControl;
    procedure CheckIdeMinimap(AMinimap: TAtlasMinimapView);
    procedure HideIdeMinimap;
    procedure TurnOff;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Removed(AView: TControl);
    procedure ApplySettings;
    procedure ApplyTheme;
  end;

function CurrentOptions: TAtlasMinimapOptions;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasIdeSettings.Current;
  Result := TAtlasMinimap.Options(Settings.MinimapRender, Settings.MinimapSide, Settings.MinimapShowSlider,
    Settings.MinimapWidth, Settings.MinimapScale, Settings.MinimapMaxColumn, Settings.MinimapSectionHeaders,
    Settings.MinimapHighlightMethod, Settings.MinimapMarkers, Settings.MinimapClickJumps);
end;

function SameOptions(const A, B: TAtlasMinimapOptions): Boolean;
begin
  Result := (A.Render = B.Render) and (A.Width = B.Width) and (A.Scale = B.Scale) and (A.MaxColumn = B.MaxColumn) and
    (A.Side = B.Side) and (A.Slider = B.Slider) and (A.SectionHeaders = B.SectionHeaders) and
    (A.HighlightMethod = B.HighlightMethod) and (A.Markers = B.Markers) and (A.ClickJumps = B.ClickJumps);
end;

{ TEvents }

function TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintLineEvents];
end;

function TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TMinimapState }

constructor TMinimapState.Create;
var
  Services: INTACodeEditorServices;
begin
  inherited Create;
  FIndex := -1;
  FPaintedTop := -1;
  FTabWidth := 4;
  FHost := TAtlasEditorBarHost.Create('Minimap', TAtlasFeature.Minimap,
    function(AEditorParent: TWinControl): TControl
    begin
      Result := CreateView;
    end,
    procedure(ABar: TControl; AEditorParent: TWinControl)
    begin
      Place(TAtlasMinimapView(ABar), AEditorParent);
    end);
  FHost.OnRemoved :=
    procedure(ABar: TControl)
    begin
      Removed(ABar);
    end;
  FOptions := CurrentOptions;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintLine := PaintLine;
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    FIndex := Services.AddEditorEventsNotifier(FEventsRef);
  FTimer := TTimer.Create(nil);
  FTimer.Interval := TickMs;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TMinimapState.Destroy;
var
  Services: INTACodeEditorServices;
begin
  FTimer.Free;
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    Services.RemoveEditorEventsNotifier(FIndex);
  FEvents.OnEditorPaintLine := nil;
  FEventsRef := nil;
  // Ein laufender Zerleger meldet sich über die Warteschlange; Inc verwirft sein Ergebnis.
  Inc(FRequest);
  if FWorker <> nil then
  begin
    FWorker.WaitFor;
    FreeAndNil(FWorker);
  end;
  FreeAndNil(FNotice);
  FHost.Free;
  inherited Destroy;
end;

procedure TMinimapState.Removed(AView: TControl);
begin
  if FContentView = AView then
    FContentView := nil;
end;

procedure TMinimapState.ApplySettings;
var
  Options: TAtlasMinimapOptions;
begin
  Options := CurrentOptions;
  if SameOptions(Options, FOptions) then
    Exit;
  // Andere höchste Spalte: neu zerlegen.
  if Options.MaxColumn <> FOptions.MaxColumn then
    FHasContent := False;
  FOptions := Options;
  FHost.ForEach(
    procedure(ABar: TControl)
    begin
      TAtlasMinimapView(ABar).SetOptions(FOptions);
      PlaceView(TAtlasMinimapView(ABar));
    end);
end;

procedure TMinimapState.ApplyTheme;
begin
  FHost.ForEach(
    procedure(ABar: TControl)
    begin
      TAtlasMinimapView(ABar).SetColors(TAtlasIdeStyle.Colors);
    end);
end;

function TMinimapState.ActiveMinimap: TAtlasMinimapView;
begin
  Result := TAtlasMinimapView(FHost.ActiveBar);
end;

procedure TMinimapState.Place(AView: TAtlasMinimapView; AParent: TWinControl);
begin
  if AView.Parent = AParent then
    Exit;
  AView.Parent := AParent;
  PlaceView(AView);
end;

procedure TMinimapState.PlaceView(AView: TAtlasMinimapView);
var
  Parent: TWinControl;
begin
  Parent := AView.Parent;
  if Parent = nil then
    Exit;
  // Zuerst ganz an den Rand, dann ausrichten: so steht die Minimap außen.
  AView.Align := alNone;
  if FOptions.Side = TAtlasMinimapSide.Left then
  begin
    AView.Left := -AView.Width;
    AView.Align := alLeft;
  end
  else
  begin
    AView.Left := Parent.ClientWidth;
    AView.Align := alRight;
  end;
end;

/// <summary>Eigene Methode: Jeder Streifen braucht seine eigene gefangene Variable.</summary>
function TMinimapState.CreateView: TAtlasMinimapView;
var
  View: TAtlasMinimapView;
begin
  View := TAtlasMinimapView.Create(nil);
  Result := View;
  View.SetOptions(FOptions);
  View.SetColors(TAtlasIdeStyle.Colors);
  View.OnScroll :=
    procedure(ATopLine: Integer)
    begin
      TAtlasGuard.Run(TAtlasFeature.Minimap,
        procedure
        begin
          Scroll(View, ATopLine);
        end);
    end;
  View.OnJump :=
    procedure(ALine: Integer)
    begin
      TAtlasGuard.Run(TAtlasFeature.Minimap,
        procedure
        begin
          Jump(View, ALine);
        end);
    end;
end;

procedure TMinimapState.StartWorker(const AText: string; AVersion: Cardinal; AMaxColumn, ATabWidth: Integer);
var
  Request: Integer;
  FileName: string;
begin
  if FWorker <> nil then
  begin
    FWorker.WaitFor;
    FreeAndNil(FWorker);
  end;
  Inc(FRequest);
  Request := FRequest;
  FileName := FFileName;
  FWorking := True;
  FWorker := TThread.CreateAnonymousThread(
    procedure
    var
      Lines: TArray<string>;
      Runs: TAtlasMinimapLines;
    begin
      try
        Lines := TTextLines.SplitLines(AText);
        Runs := TAtlasMinimap.Runs(Lines, AMaxColumn, ATabWidth);
      except
        Lines := nil;
        Runs := nil;
      end;
      // Atlas gehört der Eintrag: beim Entladen verworfen (Code-Review A-02).
      TAtlasMainThread.Queue(TAtlasFeature.Minimap,
        procedure
        begin
          if TAtlasIdeMinimap.FState <> nil then
            TAtlasGuard.Run(TAtlasFeature.Minimap,
              procedure
              begin
                if TAtlasIdeMinimap.FState <> nil then
                  TMinimapState(TAtlasIdeMinimap.FState).Accept(Request, FileName, AVersion, Lines, Runs);
              end);
        end);
    end);
  FWorker.FreeOnTerminate := False;
  FWorker.Start;
end;

procedure TMinimapState.Accept(ARequest: Integer; const AFileName: string; AVersion: Cardinal;
  const ALines: TArray<string>; const ARuns: TAtlasMinimapLines);
var
  Minimap: TAtlasMinimapView;
begin
  if ARequest <> FRequest then
    Exit;
  FWorking := False;
  if not SameText(AFileName, FFileName) then
    Exit;
  FLines := ALines;
  FRuns := ARuns;
  FAppliedVersion := AVersion;
  FHasContent := True;
  // Neue Treffer zum neuen Text.
  FTermVersion := 0;
  Minimap := ActiveMinimap;
  if Minimap <> nil then
  begin
    Minimap.SetContent(FLines, FRuns, FTabWidth);
    FContentView := Minimap;
  end;
end;

procedure TMinimapState.UpdateContent(const AView: IOTAEditView; AMinimap: TAtlasMinimapView);
var
  Snapshot: TAtlasEditorSnapshot;
  First: Boolean;
begin
  Snapshot := TAtlasEditorSnapshots.Get(AView);
  First := not SameText(Snapshot.FileName, FFileName);
  if First then
  begin
    FFileName := Snapshot.FileName;
    FHasContent := False;
    FVersion := Snapshot.Version;
    FLines := nil;
    FRuns := nil;
    FFolds := nil;
    FFoldLines := 0;
    FPainted := nil;
    FTermVersion := 0;
    FStamp := 0;
    AMinimap.SetFolds(nil);
    AMinimap.SetOutline(nil);
    AMinimap.SetMarks(nil);
    AMinimap.SetContent(nil, nil, FTabWidth);
    FContentView := AMinimap;
  end;
  if Snapshot.Version <> FVersion then
  begin
    FVersion := Snapshot.Version;
    FChangedAt := TThread.GetTickCount64;
  end;
  // Erster Stand sofort, Änderungen nach der Tipp-Pause; nie zwei Zerleger zugleich.
  if not FWorking and (not FHasContent or ((FAppliedVersion <> FVersion) and
    (TThread.GetTickCount64 - FChangedAt >= QuietMs))) then
  begin
    FTabWidth := TAtlasEditorBuffer.TabWidth(AView.Buffer);
    StartWorker(Snapshot.Text, FVersion, FOptions.MaxColumn, FTabWidth);
  end;
end;

procedure TMinimapState.UpdateFolds(AMinimap: TAtlasMinimapView; ALineCount: Integer);
begin
  // Andere Zeilenzahl: Die bekannten Bereiche stimmen nicht mehr.
  if ALineCount <> FFoldLines then
  begin
    FFolds := nil;
    FFoldLines := ALineCount;
  end;
  if (FPainted <> nil) and SameText(FPaintedFile, FFileName) then
    FFolds := TAtlasMinimap.Folds(FFolds, FPainted, FRowHeight, ALineCount);
  FPainted := nil;
  AMinimap.SetFolds(FFolds);
end;

procedure TMinimapState.UpdateMarks(const AView: IOTAEditView; AMinimap: TAtlasMinimapView; ALineCount: Integer);
var
  Block: IOTAEditBlock;
  Term: string;
begin
  if not FOptions.Markers then
  begin
    AMinimap.SetMarks(nil);
    Exit;
  end;
  Term := '';
  Block := AView.Block;
  if (Block <> nil) and Block.IsValid and (Block.Size > 0) and (Block.StartingRow = Block.EndingRow) then
    TAtlasOverview.SearchTerm(Block.Text, Term);
  if Term = '' then
    FSearchLines := nil
  else if (Term <> FTerm) or (FTermVersion <> FAppliedVersion) then
    FSearchLines := TAtlasOverview.Occurrences(FLines, Term);
  FTerm := Term;
  FTermVersion := FAppliedVersion;
  AMinimap.SetMarks(TAtlasIdeOverviewRuler.CollectMarks(AView, ALineCount, TAtlasMinimap.MarkerKinds, FTerm,
    FSearchLines));
end;

procedure TMinimapState.Update;
var
  Minimap: TAtlasMinimapView;
  View: IOTAEditView;
  Snapshot: TAtlasOutlineSnapshot;
  LineCount: Integer;
begin
  ApplySettings;
  FHost.Ensure;
  Minimap := ActiveMinimap;
  View := TAtlasEditorBuffer.ActiveView;
  if (Minimap = nil) or (View = nil) or (View.Buffer = nil) then
    Exit;
  if not FColorsSet then
  begin
    ApplyTheme;
    FColorsSet := True;
  end;
  LineCount := View.Buffer.GetLinesInBuffer;
  // Anderes Editorfenster vorn: Es übernimmt Inhalt und Gliederung.
  if Minimap <> FContentView then
  begin
    Minimap.SetContent(FLines, FRuns, FTabWidth);
    FContentView := Minimap;
    FStamp := 0;
  end;
  UpdateContent(View, Minimap);
  UpdateFolds(Minimap, LineCount);
  if not Minimap.SliderDragging then
    Minimap.SetView(View.TopRow - 1, View.BottomRow - 1, View.CursorPos.Line - 1);
  if FOptions.SectionHeaders or FOptions.HighlightMethod then
  begin
    Snapshot := TAtlasIdeOutlineCache.Refresh(View);
    if (Snapshot.Status = TAtlasOutlineStatus.Ready) and SameText(Snapshot.FileName, FFileName) and
      (Snapshot.Stamp <> FStamp) then
    begin
      FStamp := Snapshot.Stamp;
      Minimap.SetOutline(Snapshot.Nodes);
    end;
  end;
  UpdateMarks(View, Minimap, LineCount);
  CheckIdeMinimap(Minimap);
end;

procedure TMinimapState.Scroll(AMinimap: TAtlasMinimapView; ATopLine: Integer);
var
  View: IOTAEditView;
  Rows: Integer;
begin
  View := TAtlasEditorBuffer.ActiveView;
  if (AMinimap <> ActiveMinimap) or (View = nil) or (View.Buffer = nil) or (ATopLine < 0) then
    Exit;
  Rows := View.BottomRow - View.TopRow;
  View.SetTopLeft(ATopLine + 1, View.LeftColumn);
  View.Paint;
  // Sofort nachführen, damit das Ziehen flüssig bleibt.
  AMinimap.SetView(ATopLine, ATopLine + Rows, View.CursorPos.Line - 1);
end;

procedure TMinimapState.Jump(AMinimap: TAtlasMinimapView; ALine: Integer);
var
  View: IOTAEditView;
begin
  View := TAtlasEditorBuffer.ActiveView;
  if (AMinimap <> ActiveMinimap) or (View = nil) or (View.Buffer = nil) or (ALine < 0) then
    Exit;
  TAtlasIdeNavigation.GoToLocation(View.Buffer.FileName, ALine, 0);
end;

procedure TMinimapState.PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
  var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  View: IOTAEditView;
  Top, Index: Integer;
begin
  if BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) then
    Exit;
  try
    View := Context.EditView;
    if (View = nil) or (View.Buffer = nil) then
      Exit;
    // Nur Zeilen derselben Bildlaufstellung lassen sich vergleichen.
    Top := View.TopRow;
    if (Top <> FPaintedTop) or not SameText(Context.FileName, FPaintedFile) then
    begin
      FPainted := nil;
      FPaintedTop := Top;
      FPaintedFile := Context.FileName;
    end;
    FRowHeight := Rect.Bottom - Rect.Top;
    for Index := 0 to High(FPainted) do
      if FPainted[Index].Top = Rect.Top then
      begin
        FPainted[Index].Line := Context.LogicalLineNum - 1;
        Exit;
      end;
    // Höchstens eine Bildschirmseite merken.
    if Length(FPainted) < 1000 then
      FPainted := FPainted + [TAtlasMinimapPainted.Create(Rect.Top, Context.LogicalLineNum - 1)];
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Minimap, E);
  end;
end;

function TMinimapState.IdeMinimap(AParent: TWinControl): TControl;

  function Find(AControl: TWinControl; ADepth: Integer): TControl;
  var
    Index: Integer;
    Child: TControl;
  begin
    Result := nil;
    if ADepth > MaxSearchDepth then
      Exit;
    for Index := 0 to AControl.ControlCount - 1 do
    begin
      Child := AControl.Controls[Index];
      if (Child is TAtlasMinimapView) or not Child.Visible then
        Continue;
      if Pos('MINIMAP', UpperCase(Child.ClassName)) > 0 then
        Exit(Child);
      if Child is TWinControl then
      begin
        Result := Find(TWinControl(Child), ADepth + 1);
        if Result <> nil then
          Exit;
      end;
    end;
  end;

var
  Form: TCustomForm;
begin
  Result := nil;
  if AParent = nil then
    Exit;
  Form := GetParentForm(AParent);
  if Form <> nil then
    Result := Find(Form, 0)
  else
    Result := Find(AParent, 0);
end;

procedure TMinimapState.CheckIdeMinimap(AMinimap: TAtlasMinimapView);
var
  Ide: TControl;
  Settings: TAtlasPluginSettings;
  Actions: TArray<TAtlasNotificationAction>;
  Action: TAtlasNotificationAction;
  Area: TRect;
  Title, Text: string;
begin
  Settings := TAtlasIdeSettings.Stored;
  // Schon gezeigt und nichts auszublenden: den Fensterbaum nicht durchsuchen.
  if Settings.MinimapNoticeShown and not FHideIde then
    Exit;
  Ide := IdeMinimap(AMinimap.Parent);
  if (Ide <> nil) and FHideIde then
  begin
    Ide.Visible := False;
    Exit;
  end;
  if not TAtlasMinimap.ShouldNotice(AMinimap.Visible, Ide <> nil, Settings.MinimapNoticeShown) then
    Exit;
  // Nur einmal: gleich merken, auch wenn der Hinweis nur gesammelt wird.
  Settings.MinimapNoticeShown := True;
  TAtlasIdeSettings.Update(Settings);
  Title := TAtlasStrings.Text(TAtlasTextId.MinimapNoticeTitle);
  Text := TAtlasStrings.Text(TAtlasTextId.MinimapNoticeText);
  Action.Caption := TAtlasStrings.Text(TAtlasTextId.MinimapHideIde);
  Action.Run :=
    procedure
    begin
      if TAtlasIdeMinimap.FState <> nil then
        TMinimapState(TAtlasIdeMinimap.FState).HideIdeMinimap;
    end;
  Actions := [Action];
  Action.Caption := TAtlasStrings.Text(TAtlasTextId.MinimapTurnOff);
  Action.Run :=
    procedure
    begin
      if TAtlasIdeMinimap.FState <> nil then
        TMinimapState(TAtlasIdeMinimap.FState).TurnOff;
    end;
  Actions := Actions + [Action];
  if TAtlasNotificationCenter.Default.Notify(TAtlasNotificationSources.Minimap, TAtlasNotificationSeverity.Info,
    Title, Text, Actions) <> TAtlasNotificationMode.Show then
    Exit;
  if FNotice = nil then
    FNotice := TAtlasNoticeWindow.Create(nil);
  FNotice.OnAction :=
    procedure(AIndex: Integer)
    begin
      if TAtlasIdeMinimap.FState = nil then
        Exit;
      if AIndex = 0 then
        TMinimapState(TAtlasIdeMinimap.FState).HideIdeMinimap
      else if AIndex = 1 then
        TMinimapState(TAtlasIdeMinimap.FState).TurnOff;
    end;
  Area := Screen.WorkAreaRect;
  if Application.MainForm <> nil then
    Area := Application.MainForm.BoundsRect;
  FNotice.Colors := TAtlasIdeStyle.Colors;
  FNotice.SetScaling(TAtlasPopupWindow.MonitorPPI(Area.BottomRight), 1, '', 10);
  FNotice.ShowNotice(Title, Text, [TAtlasStrings.Text(TAtlasTextId.MinimapHideIde),
    TAtlasStrings.Text(TAtlasTextId.MinimapTurnOff)], Area);
end;

procedure TMinimapState.HideIdeMinimap;
begin
  // Für diese Sitzung; die Einstellung der IDE bleibt.
  FHideIde := True;
  FHost.ForEach(
    procedure(ABar: TControl)
    var
      Ide: TControl;
    begin
      Ide := IdeMinimap(ABar.Parent);
      if Ide <> nil then
        Ide.Visible := False;
    end);
end;

procedure TMinimapState.TurnOff;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasIdeSettings.Stored;
  Settings.Minimap := False;
  TAtlasIdeSettings.Update(Settings);
  // Nach dem laufenden Ereignis: der Zustand gibt sich dabei selbst frei.
  TAtlasMainThread.ForceQueue(TAtlasFeature.Minimap,
    procedure
    begin
      TAtlasIdeMinimap.ApplySettings;
    end);
end;

procedure TMinimapState.Tick(Sender: TObject);
begin
  // Schnellschalter, Hauptschalter und Sicherung wirken ohne eigenes Ereignis.
  if not TAtlasIdeMinimap.Active then
  begin
    TAtlasMainThread.ForceQueue(TAtlasFeature.Minimap,
      procedure
      begin
        TAtlasIdeMinimap.ApplySettings;
      end);
    FTimer.Enabled := False;
    Exit;
  end;
  TAtlasGuard.Run(TAtlasFeature.Minimap,
    procedure
    begin
      Update;
    end);
end;

{ TAtlasIdeMinimap }

class function TAtlasIdeMinimap.Active: Boolean;
begin
  Result := TAtlasIdeSettings.Current.Minimap and not TAtlasGuard.Disabled(TAtlasFeature.Minimap);
end;

class procedure TAtlasIdeMinimap.Install;
begin
  FreeAndNil(FState);
  if Active then
    FState := TMinimapState.Create;
end;

class procedure TAtlasIdeMinimap.Uninstall;
begin
  FreeAndNil(FState);
end;

class procedure TAtlasIdeMinimap.ApplySettings;
begin
  // Aus: alle Streifen weg, der Editor bekommt seine Breite zurück.
  if not Active then
  begin
    FreeAndNil(FState);
    Exit;
  end;
  if FState = nil then
    FState := TMinimapState.Create
  else
    TMinimapState(FState).ApplySettings;
end;

class procedure TAtlasIdeMinimap.ThemeChanged;
begin
  if FState <> nil then
    TMinimapState(FState).ApplyTheme;
end;

end.
