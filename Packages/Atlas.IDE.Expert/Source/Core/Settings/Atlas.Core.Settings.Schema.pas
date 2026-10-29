unit Atlas.Core.Settings.Schema;

// Einstellungen von atlas.json aus dem JSON-Schema (#227): Seite (x-page),
// Beschreibung, Art des Bedienelements und Standardwert. Objekte mit nur
// einfachen Gliedern (compiler, format, highlight …) werden zu einzelnen
// Feldern "objekt.glied". Was sich nicht als einfaches Feld bearbeiten lässt
// (Regeln, Profile, Listen von Objekten), ist Complex: Der Dialog bearbeitet es
// als JSON-Text, die Regeln als Tabelle aus dem Regelkatalog.
// So erscheint jede neue Einstellung im Schema ohne weiteren Code im Dialog.
// x-control (Bedienelement laut Issue), examples (Vorschläge für Textfelder),
// x-restart (wirkt erst nach Neustart) und x-scope (Ort: "global" =
// settings.json, "project" = atlas.json; ein Glied erbt den Ort seines
// Objekts) werden mitgelesen. Ein Glied mit eigenem x-page steht auf dieser
// Seite (#896: diagnostics.usesCycleLive unter Prüfregeln, die übrigen
// diagnostics.* unter Robustheit).

interface

uses
  System.Generics.Collections,
  System.SysUtils,
  System.JSON;

type
{$SCOPEDENUMS ON}
  TAtlasSettingKind = (Boolean_, Integer_, Text, Choice, List, Complex);
{$SCOPEDENUMS OFF}

  TAtlasSettingField = record
    /// <summary>Pfad in atlas.json, z. B. "compiler.onSave".</summary>
    Path: string;
    Page: string;
    Description: string;
    Kind: TAtlasSettingKind;
    /// <summary>Bei Choice: erlaubte Werte als JSON-Text ("\"de\"", "true").</summary>
    Choices: TArray<string>;
    /// <summary>Standardwert als JSON-Text; '' ohne Angabe.</summary>
    DefaultJson: string;
    /// <summary>x-control: gewünschtes Bedienelement, z. B. "Datei wählen", "Auswahl aus der .dproj".</summary>
    Control: string;
    /// <summary>examples als Anzeigetexte (Strings ohne Anführungszeichen).</summary>
    Examples: TArray<string>;
    /// <summary>x-restart: Die Änderung wirkt erst nach einem Neustart des Servers.</summary>
    Restart: Boolean;
    /// <summary>x-scope: True = gilt für alle Projekte (settings.json), False = atlas.json des Projekts.</summary>
    Global: Boolean;
    /// <summary>x-scope "both": an beiden Orten, das Projekt übersteuert je Glied (rules).</summary>
    Both: Boolean;
    /// <summary>x-experimental (#834): experimentelle Funktion, wirkt nur mit experimental.enabled.</summary>
    Experimental: Boolean;
    /// <summary>x-control verlangt eine Dateiauswahl.</summary>
    function PicksFile: Boolean;
    /// <summary>Passt AJson (JSON-Text) zur Art des Felds? Sonst bleibt der Wert unangetastet.</summary>
    function Accepts(const AJson: string): Boolean;
  end;

  TAtlasSettingsSchema = class
  public
    /// <summary>Felder in der Reihenfolge des Schemas; leer bei ungültigem Schema.</summary>
    class function Fields(const ASchemaJson: string): TArray<TAtlasSettingField>; static;
    /// <summary>Felder eines Orts: AGlobal = settings.json, sonst atlas.json; ohne die Pfade in AExclude und ohne
    /// zusammengesetzte Felder, die einen davon enthalten (z. B. "vcs" mit "vcs.provider").</summary>
    class function ForScope(const AFields: TArray<TAtlasSettingField>; AGlobal: Boolean;
      const AExclude: TArray<string>): TArray<TAtlasSettingField>; static;
    /// <summary>Seiten in der Reihenfolge ihres ersten Felds.</summary>
    class function Pages(const AFields: TArray<TAtlasSettingField>): TArray<string>; static;
    /// <summary>JSON-Text für die Anzeige: Strings ohne Anführungszeichen.</summary>
    class function Display(const AJson: string): string; static;
  end;

implementation

function TypeOf(ASchema: TJSONObject): string;
var
  Value: TJSONValue;
begin
  Value := ASchema.GetValue('type');
  if Value is TJSONString then
    Result := TJSONString(Value).Value
  else if Value is TJSONArray then
    Result := 'mixed'
  else if ASchema.GetValue('oneOf') <> nil then
    Result := 'oneOf'
  else
    Result := '';
end;

function DescriptionOf(ASchema: TJSONObject): string;
begin
  Result := ASchema.GetValue<string>('description', '');
  if Result = '' then
    Result := ASchema.GetValue<string>('markdownDescription', '');
end;

/// <summary>Art eines Schemas; Complex, wenn kein einfaches Bedienelement passt.</summary>
function KindOf(ASchema: TJSONObject; out AChoices: TArray<string>): TAtlasSettingKind;
var
  Enum, Items: TJSONValue;
  Value: TJSONValue;
  OneOf: TJSONValue;
  Option: TJSONValue;
  Kind: string;
begin
  AChoices := nil;
  Enum := ASchema.GetValue('enum');
  if Enum is TJSONArray then
  begin
    for Value in TJSONArray(Enum) do
      AChoices := AChoices + [Value.ToJSON];
    Exit(TAtlasSettingKind.Choice);
  end;
  Kind := TypeOf(ASchema);
  if Kind = 'boolean' then
    Exit(TAtlasSettingKind.Boolean_);
  if (Kind = 'integer') or (Kind = 'number') then
    Exit(TAtlasSettingKind.Integer_);
  if Kind = 'string' then
    Exit(TAtlasSettingKind.Text);
  if Kind = 'array' then
  begin
    Items := ASchema.GetValue('items');
    if (Items is TJSONObject) and (TypeOf(TJSONObject(Items)) = 'string') then
      Exit(TAtlasSettingKind.List);
  end;
  // oneOf mit String-Variante (z. B. profile): als Text, solange der Wert ein String ist.
  if Kind = 'oneOf' then
  begin
    OneOf := ASchema.GetValue('oneOf');
    if OneOf is TJSONArray then
      for Option in TJSONArray(OneOf) do
        if (Option is TJSONObject) and (TypeOf(TJSONObject(Option)) = 'string') then
          Exit(TAtlasSettingKind.Text);
  end;
  Result := TAtlasSettingKind.Complex;
end;

{ TAtlasSettingField }

function TAtlasSettingField.Accepts(const AJson: string): Boolean;
var
  Value: TJSONValue;
  Item: TJSONValue;
  Choice: string;
begin
  if AJson = '' then
    Exit(True);
  Value := TJSONObject.ParseJSONValue(AJson);
  if Value = nil then
    Exit(False);
  try
    case Kind of
      TAtlasSettingKind.Boolean_:
        Result := Value is TJSONBool;
      TAtlasSettingKind.Integer_:
        Result := Value is TJSONNumber;
      // TJSONNumber erbt von TJSONString: Zahlen ausdrücklich ausschließen.
      TAtlasSettingKind.Text:
        Result := (Value is TJSONString) and not (Value is TJSONNumber);
      TAtlasSettingKind.Choice:
        begin
          Result := False;
          for Choice in Choices do
            if Choice = Value.ToJSON then
              Result := True;
        end;
      TAtlasSettingKind.List:
        begin
          Result := Value is TJSONArray;
          if Result then
            for Item in TJSONArray(Value) do
              if not (Item is TJSONString) or (Item is TJSONNumber) then
                Result := False;
        end;
    else
      Result := True;
    end;
  finally
    Value.Free;
  end;
end;

function TAtlasSettingField.PicksFile: Boolean;
begin
  Result := Pos('Datei wählen', Control) > 0;
end;

{ TAtlasSettingsSchema }

class function TAtlasSettingsSchema.Fields(const ASchemaJson: string): TArray<TAtlasSettingField>;
var
  Root, Properties, Child, Children: TJSONValue;
  Pair, Sub: TJSONPair;
  Field: TAtlasSettingField;
  Simple: Boolean;
  Choices: TArray<string>;

  function Make(const APath, APage: string; ASchema: TJSONObject; const AFallback, AScope: string): TAtlasSettingField;
  var
    Default_, Examples, Example, Restart, Experimental: TJSONValue;
  begin
    Result := Default(TAtlasSettingField);
    Result.Path := APath;
    Result.Page := ASchema.GetValue<string>('x-page', APage);
    Result.Description := DescriptionOf(ASchema);
    if Result.Description = '' then
      Result.Description := AFallback;
    Result.Kind := KindOf(ASchema, Result.Choices);
    Default_ := ASchema.GetValue('default');
    if Default_ <> nil then
      Result.DefaultJson := Default_.ToJSON;
    Result.Control := ASchema.GetValue<string>('x-control', '');
    Examples := ASchema.GetValue('examples');
    if Examples is TJSONArray then
      for Example in TJSONArray(Examples) do
        Result.Examples := Result.Examples + [Display(Example.ToJSON)];
    Restart := ASchema.GetValue('x-restart');
    Result.Restart := (Restart is TJSONBool) and TJSONBool(Restart).AsBoolean;
    Result.Global := ASchema.GetValue<string>('x-scope', AScope) = 'global';
    Result.Both := ASchema.GetValue<string>('x-scope', AScope) = 'both';
    Experimental := ASchema.GetValue('x-experimental');
    Result.Experimental := (Experimental is TJSONBool) and TJSONBool(Experimental).AsBoolean;
  end;

begin
  Result := nil;
  Root := TJSONObject.ParseJSONValue(ASchemaJson);
  try
    if not (Root is TJSONObject) then
      Exit;
    Properties := TJSONObject(Root).GetValue('properties');
    if not (Properties is TJSONObject) then
      Exit;
    for Pair in TJSONObject(Properties) do
    begin
      if not (Pair.JsonValue is TJSONObject) or (Pair.JsonString.Value = '$schema') then
        Continue;
      Child := Pair.JsonValue;
      Children := TJSONObject(Child).GetValue('properties');
      // Objekt mit einfachen Gliedern: Felder je Glied.
      if (TypeOf(TJSONObject(Child)) = 'object') and (Children is TJSONObject) then
      begin
        Simple := TJSONObject(Children).Count > 0;
        for Sub in TJSONObject(Children) do
          if not (Sub.JsonValue is TJSONObject) or
            (KindOf(TJSONObject(Sub.JsonValue), Choices) = TAtlasSettingKind.Complex) then
            Simple := False;
        if Simple then
        begin
          for Sub in TJSONObject(Children) do
            Result := Result + [Make(Pair.JsonString.Value + '.' + Sub.JsonString.Value,
              TJSONObject(Child).GetValue<string>('x-page', ''), TJSONObject(Sub.JsonValue),
              DescriptionOf(TJSONObject(Child)), TJSONObject(Child).GetValue<string>('x-scope', ''))];
          Continue;
        end;
      end;
      Field := Make(Pair.JsonString.Value, TJSONObject(Child).GetValue<string>('x-page', ''),
        TJSONObject(Child), '', '');
      Result := Result + [Field];
    end;
  finally
    Root.Free;
  end;
end;

class function TAtlasSettingsSchema.ForScope(const AFields: TArray<TAtlasSettingField>; AGlobal: Boolean;
  const AExclude: TArray<string>): TArray<TAtlasSettingField>;
var
  Field: TAtlasSettingField;
  Path: string;
  Excluded: Boolean;
begin
  Result := nil;
  for Field in AFields do
  begin
    if (Field.Global <> AGlobal) and not Field.Both then
      Continue;
    Excluded := False;
    for Path in AExclude do
      // Ein zusammengesetztes Feld (ganzes Objekt als JSON, z. B. "vcs" seit #1285) mit einem ausgeschlossenen
      // Glied fällt mit weg: Es im Dialog als Ganzes zu bearbeiten, überschriebe die Werte der eigenen Seite.
      if SameText(Path, Field.Path) or SameText(Copy(Path, 1, Length(Field.Path) + 1), Field.Path + '.') then
        Excluded := True;
    if not Excluded then
      Result := Result + [Field];
  end;
end;

class function TAtlasSettingsSchema.Pages(const AFields: TArray<TAtlasSettingField>): TArray<string>;
var
  Field: TAtlasSettingField;
  Page: string;
  Known: Boolean;
begin
  Result := nil;
  for Field in AFields do
  begin
    Known := False;
    for Page in Result do
      if SameText(Page, Field.Page) then
        Known := True;
    if not Known then
      Result := Result + [Field.Page];
  end;
end;

class function TAtlasSettingsSchema.Display(const AJson: string): string;
var
  Value: TJSONValue;
begin
  Result := AJson;
  Value := TJSONObject.ParseJSONValue(AJson);
  try
    if Value is TJSONString then
      Result := TJSONString(Value).Value;
  finally
    Value.Free;
  end;
end;

end.
