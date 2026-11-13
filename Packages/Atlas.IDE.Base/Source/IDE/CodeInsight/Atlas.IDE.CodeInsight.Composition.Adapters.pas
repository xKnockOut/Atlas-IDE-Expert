unit Atlas.IDE.CodeInsight.Composition.Adapters;

// Adapters, Providers und Compositions der Core-Features für die Kompositionswurzel: Serverprozess,
// Ordnerbeobachter, Quellen von Vervollständigung und Parameter-Hint, Code-Aktionen für den Klick auf eine Marke,
// Ziel und Sicherung des Änderungsprotokolls und die Update-Quelle. Nur diese
// Unit erzeugt sie; die Features bekommen sie über
// Schnittstellen und Fabriken.

interface

uses
  Atlas.Core.Updates.Contract,
  Atlas.IDE.CodeInsight.Manager.State;

/// <summary>Serverprozess, Ordnerbeobachter und Quellen von Vervollständigung und Parameter-Hint aus dem Kern,
/// Code-Aktionen für den Klick auf die Marke „braucht kein Self“.</summary>
function CodeInsightAdapters: TAtlasCodeInsightAdapters;
/// <summary>Ziel auf der Platte und Sicherung des Änderungsprotokolls (#721) in TAtlasIdeUndoTarget und
/// TAtlasIdeUndo einsetzen.</summary>
procedure InstallUndoAdapters;
/// <summary>Quelle der Update-Prüfung (#495) über HTTP.</summary>
function UpdateSource: IAtlasVersionSource;

implementation

uses
  System.SysUtils,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Lsp.Adapters.ServerProcess,
  Atlas.Core.Files.WatchedChanges,
  Atlas.Core.Files.Adapters.FolderWatcher,
  Atlas.Core.Signature.Contract,
  Atlas.Core.Signature.Providers.Server,
  Atlas.Core.Completion.Snippets,
  Atlas.Core.Completion.Providers.Server,
  Atlas.Core.Completion.Providers.Snippets,
  Atlas.Core.Completion.Providers.XmlDoc,
  Atlas.Core.Undo.Contract,
  Atlas.Core.Undo.Adapters.DiskTarget,
  Atlas.Core.Undo.Adapters.FileStore,
  Atlas.Core.Updates.Adapters.HttpSource,
  Atlas.IDE.Completion.Editor,
  Atlas.IDE.Commands.Editor,
  Atlas.IDE.Undo.Changes,
  Atlas.IDE.Undo.Target;

/// <summary>Quellen der Vervollständigung: Server, XML-Doku und Snippets, mit Abbau und Schaltern.</summary>
function CompletionSources(const ASession: TAtlasSessionFunc; const ALog: TAtlasLogProc): TAtlasCompletionSources;
var
  mServer: TAtlasServerCompletionProvider;
  mSnippets: TAtlasSnippetCompletionProvider;
begin
  mServer := TAtlasServerCompletionProvider.Create(ASession);
  mServer.OnLog :=
    procedure(const AMessage: string)
    begin
      ALog(AMessage);
    end;
  mSnippets := TAtlasSnippetCompletionProvider.Create(TAtlasSnippets.BuiltIn);
  // Die Schnittstellen halten die Quellen; die Funktionen greifen über die Objekte zu.
  Result.Server := mServer;
  Result.XmlDoc := TAtlasXmlDocCompletionProvider.Create;
  Result.Snippets := mSnippets;
  Result.Shutdown :=
    procedure
    begin
      mServer.Shutdown;
      mSnippets.Shutdown;
    end;
  Result.SetSnippetsEnabled :=
    procedure(AEnabled: Boolean)
    begin
      mSnippets.Enabled := AEnabled;
      mServer.Snippets := AEnabled;
    end;
  Result.SetSnippetList :=
    procedure(AList: TAtlasSnippetList)
    begin
      mSnippets.SetSnippets(AList);
    end;
  Result.SnippetList :=
    function: TAtlasSnippetList
    begin
      Result := mSnippets.Snippets;
    end;
end;

function CodeInsightAdapters: TAtlasCodeInsightAdapters;
begin
  Result.NewServer :=
    function(AExeName, AArguments: string): IAtlasLspServer
    begin
      Result := TLspServerProcess.Create(AExeName, AArguments);
    end;
  Result.NewFolderWatcher :=
    function(AChanges: TAtlasWatchedChanges): IAtlasFolderWatcher
    begin
      Result := TAtlasFolderWatcher.Create(AChanges);
    end;
  Result.NewSignatureSource :=
    function(ASession: TAtlasSessionFunc): IAtlasSignatureSource
    begin
      Result := TAtlasServerSignatureProvider.Create(ASession);
    end;
  Result.NewCompletionSources :=
    function(const ASession: TAtlasSessionFunc; const ALog: TAtlasLogProc): TAtlasCompletionSources
    begin
      Result := CompletionSources(ASession, ALog);
    end;
  // Klick auf die Marke „braucht kein Self“ (#686): dieselbe Auswahl wie Strg+.
  Result.OpenCodeActions :=
    procedure
    begin
      TAtlasIdeEditorCommands.CodeActions;
    end;
  // Enter auf einem nicht sichtbaren Mitglied der Vervollständigung (#2108): Sichtbarkeit anheben, Eigenschaft
  // anlegen.
  Result.OfferActions :=
    procedure(const AActions: TArray<TLspCodeAction>)
    begin
      TAtlasIdeEditorCommands.OfferActions(AActions);
    end;
end;

procedure InstallUndoAdapters;
begin
  TAtlasIdeUndoTarget.DiskFactory :=
    function(const AHooks: TAtlasUndoDiskHooks): IAtlasUndoTarget
    var
      mDisk: TAtlasUndoDiskTarget;
    begin
      mDisk := TAtlasUndoDiskTarget.Create;
      mDisk.OnAddToProject := AHooks.OnAddToProject;
      mDisk.OnRemoveFromProject := AHooks.OnRemoveFromProject;
      mDisk.OnRecycle := AHooks.OnRecycle;
      Result := mDisk;
    end;
  TAtlasIdeUndo.StoreFactory :=
    function(const AFolder: string; AMaxBytes: Int64): IAtlasUndoStore
    begin
      Result := TAtlasUndoFileStore.Create(AFolder, AMaxBytes);
    end;
end;

function UpdateSource: IAtlasVersionSource;
begin
  Result := TAtlasHttpVersionSource.Create;
end;

end.
