unit Atlas.IDE.Vcs.Service;

// Versionsverwaltung in der IDE (#571): Einstieg für alle Funktionen des
// Plugins, die Branch, Revision, geänderte Dateien, Dateiinhalt einer
// Revision oder Zeilenherkunft brauchen (Willkommensseite: Projektzustand
// #592, nicht gesicherte Arbeit #762 …).
//   - ForFolder: Umsetzung für einen Ordner nach vcs.provider aus
//     %APPDATA%\Atlas\settings.json (neu gelesen, wenn sich die Datei ändert);
//     prüft nur Dateien und darf im Hauptthread laufen
//   - vcs.git.path, vcs.svn.path und vcs.timeoutSeconds (#1285) kommen aus
//     derselben Datei: Die Pfade gehen an TAtlasVcsTools.Configure (ein neuer
//     Pfad gilt ohne Neustart), das Zeitlimit gilt für jeden Aufruf ohne
//     eigenes Limit
//   - Run: Aufruf im Hintergrund, Ergebnis im Hauptthread; der Prozessläufer
//     lehnt den Hauptthread ab, beendet git bzw. svn nach dem Zeitlimit und
//     beim Entladen (TAtlasShutdown)
//   - fehlt git bzw. svn bei einer gefundenen Arbeitskopie, steht das einmal
//     je Sitzung in der Meldungsansicht und im Protokoll (bei eigenem Pfad mit
//     dem Pfad, nur in der Meldungsansicht); Atlas arbeitet ohne
//     Versionsangaben weiter
// Start und Stop ruft die Komposition beim Laden bzw. Entladen; sie setzt
// dabei auch die Umsetzung des Kerns ein (TAtlasIdeVcsBackend, A-09).

interface

uses
  System.SysUtils,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.Tools,
  Atlas.Core.Vcs.ToolCheck;

type
  TAtlasIdeVcsMessage = reference to procedure(const AText: string);
  /// <summary>Umsetzung für AFolder; ATimeoutMs = 0: Vorgabe-Zeitlimit.</summary>
  TAtlasIdeVcsOpen = reference to function(const AFolder: string; AProvider: TAtlasVcsProvider;
    const ARunner: IAtlasVcsRunner; ATimeoutMs: Cardinal): IAtlasVersionControl;

  /// <summary>Was die Kompositionswurzel aus dem Kern einsetzt (Prozessläufer, Auswahl, Meldung).</summary>
  TAtlasIdeVcsBackend = record
    /// <summary>Neuer Prozessläufer; ACancelled = nil: ohne Abbruch.</summary>
    NewRunner: TFunc<TFunc<Boolean>, IAtlasVcsRunner>;
    Open: TAtlasIdeVcsOpen;
    /// <summary>Setzt (oder mit nil löscht) die Meldung „git bzw. svn fehlt“.</summary>
    SetToolMissing: TProc<TProc<TAtlasVcsKind>>;
  end;

  TAtlasIdeVcs = class
  public
    /// <summary>Beim Laden: AMessage zeigt eine Zeile in der Meldungsansicht (Hauptthread).</summary>
    class procedure Start(const AMessage: TAtlasIdeVcsMessage; const ABackend: TAtlasIdeVcsBackend); static;
    /// <summary>Beim Entladen: laufende Aufrufe abbrechen, keine Ergebnisse mehr zustellen.</summary>
    class procedure Stop; static;
    /// <summary>Wirksamer Wert von vcs.provider.</summary>
    class function Provider: TAtlasVcsProvider; static;
    /// <summary>Zeitlimit je Aufruf aus vcs.timeoutSeconds (#1285) in Millisekunden.</summary>
    class function TimeoutMs: Cardinal; static;
    /// <summary>Das größere aus AMinimumMs und TimeoutMs: für Aufrufe, die länger dauern dürfen (Branch anlegen,
    /// Pull, #765).</summary>
    class function AtLeast(AMinimumMs: Cardinal): Cardinal; static;
    /// <summary>Settings.json neu lesen, auch wenn sich der Zeitstempel nicht geändert hat (nach dem Speichern der
    /// Optionsseite).</summary>
    class procedure Reload; static;
    /// <summary>Umsetzung für AFolder (z. B. Ordner des Projekts); leer, wenn abgeschaltet oder ohne
    /// Arbeitskopie.</summary>
    class function ForFolder(const AFolder: string): IAtlasVersionControl; overload; static;
    /// <summary>Wie oben mit eigenem Zeitlimit je Aufruf (Willkommensseite: 1 s, #592); ATimeoutMs = 0: Zeitlimit
    /// aus vcs.timeoutSeconds.</summary>
    class function ForFolder(const AFolder: string; ATimeoutMs: Cardinal): IAtlasVersionControl; overload; static;
    /// <summary>AWork im Hintergrund, danach ADone im Hauptthread; nach Stop wirkungslos. False, wenn nichts
    /// gestartet wurde (vor Start, nach Stop): Dann kommt ADone nie.</summary>
    class function Run(const AWork, ADone: TProc): Boolean; static;
    /// <summary>Fundort von git bzw. svn für den eingetragenen, noch nicht gespeicherten Pfad APath (#1285), nur
    /// Dateiprüfung; darf im Hauptthread laufen.</summary>
    class function Locate(AKind: TAtlasVcsKind; const APath: string): TAtlasVcsToolLocation; static;
    /// <summary>„Prüfen“ (#1285): git --version bzw. svn --version --quiet im Hintergrund, ADone im Hauptthread.
    /// False, wenn nichts gestartet wurde.</summary>
    class function CheckTool(AKind: TAtlasVcsKind; const APath: string;
      const ADone: TProc<TAtlasVcsToolCheck>): Boolean; static;
    /// <summary>Stand für das Projekt AProjectFile (.groupproj bzw. .dproj; Arbeitskopie seines Ordners) im
    /// Hintergrund, ADone im Hauptthread (#1285, „Aktuelles Projekt“). Ohne Projekt, ohne Arbeitskopie oder
    /// abgeschaltet kommt ADone sofort. False, wenn nichts gestartet wurde.</summary>
    class function QueryProject(const AProjectFile: string; const ADone: TProc<TAtlasVcsProjectState>): Boolean;
      static;
  end;

implementation

uses
  Atlas.Core.Diagnostics.MainThread,
  System.Classes,
  System.SyncObjs,
  System.JSON,
  Atlas.UI.Strings,
  Atlas.Core.Settings.Layers,
  Atlas.Core.Settings.JsonText,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Vcs.Detection,
  Atlas.Core.Vcs.Worker;

type
  /// <summary>Werte aus settings.json (#571, #1285).</summary>
  TVcsSettings = record
    Provider: TAtlasVcsProvider;
    GitPath: string;
    SvnPath: string;
    TimeoutMs: Cardinal;
    class function Default: TVcsSettings; static;
  end;

var
  Worker: TAtlasVcsWorker;
  Runner: IAtlasVcsRunner;
  Backend: TAtlasIdeVcsBackend;
  Message_: TAtlasIdeVcsMessage;
  Lock: TCriticalSection;
  // vcs.* mit Zeitstempel der Datei, aus der die Werte stammen.
  Cached: TVcsSettings;
  CachedAge: TDateTime = -1;

const
  cDefaultTimeoutSeconds = 15;
  cMinTimeoutSeconds = 1;
  cMaxTimeoutSeconds = 300;

class function TVcsSettings.Default: TVcsSettings;
begin
  Result.Provider := TAtlasVcsProvider.Auto;
  Result.GitPath := '';
  Result.SvnPath := '';
  Result.TimeoutMs := cDefaultTimeoutSeconds * 1000;
end;

function SettingsFile: string;
begin
  Result := TAtlasSettingsFiles.GlobalFile(GetEnvironmentVariable('APPDATA'));
end;

function JsonString(const AJson: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  if AJson = '' then
    Exit;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if mValue is TJSONString then
      Result := Trim(TJSONString(mValue).Value);
  finally
    mValue.Free;
  end;
end;

function ReadSettings(const AFileName: string): TVcsSettings;
var
  mRoot: TJSONObject;
  mSeconds: Integer;
begin
  Result := TVcsSettings.Default;
  try
    mRoot := TAtlasJsonText.Parse(TAtlasTextFile.Load(AFileName).Text);
    try
      if mRoot <> nil then
      begin
        Result.Provider := AtlasVcsProviderOf(TAtlasJsonText.ValueAt(mRoot, 'vcs.provider'));
        Result.GitPath := JsonString(TAtlasJsonText.ValueAt(mRoot, 'vcs.git.path'));
        Result.SvnPath := JsonString(TAtlasJsonText.ValueAt(mRoot, 'vcs.svn.path'));
        // Außerhalb 1–300 gilt die Vorgabe, wie im Parser des Servers.
        mSeconds := StrToIntDef(TAtlasJsonText.ValueAt(mRoot, 'vcs.timeoutSeconds'), cDefaultTimeoutSeconds);
        if (mSeconds < cMinTimeoutSeconds) or (mSeconds > cMaxTimeoutSeconds) then
          mSeconds := cDefaultTimeoutSeconds;
        Result.TimeoutMs := Cardinal(mSeconds) * 1000;
      end;
    finally
      mRoot.Free;
    end;
  except
    // Gesperrt oder unlesbar: Vorgaben.
    on Exception do
      Result := TVcsSettings.Default;
  end;
end;

function Current: TVcsSettings;
var
  mFileName: string;
  mAge: TDateTime;
begin
  mFileName := SettingsFile;
  if (mFileName = '') or not FileAge(mFileName, mAge) then
  begin
    Result := TVcsSettings.Default;
    mAge := -2;
  end
  else
  begin
    Lock.Enter;
    try
      if mAge = CachedAge then
        Exit(Cached);
    finally
      Lock.Leave;
    end;
    Result := ReadSettings(mFileName);
  end;
  // Ein geänderter Pfad gilt ohne Neustart: Configure vergisst dann das gemerkte Programm.
  TAtlasVcsTools.Configure(TAtlasVcsKind.Git, Result.GitPath);
  TAtlasVcsTools.Configure(TAtlasVcsKind.Svn, Result.SvnPath);
  Lock.Enter;
  try
    Cached := Result;
    CachedAge := mAge;
  finally
    Lock.Leave;
  end;
end;

class function TAtlasIdeVcs.Provider: TAtlasVcsProvider;
begin
  Result := Current.Provider;
end;

class function TAtlasIdeVcs.TimeoutMs: Cardinal;
begin
  Result := Current.TimeoutMs;
end;

class function TAtlasIdeVcs.AtLeast(AMinimumMs: Cardinal): Cardinal;
begin
  Result := TimeoutMs;
  if AMinimumMs > Result then
    Result := AMinimumMs;
end;

class procedure TAtlasIdeVcs.Reload;
begin
  Lock.Enter;
  try
    CachedAge := -1;
  finally
    Lock.Leave;
  end;
  Current;
end;

procedure ToolMissing(AKind: TAtlasVcsKind);
var
  Name, Text, mConfigured: string;
begin
  Name := AtlasVcsKindName(AKind);
  TAtlasGuard.Log(Format('Versionsverwaltung: %s nicht gefunden, weiter ohne', [Name]));
  // Eigener Pfad (#1285): Der Pfad steht nur in der Meldungsansicht, nie im Protokoll.
  mConfigured := TAtlasVcsTools.Configured(AKind);
  if mConfigured <> '' then
    Text := Format(TAtlasStrings.Text(TAtlasTextId.VcsToolConfiguredMissing), [Name, mConfigured])
  else
    Text := Format(TAtlasStrings.Text(TAtlasTextId.VcsToolMissing), [Name, Name]);
  // Kann aus einem Hintergrund-Thread kommen; die Meldungsansicht nur im Hauptthread.
  TAtlasMainThread.ForceQueue(TAtlasFeature.Status,
    procedure
    begin
      if Assigned(Message_) and not TAtlasShutdown.Signalled then
        Message_(Text);
    end);
end;

class procedure TAtlasIdeVcs.Start(const AMessage: TAtlasIdeVcsMessage; const ABackend: TAtlasIdeVcsBackend);
begin
  Message_ := AMessage;
  Backend := ABackend;
  if Runner = nil then
    Runner := Backend.NewRunner(
      function: Boolean
      begin
        Result := TAtlasShutdown.Signalled;
      end);
  if Worker = nil then
    Worker := TAtlasVcsWorker.Create;
  Backend.SetToolMissing(ToolMissing);
end;

class procedure TAtlasIdeVcs.Stop;
begin
  if Assigned(Backend.SetToolMissing) then
    Backend.SetToolMissing(nil);
  Message_ := nil;
  if Worker <> nil then
    Worker.Stop(TAtlasShutdown.StopMs);
  FreeAndNil(Worker);
  Runner := nil;
end;

class function TAtlasIdeVcs.ForFolder(const AFolder: string): IAtlasVersionControl;
begin
  Result := ForFolder(AFolder, 0);
end;

class function TAtlasIdeVcs.ForFolder(const AFolder: string; ATimeoutMs: Cardinal): IAtlasVersionControl;
var
  RunnerRef: IAtlasVcsRunner;
  mSettings: TVcsSettings;
  mTimeoutMs: Cardinal;
begin
  // Vor dem ersten Start ist keine Umsetzung eingesetzt.
  Result := nil;
  if not Assigned(Backend.Open) then
    Exit;
  RunnerRef := Runner;
  if RunnerRef = nil then
    RunnerRef := Backend.NewRunner(nil);
  mSettings := Current;
  mTimeoutMs := ATimeoutMs;
  if mTimeoutMs = 0 then
    mTimeoutMs := mSettings.TimeoutMs;
  Result := Backend.Open(AFolder, mSettings.Provider, RunnerRef, mTimeoutMs);
end;

class function TAtlasIdeVcs.Run(const AWork, ADone: TProc): Boolean;
begin
  Result := (Worker <> nil) and Worker.Run(AWork, ADone);
end;

class function TAtlasIdeVcs.Locate(AKind: TAtlasVcsKind; const APath: string): TAtlasVcsToolLocation;
begin
  Result := TAtlasVcsTools.Probe(AKind, APath);
end;

class function TAtlasIdeVcs.CheckTool(AKind: TAtlasVcsKind; const APath: string;
  const ADone: TProc<TAtlasVcsToolCheck>): Boolean;
var
  mRunner: IAtlasVcsRunner;
  mLocation: TAtlasVcsToolLocation;
  mCheck: TAtlasVcsToolCheck;
begin
  mRunner := Runner;
  if (mRunner = nil) or (AKind = TAtlasVcsKind.None) then
    Exit(False);
  mLocation := Locate(AKind, APath);
  mCheck := TAtlasVcsToolChecks.Missing(AKind, mLocation);
  // Arbeit und Ergebnis teilen sich mCheck; das Ergebnis kommt erst nach der Arbeit.
  Result := Run(
    procedure
    begin
      mCheck := TAtlasVcsToolChecks.Check(AKind, mLocation, mRunner);
    end,
    procedure
    begin
      ADone(mCheck);
    end);
end;

class function TAtlasIdeVcs.QueryProject(const AProjectFile: string;
  const ADone: TProc<TAtlasVcsProjectState>): Boolean;
var
  mState: TAtlasVcsProjectState;
  mVcs: IAtlasVersionControl;
  mHead: TAtlasVcsHead;
  mOutcome: TAtlasVcsOutcome;
begin
  mState := TAtlasVcsProjectState.Empty;
  mState.ProjectFile := AProjectFile;
  mState.Provider := Provider;
  if AProjectFile = '' then
  begin
    ADone(mState);
    Exit(True);
  end;
  mVcs := ForFolder(ExtractFileDir(AProjectFile));
  // Art und Wurzel ohne Prozess; die leere Umsetzung kennt sie nicht, die Erkennung schon.
  if mState.Provider = TAtlasVcsProvider.Off then
    mState.Outcome := TAtlasVcsOutcome.Disabled
  else
  begin
    mState.WorkingCopy := TAtlasVcsDetection.Find(ExtractFileDir(AProjectFile), mState.Provider);
    if mState.WorkingCopy.Kind = TAtlasVcsKind.None then
      mState.Outcome := TAtlasVcsOutcome.NoWorkingCopy
    else if (mVcs = nil) or (mVcs.Kind = TAtlasVcsKind.None) then
      mState.Outcome := TAtlasVcsOutcome.ToolMissing
    else
      mState.Outcome := TAtlasVcsOutcome.Ok;
  end;
  if mState.Outcome <> TAtlasVcsOutcome.Ok then
  begin
    ADone(mState);
    Exit(True);
  end;
  mHead := TAtlasVcsHead.Empty;
  mOutcome := TAtlasVcsOutcome.Failed;
  Result := Run(
    procedure
    begin
      mOutcome := mVcs.Head(mHead);
    end,
    procedure
    begin
      mState.Outcome := mOutcome;
      mState.Head := mHead;
      ADone(mState);
    end);
end;

initialization
  Lock := TCriticalSection.Create;
  Cached := TVcsSettings.Default;

finalization
  TAtlasIdeVcs.Stop;
  FreeAndNil(Lock);

end.
