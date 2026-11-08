unit Shell.Composition.CompileSetup;

// Baut den Compile-Host der Komposition: Editionen je Installation (#261), Fortschritt und den Auftrag zum
// Projekt einer Datei.

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
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Lsp.WorkDoneProgress,
  Shell.Workspace,
  Atlas.Common.Localization.Texts;

type
{$SCOPEDENUMS ON}
  TCompileSetupText = (NoFolder);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TCompileSetupText] of TAtlasText = (
    (De: 'Kein Ordner mit Projekt geöffnet'; En: 'No folder with a project open'));

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
      AError := cTexts[TCompileSetupText.NoFolder].Text;
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
  // Starter Edition ohne dcc (#261): Ausgabe je Installation erkennen und merken.
  mServices.Editions := TShellCompilerEditions.Create(AServices.Process, mLogger, TShellCompilerEditions.DefaultFile);
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

initialization
  TAtlasTextTables.Add('Shell.Composition.CompileSetup', cTexts);

end.
