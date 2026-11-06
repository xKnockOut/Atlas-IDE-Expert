unit Shell.Composition.Navigation;

// Internals-Rolle Shell: Navigation im Quelltext. Definition, Hover, Symbolsuche mit Lesezeichen (#306),
// Hervorhebungen, verknüpftes Bearbeiten (#658), Werte beim Debuggen (#508), Compilerschalter, nicht debugbare
// Stellen, Referenzen und Umbenennen. Die Komposition reicht Dokumente, Index, Quelltext, Projektdateien und die
// Einstellungen der Arbeitsbereiche als Dienste herein.

interface

uses
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.Bookmarks,
  Atlas.Common.Lsp.Documentation,
  Atlas.Common.Lsp.ConditionalSymbols,
  Atlas.Common.Lsp.Definition,
  Atlas.Common.Lsp.Hover,
  Atlas.Common.Lsp.WorkspaceSymbols,
  Atlas.Common.Lsp.DocumentHighlights,
  Atlas.Common.Lsp.LinkedEditing,
  Atlas.Common.Lsp.InlineValues,
  Atlas.Common.Lsp.CompilerSwitches,
  Atlas.Common.Lsp.DebugUnavailable,
  Atlas.Common.Lsp.References,
  Atlas.Common.Lsp.Rename;

type
  TShellNavigationReadText = reference to function(const AFileName: string; out AText: string): Boolean;

  /// <summary>Was die Navigation von der Komposition brauchen.</summary>
  TShellNavigationServices = record
    Documents: IDocumentStore;
    Index: ISymbolIndex;
    /// <summary>Index für Hover und Parameterhilfe: der gemeinsame samt Ersatz-Units der IDE; nil = Index.
    /// </summary>
    EditorIndex: ISymbolIndex;
    ReadText: TShellNavigationReadText;
    ProjectFiles: TReferenceFilesProvider;
    EnsureUnit: TEnsureUnitFunc;
    DelphiVersionFor: THoverVersionProvider;
    HintSettingsFor: TDocHintsProvider;
    RationaleOptionsFor: THoverRationaleProvider;
    /// <summary>Zustand und Herkunft bedingter Symbole (#102).</summary>
    ConditionalContextFor: TConditionalContextFunc;
    HighlightSettingsFor: THighlightSettingsProvider;
    CompilerSwitchContextFor: TCompilerSwitchContextFunc;
    ReferenceSettingsFor: TReferenceSettingsProvider;
  end;

  /// <summary>Navigation mit ihren Anfragen.</summary>
  TShellNavigation = class
  private
    FServices: TShellNavigationServices;
    FDefinition: TLspDefinition;
    FHover: TLspHover;
    FWorkspaceSymbols: TLspWorkspaceSymbols;
    /// <summary>Lesezeichen "// @bookmark Name" für die Symbolsuche (#306).</summary>
    FBookmarks: TBookmarkStore;
    FDocumentHighlights: TLspDocumentHighlights;
    FLinkedEditing: TLspLinkedEditing;
    FInlineValues: TLspInlineValues;
    FCompilerSwitches: TLspCompilerSwitches;
    FDebugUnavailable: TLspDebugUnavailable;
    FReferences: TLspReferences;
    FRename: TLspRename;
    /// <summary>Quelltext über den Dienst; als eigene Methode an alle Leser mit ihren eigenen Typen.</summary>
    function ReadText(const AFileName: string; out AText: string): Boolean;
    function ProjectFiles: TArray<string>;
    function GetNamespaces: TArray<string>;
    procedure CreateSymbolViews;
    procedure CreateEditorViews;
  public
    constructor Create(const AServices: TShellNavigationServices);
    destructor Destroy; override;
    /// <summary>Anfragen der Navigation am Dispatcher.</summary>
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Lesezeichen aller Projektdateien; geöffnete Dateien nach Version, sonst nach Änderungszeit.</summary>
    function CollectBookmarks: TArray<TBookmarkHit>;
    /// <summary>Namensräume des Projekts an alle Navigationen, die Namen auflösen.</summary>
    procedure SetNamespaces(const ANamespaces: TArray<string>);
    /// <summary>Zuletzt gesetzte Namensräume.</summary>
    property Namespaces: TArray<string> read GetNamespaces;
    /// <summary>Hover, damit die Komposition Markdown nach den Fähigkeiten des Clients schaltet.</summary>
    property Hover: TLspHover read FHover;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Documents.Uris;

constructor TShellNavigation.Create(const AServices: TShellNavigationServices);
begin
  inherited Create;
  FServices := AServices;
  CreateSymbolViews;
  CreateEditorViews;
end;

procedure TShellNavigation.CreateSymbolViews;
begin
  FDefinition := TLspDefinition.Create(FServices.Documents, FServices.Index, FServices.EnsureUnit);
  FDefinition.ReadText := ReadText;
  FHover := TLspHover.Create(FServices.Documents, FServices.EditorIndex, ReadText, FServices.EnsureUnit);
  FHover.VersionProvider := FServices.DelphiVersionFor;
  FHover.HintsFor := FServices.HintSettingsFor;
  FHover.RationaleFor := FServices.RationaleOptionsFor;
  FHover.SymbolsFor := FServices.ConditionalContextFor;
  FWorkspaceSymbols := TLspWorkspaceSymbols.Create(FServices.Index);
  FBookmarks := TBookmarkStore.Create;
  FWorkspaceSymbols.BookmarksFor := CollectBookmarks;
  FReferences := TLspReferences.Create(FServices.Documents, FServices.Index, ReadText, ProjectFiles,
    FServices.EnsureUnit);
  FReferences.SettingsFor := FServices.ReferenceSettingsFor;
  FRename := TLspRename.Create(FServices.Documents, FServices.Index, ReadText, ProjectFiles, FServices.EnsureUnit);
  FRename.SettingsFor := FServices.ReferenceSettingsFor;
end;

procedure TShellNavigation.CreateEditorViews;
begin
  FDocumentHighlights := TLspDocumentHighlights.Create(FServices.Documents, FServices.Index, FServices.EnsureUnit);
  FDocumentHighlights.SettingsFor := FServices.HighlightSettingsFor;
  // Lokale Bezeichner brauchen den Index (#658).
  FLinkedEditing := TLspLinkedEditing.Create(FServices.Documents, FServices.Index, FServices.EnsureUnit);
  // Werte beim Debuggen am Zeilenende (#508).
  FInlineValues := TLspInlineValues.Create(FServices.Documents, FServices.Index, FServices.EnsureUnit);
  FCompilerSwitches := TLspCompilerSwitches.Create(FServices.Documents, FServices.CompilerSwitchContextFor);
  FDebugUnavailable := TLspDebugUnavailable.Create(FServices.Documents, FServices.Index, FServices.EnsureUnit,
    FServices.CompilerSwitchContextFor);
end;

destructor TShellNavigation.Destroy;
begin
  FreeAndNil(FLinkedEditing);
  FreeAndNil(FInlineValues);
  FreeAndNil(FCompilerSwitches);
  FreeAndNil(FDebugUnavailable);
  FreeAndNil(FDefinition);
  FreeAndNil(FHover);
  FreeAndNil(FWorkspaceSymbols);
  FreeAndNil(FBookmarks);
  FreeAndNil(FDocumentHighlights);
  FreeAndNil(FReferences);
  FreeAndNil(FRename);
  inherited Destroy;
end;

function TShellNavigation.ReadText(const AFileName: string; out AText: string): Boolean;
begin
  Result := FServices.ReadText(AFileName, AText);
end;

function TShellNavigation.ProjectFiles: TArray<string>;
begin
  Result := FServices.ProjectFiles();
end;

function TShellNavigation.GetNamespaces: TArray<string>;
begin
  Result := FDefinition.Namespaces;
end;

procedure TShellNavigation.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  FDefinition.Attach(ADispatcher);
  FHover.Attach(ADispatcher);
  FWorkspaceSymbols.Attach(ADispatcher);
  FDocumentHighlights.Attach(ADispatcher);
  FLinkedEditing.Attach(ADispatcher);
  FInlineValues.Attach(ADispatcher);
  FCompilerSwitches.Attach(ADispatcher);
  FDebugUnavailable.Attach(ADispatcher);
  FReferences.Attach(ADispatcher);
  FRename.Attach(ADispatcher);
end;

function TShellNavigation.CollectBookmarks: TArray<TBookmarkHit>;
var
  mFiles: TArray<string>;
  mFileName: string;
  mDocument: ITextDocument;
  mStamp: Int64;
begin
  mFiles := ProjectFiles;
  for mFileName in mFiles do
  begin
    // Geöffnete Dateien nach Version (negativ), sonst nach Änderungszeit der Datei.
    if FServices.Documents.TryGet(TDocumentUris.FromPath(mFileName), mDocument) then
    begin
      mStamp := -1 - mDocument.Version;
    end
    else if FileExists(mFileName) then
    begin
      mStamp := Trunc(TFile.GetLastWriteTimeUtc(mFileName) * MSecsPerDay);
    end
    else
    begin
      mStamp := 0;
    end;
    FBookmarks.Update(mFileName, mStamp, ReadText);
  end;
  FBookmarks.Retain(mFiles);
  Result := FBookmarks.All;
end;

procedure TShellNavigation.SetNamespaces(const ANamespaces: TArray<string>);
begin
  FDefinition.Namespaces := ANamespaces;
  FHover.Namespaces := ANamespaces;
  FDocumentHighlights.Namespaces := ANamespaces;
  FLinkedEditing.Namespaces := ANamespaces;
  FInlineValues.Namespaces := ANamespaces;
  FReferences.Namespaces := ANamespaces;
  FRename.Namespaces := ANamespaces;
end;

end.
