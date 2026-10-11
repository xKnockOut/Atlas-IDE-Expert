unit Atlas.Common.Rules.Builtin.Architecture;

// Architekturregeln (#183):
//   forbidden-uses  uses-Eintrag verletzt eine Schichtregel aus atlas.json
//
// Konfiguration als Option der Regel:
//   "rules": { "forbidden-uses": { "severity": "error", "layers": [
//     { "from": "*.Common.*", "deny": ["Vcl.*", "Winapi.*"], "allow": ["Winapi.Windows"] } ] } }
// "from" trifft den Namen der geprüften Unit, mit "/" stattdessen ihren Pfad
// relativ zur Konfiguration (z. B. "Source/Common/**"). "deny" und "allow"
// sind Globs auf die Namen in uses; "allow" hat Vorrang. Ohne "layers"
// meldet die Regel nichts.
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

procedure RegisterArchitectureRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.JSON,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Editing.UsesClause;

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

procedure RegisterArchitectureRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TForbiddenUsesRule.Create);
end;

end.
