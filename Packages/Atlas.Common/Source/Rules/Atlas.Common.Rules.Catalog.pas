unit Atlas.Common.Rules.Catalog;

// Regelkatalog: einzige Quelle für Name, Kategorie, Beschreibung und Beispiele
// jeder Prüfregel (#145). Grundlage ist Katalog\regelkatalog.json (englisch),
// Übersetzungen liegen als Overlay daneben (regelkatalog.de.json) und
// überschreiben nur Name und Beschreibung. SARIF nutzt immer den englischen
// Katalog, damit Fingerabdrücke in GitHub Code Scanning stabil bleiben.
// "compilerCodes" nennt Compilermeldungen, denen eine Regel entspricht (#938).

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Configuration.Contract;

type
  TRuleCategory = (Bug, Vulnerability, CodeSmell, SecurityHotspot);
  /// <summary>Gruppe der Einstellungsseite und des Fensters „Atlas-Prüfung“ (#909).</summary>
  TRuleGroup = (FindBugs, Exceptions, Threads, Database, Compiler, Robustness, Performance, Security, Components,
    Forms, Architecture, Style, Packages, Internal);

  /// <summary>Eine Option einer Regel in "rules.&lt;id&gt;" (#909).</summary>
  TRuleOption = record
    Name: string;
    /// <summary>"integer", "boolean", "string", "string-list", "number-list" (#937) oder "json".</summary>
    Kind: string;
    /// <summary>Vorgabe als JSON-Text, z. B. 60, ["TODO"] oder "".</summary>
    DefaultJson: string;
    Description: string;
  end;

  /// <summary>Ein Eintrag des Regelkatalogs.</summary>
  TRuleCatalogEntry = record
    Id: string;
    Name: string;
    Category: TRuleCategory;
    DefaultSeverity: TRuleSeverity;
    Description: string;
    /// <summary>Beispiel mit Treffer.</summary>
    Bad: string;
    /// <summary>Korrigiertes Beispiel.</summary>
    Good: string;
    Group: TRuleGroup;
    Options: TArray<TRuleOption>;
    /// <summary>Compilermeldungen, denen die Regel entspricht, z. B. F2069 (#938); nil = keine.</summary>
    CompilerCodes: TArray<string>;
  end;

  ERuleCatalog = class(Exception);

  TRuleCatalog = class
  private class var
    FShared: TRuleCatalog;
  private
    FEntries: TList<TRuleCatalogEntry>;
    procedure ParseBase(const AJson: string);
    procedure ApplyOverlay(const AJson: string);
    function IndexOf(const AId: string): Integer;
  public
    /// <summary>Liest den Katalog; AOverlay darf leer sein. Löst ERuleCatalog bei ungültigem Inhalt aus.</summary>
    constructor Create(const ABase: string; const AOverlay: string = '');
    destructor Destroy; override;
    function TryFind(const AId: string; out AEntry: TRuleCatalogEntry): Boolean;
    function Entries: TArray<TRuleCatalogEntry>;
    /// <summary>Link zur Benutzerdokumentation der Regel.</summary>
    class function HelpUri(const AId: string): string; static;
    /// <summary>Ausführliche Erklärung für /explain (#300): Kennung und Name, Beschreibung, Beispiel falsch und
    /// richtig, Link zur Doku; Zeilen mit ALineBreak getrennt.</summary>
    class function Explanation(const AEntry: TRuleCatalogEntry; const ALineBreak: string): string; static;
    class function CategoryName(ACategory: TRuleCategory): string; static;
    class function TryParseCategory(const AText: string; out ACategory: TRuleCategory): Boolean; static;
    /// <summary>Kennung der Gruppe in JSON, z. B. "find-bugs".</summary>
    class function GroupName(AGroup: TRuleGroup): string; static;
    /// <summary>Schlüssel des Hauptschalters einer Gruppe in "rules" (#909): "group:find-bugs"; "off" schaltet alle
    /// Regeln der Gruppe ab.</summary>
    class function GroupKey(AGroup: TRuleGroup): string; static;
    class function TryParseGroup(const AText: string; out AGroup: TRuleGroup): Boolean; static;
    /// <summary>Gruppe einer Regel ohne Angabe: nach der Kategorie.</summary>
    class function GroupOfCategory(ACategory: TRuleCategory): TRuleGroup; static;
    /// <summary>Eingebetteter englischer Katalog, einmal je Prozess gelesen; nicht freigeben.</summary>
    class function Shared: TRuleCatalog; static;
  end;

const
  RuleDocumentationBaseUri = 'https://github.com/xKnockOut/Atlas-IDE-Expert/blob/main/docs/Regeln.md#';

implementation

uses
  System.JSON,
  System.SyncObjs,
  Atlas.Common.Rules.Catalog.Data;

const
  CategoryNames: array[TRuleCategory] of string = ('bug', 'vulnerability', 'code-smell', 'security-hotspot');
  GroupNames: array[TRuleGroup] of string = ('find-bugs', 'exceptions', 'threads', 'database', 'compiler',
    'robustness', 'performance', 'security', 'components', 'forms', 'architecture', 'style', 'packages', 'internal');
  OptionKinds: array[0..5] of string = ('integer', 'boolean', 'string', 'string-list', 'number-list', 'json');

var
  SharedLock: TCriticalSection;

function TryParseSeverity(const AText: string; out ASeverity: TRuleSeverity): Boolean;
begin
  Result := True;
  if SameText(AText, 'error') then
    ASeverity := TRuleSeverity.Error
  else if SameText(AText, 'warning') then
    ASeverity := TRuleSeverity.Warning
  else if SameText(AText, 'information') then
    ASeverity := TRuleSeverity.Information
  else if SameText(AText, 'hint') then
    ASeverity := TRuleSeverity.Hint
  else
    Result := False;
end;

function StringOf(AObject: TJSONObject; const AName: string): string;
var
  Value: TJSONValue;
begin
  Value := AObject.GetValue(AName);
  if Value is TJSONString then
    Result := TJSONString(Value).Value
  else
    Result := '';
end;

function OptionsOf(AItem: TJSONObject; const AId: string): TArray<TRuleOption>;
var
  Value, DefaultValue: TJSONValue;
  Item: TJSONValue;
  Option: TRuleOption;
  Known: Boolean;
  Kind: string;
begin
  Result := nil;
  Value := AItem.GetValue('options');
  if Value = nil then
    Exit;
  if not (Value is TJSONArray) then
    raise ERuleCatalog.CreateFmt('Regelkatalog: "%s" hat ungültige "options"', [AId]);
  for Item in TJSONArray(Value) do
  begin
    if not (Item is TJSONObject) then
      raise ERuleCatalog.CreateFmt('Regelkatalog: Option von "%s" ist kein Objekt', [AId]);
    Option := Default(TRuleOption);
    Option.Name := StringOf(TJSONObject(Item), 'name');
    Option.Kind := StringOf(TJSONObject(Item), 'type');
    Option.Description := StringOf(TJSONObject(Item), 'description');
    if Option.Name = '' then
      raise ERuleCatalog.CreateFmt('Regelkatalog: Option von "%s" ohne "name"', [AId]);
    Known := False;
    for Kind in OptionKinds do
      if Kind = Option.Kind then
        Known := True;
    if not Known then
      raise ERuleCatalog.CreateFmt('Regelkatalog: Option "%s" von "%s" hat keinen gültigen Typ', [Option.Name, AId]);
    DefaultValue := TJSONObject(Item).GetValue('default');
    if DefaultValue <> nil then
      Option.DefaultJson := DefaultValue.ToJSON;
    Result := Result + [Option];
  end;
end;

function IsCompilerCode(const ACode: string): Boolean;
var
  Index: Integer;
begin
  // X wie X1008 (#1040): Meldungen, die dcc als Warnung ausgibt.
  Result := (Length(ACode) = 5) and CharInSet(ACode[1], ['E', 'F', 'W', 'H', 'X']);
  if Result then
    for Index := 2 to 5 do
      if not CharInSet(ACode[Index], ['0'..'9']) then
        Exit(False);
end;

function CompilerCodesOf(AItem: TJSONObject; const AId: string): TArray<string>;
var
  Value, Item: TJSONValue;
begin
  Result := nil;
  Value := AItem.GetValue('compilerCodes');
  if Value = nil then
    Exit;
  if not (Value is TJSONArray) then
    raise ERuleCatalog.CreateFmt('Regelkatalog: "%s" hat ungültige "compilerCodes"', [AId]);
  for Item in TJSONArray(Value) do
  begin
    if not (Item is TJSONString) or not IsCompilerCode(TJSONString(Item).Value) then
      raise ERuleCatalog.CreateFmt('Regelkatalog: "%s" hat einen ungültigen Compilercode', [AId]);
    Result := Result + [TJSONString(Item).Value];
  end;
end;

function RulesOf(ARoot: TJSONValue): TJSONArray;
var
  Value: TJSONValue;
begin
  if not (ARoot is TJSONObject) then
    raise ERuleCatalog.Create('Regelkatalog: Objekt erwartet');
  Value := TJSONObject(ARoot).GetValue('rules');
  if not (Value is TJSONArray) then
    raise ERuleCatalog.Create('Regelkatalog: "rules" fehlt');
  Result := TJSONArray(Value);
end;

{ TRuleCatalog }

constructor TRuleCatalog.Create(const ABase, AOverlay: string);
begin
  inherited Create;
  FEntries := TList<TRuleCatalogEntry>.Create;
  ParseBase(ABase);
  if AOverlay <> '' then
    ApplyOverlay(AOverlay);
end;

destructor TRuleCatalog.Destroy;
begin
  FEntries.Free;
  inherited;
end;

procedure TRuleCatalog.ParseBase(const AJson: string);
var
  Root: TJSONValue;
  Rules: TJSONArray;
  I: Integer;
  Item: TJSONObject;
  Entry: TRuleCatalogEntry;
begin
  Root := TJSONObject.ParseJSONValue(AJson);
  try
    Rules := RulesOf(Root);
    for I := 0 to Rules.Count - 1 do
    begin
      if not (Rules.Items[I] is TJSONObject) then
        raise ERuleCatalog.Create('Regelkatalog: Eintrag ist kein Objekt');
      Item := TJSONObject(Rules.Items[I]);
      Entry := Default(TRuleCatalogEntry);
      Entry.Id := StringOf(Item, 'id');
      if Entry.Id = '' then
        raise ERuleCatalog.Create('Regelkatalog: Eintrag ohne "id"');
      if IndexOf(Entry.Id) >= 0 then
        raise ERuleCatalog.CreateFmt('Regelkatalog: "%s" doppelt', [Entry.Id]);
      Entry.Name := StringOf(Item, 'name');
      Entry.Description := StringOf(Item, 'description');
      Entry.Bad := StringOf(Item, 'bad');
      Entry.Good := StringOf(Item, 'good');
      if not TryParseCategory(StringOf(Item, 'category'), Entry.Category) then
        raise ERuleCatalog.CreateFmt('Regelkatalog: "%s" hat keine gültige Kategorie', [Entry.Id]);
      if not TryParseSeverity(StringOf(Item, 'severity'), Entry.DefaultSeverity) then
        raise ERuleCatalog.CreateFmt('Regelkatalog: "%s" hat keinen gültigen Schweregrad', [Entry.Id]);
      if Item.GetValue('group') = nil then
        Entry.Group := GroupOfCategory(Entry.Category)
      else if not TryParseGroup(StringOf(Item, 'group'), Entry.Group) then
        raise ERuleCatalog.CreateFmt('Regelkatalog: "%s" hat keine gültige Gruppe', [Entry.Id]);
      Entry.Options := OptionsOf(Item, Entry.Id);
      Entry.CompilerCodes := CompilerCodesOf(Item, Entry.Id);
      FEntries.Add(Entry);
    end;
  finally
    Root.Free;
  end;
end;

procedure TRuleCatalog.ApplyOverlay(const AJson: string);
var
  Root: TJSONValue;
  Rules: TJSONArray;
  I, Index, OptionIndex: Integer;
  Item: TJSONObject;
  Entry: TRuleCatalogEntry;
  Text, Name: string;
  Options, Option: TJSONValue;
begin
  Root := TJSONObject.ParseJSONValue(AJson);
  try
    Rules := RulesOf(Root);
    for I := 0 to Rules.Count - 1 do
    begin
      if not (Rules.Items[I] is TJSONObject) then
        Continue;
      Item := TJSONObject(Rules.Items[I]);
      Index := IndexOf(StringOf(Item, 'id'));
      // Übersetzungen unbekannter Regeln sind harmlos und werden übergangen.
      if Index < 0 then
        Continue;
      Entry := FEntries[Index];
      Text := StringOf(Item, 'name');
      if Text <> '' then
        Entry.Name := Text;
      Text := StringOf(Item, 'description');
      if Text <> '' then
        Entry.Description := Text;
      // Beschreibungen der Optionen nach Namen (#909); unbekannte Optionen bleiben unbeachtet.
      Options := Item.GetValue('options');
      if Options is TJSONArray then
        for Option in TJSONArray(Options) do
          if Option is TJSONObject then
          begin
            Name := StringOf(TJSONObject(Option), 'name');
            Text := StringOf(TJSONObject(Option), 'description');
            if Text <> '' then
              for OptionIndex := 0 to High(Entry.Options) do
                if SameText(Entry.Options[OptionIndex].Name, Name) then
                  Entry.Options[OptionIndex].Description := Text;
          end;
      FEntries[Index] := Entry;
    end;
  finally
    Root.Free;
  end;
end;

function TRuleCatalog.IndexOf(const AId: string): Integer;
var
  I: Integer;
begin
  for I := 0 to FEntries.Count - 1 do
    if SameText(FEntries[I].Id, AId) then
      Exit(I);
  Result := -1;
end;

function TRuleCatalog.TryFind(const AId: string; out AEntry: TRuleCatalogEntry): Boolean;
var
  Index: Integer;
begin
  Index := IndexOf(AId);
  Result := Index >= 0;
  if Result then
    AEntry := FEntries[Index]
  else
    AEntry := Default(TRuleCatalogEntry);
end;

function TRuleCatalog.Entries: TArray<TRuleCatalogEntry>;
begin
  Result := FEntries.ToArray;
end;

class function TRuleCatalog.HelpUri(const AId: string): string;
begin
  Result := RuleDocumentationBaseUri + LowerCase(AId);
end;

class function TRuleCatalog.Explanation(const AEntry: TRuleCatalogEntry; const ALineBreak: string): string;
begin
  Result := AEntry.Id;
  if AEntry.Name <> '' then
    Result := Result + ': ' + AEntry.Name;
  if AEntry.Description <> '' then
    Result := Result + ALineBreak + AEntry.Description;
  if AEntry.Bad <> '' then
    Result := Result + ALineBreak + ALineBreak + 'Falsch:' + ALineBreak + AEntry.Bad;
  if AEntry.Good <> '' then
    Result := Result + ALineBreak + ALineBreak + 'Richtig:' + ALineBreak + AEntry.Good;
  if AEntry.CompilerCodes <> nil then
    Result := Result + ALineBreak + ALineBreak + 'Entspricht der Compilermeldung ' +
      string.Join(', ', AEntry.CompilerCodes) + '.';
  Result := Result + ALineBreak + ALineBreak + 'Mehr: ' + HelpUri(AEntry.Id);
end;

class function TRuleCatalog.CategoryName(ACategory: TRuleCategory): string;
begin
  Result := CategoryNames[ACategory];
end;

class function TRuleCatalog.TryParseCategory(const AText: string; out ACategory: TRuleCategory): Boolean;
var
  Category: TRuleCategory;
begin
  for Category := Low(TRuleCategory) to High(TRuleCategory) do
    if SameText(AText, CategoryNames[Category]) then
    begin
      ACategory := Category;
      Exit(True);
    end;
  ACategory := TRuleCategory.Bug;
  Result := False;
end;

class function TRuleCatalog.GroupName(AGroup: TRuleGroup): string;
begin
  Result := GroupNames[AGroup];
end;

class function TRuleCatalog.GroupKey(AGroup: TRuleGroup): string;
begin
  Result := 'group:' + GroupNames[AGroup];
end;

class function TRuleCatalog.TryParseGroup(const AText: string; out AGroup: TRuleGroup): Boolean;
var
  Group: TRuleGroup;
begin
  for Group := Low(TRuleGroup) to High(TRuleGroup) do
    if SameText(AText, GroupNames[Group]) then
    begin
      AGroup := Group;
      Exit(True);
    end;
  AGroup := TRuleGroup.FindBugs;
  Result := False;
end;

class function TRuleCatalog.GroupOfCategory(ACategory: TRuleCategory): TRuleGroup;
begin
  case ACategory of
    TRuleCategory.Vulnerability, TRuleCategory.SecurityHotspot:
      Result := TRuleGroup.Security;
    TRuleCategory.CodeSmell:
      Result := TRuleGroup.Style;
  else
    Result := TRuleGroup.FindBugs;
  end;
end;

class function TRuleCatalog.Shared: TRuleCatalog;
begin
  // Mehrere Prüf-Threads fragen gleichzeitig; gelesen wird nur einmal.
  SharedLock.Acquire;
  try
    if FShared = nil then
      FShared := TRuleCatalog.Create(RuleCatalogBaseJson);
    Result := FShared;
  finally
    SharedLock.Release;
  end;
end;

initialization
  SharedLock := TCriticalSection.Create;

finalization
  FreeAndNil(TRuleCatalog.FShared);
  FreeAndNil(SharedLock);

end.
