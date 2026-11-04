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
  begin
    Exit;
  end;
  Text := AValue.ToString;
  Result := (Pos('.', Text) = 0) and (Pos('e', LowerCase(Text)) = 0);
end;

function HasType(AValue: TJSONValue; const AType: string): Boolean;
begin
  if AType = 'string' then
  begin
    Result := IsText(AValue);
  end
  else if AType = 'integer' then
  begin
    Result := IsInteger(AValue);
  end
  else if AType = 'number' then
  begin
    Result := AValue is TJSONNumber;
  end
  else if AType = 'boolean' then
  begin
    Result := AValue is TJSONBool;
  end
  else if AType = 'object' then
  begin
    Result := AValue is TJSONObject;
  end
  else if AType = 'array' then
  begin
    Result := AValue is TJSONArray;
  end
  else if AType = 'null' then
  begin
    Result := AValue is TJSONNull;
  end
  else
  begin
    // Unbekannter Typ im Schema: nicht ablehnen.
    Result := True;
  end;
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
    begin
      if IsText(Item) then
      begin
        if AExpected <> '' then
        begin
          AExpected := AExpected + '|';
        end;
        AExpected := AExpected + Item.Value;
        if HasType(AValue, Item.Value) then
        begin
          Exit(True);
        end;
      end;
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
  begin
    Path := '(Wurzel)';
  end;
  AIssues := AIssues + [Path + ': ' + AMessage];
end;

function Child(const APath, AName: string): string;
begin
  if APath = '' then
  begin
    Result := AName;
  end
  else
  begin
    Result := APath + '.' + AName;
  end;
end;

function NumberOf(AValue: TJSONValue): Double;
begin
  Result := 0;
  if AValue is TJSONNumber then
  begin
    Result := TJSONNumber(AValue).AsDouble;
  end;
end;

/// <summary>"oneOf": AValue muss zu genau einer Variante passen.</summary>
procedure CheckOneOf(AValue: TJSONValue; AVariants: TJSONArray; const APath: string; var AIssues: TArray<string>);
var
  mItem: TJSONValue;
  mMatches: Integer;
  mProbe: TArray<string>;
begin
  mMatches := 0;
  for mItem in AVariants do
  begin
    if mItem is TJSONObject then
    begin
      mProbe := nil;
      TAtlasSchemaCheck.Check(AValue, TJSONObject(mItem), APath, mProbe);
      if Length(mProbe) = 0 then
      begin
        Inc(mMatches);
      end;
    end;
  end;
  if mMatches <> 1 then
  begin
    Add(AIssues, APath, 'passt zu keiner erlaubten Form');
  end;
end;

procedure CheckEnum(AValue, AEnum: TJSONValue; const APath: string; var AIssues: TArray<string>);
var
  mItem: TJSONValue;
begin
  if not (AEnum is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(AEnum) do
  begin
    if mItem.ToJSON = AValue.ToJSON then
    begin
      Exit;
    end;
  end;
  Add(AIssues, APath, 'Wert ' + AValue.ToJSON + ' ist nicht erlaubt');
end;

procedure CheckRange(AValue: TJSONValue; ASchema: TJSONObject; const APath: string; var AIssues: TArray<string>);
var
  mBound: TJSONValue;
begin
  mBound := ASchema.GetValue('minimum');
  if (mBound is TJSONNumber) and (NumberOf(AValue) < NumberOf(mBound)) then
  begin
    Add(AIssues, APath, 'kleiner als ' + mBound.ToJSON);
  end;
  mBound := ASchema.GetValue('maximum');
  if (mBound is TJSONNumber) and (NumberOf(AValue) > NumberOf(mBound)) then
  begin
    Add(AIssues, APath, 'größer als ' + mBound.ToJSON);
  end;
end;

procedure CheckRequired(AObject: TJSONObject; ARequired: TJSONValue; const APath: string;
  var AIssues: TArray<string>);
var
  mItem: TJSONValue;
begin
  if not (ARequired is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(ARequired) do
  begin
    if IsText(mItem) and (AObject.GetValue(mItem.Value) = nil) then
    begin
      Add(AIssues, Child(APath, mItem.Value), 'fehlt');
    end;
  end;
end;

/// <summary>Ein Glied gegen sein Schema aus AProperties, sonst gegen "additionalProperties".</summary>
procedure CheckMember(APair: TJSONPair; AProperties, AAdditional: TJSONValue; const APath: string;
  var AIssues: TArray<string>);
var
  mSub: TJSONValue;
  mPath: string;
begin
  mSub := nil;
  if AProperties is TJSONObject then
  begin
    mSub := TJSONObject(AProperties).GetValue(APair.JsonString.Value);
  end;
  mPath := Child(APath, APair.JsonString.Value);
  if mSub is TJSONObject then
  begin
    TAtlasSchemaCheck.Check(APair.JsonValue, TJSONObject(mSub), mPath, AIssues);
  end
  else if AAdditional is TJSONObject then
  begin
    TAtlasSchemaCheck.Check(APair.JsonValue, TJSONObject(AAdditional), mPath, AIssues);
  end
  else if (AAdditional is TJSONBool) and not TJSONBool(AAdditional).AsBoolean then
  begin
    Add(AIssues, mPath, 'unbekannter Schlüssel');
  end;
end;

procedure CheckMembers(AObject, ASchema: TJSONObject; const APath: string; var AIssues: TArray<string>);
var
  mProperties, mAdditional: TJSONValue;
  mIndex: Integer;
begin
  mProperties := ASchema.GetValue('properties');
  mAdditional := ASchema.GetValue('additionalProperties');
  CheckRequired(AObject, ASchema.GetValue('required'), APath, AIssues);
  for mIndex := 0 to AObject.Count - 1 do
  begin
    CheckMember(AObject.Pairs[mIndex], mProperties, mAdditional, APath, AIssues);
  end;
end;

procedure CheckItems(AArray: TJSONArray; ASchema: TJSONObject; const APath: string; var AIssues: TArray<string>);
var
  mItems: TJSONValue;
  mIndex: Integer;
begin
  mItems := ASchema.GetValue('items');
  if not (mItems is TJSONObject) then
  begin
    Exit;
  end;
  for mIndex := 0 to AArray.Count - 1 do
  begin
    TAtlasSchemaCheck.Check(AArray.Items[mIndex], TJSONObject(mItems), APath + '[' + IntToStr(mIndex) + ']',
      AIssues);
  end;
end;

/// <summary>Schlüssel der obersten Ebene mit anderem x-scope als AScope (außer "both") melden.</summary>
procedure CheckScopes(ARoot, ASchema: TJSONObject; const AScope: string; var AIssues: TArray<string>);
var
  mProperties, mField, mScope: TJSONValue;
  mIndex: Integer;
  mName: string;
begin
  mProperties := ASchema.GetValue('properties');
  if (AScope = '') or not (mProperties is TJSONObject) then
  begin
    Exit;
  end;
  for mIndex := 0 to ARoot.Count - 1 do
  begin
    mName := ARoot.Pairs[mIndex].JsonString.Value;
    mField := TJSONObject(mProperties).GetValue(mName);
    mScope := nil;
    if mField is TJSONObject then
    begin
      mScope := TJSONObject(mField).GetValue('x-scope');
    end;
    if IsText(mScope) and not SameText(mScope.Value, AScope) and not SameText(mScope.Value, 'both') then
    begin
      Add(AIssues, mName, 'gehört in die Einstellungen "' + mScope.Value + '"');
    end;
  end;
end;

function ParsedRoot(const AText: string): TJSONObject;
begin
  try
    Result := TAtlasJsonText.Parse(AText);
  except
    on Exception do
      Result := nil;
  end;
end;

function ParsedSchema(const ASchemaJson: string): TJSONValue;
begin
  try
    Result := TJSONObject.ParseJSONValue(ASchemaJson);
  except
    on Exception do
      Result := nil;
  end;
end;

{ TAtlasSchemaCheck }

class procedure TAtlasSchemaCheck.Check(AValue: TJSONValue; ASchema: TJSONObject; const APath: string;
  var AIssues: TArray<string>);
var
  mExpected: string;
  mVariants: TJSONValue;
begin
  if (AValue = nil) or (ASchema = nil) then
  begin
    Exit;
  end;
  mVariants := ASchema.GetValue('oneOf');
  if mVariants is TJSONArray then
  begin
    CheckOneOf(AValue, TJSONArray(mVariants), APath, AIssues);
    Exit;
  end;
  if not TypeMatches(AValue, ASchema.GetValue('type'), mExpected) then
  begin
    Add(AIssues, APath, 'erwartet ' + mExpected);
    Exit;
  end;
  CheckEnum(AValue, ASchema.GetValue('enum'), APath, AIssues);
  if AValue is TJSONNumber then
  begin
    CheckRange(AValue, ASchema, APath, AIssues);
  end
  else if AValue is TJSONObject then
  begin
    CheckMembers(TJSONObject(AValue), ASchema, APath, AIssues);
  end
  else if AValue is TJSONArray then
  begin
    CheckItems(TJSONArray(AValue), ASchema, APath, AIssues);
  end;
end;

class function TAtlasSchemaCheck.Validate(const AText, ASchemaJson, AScope: string;
  out AIssues: TArray<string>): Boolean;
var
  mRoot: TJSONObject;
  mSchema: TJSONValue;
begin
  AIssues := nil;
  mRoot := ParsedRoot(AText);
  mSchema := nil;
  try
    if mRoot = nil then
    begin
      Add(AIssues, '', 'kein gültiges JSON-Objekt');
    end
    else
    begin
      mSchema := ParsedSchema(ASchemaJson);
      if mSchema is TJSONObject then
      begin
        Check(mRoot, TJSONObject(mSchema), '', AIssues);
        CheckScopes(mRoot, TJSONObject(mSchema), AScope, AIssues);
      end
      else
      begin
        Add(AIssues, '', 'Schema nicht lesbar');
      end;
    end;
    Result := Length(AIssues) = 0;
  finally
    mSchema.Free;
    mRoot.Free;
  end;
end;

end.
