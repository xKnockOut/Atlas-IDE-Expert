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
  Atlas.Common.Editing.Contract,
  Atlas.Common.Semantics.TypeInfoClasses,
  Atlas.Common.Lsp.Commands,
  Atlas.Common.Lsp.Completion,
  Atlas.Common.Lsp.DocumentSymbols,
  Atlas.Common.Lsp.FoldingRanges,
  Atlas.Common.Lsp.SelectionRanges,
  Atlas.Common.Lsp.Formatting,
  Atlas.Common.Lsp.SlashMenu;

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
    FFormatting: TLspFormatting;
    FSlashMenu: TLspSlashMenu;
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
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.FileEncoding;

function ReadEditorConfig(const AFileName: string; out AText: string): Boolean;
begin
  Result := FileExists(AFileName);
  if Result then
  begin
    AText := TFileEncoding.LoadText(AFileName);
  end;
end;

constructor TShellEditing.Create(const AServices: TShellEditingServices);
begin
  inherited Create;
  FServices := AServices;
  FDocumentSymbols := TLspDocumentSymbols.Create(FServices.Documents);
  FDocumentSymbols.ReadText := FServices.ReadText;
  FFoldingRanges := TLspFoldingRanges.Create(FServices.Documents);
  FFormatting := TLspFormatting.Create(FServices.Documents, FServices.FormatStyleFor, ReadEditorConfig);
  FFormatting.SlashCommandsFor := FServices.SlashCommandsFor;
  FFormatting.DelphiVersionFor := FServices.LanguageLevelFor;
  FFormatting.DocCommentsFor := FServices.DocCommentsFor;
  // Erzeugen-Menü (#719): dieselben Schalter, Versionen und derselbe Host wie die Schnellbefehle nach Enter.
  FSlashMenu := TLspSlashMenu.Create(FServices.Documents);
  FSlashMenu.SlashCommandsFor := FServices.SlashCommandsFor;
  FSlashMenu.DelphiVersionFor := LanguageLevel;
  FSlashMenu.FormatStyleFor := FServices.ResolvedFormatStyleFor;
  FSelectionRanges := TLspSelectionRanges.Create(FServices.Documents);
end;

destructor TShellEditing.Destroy;
begin
  FreeAndNil(FDocumentSymbols);
  FreeAndNil(FFoldingRanges);
  FreeAndNil(FFormatting);
  FreeAndNil(FSlashMenu);
  FreeAndNil(FSelectionRanges);
  inherited Destroy;
end;

function TShellEditing.LanguageLevel(const AUri: string): string;
begin
  Result := FServices.LanguageLevelFor(AUri);
end;

function TShellEditing.GetSlashHost: ISlashHost;
begin
  Result := FFormatting.SlashHost;
end;

procedure TShellEditing.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  FDocumentSymbols.Attach(ADispatcher);
  FFoldingRanges.Attach(ADispatcher);
  FFormatting.Attach(ADispatcher);
  FSelectionRanges.Attach(ADispatcher);
end;

procedure TShellEditing.RegisterCommands(ACommands: TLspCommands);
begin
  ACommands.Register(TLspSlashMenu.cMenuCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FSlashMenu.ExecuteMenu(AArguments);
    end);
  ACommands.Register(TLspSlashMenu.cChoicesCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FSlashMenu.ExecuteChoices(AArguments);
    end);
  ACommands.Register(TLspSlashMenu.cRunCommand,
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

procedure TShellEditing.UseCompletion(ACompletion: TLspCompletion);
begin
  FSlashMenu.Completion := ACompletion;
end;

end.
