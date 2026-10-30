unit Atlas.UI.Debug.EventBreak;

// Beim nächsten Ereignis anhalten (#856), Fensterteil (nur VCL):
// - TAtlasEventBreakDialog: Wahl der Ereignisarten, häufige Ereignisse und
//   Formulare (alle, die gerade sichtbaren, eines), darunter die Zahl der
//   Handler und Haltestellen zur aktuellen Wahl.
// - TAtlasEventBreakBar: Leiste nach dem Halt im Atlas-Stil (#410, #411)
//     Angehalten: btnSpeichern.OnClick → TfrmKunde.btnSpeichernClick
//     Weiter beobachten   Schließen
//   ohne Fokus; die Knöpfe sind Klickflächen.

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
  Atlas.UI.Popup.Window;

type
  /// <summary>Text unter der Wahl („12 Handler an 9 Stellen“) zur aktuellen Wahl.</summary>
  TAtlasEventBreakCount = reference to function(const AChoice: TAtlasEventChoice): string;

  TAtlasEventBreakDialog = class(TForm)
  private
    FCategories: array[TAtlasEventCategory] of TCheckBox;
    FFrequent: TCheckBox;
    FAll: TRadioButton;
    FVisible: TRadioButton;
    FOne: TRadioButton;
    FForm: TComboBox;
    FCount: TLabel;
    FOk: TButton;
    FCancel: TButton;
    FForms: TArray<string>;
    FChoice: TAtlasEventChoice;
    FCountText: TAtlasEventBreakCount;
    FPrepared: Boolean;
    function AddCheck(AParent: TWinControl; const ACaption: string): TCheckBox;
    function AddRadio(AParent: TWinControl; const ACaption: string): TRadioButton;
    function AddButton(AParent: TWinControl; const ACaption: string; AClick: TNotifyEvent): TButton;
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
    property CountLabel: TLabel read FCount;
    property OkButton: TButton read FOk;
  end;

  TAtlasEventBreakBar = class(TAtlasPopupWindow)
  public const
    Gap = 4;
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
  Atlas.UI.Strings,
  Atlas.UI.Popup.Accessibility;

const
  DialogGap = 8;
  DialogWidth = 440;
  Pad = 10;
  ButtonGap = 18;

function CategoryText(ACategory: TAtlasEventCategory): string;
begin
  case ACategory of
    TAtlasEventCategory.Mouse:
      Result := TAtlasStrings.Text(TAtlasTextId.EventBreakMouse);
    TAtlasEventCategory.Keyboard:
      Result := TAtlasStrings.Text(TAtlasTextId.EventBreakKeyboard);
    TAtlasEventCategory.Timer:
      Result := TAtlasStrings.Text(TAtlasTextId.EventBreakTimer);
    TAtlasEventCategory.Window:
      Result := TAtlasStrings.Text(TAtlasTextId.EventBreakWindow);
    TAtlasEventCategory.Database:
      Result := TAtlasStrings.Text(TAtlasTextId.EventBreakDatabase);
    TAtlasEventCategory.Actions:
      Result := TAtlasStrings.Text(TAtlasTextId.EventBreakActions);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.EventBreakOther);
  end;
end;

{ TAtlasEventBreakDialog }

constructor TAtlasEventBreakDialog.CreateDialog(AOwner: TComponent; const AChoice: TAtlasEventChoice;
  const AForms: TArray<string>; const AExcluded: string; const ACount: TAtlasEventBreakCount);
var
  Category: TAtlasEventCategory;
  Group: TGroupBox;
  Bottom: TPanel;
  Heading: TLabel;
  Top: Integer;
begin
  inherited CreateNew(AOwner);
  FChoice := AChoice;
  FForms := AForms;
  FCountText := ACount;
  Caption := TAtlasStrings.Text(TAtlasTextId.EventBreakTitle);
  BorderStyle := bsDialog;
  BorderIcons := [biSystemMenu];
  Position := poMainFormCenter;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  ClientWidth := ScaleValue(DialogWidth);

  Group := TGroupBox.Create(Self);
  Group.Parent := Self;
  Group.Caption := TAtlasStrings.Text(TAtlasTextId.EventBreakCategories);
  Group.SetBounds(ScaleValue(DialogGap), ScaleValue(DialogGap), ClientWidth - 2 * ScaleValue(DialogGap), 0);
  Top := ScaleValue(20);
  for Category := Low(TAtlasEventCategory) to High(TAtlasEventCategory) do
  begin
    FCategories[Category] := AddCheck(Group, CategoryText(Category));
    FCategories[Category].Top := Top;
    Inc(Top, ScaleValue(22));
  end;
  FFrequent := AddCheck(Group, TAtlasStrings.Fmt(TAtlasTextId.EventBreakFrequent, [AExcluded]));
  FFrequent.Top := Top + ScaleValue(4);
  Group.Height := FFrequent.Top + ScaleValue(30);

  Heading := TLabel.Create(Self);
  Heading.Parent := Self;
  Heading.Caption := TAtlasStrings.Text(TAtlasTextId.EventBreakScope);
  Heading.Font.Style := [fsBold];
  Heading.SetBounds(ScaleValue(DialogGap), Group.Top + Group.Height + ScaleValue(DialogGap), 0, 0);
  Heading.AutoSize := True;
  Top := Heading.Top + ScaleValue(20);
  FAll := AddRadio(Self, TAtlasStrings.Text(TAtlasTextId.EventBreakAllForms));
  FAll.Top := Top;
  FVisible := AddRadio(Self, TAtlasStrings.Text(TAtlasTextId.EventBreakVisibleForms));
  FVisible.Top := Top + ScaleValue(22);
  FOne := AddRadio(Self, TAtlasStrings.Text(TAtlasTextId.EventBreakOneForm));
  FOne.Top := Top + ScaleValue(44);
  FOne.Width := ScaleValue(150);
  FForm := TComboBox.Create(Self);
  FForm.Parent := Self;
  FForm.Style := csDropDownList;
  FForm.SetBounds(FOne.Left + FOne.Width + ScaleValue(4), FOne.Top - ScaleValue(2),
    ClientWidth - FOne.Left - FOne.Width - ScaleValue(4) - ScaleValue(DialogGap), FForm.Height);
  FForm.OnChange := Changed;

  FCount := TLabel.Create(Self);
  FCount.Parent := Self;
  FCount.ShowAccelChar := False;
  FCount.SetBounds(ScaleValue(DialogGap), FOne.Top + ScaleValue(32), ClientWidth - 2 * ScaleValue(DialogGap), 0);
  FCount.AutoSize := True;

  Bottom := TPanel.Create(Self);
  Bottom.Parent := Self;
  Bottom.Align := alBottom;
  Bottom.Height := ScaleValue(44);
  Bottom.BevelOuter := bvNone;
  FCancel := AddButton(Bottom, TAtlasStrings.Text(TAtlasTextId.EventBreakCancel), CancelClick);
  FCancel.Cancel := True;
  FCancel.Left := Bottom.ClientWidth - FCancel.Width - ScaleValue(DialogGap);
  FOk := AddButton(Bottom, TAtlasStrings.Text(TAtlasTextId.EventBreakOk), OkClick);
  FOk.Default := True;
  FOk.Left := FCancel.Left - FOk.Width - ScaleValue(DialogGap);
  ClientHeight := FCount.Top + ScaleValue(28) + Bottom.Height;
end;

function TAtlasEventBreakDialog.AddCheck(AParent: TWinControl; const ACaption: string): TCheckBox;
begin
  Result := TCheckBox.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.Left := ScaleValue(DialogGap);
  Result.Width := AParent.ClientWidth - 2 * ScaleValue(DialogGap);
  Result.OnClick := Changed;
end;

function TAtlasEventBreakDialog.AddRadio(AParent: TWinControl; const ACaption: string): TRadioButton;
begin
  Result := TRadioButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.Left := ScaleValue(DialogGap) * 2;
  Result.Width := ClientWidth - 4 * ScaleValue(DialogGap);
  Result.OnClick := Changed;
end;

function TAtlasEventBreakDialog.AddButton(AParent: TWinControl; const ACaption: string;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.OnClick := AClick;
  Canvas.Font := Font;
  Result.Width := Max(Canvas.TextWidth(ACaption) + ScaleValue(32), ScaleValue(90));
  Result.Top := ScaleValue(DialogGap);
  Result.Height := ScaleValue(28);
  Result.Anchors := [akTop, akRight];
end;

procedure TAtlasEventBreakDialog.Prepare;
var
  Category: TAtlasEventCategory;
  Name: string;
  Index: Integer;
begin
  if FPrepared then
    Exit;
  FPrepared := True;
  HandleNeeded;
  for Name in FForms do
    FForm.Items.Add(Name);
  Index := FForm.Items.IndexOf(FChoice.Form);
  if (Index < 0) and (FForm.Items.Count > 0) then
    Index := 0;
  FForm.ItemIndex := Index;
  for Category := Low(TAtlasEventCategory) to High(TAtlasEventCategory) do
    FCategories[Category].Checked := Category in FChoice.Categories;
  FFrequent.Checked := FChoice.Frequent;
  FAll.Checked := FChoice.Scope = TAtlasEventScope.AllForms;
  FVisible.Checked := FChoice.Scope = TAtlasEventScope.VisibleForms;
  FOne.Checked := FChoice.Scope = TAtlasEventScope.OneForm;
  FOne.Enabled := FForm.Items.Count > 0;
  Changed(nil);
end;

procedure TAtlasEventBreakDialog.DoShow;
begin
  Prepare;
  inherited;
end;

function TAtlasEventBreakDialog.CategoryCheck(ACategory: TAtlasEventCategory): TCheckBox;
begin
  Result := FCategories[ACategory];
end;

function TAtlasEventBreakDialog.Choice: TAtlasEventChoice;
var
  Category: TAtlasEventCategory;
begin
  Result := Default(TAtlasEventChoice);
  for Category := Low(TAtlasEventCategory) to High(TAtlasEventCategory) do
    if FCategories[Category].Checked then
      Include(Result.Categories, Category);
  Result.Frequent := FFrequent.Checked;
  Result.Scope := TAtlasEventScope.AllForms;
  if FVisible.Checked then
    Result.Scope := TAtlasEventScope.VisibleForms
  else if FOne.Checked and (FForm.ItemIndex >= 0) then
  begin
    Result.Scope := TAtlasEventScope.OneForm;
    Result.Form := FForm.Items[FForm.ItemIndex];
  end;
end;

procedure TAtlasEventBreakDialog.Changed(Sender: TObject);
var
  Current: TAtlasEventChoice;
begin
  if not FPrepared then
    Exit;
  if (Sender = FForm) and (FForm.ItemIndex >= 0) then
    FOne.Checked := True;
  Current := Choice;
  FOk.Enabled := Current.Categories <> [];
  if Assigned(FCountText) then
    FCount.Caption := FCountText(Current)
  else
    FCount.Caption := '';
end;

procedure TAtlasEventBreakDialog.OkClick(Sender: TObject);
begin
  if Choice.Categories = [] then
    Exit;
  ModalResult := mrOk;
end;

procedure TAtlasEventBreakDialog.CancelClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

class function TAtlasEventBreakDialog.Execute(var AChoice: TAtlasEventChoice; const AForms: TArray<string>;
  const AExcluded: string; const ACount: TAtlasEventBreakCount): Boolean;
var
  Dialog: TAtlasEventBreakDialog;
begin
  Dialog := TAtlasEventBreakDialog.CreateDialog(nil, AChoice, AForms, AExcluded, ACount);
  try
    Result := Dialog.ShowModal = mrOk;
    if Result then
      AChoice := Dialog.Choice;
  finally
    Dialog.Free;
  end;
end;

{ TAtlasEventBreakBar }

constructor TAtlasEventBreakBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  GuardFeature := TAtlasFeature.Debugger;
  FHot := -1;
  SetAccessible(UiaToolTipControlType, TAtlasStrings.Text(TAtlasTextId.EventBreakTitle));
end;

function TAtlasEventBreakBar.Layout(ADraw: Boolean): TSize;
var
  X, Y, TextHeight, Width: Integer;
  mText: string;

  procedure Link(const ACaption: string; AIndex: Integer; var ARect: TRect);
  begin
    ARect := Rect(X, Y, X + Canvas.TextWidth(ACaption), Y + TextHeight);
    if ADraw then
    begin
      Canvas.Font.Color := ToColor(Colors.Accent);
      if FHot = AIndex then
        Canvas.Font.Style := [fsUnderline]
      else
        Canvas.Font.Style := [];
      Canvas.TextOut(X, Y, ACaption);
      Canvas.Font.Style := [];
    end;
    X := ARect.Right + Scale(ButtonGap);
  end;

begin
  Canvas.Font := UIFont;
  TextHeight := Canvas.TextHeight('Wg');
  if ADraw then
    Canvas.Brush.Style := bsClear;
  X := Scale(Pad);
  Y := Scale(Pad);
  mText := TAtlasStrings.Fmt(TAtlasTextId.EventBreakStopped, [FText]);
  Canvas.Font.Style := [fsBold];
  if ADraw then
  begin
    Canvas.Font.Color := ToColor(Colors.Text);
    Canvas.TextOut(X, Y, mText);
  end;
  Width := X + Canvas.TextWidth(mText);
  Canvas.Font.Style := [];
  Y := Y + TextHeight + Scale(Gap) * 2;
  Link(TAtlasStrings.Text(TAtlasTextId.EventBreakContinue), 0, FContinueRect);
  Link(TAtlasStrings.Text(TAtlasTextId.EventBreakClose), 1, FCloseRect);
  Width := Max(Width, FCloseRect.Right);
  if ADraw then
    Canvas.Brush.Style := bsSolid;
  Result.cx := Width + Scale(Pad);
  Result.cy := Y + TextHeight + Scale(Pad);
end;

procedure TAtlasEventBreakBar.ShowFor(const ACaption: string; const APoint: TPoint);
var
  Size: TSize;
  Area: TRect;
  Left, Top: Integer;
begin
  FText := ACaption;
  FHot := -1;
  HandleNeeded;
  Size := Layout(False);
  Area := WorkAreaAt(APoint);
  Left := Max(Area.Left, Min(APoint.X, Area.Right - Size.cx));
  Top := APoint.Y + Scale(Gap);
  if Top + Size.cy > Area.Bottom then
    Top := APoint.Y - Scale(Gap) - Size.cy;
  Top := Max(Top, Area.Top);
  ShowAt(Rect(Left, Top, Left + Size.cx, Top + Size.cy));
  Announce(TAtlasStrings.Fmt(TAtlasTextId.EventBreakStopped, [FText]));
end;

procedure TAtlasEventBreakBar.Dismiss;
begin
  HidePopup;
end;

procedure TAtlasEventBreakBar.KeepWatching;
begin
  Dismiss;
  if Assigned(FOnContinue) then
    FOnContinue();
end;

procedure TAtlasEventBreakBar.CloseBar;
begin
  Dismiss;
  if Assigned(FOnClose) then
    FOnClose();
end;

function TAtlasEventBreakBar.ContinueRect: TRect;
begin
  Result := FContinueRect;
end;

function TAtlasEventBreakBar.CloseRect: TRect;
begin
  Result := FCloseRect;
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
  Point: TPoint;
begin
  inherited;
  if Button <> mbLeft then
    Exit;
  Point := TPoint.Create(X, Y);
  if PtInRect(FContinueRect, Point) then
    KeepWatching
  else if PtInRect(FCloseRect, Point) then
    CloseBar;
end;

procedure TAtlasEventBreakBar.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Point: TPoint;
  Hot: Integer;
begin
  inherited;
  Point := TPoint.Create(X, Y);
  Hot := -1;
  if PtInRect(FContinueRect, Point) then
    Hot := 0
  else if PtInRect(FCloseRect, Point) then
    Hot := 1;
  if Hot >= 0 then
    Cursor := crHandPoint
  else
    Cursor := crDefault;
  if Hot <> FHot then
  begin
    FHot := Hot;
    Invalidate;
  end;
end;

end.
