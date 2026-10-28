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
//   - vcs.projects und der Abschnitt vcs der .atlas (#1286): Art und
//     Hauptbranch je Projekt bzw. Ordner über TAtlasVcsProjects (gemeinsame
//     Auflösung mit der Tracker-Zuordnung). ForFolder löst je Ordner auf
//     (.atlas über dem Ordner, längste passende Zeile, sonst vcs.provider);
//     die .atlas wird je Datei nach Zeitstempel gemerkt. Ob die .atlas gilt
//     (Einstellung TeamFile), übernimmt der Hauptthread bei Start und Reload,
//     weil ForFolder auch in Hintergrund-Threads läuft
//   - Run: Aufruf im Hintergrund, Ergebnis im Hauptthread; der Prozessläufer
//     lehnt den Hauptthread ab, beendet git bzw. svn nach dem Zeitlimit und
//     beim Entladen (TAtlasShutdown)
//   - Serverzugang (#1287): CheckServer prüft auf Klick einmal im
//     Hintergrund (Atlas.Core.Vcs.ServerCheck), das Ergebnis merkt sich die
//     Sitzung je Ordner (nur im Speicher); OpenServerLogin öffnet eine
//     sichtbare Konsole mit git fetch bzw. svn info ^/ und meldet ihr Ende
//     (Zeitgeber im Hauptthread, kein wartender Thread)
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
  Atlas.Core.Vcs.ToolCheck,
  Atlas.Core.Vcs.ServerCheck,
  Atlas.Core.Projects.Vcs;

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
    /// <summary>Eine Zeile in der Meldungsansicht (#1288, Fortschritt beim Anlegen eines Branchs); aus jedem
    /// Thread, gezeigt im Hauptthread, nach Stop wirkungslos.</summary>
    class procedure Report(const AText: string); static;
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
    /// <summary>Was für den Ordner AFolder gilt (#1286): Art, Hauptbranch und woher; nur Dateiprüfung.</summary>
    class function ForFolderResolution(const AFolder: string): TAtlasVcsProjectResolution; static;
    /// <summary>Was für das Projekt AProjectFile (.dproj) mit geöffneter .groupproj AGroupFile ('' = keine) gilt
    /// (#1286, Reihenfolge .atlas → .dproj → .groupproj → längster Ordner → vcs.provider).</summary>
    class function ForProjectResolution(const AProjectFile, AGroupFile: string): TAtlasVcsProjectResolution;
      static;
    /// <summary>Hauptbranch für AProjectFile (.dproj) aus .atlas bzw. vcs.projects; '' = raten.</summary>
    class function MainBranchOf(const AProjectFile, AGroupFile: string): string; static;
    /// <summary>Persönliche Zeilen aus vcs.projects (settings.json).</summary>
    class function Projects: TArray<TAtlasVcsProjectMapping>; static;
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
      overload; static;
    /// <summary>Wie oben für das aktive Projekt AProjectFile (.dproj) in der geöffneten .groupproj AGroupFile: Art
    /// und Hauptbranch nach vcs.projects und .atlas (#1286); ProjectFile im Ergebnis ist die Gruppe, sonst die
    /// .dproj.</summary>
    class function QueryProject(const AProjectFile, AGroupFile: string;
      const ADone: TProc<TAtlasVcsProjectState>): Boolean; overload; static;
    /// <summary>Zugang zum Server für die Arbeitskopie von AFolder prüfen (#1287): einmal im Hintergrund,
    /// Zeitgrenze 10 s, ohne Rückfrage; ADone im Hauptthread, das Ergebnis merkt sich die Sitzung. Ohne
    /// Arbeitskopie kommt ADone sofort. False, wenn nichts gestartet wurde.</summary>
    class function CheckServer(const AFolder: string; const ADone: TProc<TAtlasVcsServerCheck>): Boolean; static;
    /// <summary>Letztes Ergebnis von CheckServer für AFolder in dieser Sitzung; State Unknown ohne.</summary>
    class function ServerState(const AFolder: string): TAtlasVcsServerCheck; static;
    /// <summary>„Anmelden …“ (#1287): sichtbare Konsole im Wurzelordner mit git fetch &lt;Remote&gt; bzw. svn info
    /// ^/, damit Git Credential Manager bzw. svn fragen und speichern; AClosed im Hauptthread, sobald man das
    /// Fenster schließt. False, wenn nichts gestartet wurde.</summary>
    class function OpenServerLogin(const ACheck: TAtlasVcsServerCheck; const AClosed: TProc): Boolean; static;
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
  Atlas.Core.Vcs.Worker,
  System.Generics.Collections,
  Winapi.Windows,
  Vcl.ExtCtrls,
  Atlas.Core.Projects.Matching,
  Atlas.Core.Vcs.ServerAccess,
  Atlas.Core.Settings.TeamFile,
  Atlas.IDE.Foundation.TeamFile;

type
  /// <summary>Werte aus settings.json (#571, #1285).</summary>
  TVcsSettings = record
    Provider: TAtlasVcsProvider;
    GitPath: string;
    SvnPath: string;
    TimeoutMs: Cardinal;
    Projects: TArray<TAtlasVcsProjectMapping>;
    class function Default: TVcsSettings; static;
  end;

  /// <summary>Abschnitt vcs einer .atlas mit Zeitstempel der Datei.</summary>
  TTeamEntry = record
    Age: TDateTime;
    Vcs: TAtlasTeamVcs;
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
  // .atlas je Datei (klein geschrieben); gilt die Datei (Einstellung TeamFile)?
  TeamCache: TDictionary<string, TTeamEntry>;
  TeamFileOn: Boolean;
  // Serverzugang je Ordner (klein geschrieben), nur in dieser Sitzung (#1287); nur im Hauptthread.
  ServerStates: TDictionary<string, TAtlasVcsServerCheck>;

const
  cDefaultTimeoutSeconds = 15;

type
  /// <summary>Offene Konsolen von „Anmelden …“ (#1287): ein Zeitgeber im Hauptthread fragt, ob der Prozess endete.
  /// </summary>
  TLoginWatch = class
  private const
    cIntervalMs = 500;
  private
    FTimer: TTimer;
    FProcesses: TList<THandle>;
    FClosed: TList<TProc>;
    procedure Tick(Sender: TObject);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(AProcess: THandle; const AClosed: TProc);
  end;

var
  Logins: TLoginWatch;

constructor TLoginWatch.Create;
begin
  inherited Create;
  FProcesses := TList<THandle>.Create;
  FClosed := TList<TProc>.Create;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := cIntervalMs;
  FTimer.OnTimer := Tick;
end;

destructor TLoginWatch.Destroy;
var
  mProcess: THandle;
begin
  FTimer.Free;
  // Beim Entladen bleiben die Konsolen offen; nur die Handles schließen, ohne Rückruf.
  for mProcess in FProcesses do
    CloseHandle(mProcess);
  FProcesses.Free;
  FClosed.Free;
  inherited Destroy;
end;

procedure TLoginWatch.Add(AProcess: THandle; const AClosed: TProc);
begin
  FProcesses.Add(AProcess);
  FClosed.Add(AClosed);
  FTimer.Enabled := True;
end;

procedure TLoginWatch.Tick(Sender: TObject);
var
  mIndex: Integer;
  mClosed: TProc;
begin
  for mIndex := FProcesses.Count - 1 downto 0 do
    if WaitForSingleObject(FProcesses[mIndex], 0) = WAIT_OBJECT_0 then
    begin
      CloseHandle(FProcesses[mIndex]);
      mClosed := FClosed[mIndex];
      FProcesses.Delete(mIndex);
      FClosed.Delete(mIndex);
      if Assigned(mClosed) then
        TAtlasGuard.Run(TAtlasFeature.Settings, mClosed);
    end;
  FTimer.Enabled := FProcesses.Count > 0;
end;
  cMinTimeoutSeconds = 1;
  cMaxTimeoutSeconds = 300;

class function TVcsSettings.Default: TVcsSettings;
begin
  Result.Provider := TAtlasVcsProvider.Auto;
  Result.GitPath := '';
  Result.SvnPath := '';
  Result.TimeoutMs := cDefaultTimeoutSeconds * 1000;
  Result.Projects := nil;
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
        Result.Projects := TAtlasVcsProjects.Read(TAtlasJsonText.ValueAt(mRoot, TAtlasVcsProjects.Path));
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
  // Hauptthread: ob die .atlas gilt, kann sich mit den Einstellungen geändert haben.
  TeamFileOn := TAtlasIdeTeamFile.Wanted;
  Lock.Enter;
  try
    CachedAge := -1;
    TeamCache.Clear;
  finally
    Lock.Leave;
  end;
  Current;
end;

function TeamPathExists(const APath: string): Boolean;
begin
  // .git ist ein Ordner oder bei Worktrees eine Datei.
  Result := FileExists(APath) or DirectoryExists(APath);
end;

/// <summary>Abschnitt vcs der .atlas für AFolder (dort, sonst in der Wurzel des Repositorys); leer ohne Datei,
/// wenn sie nicht lesbar ist oder die Einstellung TeamFile aus ist.</summary>
function TeamVcsOf(const AFolder: string): TAtlasTeamVcs;
var
  mFileName, mKey: string;
  mAge: TDateTime;
  mEntry: TTeamEntry;
  mTeam: TAtlasTeamSettings;
begin
  Result := Default(TAtlasTeamVcs);
  if not TeamFileOn or (AFolder = '') then
    Exit;
  mFileName := TAtlasTeamFile.Locate(ExcludeTrailingPathDelimiter(AFolder), TeamPathExists);
  if (mFileName = '') or not FileAge(mFileName, mAge) then
    Exit;
  mKey := LowerCase(mFileName);
  Lock.Enter;
  try
    if TeamCache.TryGetValue(mKey, mEntry) and (mEntry.Age = mAge) then
      Exit(mEntry.Vcs);
  finally
    Lock.Leave;
  end;
  try
    mTeam := TAtlasTeamFile.Parse(TAtlasTextFile.Load(mFileName).Text, mFileName,
      TAtlasTeamFile.RootOf(ExtractFileDir(mFileName), TeamPathExists));
    if mTeam.Valid then
      Result := mTeam.Vcs;
  except
    // Gesperrt (gerade gespeichert) oder gelöscht: ohne Abschnitt, beim nächsten Mal neu.
    on Exception do
      Exit;
  end;
  mEntry.Age := mAge;
  mEntry.Vcs := Result;
  Lock.Enter;
  try
    TeamCache.AddOrSetValue(mKey, mEntry);
  finally
    Lock.Leave;
  end;
end;

class function TAtlasIdeVcs.Projects: TArray<TAtlasVcsProjectMapping>;
begin
  Result := Current.Projects;
end;

class function TAtlasIdeVcs.ForFolderResolution(const AFolder: string): TAtlasVcsProjectResolution;
var
  mSettings: TVcsSettings;
  mTeam: TAtlasTeamVcs;
begin
  mSettings := Current;
  mTeam := TeamVcsOf(AFolder);
  Result := TAtlasVcsProjects.ResolveFolder(mTeam.Provider, mTeam.MainBranch, mSettings.Projects,
    mSettings.Provider, AFolder);
end;

class function TAtlasIdeVcs.ForProjectResolution(const AProjectFile,
  AGroupFile: string): TAtlasVcsProjectResolution;
var
  mSettings: TVcsSettings;
  mTeam: TAtlasTeamVcs;
begin
  mSettings := Current;
  mTeam := TeamVcsOf(ExtractFileDir(AProjectFile));
  Result := TAtlasVcsProjects.Resolve(mTeam.Provider, mTeam.MainBranch, mSettings.Projects, mSettings.Provider,
    AProjectFile, AGroupFile);
end;

class function TAtlasIdeVcs.MainBranchOf(const AProjectFile, AGroupFile: string): string;
begin
  Result := '';
  if AProjectFile <> '' then
    Result := ForProjectResolution(AProjectFile, AGroupFile).MainBranch;
end;

/// <summary>Umsetzung für AFolder mit der Art AProvider; nil vor dem ersten Start.</summary>
function OpenFolder(const AFolder: string; AProvider: TAtlasVcsProvider; ATimeoutMs: Cardinal): IAtlasVersionControl;
var
  mRunner: IAtlasVcsRunner;
  mTimeoutMs: Cardinal;
begin
  Result := nil;
  if not Assigned(Backend.Open) then
    Exit;
  mRunner := Runner;
  if mRunner = nil then
    mRunner := Backend.NewRunner(nil);
  mTimeoutMs := ATimeoutMs;
  if mTimeoutMs = 0 then
    mTimeoutMs := Current.TimeoutMs;
  Result := Backend.Open(AFolder, AProvider, mRunner, mTimeoutMs);
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
  TeamFileOn := TAtlasIdeTeamFile.Wanted;
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
  FreeAndNil(Logins);
end;

class procedure TAtlasIdeVcs.Report(const AText: string);
var
  mText: string;
begin
  mText := AText;
  TAtlasMainThread.ForceQueue(TAtlasFeature.Status,
    procedure
    begin
      if Assigned(Message_) and not TAtlasShutdown.Signalled then
        Message_(mText);
    end);
end;

class function TAtlasIdeVcs.ForFolder(const AFolder: string): IAtlasVersionControl;
begin
  Result := ForFolder(AFolder, 0);
end;

class function TAtlasIdeVcs.ForFolder(const AFolder: string; ATimeoutMs: Cardinal): IAtlasVersionControl;
begin
  // Vor dem ersten Start ist keine Umsetzung eingesetzt. Art je Ordner (#1286): „Aus“ liefert die leere Umsetzung.
  Result := OpenFolder(AFolder, ForFolderResolution(AFolder).Provider, ATimeoutMs);
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

class function TAtlasIdeVcs.CheckServer(const AFolder: string; const ADone: TProc<TAtlasVcsServerCheck>): Boolean;
var
  mRunner: IAtlasVcsRunner;
  mCopy: TAtlasVcsWorkingCopy;
  mExecutable, mKey: string;
  mCheck: TAtlasVcsServerCheck;
begin
  mRunner := Runner;
  if mRunner = nil then
    Exit(False);
  mKey := LowerCase(AFolder);
  // Art und Wurzel ohne Prozess; „Aus“ und keine Arbeitskopie: sofort „kein Server“.
  mCopy := ForFolder(AFolder).WorkingCopy;
  mExecutable := '';
  if mCopy.Kind <> TAtlasVcsKind.None then
    mExecutable := TAtlasVcsTools.Find(mCopy.Kind);
  mCheck := TAtlasVcsServerCheck.Empty;
  if mCopy.Kind = TAtlasVcsKind.None then
  begin
    mCheck := TAtlasVcsServerChecks.Check(mRunner, mCopy.Kind, mExecutable, mCopy.Root,
      TAtlasVcsServerChecks.TimeoutMs, Now);
    ServerStates.AddOrSetValue(mKey, mCheck);
    ADone(mCheck);
    Exit(True);
  end;
  // Arbeit und Ergebnis teilen sich mCheck; das Ergebnis kommt erst nach der Arbeit.
  Result := Run(
    procedure
    begin
      mCheck := TAtlasVcsServerChecks.Check(mRunner, mCopy.Kind, mExecutable, mCopy.Root,
        TAtlasVcsServerChecks.TimeoutMs, Now);
    end,
    procedure
    begin
      if ServerStates <> nil then
        ServerStates.AddOrSetValue(mKey, mCheck);
      ADone(mCheck);
    end);
end;

class function TAtlasIdeVcs.ServerState(const AFolder: string): TAtlasVcsServerCheck;
begin
  if (ServerStates = nil) or not ServerStates.TryGetValue(LowerCase(AFolder), Result) then
    Result := TAtlasVcsServerCheck.Empty;
end;

class function TAtlasIdeVcs.OpenServerLogin(const ACheck: TAtlasVcsServerCheck; const AClosed: TProc): Boolean;
var
  mShell, mCommandLine: string;
  mStartup: TStartupInfo;
  mProcess: TProcessInformation;
begin
  Result := False;
  if (Runner = nil) or not ACheck.CanLogin or not DirectoryExists(ACheck.Root) then
    Exit;
  mShell := System.SysUtils.GetEnvironmentVariable('ComSpec');
  if mShell = '' then
    mShell := 'cmd.exe';
  mCommandLine := TAtlasVcsServerChecks.LoginCommandLine(mShell, TAtlasVcsTools.Find(ACheck.Kind), ACheck.Kind,
    ACheck.Remote);
  if mCommandLine = '' then
    Exit;
  UniqueString(mCommandLine);
  FillChar(mStartup, SizeOf(mStartup), 0);
  mStartup.cb := SizeOf(mStartup);
  FillChar(mProcess, SizeOf(mProcess), 0);
  // Sichtbar und mit eigener Konsole: Hier dürfen git, Git Credential Manager und svn nachfragen.
  if not CreateProcess(nil, PChar(mCommandLine), nil, nil, False, CREATE_NEW_CONSOLE, nil, PChar(ACheck.Root),
    mStartup, mProcess) then
    Exit;
  CloseHandle(mProcess.hThread);
  if Logins = nil then
    Logins := TLoginWatch.Create;
  Logins.Add(mProcess.hProcess, AClosed);
  Result := True;
end;

class function TAtlasIdeVcs.QueryProject(const AProjectFile: string;
  const ADone: TProc<TAtlasVcsProjectState>): Boolean;
begin
  Result := QueryProject(AProjectFile, '', ADone);
end;

class function TAtlasIdeVcs.QueryProject(const AProjectFile, AGroupFile: string;
  const ADone: TProc<TAtlasVcsProjectState>): Boolean;
var
  mState: TAtlasVcsProjectState;
  mResolution: TAtlasVcsProjectResolution;
  mVcs: IAtlasVersionControl;
  mHead: TAtlasVcsHead;
  mOutcome: TAtlasVcsOutcome;
  mFolder: string;
begin
  mState := TAtlasVcsProjectState.Empty;
  mState.ProjectFile := TAtlasProjectMatching.CurrentMatch(AProjectFile, AGroupFile);
  if AProjectFile = '' then
  begin
    mState.Provider := Provider;
    ADone(mState);
    Exit(True);
  end;
  // Welche Zeile gilt (#1286): .atlas, .dproj, .groupproj, längster Ordner, sonst vcs.provider.
  mResolution := ForProjectResolution(AProjectFile, AGroupFile);
  mState.Provider := mResolution.Provider;
  mState.Source := mResolution.Source;
  mState.SourceMatch := mResolution.SourceMatch;
  mState.MainBranch := mResolution.MainBranch;
  mFolder := ExtractFileDir(AProjectFile);
  mVcs := OpenFolder(mFolder, mState.Provider, 0);
  // Art und Wurzel ohne Prozess; die leere Umsetzung kennt sie nicht, die Erkennung schon.
  if mState.Provider = TAtlasVcsProvider.Off then
    mState.Outcome := TAtlasVcsOutcome.Disabled
  else
  begin
    mState.WorkingCopy := TAtlasVcsDetection.Find(mFolder, mState.Provider);
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
  TeamCache := TDictionary<string, TTeamEntry>.Create;
  ServerStates := TDictionary<string, TAtlasVcsServerCheck>.Create;

finalization
  TAtlasIdeVcs.Stop;
  FreeAndNil(ServerStates);
  FreeAndNil(TeamCache);
  FreeAndNil(Lock);

end.
