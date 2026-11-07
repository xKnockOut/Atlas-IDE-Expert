unit Atlas.IDE.Tracker.BlameScope;

// „Issues zu dieser Methode“ (#1275): listet im Ergebnisfenster alle Issues,
// deren Commits die Methode am Cursor (außerhalb einer Methode die Unit)
// geändert haben; Klick öffnet die Vorschau, Doppelklick zeigt den Commit.
// - Teil der Issues in der Zeilenhistorie (Atlas.IDE.Tracker.BlameLinks); von
//   hier kommen auch die gemeinsamen Abfragen (Schalter, Muster, Vorschau,
//   Zeilen des Puffers).
// - Die Commits des Bereichs liest ein Hintergrundlauf (TAtlasIdeVcs.Run);
//   danach fragt die Liste die Titel nach, die der Zwischenspeicher nicht
//   frisch hat.
// Gesichert über TAtlasFeature.BlameIssues (#493). Nur im Hauptthread.

interface

uses
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.CodeLinks,
  Atlas.Core.Tracker.BlameLinks,
  Atlas.IDE.Tracker.IssuePreview,
  Atlas.IDE.Tracker.CodeLinks;

type
  TAtlasIdeBlameScope = class
  private const
    /// <summary>Höchstens so viele Titel fragt der Befehl nach.</summary>
    cMaxLookups = 30;
  private class var
    FInstance: TAtlasIdeBlameScope;
    FSerial: Integer;
  private
    FHooks: TAtlasCodeLinksHooks;
    FSerialOf: Integer;
    // Ergebnisliste des Befehls.
    FList: Integer;
    FListTarget: TAtlasTrackerTarget;
    FListKind: TAtlasVcsKind;
    FListResult: TAtlasBlameIssueList;
    procedure ShowList(AList: Integer; const AName: string; const AHistory: TAtlasBlameHistory;
      const ATarget: TAtlasTrackerTarget; const APattern: TAtlasIssueKeyPattern; AKind: TAtlasVcsKind);
    function IssueText(AIssue: Integer; AKnown: Boolean; const ADetails: TAtlasTrackerDetails): string;
    procedure AskRow(const APreview: TAtlasIdeIssuePreview; AList, AId: Integer);
    procedure IssueOpen(AList, AId: Integer);
    procedure IssueCommit(AList, AId: Integer);
  public
    /// <summary>AHooks wie für die Kennungen im Code (Tracker, Vorschau, Anzeigen, Browser).</summary>
    constructor Create(const AHooks: TAtlasCodeLinksHooks);
    destructor Destroy; override;
    /// <summary>Befehl für die Cursorzeile des Editors vorn.</summary>
    procedure Show;
    /// <summary>Befehl für Zeile ALine (ab 0) von AFileName.</summary>
    procedure ShowAt(const AFileName: string; ALine: Integer);
    /// <summary>issues.blameLinks an und die Funktion nicht abgeschaltet?</summary>
    class function Enabled: Boolean; static;
    /// <summary>Tracker und Muster der Kennungen; False ohne Tracker, ohne Muster oder abgeschaltet.</summary>
    class function PatternOf(const AHooks: TAtlasCodeLinksHooks; out ATarget: TAtlasTrackerTarget;
      out APattern: TAtlasIssueKeyPattern): Boolean; static;
    /// <summary>Die Issue-Vorschau aus den Hooks; nil ohne.</summary>
    class function Preview(const AHooks: TAtlasCodeLinksHooks): TAtlasIdeIssuePreview; static;
    /// <summary>Zeilen und Text des Puffers vorn, wenn er AFileName zeigt.</summary>
    class function BufferLines(const AFileName: string; out ALines: TArray<string>; out AText: string): Boolean;
      static;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  ToolsAPI,
  Atlas.Text.Lines,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Results.Model,
  Atlas.UI.Tracker.Strings,
  Atlas.UI.Tracker.IssueTip,
  Atlas.UI.Undo.DiffView,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.ResultsWindow,
  Atlas.IDE.Vcs.Service,
  Atlas.IDE.Tracker.IssueLookups;

type
  /// <summary>Alles für einen Lauf des Befehls.</summary>
  TScopeJob = record
    FileName: string;
    Name: string;
    Lines: TArray<string>;
    First: Integer;
    Last: Integer;
    Max: Integer;
    List: Integer;
    Serial: Integer;
    Vcs: IAtlasVersionControl;
    Target: TAtlasTrackerTarget;
    Pattern: TAtlasIssueKeyPattern;
    Kind: TAtlasVcsKind;
  end;

{ TAtlasIdeBlameScope }

constructor TAtlasIdeBlameScope.Create(const AHooks: TAtlasCodeLinksHooks);
begin
  inherited Create;
  FHooks := AHooks;
  Inc(FSerial);
  FSerialOf := FSerial;
  FInstance := Self;
  TAtlasIdeResultsWindow.OnIssueOpen :=
    procedure(AList, AId: Integer)
    begin
      if FInstance <> nil then
      begin
        TAtlasGuard.Run(TAtlasFeature.BlameIssues,
          procedure
          begin
            FInstance.IssueOpen(AList, AId);
          end);
      end;
    end;
  TAtlasIdeResultsWindow.OnIssueCommit :=
    procedure(AList, AId: Integer)
    begin
      if FInstance <> nil then
      begin
        TAtlasGuard.Run(TAtlasFeature.BlameIssues,
          procedure
          begin
            FInstance.IssueCommit(AList, AId);
          end);
      end;
    end;
end;

destructor TAtlasIdeBlameScope.Destroy;
begin
  if FInstance = Self then
  begin
    FInstance := nil;
    TAtlasIdeResultsWindow.OnIssueOpen := nil;
    TAtlasIdeResultsWindow.OnIssueCommit := nil;
  end;
  FListResult := Default(TAtlasBlameIssueList);
  FHooks := Default(TAtlasCodeLinksHooks);
  inherited Destroy;
end;

class function TAtlasIdeBlameScope.Enabled: Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := mSettings.Enabled and mSettings.IssuesBlameLinks and not TAtlasGuard.Disabled(TAtlasFeature.BlameIssues);
end;

class function TAtlasIdeBlameScope.PatternOf(const AHooks: TAtlasCodeLinksHooks; out ATarget: TAtlasTrackerTarget;
  out APattern: TAtlasIssueKeyPattern): Boolean;
begin
  APattern := TAtlasIssueKeyPattern.Empty;
  ATarget := TAtlasTrackerTarget.Create('', '', '', '');
  Result := Assigned(AHooks.Target) and Enabled and AHooks.Target(ATarget);
  if Result then
  begin
    APattern := TAtlasIssueKeyPattern.ForTarget(ATarget);
    Result := APattern.Active;
  end;
end;

class function TAtlasIdeBlameScope.Preview(const AHooks: TAtlasCodeLinksHooks): TAtlasIdeIssuePreview;
begin
  Result := nil;
  if Assigned(AHooks.Preview) then
  begin
    Result := AHooks.Preview();
  end;
end;

class function TAtlasIdeBlameScope.BufferLines(const AFileName: string; out ALines: TArray<string>;
  out AText: string): Boolean;
var
  mView: IOTAEditView;
begin
  ALines := nil;
  AText := '';
  mView := TAtlasEditorBuffer.ActiveView;
  Result := (mView <> nil) and (mView.Buffer <> nil) and SameText(mView.Buffer.FileName, AFileName);
  if not Result then
  begin
    Exit;
  end;
  AText := TAtlasEditorBuffer.Text(mView.Buffer);
  ALines := TTextLines.SplitLines(AText);
end;

procedure TAtlasIdeBlameScope.Show;
var
  mView: IOTAEditView;
begin
  mView := TAtlasEditorBuffer.ActiveView;
  if (mView = nil) or (mView.Buffer = nil) or (mView.Buffer.FileName = '') then
  begin
    Inc(FList);
    TAtlasIdeResultsWindow.ShowIssues(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.BlameIssuesNoEditor), FList, nil);
    Exit;
  end;
  ShowAt(mView.Buffer.FileName, mView.CursorPos.Line - 1);
end;

/// <summary>Puffer, Tracker, Versionsverwaltung und Bereich für AJob; Ergebnis: warum es nicht geht, '' = geht.
/// </summary>
function PrepareJob(const AHooks: TAtlasCodeLinksHooks; const AFileName: string; ALine: Integer;
  var AJob: TScopeJob): string;
var
  mText: string;
begin
  Result := '';
  AJob.FileName := AFileName;
  if not TAtlasIdeBlameScope.BufferLines(AFileName, AJob.Lines, mText) then
  begin
    Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.BlameIssuesNoEditor);
  end
  else if not TAtlasIdeBlameScope.PatternOf(AHooks, AJob.Target, AJob.Pattern) then
  begin
    Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.BlameIssuesNoTracker);
  end
  else
  begin
    AJob.Vcs := TAtlasIdeVcs.ForFolder(ExtractFileDir(AFileName));
    if (AJob.Vcs = nil) or (AJob.Vcs.Kind = TAtlasVcsKind.None) then
    begin
      Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.BlameIssuesNoVcs);
      Exit;
    end;
    if not TAtlasBlameLinks.Scope(mText, ALine, AJob.First, AJob.Last, AJob.Name) then
    begin
      AJob.Name := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.BlameIssuesUnitName, [ExtractFileName(AFileName)]);
    end;
    AJob.Kind := AJob.Vcs.Kind;
    AJob.Max := TAtlasIdeSettings.Current.IssuesBlameMaxRevisions;
  end;
end;

/// <summary>Commits des Bereichs im Hintergrund lesen und danach zeigen, solange niemand eine neue Liste
/// angefordert hat; False, wenn die Versionsverwaltung beendet ist.</summary>
function RunJob(const AJob: TScopeJob): Boolean;
var
  mJob: TScopeJob;
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
      if (TAtlasIdeBlameScope.FInstance <> nil) and (TAtlasIdeBlameScope.FInstance.FSerialOf = mJob.Serial) and
        (TAtlasIdeBlameScope.FInstance.FList = mJob.List) then
      begin
        TAtlasGuard.Run(TAtlasFeature.BlameIssues,
          procedure
          begin
            TAtlasIdeBlameScope.FInstance.ShowList(mJob.List, mJob.Name, mHistory, mJob.Target, mJob.Pattern,
              mJob.Kind);
          end);
      end;
    end);
end;

procedure TAtlasIdeBlameScope.ShowAt(const AFileName: string; ALine: Integer);
var
  mJob: TScopeJob;
  mProblem: string;
begin
  Inc(FList);
  mJob := Default(TScopeJob);
  mJob.List := FList;
  mJob.Serial := FSerialOf;
  mProblem := PrepareJob(FHooks, AFileName, ALine, mJob);
  if mProblem <> '' then
  begin
    TAtlasIdeResultsWindow.ShowIssues(mProblem, mJob.List, nil);
    Exit;
  end;
  TAtlasIdeResultsWindow.ShowIssues(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.BlameIssuesSearching,
    [mJob.Name]), mJob.List, nil);
  if not RunJob(mJob) then
  begin
    // Versionsverwaltung beendet (Entladen): kein Ergebnis mehr.
    TAtlasIdeResultsWindow.ShowIssues(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.BlameIssuesFailed,
      [mJob.Name, AtlasVcsOutcomeName(TAtlasVcsOutcome.Cancelled)]), mJob.List, nil);
  end;
end;

function TAtlasIdeBlameScope.IssueText(AIssue: Integer; AKnown: Boolean; const ADetails: TAtlasTrackerDetails): string;
var
  mIssue: TAtlasBlameIssue;
begin
  mIssue := FListResult.Issues[AIssue];
  Result := TAtlasIssueTip.IssueRow(mIssue.Match.Key, AKnown, ADetails, mIssue.LastDate,
    TTimeZone.Local.ToUniversalTime(Now), Length(mIssue.Commits));
end;

/// <summary>Warum die Liste leer bleibt (nicht eingecheckt, gescheitert); '' = Commits gelesen.</summary>
function HistoryProblem(const AName: string; const AHistory: TAtlasBlameHistory): string;
begin
  Result := '';
  case AHistory.Outcome of
    TAtlasBlameHistoryOutcome.NotCommitted:
      Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.BlameIssuesNotCommitted, [AName]);
    TAtlasBlameHistoryOutcome.Failed:
      Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.BlameIssuesFailed,
        [AName, AtlasVcsOutcomeName(AHistory.VcsOutcome)]);
    TAtlasBlameHistoryOutcome.Ok: ;
  end;
end;

/// <summary>Zeilen der Commits von Issue AIssue.</summary>
function CommitRows(const AResult: TAtlasBlameIssueList; AIssue: Integer; AKind: TAtlasVcsKind):
  TArray<TAtlasResultCommit>;
var
  mIndex, mId: Integer;
  mLine: TAtlasVcsLineCommit;
begin
  SetLength(Result, Length(AResult.Issues[AIssue].Commits));
  for mIndex := 0 to High(AResult.Issues[AIssue].Commits) do
  begin
    mId := AResult.Issues[AIssue].Commits[mIndex];
    mLine := AResult.Commits[mId];
    Result[mIndex].Id := mId;
    Result[mIndex].Text := TAtlasIssueTip.CommitRow(TAtlasBlameLinks.ShortRevision(AKind, mLine.Revision),
      mLine.Author, TTimeZone.Local.ToLocalTime(mLine.Date), TAtlasBlameLinks.Subject(mLine.Message));
  end;
end;

/// <summary>Zeilen der Issues mit dem Stand aus dem Zwischenspeicher; AKnown: Stand vorhanden.</summary>
function IssueRows(AOwner: TAtlasIdeBlameScope; const APreview: TAtlasIdeIssuePreview;
  out AKnown: TArray<Boolean>): TArray<TAtlasResultIssue>;
var
  mIndex: Integer;
  mMatch: TAtlasIssueKeyMatch;
  mDetails: TAtlasTrackerDetails;
begin
  SetLength(Result, Length(AOwner.FListResult.Issues));
  SetLength(AKnown, Length(AOwner.FListResult.Issues));
  for mIndex := 0 to High(AOwner.FListResult.Issues) do
  begin
    mMatch := AOwner.FListResult.Issues[mIndex].Match;
    AKnown[mIndex] := False;
    mDetails := TAtlasTrackerDetails.Empty;
    if APreview <> nil then
    begin
      AKnown[mIndex] := APreview.Lookups.Peek(mMatch.IssueTarget(AOwner.FListTarget), mMatch.IssueKey, mDetails);
    end;
    Result[mIndex].Id := mIndex;
    Result[mIndex].Text := AOwner.IssueText(mIndex, AKnown[mIndex], mDetails);
    Result[mIndex].Commits := CommitRows(AOwner.FListResult, mIndex, AOwner.FListKind);
  end;
end;

/// <summary>Titel und Zustand nachfragen, die der Zwischenspeicher nicht (frisch) hat; die Zeile folgt der Antwort.
/// </summary>
procedure AskMissing(AOwner: TAtlasIdeBlameScope; const APreview: TAtlasIdeIssuePreview; AList: Integer;
  const AKnown: TArray<Boolean>);
var
  mIndex, mAsked: Integer;
  mMatch: TAtlasIssueKeyMatch;
  mDetails: TAtlasTrackerDetails;
begin
  mAsked := 0;
  for mIndex := 0 to High(AOwner.FListResult.Issues) do
  begin
    mMatch := AOwner.FListResult.Issues[mIndex].Match;
    if AKnown[mIndex] and APreview.Lookups.Peek(mMatch.IssueTarget(AOwner.FListTarget), mMatch.IssueKey, mDetails) and
      TAtlasIdeIssueLookups.Fresh(mDetails) then
    begin
      Continue;
    end;
    if mAsked >= TAtlasIdeBlameScope.cMaxLookups then
    begin
      Break;
    end;
    Inc(mAsked);
    AOwner.AskRow(APreview, AList, mIndex);
  end;
end;

procedure TAtlasIdeBlameScope.ShowList(AList: Integer; const AName: string; const AHistory: TAtlasBlameHistory;
  const ATarget: TAtlasTrackerTarget; const APattern: TAtlasIssueKeyPattern; AKind: TAtlasVcsKind);
var
  mIssues: TArray<TAtlasResultIssue>;
  mPreview: TAtlasIdeIssuePreview;
  mKnown: TArray<Boolean>;
  mProblem: string;
begin
  mProblem := HistoryProblem(AName, AHistory);
  if mProblem = '' then
  begin
    FListTarget := ATarget;
    FListKind := AKind;
    FListResult := TAtlasBlameLinks.Group(APattern, AHistory.Commits);
    if Length(FListResult.Issues) = 0 then
    begin
      mProblem := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.BlameIssuesNone, [AName, Length(FListResult.Commits)]);
    end;
  end;
  if mProblem <> '' then
  begin
    TAtlasIdeResultsWindow.ShowIssues(mProblem, AList, nil);
    Exit;
  end;
  mPreview := Preview(FHooks);
  mIssues := IssueRows(Self, mPreview, mKnown);
  TAtlasIdeResultsWindow.ShowIssues(TAtlasIssueTip.ScopeTitle(AName, Length(FListResult.Issues),
    Length(FListResult.Commits), FListResult.Unlinked), AList, mIssues);
  if mPreview <> nil then
  begin
    AskMissing(Self, mPreview, AList, mKnown);
  end;
end;

procedure TAtlasIdeBlameScope.AskRow(const APreview: TAtlasIdeIssuePreview; AList, AId: Integer);
var
  mMatch: TAtlasIssueKeyMatch;
  mSerial: Integer;
begin
  // Eigene Routine: Jede Rückmeldung fängt ihr eigenes AId ein (nicht die Schleifenvariable).
  mMatch := FListResult.Issues[AId].Match;
  mSerial := FSerialOf;
  APreview.Lookups.Lookup(mMatch.IssueTarget(FListTarget), mMatch.IssueKey,
    procedure(ASucceeded: Boolean; const ADetails: TAtlasTrackerDetails; AError: TAtlasCiFetchError)
    begin
      if ASucceeded and (FInstance <> nil) and (FInstance.FSerialOf = mSerial) and (FInstance.FList = AList) and
        (AId <= High(FInstance.FListResult.Issues)) then
      begin
        TAtlasIdeResultsWindow.SetIssueText(AList, AId, FInstance.IssueText(AId, True, ADetails));
      end;
    end);
end;

procedure TAtlasIdeBlameScope.IssueOpen(AList, AId: Integer);
var
  mMatch: TAtlasIssueKeyMatch;
begin
  if (AList <> FList) or (AId < 0) or (AId > High(FListResult.Issues)) or not Assigned(FHooks.Show) then
  begin
    Exit;
  end;
  mMatch := FListResult.Issues[AId].Match;
  FHooks.Show(mMatch.IssueTarget(FListTarget), mMatch.IssueKey);
end;

procedure TAtlasIdeBlameScope.IssueCommit(AList, AId: Integer);
var
  mCommit: TAtlasVcsLineCommit;
  mLines: TArray<string>;
begin
  if (AList <> FList) or (AId < 0) or (AId > High(FListResult.Commits)) then
  begin
    Exit;
  end;
  mCommit := FListResult.Commits[AId];
  // Nachricht, Leerzeile, dann der Unterschied des Bereichs.
  mLines := TTextLines.SplitLines(TrimRight(mCommit.Message));
  mLines := mLines + [''] + mCommit.Patch;
  TAtlasUndoDiffView.Execute(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.BlameIssuesDiffTitle,
    [TAtlasBlameLinks.ShortRevision(FListKind, mCommit.Revision), TAtlasBlameLinks.Subject(mCommit.Message)]),
    mLines);
end;

end.
