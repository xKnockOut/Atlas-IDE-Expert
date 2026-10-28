unit Atlas.Core.Tracker.Providers.YouTrack;

// Issue-Tracker YouTrack (#765), Cloud und Server, ohne VCL und Open Tools
// API. Das Netz kommt über IAtlasCiTransport von außen.
// - Anmeldung mit permanentem Token („Authorization: Bearer perm-…“, älter perm:…), nur an
//   den eingetragenen Server.
// - Issues: GET <url>/api/issues?query=<Abfrage>&fields=idReadable,
//   numberInProject,summary,customFields(name,value(name,presentation))
//   &$top=<Max>. Die Abfrage ist die Suchsprache der YouTrack-Oberfläche
//   (Vorgabe "for: me #Unresolved"); mit Projektkürzel aus .atlas steht
//   "project: <Kürzel>" davor, damit die Liste dieselben Issues zeigt wie die
//   Suche dort im Projekt.
// - Felder: Zustand (State, Status, Zustand), Priorität (Priority,
//   Priorität) und Sprint bzw. Board (Sprint, Sprints, Board); Werte als
//   Objekt oder Liste mit "name" (bzw. "presentation").
// - Browser: <url>/issue/<Kennung>.

interface

uses
  System.SysUtils,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract;

type
  TAtlasYouTrackTracker = class(TInterfacedObject, IAtlasTrackerProvider)
  public const
    ProviderName = 'youtrack';
    Query = 'for: me #Unresolved';
    Fields = 'idReadable,numberInProject,summary,customFields(name,value(name,presentation))';
  public
    class function IssuesUrl(const ATarget: TAtlasTrackerTarget; AMax: Integer): string; static;
    /// <summary>Abfrage, wie sie an YouTrack geht (mit "project: …").</summary>
    class function FullQuery(const ATarget: TAtlasTrackerTarget): string; static;
    /// <summary>Antwort von /api/issues; False bei ungültigem JSON.</summary>
    class function ParseIssues(const AJson: string; AMax: Integer;
      out AIssues: TArray<TAtlasTrackerIssue>): Boolean; static;
    /// <summary>Fehler zu einem HTTP-Status außer 200.</summary>
    class function ErrorOfStatus(AStatus: Integer): TAtlasCiFetchError; static;
    { IAtlasTrackerProvider }
    function Name: string;
    function Caption: string;
    function DefaultQuery: string;
    function ApiServer(const ATarget: TAtlasTrackerTarget): string;
    function Fetch(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; ATimeoutMs, AMax: Integer;
      out AIssues: TArray<TAtlasTrackerIssue>; out AError: TAtlasCiFetchError): Boolean;
    function IssuePage(const ATarget: TAtlasTrackerTarget; const AKey: string): string;
    function PullRequestPage(const ATarget: TAtlasTrackerTarget; ANumber: Integer): string;
  end;

implementation

uses
  System.Classes,
  System.Generics.Collections,
  System.JSON,
  Atlas.Text.Uris;

function TextOf(AObject: TJSONObject; const AName: string): string;
var
  Value: TJSONValue;
begin
  Result := '';
  Value := AObject.Values[AName];
  if Value is TJSONString then
    Result := TJSONString(Value).Value;
end;

function Shorten(const AText: string; AMax: Integer): string;
begin
  Result := Trim(StringReplace(StringReplace(AText, #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]));
  if Length(Result) > AMax then
    Result := Copy(Result, 1, AMax - 1) + '…';
end;

/// <summary>Name eines Werts: "name", sonst "presentation"; bei einer Liste die Namen mit ", ".</summary>
function ValueText(AValue: TJSONValue): string;
var
  Item: TJSONValue;
  Part: string;
begin
  Result := '';
  if AValue is TJSONObject then
  begin
    Result := TextOf(TJSONObject(AValue), 'name');
    if Result = '' then
      Result := TextOf(TJSONObject(AValue), 'presentation');
  end
  else if AValue is TJSONString then
    Result := TJSONString(AValue).Value
  else if AValue is TJSONArray then
    for Item in TJSONArray(AValue) do
    begin
      Part := ValueText(Item);
      if Part = '' then
        Continue;
      if Result <> '' then
        Result := Result + ', ';
      Result := Result + Part;
    end;
  Result := Shorten(Result, 60);
end;

function IsOneOf(const AName: string; const ANames: array of string): Boolean;
var
  Name: string;
begin
  Result := False;
  for Name in ANames do
    if SameText(AName, Name) then
      Exit(True);
end;

{ TAtlasYouTrackTracker }

class function TAtlasYouTrackTracker.FullQuery(const ATarget: TAtlasTrackerTarget): string;
var
  Project: string;
begin
  Result := ATarget.Query;
  if Result = '' then
    Result := Query;
  Project := ATarget.Project;
  if Project = '' then
    Exit;
  // Kürzel mit Leerzeichen oder Sonderzeichen in geschweiften Klammern, wie in der Oberfläche.
  if Pos(' ', Project) > 0 then
    Project := '{' + Project + '}';
  Result := 'project: ' + Project + ' ' + Result;
end;

class function TAtlasYouTrackTracker.IssuesUrl(const ATarget: TAtlasTrackerTarget; AMax: Integer): string;
var
  Limit: Integer;
begin
  Result := '';
  if ATarget.Server = '' then
    Exit;
  Limit := AMax;
  if Limit < 1 then
    Limit := 1;
  if Limit > 100 then
    Limit := 100;
  Result := ATarget.Url + '/api/issues?query=' + TTextUris.PercentEncode(FullQuery(ATarget)) + '&fields=' +
    TTextUris.PercentEncode(Fields) + '&$top=' + IntToStr(Limit);
end;

class function TAtlasYouTrackTracker.ParseIssues(const AJson: string; AMax: Integer;
  out AIssues: TArray<TAtlasTrackerIssue>): Boolean;
var
  Value, Item, Custom, Field: TJSONValue;
  Issue: TAtlasTrackerIssue;
  FieldName, Text: string;
  Number: Int64;
  NumberValue: TJSONValue;
begin
  AIssues := nil;
  Result := False;
  Value := TJSONObject.ParseJSONValue(AJson);
  try
    if not (Value is TJSONArray) then
      Exit;
    Result := True;
    for Item in TJSONArray(Value) do
    begin
      if Length(AIssues) >= AMax then
        Break;
      if not (Item is TJSONObject) then
        Continue;
      Issue := TAtlasTrackerIssue.Empty;
      Issue.Key := Trim(TextOf(TJSONObject(Item), 'idReadable'));
      if Issue.Key = '' then
        Continue;
      NumberValue := TJSONObject(Item).Values['numberInProject'];
      if (NumberValue is TJSONNumber) and TryStrToInt64(TJSONNumber(NumberValue).Value, Number) and (Number > 0) and
        (Number <= MaxInt) then
        Issue.Number := Integer(Number);
      Issue.Title := Shorten(TextOf(TJSONObject(Item), 'summary'), TAtlasTrackerIssue.MaxTitle);
      Custom := TJSONObject(Item).Values['customFields'];
      if Custom is TJSONArray then
        for Field in TJSONArray(Custom) do
        begin
          if not (Field is TJSONObject) then
            Continue;
          FieldName := Trim(TextOf(TJSONObject(Field), 'name'));
          Text := ValueText(TJSONObject(Field).Values['value']);
          if Text = '' then
            Continue;
          if IsOneOf(FieldName, ['State', 'Status', 'Zustand']) and (Issue.State = '') then
            Issue.State := Text
          else if IsOneOf(FieldName, ['Priority', 'Priorität']) and (Issue.Priority = '') then
            Issue.Priority := Text
          else if IsOneOf(FieldName, ['Sprint', 'Sprints', 'Board']) and (Issue.Sprint = '') then
            Issue.Sprint := Text;
        end;
      AIssues := AIssues + [Issue];
    end;
  finally
    Value.Free;
  end;
end;

class function TAtlasYouTrackTracker.ErrorOfStatus(AStatus: Integer): TAtlasCiFetchError;
begin
  case AStatus of
    401, 403:
      Result := TAtlasCiFetchError.Unauthorized;
    404:
      Result := TAtlasCiFetchError.NotFound;
    400:
      Result := TAtlasCiFetchError.Invalid;
  else
    Result := TAtlasCiFetchError.Server;
  end;
end;

function TAtlasYouTrackTracker.Name: string;
begin
  Result := ProviderName;
end;

function TAtlasYouTrackTracker.Caption: string;
begin
  Result := 'YouTrack';
end;

function TAtlasYouTrackTracker.DefaultQuery: string;
begin
  Result := Query;
end;

function TAtlasYouTrackTracker.ApiServer(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := ATarget.Server;
end;

function TAtlasYouTrackTracker.Fetch(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  ATimeoutMs, AMax: Integer; out AIssues: TArray<TAtlasTrackerIssue>; out AError: TAtlasCiFetchError): Boolean;
var
  Status: Integer;
  Text: string;
begin
  AIssues := nil;
  AError := TAtlasCiFetchError.None;
  Result := False;
  if not ATarget.Configured or (ATransport = nil) then
  begin
    AError := TAtlasCiFetchError.NotConfigured;
    Exit;
  end;
  if not ATransport.Get(IssuesUrl(ATarget, AMax), ATimeoutMs, Status, Text, AError) then
    Exit;
  if Status <> 200 then
  begin
    AError := ErrorOfStatus(Status);
    Exit;
  end;
  if not ParseIssues(Text, AMax, AIssues) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  Result := True;
end;

function TAtlasYouTrackTracker.IssuePage(const ATarget: TAtlasTrackerTarget; const AKey: string): string;
var
  Key: string;
  Index: Integer;
begin
  Result := '';
  Key := Trim(AKey);
  if (ATarget.Server = '') or (Key = '') then
    Exit;
  for Index := 1 to Length(Key) do
    if not CharInSet(Key[Index], ['A'..'Z', 'a'..'z', '0'..'9', '-', '_']) then
      Exit;
  Result := ATarget.Url + '/issue/' + Key;
end;

function TAtlasYouTrackTracker.PullRequestPage(const ATarget: TAtlasTrackerTarget; ANumber: Integer): string;
begin
  Result := '';
end;

end.
