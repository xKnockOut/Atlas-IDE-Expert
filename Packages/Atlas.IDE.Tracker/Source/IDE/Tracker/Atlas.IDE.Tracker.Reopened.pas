unit Atlas.IDE.Tracker.Reopened;

// Wieder geöffnete Issues in „Meine Issues“ (#2127, issues.reopened), Teil
// des Trackers. Die Regeln stehen in Atlas.Core.Tracker.Reopened; hier die
// Verbindung zu Abfrage, Meldungen, Beenden und Vorschau:
// - Beenden (EndedIssue): Kennung, Branch, Zeitpunkt und geschriebener
//   Zustand kommen in den Abschnitt "issues" des Projekts.
// - Liste geladen (ListRecorded): erledigt gesehene, beendete Issues, die
//   jetzt offen in der Liste stehen, bekommen die Marke.
// - Meldung (FromNotice, Hook der Meldungen #1271): ein fremder
//   Zustandswechsel von erledigt bzw. Prüfung nach offen an einem Issue, das
//   ich beendet habe oder das in meiner Liste steht, setzt die Marke in jedem
//   gezeigten Projekt dieses Trackers; die Meldung nennt dann den Grund.
// - Grund: der neueste Kommentar seit dem Beenden aus der Meldung, sonst aus
//   dem Zwischenspeicher der Vorschau (#1264, ohne eigene Abfrage).
// - „Gelesen“ (Dismiss) entfernt die Marke, „Weiterarbeiten“ beginnt das
//   Issue auf dem alten Branch (TAtlasIdeIssueStart.Resume); beides nimmt die
//   Marke weg (TAtlasMyIssues.Started).
// Ohne issues.reopened: nichts gemerkt, keine Marke, Meldungen wie bisher.
// Hauptthread. Protokoll ohne Kennung, Titel oder Text.

interface

uses
  System.SysUtils,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.MyIssues,
  Atlas.Core.Tracker.Notify,
  Atlas.Core.Tracker.Reopened,
  Atlas.IDE.Tracker.IssuesContext;

type
  // Benannte Typen: Delphi kennt keine Felder mit direkt angegebenem `reference to` (FPC schon).
  TAtlasIssueReopenedPeek = reference to function(const ATarget: TAtlasTrackerTarget; const AKey: string;
    out ADetails: TAtlasTrackerDetails): Boolean;
  TAtlasIssueReopenedMe = reference to function(const ATarget: TAtlasTrackerTarget): string;
  TAtlasIssueReopenedOpen = reference to procedure(const ATarget: TAtlasTrackerTarget; const AKey: string;
    AAnchor: TDateTime);

  /// <summary>Was die Erkennung von den Diensten braucht; gebaut in Atlas.IDE.Tracker.IssuesServices.</summary>
  TAtlasIssueReopenedHooks = record
    /// <summary>Issue aus dem Zwischenspeicher der Vorschau (ohne Abfrage); False, wenn nicht bekannt.</summary>
    Peek: TAtlasIssueReopenedPeek;
    /// <summary>Mein Anmeldename bei ATarget ('' unbekannt).</summary>
    Me: TAtlasIssueReopenedMe;
    /// <summary>Issue in der Vorschau am Kommentar zu AAnchor zeigen (0 = oben).</summary>
    Open: TAtlasIssueReopenedOpen;
  end;

  TAtlasIdeIssueReopened = class
  private
    FContext: TAtlasIdeIssuesContext;
    FHooks: TAtlasIssueReopenedHooks;
    /// <summary>Gleiche Verbindung (Anbieter und Server; bei GitHub auch das Repository).</summary>
    class function SameTracker(const ATarget, AOther: TAtlasTrackerTarget): Boolean; static;
    /// <summary>Grund aus dem Zwischenspeicher der Vorschau an AReopen; True, wenn er neu ist.</summary>
    function CommentFromPreview(const ATarget: TAtlasTrackerTarget; var AReopen: TAtlasTrackerReopen): Boolean;
  public
    /// <summary>AContext gehört „Meine Issues“ und lebt länger als dieses Objekt.</summary>
    constructor Create(AContext: TAtlasIdeIssuesContext; const AHooks: TAtlasIssueReopenedHooks);
    /// <summary>issues.reopened an?</summary>
    class function Active: Boolean; static;
    /// <summary>Was bei ATarget als erledigt gilt (issues.endStates, issues.reviewStates, je Verbindung).</summary>
    class function DoneStates(const ATarget: TAtlasTrackerTarget): TAtlasTrackerDoneStates; static;
    /// <summary>Nach „Beenden“ von AKey auf ABranch in AState merken; AWritten: geschriebener Zustand ('' =
    /// nicht geändert).</summary>
    procedure EndedIssue(const AProject: string; var AState: TAtlasIssuesState; const AKey, ABranch,
      AWritten: string);
    /// <summary>Nach einer gelungenen Abfrage von AProject: Rückkehr aus der Liste erkennen (AState wird danach
    /// gespeichert).</summary>
    procedure ListRecorded(const ATarget: TAtlasTrackerTarget; var AState: TAtlasIssuesState);
    /// <summary>Hook der Meldungen: Ist ANotice eine Rückkehr an einem meiner Issues, die Marke in den gezeigten
    /// Projekten dieses Trackers setzen und True mit AReopen (für Titel und Sprung zum Kommentar).</summary>
    function FromNotice(const ATarget: TAtlasTrackerTarget; const ANotice: TAtlasTrackerNotice;
      out AReopen: TAtlasTrackerReopen): Boolean;
    /// <summary>Marken für die Ansicht von AProject (Grund aus der Vorschau ergänzt); leer ohne issues.reopened.
    /// </summary>
    function Marks(const AProject: string): TArray<TAtlasTrackerReopen>;
    /// <summary>„Gelesen“: Marke von AKey in AProject entfernen.</summary>
    procedure Dismiss(const AProject, AKey: string);
    /// <summary>Marke von AKey in AProject; False ohne.</summary>
    function Find(const AProject, AKey: string; out AReopen: TAtlasTrackerReopen): Boolean;
    /// <summary>Vorschau am Kommentar der Marke (sonst oben) öffnen.</summary>
    procedure ShowComment(const AProject, AKey: string);
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Tracker.Workflow,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Tracker.Workflow;

const
  cLogMarked = 'Meine Issues: %d wieder geöffnete Issues erkannt (%s)'; // german-ok: Diagnoseprotokoll, nicht in der Oberfläche

{ TAtlasIdeIssueReopened }

constructor TAtlasIdeIssueReopened.Create(AContext: TAtlasIdeIssuesContext; const AHooks: TAtlasIssueReopenedHooks);
begin
  inherited Create;
  FContext := AContext;
  FHooks := AHooks;
end;

class function TAtlasIdeIssueReopened.Active: Boolean;
begin
  Result := TAtlasIdeSettings.Current.IssuesReopened;
end;

class function TAtlasIdeIssueReopened.DoneStates(const ATarget: TAtlasTrackerTarget): TAtlasTrackerDoneStates;
var
  mOptions: TAtlasTrackerSyncOptions;
begin
  mOptions := TAtlasIdeTrackerSync.Options(ATarget);
  Result := TAtlasTrackerDoneStates.Create(ATarget.Provider, mOptions.EndStates, mOptions.ReviewStates);
end;

class function TAtlasIdeIssueReopened.SameTracker(const ATarget, AOther: TAtlasTrackerTarget): Boolean;
begin
  Result := (TAtlasTrackerNotify.ConnectionId(ATarget) <> '') and
    SameText(TAtlasTrackerNotify.ConnectionId(ATarget), TAtlasTrackerNotify.ConnectionId(AOther)) and
    SameText(TAtlasTrackerNotify.UnseenProject(ATarget), TAtlasTrackerNotify.UnseenProject(AOther));
end;

procedure TAtlasIdeIssueReopened.EndedIssue(const AProject: string; var AState: TAtlasIssuesState;
  const AKey, ABranch, AWritten: string);
var
  mEntry: TAtlasTrackerEnded;
begin
  if not Active or (AKey = '') then
  begin
    Exit;
  end;
  mEntry := Default(TAtlasTrackerEnded);
  mEntry.Key := AKey;
  mEntry.Branch := ABranch;
  mEntry.At := TAtlasIdeIssuesTargets.NowUtc;
  mEntry.State := AWritten;
  mEntry.Done := DoneStates(FContext.TargetOf(AProject)).IsDone(AWritten);
  TAtlasTrackerReopened.AddEnded(AState.Ended, mEntry);
end;

function TAtlasIdeIssueReopened.CommentFromPreview(const ATarget: TAtlasTrackerTarget;
  var AReopen: TAtlasTrackerReopen): Boolean;
var
  mDetails: TAtlasTrackerDetails;
  mComment: TAtlasTrackerComment;
  mSince: TDateTime;
begin
  Result := False;
  if not Assigned(FHooks.Peek) or not Assigned(FHooks.Me) or
    not FHooks.Peek(ATarget, AReopen.Key, mDetails) or not mDetails.CommentsLoaded then
  begin
    Exit;
  end;
  // Seit dem Beenden; ohne Beenden über Atlas (EndedAt = 0) der neueste fremde überhaupt.
  mSince := AReopen.EndedAt;
  if TAtlasTrackerReopened.LatestComment(mDetails.Comments, mSince, FHooks.Me(ATarget), mComment) and
    (mComment.Created > AReopen.CommentAt) then
  begin
    TAtlasTrackerReopened.TakeComment(AReopen, mComment);
    Result := True;
  end;
end;

procedure TAtlasIdeIssueReopened.ListRecorded(const ATarget: TAtlasTrackerTarget; var AState: TAtlasIssuesState);
var
  mFound: TArray<TAtlasTrackerReopen>;
  mReopen: TAtlasTrackerReopen;
begin
  if not Active or (Length(AState.Ended) = 0) then
  begin
    Exit;
  end;
  mFound := TAtlasTrackerReopened.FromList(DoneStates(ATarget), AState.Ended, AState.Items,
    TAtlasIdeIssuesTargets.NowUtc);
  for mReopen in mFound do
  begin
    TAtlasTrackerReopened.Mark(AState.Reopened, mReopen);
  end;
  if Length(mFound) > 0 then
  begin
    TAtlasGuard.Log(Format(cLogMarked, [Length(mFound), ATarget.Provider], TFormatSettings.Invariant));
  end;
end;

function TAtlasIdeIssueReopened.FromNotice(const ATarget: TAtlasTrackerTarget; const ANotice: TAtlasTrackerNotice;
  out AReopen: TAtlasTrackerReopen): Boolean;
var
  mTarget: TAtlasTrackerTarget;
  mProject: string;
  mState: TAtlasIssuesState;
  mReopen: TAtlasTrackerReopen;
begin
  Result := False;
  if not Active or (FContext = nil) or not FContext.Started or
    not TAtlasTrackerReopened.FromNotice(DoneStates(ATarget), ANotice, AReopen) then
  begin
    Exit;
  end;
  for mProject in FContext.Selection.Projects do
  begin
    mTarget := FContext.TargetOf(mProject);
    mState := FContext.StateOf(mProject);
    if not SameTracker(ATarget, mTarget) or
      not TAtlasTrackerReopened.Concerns(mState.Ended, mState.Items, ANotice.Key) then
    begin
      Continue;
    end;
    mReopen := AReopen;
    TAtlasTrackerReopened.TakeEnded(mState.Ended, mReopen);
    TAtlasTrackerReopened.Mark(mState.Reopened, mReopen);
    FContext.SaveState(mProject, mState);
    // Branch und Beenden für Titel und Sprung zum Kommentar.
    AReopen := mReopen;
    Result := True;
  end;
  if Result then
  begin
    TAtlasGuard.Log(Format(cLogMarked, [1, ATarget.Provider], TFormatSettings.Invariant));
  end;
end;

function TAtlasIdeIssueReopened.Marks(const AProject: string): TArray<TAtlasTrackerReopen>;
var
  mState: TAtlasIssuesState;
  mTarget: TAtlasTrackerTarget;
  mIndex: Integer;
  mChanged: Boolean;
begin
  Result := nil;
  if not Active or (AProject = '') then
  begin
    Exit;
  end;
  mState := FContext.StateOf(AProject);
  if Length(mState.Reopened) = 0 then
  begin
    Exit;
  end;
  // Ohne Kommentar aus der Meldung: aus der Vorschau, sobald sie das Issue kennt (kein eigenes Abfragen).
  mTarget := FContext.TargetOf(AProject);
  mChanged := False;
  for mIndex := 0 to High(mState.Reopened) do
  begin
    mChanged := CommentFromPreview(mTarget, mState.Reopened[mIndex]) or mChanged;
  end;
  if mChanged then
  begin
    FContext.SaveState(AProject, mState);
  end;
  Result := mState.Reopened;
end;

procedure TAtlasIdeIssueReopened.Dismiss(const AProject, AKey: string);
var
  mState: TAtlasIssuesState;
begin
  if AProject = '' then
  begin
    Exit;
  end;
  mState := FContext.StateOf(AProject);
  if TAtlasTrackerReopened.Dismiss(mState.Reopened, AKey) then
  begin
    FContext.SaveState(AProject, mState);
    FContext.Changed;
  end;
end;

function TAtlasIdeIssueReopened.Find(const AProject, AKey: string; out AReopen: TAtlasTrackerReopen): Boolean;
begin
  Result := (AProject <> '') and TAtlasTrackerReopened.Find(FContext.StateOf(AProject).Reopened, AKey, AReopen);
end;

procedure TAtlasIdeIssueReopened.ShowComment(const AProject, AKey: string);
var
  mReopen: TAtlasTrackerReopen;
begin
  if Assigned(FHooks.Open) and Find(AProject, AKey, mReopen) then
  begin
    FHooks.Open(FContext.TargetOf(AProject), AKey, mReopen.CommentAt);
  end;
end;

end.
