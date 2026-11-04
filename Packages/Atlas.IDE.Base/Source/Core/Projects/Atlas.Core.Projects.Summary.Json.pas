unit Atlas.Core.Projects.Summary.Json;

// Lesen und Schreiben einzelner Felder der Projekt-Zusammenfassung (#592),
// ohne VCL und Open Tools API: Texte, Zahlen, Schalter, Unterobjekte, Zeiten
// in UTC ("2026-10-15T09:30:00Z") und unbekannte Felder, die beim Schreiben
// erhalten bleiben. Genutzt von Atlas.Core.Projects.Summary und ihren
// Abschnitten (Atlas.Core.Projects.Summary.Sections).

interface

uses
  System.JSON;

/// <summary>Text des Felds AName; '' ohne Objekt, ohne Feld oder bei anderem Typ.</summary>
function TextOf(AObject: TJSONObject; const AName: string): string;
/// <summary>Zahl des Felds AName (auch als Text); ADefault ohne Objekt, ohne Feld oder bei anderem Typ.</summary>
function NumberOf(AObject: TJSONObject; const AName: string; ADefault: Integer): Integer;
/// <summary>Schalter des Felds AName; False ohne Objekt, ohne Feld oder bei anderem Typ.</summary>
function FlagOf(AObject: TJSONObject; const AName: string): Boolean;
/// <summary>Unterobjekt AName; nil ohne Objekt, ohne Feld oder bei anderem Typ.</summary>
function ObjectOf(AObject: TJSONObject; const AName: string): TJSONObject;
/// <summary>Unbekannte Felder aus AOriginal (darf nil sein) an ATarget anhängen.</summary>
procedure KeepUnknown(ATarget, AOriginal: TJSONObject; const AKeys: array of string);
/// <summary>Zeit AUtc als Feld AName; nichts bei 0.</summary>
procedure AddTime(AObject: TJSONObject; const AName: string; AUtc: TDateTime);
/// <summary>UTC als "2026-10-15T09:30:00Z"; '' bei 0.</summary>
function SummaryTimeText(AUtc: TDateTime): string;
/// <summary>Umkehrung von SummaryTimeText; Bruchteile und Zeitzone "Z" erlaubt; 0 bei ungültigem Text.</summary>
function SummaryTimeOf(const AText: string): TDateTime;

implementation

uses
  System.SysUtils,
  System.Math;

function Known(const AKeys: array of string; const AName: string): Boolean;
var
  Key: string;
begin
  Result := False;
  for Key in AKeys do
  begin
    if Key = AName then
    begin
      Exit(True);
    end;
  end;
end;

function TextOf(AObject: TJSONObject; const AName: string): string;
var
  Value: TJSONValue;
begin
  Result := '';
  if AObject = nil then
  begin
    Exit;
  end;
  Value := AObject.GetValue(AName);
  if Value is TJSONString then
  begin
    Result := TJSONString(Value).Value;
  end;
end;

function NumberOf(AObject: TJSONObject; const AName: string; ADefault: Integer): Integer;
var
  Value: TJSONValue;
begin
  Result := ADefault;
  if AObject = nil then
  begin
    Exit;
  end;
  Value := AObject.GetValue(AName);
  if Value is TJSONNumber then
  begin
    Result := TJSONNumber(Value).AsInt;
  end
  else if Value is TJSONString then
  begin
    Result := StrToIntDef(TJSONString(Value).Value, ADefault);
  end;
end;

function FlagOf(AObject: TJSONObject; const AName: string): Boolean;
var
  Value: TJSONValue;
begin
  Result := False;
  if AObject = nil then
  begin
    Exit;
  end;
  Value := AObject.GetValue(AName);
  if Value is TJSONBool then
  begin
    Result := SameText(Value.Value, 'true');
  end;
end;

function ObjectOf(AObject: TJSONObject; const AName: string): TJSONObject;
var
  Value: TJSONValue;
begin
  Result := nil;
  if AObject = nil then
  begin
    Exit;
  end;
  Value := AObject.GetValue(AName);
  if Value is TJSONObject then
  begin
    Result := TJSONObject(Value);
  end;
end;

procedure KeepUnknown(ATarget, AOriginal: TJSONObject; const AKeys: array of string);
var
  Index: Integer;
  Pair: TJSONPair;
begin
  if AOriginal = nil then
  begin
    Exit;
  end;
  for Index := 0 to AOriginal.Count - 1 do
  begin
    Pair := AOriginal.Pairs[Index];
    if not Known(AKeys, Pair.JsonString.Value) then
    begin
      ATarget.AddPair(Pair.JsonString.Value, TJSONValue(Pair.JsonValue.Clone));
    end;
  end;
end;

procedure AddTime(AObject: TJSONObject; const AName: string; AUtc: TDateTime);
begin
  if AUtc > 0 then
  begin
    AObject.AddPair(AName, SummaryTimeText(AUtc));
  end;
end;

function SummaryTimeText(AUtc: TDateTime): string;
var
  Year, Month, Day, Hour, Minute, Second, MSec: Word;
begin
  Result := '';
  if AUtc <= 0 then
  begin
    Exit;
  end;
  DecodeDate(AUtc, Year, Month, Day);
  DecodeTime(AUtc, Hour, Minute, Second, MSec);
  Result := System.SysUtils.Format('%.4d-%.2d-%.2dT%.2d:%.2d:%.2dZ', [Year, Month, Day, Hour, Minute, Second]);
end;

/// <summary>Trenner von yyyy-mm-ddThh:nn:ss an ihrer Stelle.</summary>
function IsTimeShape(const AText: string): Boolean;
begin
  Result := (Length(AText) >= 19) and (AText[5] = '-') and (AText[8] = '-');
  Result := Result and CharInSet(AText[11], ['T', 't', ' ']) and (AText[14] = ':') and (AText[17] = ':');
end;

function SummaryTimeOf(const AText: string): TDateTime;
var
  Text: string;
  Year, Month, Day, Hour, Minute, Second: Integer;
  DatePart, TimePart: TDateTime;
begin
  Result := 0;
  Text := Trim(AText);
  // yyyy-mm-ddThh:nn:ss, danach höchstens Bruchteile und "Z".
  if not IsTimeShape(Text) then
  begin
    Exit;
  end;
  Year := StrToIntDef(Copy(Text, 1, 4), -1);
  Month := StrToIntDef(Copy(Text, 6, 2), -1);
  Day := StrToIntDef(Copy(Text, 9, 2), -1);
  Hour := StrToIntDef(Copy(Text, 12, 2), -1);
  Minute := StrToIntDef(Copy(Text, 15, 2), -1);
  Second := StrToIntDef(Copy(Text, 18, 2), -1);
  if (Min(Year, Min(Month, Day)) < 1) or (Min(Hour, Min(Minute, Second)) < 0) then
  begin
    Exit;
  end;
  if not TryEncodeDate(Year, Month, Day, DatePart) or not TryEncodeTime(Hour, Minute, Second, 0, TimePart) then
  begin
    Exit;
  end;
  Result := DatePart + TimePart;
end;

end.
