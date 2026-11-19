unit Atlas.UI.Debug.BreakpointRules;

// Abhängige Haltepunkte und Trefferbedingungen (#864), Fensterteil (nur VCL):
//   Haltepunkt-Regeln: Kunden.pas:42
//   Erst aktiv nach:  [(sofort aktiv)              ▾] [bis zum Ende ▾]
//   Anhalten:         [bei jedem Treffer           ▾] [  5]
//   Thread:           [alle Threads                ▾] [Import     ]
//   Nur im Stapel:    [TKundenImport.LeseZeile     ▾]
//                     [ ] nur direkter Aufrufer
//   Trefferbedingung und Thread-Filter halten kurz an und setzen fort …
//                         [Übernehmen] [Regeln entfernen] [Abbrechen]
// Die Auswahlfelder füllt erst Fill (brauchen ein Fenster). Zeilen zeigt der
// Dialog ab 1. Das Feld für den Aufrufer (#2548) nimmt ein Muster nach
// TAtlasRoutinePattern; die Liste schlägt die Routinen des aktuellen
// Aufrufstapels vor, wenn das Programm angehalten ist.

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
    FCallers: TArray<string>;
    FCaller: TComboBox;
    FCallerDirect: TCheckBox;
    FFilled: Boolean;
    function AddCombo(ARow: TPanel; ALeft96, AWidth96: Integer): TComboBox;
    function AddEdit(ARow: TPanel; ALeft96: Integer): TEdit;
    procedure CreateRows;
    procedure CreateCallerRows;
    procedure FillCallers;
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
    /// <summary>ACallers: Vorschläge für den Aufrufer (Routinen des aktuellen Stapels), auch leer.</summary>
    constructor CreateDialog(AOwner: TComponent; const ARule: TAtlasBreakpointRule;
      const ATriggers: TAtlasRuleTriggers; const ACallers: TArray<string>);
    /// <summary>Auswahlfelder füllen; braucht ein Fenster (DoShow, Tests nach HandleNeeded). Einmal.</summary>
    procedure Fill;
    /// <summary>Regel aus den Feldern (Datei und Zeile wie übergeben).</summary>
    function ChosenRule: TAtlasBreakpointRule;
    class function TriggerText(const ATrigger: TAtlasRuleTrigger): string; static;
    /// <summary>Zeigt den Dialog modal; False bei Abbrechen. „Regeln entfernen“ liefert eine leere Regel.</summary>
    class function Execute(const ARule: TAtlasBreakpointRule; const ATriggers: TAtlasRuleTriggers;
      const ACallers: TArray<string>; out AChosen: TAtlasBreakpointRule): Boolean; static;
    property TriggerBox: TComboBox read FTrigger;
    property DependBox: TComboBox read FDepend;
    property HitBox: TComboBox read FHit;
    property HitCountEdit: TEdit read FHitCount;
    property ThreadBox: TComboBox read FThread;
    property ThreadTextEdit: TEdit read FThreadText;
    property CallerBox: TComboBox read FCaller;
    property CallerDirectBox: TCheckBox read FCallerDirect;
  end;

implementation

uses
  System.Math,
  Atlas.UI.Debug.Breakpoints.Strings;

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
  const ATriggers: TAtlasRuleTriggers; const ACallers: TArray<string>);
begin
  inherited CreateDialog(AOwner, TAtlasBreakpointsStrings.Fmt(TAtlasBreakpointsTextId.BreakpointRulesTitle,
    [TriggerText(TAtlasRuleTrigger.Create(ARule.FileName, ARule.Line))]), cDialogWidth);
  FRule := ARule;
  FTriggers := ATriggers;
  FCallers := ACallers;
  CreateRows;
  CreateButtons;
  FitHeight;
  ActiveControl := FTrigger;
end;

procedure TAtlasBreakpointRuleDialog.DoShow;
begin
  inherited;
  Fill;
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
  AddLabel(mRow, TAtlasBreakpointsStrings.Text(TAtlasBreakpointsTextId.BreakpointRulesTrigger)).ShowAccelChar := False;
  FTrigger := AddCombo(mRow, cFieldLeft, cMainWidth);
  FDepend := AddCombo(mRow, cFieldLeft + cMainWidth + cGap, cSideWidth);
  mRow := AddRow(cRowHeight);
  AddLabel(mRow, TAtlasBreakpointsStrings.Text(TAtlasBreakpointsTextId.BreakpointRulesHit)).ShowAccelChar := False;
  FHit := AddCombo(mRow, cFieldLeft, cMainWidth);
  FHitCount := AddEdit(mRow, cFieldLeft + cMainWidth + cGap);
  FHitCount.NumbersOnly := True;
  mRow := AddRow(cRowHeight);
  AddLabel(mRow, TAtlasBreakpointsStrings.Text(TAtlasBreakpointsTextId.BreakpointRulesThread)).ShowAccelChar := False;
  FThread := AddCombo(mRow, cFieldLeft, cMainWidth);
  FThreadText := AddEdit(mRow, cFieldLeft + cMainWidth + cGap);
  CreateCallerRows;
  mRow := AddRow(cHintHeight);
  mHint := AddLabel(mRow, TAtlasBreakpointsStrings.Text(TAtlasBreakpointsTextId.BreakpointRulesHint));
  mHint.ShowAccelChar := False;
  // Feste Breite aus der Zeile: kein Schrumpfen auf die längste Zeile.
  mHint.AutoSize := False;
  mHint.Align := alClient;
  mHint.WordWrap := True; // window-ok: feste Größe (AutoSize aus, alClient)
end;

procedure TAtlasBreakpointRuleDialog.CreateCallerRows;
var
  mRow: TPanel;
begin
  mRow := AddRow(cRowHeight);
  AddLabel(mRow, TAtlasBreakpointsStrings.Text(TAtlasBreakpointsTextId.BreakpointRulesCaller)).ShowAccelChar := False;
  FCaller := AddCombo(mRow, cFieldLeft, cMainWidth + cGap + cSideWidth);
  // Freie Eingabe eines Musters; die Liste macht nur Vorschläge.
  FCaller.Style := csDropDown;
  FCaller.TextHint := TAtlasBreakpointsStrings.Text(TAtlasBreakpointsTextId.BreakpointRulesCallerHint);
  mRow := AddRow(cRowHeight);
  FCallerDirect := TCheckBox.Create(Self);
  FCallerDirect.Left := ScaleValue(cFieldLeft);
  FCallerDirect.Width := ScaleValue(cMainWidth);
  FCallerDirect.Caption := TAtlasBreakpointsStrings.Text(TAtlasBreakpointsTextId.BreakpointRulesCallerDirect);
  FCallerDirect.Parent := mRow;
end;

procedure TAtlasBreakpointRuleDialog.CreateButtons;
var
  mButtons: TAtlasButtonRow;
  mButton: TButton;
begin
  mButtons := AddButtonRow;
  mButton := mButtons.AddButton(TAtlasBreakpointsStrings.Text(TAtlasBreakpointsTextId.BreakpointRulesOk),
    TAtlasButtonKind.Default);
  mButton.OnClick := OkClick;
  mButton := mButtons.AddButton(TAtlasBreakpointsStrings.Text(TAtlasBreakpointsTextId.BreakpointRulesClear));
  mButton.OnClick := ClearClick;
  mButton := mButtons.AddButton(TAtlasBreakpointsStrings.Text(TAtlasBreakpointsTextId.BreakpointRulesCancel),
    TAtlasButtonKind.Cancel);
  mButton.ModalResult := mrCancel;
end;

procedure TAtlasBreakpointRuleDialog.FillTriggers;
var
  mIndex: Integer;
begin
  FTrigger.Items.BeginUpdate;
  try
    FTrigger.Items.Add(TAtlasBreakpointsStrings.Text(TAtlasBreakpointsTextId.BreakpointRulesNoTrigger));
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

procedure AddTexts(ABox: TComboBox; const AIds: array of TAtlasBreakpointsTextId; AIndex: Integer);
var
  mId: TAtlasBreakpointsTextId;
begin
  ABox.Items.BeginUpdate;
  try
    for mId in AIds do
    begin
      ABox.Items.Add(TAtlasBreakpointsStrings.Text(mId));
    end;
  finally
    ABox.Items.EndUpdate;
  end;
  ABox.ItemIndex := AIndex;
end;

procedure TAtlasBreakpointRuleDialog.FillChoices;
begin
  // Reihenfolge wie die Aufzählungen; „Erst aktiv nach“ ohne None.
  AddTexts(FDepend, [TAtlasBreakpointsTextId.BreakpointRulesUntilEnd, TAtlasBreakpointsTextId.BreakpointRulesOnce],
    Ord(FRule.Depend = TAtlasDependMode.Once));
  AddTexts(FHit, [TAtlasBreakpointsTextId.BreakpointRulesHitAny, TAtlasBreakpointsTextId.BreakpointRulesHitExactly,
    TAtlasBreakpointsTextId.BreakpointRulesHitAtLeast, TAtlasBreakpointsTextId.BreakpointRulesHitEvery],
      Ord(FRule.Hit));
  AddTexts(FThread, [TAtlasBreakpointsTextId.BreakpointRulesThreadAny,
    TAtlasBreakpointsTextId.BreakpointRulesThreadName,
    TAtlasBreakpointsTextId.BreakpointRulesThreadId, TAtlasBreakpointsTextId.BreakpointRulesThreadMain],
      Ord(FRule.Thread));
end;

procedure TAtlasBreakpointRuleDialog.FillCallers;
var
  mCaller: string;
begin
  FCaller.Items.BeginUpdate;
  try
    for mCaller in FCallers do
    begin
      if (mCaller <> '') and (FCaller.Items.IndexOf(mCaller) < 0) then
      begin
        FCaller.Items.Add(mCaller);
      end;
    end;
  finally
    FCaller.Items.EndUpdate;
  end;
  FCaller.Text := FRule.Caller;
  FCallerDirect.Checked := FRule.CallerDirect;
end;

procedure TAtlasBreakpointRuleDialog.ChoiceChange(Sender: TObject);
begin
  UpdateFields;
end;

procedure TAtlasBreakpointRuleDialog.UpdateFields;
begin
  FDepend.Enabled := FTrigger.ItemIndex > 0;
  FHitCount.Enabled := FHit.ItemIndex > Ord(TAtlasHitMode.Any);
  FThreadText.Enabled := FThread.ItemIndex in [Ord(TAtlasThreadFilter.NameContains),
    Ord(TAtlasThreadFilter.ThreadId)];
  FCallerDirect.Enabled := Trim(FCaller.Text) <> '';
end;

procedure TAtlasBreakpointRuleDialog.OkClick(Sender: TObject);
begin
  ModalResult := mrOk;
end;

procedure TAtlasBreakpointRuleDialog.ClearClick(Sender: TObject);
begin
  ModalResult := cModeRetry;
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
  FillCallers;
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
  Result.Caller := Trim(FCaller.Text);
  Result.CallerDirect := (Result.Caller <> '') and FCallerDirect.Checked;
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

class function TAtlasBreakpointRuleDialog.TriggerText(const ATrigger: TAtlasRuleTrigger): string;
begin
  Result := Format('%s:%d', [ExtractFileName(ATrigger.FileName.Replace('/', PathDelim)), ATrigger.Line + 1]);
end;

class function TAtlasBreakpointRuleDialog.Execute(const ARule: TAtlasBreakpointRule;
  const ATriggers: TAtlasRuleTriggers; const ACallers: TArray<string>; out AChosen: TAtlasBreakpointRule): Boolean;
var
  mDialog: TAtlasBreakpointRuleDialog;
  mResult: Integer;
begin
  AChosen := ARule;
  mDialog := TAtlasBreakpointRuleDialog.CreateDialog(nil, ARule, ATriggers, ACallers);
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
