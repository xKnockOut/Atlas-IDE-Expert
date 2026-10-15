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
//                                           Kategorie und Vorgabe sowie Pfad
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
    /// <summary>{"rules": [{"id", "name", "category", "severity"}], "globalFile", "version"}.</summary>
    class function Catalog(const AEntries: TArray<TRuleCatalogEntry>; const AGlobalFile: string): TJSONObject; static;
    /// <summary>Katalog in der Sprache aus AArguments[0] ("de", "en"; sonst englisch).</summary>
    class function CatalogEntries(const AArguments: TJSONArray): TArray<TRuleCatalogEntry>; static;
  end;

implementation

uses
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
var
  Rules: TJSONArray;
  Rule: TJSONObject;
  Entry: TRuleCatalogEntry;
begin
  Rules := TJSONArray.Create;
  for Entry in AEntries do
  begin
    Rule := TJSONObject.Create;
    Rule.AddPair('id', Entry.Id);
    Rule.AddPair('name', Entry.Name);
    Rule.AddPair('category', TRuleCatalog.CategoryName(Entry.Category));
    Rule.AddPair('severity', TFindingsOutput.SeverityName(Entry.DefaultSeverity));
    Rules.AddElement(Rule);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('rules', Rules);
  Result.AddPair('globalFile', AGlobalFile);
  Result.AddPair('version', TProductVersion.Version);
end;

end.
