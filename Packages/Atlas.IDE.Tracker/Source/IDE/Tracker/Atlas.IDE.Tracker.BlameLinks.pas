unit Atlas.IDE.Tracker.BlameLinks;

// Issues in der Zeilenhistorie (#1275): Die Zeilenhistorie am Ende der
// Cursorzeile (editor.gitBlame, Atlas.IDE.Editor.LineChanges) zeigt die
// Kennungen aus der Commit-Nachricht („anna, vor 3 Mon. · ATL-97 · Betreff“),
// ihr Hover Titel und Zustand je Kennung und den Link „Issues zu dieser
// Methode (n)“. Strg+Klick auf die Randanzeige öffnet die Issue-Vorschau
// (#1264), Strg+Umschalt+Klick den Browser, Rechtsklick ein Menü. Den Befehl
// „Issues zu dieser Methode“ zeigt TAtlasIdeBlameScope
// (Atlas.IDE.Tracker.BlameScope) im Ergebnisfenster.
// - Der Editor kennt den Tracker nicht: LineHooks liefert die Haken für
//   TAtlasIdeLineChanges.SetBlameHooks, die Komposition setzt sie.
// - Muster, Vorschau und „Issue anzeigen“ wie bei den Kennungen im Code
//   (TAtlasCodeLinksHooks aus „Meine Issues“).
// - Die ganzen Nachrichten lädt die Zeilenhistorie nach jedem blame im
//   Hintergrund (IAtlasVcsLineHistory.Messages). Beim Zeichnen nur Speicher;
//   erst der Hover fragt den Tracker (Peek, sonst Lookup), der Befehl fragt
//   die Titel der gefundenen Issues nach.
// - Die Zahl im Hover zählt die Issues des Bereichs einmal je Bereich und
//   Stand der Arbeitskopie (ChangeMarker) im Hintergrund.
// - issues.blameLinks aus oder Atlas aus: Zeilenhistorie wie bisher, kein
//   Laden der Nachrichten, kein Abfangen von Klicks; den Befehl blendet die
//   Palette aus.
// Gesichert über TAtlasFeature.BlameIssues (#493). Nur im Hauptthread.

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Types,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.AppEvnts,
  Vcl.Menus,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.CodeLinks,
  Atlas.Core.Tracker.BlameLinks,
  Atlas.UI.Tracker.IssueTip,
  Atlas.IDE.Editor.LineChanges,
  Atlas.IDE.Tracker.IssuePreview,
  Atlas.IDE.Tracker.CodeLinks,
  Atlas.IDE.Tracker.BlameScope;

type
  TAtlasIdeBlameLinks = class
  private const
    MenuShow = 1;
    MenuBrowse = 2;
    MenuCopy = 3;
    MenuScope = 4;
    /// <summary>Menüeinträge tragen Kennung * MenuStride + Befehl.</summary>
    MenuStride = 8;
  private type
    /// <summary>Stand einer Kennung im Hover, solange der Zwischenspeicher nichts hat.</summary>
    TKeyState = record
      State: TAtlasIssueTipState;
      Error: TAtlasCiFetchError;
    end;
  private class var
    FInstance: TAtlasIdeBlameLinks;
    FSerial: Integer;
  private
    FHooks: TAtlasCodeLinksHooks;
    FSerialOf: Integer;
    FAppEvents: TApplicationEvents;
    FMenu: TPopupMenu;
    FMenuCommit: TAtlasBlameCommit;
    /// <summary>Nach einem geschluckten Drücken auch das Loslassen schlucken.</summary>
    FSwallowUp: Cardinal;
    // Hover: Stand je Kennung (Muster|Kennung), für einen Commit; während Describe kein Neuaufbau.
    FKeyStates: TDictionary<string, TKeyState>;
    FStatesRevision: string;
    FDescribing: Boolean;
    // Zahl „Issues zu dieser Methode (n)“: Bereich, Zahl (-1 = unbekannt), läuft.
    FCountKey: string;
    FCount: Integer;
    FCountBusy: Boolean;
    // „Issues zu dieser Methode“.
    FScope: TAtlasIdeBlameScope;
    function PatternOf(out ATarget: TAtlasTrackerTarget; out APattern: TAtlasIssueKeyPattern): Boolean;
    procedure Ask(const ATarget: TAtlasTrackerTarget; const APattern: TAtlasIssueKeyPattern;
      const AMatch: TAtlasIssueKeyMatch);
    function KeyText(const ATarget: TAtlasTrackerTarget; const APattern: TAtlasIssueKeyPattern;
      const AMatch: TAtlasIssueKeyMatch): string;
    function Describe(const ACommit: TAtlasBlameCommit; var AText: string; out ALinks: TArray<string>): Boolean;
    procedure Link(const ACommit: TAtlasBlameCommit; AIndex: Integer);
    function ScopeCount(const AFileName: string; ALine: Integer; out AMethod: Boolean): Integer;
    procedure AppMessage(var Msg: TMsg; var Handled: Boolean);
    procedure Act(const ACommit: TAtlasBlameCommit; ACommand, AKey: Integer);
    procedure ShowMenu(const ACommit: TAtlasBlameCommit; const APoint: TPoint);
    procedure MenuClick(Sender: TObject);
    function AddMenuItem(AParent: TMenuItem; const ACaption: string; ATag: Integer): TMenuItem;
    class function MessageMatches(const APattern: TAtlasIssueKeyPattern;
      const ACommit: TAtlasBlameCommit): TArray<TAtlasIssueKeyMatch>; static;
  public
    /// <summary>AHooks wie für die Kennungen im Code (Tracker, Vorschau, Anzeigen, Browser).</summary>
    constructor Create(const AHooks: TAtlasCodeLinksHooks);
    destructor Destroy; override;
    /// <summary>Haken für TAtlasIdeLineChanges.SetBlameHooks.</summary>
    function LineHooks: TAtlasBlameHooks;
    /// <summary>Befehl „Issues zu dieser Methode“ für die Cursorzeile des Editors vorn.</summary>
    procedure ShowScope;
    /// <summary>issues.blameLinks an (für die Palette)?</summary>
    class function Enabled: Boolean; static;
  end;

implementation

uses
  Vcl.Clipbrd,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.UI.Tracker.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Vcs.Service,
  Atlas.IDE.Tracker.IssueLookups;

type
  /// <summary>Alles für das Zählen der Issues eines Bereichs im Hintergrund.</summary>
  TCountJob = record
    Key: string;
    FileName: string;
    Lines: TArray<string>;
    First: Integer;
    Last: Integer;
    Max: Integer;
    Serial: Integer;
    Vcs: IAtlasVersionControl;
    Pattern: TAtlasIssueKeyPattern;
  end;

/// <summary>Messages-Haken der Zeilenhistorie (Hintergrund): ganze Nachrichten zu den Revisionen aus blame.</summary>
function LoadMessages(const AVcs: IAtlasVersionControl; const AFileName: string;
  const ALines: TArray<TAtlasVcsBlameLine>): TArray<TAtlasVcsRevisionMessage>;
var
  mHistory: IAtlasVcsLineHistory;
begin
  Result := nil;
  if (AVcs = nil) or not Supports(AVcs, IAtlasVcsLineHistory, mHistory) then
  begin
    Exit;
  end;
  // Gescheitert: Die Randanzeige bleibt wie bisher (Betreff aus blame).
  if mHistory.Messages(AFileName, TAtlasBlameLinks.BlameRevisions(ALines), Result) <> TAtlasVcsOutcome.Ok then
  begin
    Result := nil;
  end;
end;

{ TAtlasIdeBlameLinks }

constructor TAtlasIdeBlameLinks.Create(const AHooks: TAtlasCodeLinksHooks);
begin
  inherited Create;
  FHooks := AHooks;
  Inc(FSerial);
  FSerialOf := FSerial;
  FInstance := Self;
  FCount := -1;
  FKeyStates := TDictionary<string, TKeyState>.Create;
  FMenu := TPopupMenu.Create(nil);
  FAppEvents := TApplicationEvents.Create(nil);
  FAppEvents.OnMessage := AppMessage;
  FScope := TAtlasIdeBlameScope.Create(AHooks);
end;

destructor TAtlasIdeBlameLinks.Destroy;
begin
  if FInstance = Self then
  begin
    FInstance := nil;
  end;
  FreeAndNil(FScope);
  if FAppEvents <> nil then
  begin
    FAppEvents.OnMessage := nil;
    FreeAndNil(FAppEvents);
  end;
  FreeAndNil(FMenu);
  FreeAndNil(FKeyStates);
  FMenuCommit := Default(TAtlasBlameCommit);
  FHooks := Default(TAtlasCodeLinksHooks);
  inherited Destroy;
end;

class function TAtlasIdeBlameLinks.Enabled: Boolean;
begin
  Result := TAtlasIdeBlameScope.Enabled;
end;

function TAtlasIdeBlameLinks.PatternOf(out ATarget: TAtlasTrackerTarget;
  out APattern: TAtlasIssueKeyPattern): Boolean;
begin
  Result := TAtlasIdeBlameScope.PatternOf(FHooks, ATarget, APattern);
end;

class function TAtlasIdeBlameLinks.MessageMatches(const APattern: TAtlasIssueKeyPattern;
  const ACommit: TAtlasBlameCommit): TArray<TAtlasIssueKeyMatch>;
begin
  Result := TAtlasBlameLinks.Keys(APattern, ACommit.Message);
end;

function TAtlasIdeBlameLinks.LineHooks: TAtlasBlameHooks;
var
  mSerial: Integer;
begin
  mSerial := FSerialOf;
  Result := Default(TAtlasBlameHooks);
  Result.Wanted :=
    function: Boolean
    var
      mTarget: TAtlasTrackerTarget;
      mPattern: TAtlasIssueKeyPattern;
    begin
      Result := (FInstance <> nil) and (FInstance.FSerialOf = mSerial) and FInstance.PatternOf(mTarget, mPattern);
    end;
  Result.Messages := LoadMessages;
  Result.Suffix :=
    function(AMessage: string): string
    var
      mTarget: TAtlasTrackerTarget;
      mPattern: TAtlasIssueKeyPattern;
    begin
      Result := '';
      if (FInstance <> nil) and (FInstance.FSerialOf = mSerial) and FInstance.PatternOf(mTarget, mPattern) then
      begin
        Result := TAtlasBlameLinks.CaptionSuffix(TAtlasBlameLinks.Keys(mPattern, AMessage));
      end;
    end;
  Result.Describe :=
    function(const ACommit: TAtlasBlameCommit; var AText: string; out ALinks: TArray<string>): Boolean
    begin
      ALinks := nil;
      Result := (FInstance <> nil) and (FInstance.FSerialOf = mSerial) and FInstance.Describe(ACommit, AText, ALinks);
    end;
  Result.Link :=
    procedure(const ACommit: TAtlasBlameCommit; AIndex: Integer)
    begin
      if (FInstance <> nil) and (FInstance.FSerialOf = mSerial) then
      begin
        TAtlasGuard.Run(TAtlasFeature.BlameIssues,
          procedure
          begin
            FInstance.Link(ACommit, AIndex);
          end);
      end;
    end;
end;

/// <summary>Schlüssel des Stands einer Kennung im Hover (Muster|Kennung).</summary>
function StateKey(const APattern: TAtlasIssueKeyPattern; const AMatch: TAtlasIssueKeyMatch): string;
begin
  Result := APattern.Key + #1 + UpperCase(AMatch.Key);
end;

procedure TAtlasIdeBlameLinks.Ask(const ATarget: TAtlasTrackerTarget; const APattern: TAtlasIssueKeyPattern;
  const AMatch: TAtlasIssueKeyMatch);
var
  mPreview: TAtlasIdeIssuePreview;
  mDetails: TAtlasTrackerDetails;
  mState: TKeyState;
  mKey: string;
  mSerial: Integer;
begin
  mPreview := TAtlasIdeBlameScope.Preview(FHooks);
  mKey := StateKey(APattern, AMatch);
  // Einmal je Hover und Kennung; ein frischer Stand braucht keine Abfrage.
  if (mPreview = nil) or FKeyStates.ContainsKey(mKey) then
  begin
    Exit;
  end;
  if mPreview.Lookups.Peek(AMatch.IssueTarget(ATarget), AMatch.IssueKey, mDetails) and
    TAtlasIdeIssueLookups.Fresh(mDetails) then
  begin
    Exit;
  end;
  mState.State := TAtlasIssueTipState.Loading;
  mState.Error := TAtlasCiFetchError.None;
  FKeyStates.Add(mKey, mState);
  mSerial := FSerialOf;
  mPreview.Lookups.Lookup(AMatch.IssueTarget(ATarget), AMatch.IssueKey,
    procedure(ASucceeded: Boolean; const ADetails: TAtlasTrackerDetails; AError: TAtlasCiFetchError)
    var
      mDone: TKeyState;
    begin
      if (FInstance = nil) or (FInstance.FSerialOf <> mSerial) or not FInstance.FKeyStates.ContainsKey(mKey) then
      begin
        Exit;
      end;
      mDone.Error := AError;
      if ASucceeded then
      begin
        mDone.State := TAtlasIssueTipState.Found;
      end
      else if AError = TAtlasCiFetchError.NotFound then
      begin
        mDone.State := TAtlasIssueTipState.NotFound;
      end
      else
      begin
        mDone.State := TAtlasIssueTipState.Failed;
      end;
      FInstance.FKeyStates[mKey] := mDone;
      // Kam die Antwort sofort (aus Describe heraus), baut Describe den Text selbst.
      if not FInstance.FDescribing then
      begin
        TAtlasIdeLineChanges.RefreshBlameTip;
      end;
    end);
end;

function TAtlasIdeBlameLinks.KeyText(const ATarget: TAtlasTrackerTarget; const APattern: TAtlasIssueKeyPattern;
  const AMatch: TAtlasIssueKeyMatch): string;
var
  mPreview: TAtlasIdeIssuePreview;
  mDetails: TAtlasTrackerDetails;
  mState: TKeyState;
  mKnown, mCached: Boolean;
begin
  mPreview := TAtlasIdeBlameScope.Preview(FHooks);
  mCached := False;
  mDetails := TAtlasTrackerDetails.Empty;
  if mPreview <> nil then
  begin
    mCached := mPreview.Lookups.Peek(AMatch.IssueTarget(ATarget), AMatch.IssueKey, mDetails);
  end;
  mKnown := FKeyStates.TryGetValue(StateKey(APattern, AMatch), mState);
  if mKnown and (mState.State = TAtlasIssueTipState.NotFound) then
  begin
    Result := TAtlasIssueTip.KeyLine(AMatch.Key, TAtlasIssueTipState.NotFound, mDetails, mState.Error);
  end
  else if mCached then
  begin
    // Ohne Netz bleibt ein vorhandener Stand stehen.
    Result := TAtlasIssueTip.KeyLine(AMatch.Key, TAtlasIssueTipState.Found, mDetails, TAtlasCiFetchError.None);
  end
  else if mKnown and (mState.State = TAtlasIssueTipState.Failed) then
  begin
    Result := TAtlasIssueTip.KeyLine(AMatch.Key, TAtlasIssueTipState.Failed, mDetails, mState.Error);
  end
  else
  begin
    Result := TAtlasIssueTip.KeyLine(AMatch.Key, TAtlasIssueTipState.Loading, mDetails, TAtlasCiFetchError.None);
  end;
end;

function TAtlasIdeBlameLinks.Describe(const ACommit: TAtlasBlameCommit; var AText: string;
  out ALinks: TArray<string>): Boolean;
var
  mTarget: TAtlasTrackerTarget;
  mPattern: TAtlasIssueKeyPattern;
  mMatches: TArray<TAtlasIssueKeyMatch>;
  mMatch: TAtlasIssueKeyMatch;
  mMethod: Boolean;
  mCount: Integer;
begin
  ALinks := nil;
  Result := False;
  if not PatternOf(mTarget, mPattern) then
  begin
    Exit;
  end;
  // Anderer Commit: Stände der letzten Kennungen verwerfen, beim nächsten Hover wird neu gefragt.
  if ACommit.Revision <> FStatesRevision then
  begin
    FKeyStates.Clear;
    FStatesRevision := ACommit.Revision;
  end;
  mMatches := MessageMatches(mPattern, ACommit);
  FDescribing := True;
  try
    for mMatch in mMatches do
    begin
      Ask(mTarget, mPattern, mMatch);
    end;
  finally
    FDescribing := False;
  end;
  for mMatch in mMatches do
  begin
    ALinks := ALinks + [KeyText(mTarget, mPattern, mMatch)];
  end;
  if Length(mMatches) > 0 then
  begin
    AText := TrimRight(AText) + #10#10 + TAtlasIssueTip.BlameFooter(TAtlasIdeIssuePreview.Active);
  end;
  mCount := ScopeCount(ACommit.FileName, ACommit.Line, mMethod);
  ALinks := ALinks + [TAtlasIssueTip.ScopeLink(mMethod, mCount)];
  Result := True;
end;

function CountKey(const AFileName: string; AFirst, ALast: Integer; const AName: string;
  const AVcs: IAtlasVersionControl; const APattern: TAtlasIssueKeyPattern): string;
begin
  // Gezählt je Bereich und Stand der Arbeitskopie; ein Commit oder Wechsel des Branchs zählt neu.
  Result := AFileName + #1 + IntToStr(AFirst) + #1 + IntToStr(ALast) + #1 + AName + #1 + AVcs.ChangeMarker + #1 +
    APattern.Key;
end;

/// <summary>Gezählt (Hauptthread): Zahl merken und den Hover neu zeichnen, solange der Bereich derselbe ist.
/// </summary>
procedure CountDone(const AJob: TCountJob; const AHistory: TAtlasBlameHistory);
var
  mOwner: TAtlasIdeBlameLinks;
begin
  mOwner := TAtlasIdeBlameLinks.FInstance;
  if (mOwner = nil) or (mOwner.FSerialOf <> AJob.Serial) then
  begin
    Exit;
  end;
  mOwner.FCountBusy := False;
  if mOwner.FCountKey <> AJob.Key then
  begin
    Exit;
  end;
  if AHistory.Outcome = TAtlasBlameHistoryOutcome.Failed then
  begin
    // Ohne Zahl; der nächste Hover versucht es wieder.
    mOwner.FCountKey := '';
  end
  else
  begin
    mOwner.FCount := Length(TAtlasBlameLinks.Group(AJob.Pattern, AHistory.Commits).Issues);
  end;
  TAtlasIdeLineChanges.RefreshBlameTip;
end;

/// <summary>Commits des Bereichs im Hintergrund lesen; False, wenn die Versionsverwaltung beendet ist.</summary>
function StartCount(const AJob: TCountJob): Boolean;
var
  mJob: TCountJob;
  mHistory: TAtlasBlameHistory;
begin
  mJob := AJob;
  mHistory := Default(TAtlasBlameHistory);
  Result := TAtlasIdeVcs.Run(
    procedure
    begin
      mHistory := TAtlasBlameLinks.History(mJob.Vcs, mJob.FileName, mJob.Lines, mJob.First, mJob.Last, mJob.Max);
    end,
    procedure
    begin
      CountDone(mJob, mHistory);
    end);
end;

function TAtlasIdeBlameLinks.ScopeCount(const AFileName: string; ALine: Integer; out AMethod: Boolean): Integer;
var
  mJob: TCountJob;
  mText, mName: string;
  mTarget: TAtlasTrackerTarget;
begin
  Result := -1;
  AMethod := False;
  mJob := Default(TCountJob);
  if not TAtlasIdeBlameScope.BufferLines(AFileName, mJob.Lines, mText) or not PatternOf(mTarget, mJob.Pattern) then
  begin
    Exit;
  end;
  AMethod := TAtlasBlameLinks.Scope(mText, ALine, mJob.First, mJob.Last, mName);
  mJob.Vcs := TAtlasIdeVcs.ForFolder(ExtractFileDir(AFileName));
  if (mJob.Vcs = nil) or (mJob.Vcs.Kind = TAtlasVcsKind.None) then
  begin
    Exit;
  end;
  mJob.Key := CountKey(AFileName, mJob.First, mJob.Last, mName, mJob.Vcs, mJob.Pattern);
  if mJob.Key = FCountKey then
  begin
    Result := FCount;
  end
  else if not FCountBusy then
  begin
    FCountKey := mJob.Key;
    FCount := -1;
    FCountBusy := True;
    mJob.FileName := AFileName;
    mJob.Max := TAtlasIdeSettings.Current.IssuesBlameMaxRevisions;
    mJob.Serial := FSerialOf;
    if not StartCount(mJob) then
    begin
      FCountBusy := False;
    end;
  end;
end;

procedure TAtlasIdeBlameLinks.Link(const ACommit: TAtlasBlameCommit; AIndex: Integer);
var
  mTarget: TAtlasTrackerTarget;
  mPattern: TAtlasIssueKeyPattern;
  mMatches: TArray<TAtlasIssueKeyMatch>;
begin
  if not PatternOf(mTarget, mPattern) then
  begin
    Exit;
  end;
  mMatches := MessageMatches(mPattern, ACommit);
  if (AIndex >= 0) and (AIndex < Length(mMatches)) then
  begin
    Act(ACommit, MenuShow, AIndex);
  end
  else
  begin
    FScope.ShowAt(ACommit.FileName, ACommit.Line);
  end;
end;

procedure TAtlasIdeBlameLinks.Act(const ACommit: TAtlasBlameCommit; ACommand, AKey: Integer);
var
  mTarget: TAtlasTrackerTarget;
  mPattern: TAtlasIssueKeyPattern;
  mMatches: TArray<TAtlasIssueKeyMatch>;
  mMatch: TAtlasIssueKeyMatch;
begin
  if ACommand = MenuScope then
  begin
    FScope.ShowAt(ACommit.FileName, ACommit.Line);
    Exit;
  end;
  if not PatternOf(mTarget, mPattern) then
  begin
    Exit;
  end;
  mMatches := MessageMatches(mPattern, ACommit);
  if (AKey < 0) or (AKey >= Length(mMatches)) then
  begin
    Exit;
  end;
  mMatch := mMatches[AKey];
  case ACommand of
    MenuShow:
      if Assigned(FHooks.Show) then
      begin
        FHooks.Show(mMatch.IssueTarget(mTarget), mMatch.IssueKey);
      end;
    MenuBrowse:
      if Assigned(FHooks.Browse) then
      begin
        FHooks.Browse(mMatch.IssueTarget(mTarget), mMatch.IssueKey);
      end;
    MenuCopy:
      Clipboard.AsText := mMatch.Key;
  end;
end;

/// <summary>Im Hauptthread nachgereicht: Menü zum Rechtsklick auf ACommit an AWhere.</summary>
procedure QueueMenu(const ACommit: TAtlasBlameCommit; const AWhere: TPoint; ASerial: Integer);
var
  mCommit: TAtlasBlameCommit;
  mWhere: TPoint;
begin
  mCommit := ACommit;
  mWhere := AWhere;
  TAtlasMainThread.ForceQueue(TAtlasFeature.BlameIssues,
    procedure
    begin
      if (TAtlasIdeBlameLinks.FInstance <> nil) and (TAtlasIdeBlameLinks.FInstance.FSerialOf = ASerial) then
      begin
        TAtlasGuard.Run(TAtlasFeature.BlameIssues,
          procedure
          begin
            TAtlasIdeBlameLinks.FInstance.ShowMenu(mCommit, mWhere);
          end);
      end;
    end);
end;

/// <summary>Im Hauptthread nachgereicht: Befehl ACommand für die erste Kennung von ACommit.</summary>
procedure QueueAct(const ACommit: TAtlasBlameCommit; ACommand, ASerial: Integer);
var
  mCommit: TAtlasBlameCommit;
begin
  mCommit := ACommit;
  TAtlasMainThread.ForceQueue(TAtlasFeature.BlameIssues,
    procedure
    begin
      if (TAtlasIdeBlameLinks.FInstance <> nil) and (TAtlasIdeBlameLinks.FInstance.FSerialOf = ASerial) then
      begin
        TAtlasGuard.Run(TAtlasFeature.BlameIssues,
          procedure
          begin
            TAtlasIdeBlameLinks.FInstance.Act(mCommit, ACommand, 0);
          end);
      end;
    end);
end;

/// <summary>Loslassen zum geschluckten Drücken: Ohne Drücken darf auch es nicht an den Editor; nach dem
/// Rechtsklick öffnet hier das eigene Menü.</summary>
procedure SwallowUp(AOwner: TAtlasIdeBlameLinks; const AMsg: TMsg; var AHandled: Boolean);
begin
  AOwner.FSwallowUp := 0;
  AHandled := True;
  if GetCapture = AMsg.hwnd then
  begin
    ReleaseCapture;
  end;
  if AMsg.message = WM_RBUTTONUP then
  begin
    QueueMenu(AOwner.FMenuCommit, Mouse.CursorPos, AOwner.FSerialOf);
  end;
end;

/// <summary>Strg+Klick oder Rechtsklick ohne Umschalt (Umschalt+Rechtsklick: Kontextmenü der IDE)?</summary>
function IsBlameClick(const AMsg: TMsg): Boolean;
begin
  Result := ((AMsg.message = WM_LBUTTONDOWN) and ((AMsg.wParam and MK_CONTROL) <> 0)) or
    ((AMsg.message = WM_RBUTTONDOWN) and ((AMsg.wParam and MK_SHIFT) = 0));
end;

/// <summary>Klick auf die Randanzeige: Strg+Klick öffnet Vorschau bzw. Browser für die erste Kennung
/// (Strg+Umschalt+Klick: Browser), Rechtsklick merkt den Commit für das Menü beim Loslassen.</summary>
procedure BlameClick(AOwner: TAtlasIdeBlameLinks; const AMsg: TMsg; var AHandled: Boolean);
var
  mCommit: TAtlasBlameCommit;
  mTarget: TAtlasTrackerTarget;
  mPattern: TAtlasIssueKeyPattern;
  mCommand: Integer;
begin
  if not TAtlasIdeLineChanges.BlameAt(AMsg.hwnd, SmallInt(LoWord(AMsg.lParam)), SmallInt(HiWord(AMsg.lParam)),
    mCommit) or not AOwner.PatternOf(mTarget, mPattern) then
  begin
    Exit;
  end;
  // Strg+Klick nur mit Kennung; ohne Kennung bleibt der Klick beim Editor.
  if (AMsg.message = WM_LBUTTONDOWN) and (Length(TAtlasIdeBlameLinks.MessageMatches(mPattern, mCommit)) = 0) then
  begin
    Exit;
  end;
  AHandled := True;
  TAtlasIdeLineChanges.HideBlameTip;
  if AMsg.message = WM_RBUTTONDOWN then
  begin
    // Das eigene Menü ersetzt das Kontextmenü der IDE; es öffnet beim Loslassen.
    AOwner.FSwallowUp := WM_RBUTTONUP;
    AOwner.FMenuCommit := mCommit;
  end
  else
  begin
    AOwner.FSwallowUp := WM_LBUTTONUP;
    mCommand := TAtlasIdeBlameLinks.MenuShow;
    if (AMsg.wParam and MK_SHIFT) <> 0 then
    begin
      mCommand := TAtlasIdeBlameLinks.MenuBrowse;
    end;
    QueueAct(mCommit, mCommand, AOwner.FSerialOf);
  end;
end;

procedure TAtlasIdeBlameLinks.AppMessage(var Msg: TMsg; var Handled: Boolean);
begin
  try
    if (FSwallowUp <> 0) and (Msg.message = FSwallowUp) then
    begin
      SwallowUp(Self, Msg, Handled);
    end
    else if IsBlameClick(Msg) then
    begin
      BlameClick(Self, Msg, Handled);
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.BlameIssues, E);
  end;
end;

function TAtlasIdeBlameLinks.AddMenuItem(AParent: TMenuItem; const ACaption: string; ATag: Integer): TMenuItem;
begin
  Result := TMenuItem.Create(FMenu);
  Result.Caption := ACaption;
  Result.Tag := ATag;
  Result.OnClick := MenuClick;
  AParent.Add(Result);
end;

procedure TAtlasIdeBlameLinks.ShowMenu(const ACommit: TAtlasBlameCommit; const APoint: TPoint);
var
  mTarget: TAtlasTrackerTarget;
  mPattern: TAtlasIssueKeyPattern;
  mMatches: TArray<TAtlasIssueKeyMatch>;
  mIndex: Integer;
  mParent: TMenuItem;
  mMethod: Boolean;
  mFirst, mLast: Integer;
  mLines: TArray<string>;
  mText, mName: string;
begin
  FMenu.Items.Clear;
  FMenuCommit := ACommit;
  mMatches := nil;
  if PatternOf(mTarget, mPattern) then
  begin
    mMatches := MessageMatches(mPattern, ACommit);
  end;
  for mIndex := 0 to High(mMatches) do
  begin
    // Eine Kennung: Einträge direkt; mehrere: je Kennung ein Untermenü.
    mParent := FMenu.Items;
    if Length(mMatches) > 1 then
    begin
      mParent := AddMenuItem(FMenu.Items, mMatches[mIndex].Key, 0);
      mParent.OnClick := nil;
    end;
    AddMenuItem(mParent, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueLinkMenuShow),
      mIndex * MenuStride + MenuShow).Default :=
      True;
    AddMenuItem(mParent, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewBrowse),
      mIndex * MenuStride + MenuBrowse);
    AddMenuItem(mParent, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewCopyKey),
      mIndex * MenuStride + MenuCopy);
  end;
  if Length(mMatches) > 0 then
  begin
    AddMenuItem(FMenu.Items, '-', 0).OnClick := nil;
  end;
  mMethod := TAtlasIdeBlameScope.BufferLines(ACommit.FileName, mLines, mText) and
    TAtlasBlameLinks.Scope(mText, ACommit.Line, mFirst, mLast, mName);
  AddMenuItem(FMenu.Items, TAtlasIssueTip.ScopeLink(mMethod, -1), MenuScope);
  FMenu.Popup(APoint.X, APoint.Y);
end;

procedure TAtlasIdeBlameLinks.MenuClick(Sender: TObject);
var
  mTag: Integer;
  mCommit: TAtlasBlameCommit;
begin
  mTag := TMenuItem(Sender).Tag;
  mCommit := FMenuCommit;
  TAtlasGuard.Run(TAtlasFeature.BlameIssues,
    procedure
    begin
      Act(mCommit, mTag mod MenuStride, mTag div MenuStride);
    end);
end;

procedure TAtlasIdeBlameLinks.ShowScope;
begin
  FScope.Show;
end;

end.
