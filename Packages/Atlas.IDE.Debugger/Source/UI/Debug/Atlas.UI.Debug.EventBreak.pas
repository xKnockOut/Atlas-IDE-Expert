unit Atlas.UI.Debug.EventBreak;

// Beim nächsten Ereignis anhalten (#856), Fensterteil (nur VCL):
// - TAtlasEventBreakDialog: Wahl der Ereignisarten, häufige Ereignisse und
//   Formulare (alle, die gerade sichtbaren, eines), darunter die Zahl der
//   Handler und Haltestellen zur aktuellen Wahl.
// - TAtlasEventBreakBar: Leiste nach dem Halt im Atlas-Stil (#410, #411)
//     Angehalten: btnSpeichern.OnClick → TfrmKunde.btnSpeichernClick
//     Weiter beobachten   Schließen
//   ohne Fokus; die Knöpfe sind Klickflächen.
// Der Dialog erbt von TAtlasDialog (IDE-Thema, Dialogschrift, Knopfleiste);
// Zeilen in logischen Pixeln, Breiten nach dem Text.

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Atlas.Core.Debug.EventBreak,
  Atlas.UI.Foundation.Dialog,
  Atlas.UI.Popup.Window;

type
  /// <summary>Text unter der Wahl („12 Handler an 9 Stellen“) zur aktuellen Wahl.</summary>
  TAtlasEventBreakCount = reference to function(const AChoice: TAtlasEventChoice): string;

  TAtlasEventBreakDialog = class(TAtlasDialog)
  private
    FCategories: array[TAtlasEventCategory] of TCheckBox;
    FFrequent: TCheckBox;
    FAll: TRadioButton;
    FVisible: TRadioButton;
    FOne: TRadioButton;
    FForm: TComboBox;
    FCount: TAtlasNoteLabel;
    FOk: TButton;
    FCancel: TButton;
    FForms: TArray<string>;
    FChoice: TAtlasEventChoice;
    FCountText: TAtlasEventBreakCount;
    FPrepared: Boolean;
    function AddCheck(AParent: TWinControl; const ACaption: string): TCheckBox;
    function AddRadio(AParent: TWinControl; const ACaption: string): TRadioButton;
    procedure Changed(Sender: TObject);
    procedure OkClick(Sender: TObject);
    procedure CancelClick(Sender: TObject);
  protected
    procedure DoShow; override;
  public
    constructor CreateDialog(AOwner: TComponent; const AChoice: TAtlasEventChoice; const AForms: TArray<string>;
      const AExcluded: string; const ACount: TAtlasEventBreakCount);
    /// <summary>Füllt die Formularliste und setzt die Wahl in die Controls (braucht ein Fenster); einmal.</summary>
    procedure Prepare;
    /// <summary>Wahl aus den Controls.</summary>
    function Choice: TAtlasEventChoice;
    /// <summary>Zeigt den Dialog modal; True mit der Wahl in AChoice.</summary>
    class function Execute(var AChoice: TAtlasEventChoice; const AForms: TArray<string>; const AExcluded: string;
      const ACount: TAtlasEventBreakCount): Boolean; static;
    function CategoryCheck(ACategory: TAtlasEventCategory): TCheckBox;
    property FrequentCheck: TCheckBox read FFrequent;
    property AllRadio: TRadioButton read FAll;
    property VisibleRadio: TRadioButton read FVisible;
    property OneRadio: TRadioButton read FOne;
    property FormCombo: TComboBox read FForm;
    property CountLabel: TAtlasNoteLabel read FCount;
    property OkButton: TButton read FOk;
  end;

  TAtlasEventBreakBar = class(TAtlasPopupWindow)
  public const
    cGap = 4;
  private
    FText: string;
    FContinueRect: TRect;
    FCloseRect: TRect;
    FHot: Integer;
    FOnContinue: TProc;
    FOnClose: TProc;
    function Layout(ADraw: Boolean): TSize;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Zeigt „Angehalten: ACaption“ unter APoint (Bildschirm).</summary>
    procedure ShowFor(const ACaption: string; const APoint: TPoint);
    procedure Dismiss;
    /// <summary>Wie ein Klick auf „Weiter beobachten“ bzw. „Schließen“.</summary>
    procedure KeepWatching;
    procedure CloseBar;
    function ContinueRect: TRect;
    function CloseRect: TRect;
    property Text: string read FText;
    property OnContinue: TProc read FOnContinue write FOnContinue;
    property OnClose: TProc read FOnClose write FOnClose;
  end;

implementation

uses
  System.Math,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Style.Signal,
  Atlas.UI.Debug.Strings,
  Atlas.UI.Popup.Accessibility;

const
  cDialogGap = 8;
  cDialogWidth = 440;
  cPad = 10;
  cButtonGap = 18;
  /// <summary>Höhe einer Zeile mit Kästchen oder Knopf, der Zeile mit Auswahlfeld und der Zahl darunter, logische
  /// Pixel.</summary>
  cLineHeight = 22;
  cComboRowHeight = 28;
  cCountHeight = 36;
  /// <summary>Platz für den Kreis eines Optionsfelds vor seinem Text und Abstand zum Auswahlfeld, logische Pixel.
  /// </summary>
  cRadioMark = 24;
  cComboGap = 4;

function CategoryText(ACategory: TAtlasEventCategory): string;
begin
  case ACategory of
    TAtlasEventCategory.Mouse:
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.EventBreakMouse);
    TAtlasEventCategory.Keyboard:
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.EventBreakKeyboard);
    TAtlasEventCategory.Timer:
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.EventBreakTimer);
    TAtlasEventCategory.Window:
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.EventBreakWindow);
    TAtlasEventCategory.Database:
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.EventBreakDatabase);
    TAtlasEventCategory.Actions:
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.EventBreakActions);
  else
    Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.EventBreakOther);
  end;
end;

/// <summary>Gruppe der Ereignisarten mit „häufige ausnehmen“ (AExcluded) oben in ADialog.</summary>
function CreateCategories(ADialog: TAtlasEventBreakDialog; const AExcluded: string): TGroupBox;
var
  mCategory: TAtlasEventCategory;
  mTop: Integer;
begin
  Result := TGroupBox.Create(ADialog);
  Result.Parent := ADialog;
  Result.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.EventBreakCategories);
  Result.SetBounds(ADialog.ScaleValue(cDialogGap), ADialog.ScaleValue(cDialogGap),
    ADialog.ClientWidth - 2 * ADialog.ScaleValue(cDialogGap), 0);
  mTop := ADialog.ScaleValue(20);
  for mCategory := Low(TAtlasEventCategory) to High(TAtlasEventCategory) do
  begin
    ADialog.FCategories[mCategory] := ADialog.AddCheck(Result, CategoryText(mCategory));
    ADialog.FCategories[mCategory].Top := mTop;
    Inc(mTop, ADialog.ScaleValue(cLineHeight));
  end;
  ADialog.FFrequent := ADialog.AddCheck(Result, TAtlasDebugStrings.Fmt(TAtlasDebugTextId.EventBreakFrequent,
    [AExcluded]));
  ADialog.FFrequent.Top := mTop + ADialog.ScaleValue(4);
  Result.Height := ADialog.FFrequent.Top + ADialog.ScaleValue(30);
end;

/// <summary>„Ein Formular“ links, das Auswahlfeld füllt den Rest der Zeile.</summary>
procedure CreateFormRow(ADialog: TAtlasEventBreakDialog);
var
  mRow: TPanel;
begin
  mRow := ADialog.AddRow(cComboRowHeight);
  ADialog.FOne := ADialog.AddRadio(mRow, TAtlasDebugStrings.Text(TAtlasDebugTextId.EventBreakOneForm));
  ADialog.FOne.Align := alLeft;
  ADialog.FOne.Width := ADialog.FOne.Margins.Left + TAtlasDialog.TextWidth(ADialog.Font, ADialog.FOne.Caption) +
    ADialog.ScaleValue(cRadioMark);
  ADialog.FForm := TComboBox.Create(ADialog);
  ADialog.FForm.Style := csDropDownList;
  ADialog.FForm.AlignWithMargins := True;
  ADialog.FForm.Margins.SetBounds(ADialog.ScaleValue(cComboGap), 0, 0, 0);
  ADialog.FForm.Align := alClient;
  ADialog.FForm.Parent := mRow;
  ADialog.FForm.OnChange := ADialog.Changed;
end;

/// <summary>Knopfleiste mit „OK“ und „Abbrechen“ unten in ADialog.</summary>
procedure CreateButtons(ADialog: TAtlasEventBreakDialog);
var
  mButtons: TAtlasButtonRow;
begin
  mButtons := ADialog.AddButtonRow;
  ADialog.FOk := mButtons.AddButton(TAtlasDebugStrings.Text(TAtlasDebugTextId.EventBreakOk),
    TAtlasButtonKind.Default);
  ADialog.FOk.OnClick := ADialog.OkClick;
  ADialog.FCancel := mButtons.AddButton(TAtlasDebugStrings.Text(TAtlasDebugTextId.EventBreakCancel),
    TAtlasButtonKind.Cancel);
  ADialog.FCancel.OnClick := ADialog.CancelClick;
end;

{ TAtlasEventBreakDialog }

constructor TAtlasEventBreakDialog.CreateDialog(AOwner: TComponent; const AChoice: TAtlasEventChoice;
  const AForms: TArray<string>; const AExcluded: string; const ACount: TAtlasEventBreakCount);
var
  mHeading: TLabel;
begin
  inherited CreateDialog(AOwner, TAtlasDebugStrings.Text(TAtlasDebugTextId.EventBreakTitle), cDialogWidth);
  FChoice := AChoice;
  FForms := AForms;
  FCountText := ACount;
  BorderIcons := [biSystemMenu];
  CreateCategories(Self, AExcluded);
  mHeading := AddLabel(AddRow(cLineHeight), TAtlasDebugStrings.Text(TAtlasDebugTextId.EventBreakScope));
  mHeading.Font.Style := [fsBold];
  FAll := AddRadio(AddRow(cLineHeight), TAtlasDebugStrings.Text(TAtlasDebugTextId.EventBreakAllForms));
  FVisible := AddRadio(AddRow(cLineHeight), TAtlasDebugStrings.Text(TAtlasDebugTextId.EventBreakVisibleForms));
  CreateFormRow(Self);
  FCount := AddNote(cCountHeight);
  FCount.ShowAccelChar := False;
  CreateButtons(Self);
  FitHeight;
end;

procedure TAtlasEventBreakDialog.DoShow;
begin
  Prepare;
  inherited;
end;

function TAtlasEventBreakDialog.AddCheck(AParent: TWinControl; const ACaption: string): TCheckBox;
begin
  Result := TCheckBox.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.Left := ScaleValue(cDialogGap);
  Result.Width := AParent.ClientWidth - 2 * ScaleValue(cDialogGap);
  Result.OnClick := Changed;
end;

function TAtlasEventBreakDialog.AddRadio(AParent: TWinControl; const ACaption: string): TRadioButton;
begin
  // Eingerückt unter der Überschrift; füllt die Zeile, damit längere Übersetzungen nicht abgeschnitten werden.
  Result := TRadioButton.Create(Self);
  Result.Caption := ACaption;
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(ScaleValue(cDialogGap), 0, 0, 0);
  Result.Align := alClient;
  Result.Parent := AParent;
  Result.OnClick := Changed;
end;

procedure TAtlasEventBreakDialog.Changed(Sender: TObject);
var
  mCurrent: TAtlasEventChoice;
begin
  if not FPrepared then
  begin
    Exit;
  end;
  if (Sender = FForm) and (FForm.ItemIndex >= 0) then
  begin
    FOne.Checked := True;
  end;
  mCurrent := Choice;
  FOk.Enabled := mCurrent.Categories <> [];
  if Assigned(FCountText) then
  begin
    FCount.ShowNote(FCountText(mCurrent), TAtlasSignalKind.Info);
  end
  else
  begin
    FCount.ShowNote('', TAtlasSignalKind.Info);
  end;
end;

procedure TAtlasEventBreakDialog.OkClick(Sender: TObject);
begin
  if Choice.Categories = [] then
  begin
    Exit;
  end;
  ModalResult := mrOk;
end;

procedure TAtlasEventBreakDialog.CancelClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

procedure TAtlasEventBreakDialog.Prepare;
var
  mCategory: TAtlasEventCategory;
  mName: string;
  mIndex: Integer;
begin
  if FPrepared then
  begin
    Exit;
  end;
  FPrepared := True;
  HandleNeeded;
  FForm.Items.BeginUpdate;
  try
    for mName in FForms do
    begin
      FForm.Items.Add(mName);
    end;
  finally
    FForm.Items.EndUpdate;
  end;
  mIndex := FForm.Items.IndexOf(FChoice.Form);
  if (mIndex < 0) and (FForm.Items.Count > 0) then
  begin
    mIndex := 0;
  end;
  FForm.ItemIndex := mIndex;
  for mCategory := Low(TAtlasEventCategory) to High(TAtlasEventCategory) do
  begin
    FCategories[mCategory].Checked := mCategory in FChoice.Categories;
  end;
  FFrequent.Checked := FChoice.Frequent;
  FAll.Checked := FChoice.Scope = TAtlasEventScope.AllForms;
  FVisible.Checked := FChoice.Scope = TAtlasEventScope.VisibleForms;
  FOne.Checked := FChoice.Scope = TAtlasEventScope.OneForm;
  FOne.Enabled := FForm.Items.Count > 0;
  Changed(nil);
end;

function TAtlasEventBreakDialog.Choice: TAtlasEventChoice;
var
  mCategory: TAtlasEventCategory;
begin
  Result := Default(TAtlasEventChoice);
  for mCategory := Low(TAtlasEventCategory) to High(TAtlasEventCategory) do
  begin
    if FCategories[mCategory].Checked then
    begin
      Include(Result.Categories, mCategory);
    end;
  end;
  Result.Frequent := FFrequent.Checked;
  Result.Scope := TAtlasEventScope.AllForms;
  if FVisible.Checked then
  begin
    Result.Scope := TAtlasEventScope.VisibleForms;
  end
  else if FOne.Checked and (FForm.ItemIndex >= 0) then
  begin
    Result.Scope := TAtlasEventScope.OneForm;
    Result.Form := FForm.Items[FForm.ItemIndex];
  end;
end;

class function TAtlasEventBreakDialog.Execute(var AChoice: TAtlasEventChoice; const AForms: TArray<string>;
  const AExcluded: string; const ACount: TAtlasEventBreakCount): Boolean;
var
  mDialog: TAtlasEventBreakDialog;
begin
  mDialog := TAtlasEventBreakDialog.CreateDialog(nil, AChoice, AForms, AExcluded, ACount);
  try
    Result := mDialog.ShowModal = mrOk;
    if Result then
    begin
      AChoice := mDialog.Choice;
    end;
  finally
    mDialog.Free;
  end;
end;

function TAtlasEventBreakDialog.CategoryCheck(ACategory: TAtlasEventCategory): TCheckBox;
begin
  Result := FCategories[ACategory];
end;

{ TAtlasEventBreakBar }

constructor TAtlasEventBreakBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  GuardFeature := TAtlasFeature.Debugger;
  FHot := -1;
  SetAccessible(cUiaToolTipControlType, TAtlasDebugStrings.Text(TAtlasDebugTextId.EventBreakTitle));
end;

procedure TAtlasEventBreakBar.Paint;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Surface);
  Canvas.FillRect(ClientRect);
  Layout(True);
  PaintBorder;
end;

procedure TAtlasEventBreakBar.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  mPoint: TPoint;
begin
  inherited;
  if Button <> mbLeft then
  begin
    Exit;
  end;
  mPoint := TPoint.Create(X, Y);
  if PtInRect(FContinueRect, mPoint) then
  begin
    KeepWatching;
  end
  else if PtInRect(FCloseRect, mPoint) then
  begin
    CloseBar;
  end;
end;

procedure TAtlasEventBreakBar.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  mPoint: TPoint;
  mHot: Integer;
begin
  inherited;
  mPoint := TPoint.Create(X, Y);
  mHot := -1;
  if PtInRect(FContinueRect, mPoint) then
  begin
    mHot := 0;
  end
  else if PtInRect(FCloseRect, mPoint) then
  begin
    mHot := 1;
  end;
  if mHot >= 0 then
  begin
    Cursor := crHandPoint;
  end
  else
  begin
    Cursor := crDefault;
  end;
  if mHot <> FHot then
  begin
    FHot := mHot;
    Invalidate;
  end;
end;

function TAtlasEventBreakBar.Layout(ADraw: Boolean): TSize;
var
  X, Y, mTextHeight, mWidth: Integer;
  mText: string;

  procedure Link(const ACaption: string; AIndex: Integer; var ARect: TRect);
  begin
    ARect := Rect(X, Y, X + Canvas.TextWidth(ACaption), Y + mTextHeight);
    if ADraw then
    begin
      Canvas.Font.Color := ToColor(Colors.Accent);
      if FHot = AIndex then
      begin
        Canvas.Font.Style := [fsUnderline];
      end
      else
      begin
        Canvas.Font.Style := [];
      end;
      Canvas.TextOut(X, Y, ACaption);
      Canvas.Font.Style := [];
    end;
    X := ARect.Right + Scale(cButtonGap);
  end;

begin
  Canvas.Font := UIFont;
  mTextHeight := Canvas.TextHeight('Wg');
  if ADraw then
  begin
    Canvas.Brush.Style := bsClear;
  end;
  X := Scale(cPad);
  Y := Scale(cPad);
  mText := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.EventBreakStopped, [FText]);
  Canvas.Font.Style := [fsBold];
  if ADraw then
  begin
    Canvas.Font.Color := ToColor(Colors.Text);
    Canvas.TextOut(X, Y, mText);
  end;
  mWidth := X + Canvas.TextWidth(mText);
  Canvas.Font.Style := [];
  Y := Y + mTextHeight + Scale(cGap) * 2;
  Link(TAtlasDebugStrings.Text(TAtlasDebugTextId.EventBreakContinue), 0, FContinueRect);
  Link(TAtlasDebugStrings.Text(TAtlasDebugTextId.EventBreakClose), 1, FCloseRect);
  mWidth := Max(mWidth, FCloseRect.Right);
  if ADraw then
  begin
    Canvas.Brush.Style := bsSolid;
  end;
  Result.cx := mWidth + Scale(cPad);
  Result.cy := Y + mTextHeight + Scale(cPad);
end;

procedure TAtlasEventBreakBar.ShowFor(const ACaption: string; const APoint: TPoint);
var
  mSize: TSize;
  mArea: TRect;
  mLeft, mTop: Integer;
begin
  FText := ACaption;
  FHot := -1;
  HandleNeeded;
  mSize := Layout(False);
  mArea := WorkAreaAt(APoint);
  mLeft := Max(mArea.Left, Min(APoint.X, mArea.Right - mSize.cx));
  mTop := APoint.Y + Scale(cGap);
  if mTop + mSize.cy > mArea.Bottom then
  begin
    mTop := APoint.Y - Scale(cGap) - mSize.cy;
  end;
  mTop := Max(mTop, mArea.Top);
  ShowAt(Rect(mLeft, mTop, mLeft + mSize.cx, mTop + mSize.cy));
  Announce(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.EventBreakStopped, [FText]));
end;

procedure TAtlasEventBreakBar.Dismiss;
begin
  HidePopup;
end;

procedure TAtlasEventBreakBar.KeepWatching;
begin
  Dismiss;
  if Assigned(FOnContinue) then
  begin
    FOnContinue();
  end;
end;

procedure TAtlasEventBreakBar.CloseBar;
begin
  Dismiss;
  if Assigned(FOnClose) then
  begin
    FOnClose();
  end;
end;

function TAtlasEventBreakBar.ContinueRect: TRect;
begin
  Result := FContinueRect;
end;

function TAtlasEventBreakBar.CloseRect: TRect;
begin
  Result := FCloseRect;
end;

end.
