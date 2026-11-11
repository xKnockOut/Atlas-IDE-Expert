unit Atlas.IDE.CodeInsight.Composition;

// Kompositionswurzel von Atlas.IDE.Base (ADR 0006, 0017): Anmelden beim Laden des Packages und Abbau in seiner
// Finalisierung. Die Teile liegen in Atlas.IDE.CodeInsight.Composition.<Teil>; diese Unit legt nur die Reihenfolge
// fest, in der sie starten und rückwärts abgebaut werden.

interface

/// <summary>Atlas in der IDE anmelden: Host, Sicherung, Symbol, Statusfeld, Feature-Tabelle und Optionen.</summary>
procedure Register;

implementation

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.TimeLimit,
  Atlas.Core.Diagnostics.ExitWatch,
  Atlas.Core.Diagnostics.Teardown,
  Atlas.Core.Diagnostics.Hangs,
  Atlas.Core.Modules.Registry,
  Atlas.IDE.Diagnostics.Watchdog,
  Atlas.IDE.Diagnostics.StackCapture,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.Symbol,
  Atlas.IDE.Settings.Experimental,
  Atlas.IDE.Settings.Transfer,
  Atlas.IDE.Completion.History,
  Atlas.IDE.Completion.Favorites,
  Atlas.IDE.CodeInsight.Composition.Session,
  Atlas.IDE.CodeInsight.Composition.Status,
  Atlas.IDE.CodeInsight.Composition.Tools,
  Atlas.IDE.CodeInsight.Composition.Startup,
  Atlas.IDE.CodeInsight.Composition.Features,
  Atlas.IDE.CodeInsight.Composition.Settings,
  Atlas.IDE.CodeInsight.Composition.Services,
  Atlas.IDE.CodeInsight.Composition.Leftovers;

/// <summary>Sicherung, Protokoll, Stacktraces, Sprache, Versionsverwaltung und Atlas-Symbol: vor allen Teilen.
/// </summary>
procedure InstallFoundation;
begin
  TAtlasTimeLimit.LimitMs := TAtlasIdeSettings.Current.ProviderTimeLimitMs;
  // Klarnamen in atlas.log nur ausdrücklich (#1478, diagnostics.log.names).
  TAtlasGuard.SetLogNames(TAtlasIdeSettings.Current.LogNames);
  TAtlasGuard.OnWarning := GuardWarning;
  TAtlasGuard.OnTripped := GuardTripped;
  TAtlasGuard.RotatingLog.OnError := LogError;
  // Stacktraces für jede Fehlerzeile der Sicherung: ohne sie lässt sich kein Fehler bis zur Codezeile verfolgen.
  TAtlasIdeStackCapture.Install;
  InstallLanguage;
  // Atlas-Symbol (#751): Startbildschirm, Info-Dialog und Bildliste immer, auch abgesichert.
  TAtlasIdeSymbol.Register;
end;

/// <summary>Immer, auch abgesichert: abgesicherter Start (#722) zuerst, denn davon hängt ab, was angemeldet wird;
/// dann Statusfeld, Schnellschalter und Benachrichtigungen.</summary>
procedure InstallAlways;
begin
  if SafeMode = nil then
  begin
    StartSafeMode;
  end;
  if StatusField = nil then
  begin
    RegisterStatusField;
  end;
  if QuickToggles = nil then
  begin
    StartQuickToggles;
  end;
  if Notifications = nil then
  begin
    StartNotifications;
  end;
end;

/// <summary>Nach der freien Nachrichtenschleife: Ladezeit (#722) und Startanteile (Bericht N4), Prüfliste beim
/// ersten Start (#625) und eigene Tasten, sobald die übrigen Packages ihre angemeldet haben (#520).</summary>
procedure AfterStart;
begin
  ReportStartup(TAtlasWatchdog.Timestamp - LoadedAt);
  if Setup <> nil then
  begin
    Setup.Start;
  end;
  if KeyMap <> nil then
  begin
    KeyMap.CheckAtStart;
  end;
end;

/// <summary>Die übrige Anmeldung ohne die schon einzeln gezählten Teile; bis zur freien Nachrichtenschleife laden
/// IDE, übrige Packages und Projekt, Atlas ist dann nur mit Aktionen dabei (etwa Bauen beim Öffnen).</summary>
procedure CountRegistration;
begin
  if StartTimes <> nil then
  begin
    StartTimes.Add('Anmeldung', TAtlasWatchdog.Timestamp - LoadedAt - StartTimes.Total);
    TAtlasActivity.TimeInto(StartTimes);
  end;
end;

var
  // Unregister lief schon: beim Zerstören des Hauptfensters, die finalization kommt danach oder gar nicht.
  Unregistered: Boolean;

procedure WatchIdeExit; forward;

procedure Register;
begin
  Unregistered := False;
  WatchIdeExit;
  // Startanteile (Bericht N4): ab dem Laden jedes Teil, nach der Anmeldung die Atlas-Aktionen.
  EndStartTimes;
  StartStartTimes;
  // Abbruchsignal eines früheren Entladens in derselben Sitzung zurücknehmen (#493).
  TAtlasShutdown.Reset;
  // Einreihen in den Hauptthread wieder annehmen (nach einem früheren Unregister, Code-Review A-02).
  TAtlasMainThread.Start;
  // Vor den Modulen: Sie fragen Sitzung und Protokoll über TAtlasIdeHost (#1455).
  InstallHost;
  InstallFoundation;
  InstallAlways;
  RegisterFeatures;
  TAtlasIdeExperimental.ApplySettings;
  InstallSettings;
  CountRegistration;
  TAtlasMainThread.ForceQueue(TAtlasFeature.Settings, AfterStart);
end;

/// <summary>Zuerst: Hauptthread, experimentelle Funktionen, Haken der Sicherung,
/// Einstellungen, Startanteile und abgesicherter Start (#722: Startmarke löschen, Absturzzähler zurück).</summary>
procedure StopFoundation(var ATeardown: TAtlasTeardown);
begin
  // Vor allem anderen: Was jetzt noch wartet oder während des Abbaus eingereiht wird, liefe nach dem Entladen
  // in nicht mehr geladenem Code (Code-Review A-02). Queue im Hauptthread läuft weiter sofort.
  ATeardown.Step('MainThread', TAtlasMainThread.Stop);
  ATeardown.Step('Experimental', TAtlasIdeExperimental.Stop);
  TAtlasGuard.OnWarning := nil;
  TAtlasGuard.OnTripped := nil;
  TAtlasGuard.OnFailure := nil;
  TAtlasGuard.RotatingLog.OnError := nil;
  DetachSettings;
  // Entladen vor der freien Nachrichtenschleife: Die Startanteile hängen noch an Aktionen und Teilen.
  ATeardown.Step('StartTimes', EndStartTimes);
  ATeardown.Step('SafeMode', StopSafeMode);
end;

/// <summary>Regel 5 (ADR 0017): zuerst alle Module stoppen und abmelden, dann den Host; bis zu ihrem Stopp dürfen
/// sie Sitzung und Protokoll von Base fragen.</summary>
procedure StopModules(var ATeardown: TAtlasTeardown);
var
  mFailures: TArray<string>;
begin
  ATeardown.Step('ModuleHosting', DetachModuleHosting);
  // Ein var-Parameter lässt sich nicht einfangen: Fehler der Module erst sammeln, dann übernehmen.
  mFailures := nil;
  ATeardown.Step('Modules',
    procedure
    begin
      if AtlasModuleRegistryInstance <> nil then
      begin
        mFailures := AtlasModuleRegistryInstance.ShutDown;
      end;
    end);
  ATeardown.AddFailures(mFailures);
  ATeardown.Step('Host', UninstallHost);
end;

/// <summary>Rückwärts zur Startreihenfolge (Code-Review S-03): die Teile der Feature-Tabelle, dann was immer läuft.
/// Alles vor dem Statusfeld: Diagnosemodus, Einrichtung, Update-Prüfung und Willkommensseite haben Zeilen in
/// dessen Registry (#479, #625, #754); die Benachrichtigungen halten Aktionen mit Code des Plugins (#601).</summary>
procedure StopParts(var ATeardown: TAtlasTeardown);
begin
  ATeardown.AddFailures(StopFeatures);
  ATeardown.Step('QuickToggles', StopQuickToggles);
  ATeardown.Step('SettingsTransfer', TAtlasIdeSettingsTransfer.Release);
  ATeardown.Step('Notifications', StopNotifications);
  ATeardown.Step('StatusField', UnregisterStatusField);
  ATeardown.Step('Options', UnregisterOptions);
  ATeardown.Step('History', TAtlasIdeHistory.Release);
  ATeardown.Step('Favorites', TAtlasIdeFavorites.Release);
  ATeardown.Step('Symbol', TAtlasIdeSymbol.Unregister);
  ATeardown.Step('Settings', TAtlasIdeSettings.Release);
end;

/// <summary>Zuletzt: Hintergrund-Threads, Feature-Tabelle, Stacktraces und was noch an der IDE hängt (#1233);
/// Ergebnis: ob alle Hintergrund-Threads beendet sind.</summary>
function StopRest(var ATeardown: TAtlasTeardown): Boolean;
var
  mStopped: Boolean;
begin
  mStopped := False;
  ATeardown.Step('Threads',
    procedure
    begin
      mStopped := TAtlasTimeLimit.StopAll(TAtlasShutdown.cStopMs);
    end);
  ATeardown.Step('Features', FreeFeatures);
  ATeardown.Step('StackCapture', TAtlasIdeStackCapture.Uninstall);
  ATeardown.Step('Leftovers', FreeLeftovers);
  Result := mStopped;
end;

/// <summary>Abbau in der Finalisierung. Jeder Schritt für sich (#886): Eine Ausnahme, etwa beim Entladen mitten im
/// Gruppen-Build, ließ früher alle folgenden Schritte aus; Notifier, Fenster-Hooks und Threads der alten Instanz
/// blieben angemeldet, und die IDE stürzte beim Beenden in nicht mehr geladenem Code ab. Die Zeile „Atlas
/// entladen“ steht immer im Protokoll, mit den fehlgeschlagenen Schritten (nur Name und Ausnahmeklasse).</summary>
procedure Unregister;
var
  mStartedAt: UInt64;
  mStopped: Boolean;
  mTeardown: TAtlasTeardown;
begin
  if Unregistered then
  begin
    Exit;
  end;
  Unregistered := True;
  mStartedAt := TThread.GetTickCount64;
  mStopped := False;
  mTeardown := TAtlasTeardown.Create;
  try
    // Zuerst das gemeinsame Abbruchsignal: Jeder Hintergrund-Thread hört auf zu warten (#493).
    TAtlasShutdown.Signal;
    StopFoundation(mTeardown);
    StopModules(mTeardown);
    StopParts(mTeardown);
    mStopped := StopRest(mTeardown);
  finally
    TAtlasGuard.Log(Format('Atlas entladen in %d ms; Hintergrund-Threads beendet: %s; Fehler beim Abbau: %s',
      [TThread.GetTickCount64 - mStartedAt, BoolToStr(mStopped, True), mTeardown.Summary]));
  end;
end;

var
  ExitWatch: TAtlasExitWatch;

procedure WatchIdeExit;
begin
  if (ExitWatch = nil) and (Application.MainForm <> nil) then
  begin
    ExitWatch := TAtlasExitWatch.Create(Application.MainForm, Unregister);
  end;
end;

/// <summary>Einträge in den Hauptthread verfallen mit ihrem Modul: Die Registry meldet Ab- und Anmelden mit dem
/// Handle des Packages an TAtlasMainThread. Schon in der Initialisierung: Module können sich anmelden, bevor die
/// IDE Register von Base ruft (Regel 1).</summary>
procedure ConnectModuleQueue;
begin
  TAtlasModuleRegistry.OnModuleClosing :=
    procedure(AHandle: NativeUInt)
    begin
      TAtlasMainThread.CloseModule(AHandle);
    end;
  TAtlasModuleRegistry.OnModuleOpened :=
    procedure(AHandle: NativeUInt)
    begin
      TAtlasMainThread.OpenModule(AHandle);
    end;
end;

initialization
  ConnectModuleQueue;

finalization
  Unregister;
  FreeAndNil(ExitWatch);

end.
