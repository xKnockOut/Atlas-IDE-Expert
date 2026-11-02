unit Shell.Composition.FileOptions;

// Internals-Rolle Shell: Vorgaben je Datei für Editor, Vervollständigung, Code-Aktionen und Refactorings. Delphi-
// Version (#47) und Sprachstand (#1126), Schnellbefehle (#293), Doku-Kommentare (#88), Formatstil mit
// .editorconfig (#43) und Präfixe neuer Namen der Namensregel.

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Editing.Contract,
  Shell.Composition.Workspaces,
  Shell.Composition.Settings;

type
  /// <summary>Vorgaben je Datei aus dem Arbeitsbereich bzw. den Einstellungen ohne Ordner.</summary>
  TShellFileOptions = class
  private
    FWorkspaces: TShellWorkspaceRegistry;
    FSettings: TShellSettings;
  public
    constructor Create(AWorkspaces: TShellWorkspaceRegistry; ASettings: TShellSettings);
    /// <summary>Tatsächlich gewählte Installation (#47), sonst die konfigurierte Version; '' ohne Arbeitsbereich.
    /// </summary>
    function DelphiVersionFor(const AUri: string): string;
    /// <summary>Sprachstand (#1126): die ältere aus DelphiVersionFor und minDelphiVersion des Projekts. Gilt für
    /// Diagnosen, Code-Aktionen, Schnellbefehle und Formatieren; Hover und Hilfe-Links nehmen DelphiVersionFor.
    /// </summary>
    function LanguageLevelFor(const AUri: string): string;
    /// <summary>Schnellbefehle (#293): False = aus; ADisabled samt "uses" bei usesCommand = false (#254).
    /// </summary>
    function SlashCommandsFor(const AUri: string; out ADisabled: TArray<string>): Boolean;
    /// <summary>Schnellbefehle als Dienst für Editor und Vervollständigung.</summary>
    function SlashCommands: TSlashCommandsProvider;
    /// <summary>"completeBlocks.docComment" (#88).</summary>
    function DocCommentsFor(const AUri: string): Boolean;
    function FormatStyleFor(const AUri: string): TFormatStyle;
    /// <summary>Formatstil mit .editorconfig, ohne Editor-Optionen (#43); für Schnellbefehle und try/finally.
    /// </summary>
    function ResolvedFormatStyleFor(const AUri: string): TFormatStyle;
    /// <summary>Präfixe neuer Namen für Refactorings: die der Namensregel, wenn sie für die Datei läuft (dieselbe
    /// Entscheidung wie in der Prüfung, TRuleEngine.NewNames).</summary>
    function NewNamesFor(const AUri: string): TPascalNamePrefixes;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Pascal.LanguageFeatures,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Lsp.Formatting,
  Shell.Workspace;

constructor TShellFileOptions.Create(AWorkspaces: TShellWorkspaceRegistry; ASettings: TShellSettings);
begin
  inherited Create;
  FWorkspaces := AWorkspaces;
  FSettings := ASettings;
end;

function TShellFileOptions.DelphiVersionFor(const AUri: string): string;
var
  mWorkspace: TShellWorkspace;
begin
  System.TMonitor.Enter(FWorkspaces.Lock);
  try
    mWorkspace := FWorkspaces.Pick(TDocumentUris.ToPath(AUri));
    Result := '';
    if mWorkspace <> nil then
    begin
      Result := mWorkspace.State.DelphiVersion;
      if Result = '' then
      begin
        Result := mWorkspace.Configuration.Settings.DelphiVersion;
      end;
    end;
  finally
    System.TMonitor.Exit(FWorkspaces.Lock);
  end;
end;

function TShellFileOptions.LanguageLevelFor(const AUri: string): string;
begin
  Result := TLanguageFeatures.LanguageLevel(DelphiVersionFor(AUri), FSettings.SettingsFor(AUri).MinDelphiVersion);
end;

function TShellFileOptions.SlashCommandsFor(const AUri: string; out ADisabled: TArray<string>): Boolean;
var
  mSettings: TServerSettings;
begin
  mSettings := FSettings.SettingsFor(AUri);
  Result := mSettings.SlashCommands;
  ADisabled := mSettings.SlashCommandsDisabled;
  if not mSettings.UsesCommand then
  begin
    ADisabled := ADisabled + ['uses'];
  end;
end;

function TShellFileOptions.SlashCommands: TSlashCommandsProvider;
begin
  Result := SlashCommandsFor;
end;

function TShellFileOptions.DocCommentsFor(const AUri: string): Boolean;
begin
  Result := FSettings.SettingsFor(AUri).CompleteBlocksDocComment;
end;

function TShellFileOptions.FormatStyleFor(const AUri: string): TFormatStyle;
begin
  Result := FSettings.SettingsFor(AUri).Formatting;
end;

function TShellFileOptions.ResolvedFormatStyleFor(const AUri: string): TFormatStyle;
begin
  Result := TLspFormatting.Resolve(nil, TDocumentUris.ToPath(AUri), FormatStyleFor(AUri),
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := FileExists(AFileName);
      if Result then
      begin
        AText := TFileEncoding.LoadText(AFileName);
      end;
    end);
end;

function TShellFileOptions.NewNamesFor(const AUri: string): TPascalNamePrefixes;
var
  mFileName: string;
  mWorkspace: TShellWorkspace;
  mSettings: TServerSettings;
  mContext: TRuleContext;
begin
  mFileName := TDocumentUris.ToPath(AUri);
  mContext := Default(TRuleContext);
  System.TMonitor.Enter(FWorkspaces.Lock);
  try
    mWorkspace := FWorkspaces.Pick(mFileName);
    if mWorkspace = nil then
    begin
      mSettings := FSettings.Loose;
    end
    else
    begin
      mSettings := mWorkspace.Configuration.Settings;
      mContext.RelativePath := ExtractRelativePath(IncludeTrailingPathDelimiter(mWorkspace.Root), mFileName);
      mContext.Naming := mWorkspace.RuleServices.Naming;
    end;
  finally
    System.TMonitor.Exit(FWorkspaces.Lock);
  end;
  mContext.UnitName := ChangeFileExt(ExtractFileName(mFileName), '');
  Result := TRuleEngine.NewNames(BuiltinRules, mSettings, mContext);
end;

end.
