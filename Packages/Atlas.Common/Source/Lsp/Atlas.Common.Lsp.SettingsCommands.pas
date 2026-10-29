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
//                                           „experimentell“ (#909) sowie Pfad
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
    /// "options": [{"name", "type", "columns" (nur object-list), "default", "description"}], "experimental"}],
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
    Result := AArguments.Items[0].Value;
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
      mObject.AddPair('list', TJSONBool.Create(True));
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
    Scope := TConfigurationScope.Global;
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
      Valid := False;
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

class function TLspSettingsCommands.Catalog(const AEntries: TArray<TRuleCatalogEntry>; const AGlobalFile: string;
  const AExperimental: TArray<string>): TJSONObject;
var
  Rules, Options, Overrides: TJSONArray;
  Rule, OptionObject: TJSONObject;
  Entry: TRuleCatalogEntry;
  Option: TRuleOption;
  DefaultValue: TJSONValue;
  Id: string;
  Experimental: Boolean;
begin
  Rules := TJSONArray.Create;
  for Entry in AEntries do
  begin
    Rule := TJSONObject.Create;
    Rule.AddPair('id', Entry.Id);
    Rule.AddPair('name', Entry.Name);
    Rule.AddPair('category', TRuleCatalog.CategoryName(Entry.Category));
    Rule.AddPair('severity', TFindingsOutput.SeverityName(Entry.DefaultSeverity));
    Rule.AddPair('group', TRuleCatalog.GroupName(Entry.Group));
    Rule.AddPair('description', Entry.Description);
    Rule.AddPair('bad', Entry.Bad);
    Rule.AddPair('good', Entry.Good);
    Options := TJSONArray.Create;
    for Option in Entry.Options do
    begin
      OptionObject := TJSONObject.Create;
      OptionObject.AddPair('name', Option.Name);
      OptionObject.AddPair('type', Option.Kind);
      if Option.Columns <> nil then
        OptionObject.AddPair('columns', ColumnsJson(Option.Columns));
      DefaultValue := nil;
      if Option.DefaultJson <> '' then
        DefaultValue := TJSONObject.ParseJSONValue(Option.DefaultJson);
      if DefaultValue <> nil then
        OptionObject.AddPair('default', DefaultValue);
      OptionObject.AddPair('description', Option.Description);
      Options.AddElement(OptionObject);
    end;
    Rule.AddPair('options', Options);
    if Entry.OverriddenBy <> nil then
    begin
      Overrides := TJSONArray.Create;
      for Id in Entry.OverriddenBy do
        Overrides.Add(Id);
      Rule.AddPair('overriddenBy', Overrides);
    end;
    Experimental := False;
    for Id in AExperimental do
      if SameText(Id, Entry.Id) then
        Experimental := True;
    if Experimental then
      Rule.AddPair('experimental', TJSONBool.Create(True));
    Rules.AddElement(Rule);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('rules', Rules);
  Result.AddPair('globalFile', AGlobalFile);
  Result.AddPair('version', TProductVersion.Version);
end;

end.
