unit Atlas.Common.Lsp.SettingsCommands;

// Befehle für den Einstellungsdialog des IDE-Plugins (#227). Das Plugin bindet
// Atlas.Common nicht ein; damit es dieselbe Prüfung wie der Server nutzt,
// fragt es ihn:
//   atlas.server.checkSettings [Text, Ort] Meldungen des Parsers zu einem
//                                           Text im Format von atlas.json;
//                                           Ort "global" (settings.json)
//                                           oder "project" (Vorgabe) meldet
//                                           Schlüssel am falschen Ort
//   atlas.server.settingsCatalog [Sprache] Regeln des Katalogs mit Name,
//                                           Kategorie, Vorgabe, Gruppe,
//                                           Beschreibung, Beispielen,
//                                           Optionen und Kennzeichen
//                                           „experimentell“ (#909) und
//                                           „Sammelkorrektur“ (safeFix, #1352)
//                                           sowie Pfad
//                                           der globalen Datei und Version
//                                           des Servers

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Rules.Catalog;

type
  TLspSettingsCommands = class
  public const
    CheckCommand = 'atlas.server.checkSettings';
    CatalogCommand = 'atlas.server.settingsCatalog';
  public
    /// <summary>{"valid": Boolean, "issues": [{"line", "character", "message", "error"}]}; Zeilen ab 0. AArguments[1]
    /// = "global" prüft den Text als globale Datei, sonst als atlas.json.</summary>
    class function Check(const AArguments: TJSONArray): TJSONObject; static;
    /// <summary>{"rules": [{"id", "name", "category", "severity", "group", "description", "bad", "good",
    /// "options": [{"name", "type", "columns" (nur object-list), "default", "description"}], "experimental",
    /// "safeFix" (#1352)}],
    /// "globalFile", "version"}.
    /// </summary>
    class function Catalog(const AEntries: TArray<TRuleCatalogEntry>; const AGlobalFile: string): TJSONObject;
      overload; static;
    /// <summary>Wie oben; Regeln aus AExperimental tragen "experimental": true (#834, #909).</summary>
    class function Catalog(const AEntries: TArray<TRuleCatalogEntry>; const AGlobalFile: string;
      const AExperimental: TArray<string>): TJSONObject; overload; static;
    /// <summary>Katalog in der Sprache aus AArguments[0] ("de", "en"; sonst englisch).</summary>
    class function CatalogEntries(const AArguments: TJSONArray): TArray<TRuleCatalogEntry>; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.StrUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Configuration.Scopes,
  Atlas.Common.Rules.Catalog.Data,
  Atlas.Common.Rules.Output,
  Atlas.Common.Product.Version;

function FirstString(const AArguments: TJSONArray): string;
begin
  Result := '';
  if (AArguments <> nil) and (AArguments.Count > 0) and (AArguments.Items[0] is TJSONString) then
  begin
    Result := AArguments.Items[0].Value;
  end;
end;

/// <summary>Spalten einer Option der Art "object-list" (#1133): [{"name": …, "list": true}].</summary>
function ColumnsJson(const AColumns: TArray<TRuleOptionColumn>): TJSONArray;
var
  mColumn: TRuleOptionColumn;
  mObject: TJSONObject;
begin
  Result := TJSONArray.Create;
  for mColumn in AColumns do
  begin
    mObject := TJSONObject.Create;
    mObject.AddPair('name', mColumn.Name);
    if mColumn.List then
    begin
      mObject.AddPair('list', TJSONBool.Create(True));
    end;
    Result.AddElement(mObject);
  end;
end;

class function TLspSettingsCommands.Check(const AArguments: TJSONArray): TJSONObject;
var
  Issues, Misplaced: TArray<TConfigurationIssue>;
  Scope: TConfigurationScope;
  Issue: TConfigurationIssue;
  Items: TJSONArray;
  Item: TJSONObject;
  Valid: Boolean;
begin
  TConfigurationParser.Parse(FirstString(AArguments), Issues);
  Scope := TConfigurationScope.Project;
  if (AArguments <> nil) and (AArguments.Count > 1) and (AArguments.Items[1] is TJSONString) and
    SameText(AArguments.Items[1].Value, 'global') then
  begin
    Scope := TConfigurationScope.Global;
  end;
  TConfigurationScopes.Filter(FirstString(AArguments), Scope, Misplaced);
  Issues := Issues + Misplaced;
  Items := TJSONArray.Create;
  Valid := True;
  for Issue in Issues do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('line', TJSONNumber.Create(Issue.Range.StartPos.Line));
    Item.AddPair('character', TJSONNumber.Create(Issue.Range.StartPos.Character));
    Item.AddPair('message', Issue.Message);
    Item.AddPair('error', TJSONBool.Create(Issue.IsError));
    Items.AddElement(Item);
    if Issue.IsError then
    begin
      Valid := False;
    end;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('valid', TJSONBool.Create(Valid));
  Result.AddPair('issues', Items);
end;

class function TLspSettingsCommands.CatalogEntries(const AArguments: TJSONArray): TArray<TRuleCatalogEntry>;
var
  Catalog: TRuleCatalog;
begin
  Catalog := TRuleCatalog.Create(RuleCatalogBaseJson, RuleCatalogOverlayJson(FirstString(AArguments)));
  try
    Result := Catalog.Entries;
  finally
    Catalog.Free;
  end;
end;

class function TLspSettingsCommands.Catalog(const AEntries: TArray<TRuleCatalogEntry>;
  const AGlobalFile: string): TJSONObject;
begin
  Result := Catalog(AEntries, AGlobalFile, nil);
end;

/// <summary>Option einer Regel mit Art, Spalten, Vorgabe und Beschreibung.</summary>
function OptionJson(const AOption: TRuleOption): TJSONObject;
var
  mDefault: TJSONValue;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', AOption.Name);
  Result.AddPair('type', AOption.Kind);
  if AOption.Columns <> nil then
  begin
    Result.AddPair('columns', ColumnsJson(AOption.Columns));
  end;
  mDefault := nil;
  if AOption.DefaultJson <> '' then
  begin
    mDefault := TJSONObject.ParseJSONValue(AOption.DefaultJson);
  end;
  if mDefault <> nil then
  begin
    Result.AddPair('default', mDefault);
  end;
  Result.AddPair('description', AOption.Description);
end;

function OptionsJson(const AOptions: TArray<TRuleOption>): TJSONArray;
var
  mOption: TRuleOption;
begin
  Result := TJSONArray.Create;
  for mOption in AOptions do
  begin
    Result.AddElement(OptionJson(mOption));
  end;
end;

function StringsJson(const AItems: TArray<string>): TJSONArray;
var
  mItem: string;
begin
  Result := TJSONArray.Create;
  for mItem in AItems do
  begin
    Result.Add(mItem);
  end;
end;

/// <summary>Setzt AName auf true, wenn AValue gilt.</summary>
procedure AddFlag(AObject: TJSONObject; const AName: string; AValue: Boolean);
begin
  if AValue then
  begin
    AObject.AddPair(AName, TJSONBool.Create(True));
  end;
end;

/// <summary>Eintrag einer Regel im Katalog.</summary>
function RuleJson(const AEntry: TRuleCatalogEntry; const AExperimental: TArray<string>): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', AEntry.Id);
  Result.AddPair('name', AEntry.Name);
  Result.AddPair('category', TRuleCatalog.CategoryName(AEntry.Category));
  Result.AddPair('severity', TFindingsOutput.SeverityName(AEntry.DefaultSeverity));
  Result.AddPair('group', TRuleCatalog.GroupName(AEntry.Group));
  Result.AddPair('description', AEntry.Description);
  Result.AddPair('bad', AEntry.Bad);
  Result.AddPair('good', AEntry.Good);
  Result.AddPair('options', OptionsJson(AEntry.Options));
  if AEntry.OverriddenBy <> nil then
  begin
    Result.AddPair('overriddenBy', StringsJson(AEntry.OverriddenBy));
  end;
  AddFlag(Result, 'experimental', MatchText(AEntry.Id, AExperimental));
  // Sammelkorrektur (#1352): Das Plugin bietet „Alle sicheren Treffer korrigieren …“ nur dafür an.
  AddFlag(Result, 'safeFix', AEntry.SafeFix);
end;

class function TLspSettingsCommands.Catalog(const AEntries: TArray<TRuleCatalogEntry>; const AGlobalFile: string;
  const AExperimental: TArray<string>): TJSONObject;
var
  mRules: TJSONArray;
  mEntry: TRuleCatalogEntry;
begin
  mRules := TJSONArray.Create;
  for mEntry in AEntries do
  begin
    mRules.AddElement(RuleJson(mEntry, AExperimental));
  end;
  Result := TJSONObject.Create;
  Result.AddPair('rules', mRules);
  Result.AddPair('globalFile', AGlobalFile);
  Result.AddPair('version', TProductVersion.Version);
end;

end.
