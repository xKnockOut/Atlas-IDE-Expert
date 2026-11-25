unit Shell.Composition.Platform;

// Host-Rolle Shell: erzeugt die plattformabhängigen Adapter und Provider des Servers (#1109). Unter Windows die
// aus Atlas.Windows und Atlas.Core.VersionControl, unter Linux die aus Atlas.Linux bzw. Adapters.VersionControl.
// Nach der Host-Matrix importiert nur die Shell Adapters und Providers der Platform-Features; die übrigen
// Plattformdienste stehen in Platform.Server.

interface

uses
  System.SysUtils,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Profiling.Contract,
  Atlas.VersionControl.Repository.Contract,
  Core.Workspace.Setup,
  Core.VersionControlChanges,
{$IFDEF MSWINDOWS}
  Atlas.Windows.Compiler.Adapters.ProcessRunner,
  Atlas.Windows.Projects.Adapters.DelphiInstallation;
{$ELSE}
  Atlas.Linux.Compiler.Adapters.ProcessRunner,
  Atlas.Linux.Projects.Adapters.DelphiInstallation;
{$ENDIF}

type
{$IFDEF MSWINDOWS}
  TProcessRunner = Atlas.Windows.Compiler.Adapters.ProcessRunner.TProcessRunner;
  TDelphiInstallation = Atlas.Windows.Projects.Adapters.DelphiInstallation.TDelphiInstallation;
{$ELSE}
  TProcessRunner = Atlas.Linux.Compiler.Adapters.ProcessRunner.TProcessRunner;
  TDelphiInstallation = Atlas.Linux.Projects.Adapters.DelphiInstallation.TDelphiInstallation;
{$ENDIF}

  /// <summary>Erzeuger der plattformabhängigen Adapter, die keinen eigenen Typalias haben.</summary>
  TShellPlatformAdapters = record
  public
    /// <summary>Senke für Debug-Ausgaben an den Debugger (Windows: OutputDebugString); nil unter Linux, wo
    /// stderr schon das Protokoll des Servers trägt.</summary>
    class function DebugLogSink: ILogSink; static;
    /// <summary>Prozessläufer für git und svn.</summary>
    class function CreateVcsRunner(AAllowMainThread: Boolean; const ACancelled: TFunc<Boolean>): IAtlasVcsRunner;
      static;
    /// <summary>Prober des Stichproben-Profilers (#2057); nil unter Linux, wo es keinen gibt.</summary>
    class function ProfileSampler: IAtlasProfileSampler; static;
    /// <summary>Installation, Dateizugriff des Index und Unit-Suche für die Arbeitsbereiche.</summary>
    class function WorkspaceFactories: TCoreWorkspaceFactories; static;
    /// <summary>git und svn für Kommandozeile und Server: neuer Prozess, Prozessläufer der gemeinsamen Umsetzung
    /// (der Hauptthread darf warten, ohne Abbruch) und ihr Erzeuger.</summary>
    class function VcsAccess: TCoreVcsAccess; static;
  end;

implementation

uses
  Atlas.Common.Projects.Contract,
  Atlas.Common.Projects.Contract.UnitLookup,
  Atlas.Common.Projects.UnitLookup,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Providers.DiskFileSystem,
  Atlas.Common.Projects.Contract.Group,
  Atlas.Common.Architecture.UsesService,
  Atlas.Common.Architecture.Adapters.GroupFiles,
  Atlas.VersionControl.Repository.Composition,
{$IFDEF MSWINDOWS}
  Atlas.Windows.Diagnostics.Adapters.DebugOutputSink,
  Atlas.Windows.Profiling.Adapters.Sampler,
  Atlas.VersionControl.Repository.Providers.ProcessRunner;
{$ELSE}
  Adapters.VersionControl.LinuxRunner;
{$ENDIF}

function InstalledVersions: TArray<string>;
begin
  Result := TDelphiInstallation.Versions;
end;

function InstallationOf(const AVersion: string): ILibraryPathProvider;
begin
  Result := TDelphiInstallation.Create(AVersion);
end;

function NewIndexFileSystem: IIndexFileSystem;
begin
  Result := TDiskIndexFileSystem.Create;
end;

function UnitLookupOf(const ASetup: TUnitLookupSetup): IUnitLookup;
begin
  Result := TUnitLookup.Create(ASetup);
end;

function GroupFilesOf(const AProjects: TArray<TGroupProject>; const AIndex: ISymbolIndex;
  const AReadText: TProjectReadText; const AComplete: TProjectGroupComplete;
  AUsesGraph: TUsesGraphService): IProjectGroupFiles;
begin
  Result := TProjectGroupFiles.Create(AProjects, AIndex, AReadText, AComplete, AUsesGraph);
end;

function OpenVersionControl(const AWorkingCopy: TAtlasVcsWorkingCopy; const ARunner: IAtlasVcsRunner;
  const AExecutable: string; ATimeoutMs: Cardinal): IAtlasVersionControl;
begin
  Result := TAtlasVersionControl.ForWorkingCopy(AWorkingCopy, ARunner, AExecutable, ATimeoutMs);
end;

{ TShellPlatformAdapters }

class function TShellPlatformAdapters.DebugLogSink: ILogSink;
begin
{$IFDEF MSWINDOWS}
  Result := TDebugOutputLogSink.Create;
{$ELSE}
  Result := nil;
{$ENDIF}
end;

class function TShellPlatformAdapters.CreateVcsRunner(AAllowMainThread: Boolean;
  const ACancelled: TFunc<Boolean>): IAtlasVcsRunner;
begin
{$IFDEF MSWINDOWS}
  Result := TAtlasVcsProcessRunner.Create(AAllowMainThread, ACancelled);
{$ELSE}
  Result := TLinuxVcsRunner.Create(AAllowMainThread, ACancelled);
{$ENDIF}
end;

class function TShellPlatformAdapters.ProfileSampler: IAtlasProfileSampler;
begin
{$IFDEF MSWINDOWS}
  Result := TAtlasWindowsProfileSampler.Create;
{$ELSE}
  Result := nil;
{$ENDIF}
end;

class function TShellPlatformAdapters.WorkspaceFactories: TCoreWorkspaceFactories;
begin
  Result := Default(TCoreWorkspaceFactories);
  Result.InstalledVersions := InstalledVersions;
  Result.Installation := InstallationOf;
  Result.IndexFileSystem := NewIndexFileSystem;
  Result.UnitLookup := UnitLookupOf;
  Result.GroupFiles := GroupFilesOf;
end;

class function TShellPlatformAdapters.VcsAccess: TCoreVcsAccess;
begin
  Result := Default(TCoreVcsAccess);
  Result.Process := TProcessRunner.Create;
  Result.Runner := CreateVcsRunner(True, nil);
  Result.Open := OpenVersionControl;
end;

end.
