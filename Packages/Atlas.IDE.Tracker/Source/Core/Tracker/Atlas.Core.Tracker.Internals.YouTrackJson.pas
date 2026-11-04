unit Atlas.Core.Tracker.Internals.YouTrackJson;

// Einzelne Werte aus Antworten der YouTrack-API (#765) lesen, ohne Netz und
// daher testbar. Gemeinsam für den Anbieter (Providers.YouTrack), sein Board
// (YouTrackBoards), Adressen (YouTrackApi) und das Lesen der Antworten
// (YouTrackParse).

interface

uses
  System.JSON;

type
  TAtlasYouTrackJson = class
  public
    class function TextOf(AObject: TJSONObject; const AName: string): string; static;
    class function Shorten(const AText: string; AMax: Integer): string; static;
    /// <summary>Name eines Werts: "name", sonst "presentation"; bei einer Liste die Namen mit ", ".</summary>
    class function ValueText(AValue: TJSONValue): string; static;
    class function IsOneOf(const AName: string; const ANames: array of string): Boolean; static;
    class function ValidKey(const AKey: string): Boolean; static;
    /// <summary>Millisekunden seit 1970 (YouTrack) als UTC; 0 ohne.</summary>
    class function TimeOf(AObject: TJSONObject; const AName: string): TDateTime; static;
    class function BoolOf(AObject: TJSONObject; const AName: string): Boolean; static;
    class function Limited(const AText: string): string; static;
    class function FirstText(AObject: TJSONObject; const AName, AFallback: string): string; static;
    class function ValidId(const AId: string): Boolean; static;
    /// <summary>Millisekunden seit 1970 zu einer UTC-Zeit.</summary>
    class function MsOf(ATime: TDateTime): Int64; static;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  Atlas.Core.Tracker.Contract;

class function TAtlasYouTrackJson.TextOf(AObject: TJSONObject; const AName: string): string;
var
  Value: TJSONValue;
begin
  Result := '';
  Value := AObject.Values[AName];
  if Value is TJSONString then
  begin
    Result := TJSONString(Value).Value;
  end;
end;

class function TAtlasYouTrackJson.Shorten(const AText: string; AMax: Integer): string;
begin
  Result := Trim(StringReplace(StringReplace(AText, #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]));
  if Length(Result) > AMax then
  begin
    Result := Copy(Result, 1, AMax - 1) + '…';
  end;
end;

/// <summary>Erster nicht leerer Name eines Objekts: "name", "presentation",
/// bei Benutzern (Zuständig, #1264) "fullName", dann "login".</summary>
function ObjectName(AObject: TJSONObject): string;
var
  mName: string;
begin
  Result := '';
  for mName in TArray<string>.Create('name', 'presentation', 'fullName', 'login') do
  begin
    Result := TAtlasYouTrackJson.TextOf(AObject, mName);
    if Result <> '' then
    begin
      Exit;
    end;
  end;
end;

/// <summary>Namen der Einträge einer Liste mit ", "; leere fallen weg.</summary>
function ListText(AList: TJSONArray): string;
var
  mItem: TJSONValue;
  mPart: string;
begin
  Result := '';
  for mItem in AList do
  begin
    mPart := TAtlasYouTrackJson.ValueText(mItem);
    if (mPart <> '') and (Result <> '') then
    begin
      Result := Result + ', ';
    end;
    Result := Result + mPart;
  end;
end;

/// <summary>Name eines Werts: "name", sonst "presentation"; bei einer Liste die Namen mit ", ".</summary>
class function TAtlasYouTrackJson.ValueText(AValue: TJSONValue): string;
begin
  Result := '';
  if AValue is TJSONObject then
  begin
    Result := ObjectName(TJSONObject(AValue));
  end
  else if AValue is TJSONString then
  begin
    Result := TJSONString(AValue).Value;
  end
  else if AValue is TJSONArray then
  begin
    Result := ListText(TJSONArray(AValue));
  end;
  Result := Shorten(Result, 60);
end;

class function TAtlasYouTrackJson.IsOneOf(const AName: string; const ANames: array of string): Boolean;
var
  Name: string;
begin
  Result := False;
  for Name in ANames do
  begin
    if SameText(AName, Name) then
    begin
      Exit(True);
    end;
  end;
end;

class function TAtlasYouTrackJson.ValidKey(const AKey: string): Boolean;
var
  mIndex: Integer;
begin
  Result := AKey <> '';
  for mIndex := 1 to Length(AKey) do
  begin
    if not CharInSet(AKey[mIndex], ['A'..'Z', 'a'..'z', '0'..'9', '-', '_']) then
    begin
      Exit(False);
    end;
  end;
end;

/// <summary>Millisekunden seit 1970 (YouTrack) als UTC; 0 ohne.</summary>
class function TAtlasYouTrackJson.TimeOf(AObject: TJSONObject; const AName: string): TDateTime;
var
  mValue: TJSONValue;
  mMs: Int64;
begin
  Result := 0;
  mValue := AObject.Values[AName];
  if (mValue is TJSONNumber) and TryStrToInt64(TJSONNumber(mValue).Value, mMs) and (mMs > 0) then
  begin
    Result := UnixToDateTime(mMs div 1000, True) + (mMs mod 1000) / MSecsPerDay;
  end;
end;

class function TAtlasYouTrackJson.BoolOf(AObject: TJSONObject; const AName: string): Boolean;
var
  mValue: TJSONValue;
begin
  mValue := AObject.Values[AName];
  Result := (mValue is TJSONBool) and TJSONBool(mValue).AsBoolean;
end;

class function TAtlasYouTrackJson.Limited(const AText: string): string;
begin
  Result := Copy(AText, 1, TAtlasTrackerDetails.MaxText);
end;

class function TAtlasYouTrackJson.FirstText(AObject: TJSONObject; const AName, AFallback: string): string;
begin
  Result := TextOf(AObject, AName);
  if Result = '' then
  begin
    Result := TextOf(AObject, AFallback);
  end;
end;


class function TAtlasYouTrackJson.ValidId(const AId: string): Boolean;
var
  mIndex: Integer;
begin
  Result := AId <> '';
  for mIndex := 1 to Length(AId) do
  begin
    if not CharInSet(AId[mIndex], ['A'..'Z', 'a'..'z', '0'..'9', '-', '_', '.']) then
    begin
      Exit(False);
    end;
  end;
end;

/// <summary>Millisekunden seit 1970 zu einer UTC-Zeit.</summary>
class function TAtlasYouTrackJson.MsOf(ATime: TDateTime): Int64;
begin
  Result := Round((ATime - UnixDateDelta) * MSecsPerDay);
end;

end.
