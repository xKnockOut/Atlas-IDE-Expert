unit Rules.Builtin.Architecture;

// Architekturregeln (#183):
//   forbidden-uses                 uses-Eintrag verletzt eine Schichtregel aus atlas.json
//   architecture-role-import       uses-Eintrag verletzt die Rollenmatrix
//   architecture-contract-content  Contract-Unit deklariert im interface eine Klasse
//   architecture-feature-cycle     Zyklus zwischen Features (Rules.Builtin.FeatureCycles)
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
//     "hostedFeatures": ["Replay"],
//     "allow": ["Atlas.Common.Documents.Contract -> Atlas.Text.Lines"] } }
// Units heißen Ausgabeartefakt.Feature.Rolle.Sache; "prefixes"
// nennt die Ausgabeartefakte, ohne sie melden die Regeln nichts. Die Rolle ist
// der erste Rollenbezeichner an beliebiger Stelle nach dem Feature
// (Feature.Sache.Contract ist ein Contract); ein weiterer eröffnet eine
// Verschachtelung mit dem Fragment davor als Träger. Units ohne
// Präfix, deren erstes Segment in "hostRoles" steht, gehören zum Host der
// Anwendung, die mit einem Namen aus "hostedFeatures" zu dessen Hosted-Features
// (Feature.Rolle.Sache ohne Präfix, Konzept 8.1 und 8.2); alle anderen (RTL,
// VCL, Drittanbieter) prüft die Regel nicht.
// Fachcode-Packages (Konzept 6.2): "domainPackages" nennt Präfixe, deren Units wie eine
// Anwendung gegliedert sind: <Package>.<Host-Rolle>.Sache (Host-Rollen im Package, 8.1) und
// <Package>.<Feature>.<Rolle>.Sache (Hosted-Features, 8.2). "basePackage" ist das Package, das die
// anderen aufnimmt: Beim Import aus einem anderen Fachcode-Package gilt es als Teil des Hosts, sonst
// importieren sich Fachcode-Packages nie. "layerPrefixes" sind die Präfixe der alten Schichtnamen,
// "layerPackages" die Fachcode-Packages, deren Units bis zu ihrer Umstellung noch danach heißen: Für
// sie gilt das Präfix des Packages nicht, ihre Units werden über die Schichtpräfixe eingeordnet.
// Ein Fachcode-Package sieht eine Unit mit Schichtnamen als Hosted-Feature von "basePackage".
// "frameworks" nennt host-spezifische Frameworks (Name oder Namensanfang vor einem Punkt, z. B.
// "Vcl", "ToolsAPI"); in Fachcode-Packages binden sie nur Host-Rollen und die Rolle Hosting ein.
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
  Rules.Contract,
  Rules.Registry;

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
  /// <summary>Rolle einer Unit nach Ausgabeartefakt.Feature.Rolle.Sache; Host = Unit der Anwendung ohne Präfix, None =
  /// extern.</summary>
  TArchitectureRole = (None, Contract, Internals, Providers, Adapters, Root, Composition, Hosting, Host);
  {$SCOPEDENUMS OFF}
  TArchitectureRoles = set of TArchitectureRole;

  /// <summary>Einordnung eines Unit-Namens.</summary>
  TArchitectureUnit = record
    /// <summary>Präfix des Ausgabeartefakts, z. B. "Atlas.Common"; '' beim Host.</summary>
    Artefact: string;
    /// <summary>Feature, z. B. "Logging"; beim Host die Host-Rolle, z. B. "Shell".</summary>
    Feature: string;
    /// <summary>Erster Rollenbezeichner nach dem Feature, Root ohne einen; Host bzw. None siehe
    /// TArchitectureRole.</summary>
    Role: TArchitectureRole;
    /// <summary>Segmente nach dem Präfix; Segments[0] ist das Feature.</summary>
    Segments: TArray<string>;
    /// <summary>Stellen der Rollenbezeichner in Segments. Ab der zweiten eröffnet jede eine Verschachtelung;
    /// ein Bezeichner gleich dem vorigen zählt als Sache.</summary>
    Positions: TArray<Integer>;
    /// <summary>Rollen an den Stellen aus Positions.</summary>
    Roles: TArray<TArchitectureRole>;
    /// <summary>Hosted-Feature der Anwendung (Name ohne Präfix, erstes Segment aus "hostedFeatures") oder eines
    /// Fachcode-Packages.</summary>
    Hosted: Boolean;
    /// <summary>Fachcode-Package aus "domainPackages", zu dem die Unit gehört; '' sonst.</summary>
    Package: string;
    /// <summary>Bei Package &lt;&gt; '': "basePackage", das für Package zum Host gehört.</summary>
    BasePackage: string;
    /// <summary>Eingeordnet über ein Präfix aus "layerPrefixes" (alter Schichtname).</summary>
    Layer: Boolean;
    /// <summary>Unit eines host-spezifischen Frameworks aus "frameworks"; Role = None.</summary>
    Framework: Boolean;
    /// <summary>Role &lt;&gt; None.</summary>
    function Known: Boolean;
    /// <summary>Gleiches Ausgabeartefakt und gleiches Feature (ohne Groß-/Kleinschreibung).</summary>
    function SameFeature(const AOther: TArchitectureUnit): Boolean;
    /// <summary>True für einen Contract oder Sub-Contract: der letzte Rollenbezeichner ist Contract.</summary>
    function IsContract: Boolean;
  end;

  {$SCOPEDENUMS ON}
  /// <summary>Wie ein Ziel von außerhalb einer Struktur aussieht: Plain = Rolle ohne Verschachtelung,
  /// SubContract = Contract eines Trägers, Nested = andere Teile einer Struktur (nur Composition und Shell),
  /// NestedInternals = Internals einer Struktur (nie von außen).</summary>
  TArchitectureViewKind = (Plain, SubContract, Nested, NestedInternals);
  /// <summary>Host-Rollen nach Konzept 8.1; unbekannte Namen aus "hostRoles" gelten als Shell.</summary>
  TArchitectureHostRole = (Foundation, Core, Shell, Adapters, Platform);
  {$SCOPEDENUMS OFF}
  TArchitectureHostRoles = set of TArchitectureHostRole;

  /// <summary>Sicht auf ein Ziel relativ zu einem Träger.</summary>
  TArchitectureView = record
    Kind: TArchitectureViewKind;
    /// <summary>Rolle direkt hinter dem Träger (Root ohne eine).</summary>
    Role: TArchitectureRole;
  end;

  /// <summary>Optionen beider architecture-*-Regeln.</summary>
  TRoleImportOptions = record
    Prefixes: TArray<string>;
    HostRoles: TArray<string>;
    /// <summary>Hosted-Features der Anwendung (erstes Segment ohne Präfix).</summary>
    HostedFeatures: TArray<string>;
    /// <summary>Genehmigte Ausnahmen; Form je Regel siehe Kopfkommentar.</summary>
    Allow: TArray<string>;
    /// <summary>Präfixe der Fachcode-Packages (Konzept 6.2).</summary>
    DomainPackages: TArray<string>;
    /// <summary>Fachcode-Package, das die anderen aufnimmt; gilt beim Import aus ihnen als Teil des Hosts.</summary>
    BasePackage: string;
    /// <summary>Präfixe der alten Schichtnamen.</summary>
    LayerPrefixes: TArray<string>;
    /// <summary>Fachcode-Packages, deren Units noch Schichtnamen tragen; ihr Präfix gilt nicht.</summary>
    LayerPackages: TArray<string>;
    /// <summary>Host-spezifische Frameworks: Name oder Namensanfang vor einem Punkt.</summary>
    Frameworks: TArray<string>;
  end;

  {$SCOPEDENUMS ON}
  /// <summary>Welche Fachcode-Packages eine Einordnung über ihr Präfix liest: Switched = alle außer
  /// "layerPackages" (deren Units tragen noch Schichtnamen, auch wenn ein Name mit dem Präfix eines Packages beginnt
  /// wie Atlas.IDE.Editor.* in Base), Target = dazu "basePackage" (Base bekommt seine Foundation vor der
  /// Umstellung), None = keines (Ziele einer Unit mit Schichtnamen).</summary>
  TArchitectureScope = (Switched, Target, None);
  {$SCOPEDENUMS OFF}

  /// <summary>Importmatrix des Rollenkonzepts (docs/Architektur.md "Importregeln").</summary>
  TArchitectureMatrix = class
  private
    class function LongestPrefix(const AUnitName: string; const APrefixes: TArray<string>): string; static;
    class function FeatureRole(const ARoleName: string): TArchitectureRole; static;
    class function ClassifyFeature(const AUnitName, APrefix: string): TArchitectureUnit; static;
    class function ClassifyHost(const AUnitName: string; const AHostRoles, AHostedFeatures: TArray<string>):
      TArchitectureUnit; static;
    class function Within(const AUnit: TArchitectureUnit; ALength: Integer;
      const ACarrier: TArchitectureUnit): Boolean; static;
    class function LevelRoles(const AUnit: TArchitectureUnit; ALength: Integer): TArray<TArchitectureRole>; static;
    class function HostRole(const AUnit: TArchitectureUnit): TArchitectureHostRole; static;
    class function HostAllows(const ASource: TArchitectureUnit; const AView: TArchitectureView): Boolean; static;
    class function HostToHostedAllows(const ASource: TArchitectureUnit; const AView: TArchitectureView): Boolean;
      static;
    class function ForeignAllows(ARights: TArchitectureRole; const AView: TArchitectureView): Boolean; static;
    class function OwnAllows(const ASource, ATarget: TArchitectureUnit): Boolean; static;
    class function ViewName(const AView: TArchitectureView): string; static;
    class function ActivePrefixes(const AOptions: TRoleImportOptions; AScope: TArchitectureScope): TArray<string>;
      static;
    class function ClassifyDomain(const AUnitName, APackage: string;
      const AOptions: TRoleImportOptions): TArchitectureUnit; static;
    class function IsFramework(const AUnitName: string; const AFrameworks: TArray<string>): Boolean; static;
    class function FrameworkAllowed(const ASource: TArchitectureUnit): Boolean; static;
    class function SameHost(const ASource, ATarget: TArchitectureUnit): Boolean; static;
    class function DomainAllows(const ASource, ATarget: TArchitectureUnit): Boolean; static;
    class function RoleName(const AUnit: TArchitectureUnit): string; static;
  public
    /// <summary>Ordnet AUnitName ein; Role = None für externe Units.</summary>
    class function Classify(const AUnitName: string; const APrefixes, AHostRoles,
      AHostedFeatures: TArray<string>): TArchitectureUnit; overload; static;
    /// <summary>Ordnet AUnitName mit allen Optionen ein; AScope sagt, welche Fachcode-Packages über ihr Präfix
    /// gelesen werden.</summary>
    class function Classify(const AUnitName: string; const AOptions: TRoleImportOptions;
      AScope: TArchitectureScope): TArchitectureUnit; overload; static;
    /// <summary>Ordnet die geprüfte Unit ein: Packages aus "layerPackages" noch nach Schichtnamen.</summary>
    class function ClassifySource(const AUnitName: string; const AOptions: TRoleImportOptions): TArchitectureUnit;
      static;
    /// <summary>Ordnet ein Ziel von ASource ein: Von einer Unit mit Schichtnamen aus alles nach Schichtnamen, sonst
    /// jedes Fachcode-Package nach seinem Präfix; aus einem Fachcode-Package ist eine Unit mit Schichtnamen ein
    /// Hosted-Feature von "basePackage".</summary>
    class function ClassifyTarget(const ASource: TArchitectureUnit; const AUnitName: string;
      const AOptions: TRoleImportOptions): TArchitectureUnit; static;
    /// <summary>Länge des tiefsten gemeinsamen Trägers in Segmenten; 1 = nur das Feature. Kandidaten sind die
    /// Stellen verschachtelter Rollenbezeichner und der ganze Name einer Unit mit Rolle und Sache (Cache ist
    /// Träger von Cache.Store).</summary>
    class function CarrierLength(const ASource, ATarget: TArchitectureUnit): Integer; static;
    /// <summary>Importrechte von AUnit relativ zum Träger der Länge ALength: Die Struktur erbt die Rechte des
    /// Trägers, ein Sub-Contract nur die Contract-Rechte.</summary>
    class function SourceRights(const AUnit: TArchitectureUnit; ALength: Integer): TArchitectureRole; static;
    /// <summary>Sicht auf AUnit von außerhalb ihrer Struktur relativ zum Träger der Länge ALength.</summary>
    class function TargetView(const AUnit: TArchitectureUnit; ALength: Integer): TArchitectureView; static;
    /// <summary>True, wenn ASource ATarget importieren darf; unbekannte Units sind immer erlaubt.</summary>
    class function Allowed(const ASource, ATarget: TArchitectureUnit): Boolean; static;
    /// <summary>True für Internals, auch die einer Struktur: Keine genehmigte Ausnahme gibt sie frei.</summary>
    class function IsInternals(const AUnit: TArchitectureUnit): Boolean; static;
    /// <summary>Kurztext für die Meldung, z. B. "fremde Adapters aus Root".</summary>
    class function Describe(const ASource, ATarget: TArchitectureUnit): string; static;
    /// <summary>Vorgabe für "hostRoles": Foundation, Core, Shell, Adapters, Platform.</summary>
    class function DefaultHostRoles: TArray<string>; static;
  end;

  TRoleImportRule = class(TInterfacedObject, IRule)
  public const
    cRuleId = 'architecture-role-import';
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
    cRuleId = 'architecture-contract-content';
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterArchitectureRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.Generics.Collections,
  System.JSON,
  System.Math,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.UsesClauses,
  Atlas.Common.Localization.Texts,
  Rules.Builtin.FeatureCycles,
  Atlas.Text.Json,
  Rules.Trees;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TArchitectureText = (LayerTitle, LayerViolation, Describe, RoleTitle, RoleViolation, ContractTitle, ContractClass,
    Foreign, Own, SubContract, Nested, NestedInternals, ForeignPackage, ForeignHosted, FrameworkUse);

const
  cTexts: array[TArchitectureText] of TAtlasText = (
    (De: 'uses-Eintrag verletzt eine Schichtregel aus atlas.json';
     En: 'uses entry violates a layer rule from atlas.json'),
    (De: '%s darf %s nicht verwenden (Schicht "%s")'; En: '%s must not use %s (layer "%s")'),
    (De: '%s %s aus %s'; En: '%s %s from %s'),
    (De: 'uses-Eintrag verletzt die Rollenmatrix';
     En: 'uses entry violates the role matrix'),
    (De: '%s darf %s nicht importieren (%s)'; En: '%s must not import %s (%s)'),
    (De: 'Contract-Unit deklariert eine Klasse'; En: 'Contract unit declares a class'),
    (De: '%s ist eine Klasse in einer Contract-Unit; Contract enthält nur Records, Interfaces, Aufzählungen und ' +
      'Ausnahmen';
     En: '%s is a class in a contract unit; a contract contains only records, interfaces, enumerations and ' +
      'exceptions'),
    (De: 'fremde'; En: 'foreign'),
    (De: 'eigene'; En: 'own'),
    (De: 'Sub-Contract'; En: 'sub-contract'),
    (De: 'verschachtelte %s'; En: 'nested %s'),
    (De: 'Internals einer Struktur'; En: 'internals of a nested structure'),
    (De: 'Fachcode-Package %s aus %s'; En: 'domain package %s from %s'),
    (De: 'fremdes Hosted-Feature %s aus %s'; En: 'foreign hosted feature %s from %s'),
    (De: 'Framework aus %s; nur Hosting und Host-Rollen binden es ein';
     En: 'framework from %s; only hosting and host roles use it'));

{$SCOPEDENUMS OFF}

const
  cRoleNames: array[TArchitectureRole] of string =
    ('', 'Contract', 'Internals', 'Providers', 'Adapters', 'Root', 'Composition', 'Hosting', 'Host');
  cFeatureRoles = [TArchitectureRole.Contract, TArchitectureRole.Internals, TArchitectureRole.Providers,
    TArchitectureRole.Adapters, TArchitectureRole.Composition, TArchitectureRole.Hosting];
  // Eigenes Feature (in einer Struktur relativ zum Träger), Rolle der Quelle -> erlaubte Rollen des Ziels.
  // Hosting nach Konzept 8.2: nur eigener Contract und eigenes Hosting; Composition auch eigenes Hosting.
  // Muss $OwnAllowed in Tools/Check-PackageDependencies.ps1 entsprechen.
  cOwnAllowed: array[TArchitectureRole] of TArchitectureRoles = (
    [],
    [TArchitectureRole.Contract],
    [TArchitectureRole.Contract, TArchitectureRole.Internals],
    [TArchitectureRole.Contract, TArchitectureRole.Internals, TArchitectureRole.Root],
    [TArchitectureRole.Contract, TArchitectureRole.Internals, TArchitectureRole.Root],
    [TArchitectureRole.Contract, TArchitectureRole.Internals, TArchitectureRole.Root],
    [TArchitectureRole.Contract, TArchitectureRole.Providers, TArchitectureRole.Adapters,
     TArchitectureRole.Root, TArchitectureRole.Composition, TArchitectureRole.Hosting],
    [TArchitectureRole.Contract, TArchitectureRole.Hosting],
    []);
  // Host-Rollen nach Konzept 8.1: erlaubte Rollen der Features (ohne Verschachtelung) und erlaubte Host-Rollen.
  // Muss $HostAllowed und $HostHostAllowed in Tools/Check-PackageDependencies.ps1 entsprechen.
  cHostAllowed: array[TArchitectureHostRole] of TArchitectureRoles = (
    [TArchitectureRole.Contract],
    [TArchitectureRole.Contract, TArchitectureRole.Root],
    [TArchitectureRole.Contract, TArchitectureRole.Root, TArchitectureRole.Providers, TArchitectureRole.Adapters,
     TArchitectureRole.Composition, TArchitectureRole.Hosting],
    [TArchitectureRole.Contract, TArchitectureRole.Root],
    [TArchitectureRole.Contract, TArchitectureRole.Root]);
  cHostHostAllowed: array[TArchitectureHostRole] of TArchitectureHostRoles = (
    [TArchitectureHostRole.Foundation],
    [TArchitectureHostRole.Foundation, TArchitectureHostRole.Core, TArchitectureHostRole.Platform],
    [TArchitectureHostRole.Foundation, TArchitectureHostRole.Core, TArchitectureHostRole.Shell,
     TArchitectureHostRole.Adapters, TArchitectureHostRole.Platform],
    [TArchitectureHostRole.Foundation, TArchitectureHostRole.Core, TArchitectureHostRole.Adapters,
     TArchitectureHostRole.Platform],
    [TArchitectureHostRole.Platform]);
  cHostRoleNames: array[TArchitectureHostRole] of string = ('Foundation', 'Core', 'Shell', 'Adapters', 'Platform');

function MatchesAny(const APatterns: TArray<string>; const AName: string): Boolean;
var
  mPattern: string;
begin
  for mPattern in APatterns do
  begin
    if MatchesGlob(mPattern, AName) then
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

procedure TForbiddenUsesRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mLayers: TArray<TArchitectureLayer>;
  mLayer: TArchitectureLayer;
  mUsed: TUsesReference;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mLayers := ParseLayers(AContext.Options);
  if mLayers = nil then
  begin
    Exit;
  end;
  for mUsed in TPascalUses.References(AContext.Tree.Tokens) do
  begin
    if Violates(mLayers, AContext.UnitName, AContext.RelativePath, mUsed.Name, mLayer) then
    begin
      AReport.Add(mUsed.Range, cTexts[TArchitectureText.LayerViolation].Fmt([AContext.UnitName, mUsed.Name,
        mLayer.From]));
    end;
  end;
end;

class function TForbiddenUsesRule.ParseLayers(const AOptions: string): TArray<TArchitectureLayer>;
var
  mValue: TJSONValue;
  mList: TJSONArray;
  mItem: TJSONValue;
  mLayer: TArchitectureLayer;
begin
  Result := nil;
  if Trim(AOptions) = '' then
  begin
    Exit;
  end;
  mValue := TJSONObject.ParseJSONValue(AOptions);
  try
    if not ((mValue is TJSONObject) and TJSONObject(mValue).TryGetValue<TJSONArray>('layers', mList)) then
    begin
      Exit;
    end;
    for mItem in mList do
    begin
      if not ((mItem is TJSONObject) and TJSONObject(mItem).TryGetValue<string>('from', mLayer.From)) or
        (Trim(mLayer.From) = '') then
      begin
        Continue;
      end;
      mLayer.Deny := TJsonRead.Strings(TJSONObject(mItem), 'deny');
      mLayer.Allow := TJsonRead.Strings(TJSONObject(mItem), 'allow');
      if mLayer.Deny <> nil then
      begin
        Result := Result + [mLayer];
      end;
    end;
  finally
    mValue.Free;
  end;
end;

class function TForbiddenUsesRule.Violates(const ALayers: TArray<TArchitectureLayer>; const AUnitName,
  ARelativePath, AUsedUnit: string; out ALayer: TArchitectureLayer): Boolean;
var
  mLayer: TArchitectureLayer;
  mSubject: string;
begin
  for mLayer in ALayers do
  begin
    if Pos('/', mLayer.From) > 0 then
    begin
      mSubject := StringReplace(ARelativePath, '\', '/', [rfReplaceAll]);
    end
    else
    begin
      mSubject := AUnitName;
    end;
    if (mSubject = '') or not MatchesGlob(mLayer.From, mSubject) then
    begin
      Continue;
    end;
    if MatchesAny(mLayer.Deny, AUsedUnit) and not MatchesAny(mLayer.Allow, AUsedUnit) then
    begin
      ALayer := mLayer;
      Exit(True);
    end;
  end;
  Result := False;
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

function TArchitectureUnit.IsContract: Boolean;
begin
  Result := (Roles <> nil) and (Roles[High(Roles)] = TArchitectureRole.Contract);
end;

{ TArchitectureMatrix }

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
    if (mRole in cFeatureRoles) and SameText(cRoleNames[mRole], ARoleName) then
    begin
      Result := mRole;
    end;
  end;
end;

class function TArchitectureMatrix.ClassifyFeature(const AUnitName, APrefix: string): TArchitectureUnit;
var
  mParts: TArray<string>;
  mIndex, mCount: Integer;
  mRole: TArchitectureRole;
begin
  Result := Default(TArchitectureUnit);
  if APrefix = '' then
  begin
    mParts := AUnitName.Split(['.']);
  end
  else
  begin
    mParts := Copy(AUnitName, Length(APrefix) + 2, MaxInt).Split(['.']);
  end;
  if (Length(mParts) = 0) or (mParts[0] = '') then
  begin
    Exit;
  end;
  Result.Artefact := APrefix;
  Result.Feature := mParts[0];
  Result.Segments := mParts;
  Result.Role := TArchitectureRole.Root;
  for mIndex := 1 to High(mParts) do
  begin
    mRole := FeatureRole(mParts[mIndex]);
    // Keine Wiederholung: Providers.P.Providers.X ist Providers.P.X.
    if (mRole <> TArchitectureRole.Root) and ((Result.Roles = nil) or (Result.Roles[High(Result.Roles)] <> mRole)) then
    begin
      mCount := Length(Result.Roles);
      SetLength(Result.Roles, mCount + 1);
      SetLength(Result.Positions, mCount + 1);
      Result.Roles[mCount] := mRole;
      Result.Positions[mCount] := mIndex;
    end;
  end;
  if Result.Roles <> nil then
  begin
    Result.Role := Result.Roles[0];
  end;
end;

class function TArchitectureMatrix.ClassifyHost(const AUnitName: string;
  const AHostRoles, AHostedFeatures: TArray<string>): TArchitectureUnit;
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
  for mPrefix in AHostedFeatures do
  begin
    if SameText(mPrefix, mParts[0]) then
    begin
      Result := ClassifyFeature(AUnitName, '');
      Result.Hosted := True;
      Exit;
    end;
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

class function TArchitectureMatrix.Classify(const AUnitName: string; const APrefixes, AHostRoles,
  AHostedFeatures: TArray<string>): TArchitectureUnit;
var
  mOptions: TRoleImportOptions;
begin
  mOptions := Default(TRoleImportOptions);
  mOptions.Prefixes := APrefixes;
  mOptions.HostRoles := AHostRoles;
  mOptions.HostedFeatures := AHostedFeatures;
  Result := Classify(AUnitName, mOptions, TArchitectureScope.Switched);
end;

class function TArchitectureMatrix.ActivePrefixes(const AOptions: TRoleImportOptions;
  AScope: TArchitectureScope): TArray<string>;
var
  mPrefix: string;
begin
  Result := nil;
  for mPrefix in AOptions.Prefixes + AOptions.LayerPrefixes + AOptions.DomainPackages do
  begin
    if not MatchText(mPrefix, AOptions.DomainPackages) or
      ((AScope <> TArchitectureScope.None) and not MatchText(mPrefix, AOptions.LayerPackages)) or
      ((AScope = TArchitectureScope.Target) and SameText(mPrefix, AOptions.BasePackage)) then
    begin
      Result := Result + [mPrefix];
    end;
  end;
end;

class function TArchitectureMatrix.ClassifyDomain(const AUnitName, APackage: string;
  const AOptions: TRoleImportOptions): TArchitectureUnit;
var
  mRest: TArray<string>;
  mRole: string;
begin
  Result := Default(TArchitectureUnit);
  mRest := Copy(AUnitName, Length(APackage) + 2, MaxInt).Split(['.']);
  if (Length(mRest) = 0) or (mRest[0] = '') then
  begin
    Exit;
  end;
  // Host-Rollen im Package (Konzept 8.1), sonst ein Hosted-Feature des Packages (8.2).
  for mRole in AOptions.HostRoles do
  begin
    if SameText(mRole, mRest[0]) then
    begin
      Result.Feature := mRole;
      Result.Role := TArchitectureRole.Host;
    end;
  end;
  if Result.Role <> TArchitectureRole.Host then
  begin
    Result := ClassifyFeature(AUnitName, APackage);
    Result.Hosted := True;
  end;
  Result.Artefact := APackage;
  Result.Package := APackage;
  Result.BasePackage := AOptions.BasePackage;
end;

class function TArchitectureMatrix.IsFramework(const AUnitName: string; const AFrameworks: TArray<string>): Boolean;
var
  mName: string;
begin
  for mName in AFrameworks do
  begin
    if (mName <> '') and (SameText(mName, AUnitName) or StartsText(mName + '.', AUnitName)) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TArchitectureMatrix.Classify(const AUnitName: string; const AOptions: TRoleImportOptions;
  AScope: TArchitectureScope): TArchitectureUnit;
var
  mBest: string;
begin
  Result := Default(TArchitectureUnit);
  if IsFramework(AUnitName, AOptions.Frameworks) then
  begin
    Result.Framework := True;
    Exit;
  end;
  mBest := LongestPrefix(AUnitName, ActivePrefixes(AOptions, AScope));
  if mBest = '' then
  begin
    Result := ClassifyHost(AUnitName, AOptions.HostRoles, AOptions.HostedFeatures);
  end
  else if MatchText(mBest, AOptions.DomainPackages) then
  begin
    Result := ClassifyDomain(AUnitName, mBest, AOptions);
  end
  else
  begin
    Result := ClassifyFeature(AUnitName, mBest);
    Result.Layer := MatchText(mBest, AOptions.LayerPrefixes);
  end;
end;

class function TArchitectureMatrix.ClassifySource(const AUnitName: string;
  const AOptions: TRoleImportOptions): TArchitectureUnit;
begin
  Result := Classify(AUnitName, AOptions, TArchitectureScope.Switched);
end;

class function TArchitectureMatrix.ClassifyTarget(const ASource: TArchitectureUnit; const AUnitName: string;
  const AOptions: TRoleImportOptions): TArchitectureUnit;
begin
  // Eine Unit mit Schichtnamen gehört zu einem noch nicht umgestellten Package: alte Regel auch für ihre Ziele.
  if ASource.Layer then
  begin
    Result := Classify(AUnitName, AOptions, TArchitectureScope.None);
  end
  else
  begin
    Result := Classify(AUnitName, AOptions, TArchitectureScope.Target);
  end;
  // Aus einem Fachcode-Package ist ein Schichtname eine noch nicht umbenannte Unit von Base.
  if (ASource.Package <> '') and Result.Layer and (AOptions.BasePackage <> '') then
  begin
    Result.Package := AOptions.BasePackage;
    Result.BasePackage := AOptions.BasePackage;
    Result.Hosted := True;
  end;
end;

class function TArchitectureMatrix.Within(const AUnit: TArchitectureUnit; ALength: Integer;
  const ACarrier: TArchitectureUnit): Boolean;
var
  mIndex: Integer;
begin
  Result := (Length(AUnit.Segments) >= ALength) and (Length(ACarrier.Segments) >= ALength);
  mIndex := 0;
  while Result and (mIndex < ALength) do
  begin
    Result := SameText(AUnit.Segments[mIndex], ACarrier.Segments[mIndex]);
    Inc(mIndex);
  end;
end;

/// <summary>Trägerlängen, die AUnit vorgibt: Stellen verschachtelter Rollenbezeichner und, mit Rolle und Sache,
/// die Länge des ganzen Namens.</summary>
function CarrierCandidates(const AUnit: TArchitectureUnit): TArray<Integer>;
var
  mIndex: Integer;
begin
  Result := nil;
  if AUnit.Positions = nil then
  begin
    Exit;
  end;
  SetLength(Result, Length(AUnit.Positions));
  for mIndex := 1 to High(AUnit.Positions) do
  begin
    Result[mIndex - 1] := AUnit.Positions[mIndex];
  end;
  Result[High(Result)] := 0;
  if Length(AUnit.Segments) > AUnit.Positions[High(AUnit.Positions)] + 1 then
  begin
    Result[High(Result)] := Length(AUnit.Segments);
  end;
end;

class function TArchitectureMatrix.CarrierLength(const ASource, ATarget: TArchitectureUnit): Integer;
var
  mCarrier: TArchitectureUnit;
  mLength, mLongest: Integer;
begin
  Result := 1;
  mLongest := Max(Length(ASource.Segments), Length(ATarget.Segments));
  for mCarrier in TArray<TArchitectureUnit>.Create(ASource, ATarget) do
  begin
    for mLength in CarrierCandidates(mCarrier) do
    begin
      // Ein gleicher Name ist kein Träger seiner selbst.
      if (mLength > Result) and (mLongest > mLength) and Within(ASource, mLength, mCarrier) and
        Within(ATarget, mLength, mCarrier) then
      begin
        Result := mLength;
      end;
    end;
  end;
end;

class function TArchitectureMatrix.LevelRoles(const AUnit: TArchitectureUnit;
  ALength: Integer): TArray<TArchitectureRole>;
var
  mIndex, mCount: Integer;
begin
  Result := nil;
  SetLength(Result, Length(AUnit.Roles));
  mCount := 0;
  for mIndex := 0 to High(AUnit.Roles) do
  begin
    if AUnit.Positions[mIndex] >= ALength then
    begin
      Result[mCount] := AUnit.Roles[mIndex];
      Inc(mCount);
    end;
  end;
  SetLength(Result, mCount);
end;

class function TArchitectureMatrix.SourceRights(const AUnit: TArchitectureUnit;
  ALength: Integer): TArchitectureRole;
var
  mRoles: TArray<TArchitectureRole>;
  mRole: TArchitectureRole;
begin
  mRoles := LevelRoles(AUnit, ALength);
  if mRoles = nil then
  begin
    Exit(TArchitectureRole.Root);
  end;
  Result := mRoles[0];
  for mRole in mRoles do
  begin
    if mRole = TArchitectureRole.Contract then
    begin
      Result := TArchitectureRole.Contract;
    end;
  end;
end;

class function TArchitectureMatrix.TargetView(const AUnit: TArchitectureUnit;
  ALength: Integer): TArchitectureView;
var
  mRoles: TArray<TArchitectureRole>;
  mRole: TArchitectureRole;
begin
  Result := Default(TArchitectureView);
  Result.Role := TArchitectureRole.Root;
  mRoles := LevelRoles(AUnit, ALength);
  if mRoles = nil then
  begin
    Exit;
  end;
  Result.Role := mRoles[0];
  if Length(mRoles) = 1 then
  begin
    Exit;
  end;
  Result.Kind := TArchitectureViewKind.Nested;
  if mRoles[1] = TArchitectureRole.Contract then
  begin
    Result.Kind := TArchitectureViewKind.SubContract;
  end;
  for mRole in mRoles do
  begin
    if mRole = TArchitectureRole.Internals then
    begin
      Result.Kind := TArchitectureViewKind.NestedInternals;
    end;
  end;
end;

class function TArchitectureMatrix.HostRole(const AUnit: TArchitectureUnit): TArchitectureHostRole;
var
  mRole: TArchitectureHostRole;
begin
  Result := TArchitectureHostRole.Shell;
  for mRole := Low(TArchitectureHostRole) to High(TArchitectureHostRole) do
  begin
    if SameText(cHostRoleNames[mRole], AUnit.Feature) then
    begin
      Result := mRole;
    end;
  end;
end;

class function TArchitectureMatrix.HostAllows(const ASource: TArchitectureUnit;
  const AView: TArchitectureView): Boolean;
var
  mRole: TArchitectureHostRole;
begin
  mRole := HostRole(ASource);
  case AView.Kind of
    TArchitectureViewKind.Plain:
      Result := AView.Role in cHostAllowed[mRole];
    // Host-Adapters implementieren Sub-Contracts (Konzept 7.4).
    TArchitectureViewKind.SubContract:
      Result := mRole in [TArchitectureHostRole.Shell, TArchitectureHostRole.Adapters];
    TArchitectureViewKind.Nested:
      Result := mRole = TArchitectureHostRole.Shell;
  else
    Result := False;
  end;
end;

class function TArchitectureMatrix.HostToHostedAllows(const ASource: TArchitectureUnit;
  const AView: TArchitectureView): Boolean;
begin
  // Konzept 8.1, Zeilen Hosted-Feature: die Shell alles außer Internals, Host-Adapters nur den Contract (und
  // Sub-Contracts zum Implementieren, 7.4); Foundation, Core und Platform nichts.
  case HostRole(ASource) of
    TArchitectureHostRole.Shell:
      Result := HostAllows(ASource, AView);
    TArchitectureHostRole.Adapters:
      Result := (AView.Kind = TArchitectureViewKind.SubContract) or
        ((AView.Kind = TArchitectureViewKind.Plain) and (AView.Role = TArchitectureRole.Contract));
  else
    Result := False;
  end;
end;

class function TArchitectureMatrix.ForeignAllows(ARights: TArchitectureRole;
  const AView: TArchitectureView): Boolean;
begin
  Result := AView.Kind = TArchitectureViewKind.Plain;
  if Result and (ARights = TArchitectureRole.Contract) then
  begin
    Result := AView.Role = TArchitectureRole.Contract;
  end
  else if Result then
  begin
    Result := AView.Role in [TArchitectureRole.Contract, TArchitectureRole.Root];
  end;
end;

class function TArchitectureMatrix.OwnAllows(const ASource, ATarget: TArchitectureUnit): Boolean;
var
  mLength: Integer;
  mRights: TArchitectureRole;
  mView: TArchitectureView;
begin
  mLength := CarrierLength(ASource, ATarget);
  mRights := SourceRights(ASource, mLength);
  mView := TargetView(ATarget, mLength);
  case mView.Kind of
    // Sub-Contract: Geschwister der äußeren Rolle und die Composition (Konzept 7.4, Zugriff von außen).
    TArchitectureViewKind.SubContract:
      Result := (mRights = TArchitectureRole.Composition) or (TargetView(ASource, mLength).Role = mView.Role);
    TArchitectureViewKind.Nested:
      Result := mRights = TArchitectureRole.Composition;
    TArchitectureViewKind.NestedInternals:
      Result := False;
  else
    Result := mView.Role in cOwnAllowed[mRights];
  end;
end;

class function TArchitectureMatrix.FrameworkAllowed(const ASource: TArchitectureUnit): Boolean;
var
  mRole: TArchitectureRole;
begin
  // Konzept 6.1: In einem Fachcode-Package binden nur Hosting und die Host-Rollen ein Framework des Hosts ein.
  Result := (ASource.Package = '') or (ASource.Role = TArchitectureRole.Host);
  for mRole in ASource.Roles do
  begin
    Result := Result or (mRole = TArchitectureRole.Hosting);
  end;
end;

class function TArchitectureMatrix.SameHost(const ASource, ATarget: TArchitectureUnit): Boolean;
begin
  // Konzept 8.1: Der Inhalt eines Packages zählt zum Host, der es aufnimmt; Base also zum Host jedes Moduls.
  Result := (ATarget.Package <> '') and (SameText(ATarget.Package, ASource.Package) or
    SameText(ATarget.Package, ASource.BasePackage));
end;

class function TArchitectureMatrix.DomainAllows(const ASource, ATarget: TArchitectureUnit): Boolean;
begin
  // Platform-Features und die Anwendung importieren kein Fachcode-Package, Fachcode-Packages einander nicht.
  if (ASource.Package = '') or ((ATarget.Package <> '') and not SameHost(ASource, ATarget)) then
  begin
    Exit(False);
  end;
  if ATarget.Package = '' then
  begin
    // Platform-Feature; Host und Hosted-Features der Anwendung sind ein anderer Host.
    if (ATarget.Role = TArchitectureRole.Host) or ATarget.Hosted then
    begin
      Exit(False);
    end;
    if ASource.Role = TArchitectureRole.Host then
    begin
      Exit(HostAllows(ASource, TargetView(ATarget, 1)));
    end;
    Exit(ForeignAllows(SourceRights(ASource, 1), TargetView(ATarget, 1)));
  end;
  if ATarget.Role = TArchitectureRole.Host then
  begin
    if ASource.Hosted then
    begin
      Exit(HostRole(ATarget) = TArchitectureHostRole.Foundation);
    end;
    Exit(HostRole(ATarget) in cHostHostAllowed[HostRole(ASource)]);
  end;
  if ASource.Role = TArchitectureRole.Host then
  begin
    Exit(HostToHostedAllows(ASource, TargetView(ATarget, 1)));
  end;
  // Hosted-Features importieren einander nie (8.2), innen gilt die Matrix des Features.
  Result := ASource.SameFeature(ATarget) and OwnAllows(ASource, ATarget);
end;

class function TArchitectureMatrix.Allowed(const ASource, ATarget: TArchitectureUnit): Boolean;
begin
  if ATarget.Framework then
  begin
    Exit(FrameworkAllowed(ASource));
  end;
  if not (ASource.Known and ATarget.Known) then
  begin
    Exit(True);
  end;
  if (ASource.Package <> '') or (ATarget.Package <> '') then
  begin
    Exit(DomainAllows(ASource, ATarget));
  end;
  // Platform-Features importieren nie den Host (8.3), Hosted-Features nur die Foundation (8.2); Host-Rollen
  // untereinander nach 8.1.
  if ATarget.Role = TArchitectureRole.Host then
  begin
    if ASource.Hosted then
    begin
      Exit(HostRole(ATarget) = TArchitectureHostRole.Foundation);
    end;
    Exit((ASource.Role = TArchitectureRole.Host) and (HostRole(ATarget) in cHostHostAllowed[HostRole(ASource)]));
  end;
  if ASource.Role = TArchitectureRole.Host then
  begin
    if ATarget.Hosted then
    begin
      Exit(HostToHostedAllows(ASource, TargetView(ATarget, 1)));
    end;
    Exit(HostAllows(ASource, TargetView(ATarget, 1)));
  end;
  // Platform-Features importieren keine Hosted-Features (8.3), Hosted-Features einander nie (8.2).
  if ATarget.Hosted and not ASource.SameFeature(ATarget) then
  begin
    Exit(False);
  end;
  if not ASource.SameFeature(ATarget) then
  begin
    Exit(ForeignAllows(SourceRights(ASource, 1), TargetView(ATarget, 1)));
  end;
  Result := OwnAllows(ASource, ATarget);
end;

class function TArchitectureMatrix.IsInternals(const AUnit: TArchitectureUnit): Boolean;
var
  mRole: TArchitectureRole;
begin
  Result := False;
  for mRole in AUnit.Roles do
  begin
    Result := Result or (mRole = TArchitectureRole.Internals);
  end;
end;

class function TArchitectureMatrix.ViewName(const AView: TArchitectureView): string;
begin
  case AView.Kind of
    TArchitectureViewKind.SubContract:
      Result := cTexts[TArchitectureText.SubContract].Text;
    TArchitectureViewKind.Nested:
      Result := cTexts[TArchitectureText.Nested].Fmt([cRoleNames[AView.Role]]);
    TArchitectureViewKind.NestedInternals:
      Result := cTexts[TArchitectureText.NestedInternals].Text;
  else
    Result := cRoleNames[AView.Role];
  end;
end;

class function TArchitectureMatrix.RoleName(const AUnit: TArchitectureUnit): string;
begin
  Result := cRoleNames[AUnit.Role];
  if AUnit.Role = TArchitectureRole.Host then
  begin
    Result := 'Host-' + cHostRoleNames[HostRole(AUnit)];
  end;
end;

/// <summary>Feature mit Ausgabeartefakt, z. B. "Atlas.Core.Settings"; bei der Anwendung nur das Feature.</summary>
function QualifiedFeature(const AUnit: TArchitectureUnit): string;
begin
  Result := AUnit.Feature;
  if AUnit.Artefact <> '' then
  begin
    Result := AUnit.Artefact + '.' + AUnit.Feature;
  end;
end;

class function TArchitectureMatrix.Describe(const ASource, ATarget: TArchitectureUnit): string;
var
  mKind, mSource, mTarget: string;
  mLength: Integer;
begin
  if ATarget.Framework then
  begin
    Exit(cTexts[TArchitectureText.FrameworkUse].Fmt([RoleName(ASource)]));
  end;
  if (ATarget.Package <> '') and not ((ASource.Package <> '') and SameHost(ASource, ATarget)) then
  begin
    Exit(cTexts[TArchitectureText.ForeignPackage].Fmt([ATarget.Package, RoleName(ASource)]));
  end;
  if ATarget.Hosted and (ASource.Role <> TArchitectureRole.Host) and not ASource.SameFeature(ATarget) then
  begin
    Exit(cTexts[TArchitectureText.ForeignHosted].Fmt([QualifiedFeature(ATarget), RoleName(ASource)]));
  end;
  mKind := cTexts[TArchitectureText.Foreign].Text;
  mLength := 1;
  mSource := cRoleNames[ASource.Role];
  if ASource.Role = TArchitectureRole.Host then
  begin
    mSource := 'Host-' + cHostRoleNames[HostRole(ASource)];
  end
  else if (ATarget.Role <> TArchitectureRole.Host) and ASource.SameFeature(ATarget) then
  begin
    mKind := cTexts[TArchitectureText.Own].Text;
    mLength := CarrierLength(ASource, ATarget);
    mSource := cRoleNames[SourceRights(ASource, mLength)];
  end;
  mTarget := 'Host-' + cHostRoleNames[HostRole(ATarget)];
  if ATarget.Role <> TArchitectureRole.Host then
  begin
    mTarget := ViewName(TargetView(ATarget, mLength));
  end;
  Result := cTexts[TArchitectureText.Describe].Fmt([mKind, mTarget, mSource]);
end;

class function TArchitectureMatrix.DefaultHostRoles: TArray<string>;
begin
  Result := ['Foundation', 'Core', 'Shell', 'Adapters', 'Platform'];
end;

{ TRoleImportRule }

function TRoleImportRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('architecture-role-import', TRuleSeverity.Warning,
    cTexts[TArchitectureText.RoleTitle].Text);
end;

class function TRoleImportRule.ParseOptions(const AOptions: string): TRoleImportOptions;
var
  mValue: TJSONValue;
begin
  Result := Default(TRoleImportOptions);
  Result.HostRoles := TArchitectureMatrix.DefaultHostRoles;
  if Trim(AOptions) = '' then
  begin
    Exit;
  end;
  mValue := TJSONObject.ParseJSONValue(AOptions);
  try
    if not (mValue is TJSONObject) then
    begin
      Exit;
    end;
    Result.Prefixes := TJsonRead.Strings(TJSONObject(mValue), 'prefixes');
    Result.Allow := TJsonRead.Strings(TJSONObject(mValue), 'allow');
    Result.HostedFeatures := TJsonRead.Strings(TJSONObject(mValue), 'hostedFeatures');
    Result.DomainPackages := TJsonRead.Strings(TJSONObject(mValue), 'domainPackages');
    Result.BasePackage := TJsonRead.Text(TJSONObject(mValue), 'basePackage');
    Result.LayerPrefixes := TJsonRead.Strings(TJSONObject(mValue), 'layerPrefixes');
    Result.LayerPackages := TJsonRead.Strings(TJSONObject(mValue), 'layerPackages');
    Result.Frameworks := TJsonRead.Strings(TJSONObject(mValue), 'frameworks');
    if TJSONObject(mValue).GetValue('hostRoles') <> nil then
    begin
      Result.HostRoles := TJsonRead.Strings(TJSONObject(mValue), 'hostRoles');
    end;
  finally
    mValue.Free;
  end;
end;

class function TRoleImportRule.Approved(const AAllow: TArray<string>; const ASource, ATarget: string): Boolean;
var
  mEntry: string;
  mSeparator: Integer;
begin
  for mEntry in AAllow do
  begin
    mSeparator := Pos('->', mEntry);
    if mSeparator = 0 then
    begin
      Continue;
    end;
    if MatchesGlob(Trim(Copy(mEntry, 1, mSeparator - 1)), ASource) and
      MatchesGlob(Trim(Copy(mEntry, mSeparator + 2, MaxInt)), ATarget) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function OwnUnitName(const AContext: TRuleContext): string;
begin
  Result := TPascalUses.OwnName(AContext.Tree.Tokens);
  if Result = '' then
  begin
    Result := AContext.UnitName;
  end;
end;

procedure TRoleImportRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mOptions: TRoleImportOptions;
  mOwnName: string;
  mSource, mTarget: TArchitectureUnit;
  mUsed: TUsesReference;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mOptions := ParseOptions(AContext.Options);
  // Ohne Präfixe schweigt die Regel: Projekte ohne Rollenkonzept sehen nichts.
  if mOptions.Prefixes = nil then
  begin
    Exit;
  end;
  // Test-Units tragen den Namen der getesteten Unit (X.Contract.Tests), gehören aber zu keiner Rolle
  // (docs/Architektur.md: Tests werden nicht geprüft).
  if TPascalUses.IsTestUnit(AContext.Tree.Tokens) then
  begin
    Exit;
  end;
  mOwnName := OwnUnitName(AContext);
  mSource := TArchitectureMatrix.ClassifySource(mOwnName, mOptions);
  if not mSource.Known then
  begin
    Exit;
  end;
  for mUsed in TPascalUses.References(AContext.Tree.Tokens) do
  begin
    // contains eines Packages nimmt Units auf, statt sie einzubinden (#1109): Das Package ist keine Rolle.
    if mUsed.List = TUsesListKind.ContainsList then
    begin
      Continue;
    end;
    mTarget := TArchitectureMatrix.ClassifyTarget(mSource, mUsed.Name, mOptions);
    // Genehmigte Ausnahmen gelten nie für Internals: Ein Platzhalter wie Atlas.Core.* gibt sie nicht frei.
    if TArchitectureMatrix.Allowed(mSource, mTarget) or
      (Approved(mOptions.Allow, mOwnName, mUsed.Name) and not TArchitectureMatrix.IsInternals(mTarget)) then
    begin
      Continue;
    end;
    AReport.Add(mUsed.Range, cTexts[TArchitectureText.RoleViolation].Fmt(
      [mOwnName, mUsed.Name, TArchitectureMatrix.Describe(mSource, mTarget)]));
  end;
end;

{ TContractContentRule }

function TContractContentRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('architecture-contract-content', TRuleSeverity.Warning,
    cTexts[TArchitectureText.ContractTitle].Text);
end;

function IsExceptionName(const AName: string): Boolean;
var
  mLast: string;
begin
  mLast := AName;
  if LastDelimiter('.', mLast) > 0 then
  begin
    mLast := Copy(mLast, LastDelimiter('.', mLast) + 1, MaxInt);
  end;
  Result := SameText(mLast, 'Exception') or
    ((Length(mLast) >= 2) and (mLast[1] = 'E') and CharInSet(mLast[2], ['A'..'Z']));
end;

/// <summary>True, wenn die Unit von AContext eine Contract-Unit ist, die die Regel prüft.</summary>
function IsCheckedContract(const AContext: TRuleContext; const AOptions: TRoleImportOptions;
  const AOwnName: string): Boolean;
begin
  Result := (AOptions.Prefixes <> nil) and not TPascalUses.IsTestUnit(AContext.Tree.Tokens) and
    TArchitectureMatrix.ClassifySource(AOwnName, AOptions).IsContract;
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
  // Iterativ (tiefe Bäume sprengen den Stapel nicht): Konstanten im interface können lange Ausdrücke enthalten.
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
  ARegistry.Register(TFeatureCycleRule.Create);
end;

initialization
  TAtlasTextTables.Add('Rules.Builtin.Architecture', cTexts);

end.
