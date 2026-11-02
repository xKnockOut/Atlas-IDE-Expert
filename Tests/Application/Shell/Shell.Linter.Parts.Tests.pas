unit Shell.Linter.Parts.Tests;

// Teile des Linter-Modus (#95): Ziel und Einstellungen, Dateien, Baseline (#97), gespeicherte Abfragen (#1351),
// Formatieren (#1358), Befehlszeile der Prüfung, Berichte (#66, #68), Projekt einer Datei (#1112), Testprogramme
// (#1353), Sammelkorrektur (#1352) und Architekturübersicht (#1118). Die Befehle selbst prüft Shell.Linter.Tests
// über TLinterShell; Shell.Linter.Changes und Shell.Linter.Hotspots brauchen eine Versionsverwaltung und laufen
// nur dort mit.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLinterPartsTests = class
  private
    FFolder: string;
    function Path(const AName: string): string;
    procedure WriteFile(const AName, AText: string);
  public
    [Setup]
    procedure SetUp;
    [TearDown]
    procedure TearDown;
    /// <summary>Fehlendes Ziel scheitert; ohne Ziel gilt der aktuelle Ordner; Titel ohne Endung.</summary>
    [Test]
    procedure TargetResolvesFolderAndFile;
    /// <summary>atlas.json wird nach oben bis zum Stamm des Repositorys gesucht.</summary>
    [Test]
    procedure ConfigFileFoundUpToRepositoryRoot;
    /// <summary>--profile vor profile.cli vor profile; Filter aus der Befehlszeile; --source-root gewinnt.</summary>
    [Test]
    procedure ProfileFilterAndSourceRoot;
    [Test]
    procedure FilesKindsAndFolderCollect;
    /// <summary>.dpr-Texte und nicht lesbare Dateien; Index aus den Dateien.</summary>
    [Test]
    procedure FilesProgramsReadTextAndIndex;
    /// <summary>--update-baseline schreibt unter dem neuen Namen; eine genannte fehlende Baseline scheitert.</summary>
    [Test]
    procedure BaselinePathAndLoad;
    /// <summary>Nur neue Treffer; nicht mehr gefundene tragen den Standard-Schweregrad und durchlaufen den Filter.
    /// </summary>
    [Test]
    procedure BaselineNewAndKeptMarks;
    [Test]
    procedure QueryResolvesSavedQueries;
    [Test]
    procedure FormattingKindOf;
    [Test]
    procedure CheckValidateAndDescriptors;
    [Test]
    procedure ReportsSlashPathAndMetrics;
    /// <summary>Ohne Gruppe nur Dateiname und Formulare; mit testUnits.project dessen .dpr.</summary>
    [Test]
    procedure ProjectOfAndTestPrograms;
    /// <summary>Ohne Regeln keine Treffer; die Ausgabe schreibt UTF-8 ohne BOM.</summary>
    [Test]
    procedure FixCheckAndUtf8Output;
    [Test]
    procedure ArchitectureOverviewOfFolder;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Rules.Filter,
  Atlas.Common.Rules.Baseline,
  Atlas.Common.Rules.BulkFix,
  Atlas.Common.Rules.FormatOutput,
  Atlas.Common.Index.Contract,
  Atlas.Common.Architecture.Overview,
  Shell.CommandLine,
  Shell.Linter.Output,
  Shell.Linter.Settings,
  Shell.Linter.Files,
  Shell.Linter.Index,
  Shell.Linter.Baseline,
  Shell.Linter.Reports,
  Shell.Linter.Architecture,
  Shell.Linter.Query,
  Shell.Linter.Formatting,
  Shell.Linter.AffectedTests,
  Shell.Linter.Fix,
  Shell.Linter.Check;

procedure TLinterPartsTests.SetUp;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'atlas-linter-parts-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FFolder);
end;

procedure TLinterPartsTests.TearDown;
begin
  if TDirectory.Exists(FFolder) then
  begin
    TDirectory.Delete(FFolder, True);
  end;
  FFolder := '';
end;

function TLinterPartsTests.Path(const AName: string): string;
begin
  // Namen mit \ für alle Plattformen.
  Result := TPath.Combine(FFolder, StringReplace(AName, '\', PathDelim, [rfReplaceAll]));
end;

procedure TLinterPartsTests.WriteFile(const AName, AText: string);
begin
  ForceDirectories(ExtractFileDir(Path(AName)));
  TFile.WriteAllText(Path(AName), AText, TEncoding.UTF8);
end;

procedure TLinterPartsTests.TargetResolvesFolderAndFile;
var
  mTarget: TLinterTarget;
begin
  Assert.IsFalse(TLinterTarget.Resolve(Path('Fehlt'), mTarget));
  Assert.IsTrue(TLinterTarget.Resolve(FFolder, mTarget));
  Assert.IsTrue(mTarget.IsFolder);
  Assert.AreEqual(TPath.GetFullPath(FFolder), mTarget.ConfigRoot);
  Assert.AreEqual(ExtractFileName(FFolder), mTarget.Title);
  WriteFile('Src\Haupt.dproj', '<Project/>');
  Assert.IsTrue(TLinterTarget.Resolve(Path('Src\Haupt.dproj'), mTarget));
  Assert.IsFalse(mTarget.IsFolder);
  Assert.AreEqual(TPath.GetFullPath(Path('Src')), mTarget.ConfigRoot);
  Assert.AreEqual('Haupt', mTarget.Title);
  Assert.IsTrue(TLinterTarget.ResolveOrCurrent('', mTarget));
  Assert.AreEqual(GetCurrentDir, mTarget.Target);
end;

procedure TLinterPartsTests.ConfigFileFoundUpToRepositoryRoot;
begin
  TDirectory.CreateDirectory(Path('Repo\.git'));
  TDirectory.CreateDirectory(Path('Repo\A\B'));
  // Ohne Datei bleibt der Name im Ordner des Ziels.
  Assert.AreEqual(TPath.Combine(Path('Repo\A\B'), ConfigurationFileName),
    TLinterSettings.ConfigFileOf(Path('Repo\A\B')));
  WriteFile('Repo\' + ConfigurationFileName, '{}');
  Assert.AreEqual(IncludeTrailingPathDelimiter(Path('Repo')) + ConfigurationFileName,
    TLinterSettings.ConfigFileOf(Path('Repo\A\B')));
  // Über dem Stamm des Repositorys wird nicht gesucht.
  WriteFile(ConfigurationFileName, '{}');
  TDirectory.CreateDirectory(Path('Repo\A\.git'));
  Assert.AreEqual(TPath.Combine(Path('Repo\A\B'), ConfigurationFileName),
    TLinterSettings.ConfigFileOf(Path('Repo\A\B')));
end;

procedure TLinterPartsTests.ProfileFilterAndSourceRoot;
var
  mSettings: TServerSettings;
  mFilter: TFindingFilter;
begin
  mSettings := TServerSettings.Default;
  mSettings.Profile := 'basis';
  mSettings.CliProfile := 'ci';
  TLinterSettings.ApplyProfile(TCommandLineOptions.Parse(['--check', FFolder]), mSettings);
  Assert.AreEqual('ci', mSettings.Profile, 'profile.cli');
  TLinterSettings.ApplyProfile(TCommandLineOptions.Parse(['--check', FFolder, '--profile', 'strict']), mSettings);
  Assert.AreEqual('strict', mSettings.Profile, '--profile');
  mFilter := TLinterSettings.FilterOf(TCommandLineOptions.Parse(['--check', FFolder, '--units', 'A']));
  Assert.IsTrue(mFilter.AcceptsFile('Src/A.pas'));
  Assert.IsFalse(mFilter.AcceptsFile('Src/B.pas'));
  Assert.AreEqual(ExcludeTrailingPathDelimiter(TPath.GetFullPath(FFolder)),
    TLinterSettings.SourceRootOf(TCommandLineOptions.Parse(['--check', FFolder, '--source-root', FFolder]), '/x'));
end;

procedure TLinterPartsTests.FilesKindsAndFolderCollect;
var
  mRoot: string;
  mSources: TCheckSourceFunc;
begin
  Assert.IsTrue(TLinterFiles.IsSourceFile('A.PAS'));
  Assert.IsTrue(TLinterFiles.IsSourceFile('P.dpk'));
  Assert.IsFalse(TLinterFiles.IsSourceFile('F.dfm'));
  Assert.IsTrue(TLinterFiles.IsReportFile('bericht.HTML'));
  Assert.IsFalse(TLinterFiles.IsReportFile('bericht.txt'));
  WriteFile('Src\A.pas', 'unit A; interface implementation end.');
  WriteFile('Src\Sub\B.dpr', 'program B; begin end.');
  WriteFile('Src\C.txt', 'x');
  Assert.AreEqual(2, Integer(Length(TLinterFiles.Collect(Path('Src'), TServerSettings.Default, mRoot, mSources))));
  Assert.AreEqual(TPath.GetFullPath(Path('Src')), mRoot);
  Assert.AreEqual(1, Integer(Length(TLinterFiles.Collect(Path('Src\A.pas'), TServerSettings.Default, mRoot,
    mSources))), 'einzelne Datei');
  Assert.IsTrue(Assigned(mSources));
end;

procedure TLinterPartsTests.FilesProgramsReadTextAndIndex;
var
  mText: string;
  mIndex: ISymbolIndex;
  mFiles: TArray<string>;
begin
  WriteFile('A.pas', 'unit A; interface type TA = class end; implementation end.');
  WriteFile('P.dpr', 'program P; begin end.');
  mFiles := TArray<string>.Create(Path('A.pas'), Path('P.dpr'));
  Assert.AreEqual(1, Integer(Length(TLinterFiles.Programs(mFiles))));
  Assert.IsTrue(TLinterFiles.Programs(mFiles)[0].StartsWith('program P'));
  Assert.AreEqual(0, Integer(Length(TLinterFiles.Packages(mFiles))));
  Assert.IsFalse(TLinterFiles.ReadText(Path('Fehlt.pas'), mText));
  Assert.AreEqual('', mText);
  mIndex := TLinterFiles.IndexOf(mFiles + [Path('Fehlt.pas')], TLinterFiles.SourcesOf(nil, nil));
  Assert.AreEqual(2, mIndex.UnitCount, 'die fehlende Datei fällt weg');
end;

procedure TLinterPartsTests.BaselinePathAndLoad;
var
  mBaseline: IRuleBaseline;
  mOptions: TCommandLineOptions;
begin
  mOptions := TCommandLineOptions.Parse(['--check', FFolder, '--update-baseline']);
  Assert.AreEqual(TPath.Combine(FFolder, BaselineFileName), TLinterBaseline.PathOf(mOptions, FFolder));
  Assert.IsTrue(TLinterBaseline.Load(mOptions, Path('Fehlt.json'), mBaseline), 'Neuschreiben ohne alte Datei');
  Assert.IsNull(mBaseline);
  mOptions := TCommandLineOptions.Parse(['--check', FFolder, '--baseline', Path('Fehlt.json')]);
  Assert.AreEqual(Path('Fehlt.json'), TLinterBaseline.PathOf(mOptions, FFolder));
  Assert.IsFalse(TLinterBaseline.Load(mOptions, Path('Fehlt.json'), mBaseline));
  // Ohne --baseline ist eine fehlende Datei keine Baseline.
  mOptions := TCommandLineOptions.Parse(['--check', FFolder]);
  Assert.IsTrue(TLinterBaseline.Load(mOptions, TLinterBaseline.PathOf(mOptions, FFolder), mBaseline));
  Assert.IsNull(mBaseline);
end;

function MarkOf(AState: TBaselineState; const ARuleId: string): TBaselineMark;
begin
  Result := Default(TBaselineMark);
  Result.State := AState;
  Result.Finding.RuleId := ARuleId;
  Result.Finding.Severity := TRuleSeverity.Error;
end;

procedure TLinterPartsTests.BaselineNewAndKeptMarks;
var
  mMarks, mKept: TArray<TBaselineMark>;
  mFilter: TLinterMarkFilter;
  mDescriptor: TRuleDescriptor;
begin
  mMarks := TArray<TBaselineMark>.Create(MarkOf(TBaselineState.New, 'neu'),
    MarkOf(TBaselineState.Unchanged, 'alt'), MarkOf(TBaselineState.Absent, 'weg'));
  Assert.AreEqual(1, Integer(Length(TLinterBaseline.NewFindings(mMarks))));
  Assert.AreEqual('neu', TLinterBaseline.NewFindings(mMarks)[0].RuleId);
  mDescriptor := Default(TRuleDescriptor);
  mDescriptor.Id := 'weg';
  mDescriptor.DefaultSeverity := TRuleSeverity.Warning;
  mFilter := Default(TLinterMarkFilter);
  mFilter.Settings := TServerSettings.Default;
  mFilter.Descriptors := TArray<TRuleDescriptor>.Create(mDescriptor);
  mKept := TLinterBaseline.KeptMarks(mMarks, mFilter, Path('A.pas'));
  Assert.AreEqual(3, Integer(Length(mKept)));
  Assert.IsTrue(mKept[2].Finding.Severity = TRuleSeverity.Warning, 'Standard-Schweregrad der Regel');
  mFilter.Filter.MinSeverity := TRuleSeverity.Error;
  Assert.AreEqual(2, Integer(Length(TLinterBaseline.KeptMarks(mMarks, mFilter, Path('A.pas')))), 'Filter');
end;

procedure TLinterPartsTests.QueryResolvesSavedQueries;
var
  mSettings: TServerSettings;
  mSaved: TSavedQuery;
  mQuery: TLinterQueryText;
begin
  mSaved := Default(TSavedQuery);
  mSaved.Name := 'Leer';
  mSaved.Query := 'classes where methods = 0';
  mSaved.FailIfAny := True;
  mSettings := TServerSettings.Default;
  mSettings.Queries := TArray<TSavedQuery>.Create(mSaved);
  Assert.IsTrue(TLinterQuery.Resolve('  units  ', False, mSettings, mQuery));
  Assert.AreEqual('units', mQuery.Text);
  Assert.IsFalse(mQuery.FailOnMatch);
  Assert.IsTrue(TLinterQuery.Resolve('@leer', False, mSettings, mQuery));
  Assert.AreEqual(mSaved.Query, mQuery.Text);
  Assert.IsTrue(mQuery.FailOnMatch, 'failIfAny');
  Assert.IsFalse(TLinterQuery.Resolve('@fehlt', False, mSettings, mQuery));
end;

procedure TLinterPartsTests.FormattingKindOf;
var
  mKind: TFormatOutputKind;
begin
  Assert.IsTrue(TLinterFormatting.KindOf(TCommandLineOptions.Parse(['--check', FFolder, '--format-check']),
    mKind));
  Assert.IsTrue(mKind = TFormatOutputKind.Text);
  Assert.IsTrue(TLinterFormatting.KindOf(TCommandLineOptions.Parse(['--check', FFolder, '--format-check',
    '--format', 'json']), mKind));
  Assert.IsTrue(mKind = TFormatOutputKind.Json);
  Assert.IsTrue(TLinterFormatting.KindOf(TCommandLineOptions.Parse(['--check', FFolder, '--format-check',
    '--format', 'diff']), mKind));
  Assert.IsTrue(mKind = TFormatOutputKind.Diff);
  Assert.IsFalse(TLinterFormatting.KindOf(TCommandLineOptions.Parse(['--check', FFolder, '--format-check',
    '--format', 'sarif']), mKind));
  Assert.IsFalse(TLinterFormatting.KindOf(TCommandLineOptions.Parse(['--check', FFolder, '--format-check',
    '--metrics']), mKind));
end;

procedure TLinterPartsTests.CheckValidateAndDescriptors;
var
  mWithout, mWith: TArray<TRuleDescriptor>;
  mSettings: TServerSettings;
begin
  Assert.IsTrue(TLinterCheck.Validate(TCommandLineOptions.Parse(['--check', FFolder])));
  Assert.IsFalse(TLinterCheck.Validate(TCommandLineOptions.Parse(['--check', FFolder, '--metrics', '--todos'])));
  Assert.IsFalse(TLinterCheck.Validate(TCommandLineOptions.Parse(['--check', FFolder, '--metrics', '--format',
    'sarif'])));
  mSettings := TServerSettings.Default;
  mWithout := TLinterCheck.DescriptorsOf(nil, mSettings, False);
  Assert.AreEqual(2, Integer(Length(mWithout)), 'Syntax und Sprachstand');
  mWith := TLinterCheck.DescriptorsOf(nil, mSettings, True);
  Assert.AreEqual(Integer(Length(mWithout)), Integer(Length(mWith)), 'ohne gespeicherte Abfragen');
end;

procedure TLinterPartsTests.ReportsSlashPathAndMetrics;
begin
  Assert.AreEqual('Src/A.pas', TLinterReports.SlashPath('Src\A.pas'));
  Assert.AreEqual('Src/A.pas', TLinterReports.MetricsOf('Src\A.pas',
    'unit A; interface implementation procedure P; begin end; end.').Path);
  Assert.AreEqual(1, Integer(Length(TLinterReports.TodosOf('A.pas', '// TODO: weiter' + sLineBreak + 'unit A;',
    TServerSettings.Default))));
  Assert.AreEqual(0, Integer(Length(TLinterReports.TodosOf('A.pas', 'unit A;', TServerSettings.Default))));
  Assert.IsTrue(TLinterReports.TodosText(nil, True, 'T') <> '', 'JSON auch ohne Einträge');
end;

procedure TLinterPartsTests.ProjectOfAndTestPrograms;
var
  mProject: TCheckProject;
  mSettings: TServerSettings;
  mPrograms: TArray<string>;
begin
  mProject := TLinterIndex.ProjectOf(Path('A.pas'), nil, nil, nil);
  Assert.AreEqual(TPath.GetFullPath(Path('A.pas')), mProject.FileName);
  Assert.AreEqual('', mProject.Name);
  mSettings := TServerSettings.Default;
  mSettings.TestUnits.Project := TPath.Combine('Tests', 'Alle.dproj');
  mPrograms := TLinterAffectedTests.ProgramsOf(FFolder, FFolder, mSettings, nil, nil);
  Assert.AreEqual(1, Integer(Length(mPrograms)));
  Assert.AreEqual(TPath.GetFullPath(Path('Tests\Alle.dpr')), mPrograms[0]);
end;

procedure TLinterPartsTests.FixCheckAndUtf8Output;
var
  mCheck: TLinterFixCheck;
  mFunc: TBulkFixCheck;
  mBytes: TBytes;
begin
  mCheck := Default(TLinterFixCheck);
  mCheck.Settings := TServerSettings.Default;
  mCheck.RelativePath := 'A.pas';
  mCheck.FileName := Path('A.pas');
  mCheck.Source := TLinterFiles.SourcesOf(nil, nil)(Path('A.pas'));
  mFunc := TLinterFix.CheckFunc(mCheck);
  Assert.AreEqual(0, Integer(Length(mFunc('unit A; interface implementation end.', Default(TBulkFixLineMap)))));
  TLinterOutput.SaveUtf8(Path('aus.txt'), 'Grüße');
  mBytes := TFile.ReadAllBytes(Path('aus.txt'));
  Assert.AreEqual(Integer(Length(TEncoding.UTF8.GetBytes('Grüße'))), Integer(Length(mBytes)), 'ohne BOM');
end;

procedure TLinterPartsTests.ArchitectureOverviewOfFolder;
var
  mTarget: TLinterTarget;
  mOverview: TArchitectureOverview;
begin
  WriteFile('Src\A.pas', 'unit A; interface uses B; implementation end.');
  WriteFile('Src\B.pas', 'unit B; interface implementation end.');
  Assert.IsTrue(TLinterTarget.Resolve(Path('Src'), mTarget));
  mOverview := TLinterArchitecture.OverviewOf(mTarget, TServerSettings.Default);
  Assert.AreEqual(2, Integer(Length(mOverview.Units)));
end;

initialization
  TDUnitX.RegisterTestFixture(TLinterPartsTests);

end.
