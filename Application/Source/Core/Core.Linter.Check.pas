unit Core.Linter.Check;

// Host-Rolle Core: --check (#95), die Prüfung ohne Editor. Mit --suppression-stats statt der Treffer die
// Auswertung der Unterdrückungskommentare, mit --metrics die Code-Metriken (#66), mit --todos die offenen
// TODO-Einträge (#68). Bekannte Treffer aus der Baseline werden ausgeblendet; --update-baseline schreibt sie neu
// (#97). Mit --format sarif trägt jedes Ergebnis partialFingerprints und mit Baseline baselineState. Mit --timings
// (#1356) misst der Lauf die Prüfung je Unit und je Regel. Exit-Code: 1, wenn ein Treffer --fail-on erreicht, sonst
// 0; 3 Aufruf- oder Lesefehler.

interface

uses
  System.Generics.Collections,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Projects.PackageReader,
  Atlas.Common.Findings.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Findings.Output,
  Atlas.Common.Findings.Filter,
  Atlas.Common.Findings.Baseline,
  Atlas.Common.Findings.Scopes,
  Atlas.Common.Findings.SuppressionStats,
  Atlas.Common.Metrics.Contract,
  Atlas.Common.Todos.Contract,
  Atlas.Common.Diagnostics.CheckProfile,
  Atlas.Common.Diagnostics.CheckMemory,
  Core.CommandLine,
  Core.VersionControlChanges,
  Core.WorkspaceGroup,
  Core.Linter.Baseline,
  Core.Linter.Host;

type
  TLinterCheck = class
  private
    FOptions: TCommandLineOptions;
    FHost: TCoreLinterHost;
    FConfigRoot: string;
    FSettings: TServerSettings;
    FFilter: TFindingFilter;
    FRules: TCoreLinterCheckText;
    FRuleInfos: TArray<TFindingRuleInfo>;
    FBaselinePath: string;
    FBaseline: IRuleBaseline;
    FRoot: string;
    FPackages: TArray<TPackageSource>;
    FPrograms: TArray<string>;
    FGit: TVcsChanges;
    FGroup: TCoreWorkspaceGroup;
    FTimings: TCheckTimings;
    FProfiler: TCheckProfiler;
    /// <summary>Speicher des Laufs mit --timings (#1480); sonst nil.</summary>
    FMemory: TCheckMemoryTrack;
    FStats: TSuppressionStats;
    FCheckedPaths: TList<string>;
    FFiles: TArray<TCheckedFile>;
    FBaselineSources: TArray<TBaselineSource>;
    FMetrics: TArray<TFileMetrics>;
    FTodos: TArray<TFileTodos>;
    function Prepare: Boolean;
    function Candidates(out ASources: TPascalSourceFunc): TArray<string>;
    function MarkFilter(AGit: TVcsChanges; AChangedLines: Boolean): TLinterMarkFilter;
    procedure CheckFile(const AFileName: string; const ASource: TPascalSource);
    function RunRules(const AFileName, ARelativePath, AText: string; const ASource: TPascalSource;
      out AScopes: TFindingScopes): TArray<TRuleFinding>;
    procedure AddFindings(const AFileName, ARelativePath, AText: string; const AScopes: TFindingScopes;
      const AFindings: TArray<TRuleFinding>);
    procedure AddAbsentFiles;
    function WriteBaseline: Integer;
    function Render: string;
    procedure FinishTimings(AElapsedMs: Int64);
  public
    constructor Create(const AOptions: TCommandLineOptions; const AConfigRoot: string; const AHost: TCoreLinterHost);
    destructor Destroy; override;
    /// <summary>Prüft das Ziel und schreibt das Ergebnis; Exit-Code.</summary>
    function Execute: Integer;
    /// <summary>--check; Fehler in der Befehlszeile und unerwartete Fehler geben 3.</summary>
    class function Run(const AOptions: TCommandLineOptions; const AHost: TCoreLinterHost): Integer; static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Diagnostics,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Lsp.ServerActivity,
  Core.Linter.Output,
  Core.Linter.Settings,
  Core.Linter.Files,
  Core.Linter.Changes,
  Core.Linter.Index,
  Core.Linter.Reports,
  Atlas.Common.Checks.Contract;

{ TLinterCheck }

constructor TLinterCheck.Create(const AOptions: TCommandLineOptions; const AConfigRoot: string;
  const AHost: TCoreLinterHost);
begin
  inherited Create;
  FOptions := AOptions;
  FHost := AHost;
  FConfigRoot := AConfigRoot;
  FTimings := Default(TCheckTimings);
  FTimings.IndexMs := -1;
  FTimings.ClearHeap;
  FStats := TSuppressionStats.Create;
  FCheckedPaths := TList<string>.Create;
end;

destructor TLinterCheck.Destroy;
begin
  FProfiler.Free;
  TLinterIndex.Release(FGroup);
  // Erst nach der Gruppe: Der Indexaufbau meldet sich bis zum Anhalten bei FMemory.
  FMemory.Free;
  FCheckedPaths.Free;
  FGit.Free;
  FStats.Free;
  inherited Destroy;
end;

function TLinterCheck.Prepare: Boolean;
begin
  FSettings := TLinterSettings.Load(FConfigRoot);
  TFileEncodingDefaults.SetFolder(FConfigRoot, FSettings.DefaultEncoding);
  // Regelprofil der Kommandozeile (#146), z. B. "strict" im CI.
  TLinterSettings.ApplyProfile(FOptions, FSettings);
  FFilter := TLinterSettings.FilterOf(FOptions);
  FRules := FHost.Rules.CheckAll;
  FRuleInfos := FHost.Rules.Infos(FSettings, not FOptions.NoIndex);
  FBaselinePath := TLinterBaseline.PathOf(FOptions, FConfigRoot);
  Result := TLinterBaseline.Load(FOptions, FBaselinePath, FBaseline);
end;

function TLinterCheck.Candidates(out ASources: TPascalSourceFunc): TArray<string>;
begin
  Result := TLinterFiles.Collect(FOptions.CheckTarget, FSettings, FHost.InstalledVersions, FRoot, ASources);
  FPackages := TLinterFiles.Packages(Result);
  FPrograms := TLinterFiles.Programs(Result);
  // --update-baseline schreibt immer für alle Dateien; den Hinweis dazu gibt TLinterSettings.Validate.
  if (FOptions.ChangedRef <> '') and not FOptions.UpdateBaseline then
  begin
    FGit := TLinterChanges.Detect(FConfigRoot, FSettings, FHost);
    Result := TLinterChanges.Select(FOptions, Result, FGit);
  end;
end;

function TLinterCheck.MarkFilter(AGit: TVcsChanges; AChangedLines: Boolean): TLinterMarkFilter;
begin
  Result := Default(TLinterMarkFilter);
  Result.Filter := FFilter;
  Result.Settings := FSettings;
  Result.Rules := FRuleInfos;
  Result.Git := AGit;
  Result.ChangedLines := AChangedLines;
end;

procedure TLinterCheck.CheckFile(const AFileName: string; const ASource: TPascalSource);
var
  mRelativePath, mText: string;
  mFormat: TFileFormat;
  mScopes: TFindingScopes;
begin
  mRelativePath := ExtractRelativePath(IncludeTrailingPathDelimiter(FRoot), AFileName);
  if not FFilter.AcceptsFile(mRelativePath) then
  begin
    Exit;
  end;
  try
    mText := TFileEncoding.LoadFromFile(AFileName, mFormat);
  except
    on E: Exception do
    begin
      TLinterOutput.Error(Format('%s: %s', [AFileName, E.Message]));
      Exit;
    end;
  end;
  if FOptions.Metrics then
  begin
    FMetrics := FMetrics + [TLinterReports.MetricsOf(mRelativePath, mText)];
  end
  else if FOptions.Todos then
  begin
    FTodos := FTodos + TLinterReports.TodosOf(mRelativePath, mText, FSettings);
  end
  else
  begin
    AddFindings(AFileName, mRelativePath, mText, mScopes, RunRules(AFileName, mRelativePath, mText, ASource,
      mScopes));
  end;
end;

function TLinterCheck.RunRules(const AFileName, ARelativePath, AText: string; const ASource: TPascalSource;
  out AScopes: TFindingScopes): TArray<TRuleFinding>;
var
  mProject: TCheckProject;
  mPrevious: TCheckProfiler;
  mWatch: TStopwatch;
begin
  mProject := TLinterIndex.ProjectOf(AFileName, FPackages, FPrograms, FGroup);
  // Zeitprofil (#1356): Die Engine meldet ihre Regelzeiten an den angehängten Profiler.
  mPrevious := TCheckProfiler.Attach(FProfiler);
  mWatch := TStopwatch.StartNew;
  try
    Result := FRules(FSettings, ARelativePath, AText, mProject, ASource, AScopes);
  finally
    TCheckProfiler.Attach(mPrevious);
    if FProfiler <> nil then
    begin
      FProfiler.AddUnit(AFileName, TCheckProfiler.TicksToMicroseconds(mWatch.ElapsedTicks, TStopwatch.Frequency));
    end;
  end;
  if FOptions.SuppressionStats then
  begin
    FStats.Add(AText, Result);
  end;
end;

procedure TLinterCheck.AddFindings(const AFileName, ARelativePath, AText: string; const AScopes: TFindingScopes;
  const AFindings: TArray<TRuleFinding>);
var
  mSource: TBaselineSource;
  mMarks: TArray<TBaselineMark>;
  mChecked: TCheckedFile;
begin
  if FOptions.UpdateBaseline then
  begin
    mSource := Default(TBaselineSource);
    mSource.Path := ARelativePath;
    mSource.Text := AText;
    mSource.Findings := AFindings;
    FBaselineSources := FBaselineSources + [mSource];
    Exit;
  end;
  FCheckedPaths.Add(LowerCase(TRuleBaseline.NormalizePath(ARelativePath)));
  // Zustand je Treffer (#97): mit Baseline neu oder unverändert, für SARIF mit Fingerabdrücken.
  mMarks := nil;
  mChecked := Default(TCheckedFile);
  mChecked.Findings := AFindings;
  if FBaseline <> nil then
  begin
    mMarks := FBaseline.Classify(ARelativePath, AText, AScopes, AFindings);
    mChecked.Findings := TLinterBaseline.NewFindings(mMarks);
  end
  else if FOptions.CheckFormat = TFindingsFormat.Sarif then
  begin
    mMarks := TRuleBaseline.Mark(AText, AScopes, AFindings);
  end;
  mChecked.Path := ARelativePath;
  mChecked.FullPath := TPath.GetFullPath(AFileName);
  mChecked.Findings := FFilter.Apply(mChecked.Findings);
  if (FGit <> nil) and FOptions.ChangedLines then
  begin
    mChecked.Findings := TLinterChanges.InChangedLines(mChecked.Findings, FGit, AFileName);
  end;
  if FOptions.CheckFormat = TFindingsFormat.Sarif then
  begin
    mChecked.Marks := TLinterBaseline.KeptMarks(mMarks, MarkFilter(FGit, FOptions.ChangedLines), AFileName);
  end;
  FFiles := FFiles + [mChecked];
end;

/// <summary>Voller Pfad eines Baseline-Eintrags unter ARoot.</summary>
function EntryFile(const ARoot, APath: string): string;
begin
  Result := TPath.Combine(ARoot, StringReplace(APath, '/', PathDelim, [rfReplaceAll]));
end;

procedure TLinterCheck.AddAbsentFiles;
var
  mPath: string;
  mOrphan: TCheckedFile;
begin
  // SARIF: Einträge von Dateien, die es nicht mehr gibt, als "absent" (nur bei vollem Lauf).
  if (FBaseline = nil) or (FOptions.CheckFormat <> TFindingsFormat.Sarif) or (FOptions.ChangedRef <> '') or
    FOptions.SuppressionStats then
  begin
    Exit;
  end;
  for mPath in FBaseline.Paths do
  begin
    if not FCheckedPaths.Contains(LowerCase(mPath)) and FFilter.AcceptsFile(mPath) and
      not TFile.Exists(EntryFile(FRoot, mPath)) then
    begin
      mOrphan := Default(TCheckedFile);
      mOrphan.Path := mPath;
      mOrphan.FullPath := EntryFile(FRoot, mPath);
      mOrphan.Marks := TLinterBaseline.KeptMarks(FBaseline.AbsentOf(mPath), MarkFilter(nil, False),
        mOrphan.FullPath);
      if Length(mOrphan.Marks) > 0 then
      begin
        FFiles := FFiles + [mOrphan];
      end;
    end;
  end;
end;

function TLinterCheck.WriteBaseline: Integer;
var
  mUpdate: TBaselineUpdate;
  mRoot: string;
begin
  mRoot := FRoot;
  mUpdate := TRuleBaseline.Update(FBaseline, FBaselineSources,
    function(const APath: string): Boolean
    begin
      Result := TFile.Exists(EntryFile(mRoot, APath));
    end);
  TLinterBaseline.ReportOrphans(mUpdate);
  TLinterOutput.SaveUtf8(FBaselinePath, mUpdate.Json);
  TLinterBaseline.ReportUpdate(mUpdate, FBaselinePath);
  Result := TFindingsOutput.cExitClean;
end;

function TLinterCheck.Render: string;
var
  mTitle: string;
  mJson: Boolean;
begin
  mTitle := ChangeFileExt(ExtractFileName(ExcludeTrailingPathDelimiter(FOptions.CheckTarget)), '');
  mJson := FOptions.CheckFormat = TFindingsFormat.Json;
  if FOptions.Metrics then
  begin
    Result := TLinterReports.MetricsText(FMetrics, FSettings, mJson, mTitle);
  end
  else if FOptions.Todos then
  begin
    Result := TLinterReports.TodosText(FTodos, mJson, mTitle);
  end
  else if FOptions.SuppressionStats then
  begin
    Result := FStats.Render(FOptions.CheckFormat);
  end
  else
  begin
    Result := TFindingsOutput.Render(FFiles, FOptions.CheckFormat, FRuleInfos,
      TLinterSettings.SourceRootOf(FOptions, FConfigRoot));
  end;
end;

procedure TLinterCheck.FinishTimings(AElapsedMs: Int64);
begin
  if FProfiler = nil then
  begin
    Exit;
  end;
  FProfiler.FinishRun(AElapsedMs);
  FTimings.Profile := FProfiler.Snapshot(TCheckRunProfile.cTop);
  FMemory.Finish;
  FTimings.ReadyBytes := FMemory.ReadyBytes;
  FTimings.GroupBytes := FMemory.GroupBytes;
  FTimings.PeakBytes := FMemory.PeakBytes;
  FTimings.TotalBytes := FMemory.EndBytes;
  TLinterOutput.Timings(FOptions, FTimings);
end;

function TLinterCheck.Execute: Integer;
var
  mOutput: string;
  mFiles: TArray<string>;
  mIndex: Integer;
  mSources: TPascalSourceFunc;
  mWatch: TStopwatch;
begin
  if not Prepare then
  begin
    Exit(TFindingsOutput.cExitFailure);
  end;
  if FOptions.Timings then
  begin
    FMemory := TLinterIndex.MemoryTrack;
  end;
  // Metriken und TODOs brauchen keinen Index.
  if not (FOptions.NoIndex or FOptions.Metrics or FOptions.Todos) then
  begin
    FGroup := TLinterIndex.Load(FOptions, FConfigRoot, FTimings, FMemory, FHost);
  end;
  if FOptions.Timings then
  begin
    FProfiler := TCheckProfiler.Create;
    FProfiler.BeginRun(Now);
  end;
  mWatch := TStopwatch.StartNew;
  mFiles := Candidates(mSources);
  // Fortschritt für die Statusdatei (#1901).
  for mIndex := 0 to High(mFiles) do
  begin
    TServerActivity.Shared.SetProgress(mIndex, Length(mFiles));
    CheckFile(mFiles[mIndex], mSources(mFiles[mIndex]));
  end;
  TServerActivity.Shared.SetProgress(Length(mFiles), Length(mFiles));
  if FOptions.UpdateBaseline then
  begin
    Exit(WriteBaseline);
  end;
  AddAbsentFiles;
  mOutput := Render;
  FinishTimings(mWatch.ElapsedMilliseconds);
  TLinterOutput.Write(FOptions, mOutput);
  Result := TFindingsOutput.cExitClean;
  if not (FOptions.SuppressionStats or FOptions.Metrics or FOptions.Todos) then
  begin
    Result := TFindingsOutput.ExitCode(FFiles, FOptions.FailOn);
  end;
end;

class function TLinterCheck.Run(const AOptions: TCommandLineOptions; const AHost: TCoreLinterHost): Integer;
var
  mTarget: TLinterTarget;
  mCheck: TLinterCheck;
begin
  TLinterOutput.Warnings(AOptions);
  if not TLinterSettings.Validate(AOptions) or not TLinterTarget.ResolveCheck(AOptions, mTarget) then
  begin
    Exit(TFindingsOutput.cExitFailure);
  end;
  try
    mCheck := TLinterCheck.Create(AOptions, mTarget.ConfigRoot, AHost);
    try
      Result := mCheck.Execute;
    finally
      mCheck.Free;
    end;
  except
    on E: Exception do
    begin
      TLinterOutput.Error(Format('%s: %s', [E.ClassName, E.Message]));
      Result := TFindingsOutput.cExitFailure;
    end;
  end;
end;

end.
