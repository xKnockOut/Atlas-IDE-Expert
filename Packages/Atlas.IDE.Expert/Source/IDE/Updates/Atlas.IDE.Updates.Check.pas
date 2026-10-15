unit Atlas.IDE.Updates.Check;

// Update-Prüfung in der IDE (#495):
// - Erster Start ohne Antwort und ohne updates.check: einige Sekunden nach
//   dem Laden fragt ein nicht modales Fenster (TAtlasUpdateConsent). „Ja“
//   schaltet updates.check ein, beide Antworten werden gemerkt; ohne Antwort
//   fragt Atlas beim nächsten Start wieder. Bis dahin keine Abfrage.
// - Mit updates.check höchstens einmal täglich, in einem Hintergrund-Thread
//   (TAtlasHttpVersionSource); das Ergebnis kommt im Hauptthread an.
//   Eine neuere Version meldet eine Zeile in der Meldungsansicht mit
//   Versionsnummer und Link zu den Änderungen; sonst bleibt es still.
// - Ins Plugin-Protokoll nur Ergebnis und Fehlerart, keine Adresse.
// - Aus: kein Fenster, keine Abfrage, kein Thread.
// - Zeile atlas.version im Atlas-Statusfeld (#591) und damit in der
//   Zustandskachel der Willkommensseite (#754): installierte Version, gelb
//   mit Versionsnummer, solange ein gefundenes Update nicht installiert ist.
//   Klick auf die Zeile bzw. „Jetzt aktualisieren“ (OpenUpdate) öffnet wie
//   der Hinweis aus #495 die Änderungen samt Download im Browser; Atlas lädt
//   und installiert nichts selbst.
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
  Atlas.UI.Updates.Consent;

type
  TAtlasIdeUpdates = class(TComponent)
  public const
    /// <summary>So lange nach dem Laden warten, damit Frage und Abfrage den Start nicht stören.</summary>
    StartDelayMs = 8000;
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
  Atlas.UI.Strings,
  Atlas.IDE.Settings.Store;

{ TAtlasIdeUpdates }

constructor TAtlasIdeUpdates.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval := StartDelayMs;
  FTimer.OnTimer := Tick;
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
    FConsent := nil;
end;

procedure TAtlasIdeUpdates.Log(const AText: string);
begin
  if Assigned(FOnLog) then
    FOnLog(AText);
end;

procedure TAtlasIdeUpdates.LoadState;
begin
  FState := Default(TAtlasUpdateState);
  try
    if TFile.Exists(FStateFile) then
      FState := TAtlasUpdateState.FromJson(TFile.ReadAllText(FStateFile, TEncoding.UTF8));
  except
    on E: Exception do
      Log('Update-Zustand nicht gelesen: ' + E.ClassName);
  end;
end;

procedure TAtlasIdeUpdates.SaveState;
begin
  try
    ForceDirectories(ExtractFileDir(FStateFile));
    TFile.WriteAllText(FStateFile, FState.ToJson, TEncoding.UTF8);
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
  // Erst nach dem Laden der IDE fragen bzw. prüfen.
  FTimer.Enabled := True;
end;

procedure TAtlasIdeUpdates.Tick(Sender: TObject);
begin
  FTimer.Enabled := False;
  // Erster Start: einmal fragen; ohne Zustimmung nie eine Abfrage.
  if not TAtlasIdeSettings.Current.UpdatesCheck and not FState.Asked then
    ShowConsent
  else
    CheckNow;
end;

procedure TAtlasIdeUpdates.ShowConsent;
var
  Area: TRect;
begin
  if (FConsent <> nil) or TAtlasShutdown.Signalled then
    Exit;
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
    Area := Application.MainForm.BoundsRect
  else
    Area := Screen.WorkAreaRect;
  FConsent.ShowIn(Area);
end;

procedure TAtlasIdeUpdates.ApplySettings;
begin
  if FSource = nil then
    Exit;
  // updates.check an oder aus: Die Zeile „Version“ zeigt es.
  UpdateLine;
  if TAtlasIdeSettings.Current.UpdatesCheck and not FState.Asked then
  begin
    // In den Optionen eingeschaltet: das ist die Zustimmung, keine Frage mehr.
    FState.Asked := True;
    SaveState;
    if FConsent <> nil then
      FConsent.Close;
  end;
  if not FTimer.Enabled then
    CheckNow;
end;

procedure TAtlasIdeUpdates.CheckNow;
var
  Source: IAtlasVersionSource;
  State: TAtlasUpdateState;
begin
  if (FSource = nil) or (FThread <> nil) or TAtlasShutdown.Signalled or
    not TAtlasIdeSettings.Current.UpdatesCheck or not TAtlasUpdates.IsDue(FState.LastCheck, Now) then
    Exit;
  Source := FSource;
  State := FState;
  FThread := TThread.CreateAnonymousThread(
    procedure
    var
      Outcome: TAtlasUpdateResult;
      Checked: TAtlasUpdateState;
    begin
      Checked := State;
      try
        Outcome := TAtlasUpdates.Run(Source, Checked, True, TAtlasPluginVersion.Version,
          TAtlasUpdates.IdeVersion, Now);
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
        Exit;
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
  Settings: TAtlasPluginSettings;
begin
  FState.Asked := True;
  SaveState;
  if AYes then
    Log('Update-Prüfung beim ersten Start: ja')
  else
    Log('Update-Prüfung beim ersten Start: nein');
  if not AYes then
    Exit;
  // Über die Einstellungen: Optionsseite und Schnellzugriff zeigen den neuen Wert, ApplySettings prüft.
  Settings := TAtlasIdeSettings.Stored;
  Settings.UpdatesCheck := True;
  TAtlasIdeSettings.Update(Settings);
end;

procedure TAtlasIdeUpdates.Finished(const AResult: TAtlasUpdateResult; const AState: TAtlasUpdateState);
begin
  if FThread <> nil then
  begin
    FThread.WaitFor;
    FreeAndNil(FThread);
  end;
  FState.LastCheck := AState.LastCheck;
  // Gefundene Version merken bzw. nach „aktuell“ vergessen (#754).
  TAtlasUpdates.Remember(FState, AResult);
  SaveState;
  UpdateLine;
  case AResult.Outcome of
    TAtlasUpdateOutcome.NewVersion:
      begin
        Log('Update-Prüfung: neue Version ' + AResult.Release.Version);
        if Assigned(FOnMessage) then
          FOnMessage(TAtlasStrings.Fmt(TAtlasTextId.UpdatesAvailable, [AResult.Release.Version,
            TAtlasPluginVersion.Version, AResult.Release.ChangesUrl]));
      end;
    TAtlasUpdateOutcome.Current:
      Log('Update-Prüfung: aktuell');
    TAtlasUpdateOutcome.Failed:
      Log('Update-Prüfung fehlgeschlagen: ' + AResult.Error);
  end;
end;

procedure TAtlasIdeUpdates.Stop;
begin
  FTimer.Enabled := False;
  FSource := nil;
  if FLine <> nil then
    FLine.Detach;
  if FRegistry <> nil then
    FRegistry.Remove(TAtlasStatusLines.VersionId);
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
      FreeAndNil(FThread)
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
  Result := TAtlasUpdates.Pending(FState, TAtlasPluginVersion.Version, ARelease);
end;

procedure TAtlasIdeUpdates.UpdateLine;
var
  Info: TAtlasVersionInfo;
  Release: TAtlasRelease;
  Ready: Boolean;
begin
  if FRegistry = nil then
    Exit;
  Ready := UpdateReady(Release);
  Info := Default(TAtlasVersionInfo);
  Info.Installed := TAtlasPluginVersion.Version;
  Info.Available := Release.Version;
  Info.CheckEnabled := TAtlasIdeSettings.Current.UpdatesCheck;
  Info.Checked := FState.LastCheck > 0;
  // Anklickbar nur mit Update: Die Zeile wird dafür ersetzt (die Aktion gehört zur Zeile).
  if (FLine = nil) or (FLineAction <> Ready) then
  begin
    if FLine <> nil then
      FLine.Detach;
    if Ready then
      FLine := TAtlasStatusLine.Create(FRegistry, TAtlasStatusLines.VersionId, TAtlasStatusLines.VersionOrder,
        procedure
        begin
          OpenUpdate;
        end)
    else
      FLine := TAtlasStatusLine.Create(FRegistry, TAtlasStatusLines.VersionId, TAtlasStatusLines.VersionOrder);
    FLineRef := FLine;
    FLineAction := Ready;
    FLine.Update(TAtlasStatusLines.VersionText(Info), TAtlasStatusLines.VersionState(Info),
      TAtlasStatusLines.VersionSummary(Info), TAtlasStatusLines.VersionBrief(Info),
      TAtlasStatusLines.VersionDetail(Info));
    FRegistry.Add(FLineRef);
    Exit;
  end;
  FLine.Update(TAtlasStatusLines.VersionText(Info), TAtlasStatusLines.VersionState(Info),
    TAtlasStatusLines.VersionSummary(Info), TAtlasStatusLines.VersionBrief(Info),
    TAtlasStatusLines.VersionDetail(Info));
end;

procedure TAtlasIdeUpdates.OpenUpdate;
var
  Release: TAtlasRelease;
begin
  if not UpdateReady(Release) then
    Exit;
  Log('Update ' + Release.Version + ': Änderungen im Browser geöffnet');
  // Nur https-Adressen (TAtlasUpdates.TryParse bzw. Pending); heruntergeladen wird im Browser, nicht von Atlas.
  ShellExecute(0, 'open', PChar(Release.ChangesUrl), nil, nil, SW_SHOWNORMAL);
end;

end.
