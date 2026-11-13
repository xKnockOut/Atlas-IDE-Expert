unit Atlas.Core.Tracker.Internals.GitHubGraphQl;

// GraphQL-Schicht des GitHub-Anbieters (#1272, #2134), ohne VCL und Open Tools
// API: Adresse (github.com: api.github.com/graphql, Enterprise:
// <Server>/api/graphql), Inhalt einer Anfrage, Fehler aus "errors" (GraphQL
// meldet sie mit Status 200) und das Senden. Gemeinsam für das Board
// (GitHubBoards) und den Projektstatus beim Beginnen und Beenden
// (GitHubProjects). Fehlende Rechte (INSUFFICIENT_SCOPES, FORBIDDEN) gelten als
// Unauthorized, NOT_FOUND als NotFound, alles andere als Invalid.

interface

uses
  System.JSON,
  Atlas.Core.Ci.Contract,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract;

type
  /// <summary>Antwort einer Anfrage: Text, Fehler (None bei Erfolg) und erster Fehlertext.</summary>
  TAtlasGitHubGraphQlReply = record
    Text: string;
    Error: TAtlasCiFetchError;
    Message: string;
  end;

  TAtlasGitHubGraphQl = class
  public
    /// <summary>Adresse der GraphQL-Schnittstelle; '' ohne Server.</summary>
    class function Url(const ATarget: TAtlasTrackerTarget): string; static;
    /// <summary>Inhalt eines POST: {"query": AQuery, "variables": {Name: Wert, …}} aus Paaren in AVariables.
    /// </summary>
    class function Body(const AQuery: string; const AVariables: array of string): string; static;
    /// <summary>Fehler einer GraphQL-Antwort mit Status 200 ("errors"); None ohne. AMessage: erster Text.</summary>
    class function Error(const AJson: string; out AMessage: string): TAtlasCiFetchError; static;
    /// <summary>Anfrage ABody an AUrl; True nur mit Antwort 200 ohne "errors".</summary>
    class function Query(const ASend: IAtlasCiSend; const AUrl, ABody: string; ATimeoutMs: Integer;
      out AReply: TAtlasGitHubGraphQlReply): Boolean; static;
    /// <summary>Ergebnis einer Antwort auf einen Schreibzugriff: Fehler ohne Antwort, mit anderem Status als 200
    /// bzw. mit "errors", sonst Ok.</summary>
    class function WriteResult(ASent: Boolean; const AResponse: TAtlasCiResponse): TAtlasTrackerWriteResult; static;
    /// <summary>Objekt unter einem Pfad aus Namen ("data", "node"); nil, wenn ein Teil fehlt.</summary>
    class function ObjectAt(AValue: TJSONValue; const APath: array of string): TJSONObject; static;
    /// <summary>Liste "nodes" unter AName eines Objekts; nil ohne.</summary>
    class function NodesOf(AObject: TJSONObject; const AName: string): TJSONArray; static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Tracker.Internals.GitHubApi,
  Atlas.Text.Json;

const
  /// <summary>Antwort mit Inhalt; GraphQL meldet auch Fehler so.</summary>
  cStatusOk = 200;

class function TAtlasGitHubGraphQl.Url(const ATarget: TAtlasTrackerTarget): string;
var
  mBase: string;
begin
  Result := '';
  mBase := TAtlasGitHubApi.Base(ATarget);
  if mBase = '' then
  begin
    Exit;
  end;
  if mBase = TAtlasGitHubApi.cApiHost then
  begin
    Result := mBase + '/graphql';
  end
  else
  begin
    Result := ATarget.Server + '/api/graphql';
  end;
end;

class function TAtlasGitHubGraphQl.Body(const AQuery: string; const AVariables: array of string): string;
var
  mRoot, mVariables: TJSONObject;
  mIndex: Integer;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('query', AQuery);
    mVariables := TJSONObject.Create;
    mIndex := 0;
    while mIndex + 1 <= High(AVariables) do
    begin
      mVariables.AddPair(AVariables[mIndex], AVariables[mIndex + 1]);
      Inc(mIndex, 2);
    end;
    mRoot.AddPair('variables', mVariables);
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasGitHubGraphQl.Error(const AJson: string; out AMessage: string): TAtlasCiFetchError;
var
  mValue, mItem: TJSONValue;
  mType: string;
begin
  AMessage := '';
  Result := TAtlasCiFetchError.None;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONObject) then
    begin
      Exit(TAtlasCiFetchError.Invalid);
    end;
    if not (TJSONObject(mValue).Values['errors'] is TJSONArray) then
    begin
      Exit;
    end;
    for mItem in TJSONArray(TJSONObject(mValue).Values['errors']) do
    begin
      if not (mItem is TJSONObject) then
      begin
        Continue;
      end;
      if AMessage = '' then
      begin
        AMessage := Copy(TJsonRead.Text(TJSONObject(mItem), 'message'), 1, TAtlasTrackerTextLimits.cMessage);
      end;
      mType := UpperCase(TJsonRead.Text(TJSONObject(mItem), 'type'));
      if (mType = 'INSUFFICIENT_SCOPES') or (mType = 'FORBIDDEN') then
      begin
        Exit(TAtlasCiFetchError.Unauthorized);
      end;
      if mType = 'NOT_FOUND' then
      begin
        Result := TAtlasCiFetchError.NotFound;
      end;
    end;
    if Result = TAtlasCiFetchError.None then
    begin
      Result := TAtlasCiFetchError.Invalid;
    end;
  finally
    mValue.Free;
  end;
end;

class function TAtlasGitHubGraphQl.Query(const ASend: IAtlasCiSend; const AUrl, ABody: string; ATimeoutMs: Integer;
  out AReply: TAtlasGitHubGraphQlReply): Boolean;
var
  mResponse: TAtlasCiResponse;
begin
  Result := False;
  AReply := Default(TAtlasGitHubGraphQlReply);
  if not ASend.Send('POST', AUrl, ABody, ATimeoutMs, mResponse) then
  begin
    AReply.Error := mResponse.Error;
    Exit;
  end;
  AReply.Text := mResponse.Text;
  if mResponse.Status <> cStatusOk then
  begin
    AReply.Error := TAtlasGitHubApi.ErrorOfStatus(mResponse.Status);
    AReply.Message := TAtlasGitHubApi.ErrorMessage(AReply.Text);
    Exit;
  end;
  AReply.Error := Error(AReply.Text, AReply.Message);
  Result := AReply.Error = TAtlasCiFetchError.None;
end;

class function TAtlasGitHubGraphQl.WriteResult(ASent: Boolean;
  const AResponse: TAtlasCiResponse): TAtlasTrackerWriteResult;
var
  mError: TAtlasCiFetchError;
  mMessage: string;
begin
  if ASent and (AResponse.Status <> cStatusOk) then
  begin
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasGitHubApi.ErrorOfStatus(AResponse.Status), AResponse.Status,
      TAtlasGitHubApi.ErrorMessage(AResponse.Text)));
  end;
  Result := TAtlasGitHubApi.WriteResult(ASent, AResponse);
  if Result.Succeeded then
  begin
    mError := Error(AResponse.Text, mMessage);
    if mError <> TAtlasCiFetchError.None then
    begin
      Result := TAtlasTrackerWriteResult.Failed(mError, AResponse.Status, mMessage);
    end;
  end;
end;

class function TAtlasGitHubGraphQl.ObjectAt(AValue: TJSONValue; const APath: array of string): TJSONObject;
var
  mName: string;
  mValue: TJSONValue;
begin
  Result := nil;
  mValue := AValue;
  for mName in APath do
  begin
    if not (mValue is TJSONObject) then
    begin
      Exit;
    end;
    mValue := TJSONObject(mValue).Values[mName];
  end;
  if mValue is TJSONObject then
  begin
    Result := TJSONObject(mValue);
  end;
end;

class function TAtlasGitHubGraphQl.NodesOf(AObject: TJSONObject; const AName: string): TJSONArray;
var
  mValue: TJSONValue;
begin
  Result := nil;
  if AObject = nil then
  begin
    Exit;
  end;
  mValue := AObject.Values[AName];
  if mValue is TJSONObject then
  begin
    mValue := TJSONObject(mValue).Values['nodes'];
  end;
  if mValue is TJSONArray then
  begin
    Result := TJSONArray(mValue);
  end;
end;

end.
