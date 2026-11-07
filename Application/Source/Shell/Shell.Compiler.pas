unit Shell.Compiler;

// Host-Rolle Shell: Kompilieren ohne Kommandozeilen-Compiler (#261).
// - TShellCompilerEditions erkennt je BDS-Wurzel und Version vorher, ob
//   dcc32/dcc64 da und nutzbar ist (Probelauf ohne Argumente, Lizenztext der
//   Starter bzw. Community Edition), und merkt sich das in
//   %LOCALAPPDATA%\Atlas\compiler-editions.json (Atlas.Common.Compiler.Edition).
// - TShellIdeCompiler baut über eine eigene Scratch-IDE mit cc.ps1
//   (Atlas.Common.Compiler.IdeCommand): Vor dem Start merkt er sich alle
//   laufenden IDEs; liefert cc.ps1 die pid einer davon, bricht er ab. So wird
//   die IDE des Benutzers nie angesprochen; jeder weitere Aufruf trägt
//   -Instance. Die eigene Instanz bleibt für weitere Läufe stehen und endet
//   mit dem Server (Quit).
// Prozesse, laufende IDEs und das Lesen des logFile kommen von außen, damit
// die Tests ohne Windows und ohne IDE laufen.

interface

uses
  System.SysUtils,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Compiler.Edition,
  Atlas.Common.Compiler.Backend;

type
  /// <summary>Ein Compilerlauf: dcc mit fertigem Aufruf oder IDE mit Projekt und cc.ps1.</summary>
  TShellCompileJob = record
    Backend: TCompilerBackend;
    /// <summary>Über den Befehl „Projekt kompilieren“ statt nach dem Speichern.</summary>
    Manual: Boolean;
    /// <summary>Aufruf von dcc32/dcc64 (nur Backend Dcc).</summary>
    Request: TCompilerRequest;
    /// <summary>Eigener Ausgabeordner von dcc; entsteht erst vor dem Lauf.</summary>
    OutputDir: string;
    Project: string;
    Platform: string;
    BdsRoot: string;
    Version: string;
    Settings: TCompilerSettings;
  end;

  TShellCompilerEditions = class
  private
    FProcess: ICompilerProcess;
    FLogger: ILogger;
    FFileName: string;
    FLock: TObject;
    FCache: TCompilerEditionCache;
    FLoaded: Boolean;
    procedure EnsureLoaded;
    procedure Save;
    procedure Store(const ABdsRoot, AVersion, AStamp: string; AEdition: TCompilerEdition);
  public
    /// <summary>AFileName: Ablage des Zwischenspeichers ('' = nur im Speicher).</summary>
    constructor Create(const AProcess: ICompilerProcess; const ALogger: ILogger; const AFileName: string);
    destructor Destroy; override;
    /// <summary>Ausgabe zu AExecutable (dcc32/dcc64 unter ABdsRoot): aus dem Zwischenspeicher oder per Probelauf.
    /// Threadsicher.</summary>
    function Resolve(const ABdsRoot, AVersion, AExecutable: string): TCompilerEdition;
    /// <summary>Ein echter Lauf hat den Lizenztext gezeigt (#261): merken. Threadsicher.</summary>
    procedure Remember(const ABdsRoot, AVersion, AExecutable: string; AEdition: TCompilerEdition);
    /// <summary>Fingerabdruck einer Datei aus Größe und Zeitstempel; '' ohne Datei.</summary>
    class function StampOf(const AFileName: string): string; static;
    /// <summary>%LOCALAPPDATA%\Atlas\compiler-editions.json.</summary>
    class function DefaultFile: string; static;
  end;

  TShellIdeIdsFunc = reference to function: TArray<Cardinal>;
  TShellIdeRunningFunc = reference to function(APid: Cardinal): Boolean;
  TShellReadLinesFunc = reference to function(const AFileName: string): TArray<string>;

  /// <summary>Eigene IDE über cc.ps1. Nur aus einem Thread zugleich (dem Compile-Thread bzw. beim Beenden).
  /// </summary>
  TShellIdeCompiler = class
  private
    FProcess: ICompilerProcess;
    FLogger: ILogger;
    FPowerShell: string;
    FIdes: TShellIdeIdsFunc;
    FRunning: TShellIdeRunningFunc;
    FReadLines: TShellReadLinesFunc;
    FPid: Cardinal;
    FScript: string;
    function Run(const AProcess: ICompilerProcess; const AScript: string; const AArguments: TArray<string>;
      const AWorkingDir: string; out AOutput: TArray<string>): Integer;
    function EnsureInstance(const AScript, AProject: string; out AError: string): Boolean;
  public
    /// <summary>APowerShell: pwsh.exe bzw. powershell.exe; AIdes: pids aller laufenden IDEs (bds.exe);
    /// ARunning: läuft der Prozess noch; AReadLines: Zeilen des logFile (leer, wenn nicht lesbar).</summary>
    constructor Create(const AProcess: ICompilerProcess; const ALogger: ILogger; const APowerShell: string;
      const AIdes: TShellIdeIdsFunc; const ARunning: TShellIdeRunningFunc; const AReadLines: TShellReadLinesFunc);
    /// <summary>Baut AProject in der eigenen IDE (startet sie bei Bedarf). False mit Grund in AError, wenn keine
    /// eigene IDE bereitsteht oder cc.ps1 nicht antwortet. ASucceeded: "ok" von cc.ps1.</summary>
    function Build(const AScript, AProject, APlatform: string; out AMessages: TArray<TCompilerMessage>;
      out ASucceeded: Boolean; out AError: string): Boolean;
    /// <summary>Beendet die eigene IDE (cc.ps1 quit -Instance) über AProcess, z. B. einen neuen Läufer, wenn der
    /// eigene schon abgebrochen ist.</summary>
    procedure Quit(const AProcess: ICompilerProcess);
    /// <summary>pid der eigenen IDE; 0 = keine.</summary>
    property Pid: Cardinal read FPid;
  end;

implementation

uses
  System.IOUtils,
  System.DateUtils,
  Atlas.Common.Projects.Paths,
  Atlas.Common.Compiler.IdeCommand,
  Atlas.Text.LogMarks,
  Atlas.Common.Localization.Texts;

type
{$SCOPEDENUMS ON}
  TIdeCompilerText = (NoIde, ForeignIde, NoResult);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TIdeCompilerText] of TAtlasText = (
    (De: 'cc.ps1 start hat keine IDE gestartet (Exit-Code %d)';
    En: 'cc.ps1 start did not start an IDE (exit code %d)'),
    (De: 'cc.ps1 start nannte die schon laufende IDE %d; Atlas baut nur in einer eigenen IDE';
    En: 'cc.ps1 start named the already running IDE %d; Atlas only builds in an IDE of its own'),
    (De: 'cc.ps1 build hat kein Ergebnis geliefert (Exit-Code %d)';
    En: 'cc.ps1 build returned no result (exit code %d)'));

{ TShellCompilerEditions }

constructor TShellCompilerEditions.Create(const AProcess: ICompilerProcess; const ALogger: ILogger;
  const AFileName: string);
begin
  inherited Create;
  FProcess := AProcess;
  FLogger := ALogger;
  FFileName := AFileName;
  FLock := TObject.Create;
  FCache := TCompilerEditionCache.Create;
end;

destructor TShellCompilerEditions.Destroy;
begin
  FCache.Free;
  FLock.Free;
  inherited;
end;

class function TShellCompilerEditions.DefaultFile: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'),
    TCompilerEditionCache.cFileName);
end;

class function TShellCompilerEditions.StampOf(const AFileName: string): string;
begin
  Result := '';
  try
    if TFile.Exists(AFileName) then
    begin
      Result := Format('%d-%s', [TFile.GetSize(AFileName),
        DateToISO8601(TFile.GetLastWriteTimeUtc(AFileName), True)]);
    end;
  except
    on Exception do
      Result := '';
  end;
end;

procedure TShellCompilerEditions.EnsureLoaded;
begin
  if FLoaded then
  begin
    Exit;
  end;
  FLoaded := True;
  if (FFileName = '') or not TFile.Exists(FFileName) then
  begin
    Exit;
  end;
  try
    FCache.Load(TFile.ReadAllText(FFileName, TEncoding.UTF8));
  except
    on E: Exception do
      FLogger.Warning('Erkannte Delphi-Ausgaben nicht lesbar: ' + E.ClassName);
  end;
end;

procedure TShellCompilerEditions.Save;
begin
  if FFileName = '' then
  begin
    Exit;
  end;
  try
    ForceDirectories(ExtractFileDir(FFileName));
    TFile.WriteAllText(FFileName, FCache.ToJson, TEncoding.UTF8);
  except
    on E: Exception do
      FLogger.Warning('Erkannte Delphi-Ausgaben nicht gespeichert: ' + E.ClassName);
  end;
end;

procedure TShellCompilerEditions.Store(const ABdsRoot, AVersion, AStamp: string; AEdition: TCompilerEdition);
var
  mEntry: TCompilerEditionEntry;
begin
  mEntry := Default(TCompilerEditionEntry);
  mEntry.Root := ABdsRoot;
  mEntry.Version := AVersion;
  mEntry.Edition := AEdition;
  mEntry.Stamp := AStamp;
  mEntry.Checked := DateToISO8601(Now, False);
  FCache.Store(mEntry);
  Save;
end;

function TShellCompilerEditions.Resolve(const ABdsRoot, AVersion, AExecutable: string): TCompilerEdition;
var
  mStamp: string;
  mOutput: TArray<string>;
  mRequest: TCompilerRequest;
  mExists: Boolean;
begin
  mStamp := StampOf(AExecutable);
  TMonitor.Enter(FLock);
  try
    EnsureLoaded;
    Result := FCache.Find(ABdsRoot, AVersion, mStamp);
    if Result <> TCompilerEdition.Unknown then
    begin
      Exit;
    end;
    mExists := mStamp <> '';
    mOutput := nil;
    if mExists then
    begin
      // Ohne Argumente nennt sich dcc mit Kopfzeile und Aufrufhilfe; Starter und Community melden den Lizenztext.
      mRequest := Default(TCompilerRequest);
      mRequest.Executable := AExecutable;
      mRequest.WorkingDir := ExtractFileDir(AExecutable);
      try
        FProcess.Run(mRequest,
          procedure(const ALine: string)
          begin
            mOutput := mOutput + [ALine];
          end);
      except
        on E: ECompilerCancelled do
          raise;
        on E: Exception do
          FLogger.Warning('Probelauf des Compilers fehlgeschlagen: ' + E.ClassName);
      end;
    end;
    Result := TCompilerEditions.Detect(mExists, mOutput);
    FLogger.Info(Format('Delphi %s: %s', [AVersion, TCompilerEditions.Describe(Result)]));
    // Unklar (keine Ausgabe) wird nicht gemerkt; der nächste Lauf prüft erneut.
    if Result <> TCompilerEdition.Unknown then
    begin
      Store(ABdsRoot, AVersion, mStamp, Result);
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TShellCompilerEditions.Remember(const ABdsRoot, AVersion, AExecutable: string; AEdition: TCompilerEdition);
begin
  TMonitor.Enter(FLock);
  try
    EnsureLoaded;
    Store(ABdsRoot, AVersion, StampOf(AExecutable), AEdition);
  finally
    TMonitor.Exit(FLock);
  end;
end;

{ TShellIdeCompiler }

constructor TShellIdeCompiler.Create(const AProcess: ICompilerProcess; const ALogger: ILogger;
  const APowerShell: string; const AIdes: TShellIdeIdsFunc; const ARunning: TShellIdeRunningFunc;
  const AReadLines: TShellReadLinesFunc);
begin
  inherited Create;
  FProcess := AProcess;
  FLogger := ALogger;
  FPowerShell := APowerShell;
  FIdes := AIdes;
  FRunning := ARunning;
  FReadLines := AReadLines;
end;

function TShellIdeCompiler.Run(const AProcess: ICompilerProcess; const AScript: string;
  const AArguments: TArray<string>; const AWorkingDir: string; out AOutput: TArray<string>): Integer;
var
  mLines: TArray<string>;
begin
  mLines := nil;
  Result := AProcess.Run(TCompilerIdeCommand.Request(FPowerShell, AScript, AArguments, AWorkingDir),
    procedure(const ALine: string)
    begin
      mLines := mLines + [ALine];
    end);
  AOutput := mLines;
end;

function TShellIdeCompiler.EnsureInstance(const AScript, AProject: string; out AError: string): Boolean;
var
  mOutput: TArray<string>;
  mRunning: TArray<Cardinal>;
  mPid, mOther: Cardinal;
  mCode: Integer;
begin
  AError := '';
  // Eigene Instanz wiederverwenden, solange sie läuft und zum selben cc.ps1 gehört.
  if (FPid <> 0) and SameText(FScript, AScript) and FRunning(FPid) then
  begin
    Exit(True);
  end;
  if (FPid <> 0) and FRunning(FPid) then
  begin
    Quit(FProcess);
  end;
  FPid := 0;
  mRunning := FIdes();
  mCode := Run(FProcess, AScript, TCompilerIdeCommand.StartArguments(AProject),
    TProjectPaths.DirectoryOf(AProject), mOutput);
  if not TCompilerIdeCommand.ParsePid(mOutput, mPid) then
  begin
    AError := cTexts[TIdeCompilerText.NoIde].Fmt([mCode]);
    Exit(False);
  end;
  for mOther in mRunning do
  begin
    if mOther = mPid then
    begin
      // Nie in eine fremde IDE bauen, etwa die des Benutzers (ADR 0007).
      AError := cTexts[TIdeCompilerText.ForeignIde].Fmt([mPid]);
      Exit(False);
    end;
  end;
  FPid := mPid;
  FScript := AScript;
  FLogger.Info(Format('Eigene IDE für das Kompilieren gestartet (pid %d)', [mPid]));
  Result := True;
end;

function TShellIdeCompiler.Build(const AScript, AProject, APlatform: string; out AMessages: TArray<TCompilerMessage>;
  out ASucceeded: Boolean; out AError: string): Boolean;
var
  mOutput, mLines: TArray<string>;
  mReport: TIdeBuildReport;
  mCode: Integer;
  mDetail: string;
begin
  AMessages := nil;
  ASucceeded := False;
  if not EnsureInstance(AScript, AProject, AError) then
  begin
    Exit(False);
  end;
  mCode := Run(FProcess, AScript, TCompilerIdeCommand.BuildArguments(FPid, AProject, APlatform),
    TProjectPaths.DirectoryOf(AProject), mOutput);
  if not TCompilerIdeCommand.ParseBuild(mOutput, mReport) then
  begin
    // Ist die eigene IDE weg, startet der nächste Lauf eine neue.
    if not FRunning(FPid) then
    begin
      FPid := 0;
    end;
    AError := cTexts[TIdeCompilerText.NoResult].Fmt([mCode]);
    Exit(False);
  end;
  mLines := nil;
  if mReport.LogFile <> '' then
  begin
    mLines := FReadLines(mReport.LogFile);
  end;
  AMessages := TCompilerIdeCommand.Messages(mLines, AProject);
  ASucceeded := mReport.Ok;
  if not mReport.Ok and (Length(AMessages) = 0) then
  begin
    // ADR 0007: cc.ps1 kann Fehlertexte der IDE nicht immer lesen; dann steht im Log nur „Misslungen“.
    mDetail := '';
    if mReport.Error <> '' then
    begin
      mDetail := ': ' + TLogMarks.Text(mReport.Error);
    end;
    FLogger.Warning('Build über die IDE misslungen, ohne lesbare Meldungen' + mDetail);
  end;
  Result := True;
end;

procedure TShellIdeCompiler.Quit(const AProcess: ICompilerProcess);
var
  mOutput: TArray<string>;
begin
  if FPid = 0 then
  begin
    Exit;
  end;
  try
    if FRunning(FPid) then
    begin
      Run(AProcess, FScript, TCompilerIdeCommand.QuitArguments(FPid), '', mOutput);
    end;
  except
    on E: Exception do
      FLogger.Warning('Eigene IDE nicht beendet: ' + E.ClassName);
  end;
  FPid := 0;
end;

initialization
  TAtlasTextTables.Add('Shell.Compiler', cTexts);

end.
