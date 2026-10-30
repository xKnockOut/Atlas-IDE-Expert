unit Shell.Linter;

// Host-Rolle Shell: Linter-Modus ohne Editor (#95).
//
//   AtlasServer.exe --check Projekt.dproj --format sarif --output ergebnis.sarif
//
// Ziel ist eine .dproj (Hauptdatei und Units des Projekts), ein Ordner (alle
// .pas, .dpr, .dpk darunter) oder eine einzelne Datei. atlas.json im
// Ordner des Ziels gilt wie im Editor. Das Ergebnis geht auf stdout oder in
// die Datei aus --output, Meldungen zum Ablauf auf stderr.
// Mit --suppression-stats erscheint statt der Treffer die Auswertung der
// Unterdrückungskommentare je Regel; Exit-Code dann 0.
// Mit --metrics erscheinen statt der Treffer die Code-Metriken (#66): mit
// --format text der Markdown-Bericht, mit json die Metrikdaten; Grenzwerte
// aus atlas.json (Regeln metric-*, Option "max"); Exit-Code dann 0.
// Mit --todos erscheinen statt der Treffer die offenen TODO-Einträge (#68):
// mit --format text die Markdown-Übersicht, mit json die Daten; Marken aus
// atlas.json (Regel todo-comment, Option "keywords"); Exit-Code dann 0.
// Bekannte Treffer aus der Baseline (--baseline, sonst atlas-baseline.json
// neben atlas.json) werden ausgeblendet; --update-baseline schreibt sie aus
// den aktuellen Treffern neu (#97), Exit-Code dann 0. Dabei nennt es auf
// stderr hinzugekommene, entfernte und unveränderte Treffer und, bevor sie
// herausfallen, die Einträge ohne Datei (umbenannt, verschoben, gelöscht).
// Mit --format sarif trägt jedes Ergebnis partialFingerprints und mit
// Baseline baselineState; unveränderte und nicht mehr gefundene Treffer der
// Baseline stehen dort mit, zählen aber nicht für den Exit-Code.
// Mit --changed bzw. --diff werden nur die geänderten Dateien laut Git (#157)
// bzw. SVN (#276) geprüft, mit --changed-lines nur Treffer in geänderten Zeilen ausgegeben;
// zusammen mit der Baseline zählt ein Treffer nur, wenn er in einer geänderten
// Zeile liegt und nicht in der Baseline steht. Die Regeln prüfen jede Datei für
// sich, deshalb ergibt die Teilmenge dieselben Treffer wie ein voller Lauf.
// SARIF-Pfade sind relativ zur Quellwurzel (--source-root, sonst die
// Git-Wurzel über dem Ziel, sonst der Ordner des Ziels).
// Bei einer .dproj gelten deren Symbole für Plattform und Konfiguration aus
// atlas.json, und {$I}-Dateien werden über ihre Suchpfade gelesen (#860);
// sonst die Vordefinitionen von Delphi 13 für Win32 und $I aus dem Ordner der Datei.
// Symbolindex (#1112): Wie im Server und im MCP-Modus baut --check den Index des
// Projekts (Ordner, .dproj oder Ordner der Datei, mit index.projectGroup die
// ganze Gruppe) und liest dabei den gemeinsamen Index-Cache (--index-cache,
// sonst der Ordner des Servers), damit Regeln Typen aus anderen Units und der
// RTL kennen. --no-index prüft wie früher jede Datei für sich.
// --affected-tests (#1353, TLinterShell.AffectedTests): statt der Prüfung die
// DUnitX-Tests, die eine Änderung gegenüber der Basis betrifft; Ziel ist das
// Testprojekt (.dproj), die Projektgruppe (.groupproj) oder ein Ordner. Exit-Code
// 0, 2 wenn alle Tests nötig sind (die Ausgabe sagt warum), 3 bei Fehlern und
// mit tests.affected = false.
// Sammelkorrektur (#1352): --fix <Regeln|all> wendet je Datei die sicheren
// Korrekturen dieser Regeln an (TBulkFix: Konfidenz ab fix.minConfidence,
// Katalogfeld safeFix, bis zu drei Durchgänge, keine neuen Syntaxfehler) und
// schreibt alle geänderten Dateien oder keine, in ihrer Kodierung und mit ihren
// Zeilenenden; --fix-dry-run gibt stattdessen den vereinigten Diff aus. Es gelten
// --units, --changed, --diff, --changed-lines (nur Treffer in geänderten Zeilen),
// --baseline (deren Treffer bleiben) und --profile. Die Zusammenfassung (Regeln,
// Dateien, Korrekturen je Regel, übersprungene Treffer) steht auf stderr.
//
// Mit --timings (#1356) misst der Lauf die Prüfung je Unit und, über die
// Messung der Regel-Engine, je Regel (TCheckProfiler) und schreibt danach
// das Zeitprofil mit Indexzeit und Speicher als Markdown bzw. JSON in die
// Datei oder ohne Datei auf stderr. stdout und --output bleiben unverändert.
// Exit-Code: 1, wenn ein Treffer --fail-on erreicht (Standard error: mindestens
// ein Fehler; Baseline-Treffer zählen nie), sonst 0; 3 Aufruf- oder Lesefehler.
// Mit --fix zählen die Treffer, die nach der Korrektur bleiben.
// Formatieren ohne IDE (#1358): --format-check bzw. --format-write statt der
// Regeln. Dieselben Dateien wie --check (Ziel, --units, --changed/--diff,
// Ausschlüsse aus atlas.json), mit --changed-lines nur die geänderten Zeilen.
// Formatregeln wie „Dokument formatieren“: format.* aus atlas.json über
// .editorconfig über den Vorgaben (ohne die Einrückung der IDE-Optionen).
// Geschrieben wird atomar über eine Nachbardatei; Kodierung und Zeilenenden
// bleiben, außer format.endOfLine verlangt andere. Exit-Codes in
// Atlas.Common.Rules.FormatOutput.

interface

uses
  Shell.CommandLine;

type
  TLinterShell = class
  public
    class function Run(const AOptions: TCommandLineOptions): Integer; static;
    /// <summary>--fix (#1352): Sammelkorrektur statt Prüfung; Run ruft sie, sobald --fix angegeben ist.</summary>
    class function Fix(const AOptions: TCommandLineOptions): Integer; static;
    /// <summary>--architecture (#1118): Architekturbericht des Ziels aus --check (sonst des aktuellen Ordners)
    /// als Markdown oder HTML nach der Endung der Datei, als .json der Stand für den Vergleich (#1121). Berichte
    /// vergleichen mit --compare, sonst mit architecture.baseline. Mit --compare steht der Text des Vergleichs auf
    /// stdout (bzw. in --output); Exit-Code 1, wenn eine Abweichung aus --fail-on (sonst architecture.failOn)
    /// vorkommt, sonst 0; bei Fehlern 3.</summary>
    class function Architecture(const AOptions: TCommandLineOptions): Integer; static;
    /// <summary>--hotspots (#1354): Hotspots des Ziels aus --check (sonst des aktuellen Ordners) samt Methoden und
    /// Änderungskopplung als Markdown, HTML oder JSON nach der Endung der Datei. Exit-Code 0; 3 ohne
    /// Versionsverwaltung, mit hotspots.enabled = false und bei Fehlern.</summary>
    class function Hotspots(const AOptions: TCommandLineOptions): Integer; static;
    /// <summary>--format-check bzw. --format-write (#1358), siehe Kopf der Unit.</summary>
    class function Formatting(const AOptions: TCommandLineOptions): Integer; static;
    /// <summary>--clear-cache: löscht alle Index-Caches, die keine laufende Instanz nutzt (#184).</summary>
    class function ClearCache: Integer; static;
    /// <summary>--affected-tests (#1353): betroffene Tests als text, json oder dunitx (--format) auf stdout bzw. in
    /// --output. Exit-Code 0; 2, wenn alle Tests nötig sind; 3 bei Fehlern oder mit tests.affected = false.
    /// </summary>
    class function AffectedTests(const AOptions: TCommandLineOptions): Integer; static;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Diagnostics,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Configuration.Scopes,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Projects.DprojReader,
  Atlas.Common.Projects.PackageReader,
  Atlas.Common.Projects.DelphiVersions,
  Atlas.Common.Index.ProjectFiles,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Pascal.IncludeFiles,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Rules.Filter,
  Atlas.Common.Rules.Output,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.SuppressionStats,
  Atlas.Common.Rules.Builtin.Metrics,
  Atlas.Common.Rules.Builtin.FormFields,
  Atlas.Common.Metrics.Contract,
  Atlas.Common.Metrics.Calculator,
  Atlas.Common.Metrics.Report,
  Atlas.Common.Todos.Contract,
  Atlas.Common.Todos.Scanner,
  Atlas.Common.Todos.Report,
  Atlas.Common.Rules.Builtin.Todos,
  Atlas.Common.Rules.Baseline,
  Atlas.Common.Rules.Scopes,
  Atlas.Common.Rules.ChangedFiles,
  Atlas.Common.Rules.Catalog,
  Atlas.Common.Rules.BulkFix,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Index.Adapters.CacheDirectory,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Processes,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.Logging.Providers.StreamSink,
  Shell.WorkspaceGroup,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Architecture.Overview,
  Atlas.Common.Architecture.Service,
  Atlas.Common.Architecture.Report,
  Atlas.Common.Architecture.Snapshot,
  Atlas.Common.Architecture.Comparison,
  Atlas.Common.Hotspots.Contract,
  Atlas.Common.Hotspots.Analysis,
  Atlas.Common.Hotspots.Service,
  Atlas.Common.Hotspots.Report,
  Atlas.Common.Diagnostics.CheckProfile,
  Atlas.Common.Diagnostics.ShutdownLeaks,
  Atlas.Common.Editing.FormatCheck,
  Atlas.Common.Rules.FormatOutput,
  Atlas.Common.Lsp.Formatting,
  Atlas.Common.Editing.EditorConfig,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.References,
  Atlas.Common.Lsp.Impact,
  Atlas.Common.Lsp.AffectedTests,
  Shell.Platform,
  Shell.VcsChanges,
  Shell.AffectedTests,
  Shell.Hotspots,
  Shell.Bootstrap;

procedure WriteText(const AStream: TStream; const AText: string);
var
  Bytes: TBytes;
begin
  Bytes := TEncoding.UTF8.GetBytes(AText);
  if Length(Bytes) > 0 then
    AStream.WriteBuffer(Bytes[0], Length(Bytes));
end;

procedure WriteError(const AText: string);
var
  Stream: TStream;
begin
  Stream := TStdStreams.CreateError;
  try
    WriteText(Stream, AText + sLineBreak);
  finally
    Stream.Free;
  end;
end;

/// <summary>Ergebnis nach --output (UTF-8 ohne BOM), sonst auf stdout.</summary>
procedure WriteOutput(const AOptions: TCommandLineOptions; const AText: string);
var
  Encoding: TEncoding;
  Stream: TStream;
begin
  if AOptions.OutputFile <> '' then
  begin
    Encoding := TUTF8Encoding.Create(False);
    try
      TFile.WriteAllText(AOptions.OutputFile, AText, Encoding);
    finally
      Encoding.Free;
    end;
  end
  else
  begin
    Stream := TStdStreams.CreateOutput;
    try
      WriteText(Stream, AText);
    finally
      Stream.Free;
    end;
  end;
end;

function IsSourceFile(const AFileName: string): Boolean;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(AFileName));
  Result := (Ext = '.pas') or (Ext = '.dpr') or (Ext = '.dpk');
end;

// Wie im Server: globale Datei für globale Schlüssel, atlas.json für Projekt-Schlüssel (TConfigurationScopes).
function LoadSettings(const ARoot: string): TServerSettings;
var
  FileName, Text, GlobalText: string;
  Issues, Misplaced: TArray<TConfigurationIssue>;
  Issue: TConfigurationIssue;
begin
  // Ohne Logger: Eine nicht lesbare globale Datei bricht den Lauf ab (Exit-Code 3) wie bisher.
  GlobalText := TShellBootstrap.LoadGlobalSettings(nil);
  FileName := ExistingOrLegacyFile(ARoot, ConfigurationFileName, LegacyConfigurationFileName);
  TShellBootstrap.ReadSourceText(FileName, Text);
  Result := TConfigurationParser.Parse(TConfigurationScopes.Effective(GlobalText, '', Text), Misplaced);
  if Text = '' then
    Exit;
  TConfigurationParser.Parse(Text, Issues);
  TConfigurationScopes.Filter(Text, TConfigurationScope.Project, Misplaced);
  Issues := Issues + Misplaced;
  for Issue in Issues do
    WriteError(Format('%s(%d,%d): %s', [FileName, Issue.Range.StartPos.Line + 1,
      Issue.Range.StartPos.Character + 1, Issue.Message]));
end;

/// <summary>Symbole und Include-Dateien der Prüfung (#860): ADefines und die Suchpfade des Projekts.</summary>
function CheckSourcesOf(const ADefines, AIncludePaths: TArray<string>): TCheckSourceFunc;
var
  Resolver: TIncludeResolver;
begin
  Resolver := TIncludeFiles.Resolver(AIncludePaths);
  Result :=
    function(const AFileName: string): TCheckSource
    begin
      Result := TCheckSource.Create(AFileName, ADefines, Resolver);
    end;
end;

function CollectFiles(const ATarget: string; const ASettings: TServerSettings; out ARoot: string;
  out ASources: TCheckSourceFunc): TArray<string>;
var
  Options: TDprojOptions;
  Project: TProjectInfo;
  ProjectUnit: TProjectUnit;
  Files: TList<string>;
  FileName, Version: string;
begin
  ASources := CheckSourcesOf(nil, nil);
  Files := TList<string>.Create;
  try
    if TDirectory.Exists(ATarget) then
    begin
      ARoot := ExcludeTrailingPathDelimiter(TPath.GetFullPath(ATarget));
      for FileName in TDirectory.GetFiles(ARoot, '*.*', TSearchOption.soAllDirectories) do
        if IsSourceFile(FileName) then
          Files.Add(FileName);
    end
    else if SameText(ExtractFileExt(ATarget), '.dproj') then
    begin
      ARoot := ExtractFileDir(TPath.GetFullPath(ATarget));
      Options := Default(TDprojOptions);
      Options.Config := ASettings.Config;
      Options.Platform := ASettings.Platform;
      Options.FileExists :=
        function(APath: string): Boolean
        begin
          Result := TFile.Exists(APath) or TDirectory.Exists(APath);
        end;
      Project := TDprojReader.Load(TPath.GetFullPath(ATarget), Options);
      // Symbole wie im Editor: .dproj, Plattform, Compilerversion und Schalter (#860); ohne installiertes
      // Delphi die Version, die das Projekt erwartet (#1321).
      Version := TDelphiVersions.Choose(ASettings.DelphiVersion,
        TDelphiVersions.ProjectVersionOf(TFileEncoding.LoadText(TPath.GetFullPath(ATarget))), TDelphiInstallation.Versions);
      ASources := CheckSourcesOf(TIndexProjectFiles.Defines(Project, Version), Project.SearchPaths);
      if (Project.MainSource <> '') and TFile.Exists(Project.MainSource) then
        Files.Add(Project.MainSource);
      for ProjectUnit in Project.Units do
        if IsSourceFile(ProjectUnit.FileName) and TFile.Exists(ProjectUnit.FileName) and
          not Files.Contains(ProjectUnit.FileName) then
          Files.Add(ProjectUnit.FileName);
    end
    else
    begin
      ARoot := ExtractFileDir(TPath.GetFullPath(ATarget));
      Files.Add(TPath.GetFullPath(ATarget));
    end;
    Result := Files.ToArray;
  finally
    Files.Free;
  end;
end;

/// <summary>Teilmenge von AFiles nach den Änderungen laut Git; AGit bleibt für --changed-lines geladen.</summary>
// Die .dpk unter AFiles, damit Regeln wissen, welche Unit zu einem Package gehört (#943).
function ReadPackages(const AFiles: TArray<string>): TArray<TPackageSource>;
var
  FileName: string;
  FileFormat: TFileFormat;
begin
  Result := nil;
  for FileName in AFiles do
    if SameText(ExtractFileExt(FileName), '.dpk') then
      try
        Result := Result + [TPackageReader.Read(TFileEncoding.LoadFromFile(FileName, FileFormat))];
      except
        on E: Exception do
          WriteError(Format('%s: %s', [FileName, E.Message]));
      end;
end;

// Quelltexte der Programme (.dpr) für die CreateForm-Reihenfolge (form-access-before-create, #956).
function ReadPrograms(const AFiles: TArray<string>): TArray<string>;
var
  FileName: string;
  FileFormat: TFileFormat;
begin
  Result := nil;
  for FileName in AFiles do
    if SameText(ExtractFileExt(FileName), '.dpr') then
      try
        Result := Result + [TFileEncoding.LoadFromFile(FileName, FileFormat)];
      except
        on E: Exception do
          WriteError(Format('%s: %s', [FileName, E.Message]));
      end;
end;

function SelectChanged(const AOptions: TCommandLineOptions;
  const AFiles: TArray<string>; AGit: TVcsChanges): TArray<string>;
begin
  AGit.Load(AOptions.ChangedRef, AOptions.ChangedMergeBase,
    AOptions.ChangedMergeBase and (AOptions.ChangedRef = TCommandLineOptions.DefaultChangedBase),
    AOptions.IncludeUncommitted, AOptions.ChangedLines);
  Result := TChangedFiles.Select(AGit.Files, AFiles,
    function(const AFileName: string): TArray<string>
    var
      FileFormat: TFileFormat;
    begin
      try
        Result := TChangedFiles.IncludeNames(TFileEncoding.LoadFromFile(AFileName, FileFormat));
      except
        on EFileStreamError do
          Result := nil;
      end;
    end);
  WriteError(Format('%s: %d von %d Dateien geändert gegenüber %s', [AGit.Name, Length(Result), Length(AFiles),
    AOptions.ChangedRef]));
end;

/// <summary>Nur Treffer in geänderten Zeilen von AFileName.</summary>
function InChangedLines(const AFindings: TArray<TRuleFinding>; AGit: TVcsChanges;
  const AFileName: string): TArray<TRuleFinding>;
var
  Lines: TChangedLines;
  Finding: TRuleFinding;
begin
  Result := nil;
  if not TChangedFiles.LinesOf(AGit.Lines, AGit.RepoRoot, AFileName, Lines) then
    Exit;
  for Finding in AFindings do
    if Lines.Contains(Finding.Range.StartPos.Line) then
      Result := Result + [Finding];
end;

/// <summary>Treffer mit Fingerabdrücken für SARIF (#97) nach Filter und --changed-lines. Nicht mehr gefundene
/// Einträge haben keine Zeile: Sie entfallen mit --changed-lines und tragen für den Filter den Standard-Schweregrad
/// ihrer Regel.</summary>
function KeptMarks(const AMarks: TArray<TBaselineMark>; const AFilter: TFindingFilter;
  const ASettings: TServerSettings; const ADescriptors: TArray<TRuleDescriptor>; AGit: TVcsChanges;
  AChangedLines: Boolean; const AFileName: string): TArray<TBaselineMark>;
var
  Lines: TChangedLines;
  HasLines: Boolean;
  Mark, Item: TBaselineMark;
  Descriptor: TRuleDescriptor;
  Severity: TRuleSeverity;
begin
  Result := nil;
  HasLines := (AGit <> nil) and AChangedLines;
  if HasLines and not TChangedFiles.LinesOf(AGit.Lines, AGit.RepoRoot, AFileName, Lines) then
    Exit;
  for Mark in AMarks do
  begin
    Item := Mark;
    if Item.State = TBaselineState.Absent then
    begin
      if HasLines then
        Continue;
      Severity := TRuleSeverity.Hint;
      for Descriptor in ADescriptors do
        if SameText(Descriptor.Id, Item.Finding.RuleId) then
          Severity := Descriptor.DefaultSeverity;
      Item.Finding.Severity := ASettings.RuleSeverity(Item.Finding.RuleId, Severity);
    end
    else if HasLines and not Lines.Contains(Item.Finding.Range.StartPos.Line) then
      Continue;
    if AFilter.AcceptsFinding(Item.Finding) then
      Result := Result + [Item];
  end;
end;

/// <summary>Nur die Treffer, die nicht in der Baseline stehen.</summary>
function NewFindings(const AMarks: TArray<TBaselineMark>): TArray<TRuleFinding>;
var
  Mark: TBaselineMark;
begin
  Result := nil;
  for Mark in AMarks do
    if Mark.State = TBaselineState.New then
      Result := Result + [Mark.Finding];
end;

/// <summary>Einträge ohne Datei bei --update-baseline auf stderr (#97), bevor die neue Datei sie entfernt.
/// </summary>
procedure ReportBaselineOrphans(const AUpdate: TBaselineUpdate);
var
  Orphan: TBaselineOrphan;
begin
  if Length(AUpdate.Orphans) = 0 then
    Exit;
  WriteError(Format('%d Einträge ohne Datei werden entfernt (Datei umbenannt, verschoben oder gelöscht):',
    [AUpdate.OrphanCount]));
  for Orphan in AUpdate.Orphans do
    WriteError(Format('  %s (%d)', [Orphan.Path, Orphan.Count]));
end;

/// <summary>Zähler nach --update-baseline auf stderr (#97).</summary>
procedure ReportBaselineUpdate(const AUpdate: TBaselineUpdate; const APath: string);
begin
  WriteError(Format('Baseline geschrieben: %s (%d Treffer, %d Dateien geprüft; %d neu, %d entfernt, %d unverändert)',
    [APath, AUpdate.Total, AUpdate.Files, AUpdate.Added, AUpdate.Removed, AUpdate.Unchanged]));
  if AUpdate.Completed > 0 then
    WriteError(Format('%d Einträge der älteren Baseline um die Routine ergänzt', [AUpdate.Completed]));
end;

/// <summary>--source-root, sonst die Git-Wurzel über AConfigRoot, sonst AConfigRoot.</summary>
function SourceRootOf(const AOptions: TCommandLineOptions; const AConfigRoot: string): string;
begin
  if AOptions.SourceRoot <> '' then
    Exit(ExcludeTrailingPathDelimiter(TPath.GetFullPath(AOptions.SourceRoot)));
  Result := TFindingsOutput.FindGitRoot(AConfigRoot,
    function(const APath: string): Boolean
    begin
      // .git ist ein Ordner, in Worktrees und Submodulen eine Datei.
      Result := TDirectory.Exists(APath) or TFile.Exists(APath);
    end);
  if Result = '' then
    Result := ExcludeTrailingPathDelimiter(AConfigRoot);
end;

/// <summary>Projekt einer geprüften Datei: Package aus APackages, Formulare der Programme, Formulardatei daneben und
/// mit AGroup Index und Projektdienste (#1112) wie im Server.</summary>
function CheckProjectOf(const AFileName: string; const APackages: TArray<TPackageSource>;
  const APrograms: TArray<string>; AGroup: TShellWorkspaceGroup): TCheckProject;
var
  mIndexed: TCheckProject;
begin
  Result := TFileChecker.PackageOf(APackages, ChangeFileExt(ExtractFileName(AFileName), ''));
  if Result.Name = '' then
    Result.AutoCreateForms := TFormAccessBeforeCreateRule.FormsOfProgram(APrograms,
      ChangeFileExt(ExtractFileName(AFileName), ''));
  // Formulardatei und Dateien neben der Unit wie im Server (form-resource-missing, #1054).
  Result.FileName := TPath.GetFullPath(AFileName);
  if AGroup = nil then
    Exit;
  // Index, Nachladen und Projekte der Gruppe auf demselben Weg wie Server und MCP (#1112); gehört die
  // Datei zu einem geladenen Projekt, gelten dessen Anwendungsart und Formulare.
  mIndexed := AGroup.RuleProject(Result.FileName);
  Result.Services := mIndexed.Services;
  if mIndexed.Application <> TRuleApplicationKind.Unknown then
  begin
    Result.Application := mIndexed.Application;
    Result.Name := mIndexed.Name;
    Result.AutoCreateForms := mIndexed.AutoCreateForms;
    Result.ProjectMainSource := mIndexed.ProjectMainSource;
  end;
end;

/// <summary>--timings (#1356): Zeitprofil in die Datei (Markdown, mit .json als JSON) oder auf stderr.</summary>
procedure WriteTimings(const AOptions: TCommandLineOptions; const ATimings: TCheckTimings);
var
  mJson: TJSONObject;
  mText: string;
  mEncoding: TEncoding;
begin
  if TCheckTimings.IsJsonFile(AOptions.TimingsFile) then
  begin
    mJson := ATimings.ToJson;
    try
      mText := mJson.Format(2);
    finally
      mJson.Free;
    end;
  end
  else
    mText := ATimings.ToMarkdown;
  if AOptions.TimingsFile = '' then
  begin
    WriteError(mText);
    Exit;
  end;
  ForceDirectories(ExtractFileDir(TPath.GetFullPath(AOptions.TimingsFile)));
  mEncoding := TUTF8Encoding.Create(False);
  try
    TFile.WriteAllText(AOptions.TimingsFile, mText, mEncoding);
  finally
    mEncoding.Free;
  end;
  WriteError(Format('Zeitprofil geschrieben: %s', [AOptions.TimingsFile]));
end;

const
  /// <summary>Höchstens so lange auf den Index warten; danach mit dem bis dahin aufgebauten prüfen.</summary>
  IndexTimeoutMs = 30 * 60 * 1000;

/// <summary>Arbeitsbereiche mit Symbolindex für --check (#1112), wie im MCP-Modus; wartet auf den Index.
/// </summary>
function LoadIndex(const AOptions: TCommandLineOptions; const AConfigRoot: string;
  var ATimings: TCheckTimings): TShellWorkspaceGroup;
var
  LoggerImpl: TLogger;
  Logger: ILogger;
  Store: IDocumentStore;
  Index: ISymbolIndex;
  Identity: TIndexProcessInfo;
  Watch: TStopwatch;
begin
  LoggerImpl := TLogger.Create;
  Logger := LoggerImpl;
  // Nur Warnungen und Fehler auf stderr; stdout gehört dem Ergebnis.
  LoggerImpl.AddSink(TStreamLogSink.Create(TStdStreams.CreateError, True), TLogLevel.Warning);
  Store := TDocumentStore.Create(
    function(const APath: string): string
    begin
      Result := TShellPlatform.CanonicalizePath(APath);
    end);
  Index := TSymbolIndex.Create;
  // Als anonyme Methode statt TShellBootstrap.ReadSourceText: Free Pascal (Linux-Bau) bricht an der Umwandlung
  // einer Klassenmethode in eine Methodenreferenz intern ab.
  Result := TShellWorkspaceGroup.Create(ExcludeTrailingPathDelimiter(AConfigRoot), Store, Logger, Index,
    'atlas-check-index',
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := TShellBootstrap.ReadSourceText(AFileName, AText);
    end);
  try
    if SameText(ExtractFileExt(AOptions.CheckTarget), '.dproj') then
      Result.Main.ProjectFile := TPath.GetFullPath(AOptions.CheckTarget);
    if AOptions.IndexCacheFolder <> '' then
      Result.CacheRoot := ExcludeTrailingPathDelimiter(TPath.GetFullPath(AOptions.IndexCacheFolder));
    // Anmeldung am Index-Cache für „Prozesse am Projekt“ (#62).
    Identity := Default(TIndexProcessInfo);
    Identity.Pid := TShellPlatform.CurrentProcessId;
    Identity.Kind := TIndexProcessInfo.KindCheck;
    Identity.Client := 'atlas --check';
    Result.ProcessIdentity := Identity;
    Watch := TStopwatch.StartNew;
    Result.Load(TShellBootstrap.LoadGlobalSettings(nil));
    if not Result.WaitForIndex(IndexTimeoutMs) then
      WriteError(Format('Symbolindex nach %d Minuten nicht fertig; Prüfung mit dem bisher aufgebauten Index',
        [IndexTimeoutMs div 60000]))
    else if Index.UnitCount = 0 then
      WriteError('Kein Projekt gefunden; Prüfung ohne Symbolindex')
    else
      // Anzeige für Menschen auf stderr: Dezimaltrenner des Gebietsschemas.
      WriteError(Format('Symbolindex: %d Units in %.1f s', [Index.UnitCount, Watch.ElapsedMilliseconds / 1000],
        FormatSettings));
    // Zeitprofil (#1356): Aufbau und Speicher des Index.
    ATimings.IndexMs := Watch.ElapsedMilliseconds;
    ATimings.IndexUnits := Index.UnitCount;
    ATimings.ProjectBytes := Index.MemoryParts.ProjectBytes;
    ATimings.LibraryBytes := Index.MemoryParts.LibraryBytes;
    ATimings.UsageBytes := Index.MemoryParts.UsageBytes;
  except
    Result.Free;
    raise;
  end;
end;

class function TLinterShell.Architecture(const AOptions: TCommandLineOptions): Integer;
var
  Target, ConfigRoot, Root, FileName, Text: string;
  Settings: TServerSettings;
  Sources: TCheckSourceFunc;
  Source: TCheckSource;
  Index: ISymbolIndex;
  Service: TArchitectureService;
  Request: TArchitectureRequest;
  Overview: TArchitectureOverview;
  FileFormat: TFileFormat;
  Warning, Extension, Baseline, Error: string;
  FailOn: TArchitectureFailKinds;
  Comparison: TArchitectureComparison;
  Compared: Boolean;
begin
  for Warning in AOptions.Warnings do
    WriteError(Warning);
  Extension := LowerCase(ExtractFileExt(AOptions.ArchitectureFile));
  if (Extension <> '.md') and (Extension <> '.html') and (Extension <> '.htm') and (Extension <> '.json') then
  begin
    WriteError('--architecture erwartet eine .md-, .html- oder .json-Datei');
    Exit(TFindingsOutput.ExitFailure);
  end;
  FailOn := [];
  if (AOptions.CompareFile <> '') and (AOptions.FailOnText <> '') and
    not TArchitectureComparer.ParseKindList(AOptions.FailOnText, FailOn, Error) then
  begin
    WriteError('--fail-on: ' + Error);
    Exit(TFindingsOutput.ExitFailure);
  end;
  Target := AOptions.CheckTarget;
  if Target = '' then
    Target := GetCurrentDir;
  if not (TFile.Exists(Target) or TDirectory.Exists(Target)) then
  begin
    WriteError(Format('Ziel "%s" nicht gefunden', [Target]));
    Exit(TFindingsOutput.ExitFailure);
  end;
  try
    if TDirectory.Exists(Target) then
      ConfigRoot := TPath.GetFullPath(Target)
    else
      ConfigRoot := ExtractFileDir(TPath.GetFullPath(Target));
    Settings := LoadSettings(ConfigRoot);
    if not Settings.ArchitectureEnabled then
    begin
      WriteError('Architekturübersicht ist ausgeschaltet (architecture.enabled in settings.json)');
      Exit(TFindingsOutput.ExitFailure);
    end;
    TFileEncodingDefaults.SetFolder(ConfigRoot, Settings.DefaultEncoding);
    // Dieselben Dateien und Symbole wie --check; der Index enthält nur das Projekt (keine Bibliothek).
    Index := TSymbolIndex.Create;
    for FileName in CollectFiles(Target, Settings, Root, Sources) do
      try
        Text := TFileEncoding.LoadFromFile(FileName, FileFormat);
        Source := Sources(FileName);
        Index.AddUnit(TIndexExtractor.ExtractText(Text, FileName, Source.Defines, Source.ResolveInclude));
      except
        on E: Exception do
          WriteError(Format('%s: %s', [FileName, E.Message]));
      end;
    Service := TArchitectureService.Create(Index,
      function(const AFileName: string; out AText: string): Boolean
      var
        Format_: TFileFormat;
      begin
        try
          AText := TFileEncoding.LoadFromFile(AFileName, Format_);
          Result := True;
        except
          AText := '';
          Result := False;
        end;
      end,
      function(const AFileName: string): TArray<string>
      begin
        Result := Sources(AFileName).Defines;
      end);
    try
      Request := TArchitectureRequest.FromSettings(Settings);
      Request.Root := Root;
      if TDirectory.Exists(Target) then
        Request.Title := ExtractFileName(ExcludeTrailingPathDelimiter(TPath.GetFullPath(Target)))
      else
        Request.Title := ChangeFileExt(ExtractFileName(Target), '');
      // Angleichung (#1367) nur an architecture.baseline; ohne PreviousFile liest und schreibt der Lauf keinen
      // zuletzt berechneten Stand, damit CI-Läufe reproduzierbar bleiben.
      Request.Baseline := TArchitectureComparer.ResolvePath(ConfigRoot, Settings.ArchitectureBaseline);
      Request.PreviousFile := '';
      Overview := Service.Overview(Request);
    finally
      Service.Free;
    end;
    // Vergleich (#1121): --compare relativ zum aktuellen Ordner, sonst architecture.baseline relativ zum Projekt.
    if AOptions.CompareFile <> '' then
      Baseline := TPath.GetFullPath(AOptions.CompareFile)
    else
      Baseline := TArchitectureComparer.ResolvePath(ConfigRoot, Settings.ArchitectureBaseline);
    if (AOptions.CompareFile = '') or (AOptions.FailOnText = '') then
      if not TArchitectureComparer.ParseKinds(Settings.ArchitectureFailOn, FailOn, Error) then
        FailOn := TArchitectureComparer.DefaultFailOn;
    Compared := False;
    if Baseline <> '' then
    begin
      Compared := TArchitectureComparer.CompareWithFile(Baseline, Overview, Comparison, Error);
      if not Compared then
      begin
        WriteError(Error);
        // Ohne lesbaren Stand kann --compare nichts prüfen; der Bericht mit architecture.baseline entsteht trotzdem.
        if AOptions.CompareFile <> '' then
          Exit(TFindingsOutput.ExitFailure);
      end;
    end;
    if Extension = '.json' then
      TArchitectureSnapshots.Save(AOptions.ArchitectureFile, TArchitectureSnapshots.FromOverview(Overview))
    else
    begin
      ForceDirectories(ExtractFileDir(TPath.GetFullPath(AOptions.ArchitectureFile)));
      if Compared then
        TFile.WriteAllBytes(AOptions.ArchitectureFile, TEncoding.UTF8.GetBytes(TArchitectureReport.ForFile(Overview,
          AOptions.ArchitectureFile, Comparison, FailOn)))
      else
        TFile.WriteAllBytes(AOptions.ArchitectureFile, TEncoding.UTF8.GetBytes(TArchitectureReport.ForFile(Overview,
          AOptions.ArchitectureFile)));
    end;
    WriteError(Format('Architekturbericht %s: %d Units, %d Teilsysteme, %d Zyklen, %d Querverbindungen',
      [AOptions.ArchitectureFile, Length(Overview.Units), Length(Overview.Subsystems), Length(Overview.Cycles),
      Length(Overview.CrossLinks)]));
    Result := TFindingsOutput.ExitClean;
    if Compared and (AOptions.CompareFile <> '') then
    begin
      WriteOutput(AOptions, TArchitectureComparer.Text(Comparison, FailOn, 0) + sLineBreak);
      if Comparison.Kinds * FailOn <> [] then
        Result := TFindingsOutput.ExitFindings;
    end;
  except
    on E: Exception do
    begin
      WriteError(E.Message);
      Result := TFindingsOutput.ExitFailure;
    end;
  end;
end;

class function TLinterShell.Hotspots(const AOptions: TCommandLineOptions): Integer;
var
  mTarget, mConfigRoot, mRoot, mFileName, mText, mWarning, mExtension, mError: string;
  mSettings: TServerSettings;
  mSources: TCheckSourceFunc;
  mSource: TCheckSource;
  mIndex: ISymbolIndex;
  mService: THotspotService;
  mRequest: THotspotRequest;
  mResult: THotspotResult;
  mFormat: TFileFormat;
  mVcs: IHotspotVcs;
begin
  for mWarning in AOptions.Warnings do
    WriteError(mWarning);
  mExtension := LowerCase(ExtractFileExt(AOptions.HotspotsFile));
  if (mExtension <> '.md') and (mExtension <> '.html') and (mExtension <> '.htm') and (mExtension <> '.json') then
  begin
    WriteError('--hotspots erwartet eine .md-, .html- oder .json-Datei');
    Exit(TFindingsOutput.ExitFailure);
  end;
  mTarget := AOptions.CheckTarget;
  if mTarget = '' then
    mTarget := GetCurrentDir;
  if not (TFile.Exists(mTarget) or TDirectory.Exists(mTarget)) then
  begin
    WriteError(Format('Ziel "%s" nicht gefunden', [mTarget]));
    Exit(TFindingsOutput.ExitFailure);
  end;
  try
    if TDirectory.Exists(mTarget) then
      mConfigRoot := TPath.GetFullPath(mTarget)
    else
      mConfigRoot := ExtractFileDir(TPath.GetFullPath(mTarget));
    mSettings := LoadSettings(mConfigRoot);
    if not mSettings.HotspotsEnabled then
    begin
      WriteError('Hotspots sind ausgeschaltet (hotspots.enabled in settings.json)');
      Exit(TFindingsOutput.ExitFailure);
    end;
    if not TShellHotspotVcs.Detect(mConfigRoot, mSettings, mVcs, mError) then
    begin
      WriteError('Hotspots brauchen eine Versionsverwaltung: ' + mError);
      Exit(TFindingsOutput.ExitFailure);
    end;
    TFileEncodingDefaults.SetFolder(mConfigRoot, mSettings.DefaultEncoding);
    // Dieselben Dateien wie --check; der Index enthält nur das Projekt (keine Bibliothek).
    mIndex := TSymbolIndex.Create;
    for mFileName in CollectFiles(mTarget, mSettings, mRoot, mSources) do
      try
        mText := TFileEncoding.LoadFromFile(mFileName, mFormat);
        mSource := mSources(mFileName);
        mIndex.AddUnit(TIndexExtractor.ExtractText(mText, mFileName, mSource.Defines, mSource.ResolveInclude));
      except
        on E: Exception do
          WriteError(Format('%s: %s', [mFileName, E.Message]));
      end;
    mService := THotspotService.Create(mIndex,
      function(const AFileName: string; out AText: string): Boolean
      var
        mTextFormat: TFileFormat;
      begin
        try
          AText := TFileEncoding.LoadFromFile(AFileName, mTextFormat);
          Result := True;
        except
          AText := '';
          Result := False;
        end;
      end);
    try
      mRequest := THotspotRequest.FromSettings(mSettings);
      // Der Bericht zeigt beide Tabellen: Units und die Methoden der obersten Kandidaten.
      mRequest.Level := THotspotLevel.Methods;
      mRequest.Root := mRoot;
      if TDirectory.Exists(mTarget) then
        mRequest.Title := ExtractFileName(ExcludeTrailingPathDelimiter(TPath.GetFullPath(mTarget)))
      else
        mRequest.Title := ChangeFileExt(ExtractFileName(mTarget), '');
      mResult := mService.Analyze(mRequest, mVcs);
    finally
      mService.Free;
    end;
    ForceDirectories(ExtractFileDir(TPath.GetFullPath(AOptions.HotspotsFile)));
    TFile.WriteAllBytes(AOptions.HotspotsFile, TEncoding.UTF8.GetBytes(THotspotReport.ForFile(mResult,
      AOptions.HotspotsFile)));
    WriteError(Format('Hotspot-Bericht %s: %s, %d Units, %d Methoden, %d Kopplungen', [AOptions.HotspotsFile,
      THotspotReport.RangeText(mResult), Length(mResult.Units), Length(mResult.Methods), Length(mResult.Coupling)]));
    Result := TFindingsOutput.ExitClean;
  except
    on E: Exception do
    begin
      WriteError(E.Message);
      Result := TFindingsOutput.ExitFailure;
    end;
  end;
end;

/// <summary>Schreibt AText atomar (#1358): erst eine Nachbardatei, dann in einem Schritt ersetzen. Kodierung aus
/// AFormat, Zeilenumbrüche wie in AText.</summary>
procedure WriteFormatted(const AFileName, AText: string; const AFormat: TFileFormat);
var
  mTemp: string;
begin
  if TFileEncoding.IsBinaryFormFile(AFileName) then
    raise EFileEncodingError.Create('Binär gespeichertes Formular wird nicht geändert');
  mTemp := AFileName + '.atlas-format.tmp';
  TFile.WriteAllBytes(mTemp, TFileEncoding.EncodeKeepingLineBreaks(AText, AFormat));
  if not TShellPlatform.MoveReplacing(mTemp, AFileName) then
  begin
    if TFile.Exists(mTemp) then
      TFile.Delete(mTemp);
    raise EInOutError.Create('Datei nicht ersetzbar (gesperrt oder schreibgeschützt)');
  end;
end;

/// <summary>Geänderte Zeilen von AFileName als Bereiche des Formatierers; False ohne geänderte Zeile.</summary>
function ChangedSpans(AGit: TVcsChanges; const AFileName: string; out ASpans: TArray<TFormatLineSpan>): Boolean;
var
  mLines: TChangedLines;
  mSpan: TLineSpan;
begin
  ASpans := nil;
  Result := TChangedFiles.LinesOf(AGit.Lines, AGit.RepoRoot, AFileName, mLines);
  if not Result then
    Exit;
  for mSpan in mLines.Spans do
    ASpans := ASpans + [TFormatLineSpan.Create(mSpan.First, mSpan.Last)];
  Result := Length(ASpans) > 0;
end;

class function TLinterShell.Formatting(const AOptions: TCommandLineOptions): Integer;
var
  mWarning, mConfigRoot, mRoot, mFileName, mRelativePath, mText, mProblem: string;
  mSettings: TServerSettings;
  mFilter: TFindingFilter;
  mSources: TCheckSourceFunc;
  mCandidates: TArray<string>;
  mFiles: TArray<TFormattedFile>;
  mItem: TFormattedFile;
  mFileFormat: TFileFormat;
  mStyle: TFormatStyle;
  mScope: TFormatScope;
  mSpans: TArray<TFormatLineSpan>;
  mGit: TVcsChanges;
  mProcess: ICompilerProcess;
  mKind: TFormatOutputKind;
  mReadEditorConfig: TEditorConfigReadFile;
begin
  for mWarning in AOptions.Warnings do
    WriteError(mWarning);
  if AOptions.FormatCheck and AOptions.FormatWrite then
  begin
    WriteError('--format-check und --format-write schließen sich aus');
    Exit(TFindingsOutput.ExitFailure);
  end;
  if AOptions.Metrics or AOptions.Todos or AOptions.SuppressionStats or AOptions.UpdateBaseline then
  begin
    WriteError('--format-check und --format-write gehen nicht mit --metrics, --todos, --suppression-stats ' +
      'oder --update-baseline');
    Exit(TFindingsOutput.ExitFailure);
  end;
  if AOptions.FormatDiff then
    mKind := TFormatOutputKind.Diff
  else if AOptions.CheckFormat = TFindingsFormat.Json then
    mKind := TFormatOutputKind.Json
  else if AOptions.CheckFormat = TFindingsFormat.Sarif then
  begin
    WriteError('--format-check und --format-write gibt es mit --format text, json oder diff');
    Exit(TFindingsOutput.ExitFailure);
  end
  else
    mKind := TFormatOutputKind.Text;
  if not (TFile.Exists(AOptions.CheckTarget) or TDirectory.Exists(AOptions.CheckTarget)) then
  begin
    WriteError(Format('Ziel "%s" nicht gefunden', [AOptions.CheckTarget]));
    Exit(TFindingsOutput.ExitFailure);
  end;
  mReadEditorConfig :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := FileExists(AFileName);
      if Result then
        AText := TFileEncoding.LoadText(AFileName);
    end;
  mGit := nil;
  try
    try
      if TDirectory.Exists(AOptions.CheckTarget) then
        mConfigRoot := TPath.GetFullPath(AOptions.CheckTarget)
      else
        mConfigRoot := ExtractFileDir(TPath.GetFullPath(AOptions.CheckTarget));
      mSettings := LoadSettings(mConfigRoot);
      TFileEncodingDefaults.SetFolder(mConfigRoot, mSettings.DefaultEncoding);
      mFilter := Default(TFindingFilter);
      mFilter.Units := AOptions.UnitFilter;
      mCandidates := CollectFiles(AOptions.CheckTarget, mSettings, mRoot, mSources);
      if AOptions.ChangedRef <> '' then
      begin
        // Über eine Variable halten: Detect gibt einen Probelauf frei, bevor es den nächsten startet.
        mProcess := TProcessRunner.Create;
        mGit := TVcsChanges.Detect(mProcess, mConfigRoot, mSettings.VcsProvider, mSettings.VcsGitPath,
          mSettings.VcsSvnPath, mSettings.VcsTimeoutSeconds);
        mCandidates := SelectChanged(AOptions, mCandidates, mGit);
      end;
      mFiles := nil;
      for mFileName in mCandidates do
      begin
        mRelativePath := ExtractRelativePath(IncludeTrailingPathDelimiter(mRoot), mFileName);
        if not mFilter.AcceptsFile(mRelativePath) or mSettings.IsExcluded(mRelativePath) then
          Continue;
        mScope := TFormatScope.All;
        if (mGit <> nil) and AOptions.ChangedLines then
        begin
          // Nur über DFM oder Include-Datei ausgewählt: keine eigene geänderte Zeile, nichts zu formatieren.
          if not ChangedSpans(mGit, mFileName, mSpans) then
            Continue;
          mScope := TFormatScope.Lines(mSpans);
        end;
        try
          mText := TFileEncoding.LoadFromFile(mFileName, mFileFormat);
        except
          on E: Exception do
          begin
            WriteError(Format('%s: %s', [mFileName, E.Message]));
            Continue;
          end;
        end;
        mStyle := TLspFormatting.Resolve(nil, mFileName, mSettings.Formatting, mReadEditorConfig);
        mItem := TFormattedFile.Create(mRelativePath, TFormatCheck.Run(mText, mStyle, mScope,
          mSources(mFileName).Options));
        if AOptions.FormatWrite and mItem.Outcome.Changed then
          try
            WriteFormatted(mFileName, mItem.Outcome.Formatted, mFileFormat);
            mItem.Written := True;
          except
            on E: Exception do
              mItem.Error := E.Message;
          end;
        mFiles := mFiles + [mItem];
      end;
    finally
      mGit.Free;
    end;
    WriteOutput(AOptions, TFormatOutput.Render(mFiles, mKind, AOptions.FormatWrite));
    // Beim Diff gehören Syntaxfehler und instabile Dateien nicht in den Diff.
    if mKind = TFormatOutputKind.Diff then
      for mProblem in TFormatOutput.Problems(mFiles) do
        WriteError(mProblem);
    WriteError(TFormatOutput.Summary(mFiles, AOptions.FormatWrite));
    Result := TFormatOutput.ExitCode(mFiles, AOptions.FormatWrite);
  except
    on E: Exception do
    begin
      WriteError(Format('%s: %s', [E.ClassName, E.Message]));
      Result := TFindingsOutput.ExitFailure;
    end;
  end;
end;

/// <summary>Hauptdatei (.dpr) der .dproj AProject; '' ohne.</summary>
function MainSourceOf(const AProject: string; const ASettings: TServerSettings): string;
var
  mOptions: TDprojOptions;
begin
  mOptions := Default(TDprojOptions);
  mOptions.Config := ASettings.Config;
  mOptions.Platform := ASettings.Platform;
  mOptions.FileExists :=
    function(APath: string): Boolean
    begin
      Result := TFile.Exists(APath) or TDirectory.Exists(APath);
    end;
  Result := TDprojReader.Load(TPath.GetFullPath(AProject), mOptions).MainSource;
  if (Result = '') and TFile.Exists(ChangeFileExt(AProject, '.dpr')) then
    Result := TPath.GetFullPath(ChangeFileExt(AProject, '.dpr'));
end;

class function TLinterShell.AffectedTests(const AOptions: TCommandLineOptions): Integer;
const
  /// <summary>Alle Tests nötig (eine Datei nicht zuzuordnen, Testprogramm geändert, Analyse unvollständig).</summary>
  cExitAllTests = 2;
var
  mTarget, mConfigRoot, mProject, mOutput, mArgument: string;
  mSettings: TServerSettings;
  mFormat: TAffectedFormat;
  mGroup: TShellWorkspaceGroup;
  mResolver: TNameResolver;
  mRequest: TAffectedRequest;
  mQuery: TShellAffectedQuery;
  mFound: TAffectedResult;
  mProcess: ICompilerProcess;
  mPrograms: TArray<string>;
  mReadText: TReferenceReadText;
  mEnsureUnit: TEnsureUnitFunc;
  mTimings: TCheckTimings;
  mWarning: string;
begin
  for mWarning in AOptions.Warnings do
    WriteError(mWarning);
  if not TAffectedTests.TryParseFormat(AOptions.FormatText, mFormat) then
  begin
    WriteError(Format('--affected-tests kennt --format text, json und dunitx, nicht "%s"', [AOptions.FormatText]));
    Exit(TFindingsOutput.ExitFailure);
  end;
  mTarget := AOptions.CheckTarget;
  if mTarget = '' then
    mTarget := GetCurrentDir;
  if not (TFile.Exists(mTarget) or TDirectory.Exists(mTarget)) then
  begin
    WriteError(Format('Ziel "%s" nicht gefunden', [mTarget]));
    Exit(TFindingsOutput.ExitFailure);
  end;
  mGroup := nil;
  try
    try
      if TDirectory.Exists(mTarget) then
        mConfigRoot := TPath.GetFullPath(mTarget)
      else
        mConfigRoot := ExtractFileDir(TPath.GetFullPath(mTarget));
      mSettings := LoadSettings(mConfigRoot);
      if not mSettings.Tests.Affected then
      begin
        WriteError(TShellAffectedTests.OffMessage + '; einschalten mit "tests": {"affected": true}');
        Exit(TFindingsOutput.ExitFailure);
      end;
      TFileEncodingDefaults.SetFolder(mConfigRoot, mSettings.DefaultEncoding);
      mReadText :=
        function(const AFileName: string; out AText: string): Boolean
        begin
          Result := TShellBootstrap.ReadSourceText(AFileName, AText);
        end;
      // Zeiten nur für --timings beim Prüfen; hier unbenutzt.
      mTimings := Default(TCheckTimings);
      mGroup := LoadIndex(AOptions, mConfigRoot, mTimings);
      // Testprogramme: das Ziel bzw. die Projekte der Gruppe, sonst testUnits.project, sonst alle DUnitX-Programme.
      mPrograms := nil;
      if SameText(ExtractFileExt(mTarget), '.dproj') then
        mPrograms := [MainSourceOf(mTarget, mSettings)]
      else if SameText(ExtractFileExt(mTarget), '.groupproj') then
      begin
        for mProject in TShellBootstrap.LoadGroup(TPath.GetFullPath(mTarget), nil) do
          mPrograms := mPrograms + [MainSourceOf(mProject, mSettings)];
        mPrograms := TShellAffectedTests.TestPrograms(mPrograms, mReadText);
      end
      else if mSettings.TestUnits.Project <> '' then
        mPrograms := [ChangeFileExt(TPath.GetFullPath(TPath.Combine(mConfigRoot, mSettings.TestUnits.Project)), '.dpr')]
      else
        mPrograms := TShellAffectedTests.TestPrograms(mGroup.AllFiles, mReadText);
      mRequest := Default(TAffectedRequest);
      mRequest.Files := mGroup.AllFiles;
      mRequest.TestPrograms := mPrograms;
      mRequest.Options := TImpactOptions.Default;
      mRequest.Options.References := mSettings.References;
      mRequest.Options.Tests := TShellAffectedTests.TestScope(mSettings.TestUnits.Pattern, mPrograms, mReadText);
      mQuery := Default(TShellAffectedQuery);
      mQuery.WorkingDir := mConfigRoot;
      mQuery.Base := AOptions.AffectedBase;
      mQuery.IncludeUncommitted := AOptions.IncludeUncommitted;
      // Über eine Variable halten: Detect gibt einen Probelauf frei, bevor es den nächsten startet.
      mProcess := TProcessRunner.Create;
      // Typisierte Variable: TNameResolver.Create ist überladen.
      mEnsureUnit :=
        function(const AUnitName: string): Boolean
        begin
          Result := mGroup.EnsureUnit(AUnitName);
        end;
      mResolver := TNameResolver.Create(mGroup.Index, mEnsureUnit);
      try
        mResolver.Namespaces := mGroup.Main.Namespaces;
        mFound := TShellAffectedTests.Run(mProcess, mSettings, mQuery, mResolver, mGroup.Index, mRequest, mReadText,
          nil);
      finally
        mResolver.Free;
      end;
      if (mFormat = TAffectedFormat.DUnitX) and not TAffectedTests.DUnitXArgument(mFound, mArgument) then
      begin
        // Zu viele Namen für eine Befehlszeile: dann ohne --run alle.
        mFound.All := True;
        mFound.AllReason := 'zu viele Tests für ein --run-Argument';
      end;
      mOutput := TAffectedTests.Render(mFound, mFormat);
      if mFormat = TAffectedFormat.DUnitX then
      begin
        // Auf stdout nur das Argument; der Bericht mit Gründen für Menschen auf stderr (pre-commit-Hook, CI-Protokoll).
        WriteError(TrimRight(TAffectedTests.ToText(mFound)));
        if mOutput <> '' then
          mOutput := mOutput + sLineBreak;
      end;
      WriteOutput(AOptions, mOutput);
      if mFound.All then
        Result := cExitAllTests
      else
        Result := TFindingsOutput.ExitClean;
    except
      on E: Exception do
      begin
        WriteError(E.Message);
        Result := TFindingsOutput.ExitFailure;
      end;
    end;
  finally
    if mGroup <> nil then
      mGroup.Stop;
    mGroup.Free;
  end;
end;

class function TLinterShell.ClearCache: Integer;
begin
  try
    WriteError(Format('%d Index-Caches gelöscht in %s',
      [TIndexCacheDirectory.Clear(TIndexCacheDirectory.DefaultRoot), TIndexCacheDirectory.DefaultRoot]));
    Result := TFindingsOutput.ExitClean;
  except
    on E: Exception do
    begin
      WriteError(Format('%s: %s', [E.ClassName, E.Message]));
      Result := TFindingsOutput.ExitFailure;
    end;
  end;
end;

class function TLinterShell.Run(const AOptions: TCommandLineOptions): Integer;
var
  Root, ConfigRoot, FileName, RelativePath, Text: string;
  Settings: TServerSettings;
  Filter: TFindingFilter;
  Rules: TArray<IRule>;
  Rule: IRule;
  Descriptors: TArray<TRuleDescriptor>;
  Files: TArray<TCheckedFile>;
  Checked: TCheckedFile;
  FileFormat: TFileFormat;
  Encoding: TEncoding;
  Output: string;
  Warning: string;
  Stats: TSuppressionStats;
  Findings: TArray<TRuleFinding>;
  BaselinePath: string;
  Baseline: IRuleBaseline;
  Sources: TArray<TBaselineSource>;
  Source: TBaselineSource;
  Scopes: TFindingScopes;
  Marks: TArray<TBaselineMark>;
  CheckedPaths: TList<string>;
  BaselineEntryPath: string;
  Update: TBaselineUpdate;
  Orphan: TCheckedFile;
  Candidates: TArray<string>;
  Git: TVcsChanges;
  Process: ICompilerProcess;
  Metrics: TArray<TFileMetrics>;
  Todos: TArray<TFileTodos>;
  TodoEntries: TArray<TTodoEntry>;
  Packages: TArray<TPackageSource>;
  Programs: TArray<string>;
  Project: TCheckProject;
  CheckSources: TCheckSourceFunc;
  Group: TShellWorkspaceGroup;
  mTimings: TCheckTimings;
  mProfiler: TCheckProfiler;
  mRunWatch, mUnitWatch: TStopwatch;
  mPrevious: TCheckProfiler;
begin
  if AOptions.FixRules <> nil then
    Exit(Fix(AOptions));
  if AOptions.FormatCheck or AOptions.FormatWrite then
    Exit(Formatting(AOptions));
  for Warning in AOptions.Warnings do
    WriteError(Warning);
  if AOptions.FormatDiff then
  begin
    WriteError('--format diff gibt es nur mit --format-check oder --format-write');
    Exit(TFindingsOutput.ExitFailure);
  end;
  if AOptions.Metrics and (AOptions.CheckFormat = TFindingsFormat.Sarif) then
  begin
    WriteError('--metrics gibt es nur mit --format text (Markdown) oder json');
    Exit(TFindingsOutput.ExitFailure);
  end;
  if AOptions.Todos and (AOptions.CheckFormat = TFindingsFormat.Sarif) then
  begin
    WriteError('--todos gibt es nur mit --format text (Markdown) oder json');
    Exit(TFindingsOutput.ExitFailure);
  end;
  if AOptions.Todos and AOptions.Metrics then
  begin
    WriteError('--todos und --metrics schließen sich aus');
    Exit(TFindingsOutput.ExitFailure);
  end;
  if not (TFile.Exists(AOptions.CheckTarget) or TDirectory.Exists(AOptions.CheckTarget)) then
  begin
    WriteError(Format('Ziel "%s" nicht gefunden', [AOptions.CheckTarget]));
    Exit(TFindingsOutput.ExitFailure);
  end;
  if (AOptions.SourceRoot <> '') and not TDirectory.Exists(AOptions.SourceRoot) then
  begin
    WriteError(Format('Quellwurzel "%s" nicht gefunden', [AOptions.SourceRoot]));
    Exit(TFindingsOutput.ExitFailure);
  end;
  try
    if TDirectory.Exists(AOptions.CheckTarget) then
      ConfigRoot := TPath.GetFullPath(AOptions.CheckTarget)
    else
      ConfigRoot := ExtractFileDir(TPath.GetFullPath(AOptions.CheckTarget));
    Settings := LoadSettings(ConfigRoot);
    TFileEncodingDefaults.SetFolder(ConfigRoot, Settings.DefaultEncoding);
    // Regelprofil der Kommandozeile (#146), z. B. "strict" im CI: --profile vor profile.cli vor profile.
    if AOptions.Profile <> '' then
      Settings.Profile := AOptions.Profile
    else if Settings.CliProfile <> '' then
      Settings.Profile := Settings.CliProfile;

    Filter := Default(TFindingFilter);
    Filter.Rules := AOptions.RuleFilter;
    Filter.Units := AOptions.UnitFilter;
    Filter.MinSeverity := AOptions.MinSeverity;

    Rules := BuiltinRules;
    Descriptors := [TFileChecker.SyntaxDescriptor, TFileChecker.LanguageFeatureDescriptor];
    for Rule in Rules do
      Descriptors := Descriptors + [Rule.Descriptor];

    BaselinePath := AOptions.BaselineFile;
    // --update-baseline schreibt immer unter dem neuen Namen.
    if (BaselinePath = '') and AOptions.UpdateBaseline then
      BaselinePath := TPath.Combine(ConfigRoot, BaselineFileName)
    else if BaselinePath = '' then
      BaselinePath := ExistingOrLegacyFile(ConfigRoot, BaselineFileName, LegacyBaselineFileName);
    if not AOptions.UpdateBaseline then
    begin
      if TFile.Exists(BaselinePath) then
        Baseline := TRuleBaseline.FromJson(TFileEncoding.LoadFromFile(BaselinePath, FileFormat))
      else if AOptions.BaselineFile <> '' then
      begin
        WriteError(Format('Baseline "%s" nicht gefunden', [BaselinePath]));
        Exit(TFindingsOutput.ExitFailure);
      end;
    end
    else if TFile.Exists(BaselinePath) then
      // Die bisherige Baseline nur für die Zähler; eine unlesbare hält das Neuschreiben nicht auf.
      try
        Baseline := TRuleBaseline.FromJson(TFileEncoding.LoadFromFile(BaselinePath, FileFormat));
      except
        on E: Exception do
        begin
          WriteError(Format('Bisherige Baseline nicht lesbar, wird ersetzt: %s', [E.Message]));
          Baseline := nil;
        end;
      end;

    Files := nil;
    Sources := nil;
    Metrics := nil;
    Todos := nil;
    Git := nil;
    Group := nil;
    mTimings := Default(TCheckTimings);
    mTimings.IndexMs := -1;
    mProfiler := nil;
    Stats := TSuppressionStats.Create;
    CheckedPaths := TList<string>.Create;
    try
      // Metriken und TODOs brauchen keinen Index.
      if not (AOptions.NoIndex or AOptions.Metrics or AOptions.Todos) then
        Group := LoadIndex(AOptions, ConfigRoot, mTimings);
      if AOptions.Timings then
      begin
        mProfiler := TCheckProfiler.Create;
        mProfiler.BeginRun(Now);
      end;
      mRunWatch := TStopwatch.StartNew;
      Candidates := CollectFiles(AOptions.CheckTarget, Settings, Root, CheckSources);
      Packages := ReadPackages(Candidates);
      Programs := ReadPrograms(Candidates);
      if (AOptions.ChangedRef <> '') and AOptions.UpdateBaseline then
        WriteError('--update-baseline schreibt die Baseline immer für alle Dateien; --changed/--diff wird ignoriert')
      else if AOptions.ChangedRef <> '' then
      begin
        // Über eine Variable halten: Detect gibt einen Probelauf frei, bevor es den nächsten startet.
        Process := TProcessRunner.Create;
        // vcs.provider (#571): auto, git, svn oder off; eigene Programmpfade und Zeitlimit wie im Plugin (#1285).
        Git := TVcsChanges.Detect(Process, ConfigRoot, Settings.VcsProvider, Settings.VcsGitPath, Settings.VcsSvnPath,
          Settings.VcsTimeoutSeconds);
        Candidates := SelectChanged(AOptions, Candidates, Git);
      end;
      for FileName in Candidates do
      begin
        RelativePath := ExtractRelativePath(IncludeTrailingPathDelimiter(Root), FileName);
        if not Filter.AcceptsFile(RelativePath) then
          Continue;
        try
          Text := TFileEncoding.LoadFromFile(FileName, FileFormat);
        except
          on E: Exception do
          begin
            WriteError(Format('%s: %s', [FileName, E.Message]));
            Continue;
          end;
        end;
        if AOptions.Metrics then
        begin
          Metrics := Metrics + [TFileMetrics.Create(StringReplace(RelativePath, '\', '/', [rfReplaceAll]),
            TMetricsCalculator.ForText(Text))];
          Continue;
        end;
        if AOptions.Todos then
        begin
          // Erledigte Einträge (DONE) zählen nicht; Dateien ohne offenen Eintrag fehlen.
          TodoEntries := TTodoScanner.ForText(Text, TTodoRules.Keywords(Settings));
          Todos := Todos + TTodoScanner.Filter([TFileTodos.Create(StringReplace(RelativePath, '\', '/',
            [rfReplaceAll]), TodoEntries)], TTodoFilter.Default);
          Continue;
        end;
        Project := CheckProjectOf(FileName, Packages, Programs, Group);
        // Zeitprofil (#1356): Die Engine meldet ihre Regelzeiten an den angehängten Profiler.
        mPrevious := TCheckProfiler.Attach(mProfiler);
        mUnitWatch := TStopwatch.StartNew;
        try
          Findings := TFileChecker.CheckText(Rules, Settings, RelativePath, Text, Project, CheckSources(FileName),
            Scopes);
        finally
          TCheckProfiler.Attach(mPrevious);
          if mProfiler <> nil then
            mProfiler.AddUnit(FileName, TCheckProfiler.TicksToMicroseconds(mUnitWatch.ElapsedTicks,
              TStopwatch.Frequency));
        end;
        if AOptions.SuppressionStats then
          Stats.Add(Text, Findings);
        if AOptions.UpdateBaseline then
        begin
          Source.Path := RelativePath;
          Source.Text := Text;
          Source.Findings := Findings;
          Sources := Sources + [Source];
          Continue;
        end;
        CheckedPaths.Add(LowerCase(TRuleBaseline.NormalizePath(RelativePath)));
        // Zustand je Treffer (#97): mit Baseline neu oder unverändert, für SARIF mit Fingerabdrücken.
        Marks := nil;
        if Baseline <> nil then
        begin
          Marks := Baseline.Classify(RelativePath, Text, Scopes, Findings);
          Findings := NewFindings(Marks);
        end
        else if AOptions.CheckFormat = TFindingsFormat.Sarif then
          Marks := TRuleBaseline.Mark(Text, Scopes, Findings);
        Checked.Path := RelativePath;
        Checked.FullPath := TPath.GetFullPath(FileName);
        Checked.Findings := Filter.Apply(Findings);
        if (Git <> nil) and AOptions.ChangedLines then
          Checked.Findings := InChangedLines(Checked.Findings, Git, FileName);
        Checked.Marks := nil;
        if AOptions.CheckFormat = TFindingsFormat.Sarif then
          Checked.Marks := KeptMarks(Marks, Filter, Settings, Descriptors, Git, AOptions.ChangedLines, FileName);
        Files := Files + [Checked];
      end;

      // SARIF: Einträge von Dateien, die es nicht mehr gibt, als "absent" (nur bei vollem Lauf).
      if (Baseline <> nil) and (AOptions.CheckFormat = TFindingsFormat.Sarif) and (AOptions.ChangedRef = '') and
        not (AOptions.Metrics or AOptions.Todos or AOptions.SuppressionStats or AOptions.UpdateBaseline) then
        for BaselineEntryPath in Baseline.Paths do
          if not CheckedPaths.Contains(LowerCase(BaselineEntryPath)) and Filter.AcceptsFile(BaselineEntryPath) and
            not TFile.Exists(TPath.Combine(Root, StringReplace(BaselineEntryPath, '/', PathDelim, [rfReplaceAll])))
          then
          begin
            Orphan := Default(TCheckedFile);
            Orphan.Path := BaselineEntryPath;
            Orphan.FullPath := TPath.Combine(Root, StringReplace(BaselineEntryPath, '/', PathDelim, [rfReplaceAll]));
            Orphan.Findings := nil;
            Orphan.Marks := KeptMarks(Baseline.AbsentOf(BaselineEntryPath), Filter, Settings, Descriptors, nil,
              False, Orphan.FullPath);
            if Length(Orphan.Marks) > 0 then
              Files := Files + [Orphan];
          end;

      if AOptions.UpdateBaseline then
      begin
        Update := TRuleBaseline.Update(Baseline, Sources,
          function(const APath: string): Boolean
          begin
            Result := TFile.Exists(TPath.Combine(Root, StringReplace(APath, '/', PathDelim, [rfReplaceAll])));
          end);
        ReportBaselineOrphans(Update);
        Encoding := TUTF8Encoding.Create(False);
        try
          TFile.WriteAllText(BaselinePath, Update.Json, Encoding);
        finally
          Encoding.Free;
        end;
        ReportBaselineUpdate(Update, BaselinePath);
        Exit(TFindingsOutput.ExitClean);
      end;
      if AOptions.Metrics and (AOptions.CheckFormat = TFindingsFormat.Json) then
        Output := TMetricsReport.Json(Metrics, TMetricRules.Limits(Settings))
      else if AOptions.Metrics then
        Output := TMetricsReport.Markdown(Metrics, TMetricRules.Limits(Settings),
          ChangeFileExt(ExtractFileName(ExcludeTrailingPathDelimiter(AOptions.CheckTarget)), ''))
      else if AOptions.Todos and (AOptions.CheckFormat = TFindingsFormat.Json) then
        Output := TTodoReport.Json(Todos)
      else if AOptions.Todos then
        Output := TTodoReport.Markdown(Todos,
          ChangeFileExt(ExtractFileName(ExcludeTrailingPathDelimiter(AOptions.CheckTarget)), ''))
      else if AOptions.SuppressionStats then
        Output := Stats.Render(AOptions.CheckFormat)
      else
        Output := TFindingsOutput.Render(Files, AOptions.CheckFormat, Descriptors,
          SourceRootOf(AOptions, ConfigRoot));
      if mProfiler <> nil then
      begin
        mProfiler.FinishRun(mRunWatch.ElapsedMilliseconds);
        mTimings.Profile := mProfiler.Snapshot(TCheckRunProfile.cTop);
        mTimings.TotalBytes := TShutdownLeaks.AllocatedBytes;
        WriteTimings(AOptions, mTimings);
      end;
    finally
      mProfiler.Free;
      if Group <> nil then
        Group.Stop;
      Group.Free;
      CheckedPaths.Free;
      Git.Free;
      Stats.Free;
    end;
    WriteOutput(AOptions, Output);
    if AOptions.SuppressionStats or AOptions.Metrics or AOptions.Todos then
      Result := TFindingsOutput.ExitClean
    else
      Result := TFindingsOutput.ExitCode(Files, AOptions.FailOn);
  except
    on E: Exception do
    begin
      WriteError(Format('%s: %s', [E.ClassName, E.Message]));
      Result := TFindingsOutput.ExitFailure;
    end;
  end;
end;

/// <summary>Treffer einer Datei für die Sammelkorrektur und den Exit-Code: Regeln, Filter, Baseline (deren Treffer
/// bleiben) und mit --changed-lines nur Treffer in geänderten Zeilen des Ausgangstexts. Eigene Routine, damit die
/// anonyme Methode nur ihre Parameter einfängt.</summary>
function FixCheckOf(const ARules: TArray<IRule>; const ASettings: TServerSettings; const ARelativePath,
  AFileName: string; const AProject: TCheckProject; const ASource: TCheckSource; const ABaseline: IRuleBaseline;
  const AFilter: TFindingFilter; AGit: TVcsChanges; AChangedLines: Boolean): TBulkFixCheck;
begin
  Result :=
    function(const AText: string; const ALines: TBulkFixLineMap): TArray<TRuleFinding>
    var
      mScopes: TFindingScopes;
      mFindings: TArray<TRuleFinding>;
      mFinding: TRuleFinding;
      mChanged: TChangedLines;
    begin
      mFindings := TFileChecker.CheckText(ARules, ASettings, ARelativePath, AText, AProject, ASource, mScopes);
      if ABaseline <> nil then
        mFindings := NewFindings(ABaseline.Classify(ARelativePath, AText, mScopes, mFindings));
      mFindings := AFilter.Apply(mFindings);
      if (AGit = nil) or not AChangedLines then
        Exit(mFindings);
      Result := nil;
      if not TChangedFiles.LinesOf(AGit.Lines, AGit.RepoRoot, AFileName, mChanged) then
        Exit;
      for mFinding in mFindings do
        if mChanged.Contains(ALines.Original(mFinding.Range.StartPos.Line)) then
          Result := Result + [mFinding];
    end;
end;

/// <summary>Schreibt in der Kodierung und mit den Zeilenenden, mit denen die Datei gelesen wurde (#121).</summary>
function FixWriterOf(const AFormats: TDictionary<string, TFileFormat>): TBulkFixWrite;
begin
  Result :=
    procedure(const AFileName, AText: string)
    begin
      TFileEncoding.SaveToFile(AFileName, AText, AFormats[AFileName]);
    end;
end;

class function TLinterShell.Fix(const AOptions: TCommandLineOptions): Integer;
var
  mRoot, mConfigRoot, mFileName, mRelativePath, mText, mWarning, mBaselinePath, mOutput, mChangedNames: string;
  mSettings: TServerSettings;
  mFilter: TFindingFilter;
  mAllRules, mFixRules: TArray<IRule>;
  mOptions: TBulkFixOptions;
  mBaseline: IRuleBaseline;
  mFormat: TFileFormat;
  mFormats: TDictionary<string, TFileFormat>;
  mRelative: TDictionary<string, string>;
  mGit: TVcsChanges;
  mProcess: ICompilerProcess;
  mGroup: TShellWorkspaceGroup;
  mCandidates, mPrograms: TArray<string>;
  mPackages: TArray<TPackageSource>;
  mSources: TCheckSourceFunc;
  mProject: TCheckProject;
  mSource: TCheckSource;
  mResult: TBulkFixFile;
  mResults: TArray<TBulkFixFile>;
  mRemaining: TArray<TCheckedFile>;
  mChecked: TCheckedFile;
  mRemainingCheck: TBulkFixCheck;
  mTimings: TCheckTimings;
begin
  for mWarning in AOptions.Warnings do
    WriteError(mWarning);
  if AOptions.Metrics or AOptions.Todos or AOptions.SuppressionStats or AOptions.UpdateBaseline then
  begin
    WriteError('--fix verträgt sich nicht mit --metrics, --todos, --suppression-stats und --update-baseline');
    Exit(TFindingsOutput.ExitFailure);
  end;
  if not (TFile.Exists(AOptions.CheckTarget) or TDirectory.Exists(AOptions.CheckTarget)) then
  begin
    WriteError(Format('Ziel "%s" nicht gefunden', [AOptions.CheckTarget]));
    Exit(TFindingsOutput.ExitFailure);
  end;
  try
    if TDirectory.Exists(AOptions.CheckTarget) then
      mConfigRoot := TPath.GetFullPath(AOptions.CheckTarget)
    else
      mConfigRoot := ExtractFileDir(TPath.GetFullPath(AOptions.CheckTarget));
    mSettings := LoadSettings(mConfigRoot);
    TFileEncodingDefaults.SetFolder(mConfigRoot, mSettings.DefaultEncoding);
    if AOptions.Profile <> '' then
      mSettings.Profile := AOptions.Profile
    else if mSettings.CliProfile <> '' then
      mSettings.Profile := mSettings.CliProfile;
    mFilter := Default(TFindingFilter);
    mFilter.Rules := AOptions.RuleFilter;
    mFilter.Units := AOptions.UnitFilter;
    mFilter.MinSeverity := AOptions.MinSeverity;
    mAllRules := BuiltinRules;
    mFixRules := TBulkFix.RulesFor(mAllRules, AOptions.FixRules);
    mOptions := TBulkFixOptions.Create(AOptions.FixRules, mSettings.FixMinConfidence, TRuleCatalog.Shared.Entries);
    // Baseline (#97): Ihre Treffer bleiben unberührt.
    mBaselinePath := AOptions.BaselineFile;
    if mBaselinePath = '' then
      mBaselinePath := ExistingOrLegacyFile(mConfigRoot, BaselineFileName, LegacyBaselineFileName);
    if TFile.Exists(mBaselinePath) then
      mBaseline := TRuleBaseline.FromJson(TFileEncoding.LoadFromFile(mBaselinePath, mFormat))
    else if AOptions.BaselineFile <> '' then
    begin
      WriteError(Format('Baseline "%s" nicht gefunden', [mBaselinePath]));
      Exit(TFindingsOutput.ExitFailure);
    end;
    WriteError(Format('Sammelkorrektur: %s (Konfidenz ab %s)', [string.Join(', ', AOptions.FixRules),
      TBulkFix.ConfidenceText(mOptions.MinConfidence)]));
    mResults := nil;
    mRemaining := nil;
    mGit := nil;
    mGroup := nil;
    mFormats := TDictionary<string, TFileFormat>.Create;
    mRelative := TDictionary<string, string>.Create;
    try
      // Die Sammelkorrektur misst nicht (--timings gilt nur für die Prüfung).
      mTimings := Default(TCheckTimings);
      if not AOptions.NoIndex then
        mGroup := LoadIndex(AOptions, mConfigRoot, mTimings);
      mCandidates := CollectFiles(AOptions.CheckTarget, mSettings, mRoot, mSources);
      mPackages := ReadPackages(mCandidates);
      mPrograms := ReadPrograms(mCandidates);
      if AOptions.ChangedRef <> '' then
      begin
        mProcess := TProcessRunner.Create;
        mGit := TVcsChanges.Detect(mProcess, mConfigRoot, mSettings.VcsProvider, mSettings.VcsGitPath,
          mSettings.VcsSvnPath, mSettings.VcsTimeoutSeconds);
        mCandidates := SelectChanged(AOptions, mCandidates, mGit);
      end;
      for mFileName in mCandidates do
      begin
        mRelativePath := ExtractRelativePath(IncludeTrailingPathDelimiter(mRoot), mFileName);
        if not mFilter.AcceptsFile(mRelativePath) then
          Continue;
        try
          mText := TFileEncoding.LoadFromFile(mFileName, mFormat);
        except
          on E: Exception do
          begin
            WriteError(Format('%s: %s', [mFileName, E.Message]));
            Continue;
          end;
        end;
        mProject := CheckProjectOf(mFileName, mPackages, mPrograms, mGroup);
        mSource := mSources(mFileName);
        mResult := TBulkFix.Run(mFileName, mText, mOptions, FixCheckOf(mFixRules, mSettings, mRelativePath, mFileName,
          mProject, mSource, mBaseline, mFilter, mGit, AOptions.ChangedLines), TBulkFix.SyntaxErrorsWith(mSource));
        mResults := mResults + [mResult];
        mFormats.AddOrSetValue(mFileName, mFormat);
        mRelative.AddOrSetValue(mFileName, StringReplace(mRelativePath, '\', '/', [rfReplaceAll]));
        // Für den Exit-Code zählen alle Treffer, die nach der Korrektur bleiben.
        mChecked := Default(TCheckedFile);
        mChecked.Path := mRelativePath;
        mChecked.FullPath := TPath.GetFullPath(mFileName);
        mRemainingCheck := FixCheckOf(mAllRules, mSettings, mRelativePath, mFileName, mProject, mSource, mBaseline,
          mFilter, mGit, AOptions.ChangedLines);
        mChecked.Findings := mRemainingCheck(mResult.NewText, mResult.Lines);
        mRemaining := mRemaining + [mChecked];
      end;
      mOutput := '';
      mChangedNames := '';
      for mResult in mResults do
        if mResult.Changed then
        begin
          mOutput := mOutput + TBulkFix.Diff(mRelative[mResult.FileName], mResult);
          if mChangedNames <> '' then
            mChangedNames := mChangedNames + ', ';
          mChangedNames := mChangedNames + mRelative[mResult.FileName];
        end;
      if AOptions.FixDryRun then
        WriteOutput(AOptions, mOutput)
      else
        TBulkFix.WriteAll(mResults, FixWriterOf(mFormats));
      WriteError(TBulkFix.Summary(mResults, AOptions.FixDryRun, sLineBreak));
      if (mChangedNames <> '') and AOptions.FixDryRun then
        WriteError('Betroffene Dateien: ' + mChangedNames)
      else if mChangedNames <> '' then
        WriteError('Geänderte Dateien: ' + mChangedNames);
    finally
      if mGroup <> nil then
        mGroup.Stop;
      mGroup.Free;
      mGit.Free;
      mRelative.Free;
      mFormats.Free;
    end;
    Result := TFindingsOutput.ExitCode(mRemaining, AOptions.FailOn);
  except
    on E: Exception do
    begin
      WriteError(Format('%s: %s', [E.ClassName, E.Message]));
      Result := TFindingsOutput.ExitFailure;
    end;
  end;
end;

end.
