unit Atlas.Common.Rules.Providers.BulkFix;

// Anbieter von IRuleBulkFix (Atlas.Common.Rules.Contract.Api): TBulkFix je Datei mit den Regeln, Projekten und
// Symbolen, die der Host beim Anlegen mitgibt. Die Prüfung je Durchgang läuft ohne Baseline wie bisher bei
// fix_findings.

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Rules.Contract.Api;

type
  /// <summary>ARules im Konstruktor von TBoundRuleProvider: alle Regeln.</summary>
  TRuleBulkFixProvider = class(TBoundRuleProvider, IRuleBulkFix)
  public
    function Run(const AFiles: TArray<TRuleBulkFixInput>; const AFixRules: TArray<string>;
      const AMinConfidence: string; const ASettings: TServerSettings; out ARun: TRuleBulkFixRun;
      out AError: string): Boolean;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.BulkFix,
  Atlas.Common.Rules.Catalog;

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
    ARun.Files[mIndex].FileName := mResults[mIndex].FileName;
    ARun.Files[mIndex].OldText := mResults[mIndex].OldText;
    ARun.Files[mIndex].NewText := mResults[mIndex].NewText;
    ARun.Files[mIndex].Changed := mResults[mIndex].Changed;
    ARun.Files[mIndex].Diff := TBulkFix.Diff(StringReplace(AFiles[mIndex].RelativePath, '\', '/', [rfReplaceAll]),
      mResults[mIndex]);
  end;
  ARun.PreviewSummary := TBulkFix.Summary(mResults, True, sLineBreak);
  ARun.WrittenSummary := TBulkFix.Summary(mResults, False, sLineBreak);
end;

end.
