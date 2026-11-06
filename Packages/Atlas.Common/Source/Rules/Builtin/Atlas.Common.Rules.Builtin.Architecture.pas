unit Atlas.Common.Rules.Builtin.Architecture;

// Architekturregeln (#183, Code-Review A-12):
//   forbidden-uses                 uses-Eintrag verletzt eine Schichtregel aus atlas.json
//   architecture-role-import       uses-Eintrag verletzt die Rollenmatrix (Konzept 8.1/8.3)
//   architecture-contract-content  Contract-Unit deklariert im interface eine Klasse (Konzept 7.1)
//
// Konfiguration als Option der Regel:
//   "rules": { "forbidden-uses": { "severity": "error", "layers": [
//     { "from": "*.Common.*", "deny": ["Vcl.*", "Winapi.*"], "allow": ["Winapi.Windows"] } ] } }
// "from" trifft den Namen der geprüften Unit, mit "/" stattdessen ihren Pfad
// relativ zur Konfiguration (z. B. "Source/Common/**"). "deny" und "allow"
// sind Globs auf die Namen in uses; "allow" hat Vorrang. Ohne "layers"
// meldet die Regel nichts.
//
// Rollenkonzept (beide architecture-*-Regeln, experimentell, nur mit Optionen aktiv):
//   "rules": { "architecture-role-import": { "severity": "warning",
//     "prefixes": ["Atlas.Common", "Atlas.Windows"],
//     "hostRoles": ["Foundation", "Core", "Shell", "Adapters", "Platform"],
//     "allow": ["Atlas.Common.Rules.Contract -> Atlas.Common.Pascal.SyntaxTree"] } }
// Units heißen Ausgabeartefakt.Feature.Rolle.Sache (Konzept 6.3); "prefixes"
// nennt die Ausgabeartefakte, ohne sie melden die Regeln nichts. Units ohne
// Präfix, deren erstes Segment in "hostRoles" steht, gehören zum Host der
// Anwendung; alle anderen (RTL, VCL, Drittanbieter) prüft die Regel nicht.
// "allow" sind genehmigte Ausnahmen: bei architecture-role-import
// "Quelle -> Ziel" (beide Globs), bei architecture-contract-content
// "Unit.Typ" als Glob. Dieselbe Matrix prüft Tools/Check-PackageDependencies.ps1;
// beide testen gegen Tests/Data/Architecture/role-imports.json.
//
// Grenze: Namen ohne Namespace-Präfix (Forms statt Vcl.Forms) werden so
// verglichen, wie sie im Quelltext stehen.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TArchitectureLayer = record
    From: string;
    Deny: TArray<string>;
    Allow: TArray<string>;
  end;

  TForbiddenUsesRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Schichten aus den Optionen der Regel; ungültige Einträge werden übergangen.</summary>
    class function ParseLayers(const AOptions: string): TArray<TArchitectureLayer>; static;
    /// <summary>Die Schicht, die AUsedUnit für die geprüfte Datei verbietet; False, wenn erlaubt.</summary>
    class function Violates(const ALayers: TArray<TArchitectureLayer>; const AUnitName, ARelativePath,
      AUsedUnit: string; out ALayer: TArchitectureLayer): Boolean; static;
  end;

  {$SCOPEDENUMS ON}
  /// <summary>Rolle einer Unit nach Konzept 6.3; Host = Unit der Anwendung ohne Präfix, None = extern.</summary>
  TArchitectureRole = (None, Contract, Internals, Providers, Adapters, Root, Composition, Hosting, Host);
  {$SCOPEDENUMS OFF}
  TArchitectureRoles = set of TArchitectureRole;

  /// <summary>Einordnung eines Unit-Namens.</summary>
  TArchitectureUnit = record
    /// <summary>Präfix des Ausgabeartefakts, z. B. "Atlas.Common"; '' beim Host.</summary>
    Artefact: string;
    /// <summary>Feature, z. B. "Logging"; beim Host die Host-Rolle, z. B. "Shell".</summary>
    Feature: string;
    Role: TArchitectureRole;
    /// <summary>Role &lt;&gt; None.</summary>
    function Known: Boolean;
    /// <summary>Gleiches Ausgabeartefakt und gleiches Feature (ohne Groß-/Kleinschreibung).</summary>
    function SameFeature(const AOther: TArchitectureUnit): Boolean;
  end;

  /// <summary>Importmatrix des Rollenkonzepts (Konzept 8.1/8.3, docs/Architektur.md "Importregeln").</summary>
  TArchitectureMatrix = class
  private
    class function LongestPrefix(const AUnitName: string; const APrefixes: TArray<string>): string; static;
    class function FeatureRole(const ARoleName: string): TArchitectureRole; static;
    class function ClassifyFeature(const AUnitName, APrefix: string): TArchitectureUnit; static;
    class function ClassifyHost(const AUnitName: string; const AHostRoles: TArray<string>): TArchitectureUnit;
      static;
  public
    /// <summary>Ordnet AUnitName ein; Role = None für externe Units.</summary>
    class function Classify(const AUnitName: string; const APrefixes, AHostRoles: TArray<string>):
      TArchitectureUnit; static;
    /// <summary>True, wenn ASource ATarget importieren darf; unbekannte Units sind immer erlaubt.</summary>
    class function Allowed(const ASource, ATarget: TArchitectureUnit): Boolean; static;
    /// <summary>Kurztext für die Meldung, z. B. "fremde Adapters aus Root".</summary>
    class function Describe(const ASource, ATarget: TArchitectureUnit): string; static;
    /// <summary>Vorgabe für "hostRoles": Foundation, Core, Shell, Adapters, Platform.</summary>
    class function DefaultHostRoles: TArray<string>; static;
  end;

  /// <summary>Optionen beider architecture-*-Regeln.</summary>
  TRoleImportOptions = record
    Prefixes: TArray<string>;
    HostRoles: TArray<string>;
    /// <summary>Genehmigte Ausnahmen; Form je Regel siehe Kopfkommentar.</summary>
    Allow: TArray<string>;
  end;

  TRoleImportRule = class(TInterfacedObject, IRule)
  public const
    RuleId = 'architecture-role-import';
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Optionen der Regel; ohne "hostRoles" gilt TArchitectureMatrix.DefaultHostRoles.</summary>
    class function ParseOptions(const AOptions: string): TRoleImportOptions; static;
    /// <summary>True, wenn "Quelle -> Ziel" einen allow-Eintrag trifft.</summary>
    class function Approved(const AAllow: TArray<string>; const ASource, ATarget: string): Boolean; static;
  end;

  TContractContentRule = class(TInterfacedObject, IRule)
  public const
    RuleId = 'architecture-contract-content';
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterArchitectureRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.Generics.Collections,
  System.JSON,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TArchitectureText = (LayerTitle, LayerViolation, Describe, RoleTitle, RoleViolation, ContractTitle, ContractClass,
    Foreign, Own);

const
  cTexts: array[TArchitectureText] of TAtlasText = (
    (De: 'uses-Eintrag verletzt eine Schichtregel aus atlas.json';
     En: 'uses entry violates a layer rule from atlas.json'),
    (De: '%s darf %s nicht verwenden (Schicht "%s")'; En: '%s must not use %s (layer "%s")'),
    (De: '%s %s aus %s'; En: '%s %s from %s'),
    (De: 'uses-Eintrag verletzt die Rollenmatrix (Konzept 8.1/8.3)';
     En: 'uses entry violates the role matrix (concept 8.1/8.3)'),
    (De: '%s darf %s nicht importieren (%s)'; En: '%s must not import %s (%s)'),
    (De: 'Contract-Unit deklariert eine Klasse'; En: 'Contract unit declares a class'),
    (De: '%s ist eine Klasse in einer Contract-Unit; Contract enthält nur Records, Interfaces, Aufzählungen und ' +
      'Ausnahmen (Konzept 7.1)';
     En: '%s is a class in a contract unit; a contract contains only records, interfaces, enumerations and ' +
      'exceptions (concept 7.1)'),
    (De: 'fremde'; En: 'foreign'),
    (De: 'eigene'; En: 'own'));

{$SCOPEDENUMS OFF}

const
  RoleNames: array[TArchitectureRole] of string =
    ('', 'Contract', 'Internals', 'Providers', 'Adapters', 'Root', 'Composition', 'Hosting', 'Host');
  FeatureRoles = [TArchitectureRole.Contract, TArchitectureRole.Internals, TArchitectureRole.Providers,
    TArchitectureRole.Adapters, TArchitectureRole.Composition, TArchitectureRole.Hosting];
  // Konzept 8.3: eigenes Feature, Rolle der Quelle -> erlaubte Rollen des Ziels.
  // Muss $OwnAllowed in Tools/Check-PackageDependencies.ps1 entsprechen.
  OwnAllowed: array[TArchitectureRole] of TArchitectureRoles = (
    [],
    [TArchitectureRole.Contract],
    [TArchitectureRole.Contract, TArchitectureRole.Internals],
    [TArchitectureRole.Contract, TArchitectureRole.Internals, TArchitectureRole.Root],
    [TArchitectureRole.Contract, TArchitectureRole.Internals, TArchitectureRole.Root],
    [TArchitectureRole.Contract, TArchitectureRole.Internals, TArchitectureRole.Root],
    [TArchitectureRole.Contract, TArchitectureRole.Providers, TArchitectureRole.Adapters,
     TArchitectureRole.Root, TArchitectureRole.Composition],
    [TArchitectureRole.Contract, TArchitectureRole.Providers, TArchitectureRole.Adapters,
     TArchitectureRole.Root, TArchitectureRole.Composition, TArchitectureRole.Hosting],
    []);
  // Fremdes Feature. Host (8.1, Annahme bis zur Bestätigung des Konzepts): alles außer Internals.
  ForeignAllowed: array[TArchitectureRole] of TArchitectureRoles = (
    [],
    [TArchitectureRole.Contract],
    [TArchitectureRole.Contract, TArchitectureRole.Root],
    [TArchitectureRole.Contract, TArchitectureRole.Root],
    [TArchitectureRole.Contract, TArchitectureRole.Root],
    [TArchitectureRole.Contract, TArchitectureRole.Root],
    [TArchitectureRole.Contract, TArchitectureRole.Root],
    [TArchitectureRole.Contract, TArchitectureRole.Root],
    [TArchitectureRole.Contract, TArchitectureRole.Root, TArchitectureRole.Providers,
     TArchitectureRole.Adapters, TArchitectureRole.Composition, TArchitectureRole.Hosting]);

function ReadStrings(const AObject: TJSONObject; const AName: string): TArray<string>;
var
  List: TJSONArray;
  Item: TJSONValue;
begin
  Result := nil;
  if not AObject.TryGetValue<TJSONArray>(AName, List) then
  begin
    Exit;
  end;
  for Item in List do
  begin
    if Item is TJSONString then
    begin
      Result := Result + [Item.Value];
    end;
  end;
end;

function MatchesAny(const APatterns: TArray<string>; const AName: string): Boolean;
var
  Pattern: string;
begin
  for Pattern in APatterns do
  begin
    if MatchesGlob(Pattern, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TForbiddenUsesRule }

function TForbiddenUsesRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('forbidden-uses', TRuleSeverity.Error,
    cTexts[TArchitectureText.LayerTitle].Text);
end;

class function TForbiddenUsesRule.ParseLayers(const AOptions: string): TArray<TArchitectureLayer>;
var
  Value: TJSONValue;
  List: TJSONArray;
  Item: TJSONValue;
  Layer: TArchitectureLayer;
begin
  Result := nil;
  if Trim(AOptions) = '' then
  begin
    Exit;
  end;
  Value := TJSONObject.ParseJSONValue(AOptions);
  try
    if not ((Value is TJSONObject) and TJSONObject(Value).TryGetValue<TJSONArray>('layers', List)) then
    begin
      Exit;
    end;
    for Item in List do
    begin
      if not ((Item is TJSONObject) and TJSONObject(Item).TryGetValue<string>('from', Layer.From)) or
        (Trim(Layer.From) = '') then
      begin
        Continue;
      end;
      Layer.Deny := ReadStrings(TJSONObject(Item), 'deny');
      Layer.Allow := ReadStrings(TJSONObject(Item), 'allow');
      if Layer.Deny <> nil then
      begin
        Result := Result + [Layer];
      end;
    end;
  finally
    Value.Free;
  end;
end;

class function TForbiddenUsesRule.Violates(const ALayers: TArray<TArchitectureLayer>; const AUnitName,
  ARelativePath, AUsedUnit: string; out ALayer: TArchitectureLayer): Boolean;
var
  Layer: TArchitectureLayer;
  Subject: string;
begin
  for Layer in ALayers do
  begin
    if Pos('/', Layer.From) > 0 then
    begin
      Subject := StringReplace(ARelativePath, '\', '/', [rfReplaceAll]);
    end
    else
    begin
      Subject := AUnitName;
    end;
    if (Subject = '') or not MatchesGlob(Layer.From, Subject) then
    begin
      Continue;
    end;
    if MatchesAny(Layer.Deny, AUsedUnit) and not MatchesAny(Layer.Allow, AUsedUnit) then
    begin
      ALayer := Layer;
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TForbiddenUsesRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Layers: TArray<TArchitectureLayer>;
  Layer: TArchitectureLayer;
  Used: TUsesReference;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  Layers := ParseLayers(AContext.Options);
  if Layers = nil then
  begin
    Exit;
  end;
  for Used in TUsesClauses.References(AContext.Tree.Tokens) do
  begin
    if Violates(Layers, AContext.UnitName, AContext.RelativePath, Used.Name, Layer) then
    begin
      AReport.Add(Used.Range, cTexts[TArchitectureText.LayerViolation].Fmt([AContext.UnitName, Used.Name, Layer.From]));
    end;
  end;
end;

{ TArchitectureUnit }

function TArchitectureUnit.Known: Boolean;
begin
  Result := Role <> TArchitectureRole.None;
end;

function TArchitectureUnit.SameFeature(const AOther: TArchitectureUnit): Boolean;
begin
  Result := SameText(Artefact, AOther.Artefact) and SameText(Feature, AOther.Feature);
end;

{ TArchitectureMatrix }

class function TArchitectureMatrix.DefaultHostRoles: TArray<string>;
begin
  Result := ['Foundation', 'Core', 'Shell', 'Adapters', 'Platform'];
end;

class function TArchitectureMatrix.LongestPrefix(const AUnitName: string;
  const APrefixes: TArray<string>): string;
var
  mPrefix: string;
begin
  Result := '';
  for mPrefix in APrefixes do
  begin
    if (mPrefix <> '') and (Length(mPrefix) > Length(Result)) and StartsText(mPrefix + '.', AUnitName) then
    begin
      Result := mPrefix;
    end;
  end;
end;

class function TArchitectureMatrix.FeatureRole(const ARoleName: string): TArchitectureRole;
var
  mRole: TArchitectureRole;
begin
  Result := TArchitectureRole.Root;
  for mRole := Low(TArchitectureRole) to High(TArchitectureRole) do
  begin
    if (mRole in FeatureRoles) and SameText(RoleNames[mRole], ARoleName) then
    begin
      Result := mRole;
    end;
  end;
end;

class function TArchitectureMatrix.ClassifyFeature(const AUnitName, APrefix: string): TArchitectureUnit;
var
  mParts: TArray<string>;
begin
  Result := Default(TArchitectureUnit);
  mParts := Copy(AUnitName, Length(APrefix) + 2, MaxInt).Split(['.']);
  if (Length(mParts) = 0) or (mParts[0] = '') then
  begin
    Exit;
  end;
  Result.Artefact := APrefix;
  Result.Feature := mParts[0];
  Result.Role := TArchitectureRole.Root;
  if Length(mParts) >= 2 then
  begin
    Result.Role := FeatureRole(mParts[1]);
  end;
end;

class function TArchitectureMatrix.ClassifyHost(const AUnitName: string;
  const AHostRoles: TArray<string>): TArchitectureUnit;
var
  mPrefix: string;
  mParts: TArray<string>;
begin
  Result := Default(TArchitectureUnit);
  mParts := AUnitName.Split(['.']);
  if Length(mParts) < 2 then
  begin
    Exit;
  end;
  for mPrefix in AHostRoles do
  begin
    if SameText(mPrefix, mParts[0]) then
    begin
      Result.Feature := mPrefix;
      Result.Role := TArchitectureRole.Host;
      Exit;
    end;
  end;
end;

class function TArchitectureMatrix.Classify(const AUnitName: string; const APrefixes,
  AHostRoles: TArray<string>): TArchitectureUnit;
var
  mBest: string;
begin
  mBest := LongestPrefix(AUnitName, APrefixes);
  if mBest <> '' then
  begin
    Result := ClassifyFeature(AUnitName, mBest);
  end
  else
  begin
    Result := ClassifyHost(AUnitName, AHostRoles);
  end;
end;

class function TArchitectureMatrix.Allowed(const ASource, ATarget: TArchitectureUnit): Boolean;
begin
  if not (ASource.Known and ATarget.Known) then
  begin
    Exit(True);
  end;
  // Platform-Features importieren nie den Host (8.3); Host-Units untereinander frei.
  if ATarget.Role = TArchitectureRole.Host then
  begin
    Exit(ASource.Role = TArchitectureRole.Host);
  end;
  if (ASource.Role <> TArchitectureRole.Host) and ASource.SameFeature(ATarget) then
  begin
    Result := ATarget.Role in OwnAllowed[ASource.Role];
  end
  else
  begin
    Result := ATarget.Role in ForeignAllowed[ASource.Role];
  end;
end;

class function TArchitectureMatrix.Describe(const ASource, ATarget: TArchitectureUnit): string;
var
  Kind: string;
begin
  Kind := cTexts[TArchitectureText.Foreign].Text;
  if (ASource.Role <> TArchitectureRole.Host) and ASource.SameFeature(ATarget) then
  begin
    Kind := cTexts[TArchitectureText.Own].Text;
  end;
  Result := cTexts[TArchitectureText.Describe].Fmt([Kind, RoleNames[ATarget.Role], RoleNames[ASource.Role]]);
end;

{ TRoleImportRule }

function TRoleImportRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('architecture-role-import', TRuleSeverity.Warning,
    cTexts[TArchitectureText.RoleTitle].Text, True);
end;

class function TRoleImportRule.ParseOptions(const AOptions: string): TRoleImportOptions;
var
  Value: TJSONValue;
begin
  Result := Default(TRoleImportOptions);
  Result.HostRoles := TArchitectureMatrix.DefaultHostRoles;
  if Trim(AOptions) = '' then
  begin
    Exit;
  end;
  Value := TJSONObject.ParseJSONValue(AOptions);
  try
    if not (Value is TJSONObject) then
    begin
      Exit;
    end;
    Result.Prefixes := ReadStrings(TJSONObject(Value), 'prefixes');
    Result.Allow := ReadStrings(TJSONObject(Value), 'allow');
    if TJSONObject(Value).GetValue('hostRoles') <> nil then
    begin
      Result.HostRoles := ReadStrings(TJSONObject(Value), 'hostRoles');
    end;
  finally
    Value.Free;
  end;
end;

class function TRoleImportRule.Approved(const AAllow: TArray<string>; const ASource, ATarget: string): Boolean;
var
  Entry: string;
  Separator: Integer;
begin
  for Entry in AAllow do
  begin
    Separator := Pos('->', Entry);
    if Separator = 0 then
    begin
      Continue;
    end;
    if MatchesGlob(Trim(Copy(Entry, 1, Separator - 1)), ASource) and
      MatchesGlob(Trim(Copy(Entry, Separator + 2, MaxInt)), ATarget) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function OwnUnitName(const AContext: TRuleContext): string;
begin
  Result := TUsesClauses.OwnName(AContext.Tree.Tokens);
  if Result = '' then
  begin
    Result := AContext.UnitName;
  end;
end;

procedure TRoleImportRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Options: TRoleImportOptions;
  OwnName: string;
  Source, Target: TArchitectureUnit;
  Used: TUsesReference;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  Options := ParseOptions(AContext.Options);
  // Ohne Präfixe schweigt die Regel: Projekte ohne Rollenkonzept sehen nichts.
  if Options.Prefixes = nil then
  begin
    Exit;
  end;
  // Test-Units tragen den Namen der getesteten Unit (X.Contract.Tests), gehören aber zu keiner Rolle (Konzept:
  // Tests werden nicht geprüft).
  if TUsesClauses.IsTestUnit(AContext.Tree.Tokens) then
  begin
    Exit;
  end;
  OwnName := OwnUnitName(AContext);
  Source := TArchitectureMatrix.Classify(OwnName, Options.Prefixes, Options.HostRoles);
  if not Source.Known then
  begin
    Exit;
  end;
  for Used in TUsesClauses.References(AContext.Tree.Tokens) do
  begin
    // contains eines Packages nimmt Units auf, statt sie einzubinden (#1109): Das Package ist keine Rolle.
    if Used.List = TUsesListKind.ContainsList then
    begin
      Continue;
    end;
    Target := TArchitectureMatrix.Classify(Used.Name, Options.Prefixes, Options.HostRoles);
    if TArchitectureMatrix.Allowed(Source, Target) or Approved(Options.Allow, OwnName, Used.Name) then
    begin
      Continue;
    end;
    AReport.Add(Used.Range, cTexts[TArchitectureText.RoleViolation].Fmt(
      [OwnName, Used.Name, TArchitectureMatrix.Describe(Source, Target)]));
  end;
end;

{ TContractContentRule }

function TContractContentRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('architecture-contract-content', TRuleSeverity.Warning,
    cTexts[TArchitectureText.ContractTitle].Text, True);
end;

function IsExceptionName(const AName: string): Boolean;
var
  Last: string;
begin
  Last := AName;
  if LastDelimiter('.', Last) > 0 then
  begin
    Last := Copy(Last, LastDelimiter('.', Last) + 1, MaxInt);
  end;
  Result := SameText(Last, 'Exception') or
    ((Length(Last) >= 2) and (Last[1] = 'E') and CharInSet(Last[2], ['A'..'Z']));
end;

/// <summary>True, wenn die Unit von AContext eine Contract-Unit ist, die die Regel prüft.</summary>
function IsCheckedContract(const AContext: TRuleContext; const AOptions: TRoleImportOptions;
  const AOwnName: string): Boolean;
begin
  Result := (AOptions.Prefixes <> nil) and not TUsesClauses.IsTestUnit(AContext.Tree.Tokens) and
    (TArchitectureMatrix.Classify(AOwnName, AOptions.Prefixes, AOptions.HostRoles).Role =
    TArchitectureRole.Contract);
end;

/// <summary>True, wenn ATypeDecl eine Klasse ist, die keine Ausnahme ist und kein allow-Eintrag erlaubt.</summary>
function IsForbiddenContractClass(const ATypeDecl: TSyntaxNode; const AAllow: TArray<string>;
  const AOwnName: string): Boolean;
var
  mClassNode, mAncestor: TSyntaxNode;
  mIndex: Integer;
begin
  mClassNode := ATypeDecl.FindChild(TSyntaxKind.ClassType);
  Result := mClassNode <> nil;
  if Result then
  begin
    mAncestor := mClassNode.FindChild(TSyntaxKind.TypeReference);
    Result := (mAncestor = nil) or not IsExceptionName(mAncestor.Name);
  end;
  mIndex := 0;
  while Result and (mIndex <= High(AAllow)) do
  begin
    Result := not MatchesGlob(AAllow[mIndex], AOwnName + '.' + ATypeDecl.Name);
    Inc(mIndex);
  end;
end;

procedure TContractContentRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mOptions: TRoleImportOptions;
  mOwnName: string;
  mInterfaceNode: TSyntaxNode;
  mReport: IRuleReport;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mOptions := TRoleImportRule.ParseOptions(AContext.Options);
  mOwnName := OwnUnitName(AContext);
  mInterfaceNode := AContext.Tree.Root.FindChild(TSyntaxKind.InterfaceSection);
  if (mInterfaceNode = nil) or not IsCheckedContract(AContext, mOptions, mOwnName) then
  begin
    Exit;
  end;
  mReport := AReport;
  // Iterativ (Bericht M1): Konstanten im interface können lange Ausdrücke enthalten.
  mInterfaceNode.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := ANode.Kind <> TSyntaxKind.TypeDecl;
      if not Result and IsForbiddenContractClass(ANode, mOptions.Allow, mOwnName) then
      begin
        mReport.Add(TTextRange.Create(ANode.StartPos.Line, ANode.StartPos.Character, ANode.StartPos.Line,
          ANode.StartPos.Character + Length(ANode.Name)), cTexts[TArchitectureText.ContractClass].Fmt([ANode.Name]));
      end;
    end);
end;

procedure RegisterArchitectureRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TForbiddenUsesRule.Create);
  ARegistry.Register(TRoleImportRule.Create);
  ARegistry.Register(TContractContentRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Architecture', cTexts);

end.
