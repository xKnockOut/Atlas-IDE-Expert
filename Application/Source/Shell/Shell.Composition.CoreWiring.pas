unit Shell.Composition.CoreWiring;

// Verdrahtung von Kern, Index und Sitzung (S-02): Arbeitsbereiche, Indexplanung und Konfiguration mit den
// Ereignissen des Dokumentspeichers; Teilwurzel Index und Teilwurzel Sitzung mit dem Diagnoselog am Verteiler.
// Closures fragen die Teile erst beim Aufruf, weil Code, Analyse und IDE später entstehen.

interface

uses
  Shell.Composition.Core,
  Shell.Composition.IndexArea,
  Shell.Composition.Parts;

type
  /// <summary>Legt Kern, Index und Sitzung in den Teilen an.</summary>
  TShellCoreWiring = class abstract
  private
    /// <summary>Teil von Workspaces: Ereignisse des Dokumentspeichers (Shell.Composition.DocumentEvents).</summary>
    class procedure DocumentEvents(AParts: TShellParts); static;
    /// <summary>Was der Kern von der Komposition braucht.</summary>
    class function CoreServices(AParts: TShellParts): TShellCoreServices; static;
    /// <summary>Teil von CoreServices: Meldungen des Kerns an die Komposition.</summary>
    class procedure CoreEvents(AParts: TShellParts; var AServices: TShellCoreServices); static;
    /// <summary>Teil von Index: Was die Teilwurzel Index von den anderen Teilen braucht.</summary>
    class function IndexAreaServices(AParts: TShellParts): TShellIndexAreaServices; static;
    /// <summary>Teil von Index: Teilwurzel Sitzung mit dem Diagnoselog am Verteiler.</summary>
    class procedure Session(AParts: TShellParts); static;
  public
    /// <summary>Arbeitsbereiche, Indexplanung und Konfiguration ohne Ordner; Pfade für die Syntaxprüfung.</summary>
    class procedure Workspaces(AParts: TShellParts); static;
    /// <summary>Symbolindex und Diagnoselog.</summary>
    class procedure Index(AParts: TShellParts); static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Architecture.UsesService,
  Atlas.Common.Query.Contract,
  Atlas.Common.Lsp.IdeProject,
  Atlas.Common.Lsp.WatchedFiles,
  Atlas.Common.Lsp.IdeTypes,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Projects.Selection,
  Atlas.Common.Diagnostics.Anonymizer,
  Atlas.Common.Configuration.Contract,
  Shell.CrashCases,
  Shell.Composition.FileChanges,
  Shell.Composition.Folders,
  Shell.Composition.Compile,
  Shell.Composition.DiagnosticsArea,
  Shell.Composition.DocumentEvents,
  Shell.Composition.Session;

class procedure TShellCoreWiring.Workspaces(AParts: TShellParts);
begin
  AParts.Core := TShellCore.Create(CoreServices(AParts));
  DocumentEvents(AParts);
  AParts.Core.Attach(AParts.Protocol.Dispatcher);
end;

class procedure TShellCoreWiring.DocumentEvents(AParts: TShellParts);
var
  mServices: TShellDocumentEventServices;
begin
  mServices := Default(TShellDocumentEventServices);
  mServices.Core :=
    function: TShellCore
    begin
      Result := AParts.Core;
    end;
  mServices.CrashCases :=
    function: TShellCrashCases
    begin
      Result := AParts.Protocol.CrashCases;
    end;
  mServices.Compile :=
    function: TShellCompileHost
    begin
      Result := AParts.Compile;
    end;
  // Die Dateiänderungen entstehen erst mit der Teilwurzel IDE.
  mServices.FileChanges :=
    function: TShellFileChanges
    begin
      Result := nil;
      if AParts.IdeArea <> nil then
      begin
        Result := AParts.IdeArea.FileChanges;
      end;
    end;
  mServices.DeriveWorkspaces :=
    function: Boolean
    begin
      Result := AParts.DeriveWorkspaces;
    end;
  TShellDocumentEvents.Attach(AParts.Documents, mServices);
end;

/// <summary>Katalog der Typen aus der IDE (atlas/ideTypes) für die Prüfregeln.</summary>
function IdeTypesOf(AParts: TShellParts): TShellFoldersIdeTypesFunc;
begin
  Result :=
    function: IRuleIdeTypes
    begin
      Result := AParts.IdeArea.Ide.Types.Catalog;
    end;
end;

class function TShellCoreWiring.CoreServices(AParts: TShellParts): TShellCoreServices;
begin
  Result := Default(TShellCoreServices);
  Result.Logger := AParts.Channel.Logger;
  Result.Transport := AParts.Channel.Transport;
  Result.Documents := AParts.Documents;
  Result.Index :=
    function: ISymbolIndex
    begin
      Result := AParts.Index;
    end;
  Result.UsesGraph :=
    function: TUsesGraphService
    begin
      // Der Kern fragt erst nach der Teilwurzel Index und ist beim Beenden vor dem Index fort.
      Result := AParts.IndexArea.UsesGraph;
    end;
  Result.Queries :=
    function: ICodeQueries
    begin
      Result := AParts.AnalysisArea.Overviews.Queries;
    end;
  Result.SelectedProject :=
    function(const AOrigin: string): string
    begin
      Result := AParts.IdeArea.Selection.Project(AOrigin);
    end;
  Result.ActiveProject :=
    function: string
    begin
      Result := AParts.IdeArea.Ide.Project.ActiveProject;
    end;
  Result.IdeProject :=
    function: TLspIdeProject
    begin
      Result := AParts.IdeArea.Ide.Project;
    end;
  Result.IdeTypes := IdeTypesOf(AParts);
  Result.Selection :=
    function: TProjectSelection
    begin
      Result := AParts.IdeArea.Selection;
    end;
  Result.Anonymizer :=
    function: ILogAnonymizer
    begin
      Result := AParts.Channel.Anonymizer;
    end;
  Result.ClientName :=
    function: string
    begin
      Result := '';
      if AParts.Session <> nil then
      begin
        Result := AParts.Session.ClientName;
      end;
    end;
  CoreEvents(AParts, Result);
end;

class procedure TShellCoreWiring.CoreEvents(AParts: TShellParts; var AServices: TShellCoreServices);
begin
  AServices.ProjectLoaded :=
    procedure
    begin
      AParts.IndexArea.ProjectLoaded;
    end;
  AServices.IndexStageDone :=
    procedure(AProjectStage: Boolean)
    begin
      AParts.IndexArea.IndexStageDone(AProjectStage);
    end;
  AServices.IndexEvent :=
    procedure(AText: string)
    begin
      // Absicherung: Beim Beenden ist das Diagnoselog schon fort (Code-Review A-05).
      if AParts.Session <> nil then
      begin
        AParts.Session.Diagnostics.Log.LogEvent(AText);
      end;
    end;
  AServices.SettingsChanged :=
    procedure(ASettings: TServerSettings)
    begin
      AParts.Protocol.Dispatcher.Watchdog.SetTimeout(ASettings.RequestTimeoutMs);
      AParts.Session.ApplySettings(ASettings);
      // server.crashCases und server.crashSkip (#1355) gelten serverweit; beim Nachstellen bleiben beide aus.
      if not AParts.Replay then
      begin
        AParts.Protocol.CrashCases.Enabled := ASettings.ServerCrashCases;
        AParts.Protocol.CrashCases.SkipEnabled := ASettings.ServerCrashSkip;
      end;
    end;
  // Im Thread der Nachrichtenschleife verarbeiten wie eine Meldung des Clients.
  AServices.FilesChanged :=
    procedure(const AFiles: TArray<string>)
    begin
      AParts.Connection.Post(TLspWatchedFiles.Notification(AFiles));
    end;
end;

class procedure TShellCoreWiring.Index(AParts: TShellParts);
begin
  AParts.IndexArea := TShellIndexArea.Create(IndexAreaServices(AParts));
  AParts.EditingArea.Editing.UseIndex(AParts.IndexArea.Index);
  Session(AParts);
end;

class function TShellCoreWiring.IndexAreaServices(AParts: TShellParts): TShellIndexAreaServices;
begin
  Result := Default(TShellIndexAreaServices);
  Result.Dispatcher := AParts.Protocol.Dispatcher;
  Result.Core :=
    function: TShellCore
    begin
      Result := AParts.Core;
    end;
  Result.Diagnostics :=
    function: TShellDiagnosticsArea
    begin
      Result := AParts.DiagnosticsArea;
    end;
  // Closure: CreateForStdio setzt den Anonymisierer erst nach dem Anlegen.
  Result.Anonymizer :=
    function: ILogAnonymizer
    begin
      Result := AParts.Channel.Anonymizer;
    end;
  Result.ProjectStarted :=
    procedure
    begin
      if AParts.Compile <> nil then
      begin
        AParts.Compile.Reset;
      end;
    end;
  Result.NamespacesChanged :=
    procedure(const ANamespaces: TArray<string>)
    begin
      AParts.CodeArea.Navigation.SetNamespaces(ANamespaces);
      AParts.CodeArea.Completion.Completion.Hooks.Namespaces := ANamespaces;
      AParts.AnalysisArea.Analysis.SetNamespaces(ANamespaces);
    end;
  Result.LibraryRootsChanged :=
    procedure(const ARoots: TArray<string>)
    begin
      AParts.Session.Diagnostics.SetLibraryRoots(ARoots);
    end;
  Result.Queue :=
    function(const AWork: TProc): Boolean
    begin
      Result := (AParts.Connection <> nil) and AParts.Connection.Queue(AWork);
    end;
end;

class procedure TShellCoreWiring.Session(AParts: TShellParts);
var
  mServices: TShellSessionServices;
begin
  mServices.Logger := AParts.Channel.Logger;
  mServices.Documents := AParts.Documents;
  mServices.Index := AParts.Index;
  mServices.Dispatcher := AParts.Protocol.Dispatcher;
  mServices.IndexLoading :=
    function: Integer
    begin
      Result := AParts.Core.Workspaces.IndexLoading;
    end;
  mServices.Stop :=
    procedure
    begin
      AParts.Connection.Stop;
    end;
  AParts.Session := TShellSession.Create(mServices, TShellParts.RequestTimeoutMs);
end;

end.
