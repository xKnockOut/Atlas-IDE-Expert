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
    /// <summary>Role <> None.</summary>
    function Known: Boolean;
    /// <summary>Gleiches Ausgabeartefakt und gleiches Feature (ohne Groß-/Kleinschreibung).</summary>
    function SameFeature(const AOther: TArchitectureUnit): Boolean;
  end;

  /// <summary>Importmatrix des Rollenkonzepts (Konzept 8.1/8.3, docs/Architektur.md "Importregeln").</summary>
  TArchitectureMatrix = class
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
  System.JSON,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.UsesClause;

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
    Exit;
  for Item in List do
    if Item is TJSONString then
      Result := Result + [Item.Value];
end;

function MatchesAny(const APatterns: TArray<string>; const AName: string): Boolean;
var
  Pattern: string;
begin
  for Pattern in APatterns do
    if MatchesGlob(Pattern, AName) then
      Exit(True);
  Result := False;
end;

{ TForbiddenUsesRule }

function TForbiddenUsesRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('forbidden-uses', TRuleSeverity.Error,
    'uses-Eintrag verletzt eine Schichtregel aus atlas.json');
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
    Exit;
  Value := TJSONObject.ParseJSONValue(AOptions);
  try
    if not ((Value is TJSONObject) and TJSONObject(Value).TryGetValue<TJSONArray>('layers', List)) then
      Exit;
    for Item in List do
    begin
      if not ((Item is TJSONObject) and TJSONObject(Item).TryGetValue<string>('from', Layer.From)) or
        (Trim(Layer.From) = '') then
        Continue;
      Layer.Deny := ReadStrings(TJSONObject(Item), 'deny');
      Layer.Allow := ReadStrings(TJSONObject(Item), 'allow');
      if Layer.Deny <> nil then
        Result := Result + [Layer];
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
      Subject := StringReplace(ARelativePath, '\', '/', [rfReplaceAll])
    else
      Subject := AUnitName;
    if (Subject = '') or not MatchesGlob(Layer.From, Subject) then
      Continue;
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
    Exit;
  Layers := ParseLayers(AContext.Options);
  if Layers = nil then
    Exit;
  for Used in TUsesClauses.References(AContext.Tree.Tokens) do
    if Violates(Layers, AContext.UnitName, AContext.RelativePath, Used.Name, Layer) then
      AReport.Add(Used.Range, Format('%s darf %s nicht verwenden (Schicht "%s")',
        [AContext.UnitName, Used.Name, Layer.From]));
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

class function TArchitectureMatrix.Classify(const AUnitName: string; const APrefixes,
  AHostRoles: TArray<string>): TArchitectureUnit;
var
  Prefix, Best: string;
  Parts: TArray<string>;
  Role: TArchitectureRole;
begin
  Result := Default(TArchitectureUnit);
  Best := '';
  for Prefix in APrefixes do
    if (Prefix <> '') and (Length(Prefix) > Length(Best)) and StartsText(Prefix + '.', AUnitName) then
      Best := Prefix;
  if Best <> '' then
  begin
    Parts := Copy(AUnitName, Length(Best) + 2, MaxInt).Split(['.']);
    if (Length(Parts) = 0) or (Parts[0] = '') then
      Exit;
    Result.Artefact := Best;
    Result.Feature := Parts[0];
    Result.Role := TArchitectureRole.Root;
    if Length(Parts) >= 2 then
      for Role := Low(TArchitectureRole) to High(TArchitectureRole) do
        if (Role in FeatureRoles) and SameText(RoleNames[Role], Parts[1]) then
          Result.Role := Role;
    Exit;
  end;
  Parts := AUnitName.Split(['.']);
  if Length(Parts) < 2 then
    Exit;
  for Prefix in AHostRoles do
    if SameText(Prefix, Parts[0]) then
    begin
      Result.Feature := Prefix;
      Result.Role := TArchitectureRole.Host;
      Exit;
    end;
end;

class function TArchitectureMatrix.Allowed(const ASource, ATarget: TArchitectureUnit): Boolean;
begin
  if not (ASource.Known and ATarget.Known) then
    Exit(True);
  // Platform-Features importieren nie den Host (8.3); Host-Units untereinander frei.
  if ATarget.Role = TArchitectureRole.Host then
    Exit(ASource.Role = TArchitectureRole.Host);
  if (ASource.Role <> TArchitectureRole.Host) and ASource.SameFeature(ATarget) then
    Result := ATarget.Role in OwnAllowed[ASource.Role]
  else
    Result := ATarget.Role in ForeignAllowed[ASource.Role];
end;

class function TArchitectureMatrix.Describe(const ASource, ATarget: TArchitectureUnit): string;
var
  Kind: string;
begin
  Kind := 'fremde';
  if (ASource.Role <> TArchitectureRole.Host) and ASource.SameFeature(ATarget) then
    Kind := 'eigene';
  Result := Format('%s %s aus %s', [Kind, RoleNames[ATarget.Role], RoleNames[ASource.Role]]);
end;

{ TRoleImportRule }

function TRoleImportRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('architecture-role-import', TRuleSeverity.Warning,
    'uses-Eintrag verletzt die Rollenmatrix (Konzept 8.1/8.3)', True);
end;

class function TRoleImportRule.ParseOptions(const AOptions: string): TRoleImportOptions;
var
  Value: TJSONValue;
begin
  Result := Default(TRoleImportOptions);
  Result.HostRoles := TArchitectureMatrix.DefaultHostRoles;
  if Trim(AOptions) = '' then
    Exit;
  Value := TJSONObject.ParseJSONValue(AOptions);
  try
    if not (Value is TJSONObject) then
      Exit;
    Result.Prefixes := ReadStrings(TJSONObject(Value), 'prefixes');
    Result.Allow := ReadStrings(TJSONObject(Value), 'allow');
    if TJSONObject(Value).GetValue('hostRoles') <> nil then
      Result.HostRoles := ReadStrings(TJSONObject(Value), 'hostRoles');
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
      Continue;
    if MatchesGlob(Trim(Copy(Entry, 1, Separator - 1)), ASource) and
      MatchesGlob(Trim(Copy(Entry, Separator + 2, MaxInt)), ATarget) then
      Exit(True);
  end;
  Result := False;
end;

function OwnUnitName(const AContext: TRuleContext): string;
begin
  Result := TUsesClauses.OwnName(AContext.Tree.Tokens);
  if Result = '' then
    Result := AContext.UnitName;
end;

procedure TRoleImportRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Options: TRoleImportOptions;
  OwnName: string;
  Source, Target: TArchitectureUnit;
  Used: TUsesReference;
begin
  if AContext.Tree = nil then
    Exit;
  Options := ParseOptions(AContext.Options);
  // Ohne Präfixe schweigt die Regel: Projekte ohne Rollenkonzept sehen nichts.
  if Options.Prefixes = nil then
    Exit;
  OwnName := OwnUnitName(AContext);
  Source := TArchitectureMatrix.Classify(OwnName, Options.Prefixes, Options.HostRoles);
  if not Source.Known then
    Exit;
  for Used in TUsesClauses.References(AContext.Tree.Tokens) do
  begin
    Target := TArchitectureMatrix.Classify(Used.Name, Options.Prefixes, Options.HostRoles);
    if TArchitectureMatrix.Allowed(Source, Target) or Approved(Options.Allow, OwnName, Used.Name) then
      Continue;
    AReport.Add(Used.Range, Format('%s darf %s nicht importieren (%s)',
      [OwnName, Used.Name, TArchitectureMatrix.Describe(Source, Target)]));
  end;
end;

{ TContractContentRule }

function TContractContentRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('architecture-contract-content', TRuleSeverity.Warning, 'Contract-Unit deklariert eine Klasse', True);
end;

function IsExceptionName(const AName: string): Boolean;
var
  Last: string;
begin
  Last := AName;
  if LastDelimiter('.', Last) > 0 then
    Last := Copy(Last, LastDelimiter('.', Last) + 1, MaxInt);
  Result := SameText(Last, 'Exception') or
    ((Length(Last) >= 2) and (Last[1] = 'E') and CharInSet(Last[2], ['A'..'Z']));
end;

procedure TContractContentRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Options: TRoleImportOptions;
  OwnName: string;
  InterfaceNode: TSyntaxNode;
  Report: IRuleReport;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Options := TRoleImportRule.ParseOptions(AContext.Options);
  if Options.Prefixes = nil then
    Exit;
  OwnName := OwnUnitName(AContext);
  if TArchitectureMatrix.Classify(OwnName, Options.Prefixes, Options.HostRoles).Role <>
    TArchitectureRole.Contract then
    Exit;
  InterfaceNode := AContext.Tree.Root.FindChild(TSyntaxKind.InterfaceSection);
  if InterfaceNode = nil then
    Exit;
  Report := AReport;
  // Iterativ (Bericht M1): Konstanten im interface können lange Ausdrücke enthalten.
  InterfaceNode.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      Index: Integer;
      ClassNode, Ancestor: TSyntaxNode;
    begin
      Result := ANode.Kind <> TSyntaxKind.TypeDecl;
      if Result then
        Exit;
      ClassNode := ANode.FindChild(TSyntaxKind.ClassType);
      if ClassNode = nil then
        Exit;
      Ancestor := ClassNode.FindChild(TSyntaxKind.TypeReference);
      if (Ancestor <> nil) and IsExceptionName(Ancestor.Name) then
        Exit;
      for Index := 0 to High(Options.Allow) do
        if MatchesGlob(Options.Allow[Index], OwnName + '.' + ANode.Name) then
          Exit;
      Report.Add(TTextRange.Create(ANode.StartPos.Line, ANode.StartPos.Character, ANode.StartPos.Line,
        ANode.StartPos.Character + Length(ANode.Name)), Format('%s ist eine Klasse in einer Contract-Unit; ' +
        'Contract enthält nur Records, Interfaces, Aufzählungen und Ausnahmen (Konzept 7.1)', [ANode.Name]));
    end);
end;

procedure RegisterArchitectureRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TForbiddenUsesRule.Create);
  ARegistry.Register(TRoleImportRule.Create);
  ARegistry.Register(TContractContentRule.Create);
end;

end.
