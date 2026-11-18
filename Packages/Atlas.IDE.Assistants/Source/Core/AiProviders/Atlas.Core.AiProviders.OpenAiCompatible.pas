unit Atlas.Core.AiProviders.OpenAiCompatible;

// Anbieter „OpenAI-kompatibel“ (#2056): lokale Server (LM Studio, llama.cpp-
// Server, Ollama) und Gateways mit der Schnittstelle /chat/completions und
// /models, über IAtlasAiHttp und ohne SDK.
// - Adresse aus assistants.openaiCompatible.url (z. B. http://localhost:1234/v1),
//   Modell aus assistants.openaiCompatible.model, eigenes Zeitlimit
//   (assistants.openaiCompatible.timeoutMs). Das Modell steht nur in den
//   Einstellungen; leer heißt: nichts senden.
// - Schlüssel freiwillig (Anmeldespeicher wie bei #1922) und nur über https oder
//   an den eigenen Rechner (localhost, 127.0.0.1, ::1) als
//   „Authorization: Bearer“; über http an einen anderen Rechner ginge er im
//   Klartext durchs Netz.
// - Antwort: choices[0].message.content; finish_reason content_filter ist eine
//   Verweigerung. Fehler ({"error":{"message",…}} oder {"error":"…"}) nach
//   Status eingeordnet, Meldung gekürzt in Detail.
// - Modellliste aus GET /models (data[].id), für die Auswahl auf der Optionsseite.
// Reine Funktionen bis auf Complete und Models (Transport im Hintergrund-Thread).

interface

uses
  Atlas.Core.AiProviders.Contract;

type
  TAtlasOpenAiApi = class
  public const
    cId = 'openai-compatible';
  public
    /// <summary>ABase ohne / am Ende plus APath ("/chat/completions").</summary>
    class function UrlOf(const ABase, APath: string): string; static;
    /// <summary>Darf ein Schlüssel an AUrl (https oder der eigene Rechner)?</summary>
    class function MayAuthenticate(const AUrl: string): Boolean; static;
    class function RequestBody(const AModel: string; const APrompt: TAtlasAiPrompt): string; static;
    /// <summary>Köpfe; AKey '' = ohne Anmeldung.</summary>
    class function Headers(const AKey: string): TArray<TAtlasAiHeader>; static;
    class function ReadAnswer(AStatus: Integer; const ABody: string): TAtlasAiAnswer; static;
    /// <summary>Modellnamen aus der Antwort von /models, sortiert; nil, wenn keine Liste darin steht.</summary>
    class function ReadModels(const ABody: string): TArray<string>; static;
  end;

  TAtlasOpenAiProvider = class(TInterfacedObject, IAtlasAiProvider, IAtlasAiModels)
  private
    FHttp: IAtlasAiHttp;
    FKeys: TAtlasAiKeyReader;
    FUrl: string;
    FModel: string;
    FTimeoutMs: Integer;
    function Key(const AUrl: string): string;
    /// <summary>Zeitlimit des Prompts; 0 = das aus den Einstellungen.</summary>
    function TimeoutOf(const APrompt: TAtlasAiPrompt): Integer;
  public
    constructor Create(const AHttp: IAtlasAiHttp; const AKeys: TAtlasAiKeyReader; const AUrl, AModel: string;
      ATimeoutMs: Integer);
    function Id: string;
    function Complete(const APrompt: TAtlasAiPrompt): TAtlasAiAnswer;
    function Models(out AModels: TArray<string>): TAtlasAiAnswer;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.JSON,
  System.Generics.Collections, // Inline-Funktionen von TJSONArray (H2443), TArray.Sort
  Atlas.Text.Json;

{ TAtlasOpenAiApi }

class function TAtlasOpenAiApi.UrlOf(const ABase, APath: string): string;
begin
  Result := Trim(ABase);
  while Result.EndsWith('/') do
  begin
    Result := Copy(Result, 1, Length(Result) - 1);
  end;
  Result := Result + APath;
end;

class function TAtlasOpenAiApi.MayAuthenticate(const AUrl: string): Boolean;
var
  mRest, mHost: string;
  mEnd: Integer;
begin
  if StartsText('https://', AUrl) then
  begin
    Exit(True);
  end;
  if not StartsText('http://', AUrl) then
  begin
    Exit(False);
  end;
  mRest := Copy(AUrl, Length('http://') + 1, MaxInt);
  if mRest.StartsWith('[') then
  begin
    // IPv6: [::1]:1234/v1
    mEnd := Pos(']', mRest);
    mHost := Copy(mRest, 2, mEnd - 2);
  end
  else
  begin
    mEnd := mRest.IndexOfAny([':', '/', '?', '#']);
    mHost := mRest;
    if mEnd >= 0 then
    begin
      mHost := Copy(mRest, 1, mEnd);
    end;
  end;
  Result := SameText(mHost, 'localhost') or (mHost = '127.0.0.1') or (mHost = '::1');
end;

class function TAtlasOpenAiApi.RequestBody(const AModel: string; const APrompt: TAtlasAiPrompt): string;
var
  mBody, mMessage: TJSONObject;
  mMessages: TJSONArray;
begin
  mBody := TJSONObject.Create;
  try
    mBody.AddPair('model', AModel);
    mBody.AddPair('max_tokens', TJSONNumber.Create(APrompt.MaxTokens));
    mBody.AddPair('stream', TJSONBool.Create(False));
    mMessages := TJSONArray.Create;
    if APrompt.Instructions <> '' then
    begin
      mMessage := TJSONObject.Create;
      mMessage.AddPair('role', 'system');
      mMessage.AddPair('content', APrompt.Instructions);
      mMessages.AddElement(mMessage);
    end;
    mMessage := TJSONObject.Create;
    mMessage.AddPair('role', 'user');
    mMessage.AddPair('content', APrompt.Task);
    mMessages.AddElement(mMessage);
    mBody.AddPair('messages', mMessages);
    Result := mBody.ToJSON;
  finally
    mBody.Free;
  end;
end;

class function TAtlasOpenAiApi.Headers(const AKey: string): TArray<TAtlasAiHeader>;
begin
  Result := TArray<TAtlasAiHeader>.Create(TAtlasAiHeader.Create('content-type', 'application/json'));
  if AKey <> '' then
  begin
    Result := Result + [TAtlasAiHeader.Create('Authorization', 'Bearer ' + AKey)];
  end;
end;

/// <summary>Meldung einer Fehlerantwort: {"error":{"message"}} oder {"error":"…"}.</summary>
function ErrorMessageOf(AObject: TJSONObject): string;
var
  mError: TJSONValue;
begin
  Result := '';
  mError := AObject.GetValue('error');
  if mError is TJSONObject then
  begin
    Result := TJSONObject(mError).GetValue<string>('message', '');
  end
  else if TJsonRead.IsString(mError) then
  begin
    Result := TJSONString(mError).Value;
  end;
  Result := Copy(Result, 1, cMaxAiDetail);
end;

/// <summary>Erste Wahl der Antwort; nil ohne.</summary>
function FirstChoice(AObject: TJSONObject): TJSONObject;
var
  mChoices: TJSONValue;
begin
  Result := nil;
  mChoices := AObject.GetValue('choices');
  if (mChoices is TJSONArray) and (TJSONArray(mChoices).Count > 0) and
    (TJSONArray(mChoices).Items[0] is TJSONObject) then
  begin
    Result := TJSONObject(TJSONArray(mChoices).Items[0]);
  end;
end;

/// <summary>Text der Wahl AChoice (message.content); '' ohne.</summary>
function ContentOf(AChoice: TJSONObject): string;
var
  mMessage, mContent: TJSONValue;
begin
  Result := '';
  mMessage := AChoice.GetValue('message');
  if mMessage is TJSONObject then
  begin
    mContent := TJSONObject(mMessage).GetValue('content');
    if TJsonRead.IsString(mContent) then
    begin
      Result := TJSONString(mContent).Value;
    end;
  end;
end;

class function TAtlasOpenAiApi.ReadAnswer(AStatus: Integer; const ABody: string): TAtlasAiAnswer;
var
  mValue: TJSONValue;
  mObject, mChoice: TJSONObject;
begin
  Result := Default(TAtlasAiAnswer);
  Result.Status := AStatus;
  mValue := TJSONObject.ParseJSONValue(ABody);
  try
    if (AStatus < cAiHttpOkFirst) or (AStatus > cAiHttpOkLast) then
    begin
      Result.Error := TAtlasAiAnswer.ErrorOfStatus(AStatus);
      if mValue is TJSONObject then
      begin
        Result.Detail := ErrorMessageOf(TJSONObject(mValue));
      end;
      Exit;
    end;
    Result.Error := TAtlasAiError.BadAnswer;
    if not (mValue is TJSONObject) then
    begin
      Exit;
    end;
    mObject := TJSONObject(mValue);
    Result.Model := mObject.GetValue<string>('model', '');
    mChoice := FirstChoice(mObject);
    if mChoice = nil then
    begin
      Result.Detail := ErrorMessageOf(mObject);
      Exit;
    end;
    if SameText(mChoice.GetValue<string>('finish_reason', ''), 'content_filter') then
    begin
      Result.Error := TAtlasAiError.Refused;
      Exit;
    end;
    Result.Text := ContentOf(mChoice);
    if Result.Text <> '' then
    begin
      Result.Error := TAtlasAiError.None;
    end;
  finally
    mValue.Free;
  end;
end;

class function TAtlasOpenAiApi.ReadModels(const ABody: string): TArray<string>;
var
  mValue, mData, mItem: TJSONValue;
  mId: string;
begin
  Result := nil;
  mValue := TJSONObject.ParseJSONValue(ABody);
  try
    if not (mValue is TJSONObject) then
    begin
      Exit;
    end;
    mData := TJSONObject(mValue).GetValue('data');
    if not (mData is TJSONArray) then
    begin
      Exit;
    end;
    for mItem in TJSONArray(mData) do
    begin
      if mItem is TJSONObject then
      begin
        mId := Trim(TJSONObject(mItem).GetValue<string>('id', ''));
        if mId <> '' then
        begin
          Result := Result + [mId];
        end;
      end;
    end;
  finally
    mValue.Free;
  end;
  // Namen sind eindeutig: die Sortierung ist eindeutig.
  TArray.Sort<string>(Result);
end;

{ TAtlasOpenAiProvider }

constructor TAtlasOpenAiProvider.Create(const AHttp: IAtlasAiHttp; const AKeys: TAtlasAiKeyReader;
  const AUrl, AModel: string; ATimeoutMs: Integer);
begin
  inherited Create;
  FHttp := AHttp;
  FKeys := AKeys;
  FUrl := AUrl;
  FModel := Trim(AModel);
  FTimeoutMs := ATimeoutMs;
end;

function TAtlasOpenAiProvider.Id: string;
begin
  Result := TAtlasOpenAiApi.cId;
end;

function TAtlasOpenAiProvider.Key(const AUrl: string): string;
begin
  Result := '';
  if Assigned(FKeys) and TAtlasOpenAiApi.MayAuthenticate(AUrl) then
  begin
    Result := FKeys(TAtlasOpenAiApi.cId);
  end;
end;

function TAtlasOpenAiProvider.TimeoutOf(const APrompt: TAtlasAiPrompt): Integer;
begin
  Result := FTimeoutMs;
  if APrompt.TimeoutMs > 0 then
  begin
    Result := APrompt.TimeoutMs;
  end;
end;

function TAtlasOpenAiProvider.Complete(const APrompt: TAtlasAiPrompt): TAtlasAiAnswer;
var
  mUrl: string;
  mReply: TAtlasAiHttpReply;
begin
  Result := Default(TAtlasAiAnswer);
  if FModel = '' then
  begin
    Result.Error := TAtlasAiError.ModelMissing;
    Exit;
  end;
  mUrl := TAtlasOpenAiApi.UrlOf(FUrl, '/chat/completions');
  mReply := FHttp.Send('POST', mUrl, TAtlasOpenAiApi.Headers(Key(mUrl)),
    TAtlasOpenAiApi.RequestBody(FModel, APrompt), TimeoutOf(APrompt));
  if mReply.Failure <> TAtlasAiError.None then
  begin
    Result.Error := mReply.Failure;
    Exit;
  end;
  Result := TAtlasOpenAiApi.ReadAnswer(mReply.Status, mReply.Body);
end;

function TAtlasOpenAiProvider.Models(out AModels: TArray<string>): TAtlasAiAnswer;
var
  mUrl: string;
  mReply: TAtlasAiHttpReply;
begin
  AModels := nil;
  Result := Default(TAtlasAiAnswer);
  mUrl := TAtlasOpenAiApi.UrlOf(FUrl, '/models');
  mReply := FHttp.Send('GET', mUrl, TAtlasOpenAiApi.Headers(Key(mUrl)), '', FTimeoutMs);
  Result.Status := mReply.Status;
  if mReply.Failure <> TAtlasAiError.None then
  begin
    Result.Error := mReply.Failure;
    Exit;
  end;
  if (mReply.Status < cAiHttpOkFirst) or (mReply.Status > cAiHttpOkLast) then
  begin
    Result.Error := TAtlasAiAnswer.ErrorOfStatus(mReply.Status);
    Exit;
  end;
  AModels := TAtlasOpenAiApi.ReadModels(mReply.Body);
  if AModels = nil then
  begin
    Result.Error := TAtlasAiError.BadAnswer;
  end;
end;

end.
