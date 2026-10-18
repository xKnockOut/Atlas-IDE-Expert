unit Atlas.Common.Rules.Profiles;

// Regelprofile und Pfadregeln (#146). Der wirksame Schweregrad einer Regel
// entsteht in dieser Reihenfolge, spätere Stufen haben Vorrang:
//   1. Vorgabe der Regel;
//   2. eingebautes Profil: fast (nur Bugs und Schwachstellen), security
//      (Schwachstellen und Security-Hotspots), style (nur Code-Smells),
//      strict (experimentelle Regeln an), standard (unverändert);
//   3. eigene Profile aus "profiles", vom Grundprofil nach außen;
//   4. "rules" der Konfiguration;
//   5. "overrides", deren Muster den Pfad treffen ("*" = alle Regeln).
// Die Mindestkonfidenz ist low bei strict, sonst medium; ein ausdrückliches
// "minConfidence" geht vor.
// Test-Units und Testprojekte (.dpr mit uses DUnitX.TestFramework,
// TestFramework oder TestInsight.*) erkennt IsTestUnit; mit "excludeTests"
// prüft die Engine sie nicht, mit "testProfile" unter eigenem Profil.

interface

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Rules.Contract;

type
  TRuleProfiles = class
  public const
    /// <summary>Höchstzahl verketteter eigener Profile, schützt vor Zyklen.</summary>
    MaxDepth = 8;
  public
    /// <summary>Wirksamer Schweregrad der Regel für ARelativePath unter AProfile.
    /// ACategory ist der Katalogname (bug, code-smell, …), '' wenn unbekannt.
    /// AEnabled sagt, ob eine experimentelle Regel ausdrücklich eingeschaltet ist.</summary>
    class function Severity(const ASettings: TServerSettings; const AProfile: string;
      const ADescriptor: TRuleDescriptor; const ACategory, ARelativePath: string;
      out AEnabled: Boolean): TRuleSeverity; static;
    /// <summary>Eingebautes Profil am Ende der Kette eigener Profile, '' = standard.</summary>
    class function BaseProfile(const ASettings: TServerSettings; const AProfile: string): string; static;
    /// <summary>Mindestkonfidenz unter AProfile.</summary>
    class function MinConfidence(const ASettings: TServerSettings; const AProfile: string): TRuleConfidence; static;
    /// <summary>Kategorie aus dem Regelkatalog, '' wenn die Regel dort fehlt.</summary>
    class function CategoryOf(const ARuleId: string): string; static;
    /// <summary>Alle Regelkennungen des Katalogs in Kleinbuchstaben, sortiert (#41: unknown-rule-id).</summary>
    class function KnownRuleIds: TArray<string>; static;
    /// <summary>True, wenn die Unit ein Test-Framework einbindet; Weiterleitung an TUsesClauses.IsTestUnit.</summary>
    class function IsTestUnit(const ATokens: TArray<TPascalToken>): Boolean; static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Rules.Catalog,
  Atlas.Common.Rules.Catalog.Data;

var
  // Wird in initialization gefüllt und danach nur gelesen, daher ohne Sperre.
  Categories: TDictionary<string, string>;

function Contains(const AItems: TArray<string>; const AText: string): Boolean;
var
  Item: string;
begin
  for Item in AItems do
    if SameText(Item, AText) then
      Exit(True);
  Result := False;
end;

/// <summary>Wendet die Einträge auf den Schweregrad an; ARuleId '*' in AItems trifft jede Regel.</summary>
procedure ApplyRules(const AItems: TArray<TRuleSetting>; const ARuleId: string; var ASeverity: TRuleSeverity;
  var AEnabled: Boolean; AWildcard: Boolean);
var
  Rule: TRuleSetting;
begin
  for Rule in AItems do
    if (SameText(Rule.Id, ARuleId) or (AWildcard and (Rule.Id = '*'))) and
      (Rule.Severity <> TRuleSeverity.Default) then
    begin
      ASeverity := Rule.Severity;
      AEnabled := Rule.Severity <> TRuleSeverity.Off;
    end;
end;

procedure ApplyCategories(const ACategories: TArray<string>; const ACategory: string; var ASeverity: TRuleSeverity);
begin
  if (Length(ACategories) > 0) and (ACategory <> '') and not Contains(ACategories, ACategory) then
    ASeverity := TRuleSeverity.Off;
end;

procedure ApplyBuiltin(const AName, ACategory: string; var ASeverity: TRuleSeverity; var AEnabled: Boolean);
begin
  if SameText(AName, 'fast') then
    ApplyCategories(['bug', 'vulnerability'], ACategory, ASeverity)
  else if SameText(AName, 'security') then
    ApplyCategories(['vulnerability', 'security-hotspot'], ACategory, ASeverity)
  else if SameText(AName, 'style') then
    ApplyCategories(['code-smell'], ACategory, ASeverity)
  else if SameText(AName, 'strict') then
    AEnabled := True;
end;

{ TRuleProfiles }

class function TRuleProfiles.Severity(const ASettings: TServerSettings; const AProfile: string;
  const ADescriptor: TRuleDescriptor; const ACategory, ARelativePath: string; out AEnabled: Boolean): TRuleSeverity;
var
  Chain: TArray<TRuleProfile>;
  Profile: TRuleProfile;
  Name: string;
  Index: Integer;
  Item: TPathOverride;
  Pattern: string;
begin
  Result := ADescriptor.DefaultSeverity;
  AEnabled := False;
  // Kette eigener Profile bis zum eingebauten Grundprofil.
  Chain := nil;
  Name := AProfile;
  while (Name <> '') and (Length(Chain) < MaxDepth) and ASettings.TryFindProfile(Name, Profile) do
  begin
    Chain := [Profile] + Chain;
    Name := Profile.Extends;
  end;
  ApplyBuiltin(Name, ACategory, Result, AEnabled);
  for Index := 0 to High(Chain) do
  begin
    ApplyCategories(Chain[Index].Categories, ACategory, Result);
    ApplyRules(Chain[Index].Rules, ADescriptor.Id, Result, AEnabled, False);
  end;
  ApplyRules(ASettings.Rules, ADescriptor.Id, Result, AEnabled, False);
  if ARelativePath <> '' then
    for Item in ASettings.Overrides do
      for Pattern in Item.Files do
        if MatchesGlob(Pattern, ARelativePath) then
        begin
          ApplyRules(Item.Rules, ADescriptor.Id, Result, AEnabled, True);
          Break;
        end;
end;

class function TRuleProfiles.BaseProfile(const ASettings: TServerSettings; const AProfile: string): string;
var
  Profile: TRuleProfile;
  Depth: Integer;
begin
  Result := AProfile;
  Depth := 0;
  while (Result <> '') and (Depth < MaxDepth) and ASettings.TryFindProfile(Result, Profile) do
  begin
    Result := Profile.Extends;
    Inc(Depth);
  end;
end;

class function TRuleProfiles.MinConfidence(const ASettings: TServerSettings; const AProfile: string): TRuleConfidence;
begin
  if not ASettings.MinConfidenceGiven and SameText(BaseProfile(ASettings, AProfile), 'strict') then
    Result := TRuleConfidence.Low
  else
    Result := ASettings.MinConfidence;
end;

class function TRuleProfiles.CategoryOf(const ARuleId: string): string;
begin
  if (Categories = nil) or not Categories.TryGetValue(LowerCase(ARuleId), Result) then
    Result := '';
end;

class function TRuleProfiles.KnownRuleIds: TArray<string>;
var
  Pair: TPair<string, string>;
  Index: Integer;
begin
  Result := nil;
  if Categories = nil then
    Exit;
  // Ohne Categories.Keys: Die Sammlung entstünde beim ersten Zugriff und bliebe bis Programmende.
  SetLength(Result, Categories.Count);
  Index := 0;
  for Pair in Categories do
  begin
    Result[Index] := Pair.Key;
    Inc(Index);
  end;
  TArray.Sort<string>(Result);
end;

class function TRuleProfiles.IsTestUnit(const ATokens: TArray<TPascalToken>): Boolean;
begin
  Result := TUsesClauses.IsTestUnit(ATokens);
end;

procedure LoadCategories;
var
  Catalog: TRuleCatalog;
  Entry: TRuleCatalogEntry;
begin
  Categories := TDictionary<string, string>.Create;
  try
    Catalog := TRuleCatalog.Create(RuleCatalogBaseJson);
    try
      for Entry in Catalog.Entries do
        Categories.AddOrSetValue(LowerCase(Entry.Id), TRuleCatalog.CategoryName(Entry.Category));
    finally
      Catalog.Free;
    end;
  except
    // Ohne Katalog wirken Profile nur über "rules"; die Kategorie bleibt dann unbekannt.
    on ERuleCatalog do
      Categories.Clear;
  end;
end;

initialization
  LoadCategories;

finalization
  FreeAndNil(Categories);

end.
