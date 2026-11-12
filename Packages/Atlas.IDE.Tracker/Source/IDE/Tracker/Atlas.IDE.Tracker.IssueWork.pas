unit Atlas.IDE.Tracker.IssueWork;

// Arbeitsstand je Issue (#2052), Teil des Trackers, über den Vertrag
// Atlas.IDE.Contracts.IssueWork (Willkommensseite und Tracker kennen sich
// nicht):
// - TAtlasTrackerIssueWork stellt IAtlasIssueWorkSource bereit, solange
//   „Meine Issues“ läuft: aktives Issue eines Projekts (gemerkt oder aus dem
//   Branch erkannt; bei einer Projektgruppe ersatzweise das des aktiven
//   Projekts) und Zustand der Issues aus Liste und Zwischenspeicher der
//   Vorschau (Atlas.Core.Tracker.IssueWork). Ohne frischen Stand fragt es im
//   Hintergrund ohne Kommentare nach (TAtlasIdeIssueLookups) und meldet
//   danach IAtlasIssueWork.StatusesChanged.
// - TAtlasTrackerIssueWorkLink: „Beginnen“ und „Beenden“ melden der
//   Willkommensseite das bisherige Issue (Arbeitsstand sichern); nach
//   „Beginnen“ bietet sie das Wiederherstellen an. Ohne Willkommensseite
//   wirkungslos.
// Hauptthread. Protokoll ohne Kennung oder Titel.

interface

uses
  System.SysUtils,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.MyIssues,
  Atlas.IDE.Contracts.IssueWork,
  Atlas.IDE.Tracker.IssuesContext,
  Atlas.IDE.Tracker.IssuesServices;

type
  TAtlasTrackerIssueWork = class(TInterfacedObject, IAtlasIssueWorkSource)
  public const
    /// <summary>Höchstens so viele Kennungen fragt ein Aufruf von Statuses im Hintergrund nach.</summary>
    cMaxLookups = 10;
  private
    FContext: TAtlasIdeIssuesContext;
    FServices: TAtlasIdeIssuesServices;
    procedure LookUp(const ATarget: TAtlasTrackerTarget; const AKey: string);
  public
    /// <summary>AContext und AServices gehören „Meine Issues“ und leben bis Detach.</summary>
    constructor Create(AContext: TAtlasIdeIssuesContext; AServices: TAtlasIdeIssuesServices);
    /// <summary>Vor dem Stoppen von „Meine Issues“: danach antwortet das Objekt leer.</summary>
    procedure Detach;
    function ActiveIssue(const AProject: string; out AIssue: TAtlasIssueWorkIssue): Boolean;
    function Statuses(const AProject: string; const AKeys: TArray<string>): TArray<TAtlasIssueWorkInfo>;
  end;

  TAtlasTrackerIssueWorkLink = class
  public
    /// <summary>Arbeitsstand je Issue der Willkommensseite; False ohne sie.</summary>
    class function Work(out AWork: IAtlasIssueWork): Boolean; static;
    /// <summary>Aktives Issue von AProject im Format des Vertrags; False ohne.</summary>
    class function ActiveOf(AContext: TAtlasIdeIssuesContext; const AProject: string;
      out AIssue: TAtlasIssueWorkIssue): Boolean; static;
    /// <summary>Vor „Beginnen“ von ANewKey: Arbeitsstand des bisher aktiven Issues sichern (nicht, wenn es dasselbe
    /// ist).</summary>
    class procedure BeforeStart(AContext: TAtlasIdeIssuesContext; const AProject, ANewKey: string); static;
    /// <summary>Vor „Beenden“: Arbeitsstand von AActive (auf ABranch) sichern.</summary>
    class procedure BeforeEnd(const AProject, ABranch: string; const AActive: TAtlasActiveIssue); static;
    /// <summary>Nach „Beginnen“: „Arbeitsstand wiederherstellen?“, wenn es einen gibt.</summary>
    class procedure AfterStart(const AProject, AKey: string); static;
    /// <summary>Nach „Weiterarbeiten“ an einem wieder geöffneten Issue (#2127): ohne Rückfrage wiederherstellen.
    /// </summary>
    class procedure AfterResume(const AProject, AKey: string); static;
  end;

implementation

uses
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Tracker.IssueWork,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Tracker.IssueLookups,
  Atlas.IDE.Tracker.Workflow;

function IssueOf(const AActive: TAtlasActiveIssue; const ABranch: string): TAtlasIssueWorkIssue;
begin
  Result := Default(TAtlasIssueWorkIssue);
  Result.Key := AActive.Key;
  Result.Title := AActive.Title;
  Result.Branch := AActive.Branch;
  // Aus dem Branch erkannt bzw. ohne gemerkten Branch: der ausgecheckte.
  if Result.Branch = '' then
  begin
    Result.Branch := ABranch;
  end;
end;

function StatusOf(AResolution: TAtlasTrackerResolution): TAtlasIssueWorkStatus;
begin
  case AResolution of
    TAtlasTrackerResolution.Open:
      Result := TAtlasIssueWorkStatus.Open;
    TAtlasTrackerResolution.Resolved:
      Result := TAtlasIssueWorkStatus.Resolved;
  else
    Result := TAtlasIssueWorkStatus.Unknown;
  end;
end;

{ TAtlasTrackerIssueWorkLink }

class function TAtlasTrackerIssueWorkLink.Work(out AWork: IAtlasIssueWork): Boolean;
var
  mItems: TArray<IInterface>;
begin
  AWork := nil;
  Result := False;
  if AtlasModuleRegistry = nil then
  begin
    Exit;
  end;
  mItems := AtlasModuleRegistry.FindAll(IAtlasIssueWork);
  Result := (Length(mItems) > 0) and Supports(mItems[0], IAtlasIssueWork, AWork) and AWork.Enabled;
end;

class function TAtlasTrackerIssueWorkLink.ActiveOf(AContext: TAtlasIdeIssuesContext; const AProject: string;
  out AIssue: TAtlasIssueWorkIssue): Boolean;
var
  mTarget: TAtlasTrackerTarget;
  mBranch: string;
  mActive: TAtlasActiveIssue;
begin
  AIssue := Default(TAtlasIssueWorkIssue);
  Result := False;
  if (AContext = nil) or (AProject = '') then
  begin
    Exit;
  end;
  mTarget := AContext.TargetOf(AProject);
  mBranch := AContext.BranchOf(AProject);
  mActive := TAtlasMyIssues.Effective(AContext.StateOf(AProject), mTarget.Provider, mTarget.Project, mBranch);
  Result := mActive.Active;
  if Result then
  begin
    AIssue := IssueOf(mActive, mBranch);
  end;
end;

class procedure TAtlasTrackerIssueWorkLink.BeforeStart(AContext: TAtlasIdeIssuesContext;
  const AProject, ANewKey: string);
var
  mWork: IAtlasIssueWork;
  mIssue: TAtlasIssueWorkIssue;
begin
  if Work(mWork) and ActiveOf(AContext, AProject, mIssue) and not SameText(mIssue.Key, ANewKey) then
  begin
    mWork.SaveIssue(AProject, mIssue);
  end;
end;

class procedure TAtlasTrackerIssueWorkLink.BeforeEnd(const AProject, ABranch: string;
  const AActive: TAtlasActiveIssue);
var
  mWork: IAtlasIssueWork;
begin
  if AActive.Active and Work(mWork) then
  begin
    mWork.SaveIssue(AProject, IssueOf(AActive, ABranch));
  end;
end;

class procedure TAtlasTrackerIssueWorkLink.AfterStart(const AProject, AKey: string);
var
  mWork: IAtlasIssueWork;
begin
  if Work(mWork) and mWork.HasState(AProject, AKey) then
  begin
    mWork.OfferRestore(AProject, AKey);
  end;
end;

class procedure TAtlasTrackerIssueWorkLink.AfterResume(const AProject, AKey: string);
var
  mWork: IAtlasIssueWork;
begin
  if Work(mWork) and mWork.HasState(AProject, AKey) then
  begin
    mWork.Restore(AProject, AKey);
  end;
end;

{ TAtlasTrackerIssueWork }

constructor TAtlasTrackerIssueWork.Create(AContext: TAtlasIdeIssuesContext; AServices: TAtlasIdeIssuesServices);
begin
  inherited Create;
  FContext := AContext;
  FServices := AServices;
end;

procedure TAtlasTrackerIssueWork.Detach;
begin
  FContext := nil;
  FServices := nil;
end;

function TAtlasTrackerIssueWork.ActiveIssue(const AProject: string; out AIssue: TAtlasIssueWorkIssue): Boolean;
var
  mActiveProject: string;
begin
  Result := TAtlasTrackerIssueWorkLink.ActiveOf(FContext, AProject, AIssue);
  // Projektgruppe: Das Issue hängt am Projekt, das „Beginnen“ hatte; ersatzweise das aktive Projekt der IDE.
  if not Result and (FContext <> nil) and SameText(ExtractFileExt(AProject), '.groupproj') then
  begin
    mActiveProject := TAtlasIdeFiles.ActiveProjectFile;
    Result := (mActiveProject <> '') and TAtlasTrackerIssueWorkLink.ActiveOf(FContext, mActiveProject, AIssue);
  end;
end;

procedure TAtlasTrackerIssueWork.LookUp(const ATarget: TAtlasTrackerTarget; const AKey: string);
begin
  FServices.Preview.Lookups.Lookup(ATarget, AKey,
    procedure(ASucceeded: Boolean; const ADetails: TAtlasTrackerDetails; AError: TAtlasCiFetchError)
    var
      mWork: IAtlasIssueWork;
    begin
      // Nur ein neuer Stand zeichnet neu; ein Fehlschlag fragt erst nach TAtlasIdeIssueLookups.MissingMs wieder.
      if ASucceeded and TAtlasTrackerIssueWorkLink.Work(mWork) then
      begin
        mWork.StatusesChanged;
      end;
    end);
end;

function TAtlasTrackerIssueWork.Statuses(const AProject: string;
  const AKeys: TArray<string>): TArray<TAtlasIssueWorkInfo>;
var
  mTarget: TAtlasTrackerTarget;
  mState: TAtlasIssuesState;
  mFacts: TAtlasTrackerIssueFacts;
  mIssue: TAtlasTrackerIssue;
  mDetails: TAtlasTrackerDetails;
  mEndStates: TArray<string>;
  mIndex, mAsked: Integer;
begin
  SetLength(Result, Length(AKeys));
  for mIndex := 0 to High(AKeys) do
  begin
    Result[mIndex] := Default(TAtlasIssueWorkInfo);
    Result[mIndex].Key := AKeys[mIndex];
  end;
  if (FContext = nil) or (FServices = nil) or (FServices.Preview = nil) or (AProject = '') then
  begin
    Exit;
  end;
  mTarget := FContext.TargetOf(AProject);
  mState := FContext.StateOf(AProject);
  // Zielzustände wie im Dialog „Beenden“, je Verbindung überschreibbar.
  mEndStates := TAtlasIdeTrackerSync.Options(mTarget).EndStates;
  mAsked := 0;
  for mIndex := 0 to High(AKeys) do
  begin
    mFacts := TAtlasTrackerIssueFacts.Empty;
    mFacts.Provider := mTarget.Provider;
    mFacts.EndStates := mEndStates;
    mFacts.InList := mState.Matches(mTarget) and mState.Find(AKeys[mIndex], mIssue);
    if mFacts.InList then
    begin
      Result[mIndex].Title := mIssue.Title;
    end;
    mFacts.Cached := FServices.Preview.Lookups.Peek(mTarget, AKeys[mIndex], mDetails);
    if mFacts.Cached then
    begin
      mFacts.Fresh := TAtlasIdeIssueLookups.Fresh(mDetails);
      mFacts.State := mDetails.State;
      Result[mIndex].Title := mDetails.Title;
    end;
    Result[mIndex].Status := StatusOf(TAtlasTrackerIssueStates.StatusOf(mFacts));
    if TAtlasTrackerIssueStates.NeedsLookup(mFacts) and (mAsked < cMaxLookups) and (mTarget.Provider <> '') then
    begin
      Inc(mAsked);
      LookUp(mTarget, AKeys[mIndex]);
    end;
  end;
end;

end.
