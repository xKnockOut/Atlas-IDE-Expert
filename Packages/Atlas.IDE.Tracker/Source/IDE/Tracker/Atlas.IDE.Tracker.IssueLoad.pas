unit Atlas.IDE.Tracker.IssueLoad;

// Gewähltes Issue im Fenster „Atlas-Issue“ laden und zeigen (#1264).
// - Sofort der letzte Stand aus dem Zwischenspeicher, dann die Abfrage im
//   Hintergrund; frisch geladen ersetzt ihn, ohne Netz bleibt er mit Grund
//   stehen.
// - Den Ablauf (eine Abfrage zur Zeit, vormerken, abbrechen, Antwort nach
//   Generation einordnen) entscheidet TAtlasIssueLoadFlow
//   (Atlas.Core.Tracker.PreviewLoad); diese Unit ist sein Lader: zeigt, startet
//   die Abfrage im Thread, bricht über IAtlasCiCancel ab. Rückkehr über
//   TAtlasMainThread.
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
  Atlas.Core.Tracker.PreviewLoad,
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

  TAtlasIdeIssueLoad = class
  private
    FParts: TAtlasIdeIssueParts;
    FHistory: TAtlasIssueHistory;
    FHooks: TAtlasIssueLoadHooks;
    FFlow: TAtlasIssueLoadFlow;
    /// <summary>Thread der laufenden Abfrage und ihr Abbruch-Griff (nil ohne).</summary>
    FThread: TThread;
    FCancel: IAtlasCiCancel;
    /// <summary>Lader des Ablaufs: Zeigen und Abfrage (TAtlasIssueLoaderStart).</summary>
    function StartFor(const AEntry: TAtlasIssueHistoryEntry; out AGeneration: Integer;
      out AError: TAtlasCiFetchError): Boolean;
    /// <summary>Lader des Ablaufs: eingeordnete Antwort loggen und zeigen.</summary>
    procedure Arrived(const AAnswer: TAtlasIssueLoadAnswer; AStep: TAtlasIssueLoadStep);
    /// <summary>Lader des Ablaufs: die laufende Abfrage abbrechen.</summary>
    procedure CancelRunning;
    /// <summary>Lader des Ablaufs: die laufende Abfrage ist zu Ende; Griff und Thread abgeben.</summary>
    procedure RunEnded;
    /// <summary>Lader des Ablaufs: Generation des jüngsten Wunsches.</summary>
    function CurrentGeneration: Integer;
    /// <summary>Abfrage im Hintergrund; das Ergebnis über den Ablauf (Finished) im Hauptthread.</summary>
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
    destructor Destroy; override;
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
    /// <summary>Hooks lösen und den Ablauf zurücksetzen (beim Abmelden, nach ReleaseThreads(True)).</summary>
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

/// <summary>Lader für den Ablauf; eigene Routine, damit die anonymen Methoden nur AOwner fangen.</summary>
function LoaderOf(AOwner: TAtlasIdeIssueLoad): TAtlasIssueLoader;
begin
  Result := Default(TAtlasIssueLoader);
  Result.Start :=
    function(const AEntry: TAtlasIssueHistoryEntry; out AGeneration: Integer; out AError: TAtlasCiFetchError): Boolean
    begin
      Result := AOwner.StartFor(AEntry, AGeneration, AError);
    end;
  Result.Cancel :=
    procedure
    begin
      AOwner.CancelRunning;
    end;
  Result.Ended :=
    procedure
    begin
      AOwner.RunEnded;
    end;
  Result.Generation :=
    function: Integer
    begin
      Result := AOwner.CurrentGeneration;
    end;
  Result.Arrived :=
    procedure(const AAnswer: TAtlasIssueLoadAnswer; AStep: TAtlasIssueLoadStep)
    begin
      AOwner.Arrived(AAnswer, AStep);
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
  FFlow := TAtlasIssueLoadFlow.Create(LoaderOf(Self));
end;

destructor TAtlasIdeIssueLoad.Destroy;
begin
  FFlow.Free;
  inherited;
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
  // Zusammenfassen (#2462): Knopf nach Kommentaren, Karte aus dem Zwischenspeicher.
  FParts.Summary.Shown(AFrame, ADetails);
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
  FThread := TThread.CreateAnonymousThread(
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
            mOwner.FFlow.Finished(TAtlasIssueLoadAnswer.Create(AGeneration, mEntry, mOk, mResult, mError));
          end;
        end);
    end);
  FThread.FreeOnTerminate := False;
  FThread.Start;
end;

procedure TAtlasIdeIssueLoad.Load(const AEntry: TAtlasIssueHistoryEntry);
begin
  if FParts.Context.Started then
  begin
    FFlow.Request(AEntry);
  end;
end;

function TAtlasIdeIssueLoad.StartFor(const AEntry: TAtlasIssueHistoryEntry; out AGeneration: Integer;
  out AError: TAtlasCiFetchError): Boolean;
var
  mContext: TAtlasIdeIssueContext;
  mProvider: IAtlasTrackerProvider;
  mTransport: IAtlasCiTransport;
begin
  mContext := FParts.Context;
  AGeneration := mContext.Generation;
  AError := TAtlasCiFetchError.Cancelled;
  Result := False;
  if not mContext.Started then
  begin
    // Ein vorgemerkter Wunsch nach dem Abmelden: nichts mehr laden.
    Exit;
  end;
  // Die vorige Abfrage ist zu Ende (eine zur Zeit): ihren Thread abgeben.
  ReleaseThreads(False);
  FParts.Media.Cancel;
  AGeneration := mContext.Select(AEntry);
  FParts.Comments.UpdateWrite;
  FParts.Development.Select(AEntry.Target, AEntry.Key);
  UpdateHistory;
  ShowCached(AEntry);
  mProvider := mContext.ProviderOf(AEntry.Target);
  // Der Transport entsteht hier, damit „Abbrechen“ ihn erreicht; er liest das Token ohne Dialog.
  mTransport := mContext.TransportOf(mProvider, AEntry.Target);
  if mTransport = nil then
  begin
    AError := TAtlasIssuePreview.MissingTransport(mProvider <> nil, mContext.CanTransport);
    Exit;
  end;
  if not Supports(mTransport, IAtlasCiCancel, FCancel) then
  begin
    FCancel := nil;
  end;
  StartLoad(AGeneration, AEntry, mProvider, mTransport);
  Result := True;
end;

procedure TAtlasIdeIssueLoad.Arrived(const AAnswer: TAtlasIssueLoadAnswer; AStep: TAtlasIssueLoadStep);
var
  mContext: TAtlasIdeIssueContext;
  mProvider: IAtlasTrackerProvider;
begin
  mContext := FParts.Context;
  if not mContext.Started then
  begin
    Exit;
  end;
  mProvider := mContext.ProviderOf(AAnswer.Entry.Target);
  if mProvider <> nil then
  begin
    TAtlasGuard.Log(Format('Issue-Vorschau: %s, %s', [mProvider.Name,
      TAtlasIdeIssueContext.LoadState(AAnswer.Succeeded, AAnswer.Error)]));
  end;
  case AStep of
    TAtlasIssueLoadStep.Show:
      ShowLoaded(mContext.Frame, AAnswer.Entry, AAnswer.Details);
    TAtlasIssueLoadStep.Fail:
      ShowFailed(mContext.Frame, AAnswer.Entry, AAnswer.Error);
    TAtlasIssueLoadStep.Pending:
      begin
        // Ein anderer Wunsch wartet und folgt gleich: nichts zeigen.
      end;
    TAtlasIssueLoadStep.Outdated:
      begin
        // Veraltet: ein neuerer Wunsch läuft.
      end;
  end;
end;

procedure TAtlasIdeIssueLoad.CancelRunning;
begin
  TAtlasCiCancels.Cancel(FCancel);
end;

procedure TAtlasIdeIssueLoad.RunEnded;
begin
  FCancel := nil;
  ReleaseThreads(False);
end;

function TAtlasIdeIssueLoad.CurrentGeneration: Integer;
begin
  Result := FParts.Context.Generation;
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
  FFlow.Cancel;
end;

procedure TAtlasIdeIssueLoad.ReleaseThreads(AWait: Boolean);
begin
  FParts.Context.Retire(FThread);
  FThread := nil;
  FParts.Media.Retire;
  FParts.Context.ReleaseThreads(AWait);
end;

procedure TAtlasIdeIssueLoad.Stop;
begin
  FHooks := Default(TAtlasIssueLoadHooks);
  FCancel := nil;
  FFlow.Reset;
end;

end.
