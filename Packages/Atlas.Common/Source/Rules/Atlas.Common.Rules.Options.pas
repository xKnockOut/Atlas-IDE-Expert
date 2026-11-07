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
    /// <summary>Text AName aus AOptions, sonst ADefault; ein leerer Text gilt als fehlend (#943).</summary>
    class function Text(const AOptions, AName, ADefault: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections;

function Member(const AOptions, AName: string): TJSONValue;
var
  mValue: TJSONValue;
  mPair: TJSONPair;
begin
  Result := nil;
  if Trim(AOptions) = '' then
  begin
    Exit;
  end;
  mValue := TJSONObject.ParseJSONValue(AOptions);
  try
    if not (mValue is TJSONObject) then
    begin
      Exit;
    end;
    mPair := TJSONObject(mValue).Get(AName);
    if mPair <> nil then
    begin
      Result := mPair.JsonValue.Clone as TJSONValue;
    end;
  finally
    mValue.Free;
  end;
end;

{ TRuleOptions }

class function TRuleOptions.Bool(const AOptions, AName: string; ADefault: Boolean): Boolean;
var
  mValue: TJSONValue;
begin
  Result := ADefault;
  mValue := Member(AOptions, AName);
  try
    if mValue is TJSONBool then
    begin
      Result := TJSONBool(mValue).AsBoolean;
    end;
  finally
    mValue.Free;
  end;
end;

class function TRuleOptions.Int(const AOptions, AName: string; ADefault: Integer): Integer;
var
  mValue: TJSONValue;
begin
  Result := ADefault;
  mValue := Member(AOptions, AName);
  try
    if (mValue is TJSONNumber) and not TryStrToInt(mValue.Value, Result) then
    begin
      Result := ADefault;
    end;
  finally
    mValue.Free;
  end;
end;

class function TRuleOptions.Strings(const AOptions, AName: string; const ADefault: TArray<string>): TArray<string>;
var
  mValue, mItem: TJSONValue;
begin
  Result := ADefault;
  mValue := Member(AOptions, AName);
  try
    if mValue is TJSONArray then
    begin
      Result := nil;
      for mItem in TJSONArray(mValue) do
      begin
        // TJSONNumber erbt von TJSONString: Zahlen gehören nicht in eine Textliste.
        if (mItem is TJSONString) and not (mItem is TJSONNumber) then
        begin
          Result := Result + [mItem.Value];
        end;
      end;
    end;
  finally
    mValue.Free;
  end;
end;

class function TRuleOptions.Numbers(const AOptions, AName: string; const ADefault: TArray<Double>): TArray<Double>;
var
  mValue, mItem: TJSONValue;
begin
  Result := ADefault;
  mValue := Member(AOptions, AName);
  try
    if mValue is TJSONArray then
    begin
      Result := nil;
      for mItem in TJSONArray(mValue) do
      begin
        if mItem is TJSONNumber then
        begin
          Result := Result + [TJSONNumber(mItem).AsDouble];
        end;
      end;
    end;
  finally
    mValue.Free;
  end;
end;

class function TRuleOptions.Text(const AOptions, AName, ADefault: string): string;
var
  mValue: TJSONValue;
begin
  Result := ADefault;
  mValue := Member(AOptions, AName);
  try
    // TJSONNumber erbt von TJSONString.
    if (mValue is TJSONString) and not (mValue is TJSONNumber) and (Trim(mValue.Value) <> '') then
    begin
      Result := Trim(mValue.Value);
    end;
  finally
    mValue.Free;
  end;
end;

end.
