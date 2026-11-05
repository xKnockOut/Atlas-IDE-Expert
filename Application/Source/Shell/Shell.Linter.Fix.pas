unit Shell.Linter.Fix;

// Internals-Rolle Shell: Sammelkorrektur (#1352). --fix <Regeln|all> wendet je Datei die sicheren Korrekturen
// dieser Regeln an (TBulkFix: Konfidenz ab fix.minConfidence, Katalogfeld safeFix, bis zu drei Durchgänge, keine
// neuen Syntaxfehler) und schreibt alle geänderten Dateien oder keine, in ihrer Kodierung und mit ihren
// Zeilenenden; --fix-dry-run gibt stattdessen den vereinigten Diff aus. Es gelten --units, --changed, --diff,
// --changed-lines (nur Treffer in geänderten Zeilen), --baseline (deren Treffer bleiben) und --profile. Die
// Zusammenfassung (Regeln, Dateien, Korrekturen je Regel, übersprungene Treffer) steht auf stderr. Für den
// Exit-Code zählen die Treffer, die nach der Korrektur bleiben.

interface

uses
  System.Generics.Collections,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Projects.PackageReader,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Rules.Filter,
  Atlas.Common.Rules.Output,
  Atlas.Common.Rules.Baseline,
  Atlas.Common.Rules.BulkFix,
  Shell.CommandLine,
  Shell.VcsChanges,
  Shell.WorkspaceGroup;

type
  /// <summary>Was die Prüfung einer Datei für die Sammelkorrektur braucht.</summary>
  TLinterFixCheck = record
    Rules: TArray<IRule>;
    Settings: TServerSettings;
    RelativePath: string;
    FileName: string;
    Project: TCheckProject;
    Source: TCheckSource;
    /// <summary>Deren Treffer bleiben; nil ohne Baseline.</summary>
    Baseline: IRuleBaseline;
    Filter: TFindingFilter;
    /// <summary>Mit Git und ChangedLines nur Treffer in geänderten Zeilen des Ausgangstexts.</summary>
    Git: TVcsChanges;
    ChangedLines: Boolean;
  end;

  TLinterFix = class
  private
    FOptions: TCommandLineOptions;
    FSettings: TServerSettings;
    FFilter: TFindingFilter;
    FAllRules: TArray<IRule>;
    FFixRules: TArray<IRule>;
    FFixOptions: TBulkFixOptions;
    FBaseline: IRuleBaseline;
    FGit: TVcsChanges;
    FGroup: TShellWorkspaceGroup;
    FRoot: string;
    FPackages: TArray<TPackageSource>;
    FPrograms: TArray<string>;
    FFormats: TDictionary<string, TFileFormat>;
    FRelative: TDictionary<string, string>;
    FResults: TArray<TBulkFixFile>;
    FRemaining: TArray<TCheckedFile>;
    function Prepare(const AConfigRoot: string): Boolean;
    function Candidates(const AConfigRoot: string; out ASources: TCheckSourceFunc): TArray<string>;
    function CheckOf(const AFileName, ARelativePath: string; const ASource: TCheckSource): TLinterFixCheck;
    procedure FixFile(const AFileName: string; const ASource: TCheckSource);
    procedure Report;
  public
    constructor Create(const AOptions: TCommandLineOptions);
    destructor Destroy; override;
    /// <summary>Korrigiert das Ziel; Exit-Code nach den verbliebenen Treffern, 3 bei Fehlern.</summary>
    function Execute(const AConfigRoot: string): Integer;
    /// <summary>--fix: Sammelkorrektur statt Prüfung.</summary>
    class function Run(const AOptions: TCommandLineOptions): Integer; static;
    /// <summary>Treffer einer Datei für die Sammelkorrektur und den Exit-Code: Regeln, Filter, Baseline (deren
    /// Treffer bleiben) und mit --changed-lines nur Treffer in geänderten Zeilen des Ausgangstexts. Eigene Routine,
    /// damit die anonyme Methode nur ihren Parameter einfängt.</summary>
    class function CheckFunc(const ACheck: TLinterFixCheck): TBulkFixCheck; static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Catalog,
  Atlas.Common.Rules.ChangedFiles,
  Atlas.Common.Rules.Scopes,
  Atlas.Common.Diagnostics.CheckProfile,
  Shell.Linter.Output,
  Shell.Linter.Settings,
  Shell.Linter.Files,
  Shell.Linter.Changes,
  Shell.Linter.Index,
  Shell.Linter.Baseline,
  Atlas.Common.Localization.Texts;

type
{$SCOPEDENUMS ON}
  TLinterFixText = (Header, Affected, Changed, Conflicts);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TLinterFixText] of TAtlasText = (
    (De: 'Sammelkorrektur: %s (Konfidenz ab %s)'; En: 'Bulk fix: %s (confidence from %s)'),
    (De: 'Betroffene Dateien: %s'; En: 'Affected files: %s'),
    (De: 'Geänderte Dateien: %s'; En: 'Changed files: %s'),
    (De: '--fix verträgt sich nicht mit --metrics, --todos, --suppression-stats und --update-baseline';
    En: '--fix does not go with --metrics, --todos, --suppression-stats and --update-baseline'));

/// <summary>Nur die Treffer aus AFindings, deren Zeile im Ausgangstext laut ALines geändert ist.</summary>
function InChangedLines(const ACheck: TLinterFixCheck; const AFindings: TArray<TRuleFinding>;
  const ALines: TBulkFixLineMap): TArray<TRuleFinding>;
var
  mChanged: TChangedLines;
  mFinding: TRuleFinding;
begin
  Result := nil;
  if not TChangedFiles.LinesOf(ACheck.Git.Lines, ACheck.Git.RepoRoot, ACheck.FileName, mChanged) then
  begin
    Exit;
  end;
  for mFinding in AFindings do
  begin
    if mChanged.Contains(ALines.Original(mFinding.Range.StartPos.Line)) then
    begin
      Result := Result + [mFinding];
    end;
  end;
end;

/// <summary>Treffer von AText nach Regeln, Baseline und Filter.</summary>
function FindingsOf(const ACheck: TLinterFixCheck; const AText: string): TArray<TRuleFinding>;
var
  mScopes: TFindingScopes;
begin
  Result := TFileChecker.CheckText(ACheck.Rules, ACheck.Settings, ACheck.RelativePath, AText,
    TCheckOrigin.Make(ACheck.Project, ACheck.Source), mScopes);
  if ACheck.Baseline <> nil then
  begin
    Result := TLinterBaseline.NewFindings(ACheck.Baseline.Classify(ACheck.RelativePath, AText, mScopes, Result));
  end;
  Result := ACheck.Filter.Apply(Result);
end;

class function TLinterFix.CheckFunc(const ACheck: TLinterFixCheck): TBulkFixCheck;
var
  mCheck: TLinterFixCheck;
begin
  mCheck := ACheck;
  Result :=
    function(const AText: string; const ALines: TBulkFixLineMap): TArray<TRuleFinding>
    begin
      Result := FindingsOf(mCheck, AText);
      if (mCheck.Git <> nil) and mCheck.ChangedLines then
      begin
        Result := InChangedLines(mCheck, Result, ALines);
      end;
    end;
end;

/// <summary>Schreibt in der Kodierung und mit den Zeilenenden, mit denen die Datei gelesen wurde (#121).</summary>
function WriterOf(const AFormats: TDictionary<string, TFileFormat>): TBulkFixWrite;
begin
  Result :=
    procedure(const AFileName, AText: string)
    begin
      // Jede Datei der Ergebnisse steht in AFormats: Beide füllt FixFile.
      TFileEncoding.SaveToFile(AFileName, AText, AFormats[AFileName]); // lsp-ignore: dictionary-get-without-check
    end;
end;

constructor TLinterFix.Create(const AOptions: TCommandLineOptions);
begin
  inherited Create;
  FOptions := AOptions;
  FFormats := TDictionary<string, TFileFormat>.Create;
  FRelative := TDictionary<string, string>.Create;
end;

destructor TLinterFix.Destroy;
begin
  TLinterIndex.Release(FGroup);
  FGit.Free;
  FRelative.Free;
  FFormats.Free;
  inherited Destroy;
end;

function TLinterFix.Prepare(const AConfigRoot: string): Boolean;
var
  mBaselinePath: string;
begin
  FSettings := TLinterSettings.Load(AConfigRoot);
  TFileEncodingDefaults.SetFolder(AConfigRoot, FSettings.DefaultEncoding);
  TLinterSettings.ApplyProfile(FOptions, FSettings);
  FFilter := TLinterSettings.FilterOf(FOptions);
  FAllRules := BuiltinRules;
  FFixRules := TBulkFix.RulesFor(FAllRules, FOptions.FixRules);
  FFixOptions := TBulkFixOptions.Create(FOptions.FixRules, FSettings.FixMinConfidence, TRuleCatalog.Shared.Entries);
  // Baseline (#97): Ihre Treffer bleiben unberührt. --fix verträgt sich nicht mit --update-baseline.
  mBaselinePath := TLinterBaseline.PathOf(FOptions, AConfigRoot);
  Result := TLinterBaseline.Load(FOptions, mBaselinePath, FBaseline);
  if Result then
  begin
    TLinterOutput.Error(cTexts[TLinterFixText.Header].Fmt([string.Join(', ', FOptions.FixRules),
      TBulkFix.ConfidenceText(FFixOptions.MinConfidence)]));
  end;
end;

function TLinterFix.Candidates(const AConfigRoot: string; out ASources: TCheckSourceFunc): TArray<string>;
var
  mTimings: TCheckTimings;
begin
  // Die Sammelkorrektur misst nicht (--timings gilt nur für die Prüfung).
  mTimings := Default(TCheckTimings);
  if not FOptions.NoIndex then
  begin
    FGroup := TLinterIndex.Load(FOptions, AConfigRoot, mTimings);
  end;
  Result := TLinterFiles.Collect(FOptions.CheckTarget, FSettings, FRoot, ASources);
  FPackages := TLinterFiles.Packages(Result);
  FPrograms := TLinterFiles.Programs(Result);
  if FOptions.ChangedRef <> '' then
  begin
    FGit := TLinterChanges.Detect(AConfigRoot, FSettings);
    Result := TLinterChanges.Select(FOptions, Result, FGit);
  end;
end;

function TLinterFix.CheckOf(const AFileName, ARelativePath: string; const ASource: TCheckSource): TLinterFixCheck;
begin
  Result := Default(TLinterFixCheck);
  Result.Rules := FFixRules;
  Result.Settings := FSettings;
  Result.RelativePath := ARelativePath;
  Result.FileName := AFileName;
  Result.Project := TLinterIndex.ProjectOf(AFileName, FPackages, FPrograms, FGroup);
  Result.Source := ASource;
  Result.Baseline := FBaseline;
  Result.Filter := FFilter;
  Result.Git := FGit;
  Result.ChangedLines := FOptions.ChangedLines;
end;

procedure TLinterFix.FixFile(const AFileName: string; const ASource: TCheckSource);
var
  mRelativePath, mText: string;
  mFormat: TFileFormat;
  mCheck: TLinterFixCheck;
  mRemainingCheck: TBulkFixCheck;
  mResult: TBulkFixFile;
  mChecked: TCheckedFile;
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
  mCheck := CheckOf(AFileName, mRelativePath, ASource);
  mResult := TBulkFix.Run(AFileName, mText, FFixOptions, CheckFunc(mCheck), TBulkFix.SyntaxErrorsWith(mCheck.Source));
  FResults := FResults + [mResult];
  FFormats.AddOrSetValue(AFileName, mFormat);
  FRelative.AddOrSetValue(AFileName, StringReplace(mRelativePath, '\', '/', [rfReplaceAll]));
  // Für den Exit-Code zählen alle Treffer, die nach der Korrektur bleiben.
  mCheck.Rules := FAllRules;
  mChecked := Default(TCheckedFile);
  mChecked.Path := mRelativePath;
  mChecked.FullPath := TPath.GetFullPath(AFileName);
  mRemainingCheck := CheckFunc(mCheck);
  mChecked.Findings := mRemainingCheck(mResult.NewText, mResult.Lines);
  FRemaining := FRemaining + [mChecked];
end;

procedure TLinterFix.Report;
var
  mResult: TBulkFixFile;
  mOutput, mChangedNames: string;
begin
  mOutput := '';
  mChangedNames := '';
  for mResult in FResults do
  begin
    if mResult.Changed then
    begin
      mOutput := mOutput + TBulkFix.Diff(FRelative[mResult.FileName], mResult);
      mChangedNames := mChangedNames + ', ' + FRelative[mResult.FileName];
    end;
  end;
  mChangedNames := Copy(mChangedNames, 3, MaxInt);
  if FOptions.FixDryRun then
  begin
    TLinterOutput.Write(FOptions, mOutput);
  end
  else
  begin
    TBulkFix.WriteAll(FResults, WriterOf(FFormats));
  end;
  TLinterOutput.Error(TBulkFix.Summary(FResults, FOptions.FixDryRun, sLineBreak));
  if (mChangedNames <> '') and FOptions.FixDryRun then
  begin
    TLinterOutput.Error(cTexts[TLinterFixText.Affected].Fmt([mChangedNames]));
  end
  else if mChangedNames <> '' then
  begin
    TLinterOutput.Error(cTexts[TLinterFixText.Changed].Fmt([mChangedNames]));
  end;
end;

function TLinterFix.Execute(const AConfigRoot: string): Integer;
var
  mFileName: string;
  mSources: TCheckSourceFunc;
begin
  if not Prepare(AConfigRoot) then
  begin
    Exit(TFindingsOutput.ExitFailure);
  end;
  for mFileName in Candidates(AConfigRoot, mSources) do
  begin
    FixFile(mFileName, mSources(mFileName));
  end;
  Report;
  Result := TFindingsOutput.ExitCode(FRemaining, FOptions.FailOn);
end;

class function TLinterFix.Run(const AOptions: TCommandLineOptions): Integer;
var
  mTarget: TLinterTarget;
  mFix: TLinterFix;
begin
  TLinterOutput.Warnings(AOptions);
  if AOptions.Metrics or AOptions.Todos or AOptions.SuppressionStats or AOptions.UpdateBaseline then
  begin
    TLinterOutput.Error(cTexts[TLinterFixText.Conflicts].Text);
    Exit(TFindingsOutput.ExitFailure);
  end;
  if not TLinterTarget.Resolve(AOptions.CheckTarget, mTarget) then
  begin
    Exit(TFindingsOutput.ExitFailure);
  end;
  try
    mFix := TLinterFix.Create(AOptions);
    try
      Result := mFix.Execute(mTarget.ConfigRoot);
    finally
      mFix.Free;
    end;
  except
    on E: Exception do
    begin
      TLinterOutput.Error(Format('%s: %s', [E.ClassName, E.Message]));
      Result := TFindingsOutput.ExitFailure;
    end;
  end;
end;

initialization
  TAtlasTextTables.Add('Shell.Linter.Fix', cTexts);

end.
