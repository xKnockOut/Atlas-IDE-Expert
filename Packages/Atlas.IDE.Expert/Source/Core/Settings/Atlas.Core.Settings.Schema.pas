unit Atlas.Core.Settings.Schema;

// Einstellungen von atlas.json aus dem JSON-Schema (#227): Seite (x-page),
// Beschreibung, Art des Bedienelements und Standardwert. Objekte mit nur
// einfachen Gliedern (compiler, format, highlight …) werden zu einzelnen
// Feldern "objekt.glied". Was sich nicht als einfaches Feld bearbeiten lässt
// (Regeln, Profile, Listen von Objekten), ist Complex und wird nur angezeigt.
// So erscheint jede neue Einstellung im Schema ohne weiteren Code im Dialog.

interface

uses
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
    /// <summary>Passt AJson (JSON-Text) zur Art des Felds? Sonst bleibt der Wert unangetastet.</summary>
    function Accepts(const AJson: string): Boolean;
  end;

  TAtlasSettingsSchema = class
  public
    /// <summary>Felder in der Reihenfolge des Schemas; leer bei ungültigem Schema.</summary>
    class function Fields(const ASchemaJson: string): TArray<TAtlasSettingField>; static;
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
      TAtlasSettingKind.Text:
        Result := Value is TJSONString;
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
              if not (Item is TJSONString) then
                Result := False;
        end;
    else
      Result := True;
    end;
  finally
    Value.Free;
  end;
end;

{ TAtlasSettingsSchema }

class function TAtlasSettingsSchema.Fields(const ASchemaJson: string): TArray<TAtlasSettingField>;
var
  Root, Properties, Child, Children: TJSONValue;
  Pair, Sub: TJSONPair;
  Field: TAtlasSettingField;
  Simple: Boolean;
  Choices: TArray<string>;

  function Make(const APath, APage: string; ASchema: TJSONObject; const AFallback: string): TAtlasSettingField;
  var
    Default_: TJSONValue;
  begin
    Result := Default(TAtlasSettingField);
    Result.Path := APath;
    Result.Page := APage;
    Result.Description := DescriptionOf(ASchema);
    if Result.Description = '' then
      Result.Description := AFallback;
    Result.Kind := KindOf(ASchema, Result.Choices);
    Default_ := ASchema.GetValue('default');
    if Default_ <> nil then
      Result.DefaultJson := Default_.ToJSON;
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
              DescriptionOf(TJSONObject(Child)))];
          Continue;
        end;
      end;
      Field := Make(Pair.JsonString.Value, TJSONObject(Child).GetValue<string>('x-page', ''),
        TJSONObject(Child), '');
      Result := Result + [Field];
    end;
  finally
    Root.Free;
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
