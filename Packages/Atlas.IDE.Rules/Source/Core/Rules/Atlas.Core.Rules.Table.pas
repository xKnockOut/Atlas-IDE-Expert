unit Atlas.Core.Rules.Table;

// Tabelle der Prüfregeln im Einstellungsdialog (#227): Zeilen aus dem
// Regelkatalog des Servers (atlas.server.settingsCatalog) und dem Wert von
// "rules" der bearbeiteten Datei. Regeln, die nur in "rules" stehen, kommen
// hinten dazu. Setzen eines Schweregrads behält Optionen einer Regel, die als
// Objekt eingestellt ist: Dann ändert sich nur "severity".
// Seite „Prüfregeln“ (#909): Gruppe, Beschreibung, Beispiele, Optionen mit
// Typ und Vorgabe, Ausnahmen ("exclude") und der Hauptschalter je Gruppe
// ("group:<gruppe>": "off", vom Server ausgewertet). Optionen und Ausnahmen
// als Text für die Felder der Seite (OptionText, OptionJson, ListText,
// ParseList); cGroupIds sind die Gruppen des Servers in Reihenfolge der Seite.
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
    cSeverities: array[0..4] of string = ('off', 'hint', 'info', 'warning', 'error');
    /// <summary>Gruppen des Regelkatalogs (TRuleGroup des Servers) in der Reihenfolge der Seite Prüfregeln.
    /// </summary>
    cGroupIds: array[0..13] of string = ('find-bugs', 'exceptions', 'threads', 'database', 'compiler',
      'robustness', 'performance', 'security', 'components', 'forms', 'architecture', 'style', 'packages',
      'internal');
    /// <summary>Gruppe „Compiler vorab“ (#1024) mit der Option "typeLevel".</summary>
    cCompilerGroup = 'compiler';
  public
    /// <summary>ACatalog: Antwort von atlas.server.settingsCatalog (darf nil sein). ARulesJson: Wert von
    /// "rules" ('' ohne).</summary>
    class function Rows(ACatalog: TJSONValue; const ARulesJson: string): TArray<TAtlasRuleRow>; overload; static;
    /// <summary>Wie oben, dazu je Regel der Schweregrad aus "rules" der globalen Datei (AGlobalRulesJson).
    /// Das Projekt übersteuert ihn je Regel.</summary>
    class function Rows(ACatalog: TJSONValue; const ARulesJson, AGlobalRulesJson: string): TArray<TAtlasRuleRow>;
      overload; static;
    /// <summary>Pfad und JSON-Text für TAtlasJsonText, um ASeverity für AId zu setzen ('' = entfernen):
    /// "rules.&lt;id&gt;" oder bei einer Regel mit Optionen "rules.&lt;id&gt;.severity". So ändert sich in der Datei
    /// nur
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
  mValue: TJSONValue;
begin
  mValue := nil;
  if ARulesJson <> '' then
  begin
    mValue := TJSONObject.ParseJSONValue(ARulesJson);
  end;
  if mValue is TJSONObject then
  begin
    Exit(TJSONObject(mValue));
  end;
  mValue.Free;
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
  mExisting: TJSONValue;
  mSeverity: string;
  mPair: TJSONPair;
begin
  mExisting := ARules.GetValue(AId);
  if mExisting is TJSONObject then
  begin
    Exit(TJSONObject(mExisting));
  end;
  mSeverity := '';
  if (mExisting is TJSONString) and not (mExisting is TJSONNumber) then
  begin
    mSeverity := TJSONString(mExisting).Value;
  end;
  mPair := ARules.RemovePair(AId);
  mPair.Free;
  Result := TJSONObject.Create;
  if mSeverity <> '' then
  begin
    Result.AddPair('severity', mSeverity);
  end;
  ARules.AddPair(AId, Result);
end;

/// <summary>Ein Objekt nur mit "severity" wird wieder Text, ein leeres fällt weg.</summary>
procedure Compact(ARules: TJSONObject; const AId: string);
var
  mRule: TJSONValue;
  mSeverity: string;
  mPair: TJSONPair;
begin
  mRule := ARules.GetValue(AId);
  if not (mRule is TJSONObject) then
  begin
    Exit;
  end;
  if TJSONObject(mRule).Count = 0 then
  begin
    mPair := ARules.RemovePair(AId);
    mPair.Free;
  end
  else if (TJSONObject(mRule).Count = 1) and (TJSONObject(mRule).GetValue('severity') <> nil) then
  begin
    mSeverity := TJSONObject(mRule).GetValue<string>('severity', '');
    mPair := ARules.RemovePair(AId);
    mPair.Free;
    ARules.AddPair(AId, mSeverity);
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
  mItem, mDefaultValue: TJSONValue;
  mOption: TAtlasRuleOption;
begin
  ARow.Options := nil;
  if not (AOptions is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(AOptions) do
  begin
    if mItem is TJSONObject then
    begin
      mOption := Default(TAtlasRuleOption);
      mOption.Name := TJSONObject(mItem).GetValue<string>('name', '');
      if mOption.Name = '' then
      begin
        Continue;
      end;
      mOption.Kind := TJSONObject(mItem).GetValue<string>('type', 'json');
      mOption.Columns := ColumnsOf(TJSONObject(mItem).GetValue('columns'));
      mOption.Description := TJSONObject(mItem).GetValue<string>('description', '');
      mDefaultValue := TJSONObject(mItem).GetValue('default');
      if mDefaultValue <> nil then
      begin
        mOption.DefaultJson := mDefaultValue.ToJSON;
      end;
      ARow.Options := ARow.Options + [mOption];
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
  mNeedle: string;
begin
  if AText = '' then
  begin
    Exit(True);
  end;
  mNeedle := AText.ToLower;
  Result := Id.ToLower.Contains(mNeedle) or Name.ToLower.Contains(mNeedle) or
    Category.ToLower.Contains(mNeedle) or Description.ToLower.Contains(mNeedle);
end;

{ TAtlasRuleTable }

class function TAtlasRuleTable.Rows(ACatalog: TJSONValue; const ARulesJson,
  AGlobalRulesJson: string): TArray<TAtlasRuleRow>;
var
  mGlobal: TArray<TAtlasRuleRow>;
  mIndex, mOther: Integer;
begin
  Result := Rows(ACatalog, ARulesJson);
  if AGlobalRulesJson = '' then
  begin
    Exit;
  end;
  mGlobal := Rows(nil, AGlobalRulesJson);
  for mOther := 0 to High(mGlobal) do
  begin
    for mIndex := 0 to High(Result) do
    begin
      if SameText(Result[mIndex].Id, mGlobal[mOther].Id) then
      begin
        Result[mIndex].GlobalSeverity := mGlobal[mOther].Severity;
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
  mValue, mExisting: TJSONValue;
begin
  APath := 'rules.' + AId;
  mValue := nil;
  if ARulesJson <> '' then
  begin
    mValue := TJSONObject.ParseJSONValue(ARulesJson);
  end;
  try
    mExisting := nil;
    if mValue is TJSONObject then
    begin
      mExisting := TJSONObject(mValue).GetValue(AId);
    end;
    if mExisting is TJSONObject then
    begin
      APath := APath + '.severity';
    end;
  finally
    mValue.Free;
  end;
  AJson := '';
  if ASeverity <> '' then
  begin
    AJson := '"' + ASeverity + '"';
  end;
end;

class function TAtlasRuleTable.WithSeverity(const ARulesJson, AId, ASeverity: string): string;
var
  mValue: TJSONValue;
  mRules: TJSONObject;
  mExisting: TJSONValue;
  mPair: TJSONPair;
begin
  mValue := nil;
  if ARulesJson <> '' then
  begin
    mValue := TJSONObject.ParseJSONValue(ARulesJson);
  end;
  if not (mValue is TJSONObject) then
  begin
    mValue.Free;
    mValue := TJSONObject.Create;
  end;
  mRules := TJSONObject(mValue);
  try
    mExisting := mRules.GetValue(AId);
    if mExisting is TJSONObject then
    begin
      // Optionen bleiben; nur der Schweregrad wechselt.
      mPair := TJSONObject(mExisting).RemovePair('severity');
      mPair.Free;
      if ASeverity <> '' then
      begin
        TJSONObject(mExisting).AddPair('severity', ASeverity);
      end;
    end
    else
    begin
      mPair := mRules.RemovePair(AId);
      mPair.Free;
      if ASeverity <> '' then
      begin
        mRules.AddPair(AId, ASeverity);
      end;
    end;
    if mRules.Count = 0 then
    begin
      Result := '';
    end
    else
    begin
      Result := mRules.ToJSON;
    end;
  finally
    mRules.Free;
  end;
end;

class function TAtlasRuleTable.WithOption(const ARulesJson, AId, AOption, AValueJson: string): string;
var
  mRules, mRule: TJSONObject;
  mValue: TJSONValue;
  mPair: TJSONPair;
begin
  mRules := ParseRules(ARulesJson);
  try
    mValue := nil;
    if AValueJson <> '' then
    begin
      mValue := TJSONObject.ParseJSONValue(AValueJson);
      if mValue = nil then
      begin
        Exit(RulesText(mRules));
      end;
    end;
    mRule := RuleObject(mRules, AId);
    mPair := mRule.RemovePair(AOption);
    mPair.Free;
    if mValue <> nil then
    begin
      mRule.AddPair(AOption, mValue);
    end;
    Compact(mRules, AId);
    Result := RulesText(mRules);
  finally
    mRules.Free;
  end;
end;

class function TAtlasRuleTable.WithExclude(const ARulesJson, AId: string; const AExclude: TArray<string>): string;
var
  mRules, mRule: TJSONObject;
  mItems: TJSONArray;
  mPattern: string;
  mPair: TJSONPair;
begin
  mRules := ParseRules(ARulesJson);
  try
    mRule := RuleObject(mRules, AId);
    mPair := mRule.RemovePair('exclude');
    mPair.Free;
    mItems := nil;
    for mPattern in AExclude do
    begin
      if mPattern.Trim <> '' then
      begin
        if mItems = nil then
        begin
          mItems := TJSONArray.Create;
        end;
        mItems.Add(mPattern.Trim);
      end;
    end;
    if mItems <> nil then
    begin
      mRule.AddPair('exclude', mItems);
    end;
    Compact(mRules, AId);
    Result := RulesText(mRules);
  finally
    mRules.Free;
  end;
end;

class function TAtlasRuleTable.GroupKey(const AGroup: string): string;
begin
  Result := 'group:' + AGroup;
end;

class function TAtlasRuleTable.GroupOff(const ARulesJson, AGroup: string): Boolean;
var
  mRules: TJSONObject;
  mValue: TJSONValue;
begin
  mRules := ParseRules(ARulesJson);
  try
    mValue := mRules.GetValue(GroupKey(AGroup));
    if mValue is TJSONObject then
    begin
      mValue := TJSONObject(mValue).GetValue('severity');
    end;
    Result := (mValue is TJSONString) and not (mValue is TJSONNumber) and SameText(TJSONString(mValue).Value, 'off');
  finally
    mRules.Free;
  end;
end;

class function TAtlasRuleTable.WithGroup(const ARulesJson, AGroup: string; AOn: Boolean): string;
var
  mValue: string;
begin
  mValue := '';
  if not AOn then
  begin
    mValue := 'off';
  end;
  Result := WithGroupOption(ARulesJson, AGroup, 'severity', mValue);
end;

class function TAtlasRuleTable.GroupOption(const ARulesJson, AGroup, AOption: string): string;
var
  mRules: TJSONObject;
  mValue: TJSONValue;
begin
  Result := '';
  mRules := ParseRules(ARulesJson);
  try
    mValue := mRules.GetValue(GroupKey(AGroup));
    if mValue is TJSONObject then
    begin
      mValue := TJSONObject(mValue).GetValue(AOption);
    end
    else if not SameText(AOption, 'severity') then
    begin
      mValue := nil;
    end;
    if (mValue is TJSONString) and not (mValue is TJSONNumber) then
    begin
      Result := TJSONString(mValue).Value;
    end;
  finally
    mRules.Free;
  end;
end;

class function TAtlasRuleTable.WithGroupOption(const ARulesJson, AGroup, AOption, AValue: string): string;
var
  mRules, mGroup: TJSONObject;
  mValue: TJSONValue;
  mPair: TJSONPair;
  mSeverity: string;
begin
  mRules := ParseRules(ARulesJson);
  try
    // Text ("off") und Objekt einheitlich als Objekt bearbeiten, danach so knapp wie möglich zurückschreiben.
    mPair := mRules.RemovePair(GroupKey(AGroup));
    try
      mGroup := TJSONObject.Create;
      if mPair <> nil then
      begin
        mValue := mPair.JsonValue;
        if mValue is TJSONObject then
        begin
          mGroup.Free;
          mGroup := TJSONObject(TJSONObject(mValue).Clone);
        end
        else if (mValue is TJSONString) and not (mValue is TJSONNumber) then
        begin
          mGroup.AddPair('severity', TJSONString(mValue).Value);
        end;
      end;
    finally
      mPair.Free;
    end;
    mPair := mGroup.RemovePair(AOption);
    mPair.Free;
    if AValue <> '' then
    begin
      mGroup.AddPair(AOption, AValue);
    end;
    if mGroup.Count = 0 then
    begin
      mGroup.Free;
    end
    else if (mGroup.Count = 1) and (mGroup.GetValue('severity') is TJSONString) then
    begin
      mSeverity := TJSONString(mGroup.GetValue('severity')).Value;
      mGroup.Free;
      mRules.AddPair(GroupKey(AGroup), mSeverity);
    end
    else
    begin
      mRules.AddPair(GroupKey(AGroup), mGroup);
    end;
    Result := RulesText(mRules);
  finally
    mRules.Free;
  end;
end;

class function TAtlasRuleTable.Groups(const ARows: TArray<TAtlasRuleRow>): TArray<string>;
var
  mRow: TAtlasRuleRow;
  mGroup: string;
  mFound: Boolean;
begin
  Result := nil;
  for mRow in ARows do
  begin
    if mRow.Group = '' then
    begin
      Continue;
    end;
    mFound := False;
    for mGroup in Result do
    begin
      if SameText(mGroup, mRow.Group) then
      begin
        mFound := True;
      end;
    end;
    if not mFound then
    begin
      Result := Result + [mRow.Group];
    end;
  end;
end;

class function TAtlasRuleTable.Filter(const ARows: TArray<TAtlasRuleRow>; const AGroup,
  AText: string): TArray<Integer>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to High(ARows) do
  begin
    if ((AGroup = '') or SameText(ARows[mIndex].Group, AGroup)) and ARows[mIndex].Matches(AText.Trim) then
    begin
      Result := Result + [mIndex];
    end;
  end;
end;

class function TAtlasRuleTable.OverridingRule(const ARows: TArray<TAtlasRuleRow>;
  const ARow: TAtlasRuleRow): string;
var
  mId: string;
  mIndex: Integer;
begin
  for mId in ARow.OverriddenBy do
  begin
    for mIndex := 0 to High(ARows) do
    begin
      if SameText(ARows[mIndex].Id, mId) and ARows[mIndex].Enabled then
      begin
        Exit(ARows[mIndex].Id);
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
  mPart: string;
begin
  Result := nil;
  for mPart in AText.Split([';']) do
  begin
    if mPart.Trim <> '' then
    begin
      Result := Result + [mPart.Trim];
    end;
  end;
end;

class function TAtlasRuleTable.OptionText(const AOption: TAtlasRuleOption): string;
var
  mJson: string;
  mValue, mItem: TJSONValue;
  mItems: TArray<string>;
begin
  mJson := AOption.ValueJson;
  if mJson = '' then
  begin
    mJson := AOption.DefaultJson;
  end;
  Result := mJson;
  if mJson = '' then
  begin
    Exit;
  end;
  mValue := TJSONObject.ParseJSONValue(mJson);
  try
    if (mValue is TJSONString) and not (mValue is TJSONNumber) then
    begin
      Result := TJSONString(mValue).Value;
    end
    else if (mValue is TJSONArray) and (SameText(AOption.Kind, 'string-list') or
      SameText(AOption.Kind, 'number-list')) then
    begin
      mItems := nil;
      for mItem in TJSONArray(mValue) do
      begin
        if (mItem is TJSONString) and not (mItem is TJSONNumber) then
        begin
          mItems := mItems + [TJSONString(mItem).Value];
        end
        else
        begin
          mItems := mItems + [mItem.ToJSON];
        end;
      end;
      Result := ListText(mItems);
    end;
  finally
    mValue.Free;
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
  mOld, mUpdated: TJSONObject;
  mPair: TJSONPair;
  mValue: TJSONValue;
begin
  Result := nil;
  mOld := ParseRules(AOldJson);
  mUpdated := ParseRules(ANewJson);
  try
    for mPair in mUpdated do
    begin
      mValue := mOld.GetValue(mPair.JsonString.Value);
      if (mValue = nil) or (mValue.ToJSON <> mPair.JsonValue.ToJSON) then
      begin
        Result := Result + [TPair<string, string>.Create('rules.' + mPair.JsonString.Value, mPair.JsonValue.ToJSON)];
      end;
    end;
    for mPair in mOld do
    begin
      if mUpdated.GetValue(mPair.JsonString.Value) = nil then
      begin
        Result := Result + [TPair<string, string>.Create('rules.' + mPair.JsonString.Value, '')];
      end;
    end;
  finally
    mUpdated.Free;
    mOld.Free;
  end;
end;

end.
