unit Atlas.Common.Rules.Providers.BulkFix;

// Anbieter von IRuleBulkFix und IRuleWorkspaceBulkFix (Atlas.Common.Rules.Contract.Api): TBulkFix je Datei.
// IRuleBulkFix (fix_findings): Regeln, Projekte und Symbole gibt der Host beim Anlegen mit, die Prüfung je Durchgang
// läuft ohne Baseline. IRuleWorkspaceBulkFix (atlas.server.fixFindings): Text, Regeln, Einstellungen, Projekt und
// Baseline je Datei aus dem Umfeld der Prüfung (TRuleContextProvider) wie im Editor.

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Rules.CheckContext,
  Atlas.Common.Rules.Contract.Api;

type
  /// <summary>ARules im Konstruktor von TBoundRuleProvider: alle Regeln.</summary>
  TRuleBulkFixProvider = class(TBoundRuleProvider, IRuleBulkFix, IRuleWorkspaceBulkFix)
  private
    FContexts: TRuleContextProvider;
    FRead: TDocumentReadText;
    function IRuleWorkspaceBulkFix.Run = RunFiles;
  public
    /// <summary>Für IRuleWorkspaceBulkFix: AContexts gibt das Umfeld je Datei (URI), ARead den Text (Editor vor
    /// Platte), ASource die Symbole (nil = Vordefinitionen).</summary>
    constructor CreateForWorkspace(const AContexts: TRuleContextProvider; const ARead: TDocumentReadText;
      const ASource: TCheckSourceFunc);
    function Run(const AFiles: TArray<TRuleBulkFixInput>; const AFixRules: TArray<string>;
      const AMinConfidence: string; const ASettings: TServerSettings; out ARun: TRuleBulkFixRun;
      out AError: string): Boolean;
    function RunFiles(const AFileNames: TArray<string>; const AFixRules: TArray<string>;
      const AMinConfidence: string; out ARun: TRuleBulkFixRun; out AError: string): Boolean;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.BulkFix,
  Atlas.Common.Rules.Catalog,
  Atlas.Common.Checks.Contract;

/// <summary>Ergebnis einer Datei für die API; Diff mit ADiffPath.</summary>
function OutputOf(const AResult: TBulkFixFile; const ADiffPath: string): TRuleBulkFixOutput;
var
  mIndex: Integer;
begin
  Result := Default(TRuleBulkFixOutput);
  Result.FileName := AResult.FileName;
  Result.OldText := AResult.OldText;
  Result.NewText := AResult.NewText;
  Result.Changed := AResult.Changed;
  Result.Rejected := AResult.Rejected;
  Result.FixCount := AResult.FixCount;
  SetLength(Result.Applied, Length(AResult.Applied));
  for mIndex := 0 to High(AResult.Applied) do
  begin
    Result.Applied[mIndex].RuleId := AResult.Applied[mIndex].RuleId;
    Result.Applied[mIndex].Count := AResult.Applied[mIndex].Count;
  end;
  Result.Diff := TBulkFix.Diff(StringReplace(ADiffPath, '\', '/', [rfReplaceAll]), AResult);
end;

/// <summary>Projekt der Datei AFileName aus dem Umfeld der Prüfung.</summary>
function ProjectOf(const AContext: TRuleCheckContext; const AFileName: string): TCheckProject;
begin
  Result := Default(TCheckProject);
  Result.Application := AContext.Application;
  Result.Name := AContext.ProjectName;
  Result.AutoCreateForms := AContext.AutoCreateForms;
  Result.ProjectMainSource := AContext.ProjectMainSource;
  Result.FileName := AFileName;
  Result.Services := AContext.Services;
end;

{ TRuleBulkFixProvider }

function TRuleBulkFixProvider.Run(const AFiles: TArray<TRuleBulkFixInput>; const AFixRules: TArray<string>;
  const AMinConfidence: string; const ASettings: TServerSettings; out ARun: TRuleBulkFixRun;
  out AError: string): Boolean;
var
  mConfidence: TRuleConfidence;
  mOptions: TBulkFixOptions;
  mRules: TArray<IRule>;
  mResults: TArray<TBulkFixFile>;
  mSource: TCheckSource;
  mIndex: Integer;
begin
  ARun := Default(TRuleBulkFixRun);
  Result := TBulkFix.MinConfidenceOf(ASettings.FixMinConfidence, AMinConfidence, mConfidence, AError);
  if not Result then
  begin
    Exit;
  end;
  mOptions := TBulkFixOptions.Create(AFixRules, mConfidence, TRuleCatalog.Shared.Entries);
  mRules := TBulkFix.RulesFor(FRules, AFixRules);
  mResults := nil;
  SetLength(mResults, Length(AFiles));
  SetLength(ARun.Files, Length(AFiles));
  for mIndex := 0 to High(AFiles) do
  begin
    mSource := TFileChecker.SourceOf(FSource, AFiles[mIndex].FileName);
    mResults[mIndex] := TBulkFix.Run(AFiles[mIndex].FileName, AFiles[mIndex].Text, mOptions,
      TBulkFix.CheckWith(mRules, ASettings, AFiles[mIndex].RelativePath,
      TFileChecker.ProjectOf(FProject, AFiles[mIndex].FileName), mSource), TBulkFix.SyntaxErrorsWith(mSource));
    ARun.Files[mIndex] := OutputOf(mResults[mIndex], AFiles[mIndex].RelativePath);
  end;
  ARun.PreviewSummary := TBulkFix.Summary(mResults, True, sLineBreak);
  ARun.WrittenSummary := TBulkFix.Summary(mResults, False, sLineBreak);
end;

constructor TRuleBulkFixProvider.CreateForWorkspace(const AContexts: TRuleContextProvider;
  const ARead: TDocumentReadText; const ASource: TCheckSourceFunc);
begin
  inherited Create(nil, nil, ASource);
  FContexts := AContexts;
  FRead := ARead;
end;

function TRuleBulkFixProvider.RunFiles(const AFileNames: TArray<string>; const AFixRules: TArray<string>;
  const AMinConfidence: string; out ARun: TRuleBulkFixRun; out AError: string): Boolean;
var
  mFileName, mText, mRelativePath: string;
  mContext: TRuleCheckContext;
  mConfidence: TRuleConfidence;
  mSource: TCheckSource;
  mResult: TBulkFixFile;
  mResults: TArray<TBulkFixFile>;
begin
  ARun := Default(TRuleBulkFixRun);
  AError := '';
  mResults := nil;
  for mFileName in AFileNames do
  begin
    if not (Assigned(FRead) and FRead(mFileName, mText) and
      TRuleContexts.Lookup(FContexts, TDocumentUris.FromPath(mFileName), mContext)) then
    begin
      Continue;
    end;
    if not TBulkFix.MinConfidenceOf(mContext.Settings.FixMinConfidence, AMinConfidence, mConfidence, AError) then
    begin
      ARun := Default(TRuleBulkFixRun);
      Exit(False);
    end;
    mRelativePath := mContext.RelativePath;
    if mRelativePath = '' then
    begin
      mRelativePath := ExtractFileName(mFileName);
    end;
    mSource := TFileChecker.SourceOf(FSource, mFileName);
    mResult := TBulkFix.Run(mFileName, mText, TBulkFixOptions.Create(AFixRules, mConfidence,
      TRuleCatalog.Shared.Entries), TBulkFix.CheckWith(TBulkFix.RulesFor(mContext.Rules, AFixRules),
      mContext.Settings, mRelativePath, ProjectOf(mContext, mFileName), mSource, mContext.Baseline),
      TBulkFix.SyntaxErrorsWith(mSource));
    mResults := mResults + [mResult];
    ARun.Files := ARun.Files + [OutputOf(mResult, mRelativePath)];
  end;
  ARun.PreviewSummary := TBulkFix.Summary(mResults, True, sLineBreak);
  ARun.WrittenSummary := TBulkFix.Summary(mResults, False, sLineBreak);
  Result := True;
end;

end.
