unit Atlas.Common.Mcp.IdeQuestions;

// Rückfragen von KI-Assistenten an den Menschen in der IDE (#2620, MCP-Werkzeug ask_user): Der MCP-Server legt die
// Frage in den Eingang des Plugins und wartet auf die Antwort (Protokoll: Atlas.Core.Assistants.Questions im Plugin,
// Austausch über TMcpIdeInbox):
//   %LOCALAPPDATA%\Atlas\ide-questions\<pid>\<id>.json
//   {"question": …, "options": […], "allowText": …, "timeoutSeconds": n, "client": …}
//   <id>.result.json  {"status": "answered", "answer": …} | {"status": "declined"} | {"status": "timeout"}
// Nimmt kein Plugin die Frage binnen cTakeMs an (keine IDE mit Atlas, Modul KI-Assistenten nicht geladen oder
// assistants.questionsInIde aus), sagt das Werkzeug, dass der Assistent im Client fragen soll. Hier stehen Prüfung der
// Argumente, Auftrag, Lesen der Antwort und der Text für den Assistenten; die Wahl der IDE macht der Aufrufer.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  System.JSON;

type
  TMcpQuestionOutcome = (Answered, Declined, TimedOut, NoIde, NotTaken, Unreadable);

  TMcpIdeQuestion = record
    Question: string;
    Options: TArray<string>;
    AllowText: Boolean;
    TimeoutSeconds: Integer;
    Client: string;
  end;

  TMcpIdeQuestions = class
  public const
    cTool = 'ask_user';
    cTakeMs = 3000;
    cPollMs = 100;
    cDefaultTimeoutSeconds = 300;
    cMinTimeoutSeconds = 10;
    cMaxTimeoutSeconds = 3600;
    cMaxOptions = 10;
    /// <summary>Zuschlag auf die Bedenkzeit, damit die Antwort „Zeit abgelaufen“ des Plugins noch ankommt.</summary>
    cAnswerSlackMs = 2000;
  public
    /// <summary>Eingang des IDE-Prozesses APid unter ABase (%LOCALAPPDATA%\Atlas).</summary>
    class function InboxOf(const ABase: string; APid: Cardinal): string; static;
    /// <summary>Argumente des Werkzeugs prüfen; False mit Grund in AReason.</summary>
    class function FromArguments(const AArguments: TJSONObject; const AClient: string;
      out AQuestion: TMcpIdeQuestion; out AReason: string): Boolean; static;
    class function RequestText(const AQuestion: TMcpIdeQuestion): string; static;
    /// <summary>So lange wartet der MCP-Server nach der Übernahme auf die Antwort.</summary>
    class function AnswerMs(const AQuestion: TMcpIdeQuestion): Int64; static;
    /// <summary>Antwort des Plugins lesen; AAnswer bei Answered.</summary>
    class function ParseAnswer(const AText: string; out AAnswer: string): TMcpQuestionOutcome; static;
    /// <summary>Text für den Assistenten zum Ausgang AOutcome (mit AAnswer bei Answered).</summary>
    class function ResultText(AOutcome: TMcpQuestionOutcome; const AAnswer: string;
      const AQuestion: TMcpIdeQuestion): string; static;
    /// <summary>Werkzeugbeschreibung und Beschreibungen der Argumente (Sprache der Oberfläche).</summary>
    class function ToolDescription: string; static;
    class function InputSchema: string; static;
  end;

implementation

uses
  System.Generics.Collections, // Inline-Funktionen von TJSONArray (H2443)
  System.Math,
  System.IOUtils,
  Atlas.Text.Json,
  Atlas.Common.Localization.Texts;

type
  TIdeQuestionsText = (ToolDescription, ArgQuestion, ArgOptions, ArgAllowText, ArgTimeout, QuestionMissing,
    TooManyOptions, Answered, Declined, TimedOut, NoIde, NotTaken, Unreadable);

const
  cTexts: array[TIdeQuestionsText] of TAtlasText = (
    (De: 'Fragt den Menschen in der laufenden RAD-Studio-IDE (#2620): Die Frage erscheint dort als Fenster mit den ' +
      'Antworten zur Auswahl bzw. einem Eingabefeld; das Werkzeug wartet auf die Antwort. Für Entscheidungen ' +
      'mitten in der Arbeit (welche Variante, welcher Name, darf diese Datei weg), wenn der Mensch gerade in der ' +
      'IDE arbeitet. Liefert die Antwort oder sagt, dass abgelehnt wurde, die Zeit abgelaufen ist oder keine IDE ' +
      'mit Atlas Fragen annimmt; dann im Client fragen. Höchstens eine Frage zugleich stellen.';
     En: 'Asks the human in the running RAD Studio IDE (#2620): the question appears there as a window with the ' +
      'answers to choose from or an input field; the tool waits for the answer. For decisions in the middle of ' +
      'the work (which variant, which name, may this file go) while the human is working in the IDE. Returns the ' +
      'answer or says that it was declined, the time ran out or no IDE with Atlas accepts questions; then ask in ' +
      'the client. Ask at most one question at a time.'),
    (De: 'Frage an den Menschen, kurz und eindeutig'; En: 'Question to the human, short and clear'),
    (De: 'Antworten zur Auswahl (höchstens 10); leer = freie Antwort';
     En: 'Answers to choose from (at most 10); empty = free answer'),
    (De: 'Zusätzlich eine freie Antwort erlauben (Vorgabe false; ohne options immer)';
     En: 'Also allow a free answer (default false; always without options)'),
    (De: 'So lange auf die Antwort warten (Sekunden, 10 bis 3600, Vorgabe 300)';
     En: 'Wait this long for the answer (seconds, 10 to 3600, default 300)'),
    (De: 'Argument "question" fehlt.'; En: 'Argument "question" missing.'),
    (De: 'Höchstens %d Antworten in "options".'; En: 'At most %d answers in "options".'),
    (De: 'Antwort des Benutzers: %s'; En: 'Answer of the user: %s'),
    (De: 'Der Benutzer hat die Frage in der IDE abgelehnt. Nicht erneut fragen; ohne diese Entscheidung ' +
      'weitermachen oder im Client nachfragen.';
     En: 'The user declined the question in the IDE. Do not ask again; continue without this decision or ask in ' +
      'the client.'),
    (De: 'Zeit abgelaufen: keine Antwort binnen %d s. Im Client fragen.';
     En: 'Time ran out: no answer within %d s. Ask in the client.'),
    (De: 'Keine IDE mit Atlas offen – bitte im Client fragen.'; En: 'No IDE with Atlas open – please ask in the client.'),
    (De: 'Die IDE nimmt keine Fragen an (Modul KI-Assistenten nicht geladen oder „Fragen von KI-Assistenten in der ' +
      'IDE zeigen“ aus) – bitte im Client fragen.';
     En: 'The IDE does not accept questions (module AI assistants not loaded or "Show questions of AI assistants ' +
      'in the IDE" off) – please ask in the client.'),
    (De: 'Antwort der IDE nicht lesbar – bitte im Client fragen.';
     En: 'Answer of the IDE not readable – please ask in the client.'));

{ TMcpIdeQuestions }

class function TMcpIdeQuestions.InboxOf(const ABase: string; APid: Cardinal): string;
begin
  Result := TPath.Combine(TPath.Combine(ABase, 'ide-questions'), IntToStr(APid));
end;

class function TMcpIdeQuestions.FromArguments(const AArguments: TJSONObject; const AClient: string;
  out AQuestion: TMcpIdeQuestion; out AReason: string): Boolean;
var
  mValue: TJSONValue;
  mText: string;
begin
  AQuestion := Default(TMcpIdeQuestion);
  AQuestion.Client := AClient;
  AQuestion.TimeoutSeconds := cDefaultTimeoutSeconds;
  AReason := '';
  if AArguments <> nil then
  begin
    AQuestion.Question := Trim(AArguments.GetValue<string>('question', ''));
    if AArguments.GetValue('options') is TJSONArray then
    begin
      for mValue in TJSONArray(AArguments.GetValue('options')) do
      begin
        mText := Trim(mValue.Value);
        if mText <> '' then
        begin
          AQuestion.Options := AQuestion.Options + [mText];
        end;
      end;
    end;
    AQuestion.AllowText := AArguments.GetValue<Boolean>('allowText', False);
    AQuestion.TimeoutSeconds := EnsureRange(AArguments.GetValue<Integer>('timeoutSeconds', cDefaultTimeoutSeconds),
      cMinTimeoutSeconds, cMaxTimeoutSeconds);
  end;
  if AQuestion.Question = '' then
  begin
    AReason := cTexts[TIdeQuestionsText.QuestionMissing].Text;
    Exit(False);
  end;
  if Length(AQuestion.Options) > cMaxOptions then
  begin
    AReason := cTexts[TIdeQuestionsText.TooManyOptions].Fmt([cMaxOptions]);
    Exit(False);
  end;
  // Ohne Antworten zur Auswahl bleibt nur die freie Antwort.
  AQuestion.AllowText := AQuestion.AllowText or (AQuestion.Options = nil);
  Result := True;
end;

class function TMcpIdeQuestions.RequestText(const AQuestion: TMcpIdeQuestion): string;
var
  mJson: TJSONObject;
  mOptions: TJSONArray;
  mOption: string;
begin
  mJson := TJSONObject.Create;
  try
    mJson.AddPair('question', AQuestion.Question);
    mOptions := TJSONArray.Create;
    for mOption in AQuestion.Options do
    begin
      mOptions.Add(mOption);
    end;
    mJson.AddPair('options', mOptions);
    mJson.AddPair('allowText', TJSONBool.Create(AQuestion.AllowText));
    mJson.AddPair('timeoutSeconds', TJSONNumber.Create(AQuestion.TimeoutSeconds));
    if AQuestion.Client <> '' then
    begin
      mJson.AddPair('client', AQuestion.Client);
    end;
    Result := mJson.ToJSON;
  finally
    mJson.Free;
  end;
end;

class function TMcpIdeQuestions.AnswerMs(const AQuestion: TMcpIdeQuestion): Int64;
begin
  Result := Int64(AQuestion.TimeoutSeconds) * 1000 + cAnswerSlackMs;
end;

class function TMcpIdeQuestions.ParseAnswer(const AText: string; out AAnswer: string): TMcpQuestionOutcome;
var
  mJson: TJSONValue;
  mStatus: string;
begin
  AAnswer := '';
  Result := TMcpQuestionOutcome.Unreadable;
  mJson := TJSONObject.ParseJSONValue(AText);
  try
    if not (mJson is TJSONObject) then
    begin
      Exit;
    end;
    mStatus := TJSONObject(mJson).GetValue<string>('status', '');
    if mStatus = 'answered' then
    begin
      AAnswer := TJSONObject(mJson).GetValue<string>('answer', '');
      Result := TMcpQuestionOutcome.Answered;
    end
    else if mStatus = 'declined' then
    begin
      Result := TMcpQuestionOutcome.Declined;
    end
    else if mStatus = 'timeout' then
    begin
      Result := TMcpQuestionOutcome.TimedOut;
    end;
  finally
    mJson.Free;
  end;
end;

class function TMcpIdeQuestions.ResultText(AOutcome: TMcpQuestionOutcome; const AAnswer: string;
  const AQuestion: TMcpIdeQuestion): string;
begin
  case AOutcome of
    TMcpQuestionOutcome.Answered:
      Result := cTexts[TIdeQuestionsText.Answered].Fmt([AAnswer]);
    TMcpQuestionOutcome.Declined:
      Result := cTexts[TIdeQuestionsText.Declined].Text;
    TMcpQuestionOutcome.TimedOut:
      Result := cTexts[TIdeQuestionsText.TimedOut].Fmt([AQuestion.TimeoutSeconds]);
    TMcpQuestionOutcome.NoIde:
      Result := cTexts[TIdeQuestionsText.NoIde].Text;
    TMcpQuestionOutcome.NotTaken:
      Result := cTexts[TIdeQuestionsText.NotTaken].Text;
  else
    Result := cTexts[TIdeQuestionsText.Unreadable].Text;
  end;
end;

class function TMcpIdeQuestions.ToolDescription: string;
begin
  Result := cTexts[TIdeQuestionsText.ToolDescription].Text;
end;

class function TMcpIdeQuestions.InputSchema: string;
begin
  Result := Format('{"type":"object","properties":{' +
    '"question":{"type":"string","description":%s},' +
    '"options":{"type":"array","items":{"type":"string"},"maxItems":%d,"description":%s},' +
    '"allowText":{"type":"boolean","default":false,"description":%s},' +
    '"timeoutSeconds":{"type":"integer","minimum":%d,"maximum":%d,"default":%d,"description":%s}},' +
    '"required":["question"]}',
    [TJsonText.Quote(cTexts[TIdeQuestionsText.ArgQuestion].Text), cMaxOptions,
    TJsonText.Quote(cTexts[TIdeQuestionsText.ArgOptions].Text),
    TJsonText.Quote(cTexts[TIdeQuestionsText.ArgAllowText].Text), cMinTimeoutSeconds, cMaxTimeoutSeconds,
    cDefaultTimeoutSeconds, TJsonText.Quote(cTexts[TIdeQuestionsText.ArgTimeout].Text)]);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Mcp.IdeQuestions', cTexts);

end.
