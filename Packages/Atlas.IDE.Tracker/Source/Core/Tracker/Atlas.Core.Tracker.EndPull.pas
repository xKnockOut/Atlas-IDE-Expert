unit Atlas.Core.Tracker.EndPull;

// „Beenden“ mit Pull Request (#2136, issues.github.createPr), ohne VCL und
// Open Tools API; aus einem Hintergrund-Thread aufrufen.
// - Nur Git und ein Tracker, der IAtlasTrackerPullRequests kann (GitHub).
// - Zeigt origin nicht auf das Repository des Trackers (Fork): Foreign, nichts
//   gepusht.
// - Hat die Arbeitskopie ungesicherte Änderungen (unversionierte Dateien
//   zählen nicht): Dirty, nichts gepusht; erst committen.
// - Sonst git push --set-upstream origin <Branch>, dann legt der Tracker den
//   Pull Request an bzw. nennt den schon offenen (Existing). Der Push läuft
//   auch bei einem offenen Pull Request: Er bringt ihn auf den Stand.

interface

uses
  Atlas.Core.Tracker.Contract,
  Atlas.Core.VersionControl.Contract;

type
  TAtlasEndPullRequest = record
    Vcs: IAtlasVersionControl;
    Pulls: IAtlasTrackerPullRequests;
    Call: TAtlasTrackerCall;
    Key: string;
    Spec: TAtlasTrackerPullSpec;
    /// <summary>URL des Remotes origin der Arbeitskopie; '' unbekannt.</summary>
    Origin: string;
  end;

  TAtlasEndPull = class
  public const
    cOrigin = 'origin';
    cHeadsPrefix = 'refs/heads/';
  public
    /// <summary>Pushen und Pull Request anlegen bzw. finden (siehe Kopf der Unit).</summary>
    class function Run(const ARequest: TAtlasEndPullRequest): TAtlasTrackerPullResult; static;
    /// <summary>AChanges enthalten Änderungen außer unversionierten Dateien.</summary>
    class function Dirty(const AChanges: TArray<TAtlasVcsChange>): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.CiBuild.Contract;

class function TAtlasEndPull.Dirty(const AChanges: TArray<TAtlasVcsChange>): Boolean;
var
  mChange: TAtlasVcsChange;
begin
  Result := False;
  for mChange in AChanges do
  begin
    if mChange.Kind <> TAtlasVcsChangeKind.Untracked then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Was vor dem Push zu prüfen ist; False mit AResult, wenn es nicht weitergeht.</summary>
function Eligible(const ARequest: TAtlasEndPullRequest; out AWork: IAtlasVcsLocalWork;
  out AResult: TAtlasTrackerPullResult): Boolean;
var
  mChanges: TArray<TAtlasVcsChange>;
  mOutcome: TAtlasVcsOutcome;
begin
  Result := False;
  AWork := nil;
  if (ARequest.Vcs = nil) or (ARequest.Pulls = nil) or (ARequest.Vcs.Kind <> TAtlasVcsKind.Git) or
    (Trim(ARequest.Spec.Head) = '') or not Supports(ARequest.Vcs, IAtlasVcsLocalWork, AWork) then
  begin
    AResult := TAtlasTrackerPullResult.Failure(TAtlasCiFetchError.NotConfigured, 0, '');
    Exit;
  end;
  if not ARequest.Pulls.SameRepository(ARequest.Call.Target, ARequest.Origin) then
  begin
    AResult := TAtlasTrackerPullResult.Make(TAtlasTrackerPullOutcome.Foreign);
    Exit;
  end;
  mOutcome := ARequest.Vcs.Changes(mChanges);
  if (mOutcome <> TAtlasVcsOutcome.Ok) or TAtlasEndPull.Dirty(mChanges) then
  begin
    AResult := TAtlasTrackerPullResult.Make(TAtlasTrackerPullOutcome.Dirty);
    if mOutcome <> TAtlasVcsOutcome.Ok then
    begin
      AResult.Message := AtlasVcsOutcomeName(mOutcome);
    end;
    Exit;
  end;
  Result := True;
end;

class function TAtlasEndPull.Run(const ARequest: TAtlasEndPullRequest): TAtlasTrackerPullResult;
var
  mWork: IAtlasVcsLocalWork;
  mPush: TAtlasVcsOutcome;
  mHead: string;
begin
  if not Eligible(ARequest, mWork, Result) then
  begin
    Exit;
  end;
  mHead := Trim(ARequest.Spec.Head);
  mPush := mWork.Push(mHead, cOrigin, cHeadsPrefix + mHead, True);
  if mPush <> TAtlasVcsOutcome.Ok then
  begin
    Result := TAtlasTrackerPullResult.Make(TAtlasTrackerPullOutcome.PushFailed);
    Result.Message := AtlasVcsOutcomeName(mPush);
    Exit;
  end;
  Result := ARequest.Pulls.CreatePull(ARequest.Call, ARequest.Key, ARequest.Spec);
end;

end.
