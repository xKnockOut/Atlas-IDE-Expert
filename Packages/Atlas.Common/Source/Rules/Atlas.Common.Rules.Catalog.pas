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
    FGerman: TRuleCatalog;
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
    /// <summary>Katalog in der Sprache der Texte (#1458, TAtlasLocale): englisch wie Shared, deutsch mit dem
    /// Overlay regelkatalog.de.json; einmal je Sprache gelesen; nicht freigeben. Für alles, was der Benutzer
    /// liest (Erklärung, Hover); Regel-Engine und SARIF bleiben bei Shared.</summary>
    class function Localized: TRuleCatalog; static;
  end;

const
  RuleDocumentationBaseUri = 'https://github.com/xKnockOut/Atlas-IDE-Expert/blob/main/docs/Regeln.md#';

implementation

uses
  System.JSON,
  System.SyncObjs,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Rules.Catalog.Data;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Erklärung (#300) in beiden Sprachen (#1458).</summary>
  TCatalogText = (Wrong, Right, CompilerCodes, OverriddenBy, OrSeparator, More);

const
  cTexts: array[TCatalogText] of TAtlasText = (
    (De: 'Falsch:'; En: 'Wrong:'),
    (De: 'Richtig:'; En: 'Right:'),
    (De: 'Entspricht der Compilermeldung %s.'; En: 'Corresponds to compiler message %s.'),
    (De: 'Schweigt, solange %s an ist.'; En: 'Silent while %s is on.'),
    (De: ' oder '; En: ' or '),
    (De: 'Mehr: %s'; En: 'More: %s'));

{$SCOPEDENUMS OFF}

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

function IsOptionKind(const AKind: string): Boolean;
var
  mKind: string;
begin
  Result := False;
  for mKind in OptionKinds do
  begin
    if mKind = AKind then
    begin
      Result := True;
    end;
  end;
end;

/// <summary>Eine Option aus "options" von AId; ERuleCatalog ohne Objekt, Namen oder gültigen Typ.</summary>
function OptionOf(AItem: TJSONValue; const AId: string): TRuleOption;
var
  mObject: TJSONObject;
  mDefault: TJSONValue;
begin
  if not (AItem is TJSONObject) then
  begin
    raise ERuleCatalog.CreateFmt('Regelkatalog: Option von "%s" ist kein Objekt', [AId]);
  end;
  mObject := TJSONObject(AItem);
  Result := Default(TRuleOption);
  Result.Name := StringOf(mObject, 'name');
  Result.Kind := StringOf(mObject, 'type');
  Result.Description := StringOf(mObject, 'description');
  if Result.Name = '' then
  begin
    raise ERuleCatalog.CreateFmt('Regelkatalog: Option von "%s" ohne "name"', [AId]);
  end;
  if not IsOptionKind(Result.Kind) then
  begin
    raise ERuleCatalog.CreateFmt('Regelkatalog: Option "%s" von "%s" hat keinen gültigen Typ', [Result.Name, AId]);
  end;
  if Result.Kind = 'object-list' then
  begin
    Result.Columns := ColumnsOf(mObject, AId, Result.Name);
  end;
  mDefault := mObject.GetValue('default');
  if mDefault <> nil then
  begin
    Result.DefaultJson := mDefault.ToJSON;
  end;
end;

function OptionsOf(AItem: TJSONObject; const AId: string): TArray<TRuleOption>;
var
  mValue, mItem: TJSONValue;
begin
  Result := nil;
  mValue := AItem.GetValue('options');
  if mValue = nil then
  begin
    Exit;
  end;
  if not (mValue is TJSONArray) then
  begin
    raise ERuleCatalog.CreateFmt('Regelkatalog: "%s" hat ungültige "options"', [AId]);
  end;
  for mItem in TJSONArray(mValue) do
  begin
    Result := Result + [OptionOf(mItem, AId)];
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

/// <summary>Kategorie, Schweregrad und Gruppe (ohne "group" die der Kategorie) eines Eintrags.</summary>
procedure ClassifyEntry(AItem: TJSONObject; var AEntry: TRuleCatalogEntry);
begin
  if not TRuleCatalog.TryParseCategory(StringOf(AItem, 'category'), AEntry.Category) then
  begin
    raise ERuleCatalog.CreateFmt('Regelkatalog: "%s" hat keine gültige Kategorie', [AEntry.Id]);
  end;
  if not TryParseSeverity(StringOf(AItem, 'severity'), AEntry.DefaultSeverity) then
  begin
    raise ERuleCatalog.CreateFmt('Regelkatalog: "%s" hat keinen gültigen Schweregrad', [AEntry.Id]);
  end;
  AEntry.Group := TRuleCatalog.GroupOfCategory(AEntry.Category);
  if (AItem.GetValue('group') <> nil) and not TRuleCatalog.TryParseGroup(StringOf(AItem, 'group'), AEntry.Group) then
  begin
    raise ERuleCatalog.CreateFmt('Regelkatalog: "%s" hat keine gültige Gruppe', [AEntry.Id]);
  end;
end;

/// <summary>Stufe ("", A, B oder T) und safeFix eines Eintrags.</summary>
procedure ReadLevelAndSafeFix(AItem: TJSONObject; var AEntry: TRuleCatalogEntry);
var
  mSafeFix: TJSONValue;
begin
  AEntry.Level := StringOf(AItem, 'level');
  if (AEntry.Level <> '') and (AEntry.Level <> 'A') and (AEntry.Level <> 'B') and (AEntry.Level <> 'T') then
  begin
    raise ERuleCatalog.CreateFmt('Regelkatalog: "%s" hat eine ungültige Stufe "%s"', [AEntry.Id, AEntry.Level]);
  end;
  mSafeFix := AItem.GetValue('safeFix');
  AEntry.SafeFix := (mSafeFix is TJSONBool) and TJSONBool(mSafeFix).AsBoolean;
  if (mSafeFix <> nil) and not (mSafeFix is TJSONBool) then
  begin
    raise ERuleCatalog.CreateFmt('Regelkatalog: "%s" hat ein ungültiges "safeFix"', [AEntry.Id]);
  end;
end;

/// <summary>Ein Eintrag des Grundkatalogs; ERuleCatalog bei ungültigen Angaben.</summary>
function EntryOf(AItem: TJSONValue): TRuleCatalogEntry;
var
  mObject: TJSONObject;
begin
  if not (AItem is TJSONObject) then
  begin
    raise ERuleCatalog.Create('Regelkatalog: Eintrag ist kein Objekt');
  end;
  mObject := TJSONObject(AItem);
  Result := Default(TRuleCatalogEntry);
  Result.Id := StringOf(mObject, 'id');
  if Result.Id = '' then
  begin
    raise ERuleCatalog.Create('Regelkatalog: Eintrag ohne "id"');
  end;
  Result.Name := StringOf(mObject, 'name');
  Result.Description := StringOf(mObject, 'description');
  Result.Bad := StringOf(mObject, 'bad');
  Result.Good := StringOf(mObject, 'good');
  ClassifyEntry(mObject, Result);
  Result.Options := OptionsOf(mObject, Result.Id);
  Result.CompilerCodes := CompilerCodesOf(mObject, Result.Id);
  Result.OverriddenBy := OverriddenByOf(mObject, Result.Id);
  ReadLevelAndSafeFix(mObject, Result);
end;

/// <summary>Setzt die Beschreibung der Option AName (Groß-/Kleinschreibung egal).</summary>
procedure SetOptionDescription(var AOptions: TArray<TRuleOption>; const AName, AText: string);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AOptions) do
  begin
    if SameText(AOptions[mIndex].Name, AName) then
    begin
      AOptions[mIndex].Description := AText;
    end;
  end;
end;

/// <summary>Beschreibungen der Optionen nach Namen (#909); unbekannte Optionen bleiben unbeachtet.</summary>
procedure TranslateOptions(AOptions: TJSONValue; var ATarget: TArray<TRuleOption>);
var
  mOption: TJSONValue;
  mText: string;
begin
  if not (AOptions is TJSONArray) then
  begin
    Exit;
  end;
  for mOption in TJSONArray(AOptions) do
  begin
    if mOption is TJSONObject then
    begin
      mText := StringOf(TJSONObject(mOption), 'description');
      if mText <> '' then
      begin
        SetOptionDescription(ATarget, StringOf(TJSONObject(mOption), 'name'), mText);
      end;
    end;
  end;
end;

/// <summary>Übernimmt Name, Beschreibung und Optionstexte der Übersetzung AItem; leere Texte bleiben.</summary>
procedure TranslateEntry(AItem: TJSONObject; var AEntry: TRuleCatalogEntry);
var
  mText: string;
begin
  mText := StringOf(AItem, 'name');
  if mText <> '' then
  begin
    AEntry.Name := mText;
  end;
  mText := StringOf(AItem, 'description');
  if mText <> '' then
  begin
    AEntry.Description := mText;
  end;
  TranslateOptions(AItem.GetValue('options'), AEntry.Options);
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
  mRoot: TJSONValue;
  mItem: TJSONValue;
  mEntry: TRuleCatalogEntry;
begin
  mRoot := TJSONObject.ParseJSONValue(AJson);
  try
    for mItem in RulesOf(mRoot) do
    begin
      mEntry := EntryOf(mItem);
      if IndexOf(mEntry.Id) >= 0 then
      begin
        raise ERuleCatalog.CreateFmt('Regelkatalog: "%s" doppelt', [mEntry.Id]);
      end;
      FEntries.Add(mEntry);
      FPositions.Add(LowerCase(mEntry.Id), FEntries.Count - 1);
    end;
  finally
    mRoot.Free;
  end;
end;

procedure TRuleCatalog.ApplyOverlay(const AJson: string);
var
  mRoot: TJSONValue;
  mItem: TJSONValue;
  mIndex: Integer;
  mEntry: TRuleCatalogEntry;
begin
  mRoot := TJSONObject.ParseJSONValue(AJson);
  try
    for mItem in RulesOf(mRoot) do
    begin
      // Übersetzungen unbekannter Regeln und Einträge, die keine Objekte sind, sind harmlos und werden übergangen.
      if mItem is TJSONObject then
      begin
        mIndex := IndexOf(StringOf(TJSONObject(mItem), 'id'));
        if mIndex >= 0 then
        begin
          mEntry := FEntries[mIndex];
          TranslateEntry(TJSONObject(mItem), mEntry);
          FEntries[mIndex] := mEntry;
        end;
      end;
    end;
  finally
    mRoot.Free;
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
    Result := Result + ALineBreak + ALineBreak + cTexts[TCatalogText.Wrong].Text + ALineBreak + AEntry.Bad;
  end;
  if AEntry.Good <> '' then
  begin
    Result := Result + ALineBreak + ALineBreak + cTexts[TCatalogText.Right].Text + ALineBreak + AEntry.Good;
  end;
  if AEntry.CompilerCodes <> nil then
  begin
    Result := Result + ALineBreak + ALineBreak +
      cTexts[TCatalogText.CompilerCodes].Fmt([string.Join(', ', AEntry.CompilerCodes)]);
  end;
  if AEntry.OverriddenBy <> nil then
  begin
    Result := Result + ALineBreak + ALineBreak + cTexts[TCatalogText.OverriddenBy].Fmt(
      [string.Join(cTexts[TCatalogText.OrSeparator].Text, AEntry.OverriddenBy)]);
  end;
  Result := Result + ALineBreak + ALineBreak + cTexts[TCatalogText.More].Fmt([HelpUri(AEntry.Id)]);
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

class function TRuleCatalog.Localized: TRuleCatalog;
begin
  if TAtlasLocale.Language = TTextLanguage.English then
  begin
    Exit(Shared);
  end;
  SharedLock.Acquire;
  try
    if FGerman = nil then
    begin
      FGerman := TRuleCatalog.Create(RuleCatalogBaseJson, RuleCatalogOverlayJson('de'));
    end;
    Result := FGerman;
  finally
    SharedLock.Release;
  end;
end;

initialization
  SharedLock := TCriticalSection.Create;
  TAtlasTextTables.Add('Atlas.Common.Rules.Catalog', cTexts);

finalization
  FreeAndNil(TRuleCatalog.FGerman);
  FreeAndNil(TRuleCatalog.FShared);
  FreeAndNil(SharedLock);

end.
