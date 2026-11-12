unit Atlas.UI.Tracker.EndDialog;

// Dialog „ATL-123 beenden“ (#1266), ohne Open Tools API: Zielzustand
// (issues.endStates und „Zustand nicht ändern“, dazu Werte vom Tracker,
// Eingabe von Hand), Kommentar vorgefüllt aus issues.endComment und das
// Häkchen „Zuständigkeit übergeben an“ mit der Benutzerliste vom Tracker.
// - Geschrieben wird nur mit „Senden“: OnSend schreibt im Hintergrund und
//   meldet über StepsDone im Hauptthread. Solange gesendet wird, sind Felder
//   und „Abbrechen“ gesperrt und der Dialog schließt nicht (die Zeitgrenze
//   des Schreibens ist TAtlasTrackerWorkflow.cWriteTimeoutMs).
// - Fehler erscheinen im Dialog mit dem Text des Trackers (ErrorText, z. B.
//   „Keine Schreibrechte für ATL-123 (403).“); nichts wird wiederholt, der
//   Benutzer kann ändern und erneut senden oder abbrechen.
// - Strg+Enter sendet; Esc bricht ab.
// - Das Kommentarfeld ist der Kommentar-Editor (#1278): Vorschläge, Textbausteine
//   und Entwurf, sobald APrepare ihn bindet; die Vorlage gilt nicht als Entwurf,
//   ein vorhandener Entwurf wird mit „Übernehmen“ angeboten. Abbrechen behält
//   den Entwurf, erfolgreiches Senden löscht ihn.
// - Unter einer Zustandsmaschine (#2122, SetRules) heißt die Klappliste
//   „Übergang (ab „In Bearbeitung“)“ und bietet nur „Zustand nicht ändern“
//   und die erlaubten Übergänge an, mit bekanntem Ziel dahinter („Zur Prüfung
//   geben → Zur Prüfung“). Vorgewählt ist der erste Übergang in einen
//   Zustand aus issues.endStates (Reihenfolge = Vorliebe); ist der erste
//   Wunsch ab hier nicht erlaubt, sagt es die Hinweiszeile.
// - Ablauf-Reihenfolge (#2123): Mit erfasster Zeit (TAtlasTrackerEndTime,
//   issues.endTime) steht oben „Zeit“ mit Dauer und Arbeitstyp, darunter je
//   Feld aus issues.endFields eine Zeile mit den Werten vom Tracker
//   (Rows.SetFieldValues). „Senden“ übergibt den Plan (TAtlasTrackerEndPlan) mit
//   dem bisherigen Fortschritt an OnSend; geschrieben wird Zeit → Felder →
//   Kommentar → Zustand bzw. Übergang (TAtlasTrackerEndSteps). Die Zeile über
//   den Knöpfen zeigt die Schritte mit ✓/✗; Geschriebenes wird gesperrt und
//   beim erneuten Senden übersprungen. Nennt die Ablehnung ein gezeigtes Feld,
//   wird seine Zeile markiert; nennt sie ein anderes Feld des Projekts
//   (Rows.SetKnownFields), bietet „Feld „…“ hinzufügen“ eine Zeile dafür an (nur
//   für dieses Mal). Abbrechen nach einem Teilerfolg liefert den Fortschritt
//   trotzdem (Execute), damit gebuchte Zeit nicht noch einmal angeboten wird.
// SummaryText bildet die Zeile für die Meldungsansicht („Zustand „Erledigt“,
// Kommentar“), ErrorText auch für „Beginnen“ und die Vorschau;
// TAtlasTrackerEndTexts.EndSummary nennt nach dem Beenden alle geschriebenen
// Schritte.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.EndSteps,
  Atlas.Core.Tracker.Workflow,
  Atlas.UI.Tracker.ValueBox,
  Atlas.UI.Tracker.CommentEditor,
  Atlas.UI.Foundation.Dialog;

type
  /// <summary>Ergebnis des Schreibens, im Hauptthread.</summary>
  TAtlasTrackerSendDone = reference to procedure(const AResult: TAtlasTrackerWriteResult);
  /// <summary>Fortschritt nach einem Lauf der Schritte (#2123), im Hauptthread.</summary>
  TAtlasTrackerEndDone = reference to procedure(const AProgress: TAtlasTrackerEndProgress);
  /// <summary>Offene Schritte von APlan ab AProgress im Hintergrund schreiben und ADone im Hauptthread aufrufen
  /// (genau einmal).</summary>
  TAtlasTrackerEndSendEvent = reference to procedure(const APlan: TAtlasTrackerEndPlan;
    const AProgress: TAtlasTrackerEndProgress; const ADone: TAtlasTrackerEndDone);

  /// <summary>Erfasste Zeit für den Abschnitt „Zeit“ (#2123): Seconds 0 = kein Abschnitt; Rounding
  /// issues.timeRounding, Date Tag der Buchung, Text Beschreibung (Commit-Betreffe).</summary>
  TAtlasTrackerEndTime = record
    Seconds: Int64;
    Rounding: Integer;
    Date: TDateTime;
    Text: string;
    class function None: TAtlasTrackerEndTime; static;
    class function Create(ASeconds: Int64; ARounding: Integer; ADate: TDateTime;
      const AText: string): TAtlasTrackerEndTime; static;
  end;

  /// <summary>Was der Dialog zeigt: Kennung, Einstellungen, ausgefüllte Kommentarvorlage (Zeilen mit #10) und Zeit.
  /// </summary>
  TAtlasTrackerEndRequest = record
    Key: string;
    Options: TAtlasTrackerSyncOptions;
    Comment: string;
    Time: TAtlasTrackerEndTime;
    class function Create(const AKey: string; const AOptions: TAtlasTrackerSyncOptions;
      const AComment: string): TAtlasTrackerEndRequest; static;
  end;

  /// <summary>Ergebnis von Execute: Plan und Fortschritt (auch nach Abbrechen), ob alles geschrieben ist und die
  /// gezeigte erfasste Zeit (gilt mit Progress.TimeBooked).</summary>
  TAtlasTrackerEndOutcome = record
    Plan: TAtlasTrackerEndPlan;
    Progress: TAtlasTrackerEndProgress;
    Finished: Boolean;
    TimeSeconds: Int64;
  end;

  /// <summary>Zeile eines Feldes aus issues.endFields (#2123).</summary>
  TAtlasEndFieldRow = record
    Name: string;
    Caption: TLabel;
    Box: TAtlasValueBox;
  end;

  /// <summary>Die Steuerelemente des Dialogs (für Tests und APrepare). Comment ist das Memo des Editors.</summary>
  TAtlasEndDialogParts = record
    /// <summary>Abschnitt „Zeit“ (#2123); nil ohne erfasste Zeit.</summary>
    BookTime: TCheckBox;
    Duration: TEdit;
    WorkType: TAtlasValueBox;
    Fields: TArray<TAtlasEndFieldRow>;
    StateLabel: TLabel;
    State: TAtlasValueBox;
    Editor: TAtlasCommentEditor;
    Comment: TMemo;
    HandOver: TCheckBox;
    Assignee: TAtlasValueBox;
    Note: TLabel;
    /// <summary>Schritte mit ✓/✗ nach dem ersten Senden.</summary>
    Steps: TLabel;
    /// <summary>„Feld „…“ hinzufügen“; sichtbar, wenn eine Ablehnung ein nicht gezeigtes Feld nennt.</summary>
    AddField: TButton;
    Send: TButton;
    Cancel: TButton;
  end;

  TAtlasTrackerEndDialog = class;

  /// <summary>Abschnitte „Zeit“ und Felder des Beenden-Dialogs (#2123): Werte vom Tracker, Sperren nach dem
  /// Schreiben, Markieren des abgelehnten Feldes und „Feld hinzufügen“. Gehört dem Dialog.</summary>
  TAtlasEndStepRows = class(TComponent)
  private
    FDialog: TAtlasTrackerEndDialog;
    FTime: TAtlasTrackerEndTime;
    FKnownFields: TArray<string>;
    FMissingField: string;
    FTimeOff: Boolean;
    procedure AddTime;
    function NewFieldRow(const AName: string; ATop: Integer): TAtlasEndFieldRow;
    procedure AddFieldClick(Sender: TObject);
  public
    constructor CreateRows(ADialog: TAtlasTrackerEndDialog; const ATime: TAtlasTrackerEndTime;
      const AFields: TArray<string>);
    /// <summary>Arbeitstypen vom Tracker für den Abschnitt „Zeit“.</summary>
    procedure SetWorkTypes(const ATypes: TArray<string>);
    /// <summary>Zeiterfassung im Projekt aus: „Zeit“ abgewählt und gesperrt.</summary>
    procedure SetTimeOff;
    /// <summary>Werte vom Tracker für die Zeile des Feldes AName.</summary>
    procedure SetFieldValues(const AName: string; const AValues: TArray<string>);
    /// <summary>Felder des Projekts, damit eine Ablehnung, die ein nicht gezeigtes nennt, „Feld hinzufügen“
    /// anbietet.</summary>
    procedure SetKnownFields(const ANames: TArray<string>);
    /// <summary>Zeile für Feld AName unter den übrigen Feldern (nur für dieses Mal); die vorhandene, wenn es sie
    /// schon gibt. Liefert ihren Index in Parts.Fields.</summary>
    function AddFieldRow(const AName: string): Integer;
    /// <summary>Zeit und Felder in APlan; ist die Zeit schon gebucht, bleibt ABookedTime. False bei ungültiger
    /// Dauer.</summary>
    function Fill(var APlan: TAtlasTrackerEndPlan; const ABookedTime: TAtlasTrackerWorkItem;
      ATimeBooked: Boolean): Boolean;
    /// <summary>Zeit und Felder sperren (ABusy) bzw. wieder freigeben, Geschriebenes bleibt gesperrt.</summary>
    procedure Lock(ABusy: Boolean; const AProgress: TAtlasTrackerEndProgress);
    /// <summary>Ablehnung: genanntes Feld markieren bzw. „Feld hinzufügen“ anbieten; liefert den Namen des Feldes
    /// für die Hinweiszeile ('' ohne).</summary>
    function MarkRejected(const AProgress: TAtlasTrackerEndProgress): string;
  end;

  TAtlasTrackerEndDialog = class(TAtlasDialog)
  private
    FKey: string;
    FOptions: TAtlasTrackerSyncOptions;
    FRows: TAtlasEndStepRows;
    FParts: TAtlasEndDialogParts;
    FOnSend: TAtlasTrackerEndSendEvent;
    FSending: Boolean;
    FSent: Boolean;
    FPlan: TAtlasTrackerEndPlan;
    FProgress: TAtlasTrackerEndProgress;
    FRules: TAtlasTrackerStateRules;
    FStates: TArray<string>;
    procedure AddState;
    procedure AddComment(const AComment: string);
    function AddHandOver: TPanel;
    procedure AddButtons(ATop: Integer);
    procedure SendClick(Sender: TObject);
    procedure AssigneeChange(Sender: TObject);
    procedure DialogCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure DialogKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure SetBusy(AValue: Boolean);
    procedure EditorCancel(Sender: TObject);
    procedure ShowTransitions;
    function ChosenTransition: Integer;
    procedure StepsDone(const AProgress: TAtlasTrackerEndProgress);
  public
    constructor CreateDialog(AOwner: TComponent; const ARequest: TAtlasTrackerEndRequest);
    /// <summary>Plan nach den Feldern; False bei ungültiger Dauer.</summary>
    function Plan(out APlan: TAtlasTrackerEndPlan): Boolean;
    /// <summary>Werte des Zustandsfeldes vom Tracker als weitere Vorschläge hinter issues.endStates.</summary>
    procedure SetStates(const AStates: TArray<string>);
    /// <summary>Regeln des Zustandsfeldes vom Tracker (#2122): Unter einer Zustandsmaschine bietet die Klappliste
    /// nur die erlaubten Übergänge an; ohne bleibt sie bei den Zuständen.</summary>
    procedure SetRules(const ARules: TAtlasTrackerStateRules);
    /// <summary>Benutzer vom Tracker für „Zuständigkeit übergeben an“.</summary>
    procedure SetUsers(const AUsers: TArray<string>);
    /// <summary>Änderung nach den Feldern.</summary>
    function Change: TAtlasTrackerWrite;
    /// <summary>Grund eines Fehlers mit dem Text des Trackers; '' bei Erfolg.</summary>
    class function ErrorText(const AKey: string; const AResult: TAtlasTrackerWriteResult): string; static;
    /// <summary>Was geschrieben wurde, z. B. „Zustand „Erledigt“, an anna übergeben, Kommentar“.</summary>
    class function SummaryText(const AChange: TAtlasTrackerWrite): string; overload; static;
    /// <summary>Wie oben; nach einem Übergang mit dem danach gelesenen Zustand ANewState („Übergang „Beginnen“
    /// → In Bearbeitung“), ANewState '' ohne.</summary>
    class function SummaryText(const AChange: TAtlasTrackerWrite; const ANewState: string): string; overload; static;
    /// <summary>Modal zeigen; True, wenn nach „Senden“ alles geschrieben ist. AOutcome trägt Plan und Fortschritt
    /// auch nach Abbrechen. APrepare (darf nil sein) passt das Fenster vorher an und kann Werte nachladen
    /// (SetUsers, SetFieldValues, SetWorkTypes).</summary>
    class function Execute(const ARequest: TAtlasTrackerEndRequest; const AOnSend: TAtlasTrackerEndSendEvent;
      const APrepare: TProc<TAtlasTrackerEndDialog>; out AOutcome: TAtlasTrackerEndOutcome): Boolean; static;
    property OnSend: TAtlasTrackerEndSendEvent read FOnSend write FOnSend;
    /// <summary>Abschnitte „Zeit“ und Felder (#2123).</summary>
    property Rows: TAtlasEndStepRows read FRows;
    /// <summary>Senden war erfolgreich.</summary>
    property Sent: Boolean read FSent;
    property Sending: Boolean read FSending;
    /// <summary>Gesendete Änderung (gilt mit Sent).</summary>
    property SentChange: TAtlasTrackerWrite read FPlan.Change;
    property Parts: TAtlasEndDialogParts read FParts;
  end;

  /// <summary>Texte des Beenden-Dialogs ohne Fenster.</summary>
  TAtlasTrackerEndTexts = class
  public
    /// <summary>Vorschläge der Klappliste Zielzustand: „Zustand nicht ändern“, dann AOptions.EndStates.</summary>
    class function StateChoices(const AOptions: TAtlasTrackerSyncOptions): TArray<string>; static;
    /// <summary>Einträge der Klappliste unter ARules: „Zustand nicht ändern“, dann je Übergang ChoiceText mit
    /// bekanntem Ziel aus AStates.</summary>
    class function TransitionChoices(const ARules: TAtlasTrackerStateRules;
      const AStates: TArray<string>): TArray<string>; static;
    /// <summary>„✓ 1 Zeit   ✗ 2 Felder   3 Kommentar   4 Übergang“: geplante Schritte mit ihrem Stand.</summary>
    class function StepsText(const APlan: TAtlasTrackerEndPlan; const AProgress: TAtlasTrackerEndProgress): string;
      static;
    /// <summary>Geschriebene Schritte für die Meldungsansicht („Zeit 1 h 25 min gebucht, Felder Ursache, Übergang
    /// „Zur Prüfung geben“, Kommentar“).</summary>
    class function EndSummary(const APlan: TAtlasTrackerEndPlan; const AProgress: TAtlasTrackerEndProgress): string;
      static;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  Vcl.Graphics,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Transitions,
  Atlas.Core.Tracker.TimeLog,
  Atlas.UI.Tracker.Strings,
  Atlas.Core.Style.Signal,
  Atlas.UI.Foundation.Theme;

const
  cGap = 8;
  cDialogWidth = 520;
  cCommentHeight = 150;
  /// <summary>Leiste des Kommentar-Editors (Vorschau, Textbaustein, Entwurf).</summary>
  cEditorBarHeight = 30;
  /// <summary>Breite der Beschriftungen vor den Klapplisten.</summary>
  cLabelWidth = 176;
  /// <summary>Höhe der Zeilen für Kommentar-Beschriftung, Hinweis und Schritte.</summary>
  cTextRowHeight = 20;
  /// <summary>Oberkante der Häkchen in einer Zeile mit Klappliste.</summary>
  cCheckTop = 3;
  /// <summary>Breite eines Knopfes über seiner Beschriftung.</summary>
  cButtonPadding = 32;
  /// <summary>Linker Rand der Eingaben hinter den Beschriftungen.</summary>
  cFieldLeft = 180;
  cFieldWidth = 240;
  cDurationWidth = 80;
  cRowHeight = 26;
  cDoneMark = '✓ ';
  cFailedMark = '✗ ';

{ TAtlasTrackerEndTime }

class function TAtlasTrackerEndTime.None: TAtlasTrackerEndTime;
begin
  Result := Create(0, 1, 0, '');
end;

class function TAtlasTrackerEndTime.Create(ASeconds: Int64; ARounding: Integer; ADate: TDateTime;
  const AText: string): TAtlasTrackerEndTime;
begin
  Result.Seconds := ASeconds;
  Result.Rounding := ARounding;
  Result.Date := ADate;
  Result.Text := AText;
end;

{ TAtlasTrackerEndRequest }

class function TAtlasTrackerEndRequest.Create(const AKey: string; const AOptions: TAtlasTrackerSyncOptions;
  const AComment: string): TAtlasTrackerEndRequest;
begin
  Result.Key := AKey;
  Result.Options := AOptions;
  Result.Comment := AComment;
  Result.Time := TAtlasTrackerEndTime.None;
end;

/// <summary>Breite von AButton nach seiner Beschriftung.</summary>
procedure FitButton(ADialog: TAtlasTrackerEndDialog; AButton: TButton);
begin
  ADialog.Canvas.Font := ADialog.Font;
  AButton.Width := ADialog.Canvas.TextWidth(AButton.Caption) + ADialog.ScaleValue(cButtonPadding);
end;

/// <summary>Knopf mit ACaption in der Knopfleiste AParent.</summary>
function NewButton(ADialog: TAtlasTrackerEndDialog; AParent: TWinControl; const ACaption: string): TButton;
begin
  Result := TButton.Create(ADialog);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  FitButton(ADialog, Result);
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(0, 0, cGap, cGap div 2);
end;

/// <summary>Fehler rot in der Hinweiszeile ANote.</summary>
procedure ShowErrorNote(ANote: TLabel; const AText: string);
begin
  ANote.Font.Color := TAtlasUiTheme.TextColor(TAtlasSignalKind.Error);
  // Mit seFont übergeht der Stil Font.Color.
  ANote.StyleElements := ANote.StyleElements - [seFont];
  ANote.Caption := AText;
end;

{ TAtlasEndStepRows }

constructor TAtlasEndStepRows.CreateRows(ADialog: TAtlasTrackerEndDialog; const ATime: TAtlasTrackerEndTime;
  const AFields: TArray<string>);
var
  mName: string;
begin
  inherited Create(ADialog);
  FDialog := ADialog;
  FTime := ATime;
  AddTime;
  for mName in AFields do
  begin
    FDialog.FParts.Fields := FDialog.FParts.Fields + [NewFieldRow(mName, FDialog.NextTop)];
  end;
end;

/// <summary>Abschnitt „Zeit“ mit Dauer (gerundet) und Arbeitstyp; nur mit erfasster Zeit.</summary>
procedure TAtlasEndStepRows.AddTime;
var
  mRow: TPanel;
  mDialog: TAtlasTrackerEndDialog;
begin
  if FTime.Seconds <= 0 then
  begin
    Exit;
  end;
  mDialog := FDialog;
  mRow := mDialog.AddRow(cRowHeight);
  mDialog.FParts.BookTime := TCheckBox.Create(mDialog);
  mDialog.FParts.BookTime.Parent := mRow;
  mDialog.FParts.BookTime.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerEndTime);
  mDialog.FParts.BookTime.Left := 0;
  mDialog.FParts.BookTime.Top := mDialog.ScaleValue(cCheckTop);
  mDialog.FParts.BookTime.Width := mDialog.ScaleValue(cLabelWidth);
  mDialog.FParts.BookTime.Checked := True;
  mDialog.FParts.Duration := TEdit.Create(mDialog);
  mDialog.FParts.Duration.Parent := mRow;
  mDialog.FParts.Duration.Left := mDialog.ScaleValue(cFieldLeft);
  mDialog.FParts.Duration.Top := 0;
  mDialog.FParts.Duration.Width := mDialog.ScaleValue(cDurationWidth);
  mDialog.FParts.Duration.Text := TAtlasTimeRounding.ClockText(Int64(TAtlasTimeRounding.Minutes(FTime.Seconds,
    FTime.Rounding)) * SecsPerMin);
  mDialog.FParts.WorkType := TAtlasValueBox.Create(mDialog);
  mDialog.FParts.WorkType.Parent := mRow;
  mDialog.FParts.WorkType.Left := mDialog.ScaleValue(cFieldLeft + cDurationWidth + cGap);
  mDialog.FParts.WorkType.Top := 0;
  mDialog.FParts.WorkType.Width := mDialog.ScaleValue(cFieldWidth - cDurationWidth - cGap);
end;

/// <summary>Zeile für Feld AName mit Oberkante ATop (alTop ordnet nach Top ein).</summary>
function TAtlasEndStepRows.NewFieldRow(const AName: string; ATop: Integer): TAtlasEndFieldRow;
var
  mRow: TPanel;
  mDialog: TAtlasTrackerEndDialog;
begin
  mDialog := FDialog;
  mRow := TPanel.Create(mDialog);
  // Lage vor Align und Parent, damit die Zeile an ihrer Stelle einsortiert wird.
  mRow.Top := ATop;
  mRow.Height := mDialog.ScaleValue(cRowHeight);
  mRow.AlignWithMargins := True;
  mRow.Margins.SetBounds(mDialog.ScaleValue(TAtlasDialog.cRowGap), mDialog.ScaleValue(TAtlasDialog.cRowGap div 2),
    mDialog.ScaleValue(TAtlasDialog.cRowGap), 0);
  mRow.BevelOuter := bvNone;
  mRow.Caption := '';
  mRow.Align := alTop;
  mRow.Parent := mDialog;
  Result.Name := Trim(AName);
  Result.Caption := mDialog.AddLabel(mRow, Result.Name + ':');
  Result.Caption.AutoSize := False;
  Result.Caption.Width := mDialog.ScaleValue(cLabelWidth);
  Result.Caption.EllipsisPosition := epEndEllipsis;
  Result.Caption.Hint := Result.Name;
  Result.Caption.ShowHint := True;
  Result.Box := TAtlasValueBox.Create(mDialog);
  Result.Box.Parent := mRow;
  Result.Box.Left := mDialog.ScaleValue(cFieldLeft);
  Result.Box.Top := 0;
  Result.Box.Width := mDialog.ScaleValue(cFieldWidth);
end;

function TAtlasEndStepRows.AddFieldRow(const AName: string): Integer;
var
  mRow: TAtlasEndFieldRow;
  mIndex: Integer;
begin
  for mIndex := 0 to High(FDialog.FParts.Fields) do
  begin
    if SameText(FDialog.FParts.Fields[mIndex].Name, Trim(AName)) then
    begin
      Exit(mIndex);
    end;
  end;
  // Direkt über dem Übergang, also unter Zeit und den übrigen Feldern.
  mRow := NewFieldRow(AName, FDialog.FParts.StateLabel.Parent.Top - 1);
  FDialog.FParts.Fields := FDialog.FParts.Fields + [mRow];
  FDialog.ClientHeight := FDialog.ClientHeight + mRow.Box.Parent.Height + mRow.Box.Parent.Margins.Top;
  Result := High(FDialog.FParts.Fields);
end;

procedure TAtlasEndStepRows.SetWorkTypes(const ATypes: TArray<string>);
begin
  if FDialog.FParts.WorkType <> nil then
  begin
    FDialog.FParts.WorkType.SetValues(ATypes);
  end;
end;

procedure TAtlasEndStepRows.SetTimeOff;
var
  mParts: TAtlasEndDialogParts;
begin
  mParts := FDialog.FParts;
  if (mParts.BookTime = nil) or FDialog.FProgress.TimeBooked then
  begin
    Exit;
  end;
  FTimeOff := True;
  mParts.BookTime.Checked := False;
  mParts.BookTime.Enabled := False;
  mParts.BookTime.Hint := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TimeBookOff);
  mParts.BookTime.ShowHint := True;
  mParts.Duration.Enabled := False;
  mParts.WorkType.Enabled := False;
end;

procedure TAtlasEndStepRows.SetFieldValues(const AName: string; const AValues: TArray<string>);
var
  mRow: TAtlasEndFieldRow;
begin
  for mRow in FDialog.FParts.Fields do
  begin
    if SameText(mRow.Name, Trim(AName)) then
    begin
      mRow.Box.SetValues(AValues);
    end;
  end;
end;

procedure TAtlasEndStepRows.SetKnownFields(const ANames: TArray<string>);
begin
  FKnownFields := Copy(ANames);
end;

function TAtlasEndStepRows.Fill(var APlan: TAtlasTrackerEndPlan; const ABookedTime: TAtlasTrackerWorkItem;
  ATimeBooked: Boolean): Boolean;
var
  mMinutes: Integer;
  mRow: TAtlasEndFieldRow;
  mParts: TAtlasEndDialogParts;
begin
  Result := True;
  mParts := FDialog.FParts;
  // Schon gebucht: gleiche Buchung behalten, damit der Schritt als erledigt gilt.
  if ATimeBooked then
  begin
    APlan.Time := ABookedTime;
  end
  else if (mParts.BookTime <> nil) and mParts.BookTime.Checked and mParts.BookTime.Enabled then
  begin
    Result := TAtlasTimeRounding.ParseDuration(mParts.Duration.Text, mMinutes) and (mMinutes > 0);
    APlan.Time := TAtlasTrackerWorkItem.Create(mMinutes, FTime.Date, mParts.WorkType.Value, FTime.Text);
  end;
  for mRow in mParts.Fields do
  begin
    APlan.AddField(mRow.Name, mRow.Box.Value);
  end;
end;

procedure TAtlasEndStepRows.Lock(ABusy: Boolean; const AProgress: TAtlasTrackerEndProgress);
var
  mRow: TAtlasEndFieldRow;
  mParts: TAtlasEndDialogParts;
begin
  mParts := FDialog.FParts;
  if mParts.BookTime <> nil then
  begin
    // Gebucht bleibt gesperrt, ebenso bei ausgeschalteter Zeiterfassung (SetTimeOff).
    mParts.BookTime.Enabled := not ABusy and not AProgress.TimeBooked and not FTimeOff;
    mParts.Duration.Enabled := mParts.BookTime.Enabled;
    mParts.WorkType.Enabled := mParts.BookTime.Enabled;
  end;
  for mRow in mParts.Fields do
  begin
    mRow.Box.Enabled := not ABusy and not AProgress.FieldDone(TAtlasTrackerFieldValue.Create(mRow.Name,
      mRow.Box.Value));
  end;
  mParts.AddField.Enabled := not ABusy;
end;

function TAtlasEndStepRows.MarkRejected(const AProgress: TAtlasTrackerEndProgress): string;
var
  mShown: TArray<string>;
  mRow: TAtlasEndFieldRow;
  mParts: TAtlasEndDialogParts;
begin
  mParts := FDialog.FParts;
  mShown := nil;
  for mRow in mParts.Fields do
  begin
    mShown := mShown + [mRow.Name];
  end;
  Result := AProgress.FailedField;
  if Result = '' then
  begin
    Result := TAtlasTrackerEndSteps.MentionedField(AProgress.Outcome.Message, mShown);
  end;
  for mRow in mParts.Fields do
  begin
    if SameText(mRow.Name, Result) then
    begin
      mRow.Caption.Font.Style := [fsBold];
      mRow.Caption.Font.Color := TAtlasUiTheme.TextColor(TAtlasSignalKind.Error);
      mRow.Caption.StyleElements := mRow.Caption.StyleElements - [seFont];
    end;
  end;
  FMissingField := '';
  if Result = '' then
  begin
    FMissingField := TAtlasTrackerEndSteps.MentionedField(AProgress.Outcome.Message, FKnownFields);
    Result := FMissingField;
  end;
  mParts.AddField.Visible := FMissingField <> '';
  if FMissingField <> '' then
  begin
    mParts.AddField.Caption := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerEndAddField, [FMissingField]);
    FitButton(FDialog, mParts.AddField);
  end;
end;

procedure TAtlasEndStepRows.AddFieldClick(Sender: TObject);
var
  mIndex: Integer;
begin
  if (FMissingField = '') or FDialog.Sending then
  begin
    Exit;
  end;
  mIndex := AddFieldRow(FMissingField);
  FMissingField := '';
  FDialog.FParts.AddField.Visible := False;
  if FDialog.FParts.Fields[mIndex].Box.CanFocus and FDialog.Showing then
  begin
    FDialog.FParts.Fields[mIndex].Box.SetFocus;
  end;
end;

{ TAtlasTrackerEndDialog }

constructor TAtlasTrackerEndDialog.CreateDialog(AOwner: TComponent; const ARequest: TAtlasTrackerEndRequest);
var
  mSteps: TPanel;
begin
  inherited CreateDialog(AOwner, '', cDialogWidth);
  FKey := ARequest.Key;
  FOptions := ARequest.Options;
  FPlan := TAtlasTrackerEndPlan.Create(TAtlasTrackerWrite.Empty);
  FProgress := TAtlasTrackerEndProgress.Empty;
  Caption := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerEndCaption, [FKey]);
  KeyPreview := True;
  OnKeyDown := DialogKeyDown;
  OnCloseQuery := DialogCloseQuery;
  // Reihenfolge wie beim Schreiben: Zeit, Felder, Übergang; Kommentar darunter.
  FRows := TAtlasEndStepRows.CreateRows(Self, ARequest.Time, FOptions.EndFields);
  AddState;
  AddComment(ARequest.Comment);
  AddHandOver;
  mSteps := AddRow(cTextRowHeight);
  FParts.Steps := TLabel.Create(Self);
  FParts.Steps.Parent := mSteps;
  FParts.Steps.Align := alClient;
  FParts.Steps.Caption := '';
  AddButtons(mSteps.BoundsRect.Bottom + 1);
  ActiveControl := FParts.Comment;
end;

/// <summary>Zielzustand; Vorgabe ist der erste angebotene, ohne Liste „Zustand nicht ändern“.</summary>
procedure TAtlasTrackerEndDialog.AddState;
var
  mRow: TPanel;
  mLabel: TLabel;
  mChoices: TArray<string>;
begin
  mRow := AddRow(cRowHeight);
  mLabel := TLabel.Create(Self);
  mLabel.Parent := mRow;
  mLabel.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerEndState);
  mLabel.Left := 0;
  mLabel.Top := ScaleValue(4);
  // Lange Beschriftung „Übergang (ab „…“)“ endet mit „…“ vor der Klappliste, voll im Hinweis.
  mLabel.AutoSize := False;
  mLabel.Width := ScaleValue(cLabelWidth);
  mLabel.EllipsisPosition := epEndEllipsis;
  mLabel.ShowHint := True;
  FParts.StateLabel := mLabel;
  FParts.State := TAtlasValueBox.Create(Self);
  FParts.State.Parent := mRow;
  FParts.State.Left := ScaleValue(cFieldLeft);
  FParts.State.Top := 0;
  FParts.State.Width := ScaleValue(cFieldWidth);
  mChoices := TAtlasTrackerEndTexts.StateChoices(FOptions);
  FParts.State.SetValues(mChoices);
  FParts.State.Value := mChoices[Min(1, High(mChoices))];
end;

/// <summary>Kommentar-Editor (#1278) mit seiner Leiste unter dem Feld; die Vorlage ist kein Entwurf.</summary>
procedure TAtlasTrackerEndDialog.AddComment(const AComment: string);
var
  mRow: TPanel;
  mLabel: TLabel;
begin
  mRow := AddRow(cTextRowHeight);
  mLabel := TLabel.Create(Self);
  mLabel.Parent := mRow;
  mLabel.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerEndComment);
  mLabel.Left := 0;
  mLabel.Top := ScaleValue(2);
  FParts.Editor := TAtlasCommentEditor.Create(Self);
  FParts.Editor.Parent := Self;
  FParts.Editor.Align := alTop;
  FParts.Editor.AlignWithMargins := True;
  FParts.Editor.Margins.SetBounds(cGap, cGap div 2, cGap, 0);
  FParts.Editor.Top := mRow.Top + mRow.Height + 1;
  FParts.Editor.Height := ScaleValue(cCommentHeight + cEditorBarHeight);
  FParts.Editor.Events := TAtlasCommentEditorEvents.Create(SendClick, EditorCancel);
  FParts.Editor.SetText(AComment);
  FParts.Comment := FParts.Editor.Memo;
end;

/// <summary>„Zuständigkeit übergeben an“ und die Zeile für Hinweise; liefert die Hinweiszeile.</summary>
function TAtlasTrackerEndDialog.AddHandOver: TPanel;
var
  mRow: TPanel;
begin
  mRow := AddRow(cRowHeight);
  mRow.Top := FParts.Editor.Top + FParts.Editor.Height + 1;
  FParts.HandOver := TCheckBox.Create(Self);
  FParts.HandOver.Parent := mRow;
  FParts.HandOver.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerEndHandOver);
  FParts.HandOver.Left := 0;
  FParts.HandOver.Top := ScaleValue(cCheckTop);
  FParts.HandOver.Width := ScaleValue(cLabelWidth);
  FParts.Assignee := TAtlasValueBox.Create(Self);
  FParts.Assignee.Parent := mRow;
  FParts.Assignee.Left := ScaleValue(cFieldLeft);
  FParts.Assignee.Top := 0;
  FParts.Assignee.Width := ScaleValue(cFieldWidth);
  FParts.Assignee.OnChange := AssigneeChange;

  Result := AddRow(cTextRowHeight);
  FParts.Note := TLabel.Create(Self);
  FParts.Note.Parent := Result;
  FParts.Note.Align := alClient;
  FParts.Note.WordWrap := True;
  FParts.Note.Caption := '';
end;

procedure TAtlasTrackerEndDialog.AddButtons(ATop: Integer);
var
  mButtons: TFlowPanel;
begin
  mButtons := TFlowPanel.Create(Self);
  mButtons.Parent := Self;
  mButtons.Align := alTop;
  mButtons.AutoSize := True;
  mButtons.BevelOuter := bvNone;
  mButtons.AlignWithMargins := True;
  mButtons.Margins.SetBounds(cGap, cGap, cGap, cGap);
  mButtons.Top := ATop;
  FParts.AddField := NewButton(Self, mButtons, '');
  FParts.AddField.Visible := False;
  FParts.AddField.OnClick := FRows.AddFieldClick;
  FParts.Send := NewButton(Self, mButtons, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerEndSend));
  FParts.Send.OnClick := SendClick;
  FParts.Send.Default := True;
  FParts.Cancel := NewButton(Self, mButtons, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerEndCancel));
  FParts.Cancel.ModalResult := mrCancel;
  FParts.Cancel.Cancel := True;
  ClientHeight := mButtons.Top + mButtons.Height + ScaleValue(cGap);
end;

class function TAtlasTrackerEndTexts.StateChoices(const AOptions: TAtlasTrackerSyncOptions): TArray<string>;
begin
  Result := TArray<string>.Create(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerEndKeepState))
    + Copy(AOptions.EndStates);
end;

procedure TAtlasTrackerEndDialog.SetStates(const AStates: TArray<string>);
var
  mChoices: TArray<string>;
  mState, mChoice: string;
  mFound: Boolean;
begin
  FStates := Copy(AStates);
  // Unter einer Zustandsmaschine nur die Übergänge; die Zustände verraten deren Ziele.
  if FRules.StateMachine then
  begin
    ShowTransitions;
    Exit;
  end;
  mChoices := TAtlasTrackerEndTexts.StateChoices(FOptions);
  for mState in AStates do
  begin
    mFound := False;
    for mChoice in mChoices do
    begin
      if SameText(mChoice, mState) then
      begin
        mFound := True;
      end;
    end;
    if not mFound then
    begin
      mChoices := mChoices + [mState];
    end;
  end;
  FParts.State.SetValues(mChoices);
end;

class function TAtlasTrackerEndTexts.TransitionChoices(const ARules: TAtlasTrackerStateRules;
  const AStates: TArray<string>): TArray<string>;
var
  mTransition: TAtlasTrackerTransition;
begin
  Result := TArray<string>.Create(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerEndKeepState));
  for mTransition in ARules.Transitions do
  begin
    Result := Result + [TAtlasTrackerTransitions.ChoiceText(mTransition, AStates)];
  end;
end;

procedure TAtlasTrackerEndDialog.SetRules(const ARules: TAtlasTrackerStateRules);
begin
  if not ARules.StateMachine or (ARules.FieldId = '') then
  begin
    Exit;
  end;
  FRules := ARules;
  ShowTransitions;
end;

/// <summary>Klappliste und Beschriftung nach FRules; Vorwahl nach issues.endStates, Hinweis, wenn der erste Wunsch
/// ab hier nicht erlaubt ist.</summary>
procedure TAtlasTrackerEndDialog.ShowTransitions;
var
  mChoices, mKnown: TArray<string>;
  mPreferred: Integer;
begin
  if FRules.Current <> '' then
  begin
    FParts.StateLabel.Caption := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerEndTransitionFrom,
      [FRules.Current]);
  end
  else
  begin
    FParts.StateLabel.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerEndTransition);
  end;
  FParts.StateLabel.Hint := FParts.StateLabel.Caption;
  mKnown := FOptions.EndStates + FStates;
  mChoices := TAtlasTrackerEndTexts.TransitionChoices(FRules, mKnown);
  FParts.State.SetValues(mChoices);
  mPreferred := TAtlasTrackerTransitions.Preferred(FRules, FOptions.EndStates);
  FParts.State.Value := mChoices[mPreferred + 1];
  FParts.Note.Caption := '';
  if (Length(FOptions.EndStates) > 0) and (FRules.Current <> '') and
    (TAtlasTrackerTransitions.Into(FRules, TArray<string>.Create(FOptions.EndStates[0])) < 0) then
  begin
    FParts.Note.Caption := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerEndNotAllowed,
      [FOptions.EndStates[0], FRules.Current]);
  end;
end;

/// <summary>Gewählter Übergang (Index in FRules.Transitions); -1 = Zustand nicht ändern bzw. von Hand
/// eingetragener Text, zu dem kein Übergang passt.</summary>
function TAtlasTrackerEndDialog.ChosenTransition: Integer;
var
  mChoices: TArray<string>;
  mIndex: Integer;
begin
  mChoices := TAtlasTrackerEndTexts.TransitionChoices(FRules, FOptions.EndStates + FStates);
  for mIndex := 1 to High(mChoices) do
  begin
    if SameText(Trim(FParts.State.Value), mChoices[mIndex]) then
    begin
      Exit(mIndex - 1);
    end;
  end;
  // Von Hand eingetragen: Name, Kennung oder Ziel eines Übergangs.
  Result := TAtlasTrackerTransitions.Preferred(FRules, TArray<string>.Create(Trim(FParts.State.Value)));
end;

procedure TAtlasTrackerEndDialog.SetUsers(const AUsers: TArray<string>);
begin
  FParts.Assignee.SetValues(AUsers);
end;

procedure TAtlasTrackerEndDialog.AssigneeChange(Sender: TObject);
begin
  // Wer einen Namen einträgt, will übergeben.
  if FParts.Assignee.Value <> '' then
  begin
    FParts.HandOver.Checked := True;
  end;
end;

function TAtlasTrackerEndDialog.Change: TAtlasTrackerWrite;
var
  mState: string;
  mTransition: Integer;
  mKeep: Boolean;
begin
  mState := FParts.State.Value;
  mKeep := SameText(mState, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerEndKeepState));
  if FRules.StateMachine and not mKeep then
  begin
    mTransition := ChosenTransition;
    // Ohne passenden Übergang geht der Text als Wert hinaus; YouTrack begründet die Ablehnung.
    if mTransition >= 0 then
    begin
      Exit(TAtlasTrackerWorkflow.EndTransition(FOptions, FRules, mTransition,
        StringReplace(FParts.Comment.Text, #13#10, #10, [rfReplaceAll]), FParts.HandOver.Checked,
        FParts.Assignee.Value));
    end;
  end;
  if SameText(mState, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerEndKeepState)) then
  begin
    mState := '';
  end;
  Result := TAtlasTrackerWorkflow.EndChange(FOptions, mState,
    StringReplace(FParts.Comment.Text, #13#10, #10, [rfReplaceAll]), FParts.HandOver.Checked,
    FParts.Assignee.Value);
end;

procedure TAtlasTrackerEndDialog.SetBusy(AValue: Boolean);
var
  mOpen: Boolean;
begin
  FSending := AValue;
  // Geschriebenes bleibt gesperrt: Beim erneuten Senden wird es übersprungen.
  FRows.Lock(AValue, FProgress);
  mOpen := not AValue and not FProgress.CommentDone;
  FParts.State.Enabled := not AValue;
  FParts.Comment.ReadOnly := not mOpen;
  FParts.HandOver.Enabled := mOpen;
  FParts.Assignee.Enabled := mOpen;
  FParts.Send.Enabled := not AValue;
  FParts.Cancel.Enabled := not AValue;
end;

function TAtlasTrackerEndDialog.Plan(out APlan: TAtlasTrackerEndPlan): Boolean;
var
  mBooked: TAtlasTrackerWorkItem;
begin
  // Vor dem Überschreiben merken: SendClick plant in FPlan selbst.
  mBooked := FPlan.Time;
  APlan := TAtlasTrackerEndPlan.Create(Change);
  Result := FRows.Fill(APlan, mBooked, FProgress.TimeBooked);
end;

procedure TAtlasTrackerEndDialog.SendClick(Sender: TObject);
var
  mDialog: TAtlasTrackerEndDialog;
begin
  if FSending then
  begin
    Exit;
  end;
  if not Plan(FPlan) then
  begin
    ShowErrorNote(FParts.Note, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TimeBookInvalid));
    Exit;
  end;
  // Nichts (mehr) zu schreiben: nur beenden.
  if FProgress.Finished(FPlan) or not Assigned(FOnSend) then
  begin
    FSent := True;
    FParts.Editor.Sent;
    ModalResult := mrOk;
    Exit;
  end;
  FParts.Note.Font.Color := clWindowText;
  FParts.Note.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerEndSending);
  SetBusy(True);
  mDialog := Self;
  FOnSend(FPlan, FProgress,
    procedure(const AProgress: TAtlasTrackerEndProgress)
    begin
      mDialog.StepsDone(AProgress);
    end);
end;

procedure TAtlasTrackerEndDialog.StepsDone(const AProgress: TAtlasTrackerEndProgress);
var
  mField: string;
begin
  FProgress := AProgress;
  SetBusy(False);
  FParts.Steps.Caption := TAtlasTrackerEndTexts.StepsText(FPlan, FProgress);
  if FProgress.Finished(FPlan) then
  begin
    FSent := True;
    // Geschrieben: Der Entwurf hat sich erledigt.
    FParts.Editor.Sent;
    FParts.Note.Caption := '';
    ModalResult := mrOk;
    Exit;
  end;
  // Kein neuer Versuch von selbst: Der Benutzer ändert und sendet erneut oder bricht ab.
  ShowErrorNote(FParts.Note, ErrorText(FKey, FProgress.Outcome));
  mField := FRows.MarkRejected(FProgress);
  if mField <> '' then
  begin
    FParts.Note.Caption := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerEndFixField,
      [FParts.Note.Caption, mField]);
  end;
end;

/// <summary>Name eines Schritts; der letzte heißt unter einer Zustandsmaschine „Übergang“.</summary>
function StepName(const APlan: TAtlasTrackerEndPlan; AStep: TAtlasTrackerEndStep): string;
begin
  case AStep of
    TAtlasTrackerEndStep.Time:
      Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerStepTime);
    TAtlasTrackerEndStep.Fields:
      Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerStepFields);
    TAtlasTrackerEndStep.Comment:
      Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerStepComment);
  else
    if APlan.Change.Transition.Id <> '' then
    begin
      Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerStepTransition);
    end
    else
    begin
      Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerStepState);
    end;
  end;
end;

class function TAtlasTrackerEndTexts.StepsText(const APlan: TAtlasTrackerEndPlan;
  const AProgress: TAtlasTrackerEndProgress): string;
var
  mStep: TAtlasTrackerEndStep;
  mParts: TArray<string>;
  mMark: string;
begin
  mParts := nil;
  for mStep := Low(TAtlasTrackerEndStep) to High(TAtlasTrackerEndStep) do
  begin
    case AProgress.StateOf(APlan, mStep) of
      TAtlasTrackerStepState.Skipped:
        Continue;
      TAtlasTrackerStepState.Done:
        mMark := cDoneMark;
      TAtlasTrackerStepState.Failed:
        mMark := cFailedMark;
    else
      mMark := '';
    end;
    mParts := mParts + [mMark + IntToStr(Length(mParts) + 1) + ' ' + StepName(APlan, mStep)];
  end;
  Result := string.Join('   ', mParts);
end;

class function TAtlasTrackerEndTexts.EndSummary(const APlan: TAtlasTrackerEndPlan;
  const AProgress: TAtlasTrackerEndProgress): string;
var
  mParts, mNames: TArray<string>;
  mField: TAtlasTrackerFieldValue;
begin
  mParts := nil;
  if AProgress.TimeBooked and (APlan.Time.Minutes > 0) then
  begin
    mParts := mParts + [TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerPartTime,
      [TAtlasTrackerWorkflow.DurationText(APlan.Time.Minutes)])];
  end;
  mNames := nil;
  for mField in APlan.Fields do
  begin
    if AProgress.FieldDone(mField) then
    begin
      mNames := mNames + [mField.Name];
    end;
  end;
  if Length(mNames) > 0 then
  begin
    mParts := mParts + [TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerPartFields, [string.Join(', ', mNames)])];
  end;
  if AProgress.TransitionDone and APlan.TransitionPart.HasWork then
  begin
    mParts := mParts + [TAtlasTrackerEndDialog.SummaryText(APlan.TransitionPart)];
  end;
  if AProgress.CommentDone and APlan.CommentPart.HasWork then
  begin
    mParts := mParts + [TAtlasTrackerEndDialog.SummaryText(APlan.CommentPart)];
  end;
  Result := string.Join(', ', mParts);
end;

procedure TAtlasTrackerEndDialog.DialogCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  // Während des Sendens nicht schließen: Das Ergebnis kommt noch an diesen Dialog.
  CanClose := not FSending;
end;

procedure TAtlasTrackerEndDialog.EditorCancel(Sender: TObject);
begin
  // Esc im Kommentarfeld (ohne offene Vorschlagsliste); der Editor hat den Entwurf schon gesichert.
  if not FSending then
  begin
    ModalResult := mrCancel;
  end;
end;

procedure TAtlasTrackerEndDialog.DialogKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  // Im Kommentarfeld sendet der Editor selbst (und schluckt das Zeichen der Taste).
  if ActiveControl = FParts.Comment then
  begin
    Exit;
  end;
  if (Key = VK_RETURN) and (ssCtrl in Shift) then
  begin
    Key := 0;
    SendClick(Self);
  end;
end;

class function TAtlasTrackerEndDialog.ErrorText(const AKey: string; const AResult: TAtlasTrackerWriteResult): string;
begin
  case AResult.Error of
    TAtlasCiFetchError.None:
      Exit('');
    TAtlasCiFetchError.Unauthorized:
      if AResult.Status = 403 then
      begin
        Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerWriteForbidden, [AKey, AResult.Status]);
      end
      else
      begin
        Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerWriteUnauthorized, [AKey, AResult.Status]);
      end;
    TAtlasCiFetchError.NotFound:
      Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerWriteNotFound, [AKey, AResult.Status]);
    TAtlasCiFetchError.Invalid:
      Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerWriteInvalid, [AKey, AResult.Status]);
    TAtlasCiFetchError.Server:
      Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerWriteServer, [AKey, AResult.Status]);
    TAtlasCiFetchError.Timeout:
      Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerWriteTimeout);
    TAtlasCiFetchError.NotConfigured:
      Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerWriteNotConfigured);
    TAtlasCiFetchError.UnknownProvider:
      Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerWriteUnsupported);
  else
    Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerWriteNetwork);
  end;
  if AResult.Message <> '' then
  begin
    Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerWriteReason, [Result, AResult.Message]);
  end;
end;

class function TAtlasTrackerEndDialog.SummaryText(const AChange: TAtlasTrackerWrite): string;
begin
  Result := SummaryText(AChange, '');
end;

class function TAtlasTrackerEndDialog.SummaryText(const AChange: TAtlasTrackerWrite; const ANewState: string): string;
var
  mParts: TArray<string>;
begin
  mParts := nil;
  if (AChange.Transition.Id <> '') and (Trim(ANewState) <> '') then
  begin
    mParts := mParts + [TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerPartTransitionTo,
      [AChange.Transition.Caption, Trim(ANewState)])];
  end
  else if AChange.Transition.Id <> '' then
  begin
    mParts := mParts + [TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerPartTransition,
      [AChange.Transition.Caption])];
  end
  else if AChange.State <> '' then
  begin
    mParts := mParts + [TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerPartState, [AChange.State])];
  end;
  case AChange.Assign of
    TAtlasTrackerAssign.Me:
      mParts := mParts + [TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerPartAssigned)];
    TAtlasTrackerAssign.User:
      mParts := mParts + [TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerPartHandedOver, [AChange.Assignee])];
  else
    // Keep: Zuständigkeit bleibt.
  end;
  if AChange.Comment <> '' then
  begin
    mParts := mParts + [TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerPartComment)];
  end;
  Result := string.Join(', ', mParts);
end;

class function TAtlasTrackerEndDialog.Execute(const ARequest: TAtlasTrackerEndRequest;
  const AOnSend: TAtlasTrackerEndSendEvent; const APrepare: TProc<TAtlasTrackerEndDialog>;
  out AOutcome: TAtlasTrackerEndOutcome): Boolean;
var
  mDialog: TAtlasTrackerEndDialog;
begin
  mDialog := TAtlasTrackerEndDialog.CreateDialog(nil, ARequest);
  try
    mDialog.OnSend := AOnSend;
    if Assigned(APrepare) then
    begin
      APrepare(mDialog);
    end;
    Result := (mDialog.ShowModal = mrOk) and mDialog.Sent;
    AOutcome.Plan := mDialog.FPlan;
    AOutcome.Progress := mDialog.FProgress;
    AOutcome.Finished := Result;
    AOutcome.TimeSeconds := ARequest.Time.Seconds;
    // Entwurf sichern, solange das Fenster noch lebt (nach Senden ist er schon gelöscht).
    mDialog.FParts.Editor.Unbind;
  finally
    mDialog.Free;
  end;
end;

end.
