unit Atlas.Common.Rules.Providers.RuleDocs;

// Anbieter von IRuleDocs (Atlas.Common.Rules.Contract.Api): die Regeln des eingebauten Katalogs als reine Werte in
// der erfragten Sprache und ihr wirksamer Schweregrad unter den Einstellungen eines Projekts mit Herkunft (Angabe
// unter "rules", abgeschaltete Gruppe, abgeschaltete Kennzahlen, Profil).

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Findings.Contract,
  Atlas.Common.Rules.Contract.Api;

type
  TRuleDocsProvider = class(TInterfacedObject, IRuleDocs)
  public
    function Rules(const ALanguage: string): TArray<TFindingRuleInfo>;
    function State(const ARuleId: string; const ASettings: TServerSettings): TFindingRuleState;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Catalog,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Rules.Profiles;

{ TRuleDocsProvider }

function TRuleDocsProvider.Rules(const ALanguage: string): TArray<TFindingRuleInfo>;
var
  mLanguage: TTextLanguage;
  mEntries: TArray<TRuleCatalogEntry>;
  mIndex: Integer;
begin
  if not TAtlasLocale.TryParse(ALanguage, mLanguage) then
  begin
    mLanguage := TTextLanguage.English;
  end;
  mEntries := TRuleCatalog.InLanguage(mLanguage).Entries;
  Result := nil;
  SetLength(Result, Length(mEntries));
  for mIndex := 0 to High(mEntries) do
  begin
    Result[mIndex] := TRuleCatalog.InfoOf(mEntries[mIndex]);
  end;
end;

function TRuleDocsProvider.State(const ARuleId: string; const ASettings: TServerSettings): TFindingRuleState;
var
  mEntry: TRuleCatalogEntry;
  mEnabled: Boolean;
begin
  Result := Default(TFindingRuleState);
  if not TRuleCatalog.Shared.TryFind(ARuleId, mEntry) then
  begin
    mEntry := Default(TRuleCatalogEntry);
    mEntry.Id := ARuleId;
  end;
  Result.Severity := TRuleEngine.EffectiveSeverity(TRuleDescriptor.Create(mEntry.Id, mEntry.DefaultSeverity,
    mEntry.Description), ASettings, '', mEnabled);
  if not mEnabled and TRuleProfiles.IsExperimental(ARuleId) then
  begin
    Result.Severity := TRuleSeverity.Off;
  end;
  if ASettings.RuleSeverity(ARuleId, TRuleSeverity.Default) <> TRuleSeverity.Default then
  begin
    Result.Origin := TFindingRuleOrigin.Rules;
  end
  else if TRuleEngine.GroupOff(ARuleId, ASettings) then
  begin
    Result.Origin := TFindingRuleOrigin.Group;
    Result.Detail := TRuleCatalog.GroupKey(mEntry.Group);
  end
  else if not ASettings.Metrics and StartsText('metric-', ARuleId) then
  begin
    Result.Origin := TFindingRuleOrigin.Metrics;
  end
  else
  begin
    Result.Origin := TFindingRuleOrigin.Profile;
    Result.Detail := ASettings.Profile;
    if Result.Detail = '' then
    begin
      Result.Detail := 'standard';
    end;
  end;
  Result.ProjectOptions := TRuleEngine.RuleOptions(ARuleId, ASettings);
end;

end.
