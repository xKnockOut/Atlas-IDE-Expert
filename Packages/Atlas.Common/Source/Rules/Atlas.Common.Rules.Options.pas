unit Atlas.Common.Rules.Options;

// Optionen einer Prüfregel aus atlas.json lesen (#909): TRuleContext.Options
// ist der JSON-Text des Regelobjekts, z. B. {"severity": "warning",
// "allowCommented": false}. Fehlt die Option oder hat sie den falschen Typ,
// gilt die Vorgabe; der Konfigurationsparser meldet falsche Typen selbst.

interface

type
  TRuleOptions = record
  public
    /// <summary>Wahrheitswert AName aus AOptions, sonst ADefault.</summary>
    class function Bool(const AOptions, AName: string; ADefault: Boolean): Boolean; static;
    /// <summary>Ganze Zahl AName aus AOptions, sonst ADefault.</summary>
    class function Int(const AOptions, AName: string; ADefault: Integer): Integer; static;
    /// <summary>Liste von Texten AName aus AOptions, sonst ADefault.</summary>
    class function Strings(const AOptions, AName: string; const ADefault: TArray<string>): TArray<string>; static;
    /// <summary>Liste von Zahlen AName aus AOptions, sonst ADefault (#937).</summary>
    class function Numbers(const AOptions, AName: string; const ADefault: TArray<Double>): TArray<Double>; static;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections;

function Member(const AOptions, AName: string): TJSONValue;
var
  Value: TJSONValue;
  Pair: TJSONPair;
begin
  Result := nil;
  if Trim(AOptions) = '' then
    Exit;
  Value := TJSONObject.ParseJSONValue(AOptions);
  try
    if not (Value is TJSONObject) then
      Exit;
    Pair := TJSONObject(Value).Get(AName);
    if Pair <> nil then
      Result := Pair.JsonValue.Clone as TJSONValue;
  finally
    Value.Free;
  end;
end;

{ TRuleOptions }

class function TRuleOptions.Bool(const AOptions, AName: string; ADefault: Boolean): Boolean;
var
  Value: TJSONValue;
begin
  Result := ADefault;
  Value := Member(AOptions, AName);
  try
    if Value is TJSONBool then
      Result := TJSONBool(Value).AsBoolean;
  finally
    Value.Free;
  end;
end;

class function TRuleOptions.Int(const AOptions, AName: string; ADefault: Integer): Integer;
var
  Value: TJSONValue;
begin
  Result := ADefault;
  Value := Member(AOptions, AName);
  try
    if (Value is TJSONNumber) and not TryStrToInt(Value.Value, Result) then
      Result := ADefault;
  finally
    Value.Free;
  end;
end;

class function TRuleOptions.Strings(const AOptions, AName: string; const ADefault: TArray<string>): TArray<string>;
var
  Value, Item: TJSONValue;
begin
  Result := ADefault;
  Value := Member(AOptions, AName);
  try
    if Value is TJSONArray then
    begin
      Result := nil;
      for Item in TJSONArray(Value) do
        // TJSONNumber erbt von TJSONString: Zahlen gehören nicht in eine Textliste.
        if (Item is TJSONString) and not (Item is TJSONNumber) then
          Result := Result + [Item.Value];
    end;
  finally
    Value.Free;
  end;
end;

class function TRuleOptions.Numbers(const AOptions, AName: string; const ADefault: TArray<Double>): TArray<Double>;
var
  Value, Item: TJSONValue;
begin
  Result := ADefault;
  Value := Member(AOptions, AName);
  try
    if Value is TJSONArray then
    begin
      Result := nil;
      for Item in TJSONArray(Value) do
        if Item is TJSONNumber then
          Result := Result + [TJSONNumber(Item).AsDouble];
    end;
  finally
    Value.Free;
  end;
end;

end.
