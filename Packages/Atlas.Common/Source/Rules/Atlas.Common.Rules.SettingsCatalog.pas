unit Atlas.Common.Rules.SettingsCatalog;

// Regeln des Katalogs für die Einstellungsseite des IDE-Plugins (#227, Befehl atlas.server.settingsCatalog): Name,
// Kategorie, Vorgabe, Gruppe, Beschreibung, Beispiele, Optionen und die Kennzeichen „experimentell“ (#909) und
// „Sammelkorrektur“ (safeFix, #1352), dazu Pfad der globalen Datei und Version des Servers. Die Komposition ruft es
// auf; die Erklärungen der Compilermeldungen ergänzt Atlas.Common.Lsp.SettingsCommands.

interface

uses
  System.JSON,
  Atlas.Common.Rules.Catalog;

type
  TRuleSettingsCatalog = class
  public
    /// <summary>{"rules": [{"id", "name", "category", "severity", "group", "description", "bad", "good",
    /// "options": [{"name", "type", "columns" (nur object-list), "default", "description"}], "experimental",
    /// "safeFix" (#1352)}],
    /// "globalFile", "version"}. "experimental" (#834, #909) kommt aus "profiles" des Regelkatalogs (#145).
    /// </summary>
    class function Json(const AEntries: TArray<TRuleCatalogEntry>; const AGlobalFile: string): TJSONObject; static;
    /// <summary>Katalog in der Sprache ALanguage ("de", "en"; sonst englisch).</summary>
    class function Entries(const ALanguage: string): TArray<TRuleCatalogEntry>; static;
  end;

implementation

uses
  System.Generics.Collections, // Inline-Funktionen von TJSONArray (H2443)
  Atlas.Common.Rules.Catalog.Data,
  Atlas.Common.Findings.Output,
  Atlas.Common.Product.Version,
  Atlas.Text.Json;

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

/// <summary>Eintrag einer Regel im Katalog.</summary>
function RuleJson(const AEntry: TRuleCatalogEntry): TJSONObject;
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
    Result.AddPair('overriddenBy', TJsonBuild.Strings(AEntry.OverriddenBy));
  end;
  TJsonBuild.AddFlag(Result, 'experimental', AEntry.Experimental);
  // Sammelkorrektur (#1352): Das Plugin bietet „Alle sicheren Treffer korrigieren …“ nur dafür an.
  TJsonBuild.AddFlag(Result, 'safeFix', AEntry.SafeFix);
end;

{ TRuleSettingsCatalog }

class function TRuleSettingsCatalog.Json(const AEntries: TArray<TRuleCatalogEntry>;
  const AGlobalFile: string): TJSONObject;
var
  mRules: TJSONArray;
  mEntry: TRuleCatalogEntry;
begin
  mRules := TJSONArray.Create;
  for mEntry in AEntries do
  begin
    mRules.AddElement(RuleJson(mEntry));
  end;
  Result := TJSONObject.Create;
  Result.AddPair('rules', mRules);
  Result.AddPair('globalFile', AGlobalFile);
  Result.AddPair('version', TProductVersion.cVersion);
end;

class function TRuleSettingsCatalog.Entries(const ALanguage: string): TArray<TRuleCatalogEntry>;
var
  mCatalog: TRuleCatalog;
begin
  mCatalog := TRuleCatalog.Create(RuleCatalogBaseJson, RuleCatalogOverlayJson(ALanguage));
  try
    Result := mCatalog.Entries;
  finally
    mCatalog.Free;
  end;
end;

end.
