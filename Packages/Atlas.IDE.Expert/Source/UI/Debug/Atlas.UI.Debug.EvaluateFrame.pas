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
  Atlas.Core.Debug.Evaluate;

type
  TAtlasEvalNodeProc = reference to procedure(ANode: TAtlasEvalNode);

  TAtlasDebugEvaluateFrame = class(TFrame)
  public const
    /// <summary>Höchstens so viele Zeichen eines Werts im Baum; der ganze steht unten.</summary>
    MaxTreeValue = 200;
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
    // Schlüssel je Baumknoten (Data = Index + 1): Knoten der Liste können zwischen zwei Refresh freigegeben sein.
    FNodeKeys: TArray<string>;
    FView: TAtlasEvalView;
    FFilling: Boolean;
    FShape: string;
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
    function KeyOf(ATreeNode: TTreeNode): string;
    function NodeOf(ATreeNode: TTreeNode): TAtlasEvalNode;
    function Shape: string;
    procedure Rebuild;
    procedure AddTreeNodes(AParent: TTreeNode; ANode: TAtlasEvalNode);
    procedure UpdateTexts;
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
    /// <summary>Liste, die der Baum zeigt; gehört der IDE-Schicht.</summary>
    procedure SetList(AList: TAtlasEvalList);
    /// <summary>Nach jeder Änderung der Liste: Baum neu aufbauen, wenn sich Zeilen geändert haben, sonst nur Texte.
    /// </summary>
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
    /// <summary>Text im Baum: „Name = Wert“, Wert gekürzt und einzeilig.</summary>
    class function NodeText(ANode: TAtlasEvalNode): string; static;
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
  Winapi.Windows,
  System.Types,
  Vcl.Themes,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.UI.Strings;

{$R *.dfm}

const
  ViewTexts: array[TAtlasEvalView] of TAtlasTextId = (TAtlasTextId.DebugEvaluateViewText,
    TAtlasTextId.DebugEvaluateViewLines, TAtlasTextId.DebugEvaluateViewJson, TAtlasTextId.DebugEvaluateViewHex);

{ TAtlasDebugEvaluateFrame }

constructor TAtlasDebugEvaluateFrame.Create(AOwner: TComponent);
var
  Kind: TAtlasEvalView;
  Button: TSpeedButton;
begin
  inherited Create(AOwner);
  // Der Name aus der DFM stört, wenn mehrere Frames denselben Besitzer haben.
  Name := '';
  FView := TAtlasEvalView.Text;

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
  FSideEffects.Caption := TAtlasStrings.Text(TAtlasTextId.DebugEvaluateSideEffects);
  FSideEffects.Checked := False;
  FSideEffects.OnClick := SideEffectsClick;

  FInput := TEdit.Create(Self);
  FInput.Parent := FTop;
  FInput.Align := alClient;
  FInput.AlignWithMargins := True;
  FInput.TextHint := TAtlasStrings.Text(TAtlasTextId.DebugEvaluateInputHint);
  FInput.OnKeyDown := InputKeyDown;

  FHistoryMenu := TPopupMenu.Create(Self);

  FKeys := TLabel.Create(Self);
  FKeys.Parent := Self;
  FKeys.Align := alBottom;
  FKeys.AlignWithMargins := True;
  FKeys.ShowAccelChar := False;
  FKeys.WordWrap := True;
  FKeys.Font.Color := clGrayText;
  FKeys.Caption := TAtlasStrings.Text(TAtlasTextId.DebugEvaluateKeys);

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
  FIdeDialog := AddButton(FBar, TAtlasStrings.Text(TAtlasTextId.DebugEvaluateIdeDialog), IdeDialogClick);
  FPin := AddButton(FBar, TAtlasStrings.Text(TAtlasTextId.DebugEvaluatePin), PinClick);
  FModify := AddButton(FBar, TAtlasStrings.Text(TAtlasTextId.DebugEvaluateModify), ModifyClick);
  for Kind := High(TAtlasEvalView) downto Low(TAtlasEvalView) do
  begin
    Button := TSpeedButton.Create(Self);
    Button.Parent := FBar;
    Button.Align := alLeft;
    Button.AlignWithMargins := True;
    Button.Width := MulDiv(54, CurrentPPI, 96);
    Button.GroupIndex := 1;
    Button.AllowAllUp := False;
    Button.Caption := TAtlasStrings.Text(ViewTexts[Kind]);
    Button.Tag := Ord(Kind);
    Button.Down := Kind = FView;
    Button.OnClick := ViewClick;
    FViewButtons[Kind] := Button;
  end;

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
  UpdateButtons;
end;

procedure TAtlasDebugEvaluateFrame.CreateWnd;
begin
  inherited CreateWnd;
  // TTreeView.Items braucht ein Fenster.
  FShape := #0;
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
  FShape := #0;
  Refresh;
end;

function TAtlasDebugEvaluateFrame.KeyOf(ATreeNode: TTreeNode): string;
var
  Index: NativeInt;
begin
  Result := '';
  if (ATreeNode = nil) or (ATreeNode.Data = nil) then
    Exit;
  Index := NativeInt(ATreeNode.Data) - 1;
  if (Index >= 0) and (Index <= High(FNodeKeys)) then
    Result := FNodeKeys[Index];
end;

function TAtlasDebugEvaluateFrame.NodeOf(ATreeNode: TTreeNode): TAtlasEvalNode;
var
  Key: string;
begin
  // Über den Schlüssel: nil, wenn es den Knoten nicht mehr gibt.
  Result := nil;
  Key := KeyOf(ATreeNode);
  if (Key <> '') and (FList <> nil) then
    Result := FList.Find(Key);
end;

function TAtlasDebugEvaluateFrame.Shape: string;
var
  Builder: TStringBuilder;

  procedure Walk(ANode: TAtlasEvalNode);
  var
    Index: Integer;
  begin
    Builder.Append(ANode.Key);
    if ANode.ChildrenLoaded then
    begin
      Builder.Append('{');
      for Index := 0 to ANode.ChildCount - 1 do
        Walk(ANode.Children[Index]);
      Builder.Append('}');
    end
    else if ANode.CanExpand then
      Builder.Append('+');
    Builder.Append(#3);
  end;

var
  Index: Integer;
begin
  // Zeilen samt Aufklappbarkeit: Ändert sich das, baut Refresh den Baum neu auf.
  Result := '';
  if FList = nil then
    Exit;
  Builder := TStringBuilder.Create;
  try
    for Index := 0 to FList.Count - 1 do
      Walk(FList.Roots[Index]);
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

procedure TAtlasDebugEvaluateFrame.AddTreeNodes(AParent: TTreeNode; ANode: TAtlasEvalNode);
var
  Item: TTreeNode;
  Index: Integer;
begin
  FNodeKeys := FNodeKeys + [ANode.Key];
  Item := FTree.Items.AddChildObject(AParent, NodeText(ANode), Pointer(NativeInt(Length(FNodeKeys))));
  if ANode.ChildrenLoaded then
  begin
    for Index := 0 to ANode.ChildCount - 1 do
      AddTreeNodes(Item, ANode.Children[Index]);
    if ANode.ChildCount = 0 then
      FTree.Items.AddChildObject(Item, TAtlasStrings.Text(TAtlasTextId.DebugEvaluateNoFields), nil);
  end
  else if ANode.CanExpand then
    // Platzhalter für das Aufklappzeichen; die Felder holt OnExpand.
    FTree.Items.AddChildObject(Item, TAtlasStrings.Text(TAtlasTextId.DebugEvaluatePending), nil);
  if ANode.Expanded and ANode.ChildrenLoaded then
    Item.Expand(False);
end;

procedure TAtlasDebugEvaluateFrame.Rebuild;
var
  Keep: string;
  Index: Integer;
begin
  Keep := KeyOf(FTree.Selected);
  FFilling := True;
  FTree.Items.BeginUpdate;
  try
    FTree.Items.Clear;
    FNodeKeys := nil;
    if FList <> nil then
      for Index := 0 to FList.Count - 1 do
        AddTreeNodes(nil, FList.Roots[Index]);
  finally
    FTree.Items.EndUpdate;
    FFilling := False;
  end;
  if Keep <> '' then
    Select(Keep);
end;

procedure TAtlasDebugEvaluateFrame.UpdateTexts;
var
  Index: Integer;
  Item: TTreeNode;
begin
  for Index := 0 to FTree.Items.Count - 1 do
  begin
    Item := FTree.Items[Index];
    if (NodeOf(Item) <> nil) and (Item.Text <> NodeText(NodeOf(Item))) then
      Item.Text := NodeText(NodeOf(Item));
  end;
  // Farben (geändert, Fehler) hängen nicht am Text.
  FTree.Invalidate;
end;

procedure TAtlasDebugEvaluateFrame.Refresh;
var
  Current: string;
begin
  if HandleAllocated then
  begin
    Current := Shape;
    if Current <> FShape then
    begin
      FShape := Current;
      Rebuild;
    end
    else
      UpdateTexts;
  end;
  UpdateButtons;
  UpdateDetail;
end;

function TAtlasDebugEvaluateFrame.Selected: TAtlasEvalNode;
begin
  Result := nil;
  if HandleAllocated then
    Result := NodeOf(FTree.Selected);
end;

procedure TAtlasDebugEvaluateFrame.Select(const AKey: string);
var
  Index: Integer;
begin
  if not HandleAllocated then
    Exit;
  for Index := 0 to FTree.Items.Count - 1 do
    if KeyOf(FTree.Items[Index]) = AKey then
    begin
      FTree.Selected := FTree.Items[Index];
      Exit;
    end;
end;

class function TAtlasDebugEvaluateFrame.NodeText(ANode: TAtlasEvalNode): string;
var
  Value: string;
begin
  case ANode.State of
    TAtlasEvalState.Pending:
      // Bis zum neuen Wert grau der des letzten Halts: kein Flackern bei jedem Schritt.
      if ANode.Value <> '' then
        Value := ANode.Value
      else
        Value := TAtlasStrings.Text(TAtlasTextId.DebugEvaluatePending);
    TAtlasEvalState.Unavailable:
      Value := TAtlasStrings.Text(TAtlasTextId.DebugEvaluateNotStopped);
  else
    Value := ANode.Value;
  end;
  // Einzeilig und gekürzt; den ganzen Wert zeigt die Ansicht unten.
  Value := StringReplace(StringReplace(Value, #13#10, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]);
  if Length(Value) > MaxTreeValue then
    Value := Copy(Value, 1, MaxTreeValue) + #$2026;
  Result := ANode.Name + ' = ' + Value;
end;

class function TAtlasDebugEvaluateFrame.DetailText(ANode: TAtlasEvalNode; AView: TAtlasEvalView;
  ALinesOk: Boolean; const ALines: string; out AUnfit: Boolean): string;
var
  Source: string;
begin
  AUnfit := False;
  if ANode = nil then
    Exit(TAtlasStrings.Text(TAtlasTextId.DebugEvaluateNoSelection));
  case ANode.State of
    TAtlasEvalState.Pending:
      Exit(TAtlasStrings.Text(TAtlasTextId.DebugEvaluatePending));
    TAtlasEvalState.Unavailable:
      Exit(TAtlasStrings.Text(TAtlasTextId.DebugEvaluateNotStopped));
    TAtlasEvalState.Error:
      Exit(ANode.Value);
  end;
  Source := ANode.Value;
  if AView = TAtlasEvalView.Lines then
  begin
    if not ALinesOk then
    begin
      AUnfit := True;
      TAtlasEvalText.Render(ANode.Value, TAtlasEvalView.Text, Result);
      if ALines <> '' then
        Result := TAtlasStrings.Fmt(TAtlasTextId.DebugEvaluateLinesFailed,
          [TAtlasEvalText.FieldExpression(ANode.Expression, 'Text'), ALines]) + sLineBreak + sLineBreak + Result;
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
      FDetail.Text := TAtlasStrings.Text(TAtlasTextId.DebugEvaluatePending);
      FOnLines(Node);
      Exit;
    end;
  end;
  Text := DetailText(Node, FView, Ok, Lines, Unfit);
  if Unfit and (FView <> TAtlasEvalView.Lines) then
    Text := TAtlasStrings.Text(TAtlasTextId.DebugEvaluateViewUnfit) + sLineBreak + sLineBreak + Text;
  if FDetail.Text <> Text then
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
    FPin.Caption := TAtlasStrings.Text(TAtlasTextId.DebugEvaluateUnpin)
  else
    FPin.Caption := TAtlasStrings.Text(TAtlasTextId.DebugEvaluatePin);
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
  if FInput.CanFocus then
    FInput.SetFocus;
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
    Items := FOnHistory();
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
    MenuItem.Caption := TAtlasStrings.Text(TAtlasTextId.DebugEvaluateHistoryEmpty);
    MenuItem.Enabled := False;
    FHistoryMenu.Items.Add(MenuItem);
  end;
  Place := FInput.ClientToScreen(System.Types.Point(0, FInput.Height));
  FHistoryMenu.Popup(Place.X, Place.Y);
end;

procedure TAtlasDebugEvaluateFrame.HistoryClick(Sender: TObject);
begin
  if Sender is TMenuItem then
    FocusInput(TMenuItem(Sender).Hint);
end;

function TAtlasDebugEvaluateFrame.TreeColor(AColor: TColor): TColor;
begin
  // Stil des Baums, nicht der globale: Die IDE themt ihre Fenster je Formular.
  Result := ColorToRGB(StyleServices(FTree).GetSystemColor(AColor));
end;

procedure TAtlasDebugEvaluateFrame.TreeCustomDrawItem(Sender: TCustomTreeView; Node: TTreeNode;
  State: TCustomDrawState; var DefaultDraw: Boolean);
var
  EvalNode: TAtlasEvalNode;
  Canvas: TCanvas;
begin
  DefaultDraw := True;
  Canvas := Sender.Canvas;
  EvalNode := NodeOf(Node);
  Canvas.Font.Style := [];
  if (EvalNode <> nil) and (EvalNode.Parent = nil) and EvalNode.Pinned then
    Canvas.Font.Style := [fsBold];
  if cdsSelected in State then
  begin
    Canvas.Brush.Color := TreeColor(clHighlight);
    Canvas.Font.Color := TreeColor(clHighlightText);
    Exit;
  end;
  Canvas.Brush.Color := TreeColor(FTree.Color);
  if (EvalNode <> nil) and EvalNode.Changed then
    Canvas.Font.Color := ColorToRGB(TColor(TAtlasColors.ForBackground(TAtlasColor(ColorToRGB(
      Canvas.Brush.Color))).Warn))
  else if (EvalNode = nil) or (EvalNode.State <> TAtlasEvalState.Value) then
    Canvas.Font.Color := TreeColor(clGrayText)
  else
    Canvas.Font.Color := TreeColor(FTree.Font.Color);
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
    Exit;
  if (Key = VK_DELETE) and (Shift = []) then
  begin
    Key := 0;
    // Nur ganze Zeilen; Felder gehören zum Ausdruck.
    while Node.Parent <> nil do
      Node := Node.Parent;
    if Assigned(FOnDelete) then
      FOnDelete(Node);
  end
  else if (Key = VK_RETURN) and (Shift = [ssCtrl]) then
  begin
    Key := 0;
    if (Node.Expression <> '') and Assigned(FOnPin) then
      FOnPin(Node);
  end
  else if (Key = VK_F2) and (Shift = []) then
  begin
    Key := 0;
    if FModify.Enabled then
      FOnModify(Node);
  end;
end;

procedure TAtlasDebugEvaluateFrame.TreeExpanding(Sender: TObject; Node: TTreeNode; var AllowExpansion: Boolean);
var
  EvalNode: TAtlasEvalNode;
begin
  AllowExpansion := True;
  EvalNode := NodeOf(Node);
  if FFilling or (EvalNode = nil) then
    Exit;
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
    NodeOf(Node).Expanded := False;
end;

procedure TAtlasDebugEvaluateFrame.TreeChange(Sender: TObject; Node: TTreeNode);
begin
  if FFilling then
    Exit;
  UpdateButtons;
  UpdateDetail;
end;

procedure TAtlasDebugEvaluateFrame.ViewClick(Sender: TObject);
begin
  if Sender is TSpeedButton then
    SetView(TAtlasEvalView(TSpeedButton(Sender).Tag));
end;

procedure TAtlasDebugEvaluateFrame.ModifyClick(Sender: TObject);
begin
  if FModify.Enabled and (Selected <> nil) then
    FOnModify(Selected);
end;

procedure TAtlasDebugEvaluateFrame.PinClick(Sender: TObject);
begin
  if (Selected <> nil) and (Selected.Expression <> '') and Assigned(FOnPin) then
    FOnPin(Selected);
end;

procedure TAtlasDebugEvaluateFrame.IdeDialogClick(Sender: TObject);
begin
  if Assigned(FOnIdeDialog) then
    FOnIdeDialog();
end;

procedure TAtlasDebugEvaluateFrame.SideEffectsClick(Sender: TObject);
begin
  if Assigned(FOnSideEffects) then
    FOnSideEffects(FSideEffects.Checked);
end;

end.
