unit Atlas.IDE.Tracker.KnownErrors;

// Bekannte Fehler beim Exception-Halt (#2460), Teil des Trackers, über den
// Vertrag Atlas.IDE.Contracts.KnownErrors (Debugger und Tracker kennen sich
// nicht). TAtlasTrackerKnownErrors stellt IAtlasKnownErrors bereit, solange
// „Meine Issues“ läuft:
// - Lookup: Signatur und Suchtexte aus Atlas.Core.Tracker.KnownErrors; Treffer
//   aus dem Zwischenspeicher der Sitzung, sonst eine Suche im Hintergrund beim
//   Tracker des gestarteten Projekts (bis zu drei Freitextsuchen, je höchstens
//   cTimeoutMs). Das Ende meldet IAtlasKnownErrorsView.KnownErrorsChanged.
//   Ohne Netz bleibt die Signatur für die Sitzung ohne Treffer.
// - Run: Öffnen im Fenster „Atlas-Issue“, Kommentar über den Schreibweg von
//   „Beginnen“ (issues.syncState), Wieder öffnen = Kommentar und Öffnen (den
//   Zustand setzt der Benutzer dort), Neues Issue über „Issue anlegen …“.
// Ohne issues.debugKnownErrors antwortet Lookup mit Off. Hauptthread.
// Protokoll ohne Kennung, Titel oder Meldung.

interface

uses
  System.SysUtils,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.KnownErrors,
  Atlas.Core.Diagnostics.WorkerSlot,
  Atlas.Core.Modules.Contract,
  Atlas.Core.KnownErrors.Contract,
  Atlas.IDE.Contracts.KnownErrors,
  Atlas.IDE.Tracker.IssuesContext,
  Atlas.IDE.Tracker.IssuesServices;

type
  TAtlasTrackerKnownErrors = class(TInterfacedObject, IAtlasKnownErrors)
  public const
    /// <summary>Zeitgrenze je Suche beim Tracker.</summary>
    cTimeoutMs = 5000;
  private type
    /// <summary>Eine Suche, wie sie in den Hintergrund geht.</summary>
    TJob = record
      Key: string;
      Queries: TArray<string>;
      Provider: IAtlasTrackerProvider;
      Target: TAtlasTrackerTarget;
      EndStates: TArray<string>;
      Transport: IAtlasCiTransport;
    end;
  private
    FContext: TAtlasIdeIssuesContext;
    FServices: TAtlasIdeIssuesServices;
    FCache: TAtlasKnownErrorsCache;
    FWorkers: TAtlasWorkerSlot;
    function Worker(const AKeep: IInterface; const AJob: TJob): TProc;
    procedure Found(const AKey: string; const AErrors: TArray<TAtlasKnownError>);
    procedure Search(const AKey: string; const AQueries: TArray<string>; const AProvider: IAtlasTrackerProvider;
      const ATarget: TAtlasTrackerTarget);
    function CanComment(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget): Boolean;
    procedure Comment(const AReport: TAtlasDebugExceptionReport; const AKey: string);
    function Labels: TAtlasKnownErrorLabels;
    function BranchOf(const AProject: string): string;
  public
    /// <summary>AContext und AServices gehören „Meine Issues“ und leben bis Detach.</summary>
    constructor Create(AContext: TAtlasIdeIssuesContext; AServices: TAtlasIdeIssuesServices);
    destructor Destroy; override;
    /// <summary>Vor dem Stoppen von „Meine Issues“: Suchen abbrechen, danach antwortet das Objekt mit Off.</summary>
    procedure Detach;
    /// <summary>Als IAtlasKnownErrors über AScope bereitstellen (für den Debugger).</summary>
    function ProvideIn(const AScope: IAtlasModuleScope): IAtlasRegistration;
    function Lookup(const AReport: TAtlasDebugExceptionReport): TAtlasKnownErrorsResult;
    procedure Run(AAction: TAtlasKnownErrorAction; const AReport: TAtlasDebugExceptionReport; const AKey: string);
  end;

implementation

uses
  System.Classes,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Notifications.MessageSink,
  Atlas.Core.Tracker.Files,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Tracker.NewIssue,
  Atlas.IDE.Tracker.Workflow,
  Atlas.UI.Tracker.Issue.Strings;

/// <summary>Bis zu AJob.Queries beim Tracker suchen; bricht beim ersten Fehler ab und behält, was es hat.</summary>
function SearchAll(const AJob: TAtlasTrackerKnownErrors.TJob): TArray<TArray<TAtlasTrackerIssue>>;
var
  mQuery: string;
  mIssues: TArray<TAtlasTrackerIssue>;
  mError: TAtlasCiFetchError;
begin
  Result := nil;
  for mQuery in AJob.Queries do
  begin
    if TAtlasShutdown.Signalled or not AJob.Provider.Search(TAtlasTrackerCall.Create(AJob.Target, AJob.Transport,
      TAtlasTrackerKnownErrors.cTimeoutMs), mQuery, TAtlasKnownErrorSearch.cMaxPerQuery, mIssues, mError) then
    begin
      Break;
    end;
    Result := Result + [mIssues];
  end;
end;

/// <summary>Ergebnis an alle Ansichten (Debugger) melden.</summary>
procedure NotifyViews;
var
  mItem: IInterface;
  mView: IAtlasKnownErrorsView;
begin
  for mItem in AtlasModuleRegistry.FindAll(IAtlasKnownErrorsView) do
  begin
    if Supports(mItem, IAtlasKnownErrorsView, mView) then
    begin
      mView.KnownErrorsChanged;
    end;
  end;
end;

{ TAtlasTrackerKnownErrors }

constructor TAtlasTrackerKnownErrors.Create(AContext: TAtlasIdeIssuesContext; AServices: TAtlasIdeIssuesServices);
begin
  inherited Create;
  FContext := AContext;
  FServices := AServices;
  FCache := TAtlasKnownErrorsCache.Create;
  FWorkers := TAtlasWorkerSlot.Create(HInstance);
end;

destructor TAtlasTrackerKnownErrors.Destroy;
begin
  Detach;
  FWorkers.Free;
  FCache.Free;
  inherited;
end;

procedure TAtlasTrackerKnownErrors.Detach;
begin
  FContext := nil;
  FServices := nil;
  FWorkers.Release(True);
end;

function TAtlasTrackerKnownErrors.ProvideIn(const AScope: IAtlasModuleScope): IAtlasRegistration;
begin
  Result := AScope.Provide(IAtlasKnownErrors, Self as IAtlasKnownErrors);
end;

function TAtlasTrackerKnownErrors.Worker(const AKeep: IInterface; const AJob: TJob): TProc;
var
  mJob: TJob;
  mKeep: IInterface;
  mOwner: TAtlasTrackerKnownErrors;
begin
  // Eigene Routine: Die anonyme Methode hält nur diese Werte.
  mJob := AJob;
  mKeep := AKeep;
  mOwner := Self;
  Result :=
    procedure
    var
      mFound: TArray<TArray<TAtlasTrackerIssue>>;
      mErrors: TArray<TAtlasKnownError>;
    begin
      mFound := nil;
      try
        mFound := SearchAll(mJob);
      except
        // Kein Dialog aus dem Hintergrund: als „ohne Treffer“ werten.
        on E: Exception do
        begin
          TAtlasGuard.Log('Bekannte Fehler: Suche mit ' + E.ClassName + ' abgebrochen'); // german-ok: Protokoll
        end;
      end;
      mJob.Transport := nil;
      mErrors := TAtlasKnownErrorSearch.Rank(mFound, mJob.Target.Provider, mJob.EndStates);
      if TAtlasShutdown.Signalled then
      begin
        Exit;
      end;
      TAtlasMainThread.Queue(TAtlasFeature.Tracker,
        procedure
        begin
          if mKeep <> nil then
          begin
            mOwner.Found(mJob.Key, mErrors);
          end;
        end);
    end;
end;

procedure TAtlasTrackerKnownErrors.Found(const AKey: string; const AErrors: TArray<TAtlasKnownError>);
begin
  FWorkers.Prune;
  if FContext = nil then
  begin
    Exit;
  end;
  FCache.Finished(AKey, AErrors);
  TAtlasGuard.Log(Format('Bekannte Fehler: %d Treffer', [Length(AErrors)])); // german-ok: Protokoll
  NotifyViews;
end;

procedure TAtlasTrackerKnownErrors.Search(const AKey: string; const AQueries: TArray<string>;
  const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget);
var
  mJob: TJob;
begin
  mJob := Default(TJob);
  mJob.Key := AKey;
  mJob.Queries := AQueries;
  mJob.Provider := AProvider;
  mJob.Target := ATarget;
  mJob.EndStates := TAtlasIdeTrackerSync.Options(ATarget).EndStates;
  // Der Transport liest das Token ohne Dialog; ohne Token bleibt die Signatur ohne Treffer.
  mJob.Transport := FContext.TransportOf(AProvider, ATarget);
  FCache.Started(AKey);
  if mJob.Transport = nil then
  begin
    FCache.Finished(AKey, nil);
    Exit;
  end;
  FWorkers.Start(TThread.CreateAnonymousThread(Worker(Self, mJob)));
end;

function TAtlasTrackerKnownErrors.CanComment(const AProvider: IAtlasTrackerProvider;
  const ATarget: TAtlasTrackerTarget): Boolean;
begin
  Result := (FServices <> nil) and (FServices.Tracking <> nil) and (FServices.Tracking.Sync <> nil) and
    FServices.Tracking.Sync.Enabled(AProvider, ATarget);
end;

function TAtlasTrackerKnownErrors.Lookup(const AReport: TAtlasDebugExceptionReport): TAtlasKnownErrorsResult;
var
  mTarget: TAtlasTrackerTarget;
  mProvider: IAtlasTrackerProvider;
  mSignature: TAtlasKnownErrorSignature;
  mQueries: TArray<string>;
  mKey: string;
begin
  Result := Default(TAtlasKnownErrorsResult);
  if (FContext = nil) or not TAtlasIdeSettings.Current.IssuesDebugKnownErrors or (AReport.Project = '') then
  begin
    Exit;
  end;
  mTarget := FContext.TargetOf(AReport.Project);
  mProvider := FContext.ProviderOf(mTarget.Provider);
  mSignature := TAtlasKnownErrorSignature.FromReport(AReport);
  mQueries := TAtlasKnownErrorSearch.Queries(mSignature);
  if (mProvider = nil) or (Length(mQueries) = 0) then
  begin
    Exit;
  end;
  Result.CanComment := CanComment(mProvider, mTarget);
  Result.CanCreate := TAtlasIdeNewIssue.Enabled;
  mKey := LowerCase(mTarget.Provider + '|' + mTarget.Url + '|' + mTarget.Project) + '|' + mSignature.Key;
  Result.State := FCache.StateOf(mKey, Result.Errors);
  if Result.State = TAtlasKnownErrorsState.Off then
  begin
    Search(mKey, mQueries, mProvider, mTarget);
    Result.State := FCache.StateOf(mKey, Result.Errors);
  end;
end;

function TAtlasTrackerKnownErrors.Labels: TAtlasKnownErrorLabels;
begin
  Result.Again := TAtlasIssueStrings.Text(TAtlasIssueTextId.KnownErrorsAgain);
  Result.Location := TAtlasIssueStrings.Text(TAtlasIssueTextId.KnownErrorsLocation);
  Result.Stack := TAtlasIssueStrings.Text(TAtlasIssueTextId.KnownErrorsStack);
  Result.Branch := TAtlasIssueStrings.Text(TAtlasIssueTextId.KnownErrorsBranch);
end;

function TAtlasTrackerKnownErrors.BranchOf(const AProject: string): string;
var
  mGitDir, mHead: string;
begin
  Result := '';
  mGitDir := '';
  if FContext <> nil then
  begin
    mGitDir := FContext.StateOf(AProject).GitDir;
  end;
  if (mGitDir <> '') and TAtlasTrackerFiles.Files.ReadText(TAtlasTrackerFiles.Join(mGitDir, 'HEAD'), mHead) then
  begin
    Result := TAtlasKnownErrorSearch.BranchOfHead(mHead);
  end;
end;

procedure TAtlasTrackerKnownErrors.Comment(const AReport: TAtlasDebugExceptionReport; const AKey: string);
var
  mTarget: TAtlasTrackerTarget;
  mMessages: TAtlasMessageSink;
  mKey: string;
begin
  mTarget := FContext.TargetOf(AReport.Project);
  mMessages := FContext.Messages;
  mKey := AKey;
  FServices.Tracking.Sync.SendComment(FContext.ProviderOf(mTarget.Provider), mTarget, AKey,
    TAtlasKnownErrorSearch.CommentText(AReport, Labels, BranchOf(AReport.Project)),
    procedure(const AResult: TAtlasTrackerWriteResult)
    begin
      if AResult.Error = TAtlasCiFetchError.None then
      begin
        mMessages.Say(TAtlasIssueStrings.Fmt(TAtlasIssueTextId.KnownErrorsCommented, [mKey]));
      end
      else
      begin
        mMessages.Say(TAtlasIssueStrings.Fmt(TAtlasIssueTextId.KnownErrorsCommentFailed, [mKey]));
      end;
    end);
end;

procedure TAtlasTrackerKnownErrors.Run(AAction: TAtlasKnownErrorAction; const AReport: TAtlasDebugExceptionReport;
  const AKey: string);
var
  mTarget: TAtlasTrackerTarget;
begin
  if (FContext = nil) or (FServices = nil) then
  begin
    Exit;
  end;
  mTarget := FContext.TargetOf(AReport.Project);
  case AAction of
    TAtlasKnownErrorAction.Open:
      FServices.Preview.Show(mTarget, AKey);
    TAtlasKnownErrorAction.Comment:
      Comment(AReport, AKey);
    TAtlasKnownErrorAction.Reopen:
      begin
        // Zustand setzt der Benutzer im Fenster „Atlas-Issue“; der Kommentar sagt, warum.
        if CanComment(FContext.ProviderOf(mTarget.Provider), mTarget) then
        begin
          Comment(AReport, AKey);
        end;
        FServices.Preview.Show(mTarget, AKey);
      end;
    TAtlasKnownErrorAction.NewIssue:
      TAtlasIdeNewIssue.FromCrash(TAtlasKnownErrorSearch.IssueTitle(AReport),
        TAtlasKnownErrorSearch.IssueText(AReport, Labels, BranchOf(AReport.Project)), nil);
  end;
end;

end.
