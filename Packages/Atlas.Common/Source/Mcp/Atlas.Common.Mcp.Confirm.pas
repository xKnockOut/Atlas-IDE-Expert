unit Atlas.Common.Mcp.Confirm;

// Rückfragen von Atlas selbst (#2620, Stufe 2): Wo ein schreibendes Werkzeug bisher still nur das Sichere tat
// (rename_symbol mit erschlossenen Stellen) oder ohne Halt schrieb (fix_findings über viele Dateien), fragt es den
// Menschen. Der Weg:
//   1. Client: Hat er bei initialize elicitation gemeldet, geht die Frage als elicitation/create an ihn; er zeigt
//      sie dem Menschen (Auswahl aus den Antworten).
//   2. IDE: sonst das Fenster „KI-Assistent fragt“ über den Fragen-Eingang des Plugins (wie ask_user).
//   3. Keiner (kein Client mit elicitation, keine IDE nimmt die Frage an, mcp.confirm aus): wie bisher, ohne
//      Rückfrage.
// Choose liefert die Nummer der gewählten Antwort, cNotAsked ohne Weg und cNoAnswer, wenn gefragt, aber nicht
// geantwortet wurde (abgelehnt, Zeit abgelaufen); dann wählt das Werkzeug den vorsichtigen Ausgang.
// Hier stehen Auswahl des Wegs, Aufbau der Anfrage an den Client und Lesen seiner Antwort; das Senden und Warten
// macht IJsonRpcOutgoing, die IDE fragt der Aufrufer (Core.Mcp.Ide).

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Outgoing,
  Atlas.Common.Mcp.IdeQuestions;

type
  /// <summary>Fragt AQuestion auf einem Weg; AAnswer bei Answered.</summary>
  TMcpAskFunc = reference to function(const AQuestion: TMcpIdeQuestion; out AAnswer: string): TMcpQuestionOutcome;

  /// <summary>Lässt den Menschen unter AOptions wählen; Nummer der Antwort ab 0 oder TMcpConfirm.cNotAsked bzw.
  /// cNoAnswer.</summary>
  TMcpChooseFunc = reference to function(const AText: string; const AOptions: TArray<string>): Integer;

  TMcpConfirm = class
  public const
    /// <summary>Kein Weg zum Menschen: Das Werkzeug verhält sich wie ohne Rückfrage.</summary>
    cNotAsked = -1;
    /// <summary>Gefragt, aber keine Antwort (abgelehnt, abgebrochen, Zeit abgelaufen).</summary>
    cNoAnswer = -2;
    cMethod = 'elicitation/create';
    /// <summary>Feld der Antwort in requestedSchema.</summary>
    cField = 'answer';
  public
    /// <summary>Weg wählen und fragen: AClient (nil ohne elicitation) vor AIde (nil ohne IDE-Weg).</summary>
    class function Choose(const AClient, AIde: TMcpAskFunc; const AQuestion: TMcpIdeQuestion): Integer; static;
    /// <summary>Nummer von AAnswer in AOptions, sonst cNoAnswer.</summary>
    class function IndexOfAnswer(const AOptions: TArray<string>; const AAnswer: string): Integer; static;
    /// <summary>Parameter für elicitation/create: Nachricht und ein Pflichtfeld answer mit den Antworten als enum.
    /// </summary>
    class function ElicitParams(const AQuestion: TMcpIdeQuestion): TJSONObject; static;
    /// <summary>Antwort des Clients auf elicitation/create lesen (action accept, decline, cancel).</summary>
    class function ParseElicitResponse(AResponse: TJSONObject; out AAnswer: string): TMcpQuestionOutcome; static;
    /// <summary>Fragt über den Client: sendet elicitation/create über AOutgoing und wartet die Bedenkzeit der Frage.
    /// </summary>
    class function AskClient(const AOutgoing: IJsonRpcOutgoing; const AQuestion: TMcpIdeQuestion;
      out AAnswer: string): TMcpQuestionOutcome; static;
    /// <summary>Frage mit AText und AOptions, Bedenkzeit wie ask_user, ohne freie Antwort.</summary>
    class function Question(const AText: string; const AOptions: TArray<string>;
      const AClient: string): TMcpIdeQuestion; static;
  end;

implementation

uses
  System.Generics.Collections; // Inline-Funktionen von TJSONArray (H2443)

{ TMcpConfirm }

class function TMcpConfirm.Question(const AText: string; const AOptions: TArray<string>;
  const AClient: string): TMcpIdeQuestion;
begin
  Result := Default(TMcpIdeQuestion);
  Result.Question := AText;
  Result.Options := AOptions;
  Result.AllowText := False;
  Result.TimeoutSeconds := TMcpIdeQuestions.cDefaultTimeoutSeconds;
  Result.Client := AClient;
end;

class function TMcpConfirm.IndexOfAnswer(const AOptions: TArray<string>; const AAnswer: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AOptions) do
  begin
    if AOptions[mIndex] = AAnswer then
    begin
      Exit(mIndex);
    end;
  end;
  Result := cNoAnswer;
end;

class function TMcpConfirm.Choose(const AClient, AIde: TMcpAskFunc; const AQuestion: TMcpIdeQuestion): Integer;
var
  mAnswer: string;
  mOutcome: TMcpQuestionOutcome;
begin
  if Assigned(AClient) then
  begin
    mOutcome := AClient(AQuestion, mAnswer);
  end
  else if Assigned(AIde) then
  begin
    mOutcome := AIde(AQuestion, mAnswer);
  end
  else
  begin
    Exit(cNotAsked);
  end;
  case mOutcome of
    TMcpQuestionOutcome.Answered:
      Result := IndexOfAnswer(AQuestion.Options, mAnswer);
    TMcpQuestionOutcome.NoIde, TMcpQuestionOutcome.NotTaken:
      Result := cNotAsked;
  else
    Result := cNoAnswer;
  end;
end;

class function TMcpConfirm.ElicitParams(const AQuestion: TMcpIdeQuestion): TJSONObject;
var
  mSchema, mProperties, mField: TJSONObject;
  mEnum, mRequired: TJSONArray;
  mOption: string;
begin
  mEnum := TJSONArray.Create;
  for mOption in AQuestion.Options do
  begin
    mEnum.Add(mOption);
  end;
  mField := TJSONObject.Create;
  mField.AddPair('type', 'string');
  mField.AddPair('title', AQuestion.Question);
  mField.AddPair('enum', mEnum);
  mProperties := TJSONObject.Create;
  mProperties.AddPair(cField, mField);
  mRequired := TJSONArray.Create;
  mRequired.Add(cField);
  mSchema := TJSONObject.Create;
  mSchema.AddPair('type', 'object');
  mSchema.AddPair('properties', mProperties);
  mSchema.AddPair('required', mRequired);
  Result := TJSONObject.Create;
  Result.AddPair('message', AQuestion.Question);
  Result.AddPair('requestedSchema', mSchema);
end;

class function TMcpConfirm.ParseElicitResponse(AResponse: TJSONObject; out AAnswer: string): TMcpQuestionOutcome;
var
  mAction: string;
begin
  AAnswer := '';
  if (AResponse = nil) or not AResponse.TryGetValue<string>('result.action', mAction) then
  begin
    Exit(TMcpQuestionOutcome.Unreadable);
  end;
  if mAction <> 'accept' then
  begin
    Exit(TMcpQuestionOutcome.Declined);
  end;
  if not AResponse.TryGetValue<string>('result.content.' + cField, AAnswer) then
  begin
    Exit(TMcpQuestionOutcome.Unreadable);
  end;
  Result := TMcpQuestionOutcome.Answered;
end;

class function TMcpConfirm.AskClient(const AOutgoing: IJsonRpcOutgoing; const AQuestion: TMcpIdeQuestion;
  out AAnswer: string): TMcpQuestionOutcome;
var
  mResponse: TJSONObject;
begin
  AAnswer := '';
  case AOutgoing.Request(cMethod, ElicitParams(AQuestion), Cardinal(AQuestion.TimeoutSeconds) * 1000,
    mResponse) of
    TJsonRpcOutgoingOutcome.Answered:
      try
        Result := ParseElicitResponse(mResponse, AAnswer);
      finally
        mResponse.Free;
      end;
    TJsonRpcOutgoingOutcome.TimedOut:
      Result := TMcpQuestionOutcome.TimedOut;
  else
    Result := TMcpQuestionOutcome.Declined;
  end;
end;

end.
