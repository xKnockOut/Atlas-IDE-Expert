unit Atlas.IDE.Tracker.CodeLinks;

// Issue-Kennungen im Editor (#1265): ATL-123, #42 und owner/repo#42 in
// Kommentaren (und in Literalen, die mit dem Commit-Präfix beginnen) werden
// gepunktet unterstrichen; Überfahren zeigt eine Kurzvorschau, Strg+Klick die
// Issue-Vorschau (#1264), Strg+Umschalt+Klick den Browser, Rechtsklick ein
// eigenes Menü. Was eine Kennung ist, rechnet Atlas.Core.Tracker.CodeLinks
// aus; hier bleiben Zeitgeber, Zeichnen, Maus und Menü.
// - Muster aus dem Tracker des aktiven Projekts (Haken Target, in der
//   Komposition TAtlasIdeIssueCommands.CodeTarget: .atlas, sonst die Zuordnung
//   #1261). Ohne Tracker keine Erkennung.
// - Ein Zeitgeber (TickMs) liest den Stand des Puffers der Ansicht vorn
//   (TAtlasEditorSnapshots) und rechnet bei neuem Stand nur die Zustände der
//   Zeilen (Kommentar über mehrere Zeilen) neu. Kennungen sucht PaintLine nur in
//   den Zeilen, die der Editor zeichnet, und merkt sie je Zeile bis zum
//   nächsten Stand. Beim Zeichnen nie ein Netzzugriff.
// - Unterstreichen und Hover (Kurzvorschau aus dem Zwischenspeicher, sonst
//   Kurzabfrage) stehen in Atlas.IDE.Tracker.CodeLinkMarks. Nicht gefunden:
//   „Issue … nicht gefunden.“, die Unterstreichung bleibt.
// - Strg+Klick und Rechtsklick werden vor dem Editor abgefangen
//   (TApplicationEvents.OnMessage wie bei den schnellen Lesezeichen #1104):
//   Die IDE springt dann nicht und öffnet ihr Kontextmenü nicht.
//   Umschalt+Rechtsklick lässt das Kontextmenü der IDE offen.
// - issues.codeLinks aus oder Atlas aus: keine Unterstreichung, kein Hover,
//   keine Abfrage.
// Gesichert über TAtlasFeature.IssueLinks (#493). Nur im Hauptthread.

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Types,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Vcl.AppEvnts,
  Vcl.Menus,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.CodeLinks,
  Atlas.IDE.Tracker.IssuePreview,
  Atlas.IDE.Tracker.CodeLinkMarks;

type
  /// <summary>Tracker des aktiven Projekts; False ohne.</summary>
  TAtlasCodeLinksTargetHook = reference to function(out ATarget: TAtlasTrackerTarget): Boolean;
  TAtlasCodeLinksIssueHook = reference to procedure(const ATarget: TAtlasTrackerTarget; const AKey: string);

  /// <summary>Was die Kennungen von „Meine Issues“ brauchen; die Komposition setzt es (kein Zyklus
  /// Tracker ↔ Welcome).</summary>
  TAtlasCodeLinksHooks = record
    Target: TAtlasCodeLinksTargetHook;
    /// <summary>issues.commitPattern.</summary>
    CommitPattern: TFunc<string>;
    /// <summary>Vorschau-Steuerung (Zwischenspeicher, Kurzabfrage); nil ohne.</summary>
    Preview: TFunc<TAtlasIdeIssuePreview>;
    /// <summary>Vorschau bzw. Browser (issues.preview).</summary>
    Show: TAtlasCodeLinksIssueHook;
    Browse: TAtlasCodeLinksIssueHook;
    /// <summary>„Beginnen“ wie in „Meine Issues“.</summary>
    Start: TAtlasCodeLinksIssueHook;
    CanStart: TFunc<Boolean>;
  end;

  TAtlasIdeCodeLinks = class
  private const
    TickMs = 150;
    MenuShow = 1;
    MenuBrowse = 2;
    MenuCopy = 3;
    MenuStart = 4;
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedLineStages: TPaintLineStages; override;
    end;
    /// <summary>Stand: Datei, Pufferstand, Muster (Tracker und Commit-Präfix), Zeilen und ihre Zustände.</summary>
    TState = record
      FileName: string;
      Version: Cardinal;
      PatternKey: string;
      Target: TAtlasTrackerTarget;
      Pattern: TAtlasIssueKeyPattern;
      Commit: string;
      Lines: TArray<string>;
      States: TArray<TAtlasCodeLinkState>;
      TabWidth: Integer;
    end;
  private class var
    FInstance: TAtlasIdeCodeLinks;
    FSerial: Integer;
  private
    FHooks: TAtlasCodeLinksHooks;
    FSerialOf: Integer;
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FTimer: TTimer;
    FHover: TAtlasCodeLinkHover;
    FAppEvents: TApplicationEvents;
    FMenu: TPopupMenu;
    FMenuHit: TAtlasCodeLinkHit;
    /// <summary>Nach einem geschluckten Drücken auch das Loslassen schlucken (WM_LBUTTONUP, WM_RBUTTONUP).
    /// </summary>
    FSwallowUp: Cardinal;
    FState: TState;
    // Gefundene Kennungen je Zeile (0-basiert) des Stands; gezeichnete je Zeile des Editors.
    FMatches: TDictionary<Integer, TArray<TAtlasIssueKeyMatch>>;
    FHits: TDictionary<Integer, TArray<TAtlasCodeLinkHit>>;
    function Active: Boolean;
    function Shown: Boolean;
    procedure Tick(Sender: TObject);
    procedure Update;
    procedure Clear;
    function MatchesOf(ALine: Integer): TArray<TAtlasIssueKeyMatch>;
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    function HitAt(AWnd: HWND; X, Y: Integer; out AHit: TAtlasCodeLinkHit): Boolean;
    procedure EditorMouseMove(const Editor: TWinControl; Shift: TShiftState; X, Y: Integer);
    procedure AppMessage(var Msg: TMsg; var Handled: Boolean);
    procedure Act(const AHit: TAtlasCodeLinkHit; ACommand: Integer);
    procedure ShowMenu(const AHit: TAtlasCodeLinkHit; const APoint: TPoint);
    procedure MenuClick(Sender: TObject);
  public
    /// <summary>AHooks: Tracker, Vorschau und Beginnen aus „Meine Issues“ (alle gesetzt).</summary>
    constructor Create(const AHooks: TAtlasCodeLinksHooks);
    destructor Destroy; override;
  end;

implementation

uses
  System.StrUtils,
  Vcl.Clipbrd,
  Atlas.Text.Lines,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Tracker.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.IDE.Foundation.EditorRefresh;

function PatternKey(const ATarget: TAtlasTrackerTarget; const ACommit: string): string;
begin
  Result := ATarget.Provider + #1 + ATarget.Url + #1 + ATarget.Project + #1 + ACommit;
end;

/// <summary>Den Editor vorn neu zeichnen.</summary>
procedure InvalidateEditor;
var
  mServices: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    TAtlasIdeEditorRefresh.InvalidateTop(mServices);
  end;
end;

function IsPascal(const AFileName: string): Boolean;
begin
  Result := MatchText(ExtractFileExt(AFileName), ['.pas', '.dpr', '.dpk', '.inc', '.lpr', '.pp']);
end;

function CanStart(const AHooks: TAtlasCodeLinksHooks): Boolean;
begin
  Result := Assigned(AHooks.CanStart) and Assigned(AHooks.Start) and AHooks.CanStart();
end;

{ TAtlasIdeCodeLinks.TEvents }

function TAtlasIdeCodeLinks.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintLineEvents, cevMouseEvents];
end;

function TAtlasIdeCodeLinks.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TAtlasIdeCodeLinks }

constructor TAtlasIdeCodeLinks.Create(const AHooks: TAtlasCodeLinksHooks);
var
  mServices: INTACodeEditorServices;
begin
  inherited Create;
  FHooks := AHooks;
  FIndex := -1;
  Inc(FSerial);
  FSerialOf := FSerial;
  FInstance := Self;
  FMatches := TDictionary<Integer, TArray<TAtlasIssueKeyMatch>>.Create;
  FHits := TDictionary<Integer, TArray<TAtlasCodeLinkHit>>.Create;
  FHover := TAtlasCodeLinkHover.Create(AHooks.Preview);
  FMenu := TPopupMenu.Create(nil);
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintLine := PaintLine;
  FEvents.OnEditorMouseMove := EditorMouseMove;
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    FIndex := mServices.AddEditorEventsNotifier(FEventsRef);
  end;
  FAppEvents := TApplicationEvents.Create(nil);
  FAppEvents.OnMessage := AppMessage;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := TickMs;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TAtlasIdeCodeLinks.Destroy;
var
  mServices: INTACodeEditorServices;
  mPainted: Boolean;
begin
  if FInstance = Self then
  begin
    FInstance := nil;
  end;
  FreeAndNil(FTimer);
  if FAppEvents <> nil then
  begin
    FAppEvents.OnMessage := nil;
    FreeAndNil(FAppEvents);
  end;
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    mServices.RemoveEditorEventsNotifier(FIndex);
  end;
  if FEvents <> nil then
  begin
    FEvents.OnEditorPaintLine := nil;
    FEvents.OnEditorMouseMove := nil;
  end;
  FEventsRef := nil;
  mPainted := FHits.Count > 0;
  FreeAndNil(FMenu);
  FreeAndNil(FHover);
  Clear;
  FreeAndNil(FHits);
  FreeAndNil(FMatches);
  FMenuHit := Default(TAtlasCodeLinkHit);
  FHooks := Default(TAtlasCodeLinksHooks);
  if mPainted then
  begin
    InvalidateEditor;
  end;
  inherited Destroy;
end;

function TAtlasIdeCodeLinks.Active: Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  Result := (FIndex >= 0) and Assigned(FHooks.Target) and not TAtlasGuard.Disabled(TAtlasFeature.IssueLinks);
  if not Result then
  begin
    Exit;
  end;
  mSettings := TAtlasIdeSettings.Current;
  Result := mSettings.Enabled and mSettings.IssuesCodeLinks;
end;

function TAtlasIdeCodeLinks.Shown: Boolean;
begin
  Result := Active and FState.Pattern.Active and (FState.FileName <> '');
end;

procedure TAtlasIdeCodeLinks.Clear;
begin
  FState := Default(TState);
  FState.Pattern := TAtlasIssueKeyPattern.Empty;
  if FMatches <> nil then
  begin
    FMatches.Clear;
  end;
  if FHits <> nil then
  begin
    FHits.Clear;
  end;
end;

procedure TAtlasIdeCodeLinks.Tick(Sender: TObject);
begin
  try
    Update;
    FHover.Check(Shown, FState.Target);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.IssueLinks, E);
  end;
end;

/// <summary>Pascal-Ansicht vorn mit Tracker; nil, wenn es nichts zu zeigen gibt.</summary>
function ShownView(AOwner: TAtlasIdeCodeLinks; out ATarget: TAtlasTrackerTarget): IOTAEditView;
begin
  Result := nil;
  if AOwner.Active and AOwner.FHooks.Target(ATarget) then
  begin
    Result := TAtlasEditorBuffer.ActiveView;
  end;
  if (Result <> nil) and ((Result.Buffer = nil) or not IsPascal(Result.Buffer.FileName)) then
  begin
    Result := nil;
  end;
end;

procedure TAtlasIdeCodeLinks.Update;
var
  mView: IOTAEditView;
  mSnapshot: TAtlasEditorSnapshot;
  mTarget: TAtlasTrackerTarget;
  mCommit, mKey: string;
begin
  mView := ShownView(Self, mTarget);
  if mView = nil then
  begin
    FHover.SetHit(Default(TAtlasCodeLinkHit), False);
    if FState.FileName <> '' then
    begin
      Clear;
      InvalidateEditor;
    end;
    Exit;
  end;
  mCommit := '';
  if Assigned(FHooks.CommitPattern) then
  begin
    mCommit := FHooks.CommitPattern();
  end;
  mKey := PatternKey(mTarget, mCommit);
  mSnapshot := TAtlasEditorSnapshots.Get(mView);
  if (mSnapshot.Version = FState.Version) and SameText(mSnapshot.FileName, FState.FileName) and
    (mKey = FState.PatternKey) then
  begin
    Exit;
  end;
  // Neuer Stand: nur die Zustände der Zeilen; Kennungen sucht erst das Zeichnen der sichtbaren Zeilen.
  FHover.SetHit(Default(TAtlasCodeLinkHit), False);
  FState.FileName := mSnapshot.FileName;
  FState.Version := mSnapshot.Version;
  FState.PatternKey := mKey;
  FState.Target := mTarget;
  FState.Pattern := TAtlasIssueKeyPattern.ForTarget(mTarget);
  FState.Commit := mCommit;
  FState.Lines := TTextLines.SplitLines(mSnapshot.Text);
  FState.States := TAtlasCodeLinks.States(FState.Lines);
  FState.TabWidth := TAtlasEditorBuffer.TabWidth(mView.Buffer);
  FMatches.Clear;
  FHits.Clear;
  InvalidateEditor;
end;

function TAtlasIdeCodeLinks.MatchesOf(ALine: Integer): TArray<TAtlasIssueKeyMatch>;
begin
  if FMatches.TryGetValue(ALine, Result) then
  begin
    Exit;
  end;
  Result := TAtlasCodeLinks.LineMatches(FState.Pattern, FState.Lines[ALine], FState.States[ALine], FState.Commit);
  FMatches.Add(ALine, Result);
end;

/// <summary>Zeile des Stands, die AContext zeichnet; -1, wenn sie nicht dem Stand entspricht (sonst kommt gleich
/// ein neuer Takt) oder nichts gezeigt wird.</summary>
function PaintedLine(AOwner: TAtlasIdeCodeLinks; const AContext: INTACodeEditorPaintContext): Integer;
var
  mLineState: INTACodeEditorLineState;
  mLine: Integer;
begin
  Result := -1;
  if not AOwner.Shown or not SameText(AContext.FileName, AOwner.FState.FileName) then
  begin
    Exit;
  end;
  mLineState := AContext.LineState;
  mLine := AContext.LogicalLineNum - 1;
  if (mLineState <> nil) and (mLine >= 0) and (mLine < Length(AOwner.FState.Lines)) and
    (TrimRight(mLineState.Text) = TrimRight(AOwner.FState.Lines[mLine])) then
  begin
    Result := mLine;
  end;
end;

procedure TAtlasIdeCodeLinks.PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
  var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  mMatches: TArray<TAtlasIssueKeyMatch>;
  mLine: Integer;
begin
  if BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) or (FState.FileName = '') or
    TAtlasGuard.Disabled(TAtlasFeature.IssueLinks) then
  begin
    Exit;
  end;
  try
    if (Context.EditControl = nil) or (Context.EditView = nil) or (Context.EditorState = nil) then
    begin
      Exit;
    end;
    // Was diese Zeile des Editors vorher zeigte, gilt nicht mehr.
    FHits.Remove(Context.EditorLineNum);
    mLine := PaintedLine(Self, Context);
    if mLine < 0 then
    begin
      Exit;
    end;
    mMatches := MatchesOf(mLine);
    if Length(mMatches) > 0 then
    begin
      FHits.AddOrSetValue(Context.EditorLineNum, TAtlasCodeLinkPainter.Paint(Rect, Context, FState.Lines[mLine],
        mMatches, FState.TabWidth));
    end;
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.IssueLinks, E);
  end;
end;

/// <summary>Erste gezeichnete Kennung in AWnd unter APoint.</summary>
function FindHit(AHits: TDictionary<Integer, TArray<TAtlasCodeLinkHit>>; AWnd: HWND; const APoint: TPoint;
  out AHit: TAtlasCodeLinkHit): Boolean;
var
  mHits: TArray<TAtlasCodeLinkHit>;
  mHit: TAtlasCodeLinkHit;
begin
  AHit := Default(TAtlasCodeLinkHit);
  for mHits in AHits.Values do
  begin
    for mHit in mHits do
    begin
      if (mHit.Wnd = AWnd) and PtInRect(mHit.Rect, APoint) then
      begin
        AHit := mHit;
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

function TAtlasIdeCodeLinks.HitAt(AWnd: HWND; X, Y: Integer; out AHit: TAtlasCodeLinkHit): Boolean;
var
  mView: IOTAEditView;
begin
  AHit := Default(TAtlasCodeLinkHit);
  Result := False;
  if not Shown or (FHits.Count = 0) then
  begin
    Exit;
  end;
  mView := TAtlasEditorBuffer.ActiveView;
  if (mView = nil) or (mView.Buffer = nil) then
  begin
    Exit;
  end;
  // Nur, wenn die Kennung noch dort steht: gleiche Datei, nicht gescrollt.
  Result := FindHit(FHits, AWnd, Point(X, Y), AHit) and SameText(AHit.FileName, mView.Buffer.FileName) and
    (AHit.TopRow = mView.TopRow);
  if not Result then
  begin
    AHit := Default(TAtlasCodeLinkHit);
  end;
end;

procedure TAtlasIdeCodeLinks.EditorMouseMove(const Editor: TWinControl; Shift: TShiftState; X, Y: Integer);
var
  mHit: TAtlasCodeLinkHit;
begin
  try
    if (Editor = nil) or not Editor.HandleAllocated or not HitAt(Editor.Handle, X, Y, mHit) then
    begin
      // Über dem Tooltip selbst bleibt er offen (Check).
      if not FHover.Over(Mouse.CursorPos) then
      begin
        FHover.SetHit(Default(TAtlasCodeLinkHit), False);
      end;
      Exit;
    end;
    FHover.SetHit(mHit, True);
    FHover.SetScreen(TRect.Create(Editor.ClientToScreen(mHit.Rect.TopLeft),
      Editor.ClientToScreen(mHit.Rect.BottomRight)));
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.IssueLinks, E);
  end;
end;

procedure TAtlasIdeCodeLinks.Act(const AHit: TAtlasCodeLinkHit; ACommand: Integer);
var
  mTarget: TAtlasTrackerTarget;
begin
  mTarget := AHit.Match.IssueTarget(FState.Target);
  case ACommand of
    MenuShow:
      if Assigned(FHooks.Show) then
      begin
        FHooks.Show(mTarget, AHit.Match.IssueKey);
      end;
    MenuBrowse:
      if Assigned(FHooks.Browse) then
      begin
        FHooks.Browse(mTarget, AHit.Match.IssueKey);
      end;
    MenuCopy:
      Clipboard.AsText := AHit.Match.Key;
    MenuStart:
      if CanStart(FHooks) then
      begin
        FHooks.Start(mTarget, AHit.Match.IssueKey);
      end;
  end;
end;

/// <summary>Im Hauptthread nachgereicht: eigenes Menü zu AHit an AWhere.</summary>
procedure QueueMenu(const AHit: TAtlasCodeLinkHit; const AWhere: TPoint; ASerial: Integer);
var
  mHit: TAtlasCodeLinkHit;
  mWhere: TPoint;
begin
  mHit := AHit;
  mWhere := AWhere;
  TAtlasMainThread.ForceQueue(TAtlasFeature.IssueLinks,
    procedure
    begin
      if (TAtlasIdeCodeLinks.FInstance <> nil) and (TAtlasIdeCodeLinks.FInstance.FSerialOf = ASerial) then
      begin
        TAtlasGuard.Run(TAtlasFeature.IssueLinks,
          procedure
          begin
            TAtlasIdeCodeLinks.FInstance.ShowMenu(mHit, mWhere);
          end);
      end;
    end);
end;

/// <summary>Im Hauptthread nachgereicht: Befehl ACommand für AHit.</summary>
procedure QueueAct(const AHit: TAtlasCodeLinkHit; ACommand, ASerial: Integer);
var
  mHit: TAtlasCodeLinkHit;
begin
  mHit := AHit;
  TAtlasMainThread.ForceQueue(TAtlasFeature.IssueLinks,
    procedure
    begin
      if (TAtlasIdeCodeLinks.FInstance <> nil) and (TAtlasIdeCodeLinks.FInstance.FSerialOf = ASerial) then
      begin
        TAtlasGuard.Run(TAtlasFeature.IssueLinks,
          procedure
          begin
            TAtlasIdeCodeLinks.FInstance.Act(mHit, ACommand);
          end);
      end;
    end);
end;

/// <summary>Loslassen zum geschluckten Drücken: Ohne Drücken darf auch es nicht an den Editor; nach dem
/// Rechtsklick öffnet hier das eigene Menü.</summary>
procedure SwallowUp(AOwner: TAtlasIdeCodeLinks; const AMsg: TMsg; var AHandled: Boolean);
begin
  AOwner.FSwallowUp := 0;
  AHandled := True;
  if GetCapture = AMsg.hwnd then
  begin
    ReleaseCapture;
  end;
  if AMsg.message = WM_RBUTTONUP then
  begin
    QueueMenu(AOwner.FMenuHit, Mouse.CursorPos, AOwner.FSerialOf);
  end;
end;

/// <summary>Strg+Klick oder Rechtsklick ohne Umschalt (Umschalt+Rechtsklick: Kontextmenü der IDE)?</summary>
function IsLinkClick(const AMsg: TMsg): Boolean;
begin
  Result := ((AMsg.message = WM_LBUTTONDOWN) and ((AMsg.wParam and MK_CONTROL) <> 0)) or
    ((AMsg.message = WM_RBUTTONDOWN) and ((AMsg.wParam and MK_SHIFT) = 0));
end;

/// <summary>Klick auf eine Kennung: Strg+Klick öffnet Vorschau bzw. Browser (Strg+Umschalt+Klick: Browser; die
/// IDE springt nicht), Rechtsklick merkt die Kennung für das Menü beim Loslassen.</summary>
procedure LinkClick(AOwner: TAtlasIdeCodeLinks; const AMsg: TMsg; var AHandled: Boolean);
var
  mHit: TAtlasCodeLinkHit;
  mCommand: Integer;
begin
  if not AOwner.HitAt(AMsg.hwnd, SmallInt(LoWord(AMsg.lParam)), SmallInt(HiWord(AMsg.lParam)), mHit) then
  begin
    Exit;
  end;
  AHandled := True;
  AOwner.FHover.Hide;
  if AMsg.message = WM_RBUTTONDOWN then
  begin
    // Das eigene Menü ersetzt das Kontextmenü der IDE; es öffnet beim Loslassen.
    AOwner.FSwallowUp := WM_RBUTTONUP;
    AOwner.FMenuHit := mHit;
  end
  else
  begin
    AOwner.FSwallowUp := WM_LBUTTONUP;
    mCommand := TAtlasIdeCodeLinks.MenuShow;
    if (AMsg.wParam and MK_SHIFT) <> 0 then
    begin
      mCommand := TAtlasIdeCodeLinks.MenuBrowse;
    end;
    QueueAct(mHit, mCommand, AOwner.FSerialOf);
  end;
end;

procedure TAtlasIdeCodeLinks.AppMessage(var Msg: TMsg; var Handled: Boolean);
begin
  try
    if (FSwallowUp <> 0) and (Msg.message = FSwallowUp) then
    begin
      SwallowUp(Self, Msg, Handled);
    end
    else if IsLinkClick(Msg) then
    begin
      LinkClick(Self, Msg, Handled);
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.IssueLinks, E);
  end;
end;

function AddMenuItem(AMenu: TPopupMenu; const ACaption: string; ATag: Integer; AClick: TNotifyEvent): TMenuItem;
begin
  Result := TMenuItem.Create(AMenu);
  Result.Caption := ACaption;
  Result.Tag := ATag;
  Result.OnClick := AClick;
  AMenu.Items.Add(Result);
end;

procedure TAtlasIdeCodeLinks.ShowMenu(const AHit: TAtlasCodeLinkHit; const APoint: TPoint);
begin
  FMenu.Items.Clear;
  FMenuHit := AHit;
  AddMenuItem(FMenu, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueLinkMenuShow), MenuShow,
    MenuClick).Default := True;
  AddMenuItem(FMenu, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewBrowse), MenuBrowse, MenuClick);
  AddMenuItem(FMenu, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewCopyKey), MenuCopy, MenuClick);
  AddMenuItem(FMenu, '-', 0, nil);
  AddMenuItem(FMenu, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewStart), MenuStart,
    MenuClick).Enabled := CanStart(FHooks);
  FMenu.Popup(APoint.X, APoint.Y);
end;

procedure TAtlasIdeCodeLinks.MenuClick(Sender: TObject);
var
  mCommand: Integer;
  mHit: TAtlasCodeLinkHit;
begin
  mCommand := TMenuItem(Sender).Tag;
  mHit := FMenuHit;
  TAtlasGuard.Run(TAtlasFeature.IssueLinks,
    procedure
    begin
      Act(mHit, mCommand);
    end);
end;

end.
