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
    /// <summary>Positive ganze Zahl des Felds AName; 0 ohne, bei anderem Typ oder außerhalb von Integer.</summary>
    class function IntOf(AObject: TJSONObject; const AName: string): Integer; static;
    /// <summary>Eine Zeile (Umbrüche als Leerzeichen), höchstens AMax Zeichen mit „…“.</summary>
    class function Shorten(const AText: string; AMax: Integer): string; static;
    /// <summary>Logins aus "assignees" mit ", ", ersatzweise "assignee"; '' ohne.</summary>
    class function AssigneesOf(AObject: TJSONObject): string; static;
    /// <summary>ISO 8601 ("2026-10-28T10:40:49Z") als UTC; 0 ohne.</summary>
    class function TimeOf(AObject: TJSONObject; const AName: string): TDateTime; static;
    /// <summary>"login" eines Benutzerobjekts, gekürzt; '' ohne.</summary>
    class function LoginOf(AValue: TJSONValue): string; static;
    /// <summary>AText, höchstens TAtlasTrackerDetails.cMaxText Zeichen.</summary>
    class function Limited(const AText: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  System.Math,
  Atlas.Core.Tracker.Contract,
  Atlas.Text.Json;

class function TAtlasGitHubJson.IntOf(AObject: TJSONObject; const AName: string): Integer;
begin
  Result := Max(0, TJsonRead.Int(AObject, AName));
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
        mText := Shorten(TJsonRead.Text(TJSONObject(mEntry), 'login'), 60);
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
    Result := Shorten(TJsonRead.Text(TJSONObject(mItem), 'login'), 60);
  end;
end;

/// <summary>ISO 8601 ("2026-10-28T10:40:49Z") als UTC; 0 ohne.</summary>
class function TAtlasGitHubJson.TimeOf(AObject: TJSONObject; const AName: string): TDateTime;
var
  mText: string;
begin
  Result := 0;
  mText := TJsonRead.Text(AObject, AName);
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
    Result := Shorten(TJsonRead.Text(TJSONObject(AValue), 'login'), 60);
  end;
end;

class function TAtlasGitHubJson.Limited(const AText: string): string;
begin
  Result := Copy(AText, 1, TAtlasTrackerDetails.cMaxText);
end;

end.
