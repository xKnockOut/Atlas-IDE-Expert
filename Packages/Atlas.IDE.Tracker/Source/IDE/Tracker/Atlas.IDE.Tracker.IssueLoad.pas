unit Atlas.IDE.Tracker.IssueLoad;

// Gewähltes Issue im Fenster „Atlas-Issue“ laden und zeigen (#1264).
// - Sofort der letzte Stand aus dem Zwischenspeicher, dann die Abfrage im
//   Hintergrund; frisch geladen ersetzt ihn, ohne Netz bleibt er mit Grund
//   stehen.
// - Eine Abfrage zur Zeit: Ein neuer Wunsch bricht die laufende ab
//   (IAtlasCiCancel) und folgt ihr; Antworten älterer Generationen zählen
//   nicht. Rückkehr über TAtlasMainThread.
// - Zeigt Baum oder Liste der Verknüpfungen (#1279), Knöpfe nur, wenn der
//   Anbieter schreiben kann; Meldungen der Checklisten (#1273) und
//   Verknüpfungen über dem frischen Stand.
// Protokoll anonym: Anbieter und Ergebnis, nie Kennung oder Adresse.

interface

uses
  System.SysUtils,
  System.Classes,
  Atlas.Core.Ci.Contract,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Preview,
  Atlas.UI.Tracker.IssueFrame,
  Atlas.IDE.Tracker.IssueParts;

type
  /// <summary>Schalter aus „Meine Issues“ für das gezeigte Issue.</summary>
  TAtlasIssueLoadHooks = record
    /// <summary>„Beginnen“ möglich.</summary>
    CanStart: TFunc<Boolean>;
    /// <summary>„Anhängen …“ zeigen.</summary>
    CanAttach: TFunc<Boolean>;
    /// <summary>„Prüfen …“ zeigen (#2126).</summary>
    CanReview: TFunc<TAtlasTrackerTarget, TAtlasTrackerIssue, Boolean>;
  end;

  /// <summary>Laufende Abfrage des gezeigten Issues und der Wunsch, der ihr folgt.</summary>
  TAtlasIssueLoadState = record
    Thread: TThread;
    Cancel: IAtlasCiCancel;
    Pending: TAtlasIssueHistoryEntry;
    HasPending: Boolean;
  end;

  TAtlasIdeIssueLoad = class
  private
    FParts: TAtlasIdeIssueParts;
    FHistory: TAtlasIssueHistory;
    FHooks: TAtlasIssueLoadHooks;
    FState: TAtlasIssueLoadState;
    procedure Loaded(AGeneration: Integer; const AEntry: TAtlasIssueHistoryEntry; ASucceeded: Boolean;
      const ADetails: TAtlasTrackerDetails; AError: TAtlasCiFetchError);
    /// <summary>Abfrage im Hintergrund; das Ergebnis über Loaded im Hauptthread.</summary>
    procedure StartLoad(AGeneration: Integer; const AEntry: TAtlasIssueHistoryEntry;
      const AProvider: IAtlasTrackerProvider; const ATransport: IAtlasCiTransport);
    /// <summary>Frisch geladen: Zwischenspeicher, zuletzt geöffnet und Fenster mit den Meldungen der Teile.</summary>
    procedure ShowLoaded(AFrame: TAtlasIssueFrame; const AEntry: TAtlasIssueHistoryEntry;
      const ADetails: TAtlasTrackerDetails);
    /// <summary>Nicht geladen: ohne Netz der letzte Stand mit Grund, sonst die Meldung; abgebrochen nichts.</summary>
    procedure ShowFailed(AFrame: TAtlasIssueFrame; const AEntry: TAtlasIssueHistoryEntry; AError: TAtlasCiFetchError);
    /// <summary>Sofort der letzte Stand aus dem Zwischenspeicher; frisch geladen ersetzt ihn.</summary>
    procedure ShowCached(const AEntry: TAtlasIssueHistoryEntry);
    /// <summary>Issue im Frame zeigen; Baum oder Liste (#1279), die Knöpfe nur, wenn der Anbieter schreiben kann.
    /// </summary>
    procedure ShowOn(AFrame: TAtlasIssueFrame; const ADetails: TAtlasTrackerDetails; const AStatus: string);
    procedure UpdateHistory;
  public
    /// <summary>AParts und AHistory gehören dem Aufrufer.</summary>
    constructor Create(AParts: TAtlasIdeIssueParts; AHistory: TAtlasIssueHistory; const AHooks: TAtlasIssueLoadHooks);
    /// <summary>AEntry laden und zeigen; läuft schon eine Abfrage, folgt dieser Wunsch ihr.</summary>
    procedure Load(const AEntry: TAtlasIssueHistoryEntry);
    /// <summary>Gezeigtes Issue aus dem Zwischenspeicher zeigen (neuer Frame).</summary>
    procedure ShowCurrent;
    /// <summary>Schalter aus den Hooks: „Beginnen“ und „Anhängen …“.</summary>
    procedure ApplyHookFlags(AFrame: TAtlasIssueFrame);
    /// <summary>Laufende Abfrage abbrechen, wartenden Wunsch vergessen.</summary>
    procedure CancelLoad;
    /// <summary>Beendete Threads freigeben; AWait: auf alle warten (Anhalten).</summary>
    procedure ReleaseThreads(AWait: Boolean);
    /// <summary>Hooks lösen (beim Abmelden).</summary>
    procedure Stop;
  end;

implementation

uses
  System.DateUtils,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.UI.Tracker.Issue.Strings,
  Atlas.UI.Tracker.IssueFrame.Contract,
  Atlas.UI.Tracker.IssueTip,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Tracker.IssueContext;

function StaleText(const ADetails: TAtlasTrackerDetails; const AReason: string): string;
var
  mWhen: string;
begin
  mWhen := FormatDateTime('dd.mm.yyyy hh:nn', TTimeZone.Local.ToLocalTime(ADetails.Fetched), FormatSettings);
  if AReason = '' then
  begin
    Result := TAtlasIssueStrings.Fmt(TAtlasIssueTextId.IssuePreviewStale, [mWhen]);
  end
  else
  begin
    Result := TAtlasIssueStrings.Fmt(TAtlasIssueTextId.IssuePreviewStaleOffline, [mWhen, AReason]);
  end;
end;

{ TAtlasIdeIssueLoad }

constructor TAtlasIdeIssueLoad.Create(AParts: TAtlasIdeIssueParts; AHistory: TAtlasIssueHistory;
  const AHooks: TAtlasIssueLoadHooks);
begin
  inherited Create;
  FParts := AParts;
  FHistory := AHistory;
  FHooks := AHooks;
end;

procedure TAtlasIdeIssueLoad.UpdateHistory;
var
  mFrame: TAtlasIssueFrame;
begin
  mFrame := FParts.Context.Frame;
  if mFrame <> nil then
  begin
    mFrame.SetHistory(FHistory.CanBack, FHistory.CanForward);
  end;
end;

procedure TAtlasIdeIssueLoad.ShowOn(AFrame: TAtlasIssueFrame; const ADetails: TAtlasTrackerDetails;
  const AStatus: string);
var
  mContext: TAtlasIdeIssueContext;
  mProvider: IAtlasTrackerProvider;
  mLinks: Boolean;
begin
  mContext := FParts.Context;
  mProvider := nil;
  if mContext.HasCurrent then
  begin
    mProvider := mContext.ProviderOf(mContext.Current.Target);
  end;
  mLinks := TAtlasIdeSettings.Current.IssuesPreviewLinks;
  AFrame.SetFlag(TAtlasIssueFlag.LinksAsTree, mLinks);
  AFrame.SetFlag(TAtlasIssueFlag.CanWriteLinks, mLinks and Supports(mProvider, IAtlasTrackerLinkWriter));
  AFrame.SetFlag(TAtlasIssueFlag.CanReview, mContext.HasCurrent and Assigned(FHooks.CanReview) and
    FHooks.CanReview(mContext.Current.Target, ADetails.Issue));
  AFrame.ShowDetails(ADetails, TAtlasIdeIssueContext.NowUtc, AStatus,
    not TAtlasIdeSettings.Current.IssuesPreviewComments);
end;

procedure TAtlasIdeIssueLoad.ApplyHookFlags(AFrame: TAtlasIssueFrame);
begin
  if Assigned(FHooks.CanStart) then
  begin
    AFrame.SetFlag(TAtlasIssueFlag.CanStart, FHooks.CanStart());
  end;
  AFrame.SetFlag(TAtlasIssueFlag.CanAttach, Assigned(FHooks.CanAttach) and FHooks.CanAttach());
end;

procedure TAtlasIdeIssueLoad.ShowLoaded(AFrame: TAtlasIssueFrame; const AEntry: TAtlasIssueHistoryEntry;
  const ADetails: TAtlasTrackerDetails);
var
  mDetails: TAtlasTrackerDetails;
  mNotice: string;
begin
  mDetails := ADetails;
  mDetails.Fetched := TAtlasIdeIssueContext.NowUtc;
  FParts.Context.Cache.Put(AEntry.Target, mDetails);
  FParts.Context.Remember(AEntry.Target, mDetails.Issue);
  // Nach einem abgewiesenen Abhaken (Beschreibung geändert): Hinweis über dem neuen Stand.
  mNotice := FParts.Checklists.TakeNotice;
  if AFrame = nil then
  begin
    FParts.LinkWrites.TakeNotice;
    Exit;
  end;
  AFrame.SetFlag(TAtlasIssueFlag.Loading, False);
  ApplyHookFlags(AFrame);
  FParts.Checklists.Prepare(AFrame, AEntry);
  // Meldung nach dem Anlegen bzw. Verknüpfen (#1279) über dem frischen Stand.
  ShowOn(AFrame, mDetails, FParts.LinkWrites.TakeNotice);
  FParts.Comments.UpdateWrite;
  if mNotice <> '' then
  begin
    AFrame.ShowNotice(mNotice);
  end;
end;

procedure TAtlasIdeIssueLoad.ShowFailed(AFrame: TAtlasIssueFrame; const AEntry: TAtlasIssueHistoryEntry;
  AError: TAtlasCiFetchError);
var
  mCached: TAtlasTrackerDetails;
begin
  FParts.Checklists.TakeNotice;
  if AFrame = nil then
  begin
    Exit;
  end;
  AFrame.SetFlag(TAtlasIssueFlag.Loading, False);
  if AError = TAtlasCiFetchError.Cancelled then
  begin
    Exit;
  end;
  if FParts.Context.Cache.Get(AEntry.Target, AEntry.Key, TAtlasIdeIssueContext.NowUtc, mCached) then
  begin
    ShowOn(AFrame, mCached, StaleText(mCached, TAtlasIssueTip.ErrorText(AError, AEntry.Key)));
  end
  else
  begin
    AFrame.ShowError(TAtlasIssueTip.ErrorText(AError, AEntry.Key), TAtlasIssuePreview.FixOf(AError));
  end;
end;

procedure TAtlasIdeIssueLoad.ShowCached(const AEntry: TAtlasIssueHistoryEntry);
var
  mFrame: TAtlasIssueFrame;
  mDetails: TAtlasTrackerDetails;
begin
  mFrame := FParts.Context.Frame;
  if mFrame = nil then
  begin
    Exit;
  end;
  FParts.Checklists.Prepare(mFrame, AEntry);
  if FParts.Context.Cache.Get(AEntry.Target, AEntry.Key, TAtlasIdeIssueContext.NowUtc, mDetails) then
  begin
    ShowOn(mFrame, mDetails, StaleText(mDetails, ''));
    FParts.Context.Remember(AEntry.Target, mDetails.Issue);
  end;
  mFrame.SetFlag(TAtlasIssueFlag.Loading, True);
end;

procedure TAtlasIdeIssueLoad.StartLoad(AGeneration: Integer; const AEntry: TAtlasIssueHistoryEntry;
  const AProvider: IAtlasTrackerProvider; const ATransport: IAtlasCiTransport);
var
  mKeep: IInterface;
  mOwner: TAtlasIdeIssueLoad;
  mEntry: TAtlasIssueHistoryEntry;
  mProvider: IAtlasTrackerProvider;
  mTransport: IAtlasCiTransport;
  mComments: Boolean;
begin
  // Der Besitzer der Teile hält auch dieses Objekt; die Antwort kommt nur, solange er lebt.
  mKeep := FParts.Context.Keep;
  mOwner := Self;
  mEntry := AEntry;
  mProvider := AProvider;
  mTransport := ATransport;
  mComments := TAtlasIdeSettings.Current.IssuesPreviewComments;
  FState.Thread := TThread.CreateAnonymousThread(
    procedure
    var
      mResult: TAtlasTrackerDetails;
      mError: TAtlasCiFetchError;
      mOk: Boolean;
    begin
      mResult := TAtlasTrackerDetails.Empty;
      mOk := False;
      mError := TAtlasCiFetchError.Network;
      try
        mOk := mProvider.Details(TAtlasTrackerCall.Create(mEntry.Target, mTransport, TAtlasIssuePreview.cTimeoutMs),
          mEntry.Key, mComments, mResult, mError);
      except
        // Kein Dialog, kein Fehler an die IDE: als Netzfehler werten.
        on E: Exception do
        begin
          mOk := False;
          mError := TAtlasCiFetchError.Network;
          TAtlasGuard.Log('Issue-Vorschau: Abfrage mit ' + E.ClassName + ' abgebrochen');
        end;
      end;
      mTransport := nil;
      if TAtlasShutdown.Signalled then
      begin
        Exit;
      end;
      TAtlasMainThread.Queue(TAtlasFeature.Tracker,
        procedure
        begin
          if mKeep <> nil then
          begin
            mOwner.Loaded(AGeneration, mEntry, mOk, mResult, mError);
          end;
        end);
    end);
  FState.Thread.FreeOnTerminate := False;
  FState.Thread.Start;
end;

procedure TAtlasIdeIssueLoad.Load(const AEntry: TAtlasIssueHistoryEntry);
var
  mContext: TAtlasIdeIssueContext;
  mProvider: IAtlasTrackerProvider;
  mTransport: IAtlasCiTransport;
  mGeneration: Integer;
begin
  mContext := FParts.Context;
  if not mContext.Started then
  begin
    Exit;
  end;
  // Eine Abfrage zur Zeit: die laufende abbrechen, dieser Wunsch folgt ihr.
  ReleaseThreads(False);
  if FState.Thread <> nil then
  begin
    FState.Pending := AEntry;
    FState.HasPending := True;
    if FState.Cancel <> nil then
    begin
      FState.Cancel.Cancel;
    end;
    Exit;
  end;
  FParts.Media.Cancel;
  mGeneration := mContext.Select(AEntry);
  FParts.Comments.UpdateWrite;
  FParts.Development.Select(AEntry.Target, AEntry.Key);
  UpdateHistory;
  ShowCached(AEntry);
  mProvider := mContext.ProviderOf(AEntry.Target);
  // Der Transport entsteht hier, damit „Abbrechen“ ihn erreicht; er liest das Token ohne Dialog.
  mTransport := mContext.TransportOf(mProvider, AEntry.Target);
  if mTransport = nil then
  begin
    Loaded(mGeneration, AEntry, False, TAtlasTrackerDetails.Empty,
      TAtlasIssuePreview.MissingTransport(mProvider <> nil, mContext.CanTransport));
    Exit;
  end;
  if not Supports(mTransport, IAtlasCiCancel, FState.Cancel) then
  begin
    FState.Cancel := nil;
  end;
  StartLoad(mGeneration, AEntry, mProvider, mTransport);
end;

procedure TAtlasIdeIssueLoad.Loaded(AGeneration: Integer; const AEntry: TAtlasIssueHistoryEntry;
  ASucceeded: Boolean; const ADetails: TAtlasTrackerDetails; AError: TAtlasCiFetchError);
var
  mContext: TAtlasIdeIssueContext;
  mProvider: IAtlasTrackerProvider;
begin
  FState.Cancel := nil;
  ReleaseThreads(False);
  mContext := FParts.Context;
  if not mContext.Started then
  begin
    Exit;
  end;
  mProvider := mContext.ProviderOf(AEntry.Target);
  if mProvider <> nil then
  begin
    TAtlasGuard.Log(Format('Issue-Vorschau: %s, %s', [mProvider.Name, TAtlasIdeIssueContext.LoadState(ASucceeded, AError)]));
  end;
  case TAtlasIssuePreview.LoadStep(FState.HasPending, AGeneration, mContext.Generation, ASucceeded) of
    TAtlasIssueLoadStep.Pending:
      begin
        // Ein anderer Wunsch wartet: der zählt.
        FState.HasPending := False;
        Load(FState.Pending);
      end;
    TAtlasIssueLoadStep.Show:
      ShowLoaded(mContext.Frame, AEntry, ADetails);
    TAtlasIssueLoadStep.Fail:
      ShowFailed(mContext.Frame, AEntry, AError);
    TAtlasIssueLoadStep.Outdated:
      begin
        // Veraltet: ein neuerer Wunsch läuft.
      end;
  end;
end;

procedure TAtlasIdeIssueLoad.ShowCurrent;
var
  mContext: TAtlasIdeIssueContext;
  mFrame: TAtlasIssueFrame;
  mDetails: TAtlasTrackerDetails;
  mCurrent: TAtlasIssueHistoryEntry;
begin
  mContext := FParts.Context;
  mFrame := mContext.Frame;
  if mFrame = nil then
  begin
    Exit;
  end;
  UpdateHistory;
  FParts.Comments.UpdateWrite;
  if not mContext.HasCurrent then
  begin
    mFrame.ShowEmpty;
    Exit;
  end;
  mCurrent := mContext.Current;
  FParts.Checklists.Prepare(mFrame, mCurrent);
  if mContext.Cache.Get(mCurrent.Target, mCurrent.Key, TAtlasIdeIssueContext.NowUtc, mDetails) then
  begin
    ShowOn(mFrame, mDetails, '');
  end;
end;

procedure TAtlasIdeIssueLoad.CancelLoad;
begin
  FState.HasPending := False;
  if FState.Cancel <> nil then
  begin
    FState.Cancel.Cancel;
  end;
end;

procedure TAtlasIdeIssueLoad.ReleaseThreads(AWait: Boolean);
begin
  FParts.Context.Retire(FState.Thread);
  FState.Thread := nil;
  FParts.Media.Retire;
  FParts.Context.ReleaseThreads(AWait);
end;

procedure TAtlasIdeIssueLoad.Stop;
begin
  FHooks := Default(TAtlasIssueLoadHooks);
end;

end.
