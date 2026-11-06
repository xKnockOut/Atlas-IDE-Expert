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
  cRuleDocumentationBaseUri = 'https://github.com/xKnockOut/Atlas-IDE-Expert/blob/main/docs/Regeln.md#';

implementation

uses
  System.JSON,
  System.SyncObjs,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Rules.Catalog.Data;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Erklärung (#300) in beiden Sprachen (#1458).</summary>
  TCatalogText = (Wrong, Right, CompilerCodes, OverriddenBy, OrSeparator, More, NeedsColumns, ColumnNoName,
    OptionNoObject, OptionNoName, OptionBadType, BadOptions, BadCompilerCodes, BadCompilerCode, BadOverriddenBy,
    BadCounterRule, ObjectExpected, RulesMissing, BadCategory, BadSeverity, BadGroup, BadLevel, BadSafeFix,
    EntryNoObject, EntryNoId, Duplicate);

const
  cTexts: array[TCatalogText] of TAtlasText = (
    (De: 'Falsch:'; En: 'Wrong:'),
    (De: 'Richtig:'; En: 'Right:'),
    (De: 'Entspricht der Compilermeldung %s.'; En: 'Corresponds to compiler message %s.'),
    (De: 'Schweigt, solange %s an ist.'; En: 'Silent while %s is on.'),
    (De: ' oder '; En: ' or '),
    (De: 'Mehr: %s'; En: 'More: %s'),
    (De: 'Regelkatalog: Option "%s" von "%s" braucht "columns"';
     En: 'Rule catalog: option "%s" of "%s" needs "columns"'),
    (De: 'Regelkatalog: Spalte von "%s" in "%s" ohne "name"';
     En: 'Rule catalog: column of "%s" in "%s" without "name"'),
    (De: 'Regelkatalog: Option von "%s" ist kein Objekt'; En: 'Rule catalog: option of "%s" is not an object'),
    (De: 'Regelkatalog: Option von "%s" ohne "name"'; En: 'Rule catalog: option of "%s" without "name"'),
    (De: 'Regelkatalog: Option "%s" von "%s" hat keinen gültigen Typ';
     En: 'Rule catalog: option "%s" of "%s" has no valid type'),
    (De: 'Regelkatalog: "%s" hat ungültige "options"'; En: 'Rule catalog: "%s" has invalid "options"'),
    (De: 'Regelkatalog: "%s" hat ungültige "compilerCodes"'; En: 'Rule catalog: "%s" has invalid "compilerCodes"'),
    (De: 'Regelkatalog: "%s" hat einen ungültigen Compilercode'; En: 'Rule catalog: "%s" has an invalid compiler code'),
    (De: 'Regelkatalog: "%s" hat ungültige "overriddenBy"'; En: 'Rule catalog: "%s" has invalid "overriddenBy"'),
    (De: 'Regelkatalog: "%s" hat eine ungültige Gegenregel'; En: 'Rule catalog: "%s" has an invalid counter rule'),
    (De: 'Regelkatalog: Objekt erwartet'; En: 'Rule catalog: object expected'),
    (De: 'Regelkatalog: "rules" fehlt'; En: 'Rule catalog: "rules" is missing'),
    (De: 'Regelkatalog: "%s" hat keine gültige Kategorie'; En: 'Rule catalog: "%s" has no valid category'),
    (De: 'Regelkatalog: "%s" hat keinen gültigen Schweregrad'; En: 'Rule catalog: "%s" has no valid severity'),
    (De: 'Regelkatalog: "%s" hat keine gültige Gruppe'; En: 'Rule catalog: "%s" has no valid group'),
    (De: 'Regelkatalog: "%s" hat eine ungültige Stufe "%s"'; En: 'Rule catalog: "%s" has an invalid level "%s"'),
    (De: 'Regelkatalog: "%s" hat ein ungültiges "safeFix"'; En: 'Rule catalog: "%s" has an invalid "safeFix"'),
    (De: 'Regelkatalog: Eintrag ist kein Objekt'; En: 'Rule catalog: entry is not an object'),
    (De: 'Regelkatalog: Eintrag ohne "id"'; En: 'Rule catalog: entry without "id"'),
    (De: 'Regelkatalog: "%s" doppelt'; En: 'Rule catalog: "%s" is duplicated'));

{$SCOPEDENUMS OFF}

const
  cCategoryNames: array[TRuleCategory] of string = ('bug', 'vulnerability', 'code-smell', 'security-hotspot');
  cGroupNames: array[TRuleGroup] of string = ('find-bugs', 'exceptions', 'threads', 'database', 'compiler',
    'robustness', 'performance', 'security', 'components', 'forms', 'architecture', 'style', 'packages', 'internal');
  cOptionKinds: array[0..6] of string = ('integer', 'boolean', 'string', 'string-list', 'number-list', 'object-list',
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
  mValue: TJSONValue;
begin
  mValue := AObject.GetValue(AName);
  if mValue is TJSONString then
  begin
    Result := TJSONString(mValue).Value;
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
    raise ERuleCatalog.CreateFmt(cTexts[TCatalogText.NeedsColumns].Text, [AName, AId]);
  end;
  for mItem in TJSONArray(mValue) do
  begin
    if not (mItem is TJSONObject) or (StringOf(TJSONObject(mItem), 'name') = '') then
    begin
      raise ERuleCatalog.CreateFmt(cTexts[TCatalogText.ColumnNoName].Text, [AName, AId]);
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
  for mKind in cOptionKinds do
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
    raise ERuleCatalog.CreateFmt(cTexts[TCatalogText.OptionNoObject].Text, [AId]);
  end;
  mObject := TJSONObject(AItem);
  Result := Default(TRuleOption);
  Result.Name := StringOf(mObject, 'name');
  Result.Kind := StringOf(mObject, 'type');
  Result.Description := StringOf(mObject, 'description');
  if Result.Name = '' then
  begin
    raise ERuleCatalog.CreateFmt(cTexts[TCatalogText.OptionNoName].Text, [AId]);
  end;
  if not IsOptionKind(Result.Kind) then
  begin
    raise ERuleCatalog.CreateFmt(cTexts[TCatalogText.OptionBadType].Text, [Result.Name, AId]);
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
    raise ERuleCatalog.CreateFmt(cTexts[TCatalogText.BadOptions].Text, [AId]);
  end;
  for mItem in TJSONArray(mValue) do
  begin
    Result := Result + [OptionOf(mItem, AId)];
  end;
end;

function IsCompilerCode(const ACode: string): Boolean;
var
  mIndex: Integer;
begin
  // X wie X1008 (#1040): Meldungen, die dcc als Warnung ausgibt.
  Result := (Length(ACode) = 5) and CharInSet(ACode[1], ['E', 'F', 'W', 'H', 'X']);
  if Result then
  begin
    for mIndex := 2 to 5 do
    begin
      if not CharInSet(ACode[mIndex], ['0'..'9']) then
      begin
        Exit(False);
      end;
    end;
  end;
end;

function CompilerCodesOf(AItem: TJSONObject; const AId: string): TArray<string>;
var
  mValue, mItem: TJSONValue;
begin
  Result := nil;
  mValue := AItem.GetValue('compilerCodes');
  if mValue = nil then
  begin
    Exit;
  end;
  if not (mValue is TJSONArray) then
  begin
    raise ERuleCatalog.CreateFmt(cTexts[TCatalogText.BadCompilerCodes].Text, [AId]);
  end;
  for mItem in TJSONArray(mValue) do
  begin
    if not (mItem is TJSONString) or not IsCompilerCode(TJSONString(mItem).Value) then
    begin
      raise ERuleCatalog.CreateFmt(cTexts[TCatalogText.BadCompilerCode].Text, [AId]);
    end;
    Result := Result + [TJSONString(mItem).Value];
  end;
end;

function OverriddenByOf(AItem: TJSONObject; const AId: string): TArray<string>;
var
  mValue, mItem: TJSONValue;
begin
  Result := nil;
  mValue := AItem.GetValue('overriddenBy');
  if mValue = nil then
  begin
    Exit;
  end;
  if not (mValue is TJSONArray) then
  begin
    raise ERuleCatalog.CreateFmt(cTexts[TCatalogText.BadOverriddenBy].Text, [AId]);
  end;
  for mItem in TJSONArray(mValue) do
  begin
    if not (mItem is TJSONString) or (mItem is TJSONNumber) or (TJSONString(mItem).Value = '') then
    begin
      raise ERuleCatalog.CreateFmt(cTexts[TCatalogText.BadCounterRule].Text, [AId]);
    end;
    Result := Result + [TJSONString(mItem).Value];
  end;
end;

function RulesOf(ARoot: TJSONValue): TJSONArray;
var
  mValue: TJSONValue;
begin
  if not (ARoot is TJSONObject) then
  begin
    raise ERuleCatalog.Create(cTexts[TCatalogText.ObjectExpected].Text);
  end;
  mValue := TJSONObject(ARoot).GetValue('rules');
  if not (mValue is TJSONArray) then
  begin
    raise ERuleCatalog.Create(cTexts[TCatalogText.RulesMissing].Text);
  end;
  Result := TJSONArray(mValue);
end;

/// <summary>Kategorie, Schweregrad und Gruppe (ohne "group" die der Kategorie) eines Eintrags.</summary>
procedure ClassifyEntry(AItem: TJSONObject; var AEntry: TRuleCatalogEntry);
begin
  if not TRuleCatalog.TryParseCategory(StringOf(AItem, 'category'), AEntry.Category) then
  begin
    raise ERuleCatalog.CreateFmt(cTexts[TCatalogText.BadCategory].Text, [AEntry.Id]);
  end;
  if not TryParseSeverity(StringOf(AItem, 'severity'), AEntry.DefaultSeverity) then
  begin
    raise ERuleCatalog.CreateFmt(cTexts[TCatalogText.BadSeverity].Text, [AEntry.Id]);
  end;
  AEntry.Group := TRuleCatalog.GroupOfCategory(AEntry.Category);
  if (AItem.GetValue('group') <> nil) and not TRuleCatalog.TryParseGroup(StringOf(AItem, 'group'), AEntry.Group) then
  begin
    raise ERuleCatalog.CreateFmt(cTexts[TCatalogText.BadGroup].Text, [AEntry.Id]);
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
    raise ERuleCatalog.CreateFmt(cTexts[TCatalogText.BadLevel].Text, [AEntry.Id, AEntry.Level]);
  end;
  mSafeFix := AItem.GetValue('safeFix');
  AEntry.SafeFix := (mSafeFix is TJSONBool) and TJSONBool(mSafeFix).AsBoolean;
  if (mSafeFix <> nil) and not (mSafeFix is TJSONBool) then
  begin
    raise ERuleCatalog.CreateFmt(cTexts[TCatalogText.BadSafeFix].Text, [AEntry.Id]);
  end;
end;

/// <summary>Ein Eintrag des Grundkatalogs; ERuleCatalog bei ungültigen Angaben.</summary>
function EntryOf(AItem: TJSONValue): TRuleCatalogEntry;
var
  mObject: TJSONObject;
begin
  if not (AItem is TJSONObject) then
  begin
    raise ERuleCatalog.Create(cTexts[TCatalogText.EntryNoObject].Text);
  end;
  mObject := TJSONObject(AItem);
  Result := Default(TRuleCatalogEntry);
  Result.Id := StringOf(mObject, 'id');
  if Result.Id = '' then
  begin
    raise ERuleCatalog.Create(cTexts[TCatalogText.EntryNoId].Text);
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
        raise ERuleCatalog.CreateFmt(cTexts[TCatalogText.Duplicate].Text, [mEntry.Id]);
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
  mIndex: Integer;
begin
  mIndex := IndexOf(AId);
  Result := mIndex >= 0;
  if Result then
  begin
    AEntry := FEntries[mIndex];
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
  Result := cRuleDocumentationBaseUri + LowerCase(AId);
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
  Result := cCategoryNames[ACategory];
end;

class function TRuleCatalog.TryParseCategory(const AText: string; out ACategory: TRuleCategory): Boolean;
var
  mCategory: TRuleCategory;
begin
  for mCategory := Low(TRuleCategory) to High(TRuleCategory) do
  begin
    if SameText(AText, cCategoryNames[mCategory]) then
    begin
      ACategory := mCategory;
      Exit(True);
    end;
  end;
  ACategory := TRuleCategory.Bug;
  Result := False;
end;

class function TRuleCatalog.GroupName(AGroup: TRuleGroup): string;
begin
  Result := cGroupNames[AGroup];
end;

class function TRuleCatalog.GroupKey(AGroup: TRuleGroup): string;
begin
  Result := 'group:' + cGroupNames[AGroup];
end;

class function TRuleCatalog.TryParseGroup(const AText: string; out AGroup: TRuleGroup): Boolean;
var
  mGroup: TRuleGroup;
begin
  for mGroup := Low(TRuleGroup) to High(TRuleGroup) do
  begin
    if SameText(AText, cGroupNames[mGroup]) then
    begin
      AGroup := mGroup;
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
