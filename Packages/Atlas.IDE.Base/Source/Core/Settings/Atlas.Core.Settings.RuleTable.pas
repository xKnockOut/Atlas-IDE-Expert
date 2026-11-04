unit Atlas.Core.Settings.RuleTable;

// Tabelle der Prüfregeln im Einstellungsdialog (#227): Zeilen aus dem
// Regelkatalog des Servers (atlas.server.settingsCatalog) und dem Wert von
// "rules" der bearbeiteten Datei. Regeln, die nur in "rules" stehen, kommen
// hinten dazu. Setzen eines Schweregrads behält Optionen einer Regel, die als
// Objekt eingestellt ist: Dann ändert sich nur "severity".
// Seite „Prüfregeln“ (#909): Gruppe, Beschreibung, Beispiele, Optionen mit
// Typ und Vorgabe, Ausnahmen ("exclude") und der Hauptschalter je Gruppe
// ("group:<gruppe>": "off", vom Server ausgewertet). Optionen und Ausnahmen
// als Text für die Felder der Seite (OptionText, OptionJson, ListText,
// ParseList); GroupIds sind die Gruppen des Servers in Reihenfolge der Seite.
// Optionen der Art "object-list" (#1133) als Tabelle mit den Spalten des
// Katalogs (TableCells, TableJson).

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON;

type
  /// <summary>Spalte einer Option der Art "object-list" (#1133).</summary>
  TAtlasRuleColumn = record
    Name: string;
    /// <summary>Der Wert ist eine Liste von Texten (in der Zelle mit "; " getrennt).</summary>
    List: Boolean;
  end;

  /// <summary>Option einer Regel aus dem Katalog; Werte als JSON-Text.</summary>
  TAtlasRuleOption = record
    Name: string;
    /// <summary>"integer", "string", "string-list", "number-list" (#937), "object-list" (#1133) oder "json".
    /// </summary>
    Kind: string;
    /// <summary>Nur "object-list": Spalten der Tabelle.</summary>
    Columns: TArray<TAtlasRuleColumn>;
    /// <summary>Vorgabe als JSON-Text; '' = keine.</summary>
    DefaultJson: string;
    Description: string;
    /// <summary>Eingestellter Wert als JSON-Text; '' = Vorgabe.</summary>
    ValueJson: string;
  end;

  TAtlasRuleRow = record
    Id: string;
    Name: string;
    Category: string;
    /// <summary>Vorgabe des Katalogs, z. B. "warning".</summary>
    DefaultSeverity: string;
    /// <summary>Eingestellter Schweregrad; '' = Vorgabe.</summary>
    Severity: string;
    /// <summary>Die Regel ist als Objekt mit Optionen eingestellt.</summary>
    HasOptions: Boolean;
    /// <summary>Steht im Katalog des Servers.</summary>
    Known: Boolean;
    /// <summary>Im Projekt: Schweregrad aus den globalen Einstellungen; '' = dort nicht gesetzt.</summary>
    GlobalSeverity: string;
    /// <summary>Gruppe des Katalogs, z. B. "exceptions"; '' = unbekannt.</summary>
    Group: string;
    Description: string;
    /// <summary>Beispiel mit Befund und ohne.</summary>
    Bad: string;
    Good: string;
    Experimental: Boolean;
    Options: TArray<TAtlasRuleOption>;
    /// <summary>Muster aus "exclude" (Glob oder Unit-Name).</summary>
    Exclude: TArray<string>;
    /// <summary>Regeln, die diese übersteuern (Katalog "overriddenBy", #1025): Ist eine davon an, meldet diese
    /// nichts.</summary>
    OverriddenBy: TArray<string>;
    /// <summary>Wirksamer Schweregrad: eingestellt, sonst global, sonst Vorgabe.</summary>
    function Effective: string;
    /// <summary>Regel meldet etwas (wirksamer Schweregrad nicht "off").</summary>
    function Enabled: Boolean;
    /// <summary>AText kommt in Kennung, Name, Kategorie oder Beschreibung vor (ohne Groß-/Kleinschreibung); ''
    /// passt immer.</summary>
    function Matches(const AText: string): Boolean;
  end;

  TAtlasRuleTable = class
  public const
    Severities: array[0..4] of string = ('off', 'hint', 'info', 'warning', 'error');
    /// <summary>Gruppen des Regelkatalogs (TRuleGroup des Servers) in der Reihenfolge der Seite Prüfregeln.
    /// </summary>
    GroupIds: array[0..13] of string = ('find-bugs', 'exceptions', 'threads', 'database', 'compiler',
      'robustness', 'performance', 'security', 'components', 'forms', 'architecture', 'style', 'packages',
      'internal');
    /// <summary>Gruppe „Compiler vorab“ (#1024) mit der Option "typeLevel".</summary>
    CompilerGroup = 'compiler';
  public
    /// <summary>ACatalog: Antwort von atlas.server.settingsCatalog (darf nil sein). ARulesJson: Wert von
    /// "rules" ('' ohne).</summary>
    class function Rows(ACatalog: TJSONValue; const ARulesJson: string): TArray<TAtlasRuleRow>; overload; static;
    /// <summary>Wie oben, dazu je Regel der Schweregrad aus "rules" der globalen Datei (AGlobalRulesJson).
    /// Das Projekt übersteuert ihn je Regel.</summary>
    class function Rows(ACatalog: TJSONValue; const ARulesJson, AGlobalRulesJson: string): TArray<TAtlasRuleRow>;
      overload; static;
    /// <summary>Pfad und JSON-Text für TAtlasJsonText, um ASeverity für AId zu setzen ('' = entfernen):
    /// "rules.&lt;id&gt;" oder bei einer Regel mit Optionen "rules.&lt;id&gt;.severity". So ändert sich in der Datei nur
    /// dieser Wert.</summary>
    class procedure SeverityChange(const ARulesJson, AId, ASeverity: string; out APath, AJson: string); static;
    /// <summary>Neuer Wert von "rules" mit ASeverity für AId; '' entfernt die Regel (bei Optionen nur
    /// "severity"). Ergebnis '' für ein leeres Objekt.</summary>
    class function WithSeverity(const ARulesJson, AId, ASeverity: string): string; static;
    /// <summary>Neuer Wert von "rules" mit Option AOption = AValueJson (JSON-Text) für AId; '' entfernt die
    /// Option. Eine Regel als Text wird zum Objekt mit "severity"; ein Objekt, das nur noch "severity"
    /// hat, wird wieder Text.</summary>
    class function WithOption(const ARulesJson, AId, AOption, AValueJson: string): string; static;
    /// <summary>Neuer Wert von "rules" mit den Mustern AExclude in "exclude" von AId; leer entfernt sie.</summary>
    class function WithExclude(const ARulesJson, AId: string; const AExclude: TArray<string>): string; static;
    /// <summary>Gruppe AGroup ist in "rules" abgeschaltet ("group:&lt;gruppe&gt;": "off" oder als Objekt
    /// {"severity": "off", …}, #1024).</summary>
    class function GroupOff(const ARulesJson, AGroup: string): Boolean; static;
    /// <summary>Neuer Wert von "rules" mit Hauptschalter der Gruppe: AOn entfernt den Schlüssel bzw. im
    /// Objekt "severity", sonst "group:&lt;gruppe&gt;": "off" bzw. "severity": "off". Optionen der Gruppe
    /// (z. B. "typeLevel") bleiben stehen.</summary>
    class function WithGroup(const ARulesJson, AGroup: string; AOn: Boolean): string; static;
    /// <summary>Option AOption der Gruppe als Text ('' = nicht gesetzt), z. B. "typeLevel" der Gruppe
    /// „Compiler vorab“ (#1024).</summary>
    class function GroupOption(const ARulesJson, AGroup, AOption: string): string; static;
    /// <summary>Neuer Wert von "rules" mit Option AOption = AValue (Text) der Gruppe; '' entfernt sie. Der
    /// Schlüssel wird dazu zum Objekt; bleibt nur "severity", wird er wieder Text, ein leeres Objekt
    /// entfällt.</summary>
    class function WithGroupOption(const ARulesJson, AGroup, AOption, AValue: string): string; static;
    /// <summary>Schlüssel des Hauptschalters, z. B. "group:style".</summary>
    class function GroupKey(const AGroup: string): string; static;
    /// <summary>Gruppen der Zeilen in Reihenfolge des ersten Vorkommens, ohne ''.</summary>
    class function Groups(const ARows: TArray<TAtlasRuleRow>): TArray<string>; static;
    /// <summary>Indizes der Zeilen, die zu AGroup gehören ('' = alle) und auf AText passen.</summary>
    class function Filter(const ARows: TArray<TAtlasRuleRow>; const AGroup, AText: string): TArray<Integer>;
      static;
    /// <summary>Wert der Option als Feldtext: eingestellt, sonst Vorgabe; Text ohne Anführungszeichen, Liste
    /// mit "; " getrennt, sonst JSON.</summary>
    class function OptionText(const AOption: TAtlasRuleOption): string; static;
    /// <summary>Feldtext AText einer Option der Art AKind als JSON-Text; '' = Vorgabe (leeres Feld). False
    /// bei ungültiger Eingabe (keine Zahl, kein true/false, kein JSON).</summary>
    class function OptionJson(const AKind, AText: string; out AJson: string): Boolean; static;
    /// <summary>Zellen einer Option der Art "object-list" (#1133): je Objekt des Werts (sonst der Vorgabe) eine
    /// Zeile mit den Spalten von AOption.Columns; Text ohne Anführungszeichen, Liste mit "; " getrennt, andere
    /// Werte als JSON.</summary>
    class function TableCells(const AOption: TAtlasRuleOption): TArray<TArray<string>>; static;
    /// <summary>JSON-Text zu den Zellen ACells mit den Spalten von AOption: leere Zellen fehlen im Objekt, Zeilen
    /// ohne Inhalt entfallen; "[]" ohne Zeile.</summary>
    class function TableJson(const AOption: TAtlasRuleOption; const ACells: TArray<TArray<string>>): string; static;
    /// <summary>Kennung der eingeschalteten Regel aus ARow.OverriddenBy, die ARow übersteuert (#1025); ''
    /// ohne.</summary>
    class function OverridingRule(const ARows: TArray<TAtlasRuleRow>; const ARow: TAtlasRuleRow): string; static;
    /// <summary>Muster als Feldtext, mit "; " getrennt.</summary>
    class function ListText(const AItems: TArray<string>): string; static;
    /// <summary>Feldtext an ";" geteilt, ohne Leerraum und leere Einträge.</summary>
    class function ParseList(const AText: string): TArray<string>; static;
    /// <summary>Änderungen von "rules" zwischen AOldJson und ANewJson je Regel bzw. Hauptschalter als Pfad
    /// ("rules.&lt;id&gt;") und JSON-Text ('' = entfernen), für TAtlasJsonText.ApplyChanges und
    /// TAtlasSettingsModel.SetPath: Kommentare und Schreibweise unveränderter Regeln bleiben in der Datei.</summary>
    class function Changes(const AOldJson, ANewJson: string): TArray<TPair<string, string>>; static;
  end;

implementation

uses
  System.Math;

function SeverityOf(AValue: TJSONValue; out AHasOptions: Boolean): string;
begin
  Result := '';
  AHasOptions := AValue is TJSONObject;
  if (AValue is TJSONString) and not (AValue is TJSONNumber) then
  begin
    Result := TJSONString(AValue).Value;
  end
  else if AHasOptions then
  begin
    Result := TJSONObject(AValue).GetValue<string>('severity', '');
  end;
end;

function ParseRules(const ARulesJson: string): TJSONObject;
var
  Value: TJSONValue;
begin
  Value := nil;
  if ARulesJson <> '' then
  begin
    Value := TJSONObject.ParseJSONValue(ARulesJson);
  end;
  if Value is TJSONObject then
  begin
    Exit(TJSONObject(Value));
  end;
  Value.Free;
  Result := TJSONObject.Create;
end;

function RulesText(ARules: TJSONObject): string;
begin
  Result := '';
  if ARules.Count > 0 then
  begin
    Result := ARules.ToJSON;
  end;
end;

/// <summary>Einstellung von AId als Objekt; ein Text wird zu {"severity": …}.</summary>
function RuleObject(ARules: TJSONObject; const AId: string): TJSONObject;
var
  Existing: TJSONValue;
  Severity: string;
  Pair: TJSONPair;
begin
  Existing := ARules.GetValue(AId);
  if Existing is TJSONObject then
  begin
    Exit(TJSONObject(Existing));
  end;
  Severity := '';
  if (Existing is TJSONString) and not (Existing is TJSONNumber) then
  begin
    Severity := TJSONString(Existing).Value;
  end;
  Pair := ARules.RemovePair(AId);
  Pair.Free;
  Result := TJSONObject.Create;
  if Severity <> '' then
  begin
    Result.AddPair('severity', Severity);
  end;
  ARules.AddPair(AId, Result);
end;

/// <summary>Ein Objekt nur mit "severity" wird wieder Text, ein leeres fällt weg.</summary>
procedure Compact(ARules: TJSONObject; const AId: string);
var
  Rule: TJSONValue;
  Severity: string;
  Pair: TJSONPair;
begin
  Rule := ARules.GetValue(AId);
  if not (Rule is TJSONObject) then
  begin
    Exit;
  end;
  if TJSONObject(Rule).Count = 0 then
  begin
    Pair := ARules.RemovePair(AId);
    Pair.Free;
  end
  else if (TJSONObject(Rule).Count = 1) and (TJSONObject(Rule).GetValue('severity') <> nil) then
  begin
    Severity := TJSONObject(Rule).GetValue<string>('severity', '');
    Pair := ARules.RemovePair(AId);
    Pair.Free;
    ARules.AddPair(AId, Severity);
  end;
end;

/// <summary>Spalten "columns" einer Option aus dem Katalog des Servers (#1133); leer ohne.</summary>
function ColumnsOf(AValue: TJSONValue): TArray<TAtlasRuleColumn>;
var
  mItem: TJSONValue;
  mColumn: TAtlasRuleColumn;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(AValue) do
  begin
    if mItem is TJSONObject then
    begin
      mColumn.Name := TJSONObject(mItem).GetValue<string>('name', '');
      mColumn.List := TJSONObject(mItem).GetValue<Boolean>('list', False);
      if mColumn.Name <> '' then
      begin
        Result := Result + [mColumn];
      end;
    end;
  end;
end;

procedure ReadOptions(AOptions: TJSONValue; var ARow: TAtlasRuleRow);
var
  Item, DefaultValue: TJSONValue;
  Option: TAtlasRuleOption;
begin
  ARow.Options := nil;
  if not (AOptions is TJSONArray) then
  begin
    Exit;
  end;
  for Item in TJSONArray(AOptions) do
  begin
    if Item is TJSONObject then
    begin
      Option := Default(TAtlasRuleOption);
      Option.Name := TJSONObject(Item).GetValue<string>('name', '');
      if Option.Name = '' then
      begin
        Continue;
      end;
      Option.Kind := TJSONObject(Item).GetValue<string>('type', 'json');
      Option.Columns := ColumnsOf(TJSONObject(Item).GetValue('columns'));
      Option.Description := TJSONObject(Item).GetValue<string>('description', '');
      DefaultValue := TJSONObject(Item).GetValue('default');
      if DefaultValue <> nil then
      begin
        Option.DefaultJson := DefaultValue.ToJSON;
      end;
      ARow.Options := ARow.Options + [Option];
    end;
  end;
end;

/// <summary>Muster aus "exclude" einer Regel; leer ohne.</summary>
function ExcludeOf(AValue: TJSONValue): TArray<string>;
var
  mItem: TJSONValue;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(AValue) do
  begin
    if mItem is TJSONString then
    begin
      Result := Result + [TJSONString(mItem).Value];
    end;
  end;
end;

/// <summary>Wert AValueJson der Option AName setzen; eine unbekannte Option kommt als "json" dazu.</summary>
procedure SetOptionValue(var ARow: TAtlasRuleRow; const AName, AValueJson: string);
var
  mIndex: Integer;
  mFound: Boolean;
  mOption: TAtlasRuleOption;
begin
  mFound := False;
  for mIndex := 0 to High(ARow.Options) do
  begin
    if SameText(ARow.Options[mIndex].Name, AName) then
    begin
      ARow.Options[mIndex].ValueJson := AValueJson;
      mFound := True;
    end;
  end;
  if not mFound then
  begin
    mOption := Default(TAtlasRuleOption);
    mOption.Name := AName;
    mOption.Kind := 'json';
    mOption.ValueJson := AValueJson;
    ARow.Options := ARow.Options + [mOption];
  end;
end;

/// <summary>Werte der Optionen und "exclude" aus der Einstellung einer Regel; unbekannte Optionen kommen
/// als "json" dazu.</summary>
procedure ReadSettings(AValue: TJSONValue; var ARow: TAtlasRuleRow);
var
  mPair: TJSONPair;
begin
  ARow.Exclude := nil;
  if not (AValue is TJSONObject) then
  begin
    Exit;
  end;
  for mPair in TJSONObject(AValue) do
  begin
    if SameText(mPair.JsonString.Value, 'exclude') then
    begin
      ARow.Exclude := ExcludeOf(mPair.JsonValue);
    end
    else if not SameText(mPair.JsonString.Value, 'severity') then
    begin
      SetOptionValue(ARow, mPair.JsonString.Value, mPair.JsonValue.ToJSON);
    end;
  end;
end;

/// <summary>Texte aus "overriddenBy" des Katalogs (#1025); leer ohne.</summary>
function OverridesOf(AValue: TJSONValue): TArray<string>;
var
  mItem: TJSONValue;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(AValue) do
  begin
    if (mItem is TJSONString) and not (mItem is TJSONNumber) then
    begin
      Result := Result + [mItem.Value];
    end;
  end;
end;

/// <summary>Zeile zu einem Eintrag des Katalogs; False ohne "id". ARules: Wert von "rules" (darf nil sein).
/// </summary>
function CatalogRow(AItem: TJSONObject; ARules: TJSONValue; out ARow: TAtlasRuleRow): Boolean;
begin
  ARow := Default(TAtlasRuleRow);
  ARow.Id := AItem.GetValue<string>('id', '');
  Result := ARow.Id <> '';
  if not Result then
  begin
    Exit;
  end;
  ARow.Name := AItem.GetValue<string>('name', '');
  ARow.Category := AItem.GetValue<string>('category', '');
  ARow.DefaultSeverity := AItem.GetValue<string>('severity', '');
  ARow.Group := AItem.GetValue<string>('group', '');
  ARow.Description := AItem.GetValue<string>('description', '');
  ARow.Bad := AItem.GetValue<string>('bad', '');
  ARow.Good := AItem.GetValue<string>('good', '');
  ARow.Experimental := AItem.GetValue<Boolean>('experimental', False);
  ARow.Known := True;
  ARow.OverriddenBy := OverridesOf(AItem.GetValue('overriddenBy'));
  ReadOptions(AItem.GetValue('options'), ARow);
  if ARules is TJSONObject then
  begin
    ARow.Severity := SeverityOf(TJSONObject(ARules).GetValue(ARow.Id), ARow.HasOptions);
    ReadSettings(TJSONObject(ARules).GetValue(ARow.Id), ARow);
  end;
end;

/// <summary>Zeilen aus "rules" des Katalogs ACatalog (darf nil sein).</summary>
function CatalogRows(ACatalog, ARules: TJSONValue): TArray<TAtlasRuleRow>;
var
  mItems, mItem: TJSONValue;
  mRow: TAtlasRuleRow;
begin
  Result := nil;
  mItems := nil;
  if ACatalog is TJSONObject then
  begin
    mItems := TJSONObject(ACatalog).GetValue('rules');
  end;
  if not (mItems is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(mItems) do
  begin
    if (mItem is TJSONObject) and CatalogRow(TJSONObject(mItem), ARules, mRow) then
    begin
      Result := Result + [mRow];
    end;
  end;
end;

function HasRow(const ARows: TArray<TAtlasRuleRow>; const AId: string): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex := 0 to High(ARows) do
  begin
    if SameText(ARows[mIndex].Id, AId) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Regeln aus ARules, die ARows noch nicht hat, ohne Hauptschalter ("group:…").</summary>
procedure AddUnknownRows(ARules: TJSONObject; var ARows: TArray<TAtlasRuleRow>);
var
  mPair: TJSONPair;
  mRow: TAtlasRuleRow;
begin
  for mPair in ARules do
  begin
    if HasRow(ARows, mPair.JsonString.Value) or mPair.JsonString.Value.StartsWith('group:') then
    begin
      Continue;
    end;
    mRow := Default(TAtlasRuleRow);
    mRow.Id := mPair.JsonString.Value;
    mRow.Severity := SeverityOf(mPair.JsonValue, mRow.HasOptions);
    ReadSettings(mPair.JsonValue, mRow);
    ARows := ARows + [mRow];
  end;
end;

/// <summary>Text eines Texts oder JSON-Text eines anderen Werts.</summary>
function PlainText(AValue: TJSONValue): string;
begin
  if (AValue is TJSONString) and not (AValue is TJSONNumber) then
  begin
    Result := TJSONString(AValue).Value;
  end
  else
  begin
    Result := AValue.ToJSON;
  end;
end;

/// <summary>Zelle zum Wert ACell: '' ohne, Liste mit "; " getrennt, Text ohne Anführungszeichen.</summary>
function CellText(ACell: TJSONValue): string;
var
  mEntry: TJSONValue;
  mItems: TArray<string>;
begin
  Result := '';
  if ACell is TJSONArray then
  begin
    mItems := nil;
    for mEntry in TJSONArray(ACell) do
    begin
      mItems := mItems + [PlainText(mEntry)];
    end;
    Result := TAtlasRuleTable.ListText(mItems);
  end
  else if ACell <> nil then
  begin
    Result := PlainText(ACell);
  end;
end;

function ObjectCells(AItem: TJSONObject; const AColumns: TArray<TAtlasRuleColumn>): TArray<string>;
var
  mColumn: TAtlasRuleColumn;
begin
  Result := nil;
  for mColumn in AColumns do
  begin
    Result := Result + [CellText(AItem.GetValue(mColumn.Name))];
  end;
end;

/// <summary>Objekt zu einer Tabellenzeile; leere Zellen fehlen, nil ohne Inhalt.</summary>
function RowObject(const AColumns: TArray<TAtlasRuleColumn>; const ARow: TArray<string>): TJSONObject;
var
  mIndex: Integer;
  mText, mEntry: string;
  mList: TJSONArray;
begin
  Result := TJSONObject.Create;
  for mIndex := 0 to Min(High(AColumns), High(ARow)) do
  begin
    mText := Trim(ARow[mIndex]);
    if mText = '' then
    begin
      Continue;
    end;
    if AColumns[mIndex].List then
    begin
      mList := TJSONArray.Create;
      for mEntry in TAtlasRuleTable.ParseList(mText) do
      begin
        mList.Add(mEntry);
      end;
      Result.AddPair(AColumns[mIndex].Name, mList);
    end
    else
    begin
      Result.AddPair(AColumns[mIndex].Name, mText);
    end;
  end;
  if Result.Count = 0 then
  begin
    FreeAndNil(Result);
  end;
end;

function StringListJson(const AText: string): string;
var
  mItems: TJSONArray;
  mItem: string;
begin
  mItems := TJSONArray.Create;
  try
    for mItem in TAtlasRuleTable.ParseList(AText) do
    begin
      mItems.Add(mItem);
    end;
    Result := mItems.ToJSON;
  finally
    mItems.Free;
  end;
end;

/// <summary>Zahlen mit Punkt als Dezimaltrenner; ganze Zahlen bleiben ganz (#937). False bei einem Eintrag,
/// der keine Zahl ist.</summary>
function NumberListJson(const AText: string; out AJson: string): Boolean;
var
  mItems: TJSONArray;
  mItem: string;
  mFloat: Double;
begin
  Result := True;
  AJson := '';
  mItems := TJSONArray.Create;
  try
    for mItem in TAtlasRuleTable.ParseList(AText) do
    begin
      if not TryStrToFloat(mItem, mFloat, TFormatSettings.Invariant) then
      begin
        Exit(False);
      end;
      if (Frac(mFloat) = 0) and (Abs(mFloat) < 1E15) then
      begin
        mItems.AddElement(TJSONNumber.Create(Trunc(mFloat)));
      end
      else
      begin
        mItems.AddElement(TJSONNumber.Create(mFloat));
      end;
    end;
    AJson := mItems.ToJSON;
  finally
    mItems.Free;
  end;
end;

function StringJson(const AText: string): string;
var
  mValue: TJSONValue;
begin
  mValue := TJSONString.Create(AText);
  try
    Result := mValue.ToJSON;
  finally
    mValue.Free;
  end;
end;

/// <summary>AText als JSON-Text, wenn er gültiges JSON ist.</summary>
function ParsedJson(const AText: string; out AJson: string): Boolean;
var
  mValue: TJSONValue;
begin
  AJson := '';
  mValue := TJSONObject.ParseJSONValue(AText);
  Result := mValue <> nil;
  if Result then
  begin
    AJson := mValue.ToJSON;
  end;
  mValue.Free;
end;

/// <summary>Ganze Zahl oder true/false als JSON-Text.</summary>
function ScalarJson(const AKind, AText: string; out AJson: string): Boolean;
var
  mNumber: Int64;
begin
  AJson := '';
  if SameText(AKind, 'integer') then
  begin
    Result := TryStrToInt64(AText, mNumber);
    if Result then
    begin
      AJson := IntToStr(mNumber);
    end;
  end
  else
  begin
    Result := SameText(AText, 'true') or SameText(AText, 'false');
    if Result then
    begin
      AJson := AText.ToLower;
    end;
  end;
end;

{ TAtlasRuleRow }

function TAtlasRuleRow.Effective: string;
begin
  Result := Severity;
  if Result = '' then
  begin
    Result := GlobalSeverity;
  end;
  if Result = '' then
  begin
    Result := DefaultSeverity;
  end;
end;

function TAtlasRuleRow.Enabled: Boolean;
begin
  Result := not SameText(Effective, 'off');
end;

function TAtlasRuleRow.Matches(const AText: string): Boolean;
var
  Needle: string;
begin
  if AText = '' then
  begin
    Exit(True);
  end;
  Needle := AText.ToLower;
  Result := Id.ToLower.Contains(Needle) or Name.ToLower.Contains(Needle) or
    Category.ToLower.Contains(Needle) or Description.ToLower.Contains(Needle);
end;

{ TAtlasRuleTable }

class function TAtlasRuleTable.Rows(ACatalog: TJSONValue; const ARulesJson,
  AGlobalRulesJson: string): TArray<TAtlasRuleRow>;
var
  Global: TArray<TAtlasRuleRow>;
  Index, Other: Integer;
begin
  Result := Rows(ACatalog, ARulesJson);
  if AGlobalRulesJson = '' then
  begin
    Exit;
  end;
  Global := Rows(nil, AGlobalRulesJson);
  for Other := 0 to High(Global) do
  begin
    for Index := 0 to High(Result) do
    begin
      if SameText(Result[Index].Id, Global[Other].Id) then
      begin
        Result[Index].GlobalSeverity := Global[Other].Severity;
      end;
    end;
  end;
end;

class function TAtlasRuleTable.Rows(ACatalog: TJSONValue; const ARulesJson: string): TArray<TAtlasRuleRow>;
var
  mRules: TJSONValue;
begin
  mRules := nil;
  if ARulesJson <> '' then
  begin
    mRules := TJSONObject.ParseJSONValue(ARulesJson);
  end;
  try
    Result := CatalogRows(ACatalog, mRules);
    // Regeln, die der Katalog nicht kennt (oder ohne Server): trotzdem zeigen.
    if mRules is TJSONObject then
    begin
      AddUnknownRows(TJSONObject(mRules), Result);
    end;
  finally
    mRules.Free;
  end;
end;

class procedure TAtlasRuleTable.SeverityChange(const ARulesJson, AId, ASeverity: string; out APath,
  AJson: string);
var
  Value, Existing: TJSONValue;
begin
  APath := 'rules.' + AId;
  Value := nil;
  if ARulesJson <> '' then
  begin
    Value := TJSONObject.ParseJSONValue(ARulesJson);
  end;
  try
    Existing := nil;
    if Value is TJSONObject then
    begin
      Existing := TJSONObject(Value).GetValue(AId);
    end;
    if Existing is TJSONObject then
    begin
      APath := APath + '.severity';
    end;
  finally
    Value.Free;
  end;
  AJson := '';
  if ASeverity <> '' then
  begin
    AJson := '"' + ASeverity + '"';
  end;
end;

class function TAtlasRuleTable.WithSeverity(const ARulesJson, AId, ASeverity: string): string;
var
  Value: TJSONValue;
  Rules: TJSONObject;
  Existing: TJSONValue;
  Pair: TJSONPair;
begin
  Value := nil;
  if ARulesJson <> '' then
  begin
    Value := TJSONObject.ParseJSONValue(ARulesJson);
  end;
  if not (Value is TJSONObject) then
  begin
    Value.Free;
    Value := TJSONObject.Create;
  end;
  Rules := TJSONObject(Value);
  try
    Existing := Rules.GetValue(AId);
    if Existing is TJSONObject then
    begin
      // Optionen bleiben; nur der Schweregrad wechselt.
      Pair := TJSONObject(Existing).RemovePair('severity');
      Pair.Free;
      if ASeverity <> '' then
      begin
        TJSONObject(Existing).AddPair('severity', ASeverity);
      end;
    end
    else
    begin
      Pair := Rules.RemovePair(AId);
      Pair.Free;
      if ASeverity <> '' then
      begin
        Rules.AddPair(AId, ASeverity);
      end;
    end;
    if Rules.Count = 0 then
    begin
      Result := '';
    end
    else
    begin
      Result := Rules.ToJSON;
    end;
  finally
    Rules.Free;
  end;
end;

class function TAtlasRuleTable.WithOption(const ARulesJson, AId, AOption, AValueJson: string): string;
var
  Rules, Rule: TJSONObject;
  Value: TJSONValue;
  Pair: TJSONPair;
begin
  Rules := ParseRules(ARulesJson);
  try
    Value := nil;
    if AValueJson <> '' then
    begin
      Value := TJSONObject.ParseJSONValue(AValueJson);
      if Value = nil then
      begin
        Exit(RulesText(Rules));
      end;
    end;
    Rule := RuleObject(Rules, AId);
    Pair := Rule.RemovePair(AOption);
    Pair.Free;
    if Value <> nil then
    begin
      Rule.AddPair(AOption, Value);
    end;
    Compact(Rules, AId);
    Result := RulesText(Rules);
  finally
    Rules.Free;
  end;
end;

class function TAtlasRuleTable.WithExclude(const ARulesJson, AId: string; const AExclude: TArray<string>): string;
var
  Rules, Rule: TJSONObject;
  Items: TJSONArray;
  Pattern: string;
  Pair: TJSONPair;
begin
  Rules := ParseRules(ARulesJson);
  try
    Rule := RuleObject(Rules, AId);
    Pair := Rule.RemovePair('exclude');
    Pair.Free;
    Items := nil;
    for Pattern in AExclude do
    begin
      if Pattern.Trim <> '' then
      begin
        if Items = nil then
        begin
          Items := TJSONArray.Create;
        end;
        Items.Add(Pattern.Trim);
      end;
    end;
    if Items <> nil then
    begin
      Rule.AddPair('exclude', Items);
    end;
    Compact(Rules, AId);
    Result := RulesText(Rules);
  finally
    Rules.Free;
  end;
end;

class function TAtlasRuleTable.GroupKey(const AGroup: string): string;
begin
  Result := 'group:' + AGroup;
end;

class function TAtlasRuleTable.GroupOff(const ARulesJson, AGroup: string): Boolean;
var
  Rules: TJSONObject;
  Value: TJSONValue;
begin
  Rules := ParseRules(ARulesJson);
  try
    Value := Rules.GetValue(GroupKey(AGroup));
    if Value is TJSONObject then
    begin
      Value := TJSONObject(Value).GetValue('severity');
    end;
    Result := (Value is TJSONString) and not (Value is TJSONNumber) and SameText(TJSONString(Value).Value, 'off');
  finally
    Rules.Free;
  end;
end;

class function TAtlasRuleTable.WithGroup(const ARulesJson, AGroup: string; AOn: Boolean): string;
var
  Value: string;
begin
  Value := '';
  if not AOn then
  begin
    Value := 'off';
  end;
  Result := WithGroupOption(ARulesJson, AGroup, 'severity', Value);
end;

class function TAtlasRuleTable.GroupOption(const ARulesJson, AGroup, AOption: string): string;
var
  Rules: TJSONObject;
  Value: TJSONValue;
begin
  Result := '';
  Rules := ParseRules(ARulesJson);
  try
    Value := Rules.GetValue(GroupKey(AGroup));
    if Value is TJSONObject then
    begin
      Value := TJSONObject(Value).GetValue(AOption);
    end
    else if not SameText(AOption, 'severity') then
    begin
      Value := nil;
    end;
    if (Value is TJSONString) and not (Value is TJSONNumber) then
    begin
      Result := TJSONString(Value).Value;
    end;
  finally
    Rules.Free;
  end;
end;

class function TAtlasRuleTable.WithGroupOption(const ARulesJson, AGroup, AOption, AValue: string): string;
var
  Rules, Group: TJSONObject;
  Value: TJSONValue;
  Pair: TJSONPair;
  Severity: string;
begin
  Rules := ParseRules(ARulesJson);
  try
    // Text ("off") und Objekt einheitlich als Objekt bearbeiten, danach so knapp wie möglich zurückschreiben.
    Pair := Rules.RemovePair(GroupKey(AGroup));
    try
      Group := TJSONObject.Create;
      if Pair <> nil then
      begin
        Value := Pair.JsonValue;
        if Value is TJSONObject then
        begin
          Group.Free;
          Group := TJSONObject(TJSONObject(Value).Clone);
        end
        else if (Value is TJSONString) and not (Value is TJSONNumber) then
        begin
          Group.AddPair('severity', TJSONString(Value).Value);
        end;
      end;
    finally
      Pair.Free;
    end;
    Pair := Group.RemovePair(AOption);
    Pair.Free;
    if AValue <> '' then
    begin
      Group.AddPair(AOption, AValue);
    end;
    if Group.Count = 0 then
    begin
      Group.Free;
    end
    else if (Group.Count = 1) and (Group.GetValue('severity') is TJSONString) then
    begin
      Severity := TJSONString(Group.GetValue('severity')).Value;
      Group.Free;
      Rules.AddPair(GroupKey(AGroup), Severity);
    end
    else
    begin
      Rules.AddPair(GroupKey(AGroup), Group);
    end;
    Result := RulesText(Rules);
  finally
    Rules.Free;
  end;
end;

class function TAtlasRuleTable.Groups(const ARows: TArray<TAtlasRuleRow>): TArray<string>;
var
  Row: TAtlasRuleRow;
  Group: string;
  Found: Boolean;
begin
  Result := nil;
  for Row in ARows do
  begin
    if Row.Group = '' then
    begin
      Continue;
    end;
    Found := False;
    for Group in Result do
    begin
      if SameText(Group, Row.Group) then
      begin
        Found := True;
      end;
    end;
    if not Found then
    begin
      Result := Result + [Row.Group];
    end;
  end;
end;

class function TAtlasRuleTable.Filter(const ARows: TArray<TAtlasRuleRow>; const AGroup,
  AText: string): TArray<Integer>;
var
  Index: Integer;
begin
  Result := nil;
  for Index := 0 to High(ARows) do
  begin
    if ((AGroup = '') or SameText(ARows[Index].Group, AGroup)) and ARows[Index].Matches(AText.Trim) then
    begin
      Result := Result + [Index];
    end;
  end;
end;

class function TAtlasRuleTable.OverridingRule(const ARows: TArray<TAtlasRuleRow>;
  const ARow: TAtlasRuleRow): string;
var
  Id: string;
  Index: Integer;
begin
  for Id in ARow.OverriddenBy do
  begin
    for Index := 0 to High(ARows) do
    begin
      if SameText(ARows[Index].Id, Id) and ARows[Index].Enabled then
      begin
        Exit(ARows[Index].Id);
      end;
    end;
  end;
  Result := '';
end;

class function TAtlasRuleTable.ListText(const AItems: TArray<string>): string;
begin
  Result := string.Join('; ', AItems);
end;

class function TAtlasRuleTable.ParseList(const AText: string): TArray<string>;
var
  Part: string;
begin
  Result := nil;
  for Part in AText.Split([';']) do
  begin
    if Part.Trim <> '' then
    begin
      Result := Result + [Part.Trim];
    end;
  end;
end;

class function TAtlasRuleTable.OptionText(const AOption: TAtlasRuleOption): string;
var
  Json: string;
  Value, Item: TJSONValue;
  Items: TArray<string>;
begin
  Json := AOption.ValueJson;
  if Json = '' then
  begin
    Json := AOption.DefaultJson;
  end;
  Result := Json;
  if Json = '' then
  begin
    Exit;
  end;
  Value := TJSONObject.ParseJSONValue(Json);
  try
    if (Value is TJSONString) and not (Value is TJSONNumber) then
    begin
      Result := TJSONString(Value).Value;
    end
    else if (Value is TJSONArray) and (SameText(AOption.Kind, 'string-list') or
      SameText(AOption.Kind, 'number-list')) then
    begin
      Items := nil;
      for Item in TJSONArray(Value) do
      begin
        if (Item is TJSONString) and not (Item is TJSONNumber) then
        begin
          Items := Items + [TJSONString(Item).Value];
        end
        else
        begin
          Items := Items + [Item.ToJSON];
        end;
      end;
      Result := ListText(Items);
    end;
  finally
    Value.Free;
  end;
end;

class function TAtlasRuleTable.TableCells(const AOption: TAtlasRuleOption): TArray<TArray<string>>;
var
  mJson: string;
  mValue, mItem: TJSONValue;
begin
  Result := nil;
  mJson := AOption.ValueJson;
  if mJson = '' then
  begin
    mJson := AOption.DefaultJson;
  end;
  if mJson = '' then
  begin
    Exit;
  end;
  mValue := TJSONObject.ParseJSONValue(mJson);
  try
    if mValue is TJSONArray then
    begin
      for mItem in TJSONArray(mValue) do
      begin
        if mItem is TJSONObject then
        begin
          Result := Result + [ObjectCells(TJSONObject(mItem), AOption.Columns)];
        end;
      end;
    end;
  finally
    mValue.Free;
  end;
end;

class function TAtlasRuleTable.TableJson(const AOption: TAtlasRuleOption;
  const ACells: TArray<TArray<string>>): string;
var
  mItems: TJSONArray;
  mObject: TJSONObject;
  mRow: TArray<string>;
begin
  mItems := TJSONArray.Create;
  try
    for mRow in ACells do
    begin
      mObject := RowObject(AOption.Columns, mRow);
      if mObject <> nil then
      begin
        mItems.AddElement(mObject);
      end;
    end;
    Result := mItems.ToJSON;
  finally
    mItems.Free;
  end;
end;

class function TAtlasRuleTable.OptionJson(const AKind, AText: string; out AJson: string): Boolean;
var
  mText: string;
begin
  AJson := '';
  mText := AText.Trim;
  Result := True;
  if mText = '' then
  begin
    Exit;
  end;
  if SameText(AKind, 'integer') or SameText(AKind, 'boolean') then
  begin
    Result := ScalarJson(AKind, mText, AJson);
  end
  else if SameText(AKind, 'string') then
  begin
    AJson := StringJson(mText);
  end
  else if SameText(AKind, 'string-list') then
  begin
    AJson := StringListJson(mText);
  end
  else if SameText(AKind, 'number-list') then
  begin
    Result := NumberListJson(mText, AJson);
  end
  else
  begin
    // json und unbekannte Arten: der Text muss gültiges JSON sein.
    Result := ParsedJson(mText, AJson);
  end;
end;

class function TAtlasRuleTable.Changes(const AOldJson, ANewJson: string): TArray<TPair<string, string>>;
var
  Old, Updated: TJSONObject;
  Pair: TJSONPair;
  Value: TJSONValue;
begin
  Result := nil;
  Old := ParseRules(AOldJson);
  Updated := ParseRules(ANewJson);
  try
    for Pair in Updated do
    begin
      Value := Old.GetValue(Pair.JsonString.Value);
      if (Value = nil) or (Value.ToJSON <> Pair.JsonValue.ToJSON) then
      begin
        Result := Result + [TPair<string, string>.Create('rules.' + Pair.JsonString.Value, Pair.JsonValue.ToJSON)];
      end;
    end;
    for Pair in Old do
    begin
      if Updated.GetValue(Pair.JsonString.Value) = nil then
      begin
        Result := Result + [TPair<string, string>.Create('rules.' + Pair.JsonString.Value, '')];
      end;
    end;
  finally
    Updated.Free;
    Old.Free;
  end;
end;

end.
