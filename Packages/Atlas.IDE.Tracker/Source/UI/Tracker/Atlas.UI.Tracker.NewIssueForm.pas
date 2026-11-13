unit Atlas.UI.Tracker.NewIssueForm;

// Eingaben im Dialog „Issue anlegen“ für GitHub (#2137), reine VCL:
// - TAtlasNewIssueFormPanel: die Felder einer Issue-Vorlage untereinander in
//   einem rollbaren Bereich, je Feld die Beschriftung (Pflichtfelder mit „*“)
//   und darunter die Eingabe: input als Eingabefeld, textarea mehrzeilig (mit
//   render in Consolas), dropdown als Klappliste bzw. mit multiple als
//   Kontrollkästchen, checkboxes als Kontrollkästchen, markdown als
//   schreibgeschützter Hinweistext. Beschreibung und Platzhalter der Vorlage
//   stehen im Tooltip.
// - TAtlasNewIssueFieldRows: die Issue-Felder des Repositorys (Text, Zahl,
//   Datum, Einfachauswahl) als Zeilen wie die übrigen des Dialogs.
// Lesen, Vorbelegen, Prüfen und Beschreibung macht Atlas.Core.Tracker.IssueForms;
// hier stehen nur Aufbau, Werte setzen und Werte lesen. Die Steuerelemente
// brauchen beim Aufbau kein Fenster (Klapplisten über TAtlasNewIssueBox).

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Atlas.Core.Tracker.IssueForms,
  Atlas.Core.Tracker.NewIssueGitHub,
  Atlas.UI.Tracker.NewIssueBox;

type
  /// <summary>Eingabe zu einem Feld der Vorlage: genau eines von Edit, Memo, Box bzw. Checks ist gesetzt.</summary>
  TAtlasNewIssueFormInput = record
    Edit: TEdit;
    Memo: TMemo;
    Box: TAtlasNewIssueBox;
    /// <summary>Box mit leerem ersten Eintrag (Feld ohne Pflicht): Option = Choice - 1.</summary>
    BoxOffset: Integer;
    Checks: TArray<TCheckBox>;
    /// <summary>Erstes Steuerelement für den Fokus; nil bei markdown.</summary>
    Focus: TWinControl;
  end;

  /// <summary>Felder einer Issue-Vorlage in einem rollbaren Bereich.</summary>
  TAtlasNewIssueFormPanel = class(TScrollBox)
  private
    FForm: TAtlasIssueForm;
    FHost: TPanel;
    FInputs: TArray<TAtlasNewIssueFormInput>;
    FNote: TMemo;
    function Scaled(AValue: Integer): Integer;
    function AddRow(AHeight: Integer): TPanel;
    function AddCaption(ARow: TPanel; const AField: TAtlasIssueFormField): Integer;
    function AddText(ARow: TPanel; ATop, AHeight: Integer; AMultiLine: Boolean): TCustomEdit;
    procedure AddChecks(ARow: TPanel; ATop: Integer; const AOptions: TArray<string>;
      var AInput: TAtlasNewIssueFormInput);
    procedure AddChoice(ARow: TPanel; ATop: Integer; const AField: TAtlasIssueFormField;
      var AInput: TAtlasNewIssueFormInput);
    function BuildField(const AField: TAtlasIssueFormField): TAtlasNewIssueFormInput;
    procedure SetAnswer(const AInput: TAtlasNewIssueFormInput; const AAnswer: TAtlasIssueFormAnswer);
    function AnswerOf(const AInput: TAtlasNewIssueFormInput): TAtlasIssueFormAnswer;
    procedure ClearHost;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Felder von AForm mit den Werten AAnswers aufbauen; AWidth: Breite des Inhalts, ANote: Zeile über den
    /// Feldern ('' = keine).</summary>
    procedure ShowForm(const AForm: TAtlasIssueForm; const AAnswers: TAtlasIssueFormAnswers; AWidth: Integer;
      const ANote: string);
    /// <summary>Eingaben je Feld der Vorlage (markdown leer).</summary>
    function Answers: TAtlasIssueFormAnswers;
    /// <summary>Fokus auf das erste Feld mit der Beschriftung bzw. Option ACaption.</summary>
    procedure FocusCaption(const ACaption: string);
    property Form: TAtlasIssueForm read FForm;
    property Inputs: TArray<TAtlasNewIssueFormInput> read FInputs;
    /// <summary>Zeile über den Feldern (Labels, Zuständige, Projekte der Vorlage bzw. Hinweis).</summary>
    property Note: TMemo read FNote;
  end;

  /// <summary>Issue-Felder des Repositorys als Zeilen mit Beschriftung links.</summary>
  TAtlasNewIssueFieldRows = class(TPanel)
  private
    FFields: TArray<TAtlasGitHubIssueField>;
    FEdits: TArray<TEdit>;
    FBoxes: TArray<TAtlasNewIssueBox>;
    function Scaled(AValue: Integer): Integer;
  public
    destructor Destroy; override;
    /// <summary>Zeilen für AFields aufbauen (alte entfallen); Höhe danach = Zeilen × ARowHeight.</summary>
    procedure ShowFields(const AFields: TArray<TAtlasGitHubIssueField>; ALabelWidth, ARowHeight: Integer);
    /// <summary>Werte der ausgefüllten Felder.</summary>
    function Values: TArray<TAtlasGitHubFieldValue>;
    /// <summary>Name des ersten Felds, dessen Wert nicht zu seiner Art passt; '' wenn alle passen.</summary>
    function InvalidField: string;
    property Fields: TArray<TAtlasGitHubIssueField> read FFields;
    property Edits: TArray<TEdit> read FEdits;
    property Boxes: TArray<TAtlasNewIssueBox> read FBoxes;
  end;

implementation

uses
  System.Math,
  Atlas.UI.Tracker.NewIssue.Strings;

const
  cGap = 8;
  cCaptionHeight = 20;
  cEditHeight = 24;
  cMemoHeight = 72;
  cNoteHeight = 52;
  cCheckHeight = 22;
  cCodeFontName = 'Consolas';
  cRequiredMark = ' *';
  cControlTop = 4;

{ TAtlasNewIssueFormPanel }

constructor TAtlasNewIssueFormPanel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BorderStyle := bsNone;
  HorzScrollBar.Visible := False;
  VertScrollBar.Tracking := True;
  FForm := TAtlasIssueForm.Empty;
end;

destructor TAtlasNewIssueFormPanel.Destroy;
begin
  FInputs := nil;
  FForm := TAtlasIssueForm.Empty;
  inherited Destroy;
end;

function TAtlasNewIssueFormPanel.Scaled(AValue: Integer): Integer;
begin
  Result := ScaleValue(AValue);
end;

procedure TAtlasNewIssueFormPanel.ClearHost;
begin
  FInputs := nil;
  FNote := nil;
  // Die Steuerelemente gehören FHost; mit ihm gehen sie.
  FreeAndNil(FHost);
end;

function TAtlasNewIssueFormPanel.AddRow(AHeight: Integer): TPanel;
begin
  Result := TPanel.Create(FHost);
  Result.Top := FHost.Height;
  Result.Height := AHeight;
  Result.Align := alTop;
  Result.Parent := FHost;
  Result.BevelOuter := bvNone;
  FHost.Height := FHost.Height + AHeight;
end;

function TAtlasNewIssueFormPanel.AddCaption(ARow: TPanel; const AField: TAtlasIssueFormField): Integer;
var
  mLabel: TLabel;
begin
  mLabel := TLabel.Create(FHost);
  mLabel.Parent := ARow;
  mLabel.Left := 0;
  mLabel.Top := Scaled(cControlTop);
  mLabel.ShowAccelChar := False;
  mLabel.Caption := AField.Caption;
  if AField.Required then
  begin
    mLabel.Caption := AField.Caption + cRequiredMark;
  end;
  mLabel.Hint := AField.Description;
  mLabel.ShowHint := AField.Description <> '';
  Result := Scaled(cCaptionHeight);
end;

function TAtlasNewIssueFormPanel.AddText(ARow: TPanel; ATop, AHeight: Integer; AMultiLine: Boolean): TCustomEdit;
begin
  if AMultiLine then
  begin
    Result := TMemo.Create(FHost);
    TMemo(Result).ScrollBars := ssVertical;
    TMemo(Result).WantReturns := True;
  end
  else
  begin
    Result := TEdit.Create(FHost);
  end;
  Result.Parent := ARow;
  Result.Left := 0;
  Result.Top := ATop;
  Result.Width := ARow.ClientWidth - Scaled(cGap);
  Result.Height := AHeight;
  Result.Anchors := [akLeft, akTop, akRight];
end;

procedure TAtlasNewIssueFormPanel.AddChecks(ARow: TPanel; ATop: Integer; const AOptions: TArray<string>;
  var AInput: TAtlasNewIssueFormInput);
var
  mIndex: Integer;
  mCheck: TCheckBox;
begin
  for mIndex := 0 to High(AOptions) do
  begin
    mCheck := TCheckBox.Create(FHost);
    mCheck.Parent := ARow;
    mCheck.Left := 0;
    mCheck.Top := ATop + mIndex * Scaled(cCheckHeight);
    mCheck.Width := ARow.ClientWidth - Scaled(cGap);
    mCheck.Anchors := [akLeft, akTop, akRight];
    mCheck.Caption := AOptions[mIndex];
    AInput.Checks := AInput.Checks + [mCheck];
  end;
  if Length(AInput.Checks) > 0 then
  begin
    AInput.Focus := AInput.Checks[0];
  end;
end;

/// <summary>Höhe der Zeile eines Felds ohne Beschriftung.</summary>
function InputHeight(const AField: TAtlasIssueFormField): Integer;
begin
  case AField.Kind of
    TAtlasIssueFormKind.Markdown:
      Result := cNoteHeight;
    TAtlasIssueFormKind.Textarea:
      Result := cMemoHeight;
    TAtlasIssueFormKind.Checkboxes:
      Result := Max(1, Length(AField.Options)) * cCheckHeight;
    TAtlasIssueFormKind.Dropdown:
      begin
        Result := cEditHeight;
        if AField.Multiple then
        begin
          Result := Max(1, Length(AField.Options)) * cCheckHeight;
        end;
      end;
  else
    Result := cEditHeight;
  end;
end;

/// <summary>Hinweistext (markdown) bzw. Zeile über den Feldern: schreibgeschützt, ohne Rahmen.</summary>
procedure StyleNote(AMemo: TMemo);
begin
  AMemo.ReadOnly := True;
  AMemo.BorderStyle := bsNone;
  AMemo.ParentColor := True;
  AMemo.TabStop := False;
  AMemo.WordWrap := True;
  AMemo.ScrollBars := ssNone;
end;

/// <summary>Klappliste mit einer Auswahl; ohne Pflicht zuerst ein leerer Eintrag (BoxOffset 1).</summary>
procedure TAtlasNewIssueFormPanel.AddChoice(ARow: TPanel; ATop: Integer; const AField: TAtlasIssueFormField;
  var AInput: TAtlasNewIssueFormInput);
var
  mValues: TArray<string>;
begin
  AInput.Box := TAtlasNewIssueBox.Create(FHost);
  AInput.Box.Style := csDropDownList;
  AInput.Box.Parent := ARow;
  AInput.Box.Left := 0;
  AInput.Box.Top := ATop;
  AInput.Box.Width := ARow.ClientWidth - Scaled(cGap);
  AInput.Box.Anchors := [akLeft, akTop, akRight];
  mValues := AField.Options;
  // Ohne Pflicht lässt GitHub die Auswahl leer („None“).
  if not AField.Required then
  begin
    mValues := TArray<string>.Create('') + mValues;
    AInput.BoxOffset := 1;
  end;
  AInput.Box.SetValues(mValues);
  AInput.Focus := AInput.Box;
end;

function TAtlasNewIssueFormPanel.BuildField(const AField: TAtlasIssueFormField): TAtlasNewIssueFormInput;
var
  mRow: TPanel;
  mTop: Integer;
begin
  Result := Default(TAtlasNewIssueFormInput);
  Result.Checks := nil;
  mTop := 0;
  mRow := AddRow(Scaled(InputHeight(AField) + cGap));
  if AField.Editable then
  begin
    mRow.Height := mRow.Height + Scaled(cCaptionHeight);
    FHost.Height := FHost.Height + Scaled(cCaptionHeight);
    mTop := AddCaption(mRow, AField);
  end;
  case AField.Kind of
    TAtlasIssueFormKind.Markdown:
      begin
        Result.Memo := TMemo(AddText(mRow, mTop, Scaled(cNoteHeight), True));
        StyleNote(Result.Memo);
        Result.Memo.Text := StringReplace(AField.Value, #10, sLineBreak, [rfReplaceAll]);
      end;
    TAtlasIssueFormKind.Input:
      begin
        Result.Edit := TEdit(AddText(mRow, mTop, Scaled(cEditHeight), False));
        Result.Edit.TextHint := AField.Placeholder;
        Result.Focus := Result.Edit;
      end;
    TAtlasIssueFormKind.Textarea:
      begin
        Result.Memo := TMemo(AddText(mRow, mTop, Scaled(cMemoHeight), True));
        if AField.Render <> '' then
        begin
          Result.Memo.Font.Name := cCodeFontName;
          Result.Memo.WordWrap := False;
          Result.Memo.ScrollBars := ssBoth;
        end;
        Result.Focus := Result.Memo;
      end;
    TAtlasIssueFormKind.Dropdown:
      begin
        if AField.Multiple then
        begin
          AddChecks(mRow, mTop, AField.Options, Result);
        end
        else
        begin
          AddChoice(mRow, mTop, AField, Result);
        end;
      end;
    TAtlasIssueFormKind.Checkboxes:
      AddChecks(mRow, mTop, AField.Options, Result);
  end;
  // Beschreibung und Platzhalter der Vorlage als Tooltip (ein Memo kennt keinen Platzhaltertext).
  if (Result.Focus <> nil) and (Trim(AField.Description + AField.Placeholder) <> '') then
  begin
    Result.Focus.Hint := Trim(AField.Description + sLineBreak + AField.Placeholder);
    Result.Focus.ShowHint := True;
  end;
end;

procedure TAtlasNewIssueFormPanel.SetAnswer(const AInput: TAtlasNewIssueFormInput;
  const AAnswer: TAtlasIssueFormAnswer);
var
  mIndex: Integer;
begin
  if AInput.Edit <> nil then
  begin
    AInput.Edit.Text := AAnswer.Text;
  end
  else if (AInput.Memo <> nil) and (AInput.Focus <> nil) then
  begin
    AInput.Memo.Text := StringReplace(AAnswer.Text, #10, sLineBreak, [rfReplaceAll]);
  end
  else if AInput.Box <> nil then
  begin
    AInput.Box.Choice := AInput.BoxOffset - 1;
    if Length(AAnswer.Chosen) > 0 then
    begin
      AInput.Box.Choice := AAnswer.Chosen[0] + AInput.BoxOffset;
    end;
  end;
  for mIndex := 0 to High(AInput.Checks) do
  begin
    AInput.Checks[mIndex].Checked := AAnswer.Has(mIndex);
  end;
end;

function TAtlasNewIssueFormPanel.AnswerOf(const AInput: TAtlasNewIssueFormInput): TAtlasIssueFormAnswer;
var
  mIndex: Integer;
begin
  Result := Default(TAtlasIssueFormAnswer);
  Result.Chosen := nil;
  if AInput.Edit <> nil then
  begin
    Result.Text := AInput.Edit.Text;
  end
  else if (AInput.Memo <> nil) and (AInput.Focus <> nil) then
  begin
    Result.Text := StringReplace(AInput.Memo.Text, sLineBreak, #10, [rfReplaceAll]);
  end
  else if (AInput.Box <> nil) and (AInput.Box.Choice - AInput.BoxOffset >= 0) then
  begin
    Result.Chosen := [AInput.Box.Choice - AInput.BoxOffset];
  end;
  for mIndex := 0 to High(AInput.Checks) do
  begin
    if AInput.Checks[mIndex].Checked then
    begin
      Result.Chosen := Result.Chosen + [mIndex];
    end;
  end;
end;

procedure TAtlasNewIssueFormPanel.ShowForm(const AForm: TAtlasIssueForm; const AAnswers: TAtlasIssueFormAnswers;
  AWidth: Integer; const ANote: string);
var
  mIndex: Integer;
begin
  ClearHost;
  FForm := AForm;
  FHost := TPanel.Create(Self);
  FHost.BevelOuter := bvNone;
  FHost.Left := 0;
  FHost.Top := 0;
  FHost.Width := AWidth;
  FHost.Height := 0;
  FHost.Parent := Self;
  FHost.Anchors := [akLeft, akTop, akRight];
  if ANote <> '' then
  begin
    FNote := TMemo(AddText(AddRow(Scaled(cNoteHeight)), 0, Scaled(cNoteHeight - cGap), True));
    StyleNote(FNote);
    FNote.Text := ANote;
  end;
  SetLength(FInputs, Length(AForm.Fields));
  for mIndex := 0 to High(AForm.Fields) do
  begin
    FInputs[mIndex] := BuildField(AForm.Fields[mIndex]);
    if mIndex <= High(AAnswers) then
    begin
      SetAnswer(FInputs[mIndex], AAnswers[mIndex]);
    end;
  end;
  VertScrollBar.Position := 0;
end;

function TAtlasNewIssueFormPanel.Answers: TAtlasIssueFormAnswers;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(FInputs));
  for mIndex := 0 to High(FInputs) do
  begin
    Result[mIndex] := AnswerOf(FInputs[mIndex]);
  end;
end;

procedure TAtlasNewIssueFormPanel.FocusCaption(const ACaption: string);
var
  mIndex, mOption: Integer;
  mTarget: TWinControl;
begin
  mTarget := nil;
  for mIndex := 0 to Min(High(FInputs), High(FForm.Fields)) do
  begin
    if SameText(FForm.Fields[mIndex].Caption, ACaption) then
    begin
      mTarget := FInputs[mIndex].Focus;
    end;
    for mOption := 0 to High(FInputs[mIndex].Checks) do
    begin
      if (mTarget = nil) and SameText(FInputs[mIndex].Checks[mOption].Caption, ACaption) then
      begin
        mTarget := FInputs[mIndex].Checks[mOption];
      end;
    end;
    if mTarget <> nil then
    begin
      Break;
    end;
  end;
  if mTarget = nil then
  begin
    Exit;
  end;
  ScrollInView(mTarget);
  if mTarget.CanFocus and Showing then
  begin
    mTarget.SetFocus;
  end;
end;

{ TAtlasNewIssueFieldRows }

destructor TAtlasNewIssueFieldRows.Destroy;
begin
  FFields := nil;
  FEdits := nil;
  FBoxes := nil;
  inherited Destroy;
end;

function TAtlasNewIssueFieldRows.Scaled(AValue: Integer): Integer;
begin
  Result := ScaleValue(AValue);
end;

procedure TAtlasNewIssueFieldRows.ShowFields(const AFields: TArray<TAtlasGitHubIssueField>;
  ALabelWidth, ARowHeight: Integer);
var
  mIndex: Integer;
  mLabel: TLabel;
  mControl: TWinControl;
begin
  while ControlCount > 0 do
  begin
    Controls[0].Free;
  end;
  FFields := AFields;
  SetLength(FEdits, Length(AFields));
  SetLength(FBoxes, Length(AFields));
  Height := Length(AFields) * Scaled(ARowHeight);
  for mIndex := 0 to High(AFields) do
  begin
    FEdits[mIndex] := nil;
    FBoxes[mIndex] := nil;
    if AFields[mIndex].Kind = TAtlasIssueFieldKind.SingleSelect then
    begin
      FBoxes[mIndex] := TAtlasNewIssueBox.Create(Self);
      FBoxes[mIndex].Style := csDropDownList;
      FBoxes[mIndex].SetValues(TArray<string>.Create('') + AFields[mIndex].Options);
      mControl := FBoxes[mIndex];
    end
    else
    begin
      FEdits[mIndex] := TEdit.Create(Self);
      if AFields[mIndex].Kind = TAtlasIssueFieldKind.Date then
      begin
        FEdits[mIndex].TextHint := TAtlasNewIssueStrings.Text(TAtlasNewIssueTextId.NewIssueDateHint);
      end;
      mControl := FEdits[mIndex];
    end;
    mControl.Parent := Self;
    mControl.Left := Scaled(cGap) + Scaled(ALabelWidth);
    mControl.Top := mIndex * Scaled(ARowHeight) + Scaled(cControlTop);
    mControl.Width := ClientWidth - mControl.Left - Scaled(cGap);
    mControl.Anchors := [akLeft, akTop, akRight];
    mLabel := TLabel.Create(Self);
    mLabel.Parent := Self;
    mLabel.Left := Scaled(cGap);
    mLabel.Top := mIndex * Scaled(ARowHeight) + Scaled(cGap);
    mLabel.ShowAccelChar := False;
    mLabel.Caption := AFields[mIndex].Name + ':';
    mLabel.FocusControl := mControl;
  end;
end;

function TAtlasNewIssueFieldRows.Values: TArray<TAtlasGitHubFieldValue>;
var
  mIndex: Integer;
  mText: string;
begin
  Result := nil;
  for mIndex := 0 to High(FFields) do
  begin
    mText := '';
    if FEdits[mIndex] <> nil then
    begin
      mText := Trim(FEdits[mIndex].Text);
    end
    else if (FBoxes[mIndex] <> nil) and (FBoxes[mIndex].Choice > 0) then
    begin
      mText := FFields[mIndex].Options[FBoxes[mIndex].Choice - 1];
    end;
    if mText <> '' then
    begin
      Result := Result + [TAtlasGitHubFieldValue.Create(FFields[mIndex], mText)];
    end;
  end;
end;

function TAtlasNewIssueFieldRows.InvalidField: string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to High(FFields) do
  begin
    if (FEdits[mIndex] <> nil) and not TAtlasGitHubNewIssue.ValidValue(FFields[mIndex], FEdits[mIndex].Text) then
    begin
      Exit(FFields[mIndex].Name);
    end;
  end;
end;

end.
