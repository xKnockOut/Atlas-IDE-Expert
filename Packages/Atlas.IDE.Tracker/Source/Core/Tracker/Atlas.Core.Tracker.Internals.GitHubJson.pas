unit Atlas.Core.Tracker.Internals.GitHubJson;

// Einzelne Werte aus Antworten der GitHub-API (#765) lesen, ohne Netz und
// daher testbar. Gemeinsam für den Anbieter (Providers.GitHub), sein Board
// (GitHubBoards) und das Lesen der Antworten (GitHubParse).

interface

uses
  System.JSON;

type
  TAtlasGitHubJson = class
  public
    /// <summary>Text des Felds AName; '' ohne Feld oder bei anderem Typ.</summary>
    class function TextOf(AObject: TJSONObject; const AName: string): string; static;
    /// <summary>Positive ganze Zahl des Felds AName; 0 ohne, bei anderem Typ oder außerhalb von Integer.</summary>
    class function IntOf(AObject: TJSONObject; const AName: string): Integer; static;
    /// <summary>True nur bei einem Feld AName mit true.</summary>
    class function FlagOf(AObject: TJSONObject; const AName: string): Boolean; static;
    /// <summary>Eine Zeile (Umbrüche als Leerzeichen), höchstens AMax Zeichen mit „…“.</summary>
    class function Shorten(const AText: string; AMax: Integer): string; static;
    /// <summary>Logins aus "assignees" mit ", ", ersatzweise "assignee"; '' ohne.</summary>
    class function AssigneesOf(AObject: TJSONObject): string; static;
    /// <summary>ISO 8601 ("2026-10-28T10:40:49Z") als UTC; 0 ohne.</summary>
    class function TimeOf(AObject: TJSONObject; const AName: string): TDateTime; static;
    /// <summary>"login" eines Benutzerobjekts, gekürzt; '' ohne.</summary>
    class function LoginOf(AValue: TJSONValue): string; static;
    /// <summary>AText, höchstens TAtlasTrackerDetails.MaxText Zeichen.</summary>
    class function Limited(const AText: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  Atlas.Core.Tracker.Contract;

class function TAtlasGitHubJson.TextOf(AObject: TJSONObject; const AName: string): string;
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

class function TAtlasGitHubJson.IntOf(AObject: TJSONObject; const AName: string): Integer;
var
  Value: TJSONValue;
  Number: Int64;
begin
  Result := 0;
  Value := AObject.Values[AName];
  if (Value is TJSONNumber) and TryStrToInt64(TJSONNumber(Value).Value, Number) and (Number > 0) and
    (Number <= MaxInt) then
  begin
    Result := Integer(Number);
  end;
end;

class function TAtlasGitHubJson.FlagOf(AObject: TJSONObject; const AName: string): Boolean;
var
  Value: TJSONValue;
begin
  Value := AObject.Values[AName];
  Result := (Value is TJSONBool) and TJSONBool(Value).AsBoolean;
end;

class function TAtlasGitHubJson.Shorten(const AText: string; AMax: Integer): string;
begin
  Result := Trim(StringReplace(StringReplace(AText, #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]));
  if Length(Result) > AMax then
  begin
    Result := Copy(Result, 1, AMax - 1) + '…';
  end;
end;

/// <summary>Logins aus "assignees" mit ", ", ersatzweise "assignee"; '' ohne.</summary>
class function TAtlasGitHubJson.AssigneesOf(AObject: TJSONObject): string;
var
  mItem, mEntry: TJSONValue;
  mText: string;
begin
  Result := '';
  mItem := AObject.Values['assignees'];
  if mItem is TJSONArray then
  begin
    for mEntry in TJSONArray(mItem) do
    begin
      mText := '';
      if mEntry is TJSONObject then
      begin
        mText := Shorten(TextOf(TJSONObject(mEntry), 'login'), 60);
      end;
      if mText = '' then
      begin
        Continue;
      end;
      if Result <> '' then
      begin
        Result := Result + ', ';
      end;
      Result := Result + mText;
    end;
  end;
  mItem := AObject.Values['assignee'];
  if (Result = '') and (mItem is TJSONObject) then
  begin
    Result := Shorten(TextOf(TJSONObject(mItem), 'login'), 60);
  end;
end;

/// <summary>ISO 8601 ("2026-10-28T10:40:49Z") als UTC; 0 ohne.</summary>
class function TAtlasGitHubJson.TimeOf(AObject: TJSONObject; const AName: string): TDateTime;
var
  mText: string;
begin
  Result := 0;
  mText := TextOf(AObject, AName);
  if (mText = '') or not TryISO8601ToDate(mText, Result, True) then
  begin
    Result := 0;
  end;
end;

class function TAtlasGitHubJson.LoginOf(AValue: TJSONValue): string;
begin
  Result := '';
  if AValue is TJSONObject then
  begin
    Result := Shorten(TextOf(TJSONObject(AValue), 'login'), 60);
  end;
end;

class function TAtlasGitHubJson.Limited(const AText: string): string;
begin
  Result := Copy(AText, 1, TAtlasTrackerDetails.MaxText);
end;

end.
