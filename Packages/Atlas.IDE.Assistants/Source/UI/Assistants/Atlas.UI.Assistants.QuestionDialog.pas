unit Atlas.UI.Assistants.QuestionDialog;

// Fenster „KI-Assistent fragt“ (#2620), reine VCL und nicht modal: Frage, Antworten zur Auswahl als
// Optionsfelder, bei erlaubter freier Antwort „Eigene Antwort:“ mit Eingabefeld (ohne Optionen nur das Feld),
// darunter, wie viele Fragen danach noch warten, und „Antworten“, „Später“, „Abbrechen“. Das Fenster zeigt immer eine
// Frage; ShowQuestion baut den Inhalt für die nächste neu, die Knöpfe bleiben. Schließen über das Kreuz zählt wie
// „Später“. Was mit der Antwort geschieht, entscheidet der Eingang (OnAnswer, OnLater, OnCancel); welche Antwort
// gewählt ist, sagt TAtlasQuestionInbox.Chosen.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Atlas.Core.Assistants.Questions,
  Atlas.UI.Foundation.Dialog;

type
  TAtlasQuestionAnswerProc = reference to procedure(const AId, AAnswer: string);
  TAtlasQuestionIdProc = reference to procedure(const AId: string);

  TAtlasQuestionDialog = class(TAtlasDialog)
  public const
    /// <summary>SelectedOption: nichts gewählt.</summary>
    cNoAnswer = -2;
  private
    FQuestion: TAtlasQuestion;
    FBody: TPanel;
    FText: TLabel;
    FOptions: TArray<TRadioButton>;
    FOwn: TRadioButton;
    FEdit: TEdit;
    FMore: TLabel;
    FButtons: TAtlasButtonRow;
    FAnswer: TButton;
    FLater: TButton;
    FCancel: TButton;
    FOnAnswer: TAtlasQuestionAnswerProc;
    FOnLater: TAtlasQuestionIdProc;
    FOnCancel: TAtlasQuestionIdProc;
    procedure BuildBody(AWaiting: Integer);
    function AddRadio(const ACaption: string; var ATop: Integer): TRadioButton;
    procedure ChoiceChanged(Sender: TObject);
    procedure EditChanged(Sender: TObject);
    procedure AnswerClick(Sender: TObject);
    procedure LaterClick(Sender: TObject);
    procedure CancelClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
  public
    constructor CreateQuestion(AOwner: TComponent);
    /// <summary>AQuestion zeigen (Inhalt neu); AWaiting: so viele Fragen warten danach noch.</summary>
    procedure ShowQuestion(const AQuestion: TAtlasQuestion; AWaiting: Integer);
    /// <summary>„Danach warten noch n Fragen“ nachführen, ohne die Auswahl anzutasten.</summary>
    procedure SetWaiting(AWaiting: Integer);
    /// <summary>Gewählte Option (ab 0), -1 die eigene Antwort, -2 nichts.</summary>
    function SelectedOption: Integer;
    /// <summary>Gewählte Antwort; False, wenn nichts gewählt ist.</summary>
    function TryAnswer(out AAnswer: string): Boolean;
    /// <summary>Titel für eine Frage von AClient ('' unbekannt).</summary>
    class function CaptionFor(const AClient: string): string; static;
    property Question: TAtlasQuestion read FQuestion;
    property TextLabel: TLabel read FText;
    property Options: TArray<TRadioButton> read FOptions;
    property OwnAnswer: TRadioButton read FOwn;
    property AnswerEdit: TEdit read FEdit;
    property MoreLabel: TLabel read FMore;
    property AnswerButton: TButton read FAnswer;
    property LaterButton: TButton read FLater;
    property CancelButton: TButton read FCancel;
    property OnAnswer: TAtlasQuestionAnswerProc read FOnAnswer write FOnAnswer;
    property OnLater: TAtlasQuestionIdProc read FOnLater write FOnLater;
    property OnCancel: TAtlasQuestionIdProc read FOnCancel write FOnCancel;
  end;

implementation

uses
  Atlas.UI.Foundation.WrapLabel,
  Atlas.UI.Assistants.Strings;

const
  // Maße in logischen Pixeln (96 dpi).
  cDialogWidth = 460;
  cGap = 8;
  cIndent = 16;
  cRadioHeight = 22;
  cEditHeight = 24;

{ TAtlasQuestionDialog }

constructor TAtlasQuestionDialog.CreateQuestion(AOwner: TComponent);
begin
  inherited CreateDialog(AOwner, CaptionFor(''), cDialogWidth);
  BorderIcons := [biSystemMenu];
  OnClose := FormClose;
  FBody := nil;
  FMore := nil;
  // Die Knöpfe entstehen einmal; der Inhalt darüber wechselt je Frage.
  FButtons := AddButtonRow;
  FButtons.Align := alBottom;
  FAnswer := FButtons.AddButton(TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.QuestionAnswer),
    TAtlasButtonKind.Default);
  FAnswer.OnClick := AnswerClick;
  FLater := FButtons.AddButton(TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.QuestionLater));
  FLater.OnClick := LaterClick;
  FCancel := FButtons.AddButton(TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.QuestionCancel),
    TAtlasButtonKind.Cancel);
  // Nicht modal: Abbrechen schließt nicht über ModalResult, sondern lehnt ab.
  FCancel.ModalResult := mrNone;
  FCancel.OnClick := CancelClick;
end;

class function TAtlasQuestionDialog.CaptionFor(const AClient: string): string;
begin
  if AClient = '' then
  begin
    Result := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.QuestionCaption);
  end
  else
  begin
    Result := TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.QuestionCaptionClient, [AClient]);
  end;
end;

function TAtlasQuestionDialog.AddRadio(const ACaption: string; var ATop: Integer): TRadioButton;
begin
  Result := TRadioButton.Create(FBody);
  Result.Parent := FBody;
  Result.SetBounds(ScaleValue(cIndent), ATop, FBody.ClientWidth - ScaleValue(cIndent + cGap),
    ScaleValue(cRadioHeight));
  Result.Caption := ACaption;
  Result.OnClick := ChoiceChanged;
  ATop := ATop + Result.Height;
end;

procedure TAtlasQuestionDialog.BuildBody(AWaiting: Integer);
var
  mTop, mIndex: Integer;
begin
  // Der alte Inhalt geht ganz; die Knöpfe hängen nicht daran.
  FreeAndNil(FBody);
  FOptions := nil;
  FOwn := nil;
  FEdit := nil;
  FMore := nil;
  FBody := TPanel.Create(Self);
  FBody.BevelOuter := bvNone;
  FBody.Caption := '';
  FBody.ShowCaption := False;
  FBody.SetBounds(0, 0, ClientWidth, ScaleValue(cGap));
  FBody.Parent := Self;
  FText := TAtlasWrapLabel.Create(FBody);
  FText.Parent := FBody;
  FText.ShowAccelChar := False;
  FText.SetBounds(ScaleValue(cGap), ScaleValue(cGap), FBody.ClientWidth - 2 * ScaleValue(cGap), FText.Height);
  FText.Caption := FQuestion.Question;
  mTop := FText.Top + FText.Height + ScaleValue(cGap);
  SetLength(FOptions, Length(FQuestion.Options));
  for mIndex := 0 to High(FQuestion.Options) do
  begin
    FOptions[mIndex] := AddRadio(FQuestion.Options[mIndex], mTop);
  end;
  if FQuestion.AllowText then
  begin
    if FQuestion.Options <> nil then
    begin
      FOwn := AddRadio(TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.QuestionOwnAnswer), mTop);
    end;
    FEdit := TEdit.Create(FBody);
    FEdit.Parent := FBody;
    FEdit.SetBounds(ScaleValue(cIndent), mTop, FBody.ClientWidth - ScaleValue(cIndent + cGap),
      ScaleValue(cEditHeight));
    FEdit.OnChange := EditChanged;
    mTop := mTop + FEdit.Height + ScaleValue(cGap div 2);
  end;
  FMore := TLabel.Create(FBody);
  FMore.Parent := FBody;
  FMore.ShowAccelChar := False;
  FMore.Left := ScaleValue(cGap);
  FMore.Top := mTop + ScaleValue(cGap div 2);
  // Die Zeile bleibt auch ohne wartende Fragen stehen: SetWaiting ändert nur den Text.
  FMore.Caption := ' ';
  mTop := FMore.Top + FMore.Height;
  SetWaiting(AWaiting);
  FBody.Height := mTop + ScaleValue(cGap);
  ClientHeight := FBody.Height + FButtons.Height + FButtons.Margins.Top + FButtons.Margins.Bottom;
end;

procedure TAtlasQuestionDialog.ShowQuestion(const AQuestion: TAtlasQuestion; AWaiting: Integer);
begin
  FQuestion := AQuestion;
  Caption := CaptionFor(AQuestion.Client);
  BuildBody(AWaiting);
  ChoiceChanged(nil);
end;

procedure TAtlasQuestionDialog.SetWaiting(AWaiting: Integer);
begin
  if FMore = nil then
  begin
    Exit;
  end;
  FMore.Caption := '';
  if AWaiting > 0 then
  begin
    FMore.Caption := TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.QuestionMore, [AWaiting]);
  end;
end;

function TAtlasQuestionDialog.SelectedOption: Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FOptions) do
  begin
    if FOptions[mIndex].Checked then
    begin
      Exit(mIndex);
    end;
  end;
  // Ohne Optionen ist das Eingabefeld die Antwort.
  if ((FOwn <> nil) and FOwn.Checked) or ((FOwn = nil) and (FEdit <> nil)) then
  begin
    Exit(TAtlasQuestionInbox.cOwnAnswer);
  end;
  Result := cNoAnswer;
end;

function TAtlasQuestionDialog.TryAnswer(out AAnswer: string): Boolean;
var
  mText: string;
begin
  mText := '';
  if FEdit <> nil then
  begin
    mText := FEdit.Text;
  end;
  Result := TAtlasQuestionInbox.Chosen(FQuestion, SelectedOption, mText, AAnswer);
end;

procedure TAtlasQuestionDialog.ChoiceChanged(Sender: TObject);
var
  mAnswer: string;
begin
  if FEdit <> nil then
  begin
    FEdit.Enabled := (FOwn = nil) or FOwn.Checked;
  end;
  FAnswer.Enabled := TryAnswer(mAnswer);
end;

procedure TAtlasQuestionDialog.EditChanged(Sender: TObject);
begin
  // Wer tippt, meint die eigene Antwort.
  if (FOwn <> nil) and not FOwn.Checked and (FEdit.Text <> '') then
  begin
    FOwn.Checked := True;
  end;
  ChoiceChanged(Sender);
end;

procedure TAtlasQuestionDialog.AnswerClick(Sender: TObject);
var
  mAnswer: string;
begin
  if TryAnswer(mAnswer) and Assigned(FOnAnswer) then
  begin
    FOnAnswer(FQuestion.Id, mAnswer);
  end;
end;

procedure TAtlasQuestionDialog.LaterClick(Sender: TObject);
begin
  if Assigned(FOnLater) then
  begin
    FOnLater(FQuestion.Id);
  end;
end;

procedure TAtlasQuestionDialog.CancelClick(Sender: TObject);
begin
  if Assigned(FOnCancel) then
  begin
    FOnCancel(FQuestion.Id);
  end;
end;

procedure TAtlasQuestionDialog.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  // Das Fenster gehört dem Eingang: nur verbergen. Das Kreuz entscheidet nichts und stellt die Frage zurück.
  Action := caHide;
  if Assigned(FOnLater) and (FQuestion.Id <> '') then
  begin
    FOnLater(FQuestion.Id);
  end;
end;

end.
