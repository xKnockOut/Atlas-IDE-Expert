unit Atlas.IDE.Updates.Check;

// Update-Prüfung in der IDE (#495):
// - Erster Start ohne Antwort und ohne updates.check: einige Sekunden nach
//   dem Laden fragt ein nicht modales Fenster (TAtlasUpdateConsent). „Ja“
//   schaltet updates.check ein, beide Antworten werden gemerkt; ohne Antwort
//   fragt Atlas beim nächsten Start wieder. Bis dahin keine Abfrage.
// - Mit updates.check höchstens einmal täglich, in einem Hintergrund-Thread
//   (TAtlasHttpVersionSource); das Ergebnis kommt im Hauptthread an.
//   Eine neuere Version meldet eine Zeile in der Meldungsansicht mit
//   Versionsnummer und Link zu den Änderungen. Scheitert die Abfrage, zeigt
//   die Zeile „Version“ das statt „aktuell“, und die Meldungsansicht nennt
//   die Fehlerart einmal, solange sie sich nicht ändert; sonst bleibt es still.
// - Ins Plugin-Protokoll nur Ergebnis und Fehlerart, keine Adresse.
// - Aus: kein Fenster, keine Abfrage, kein Thread.
// - Zeile atlas.version im Atlas-Statusfeld (#591) und damit in der
//   Zustandskachel der Willkommensseite (#754): installierte Version, gelb
//   mit Versionsnummer, solange ein gefundenes Update nicht installiert ist.
//   Klick auf die Zeile bzw. „Jetzt aktualisieren“ (OpenUpdate) bietet das
//   Update zur Installation an (#1519, TAtlasIdeUpdateInstaller): vorbereiten
//   im Hintergrund, einspielen beim Schließen der IDE. Mit updates.install =
//   auto beginnt die Vorbereitung ohne Frage (nicht bei einer neuen
//   Hauptversion). Mit off, über GetIt, ohne AtlasUpdate.exe oder außerhalb
//   eines Release-Ordners öffnet sie wie bisher (#495) die Änderungen samt
//   Download im Browser.
// - Abgefragt wird der Kanal aus updates.channel (#1519).
// Zustand (gefragt, letzte Prüfung, gefundene Version) in
// %LOCALAPPDATA%\Atlas\updates.json.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.ExtCtrls,
  Atlas.Core.Status.Contract,
  Atlas.Core.Status.Registry,
  Atlas.Core.Updates.Contract,
  Atlas.Core.Updates.Check,
  Atlas.Core.Updates.Install,
  Atlas.UI.Updates.Consent,
  Atlas.IDE.Updates.Install;

type
  TAtlasIdeUpdates = class(TComponent)
  public const
    /// <summary>So lange nach dem Laden warten, damit Frage und Abfrage den Start nicht stören.</summary>
    cStartDelayMs = 8000;
  private
    FStateFile: string;
    FState: TAtlasUpdateState;
    FSource: IAtlasVersionSource;
    FTimer: TTimer;
    FThread: TThread;
    FConsent: TAtlasUpdateConsent;
    FOnMessage: TProc<string>;
    FOnLog: TProc<string>;
    // Zeile atlas.version (#754); FLineRef hält sie, die Registry ebenfalls.
    FRegistry: IAtlasStatusRegistry;
    FLine: TAtlasStatusLine;
    FLineRef: IAtlasStatusItem;
    FLineAction: Boolean;
    FInstaller: TAtlasIdeUpdateInstaller;
    procedure StartInstaller;
    procedure PrepareUpdate(const ARelease: TAtlasRelease);
    procedure AutoPrepare;
    procedure OfferUpdate(const ARelease: TAtlasRelease);
    procedure OpenChanges(const ARelease: TAtlasRelease);
    function InstallMode: TAtlasUpdateInstallMode;
    procedure UpdateLine;
    procedure LoadState;
    procedure SaveState;
    procedure Tick(Sender: TObject);
    procedure ShowConsent;
    procedure Answer(AYes: Boolean);
    procedure Finished(const AResult: TAtlasUpdateResult; const AState: TAtlasUpdateState);
    procedure Log(const AText: string);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>AStateFile: Zustandsdatei; ASource: Quelle der Versionsdatei; AMessage: Meldungsansicht;
    /// ALog: Plugin-Protokoll.</summary>
    procedure Start(const AStateFile: string; const ASource: IAtlasVersionSource; const AMessage,
      ALog: TProc<string>);
    /// <summary>Nach geänderten Einstellungen: eingeschaltet gilt als Zustimmung,
    /// dann prüfen, wenn fällig.</summary>
    procedure ApplySettings;
    /// <summary>Prüfen, wenn eingeschaltet und fällig.</summary>
    procedure CheckNow;
    /// <summary>Beim Entladen: Takt und Fenster weg, Zeile im Statusfeld weg, Thread beenden (TAtlasShutdown
    /// bricht die Abfrage ab).</summary>
    procedure Stop;
    /// <summary>Zeile atlas.version in ARegistry melden (#754); nach Start.</summary>
    procedure ShowStatus(const ARegistry: IAtlasStatusRegistry);
    /// <summary>Gefundenes Update, das noch nicht installiert ist.</summary>
    function UpdateReady(out ARelease: TAtlasRelease): Boolean;
    /// <summary>„Jetzt aktualisieren“ (#754): Änderungen und Download des Updates im Browser öffnen (Ablauf aus
    /// #495); ohne Update nichts.</summary>
    procedure OpenUpdate;
    property State: TAtlasUpdateState read FState;
    property Consent: TAtlasUpdateConsent read FConsent;
    property Busy: TThread read FThread;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.ShellAPI,
  System.Types,
  System.IOUtils,
  Vcl.Forms,
  Atlas.Core.Status.Lines,
  Atlas.Core.Product.Version,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Files.DataFile,
  Atlas.UI.Strings,
  Atlas.UI.Updates.Strings,
  Atlas.UI.Updates.Offer,
  Atlas.UI.Updates.Selection,
  Atlas.UI.Updates.Texts,
  Atlas.Text.UpdateRun,
  ToolsAPI,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings;

{ TAtlasIdeUpdates }

constructor TAtlasIdeUpdates.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval := cStartDelayMs;
  FTimer.OnTimer := Tick;
  FInstaller := TAtlasIdeUpdateInstaller.Create(Self);
end;

destructor TAtlasIdeUpdates.Destroy;
begin
  Stop;
  inherited;
end;

procedure TAtlasIdeUpdates.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = FConsent) then
  begin
    FConsent := nil;
  end;
end;

procedure TAtlasIdeUpdates.Log(const AText: string);
begin
  if Assigned(FOnLog) then
  begin
    FOnLog(AText);
  end;
end;

procedure TAtlasIdeUpdates.LoadState;
var
  mText: string;
begin
  // Fehlt, gesperrt oder unbrauchbar: wie beim ersten Start. Kein .defekt (Bericht N3): Die Datei hält nur
  // Zeitpunkt und Ergebnis der letzten Abfrage und ob schon gefragt wurde.
  FState := Default(TAtlasUpdateState);
  if TAtlasDataFile.TryRead(FStateFile, mText) then
    try
      FState := TAtlasUpdateState.FromJson(mText);
    except
      // Unerwarteter Inhalt, den FromJson nicht abfängt: wie beim ersten Start.
      on E: Exception do
      begin
        FState := Default(TAtlasUpdateState);
        Log('Update-Zustand nicht gelesen: ' + E.ClassName);
      end;
    end;
end;

procedure TAtlasIdeUpdates.SaveState;
begin
  try
    // Atomar: Ein Abbruch hinterlässt keine halbe Datei (Bericht N3).
    TAtlasDataFile.Write(FStateFile, FState.ToJson);
  except
    on E: Exception do
      Log('Update-Zustand nicht geschrieben: ' + E.ClassName);
  end;
end;

procedure TAtlasIdeUpdates.Start(const AStateFile: string; const ASource: IAtlasVersionSource; const AMessage,
  ALog: TProc<string>);
begin
  FStateFile := AStateFile;
  FSource := ASource;
  FOnMessage := AMessage;
  FOnLog := ALog;
  LoadState;
  StartInstaller;
  // Erst nach dem Laden der IDE fragen bzw. prüfen.
  FTimer.Enabled := True;
end;

function RegistryKey: string;
var
  mServices: IOTAServices;
begin
  Result := '';
  if Supports(BorlandIDEServices, IOTAServices, mServices) then
  begin
    Result := mServices.GetBaseRegistryKey;
  end;
end;

procedure TAtlasIdeUpdates.StartInstaller;
var
  mEnvironment: TAtlasUpdateEnvironment;
begin
  mEnvironment := Default(TAtlasUpdateEnvironment);
  mEnvironment.PluginDir := TAtlasIdeHost.InstallFolder;
{$IFDEF WIN64}
  mEnvironment.Platform := 'Win64';
{$ELSE}
  mEnvironment.Platform := 'Win32';
{$ENDIF}
  mEnvironment.Ide := TAtlasUpdates.IdeVersion;
  mEnvironment.RegistryKey := RegistryKey;
  mEnvironment.Installed := TAtlasPluginVersion.cVersion;
  mEnvironment.UpdaterExists := FileExists(TAtlasUpdateInstall.UpdaterOf(mEnvironment.PluginDir));
  FInstaller.Start(mEnvironment, TAtlasUpdateInstall.UpdatesRoot(GetEnvironmentVariable('LOCALAPPDATA')), FOnMessage,
    FOnLog,
    procedure
    begin
      UpdateLine;
    end);
  // Ergebnis eines Updates beim letzten Schließen (#1519).
  FInstaller.ReportOutcome;
end;

function TAtlasIdeUpdates.InstallMode: TAtlasUpdateInstallMode;
begin
  Result := TAtlasUpdateInstall.ModeOf(TAtlasIdeSettings.Current.UpdatesInstall);
  if FInstaller.Blocked <> TAtlasUpdateBlock.None then
  begin
    Result := TAtlasUpdateInstallMode.Off;
  end;
end;

procedure TAtlasIdeUpdates.Tick(Sender: TObject);
begin
  FTimer.Enabled := False;
  // Erster Start: einmal fragen; ohne Zustimmung nie eine Abfrage.
  if not TAtlasIdeSettings.Current.UpdatesCheck and not FState.Asked then
  begin
    ShowConsent;
  end
  else
  begin
    CheckNow;
    // Ein früher gefundenes Update, das noch nicht vorbereitet ist (#1519).
    AutoPrepare;
  end;
end;

procedure TAtlasIdeUpdates.ShowConsent;
var
  mArea: TRect;
begin
  if (FConsent <> nil) or TAtlasShutdown.Signalled then
  begin
    Exit;
  end;
  FConsent := TAtlasUpdateConsent.CreateConsent(nil);
  FConsent.FreeNotification(Self);
  FConsent.OnYes :=
    procedure
    begin
      Answer(True);
    end;
  FConsent.OnNo :=
    procedure
    begin
      Answer(False);
    end;
  if Application.MainForm <> nil then
  begin
    mArea := Application.MainForm.BoundsRect;
  end
  else
  begin
    mArea := Screen.WorkAreaRect;
  end;
  FConsent.ShowIn(mArea);
end;

procedure TAtlasIdeUpdates.ApplySettings;
begin
  if FSource = nil then
  begin
    Exit;
  end;
  // updates.check an oder aus: Die Zeile „Version“ zeigt es.
  UpdateLine;
  if TAtlasIdeSettings.Current.UpdatesCheck and not FState.Asked then
  begin
    // In den Optionen eingeschaltet: das ist die Zustimmung, keine Frage mehr.
    FState.Asked := True;
    SaveState;
    if FConsent <> nil then
    begin
      FConsent.Close;
    end;
  end;
  if not FTimer.Enabled then
  begin
    CheckNow;
  end;
end;

procedure TAtlasIdeUpdates.CheckNow;
var
  mSource: IAtlasVersionSource;
  mState: TAtlasUpdateState;
  mQuery: TAtlasUpdateQuery;
begin
  if (FSource = nil) or (FThread <> nil) or TAtlasShutdown.Signalled or
    not TAtlasIdeSettings.Current.UpdatesCheck or not TAtlasUpdates.IsDue(FState.LastCheck, Now) then
  begin
    Exit;
  end;
  mSource := FSource;
  mState := FState;
  mQuery.Url := TAtlasUpdateInstall.ChannelUrl(TAtlasIdeSettings.Current.UpdatesChannel,
    TAtlasPluginVersion.cVersion);
  mQuery.Installed := TAtlasPluginVersion.cVersion;
  mQuery.IdeVersion := TAtlasUpdates.IdeVersion;
  FThread := TThread.CreateAnonymousThread(
    procedure
    var
      Outcome: TAtlasUpdateResult;
      Checked: TAtlasUpdateState;
    begin
      Checked := mState;
      try
        Outcome := TAtlasUpdates.Run(mSource, mQuery, Checked, True, Now);
      except
        on E: Exception do
        begin
          Outcome := Default(TAtlasUpdateResult);
          Outcome.Outcome := TAtlasUpdateOutcome.Failed;
          Outcome.Error := E.ClassName;
          Checked.LastCheck := Now;
        end;
      end;
      if TAtlasShutdown.Signalled then
      begin
        Exit;
      end;
      // An diesen Thread gebunden: Stop entfernt das Ergebnis, wenn es nicht mehr ankommen soll.
      TThread.Queue(TThread.Current,
        procedure
        begin
          Finished(Outcome, Checked);
        end);
    end);
  FThread.FreeOnTerminate := False;
  FThread.Start;
end;

procedure TAtlasIdeUpdates.Answer(AYes: Boolean);
var
  mSettings: TAtlasPluginSettings;
begin
  FState.Asked := True;
  SaveState;
  if AYes then
  begin
    Log('Update-Prüfung beim ersten Start: ja');
  end
  else
  begin
    Log('Update-Prüfung beim ersten Start: nein');
  end;
  if not AYes then
  begin
    Exit;
  end;
  // Über die Einstellungen: Optionsseite und Schnellzugriff zeigen den neuen Wert, ApplySettings prüft.
  mSettings := TAtlasIdeSettings.Stored;
  mSettings.UpdatesCheck := True;
  TAtlasIdeSettings.Update(mSettings);
end;

procedure TAtlasIdeUpdates.Finished(const AResult: TAtlasUpdateResult; const AState: TAtlasUpdateState);
var
  mPreviousError: string;
begin
  if FThread <> nil then
  begin
    FThread.WaitFor;
    FreeAndNil(FThread);
  end;
  FState.LastCheck := AState.LastCheck;
  mPreviousError := FState.LastError;
  // Gefundene Version merken bzw. nach „aktuell“ vergessen (#754), Fehlerart merken bzw. vergessen.
  TAtlasUpdates.Remember(FState, AResult);
  SaveState;
  UpdateLine;
  case AResult.Outcome of
    TAtlasUpdateOutcome.NewVersion:
      begin
        Log('Update-Prüfung: neue Version ' + AResult.Release.Version);
        if Assigned(FOnMessage) then
        begin
          FOnMessage(TAtlasStrings.Fmt(TAtlasTextId.UpdatesAvailable, [AResult.Release.Version,
            TAtlasPluginVersion.cVersion, AResult.Release.ChangesUrl]));
        end;
        AutoPrepare;
      end;
    TAtlasUpdateOutcome.Current:
      Log('Update-Prüfung: aktuell');
    TAtlasUpdateOutcome.Failed:
      begin
        Log('Update-Prüfung fehlgeschlagen: ' + AResult.Error);
        // Einmal je Fehlerart, nicht jeden Tag dieselbe Zeile (z. B. hinter einem Proxy, der GitHub sperrt).
        if (FState.LastError <> mPreviousError) and Assigned(FOnMessage) then
        begin
          FOnMessage(TAtlasUpdatesStrings.Fmt(TAtlasUpdatesTextId.UpdatesCheckFailedMessage, [FState.LastError,
            TAtlasUpdates.cReleasesUrl]));
        end;
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

procedure TAtlasIdeUpdates.Stop;
begin
  // IDE wird geschlossen (#1519): vorbereitetes Update nach dem Ende der IDE einspielen. Beim bloßen Entladen
  // des Packages bleibt es für das nächste Schließen liegen.
  if Application.Terminated and (FSource <> nil) then
  begin
    FInstaller.ApplyOnExit(FState.Available);
  end;
  FInstaller.Stop;
  FTimer.Enabled := False;
  FSource := nil;
  if FLine <> nil then
  begin
    FLine.Detach;
  end;
  if FRegistry <> nil then
  begin
    FRegistry.Remove(TAtlasStatusLines.cVersionId);
  end;
  FLine := nil;
  FLineRef := nil;
  FRegistry := nil;
  if FConsent <> nil then
  begin
    FConsent.RemoveFreeNotification(Self);
    FreeAndNil(FConsent);
  end;
  if FThread <> nil then
  begin
    // Das Abbruchsignal ist schon gesetzt; die Abfrage endet innerhalb von StopMs.
    TAtlasShutdown.WaitForThreads([FThread]);
    TThread.RemoveQueuedEvents(FThread);
    if FThread.Finished then
    begin
      FreeAndNil(FThread);
    end
    else
    begin
      // Hängt der Thread noch, wird er nicht freigegeben, sondern bleibt sich selbst überlassen.
      FThread.FreeOnTerminate := True;
      FThread := nil;
    end;
  end;
end;

procedure TAtlasIdeUpdates.ShowStatus(const ARegistry: IAtlasStatusRegistry);
begin
  FRegistry := ARegistry;
  UpdateLine;
end;

function TAtlasIdeUpdates.UpdateReady(out ARelease: TAtlasRelease): Boolean;
begin
  Result := TAtlasUpdates.Pending(FState, TAtlasPluginVersion.cVersion, ARelease);
end;

procedure TAtlasIdeUpdates.UpdateLine;
var
  mInfo: TAtlasVersionInfo;
  mRelease: TAtlasRelease;
  mReady: Boolean;
  mStage: TUpdateStage;
begin
  if FRegistry = nil then
  begin
    Exit;
  end;
  mReady := UpdateReady(mRelease);
  mInfo := Default(TAtlasVersionInfo);
  mInfo.Installed := TAtlasPluginVersion.cVersion;
  mInfo.Available := mRelease.Version;
  mInfo.CheckEnabled := TAtlasIdeSettings.Current.UpdatesCheck;
  mInfo.Checked := FState.LastCheck > 0;
  mInfo.Failure := FState.LastError;
  if mReady and FInstaller.TryStage(mRelease.Version, mStage) then
  begin
    mInfo.Install := TAtlasUpdateTexts.StageText(mStage);
  end;
  // Anklickbar nur mit Update: Die Zeile wird dafür ersetzt (die Aktion gehört zur Zeile).
  if (FLine = nil) or (FLineAction <> mReady) then
  begin
    if FLine <> nil then
    begin
      FLine.Detach;
    end;
    if mReady then
    begin
      FLine := TAtlasStatusLine.Create(FRegistry, TAtlasStatusLines.cVersionId, TAtlasStatusLines.cVersionOrder,
        procedure
        begin
          OpenUpdate;
        end);
    end
    else
    begin
      FLine := TAtlasStatusLine.Create(FRegistry, TAtlasStatusLines.cVersionId, TAtlasStatusLines.cVersionOrder);
    end;
    FLineRef := FLine;
    FLineAction := mReady;
    FLine.Update(TAtlasStatusLines.VersionText(mInfo), TAtlasStatusLines.VersionState(mInfo),
      TAtlasStatusLines.VersionSummary(mInfo), TAtlasStatusLines.VersionBrief(mInfo),
      TAtlasStatusLines.VersionDetail(mInfo));
    FRegistry.Add(FLineRef);
    Exit;
  end;
  FLine.Update(TAtlasStatusLines.VersionText(mInfo), TAtlasStatusLines.VersionState(mInfo),
    TAtlasStatusLines.VersionSummary(mInfo), TAtlasStatusLines.VersionBrief(mInfo),
    TAtlasStatusLines.VersionDetail(mInfo));
end;

procedure TAtlasIdeUpdates.OpenChanges(const ARelease: TAtlasRelease);
begin
  Log('Update ' + ARelease.Version + ': Änderungen im Browser geöffnet');
  // Nur https-Adressen (TAtlasUpdates.TryParse bzw. Pending); heruntergeladen wird im Browser.
  ShellExecute(0, 'open', PChar(ARelease.ChangesUrl), nil, nil, SW_SHOWNORMAL);
end;

procedure TAtlasIdeUpdates.PrepareUpdate(const ARelease: TAtlasRelease);
begin
  FInstaller.Prepare(ARelease.Version, TAtlasUpdateInstall.ChannelUrl(TAtlasIdeSettings.Current.UpdatesChannel,
    TAtlasPluginVersion.cVersion), TAtlasIdeSettings.Current.UpdatesNewModules);
  UpdateLine;
end;

procedure TAtlasIdeUpdates.AutoPrepare;
var
  mRelease: TAtlasRelease;
  mStage: TUpdateStage;
begin
  // updates.install = auto (#1519): ohne Frage vorbereiten, eine neue Hauptversion nur nach Frage. Ein schon
  // vorbereitetes oder gescheitertes Update bleibt, wie es ist.
  if UpdateReady(mRelease) and not FInstaller.Preparing and not FInstaller.TryStage(mRelease.Version, mStage) and
    TAtlasUpdateInstall.PrepareWithoutAsking(InstallMode, TAtlasPluginVersion.cVersion, mRelease.Version) then
  begin
    PrepareUpdate(mRelease);
  end;
end;

procedure TAtlasIdeUpdates.OfferUpdate(const ARelease: TAtlasRelease);
var
  mStage: TUpdateStage;
  mChosen: TArray<string>;
begin
  // Vorbereitet: Module wählen oder verwerfen (Mockup 6); sonst anbieten (Mockup 2).
  if FInstaller.TryStage(ARelease.Version, mStage) and (mStage.Phase = TUpdatePhase.Ready) then
  begin
    case TAtlasUpdateOffer.Ready(ARelease.Version, Length(mStage.Candidates) > 0) of
      TAtlasUpdateReadyAnswer.Modules:
        if TAtlasUpdateSelectionDialog.Choose(ARelease.Version, mStage.Candidates, mChosen) then
        begin
          FInstaller.Choose(ARelease.Version, mChosen);
        end;
      TAtlasUpdateReadyAnswer.Discard:
        FInstaller.Discard(ARelease.Version);
      TAtlasUpdateReadyAnswer.Close: ;
    end;
    UpdateLine;
    Exit;
  end;
  case TAtlasUpdateOffer.Offer(ARelease.Version, TAtlasPluginVersion.cVersion,
    TAtlasUpdateInstall.IsMajorJump(TAtlasPluginVersion.cVersion, ARelease.Version)) of
    TAtlasUpdateOfferAnswer.Install:
      PrepareUpdate(ARelease);
    TAtlasUpdateOfferAnswer.Changes:
      OpenChanges(ARelease);
    TAtlasUpdateOfferAnswer.Later: ;
  end;
end;

procedure TAtlasIdeUpdates.OpenUpdate;
var
  mRelease: TAtlasRelease;
  mBlock: TAtlasUpdateBlock;
begin
  if not UpdateReady(mRelease) then
  begin
    Exit;
  end;
  mBlock := FInstaller.Blocked;
  if (mBlock <> TAtlasUpdateBlock.None) and (TAtlasUpdateInstall.ModeOf(TAtlasIdeSettings.Current.UpdatesInstall) <>
    TAtlasUpdateInstallMode.Off) and Assigned(FOnMessage) then
  begin
    // Warum Atlas nicht selbst installiert (#1519), dann wie bisher der Browser.
    FOnMessage(TAtlasUpdatesStrings.Fmt(TAtlasUpdatesTextId.UpdatesBlockedMessage, [mRelease.Version,
      TAtlasUpdateTexts.BlockText(mBlock), mRelease.ChangesUrl]));
  end;
  if (InstallMode = TAtlasUpdateInstallMode.Off) or FInstaller.Preparing then
  begin
    OpenChanges(mRelease);
    Exit;
  end;
  OfferUpdate(mRelease);
end;

end.
