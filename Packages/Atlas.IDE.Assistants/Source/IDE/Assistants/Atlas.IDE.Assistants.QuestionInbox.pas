unit Atlas.IDE.Assistants.QuestionInbox;

// Eingang für Rückfragen von KI-Assistenten (#2620, MCP-Werkzeug ask_user; Protokoll und Warteschlange in
// Atlas.Core.Assistants.Questions): Sobald der Ordner sich ändert (Signal alle 100 ms abgefragt, aufgelistet nur nach
// einem Signal oder alle zwei Sekunden, wie die anderen Eingänge), übernimmt das Plugin eine Frage, meldet sie in der
// Benachrichtigungszentrale (nur Text) und zeigt sie im nicht modalen Fenster „KI-Assistent fragt“. Weitere Fragen
// warten in der Reihenfolge ihres Eingangs; „Später“ stellt eine zurück. Das Statusfeld zeigt „KI: n Fragen offen“,
// ein Klick holt alle zurückgestellten wieder nach vorn. Läuft die Frist ab, antwortet der Eingang „timeout“; bei
// „Pause für KI“ (#1906) lehnt er neue Fragen gleich ab. Beim Stoppen beantwortet er alle offenen mit „declined“;
// Fenster, Zeitgeber und Statusfeld gehen mit ihm (ADR 0017, Regel 3). Jede Frage landet im KI-Protokoll (#2049).

interface

uses
  System.SysUtils,
  System.Types,
  Vcl.ExtCtrls,
  Atlas.Core.Assistants.Activity,
  Atlas.Core.Assistants.InboxPace,
  Atlas.Core.Assistants.Questions,
  Atlas.Core.Assistants.Log,
  Atlas.IDE.Assistants.FolderSignal,
  Atlas.UI.Assistants.QuestionDialog;

type
  TAtlasIdeQuestionInbox = class
  public const
    cFieldId = 'atlas.assistants.questions';
    cTickMs = 100;
  private
    FFolder: string;
    FTimer: TTimer;
    FSignal: TAtlasFolderSignal;
    FPace: TAtlasInboxPace;
    FQueue: TAtlasQuestionQueue;
    FDialog: TAtlasQuestionDialog;
    FActivity: TAtlasAssistantsActivity;
    FLog: TAtlasAssistantsLog;
    procedure Tick(Sender: TObject);
    procedure Process(const ARequestFile: string);
    procedure Expire;
    procedure Reply(const AQuestion: TAtlasQuestion; AStatus: TAtlasQuestionStatus; const AAnswer: string);
    procedure Answered(const AId, AAnswer: string);
    procedure Later(const AId: string);
    procedure Cancelled(const AId: string);
    procedure StatusClicked(APoint: TPoint);
    procedure EnsureDialog;
  public
    /// <summary>AActivity: Pause für KI-Assistenten; ALog: KI-Protokoll, darf nil sein; beide gehören der
    /// Composition und leben länger als der Eingang.</summary>
    constructor Create(AActivity: TAtlasAssistantsActivity; ALog: TAtlasAssistantsLog);
    destructor Destroy; override;
    /// <summary>Fenster und Statusfeld nach der Warteschlange richten.</summary>
    procedure Present;
    /// <summary>Text für das Statusfeld; '' ohne offene Frage.</summary>
    class function StatusText(ACount: Integer): string; static;
    /// <summary>Texte für unlesbare Aufträge in der Sprache der Oberfläche.</summary>
    class function Texts: TAtlasQuestionTexts; static;
    property Folder: string read FFolder;
    property Queue: TAtlasQuestionQueue read FQueue;
    property Dialog: TAtlasQuestionDialog read FDialog;
  end;

implementation

uses
  Winapi.Windows,
  System.IOUtils,
  Atlas.Text.Files,
  Atlas.Core.Status.Contract,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Notifications.Center,
  Atlas.Core.Notifications.Contract,
  Atlas.Core.Assistants.Inbox,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Assistants.HeldEdits,
  Atlas.UI.Assistants.Strings;

var
  /// <summary>Ordner dieses Prozesses schon einmal aufgeräumt?</summary>
  GCleaned: Boolean;

{ TAtlasIdeQuestionInbox }

constructor TAtlasIdeQuestionInbox.Create(AActivity: TAtlasAssistantsActivity; ALog: TAtlasAssistantsLog);
begin
  inherited Create;
  FActivity := AActivity;
  FLog := ALog;
  FQueue := TAtlasQuestionQueue.Create;
  FFolder := TAtlasQuestionInbox.Folder(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'),
    GetCurrentProcessId);
  // Nur beim ersten Start in diesem Prozess aufräumen: Antworten eines früheren Laufs des Eingangs liest der
  // MCP-Server vielleicht noch.
  if not GCleaned then
  begin
    // Gesperrt: bleibt liegen, der Eingang arbeitet trotzdem.
    TTextFiles.DeleteFolder(FFolder);
    GCleaned := True;
  end;
  FSignal := TAtlasFolderSignal.Create(FFolder);
  FPace := Default(TAtlasInboxPace);
  FTimer := TTimer.Create(nil);
  FTimer.Interval := cTickMs;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TAtlasIdeQuestionInbox.Destroy;
var
  mQuestion: TAtlasQuestion;
begin
  FTimer.Free;
  FSignal.Free;
  // Regel 3: Offene Fragen bekommen „abgelehnt“, danach erreicht nichts mehr dieses Objekt.
  for mQuestion in FQueue.TakeAll do
  begin
    Reply(mQuestion, TAtlasQuestionStatus.Declined, '');
  end;
  FreeAndNil(FDialog);
  TAtlasIdeHost.SetStatusItem(TAtlasStatusExtra.Make(cFieldId, '', '', nil));
  FQueue.Free;
  inherited Destroy;
end;

class function TAtlasIdeQuestionInbox.Texts: TAtlasQuestionTexts;
begin
  Result.Unreadable := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.QuestionUnreadable);
  Result.NoQuestion := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.QuestionNoText);
end;

class function TAtlasIdeQuestionInbox.StatusText(ACount: Integer): string;
begin
  if ACount <= 0 then
  begin
    Result := '';
  end
  else if ACount = 1 then
  begin
    Result := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.QuestionStatusOne);
  end
  else
  begin
    Result := TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.QuestionStatusMany, [ACount]);
  end;
end;

procedure TAtlasIdeQuestionInbox.Tick(Sender: TObject);
var
  mRequestFile: string;
begin
  if TAtlasGuard.Disabled(TAtlasFeature.Files) then
  begin
    Exit;
  end;
  try
    Expire;
    if not FPace.Due(FSignal.Changed, GetTickCount64) then
    begin
      Exit;
    end;
    FSignal.Reopen;
    FPace.Listed(GetTickCount64, False);
    for mRequestFile in TAtlasFileInbox.Pending(FFolder) do
    begin
      Process(mRequestFile);
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Files, E);
  end;
end;

procedure TAtlasIdeQuestionInbox.Expire;
var
  mExpired: TArray<TAtlasQuestion>;
  mQuestion: TAtlasQuestion;
begin
  mExpired := FQueue.TakeExpired(GetTickCount64);
  for mQuestion in mExpired do
  begin
    Reply(mQuestion, TAtlasQuestionStatus.TimedOut, '');
  end;
  if mExpired <> nil then
  begin
    Present;
  end;
end;

procedure TAtlasIdeQuestionInbox.Process(const ARequestFile: string);
var
  mId, mText, mReason: string;
  mQuestion: TAtlasQuestion;
begin
  if not TAtlasFileInbox.Claim(ARequestFile, mId, mText) then
  begin
    Exit;
  end;
  if not TAtlasQuestionInbox.Parse(mId, mText, GetTickCount64, Texts, mQuestion, mReason) then
  begin
    mQuestion.Question := mReason;
    Reply(mQuestion, TAtlasQuestionStatus.Declined, '');
    Exit;
  end;
  // Pause für KI (#1906): keine neuen Fragen.
  if FActivity.Paused then
  begin
    Reply(mQuestion, TAtlasQuestionStatus.Declined, '');
    Exit;
  end;
  FQueue.Add(mQuestion);
  TAtlasNotificationCenter.Default.Notify(TAtlasIdeHeldEdits.cSource, TAtlasNotificationSeverity.Info,
    TAtlasQuestionDialog.CaptionFor(mQuestion.Client), mQuestion.Question);
  Present;
end;

procedure TAtlasIdeQuestionInbox.Reply(const AQuestion: TAtlasQuestion; AStatus: TAtlasQuestionStatus;
  const AAnswer: string);
var
  mDetail: string;
begin
  TAtlasFileInbox.Answer(FFolder, AQuestion.Id, TAtlasQuestionInbox.AnswerText(AStatus, AAnswer));
  if FLog = nil then
  begin
    Exit;
  end;
  case AStatus of
    TAtlasQuestionStatus.Answered:
      mDetail := TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.LogAnswered, [AQuestion.Question, AAnswer]);
    TAtlasQuestionStatus.TimedOut:
      mDetail := TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.LogTimedOut, [AQuestion.Question]);
  else
    mDetail := TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.LogDeclined, [AQuestion.Question]);
  end;
  FLog.Add(TAtlasAssistantsLog.PlainEntry(TAtlasAssistantsLogKind.Question, '', AQuestion.Client, mDetail));
end;

procedure TAtlasIdeQuestionInbox.EnsureDialog;
begin
  if FDialog <> nil then
  begin
    Exit;
  end;
  FDialog := TAtlasQuestionDialog.CreateQuestion(nil);
  FDialog.OnAnswer := Answered;
  FDialog.OnLater := Later;
  FDialog.OnCancel := Cancelled;
end;

procedure TAtlasIdeQuestionInbox.Present;
var
  mQuestion: TAtlasQuestion;
  mExtra: TAtlasStatusExtra;
  mShown: Boolean;
begin
  mExtra := Default(TAtlasStatusExtra);
  mExtra.Id := cFieldId;
  mExtra.Text := StatusText(FQueue.Count);
  if mExtra.Text <> '' then
  begin
    mExtra.Hint := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.QuestionStatusHint);
    mExtra.State := TAtlasStatusState.Yellow;
    mExtra.OnClick := StatusClicked;
  end;
  TAtlasIdeHost.SetStatusItem(mExtra);
  // Das Fenster zeigt die älteste nicht zurückgestellte Frage; sind alle zurückgestellt, bleibt nur das Statusfeld.
  mShown := FQueue.TryCurrent(mQuestion) and not mQuestion.Postponed;
  if not mShown then
  begin
    if FDialog <> nil then
    begin
      FDialog.Hide;
    end;
    Exit;
  end;
  EnsureDialog;
  if not FDialog.Visible or (FDialog.Question.Id <> mQuestion.Id) then
  begin
    FDialog.ShowQuestion(mQuestion, FQueue.Count - 1);
  end
  else
  begin
    FDialog.SetWaiting(FQueue.Count - 1);
  end;
  if not FDialog.Visible then
  begin
    // Nicht modal: Die IDE arbeitet weiter, während die Frage offen ist.
    FDialog.Show;
  end;
end;

procedure TAtlasIdeQuestionInbox.Answered(const AId, AAnswer: string);
var
  mQuestion: TAtlasQuestion;
begin
  if FQueue.TryGet(AId, mQuestion) and FQueue.Remove(AId) then
  begin
    Reply(mQuestion, TAtlasQuestionStatus.Answered, AAnswer);
  end;
  Present;
end;

procedure TAtlasIdeQuestionInbox.Later(const AId: string);
begin
  FQueue.Postpone(AId, True);
  Present;
end;

procedure TAtlasIdeQuestionInbox.Cancelled(const AId: string);
var
  mQuestion: TAtlasQuestion;
begin
  if FQueue.TryGet(AId, mQuestion) and FQueue.Remove(AId) then
  begin
    Reply(mQuestion, TAtlasQuestionStatus.Declined, '');
  end;
  Present;
end;

procedure TAtlasIdeQuestionInbox.StatusClicked(APoint: TPoint);
begin
  FQueue.RecallAll;
  Present;
end;

end.
