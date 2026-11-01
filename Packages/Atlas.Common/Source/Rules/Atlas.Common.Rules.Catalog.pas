unit Atlas.Common.Rules.Catalog;

// Regelkatalog: einzige Quelle für Name, Kategorie, Beschreibung und Beispiele
// jeder Prüfregel (#145). Grundlage ist Katalog\regelkatalog.json (englisch),
// Übersetzungen liegen als Overlay daneben (regelkatalog.de.json) und
// überschreiben nur Name und Beschreibung. SARIF nutzt immer den englischen
// Katalog, damit Fingerabdrücke in GitHub Code Scanning stabil bleiben.
// "compilerCodes" nennt Compilermeldungen, denen eine Regel entspricht (#938),
// "level" die Stufe einer Regel der Gruppe „Compiler vorab“ (#1024): A = Parser
// genügt, B = Namensauflösung über Units, T = braucht Ausdruckstypen; nur
// Stufe T lässt sich über "group:compiler": {"typeLevel": "off"} abschalten.
// "overriddenBy" nennt Gegenregeln: Ist eine davon an, meldet die Regel nichts
// (#1025, z. B. redundant-begin-end bei missing-begin-end); Rules.Engine.
// "safeFix" (#1352) gibt die als sicher markierten Korrekturen der Regel für
// die Sammelkorrektur frei (--fix, fix_findings, „Alle sicheren Treffer
// korrigieren …“); ohne das Feld korrigiert sie nur einzeln.

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

  /// <summary>Spalte einer Option der Art "object-list" (#1133): Schlüssel der Objekte.</summary>
  TRuleOptionColumn = record
    Name: string;
    /// <summary>Der Wert ist eine Liste von Texten.</summary>
    List: Boolean;
  end;

  /// <summary>Eine Option einer Regel in "rules.&lt;id&gt;" (#909).</summary>
  TRuleOption = record
    Name: string;
    /// <summary>"integer", "boolean", "string", "string-list", "number-list" (#937), "object-list" (#1133) oder
    /// "json".</summary>
    Kind: string;
    /// <summary>Nur "object-list": Spalten der Tabelle in der Reihenfolge der Seite Prüfregeln.</summary>
    Columns: TArray<TRuleOptionColumn>;
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
    /// <summary>Stufe "A", "B" oder "T" (#1024); '' ohne Angabe.</summary>
    Level: string;
    /// <summary>Gegenregeln (#1025): Ist eine davon an, meldet diese Regel nichts; nil = keine.</summary>
    OverriddenBy: TArray<string>;
    /// <summary>Sichere Korrekturen dürfen in die Sammelkorrektur (#1352, "safeFix").</summary>
    SafeFix: Boolean;
  end;

  ERuleCatalog = class(Exception);

  TRuleCatalog = class
  private class var
    FShared: TRuleCatalog;
  private
    FEntries: TList<TRuleCatalogEntry>;
    // Kennung (klein) -> Position des ersten Eintrags in FEntries; IndexOf lief linear über alle Regeln (#1342).
    FPositions: TDictionary<string, Integer>;
    procedure ParseBase(const AJson: string);
    procedure ApplyOverlay(const AJson: string);
    function IndexOf(const AId: string): Integer;
  public
    /// <summary>Liest den Katalog; AOverlay darf leer sein. Löst ERuleCatalog bei ungültigem Inhalt aus.</summary>
    constructor Create(const ABase, AOverlay: string); overload;
    /// <summary>Wie oben ohne Overlay (AOverlay = '').</summary>
    constructor Create(const ABase: string); overload;
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
  OptionKinds: array[0..6] of string = ('integer', 'boolean', 'string', 'string-list', 'number-list', 'object-list',
    'json');

var
  SharedLock: TCriticalSection;

function TryParseSeverity(const AText: string; out ASeverity: TRuleSeverity): Boolean;
begin
  Result := True;
  if SameText(AText, 'error') then
  begin
    ASeverity := TRuleSeverity.Error;
  end
  else if SameText(AText, 'warning') then
  begin
    ASeverity := TRuleSeverity.Warning;
  end
  else if SameText(AText, 'information') then
  begin
    ASeverity := TRuleSeverity.Information;
  end
  else if SameText(AText, 'hint') then
  begin
    ASeverity := TRuleSeverity.Hint;
  end
  else
  begin
    Result := False;
  end;
end;

function StringOf(AObject: TJSONObject; const AName: string): string;
var
  Value: TJSONValue;
begin
  Value := AObject.GetValue(AName);
  if Value is TJSONString then
  begin
    Result := TJSONString(Value).Value;
  end
  else
  begin
    Result := '';
  end;
end;

/// <summary>Spalten "columns" einer Option der Art "object-list" (#1133).</summary>
function ColumnsOf(AItem: TJSONObject; const AId, AName: string): TArray<TRuleOptionColumn>;
var
  mValue, mItem, mList: TJSONValue;
  mColumn: TRuleOptionColumn;
begin
  Result := nil;
  mValue := AItem.GetValue('columns');
  if not (mValue is TJSONArray) or (TJSONArray(mValue).Count = 0) then
  begin
    raise ERuleCatalog.CreateFmt('Regelkatalog: Option "%s" von "%s" braucht "columns"', [AName, AId]);
  end;
  for mItem in TJSONArray(mValue) do
  begin
    if not (mItem is TJSONObject) or (StringOf(TJSONObject(mItem), 'name') = '') then
    begin
      raise ERuleCatalog.CreateFmt('Regelkatalog: Spalte von "%s" in "%s" ohne "name"', [AName, AId]);
    end;
    mColumn.Name := StringOf(TJSONObject(mItem), 'name');
    mList := TJSONObject(mItem).GetValue('list');
    mColumn.List := (mList is TJSONBool) and TJSONBool(mList).AsBoolean;
    Result := Result + [mColumn];
  end;
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
  begin
    Exit;
  end;
  if not (Value is TJSONArray) then
  begin
    raise ERuleCatalog.CreateFmt('Regelkatalog: "%s" hat ungültige "options"', [AId]);
  end;
  for Item in TJSONArray(Value) do
  begin
    if not (Item is TJSONObject) then
    begin
      raise ERuleCatalog.CreateFmt('Regelkatalog: Option von "%s" ist kein Objekt', [AId]);
    end;
    Option := Default(TRuleOption);
    Option.Name := StringOf(TJSONObject(Item), 'name');
    Option.Kind := StringOf(TJSONObject(Item), 'type');
    Option.Description := StringOf(TJSONObject(Item), 'description');
    if Option.Name = '' then
    begin
      raise ERuleCatalog.CreateFmt('Regelkatalog: Option von "%s" ohne "name"', [AId]);
    end;
    Known := False;
    for Kind in OptionKinds do
    begin
      if Kind = Option.Kind then
      begin
        Known := True;
      end;
    end;
    if not Known then
    begin
      raise ERuleCatalog.CreateFmt('Regelkatalog: Option "%s" von "%s" hat keinen gültigen Typ', [Option.Name, AId]);
    end;
    if Option.Kind = 'object-list' then
    begin
      Option.Columns := ColumnsOf(TJSONObject(Item), AId, Option.Name);
    end;
    DefaultValue := TJSONObject(Item).GetValue('default');
    if DefaultValue <> nil then
    begin
      Option.DefaultJson := DefaultValue.ToJSON;
    end;
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
  begin
    for Index := 2 to 5 do
    begin
      if not CharInSet(ACode[Index], ['0'..'9']) then
      begin
        Exit(False);
      end;
    end;
  end;
end;

function CompilerCodesOf(AItem: TJSONObject; const AId: string): TArray<string>;
var
  Value, Item: TJSONValue;
begin
  Result := nil;
  Value := AItem.GetValue('compilerCodes');
  if Value = nil then
  begin
    Exit;
  end;
  if not (Value is TJSONArray) then
  begin
    raise ERuleCatalog.CreateFmt('Regelkatalog: "%s" hat ungültige "compilerCodes"', [AId]);
  end;
  for Item in TJSONArray(Value) do
  begin
    if not (Item is TJSONString) or not IsCompilerCode(TJSONString(Item).Value) then
    begin
      raise ERuleCatalog.CreateFmt('Regelkatalog: "%s" hat einen ungültigen Compilercode', [AId]);
    end;
    Result := Result + [TJSONString(Item).Value];
  end;
end;

function OverriddenByOf(AItem: TJSONObject; const AId: string): TArray<string>;
var
  Value, Item: TJSONValue;
begin
  Result := nil;
  Value := AItem.GetValue('overriddenBy');
  if Value = nil then
  begin
    Exit;
  end;
  if not (Value is TJSONArray) then
  begin
    raise ERuleCatalog.CreateFmt('Regelkatalog: "%s" hat ungültige "overriddenBy"', [AId]);
  end;
  for Item in TJSONArray(Value) do
  begin
    if not (Item is TJSONString) or (Item is TJSONNumber) or (TJSONString(Item).Value = '') then
    begin
      raise ERuleCatalog.CreateFmt('Regelkatalog: "%s" hat eine ungültige Gegenregel', [AId]);
    end;
    Result := Result + [TJSONString(Item).Value];
  end;
end;

function RulesOf(ARoot: TJSONValue): TJSONArray;
var
  Value: TJSONValue;
begin
  if not (ARoot is TJSONObject) then
  begin
    raise ERuleCatalog.Create('Regelkatalog: Objekt erwartet');
  end;
  Value := TJSONObject(ARoot).GetValue('rules');
  if not (Value is TJSONArray) then
  begin
    raise ERuleCatalog.Create('Regelkatalog: "rules" fehlt');
  end;
  Result := TJSONArray(Value);
end;

{ TRuleCatalog }

constructor TRuleCatalog.Create(const ABase: string);
begin
  Create(ABase, '');
end;

constructor TRuleCatalog.Create(const ABase, AOverlay: string);
begin
  inherited Create;
  FEntries := TList<TRuleCatalogEntry>.Create;
  FPositions := TDictionary<string, Integer>.Create;
  ParseBase(ABase);
  if AOverlay <> '' then
  begin
    ApplyOverlay(AOverlay);
  end;
end;

destructor TRuleCatalog.Destroy;
begin
  FPositions.Free;
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
      begin
        raise ERuleCatalog.Create('Regelkatalog: Eintrag ist kein Objekt');
      end;
      Item := TJSONObject(Rules.Items[I]);
      Entry := Default(TRuleCatalogEntry);
      Entry.Id := StringOf(Item, 'id');
      if Entry.Id = '' then
      begin
        raise ERuleCatalog.Create('Regelkatalog: Eintrag ohne "id"');
      end;
      if IndexOf(Entry.Id) >= 0 then
      begin
        raise ERuleCatalog.CreateFmt('Regelkatalog: "%s" doppelt', [Entry.Id]);
      end;
      Entry.Name := StringOf(Item, 'name');
      Entry.Description := StringOf(Item, 'description');
      Entry.Bad := StringOf(Item, 'bad');
      Entry.Good := StringOf(Item, 'good');
      if not TryParseCategory(StringOf(Item, 'category'), Entry.Category) then
      begin
        raise ERuleCatalog.CreateFmt('Regelkatalog: "%s" hat keine gültige Kategorie', [Entry.Id]);
      end;
      if not TryParseSeverity(StringOf(Item, 'severity'), Entry.DefaultSeverity) then
      begin
        raise ERuleCatalog.CreateFmt('Regelkatalog: "%s" hat keinen gültigen Schweregrad', [Entry.Id]);
      end;
      if Item.GetValue('group') = nil then
      begin
        Entry.Group := GroupOfCategory(Entry.Category);
      end
      else if not TryParseGroup(StringOf(Item, 'group'), Entry.Group) then
      begin
        raise ERuleCatalog.CreateFmt('Regelkatalog: "%s" hat keine gültige Gruppe', [Entry.Id]);
      end;
      Entry.Options := OptionsOf(Item, Entry.Id);
      Entry.CompilerCodes := CompilerCodesOf(Item, Entry.Id);
      Entry.Level := StringOf(Item, 'level');
      if (Entry.Level <> '') and (Entry.Level <> 'A') and (Entry.Level <> 'B') and (Entry.Level <> 'T') then
      begin
        raise ERuleCatalog.CreateFmt('Regelkatalog: "%s" hat eine ungültige Stufe "%s"', [Entry.Id, Entry.Level]);
      end;
      Entry.OverriddenBy := OverriddenByOf(Item, Entry.Id);
      Entry.SafeFix := False;
      if Item.GetValue('safeFix') is TJSONBool then
      begin
        Entry.SafeFix := TJSONBool(Item.GetValue('safeFix')).AsBoolean;
      end
      else if Item.GetValue('safeFix') <> nil then
      begin
        raise ERuleCatalog.CreateFmt('Regelkatalog: "%s" hat ein ungültiges "safeFix"', [Entry.Id]);
      end;
      FEntries.Add(Entry);
      if not FPositions.ContainsKey(LowerCase(Entry.Id)) then
      begin
        FPositions.Add(LowerCase(Entry.Id), FEntries.Count - 1);
      end;
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
      begin
        Continue;
      end;
      Item := TJSONObject(Rules.Items[I]);
      Index := IndexOf(StringOf(Item, 'id'));
      // Übersetzungen unbekannter Regeln sind harmlos und werden übergangen.
      if Index < 0 then
      begin
        Continue;
      end;
      Entry := FEntries[Index];
      Text := StringOf(Item, 'name');
      if Text <> '' then
      begin
        Entry.Name := Text;
      end;
      Text := StringOf(Item, 'description');
      if Text <> '' then
      begin
        Entry.Description := Text;
      end;
      // Beschreibungen der Optionen nach Namen (#909); unbekannte Optionen bleiben unbeachtet.
      Options := Item.GetValue('options');
      if Options is TJSONArray then
      begin
        for Option in TJSONArray(Options) do
        begin
          if Option is TJSONObject then
          begin
            Name := StringOf(TJSONObject(Option), 'name');
            Text := StringOf(TJSONObject(Option), 'description');
            if Text <> '' then
            begin
              for OptionIndex := 0 to High(Entry.Options) do
              begin
                if SameText(Entry.Options[OptionIndex].Name, Name) then
                begin
                  Entry.Options[OptionIndex].Description := Text;
                end;
              end;
            end;
          end;
        end;
      end;
      FEntries[Index] := Entry;
    end;
  finally
    Root.Free;
  end;
end;

function TRuleCatalog.IndexOf(const AId: string): Integer;
begin
  if not FPositions.TryGetValue(LowerCase(AId), Result) then
  begin
    Result := -1;
  end;
end;

function TRuleCatalog.TryFind(const AId: string; out AEntry: TRuleCatalogEntry): Boolean;
var
  Index: Integer;
begin
  Index := IndexOf(AId);
  Result := Index >= 0;
  if Result then
  begin
    AEntry := FEntries[Index];
  end
  else
  begin
    AEntry := Default(TRuleCatalogEntry);
  end;
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
  begin
    Result := Result + ': ' + AEntry.Name;
  end;
  if AEntry.Description <> '' then
  begin
    Result := Result + ALineBreak + AEntry.Description;
  end;
  if AEntry.Bad <> '' then
  begin
    Result := Result + ALineBreak + ALineBreak + 'Falsch:' + ALineBreak + AEntry.Bad;
  end;
  if AEntry.Good <> '' then
  begin
    Result := Result + ALineBreak + ALineBreak + 'Richtig:' + ALineBreak + AEntry.Good;
  end;
  if AEntry.CompilerCodes <> nil then
  begin
    Result := Result + ALineBreak + ALineBreak + 'Entspricht der Compilermeldung ' +
      string.Join(', ', AEntry.CompilerCodes) + '.';
  end;
  if AEntry.OverriddenBy <> nil then
  begin
    Result := Result + ALineBreak + ALineBreak + 'Schweigt, solange ' + string.Join(' oder ', AEntry.OverriddenBy) +
      ' an ist.';
  end;
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
  begin
    if SameText(AText, CategoryNames[Category]) then
    begin
      ACategory := Category;
      Exit(True);
    end;
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
  begin
    if SameText(AText, GroupNames[Group]) then
    begin
      AGroup := Group;
      Exit(True);
    end;
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
    begin
      FShared := TRuleCatalog.Create(RuleCatalogBaseJson);
    end;
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
