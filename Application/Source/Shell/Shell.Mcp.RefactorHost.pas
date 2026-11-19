unit Shell.Mcp.RefactorHost;

// Host-Rolle Shell: MCP-Modus (--mcp, #48), Quelle des Werkzeugs refactor (#2150). Legt dieselben Code-Aktionen
// (TLspCodeActions) und Refactorings des Servers (TShellRefactorings samt ihrer Befehle) wie die Komposition an,
// aber über den Diensten des MCP-Laufs und mit eigenem Dokumentspeicher: Run öffnet die Datei für einen Aufruf
// und schließt sie danach wieder. Regelkorrekturen bleiben bei apply_code_action (ohne Regelkontext).

interface

uses
  System.SysUtils,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Lsp.References,
  Atlas.Common.Lsp.Commands,
  Atlas.Common.Lsp.CodeActions,
  Atlas.Common.Mcp.EditTools,
  Atlas.Common.Mcp.RefactorTools,
  Shell.Composition.Refactorings.Services,
  Shell.Composition.Refactorings;

type
  /// <summary>Einstellungen der Datei (atlas.json ihres Arbeitsbereichs).</summary>
  TMcpRefactorSettingsFunc = reference to function(const AFileName: string): TServerSettings;

  /// <summary>Was refactor vom MCP-Lauf braucht.</summary>
  TMcpRefactorHostServices = record
    Logger: ILogger;
    Index: ISymbolIndex;
    EnsureUnit: TEnsureUnitFunc;
    Namespaces: TShellNamesFunc;
    ProjectFiles: TShellNamesFunc;
    /// <summary>Lesen von der Platte; geöffnete Dokumente des Hosts haben Vorrang.</summary>
    ReadText: TReferenceReadText;
    SettingsFor: TMcpRefactorSettingsFunc;
    FormatStyleFor: TShellFormatStyleFunc;
    DelphiVersionFor: TShellUriTextFunc;
    NewNamesFor: TShellNewNamesFunc;
    ProjectFor: TShellProjectFunc;
  end;

  /// <summary>refactor über den Code-Aktionen des Servers; lebt so lange wie die Werkzeuge, die es halten.</summary>
  IMcpRefactorHost = interface
    ['{2BD0AEF6-9A39-4A3E-8966-B708304A4EA2}']
    /// <summary>refactor für ARequest; ARequest.FileName ist mit seinem Text für den Aufruf geöffnet. Liest die Datei
    /// über AEdit.ReadText; EMcpToolError, wenn sie nicht lesbar ist.</summary>
    function Run(AEdit: TMcpEditTools; const ARequest: TMcpRefactorRequest): string;
  end;

  TMcpRefactorHost = class(TInterfacedObject, IMcpRefactorHost)
  private
    FServices: TMcpRefactorHostServices;
    FDocuments: IDocumentStore;
    FCommands: TLspCommands;
    FRefactorings: TShellRefactorings;
    FCodeActions: TLspCodeActions;
    function ReadText(const AFileName: string; out AText: string): Boolean;
    function Settings(const AUri: string): TServerSettings;
    function LanguageLevel(const AUri: string): string;
    function RefactoringServices: TShellRefactoringServices;
    procedure ConfigureCodeActions;
    function Source: TMcpRefactorSource;
  public
    constructor Create(const AServices: TMcpRefactorHostServices);
    destructor Destroy; override;
    function Run(AEdit: TMcpEditTools; const ARequest: TMcpRefactorRequest): string;
  end;

implementation

uses
  System.JSON,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Pascal.LanguageFeatures,
  Atlas.Common.Editing.ClassActions,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Localization.Texts;

type
{$SCOPEDENUMS ON}
  TRefactorHostText = (IsNotReadable);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TRefactorHostText] of TAtlasText = (
    (De: '%s ist nicht lesbar'; En: '%s is not readable'));

{ TMcpRefactorHost }

constructor TMcpRefactorHost.Create(const AServices: TMcpRefactorHostServices);
begin
  inherited Create;
  FServices := AServices;
  FDocuments := TDocumentStore.Create;
  FCommands := TLspCommands.Create;
  FRefactorings := TShellRefactorings.Create(RefactoringServices);
  FRefactorings.Register(FCommands);
  FCodeActions := TLspCodeActions.Create(FDocuments, nil);
  ConfigureCodeActions;
end;

destructor TMcpRefactorHost.Destroy;
begin
  FreeAndNil(FCodeActions);
  if FRefactorings <> nil then
  begin
    FRefactorings.StopForeignWork;
  end;
  FreeAndNil(FRefactorings);
  FreeAndNil(FCommands);
  FDocuments := nil;
  inherited;
end;

function TMcpRefactorHost.ReadText(const AFileName: string; out AText: string): Boolean;
var
  mDocument: ITextDocument;
begin
  if FDocuments.TryGet(TDocumentUris.FromPath(AFileName), mDocument) then
  begin
    AText := mDocument.Text;
    Exit(True);
  end;
  Result := FServices.ReadText(AFileName, AText);
end;

function TMcpRefactorHost.Settings(const AUri: string): TServerSettings;
begin
  Result := FServices.SettingsFor(TDocumentUris.ToPath(AUri));
end;

function TMcpRefactorHost.LanguageLevel(const AUri: string): string;
begin
  Result := TLanguageFeatures.LanguageLevel(FServices.DelphiVersionFor(AUri), Settings(AUri).MinDelphiVersion);
end;

function TMcpRefactorHost.RefactoringServices: TShellRefactoringServices;
begin
  Result := Default(TShellRefactoringServices);
  Result.Logger := FServices.Logger;
  Result.Documents := FDocuments;
  Result.Index := FServices.Index;
  Result.EnsureUnit := FServices.EnsureUnit;
  Result.Namespaces := FServices.Namespaces;
  Result.ProjectFiles := FServices.ProjectFiles;
  Result.ReadText := ReadText;
  Result.SettingsFor :=
    function(const AUri: string): TRefactoringSettings
    begin
      Result := Settings(AUri).Refactoring;
    end;
  Result.FormatStyleFor := FServices.FormatStyleFor;
  Result.LanguageLevelFor := LanguageLevel;
  Result.DelphiVersionFor := FServices.DelphiVersionFor;
  Result.TypeCommentFor :=
    function(const AUri: string): string
    begin
      Result := Settings(AUri).ClassCompletion.TypeComment;
    end;
  // Ohne Compilerlauf keine Compilermeldungen; ohne uses-Umfeld keine uses-Folgeschritte.
  Result.MessagesFor :=
    function(const AFileName: string): TArray<TCompilerMessage>
    begin
      Result := nil;
    end;
  Result.UsesContextFor :=
    function(const AUri: string; out AContext: TUsesContext): Boolean
    begin
      AContext := Default(TUsesContext);
      Result := False;
    end;
  Result.ProjectFor := FServices.ProjectFor;
  Result.NewNamesFor := FServices.NewNamesFor;
end;

procedure TMcpRefactorHost.ConfigureCodeActions;
begin
  FCodeActions.FormatStyleFor := FServices.FormatStyleFor;
  FCodeActions.RefactoringFor :=
    function(const AUri: string): TRefactoringSettings
    begin
      Result := Settings(AUri).Refactoring;
    end;
  FCodeActions.ClassActionContextFor :=
    function(const AUri: string): TClassActionContext
    begin
      Result := TClassActionContext.Default;
      Result.Index := FServices.Index;
      Result.DelphiVersion := LanguageLevel(AUri);
      Result.Uri := AUri;
    end;
  // Actions ist virtuell: über eine anonyme Methode (FPC übersetzt die direkte Zuweisung nicht).
  FCodeActions.ExtraActions :=
    function(const AUri: string; const ARange: TTextRange): TArray<TJSONObject>
    begin
      Result := FRefactorings.Actions(AUri, ARange);
    end;
end;

function TMcpRefactorHost.Source: TMcpRefactorSource;
begin
  Result := Default(TMcpRefactorSource);
  Result.Actions :=
    function(const AFileName: string; const ARange: TTextRange): TJSONArray
    begin
      Result := FCodeActions.ActionsAt(TDocumentUris.FromPath(AFileName), ARange);
    end;
  Result.Execute :=
    function(const ACommand: string; const AArguments: TJSONArray): TJSONValue
    begin
      Result := FCommands.Execute(ACommand, AArguments);
    end;
end;

function TMcpRefactorHost.Run(AEdit: TMcpEditTools; const ARequest: TMcpRefactorRequest): string;
var
  mRead: TReferenceReadText;
  mText, mUri: string;
begin
  mRead := AEdit.ReadText;
  if not mRead(ARequest.FileName, mText) then
  begin
    raise EMcpToolError.CreateFmt(cTexts[TRefactorHostText.IsNotReadable].Text, [ARequest.FileName]);
  end;
  mUri := TDocumentUris.FromPath(ARequest.FileName);
  FDocuments.Open(mUri, 'pascal', 1, mText);
  try
    Result := TMcpRefactorTools.Run(AEdit, Source, ARequest);
  finally
    FDocuments.Close(mUri);
  end;
end;

initialization
  TAtlasTextTables.Add('Shell.Mcp.RefactorHost', cTexts);

end.
