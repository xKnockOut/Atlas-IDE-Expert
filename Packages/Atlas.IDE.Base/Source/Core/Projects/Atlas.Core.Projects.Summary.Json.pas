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
  System.Generics.Collections,
  System.SysUtils,
  System.Math;

function Known(const AKeys: array of string; const AName: string): Boolean;
var
  mKey: string;
begin
  Result := False;
  for mKey in AKeys do
  begin
    if mKey = AName then
    begin
      Exit(True);
    end;
  end;
end;

function TextOf(AObject: TJSONObject; const AName: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  if AObject = nil then
  begin
    Exit;
  end;
  mValue := AObject.GetValue(AName);
  if mValue is TJSONString then
  begin
    Result := TJSONString(mValue).Value;
  end;
end;

function NumberOf(AObject: TJSONObject; const AName: string; ADefault: Integer): Integer;
var
  mValue: TJSONValue;
begin
  Result := ADefault;
  if AObject = nil then
  begin
    Exit;
  end;
  mValue := AObject.GetValue(AName);
  if mValue is TJSONNumber then
  begin
    Result := TJSONNumber(mValue).AsInt;
  end
  else if mValue is TJSONString then
  begin
    Result := StrToIntDef(TJSONString(mValue).Value, ADefault);
  end;
end;

function FlagOf(AObject: TJSONObject; const AName: string): Boolean;
var
  mValue: TJSONValue;
begin
  Result := False;
  if AObject = nil then
  begin
    Exit;
  end;
  mValue := AObject.GetValue(AName);
  if mValue is TJSONBool then
  begin
    Result := SameText(mValue.Value, 'true');
  end;
end;

function ObjectOf(AObject: TJSONObject; const AName: string): TJSONObject;
var
  mValue: TJSONValue;
begin
  Result := nil;
  if AObject = nil then
  begin
    Exit;
  end;
  mValue := AObject.GetValue(AName);
  if mValue is TJSONObject then
  begin
    Result := TJSONObject(mValue);
  end;
end;

procedure KeepUnknown(ATarget, AOriginal: TJSONObject; const AKeys: array of string);
var
  mIndex: Integer;
  mPair: TJSONPair;
begin
  if AOriginal = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to AOriginal.Count - 1 do
  begin
    mPair := AOriginal.Pairs[mIndex];
    if not Known(AKeys, mPair.JsonString.Value) then
    begin
      ATarget.AddPair(mPair.JsonString.Value, TJSONValue(mPair.JsonValue.Clone));
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
  mYear, mMonth, mDay, mHour, mMinute, mSecond, mMSec: Word;
begin
  Result := '';
  if AUtc <= 0 then
  begin
    Exit;
  end;
  DecodeDate(AUtc, mYear, mMonth, mDay);
  DecodeTime(AUtc, mHour, mMinute, mSecond, mMSec);
  Result := System.SysUtils.Format('%.4d-%.2d-%.2dT%.2d:%.2d:%.2dZ', [mYear, mMonth, mDay, mHour, mMinute, mSecond]);
end;

/// <summary>Trenner von yyyy-mm-ddThh:nn:ss an ihrer Stelle.</summary>
function IsTimeShape(const AText: string): Boolean;
begin
  Result := (Length(AText) >= 19) and (AText[5] = '-') and (AText[8] = '-');
  Result := Result and CharInSet(AText[11], ['T', 't', ' ']) and (AText[14] = ':') and (AText[17] = ':');
end;

function SummaryTimeOf(const AText: string): TDateTime;
var
  mText: string;
  mYear, mMonth, mDay, mHour, mMinute, mSecond: Integer;
  mDatePart, mTimePart: TDateTime;
begin
  Result := 0;
  mText := Trim(AText);
  // yyyy-mm-ddThh:nn:ss, danach höchstens Bruchteile und "Z".
  if not IsTimeShape(mText) then
  begin
    Exit;
  end;
  mYear := StrToIntDef(Copy(mText, 1, 4), -1);
  mMonth := StrToIntDef(Copy(mText, 6, 2), -1);
  mDay := StrToIntDef(Copy(mText, 9, 2), -1);
  mHour := StrToIntDef(Copy(mText, 12, 2), -1);
  mMinute := StrToIntDef(Copy(mText, 15, 2), -1);
  mSecond := StrToIntDef(Copy(mText, 18, 2), -1);
  if (Min(mYear, Min(mMonth, mDay)) < 1) or (Min(mHour, Min(mMinute, mSecond)) < 0) then
  begin
    Exit;
  end;
  if not TryEncodeDate(mYear, mMonth, mDay, mDatePart) or not TryEncodeTime(mHour, mMinute, mSecond, 0, mTimePart) then
  begin
    Exit;
  end;
  Result := mDatePart + mTimePart;
end;

end.
