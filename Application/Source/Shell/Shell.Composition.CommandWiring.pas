unit Shell.Composition.CommandWiring;

// Verdrahtung von workspace/executeCommand: Teilwurzel Befehle mit Status- und Server-Diensten, die nur
// die Teile der Komposition kennen. Closures fragen die Teile erst beim Aufruf, weil IDE, Mitschnitt und
// Anonymisierer später entstehen.

interface

uses
  Shell.Composition.Status.Contract,
  Shell.Composition.ServerCommands,
  Shell.Composition.Parts;

type
  /// <summary>Legt die Teilwurzel Befehle in den Teilen an.</summary>
  TShellCommandWiring = class abstract
  private
    /// <summary>Teil von Commands: Status-Dienste, die nur die Komposition kennt.</summary>
    class procedure Status(AParts: TShellParts; var AServices: TShellStatusServices); static;
    /// <summary>Teil von Commands: Server-Befehle, die nur die Komposition kennt.</summary>
    class procedure Server(AParts: TShellParts; var AServices: TShellServerCommandServices); static;
  public
    /// <summary>workspace/executeCommand: alle Befehle des Servers.</summary>
    class procedure Commands(AParts: TShellParts); static;
  end;

implementation

uses
  Atlas.Common.JsonRpc.TracingTransport,
  Atlas.Common.Logging.Providers.RecentSink,
  Atlas.Common.Diagnostics.Anonymizer,
  Atlas.Common.Diagnostics.CheckProfile,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Compiler.Backend,
  Atlas.Common.Lsp.Status,
  Atlas.Common.Lsp.WorkspaceCheck,
  Shell.Composition.CommandArea;

class procedure TShellCommandWiring.Commands(AParts: TShellParts);
var
  mServices: TShellCommandAreaServices;
begin
  mServices := Default(TShellCommandAreaServices);
  mServices.Logger := AParts.Channel.Logger;
  mServices.Dispatcher := AParts.Protocol.Dispatcher;
  Status(AParts, mServices.Status);
  Server(AParts, mServices.Server);
  mServices.Editor.Documents := AParts.Documents;
  mServices.Editor.Index := AParts.Index;
  mServices.Editor.ResourceStringWrite := AParts.EditingArea.Slash.ResourceStringWrite;
  mServices.UnitSearch.Index := AParts.Index;
  mServices.UnitSearch.UsesContextFor :=
    function(const AUri: string; out AContext: TUsesContext): Boolean
    begin
      Result := AParts.UsesContextFor(AUri, AContext);
    end;
  mServices.UnitSearch.Process :=
    function: ICompilerProcess
    begin
      Result := AParts.CompilerProcess;
    end;
  mServices.RuntimeReport.Results := AParts.RuntimeReports;
  mServices.RuntimeReport.Publish :=
    procedure(const AFiles: TArray<string>)
    begin
      AParts.DiagnosticsArea.Syntax.RefreshFiles(AFiles);
    end;
  AParts.CommandArea := TShellCommandArea.Create(AParts.Core, AParts.CodeArea, AParts.AnalysisArea,
    AParts.EditingArea.Editing, mServices);
end;

class procedure TShellCommandWiring.Status(AParts: TShellParts; var AServices: TShellStatusServices);
begin
  AServices.Index := AParts.Index;
  AServices.Documents := AParts.Documents;
  AServices.Statistics := AParts.Protocol.Statistics;
  AServices.ActiveProject :=
    function: string
    begin
      Result := AParts.IdeArea.Ide.Project.ActiveProject;
    end;
  // Protokoll, Mitschnitt und Anonymisierung setzt CreateForStdio erst nach dem Anlegen.
  AServices.RecentLog :=
    function: IRecentLogLines
    begin
      Result := AParts.Channel.RecentLog;
    end;
  AServices.Tracing :=
    function: TJsonRpcTracingTransport
    begin
      Result := AParts.Channel.Tracing;
    end;
  AServices.Anonymizer :=
    function: ILogAnonymizer
    begin
      Result := AParts.Channel.Anonymizer;
    end;
  AServices.CompilerStatus :=
    procedure(var AStatus: TServerStatus)
    begin
      AParts.Compile.StatusOf(AStatus);
    end;
  AServices.CheckStatus :=
    procedure(var AStatus: TServerStatus; out AQueue: TWorkspaceCheckQueue)
    begin
      AQueue := Default(TWorkspaceCheckQueue);
      if (AParts.DiagnosticsArea <> nil) and (AParts.DiagnosticsArea.Pull <> nil) then
      begin
        AStatus.CheckRun := AParts.DiagnosticsArea.Pull.Check.Profile(TCheckRunProfile.cTop);
        AQueue := AParts.DiagnosticsArea.Pull.Check.Queue;
      end;
    end;
end;

class procedure TShellCommandWiring.Server(AParts: TShellParts; var AServices: TShellServerCommandServices);
begin
  AServices.Compile :=
    function(const AFileName: string; out AChoice: TCompilerBackendChoice): Boolean
    begin
      Result := AParts.Compile.Start(AFileName, True, AChoice);
    end;
  AServices.ActiveProject :=
    function: string
    begin
      Result := AParts.IdeArea.Ide.Project.ActiveProject;
    end;
  AServices.SetProject :=
    procedure(const AScope, AProject: string)
    begin
      AParts.IdeArea.Selection.SetProject(AScope, AProject);
    end;
  AServices.RetryCrashCase :=
    function(const AUri: string): Integer
    begin
      Result := AParts.Protocol.CrashCases.Retry(AUri);
    end;
  AServices.Recheck :=
    procedure
    begin
      AParts.DiagnosticsArea.Pull.Changed;
    end;
end;

end.
