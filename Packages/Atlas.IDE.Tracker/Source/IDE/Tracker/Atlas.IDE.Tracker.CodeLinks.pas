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
// - Hover nach TAtlasCloseRules.TooltipShowDelayMs: Stand aus dem Zwischenspeicher der
//   Vorschau (Peek), sonst „Wird geladen …“ und eine Kurzabfrage im Hintergrund
//   (Lookup); ein Stand älter als TAtlasIdeIssuePreview.FreshMs wird dabei
//   aufgefrischt. Nicht gefunden: „Issue … nicht gefunden.“, die
//   Unterstreichung bleibt.
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
  Vcl.Graphics,
  Vcl.ExtCtrls,
  Vcl.AppEvnts,
  Vcl.Menus,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.CodeLinks,
  Atlas.UI.Popup.TitledTip,
  Atlas.UI.Tracker.IssueTip,
  Atlas.IDE.Tracker.IssuePreview;

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
    /// <summary>Anteil der Akzentfarbe an der Unterstreichung (Rest: Hintergrund).</summary>
    LineStrength = 0.75;
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
    /// <summary>Gezeichnete Kennung (Koordinaten des Editors).</summary>
    THit = record
      Wnd: HWND;
      FileName: string;
      /// <summary>0-basiert.</summary>
      Line: Integer;
      TopRow: Integer;
      Rect: TRect;
      Match: TAtlasIssueKeyMatch;
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
    FTip: TAtlasTitledTip;
    FAppEvents: TApplicationEvents;
    FMenu: TPopupMenu;
    FMenuHit: THit;
    /// <summary>Nach einem geschluckten Drücken auch das Loslassen schlucken (WM_LBUTTONUP, WM_RBUTTONUP).
    /// </summary>
    FSwallowUp: Cardinal;
    // Stand: Datei, Pufferstand, Muster (Tracker und Commit-Präfix), Zeilen und ihre Zustände.
    FFileName: string;
    FVersion: Cardinal;
    FPatternKey: string;
    FTarget: TAtlasTrackerTarget;
    FPattern: TAtlasIssueKeyPattern;
    FCommit: string;
    FLines: TArray<string>;
    FStates: TArray<TAtlasCodeLinkState>;
    FTabWidth: Integer;
    // Gefundene Kennungen je Zeile (0-basiert) des Stands; gezeichnete je Zeile des Editors.
    FMatches: TDictionary<Integer, TArray<TAtlasIssueKeyMatch>>;
    FHits: TDictionary<Integer, TArray<THit>>;
    // Überfahren.
    FHover: THit;
    FHovering: Boolean;
    FHoverSince: UInt64;
    FHoverScreen: TRect;
    FTipKey: string;
    function Active: Boolean;
    function Shown: Boolean;
    procedure Tick(Sender: TObject);
    procedure Update;
    procedure Clear;
    function MatchesOf(ALine: Integer): TArray<TAtlasIssueKeyMatch>;
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    procedure PaintMatches(const Rect: TRect; const Context: INTACodeEditorPaintContext; const AText: string;
      const AMatches: TArray<TAtlasIssueKeyMatch>);
    function HitAt(AWnd: HWND; X, Y: Integer; out AHit: THit): Boolean;
    procedure EditorMouseMove(const Editor: TWinControl; Shift: TShiftState; X, Y: Integer);
    procedure AppMessage(var Msg: TMsg; var Handled: Boolean);
    procedure SetHover(const AHit: THit; AOn: Boolean);
    procedure CheckHover;
    procedure HideTip;
    procedure ShowTip(const AHit: THit);
    procedure ShowState(const AKey: string; AState: TAtlasIssueTipState; const ADetails: TAtlasTrackerDetails;
      AError: TAtlasCiFetchError);
    procedure LookedUp(const AKey: string; ASucceeded: Boolean; const ADetails: TAtlasTrackerDetails;
      AError: TAtlasCiFetchError);
    procedure Act(const AHit: THit; ACommand: Integer);
    procedure ShowMenu(const AHit: THit; const APoint: TPoint);
    procedure MenuClick(Sender: TObject);
    function AddMenuItem(const ACaption: string; ATag: Integer): TMenuItem;
    function TargetOf(const AHit: THit): TAtlasTrackerTarget;
    function Preview: TAtlasIdeIssuePreview;
    function CanStart: Boolean;
    class procedure Invalidate; static;
    class function IsPascal(const AFileName: string): Boolean; static;
  public
    /// <summary>AHooks: Tracker, Vorschau und Beginnen aus „Meine Issues“ (alle gesetzt).</summary>
    constructor Create(const AHooks: TAtlasCodeLinksHooks);
    destructor Destroy; override;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  System.DateUtils,
  Vcl.Clipbrd,
  Atlas.Text.Lines,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Editor.CloseRules,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Tracker.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.EditorRefresh;

function PatternKey(const ATarget: TAtlasTrackerTarget; const ACommit: string): string;
begin
  Result := ATarget.Provider + #1 + ATarget.Url + #1 + ATarget.Project + #1 + ACommit;
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
  FHits := TDictionary<Integer, TArray<THit>>.Create;
  FTip := TAtlasTitledTip.Create(nil);
  FTip.GuardFeature := TAtlasFeature.IssueLinks;
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
  FreeAndNil(FTip);
  Clear;
  FreeAndNil(FHits);
  FreeAndNil(FMatches);
  FMenuHit := Default(THit);
  FHover := Default(THit);
  FHooks := Default(TAtlasCodeLinksHooks);
  if mPainted then
  begin
    Invalidate;
  end;
  inherited Destroy;
end;

class procedure TAtlasIdeCodeLinks.Invalidate;
var
  mServices: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    TAtlasIdeEditorRefresh.InvalidateTop(mServices);
  end;
end;

class function TAtlasIdeCodeLinks.IsPascal(const AFileName: string): Boolean;
begin
  Result := MatchText(ExtractFileExt(AFileName), ['.pas', '.dpr', '.dpk', '.inc', '.lpr', '.pp']);
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
  Result := Active and FPattern.Active and (FFileName <> '');
end;

procedure TAtlasIdeCodeLinks.Clear;
begin
  FFileName := '';
  FVersion := 0;
  FPatternKey := '';
  FPattern := TAtlasIssueKeyPattern.Empty;
  FLines := nil;
  FStates := nil;
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
    CheckHover;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.IssueLinks, E);
  end;
end;

procedure TAtlasIdeCodeLinks.Update;
var
  mView: IOTAEditView;
  mSnapshot: TAtlasEditorSnapshot;
  mTarget: TAtlasTrackerTarget;
  mCommit, mKey: string;
  mHad: Boolean;
begin
  mHad := FFileName <> '';
  mView := nil;
  if Active and FHooks.Target(mTarget) then
  begin
    mView := TAtlasEditorBuffer.ActiveView;
  end;
  if (mView = nil) or (mView.Buffer = nil) or not IsPascal(mView.Buffer.FileName) then
  begin
    SetHover(Default(THit), False);
    if mHad then
    begin
      Clear;
      Invalidate;
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
  if (mSnapshot.Version = FVersion) and SameText(mSnapshot.FileName, FFileName) and (mKey = FPatternKey) then
  begin
    Exit;
  end;
  // Neuer Stand: nur die Zustände der Zeilen; Kennungen sucht erst das Zeichnen der sichtbaren Zeilen.
  SetHover(Default(THit), False);
  FFileName := mSnapshot.FileName;
  FVersion := mSnapshot.Version;
  FPatternKey := mKey;
  FTarget := mTarget;
  FPattern := TAtlasIssueKeyPattern.ForTarget(mTarget);
  FCommit := mCommit;
  FLines := TTextLines.SplitLines(mSnapshot.Text);
  FStates := TAtlasCodeLinks.States(FLines);
  FTabWidth := TAtlasEditorBuffer.TabWidth(mView.Buffer);
  FMatches.Clear;
  FHits.Clear;
  Invalidate;
end;

function TAtlasIdeCodeLinks.MatchesOf(ALine: Integer): TArray<TAtlasIssueKeyMatch>;
begin
  if FMatches.TryGetValue(ALine, Result) then
  begin
    Exit;
  end;
  Result := TAtlasCodeLinks.LineMatches(FPattern, FLines[ALine], FStates[ALine], FCommit);
  FMatches.Add(ALine, Result);
end;

procedure TAtlasIdeCodeLinks.PaintMatches(const Rect: TRect; const Context: INTACodeEditorPaintContext;
  const AText: string; const AMatches: TArray<TAtlasIssueKeyMatch>);
var
  mMatch: TAtlasIssueKeyMatch;
  mFirst, mLast, mCode: TRect;
  mBack: TAtlasColor;
  mColor: COLORREF;
  mDC: HDC;
  mSaved, mX, mY: Integer;
  mHit: THit;
  mHits: TArray<THit>;
begin
  mBack := TAtlasIdeStyle.SampleBack(Context.Canvas, Rect.Right - 2, Rect.Top + 1);
  mColor := COLORREF(ColorToRGB(TColor(TAtlasColorMath.Mix(TAtlasColors.ForBackground(mBack).Accent, mBack,
    LineStrength))));
  mDC := Context.Canvas.Handle;
  mCode := Context.LineState.CodeRect;
  mHits := nil;
  mSaved := SaveDC(mDC);
  try
    if mCode.Right > mCode.Left then
    begin
      IntersectClipRect(mDC, mCode.Left, Rect.Top, Rect.Right, Rect.Bottom);
    end;
    mY := Rect.Bottom - 2;
    for mMatch in AMatches do
    begin
      mFirst := Context.EditorState.GetCharacterPosPx(TLspSession.IndexToColumn(AText, mMatch.Character, FTabWidth),
        Context.EditorLineNum);
      mLast := Context.EditorState.GetCharacterPosPx(
        TLspSession.IndexToColumn(AText, mMatch.Character + mMatch.Length, FTabWidth), Context.EditorLineNum);
      // Gepunktet wie die Links des Editors: jeder zweite Pixel.
      mX := mFirst.Left;
      while mX < mLast.Left do
      begin
        SetPixel(mDC, mX, mY, mColor);
        Inc(mX, 2);
      end;
      mHit := Default(THit);
      mHit.Wnd := Context.EditControl.Handle;
      mHit.FileName := Context.FileName;
      mHit.Line := Context.LogicalLineNum - 1;
      mHit.TopRow := Context.EditView.TopRow;
      mHit.Rect := TRect.Create(mFirst.Left, Rect.Top, Max(mLast.Left, mFirst.Left + 1), Rect.Bottom);
      mHit.Match := mMatch;
      mHits := mHits + [mHit];
    end;
  finally
    RestoreDC(mDC, mSaved);
  end;
  FHits.AddOrSetValue(Context.EditorLineNum, mHits);
end;

procedure TAtlasIdeCodeLinks.PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
  var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  mLineState: INTACodeEditorLineState;
  mMatches: TArray<TAtlasIssueKeyMatch>;
  mText: string;
  mLine: Integer;
begin
  if BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) or (FFileName = '') or
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
    if not Shown or not SameText(Context.FileName, FFileName) then
    begin
      Exit;
    end;
    mLineState := Context.LineState;
    if mLineState = nil then
    begin
      Exit;
    end;
    mLine := Context.LogicalLineNum - 1;
    if (mLine < 0) or (mLine >= Length(FLines)) then
    begin
      Exit;
    end;
    mText := FLines[mLine];
    // Nur, wenn die Zeile im Editor dem Stand entspricht (sonst kommt gleich ein neuer Takt).
    if TrimRight(mLineState.Text) <> TrimRight(mText) then
    begin
      Exit;
    end;
    mMatches := MatchesOf(mLine);
    if Length(mMatches) > 0 then
    begin
      PaintMatches(Rect, Context, mText, mMatches);
    end;
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.IssueLinks, E);
  end;
end;

function TAtlasIdeCodeLinks.HitAt(AWnd: HWND; X, Y: Integer; out AHit: THit): Boolean;
var
  mHits: TArray<THit>;
  mHit: THit;
  mView: IOTAEditView;
begin
  AHit := Default(THit);
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
  for mHits in FHits.Values do
  begin
    for mHit in mHits do
    begin
      if (mHit.Wnd = AWnd) and PtInRect(mHit.Rect, Point(X, Y)) then
      begin
        // Nur, wenn die Kennung noch dort steht: gleiche Datei, nicht gescrollt.
        if not SameText(mHit.FileName, mView.Buffer.FileName) or (mHit.TopRow <> mView.TopRow) then
        begin
          Exit;
        end;
        AHit := mHit;
        Exit(True);
      end;
    end;
  end;
end;

function TAtlasIdeCodeLinks.TargetOf(const AHit: THit): TAtlasTrackerTarget;
begin
  Result := AHit.Match.IssueTarget(FTarget);
end;

function TAtlasIdeCodeLinks.Preview: TAtlasIdeIssuePreview;
begin
  Result := nil;
  if Assigned(FHooks.Preview) then
  begin
    Result := FHooks.Preview();
  end;
end;

function TAtlasIdeCodeLinks.CanStart: Boolean;
begin
  Result := Assigned(FHooks.CanStart) and Assigned(FHooks.Start) and FHooks.CanStart();
end;

procedure TAtlasIdeCodeLinks.SetHover(const AHit: THit; AOn: Boolean);
var
  mChanged: Boolean;
begin
  mChanged := AOn <> FHovering;
  if AOn and FHovering then
  begin
    mChanged := (AHit.Wnd <> FHover.Wnd) or (AHit.Line <> FHover.Line) or
      (AHit.Match.Character <> FHover.Match.Character) or not SameText(AHit.FileName, FHover.FileName);
  end;
  if not mChanged then
  begin
    Exit;
  end;
  HideTip;
  FHovering := AOn;
  FHover := AHit;
  FHoverSince := TThread.GetTickCount64;
end;

procedure TAtlasIdeCodeLinks.EditorMouseMove(const Editor: TWinControl; Shift: TShiftState; X, Y: Integer);
var
  mHit: THit;
begin
  try
    if (Editor = nil) or not Editor.HandleAllocated or not HitAt(Editor.Handle, X, Y, mHit) then
    begin
      // Über dem Tooltip selbst bleibt er offen (CheckHover).
      if not (FTip.IsShown and PtInRect(FTip.BoundsRect, Mouse.CursorPos)) then
      begin
        SetHover(Default(THit), False);
      end;
      Exit;
    end;
    SetHover(mHit, True);
    FHoverScreen := TRect.Create(Editor.ClientToScreen(mHit.Rect.TopLeft),
      Editor.ClientToScreen(mHit.Rect.BottomRight));
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.IssueLinks, E);
  end;
end;

procedure TAtlasIdeCodeLinks.CheckHover;
begin
  if not FHovering then
  begin
    Exit;
  end;
  if not Shown then
  begin
    SetHover(Default(THit), False);
    Exit;
  end;
  // Maus hat die Kennung verlassen, ohne dass der Editor es gemeldet hat (anderes Fenster).
  if not PtInRect(FHoverScreen, Mouse.CursorPos) and not (FTip.IsShown and PtInRect(FTip.BoundsRect,
    Mouse.CursorPos)) then
  begin
    SetHover(Default(THit), False);
    Exit;
  end;
  if not FTip.IsShown and (TThread.GetTickCount64 - FHoverSince >= TAtlasCloseRules.TooltipShowDelayMs) then
  begin
    ShowTip(FHover);
  end;
end;

procedure TAtlasIdeCodeLinks.HideTip;
begin
  FTipKey := '';
  if (FTip <> nil) and FTip.IsShown then
  begin
    FTip.HidePopup;
  end;
end;

procedure TAtlasIdeCodeLinks.ShowState(const AKey: string; AState: TAtlasIssueTipState;
  const ADetails: TAtlasTrackerDetails; AError: TAtlasCiFetchError);
var
  mTitle, mText: string;
begin
  TAtlasIssueTip.Compose(AKey, AState, ADetails, AError, TTimeZone.Local.ToUniversalTime(Now),
    TAtlasIdeIssuePreview.Active, mTitle, mText);
  FTipKey := AKey;
  FTip.ShowNote(mTitle, mText, Point(FHoverScreen.Left, FHoverScreen.Bottom + 2));
end;

procedure TAtlasIdeCodeLinks.ShowTip(const AHit: THit);
var
  mPreview: TAtlasIdeIssuePreview;
  mTarget: TAtlasTrackerTarget;
  mDetails: TAtlasTrackerDetails;
  mKey: string;
  mSerial: Integer;
  mCached: Boolean;
begin
  mPreview := Preview;
  if mPreview = nil then
  begin
    Exit;
  end;
  mTarget := TargetOf(AHit);
  mKey := AHit.Match.IssueKey;
  mCached := mPreview.Peek(mTarget, mKey, mDetails);
  if mCached then
  begin
    ShowState(AHit.Match.Key, TAtlasIssueTipState.Found, mDetails, TAtlasCiFetchError.None);
  end
  else
  begin
    ShowState(AHit.Match.Key, TAtlasIssueTipState.Loading, mDetails, TAtlasCiFetchError.None);
  end;
  // Erst der Hover fragt; ein frischer Stand braucht keine Abfrage.
  if mCached and TAtlasIdeIssuePreview.Fresh(mDetails) then
  begin
    Exit;
  end;
  mSerial := FSerialOf;
  mKey := AHit.Match.Key;
  mPreview.Lookup(mTarget, AHit.Match.IssueKey,
    procedure(ASucceeded: Boolean; const ADetails: TAtlasTrackerDetails; AError: TAtlasCiFetchError)
    begin
      if (FInstance <> nil) and (FInstance.FSerialOf = mSerial) then
      begin
        FInstance.LookedUp(mKey, ASucceeded, ADetails, AError);
      end;
    end);
end;

procedure TAtlasIdeCodeLinks.LookedUp(const AKey: string; ASucceeded: Boolean; const ADetails: TAtlasTrackerDetails;
  AError: TAtlasCiFetchError);
var
  mCached: TAtlasTrackerDetails;
begin
  // Nur, solange der Tooltip noch diese Kennung zeigt.
  if not FHovering or not FTip.IsShown or (FTipKey <> AKey) then
  begin
    Exit;
  end;
  if ASucceeded then
  begin
    ShowState(AKey, TAtlasIssueTipState.Found, ADetails, AError);
  end
  else if AError = TAtlasCiFetchError.NotFound then
  begin
    ShowState(AKey, TAtlasIssueTipState.NotFound, ADetails, AError);
  end
  else if not ((Preview <> nil) and Preview.Peek(TargetOf(FHover), FHover.Match.IssueKey, mCached)) then
  begin
    // Ohne Netz bleibt ein vorhandener Stand stehen; sonst der Grund.
    ShowState(AKey, TAtlasIssueTipState.Failed, ADetails, AError);
  end;
end;

procedure TAtlasIdeCodeLinks.Act(const AHit: THit; ACommand: Integer);
begin
  case ACommand of
    MenuShow:
      if Assigned(FHooks.Show) then
      begin
        FHooks.Show(TargetOf(AHit), AHit.Match.IssueKey);
      end;
    MenuBrowse:
      if Assigned(FHooks.Browse) then
      begin
        FHooks.Browse(TargetOf(AHit), AHit.Match.IssueKey);
      end;
    MenuCopy:
      Clipboard.AsText := AHit.Match.Key;
    MenuStart:
      if CanStart then
      begin
        FHooks.Start(TargetOf(AHit), AHit.Match.IssueKey);
      end;
  end;
end;

procedure TAtlasIdeCodeLinks.AppMessage(var Msg: TMsg; var Handled: Boolean);
var
  mHit: THit;
  mWhere: TPoint;
  mCommand, mSerial: Integer;
begin
  try
    if (Msg.message = FSwallowUp) and (FSwallowUp <> 0) then
    begin
      // Loslassen zum geschluckten Drücken: Ohne Drücken darf auch es nicht an den Editor.
      FSwallowUp := 0;
      Handled := True;
      if GetCapture = Msg.hwnd then
      begin
        ReleaseCapture;
      end;
      if Msg.message = WM_RBUTTONUP then
      begin
        mHit := FMenuHit;
        mWhere := Mouse.CursorPos;
        mSerial := FSerialOf;
        TAtlasMainThread.ForceQueue(TAtlasFeature.IssueLinks,
          procedure
          begin
            if (FInstance <> nil) and (FInstance.FSerialOf = mSerial) then
            begin
              TAtlasGuard.Run(TAtlasFeature.IssueLinks,
                procedure
                begin
                  FInstance.ShowMenu(mHit, mWhere);
                end);
            end;
          end);
      end;
      Exit;
    end;
    if not ((Msg.message = WM_LBUTTONDOWN) or (Msg.message = WM_RBUTTONDOWN)) then
    begin
      Exit;
    end;
    if (Msg.message = WM_LBUTTONDOWN) and ((Msg.wParam and MK_CONTROL) = 0) then
    begin
      Exit;
    end;
    // Umschalt+Rechtsklick: Kontextmenü der IDE.
    if (Msg.message = WM_RBUTTONDOWN) and ((Msg.wParam and MK_SHIFT) <> 0) then
    begin
      Exit;
    end;
    if not HitAt(Msg.hwnd, SmallInt(LoWord(Msg.lParam)), SmallInt(HiWord(Msg.lParam)), mHit) then
    begin
      Exit;
    end;
    Handled := True;
    HideTip;
    if Msg.message = WM_RBUTTONDOWN then
    begin
      // Das eigene Menü ersetzt das Kontextmenü der IDE; es öffnet beim Loslassen.
      FSwallowUp := WM_RBUTTONUP;
      FMenuHit := mHit;
      Exit;
    end;
    // Strg+Klick: Vorschau bzw. Browser; Strg+Umschalt+Klick: Browser. Die IDE springt nicht.
    FSwallowUp := WM_LBUTTONUP;
    mCommand := MenuShow;
    if (Msg.wParam and MK_SHIFT) <> 0 then
    begin
      mCommand := MenuBrowse;
    end;
    mSerial := FSerialOf;
    TAtlasMainThread.ForceQueue(TAtlasFeature.IssueLinks,
      procedure
      begin
        if (FInstance <> nil) and (FInstance.FSerialOf = mSerial) then
        begin
          TAtlasGuard.Run(TAtlasFeature.IssueLinks,
            procedure
            begin
              FInstance.Act(mHit, mCommand);
            end);
        end;
      end);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.IssueLinks, E);
  end;
end;

function TAtlasIdeCodeLinks.AddMenuItem(const ACaption: string; ATag: Integer): TMenuItem;
begin
  Result := TMenuItem.Create(FMenu);
  Result.Caption := ACaption;
  Result.Tag := ATag;
  Result.OnClick := MenuClick;
  FMenu.Items.Add(Result);
end;

procedure TAtlasIdeCodeLinks.ShowMenu(const AHit: THit; const APoint: TPoint);
begin
  FMenu.Items.Clear;
  FMenuHit := AHit;
  AddMenuItem(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueLinkMenuShow), MenuShow).Default := True;
  AddMenuItem(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewBrowse), MenuBrowse);
  AddMenuItem(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewCopyKey), MenuCopy);
  AddMenuItem('-', 0).OnClick := nil;
  AddMenuItem(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewStart), MenuStart).Enabled := CanStart;
  FMenu.Popup(APoint.X, APoint.Y);
end;

procedure TAtlasIdeCodeLinks.MenuClick(Sender: TObject);
var
  mCommand: Integer;
  mHit: THit;
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
