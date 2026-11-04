unit Shell.Composition.CompileSetup;

// Baut den Compile-Host der Komposition: Editionen je Installation, eigene IDE über cc.ps1 (#261), Fortschritt und
// den Auftrag zum Projekt einer Datei.

interface

uses
  Atlas.Common.Logging.Contract,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Compiler.Contract,
  Shell.Compiler,
  Shell.Composition.Compile,
  Shell.Composition.Workspaces;

type
  TShellCompileWorkspacesFunc = reference to function: TShellWorkspaceRegistry;

  /// <summary>Was der Compile-Host von der Komposition braucht.</summary>
  TShellCompileSetupServices = record
    Logger: ILogger;
    Transport: IJsonRpcTransport;
    Process: ICompilerProcess;
    /// <summary>Fragt erst beim Auftrag: Die Arbeitsbereiche entstehen nach dem Compile-Host.</summary>
    Workspaces: TShellCompileWorkspacesFunc;
    /// <summary>Meldungen der Dateien neu veröffentlichen.</summary>
    Publish: TShellCompilePublish;
  end;

  /// <summary>Legt den Compile-Host an.</summary>
  TShellCompileSetup = class
  public
    class function NewHost(const AServices: TShellCompileSetupServices): TShellCompileHost; static;
    /// <summary>Auftrag für das Projekt zu AFileName ('' = einziger Ordner); False ohne Projekt oder Installation
    /// (Grund in AError).</summary>
    class function JobFor(AWorkspaces: TShellWorkspaceRegistry; const AFileName: string; out AJob: TShellCompileJob;
      out AError: string): Boolean; static;
    /// <summary>PowerShell für cc.ps1 (#261): pwsh aus PATH, sonst Windows PowerShell. Der Prozessläufer
    /// durchsucht PATH nicht selbst.</summary>
    class function PowerShellProgram: string; static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Lsp.WorkDoneProgress,
  Shell.Platform,
  Shell.VcsChanges,
  Shell.Workspace;

function RunningIdes: TArray<Cardinal>;
begin
  Result := TProcessInstances.IdsOf('bds.exe');
end;

function IdeRunning(APid: Cardinal): Boolean;
begin
  Result := TProcessInstances.Running(APid);
end;

class function TShellCompileSetup.PowerShellProgram: string;
begin
  Result := TVcsChanges.FindProgram('pwsh');
  if SameText(Result, 'pwsh') then
  begin
    Result := TVcsChanges.FindProgram('powershell');
  end;
  if SameText(Result, 'powershell') then
  begin
    Result := TPath.Combine(GetEnvironmentVariable('SystemRoot'), 'System32\WindowsPowerShell\v1.0\powershell.exe');
  end;
end;

class function TShellCompileSetup.JobFor(AWorkspaces: TShellWorkspaceRegistry; const AFileName: string;
  out AJob: TShellCompileJob; out AError: string): Boolean;
var
  mWorkspace: TShellWorkspace;
begin
  AJob := Default(TShellCompileJob);
  AError := '';
  System.TMonitor.Enter(AWorkspaces.Lock);
  try
    mWorkspace := nil;
    if AFileName <> '' then
    begin
      mWorkspace := AWorkspaces.WorkspaceOf(AFileName);
    end;
    mWorkspace := TShellWorkspaces.Choose(mWorkspace, AWorkspaces.Items);
    if mWorkspace = nil then
    begin
      AError := 'Kein Ordner mit Projekt geöffnet';
    end
    else if mWorkspace.CompileJob(AJob, AError) then
    begin
      AError := '';
    end;
  finally
    System.TMonitor.Exit(AWorkspaces.Lock);
  end;
  Result := AError = '';
end;

class function TShellCompileSetup.NewHost(const AServices: TShellCompileSetupServices): TShellCompileHost;
var
  mServices: TShellCompileServices;
  mLogger: ILogger;
  mWorkspaces: TShellCompileWorkspacesFunc;
begin
  mLogger := AServices.Logger;
  mWorkspaces := AServices.Workspaces;
  mServices := Default(TShellCompileServices);
  // Starter Edition ohne dcc (#261): Ausgabe je Installation erkennen und merken; eigene IDE über cc.ps1.
  mServices.Editions := TShellCompilerEditions.Create(AServices.Process, mLogger, TShellCompilerEditions.DefaultFile);
  mServices.IdeCompiler := TShellIdeCompiler.Create(AServices.Process, mLogger, PowerShellProgram, RunningIdes,
    IdeRunning,
    function(const AFileName: string): TArray<string>
    begin
      Result := nil;
      try
        if TFile.Exists(AFileName) then
        begin
          Result := TFileEncoding.LoadLines(AFileName);
        end;
      except
        on E: Exception do
          mLogger.Warning('Build-Log der IDE nicht lesbar: ' + E.ClassName);
      end;
    end);
  mServices.Logger := mLogger;
  mServices.Transport := AServices.Transport;
  mServices.Process := AServices.Process;
  mServices.Progress := TLspWorkDoneProgress.Create(AServices.Transport, 'atlas-compile');
  mServices.JobFor :=
    function(const AFileName: string; out AJob: TShellCompileJob; out AError: string): Boolean
    begin
      Result := JobFor(mWorkspaces(), AFileName, AJob, AError);
    end;
  mServices.Publish := AServices.Publish;
  Result := TShellCompileHost.Create(mServices);
end;

end.
