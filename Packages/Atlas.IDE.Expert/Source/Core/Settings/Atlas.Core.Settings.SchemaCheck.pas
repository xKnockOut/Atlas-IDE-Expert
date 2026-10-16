unit Atlas.Core.Settings.SchemaCheck;

// Prüft eine atlas.json gegen schemas/atlas.schema.json (#759), ohne VCL und
// Open Tools API und ohne Server: Die Einrichtung legt eine Datei aus einer
// Vorlage an und prüft sie vorher; die Tests prüfen damit die mitgelieferten
// Vorlagen. Der Server bleibt die maßgebliche Prüfung beim Laden
// (atlas.server.checkSettings, #227); dies hier ist die Teilmenge von JSON
// Schema (draft-07), die atlas.schema.json nutzt: type (auch als Liste),
// enum, oneOf, properties, additionalProperties (false oder Schema),
// required, items, minimum und maximum. pattern wird nicht geprüft.
//
// AScope: Schlüssel der obersten Ebene mit einem anderen x-scope (z. B.
// "global" in einer atlas.json des Projekts) sind ein Fehler, wie beim Server
// („Ein Schlüssel am falschen Ort wird ignoriert und gemeldet“).

interface

uses
  System.SysUtils,
  System.JSON;

type
  TAtlasSchemaCheck = class
  public
    /// <summary>Prüft AText (JSON, Kommentare erlaubt) gegen ASchemaJson. AScope "project" oder "global";
    /// '' prüft den Ort nicht. AIssues: "Pfad: Meldung" je Fehler. True ohne Fehler.</summary>
    class function Validate(const AText, ASchemaJson, AScope: string; out AIssues: TArray<string>): Boolean; static;
    /// <summary>Prüft AValue gegen ASchema; Meldungen werden an AIssues angehängt.</summary>
    class procedure Check(AValue: TJSONValue; ASchema: TJSONObject; const APath: string;
      var AIssues: TArray<string>); static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Core.Settings.JsonText;

function IsText(AValue: TJSONValue): Boolean;
begin
  Result := (AValue is TJSONString) and not (AValue is TJSONNumber);
end;

function IsInteger(AValue: TJSONValue): Boolean;
var
  Text: string;
begin
  Result := False;
  if not (AValue is TJSONNumber) then
    Exit;
  Text := AValue.ToString;
  Result := (Pos('.', Text) = 0) and (Pos('e', LowerCase(Text)) = 0);
end;

function HasType(AValue: TJSONValue; const AType: string): Boolean;
begin
  if AType = 'string' then
    Result := IsText(AValue)
  else if AType = 'integer' then
    Result := IsInteger(AValue)
  else if AType = 'number' then
    Result := AValue is TJSONNumber
  else if AType = 'boolean' then
    Result := AValue is TJSONBool
  else if AType = 'object' then
    Result := AValue is TJSONObject
  else if AType = 'array' then
    Result := AValue is TJSONArray
  else if AType = 'null' then
    Result := AValue is TJSONNull
  else
    // Unbekannter Typ im Schema: nicht ablehnen.
    Result := True;
end;

function TypeMatches(AValue: TJSONValue; AType: TJSONValue; out AExpected: string): Boolean;
var
  Item: TJSONValue;
begin
  AExpected := '';
  if IsText(AType) then
  begin
    AExpected := AType.Value;
    Exit(HasType(AValue, AExpected));
  end;
  if AType is TJSONArray then
  begin
    for Item in TJSONArray(AType) do
      if IsText(Item) then
      begin
        if AExpected <> '' then
          AExpected := AExpected + '|';
        AExpected := AExpected + Item.Value;
        if HasType(AValue, Item.Value) then
          Exit(True);
      end;
    Exit(False);
  end;
  Result := True;
end;

procedure Add(var AIssues: TArray<string>; const APath, AMessage: string);
var
  Path: string;
begin
  Path := APath;
  if Path = '' then
    Path := '(Wurzel)';
  AIssues := AIssues + [Path + ': ' + AMessage];
end;

function Child(const APath, AName: string): string;
begin
  if APath = '' then
    Result := AName
  else
    Result := APath + '.' + AName;
end;

function NumberOf(AValue: TJSONValue): Double;
begin
  Result := 0;
  if AValue is TJSONNumber then
    Result := TJSONNumber(AValue).AsDouble;
end;

{ TAtlasSchemaCheck }

class procedure TAtlasSchemaCheck.Check(AValue: TJSONValue; ASchema: TJSONObject; const APath: string;
  var AIssues: TArray<string>);
var
  Expected: string;
  Variants, Enum, Required, Item: TJSONValue;
  Properties, Additional, Items, Sub: TJSONValue;
  Matches, Index: Integer;
  Probe: TArray<string>;
  Found: Boolean;
  Pair: TJSONPair;
begin
  if (AValue = nil) or (ASchema = nil) then
    Exit;
  Variants := ASchema.GetValue('oneOf');
  if Variants is TJSONArray then
  begin
    Matches := 0;
    for Item in TJSONArray(Variants) do
      if Item is TJSONObject then
      begin
        Probe := nil;
        Check(AValue, TJSONObject(Item), APath, Probe);
        if Length(Probe) = 0 then
          Inc(Matches);
      end;
    if Matches <> 1 then
      Add(AIssues, APath, 'passt zu keiner erlaubten Form');
    Exit;
  end;
  if not TypeMatches(AValue, ASchema.GetValue('type'), Expected) then
  begin
    Add(AIssues, APath, 'erwartet ' + Expected);
    Exit;
  end;
  Enum := ASchema.GetValue('enum');
  if Enum is TJSONArray then
  begin
    Found := False;
    for Item in TJSONArray(Enum) do
      if Item.ToJSON = AValue.ToJSON then
        Found := True;
    if not Found then
      Add(AIssues, APath, 'Wert ' + AValue.ToJSON + ' ist nicht erlaubt');
  end;
  if AValue is TJSONNumber then
  begin
    Sub := ASchema.GetValue('minimum');
    if (Sub is TJSONNumber) and (NumberOf(AValue) < NumberOf(Sub)) then
      Add(AIssues, APath, 'kleiner als ' + Sub.ToJSON);
    Sub := ASchema.GetValue('maximum');
    if (Sub is TJSONNumber) and (NumberOf(AValue) > NumberOf(Sub)) then
      Add(AIssues, APath, 'größer als ' + Sub.ToJSON);
  end;
  if AValue is TJSONObject then
  begin
    Properties := ASchema.GetValue('properties');
    Additional := ASchema.GetValue('additionalProperties');
    Required := ASchema.GetValue('required');
    if Required is TJSONArray then
      for Item in TJSONArray(Required) do
        if IsText(Item) and (TJSONObject(AValue).GetValue(Item.Value) = nil) then
          Add(AIssues, Child(APath, Item.Value), 'fehlt');
    for Index := 0 to TJSONObject(AValue).Count - 1 do
    begin
      Pair := TJSONObject(AValue).Pairs[Index];
      Sub := nil;
      if Properties is TJSONObject then
        Sub := TJSONObject(Properties).GetValue(Pair.JsonString.Value);
      if Sub is TJSONObject then
        Check(Pair.JsonValue, TJSONObject(Sub), Child(APath, Pair.JsonString.Value), AIssues)
      else if Additional is TJSONObject then
        Check(Pair.JsonValue, TJSONObject(Additional), Child(APath, Pair.JsonString.Value), AIssues)
      else if (Additional is TJSONBool) and not TJSONBool(Additional).AsBoolean then
        Add(AIssues, Child(APath, Pair.JsonString.Value), 'unbekannter Schlüssel');
    end;
  end;
  if AValue is TJSONArray then
  begin
    Items := ASchema.GetValue('items');
    if Items is TJSONObject then
      for Index := 0 to TJSONArray(AValue).Count - 1 do
        Check(TJSONArray(AValue).Items[Index], TJSONObject(Items), APath + '[' + IntToStr(Index) + ']', AIssues);
  end;
end;

class function TAtlasSchemaCheck.Validate(const AText, ASchemaJson, AScope: string;
  out AIssues: TArray<string>): Boolean;
var
  Root: TJSONObject;
  Schema: TJSONValue;
  Properties, Field, Scope: TJSONValue;
  Index: Integer;
  Pair: TJSONPair;
begin
  AIssues := nil;
  Root := nil;
  Schema := nil;
  try
    try
      Root := TAtlasJsonText.Parse(AText);
    except
      on Exception do
        Root := nil;
    end;
    if Root = nil then
    begin
      Add(AIssues, '', 'kein gültiges JSON-Objekt');
      Exit(False);
    end;
    try
      Schema := TJSONObject.ParseJSONValue(ASchemaJson);
    except
      on Exception do
        Schema := nil;
    end;
    if not (Schema is TJSONObject) then
    begin
      Add(AIssues, '', 'Schema nicht lesbar');
      Exit(False);
    end;
    Check(Root, TJSONObject(Schema), '', AIssues);
    if AScope <> '' then
    begin
      Properties := TJSONObject(Schema).GetValue('properties');
      if Properties is TJSONObject then
        for Index := 0 to Root.Count - 1 do
        begin
          Pair := Root.Pairs[Index];
          Field := TJSONObject(Properties).GetValue(Pair.JsonString.Value);
          if not (Field is TJSONObject) then
            Continue;
          Scope := TJSONObject(Field).GetValue('x-scope');
          if IsText(Scope) and not SameText(Scope.Value, AScope) then
            Add(AIssues, Pair.JsonString.Value, 'gehört in die Einstellungen "' + Scope.Value + '"');
        end;
    end;
    Result := Length(AIssues) = 0;
  finally
    Schema.Free;
    Root.Free;
  end;
end;

end.
