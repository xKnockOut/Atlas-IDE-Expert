unit Atlas.UI.Debug.BreakpointRules;

// Abhängige Haltepunkte und Trefferbedingungen (#864), Fensterteil (nur VCL):
//   Haltepunkt-Regeln: Kunden.pas:42
//   Erst aktiv nach:  [(sofort aktiv)              ▾] [bis zum Ende ▾]
//   Anhalten:         [bei jedem Treffer           ▾] [  5]
//   Thread:           [alle Threads                ▾] [Import     ]
//   Trefferbedingung und Thread-Filter halten kurz an und setzen fort …
//                         [Übernehmen] [Regeln entfernen] [Abbrechen]
// Die Auswahlfelder füllt erst Fill (brauchen ein Fenster). Zeilen zeigt der
// Dialog ab 1.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Atlas.Core.Debug.BreakpointRules,
  Atlas.UI.Foundation.Dialog;

type
  /// <summary>Möglicher Auslöser: ein anderer Quelltext-Haltepunkt (Zeile ab 0).</summary>
  TAtlasRuleTrigger = record
    FileName: string;
    Line: Integer;
    class function Create(const AFileName: string; ALine: Integer): TAtlasRuleTrigger; static;
  end;

  TAtlasRuleTriggers = TArray<TAtlasRuleTrigger>;

  TAtlasBreakpointRuleDialog = class(TAtlasDialog)
  private
    FRule: TAtlasBreakpointRule;
    FTriggers: TAtlasRuleTriggers;
    FTrigger: TComboBox;
    FDepend: TComboBox;
    FHit: TComboBox;
    FHitCount: TEdit;
    FThread: TComboBox;
    FThreadText: TEdit;
    FFilled: Boolean;
    function AddCombo(ARow: TPanel; ALeft96, AWidth96: Integer): TComboBox;
    function AddEdit(ARow: TPanel; ALeft96: Integer): TEdit;
    procedure CreateRows;
    procedure CreateButtons;
    procedure FillTriggers;
    procedure FillChoices;
    procedure ChoiceChange(Sender: TObject);
    procedure UpdateFields;
    procedure OkClick(Sender: TObject);
    procedure ClearClick(Sender: TObject);
  protected
    procedure DoShow; override;
  public
    constructor CreateDialog(AOwner: TComponent; const ARule: TAtlasBreakpointRule;
      const ATriggers: TAtlasRuleTriggers);
    /// <summary>Auswahlfelder füllen; braucht ein Fenster (DoShow, Tests nach HandleNeeded). Einmal.</summary>
    procedure Fill;
    /// <summary>Regel aus den Feldern (Datei und Zeile wie übergeben).</summary>
    function ChosenRule: TAtlasBreakpointRule;
    class function TriggerText(const ATrigger: TAtlasRuleTrigger): string; static;
    /// <summary>Zeigt den Dialog modal; False bei Abbrechen. „Regeln entfernen“ liefert eine leere Regel.</summary>
    class function Execute(const ARule: TAtlasBreakpointRule; const ATriggers: TAtlasRuleTriggers;
      out AChosen: TAtlasBreakpointRule): Boolean; static;
    property TriggerBox: TComboBox read FTrigger;
    property DependBox: TComboBox read FDepend;
    property HitBox: TComboBox read FHit;
    property HitCountEdit: TEdit read FHitCount;
    property ThreadBox: TComboBox read FThread;
    property ThreadTextEdit: TEdit read FThreadText;
  end;

implementation

uses
  System.Math,
  Atlas.UI.Debug.Strings;

const
  cDialogWidth = 560;
  cRowHeight = 26;
  cHintHeight = 36;
  cFieldLeft = 130;
  cMainWidth = 260;
  cSideWidth = 140;
  cGap = 8;
  cModeRetry = mrRetry;

{ TAtlasRuleTrigger }

class function TAtlasRuleTrigger.Create(const AFileName: string; ALine: Integer): TAtlasRuleTrigger;
begin
  Result.FileName := AFileName;
  Result.Line := ALine;
end;

{ TAtlasBreakpointRuleDialog }

constructor TAtlasBreakpointRuleDialog.CreateDialog(AOwner: TComponent; const ARule: TAtlasBreakpointRule;
  const ATriggers: TAtlasRuleTriggers);
begin
  inherited CreateDialog(AOwner, TAtlasDebugStrings.Fmt(TAtlasDebugTextId.BreakpointRulesTitle,
    [TriggerText(TAtlasRuleTrigger.Create(ARule.FileName, ARule.Line))]), cDialogWidth);
  FRule := ARule;
  FTriggers := ATriggers;
  CreateRows;
  CreateButtons;
  FitHeight;
  ActiveControl := FTrigger;
end;

class function TAtlasBreakpointRuleDialog.TriggerText(const ATrigger: TAtlasRuleTrigger): string;
begin
  Result := Format('%s:%d', [ExtractFileName(ATrigger.FileName.Replace('/', PathDelim)), ATrigger.Line + 1]);
end;

function TAtlasBreakpointRuleDialog.AddCombo(ARow: TPanel; ALeft96, AWidth96: Integer): TComboBox;
begin
  Result := TComboBox.Create(Self);
  Result.Style := csDropDownList;
  Result.Left := ScaleValue(ALeft96);
  Result.Width := ScaleValue(AWidth96);
  Result.Parent := ARow;
  Result.OnChange := ChoiceChange;
end;

function TAtlasBreakpointRuleDialog.AddEdit(ARow: TPanel; ALeft96: Integer): TEdit;
begin
  Result := TEdit.Create(Self);
  Result.Left := ScaleValue(ALeft96);
  Result.Width := ScaleValue(cSideWidth);
  Result.Parent := ARow;
end;

procedure TAtlasBreakpointRuleDialog.CreateRows;
var
  mRow: TPanel;
  mHint: TLabel;
begin
  mRow := AddRow(cRowHeight);
  AddLabel(mRow, TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointRulesTrigger)).ShowAccelChar := False;
  FTrigger := AddCombo(mRow, cFieldLeft, cMainWidth);
  FDepend := AddCombo(mRow, cFieldLeft + cMainWidth + cGap, cSideWidth);
  mRow := AddRow(cRowHeight);
  AddLabel(mRow, TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointRulesHit)).ShowAccelChar := False;
  FHit := AddCombo(mRow, cFieldLeft, cMainWidth);
  FHitCount := AddEdit(mRow, cFieldLeft + cMainWidth + cGap);
  FHitCount.NumbersOnly := True;
  mRow := AddRow(cRowHeight);
  AddLabel(mRow, TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointRulesThread)).ShowAccelChar := False;
  FThread := AddCombo(mRow, cFieldLeft, cMainWidth);
  FThreadText := AddEdit(mRow, cFieldLeft + cMainWidth + cGap);
  mRow := AddRow(cHintHeight);
  mHint := AddLabel(mRow, TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointRulesHint));
  mHint.ShowAccelChar := False;
  // Feste Breite aus der Zeile: kein Schrumpfen auf die längste Zeile.
  mHint.AutoSize := False;
  mHint.Align := alClient;
  mHint.WordWrap := True;
end;

procedure TAtlasBreakpointRuleDialog.CreateButtons;
var
  mButtons: TAtlasButtonRow;
  mButton: TButton;
begin
  mButtons := AddButtonRow;
  mButton := mButtons.AddButton(TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointRulesOk),
    TAtlasButtonKind.Default);
  mButton.OnClick := OkClick;
  mButton := mButtons.AddButton(TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointRulesClear));
  mButton.OnClick := ClearClick;
  mButton := mButtons.AddButton(TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointRulesCancel),
    TAtlasButtonKind.Cancel);
  mButton.ModalResult := mrCancel;
end;

procedure TAtlasBreakpointRuleDialog.FillTriggers;
var
  mIndex: Integer;
begin
  FTrigger.Items.BeginUpdate;
  try
    FTrigger.Items.Add(TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointRulesNoTrigger));
    for mIndex := 0 to High(FTriggers) do
    begin
      FTrigger.Items.Add(TriggerText(FTriggers[mIndex]));
      if FRule.TriggeredBy(FTriggers[mIndex].FileName, FTriggers[mIndex].Line) then
      begin
        FTrigger.ItemIndex := mIndex + 1;
      end;
    end;
  finally
    FTrigger.Items.EndUpdate;
  end;
  FTrigger.ItemIndex := Max(0, FTrigger.ItemIndex);
end;

procedure AddTexts(ABox: TComboBox; const AIds: array of TAtlasDebugTextId; AIndex: Integer);
var
  mId: TAtlasDebugTextId;
begin
  ABox.Items.BeginUpdate;
  try
    for mId in AIds do
    begin
      ABox.Items.Add(TAtlasDebugStrings.Text(mId));
    end;
  finally
    ABox.Items.EndUpdate;
  end;
  ABox.ItemIndex := AIndex;
end;

procedure TAtlasBreakpointRuleDialog.FillChoices;
begin
  // Reihenfolge wie die Aufzählungen; „Erst aktiv nach“ ohne None.
  AddTexts(FDepend, [TAtlasDebugTextId.BreakpointRulesUntilEnd, TAtlasDebugTextId.BreakpointRulesOnce],
    Ord(FRule.Depend = TAtlasDependMode.Once));
  AddTexts(FHit, [TAtlasDebugTextId.BreakpointRulesHitAny, TAtlasDebugTextId.BreakpointRulesHitExactly,
    TAtlasDebugTextId.BreakpointRulesHitAtLeast, TAtlasDebugTextId.BreakpointRulesHitEvery], Ord(FRule.Hit));
  AddTexts(FThread, [TAtlasDebugTextId.BreakpointRulesThreadAny, TAtlasDebugTextId.BreakpointRulesThreadName,
    TAtlasDebugTextId.BreakpointRulesThreadId, TAtlasDebugTextId.BreakpointRulesThreadMain], Ord(FRule.Thread));
end;

procedure TAtlasBreakpointRuleDialog.Fill;
begin
  if FFilled then
  begin
    Exit;
  end;
  FFilled := True;
  FillTriggers;
  FillChoices;
  FHitCount.Text := IntToStr(Max(1, FRule.HitCount));
  if FRule.Thread = TAtlasThreadFilter.ThreadId then
  begin
    FThreadText.Text := IntToStr(FRule.ThreadId);
  end
  else
  begin
    FThreadText.Text := FRule.ThreadText;
  end;
  UpdateFields;
end;

procedure TAtlasBreakpointRuleDialog.DoShow;
begin
  inherited;
  Fill;
end;

procedure TAtlasBreakpointRuleDialog.UpdateFields;
begin
  FDepend.Enabled := FTrigger.ItemIndex > 0;
  FHitCount.Enabled := FHit.ItemIndex > Ord(TAtlasHitMode.Any);
  FThreadText.Enabled := FThread.ItemIndex in [Ord(TAtlasThreadFilter.NameContains),
    Ord(TAtlasThreadFilter.ThreadId)];
end;

procedure TAtlasBreakpointRuleDialog.ChoiceChange(Sender: TObject);
begin
  UpdateFields;
end;

function TAtlasBreakpointRuleDialog.ChosenRule: TAtlasBreakpointRule;
var
  mTrigger: Integer;
begin
  Result := FRule;
  Result.Hit := TAtlasHitMode(EnsureRange(FHit.ItemIndex, 0, Ord(High(TAtlasHitMode))));
  Result.HitCount := Max(1, StrToIntDef(FHitCount.Text, 1));
  Result.Thread := TAtlasThreadFilter(EnsureRange(FThread.ItemIndex, 0, Ord(High(TAtlasThreadFilter))));
  Result.ThreadText := '';
  Result.ThreadId := 0;
  if Result.Thread = TAtlasThreadFilter.NameContains then
  begin
    Result.ThreadText := Trim(FThreadText.Text);
  end
  else if Result.Thread = TAtlasThreadFilter.ThreadId then
  begin
    Result.ThreadId := Cardinal(Max(0, StrToIntDef(Trim(FThreadText.Text), 0)));
  end;
  mTrigger := FTrigger.ItemIndex - 1;
  Result.Depend := TAtlasDependMode.None;
  Result.TriggerFile := '';
  Result.TriggerLine := 0;
  if (mTrigger >= 0) and (mTrigger <= High(FTriggers)) then
  begin
    Result.TriggerFile := FTriggers[mTrigger].FileName;
    Result.TriggerLine := FTriggers[mTrigger].Line;
    Result.Depend := TAtlasDependMode.UntilEnd;
    if FDepend.ItemIndex = 1 then
    begin
      Result.Depend := TAtlasDependMode.Once;
    end;
  end;
end;

procedure TAtlasBreakpointRuleDialog.OkClick(Sender: TObject);
begin
  ModalResult := mrOk;
end;

procedure TAtlasBreakpointRuleDialog.ClearClick(Sender: TObject);
begin
  ModalResult := cModeRetry;
end;

class function TAtlasBreakpointRuleDialog.Execute(const ARule: TAtlasBreakpointRule;
  const ATriggers: TAtlasRuleTriggers; out AChosen: TAtlasBreakpointRule): Boolean;
var
  mDialog: TAtlasBreakpointRuleDialog;
  mResult: Integer;
begin
  AChosen := ARule;
  mDialog := TAtlasBreakpointRuleDialog.CreateDialog(nil, ARule, ATriggers);
  try
    mResult := mDialog.ShowModal;
    Result := mResult in [mrOk, cModeRetry];
    if mResult = mrOk then
    begin
      AChosen := mDialog.ChosenRule;
    end
    else if mResult = cModeRetry then
    begin
      // Regeln entfernen: nur Datei und Zeile bleiben.
      AChosen := Default(TAtlasBreakpointRule);
      AChosen.FileName := ARule.FileName;
      AChosen.Line := ARule.Line;
    end;
  finally
    mDialog.Free;
  end;
end;

end.
