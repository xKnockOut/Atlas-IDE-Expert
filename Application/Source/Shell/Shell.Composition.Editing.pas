unit Shell.Composition.Editing;

// Internals-Rolle Shell: Bearbeiten im Editor. Gliederung, Faltbereiche, Auswahlbereiche, Formatieren mit
// Schnellbefehlen nach Enter und das Erzeugen-Menü (#719). Die Komposition reicht Dokumente, Formatstil, Schalter
// und Sprachstand als Dienste herein; Host der Schnellbefehle, Index und Vervollständigung kommen nach, sobald sie
// bestehen.

interface

uses
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Editing.Contract,
  Atlas.Common.Semantics.TypeInfoClasses,
  Lsp.Commands,
  Lsp.Completion,
  Lsp.DocumentSymbols,
  Lsp.FoldingRanges,
  Lsp.BlockFolds,
  Lsp.SelectionRanges,
  Editing.Formatting.Protocol,
  Editing.SlashMenu.Protocol;

type
  /// <summary>Was das Bearbeiten von der Komposition braucht.</summary>
  TShellEditingServices = record
    Documents: IDocumentStore;
    /// <summary>Formatstil mit Editor-Optionen.</summary>
    FormatStyleFor: TFormatStyleProvider;
    /// <summary>Einrückung wie beim Formatieren (#43), ohne Editor-Optionen: .editorconfig und "format".</summary>
    ResolvedFormatStyleFor: TSlashMenuStyleFunc;
    SlashCommandsFor: TSlashCommandsProvider;
    LanguageLevelFor: TFormattingVersionFunc;
    DocCommentsFor: TFormattingEnabledFunc;
    /// <summary>Quelltext für die Standardsichtbarkeit published über die Vorfahren (#537).</summary>
    ReadText: TTypeInfoReadText;
  end;

  /// <summary>Gliederung, Falt- und Auswahlbereiche, Formatieren und Erzeugen-Menü.</summary>
  TShellEditing = class
  private
    FServices: TShellEditingServices;
    FDocumentSymbols: TLspDocumentSymbols;
    FFoldingRanges: TLspFoldingRanges;
    FBlockFolds: TLspBlockFolds;
    FFormatting: TFormattingProtocol;
    FSlashMenu: TSlashMenuProtocol;
    FSelectionRanges: TLspSelectionRanges;
    function LanguageLevel(const AUri: string): string;
    function GetSlashHost: ISlashHost;
  public
    constructor Create(const AServices: TShellEditingServices);
    destructor Destroy; override;
    /// <summary>Anfragen des Bearbeitens am Dispatcher.</summary>
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Befehle des Erzeugen-Menüs.</summary>
    procedure RegisterCommands(ACommands: TLspCommands);
    /// <summary>Host der Schnellbefehle für Formatieren und Erzeugen-Menü.</summary>
    procedure UseSlashHost(const AHost: ISlashHost);
    /// <summary>Index, sobald er besteht.</summary>
    procedure UseIndex(const AIndex: ISymbolIndex);
    /// <summary>„Interface implementieren“ im Erzeugen-Menü (#719, #466) wie in der Vervollständigung.</summary>
    procedure UseCompletion(ACompletion: TLspCompletion);
    property SlashHost: ISlashHost read GetSlashHost;
  end;

implementation

uses
  Atlas.Common.Completion.Contract,
  System.Generics.Collections, // Inline-Funktionen von TJSONArray (H2443)
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.FileEncoding,
  Editing.MaintenanceCommands;

function ReadEditorConfig(const AFileName: string; out AText: string): Boolean;
begin
  Result := FileExists(AFileName);
  if Result then
  begin
    AText := TFileEncoding.LoadText(AFileName);
  end;
end;

{ TShellEditing }

constructor TShellEditing.Create(const AServices: TShellEditingServices);
begin
  inherited Create;
  FServices := AServices;
  FDocumentSymbols := TLspDocumentSymbols.Create(FServices.Documents);
  FDocumentSymbols.ReadText := FServices.ReadText;
  FFoldingRanges := TLspFoldingRanges.Create(FServices.Documents);
  FBlockFolds := TLspBlockFolds.Create(FServices.Documents);
  FFormatting := TFormattingProtocol.Create(FServices.Documents, FServices.FormatStyleFor, ReadEditorConfig);
  FFormatting.SlashCommandsFor := FServices.SlashCommandsFor;
  FFormatting.DelphiVersionFor := FServices.LanguageLevelFor;
  FFormatting.DocCommentsFor := FServices.DocCommentsFor;
  FFormatting.SortUses := SortUsesEdits;
  // Erzeugen-Menü (#719): dieselben Schalter, Versionen und derselbe Host wie die Schnellbefehle nach Enter.
  FSlashMenu := TSlashMenuProtocol.Create(FServices.Documents);
  FSlashMenu.SlashCommandsFor := FServices.SlashCommandsFor;
  FSlashMenu.DelphiVersionFor := LanguageLevel;
  FSlashMenu.FormatStyleFor := FServices.ResolvedFormatStyleFor;
  FSelectionRanges := TLspSelectionRanges.Create(FServices.Documents);
end;

destructor TShellEditing.Destroy;
begin
  FreeAndNil(FDocumentSymbols);
  FreeAndNil(FBlockFolds);
  FreeAndNil(FFoldingRanges);
  FreeAndNil(FFormatting);
  FreeAndNil(FSlashMenu);
  FreeAndNil(FSelectionRanges);
  inherited Destroy;
end;

function TShellEditing.GetSlashHost: ISlashHost;
begin
  Result := FFormatting.SlashHost;
end;

function TShellEditing.LanguageLevel(const AUri: string): string;
begin
  Result := FServices.LanguageLevelFor(AUri);
end;

procedure TShellEditing.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  FDocumentSymbols.Attach(ADispatcher);
  FFoldingRanges.Attach(ADispatcher);
  FBlockFolds.Attach(ADispatcher);
  FFormatting.Attach(ADispatcher);
  FSelectionRanges.Attach(ADispatcher);
end;

procedure TShellEditing.RegisterCommands(ACommands: TLspCommands);
begin
  ACommands.Register(TSlashMenuProtocol.cMenuCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FSlashMenu.ExecuteMenu(AArguments);
    end);
  ACommands.Register(TSlashMenuProtocol.cChoicesCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FSlashMenu.ExecuteChoices(AArguments);
    end);
  ACommands.Register(TSlashMenuProtocol.cRunCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FSlashMenu.ExecuteRun(AArguments);
    end);
end;

procedure TShellEditing.UseSlashHost(const AHost: ISlashHost);
begin
  FFormatting.SlashHost := AHost;
  FSlashMenu.SlashHost := AHost;
end;

procedure TShellEditing.UseIndex(const AIndex: ISymbolIndex);
begin
  FFormatting.Index := AIndex;
  // Standardsichtbarkeit published über die Vorfahren (#537).
  FDocumentSymbols.Index := AIndex;
  FSlashMenu.Index := AIndex;
end;

/// <summary>Fehlende Interface-Methoden für das Erzeugen-Menü aus der Vervollständigung ACompletion; nil ohne.
/// </summary>
function InterfaceItemsOf(ACompletion: TLspCompletion): TSlashInterfaceItemsFunc;
begin
  Result := nil;
  if ACompletion <> nil then
  begin
    Result :=
      function(const AUri, AText: string; const APosition: TTextPosition; out AItems: TArray<TCompletionItem>): Boolean
      begin
        Result := ACompletion.InterfaceItemsAt(AUri, AText, APosition, AItems);
      end;
  end;
end;

procedure TShellEditing.UseCompletion(ACompletion: TLspCompletion);
begin
  FSlashMenu.InterfaceItemsFor := InterfaceItemsOf(ACompletion);
end;

end.
