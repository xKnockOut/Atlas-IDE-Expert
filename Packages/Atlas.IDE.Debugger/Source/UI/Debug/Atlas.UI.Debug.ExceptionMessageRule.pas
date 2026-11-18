unit Atlas.UI.Debug.ExceptionMessageRule;

// Exception-Regel nach Meldungstext anlegen (#2549), reine VCL:
//   Klasse:  EKonfigFehler
//   [Nur bei Meldungen wie dieser anhalten ▾]
//   Muster:  [Schlüssel unbekannt: *          ] [ ] regulärer Ausdruck
//   Unit:    [beliebig                        ▾]
//   * steht für beliebigen Text …  bzw. der Fehler im Ausdruck
//                                          [Anlegen] [Abbrechen]
// Das Muster ist aus der Meldung vorbelegt (TAtlasExceptionRules.
// SuggestPattern). „Anlegen“ geht nur mit gültigem Muster. „Nur bei Meldungen
// wie dieser anhalten“ wird eine Regel „Meldung passt nicht → fortsetzen“,
// „Meldungen wie diese ignorieren“ eine Regel „Meldung passt → fortsetzen“;
// beide zählen den Halt im Verlauf (Aktion Log). Die Unit schränkt den Ort ein
// (erster eigener Rahmen). Aufgebaut im Code (keine DFM).

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
  {$SCOPEDENUMS ON}
  TAtlasMessageRuleMode = (StopOnly, Ignore);
  {$SCOPEDENUMS OFF}

  /// <summary>Vorgaben des Dialogs aus der Exception.</summary>
  TAtlasMessageRuleInput = record
    ExceptionClass: string;
    Message: string;
    /// <summary>Unit des ersten eigenen Rahmens; '' ohne.</summary>
    UnitName: string;
    Mode: TAtlasMessageRuleMode;
    class function Create(const AClass, AMessage, AUnitName: string;
      AMode: TAtlasMessageRuleMode): TAtlasMessageRuleInput; static;
  end;

  TAtlasExceptionMessageRuleDialog = class(TAtlasDialog)
  private
    FInput: TAtlasMessageRuleInput;
    FMode: TComboBox;
    FPattern: TEdit;
    FRegex: TCheckBox;
    FUnit: TComboBox;
    FNote: TAtlasNoteLabel;
    FCreate: TButton;
    FFilled: Boolean;
    function AddField(const ACaption: string): TPanel;
    procedure InputChange(Sender: TObject);
    procedure CreateClick(Sender: TObject);
  protected
    procedure DoShow; override;
  public
    constructor CreateFor(AOwner: TComponent; const AInput: TAtlasMessageRuleInput);
    /// <summary>Auswahlfelder füllen; braucht ein Fenster (DoShow, Tests nach HandleNeeded). Einmal.</summary>
    procedure Fill;
    /// <summary>Regel aus den Feldern; False bei leerem oder ungültigem Muster.</summary>
    function TryRule(out ARule: TAtlasExceptionRule): Boolean;
    /// <summary>Regel zu Modus, Muster und Unit (ohne Prüfung des Musters).</summary>
    class function RuleOf(const AClass, APattern: string; ARegex: Boolean; AMode: TAtlasMessageRuleMode;
      const AUnitName: string): TAtlasExceptionRule; static;
    /// <summary>Modal zeigen; True mit der angelegten Regel.</summary>
    class function Execute(const AInput: TAtlasMessageRuleInput; out ARule: TAtlasExceptionRule): Boolean; static;
    property ModeBox: TComboBox read FMode;
    property PatternEdit: TEdit read FPattern;
    property RegexBox: TCheckBox read FRegex;
    property UnitBox: TComboBox read FUnit;
    property Note: TAtlasNoteLabel read FNote;
    property CreateButton: TButton read FCreate;
  end;

implementation

uses
  Atlas.Core.Style.Signal,
  Atlas.UI.Debug.Exceptions.Strings;

const
  cWidth = 520;
  cRowHeight = 26;
  cLabelWidth = 80;
  cFieldWidth = 300;
  cGap = 8;
  cNoteHeight = 36;

{ TAtlasMessageRuleInput }

class function TAtlasMessageRuleInput.Create(const AClass, AMessage, AUnitName: string;
  AMode: TAtlasMessageRuleMode): TAtlasMessageRuleInput;
begin
  Result.ExceptionClass := AClass;
  Result.Message := AMessage;
  Result.UnitName := AUnitName;
  Result.Mode := AMode;
end;

function TitleOf(AMode: TAtlasMessageRuleMode): string;
begin
  if AMode = TAtlasMessageRuleMode.StopOnly then
  begin
    Result := TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugMessageRuleTitleStopOnly);
  end
  else
  begin
    Result := TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugMessageRuleTitleIgnore);
  end;
end;

{ TAtlasExceptionMessageRuleDialog }

constructor TAtlasExceptionMessageRuleDialog.CreateFor(AOwner: TComponent; const AInput: TAtlasMessageRuleInput);
var
  mRow: TPanel;
  mButtons: TAtlasButtonRow;
begin
  inherited CreateDialog(AOwner, TitleOf(AInput.Mode), cWidth);
  FInput := AInput;
  mRow := AddField(TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugMessageRuleClass));
  AddLabel(mRow, AInput.ExceptionClass).Left := ScaleValue(cLabelWidth);
  mRow := AddRow(cRowHeight);
  FMode := TComboBox.Create(Self);
  FMode.Style := csDropDownList;
  FMode.Left := ScaleValue(cLabelWidth);
  FMode.Width := ScaleValue(cFieldWidth);
  FMode.Parent := mRow;
  mRow := AddField(TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugMessageRulePattern));
  FPattern := TEdit.Create(Self);
  FPattern.Left := ScaleValue(cLabelWidth);
  FPattern.Width := ScaleValue(cFieldWidth);
  FPattern.Parent := mRow;
  FPattern.Text := TAtlasExceptionRules.SuggestPattern(AInput.Message);
  FPattern.OnChange := InputChange;
  FRegex := TCheckBox.Create(Self);
  FRegex.Left := ScaleValue(cLabelWidth + cFieldWidth + cGap);
  FRegex.Width := ScaleValue(cWidth - cLabelWidth - cFieldWidth - 2 * cGap);
  FRegex.Caption := TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugMessageRuleRegex);
  FRegex.Parent := mRow;
  FRegex.OnClick := InputChange;
  mRow := AddField(TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugMessageRuleUnit));
  FUnit := TComboBox.Create(Self);
  FUnit.Style := csDropDownList;
  FUnit.Left := ScaleValue(cLabelWidth);
  FUnit.Width := ScaleValue(cFieldWidth);
  FUnit.Parent := mRow;
  FNote := AddNote(cNoteHeight);
  mButtons := AddButtonRow;
  FCreate := mButtons.AddButton(TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugMessageRuleCreate),
    TAtlasButtonKind.Default);
  FCreate.ModalResult := mrNone;
  FCreate.OnClick := CreateClick;
  mButtons.AddButton(TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugMessageRuleCancel),
    TAtlasButtonKind.Cancel);
  FitHeight;
  ActiveControl := FPattern;
  InputChange(nil);
end;

procedure TAtlasExceptionMessageRuleDialog.DoShow;
begin
  inherited;
  Fill;
end;

function TAtlasExceptionMessageRuleDialog.AddField(const ACaption: string): TPanel;
begin
  Result := AddRow(cRowHeight);
  AddLabel(Result, ACaption).ShowAccelChar := False;
end;

procedure TAtlasExceptionMessageRuleDialog.Fill;
begin
  if FFilled then
  begin
    Exit;
  end;
  FFilled := True;
  // Reihenfolge wie TAtlasMessageRuleMode.
  FMode.Items.Add(TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugMessageRuleModeStopOnly));
  FMode.Items.Add(TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugMessageRuleModeIgnore));
  FMode.ItemIndex := Ord(FInput.Mode);
  FUnit.Items.Add(TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugMessageRuleAnyUnit));
  if FInput.UnitName <> '' then
  begin
    FUnit.Items.Add(FInput.UnitName);
  end;
  FUnit.ItemIndex := 0;
end;

procedure TAtlasExceptionMessageRuleDialog.InputChange(Sender: TObject);
var
  mError: string;
begin
  if TAtlasExceptionRules.ValidPattern(FPattern.Text, FRegex.Checked, mError) then
  begin
    FNote.ShowNote(TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugMessageRuleHint), TAtlasSignalKind.Info);
    FCreate.Enabled := True;
    Exit;
  end;
  FCreate.Enabled := False;
  if mError = '' then
  begin
    FNote.ShowNote(TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugMessageRuleEmpty),
      TAtlasSignalKind.Error);
  end
  else
  begin
    FNote.ShowNote(TAtlasExceptionsStrings.Fmt(TAtlasExceptionsTextId.DebugMessageRuleInvalid, [mError]),
      TAtlasSignalKind.Error);
  end;
end;

procedure TAtlasExceptionMessageRuleDialog.CreateClick(Sender: TObject);
begin
  if FCreate.Enabled then
  begin
    ModalResult := mrOk;
  end;
end;

class function TAtlasExceptionMessageRuleDialog.RuleOf(const AClass, APattern: string; ARegex: Boolean;
  AMode: TAtlasMessageRuleMode; const AUnitName: string): TAtlasExceptionRule;
begin
  if AMode = TAtlasMessageRuleMode.StopOnly then
  begin
    Result := TAtlasExceptionRule.Create(AClass, APattern, TAtlasMessageMatch.NotMatches, TAtlasExceptionAction.Log);
  end
  else
  begin
    Result := TAtlasExceptionRule.Create(AClass, APattern, TAtlasMessageMatch.Matches, TAtlasExceptionAction.Log);
  end;
  Result.Regex := ARegex;
  Result.Location := AUnitName;
end;

function TAtlasExceptionMessageRuleDialog.TryRule(out ARule: TAtlasExceptionRule): Boolean;
var
  mError, mUnit: string;
  mMode: TAtlasMessageRuleMode;
begin
  Result := TAtlasExceptionRules.ValidPattern(FPattern.Text, FRegex.Checked, mError);
  mMode := FInput.Mode;
  if FMode.ItemIndex = Ord(TAtlasMessageRuleMode.Ignore) then
  begin
    mMode := TAtlasMessageRuleMode.Ignore;
  end
  else if FMode.ItemIndex = Ord(TAtlasMessageRuleMode.StopOnly) then
  begin
    mMode := TAtlasMessageRuleMode.StopOnly;
  end;
  mUnit := '';
  if FUnit.ItemIndex > 0 then
  begin
    mUnit := FInput.UnitName;
  end;
  ARule := RuleOf(FInput.ExceptionClass, Trim(FPattern.Text), FRegex.Checked, mMode, mUnit);
end;

class function TAtlasExceptionMessageRuleDialog.Execute(const AInput: TAtlasMessageRuleInput;
  out ARule: TAtlasExceptionRule): Boolean;
var
  mDialog: TAtlasExceptionMessageRuleDialog;
begin
  ARule := Default(TAtlasExceptionRule);
  mDialog := TAtlasExceptionMessageRuleDialog.CreateFor(nil, AInput);
  try
    Result := (mDialog.ShowModal = mrOk) and mDialog.TryRule(ARule);
  finally
    mDialog.Free;
  end;
end;

end.
