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
// den aktuellen Treffern neu (#97), Exit-Code dann 0.
// Mit --changed bzw. --diff werden nur die geänderten Dateien laut Git (#157)
// bzw. SVN (#276) geprüft, mit --changed-lines nur Treffer in geänderten Zeilen ausgegeben;
// zusammen mit der Baseline zählt ein Treffer nur, wenn er in einer geänderten
// Zeile liegt und nicht in der Baseline steht. Die Regeln prüfen jede Datei für
// sich, deshalb ergibt die Teilmenge dieselben Treffer wie ein voller Lauf.
// SARIF-Pfade sind relativ zur Quellwurzel (--source-root, sonst die
// Git-Wurzel über dem Ziel, sonst der Ordner des Ziels).
// Exit-Code: 1, wenn ein Treffer --fail-on erreicht (Standard error: mindestens
// ein Fehler; Baseline-Treffer zählen nie), sonst 0; 3 Aufruf- oder Lesefehler.

interface

uses
  Shell.CommandLine;

type
  TLinterShell = class
  public
    class function Run(const AOptions: TCommandLineOptions): Integer; static;
    /// <summary>--clear-cache: löscht alle Index-Caches, die keine laufende Instanz nutzt (#184).</summary>
    class function ClearCache: Integer; static;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Generics.Collections,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Configuration.Scopes,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Projects.DprojReader,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Rules.Filter,
  Atlas.Common.Rules.Output,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.SuppressionStats,
  Atlas.Common.Rules.Builtin.Metrics,
  Atlas.Common.Metrics.Contract,
  Atlas.Common.Metrics.Calculator,
  Atlas.Common.Metrics.Report,
  Atlas.Common.Todos.Contract,
  Atlas.Common.Todos.Scanner,
  Atlas.Common.Todos.Report,
  Atlas.Common.Rules.Builtin.Todos,
  Atlas.Common.Rules.Baseline,
  Atlas.Common.Rules.ChangedFiles,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Index.Adapters.CacheDirectory,
  Atlas.Windows.Console.StdStreams,
  Atlas.Windows.Compiler.Adapters.ProcessRunner,
  Shell.VcsChanges;

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
  FileName, GlobalFile, Text, GlobalText: string;
  FileFormat: TFileFormat;
  Issues, Misplaced: TArray<TConfigurationIssue>;
  Issue: TConfigurationIssue;
begin
  GlobalText := '';
  GlobalFile := TConfigurationScopes.GlobalFile(GetEnvironmentVariable('APPDATA'));
  if (GlobalFile <> '') and TFile.Exists(GlobalFile) then
    GlobalText := TFileEncoding.LoadFromFile(GlobalFile, FileFormat);
  Text := '';
  FileName := ExistingOrLegacyFile(ARoot, ConfigurationFileName, LegacyConfigurationFileName);
  if TFile.Exists(FileName) then
    Text := TFileEncoding.LoadFromFile(FileName, FileFormat);
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

function CollectFiles(const ATarget: string; const ASettings: TServerSettings; out ARoot: string): TArray<string>;
var
  Options: TDprojOptions;
  Project: TProjectInfo;
  ProjectUnit: TProjectUnit;
  Files: TList<string>;
  FileName: string;
begin
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
  Stream: TStream;
  Warning: string;
  Stats: TSuppressionStats;
  Findings: TArray<TRuleFinding>;
  BaselinePath: string;
  Baseline: IRuleBaseline;
  Sources: TArray<TBaselineSource>;
  Source: TBaselineSource;
  Candidates: TArray<string>;
  Git: TVcsChanges;
  Process: ICompilerProcess;
  Metrics: TArray<TFileMetrics>;
  Todos: TArray<TFileTodos>;
  TodoEntries: TArray<TTodoEntry>;
begin
  for Warning in AOptions.Warnings do
    WriteError(Warning);
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
    Descriptors := [TFileChecker.SyntaxDescriptor];
    for Rule in Rules do
      Descriptors := Descriptors + [Rule.Descriptor];

    BaselinePath := AOptions.BaselineFile;
    // --update-baseline schreibt immer unter dem neuen Namen.
    if (BaselinePath = '') and AOptions.UpdateBaseline then
      BaselinePath := TPath.Combine(ConfigRoot, BaselineFileName)
    else if BaselinePath = '' then
      BaselinePath := ExistingOrLegacyFile(ConfigRoot, BaselineFileName, LegacyBaselineFileName);
    if not AOptions.UpdateBaseline then
      if TFile.Exists(BaselinePath) then
        Baseline := TRuleBaseline.FromJson(TFileEncoding.LoadFromFile(BaselinePath, FileFormat))
      else if AOptions.BaselineFile <> '' then
      begin
        WriteError(Format('Baseline "%s" nicht gefunden', [BaselinePath]));
        Exit(TFindingsOutput.ExitFailure);
      end;

    Files := nil;
    Sources := nil;
    Metrics := nil;
    Todos := nil;
    Git := nil;
    Stats := TSuppressionStats.Create;
    try
      Candidates := CollectFiles(AOptions.CheckTarget, Settings, Root);
      if (AOptions.ChangedRef <> '') and AOptions.UpdateBaseline then
        WriteError('--update-baseline schreibt die Baseline immer für alle Dateien; --changed/--diff wird ignoriert')
      else if AOptions.ChangedRef <> '' then
      begin
        // Über eine Variable halten: Detect gibt einen Probelauf frei, bevor es den nächsten startet.
        Process := TProcessRunner.Create;
        // vcs.provider (#571): auto, git, svn oder off.
        Git := TVcsChanges.Detect(Process, ConfigRoot, Settings.VcsProvider);
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
        Findings := TFileChecker.CheckText(Rules, Settings, RelativePath, Text);
        if AOptions.SuppressionStats then
          Stats.Add(Text, Findings);
        if AOptions.UpdateBaseline then
        begin
          Source.Path := RelativePath;
          Source.Text := Text;
          Source.Findings := Findings;
          Sources := Sources + [Source];
        end;
        if Baseline <> nil then
          Findings := Baseline.Filter(RelativePath, Text, Findings);
        Checked.Path := RelativePath;
        Checked.FullPath := TPath.GetFullPath(FileName);
        Checked.Findings := Filter.Apply(Findings);
        if (Git <> nil) and AOptions.ChangedLines then
          Checked.Findings := InChangedLines(Checked.Findings, Git, FileName);
        Files := Files + [Checked];
      end;

      if AOptions.UpdateBaseline then
      begin
        Output := TRuleBaseline.Build(Sources);
        Encoding := TUTF8Encoding.Create(False);
        try
          TFile.WriteAllText(BaselinePath, Output, Encoding);
        finally
          Encoding.Free;
        end;
        WriteError(Format('Baseline geschrieben: %s', [BaselinePath]));
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
    finally
      Git.Free;
      Stats.Free;
    end;
    if AOptions.OutputFile <> '' then
    begin
      Encoding := TUTF8Encoding.Create(False);
      try
        TFile.WriteAllText(AOptions.OutputFile, Output, Encoding);
      finally
        Encoding.Free;
      end;
    end
    else
    begin
      Stream := TStdStreams.CreateOutput;
      try
        WriteText(Stream, Output);
      finally
        Stream.Free;
      end;
    end;
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

end.
