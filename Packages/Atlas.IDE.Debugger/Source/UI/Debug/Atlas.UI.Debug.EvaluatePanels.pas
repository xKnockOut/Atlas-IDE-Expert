unit Atlas.UI.Debug.EvaluatePanels;

// Teile des Fensters „Auswerten“ (#784) neben dem Baum, reine VCL:
//   - TAtlasEvalFrameHooks: was der Frame an die IDE-Schicht meldet; ein
//     Objekt, das sich Frame, Eingabezeile und Ansicht teilen.
//   - TAtlasEvalInputBar: oben das Eingabefeld (Enter fügt den Ausdruck als
//     Zeile an, Strg+Enter heftet ihn fest, Pfeil nach unten im leeren Feld
//     zeigt den Verlauf) und „Nebenwirkungen erlauben“.
//   - TAtlasEvalDetailPanel: unten die Ansicht des gewählten Werts (Text mit
//     sichtbaren Steuerzeichen, Zeilen einer TStrings, JSON, Hex), darüber die
//     Leiste mit den Ansichten, „Ändern …“, „Festheften“ und „IDE-Dialog“. Die
//     Zeilen-Ansicht braucht den Wert von „Ausdruck.Text“: Die IDE-Schicht
//     wertet ihn auf Hooks.Lines aus und reicht ihn mit SetLines zurück.
// Welcher Knoten gewählt ist, weiß nur der Frame; die Ansicht fragt ihn über
// TAtlasEvalNodeSource.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Buttons,
  Vcl.Menus,
  Atlas.Core.Debug.Evaluate,
  Atlas.UI.Debug.EvaluateTreeView;

type
  /// <summary>Was der Frame an die IDE-Schicht meldet; nicht gesetzte Einträge bleiben still. Gehört dem Frame.
  /// </summary>
  TAtlasEvalFrameHooks = class
  private
    FAdd: TProc<string>;
    FPin: TAtlasEvalNodeProc;
    FPinExpression: TProc<string>;
    FDelete: TAtlasEvalNodeProc;
    FExpand: TAtlasEvalNodeProc;
    FModify: TAtlasEvalNodeProc;
    FLines: TAtlasEvalNodeProc;
    FHistory: TFunc<TArray<string>>;
    FSideEffects: TProc<Boolean>;
    FIdeDialog: TProc;
  public
    /// <summary>Enter im Eingabefeld: Ausdruck als Zeile anfügen.</summary>
    property Add: TProc<string> read FAdd write FAdd;
    /// <summary>Knoten festheften bzw. lösen (Wurzel) oder seinen Ausdruck als festgeheftete Zeile anlegen (Kind).
    /// </summary>
    property Pin: TAtlasEvalNodeProc read FPin write FPin;
    /// <summary>Strg+Enter im Eingabefeld.</summary>
    property PinExpression: TProc<string> read FPinExpression write FPinExpression;
    /// <summary>Entf: ganze Zeile entfernen (immer die Wurzel).</summary>
    property Delete: TAtlasEvalNodeProc read FDelete write FDelete;
    /// <summary>Erstes Aufklappen: Felder holen, danach Refresh.</summary>
    property Expand: TAtlasEvalNodeProc read FExpand write FExpand;
    property Modify: TAtlasEvalNodeProc read FModify write FModify;
    /// <summary>Zeilen-Ansicht: „Ausdruck.Text“ auswerten und mit SetLines zurückreichen.</summary>
    property Lines: TAtlasEvalNodeProc read FLines write FLines;
    property History: TFunc<TArray<string>> read FHistory write FHistory;
    property SideEffects: TProc<Boolean> read FSideEffects write FSideEffects;
    property IdeDialog: TProc read FIdeDialog write FIdeDialog;
  end;

  /// <summary>Eingabefeld, „Nebenwirkungen erlauben“ und das Verlaufsmenü.</summary>
  TAtlasEvalInputBar = class(TPanel)
  private
    FHooks: TAtlasEvalFrameHooks;
    FInput: TEdit;
    FSideEffectsCheck: TCheckBox;
    FHistoryMenu: TPopupMenu;
    procedure InputKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure SideEffectsClick(Sender: TObject);
    procedure HistoryClick(Sender: TObject);
    /// <summary>Enter fügt an, Strg+Enter heftet fest (beide leeren das Feld).</summary>
    procedure Submit(const AHook: TProc<string>);
  public
    /// <summary>AFrame ist Besitzer und Elternfenster; seine Auflösung bestimmt die Größen.</summary>
    constructor CreateIn(AFrame: TWinControl; AHooks: TAtlasEvalFrameHooks);
    procedure SetSideEffects(AValue: Boolean);
    /// <summary>Ausdruck ins Eingabefeld (Strg+F7 mit Bezeichner unter dem Cursor) und Fokus dorthin.</summary>
    procedure FocusInput(const AExpression: string);
    /// <summary>Verlaufsmenü unter dem Eingabefeld zeigen (Pfeil nach unten im leeren Feld).</summary>
    procedure ShowHistory;
    property Input: TEdit read FInput;
    property SideEffectsCheck: TCheckBox read FSideEffectsCheck;
  end;

  /// <summary>Ansicht des gewählten Werts mit ihrer Leiste.</summary>
  TAtlasEvalDetailPanel = class(TPanel)
  private
    FHooks: TAtlasEvalFrameHooks;
    FSource: TAtlasEvalNodeSource;
    FBar: TFlowPanel;
    FViewButtons: array[TAtlasEvalView] of TSpeedButton;
    FModifyButton: TButton;
    FPinButton: TButton;
    FIdeDialogButton: TButton;
    FMemo: TMemo;
    FView: TAtlasEvalView;
    // Was die Ansicht zuletzt zeigt: Refresh kommt nach jeder Zeitscheibe der Auswertung.
    FShown: TAtlasEvalDetailInput;
    // Wert von „.Text“ für die Zeilen-Ansicht und der Knoten, zu dem er gehört.
    FLinesKey: string;
    FLinesOk: Boolean;
    FLinesText: string;
    procedure BuildBar(AFrame: TWinControl);
    procedure ViewClick(Sender: TObject);
    procedure ModifyClick(Sender: TObject);
    procedure PinClick(Sender: TObject);
    procedure IdeDialogClick(Sender: TObject);
    /// <summary>Zeilen-Ansicht: Wert von „.Text“ fehlt noch. Anfragen, bis dahin „wird ausgewertet“; True, wenn
    /// angefragt.</summary>
    function RequestLines(ANode: TAtlasEvalNode): Boolean;
    procedure ShowValue(ANode: TAtlasEvalNode; AOk: Boolean; const ALines: string);
    function GetViewButton(AView: TAtlasEvalView): TSpeedButton;
  public
    /// <summary>AFrame ist Besitzer und Elternfenster; seine Auflösung bestimmt die Größen. ASource liefert den
    /// gewählten Knoten.</summary>
    constructor CreateIn(AFrame: TWinControl; AHooks: TAtlasEvalFrameHooks; const ASource: TAtlasEvalNodeSource);
    /// <summary>Ansicht für den gewählten Knoten; fragt „.Text“ an, wenn die Zeilen-Ansicht ihn braucht.</summary>
    procedure ShowSelected;
    /// <summary>Knöpfe für den gewählten Knoten freigeben, „Festheften“ bzw. „Lösen“.</summary>
    procedure UpdateButtons;
    procedure SetView(AView: TAtlasEvalView);
    /// <summary>Wert von „Ausdruck.Text“ für die Zeilen-Ansicht des Knotens mit AKey.</summary>
    procedure SetLines(const AKey: string; AOk: Boolean; const AText: string);
    /// <summary>Neuer Halt oder neue Liste: „.Text“ für die Zeilen-Ansicht neu fragen.</summary>
    procedure InvalidateLines;
    /// <summary>Ausdruck des Knotens festheften bzw. lösen (Knopf, Strg+Enter im Baum).</summary>
    procedure PinNode(ANode: TAtlasEvalNode);
    /// <summary>Wert ändern, wenn „Ändern …“ für ihn frei ist (Knopf, F2 im Baum).</summary>
    procedure ModifyNode(ANode: TAtlasEvalNode);
    /// <summary>Inhalt der Ansicht; AUnfit: Ansicht passt nicht, gezeigt wird der Text.</summary>
    class function DetailText(ANode: TAtlasEvalNode; AView: TAtlasEvalView; ALinesOk: Boolean;
      const ALines: string; out AUnfit: Boolean): string; static;
    property Bar: TFlowPanel read FBar;
    property ViewButtons[AView: TAtlasEvalView]: TSpeedButton read GetViewButton;
    property ModifyButton: TButton read FModifyButton;
    property PinButton: TButton read FPinButton;
    property IdeDialogButton: TButton read FIdeDialogButton;
    property Memo: TMemo read FMemo;
  end;

implementation

uses
  System.Types,
  Winapi.Windows,
  Atlas.UI.Debug.Evaluate.Strings;

const
  /// <summary>Maße bei 96 dpi: Knöpfe der Leiste, Eingabezeile, Haken „Nebenwirkungen“, Ansicht unten.</summary>
  cButtonHeight = 24;
  cButtonWidth = 86;
  cViewButtonWidth = 54;
  cInputBarHeight = 30;
  cSideEffectsWidth = 170;
  cDetailHeight = 150;
  cViewTexts: array[TAtlasEvalView] of TAtlasEvaluateTextId = (TAtlasEvaluateTextId.DebugEvaluateViewText,
    TAtlasEvaluateTextId.DebugEvaluateViewLines, TAtlasEvaluateTextId.DebugEvaluateViewJson,
      TAtlasEvaluateTextId.DebugEvaluateViewHex);

/// <summary>AValue Pixel bei 96 dpi in der Auflösung von AControl.</summary>
function PixelsFor(AControl: TControl; AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, AControl.CurrentPPI, 96);
end;

/// <summary>Randloses Feld ohne Beschriftung, ausgerichtet in AFrame.</summary>
procedure PlacePanel(APanel: TPanel; AFrame: TWinControl; AAlign: TAlign; AHeight: Integer);
begin
  APanel.Parent := AFrame;
  APanel.Align := AAlign;
  APanel.BevelOuter := bvNone;
  APanel.ShowCaption := False;
  APanel.ParentBackground := True;
  APanel.Height := PixelsFor(AFrame, AHeight);
end;

/// <summary>Knopf der fließenden Leiste; die Reihenfolge ist die der Erzeugung.</summary>
function AddButton(AFrame, AParent: TWinControl; AText: TAtlasEvaluateTextId; AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(AParent);
  Result.Parent := AParent;
  Result.AlignWithMargins := True;
  Result.Width := PixelsFor(AFrame, cButtonWidth);
  Result.Height := PixelsFor(AFrame, cButtonHeight);
  Result.Caption := TAtlasEvaluateStrings.Text(AText);
  Result.OnClick := AClick;
end;

function AddViewButton(AFrame, AParent: TWinControl; AKind: TAtlasEvalView; ADown: Boolean;
  AClick: TNotifyEvent): TSpeedButton;
begin
  Result := TSpeedButton.Create(AParent);
  Result.Parent := AParent;
  Result.AlignWithMargins := True;
  Result.Width := PixelsFor(AFrame, cViewButtonWidth);
  Result.Height := PixelsFor(AFrame, cButtonHeight);
  Result.GroupIndex := 1;
  Result.AllowAllUp := False;
  Result.Caption := TAtlasEvaluateStrings.Text(cViewTexts[AKind]);
  Result.Tag := Ord(AKind);
  Result.Down := ADown;
  Result.OnClick := AClick;
end;

procedure FillHistory(AMenu: TPopupMenu; const AItems: TArray<string>; AClick: TNotifyEvent);
var
  mItem: string;
  mMenuItem: TMenuItem;
begin
  AMenu.Items.Clear;
  for mItem in AItems do
  begin
    mMenuItem := TMenuItem.Create(AMenu);
    // & im Ausdruck (&Begin, Escape von Schlüsselwörtern) nicht als Tastenkürzel lesen.
    mMenuItem.Caption := StringReplace(mItem, '&', '&&', [rfReplaceAll]);
    mMenuItem.Hint := mItem;
    mMenuItem.OnClick := AClick;
    AMenu.Items.Add(mMenuItem);
  end;
  if AMenu.Items.Count = 0 then
  begin
    mMenuItem := TMenuItem.Create(AMenu);
    mMenuItem.Caption := TAtlasEvaluateStrings.Text(TAtlasEvaluateTextId.DebugEvaluateHistoryEmpty);
    mMenuItem.Enabled := False;
    AMenu.Items.Add(mMenuItem);
  end;
end;

/// <summary>Text eines Knotens ohne Wert: wird ausgewertet, nicht angehalten, Fehlermeldung.</summary>
function StateDetail(ANode: TAtlasEvalNode): string;
begin
  case ANode.State of
    TAtlasEvalState.Pending:
      Result := TAtlasEvaluateStrings.Text(TAtlasEvaluateTextId.DebugEvaluatePending);
    TAtlasEvalState.Unavailable:
      Result := TAtlasEvaluateStrings.Text(TAtlasEvaluateTextId.DebugEvaluateNotStopped);
  else
    Result := ANode.Value;
  end;
end;

/// <summary>Zeilen-Ansicht ohne „.Text“: der Wert als Text, davor die Meldung der Auswertung, falls es eine gibt.
/// </summary>
function LinesFailedDetail(ANode: TAtlasEvalNode; const ALines: string): string;
begin
  TAtlasEvalText.Render(ANode.Value, TAtlasEvalView.Text, Result);
  if ALines <> '' then
  begin
    Result := TAtlasEvaluateStrings.Fmt(TAtlasEvaluateTextId.DebugEvaluateLinesFailed,
      [TAtlasEvalText.FieldExpression(ANode.Expression, 'Text'), ALines]) + sLineBreak + sLineBreak + Result;
  end;
end;

{ TAtlasEvalInputBar }

constructor TAtlasEvalInputBar.CreateIn(AFrame: TWinControl; AHooks: TAtlasEvalFrameHooks);
begin
  inherited Create(AFrame);
  FHooks := AHooks;
  PlacePanel(Self, AFrame, alTop, cInputBarHeight);

  FSideEffectsCheck := TCheckBox.Create(Self);
  FSideEffectsCheck.Parent := Self;
  FSideEffectsCheck.Align := alRight;
  FSideEffectsCheck.AlignWithMargins := True;
  FSideEffectsCheck.Width := PixelsFor(AFrame, cSideEffectsWidth);
  FSideEffectsCheck.Caption := TAtlasEvaluateStrings.Text(TAtlasEvaluateTextId.DebugEvaluateSideEffects);
  FSideEffectsCheck.Checked := False;
  FSideEffectsCheck.OnClick := SideEffectsClick;

  FInput := TEdit.Create(Self);
  FInput.Parent := Self;
  FInput.Align := alClient;
  FInput.AlignWithMargins := True;
  FInput.TextHint := TAtlasEvaluateStrings.Text(TAtlasEvaluateTextId.DebugEvaluateInputHint);
  FInput.OnKeyDown := InputKeyDown;

  FHistoryMenu := TPopupMenu.Create(Self);
end;

procedure TAtlasEvalInputBar.InputKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_RETURN) and (Shift = []) then
  begin
    Key := 0;
    Submit(FHooks.Add);
  end
  else if (Key = VK_RETURN) and (Shift = [ssCtrl]) then
  begin
    Key := 0;
    Submit(FHooks.PinExpression);
  end
  else if (Key = VK_DOWN) and (Shift = []) and (FInput.Text = '') then
  begin
    Key := 0;
    ShowHistory;
  end;
end;

procedure TAtlasEvalInputBar.Submit(const AHook: TProc<string>);
var
  mText: string;
begin
  mText := Trim(FInput.Text);
  if (mText <> '') and Assigned(AHook) then
  begin
    FInput.Text := '';
    AHook(mText);
  end;
end;

procedure TAtlasEvalInputBar.SideEffectsClick(Sender: TObject);
begin
  if Assigned(FHooks.SideEffects) then
  begin
    FHooks.SideEffects(FSideEffectsCheck.Checked);
  end;
end;

procedure TAtlasEvalInputBar.HistoryClick(Sender: TObject);
begin
  if Sender is TMenuItem then
  begin
    FocusInput(TMenuItem(Sender).Hint);
  end;
end;

procedure TAtlasEvalInputBar.SetSideEffects(AValue: Boolean);
var
  mHandler: TNotifyEvent;
begin
  mHandler := FSideEffectsCheck.OnClick;
  FSideEffectsCheck.OnClick := nil;
  try
    FSideEffectsCheck.Checked := AValue;
  finally
    FSideEffectsCheck.OnClick := mHandler;
  end;
end;

procedure TAtlasEvalInputBar.FocusInput(const AExpression: string);
begin
  if AExpression <> '' then
  begin
    FInput.Text := AExpression;
    FInput.SelectAll;
  end;
  if FInput.CanFocus and FInput.Showing then
  begin
    FInput.SetFocus;
  end;
end;

procedure TAtlasEvalInputBar.ShowHistory;
var
  mItems: TArray<string>;
  mPlace: TPoint;
begin
  mItems := nil;
  if Assigned(FHooks.History) then
  begin
    mItems := FHooks.History();
  end;
  FillHistory(FHistoryMenu, mItems, HistoryClick);
  mPlace := FInput.ClientToScreen(System.Types.Point(0, FInput.Height));
  FHistoryMenu.Popup(mPlace.X, mPlace.Y);
end;

{ TAtlasEvalDetailPanel }

constructor TAtlasEvalDetailPanel.CreateIn(AFrame: TWinControl; AHooks: TAtlasEvalFrameHooks;
  const ASource: TAtlasEvalNodeSource);
begin
  inherited Create(AFrame);
  FHooks := AHooks;
  FSource := ASource;
  FView := TAtlasEvalView.Text;
  PlacePanel(Self, AFrame, alBottom, cDetailHeight);
  BuildBar(AFrame);

  FMemo := TMemo.Create(Self);
  FMemo.Parent := Self;
  FMemo.Align := alClient;
  FMemo.AlignWithMargins := True;
  FMemo.ReadOnly := True;
  FMemo.ScrollBars := ssBoth;
  FMemo.WordWrap := False;
  FMemo.Font.Name := 'Consolas';
end;

/// <summary>Leiste über der Ansicht: erst die Ansichten, dann Ändern, Festheften, IDE-Dialog. Fließend: Bei
/// schmalem Fenster brechen die Knöpfe in weitere Zeilen um; TFlowPanel ordnet nach Erzeugungsreihenfolge.</summary>
procedure TAtlasEvalDetailPanel.BuildBar(AFrame: TWinControl);
var
  mKind: TAtlasEvalView;
begin
  FBar := TFlowPanel.Create(Self);
  FBar.Parent := Self;
  FBar.Align := alTop;
  FBar.BevelOuter := bvNone;
  FBar.ShowCaption := False;
  FBar.ParentBackground := True;
  FBar.AutoWrap := True;
  FBar.AutoSize := True;
  for mKind := Low(TAtlasEvalView) to High(TAtlasEvalView) do
  begin
    FViewButtons[mKind] := AddViewButton(AFrame, FBar, mKind, mKind = FView, ViewClick);
  end;
  FModifyButton := AddButton(AFrame, FBar, TAtlasEvaluateTextId.DebugEvaluateModify, ModifyClick);
  FPinButton := AddButton(AFrame, FBar, TAtlasEvaluateTextId.DebugEvaluatePin, PinClick);
  FIdeDialogButton := AddButton(AFrame, FBar, TAtlasEvaluateTextId.DebugEvaluateIdeDialog, IdeDialogClick);
end;

function TAtlasEvalDetailPanel.GetViewButton(AView: TAtlasEvalView): TSpeedButton;
begin
  Result := FViewButtons[AView];
end;

procedure TAtlasEvalDetailPanel.ViewClick(Sender: TObject);
begin
  if Sender is TSpeedButton then
  begin
    SetView(TAtlasEvalView(TSpeedButton(Sender).Tag));
  end;
end;

procedure TAtlasEvalDetailPanel.ModifyClick(Sender: TObject);
begin
  ModifyNode(FSource());
end;

procedure TAtlasEvalDetailPanel.PinClick(Sender: TObject);
begin
  PinNode(FSource());
end;

procedure TAtlasEvalDetailPanel.IdeDialogClick(Sender: TObject);
begin
  if Assigned(FHooks.IdeDialog) then
  begin
    FHooks.IdeDialog();
  end;
end;

function TAtlasEvalDetailPanel.RequestLines(ANode: TAtlasEvalNode): Boolean;
begin
  Result := (ANode.Expression <> '') and Assigned(FHooks.Lines);
  if Result then
  begin
    FLinesKey := ANode.Key;
    FLinesOk := False;
    FLinesText := '';
    FShown.Valid := False;
    FMemo.Text := TAtlasEvaluateStrings.Text(TAtlasEvaluateTextId.DebugEvaluatePending);
    FHooks.Lines(ANode);
  end;
end;

procedure TAtlasEvalDetailPanel.ShowValue(ANode: TAtlasEvalNode; AOk: Boolean; const ALines: string);
var
  mText: string;
  mUnfit: Boolean;
  mInput: TAtlasEvalDetailInput;
begin
  // Refresh kommt nach jeder Zeitscheibe der Auswertung: nur rechnen, wenn sich das Gezeigte ändert.
  mInput := TAtlasEvalDetailInput.ForNode(ANode, FView, AOk, ALines);
  if mInput.Same(FShown) then
  begin
    Exit;
  end;
  FShown := mInput;
  mText := DetailText(ANode, FView, AOk, ALines, mUnfit);
  if mUnfit and (FView <> TAtlasEvalView.Lines) then
  begin
    mText := TAtlasEvaluateStrings.Text(TAtlasEvaluateTextId.DebugEvaluateViewUnfit) + sLineBreak + sLineBreak + mText;
  end;
  FMemo.Text := mText;
end;

procedure TAtlasEvalDetailPanel.ShowSelected;
var
  mNode: TAtlasEvalNode;
  mNeedsLines: Boolean;
begin
  mNode := FSource();
  mNeedsLines := (mNode <> nil) and (FView = TAtlasEvalView.Lines) and (mNode.State = TAtlasEvalState.Value);
  if mNeedsLines and (mNode.Key = FLinesKey) then
  begin
    ShowValue(mNode, FLinesOk, FLinesText);
  end
  else if not (mNeedsLines and RequestLines(mNode)) then
  begin
    ShowValue(mNode, False, '');
  end;
end;

procedure TAtlasEvalDetailPanel.UpdateButtons;
var
  mNode: TAtlasEvalNode;
  mHasExpression: Boolean;
begin
  mNode := FSource();
  mHasExpression := (mNode <> nil) and (mNode.Expression <> '');
  FModifyButton.Enabled := mHasExpression and (mNode.State = TAtlasEvalState.Value) and Assigned(FHooks.Modify);
  FPinButton.Enabled := mHasExpression;
  if (mNode <> nil) and (mNode.Parent = nil) and mNode.Pinned then
  begin
    FPinButton.Caption := TAtlasEvaluateStrings.Text(TAtlasEvaluateTextId.DebugEvaluateUnpin);
  end
  else
  begin
    FPinButton.Caption := TAtlasEvaluateStrings.Text(TAtlasEvaluateTextId.DebugEvaluatePin);
  end;
  FIdeDialogButton.Enabled := Assigned(FHooks.IdeDialog);
end;

procedure TAtlasEvalDetailPanel.SetView(AView: TAtlasEvalView);
begin
  FView := AView;
  FViewButtons[AView].Down := True;
  // Neu fragen: „.Text“ kann sich seit dem letzten Mal geändert haben.
  FLinesKey := '';
  ShowSelected;
end;

procedure TAtlasEvalDetailPanel.SetLines(const AKey: string; AOk: Boolean; const AText: string);
begin
  FLinesKey := AKey;
  FLinesOk := AOk;
  FLinesText := AText;
  ShowSelected;
end;

procedure TAtlasEvalDetailPanel.InvalidateLines;
begin
  FLinesKey := '';
  FLinesText := '';
end;

procedure TAtlasEvalDetailPanel.PinNode(ANode: TAtlasEvalNode);
begin
  if (ANode <> nil) and (ANode.Expression <> '') and Assigned(FHooks.Pin) then
  begin
    FHooks.Pin(ANode);
  end;
end;

procedure TAtlasEvalDetailPanel.ModifyNode(ANode: TAtlasEvalNode);
begin
  if (ANode <> nil) and FModifyButton.Enabled and Assigned(FHooks.Modify) then
  begin
    FHooks.Modify(ANode);
  end;
end;

class function TAtlasEvalDetailPanel.DetailText(ANode: TAtlasEvalNode; AView: TAtlasEvalView;
  ALinesOk: Boolean; const ALines: string; out AUnfit: Boolean): string;
begin
  AUnfit := False;
  if ANode = nil then
  begin
    Result := TAtlasEvaluateStrings.Text(TAtlasEvaluateTextId.DebugEvaluateNoSelection);
  end
  else if ANode.State <> TAtlasEvalState.Value then
  begin
    Result := StateDetail(ANode);
  end
  else if AView <> TAtlasEvalView.Lines then
  begin
    AUnfit := not TAtlasEvalText.Render(ANode.Value, AView, Result);
  end
  else if ALinesOk then
  begin
    AUnfit := not TAtlasEvalText.Render(ALines, AView, Result);
  end
  else
  begin
    AUnfit := True;
    Result := LinesFailedDetail(ANode, ALines);
  end;
end;

end.
