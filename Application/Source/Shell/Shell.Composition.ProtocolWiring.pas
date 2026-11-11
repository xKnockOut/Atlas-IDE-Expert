unit Shell.Composition.ProtocolWiring;

// Verdrahtung von Protokoll und Dokumenten: Teilwurzel Protokoll mit Verteiler, Watchdog und
// Lebenszyklus; Dokumentspeicher, Synchronisation, Absturzfälle, Compilerläufe und die Teilwurzel Diagnosen.
// Closures fragen die Teile erst beim Aufruf, weil Kern, Index und Sitzung später entstehen.

interface

uses
  Shell.Composition.Parts;

type
  /// <summary>Legt Protokoll, Dokumente, Compilerläufe und Diagnosen in den Teilen an.</summary>
  TShellProtocolWiring = class abstract
  private
    /// <summary>Teil von Documents (#1355): Absturzfälle und Sicherheitsnetz mit Dokumenten, Einstellungen
    /// und Benachrichtigung an den Client.</summary>
    class procedure CrashCases(AParts: TShellParts); static;
    /// <summary>Teil von Documents: Compilerläufe (#40, #261) mit dem Kommandozeilen-Compiler.</summary>
    class procedure Compile(AParts: TShellParts); static;
    /// <summary>Teil von Documents: Syntax- und Pull-Diagnosen, Compilerergebnisse.</summary>
    class procedure Diagnostics(AParts: TShellParts); static;
  public
    /// <summary>Teilwurzel Protokoll mit Verteiler, Watchdog und Lebenszyklus.</summary>
    class procedure Protocol(AParts: TShellParts); static;
    /// <summary>Dokumentspeicher, Synchronisation, Absturzfälle, Compilerläufe und Diagnosen.</summary>
    class procedure Documents(AParts: TShellParts); static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.JSON,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.TextDocumentSync,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Compiler.Contract,
  Shell.Platform,
  Shell.Workspace,
  Shell.Composition.Core,
  Shell.Composition.Workspaces,
  Shell.Composition.Capabilities,
  Shell.Composition.Protocol,
  Shell.Composition.CompileSetup,
  Shell.Composition.DiagnosticsArea;

/// <summary>Kanonischer Pfad für den Dokumentspeicher.</summary>
function CanonicalPath(const APath: string): string;
begin
  Result := TShellPlatform.CanonicalizePath(APath);
end;

class procedure TShellProtocolWiring.Protocol(AParts: TShellParts);
var
  mServices: TShellProtocolServices;
begin
  mServices.Logger := AParts.Channel.Logger;
  mServices.TimeoutMs := TShellParts.cRequestTimeoutMs;
  mServices.Capabilities :=
    function: TJSONObject
    begin
      Result := TShellCapabilities.Build;
      // Pull-Diagnosen nur für Clients, die sie können; sonst bleibt es bei publishDiagnostics (#82).
      AParts.DiagnosticsArea.ApplyClientCapabilities(AParts.Protocol.Lifecycle.InitializeParams, Result);
    end;
  AParts.Protocol := TShellProtocol.Create(mServices);
end;

class procedure TShellProtocolWiring.Documents(AParts: TShellParts);
begin
  AParts.Documents := TDocumentStore.Create(CanonicalPath);
  AParts.TextDocumentSync := TLspTextDocumentSync.Create(AParts.Documents);
  AParts.TextDocumentSync.Attach(AParts.Protocol.Dispatcher);
  CrashCases(AParts);
  Compile(AParts);
  Diagnostics(AParts);
end;

class procedure TShellProtocolWiring.CrashCases(AParts: TShellParts);
begin
  AParts.Protocol.CreateCrashCases(AParts.Documents,
    function(const AUri: string): TArray<string>
    var
      mCore: TShellCore;
      mWorkspace: TShellWorkspace;
    begin
      Result := nil;
      mCore := AParts.Core;
      if (mCore <> nil) and (mCore.Configuration.GlobalSettingsFile <> '') then
      begin
        Result := Result + [mCore.Configuration.GlobalSettingsFile];
      end;
      if not StartsText('file:', AUri) or (mCore = nil) then
      begin
        Exit;
      end;
      System.TMonitor.Enter(mCore.Workspaces.Lock);
      try
        mWorkspace := mCore.Workspaces.WorkspaceOf(TDocumentUris.ToPath(AUri));
        if mWorkspace <> nil then
        begin
          Result := Result + [ExistingOrLegacyFile(mWorkspace.Root, cConfigurationFileName,
            cLegacyConfigurationFileName)];
        end;
      finally
        System.TMonitor.Exit(mCore.Workspaces.Lock);
      end;
    end,
    procedure(const AMethod: string; AParams: TJSONObject)
    begin
      AParts.NotifyClient(AMethod, AParams);
    end);
end;

class procedure TShellProtocolWiring.Compile(AParts: TShellParts);
var
  mServices: TShellCompileSetupServices;
begin
  AParts.CompilerProcess := TProcessRunner.Create;
  mServices := Default(TShellCompileSetupServices);
  mServices.Logger := AParts.Channel.Logger;
  mServices.Transport := AParts.Channel.Transport;
  mServices.Process := AParts.CompilerProcess;
  mServices.Workspaces :=
    function: TShellWorkspaceRegistry
    begin
      Result := AParts.Core.Workspaces;
    end;
  mServices.Publish :=
    procedure(const AFiles: TArray<string>)
    begin
      AParts.DiagnosticsArea.Syntax.RefreshFiles(AFiles);
    end;
  AParts.Compile := TShellCompileSetup.NewHost(mServices);
end;

class procedure TShellProtocolWiring.Diagnostics(AParts: TShellParts);
var
  mServices: TShellDiagnosticsAreaServices;
begin
  mServices := Default(TShellDiagnosticsAreaServices);
  mServices.Logger := AParts.Channel.Logger;
  mServices.Transport := AParts.Channel.Transport;
  mServices.Dispatcher := AParts.Protocol.Dispatcher;
  mServices.Documents := AParts.Documents;
  // Closures: Kern und Index entstehen erst nach den Diagnosen (CoreWiring).
  mServices.Core :=
    function: TShellCore
    begin
      Result := AParts.Core;
    end;
  mServices.Index :=
    function: ISymbolIndex
    begin
      Result := AParts.Index;
    end;
  mServices.CompilerMessages :=
    function(const AFileName: string): TArray<TCompilerMessage>
    begin
      Result := AParts.Compile.Results.MessagesFor(AFileName);
    end;
  mServices.UsesContext :=
    function(const AUri: string; out AContext: TUsesContext): Boolean
    begin
      Result := AParts.UsesContextFor(AUri, AContext);
    end;
  // Das Diagnoselog entsteht erst mit der Sitzung; bis dahin heißt jede Datei 'unit' (#1094).
  mServices.FileLabel :=
    function(const AFileName: string): string
    begin
      Result := 'unit';
      if AParts.Session <> nil then
      begin
        Result := AParts.Session.FileLabel(AFileName);
      end;
    end;
  mServices.RequestTimeout :=
    function: Cardinal
    begin
      Result := AParts.CurrentRequestTimeout;
    end;
  AParts.DiagnosticsArea := TShellDiagnosticsArea.Create(mServices);
end;

end.
