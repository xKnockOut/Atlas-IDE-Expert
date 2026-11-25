unit Shell.Composition.LinterRules;

// Verdrahtung der Prüfregeln für den Linter-Modus: TCoreLinterRules (Core.Linter.Host) mit den eingebauten Regeln,
// TFileChecker, dem Regelkatalog und den gespeicherten Abfragen.

interface

uses
  Core.Linter.Host;

type
  TShellLinterRules = record
    /// <summary>Die eingebauten Prüfregeln für --check und --fix.</summary>
    class function Create: TCoreLinterRules; static;
  end;

implementation

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Findings.Contract,
  Atlas.Common.Findings.Scopes,
  Atlas.Common.Checks.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Rules.Catalog,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Builtin.SavedQueries,
  Atlas.Common.Rules.BulkFixRules;

/// <summary>Prüfung mit ARules; eigene Routine, damit die anonyme Methode nur ihren Parameter einfängt.</summary>
function CheckWith(const ARules: TArray<IRule>): TCoreLinterCheckText;
begin
  Result :=
    function(const ASettings: TServerSettings; const ARelativePath, AText: string; const AProject: TCheckProject;
      const ASource: TPascalSource; out AScopes: TFindingScopes): TArray<TRuleFinding>
    begin
      Result := TFileChecker.CheckText(ARules, ASettings, ARelativePath, AText, TCheckOrigin.Make(AProject, ASource),
        AScopes);
    end;
end;

function FixCheckOf(const ARules: TArray<IRule>): TCoreLinterFixCheck;
begin
  Result :=
    function(const AFixRules: TArray<string>): TCoreLinterCheckText
    begin
      Result := CheckWith(TRuleBulkFix.RulesFor(ARules, AFixRules));
    end;
end;

function SafeFixRules: TArray<string>;
begin
  Result := TRuleBulkFix.SafeRulesOf(TRuleCatalog.Shared.Entries);
end;

function InfosOf(const ARules: TArray<IRule>): TCoreLinterRuleInfos;
begin
  Result :=
    function(const ASettings: TServerSettings; AWithIndex: Boolean): TArray<TFindingRuleInfo>
    var
      mDescriptors: TArray<TRuleDescriptor>;
      mRule: IRule;
    begin
      mDescriptors := TArray<TRuleDescriptor>.Create(TFileChecker.SyntaxDescriptor,
        TFileChecker.LanguageFeatureDescriptor);
      for mRule in ARules do
      begin
        mDescriptors := mDescriptors + [mRule.Descriptor];
      end;
      if AWithIndex then
      begin
        for mRule in TSavedQueryRule.RulesOf(ASettings) do
        begin
          mDescriptors := mDescriptors + [mRule.Descriptor];
        end;
      end;
      Result := TRuleCatalog.RuleInfos(mDescriptors);
    end;
end;

{ TShellLinterRules }

class function TShellLinterRules.Create: TCoreLinterRules;
var
  mRules: TArray<IRule>;
begin
  mRules := BuiltinRules;
  Result := Default(TCoreLinterRules);
  Result.CheckAll := CheckWith(mRules);
  Result.FixCheck := FixCheckOf(mRules);
  Result.SafeFixRules := SafeFixRules;
  Result.Infos := InfosOf(mRules);
end;

end.
