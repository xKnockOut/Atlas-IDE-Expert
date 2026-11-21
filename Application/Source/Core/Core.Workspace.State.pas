unit Core.Workspace.State;

// Host-Rolle Core: Stand des zuletzt geladenen Projekts eines Arbeitsbereichs, den Anfrage-Threads lesen:
// Projekt und Installation (#40, #47), Symbole, Namespaces und Dateien des Index (#648), Unit-Suche (#1016) und
// Packages (#46, #1220) und der letzte Indexlauf (#28, #492). Alles threadsicher.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Builder,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Checker,
  Core.Workspace.Setup,
  Core.Workspace.Packages;

type
  /// <summary>Für den Compileraufruf (#40): Delphi-Version, $(BDS) und Bibliothekspfade der Installation; leer
  /// ohne Installation.</summary>
  TCoreInstallInfo = record
    DelphiVersion: string;
    BdsRoot: string;
    LibraryPaths: TArray<string>;
  end;

  /// <summary>Was der Indexaufbau über die Dateien des Projekts festlegt.</summary>
  TCoreIndexedFiles = record
    /// <summary>Dieselben Symbole bestimmen, welche {$IFDEF}-Zweige der Editor abblendet.</summary>
    Defines: TArray<string>;
    Namespaces: TArray<string>;
    SearchPaths: TArray<string>;
    ProjectFiles: TArray<string>;
    /// <summary>Alle Units der Suchpfade im Index (#648).</summary>
    SearchFiles: TArray<string>;
  end;

  /// <summary>Letzter vollständiger Indexlauf (#28) und letzte Änderung am Index (#492).</summary>
  TCoreIndexStats = record
    /// <summary>-1 = noch keiner fertig.</summary>
    LastIndexMs: Int64;
    LastIndex: TIndexBuildResult;
    LastUpdate: TDateTime;
  end;

  TCoreProjectState = class
  private
    FSetup: TCoreWorkspaceSetup;
    FLock: TObject;
    FProject: TProjectInfo;
    FHasProject: Boolean;
    FInstall: TCoreInstallInfo;
    FFiles: TCoreIndexedFiles;
    FHasDefines: Boolean;
    /// <summary>Projektdateien und Suchpfad-Units in Großschreibung, für ContainsFile.</summary>
    FOwnFiles: TDictionary<string, Boolean>;
    /// <summary>Unit-Suche wie beim Compiler für uses-unit-not-found (#1016), je Indexaufbau neu.</summary>
    FUnitLookup: IRuleUnitLookup;
    // Der Locator lebt, solange ihn ein Halter hat (#1220): Arbeitsbereich und die Unit-Suche, die Prüfungen in
    // Anfrage-Threads noch über die Freigabe des Arbeitsbereichs hinaus benutzen können. Frühere bleiben bis zur
    // Freigabe des Arbeitsbereichs.
    FPackages: IPackageLocatorHold;
    FRetiredPackages: TList<IPackageLocatorHold>;
    FStats: TCoreIndexStats;
    /// <summary>Antworten zum Index über alle Units des Arbeitsbereichs (TIndexNameFacts); lebt mit ihm.</summary>
    FNameFacts: IIndexNameFacts;
    FProjectPending: Boolean;
    FWithoutProject: Boolean;
  public
    constructor Create(ASetup: TCoreWorkspaceSetup);
    destructor Destroy; override;
    procedure SetProject(const AProject: TProjectInfo; const AInstall: TCoreInstallInfo);
    procedure SetLookups(const APackages: IPackageLocatorHold; const AUnitLookup: IRuleUnitLookup);
    procedure SetIndexedFiles(const AFiles: TCoreIndexedFiles);
    /// <summary>Vollständiger Indexlauf (nicht abgebrochen) nach AElapsedMs.</summary>
    procedure Finished(const AResult: TIndexBuildResult; AElapsedMs: Int64);
    /// <summary>Änderung am Index (Speichern, Tipp-Pause).</summary>
    procedure Touch;
    function Stats: TCoreIndexStats;
    /// <summary>Geladenes Projekt; False ohne Projekt.</summary>
    function Project(out AProject: TProjectInfo): Boolean;
    function Install: TCoreInstallInfo;
    /// <summary>Symbole des Projekts für das Abblenden; False ohne Projekt.</summary>
    function Defines(out ADefines: TArray<string>): Boolean;
    /// <summary>Für das Projekt gewählte Delphi-Version (z. B. "23.0", #47); '' ohne Installation.</summary>
    function DelphiVersion: string;
    /// <summary>Ordner der Delphi-Installation ($(BDS)); '' ohne Installation.</summary>
    function BdsRoot: string;
    /// <summary>Unit-Namespaces des Projekts.</summary>
    function Namespaces: TArray<string>;
    /// <summary>Suchpfade für Include-Dateien (#264): Projekt-Suchpfade, dann Bibliothekspfade.</summary>
    function IncludePaths: TArray<string>;
    /// <summary>Quelltexte des Projekts (Hauptdatei, Units).</summary>
    function ProjectFiles: TArray<string>;
    /// <summary>True, wenn AFileName zum Projekt gehört (DCCReference, Hauptdatei oder Suchpfad-Unit).</summary>
    function ContainsFile(const AFileName: string): Boolean;
    /// <summary>Feste Projektdatei oder die des geladenen Projekts; '' ohne Projekt.</summary>
    function ProjectFileName: string;
    /// <summary>Unit-Suche des zuletzt geladenen Projekts (#1016); nil vor dem ersten Laden.</summary>
    function UnitLookup: IRuleUnitLookup;
    /// <summary>Package-Locator des zuletzt geladenen Projekts (#46); nil vor dem ersten Laden.</summary>
    function Packages: IPackageLocatorHold;
    /// <summary>Symbole und Include-Dateien des Projekts für die Regelprüfung von AFileName (#860); ohne
    /// Projekt die Vordefinitionen, $I dann nur im Ordner der Datei.</summary>
    function CheckSource(const AFileName: string): TCheckSource;
    /// <summary>Projekt für projektweite Regeln (#1102) mit Datei und Quelltexten, dazu der Hauptquelltext;
    /// False ohne geladenes Projekt. Liest keine Dateien; Art, Test-Projekt und Formulare ergänzt
    /// TRuleProjectFiles.ProjectOf außerhalb von Sperren.</summary>
    function RuleProject(out AProject: TRuleProject; out AMainSource: string): Boolean;
    property NameFacts: IIndexNameFacts read FNameFacts;
    /// <summary>True, solange ein Aufbau die Projektstufe noch nicht hinter sich hat.</summary>
    property ProjectPending: Boolean read FProjectPending write FProjectPending;
    /// <summary>Der letzte Aufbau hat entschieden, ohne Projekt zu indizieren (keine oder fehlende Projektdatei,
    /// index.projectGroup aus und noch nicht aktiviert); dann wartet keine Prüfung auf ein Projekt (#1220).</summary>
    property WithoutProject: Boolean read FWithoutProject write FWithoutProject;
  end;

implementation

uses
  Atlas.Common.Index.NameFacts,
  Atlas.Common.Pascal.IncludeFiles;

{ TCoreProjectState }

constructor TCoreProjectState.Create(ASetup: TCoreWorkspaceSetup);
begin
  inherited Create;
  FSetup := ASetup;
  FLock := TObject.Create;
  FOwnFiles := TDictionary<string, Boolean>.Create;
  FRetiredPackages := TList<IPackageLocatorHold>.Create;
  FNameFacts := TIndexNameFacts.Create;
  FStats.LastIndexMs := -1;
end;

destructor TCoreProjectState.Destroy;
begin
  FUnitLookup := nil;
  FPackages := nil;
  FRetiredPackages.Free;
  FOwnFiles.Free;
  FLock.Free;
  inherited;
end;

procedure TCoreProjectState.SetProject(const AProject: TProjectInfo; const AInstall: TCoreInstallInfo);
begin
  TMonitor.Enter(FLock);
  try
    FProject := AProject;
    FHasProject := True;
    FInstall := AInstall;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TCoreProjectState.SetLookups(const APackages: IPackageLocatorHold; const AUnitLookup: IRuleUnitLookup);
begin
  TMonitor.Enter(FLock);
  try
    if FPackages <> nil then
    begin
      FRetiredPackages.Add(FPackages);
    end;
    FPackages := APackages;
    FUnitLookup := AUnitLookup;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TCoreProjectState.SetIndexedFiles(const AFiles: TCoreIndexedFiles);
var
  mFileName: string;
begin
  TMonitor.Enter(FLock);
  try
    FFiles := AFiles;
    FHasDefines := True;
    FOwnFiles.Clear;
    for mFileName in AFiles.ProjectFiles + AFiles.SearchFiles do
    begin
      FOwnFiles.AddOrSetValue(AnsiUpperCase(mFileName), True);
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TCoreProjectState.Finished(const AResult: TIndexBuildResult; AElapsedMs: Int64);
begin
  TMonitor.Enter(FLock);
  try
    FStats.LastIndexMs := AElapsedMs;
    FStats.LastIndex := AResult;
    FStats.LastUpdate := Now;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TCoreProjectState.Touch;
begin
  TMonitor.Enter(FLock);
  try
    FStats.LastUpdate := Now;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TCoreProjectState.Stats: TCoreIndexStats;
begin
  TMonitor.Enter(FLock);
  try
    Result := FStats;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TCoreProjectState.Project(out AProject: TProjectInfo): Boolean;
begin
  TMonitor.Enter(FLock);
  try
    Result := FHasProject;
    AProject := Default(TProjectInfo);
    if Result then
    begin
      AProject := FProject;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TCoreProjectState.Install: TCoreInstallInfo;
begin
  TMonitor.Enter(FLock);
  try
    Result := FInstall;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TCoreProjectState.Defines(out ADefines: TArray<string>): Boolean;
begin
  TMonitor.Enter(FLock);
  try
    ADefines := FFiles.Defines;
    Result := FHasDefines;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TCoreProjectState.DelphiVersion: string;
begin
  Result := Install.DelphiVersion;
end;

function TCoreProjectState.BdsRoot: string;
begin
  Result := Install.BdsRoot;
end;

function TCoreProjectState.Namespaces: TArray<string>;
begin
  TMonitor.Enter(FLock);
  try
    Result := FFiles.Namespaces;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TCoreProjectState.IncludePaths: TArray<string>;
begin
  TMonitor.Enter(FLock);
  try
    Result := FFiles.SearchPaths + FInstall.LibraryPaths;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TCoreProjectState.ProjectFiles: TArray<string>;
begin
  TMonitor.Enter(FLock);
  try
    Result := FFiles.ProjectFiles;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TCoreProjectState.ContainsFile(const AFileName: string): Boolean;
begin
  TMonitor.Enter(FLock);
  try
    Result := FOwnFiles.ContainsKey(AnsiUpperCase(AFileName));
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TCoreProjectState.ProjectFileName: string;
begin
  TMonitor.Enter(FLock);
  try
    Result := FSetup.ProjectFile;
    if (Result = '') and FHasProject then
    begin
      Result := FProject.FileName;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TCoreProjectState.UnitLookup: IRuleUnitLookup;
begin
  TMonitor.Enter(FLock);
  try
    Result := FUnitLookup;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TCoreProjectState.Packages: IPackageLocatorHold;
begin
  TMonitor.Enter(FLock);
  try
    Result := FPackages;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TCoreProjectState.CheckSource(const AFileName: string): TCheckSource;
var
  mSymbols: TArray<string>;
begin
  if not Defines(mSymbols) then
  begin
    mSymbols := nil;
  end;
  Result := TCheckSource.Create(AFileName, mSymbols, TIncludeFiles.Resolver(IncludePaths));
end;

function TCoreProjectState.RuleProject(out AProject: TRuleProject; out AMainSource: string): Boolean;
var
  mInfo: TProjectInfo;
begin
  AProject := Default(TRuleProject);
  AMainSource := '';
  Result := Project(mInfo);
  if not Result then
  begin
    Exit;
  end;
  AProject.FileName := ProjectFileName;
  AProject.Sources := ProjectFiles;
  AMainSource := mInfo.MainSource;
end;

end.
