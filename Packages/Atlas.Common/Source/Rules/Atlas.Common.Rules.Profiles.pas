unit Atlas.Common.Rules.Profiles;

// Regelprofile und Pfadregeln (#146). Der wirksame Schweregrad einer Regel
// entsteht in dieser Reihenfolge, spätere Stufen haben Vorrang:
//   1. Vorgabe der Regel;
//   2. eingebautes Profil: fast (nur Bugs und Schwachstellen), security
//      (Schwachstellen und Security-Hotspots), style (nur Code-Smells),
//      strict (experimentelle Regeln an), standard (unverändert);
//      experimentell ist eine Regel, deren "profiles" im Regelkatalog
//      standard nicht nennt (#145, IsExperimental);
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
    cMaxDepth = 8;
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
    /// <summary>True, wenn die Regel laut Regelkatalog nicht im Profil standard läuft (#145, #834): Dann meldet sie
    /// nur im Profil strict oder in "rules" eingeschaltet. False für Regeln, die der Katalog nicht kennt
    /// (gespeicherte Abfragen).</summary>
    class function IsExperimental(const ARuleId: string): Boolean; static;
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
  // Werden in initialization gefüllt und danach nur gelesen, daher ohne Sperre.
  Categories: TDictionary<string, string>;
  // Kennungen (klein) der experimentellen Regeln; Wert ohne Bedeutung.
  Experimentals: TDictionary<string, Boolean>;

function Contains(const AItems: TArray<string>; const AText: string): Boolean;
var
  mItem: string;
begin
  for mItem in AItems do
  begin
    if SameText(mItem, AText) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Wendet die Einträge auf den Schweregrad an; ARuleId '*' in AItems trifft jede Regel.</summary>
procedure ApplyRules(const AItems: TArray<TRuleSetting>; const ARuleId: string; var ASeverity: TRuleSeverity;
  var AEnabled: Boolean; AWildcard: Boolean);
var
  mRule: TRuleSetting;
begin
  for mRule in AItems do
  begin
    if (SameText(mRule.Id, ARuleId) or (AWildcard and (mRule.Id = '*'))) and
      (mRule.Severity <> TRuleSeverity.Default) then
    begin
      ASeverity := mRule.Severity;
      AEnabled := mRule.Severity <> TRuleSeverity.Off;
    end;
  end;
end;

procedure ApplyCategories(const ACategories: TArray<string>; const ACategory: string; var ASeverity: TRuleSeverity);
begin
  if (Length(ACategories) > 0) and (ACategory <> '') and not Contains(ACategories, ACategory) then
  begin
    ASeverity := TRuleSeverity.Off;
  end;
end;

procedure ApplyBuiltin(const AName, ACategory: string; var ASeverity: TRuleSeverity; var AEnabled: Boolean);
begin
  if SameText(AName, 'fast') then
  begin
    ApplyCategories(['bug', 'vulnerability'], ACategory, ASeverity);
  end
  else if SameText(AName, 'security') then
  begin
    ApplyCategories(['vulnerability', 'security-hotspot'], ACategory, ASeverity);
  end
  else if SameText(AName, 'style') then
  begin
    ApplyCategories(['code-smell'], ACategory, ASeverity);
  end
  else if SameText(AName, 'strict') then
  begin
    AEnabled := True;
  end;
end;

{ TRuleProfiles }

class function TRuleProfiles.Severity(const ASettings: TServerSettings; const AProfile: string;
  const ADescriptor: TRuleDescriptor; const ACategory, ARelativePath: string; out AEnabled: Boolean): TRuleSeverity;
var
  mChain: TArray<TRuleProfile>;
  mProfile: TRuleProfile;
  mName: string;
  mIndex: Integer;
  mItem: TPathOverride;
  mPattern: string;
begin
  Result := ADescriptor.DefaultSeverity;
  AEnabled := False;
  // Kette eigener Profile bis zum eingebauten Grundprofil.
  mChain := nil;
  mName := AProfile;
  while (mName <> '') and (Length(mChain) < cMaxDepth) and ASettings.TryFindProfile(mName, mProfile) do
  begin
    mChain := [mProfile] + mChain;
    mName := mProfile.Extends;
  end;
  ApplyBuiltin(mName, ACategory, Result, AEnabled);
  for mIndex := 0 to High(mChain) do
  begin
    ApplyCategories(mChain[mIndex].Categories, ACategory, Result);
    ApplyRules(mChain[mIndex].Rules, ADescriptor.Id, Result, AEnabled, False);
  end;
  ApplyRules(ASettings.Rules, ADescriptor.Id, Result, AEnabled, False);
  if ARelativePath <> '' then
  begin
    for mItem in ASettings.Overrides do
    begin
      for mPattern in mItem.Files do
      begin
        if MatchesGlob(mPattern, ARelativePath) then
        begin
          ApplyRules(mItem.Rules, ADescriptor.Id, Result, AEnabled, True);
          Break;
        end;
      end;
    end;
  end;
end;

class function TRuleProfiles.BaseProfile(const ASettings: TServerSettings; const AProfile: string): string;
var
  mProfile: TRuleProfile;
  mDepth: Integer;
begin
  Result := AProfile;
  mDepth := 0;
  while (Result <> '') and (mDepth < cMaxDepth) and ASettings.TryFindProfile(Result, mProfile) do
  begin
    Result := mProfile.Extends;
    Inc(mDepth);
  end;
end;

class function TRuleProfiles.MinConfidence(const ASettings: TServerSettings; const AProfile: string): TRuleConfidence;
begin
  if not ASettings.MinConfidenceGiven and SameText(BaseProfile(ASettings, AProfile), 'strict') then
  begin
    Result := TRuleConfidence.Low;
  end
  else
  begin
    Result := ASettings.MinConfidence;
  end;
end;

class function TRuleProfiles.CategoryOf(const ARuleId: string): string;
begin
  if (Categories = nil) or not Categories.TryGetValue(LowerCase(ARuleId), Result) then
  begin
    Result := '';
  end;
end;

class function TRuleProfiles.IsExperimental(const ARuleId: string): Boolean;
begin
  Result := (Experimentals <> nil) and Experimentals.ContainsKey(LowerCase(ARuleId));
end;

class function TRuleProfiles.KnownRuleIds: TArray<string>;
var
  mPair: TPair<string, string>;
  mIndex: Integer;
begin
  Result := nil;
  if Categories = nil then
  begin
    Exit;
  end;
  // Ohne Categories.Keys: Die Sammlung entstünde beim ersten Zugriff und bliebe bis Programmende.
  SetLength(Result, Categories.Count);
  mIndex := 0;
  for mPair in Categories do
  begin
    Result[mIndex] := mPair.Key;
    Inc(mIndex);
  end;
  TArray.Sort<string>(Result);
end;

class function TRuleProfiles.IsTestUnit(const ATokens: TArray<TPascalToken>): Boolean;
begin
  Result := TUsesClauses.IsTestUnit(ATokens);
end;

procedure LoadCategories;
var
  mCatalog: TRuleCatalog;
  mEntry: TRuleCatalogEntry;
begin
  Categories := TDictionary<string, string>.Create;
  Experimentals := TDictionary<string, Boolean>.Create;
  try
    mCatalog := TRuleCatalog.Create(RuleCatalogBaseJson);
    try
      for mEntry in mCatalog.Entries do
      begin
        Categories.AddOrSetValue(LowerCase(mEntry.Id), TRuleCatalog.CategoryName(mEntry.Category));
        if mEntry.Experimental then
        begin
          Experimentals.AddOrSetValue(LowerCase(mEntry.Id), True);
        end;
      end;
    finally
      mCatalog.Free;
    end;
  except
    // Ohne Katalog wirken Profile nur über "rules"; die Kategorie bleibt dann unbekannt.
    on ERuleCatalog do
    begin
      Categories.Clear;
      Experimentals.Clear;
    end;
  end;
end;

initialization
  LoadCategories;

finalization
  FreeAndNil(Experimentals);
  FreeAndNil(Categories);

end.
