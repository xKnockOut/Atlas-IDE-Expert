unit Atlas.IDE.Tracker.FlowMap;

// Steuerung des Fensters „Atlas-Ablauf“ (#2125):
// - Show öffnet das Fenster und lädt die Ablauf-Karte des Trackers des
//   aktiven Projekts (wie das Board, #1272). Nur YouTrack mit Projektkürzel;
//   der Anbieter muss IAtlasTrackerFlow anbieten, sonst ein Hinweis.
// - Sofort erscheint der letzte Stand aus dem Zwischenspeicher
//   (%LOCALAPPDATA%\Atlas\issues\<Tracker>-flow.json); im Hintergrund holt
//   der Anbieter nur die Wechsel ab dem letzten Abruf
//   (TAtlasTrackerFlow.SinceOf), mit TAtlasTrackerFlow.cTimeoutMs als
//   Zeitgrenze; ohne Antwort bleibt der Stand mit „Stand vom … · Grund“.
// - Kein eigenes Intervall: geladen wird beim Öffnen und mit „Aktualisieren“.
// - Zeitraum issues.flowMap.days, Grenze „liegt lange“
//   issues.flowMap.stuckDays, Zustandsfeld aus den Einstellungen bzw. der
//   Verbindung (Hook StateField). Mit issues.flowMap aus schließt das
//   Fenster und der Befehl fehlt.
// - Doppelklick auf eine Zeile von „Liegt lange“ zeigt die Vorschau (#1264).

interface

uses
  System.SysUtils,
  System.Classes,
  Atlas.Core.Ci.Contract,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.FlowMap,
  Atlas.Core.VersionControl.Worker,
  Atlas.UI.Tracker.FlowFrame;

type
  TAtlasFlowMapProviderHook = reference to function(const AName: string): IAtlasTrackerProvider;
  /// <summary>Transport mit dem Token aus dem Anmeldespeicher; nil ohne Token.</summary>
  TAtlasFlowMapTransportHook = reference to function(const AProvider: IAtlasTrackerProvider;
    const ATarget: TAtlasTrackerTarget): IAtlasCiTransport;

  TAtlasFlowMapHooks = record
    Provider: TAtlasFlowMapProviderHook;
    Transport: TAtlasFlowMapTransportHook;
    /// <summary>Tracker des aktiven Projekts; Server '' ohne.</summary>
    Target: TFunc<TAtlasTrackerTarget>;
    /// <summary>Name des Zustandsfeldes für ATarget ('' = erkennen).</summary>
    StateField: TFunc<TAtlasTrackerTarget, string>;
    /// <summary>Issue in „Atlas-Issue“ zeigen (#1264).</summary>
    Preview: TProc<TAtlasTrackerTarget, string>;
  end;

  TAtlasIdeFlowMap = class(TInterfacedObject)
  private
    FHooks: TAtlasFlowMapHooks;
    FCacheFolder: string;
    FStarted: Boolean;
    FWorker: TAtlasVcsWorker;
    FCancel: IAtlasCiCancel;
    FGeneration: Integer;
    FTarget: TAtlasTrackerTarget;
    function Frame: TAtlasFlowFrame;
    procedure Wire(AFrame: TAtlasFlowFrame);
    procedure Load;
    procedure Loaded(AGeneration: Integer; ASucceeded: Boolean; const AData: TAtlasFlowData;
      AError: TAtlasCiFetchError; ASince: TDateTime);
    procedure Present(AFrame: TAtlasFlowFrame; const AData: TAtlasFlowData; const AStatus: string);
    procedure CancelLoad;
    class function NowUtc: TDateTime; static;
  public
    /// <summary>ACacheFolder: Ordner des Zwischenspeichers ('' = keiner).</summary>
    constructor Create(const AHooks: TAtlasFlowMapHooks; const ACacheFolder: string);
    destructor Destroy; override;
    /// <summary>Fenster bei der IDE anmelden (Desktop, #879).</summary>
    procedure Start;
    /// <summary>Abbrechen, kurz warten, Fenster abmelden; danach wirkungslos.</summary>
    procedure Stop;
    /// <summary>Fenster zeigen und neu laden (Befehl Atlas.FlowMap, Menü Ansicht › Atlas › Ablauf).</summary>
    procedure Show;
    /// <summary>Nach geänderten Einstellungen: mit issues.flowMap aus das Fenster schließen.</summary>
    procedure UpdateSettings;
    /// <summary>issues.flowMap an?</summary>
    class function Active: Boolean; static;
    /// <summary>Text zu einem Fehler beim Laden.</summary>
    class function ErrorText(AError: TAtlasCiFetchError): string; static;
  end;

implementation

uses
  System.DateUtils,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Tracker.Issue.Strings,
  Atlas.UI.Tracker.Flow.Strings,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Tracker.FlowWindow;

const
  // So lange wartet das Beenden auf einen laufenden Abruf.
  cStopMs = 1000;

{ TAtlasIdeFlowMap }

constructor TAtlasIdeFlowMap.Create(const AHooks: TAtlasFlowMapHooks; const ACacheFolder: string);
begin
  inherited Create;
  FHooks := AHooks;
  FCacheFolder := ACacheFolder;
  FWorker := TAtlasVcsWorker.Create;
end;

destructor TAtlasIdeFlowMap.Destroy;
begin
  FWorker.Free;
  inherited;
end;

class function TAtlasIdeFlowMap.Active: Boolean;
begin
  Result := TAtlasIdeSettings.Current.IssuesFlowMap;
end;

class function TAtlasIdeFlowMap.NowUtc: TDateTime;
begin
  Result := TTimeZone.Local.ToUniversalTime(Now);
end;

procedure TAtlasIdeFlowMap.Start;
var
  mKeep: IInterface;
  mOwner: TAtlasIdeFlowMap;
begin
  if FStarted then
  begin
    Exit;
  end;
  FStarted := True;
  mKeep := Self;
  mOwner := Self;
  TAtlasIdeFlowWindow.OnFrame :=
    procedure(AFrame: TAtlasFlowFrame)
    begin
      if (mKeep <> nil) and mOwner.FStarted then
      begin
        mOwner.Wire(AFrame);
      end;
    end;
  // Früh anmelden: Die IDE speichert das Fenster im Desktop und legt es beim Laden selbst an (#879).
  TAtlasIdeFlowWindow.Prepare;
end;

procedure TAtlasIdeFlowMap.Stop;
begin
  if not FStarted then
  begin
    Exit;
  end;
  FStarted := False;
  Inc(FGeneration);
  CancelLoad;
  FWorker.Stop(cStopMs);
  TAtlasIdeFlowWindow.Release;
  FHooks := Default(TAtlasFlowMapHooks);
end;

function TAtlasIdeFlowMap.Frame: TAtlasFlowFrame;
begin
  Result := TAtlasIdeFlowWindow.ExistingFrame;
end;

/// <summary>Ereignisse des Frames an AOwner; AKeep hält AOwner, solange der Frame lebt.</summary>
function FlowEvents(AOwner: TAtlasIdeFlowMap; const AKeep: IInterface): TAtlasFlowFrameEvents;
var
  mKeep: IInterface;
  mOwner: TAtlasIdeFlowMap;
begin
  mKeep := AKeep;
  mOwner := AOwner;
  Result := Default(TAtlasFlowFrameEvents);
  Result.Refresh :=
    procedure
    begin
      if mKeep <> nil then
      begin
        mOwner.Load;
      end;
    end;
  Result.Open :=
    procedure(AKey: string)
    begin
      if (mKeep <> nil) and Assigned(mOwner.FHooks.Preview) then
      begin
        mOwner.FHooks.Preview(mOwner.FTarget, AKey);
      end;
    end;
  Result.Hidden :=
    procedure
    begin
      // Fenster geschlossen: Laden abbrechen.
      if mKeep <> nil then
      begin
        mOwner.CancelLoad;
      end;
    end;
end;

procedure TAtlasIdeFlowMap.Wire(AFrame: TAtlasFlowFrame);
begin
  AFrame.ApplyColors(TAtlasIdeStyle.Colors);
  AFrame.Events := FlowEvents(Self, Self);
end;

procedure TAtlasIdeFlowMap.Show;
begin
  if not FStarted or not Active then
  begin
    Exit;
  end;
  TAtlasGuard.Run(TAtlasFeature.Tracker,
    procedure
    var
      mFrame: TAtlasFlowFrame;
    begin
      mFrame := TAtlasIdeFlowWindow.Show;
      if mFrame <> nil then
      begin
        TAtlasIdeFlowWindow.ApplyTheme;
      end;
      Load;
    end);
end;

procedure TAtlasIdeFlowMap.UpdateSettings;
begin
  if FStarted and not Active then
  begin
    CancelLoad;
    TAtlasIdeFlowWindow.Hide;
  end;
end;

procedure TAtlasIdeFlowMap.CancelLoad;
begin
  if FCancel <> nil then
  begin
    FCancel.Cancel;
  end;
end;

class function TAtlasIdeFlowMap.ErrorText(AError: TAtlasCiFetchError): string;
begin
  case AError of
    TAtlasCiFetchError.Unauthorized:
      Result := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewErrorToken);
    TAtlasCiFetchError.Timeout:
      Result := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewErrorTimeout);
    TAtlasCiFetchError.NotConfigured, TAtlasCiFetchError.UnknownProvider, TAtlasCiFetchError.NotFound:
      Result := TAtlasFlowStrings.Text(TAtlasFlowTextId.FlowNoTracker);
    TAtlasCiFetchError.Invalid, TAtlasCiFetchError.Server:
      Result := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewErrorInvalid);
  else
    Result := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewErrorNetwork);
  end;
end;

type
  /// <summary>Laden im Hintergrund: was der Worker braucht.</summary>
  TLoadJob = record
    Generation: Integer;
    Flow: IAtlasTrackerFlow;
    Request: TAtlasFlowRequest;
  end;

/// <summary>Projekt, Settings und letzter Stand; ohne YouTrack-Projekt der Hinweis und False.</summary>
function PrepareLoad(AOwner: TAtlasIdeFlowMap; AFrame: TAtlasFlowFrame; out AJob: TLoadJob): Boolean;
var
  mProvider: IAtlasTrackerProvider;
  mCached: TAtlasFlowData;
  mHasCache: Boolean;
  mField: string;
  mDays: Integer;
begin
  AJob := Default(TLoadJob);
  AJob.Generation := AOwner.FGeneration;
  mProvider := nil;
  if Assigned(AOwner.FHooks.Provider) then
  begin
    mProvider := AOwner.FHooks.Provider(AOwner.FTarget.Provider);
  end;
  Result := (AOwner.FTarget.Server <> '') and (Trim(AOwner.FTarget.Project) <> '') and
    Supports(mProvider, IAtlasTrackerFlow, AJob.Flow);
  if not Result then
  begin
    AFrame.ShowNotice(TAtlasFlowStrings.Text(TAtlasFlowTextId.FlowNoTracker));
    AFrame.SetStatus('');
    Exit;
  end;
  mField := '';
  if Assigned(AOwner.FHooks.StateField) then
  begin
    mField := AOwner.FHooks.StateField(AOwner.FTarget);
  end;
  mDays := TAtlasIdeSettings.Current.IssuesFlowMapDays;
  mHasCache := TAtlasTrackerFlow.Load(AOwner.FCacheFolder, AOwner.FTarget, mCached);
  // Sofort der letzte Stand; frisch geladen ersetzt ihn.
  if mHasCache and not AFrame.HasMap then
  begin
    AOwner.Present(AFrame, mCached, '');
  end;
  AFrame.SetLoading(True);
  AJob.Request := TAtlasFlowRequest.Create(AOwner.FTarget, nil, mField, TAtlasTrackerFlow.SinceOf(mCached, mHasCache,
    TAtlasIdeFlowMap.NowUtc, mDays, mField), TAtlasTrackerFlow.cTimeoutMs);
  if Assigned(AOwner.FHooks.Transport) then
  begin
    AJob.Request.Transport := AOwner.FHooks.Transport(mProvider, AOwner.FTarget);
  end;
  Result := AJob.Request.Transport <> nil;
  if not Result then
  begin
    // Ohne Token kein Transport.
    AOwner.Loaded(AJob.Generation, False, TAtlasFlowData.Empty, TAtlasCiFetchError.Unauthorized, 0);
  end;
end;

/// <summary>Im Hintergrund laden; das Ergebnis geht im Hauptthread an AOwner.Loaded.</summary>
procedure RunLoad(AOwner: TAtlasIdeFlowMap; const AJob: TLoadJob);
var
  mJob: TLoadJob;
  mKeep: IInterface;
  mOwner: TAtlasIdeFlowMap;
  mOk: Boolean;
  mData: TAtlasFlowData;
  mError: TAtlasCiFetchError;
begin
  mJob := AJob;
  if not Supports(mJob.Request.Transport, IAtlasCiCancel, AOwner.FCancel) then
  begin
    AOwner.FCancel := nil;
  end;
  mKeep := AOwner;
  mOwner := AOwner;
  mData := TAtlasFlowData.Empty;
  mOk := False;
  mError := TAtlasCiFetchError.Network;
  if not AOwner.FWorker.Run(
    procedure
    begin
      try
        mOk := mJob.Flow.LoadFlow(mJob.Request, mData, mError);
      except
        // Kein Dialog, kein Fehler an die IDE: als Netzfehler werten.
        on E: Exception do
        begin
          mOk := False;
          mError := TAtlasCiFetchError.Network;
          TAtlasGuard.Log('Atlas flow map: query aborted with ' + E.ClassName);
        end;
      end;
      mJob.Request.Transport := nil;
      mJob.Flow := nil;
    end,
    procedure
    begin
      if mKeep <> nil then
      begin
        mOwner.Loaded(mJob.Generation, mOk, mData, mError, mJob.Request.Since);
      end;
    end) then
  begin
    AOwner.Loaded(mJob.Generation, False, TAtlasFlowData.Empty, TAtlasCiFetchError.Cancelled, 0);
  end;
end;

procedure TAtlasIdeFlowMap.Load;
var
  mFrame: TAtlasFlowFrame;
  mJob: TLoadJob;
  mTarget: TAtlasTrackerTarget;
begin
  mFrame := Frame;
  if not FStarted or (mFrame = nil) then
  begin
    Exit;
  end;
  CancelLoad;
  Inc(FGeneration);
  mTarget := Default(TAtlasTrackerTarget);
  if Assigned(FHooks.Target) then
  begin
    mTarget := FHooks.Target();
  end;
  // Anderer Tracker (Projektwechsel): der gezeigte Stand gilt nicht mehr.
  if not SameText(mTarget.Key, FTarget.Key) then
  begin
    mFrame.ShowNotice('');
  end;
  FTarget := mTarget;
  if PrepareLoad(Self, mFrame, mJob) then
  begin
    RunLoad(Self, mJob);
  end;
end;

procedure TAtlasIdeFlowMap.Present(AFrame: TAtlasFlowFrame; const AData: TAtlasFlowData; const AStatus: string);
begin
  AFrame.SetMap(TAtlasFlowMap.Build(AData, NowUtc, TAtlasIdeSettings.Current.IssuesFlowMapStuckDays), FTarget.Project,
    TAtlasIdeSettings.Current.IssuesFlowMapStuckDays, AStatus);
end;

procedure TAtlasIdeFlowMap.Loaded(AGeneration: Integer; ASucceeded: Boolean; const AData: TAtlasFlowData;
  AError: TAtlasCiFetchError; ASince: TDateTime);
var
  mFrame: TAtlasFlowFrame;
  mData, mCached: TAtlasFlowData;
  mHasCache: Boolean;
  mNow: TDateTime;
  mWhen: string;
begin
  if AGeneration <> FGeneration then
  begin
    Exit;
  end;
  FCancel := nil;
  mFrame := Frame;
  if not FStarted or (mFrame = nil) then
  begin
    Exit;
  end;
  mFrame.SetLoading(False);
  TAtlasGuard.Log('Atlas flow map: ' + FTarget.Provider + ', ' + TAtlasCiBuild.ErrorKey(AError));
  mHasCache := TAtlasTrackerFlow.Load(FCacheFolder, FTarget, mCached);
  if ASucceeded then
  begin
    mNow := NowUtc;
    mData := AData;
    mData.Fetched := mNow;
    mData.Days := TAtlasIdeSettings.Current.IssuesFlowMapDays;
    // Nachgeladen ab dem letzten Stand: mit ihm zusammenführen; sonst ersetzt der neue Stand ihn.
    mData := TAtlasTrackerFlow.Merge(mCached, mData, mHasCache and (ASince > TAtlasTrackerFlow.WindowStart(mNow,
      mData.Days)), mNow);
    TAtlasTrackerFlow.Save(FCacheFolder, FTarget, mData);
    Present(mFrame, mData, '');
    Exit;
  end;
  // Ohne Antwort: der letzte Stand mit Grund.
  if mHasCache then
  begin
    mWhen := FormatDateTime('dd.mm.yyyy hh:nn', TTimeZone.Local.ToLocalTime(mCached.Fetched), FormatSettings);
    Present(mFrame, mCached, TAtlasFlowStrings.Fmt(TAtlasFlowTextId.FlowOffline, [mWhen, ErrorText(AError)]));
  end
  else if AError <> TAtlasCiFetchError.Cancelled then
  begin
    mFrame.ShowNotice(ErrorText(AError));
    mFrame.SetStatus('');
  end;
end;

end.
