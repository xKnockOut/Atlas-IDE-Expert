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
// Die Meldungen von „Beginnen“, „Beenden“ und „Prüfen“ an die
// Willkommensseite stehen in Atlas.IDE.Tracker.IssueWorkLink.
// Hauptthread. Protokoll ohne Kennung oder Titel.

interface

uses
  System.SysUtils,
  Atlas.Core.Tracker.Contract,
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


implementation

uses
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.IssueWork,
  Atlas.Core.Tracker.MyIssues,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Tracker.IssueLookups,
  Atlas.IDE.Tracker.IssueWorkLink,
  Atlas.IDE.Tracker.Workflow;

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
