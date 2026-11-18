unit Atlas.UI.Debug.ExceptionRuleEdit;

// Eine Exception-Regel anlegen oder bearbeiten (#838), reine VCL:
//   Klasse:   [EConvertError                    ]
//   Ort:      [Bericht.Druck.*                  ]
//             Unit, Klasse oder Unit.Klasse.Methode; * als Platzhalter; leer = überall
//   Meldung:  [                                 ] [ ] regulärer Ausdruck
//             [Meldung passt ▾]
//   Aktion:   [Weiterlaufen ▾]                    [x] eingeschaltet
//                                           [Übernehmen] [Abbrechen]
// „Übernehmen“ geht nur mit Klasse und gültigem Muster. Die Herkunft der Regel
// bleibt, wie sie war. Aufgebaut im Code (keine DFM).

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Atlas.Core.Debug.ExceptionRules,
  Atlas.UI.Foundation.Dialog;

type
  TAtlasExceptionRuleEditDialog = class(TAtlasDialog)
  private
    FRule: TAtlasExceptionRule;
    FClass: TEdit;
    FPlace: TEdit;
    FMessage: TEdit;
    FRegex: TCheckBox;
    FMatch: TComboBox;
    FAction: TComboBox;
    FEnabled: TCheckBox;
    FNote: TAtlasNoteLabel;
    FSave: TButton;
    FFilled: Boolean;
    function AddField(const ACaption: string): TPanel;
    function AddEdit(ARow: TPanel; const AText: string): TEdit;
    function AddCombo(ARow: TPanel): TComboBox;
    procedure CreateMessageRows;
    procedure InputChange(Sender: TObject);
    procedure SaveClick(Sender: TObject);
  protected
    procedure DoShow; override;
  public
    /// <summary>ANew: Titel „anlegen“ statt „bearbeiten“.</summary>
    constructor CreateFor(AOwner: TComponent; const ARule: TAtlasExceptionRule; ANew: Boolean);
    /// <summary>Auswahlfelder füllen; braucht ein Fenster (DoShow, Tests nach HandleNeeded). Einmal.</summary>
    procedure Fill;
    /// <summary>Regel aus den Feldern; False ohne Klasse oder mit ungültigem Muster.</summary>
    function TryRule(out ARule: TAtlasExceptionRule): Boolean;
    /// <summary>Dialog zeigen; True mit ARule nach „Übernehmen“.</summary>
    class function Execute(var ARule: TAtlasExceptionRule; ANew: Boolean): Boolean; static;
    /// <summary>Text der Aktion für Listen und Auswahl.</summary>
    class function ActionText(AAction: TAtlasExceptionAction): string; static;
    property ClassEdit: TEdit read FClass;
    property PlaceEdit: TEdit read FPlace;
    property MessageEdit: TEdit read FMessage;
    property RegexBox: TCheckBox read FRegex;
    property MatchBox: TComboBox read FMatch;
    property ActionBox: TComboBox read FAction;
    property EnabledBox: TCheckBox read FEnabled;
    property Note: TAtlasNoteLabel read FNote;
    property SaveButton: TButton read FSave;
  end;

implementation

uses
  Atlas.Core.Style.Signal,
  Atlas.UI.Debug.Exceptions.Strings;

const
  cWidth = 560;
  cRowHeight = 26;
  cLabelWidth = 80;
  cFieldWidth = 300;
  cHintHeight = 20;
  cGap = 8;
  cNoteHeight = 36;

function TitleOf(ANew: Boolean): string;
begin
  if ANew then
  begin
    Result := TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugRuleTitleNew);
  end
  else
  begin
    Result := TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugRuleTitleEdit);
  end;
end;

{ TAtlasExceptionRuleEditDialog }

constructor TAtlasExceptionRuleEditDialog.CreateFor(AOwner: TComponent; const ARule: TAtlasExceptionRule;
  ANew: Boolean);
var
  mRow: TPanel;
  mButtons: TAtlasButtonRow;
begin
  inherited CreateDialog(AOwner, TitleOf(ANew), cWidth);
  FRule := ARule;
  FClass := AddEdit(AddField(TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugMessageRuleClass)),
    ARule.ExceptionClass);
  FPlace := AddEdit(AddField(TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugRulePlace)), ARule.Location);
  mRow := AddRow(cHintHeight);
  AddLabel(mRow, TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugRulePlaceHint)).Left :=
    ScaleValue(cLabelWidth);
  CreateMessageRows;
  mRow := AddField(TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugRuleAction));
  FAction := AddCombo(mRow);
  FEnabled := TCheckBox.Create(Self);
  FEnabled.Left := ScaleValue(cLabelWidth + cFieldWidth + cGap);
  FEnabled.Width := ScaleValue(cWidth - cLabelWidth - cFieldWidth - 2 * cGap);
  FEnabled.Caption := TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugRuleEnabled);
  FEnabled.Parent := mRow;
  FEnabled.Checked := ARule.Enabled;
  FNote := AddNote(cNoteHeight);
  mButtons := AddButtonRow;
  FSave := mButtons.AddButton(TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugRulesSave),
    TAtlasButtonKind.Default);
  FSave.ModalResult := mrNone;
  FSave.OnClick := SaveClick;
  mButtons.AddButton(TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugRulesCancel), TAtlasButtonKind.Cancel);
  FitHeight;
  ActiveControl := FClass;
  InputChange(nil);
end;

procedure TAtlasExceptionRuleEditDialog.CreateMessageRows;
var
  mRow: TPanel;
begin
  mRow := AddField(TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugRuleMessage));
  FMessage := AddEdit(mRow, FRule.Message);
  FMessage.TextHint := TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugRuleMessageHint);
  FRegex := TCheckBox.Create(Self);
  FRegex.Left := ScaleValue(cLabelWidth + cFieldWidth + cGap);
  FRegex.Width := ScaleValue(cWidth - cLabelWidth - cFieldWidth - 2 * cGap);
  FRegex.Caption := TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugMessageRuleRegex);
  FRegex.Parent := mRow;
  FRegex.Checked := FRule.Regex;
  FRegex.OnClick := InputChange;
  FMatch := AddCombo(AddRow(cRowHeight));
end;

procedure TAtlasExceptionRuleEditDialog.DoShow;
begin
  inherited;
  Fill;
end;

function TAtlasExceptionRuleEditDialog.AddField(const ACaption: string): TPanel;
begin
  Result := AddRow(cRowHeight);
  AddLabel(Result, ACaption).ShowAccelChar := False;
end;

function TAtlasExceptionRuleEditDialog.AddEdit(ARow: TPanel; const AText: string): TEdit;
begin
  Result := TEdit.Create(Self);
  Result.Left := ScaleValue(cLabelWidth);
  Result.Width := ScaleValue(cFieldWidth);
  Result.Parent := ARow;
  Result.Text := AText;
  Result.OnChange := InputChange;
end;

function TAtlasExceptionRuleEditDialog.AddCombo(ARow: TPanel): TComboBox;
begin
  Result := TComboBox.Create(Self);
  Result.Style := csDropDownList;
  Result.Left := ScaleValue(cLabelWidth);
  Result.Width := ScaleValue(cFieldWidth);
  Result.Parent := ARow;
end;

procedure TAtlasExceptionRuleEditDialog.Fill;
var
  mAction: TAtlasExceptionAction;
begin
  if FFilled then
  begin
    Exit;
  end;
  FFilled := True;
  // Reihenfolge wie TAtlasMessageMatch bzw. TAtlasExceptionAction.
  FMatch.Items.Add(TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugRuleMatchContains));
  FMatch.Items.Add(TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugRuleMatchNot));
  FMatch.ItemIndex := Ord(FRule.MessageMatch);
  FAction.Items.BeginUpdate;
  try
    for mAction := Low(TAtlasExceptionAction) to High(TAtlasExceptionAction) do
    begin
      FAction.Items.Add(ActionText(mAction));
    end;
  finally
    FAction.Items.EndUpdate;
  end;
  FAction.ItemIndex := Ord(FRule.Action);
end;

class function TAtlasExceptionRuleEditDialog.ActionText(AAction: TAtlasExceptionAction): string;
begin
  case AAction of
    TAtlasExceptionAction.Stop:
      Result := TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugRulesActionStop);
    TAtlasExceptionAction.Log:
      Result := TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugRulesActionLog);
  else
    Result := TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugRulesActionContinue);
  end;
end;

procedure TAtlasExceptionRuleEditDialog.InputChange(Sender: TObject);
var
  mError: string;
  mValid: Boolean;
begin
  mError := '';
  mValid := (Trim(FMessage.Text) = '') or TAtlasExceptionRules.ValidPattern(FMessage.Text, FRegex.Checked, mError);
  FSave.Enabled := (Trim(FClass.Text) <> '') and mValid;
  if Trim(FClass.Text) = '' then
  begin
    FNote.ShowNote(TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugRuleNoClass), TAtlasSignalKind.Error);
  end
  else if not mValid then
  begin
    FNote.ShowNote(TAtlasExceptionsStrings.Fmt(TAtlasExceptionsTextId.DebugMessageRuleInvalid, [mError]),
      TAtlasSignalKind.Error);
  end
  else
  begin
    FNote.ShowNote(TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugMessageRuleHint), TAtlasSignalKind.Info);
  end;
end;

procedure TAtlasExceptionRuleEditDialog.SaveClick(Sender: TObject);
begin
  if FSave.Enabled then
  begin
    ModalResult := mrOk;
  end;
end;

function TAtlasExceptionRuleEditDialog.TryRule(out ARule: TAtlasExceptionRule): Boolean;
var
  mError: string;
begin
  ARule := FRule;
  ARule.ExceptionClass := Trim(FClass.Text);
  ARule.Location := Trim(FPlace.Text);
  ARule.Message := Trim(FMessage.Text);
  ARule.Regex := FRegex.Checked and (ARule.Message <> '');
  ARule.MessageMatch := TAtlasMessageMatch.Matches;
  if FMatch.ItemIndex = Ord(TAtlasMessageMatch.NotMatches) then
  begin
    ARule.MessageMatch := TAtlasMessageMatch.NotMatches;
  end;
  // Die Auswahl hat genau die Aktionen in ihrer Reihenfolge.
  if FAction.ItemIndex >= 0 then
  begin
    ARule.Action := TAtlasExceptionAction(FAction.ItemIndex);
  end;
  ARule.Enabled := FEnabled.Checked;
  Result := (ARule.ExceptionClass <> '') and
    ((ARule.Message = '') or TAtlasExceptionRules.ValidPattern(ARule.Message, ARule.Regex, mError));
end;

class function TAtlasExceptionRuleEditDialog.Execute(var ARule: TAtlasExceptionRule; ANew: Boolean): Boolean;
var
  mDialog: TAtlasExceptionRuleEditDialog;
  mRule: TAtlasExceptionRule;
begin
  mDialog := TAtlasExceptionRuleEditDialog.CreateFor(nil, ARule, ANew);
  try
    Result := (mDialog.ShowModal = mrOk) and mDialog.TryRule(mRule);
    if Result then
    begin
      ARule := mRule;
    end;
  finally
    mDialog.Free;
  end;
end;

end.
