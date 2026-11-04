unit Atlas.UI.Debug.EvaluateFrame;

// Inhalt des Fensters „Auswerten“ (#784), reine VCL: oben das Eingabefeld
// (Enter fügt den Ausdruck als Zeile an, Strg+Enter heftet ihn fest, Pfeil
// nach unten im leeren Feld zeigt den Verlauf) und „Nebenwirkungen erlauben“.
// Darunter der Baum der Ausdrücke aus TAtlasEvalList: „Name = Wert“, Objekte,
// Records und Arrays klappen auf (beim ersten Aufklappen holt die IDE-Schicht
// die Felder, OnExpand), seit dem letzten Halt geänderte Werte stehen in der
// Warnfarbe, festgeheftete fett, Fehler grau. Entf entfernt eine Zeile,
// Strg+Enter heftet fest bzw. löst, F2 ändert. Unten die Ansicht des
// gewählten Werts (Text mit sichtbaren Steuerzeichen, Zeilen einer TStrings,
// JSON, Hex), „Ändern …“, „Festheften“ und „IDE-Dialog“, darunter die
// Tastenhilfe. Die Zeilen-Ansicht braucht den Wert von „Ausdruck.Text“: Die
// IDE-Schicht wertet ihn auf OnLines aus und reicht ihn mit SetLines zurück.
// Die Farben kommen aus dem Stil des Baums, hell wie dunkel. Die DFM ist
// leer, weil TCustomFrame.Create für abgeleitete Frames eine Ressource
// verlangt; aufgebaut wird im Code.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Buttons,
  Vcl.ComCtrls,
  Vcl.Menus,
  Vcl.Forms,
  Atlas.Core.Debug.Evaluate,
  Atlas.UI.Debug.EvaluateTree;

type
  TAtlasEvalNodeProc = reference to procedure(ANode: TAtlasEvalNode);

  TAtlasDebugEvaluateFrame = class(TFrame)
  private
    FTop: TPanel;
    FInput: TEdit;
    FSideEffects: TCheckBox;
    FTree: TTreeView;
    FSplitter: TSplitter;
    FBottom: TPanel;
    FBar: TPanel;
    FViewButtons: array[TAtlasEvalView] of TSpeedButton;
    FModify: TButton;
    FPin: TButton;
    FIdeDialog: TButton;
    FDetail: TMemo;
    FKeys: TLabel;
    FHistoryMenu: TPopupMenu;
    FList: TAtlasEvalList;
    // Schlüssel und Darstellung je Baumknoten: Knoten der Liste können zwischen zwei Refresh freigegeben sein.
    FSync: TAtlasEvalTreeSync;
    FShown: TAtlasEvalDetailInput;
    FView: TAtlasEvalView;
    FFilling: Boolean;
    FLinesKey: string;
    FLinesOk: Boolean;
    FLinesText: string;
    FOnAdd: TProc<string>;
    FOnPin: TAtlasEvalNodeProc;
    FOnPinExpression: TProc<string>;
    FOnDelete: TAtlasEvalNodeProc;
    FOnExpand: TAtlasEvalNodeProc;
    FOnModify: TAtlasEvalNodeProc;
    FOnLines: TAtlasEvalNodeProc;
    FOnHistory: TFunc<TArray<string>>;
    FOnSideEffects: TProc<Boolean>;
    FOnIdeDialog: TProc;
    function AddButton(AParent: TWinControl; const ACaption: string; AClick: TNotifyEvent): TButton;
    procedure BuildTop;
    procedure AddViewButtons;
    procedure BuildTree;
    function NodeOf(ATreeNode: TTreeNode): TAtlasEvalNode;
    procedure SyncTree;
    procedure UpdateButtons;
    procedure UpdateDetail;
    function TreeColor(AColor: TColor): TColor;
    procedure InputKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure TreeExpanding(Sender: TObject; Node: TTreeNode; var AllowExpansion: Boolean);
    procedure TreeCollapsing(Sender: TObject; Node: TTreeNode; var AllowCollapse: Boolean);
    procedure TreeChange(Sender: TObject; Node: TTreeNode);
    procedure TreeCustomDrawItem(Sender: TCustomTreeView; Node: TTreeNode; State: TCustomDrawState;
      var DefaultDraw: Boolean);
    procedure ViewClick(Sender: TObject);
    procedure ModifyClick(Sender: TObject);
    procedure PinClick(Sender: TObject);
    procedure IdeDialogClick(Sender: TObject);
    procedure SideEffectsClick(Sender: TObject);
    procedure HistoryClick(Sender: TObject);
  protected
    procedure CreateWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Liste, die der Baum zeigt; gehört der IDE-Schicht.</summary>
    procedure SetList(AList: TAtlasEvalList);
    /// <summary>Nach jeder Änderung der Liste: Baum abgleichen (nur geänderte Zeilen), Knöpfe und Ansicht.</summary>
    procedure Refresh;
    /// <summary>Wert von „Ausdruck.Text“ für die Zeilen-Ansicht des Knotens mit AKey.</summary>
    procedure SetLines(const AKey: string; AOk: Boolean; const AText: string);
    /// <summary>Neuer Halt: „.Text“ für die Zeilen-Ansicht neu fragen.</summary>
    procedure InvalidateLines;
    procedure SetSideEffects(AValue: Boolean);
    /// <summary>Ausdruck ins Eingabefeld (Strg+F7 mit Bezeichner unter dem Cursor) und Fokus dorthin.</summary>
    procedure FocusInput(const AExpression: string);
    /// <summary>Gewählter Knoten; nil ohne Auswahl.</summary>
    function Selected: TAtlasEvalNode;
    /// <summary>Knoten mit AKey wählen.</summary>
    procedure Select(const AKey: string);
    /// <summary>Verlaufsmenü unter dem Eingabefeld zeigen (Pfeil nach unten im leeren Feld).</summary>
    procedure ShowHistory;
    procedure SetView(AView: TAtlasEvalView);
    /// <summary>Inhalt der Ansicht unten; AUnfit: Ansicht passt nicht, gezeigt wird der Text.</summary>
    class function DetailText(ANode: TAtlasEvalNode; AView: TAtlasEvalView; ALinesOk: Boolean;
      const ALines: string; out AUnfit: Boolean): string; static;
    property Input: TEdit read FInput;
    property SideEffectsCheck: TCheckBox read FSideEffects;
    property Tree: TTreeView read FTree;
    property Detail: TMemo read FDetail;
    property ModifyButton: TButton read FModify;
    property PinButton: TButton read FPin;
    property IdeDialogButton: TButton read FIdeDialog;
    property HistoryMenu: TPopupMenu read FHistoryMenu;
    property View: TAtlasEvalView read FView;
    property OnAdd: TProc<string> read FOnAdd write FOnAdd;
    /// <summary>Knoten festheften bzw. lösen (Wurzel) oder seinen Ausdruck als festgeheftete Zeile anlegen (Kind).
    /// </summary>
    property OnPin: TAtlasEvalNodeProc read FOnPin write FOnPin;
    /// <summary>Strg+Enter im Eingabefeld.</summary>
    property OnPinExpression: TProc<string> read FOnPinExpression write FOnPinExpression;
    property OnDelete: TAtlasEvalNodeProc read FOnDelete write FOnDelete;
    property OnExpand: TAtlasEvalNodeProc read FOnExpand write FOnExpand;
    property OnModify: TAtlasEvalNodeProc read FOnModify write FOnModify;
    property OnLines: TAtlasEvalNodeProc read FOnLines write FOnLines;
    property OnHistory: TFunc<TArray<string>> read FOnHistory write FOnHistory;
    property OnSideEffects: TProc<Boolean> read FOnSideEffects write FOnSideEffects;
    property OnIdeDialog: TProc read FOnIdeDialog write FOnIdeDialog;
  end;

implementation

uses
  System.UITypes,
  Winapi.Windows,
  System.Types,
  Vcl.Themes,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.UI.Strings,
  Atlas.UI.Debug.Strings;

{$R *.dfm}

const
  ViewTexts: array[TAtlasEvalView] of TAtlasDebugTextId = (TAtlasDebugTextId.DebugEvaluateViewText,
    TAtlasDebugTextId.DebugEvaluateViewLines, TAtlasDebugTextId.DebugEvaluateViewJson,
      TAtlasDebugTextId.DebugEvaluateViewHex);

{ TAtlasDebugEvaluateFrame }

constructor TAtlasDebugEvaluateFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Der Name aus der DFM stört, wenn mehrere Frames denselben Besitzer haben.
  Name := '';
  FView := TAtlasEvalView.Text;
  BuildTop;
  FHistoryMenu := TPopupMenu.Create(Self);

  FKeys := TLabel.Create(Self);
  FKeys.Parent := Self;
  FKeys.Align := alBottom;
  FKeys.AlignWithMargins := True;
  FKeys.ShowAccelChar := False;
  FKeys.WordWrap := True;
  FKeys.Font.Color := clGrayText;
  FKeys.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEvaluateKeys);

  FBottom := TPanel.Create(Self);
  FBottom.Parent := Self;
  FBottom.Align := alBottom;
  FBottom.BevelOuter := bvNone;
  FBottom.ShowCaption := False;
  FBottom.ParentBackground := True;
  FBottom.Height := MulDiv(150, CurrentPPI, 96);

  FBar := TPanel.Create(Self);
  FBar.Parent := FBottom;
  FBar.Align := alTop;
  FBar.BevelOuter := bvNone;
  FBar.ShowCaption := False;
  FBar.ParentBackground := True;
  FBar.Height := MulDiv(28, CurrentPPI, 96);

  // Von rechts: IDE-Dialog, Festheften, Ändern; links die Ansichten.
  FIdeDialog := AddButton(FBar, TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEvaluateIdeDialog), IdeDialogClick);
  FPin := AddButton(FBar, TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEvaluatePin), PinClick);
  FModify := AddButton(FBar, TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEvaluateModify), ModifyClick);
  AddViewButtons;

  FDetail := TMemo.Create(Self);
  FDetail.Parent := FBottom;
  FDetail.Align := alClient;
  FDetail.AlignWithMargins := True;
  FDetail.ReadOnly := True;
  FDetail.ScrollBars := ssBoth;
  FDetail.WordWrap := False;
  FDetail.Font.Name := 'Consolas';

  FSplitter := TSplitter.Create(Self);
  FSplitter.Parent := Self;
  FSplitter.Height := MulDiv(4, CurrentPPI, 96);
  // Erst über die Ansicht stellen, dann ausrichten: sonst landet der Teiler unter ihr.
  FSplitter.Top := FBottom.Top - FSplitter.Height;
  FSplitter.Align := alBottom;
  BuildTree;
  FSync := TAtlasEvalTreeSync.Create(FTree);
  UpdateButtons;
end;

procedure TAtlasDebugEvaluateFrame.BuildTop;
begin
  FTop := TPanel.Create(Self);
  FTop.Parent := Self;
  FTop.Align := alTop;
  FTop.BevelOuter := bvNone;
  FTop.ShowCaption := False;
  FTop.ParentBackground := True;
  FTop.Height := MulDiv(30, CurrentPPI, 96);

  FSideEffects := TCheckBox.Create(Self);
  FSideEffects.Parent := FTop;
  FSideEffects.Align := alRight;
  FSideEffects.AlignWithMargins := True;
  FSideEffects.Width := MulDiv(170, CurrentPPI, 96);
  FSideEffects.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEvaluateSideEffects);
  FSideEffects.Checked := False;
  FSideEffects.OnClick := SideEffectsClick;

  FInput := TEdit.Create(Self);
  FInput.Parent := FTop;
  FInput.Align := alClient;
  FInput.AlignWithMargins := True;
  FInput.TextHint := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEvaluateInputHint);
  FInput.OnKeyDown := InputKeyDown;
end;

procedure TAtlasDebugEvaluateFrame.AddViewButtons;
var
  mKind: TAtlasEvalView;
  mButton: TSpeedButton;
begin
  for mKind := High(TAtlasEvalView) downto Low(TAtlasEvalView) do
  begin
    mButton := TSpeedButton.Create(Self);
    mButton.Parent := FBar;
    mButton.Align := alLeft;
    mButton.AlignWithMargins := True;
    mButton.Width := MulDiv(54, CurrentPPI, 96);
    mButton.GroupIndex := 1;
    mButton.AllowAllUp := False;
    mButton.Caption := TAtlasDebugStrings.Text(ViewTexts[mKind]);
    mButton.Tag := Ord(mKind);
    mButton.Down := mKind = FView;
    mButton.OnClick := ViewClick;
    FViewButtons[mKind] := mButton;
  end;
end;

procedure TAtlasDebugEvaluateFrame.BuildTree;
begin
  FTree := TTreeView.Create(Self);
  FTree.Parent := Self;
  FTree.Align := alClient;
  FTree.AlignWithMargins := True;
  FTree.ReadOnly := True;
  FTree.HideSelection := False;
  FTree.OnKeyDown := TreeKeyDown;
  FTree.OnExpanding := TreeExpanding;
  FTree.OnCollapsing := TreeCollapsing;
  FTree.OnChange := TreeChange;
  FTree.OnCustomDrawItem := TreeCustomDrawItem;
end;

destructor TAtlasDebugEvaluateFrame.Destroy;
begin
  // Der Baum entsteht und vergeht als Komponente des Frames: Beim Löschen seiner Knoten im inherited darf er nicht
  // mehr nach FSync fragen.
  if FTree <> nil then
  begin
    FTree.OnChange := nil;
    FTree.OnExpanding := nil;
    FTree.OnCollapsing := nil;
    FTree.OnCustomDrawItem := nil;
  end;
  FreeAndNil(FSync);
  inherited Destroy;
end;

procedure TAtlasDebugEvaluateFrame.CreateWnd;
begin
  inherited CreateWnd;
  // TTreeView.Items braucht ein Fenster.
  Refresh;
end;

function TAtlasDebugEvaluateFrame.AddButton(AParent: TWinControl; const ACaption: string;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Align := alRight;
  Result.AlignWithMargins := True;
  Result.Width := MulDiv(86, CurrentPPI, 96);
  Result.Caption := ACaption;
  Result.OnClick := AClick;
end;

procedure TAtlasDebugEvaluateFrame.SetList(AList: TAtlasEvalList);
begin
  FList := AList;
  FLinesKey := '';
  Refresh;
end;

function TAtlasDebugEvaluateFrame.NodeOf(ATreeNode: TTreeNode): TAtlasEvalNode;
var
  mKey: string;
begin
  // Über den Schlüssel: nil, wenn es den Knoten nicht mehr gibt.
  Result := nil;
  mKey := FSync.KeyOf(ATreeNode);
  if (mKey <> '') and (FList <> nil) then
  begin
    Result := FList.Find(mKey);
  end;
end;

procedure TAtlasDebugEvaluateFrame.SyncTree;
var
  mKeep: string;
begin
  mKeep := FSync.KeyOf(FTree.Selected);
  FFilling := True;
  try
    FSync.Sync(FList);
  finally
    FFilling := False;
  end;
  // Wurde der gewählte Knoten ersetzt (Teile eines neuen Werts), denselben Schlüssel wieder wählen.
  if (mKeep <> '') and (FSync.KeyOf(FTree.Selected) <> mKeep) then
  begin
    Select(mKeep);
  end;
end;

procedure TAtlasDebugEvaluateFrame.Refresh;
begin
  if HandleAllocated then
  begin
    SyncTree;
  end;
  UpdateButtons;
  UpdateDetail;
end;

function TAtlasDebugEvaluateFrame.Selected: TAtlasEvalNode;
begin
  Result := nil;
  if HandleAllocated then
  begin
    Result := NodeOf(FTree.Selected);
  end;
end;

procedure TAtlasDebugEvaluateFrame.Select(const AKey: string);
var
  mItem: TTreeNode;
begin
  if not HandleAllocated then
  begin
    Exit;
  end;
  mItem := FSync.ItemOf(AKey);
  if mItem <> nil then
  begin
    FTree.Selected := mItem;
  end;
end;

class function TAtlasDebugEvaluateFrame.DetailText(ANode: TAtlasEvalNode; AView: TAtlasEvalView;
  ALinesOk: Boolean; const ALines: string; out AUnfit: Boolean): string;
var
  Source: string;
begin
  AUnfit := False;
  if ANode = nil then
  begin
    Exit(TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEvaluateNoSelection));
  end;
  case ANode.State of
    TAtlasEvalState.Pending:
      Exit(TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEvaluatePending));
    TAtlasEvalState.Unavailable:
      Exit(TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEvaluateNotStopped));
    TAtlasEvalState.Error:
      Exit(ANode.Value);
    TAtlasEvalState.Value: ;
  end;
  Source := ANode.Value;
  if AView = TAtlasEvalView.Lines then
  begin
    if not ALinesOk then
    begin
      AUnfit := True;
      TAtlasEvalText.Render(ANode.Value, TAtlasEvalView.Text, Result);
      if ALines <> '' then
      begin
        Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugEvaluateLinesFailed,
          [TAtlasEvalText.FieldExpression(ANode.Expression, 'Text'), ALines]) + sLineBreak + sLineBreak + Result;
      end;
      Exit;
    end;
    Source := ALines;
  end;
  AUnfit := not TAtlasEvalText.Render(Source, AView, Result);
end;

procedure TAtlasDebugEvaluateFrame.UpdateDetail;
var
  Node: TAtlasEvalNode;
  Text: string;
  Unfit, Ok: Boolean;
  Lines: string;
  mInput: TAtlasEvalDetailInput;
begin
  Node := Selected;
  Ok := False;
  Lines := '';
  if (Node <> nil) and (FView = TAtlasEvalView.Lines) and (Node.State = TAtlasEvalState.Value) then
  begin
    if Node.Key = FLinesKey then
    begin
      Ok := FLinesOk;
      Lines := FLinesText;
    end
    else if (Node.Expression <> '') and Assigned(FOnLines) then
    begin
      // Wert von „.Text“ fehlt noch: anfragen, bis dahin „wird ausgewertet“.
      FLinesKey := Node.Key;
      FLinesOk := False;
      FLinesText := '';
      FShown.Valid := False;
      FDetail.Text := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEvaluatePending);
      FOnLines(Node);
      Exit;
    end;
  end;
  // Refresh kommt nach jeder Zeitscheibe der Auswertung: nur rechnen, wenn sich das Gezeigte ändert.
  mInput := TAtlasEvalDetailInput.ForNode(Node, FView, Ok, Lines);
  if mInput.Same(FShown) then
  begin
    Exit;
  end;
  FShown := mInput;
  Text := DetailText(Node, FView, Ok, Lines, Unfit);
  if Unfit and (FView <> TAtlasEvalView.Lines) then
  begin
    Text := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEvaluateViewUnfit) + sLineBreak + sLineBreak + Text;
  end;
  FDetail.Text := Text;
end;

procedure TAtlasDebugEvaluateFrame.SetLines(const AKey: string; AOk: Boolean; const AText: string);
begin
  FLinesKey := AKey;
  FLinesOk := AOk;
  FLinesText := AText;
  UpdateDetail;
end;

procedure TAtlasDebugEvaluateFrame.InvalidateLines;
begin
  FLinesKey := '';
  FLinesText := '';
end;

procedure TAtlasDebugEvaluateFrame.UpdateButtons;
var
  Node: TAtlasEvalNode;
begin
  Node := Selected;
  FModify.Enabled := (Node <> nil) and (Node.Expression <> '') and (Node.State = TAtlasEvalState.Value) and
    Assigned(FOnModify);
  FPin.Enabled := (Node <> nil) and (Node.Expression <> '');
  if (Node <> nil) and (Node.Parent = nil) and Node.Pinned then
  begin
    FPin.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEvaluateUnpin);
  end
  else
  begin
    FPin.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEvaluatePin);
  end;
  FIdeDialog.Enabled := Assigned(FOnIdeDialog);
end;

procedure TAtlasDebugEvaluateFrame.SetSideEffects(AValue: Boolean);
var
  Handler: TNotifyEvent;
begin
  Handler := FSideEffects.OnClick;
  FSideEffects.OnClick := nil;
  try
    FSideEffects.Checked := AValue;
  finally
    FSideEffects.OnClick := Handler;
  end;
end;

procedure TAtlasDebugEvaluateFrame.SetView(AView: TAtlasEvalView);
begin
  FView := AView;
  FViewButtons[AView].Down := True;
  // Neu fragen: „.Text“ kann sich seit dem letzten Mal geändert haben.
  FLinesKey := '';
  UpdateDetail;
end;

procedure TAtlasDebugEvaluateFrame.FocusInput(const AExpression: string);
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

procedure TAtlasDebugEvaluateFrame.ShowHistory;
var
  Items: TArray<string>;
  Item: string;
  MenuItem: TMenuItem;
  Place: TPoint;
begin
  Items := nil;
  if Assigned(FOnHistory) then
  begin
    Items := FOnHistory();
  end;
  FHistoryMenu.Items.Clear;
  for Item in Items do
  begin
    MenuItem := TMenuItem.Create(FHistoryMenu);
    // & im Ausdruck (&Begin, Escape von Schlüsselwörtern) nicht als Tastenkürzel lesen.
    MenuItem.Caption := StringReplace(Item, '&', '&&', [rfReplaceAll]);
    MenuItem.Hint := Item;
    MenuItem.OnClick := HistoryClick;
    FHistoryMenu.Items.Add(MenuItem);
  end;
  if FHistoryMenu.Items.Count = 0 then
  begin
    MenuItem := TMenuItem.Create(FHistoryMenu);
    MenuItem.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEvaluateHistoryEmpty);
    MenuItem.Enabled := False;
    FHistoryMenu.Items.Add(MenuItem);
  end;
  Place := FInput.ClientToScreen(System.Types.Point(0, FInput.Height));
  FHistoryMenu.Popup(Place.X, Place.Y);
end;

procedure TAtlasDebugEvaluateFrame.HistoryClick(Sender: TObject);
begin
  if Sender is TMenuItem then
  begin
    FocusInput(TMenuItem(Sender).Hint);
  end;
end;

function TAtlasDebugEvaluateFrame.TreeColor(AColor: TColor): TColor;
begin
  // Stil des Baums, nicht der globale: Die IDE themt ihre Fenster je Formular.
  Result := ColorToRGB(StyleServices(FTree).GetSystemColor(AColor));
end;

procedure TAtlasDebugEvaluateFrame.TreeCustomDrawItem(Sender: TCustomTreeView; Node: TTreeNode;
  State: TCustomDrawState; var DefaultDraw: Boolean);
var
  mInfo: TAtlasEvalItemInfo;
  mCanvas: TCanvas;
begin
  DefaultDraw := True;
  mCanvas := Sender.Canvas;
  // Darstellung steht am Baumknoten (FSync): Zeichnen sucht nicht in der Liste.
  mInfo := FSync.InfoOf(Node);
  mCanvas.Font.Style := [];
  if mInfo.Bold then
  begin
    mCanvas.Font.Style := [fsBold];
  end;
  if cdsSelected in State then
  begin
    mCanvas.Brush.Color := TreeColor(clHighlight);
    mCanvas.Font.Color := TreeColor(clHighlightText);
    Exit;
  end;
  mCanvas.Brush.Color := TreeColor(FTree.Color);
  case mInfo.Look of
    TAtlasEvalLook.Changed:
      mCanvas.Font.Color := ColorToRGB(TColor(TAtlasColors.ForBackground(TAtlasColor(ColorToRGB(
        mCanvas.Brush.Color))).Warn));
    TAtlasEvalLook.Gray:
      mCanvas.Font.Color := TreeColor(clGrayText);
  else
    mCanvas.Font.Color := TreeColor(FTree.Font.Color);
  end;
end;

procedure TAtlasDebugEvaluateFrame.InputKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  Text: string;
begin
  Text := Trim(FInput.Text);
  if (Key = VK_RETURN) and (Shift = []) then
  begin
    Key := 0;
    if (Text <> '') and Assigned(FOnAdd) then
    begin
      FInput.Text := '';
      FOnAdd(Text);
    end;
  end
  else if (Key = VK_RETURN) and (Shift = [ssCtrl]) then
  begin
    Key := 0;
    if (Text <> '') and Assigned(FOnPinExpression) then
    begin
      FInput.Text := '';
      FOnPinExpression(Text);
    end;
  end
  else if (Key = VK_DOWN) and (Shift = []) and (FInput.Text = '') then
  begin
    Key := 0;
    ShowHistory;
  end;
end;

procedure TAtlasDebugEvaluateFrame.TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  Node: TAtlasEvalNode;
begin
  Node := Selected;
  if Node = nil then
  begin
    Exit;
  end;
  if (Key = VK_DELETE) and (Shift = []) then
  begin
    Key := 0;
    // Nur ganze Zeilen; Felder gehören zum Ausdruck.
    while Node.Parent <> nil do
    begin
      Node := Node.Parent;
    end;
    if Assigned(FOnDelete) then
    begin
      FOnDelete(Node);
    end;
  end
  else if (Key = VK_RETURN) and (Shift = [ssCtrl]) then
  begin
    Key := 0;
    if (Node.Expression <> '') and Assigned(FOnPin) then
    begin
      FOnPin(Node);
    end;
  end
  else if (Key = VK_F2) and (Shift = []) then
  begin
    Key := 0;
    if FModify.Enabled and Assigned(FOnModify) then
    begin
      FOnModify(Node);
    end;
  end;
end;

procedure TAtlasDebugEvaluateFrame.TreeExpanding(Sender: TObject; Node: TTreeNode; var AllowExpansion: Boolean);
var
  EvalNode: TAtlasEvalNode;
begin
  AllowExpansion := True;
  EvalNode := NodeOf(Node);
  if FFilling or (EvalNode = nil) then
  begin
    Exit;
  end;
  EvalNode.Expanded := True;
  if not EvalNode.ChildrenLoaded and Assigned(FOnExpand) then
  begin
    // Felder kommen später; Refresh baut dann mit aufgeklapptem Knoten neu auf. OnExpand darf Refresh nicht
    // sofort rufen: Der Baum steckt noch in der Benachrichtigung für diesen Knoten.
    AllowExpansion := False;
    FOnExpand(EvalNode);
  end;
end;

procedure TAtlasDebugEvaluateFrame.TreeCollapsing(Sender: TObject; Node: TTreeNode; var AllowCollapse: Boolean);
begin
  AllowCollapse := True;
  if not FFilling and (NodeOf(Node) <> nil) then
  begin
    NodeOf(Node).Expanded := False;
  end;
end;

procedure TAtlasDebugEvaluateFrame.TreeChange(Sender: TObject; Node: TTreeNode);
begin
  if FFilling then
  begin
    Exit;
  end;
  UpdateButtons;
  UpdateDetail;
end;

procedure TAtlasDebugEvaluateFrame.ViewClick(Sender: TObject);
begin
  if Sender is TSpeedButton then
  begin
    SetView(TAtlasEvalView(TSpeedButton(Sender).Tag));
  end;
end;

procedure TAtlasDebugEvaluateFrame.ModifyClick(Sender: TObject);
begin
  if FModify.Enabled and (Selected <> nil) and Assigned(FOnModify) then
  begin
    FOnModify(Selected);
  end;
end;

procedure TAtlasDebugEvaluateFrame.PinClick(Sender: TObject);
begin
  if (Selected <> nil) and (Selected.Expression <> '') and Assigned(FOnPin) then
  begin
    FOnPin(Selected);
  end;
end;

procedure TAtlasDebugEvaluateFrame.IdeDialogClick(Sender: TObject);
begin
  if Assigned(FOnIdeDialog) then
  begin
    FOnIdeDialog();
  end;
end;

procedure TAtlasDebugEvaluateFrame.SideEffectsClick(Sender: TObject);
begin
  if Assigned(FOnSideEffects) then
  begin
    FOnSideEffects(FSideEffects.Checked);
  end;
end;

end.
