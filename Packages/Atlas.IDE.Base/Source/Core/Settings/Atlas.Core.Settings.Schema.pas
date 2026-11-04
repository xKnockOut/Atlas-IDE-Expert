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
  begin
    Result := TJSONString(Value).Value;
  end
  else if Value is TJSONArray then
  begin
    Result := 'mixed';
  end
  else if ASchema.GetValue('oneOf') <> nil then
  begin
    Result := 'oneOf';
  end
  else
  begin
    Result := '';
  end;
end;

function DescriptionOf(ASchema: TJSONObject): string;
begin
  Result := ASchema.GetValue<string>('description', '');
  if Result = '' then
  begin
    Result := ASchema.GetValue<string>('markdownDescription', '');
  end;
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
    begin
      AChoices := AChoices + [Value.ToJSON];
    end;
    Exit(TAtlasSettingKind.Choice);
  end;
  Kind := TypeOf(ASchema);
  if Kind = 'boolean' then
  begin
    Exit(TAtlasSettingKind.Boolean_);
  end;
  if (Kind = 'integer') or (Kind = 'number') then
  begin
    Exit(TAtlasSettingKind.Integer_);
  end;
  if Kind = 'string' then
  begin
    Exit(TAtlasSettingKind.Text);
  end;
  if Kind = 'array' then
  begin
    Items := ASchema.GetValue('items');
    if (Items is TJSONObject) and (TypeOf(TJSONObject(Items)) = 'string') then
    begin
      Exit(TAtlasSettingKind.List);
    end;
  end;
  // oneOf mit String-Variante (z. B. profile): als Text, solange der Wert ein String ist.
  if Kind = 'oneOf' then
  begin
    OneOf := ASchema.GetValue('oneOf');
    if OneOf is TJSONArray then
    begin
      for Option in TJSONArray(OneOf) do
      begin
        if (Option is TJSONObject) and (TypeOf(TJSONObject(Option)) = 'string') then
        begin
          Exit(TAtlasSettingKind.Text);
        end;
      end;
    end;
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
  begin
    Exit(True);
  end;
  Value := TJSONObject.ParseJSONValue(AJson);
  if Value = nil then
  begin
    Exit(False);
  end;
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
          begin
            if Choice = Value.ToJSON then
            begin
              Result := True;
            end;
          end;
        end;
      TAtlasSettingKind.List:
        begin
          Result := Value is TJSONArray;
          if Result then
          begin
            for Item in TJSONArray(Value) do
            begin
              if not (Item is TJSONString) or (Item is TJSONNumber) then
              begin
                Result := False;
              end;
            end;
          end;
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
    begin
      Result.Description := AFallback;
    end;
    Result.Kind := KindOf(ASchema, Result.Choices);
    Default_ := ASchema.GetValue('default');
    if Default_ <> nil then
    begin
      Result.DefaultJson := Default_.ToJSON;
    end;
    Result.Control := ASchema.GetValue<string>('x-control', '');
    Examples := ASchema.GetValue('examples');
    if Examples is TJSONArray then
    begin
      for Example in TJSONArray(Examples) do
      begin
        Result.Examples := Result.Examples + [Display(Example.ToJSON)];
      end;
    end;
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
    begin
      Exit;
    end;
    Properties := TJSONObject(Root).GetValue('properties');
    if not (Properties is TJSONObject) then
    begin
      Exit;
    end;
    for Pair in TJSONObject(Properties) do
    begin
      if not (Pair.JsonValue is TJSONObject) or (Pair.JsonString.Value = '$schema') then
      begin
        Continue;
      end;
      Child := Pair.JsonValue;
      Children := TJSONObject(Child).GetValue('properties');
      // Objekt mit mindestens einem einfachen Glied: Felder je Glied, komplexe Glieder als eigenes JSON-Feld
      // (mcp.customPrompts darf mcp.globalSettings nicht verdecken).
      if (TypeOf(TJSONObject(Child)) = 'object') and (Children is TJSONObject) then
      begin
        Simple := False;
        for Sub in TJSONObject(Children) do
        begin
          if (Sub.JsonValue is TJSONObject) and
            (KindOf(TJSONObject(Sub.JsonValue), Choices) <> TAtlasSettingKind.Complex) then
          begin
            Simple := True;
          end;
        end;
        for Sub in TJSONObject(Children) do
        begin
          if not (Sub.JsonValue is TJSONObject) then
          begin
            Simple := False;
          end;
        end;
        if Simple then
        begin
          for Sub in TJSONObject(Children) do
          begin
            Result := Result + [Make(Pair.JsonString.Value + '.' + Sub.JsonString.Value,
              TJSONObject(Child).GetValue<string>('x-page', ''), TJSONObject(Sub.JsonValue),
              DescriptionOf(TJSONObject(Child)), TJSONObject(Child).GetValue<string>('x-scope', ''))];
          end;
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
    begin
      Continue;
    end;
    Excluded := False;
    for Path in AExclude do
    begin
      // Ein zusammengesetztes Feld (ganzes Objekt als JSON, z. B. "vcs" seit #1285) mit einem ausgeschlossenen
      // Glied fällt mit weg: Es im Dialog als Ganzes zu bearbeiten, überschriebe die Werte der eigenen Seite.
      if SameText(Path, Field.Path) or SameText(Copy(Path, 1, Length(Field.Path) + 1), Field.Path + '.') then
      begin
        Excluded := True;
      end;
    end;
    if not Excluded then
    begin
      Result := Result + [Field];
    end;
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
    begin
      if SameText(Page, Field.Page) then
      begin
        Known := True;
      end;
    end;
    if not Known then
    begin
      Result := Result + [Field.Page];
    end;
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
    begin
      Result := TJSONString(Value).Value;
    end;
  finally
    Value.Free;
  end;
end;

end.
