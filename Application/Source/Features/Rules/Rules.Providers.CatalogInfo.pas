unit Rules.Providers.CatalogInfo;

// Anbieter von IRuleCatalogInfo (Rules.Contract.Api): Kennungen, Kategorie, Gruppe und vorweggenommene
// Compilermeldungen aus dem eingebauten Regelkatalog (TRuleCatalog.Shared), die Hilfeseite einer Regel und welche
// Befunde der Editor durchstreicht (deprecated-symbol mit W1000/W1006, #38, #1018).

interface

uses
  Atlas.Common.Findings.Contract,
  Rules.Contract.Api;

type
  TRuleCatalogInfo = class(TInterfacedObject, IRuleCatalogInfo)
  public
    function RuleIds: TArray<string>;
    function TryDescribe(const ARuleId: string; out AFacts: TRuleCatalogFacts): Boolean;
    function HelpUri(const ARuleId: string): string;
    function StruckThrough(const AFinding: TRuleFinding): Boolean;
  end;

implementation

uses
  Rules.Catalog,
  Rules.Builtin.Deprecated;

function TRuleCatalogInfo.RuleIds: TArray<string>;
var
  mEntry: TRuleCatalogEntry;
begin
  Result := nil;
  for mEntry in TRuleCatalog.Shared.Entries do
  begin
    Result := Result + [mEntry.Id];
  end;
end;

function TRuleCatalogInfo.TryDescribe(const ARuleId: string; out AFacts: TRuleCatalogFacts): Boolean;
var
  mEntry: TRuleCatalogEntry;
begin
  AFacts := Default(TRuleCatalogFacts);
  Result := TRuleCatalog.Shared.TryFind(ARuleId, mEntry);
  if Result then
  begin
    AFacts.Category := TRuleCatalog.CategoryName(mEntry.Category);
    AFacts.Group := TRuleCatalog.GroupName(mEntry.Group);
    AFacts.CompilerCodes := Copy(mEntry.CompilerCodes);
  end;
end;

function TRuleCatalogInfo.HelpUri(const ARuleId: string): string;
begin
  Result := TRuleCatalog.HelpUri(ARuleId);
end;

function TRuleCatalogInfo.StruckThrough(const AFinding: TRuleFinding): Boolean;
begin
  Result := (AFinding.RuleId = cDeprecatedSymbolRuleId) and TDeprecatedSymbolRule.IsDeprecation(AFinding.Message);
end;

end.
