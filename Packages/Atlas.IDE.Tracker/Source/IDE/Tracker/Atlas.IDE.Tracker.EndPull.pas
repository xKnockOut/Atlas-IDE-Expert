unit Atlas.IDE.Tracker.EndPull;

// Pull Request beim „Beenden“ in der IDE (#2136), für
// Atlas.IDE.Tracker.Workflow:
// - Offer im Hauptthread: Abschnitt „Pull Request anlegen“ nur mit einem
//   Tracker, der IAtlasTrackerPullRequests kann (GitHub), und einem Branch;
//   vorab angehakt mit issues.github.createPr, solange kein Pull Request für
//   das Issue offen ist. Ziel issues.github.prBase (auch je Verbindung), Text
//   aus issues.github.prBody mit denselben Platzhaltern wie der Kommentar.
// - Runner für den Hintergrund: Versionsverwaltung des Ordners, origin aus
//   .git/config, dann TAtlasEndPull (Push und Anlegen).

interface

uses
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.EndSteps,
  Atlas.Core.Tracker.Workflow,
  Atlas.UI.Tracker.EndPullRows;

type
  TAtlasIdeEndPull = class
  public const
    /// <summary>Zeitlimit je Anfrage an den Tracker bzw. für Push und Prüfung der Arbeitskopie.</summary>
    cTrackerTimeoutMs = 15000;
    cVcsTimeoutMs = 120000;
  public
    /// <summary>Im Hauptthread: Angebot für den Beenden-Dialog. ATitle: Titel des Issues, AValues: Platzhalter wie
    /// für den Kommentar mit Branch und Adresse eines offenen Pull Requests (PullRequest, '' ohne).</summary>
    class function Offer(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget;
      const AOptions: TAtlasTrackerSyncOptions; const ATitle: string;
      const AValues: TAtlasTrackerPlaceholders): TAtlasEndPullOffer; static;
    /// <summary>Im Hintergrund: Schritt „Pull Request“ für AKey in der Arbeitskopie AFolder über ATransport.
    /// </summary>
    class function Runner(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget;
      const ATransport: IAtlasCiTransport; const AFolder, AKey: string): TAtlasTrackerPullRun; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Tracker.EndPull,
  Atlas.IDE.Contracts.VersionControl,
  Atlas.IDE.Tracker.PathSuggestions;

class function TAtlasIdeEndPull.Offer(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget;
  const AOptions: TAtlasTrackerSyncOptions; const ATitle: string;
  const AValues: TAtlasTrackerPlaceholders): TAtlasEndPullOffer;
var
  mBody: string;
begin
  Result := TAtlasEndPullOffer.None;
  if not Supports(AProvider, IAtlasTrackerPullRequests) or (Trim(AValues.Branch) = '') then
  begin
    Exit;
  end;
  mBody := AOptions.GitHub.PrBody;
  if Trim(mBody) = '' then
  begin
    mBody := TAtlasTrackerWorkflow.cDefaultPrBody;
  end;
  Result.Offered := True;
  Result.Checked := AOptions.GitHub.CreatePr and (AValues.PullRequest = '');
  Result.Head := Trim(AValues.Branch);
  Result.Base := AOptions.GitHub.PrBase;
  Result.Title := ATitle;
  Result.Body := TAtlasTrackerWorkflow.Fill(mBody, AValues);
  Result.Draft := AOptions.GitHub.PrDraft;
  Result.Existing := AValues.PullRequest;
  Result.Repository := ATarget.Project;
end;

class function TAtlasIdeEndPull.Runner(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget;
  const ATransport: IAtlasCiTransport; const AFolder, AKey: string): TAtlasTrackerPullRun;
var
  mPulls: IAtlasTrackerPullRequests;
  mTarget: TAtlasTrackerTarget;
  mTransport: IAtlasCiTransport;
  mFolder, mKey: string;
begin
  // Eigene Routine: Die Methodenreferenz hält nur diese Werte.
  if not Supports(AProvider, IAtlasTrackerPullRequests, mPulls) then
  begin
    mPulls := nil;
  end;
  mTarget := ATarget;
  mTransport := ATransport;
  mFolder := AFolder;
  mKey := AKey;
  Result :=
    function(const ASpec: TAtlasTrackerPullSpec): TAtlasTrackerPullResult
    var
      mRequest: TAtlasEndPullRequest;
    begin
      mRequest := Default(TAtlasEndPullRequest);
      mRequest.Vcs := TAtlasIdeVcs.ForFolder(mFolder, TAtlasIdeVcs.AtLeast(cVcsTimeoutMs));
      mRequest.Pulls := mPulls;
      mRequest.Call := TAtlasTrackerCall.Create(mTarget, mTransport, cTrackerTimeoutMs);
      mRequest.Key := mKey;
      mRequest.Spec := ASpec;
      mRequest.Origin := TAtlasIdeTrackerPathSuggestions.OriginOfFolder(mFolder);
      Result := TAtlasEndPull.Run(mRequest);
    end;
end;

end.
