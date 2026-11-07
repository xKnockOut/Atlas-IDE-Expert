unit Shell.Linter.Settings;

// Internals-Rolle Shell: Ziel und Einstellungen des Linter-Modus (#95). atlas.json im Ordner des Ziels oder
// darüber gilt wie im Editor; globale Schlüssel aus der globalen Datei (TConfigurationScopes).

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Filter,
  Shell.CommandLine;

type
  /// <summary>Ziel aus --check und der Ordner, in dem atlas.json gesucht wird.</summary>
  TLinterTarget = record
    Target: string;
    ConfigRoot: string;
    /// <summary>Ziel ATarget; False mit Meldung auf stderr, wenn es fehlt.</summary>
    class function Resolve(const ATarget: string; out AResult: TLinterTarget): Boolean; static;
    /// <summary>Wie Resolve, ohne ATarget der aktuelle Ordner.</summary>
    class function ResolveOrCurrent(const ATarget: string; out AResult: TLinterTarget): Boolean; static;
    /// <summary>Ziel von --check wie Resolve; False mit Meldung auf stderr auch, wenn --source-root fehlt.</summary>
    class function ResolveCheck(const AOptions: TCommandLineOptions; out AResult: TLinterTarget): Boolean; static;
    /// <summary>Name des Ziels für Berichte: Ordnername bzw. Dateiname ohne Endung.</summary>
    function Title: string;
    /// <summary>Ist das Ziel ein Ordner?</summary>
    function IsFolder: Boolean;
  end;

  TLinterSettings = class
  public
    /// <summary>Einstellungen für ARoot wie im Server; Fehler in atlas.json mit Stelle auf stderr.</summary>
    class function Load(const ARoot: string): TServerSettings; static;
    /// <summary>atlas.json für ARoot: nach oben bis zum Stamm des Repositorys (.git/.svn) bzw. des Laufwerks.
    /// </summary>
    class function ConfigFileOf(const ARoot: string): string; static;
    /// <summary>Regelprofil der Kommandozeile (#146): --profile vor profile.cli vor profile.</summary>
    class procedure ApplyProfile(const AOptions: TCommandLineOptions; var ASettings: TServerSettings); static;
    /// <summary>Wurzel der SARIF-Pfade: --source-root, sonst die Git-Wurzel über AConfigRoot, sonst AConfigRoot.
    /// </summary>
    class function SourceRootOf(const AOptions: TCommandLineOptions; const AConfigRoot: string): string; static;
    /// <summary>Filter aus --rules, --units und --min-severity.</summary>
    class function FilterOf(const AOptions: TCommandLineOptions): TFindingFilter; static;
    /// <summary>Prüft Kombinationen der Befehlszeile von --check; False mit Meldung auf stderr. --update-baseline
    /// mit --changed/--diff ist erlaubt und bekommt nur einen Hinweis (die Baseline gilt immer für alle Dateien).
    /// </summary>
    class function Validate(const AOptions: TCommandLineOptions): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Configuration.Scopes,
  Atlas.Common.Query.Language,
  Atlas.Common.Rules.Output,
  Shell.Bootstrap,
  Shell.Linter.Output,
  Atlas.Common.Localization.Texts;

type
{$SCOPEDENUMS ON}
  TLinterSettingsText = (NotFound, NoSourceRoot, DiffOnly, MetricsFormat, TodosFormat, TodosMetrics, BaselineAll);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TLinterSettingsText] of TAtlasText = (
    (De: 'Ziel "%s" nicht gefunden'; En: 'Target "%s" not found'),
    (De: 'Quellwurzel "%s" nicht gefunden'; En: 'Source root "%s" not found'),
    (De: '--format diff gibt es nur mit --format-check oder --format-write';
    En: '--format diff only exists with --format-check or --format-write'),
    (De: '--metrics gibt es nur mit --format text (Markdown) oder json';
    En: '--metrics only exists with --format text (Markdown) or json'),
    (De: '--todos gibt es nur mit --format text (Markdown) oder json';
    En: '--todos only exists with --format text (Markdown) or json'),
    (De: '--todos und --metrics schließen sich aus'; En: '--todos and --metrics exclude each other'),
    (De: '--update-baseline schreibt die Baseline immer für alle Dateien; --changed/--diff wird ignoriert';
    En: '--update-baseline always writes the baseline for all files; --changed/--diff is ignored'));

{ TLinterTarget }

class function TLinterTarget.Resolve(const ATarget: string; out AResult: TLinterTarget): Boolean;
begin
  AResult := Default(TLinterTarget);
  AResult.Target := ATarget;
  Result := TFile.Exists(ATarget) or TDirectory.Exists(ATarget);
  if not Result then
  begin
    TLinterOutput.Error(cTexts[TLinterSettingsText.NotFound].Fmt([ATarget]));
    Exit;
  end;
  if AResult.IsFolder then
  begin
    AResult.ConfigRoot := TPath.GetFullPath(ATarget);
  end
  else
  begin
    AResult.ConfigRoot := ExtractFileDir(TPath.GetFullPath(ATarget));
  end;
end;

class function TLinterTarget.ResolveOrCurrent(const ATarget: string; out AResult: TLinterTarget): Boolean;
begin
  if ATarget = '' then
  begin
    Result := Resolve(GetCurrentDir, AResult);
  end
  else
  begin
    Result := Resolve(ATarget, AResult);
  end;
end;

function TLinterTarget.IsFolder: Boolean;
begin
  Result := TDirectory.Exists(Target);
end;

function TLinterTarget.Title: string;
begin
  if IsFolder then
  begin
    Result := ExtractFileName(ExcludeTrailingPathDelimiter(TPath.GetFullPath(Target)));
  end
  else
  begin
    Result := ChangeFileExt(ExtractFileName(Target), '');
  end;
end;

{ TLinterSettings }

function ConfigFileIn(const AFolder: string): string;
begin
  Result := ExistingOrLegacyFile(AFolder, cConfigurationFileName, cLegacyConfigurationFileName);
end;

/// <summary>Ist AFolder (mit Trenner am Ende) der Stamm eines Repositorys?</summary>
function IsRepositoryRoot(const AFolder: string): Boolean;
begin
  Result := DirectoryExists(AFolder + '.git') or DirectoryExists(AFolder + '.svn') or FileExists(AFolder + '.git');
end;

class function TLinterSettings.ConfigFileOf(const ARoot: string): string;
var
  mFolder, mParent: string;
begin
  // Wie der Editor (TLspConfiguration): Sonst galten bei --check Datei.pas in einem Unterordner andere Regeln als im
  // Editor. Ohne Datei bleibt der Name im Ordner des Ziels.
  Result := ConfigFileIn(ARoot);
  mFolder := IncludeTrailingPathDelimiter(ARoot);
  while not FileExists(ConfigFileIn(mFolder)) and not IsRepositoryRoot(mFolder) do
  begin
    mParent := ExtractFilePath(ExcludeTrailingPathDelimiter(mFolder));
    if (mParent = '') or SameText(mParent, mFolder) then
    begin
      Break;
    end;
    mFolder := mParent;
  end;
  if FileExists(ConfigFileIn(mFolder)) then
  begin
    Result := ConfigFileIn(mFolder);
  end;
end;

/// <summary>Fehler in AText (atlas.json) mit Stelle auf stderr, auch gespeicherte Abfragen mit Fehler (#1351).
/// </summary>
procedure ReportIssues(const AFileName, AText: string; const ASettings: TServerSettings);
var
  mIssues, mScoped: TArray<TConfigurationIssue>;
  mIssue: TConfigurationIssue;
begin
  TConfigurationParser.Parse(AText, mIssues);
  TConfigurationScopes.Filter(AText, TConfigurationScope.Project, mScoped);
  mIssues := mIssues + mScoped + TQueryParser.ConfigurationIssues(ASettings.Queries);
  for mIssue in mIssues do
  begin
    TLinterOutput.Error(Format('%s(%d,%d): %s', [AFileName, mIssue.Range.StartPos.Line + 1,
      mIssue.Range.StartPos.Character + 1, mIssue.Message]));
  end;
end;

class function TLinterSettings.Load(const ARoot: string): TServerSettings;
var
  mFileName, mText, mGlobalText: string;
  mMisplaced: TArray<TConfigurationIssue>;
begin
  // Die Meldungen des wirksamen Texts zählen nicht; ReportIssues meldet die aus atlas.json.
  // Ohne Logger: Eine nicht lesbare globale Datei bricht den Lauf ab (Exit-Code 3) wie bisher.
  mGlobalText := TShellBootstrap.LoadGlobalSettings(nil);
  mFileName := ConfigFileOf(ARoot);
  TShellBootstrap.ReadSourceText(mFileName, mText);
  Result := TConfigurationParser.Parse(TConfigurationScopes.Effective(mGlobalText, '', mText), mMisplaced);
  if mText <> '' then
  begin
    ReportIssues(mFileName, mText, Result);
  end;
end;

class procedure TLinterSettings.ApplyProfile(const AOptions: TCommandLineOptions; var ASettings: TServerSettings);
begin
  if AOptions.Profile <> '' then
  begin
    ASettings.Profile := AOptions.Profile;
  end
  else if ASettings.CliProfile <> '' then
  begin
    ASettings.Profile := ASettings.CliProfile;
  end;
end;

class function TLinterSettings.SourceRootOf(const AOptions: TCommandLineOptions; const AConfigRoot: string): string;
begin
  if AOptions.SourceRoot <> '' then
  begin
    Exit(ExcludeTrailingPathDelimiter(TPath.GetFullPath(AOptions.SourceRoot)));
  end;
  Result := TFindingsOutput.FindGitRoot(AConfigRoot,
    function(const APath: string): Boolean
    begin
      // .git ist ein Ordner, in Worktrees und Submodulen eine Datei.
      Result := TDirectory.Exists(APath) or TFile.Exists(APath);
    end);
  if Result = '' then
  begin
    Result := ExcludeTrailingPathDelimiter(AConfigRoot);
  end;
end;

class function TLinterSettings.FilterOf(const AOptions: TCommandLineOptions): TFindingFilter;
begin
  Result := Default(TFindingFilter);
  Result.Rules := AOptions.RuleFilter;
  Result.Units := AOptions.UnitFilter;
  Result.MinSeverity := AOptions.MinSeverity;
end;

class function TLinterTarget.ResolveCheck(const AOptions: TCommandLineOptions; out AResult: TLinterTarget): Boolean;
begin
  Result := Resolve(AOptions.CheckTarget, AResult);
  if Result and (AOptions.SourceRoot <> '') and not TDirectory.Exists(AOptions.SourceRoot) then
  begin
    TLinterOutput.Error(cTexts[TLinterSettingsText.NoSourceRoot].Fmt([AOptions.SourceRoot]));
    Result := False;
  end;
end;

/// <summary>Fehler der Kombination von Optionen in AOptions; '' ohne Fehler.</summary>
function OptionError(const AOptions: TCommandLineOptions): string;
begin
  Result := '';
  if AOptions.FormatDiff then
  begin
    Result := cTexts[TLinterSettingsText.DiffOnly].Text;
  end
  else if AOptions.Metrics and (AOptions.CheckFormat = TFindingsFormat.Sarif) then
  begin
    Result := cTexts[TLinterSettingsText.MetricsFormat].Text;
  end
  else if AOptions.Todos and (AOptions.CheckFormat = TFindingsFormat.Sarif) then
  begin
    Result := cTexts[TLinterSettingsText.TodosFormat].Text;
  end
  else if AOptions.Todos and AOptions.Metrics then
  begin
    Result := cTexts[TLinterSettingsText.TodosMetrics].Text;
  end;
end;

class function TLinterSettings.Validate(const AOptions: TCommandLineOptions): Boolean;
var
  mError: string;
begin
  mError := OptionError(AOptions);
  Result := mError = '';
  if not Result then
  begin
    TLinterOutput.Error(mError);
  end
  else if (AOptions.ChangedRef <> '') and AOptions.UpdateBaseline then
  begin
    TLinterOutput.Error(cTexts[TLinterSettingsText.BaselineAll].Text);
  end;
end;

initialization
  TAtlasTextTables.Add('Shell.Linter.Settings', cTexts);

end.
