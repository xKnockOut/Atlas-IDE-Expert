unit Atlas.Core.AiProviders.Anthropic;

// Anbieter Anthropic-API (#1922): POST https://api.anthropic.com/v1/messages
// über IAtlasAiHttp, kein SDK. Der Schlüssel geht nur als Kopf x-api-key an
// diese Adresse; ohne Schlüssel geht nichts hinaus.
// - Anfrage: Modell aus assistants.model, max_tokens, Anweisungen als system,
//   Aufgabe als eine Nachricht des Nutzers; ohne Streaming. Das Modell steht
//   nur in den Einstellungen, nie hier.
// - Antwort: alle Blöcke vom Typ text hintereinander; stop_reason refusal ist
//   ein Fehler. Fehlerantworten ({"type":"error","error":{…}}) werden nach
//   Status und Art eingeordnet (Schlüssel falsch, Modell fehlt, Grenze,
//   überlastet); ihre Meldung landet gekürzt in Detail.
// Reine Funktionen bis auf Complete (Transport im Hintergrund-Thread).

interface

uses
  Atlas.Core.AiProviders.Contract;

type
  TAtlasAnthropicApi = class
  public const
    cId = 'anthropic';
    cUrl = 'https://api.anthropic.com/v1/messages';
    cVersion = '2026-10-21';
  public
    /// <summary>JSON der Anfrage für AModel.</summary>
    class function RequestBody(const AModel: string; const APrompt: TAtlasAiPrompt): string; static;
    /// <summary>Köpfe mit dem Schlüssel AKey.</summary>
    class function Headers(const AKey: string): TArray<TAtlasAiHeader>; static;
    /// <summary>Antwort aus Status und Inhalt.</summary>
    class function ReadAnswer(AStatus: Integer; const ABody: string): TAtlasAiAnswer; static;
  end;

  TAtlasAnthropicProvider = class(TInterfacedObject, IAtlasAiProvider)
  private
    FHttp: IAtlasAiHttp;
    FKeys: TAtlasAiKeyReader;
    FModel: string;
  public
    constructor Create(const AHttp: IAtlasAiHttp; const AKeys: TAtlasAiKeyReader; const AModel: string);
    function Id: string;
    function Complete(const APrompt: TAtlasAiPrompt): TAtlasAiAnswer;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections; // Inline-Funktionen von TJSONArray (H2443)

{ TAtlasAnthropicApi }

class function TAtlasAnthropicApi.RequestBody(const AModel: string; const APrompt: TAtlasAiPrompt): string;
var
  mBody, mMessage: TJSONObject;
  mMessages: TJSONArray;
begin
  mBody := TJSONObject.Create;
  try
    mBody.AddPair('model', AModel);
    mBody.AddPair('max_tokens', TJSONNumber.Create(APrompt.MaxTokens));
    if APrompt.Instructions <> '' then
    begin
      mBody.AddPair('system', APrompt.Instructions);
    end;
    mMessage := TJSONObject.Create;
    mMessage.AddPair('role', 'user');
    mMessage.AddPair('content', APrompt.Task);
    mMessages := TJSONArray.Create;
    mMessages.AddElement(mMessage);
    mBody.AddPair('messages', mMessages);
    Result := mBody.ToJSON;
  finally
    mBody.Free;
  end;
end;

class function TAtlasAnthropicApi.Headers(const AKey: string): TArray<TAtlasAiHeader>;
begin
  Result := TArray<TAtlasAiHeader>.Create(
    TAtlasAiHeader.Create('x-api-key', AKey),
    TAtlasAiHeader.Create('anthropic-version', cVersion),
    TAtlasAiHeader.Create('content-type', 'application/json'));
end;

/// <summary>Fehler nach Status und Art der Fehlerantwort.</summary>
function ErrorOf(AStatus: Integer; const AKind: string): TAtlasAiError;
begin
  case AStatus of
    cAiHttpUnauthorized, cAiHttpForbidden:
      Result := TAtlasAiError.Unauthorized;
    cAiHttpNotFound:
      Result := TAtlasAiError.ModelMissing;
    cAiHttpTooManyRequests, cAiHttpOverloaded:
      Result := TAtlasAiError.RateLimited;
  else
    if AStatus >= cAiHttpServerError then
    begin
      Result := TAtlasAiError.ServerError;
    end
    else
    begin
      Result := TAtlasAiError.BadAnswer;
    end;
  end;
  if SameText(AKind, 'authentication_error') or SameText(AKind, 'permission_error') then
  begin
    Result := TAtlasAiError.Unauthorized;
  end;
  if SameText(AKind, 'not_found_error') then
  begin
    Result := TAtlasAiError.ModelMissing;
  end;
end;

/// <summary>Text aller Blöcke vom Typ text.</summary>
function TextOf(AContent: TJSONArray): string;
var
  mItem: TJSONValue;
  mText: TJSONValue;
begin
  Result := '';
  for mItem in AContent do
  begin
    if (mItem is TJSONObject) and SameText(TJSONObject(mItem).GetValue<string>('type', ''), 'text') then
    begin
      mText := TJSONObject(mItem).GetValue('text');
      if mText is TJSONString then
      begin
        Result := Result + TJSONString(mText).Value;
      end;
    end;
  end;
end;

/// <summary>Fehlerantwort {"type":"error","error":{"type","message"}} in AAnswer.</summary>
procedure ReadError(AObject: TJSONObject; var AAnswer: TAtlasAiAnswer);
var
  mError: TJSONValue;
  mKind: string;
begin
  mKind := '';
  mError := AObject.GetValue('error');
  if mError is TJSONObject then
  begin
    mKind := TJSONObject(mError).GetValue<string>('type', '');
    AAnswer.Detail := Copy(TJSONObject(mError).GetValue<string>('message', ''), 1, cMaxAiDetail);
  end;
  AAnswer.Error := ErrorOf(AAnswer.Status, mKind);
end;

class function TAtlasAnthropicApi.ReadAnswer(AStatus: Integer; const ABody: string): TAtlasAiAnswer;
var
  mValue, mContent: TJSONValue;
  mObject: TJSONObject;
begin
  Result := Default(TAtlasAiAnswer);
  Result.Status := AStatus;
  mValue := TJSONObject.ParseJSONValue(ABody);
  try
    if not (mValue is TJSONObject) then
    begin
      Result.Error := ErrorOf(AStatus, '');
      if (AStatus >= cAiHttpOkFirst) and (AStatus <= cAiHttpOkLast) then
      begin
        Result.Error := TAtlasAiError.BadAnswer;
      end;
      Exit;
    end;
    mObject := TJSONObject(mValue);
    if (AStatus < cAiHttpOkFirst) or (AStatus > cAiHttpOkLast) or SameText(mObject.GetValue<string>('type', ''), 'error') then
    begin
      ReadError(mObject, Result);
      Exit;
    end;
    Result.Model := mObject.GetValue<string>('model', '');
    if SameText(mObject.GetValue<string>('stop_reason', ''), 'refusal') then
    begin
      Result.Error := TAtlasAiError.Refused;
      Exit;
    end;
    mContent := mObject.GetValue('content');
    if mContent is TJSONArray then
    begin
      Result.Text := TextOf(TJSONArray(mContent));
    end;
    if Result.Text = '' then
    begin
      Result.Error := TAtlasAiError.BadAnswer;
    end;
  finally
    mValue.Free;
  end;
end;

{ TAtlasAnthropicProvider }

constructor TAtlasAnthropicProvider.Create(const AHttp: IAtlasAiHttp; const AKeys: TAtlasAiKeyReader;
  const AModel: string);
begin
  inherited Create;
  FHttp := AHttp;
  FKeys := AKeys;
  FModel := AModel;
end;

function TAtlasAnthropicProvider.Id: string;
begin
  Result := TAtlasAnthropicApi.cId;
end;

function TAtlasAnthropicProvider.Complete(const APrompt: TAtlasAiPrompt): TAtlasAiAnswer;
var
  mKey: string;
  mReply: TAtlasAiHttpReply;
begin
  Result := Default(TAtlasAiAnswer);
  mKey := '';
  if Assigned(FKeys) then
  begin
    mKey := FKeys(TAtlasAnthropicApi.cId);
  end;
  if mKey = '' then
  begin
    Result.Error := TAtlasAiError.NoKey;
    Exit;
  end;
  mReply := FHttp.Send('POST', TAtlasAnthropicApi.cUrl, TAtlasAnthropicApi.Headers(mKey),
    TAtlasAnthropicApi.RequestBody(FModel, APrompt), APrompt.TimeoutMs);
  if mReply.Failure <> TAtlasAiError.None then
  begin
    Result.Error := mReply.Failure;
    Exit;
  end;
  Result := TAtlasAnthropicApi.ReadAnswer(mReply.Status, mReply.Body);
end;

end.
