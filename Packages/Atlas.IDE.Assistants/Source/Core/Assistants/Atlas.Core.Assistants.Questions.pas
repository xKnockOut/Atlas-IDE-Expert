unit Atlas.Core.Assistants.Questions;

// Rückfragen von KI-Assistenten an den Menschen in der IDE (#2620, MCP-Werkzeug ask_user), ohne Windows und VCL.
// Der MCP-Server legt je Frage einen Auftrag in den Eingang des Plugins:
//   %LOCALAPPDATA%\Atlas\ide-questions\<pid>\<id>.json
//   {"question": Text, "options": [Antworten], "allowText": true|false, "timeoutSeconds": n, "client": Name}
// Das Plugin übernimmt ihn durch Umbenennen in <id>.taken (TAtlasFileInbox) und antwortet mit <id>.result.json:
//   {"status": "answered", "answer": "…"}  bzw.  {"status": "declined"}  bzw.  {"status": "timeout"}
// Gegenstück im MCP-Server: Mcp.IdeQuestions.
// TAtlasQuestionQueue hält die offenen Fragen in der Reihenfolge ihres Eingangs: Das Fenster zeigt immer nur eine
// (Current, die älteste nicht zurückgestellte), weitere warten. „Später“ stellt eine Frage zurück; sind nur noch
// zurückgestellte offen, zeigt das Fenster keine, bis der Mensch sie über das Statusfeld wieder holt. Abgelaufene
// Fragen (der MCP-Server wartet nicht länger) liefert TakeExpired; ihr Zeitpunkt kommt vom Aufrufer (Tickzähler in
// Millisekunden).

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Assistants.Queue;

type
  TAtlasQuestionStatus = (Answered, Declined, TimedOut);

  TAtlasQuestion = record
    /// <summary>Name des Auftrags ohne Endung.</summary>
    Id: string;
    Question: string;
    /// <summary>Antworten zur Auswahl; leer = nur freier Text.</summary>
    Options: TArray<string>;
    /// <summary>Freie Antwort erlaubt (immer, wenn es keine Optionen gibt).</summary>
    AllowText: Boolean;
    TimeoutSeconds: Integer;
    /// <summary>clientInfo.name des MCP-Clients; '' unbekannt.</summary>
    Client: string;
    /// <summary>Ab hier wartet der MCP-Server nicht mehr (Tickzähler in ms).</summary>
    DeadlineMs: UInt64;
    /// <summary>Mit „Später“ zurückgestellt.</summary>
    Postponed: Boolean;
  end;

  /// <summary>Gründe, aus denen ein Auftrag nicht lesbar ist, in der Sprache der Oberfläche.</summary>
  TAtlasQuestionTexts = record
    Unreadable: string;
    NoQuestion: string;
  end;

  TAtlasQuestionInbox = class
  public const
    cDefaultTimeoutSeconds = 300;
    cMinTimeoutSeconds = 10;
    cMaxTimeoutSeconds = 3600;
    /// <summary>Chosen: Nummer der eigenen Antwort statt einer Option.</summary>
    cOwnAnswer = -1;
    cStatusNames: array[TAtlasQuestionStatus] of string = ('answered', 'declined', 'timeout');
  public
    /// <summary>Eingang des Prozesses APid unter ABase (%LOCALAPPDATA%\Atlas).</summary>
    class function Folder(const ABase: string; APid: Cardinal): string; static;
    /// <summary>Liest eine Frage; AId ist der Name des Auftrags, ANowMs der Eingang. False mit Grund.</summary>
    class function Parse(const AId, AText: string; ANowMs: UInt64; const ATexts: TAtlasQuestionTexts;
      out AQuestion: TAtlasQuestion; out AReason: string): Boolean; static;
    /// <summary>Antwort an den MCP-Server; AAnswer nur bei Answered.</summary>
    class function AnswerText(AStatus: TAtlasQuestionStatus; const AAnswer: string): string; static;
    /// <summary>Gewählte Antwort im Fenster: AOption ist die Nummer der Option, -1 die eigene Antwort AText. False,
    /// wenn nichts gewählt oder die eigene Antwort leer oder nicht erlaubt ist.</summary>
    class function Chosen(const AQuestion: TAtlasQuestion; AOption: Integer; const AText: string;
      out AAnswer: string): Boolean; static;
  end;

  TAtlasQuestionQueue = class(TAtlasAssistantsQueue<TAtlasQuestion, string>)
  protected
    function KeyOf(const AItem: TAtlasQuestion): string; override;
  public
    procedure Add(const AQuestion: TAtlasQuestion);
    /// <summary>Frage, die das Fenster zeigt: die älteste nicht zurückgestellte, sonst die älteste. False ohne.
    /// </summary>
    function TryCurrent(out AQuestion: TAtlasQuestion): Boolean;
    /// <summary>„Später“: AId zurückstellen; APostponed = False holt sie wieder nach vorn.</summary>
    procedure Postpone(const AId: string; APostponed: Boolean);
    /// <summary>Alle wieder nach vorn holen (Klick auf das Statusfeld).</summary>
    procedure RecallAll;
    /// <summary>Entfernt die Fragen, deren Frist zu ANowMs abgelaufen ist, und liefert sie.</summary>
    function TakeExpired(ANowMs: UInt64): TArray<TAtlasQuestion>;
    /// <summary>Entfernt alle Fragen und liefert sie (Abschalten des Moduls: als abgelehnt beantworten).</summary>
    function TakeAll: TArray<TAtlasQuestion>;
  end;

implementation

uses
  System.JSON,
  System.Math,
  System.IOUtils;

{ TAtlasQuestionInbox }

class function TAtlasQuestionInbox.Folder(const ABase: string; APid: Cardinal): string;
begin
  Result := TPath.Combine(TPath.Combine(ABase, 'ide-questions'), IntToStr(APid));
end;

/// <summary>Nicht leere Texte aus dem Feld "options".</summary>
function OptionsOf(AObject: TJSONObject): TArray<string>;
var
  mValue: TJSONValue;
  mText: string;
begin
  Result := nil;
  if not (AObject.GetValue('options') is TJSONArray) then
  begin
    Exit;
  end;
  for mValue in TJSONArray(AObject.GetValue('options')) do
  begin
    if mValue is TJSONString then
    begin
      mText := Trim(mValue.Value);
      if mText <> '' then
      begin
        Result := Result + [mText];
      end;
    end;
  end;
end;

class function TAtlasQuestionInbox.Parse(const AId, AText: string; ANowMs: UInt64;
  const ATexts: TAtlasQuestionTexts; out AQuestion: TAtlasQuestion; out AReason: string): Boolean;
var
  mJson: TJSONValue;
  mObject: TJSONObject;
begin
  AQuestion := Default(TAtlasQuestion);
  AQuestion.Id := AId;
  AReason := '';
  mJson := TJSONObject.ParseJSONValue(AText);
  try
    if not (mJson is TJSONObject) then
    begin
      AReason := ATexts.Unreadable;
      Exit(False);
    end;
    mObject := TJSONObject(mJson);
    AQuestion.Question := Trim(mObject.GetValue<string>('question', ''));
    if AQuestion.Question = '' then
    begin
      AReason := ATexts.NoQuestion;
      Exit(False);
    end;
    AQuestion.Options := OptionsOf(mObject);
    AQuestion.AllowText := mObject.GetValue<Boolean>('allowText', False) or (AQuestion.Options = nil);
    AQuestion.TimeoutSeconds := EnsureRange(mObject.GetValue<Integer>('timeoutSeconds', cDefaultTimeoutSeconds),
      cMinTimeoutSeconds, cMaxTimeoutSeconds);
    AQuestion.Client := mObject.GetValue<string>('client', '');
    AQuestion.DeadlineMs := ANowMs + UInt64(AQuestion.TimeoutSeconds) * 1000;
    Result := True;
  finally
    mJson.Free;
  end;
end;

class function TAtlasQuestionInbox.AnswerText(AStatus: TAtlasQuestionStatus; const AAnswer: string): string;
var
  mJson: TJSONObject;
begin
  mJson := TJSONObject.Create;
  try
    mJson.AddPair('status', cStatusNames[AStatus]);
    if AStatus = TAtlasQuestionStatus.Answered then
    begin
      mJson.AddPair('answer', AAnswer);
    end;
    Result := mJson.ToJSON;
  finally
    mJson.Free;
  end;
end;

class function TAtlasQuestionInbox.Chosen(const AQuestion: TAtlasQuestion; AOption: Integer; const AText: string;
  out AAnswer: string): Boolean;
begin
  AAnswer := '';
  if (AOption >= 0) and (AOption <= High(AQuestion.Options)) then
  begin
    AAnswer := AQuestion.Options[AOption];
  end
  else if (AOption = cOwnAnswer) and AQuestion.AllowText then
  begin
    AAnswer := Trim(AText);
  end;
  Result := AAnswer <> '';
end;

{ TAtlasQuestionQueue }

function TAtlasQuestionQueue.KeyOf(const AItem: TAtlasQuestion): string;
begin
  Result := AItem.Id;
end;

procedure TAtlasQuestionQueue.Add(const AQuestion: TAtlasQuestion);
begin
  FItems.Add(AQuestion);
end;

function TAtlasQuestionQueue.TryCurrent(out AQuestion: TAtlasQuestion): Boolean;
var
  mQuestion: TAtlasQuestion;
begin
  AQuestion := Default(TAtlasQuestion);
  for mQuestion in FItems do
  begin
    if not mQuestion.Postponed then
    begin
      AQuestion := mQuestion;
      Exit(True);
    end;
  end;
  Result := FItems.Count > 0;
  if Result then
  begin
    AQuestion := FItems[0];
  end;
end;

procedure TAtlasQuestionQueue.Postpone(const AId: string; APostponed: Boolean);
var
  mIndex: Integer;
  mQuestion: TAtlasQuestion;
begin
  mIndex := IndexOf(AId);
  if mIndex < 0 then
  begin
    Exit;
  end;
  mQuestion := FItems[mIndex];
  mQuestion.Postponed := APostponed;
  FItems[mIndex] := mQuestion;
end;

procedure TAtlasQuestionQueue.RecallAll;
var
  mIndex: Integer;
  mQuestion: TAtlasQuestion;
begin
  for mIndex := 0 to FItems.Count - 1 do
  begin
    mQuestion := FItems[mIndex];
    mQuestion.Postponed := False;
    FItems[mIndex] := mQuestion;
  end;
end;

function TAtlasQuestionQueue.TakeExpired(ANowMs: UInt64): TArray<TAtlasQuestion>;
var
  mIndex: Integer;
begin
  Result := nil;
  mIndex := 0;
  while mIndex < FItems.Count do
  begin
    if ANowMs >= FItems[mIndex].DeadlineMs then
    begin
      Result := Result + [FItems[mIndex]];
      FItems.Delete(mIndex);
    end
    else
    begin
      Inc(mIndex);
    end;
  end;
end;

function TAtlasQuestionQueue.TakeAll: TArray<TAtlasQuestion>;
begin
  Result := FItems.ToArray;
  FItems.Clear;
end;

end.
