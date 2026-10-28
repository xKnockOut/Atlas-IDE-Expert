unit Atlas.IDE.Tracker.BlameLinks;

// Issues in der Zeilenhistorie (#1275): Die Zeilenhistorie am Ende der
// Cursorzeile (editor.gitBlame, Atlas.IDE.Editor.LineChanges) zeigt die
// Kennungen aus der Commit-Nachricht („anna, vor 3 Mon. · ATL-97 · Betreff“),
// ihr Hover Titel und Zustand je Kennung und den Link „Issues zu dieser
// Methode (n)“. Strg+Klick auf die Randanzeige öffnet die Issue-Vorschau
// (#1264), Strg+Umschalt+Klick den Browser, Rechtsklick ein Menü. Der Befehl
// „Issues zu dieser Methode“ listet im Ergebnisfenster alle Issues, deren
// Commits die Methode am Cursor (außerhalb einer Methode die Unit) geändert
// haben; Klick öffnet die Vorschau, Doppelklick zeigt den Commit.
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
  Atlas.Core.Ci.Contract,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.CodeLinks,
  Atlas.Core.Tracker.BlameLinks,
  Atlas.UI.Tracker.IssueTip,
  Atlas.IDE.Editor.LineChanges,
  Atlas.IDE.Tracker.IssuePreview,
  Atlas.IDE.Tracker.CodeLinks;

type
  TAtlasIdeBlameLinks = class
  private const
    MenuShow = 1;
    MenuBrowse = 2;
    MenuCopy = 3;
    MenuScope = 4;
    /// <summary>Menüeinträge tragen Kennung * MenuStride + Befehl.</summary>
    MenuStride = 8;
    /// <summary>Höchstens so viele Titel fragt der Befehl nach.</summary>
    MaxLookups = 30;
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
    // Ergebnisliste des Befehls.
    FList: Integer;
    FListTarget: TAtlasTrackerTarget;
    FListKind: TAtlasVcsKind;
    FListResult: TAtlasBlameIssueList;
    function Active: Boolean;
    function PatternOf(out ATarget: TAtlasTrackerTarget; out APattern: TAtlasIssueKeyPattern): Boolean;
    function Preview: TAtlasIdeIssuePreview;
    function StateKey(const APattern: TAtlasIssueKeyPattern; const AMatch: TAtlasIssueKeyMatch): string;
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
    procedure ShowScopeAt(const AFileName: string; ALine: Integer);
    procedure ShowList(AList: Integer; const AName: string; const AHistory: TAtlasBlameHistory;
      const ATarget: TAtlasTrackerTarget; const APattern: TAtlasIssueKeyPattern; AKind: TAtlasVcsKind);
    function IssueText(AIssue: Integer; AKnown: Boolean; const ADetails: TAtlasTrackerDetails): string;
    procedure AskRow(const APreview: TAtlasIdeIssuePreview; const ATarget: TAtlasTrackerTarget; AList, AId: Integer);
    procedure IssueOpen(AList, AId: Integer);
    procedure IssueCommit(AList, AId: Integer);
    class function BufferLines(const AFileName: string; out ALines: TArray<string>; out AText: string): Boolean;
      static;
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
  System.DateUtils,
  Vcl.Clipbrd,
  ToolsAPI,
  Atlas.Text.Lines,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Strings,
  Atlas.UI.Undo.DiffView,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.ResultsWindow,
  Atlas.Core.Results.Model,
  Atlas.IDE.Vcs.Service;

/// <summary>Messages-Haken der Zeilenhistorie (Hintergrund): ganze Nachrichten zu den Revisionen aus blame.</summary>
function LoadMessages(const AVcs: IAtlasVersionControl; const AFileName: string;
  const ALines: TArray<TAtlasVcsBlameLine>): TArray<TAtlasVcsRevisionMessage>;
var
  mHistory: IAtlasVcsLineHistory;
begin
  Result := nil;
  if (AVcs = nil) or not Supports(AVcs, IAtlasVcsLineHistory, mHistory) then
    Exit;
  // Gescheitert: Die Randanzeige bleibt wie bisher (Betreff aus blame).
  if mHistory.Messages(AFileName, TAtlasBlameLinks.BlameRevisions(ALines), Result) <> TAtlasVcsOutcome.Ok then
    Result := nil;
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
  TAtlasIdeResultsWindow.OnIssueOpen :=
    procedure(AList, AId: Integer)
    begin
      if FInstance <> nil then
        TAtlasGuard.Run(TAtlasFeature.BlameIssues,
          procedure
          begin
            FInstance.IssueOpen(AList, AId);
          end);
    end;
  TAtlasIdeResultsWindow.OnIssueCommit :=
    procedure(AList, AId: Integer)
    begin
      if FInstance <> nil then
        TAtlasGuard.Run(TAtlasFeature.BlameIssues,
          procedure
          begin
            FInstance.IssueCommit(AList, AId);
          end);
    end;
end;

destructor TAtlasIdeBlameLinks.Destroy;
begin
  if FInstance = Self then
  begin
    FInstance := nil;
    TAtlasIdeResultsWindow.OnIssueOpen := nil;
    TAtlasIdeResultsWindow.OnIssueCommit := nil;
  end;
  if FAppEvents <> nil then
  begin
    FAppEvents.OnMessage := nil;
    FreeAndNil(FAppEvents);
  end;
  FreeAndNil(FMenu);
  FreeAndNil(FKeyStates);
  FMenuCommit := Default(TAtlasBlameCommit);
  FListResult := Default(TAtlasBlameIssueList);
  FHooks := Default(TAtlasCodeLinksHooks);
  inherited Destroy;
end;

class function TAtlasIdeBlameLinks.Enabled: Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := mSettings.Enabled and mSettings.IssuesBlameLinks and not TAtlasGuard.Disabled(TAtlasFeature.BlameIssues);
end;

function TAtlasIdeBlameLinks.Active: Boolean;
begin
  Result := Assigned(FHooks.Target) and Enabled;
end;

function TAtlasIdeBlameLinks.PatternOf(out ATarget: TAtlasTrackerTarget;
  out APattern: TAtlasIssueKeyPattern): Boolean;
begin
  APattern := TAtlasIssueKeyPattern.Empty;
  ATarget := TAtlasTrackerTarget.Create('', '', '', '');
  Result := Active and FHooks.Target(ATarget);
  if Result then
  begin
    APattern := TAtlasIssueKeyPattern.ForTarget(ATarget);
    Result := APattern.Active;
  end;
end;

function TAtlasIdeBlameLinks.Preview: TAtlasIdeIssuePreview;
begin
  Result := nil;
  if Assigned(FHooks.Preview) then
    Result := FHooks.Preview();
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
    function(const AMessage: string): string
    var
      mTarget: TAtlasTrackerTarget;
      mPattern: TAtlasIssueKeyPattern;
    begin
      Result := '';
      if (FInstance <> nil) and (FInstance.FSerialOf = mSerial) and FInstance.PatternOf(mTarget, mPattern) then
        Result := TAtlasBlameLinks.CaptionSuffix(TAtlasBlameLinks.Keys(mPattern, AMessage));
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
        TAtlasGuard.Run(TAtlasFeature.BlameIssues,
          procedure
          begin
            FInstance.Link(ACommit, AIndex);
          end);
    end;
end;

function TAtlasIdeBlameLinks.StateKey(const APattern: TAtlasIssueKeyPattern; const AMatch: TAtlasIssueKeyMatch): string;
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
  mPreview := Preview;
  mKey := StateKey(APattern, AMatch);
  // Einmal je Hover und Kennung; ein frischer Stand braucht keine Abfrage.
  if (mPreview = nil) or FKeyStates.ContainsKey(mKey) then
    Exit;
  if mPreview.Peek(AMatch.IssueTarget(ATarget), AMatch.IssueKey, mDetails) and
    TAtlasIdeIssuePreview.Fresh(mDetails) then
    Exit;
  mState.State := TAtlasIssueTipState.Loading;
  mState.Error := TAtlasCiFetchError.None;
  FKeyStates.Add(mKey, mState);
  mSerial := FSerialOf;
  mPreview.Lookup(AMatch.IssueTarget(ATarget), AMatch.IssueKey,
    procedure(ASucceeded: Boolean; const ADetails: TAtlasTrackerDetails; AError: TAtlasCiFetchError)
    var
      mDone: TKeyState;
    begin
      if (FInstance = nil) or (FInstance.FSerialOf <> mSerial) or not FInstance.FKeyStates.ContainsKey(mKey) then
        Exit;
      mDone.Error := AError;
      if ASucceeded then
        mDone.State := TAtlasIssueTipState.Found
      else if AError = TAtlasCiFetchError.NotFound then
        mDone.State := TAtlasIssueTipState.NotFound
      else
        mDone.State := TAtlasIssueTipState.Failed;
      FInstance.FKeyStates[mKey] := mDone;
      // Kam die Antwort sofort (aus Describe heraus), baut Describe den Text selbst.
      if not FInstance.FDescribing then
        TAtlasIdeLineChanges.RefreshBlameTip;
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
  mPreview := Preview;
  mCached := False;
  mDetails := TAtlasTrackerDetails.Empty;
  if mPreview <> nil then
    mCached := mPreview.Peek(AMatch.IssueTarget(ATarget), AMatch.IssueKey, mDetails);
  mKnown := FKeyStates.TryGetValue(StateKey(APattern, AMatch), mState);
  if mKnown and (mState.State = TAtlasIssueTipState.NotFound) then
    Result := TAtlasIssueTip.KeyLine(AMatch.Key, TAtlasIssueTipState.NotFound, mDetails, mState.Error)
  else if mCached then
    // Ohne Netz bleibt ein vorhandener Stand stehen.
    Result := TAtlasIssueTip.KeyLine(AMatch.Key, TAtlasIssueTipState.Found, mDetails, TAtlasCiFetchError.None)
  else if mKnown and (mState.State = TAtlasIssueTipState.Failed) then
    Result := TAtlasIssueTip.KeyLine(AMatch.Key, TAtlasIssueTipState.Failed, mDetails, mState.Error)
  else
    Result := TAtlasIssueTip.KeyLine(AMatch.Key, TAtlasIssueTipState.Loading, mDetails, TAtlasCiFetchError.None);
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
    Exit;
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
      Ask(mTarget, mPattern, mMatch);
  finally
    FDescribing := False;
  end;
  for mMatch in mMatches do
    ALinks := ALinks + [KeyText(mTarget, mPattern, mMatch)];
  if Length(mMatches) > 0 then
    AText := TrimRight(AText) + #10#10 + TAtlasIssueTip.BlameFooter(TAtlasIdeIssuePreview.Active);
  mCount := ScopeCount(ACommit.FileName, ACommit.Line, mMethod);
  ALinks := ALinks + [TAtlasIssueTip.ScopeLink(mMethod, mCount)];
  Result := True;
end;

class function TAtlasIdeBlameLinks.BufferLines(const AFileName: string; out ALines: TArray<string>;
  out AText: string): Boolean;
var
  mView: IOTAEditView;
begin
  ALines := nil;
  AText := '';
  mView := TAtlasEditorBuffer.ActiveView;
  Result := (mView <> nil) and (mView.Buffer <> nil) and SameText(mView.Buffer.FileName, AFileName);
  if not Result then
    Exit;
  AText := TAtlasEditorBuffer.Text(mView.Buffer);
  ALines := TTextLines.SplitLines(AText);
end;

function TAtlasIdeBlameLinks.ScopeCount(const AFileName: string; ALine: Integer; out AMethod: Boolean): Integer;
var
  mLines: TArray<string>;
  mText, mName, mKey: string;
  mFirst, mLast, mMax, mSerial: Integer;
  mVcs: IAtlasVersionControl;
  mTarget: TAtlasTrackerTarget;
  mPattern: TAtlasIssueKeyPattern;
  mHistory: TAtlasBlameHistory;
begin
  Result := -1;
  AMethod := False;
  if not BufferLines(AFileName, mLines, mText) or not PatternOf(mTarget, mPattern) then
    Exit;
  AMethod := TAtlasBlameLinks.Scope(mText, ALine, mFirst, mLast, mName);
  mVcs := TAtlasIdeVcs.ForFolder(ExtractFileDir(AFileName));
  if (mVcs = nil) or (mVcs.Kind = TAtlasVcsKind.None) then
    Exit;
  // Gezählt je Bereich und Stand der Arbeitskopie; ein Commit oder Wechsel des Branchs zählt neu.
  mKey := AFileName + #1 + IntToStr(mFirst) + #1 + IntToStr(mLast) + #1 + mName + #1 + mVcs.ChangeMarker + #1 +
    mPattern.Key;
  if mKey = FCountKey then
    Exit(FCount);
  if FCountBusy then
    Exit;
  FCountKey := mKey;
  FCount := -1;
  FCountBusy := True;
  mMax := TAtlasIdeSettings.Current.IssuesBlameMaxRevisions;
  mSerial := FSerialOf;
  mHistory := Default(TAtlasBlameHistory);
  if not TAtlasIdeVcs.Run(
    procedure
    begin
      mHistory := TAtlasBlameLinks.History(mVcs, AFileName, mLines, mFirst, mLast, mMax);
    end,
    procedure
    begin
      if (FInstance = nil) or (FInstance.FSerialOf <> mSerial) then
        Exit;
      FInstance.FCountBusy := False;
      if FInstance.FCountKey <> mKey then
        Exit;
      if mHistory.Outcome = TAtlasBlameHistoryOutcome.Failed then
        // Ohne Zahl; der nächste Hover versucht es wieder.
        FInstance.FCountKey := ''
      else
        FInstance.FCount := Length(TAtlasBlameLinks.Group(mPattern, mHistory.Commits).Issues);
      TAtlasIdeLineChanges.RefreshBlameTip;
    end) then
    FCountBusy := False;
end;

procedure TAtlasIdeBlameLinks.Link(const ACommit: TAtlasBlameCommit; AIndex: Integer);
var
  mTarget: TAtlasTrackerTarget;
  mPattern: TAtlasIssueKeyPattern;
  mMatches: TArray<TAtlasIssueKeyMatch>;
begin
  if not PatternOf(mTarget, mPattern) then
    Exit;
  mMatches := MessageMatches(mPattern, ACommit);
  if (AIndex >= 0) and (AIndex < Length(mMatches)) then
    Act(ACommit, MenuShow, AIndex)
  else
    ShowScopeAt(ACommit.FileName, ACommit.Line);
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
    ShowScopeAt(ACommit.FileName, ACommit.Line);
    Exit;
  end;
  if not PatternOf(mTarget, mPattern) then
    Exit;
  mMatches := MessageMatches(mPattern, ACommit);
  if (AKey < 0) or (AKey >= Length(mMatches)) then
    Exit;
  mMatch := mMatches[AKey];
  case ACommand of
    MenuShow:
      if Assigned(FHooks.Show) then
        FHooks.Show(mMatch.IssueTarget(mTarget), mMatch.IssueKey);
    MenuBrowse:
      if Assigned(FHooks.Browse) then
        FHooks.Browse(mMatch.IssueTarget(mTarget), mMatch.IssueKey);
    MenuCopy:
      Clipboard.AsText := mMatch.Key;
  end;
end;

procedure TAtlasIdeBlameLinks.AppMessage(var Msg: TMsg; var Handled: Boolean);
var
  mCommit: TAtlasBlameCommit;
  mTarget: TAtlasTrackerTarget;
  mPattern: TAtlasIssueKeyPattern;
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
        ReleaseCapture;
      if Msg.message = WM_RBUTTONUP then
      begin
        mCommit := FMenuCommit;
        mWhere := Mouse.CursorPos;
        mSerial := FSerialOf;
        TAtlasMainThread.ForceQueue(TAtlasFeature.BlameIssues,
          procedure
          begin
            if (FInstance <> nil) and (FInstance.FSerialOf = mSerial) then
              TAtlasGuard.Run(TAtlasFeature.BlameIssues,
                procedure
                begin
                  FInstance.ShowMenu(mCommit, mWhere);
                end);
          end);
      end;
      Exit;
    end;
    if not ((Msg.message = WM_LBUTTONDOWN) or (Msg.message = WM_RBUTTONDOWN)) then
      Exit;
    if (Msg.message = WM_LBUTTONDOWN) and ((Msg.wParam and MK_CONTROL) = 0) then
      Exit;
    // Umschalt+Rechtsklick: Kontextmenü der IDE.
    if (Msg.message = WM_RBUTTONDOWN) and ((Msg.wParam and MK_SHIFT) <> 0) then
      Exit;
    if not TAtlasIdeLineChanges.BlameAt(Msg.hwnd, SmallInt(LoWord(Msg.lParam)), SmallInt(HiWord(Msg.lParam)),
      mCommit) or not PatternOf(mTarget, mPattern) then
      Exit;
    // Strg+Klick nur mit Kennung; ohne Kennung bleibt der Klick beim Editor.
    if (Msg.message = WM_LBUTTONDOWN) and (Length(MessageMatches(mPattern, mCommit)) = 0) then
      Exit;
    Handled := True;
    TAtlasIdeLineChanges.HideBlameTip;
    if Msg.message = WM_RBUTTONDOWN then
    begin
      // Das eigene Menü ersetzt das Kontextmenü der IDE; es öffnet beim Loslassen.
      FSwallowUp := WM_RBUTTONUP;
      FMenuCommit := mCommit;
      Exit;
    end;
    // Strg+Klick: Vorschau bzw. Browser für die erste Kennung; Strg+Umschalt+Klick: Browser.
    FSwallowUp := WM_LBUTTONUP;
    mCommand := MenuShow;
    if (Msg.wParam and MK_SHIFT) <> 0 then
      mCommand := MenuBrowse;
    mSerial := FSerialOf;
    TAtlasMainThread.ForceQueue(TAtlasFeature.BlameIssues,
      procedure
      begin
        if (FInstance <> nil) and (FInstance.FSerialOf = mSerial) then
          TAtlasGuard.Run(TAtlasFeature.BlameIssues,
            procedure
            begin
              FInstance.Act(mCommit, mCommand, 0);
            end);
      end);
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
    mMatches := MessageMatches(mPattern, ACommit);
  for mIndex := 0 to High(mMatches) do
  begin
    // Eine Kennung: Einträge direkt; mehrere: je Kennung ein Untermenü.
    mParent := FMenu.Items;
    if Length(mMatches) > 1 then
    begin
      mParent := AddMenuItem(FMenu.Items, mMatches[mIndex].Key, 0);
      mParent.OnClick := nil;
    end;
    AddMenuItem(mParent, TAtlasStrings.Text(TAtlasTextId.IssueLinkMenuShow), mIndex * MenuStride + MenuShow).Default :=
      True;
    AddMenuItem(mParent, TAtlasStrings.Text(TAtlasTextId.IssuePreviewBrowse), mIndex * MenuStride + MenuBrowse);
    AddMenuItem(mParent, TAtlasStrings.Text(TAtlasTextId.IssuePreviewCopyKey), mIndex * MenuStride + MenuCopy);
  end;
  if Length(mMatches) > 0 then
    AddMenuItem(FMenu.Items, '-', 0).OnClick := nil;
  mMethod := BufferLines(ACommit.FileName, mLines, mText) and
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
var
  mView: IOTAEditView;
begin
  mView := TAtlasEditorBuffer.ActiveView;
  if (mView = nil) or (mView.Buffer = nil) or (mView.Buffer.FileName = '') then
  begin
    Inc(FList);
    TAtlasIdeResultsWindow.ShowIssues(TAtlasStrings.Text(TAtlasTextId.BlameIssuesNoEditor), FList, nil);
    Exit;
  end;
  ShowScopeAt(mView.Buffer.FileName, mView.CursorPos.Line - 1);
end;

procedure TAtlasIdeBlameLinks.ShowScopeAt(const AFileName: string; ALine: Integer);
var
  mLines: TArray<string>;
  mText, mName: string;
  mFirst, mLast, mMax, mList, mSerial: Integer;
  mVcs: IAtlasVersionControl;
  mTarget: TAtlasTrackerTarget;
  mPattern: TAtlasIssueKeyPattern;
  mHistory: TAtlasBlameHistory;
  mKind: TAtlasVcsKind;
begin
  Inc(FList);
  mList := FList;
  if not BufferLines(AFileName, mLines, mText) then
  begin
    TAtlasIdeResultsWindow.ShowIssues(TAtlasStrings.Text(TAtlasTextId.BlameIssuesNoEditor), mList, nil);
    Exit;
  end;
  if not PatternOf(mTarget, mPattern) then
  begin
    TAtlasIdeResultsWindow.ShowIssues(TAtlasStrings.Text(TAtlasTextId.BlameIssuesNoTracker), mList, nil);
    Exit;
  end;
  mVcs := TAtlasIdeVcs.ForFolder(ExtractFileDir(AFileName));
  if (mVcs = nil) or (mVcs.Kind = TAtlasVcsKind.None) then
  begin
    TAtlasIdeResultsWindow.ShowIssues(TAtlasStrings.Text(TAtlasTextId.BlameIssuesNoVcs), mList, nil);
    Exit;
  end;
  if not TAtlasBlameLinks.Scope(mText, ALine, mFirst, mLast, mName) then
    mName := TAtlasStrings.Fmt(TAtlasTextId.BlameIssuesUnitName, [ExtractFileName(AFileName)]);
  mKind := mVcs.Kind;
  mMax := TAtlasIdeSettings.Current.IssuesBlameMaxRevisions;
  mSerial := FSerialOf;
  mHistory := Default(TAtlasBlameHistory);
  TAtlasIdeResultsWindow.ShowIssues(TAtlasStrings.Fmt(TAtlasTextId.BlameIssuesSearching, [mName]), mList, nil);
  if not TAtlasIdeVcs.Run(
    procedure
    begin
      mHistory := TAtlasBlameLinks.History(mVcs, AFileName, mLines, mFirst, mLast, mMax);
    end,
    procedure
    begin
      // Nur, solange niemand eine neue Liste angefordert hat.
      if (FInstance <> nil) and (FInstance.FSerialOf = mSerial) and (FInstance.FList = mList) then
        TAtlasGuard.Run(TAtlasFeature.BlameIssues,
          procedure
          begin
            FInstance.ShowList(mList, mName, mHistory, mTarget, mPattern, mKind);
          end);
    end) then
    // Versionsverwaltung beendet (Entladen): kein Ergebnis mehr.
    TAtlasIdeResultsWindow.ShowIssues(TAtlasStrings.Fmt(TAtlasTextId.BlameIssuesFailed,
      [mName, AtlasVcsOutcomeName(TAtlasVcsOutcome.Cancelled)]), mList, nil);
end;

function TAtlasIdeBlameLinks.IssueText(AIssue: Integer; AKnown: Boolean; const ADetails: TAtlasTrackerDetails): string;
var
  mIssue: TAtlasBlameIssue;
begin
  mIssue := FListResult.Issues[AIssue];
  Result := TAtlasIssueTip.IssueRow(mIssue.Match.Key, AKnown, ADetails, mIssue.LastDate,
    TTimeZone.Local.ToUniversalTime(Now), Length(mIssue.Commits));
end;

procedure TAtlasIdeBlameLinks.ShowList(AList: Integer; const AName: string; const AHistory: TAtlasBlameHistory;
  const ATarget: TAtlasTrackerTarget; const APattern: TAtlasIssueKeyPattern; AKind: TAtlasVcsKind);
var
  mIssues: TArray<TAtlasResultIssue>;
  mIndex, mCommit, mAsked, mId: Integer;
  mPreview: TAtlasIdeIssuePreview;
  mDetails: TAtlasTrackerDetails;
  mKnown: TArray<Boolean>;
  mLine: TAtlasVcsLineCommit;
  mMatch: TAtlasIssueKeyMatch;
begin
  case AHistory.Outcome of
    TAtlasBlameHistoryOutcome.NotCommitted:
      begin
        TAtlasIdeResultsWindow.ShowIssues(TAtlasStrings.Fmt(TAtlasTextId.BlameIssuesNotCommitted, [AName]), AList,
          nil);
        Exit;
      end;
    TAtlasBlameHistoryOutcome.Failed:
      begin
        TAtlasIdeResultsWindow.ShowIssues(TAtlasStrings.Fmt(TAtlasTextId.BlameIssuesFailed,
          [AName, AtlasVcsOutcomeName(AHistory.VcsOutcome)]), AList, nil);
        Exit;
      end;
  end;
  FListTarget := ATarget;
  FListKind := AKind;
  FListResult := TAtlasBlameLinks.Group(APattern, AHistory.Commits);
  if Length(FListResult.Issues) = 0 then
  begin
    TAtlasIdeResultsWindow.ShowIssues(TAtlasStrings.Fmt(TAtlasTextId.BlameIssuesNone,
      [AName, Length(FListResult.Commits)]), AList, nil);
    Exit;
  end;
  mPreview := Preview;
  SetLength(mIssues, Length(FListResult.Issues));
  SetLength(mKnown, Length(FListResult.Issues));
  for mIndex := 0 to High(FListResult.Issues) do
  begin
    mMatch := FListResult.Issues[mIndex].Match;
    mKnown[mIndex] := False;
    mDetails := TAtlasTrackerDetails.Empty;
    if mPreview <> nil then
      mKnown[mIndex] := mPreview.Peek(mMatch.IssueTarget(ATarget), mMatch.IssueKey, mDetails);
    mIssues[mIndex].Id := mIndex;
    mIssues[mIndex].Text := IssueText(mIndex, mKnown[mIndex], mDetails);
    SetLength(mIssues[mIndex].Commits, Length(FListResult.Issues[mIndex].Commits));
    for mCommit := 0 to High(FListResult.Issues[mIndex].Commits) do
    begin
      mId := FListResult.Issues[mIndex].Commits[mCommit];
      mLine := FListResult.Commits[mId];
      mIssues[mIndex].Commits[mCommit].Id := mId;
      mIssues[mIndex].Commits[mCommit].Text := TAtlasIssueTip.CommitRow(TAtlasBlameLinks.ShortRevision(AKind,
        mLine.Revision), mLine.Author, TTimeZone.Local.ToLocalTime(mLine.Date),
        TAtlasBlameLinks.Subject(mLine.Message));
    end;
  end;
  TAtlasIdeResultsWindow.ShowIssues(TAtlasIssueTip.ScopeTitle(AName, Length(FListResult.Issues),
    Length(FListResult.Commits), FListResult.Unlinked), AList, mIssues);
  if mPreview = nil then
    Exit;
  // Titel und Zustand nachfragen, die der Zwischenspeicher nicht (frisch) hat; die Zeile folgt der Antwort.
  mAsked := 0;
  for mIndex := 0 to High(FListResult.Issues) do
  begin
    mMatch := FListResult.Issues[mIndex].Match;
    if mKnown[mIndex] and mPreview.Peek(mMatch.IssueTarget(ATarget), mMatch.IssueKey, mDetails) and
      TAtlasIdeIssuePreview.Fresh(mDetails) then
      Continue;
    if mAsked >= MaxLookups then
      Break;
    Inc(mAsked);
    AskRow(mPreview, ATarget, AList, mIndex);
  end;
end;

procedure TAtlasIdeBlameLinks.AskRow(const APreview: TAtlasIdeIssuePreview; const ATarget: TAtlasTrackerTarget;
  AList, AId: Integer);
var
  mMatch: TAtlasIssueKeyMatch;
  mSerial: Integer;
begin
  // Eigene Routine: Jede Rückmeldung fängt ihr eigenes AId ein (nicht die Schleifenvariable).
  mMatch := FListResult.Issues[AId].Match;
  mSerial := FSerialOf;
  APreview.Lookup(mMatch.IssueTarget(ATarget), mMatch.IssueKey,
    procedure(ASucceeded: Boolean; const ADetails: TAtlasTrackerDetails; AError: TAtlasCiFetchError)
    begin
      if ASucceeded and (FInstance <> nil) and (FInstance.FSerialOf = mSerial) and (FInstance.FList = AList) and
        (AId <= High(FInstance.FListResult.Issues)) then
        TAtlasIdeResultsWindow.SetIssueText(AList, AId, FInstance.IssueText(AId, True, ADetails));
    end);
end;

procedure TAtlasIdeBlameLinks.IssueOpen(AList, AId: Integer);
var
  mMatch: TAtlasIssueKeyMatch;
begin
  if (AList <> FList) or (AId < 0) or (AId > High(FListResult.Issues)) or not Assigned(FHooks.Show) then
    Exit;
  mMatch := FListResult.Issues[AId].Match;
  FHooks.Show(mMatch.IssueTarget(FListTarget), mMatch.IssueKey);
end;

procedure TAtlasIdeBlameLinks.IssueCommit(AList, AId: Integer);
var
  mCommit: TAtlasVcsLineCommit;
  mLines: TArray<string>;
begin
  if (AList <> FList) or (AId < 0) or (AId > High(FListResult.Commits)) then
    Exit;
  mCommit := FListResult.Commits[AId];
  // Nachricht, Leerzeile, dann der Unterschied des Bereichs.
  mLines := TTextLines.SplitLines(TrimRight(mCommit.Message));
  mLines := mLines + [''] + mCommit.Patch;
  TAtlasUndoDiffView.Execute(TAtlasStrings.Fmt(TAtlasTextId.BlameIssuesDiffTitle,
    [TAtlasBlameLinks.ShortRevision(FListKind, mCommit.Revision), TAtlasBlameLinks.Subject(mCommit.Message)]),
    mLines);
end;

end.
