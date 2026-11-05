unit Atlas.UI.Debug.EvaluateFrame;

// Inhalt des Fensters „Auswerten“ (#784), reine VCL: oben das Eingabefeld
// (Enter fügt den Ausdruck als Zeile an, Strg+Enter heftet ihn fest, Pfeil
// nach unten im leeren Feld zeigt den Verlauf) und „Nebenwirkungen erlauben“.
// Darunter der Baum der Ausdrücke aus TAtlasEvalList: „Name = Wert“, Objekte,
// Records und Arrays klappen auf (beim ersten Aufklappen holt die IDE-Schicht
// die Felder, Hooks.Expand), seit dem letzten Halt geänderte Werte stehen in der
// Warnfarbe, festgeheftete fett, Fehler grau. Entf entfernt eine Zeile,
// Strg+Enter heftet fest bzw. löst, F2 ändert. Unten die Ansicht des
// gewählten Werts (Text mit sichtbaren Steuerzeichen, Zeilen einer TStrings,
// JSON, Hex), „Ändern …“, „Festheften“ und „IDE-Dialog“, darunter die
// Tastenhilfe. Die Zeilen-Ansicht braucht den Wert von „Ausdruck.Text“: Die
// IDE-Schicht wertet ihn auf Hooks.Lines aus und reicht ihn mit SetLines zurück.
// Die Farben kommen aus dem Stil des Baums, hell wie dunkel. Die DFM ist
// leer, weil TCustomFrame.Create für abgeleitete Frames eine Ressource
// verlangt; aufgebaut wird im Code (Bauroutinen im Implementationsteil).

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

  /// <summary>Was der Frame an die IDE-Schicht meldet; nicht gesetzte Einträge bleiben still.</summary>
  TAtlasEvalFrameHooks = record
    /// <summary>Enter im Eingabefeld: Ausdruck als Zeile anfügen.</summary>
    Add: TProc<string>;
    /// <summary>Knoten festheften bzw. lösen (Wurzel) oder seinen Ausdruck als festgeheftete Zeile anlegen (Kind).
    /// </summary>
    Pin: TAtlasEvalNodeProc;
    /// <summary>Strg+Enter im Eingabefeld.</summary>
    PinExpression: TProc<string>;
    /// <summary>Entf: ganze Zeile entfernen (immer die Wurzel).</summary>
    Delete: TAtlasEvalNodeProc;
    /// <summary>Erstes Aufklappen: Felder holen, danach Refresh.</summary>
    Expand: TAtlasEvalNodeProc;
    Modify: TAtlasEvalNodeProc;
    /// <summary>Zeilen-Ansicht: „Ausdruck.Text“ auswerten und mit SetLines zurückreichen.</summary>
    Lines: TAtlasEvalNodeProc;
    History: TFunc<TArray<string>>;
    SideEffects: TProc<Boolean>;
    IdeDialog: TProc;
  end;

  /// <summary>Steuerelemente des Frames; alle gehören dem Frame.</summary>
  TAtlasEvalFrameParts = record
    Top: TPanel;
    Input: TEdit;
    SideEffectsCheck: TCheckBox;
    Tree: TTreeView;
    Splitter: TSplitter;
    Bottom: TPanel;
    Bar: TPanel;
    ViewButtons: array[TAtlasEvalView] of TSpeedButton;
    ModifyButton: TButton;
    PinButton: TButton;
    IdeDialogButton: TButton;
    Detail: TMemo;
    Keys: TLabel;
    HistoryMenu: TPopupMenu;
  end;

  /// <summary>Zustand zwischen zwei Refresh.</summary>
  TAtlasEvalFrameState = record
    List: TAtlasEvalList;
    // Schlüssel und Darstellung je Baumknoten: Knoten der Liste können zwischen zwei Refresh freigegeben sein.
    Sync: TAtlasEvalTreeSync;
    Shown: TAtlasEvalDetailInput;
    View: TAtlasEvalView;
    Filling: Boolean;
    // Wert von „.Text“ für die Zeilen-Ansicht und der Knoten, zu dem er gehört.
    LinesKey: string;
    LinesOk: Boolean;
    LinesText: string;
  end;

  TAtlasDebugEvaluateFrame = class(TFrame)
  private
    FParts: TAtlasEvalFrameParts;
    FState: TAtlasEvalFrameState;
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
    procedure Resize; override;
  public
    /// <summary>Meldungen an die IDE-Schicht.</summary>
    Hooks: TAtlasEvalFrameHooks;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
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
    /// <summary>Inhalt der Ansicht unten; AUnfit: Ansicht passt nicht, gezeigt wird der Text.</summary>
    class function DetailText(ANode: TAtlasEvalNode; AView: TAtlasEvalView; ALinesOk: Boolean;
      const ALines: string; out AUnfit: Boolean): string; static;
    /// <summary>Eingabefeld, Baum, Ansicht und Knöpfe (für Tests und die IDE-Schicht).</summary>
    property Parts: TAtlasEvalFrameParts read FParts;
    property View: TAtlasEvalView read FState.View;
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
  cViewTexts: array[TAtlasEvalView] of TAtlasDebugTextId = (TAtlasDebugTextId.DebugEvaluateViewText,
    TAtlasDebugTextId.DebugEvaluateViewLines, TAtlasDebugTextId.DebugEvaluateViewJson,
      TAtlasDebugTextId.DebugEvaluateViewHex);

type
  /// <summary>Was eine Taste im Baum auslöst.</summary>
  TTreeKeyAction = (KeyNone, KeyDelete, KeyPin, KeyModify);

{ Aufbau }

function Scaled(ASelf: TAtlasDebugEvaluateFrame; AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, ASelf.CurrentPPI, 96);
end;

function AddPanel(ASelf: TAtlasDebugEvaluateFrame; AParent: TWinControl; AAlign: TAlign;
  AHeight: Integer): TPanel;
begin
  Result := TPanel.Create(ASelf);
  Result.Parent := AParent;
  Result.Align := AAlign;
  Result.BevelOuter := bvNone;
  Result.ShowCaption := False;
  Result.ParentBackground := True;
  Result.Height := Scaled(ASelf, AHeight);
end;

/// <summary>Reihenfolge nebeneinander ausgerichteter Teile: Die VCL ordnet sie nach Left. Neue Teile haben alle
/// Left 0; ohne eigene Werte hängt die Reihenfolge davon ab, wie die VCL Gleichstände auflöst (vorher standen die
/// Ansichten verkehrt herum und „IDE-Dialog“ links statt rechts).</summary>
function OrderLeft(APosition: Integer): Integer;
begin
  Result := 10000 + APosition;
end;

function AddButton(ASelf: TAtlasDebugEvaluateFrame; AParent: TWinControl; AText: TAtlasDebugTextId;
  AClick: TNotifyEvent; APosition: Integer): TButton;
begin
  Result := TButton.Create(ASelf);
  Result.Parent := AParent;
  Result.Left := OrderLeft(APosition);
  Result.Align := alRight;
  Result.AlignWithMargins := True;
  Result.Width := Scaled(ASelf, 86);
  Result.Caption := TAtlasDebugStrings.Text(AText);
  Result.OnClick := AClick;
end;

/// <summary>Oben: Eingabefeld und „Nebenwirkungen erlauben“, dazu das Verlaufsmenü.</summary>
procedure BuildTop(ASelf: TAtlasDebugEvaluateFrame);
begin
  ASelf.FParts.Top := AddPanel(ASelf, ASelf, alTop, 30);

  ASelf.FParts.SideEffectsCheck := TCheckBox.Create(ASelf);
  ASelf.FParts.SideEffectsCheck.Parent := ASelf.FParts.Top;
  ASelf.FParts.SideEffectsCheck.Align := alRight;
  ASelf.FParts.SideEffectsCheck.AlignWithMargins := True;
  ASelf.FParts.SideEffectsCheck.Width := Scaled(ASelf, 170);
  ASelf.FParts.SideEffectsCheck.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEvaluateSideEffects);
  ASelf.FParts.SideEffectsCheck.Checked := False;
  ASelf.FParts.SideEffectsCheck.OnClick := ASelf.SideEffectsClick;

  ASelf.FParts.Input := TEdit.Create(ASelf);
  ASelf.FParts.Input.Parent := ASelf.FParts.Top;
  ASelf.FParts.Input.Align := alClient;
  ASelf.FParts.Input.AlignWithMargins := True;
  ASelf.FParts.Input.TextHint := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEvaluateInputHint);
  ASelf.FParts.Input.OnKeyDown := ASelf.InputKeyDown;

  ASelf.FParts.HistoryMenu := TPopupMenu.Create(ASelf);
end;

/// <summary>Ganz unten die Tastenhilfe. Die Höhe setzt FitKeys bei jeder Größenänderung: Mit AutoSize rechnet
/// TLabel sie nur bei Text- und Schriftwechsel aus, hier also bei der Anfangsbreite von 65 Pixeln (viele Zeilen),
/// und behält sie, wenn das Fenster breiter wird. Der Rest blieb als leerer Streifen unten stehen, Baum und Ansicht
/// wuchsen nicht mit.</summary>
procedure BuildKeys(ASelf: TAtlasDebugEvaluateFrame);
begin
  ASelf.FParts.Keys := TLabel.Create(ASelf);
  ASelf.FParts.Keys.Parent := ASelf;
  ASelf.FParts.Keys.AutoSize := False;
  ASelf.FParts.Keys.Align := alBottom;
  ASelf.FParts.Keys.AlignWithMargins := True;
  ASelf.FParts.Keys.ShowAccelChar := False;
  ASelf.FParts.Keys.WordWrap := True;
  ASelf.FParts.Keys.Font.Color := clGrayText;
  ASelf.FParts.Keys.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEvaluateKeys);
end;

/// <summary>Höhe der Tastenhilfe für ihre jetzige Breite (Zeilen umbrochen wie beim Zeichnen).</summary>
procedure FitKeys(ASelf: TAtlasDebugEvaluateFrame);
var
  mKeys: TLabel;
  mRect: TRect;
begin
  mKeys := ASelf.FParts.Keys;
  if (mKeys = nil) or not ASelf.HandleAllocated or (mKeys.Width <= 0) then
  begin
    Exit;
  end;
  mRect := Rect(0, 0, mKeys.Width, 0);
  mKeys.Canvas.Font := mKeys.Font;
  DrawText(mKeys.Canvas.Handle, PChar(mKeys.Caption), -1, mRect, DT_CALCRECT or DT_WORDBREAK or DT_NOPREFIX);
  if mKeys.Height <> mRect.Height then
  begin
    mKeys.Height := mRect.Height;
  end;
end;

function AddViewButton(ASelf: TAtlasDebugEvaluateFrame; AKind: TAtlasEvalView): TSpeedButton;
begin
  Result := TSpeedButton.Create(ASelf);
  Result.Parent := ASelf.FParts.Bar;
  Result.Left := OrderLeft(Ord(AKind));
  Result.Align := alLeft;
  Result.AlignWithMargins := True;
  Result.Width := Scaled(ASelf, 54);
  Result.GroupIndex := 1;
  Result.AllowAllUp := False;
  Result.Caption := TAtlasDebugStrings.Text(cViewTexts[AKind]);
  Result.Tag := Ord(AKind);
  Result.Down := AKind = ASelf.FState.View;
  Result.OnClick := ASelf.ViewClick;
end;

/// <summary>Leiste über der Ansicht: von rechts IDE-Dialog, Festheften, Ändern; links die Ansichten.</summary>
procedure BuildBar(ASelf: TAtlasDebugEvaluateFrame);
var
  mKind: TAtlasEvalView;
begin
  ASelf.FParts.Bar := AddPanel(ASelf, ASelf.FParts.Bottom, alTop, 28);
  ASelf.FParts.ModifyButton := AddButton(ASelf, ASelf.FParts.Bar, TAtlasDebugTextId.DebugEvaluateModify,
    ASelf.ModifyClick, 0);
  ASelf.FParts.PinButton := AddButton(ASelf, ASelf.FParts.Bar, TAtlasDebugTextId.DebugEvaluatePin, ASelf.PinClick, 1);
  ASelf.FParts.IdeDialogButton := AddButton(ASelf, ASelf.FParts.Bar, TAtlasDebugTextId.DebugEvaluateIdeDialog,
    ASelf.IdeDialogClick, 2);
  for mKind := Low(TAtlasEvalView) to High(TAtlasEvalView) do
  begin
    ASelf.FParts.ViewButtons[mKind] := AddViewButton(ASelf, mKind);
  end;
end;

/// <summary>Unten die Leiste und die Ansicht des gewählten Werts, darüber der Teiler.</summary>
procedure BuildBottom(ASelf: TAtlasDebugEvaluateFrame);
begin
  ASelf.FParts.Bottom := AddPanel(ASelf, ASelf, alBottom, 150);
  BuildBar(ASelf);

  ASelf.FParts.Detail := TMemo.Create(ASelf);
  ASelf.FParts.Detail.Parent := ASelf.FParts.Bottom;
  ASelf.FParts.Detail.Align := alClient;
  ASelf.FParts.Detail.AlignWithMargins := True;
  ASelf.FParts.Detail.ReadOnly := True;
  ASelf.FParts.Detail.ScrollBars := ssBoth;
  ASelf.FParts.Detail.WordWrap := False;
  ASelf.FParts.Detail.Font.Name := 'Consolas';

  ASelf.FParts.Splitter := TSplitter.Create(ASelf);
  ASelf.FParts.Splitter.Parent := ASelf;
  ASelf.FParts.Splitter.Height := Scaled(ASelf, 4);
  // Erst über die Ansicht stellen, dann ausrichten: sonst landet der Teiler unter ihr.
  ASelf.FParts.Splitter.Top := ASelf.FParts.Bottom.Top - ASelf.FParts.Splitter.Height;
  ASelf.FParts.Splitter.Align := alBottom;
end;

procedure BuildTree(ASelf: TAtlasDebugEvaluateFrame);
begin
  ASelf.FParts.Tree := TTreeView.Create(ASelf);
  ASelf.FParts.Tree.Parent := ASelf;
  ASelf.FParts.Tree.Align := alClient;
  ASelf.FParts.Tree.AlignWithMargins := True;
  ASelf.FParts.Tree.ReadOnly := True;
  ASelf.FParts.Tree.HideSelection := False;
  ASelf.FParts.Tree.OnKeyDown := ASelf.TreeKeyDown;
  ASelf.FParts.Tree.OnExpanding := ASelf.TreeExpanding;
  ASelf.FParts.Tree.OnCollapsing := ASelf.TreeCollapsing;
  ASelf.FParts.Tree.OnChange := ASelf.TreeChange;
  ASelf.FParts.Tree.OnCustomDrawItem := ASelf.TreeCustomDrawItem;
end;

{ Knoten }

function NodeOf(ASelf: TAtlasDebugEvaluateFrame; ATreeNode: TTreeNode): TAtlasEvalNode;
var
  mKey: string;
begin
  // Über den Schlüssel: nil, wenn es den Knoten nicht mehr gibt.
  Result := nil;
  mKey := ASelf.FState.Sync.KeyOf(ATreeNode);
  if (mKey <> '') and (ASelf.FState.List <> nil) then
  begin
    Result := ASelf.FState.List.Find(mKey);
  end;
end;

procedure SyncTree(ASelf: TAtlasDebugEvaluateFrame);
var
  mKeep: string;
begin
  mKeep := ASelf.FState.Sync.KeyOf(ASelf.FParts.Tree.Selected);
  ASelf.FState.Filling := True;
  try
    ASelf.FState.Sync.Sync(ASelf.FState.List);
  finally
    ASelf.FState.Filling := False;
  end;
  // Wurde der gewählte Knoten ersetzt (Teile eines neuen Werts), denselben Schlüssel wieder wählen.
  if (mKeep <> '') and (ASelf.FState.Sync.KeyOf(ASelf.FParts.Tree.Selected) <> mKeep) then
  begin
    ASelf.Select(mKeep);
  end;
end;

{ Ansicht und Knöpfe }

/// <summary>Text eines Knotens ohne Wert: wird ausgewertet, nicht angehalten, Fehlermeldung.</summary>
function StateDetail(ANode: TAtlasEvalNode): string;
begin
  case ANode.State of
    TAtlasEvalState.Pending:
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEvaluatePending);
    TAtlasEvalState.Unavailable:
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEvaluateNotStopped);
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
    Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugEvaluateLinesFailed,
      [TAtlasEvalText.FieldExpression(ANode.Expression, 'Text'), ALines]) + sLineBreak + sLineBreak + Result;
  end;
end;

/// <summary>Zeilen-Ansicht: Wert von „.Text“ fehlt noch. Anfragen, bis dahin „wird ausgewertet“; True, wenn
/// angefragt.</summary>
function RequestLines(ASelf: TAtlasDebugEvaluateFrame; ANode: TAtlasEvalNode): Boolean;
begin
  Result := (ANode.Expression <> '') and Assigned(ASelf.Hooks.Lines);
  if Result then
  begin
    ASelf.FState.LinesKey := ANode.Key;
    ASelf.FState.LinesOk := False;
    ASelf.FState.LinesText := '';
    ASelf.FState.Shown.Valid := False;
    ASelf.FParts.Detail.Text := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEvaluatePending);
    ASelf.Hooks.Lines(ANode);
  end;
end;

procedure ShowDetail(ASelf: TAtlasDebugEvaluateFrame; ANode: TAtlasEvalNode; AOk: Boolean; const ALines: string);
var
  mText: string;
  mUnfit: Boolean;
  mInput: TAtlasEvalDetailInput;
begin
  // Refresh kommt nach jeder Zeitscheibe der Auswertung: nur rechnen, wenn sich das Gezeigte ändert.
  mInput := TAtlasEvalDetailInput.ForNode(ANode, ASelf.FState.View, AOk, ALines);
  if mInput.Same(ASelf.FState.Shown) then
  begin
    Exit;
  end;
  ASelf.FState.Shown := mInput;
  mText := TAtlasDebugEvaluateFrame.DetailText(ANode, ASelf.FState.View, AOk, ALines, mUnfit);
  if mUnfit and (ASelf.FState.View <> TAtlasEvalView.Lines) then
  begin
    mText := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEvaluateViewUnfit) + sLineBreak + sLineBreak + mText;
  end;
  ASelf.FParts.Detail.Text := mText;
end;

procedure UpdateDetail(ASelf: TAtlasDebugEvaluateFrame);
var
  mNode: TAtlasEvalNode;
  mNeedsLines: Boolean;
begin
  mNode := ASelf.Selected;
  mNeedsLines := (mNode <> nil) and (ASelf.FState.View = TAtlasEvalView.Lines) and
    (mNode.State = TAtlasEvalState.Value);
  if mNeedsLines and (mNode.Key = ASelf.FState.LinesKey) then
  begin
    ShowDetail(ASelf, mNode, ASelf.FState.LinesOk, ASelf.FState.LinesText);
  end
  else if not (mNeedsLines and RequestLines(ASelf, mNode)) then
  begin
    ShowDetail(ASelf, mNode, False, '');
  end;
end;

procedure UpdateButtons(ASelf: TAtlasDebugEvaluateFrame);
var
  mNode: TAtlasEvalNode;
  mHasExpression: Boolean;
begin
  mNode := ASelf.Selected;
  mHasExpression := (mNode <> nil) and (mNode.Expression <> '');
  ASelf.FParts.ModifyButton.Enabled := mHasExpression and (mNode.State = TAtlasEvalState.Value) and
    Assigned(ASelf.Hooks.Modify);
  ASelf.FParts.PinButton.Enabled := mHasExpression;
  if (mNode <> nil) and (mNode.Parent = nil) and mNode.Pinned then
  begin
    ASelf.FParts.PinButton.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEvaluateUnpin);
  end
  else
  begin
    ASelf.FParts.PinButton.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEvaluatePin);
  end;
  ASelf.FParts.IdeDialogButton.Enabled := Assigned(ASelf.Hooks.IdeDialog);
end;

function TreeColor(ASelf: TAtlasDebugEvaluateFrame; AColor: TColor): TColor;
begin
  // Stil des Baums, nicht der globale: Die IDE themt ihre Fenster je Formular.
  Result := ColorToRGB(StyleServices(ASelf.FParts.Tree).GetSystemColor(AColor));
end;

{ Tasten }

/// <summary>Eingabefeld: Enter fügt an, Strg+Enter heftet fest (beide leeren das Feld).</summary>
procedure SubmitInput(ASelf: TAtlasDebugEvaluateFrame; const AHook: TProc<string>);
var
  mText: string;
begin
  mText := Trim(ASelf.FParts.Input.Text);
  if (mText <> '') and Assigned(AHook) then
  begin
    ASelf.FParts.Input.Text := '';
    AHook(mText);
  end;
end;

function TreeKeyAction(AKey: Word; AShift: TShiftState): TTreeKeyAction;
begin
  Result := TTreeKeyAction.KeyNone;
  if (AKey = VK_DELETE) and (AShift = []) then
  begin
    Result := TTreeKeyAction.KeyDelete;
  end
  else if (AKey = VK_RETURN) and (AShift = [ssCtrl]) then
  begin
    Result := TTreeKeyAction.KeyPin;
  end
  else if (AKey = VK_F2) and (AShift = []) then
  begin
    Result := TTreeKeyAction.KeyModify;
  end;
end;

/// <summary>Entf: nur ganze Zeilen; Felder gehören zum Ausdruck.</summary>
procedure DeleteRow(ASelf: TAtlasDebugEvaluateFrame; ANode: TAtlasEvalNode);
var
  mRoot: TAtlasEvalNode;
begin
  mRoot := ANode;
  while mRoot.Parent <> nil do
  begin
    mRoot := mRoot.Parent;
  end;
  if Assigned(ASelf.Hooks.Delete) then
  begin
    ASelf.Hooks.Delete(mRoot);
  end;
end;

procedure PinRow(ASelf: TAtlasDebugEvaluateFrame; ANode: TAtlasEvalNode);
begin
  if (ANode <> nil) and (ANode.Expression <> '') and Assigned(ASelf.Hooks.Pin) then
  begin
    ASelf.Hooks.Pin(ANode);
  end;
end;

procedure ModifyRow(ASelf: TAtlasDebugEvaluateFrame; ANode: TAtlasEvalNode);
begin
  if (ANode <> nil) and ASelf.FParts.ModifyButton.Enabled and Assigned(ASelf.Hooks.Modify) then
  begin
    ASelf.Hooks.Modify(ANode);
  end;
end;

procedure RunTreeKey(ASelf: TAtlasDebugEvaluateFrame; AAction: TTreeKeyAction; ANode: TAtlasEvalNode);
begin
  case AAction of
    TTreeKeyAction.KeyDelete:
      DeleteRow(ASelf, ANode);
    TTreeKeyAction.KeyPin:
      PinRow(ASelf, ANode);
    TTreeKeyAction.KeyModify:
      ModifyRow(ASelf, ANode);
    TTreeKeyAction.KeyNone: ;
  end;
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
    mMenuItem.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEvaluateHistoryEmpty);
    mMenuItem.Enabled := False;
    AMenu.Items.Add(mMenuItem);
  end;
end;

{ TAtlasDebugEvaluateFrame }

constructor TAtlasDebugEvaluateFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Der Name aus der DFM stört, wenn mehrere Frames denselben Besitzer haben.
  Name := '';
  FState.View := TAtlasEvalView.Text;
  // Reihenfolge zählt: Unten ausgerichtete Teile stapeln sich von unten nach oben, der Baum füllt den Rest.
  BuildTop(Self);
  BuildKeys(Self);
  BuildBottom(Self);
  BuildTree(Self);
  FState.Sync := TAtlasEvalTreeSync.Create(FParts.Tree);
  UpdateButtons(Self);
end;

destructor TAtlasDebugEvaluateFrame.Destroy;
begin
  // Der Baum entsteht und vergeht als Komponente des Frames: Beim Löschen seiner Knoten im inherited darf er nicht
  // mehr nach FState.Sync fragen.
  if FParts.Tree <> nil then
  begin
    FParts.Tree.OnChange := nil;
    FParts.Tree.OnExpanding := nil;
    FParts.Tree.OnCollapsing := nil;
    FParts.Tree.OnCustomDrawItem := nil;
  end;
  FreeAndNil(FState.Sync);
  inherited Destroy;
end;

procedure TAtlasDebugEvaluateFrame.CreateWnd;
begin
  inherited CreateWnd;
  FitKeys(Self);
  // TTreeView.Items braucht ein Fenster.
  Refresh;
end;

procedure TAtlasDebugEvaluateFrame.Resize;
begin
  inherited Resize;
  // Breiter oder schmaler: Die Tastenhilfe braucht weniger oder mehr Zeilen, Baum und Ansicht bekommen den Rest.
  FitKeys(Self);
end;

procedure TAtlasDebugEvaluateFrame.SetList(AList: TAtlasEvalList);
begin
  FState.List := AList;
  FState.LinesKey := '';
  Refresh;
end;

procedure TAtlasDebugEvaluateFrame.Refresh;
begin
  if HandleAllocated then
  begin
    SyncTree(Self);
  end;
  UpdateButtons(Self);
  UpdateDetail(Self);
end;

function TAtlasDebugEvaluateFrame.Selected: TAtlasEvalNode;
begin
  Result := nil;
  if HandleAllocated then
  begin
    Result := NodeOf(Self, FParts.Tree.Selected);
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
  mItem := FState.Sync.ItemOf(AKey);
  if mItem <> nil then
  begin
    FParts.Tree.Selected := mItem;
  end;
end;

class function TAtlasDebugEvaluateFrame.DetailText(ANode: TAtlasEvalNode; AView: TAtlasEvalView;
  ALinesOk: Boolean; const ALines: string; out AUnfit: Boolean): string;
begin
  AUnfit := False;
  if ANode = nil then
  begin
    Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEvaluateNoSelection);
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

procedure TAtlasDebugEvaluateFrame.SetLines(const AKey: string; AOk: Boolean; const AText: string);
begin
  FState.LinesKey := AKey;
  FState.LinesOk := AOk;
  FState.LinesText := AText;
  UpdateDetail(Self);
end;

procedure TAtlasDebugEvaluateFrame.InvalidateLines;
begin
  FState.LinesKey := '';
  FState.LinesText := '';
end;

procedure TAtlasDebugEvaluateFrame.SetSideEffects(AValue: Boolean);
var
  mHandler: TNotifyEvent;
begin
  mHandler := FParts.SideEffectsCheck.OnClick;
  FParts.SideEffectsCheck.OnClick := nil;
  try
    FParts.SideEffectsCheck.Checked := AValue;
  finally
    FParts.SideEffectsCheck.OnClick := mHandler;
  end;
end;

procedure TAtlasDebugEvaluateFrame.SetView(AView: TAtlasEvalView);
begin
  FState.View := AView;
  FParts.ViewButtons[AView].Down := True;
  // Neu fragen: „.Text“ kann sich seit dem letzten Mal geändert haben.
  FState.LinesKey := '';
  UpdateDetail(Self);
end;

procedure TAtlasDebugEvaluateFrame.FocusInput(const AExpression: string);
begin
  if AExpression <> '' then
  begin
    FParts.Input.Text := AExpression;
    FParts.Input.SelectAll;
  end;
  if FParts.Input.CanFocus and FParts.Input.Showing then
  begin
    FParts.Input.SetFocus;
  end;
end;

procedure TAtlasDebugEvaluateFrame.ShowHistory;
var
  mItems: TArray<string>;
  mPlace: TPoint;
begin
  mItems := nil;
  if Assigned(Hooks.History) then
  begin
    mItems := Hooks.History();
  end;
  FillHistory(FParts.HistoryMenu, mItems, HistoryClick);
  mPlace := FParts.Input.ClientToScreen(System.Types.Point(0, FParts.Input.Height));
  FParts.HistoryMenu.Popup(mPlace.X, mPlace.Y);
end;

procedure TAtlasDebugEvaluateFrame.HistoryClick(Sender: TObject);
begin
  if Sender is TMenuItem then
  begin
    FocusInput(TMenuItem(Sender).Hint);
  end;
end;

procedure TAtlasDebugEvaluateFrame.TreeCustomDrawItem(Sender: TCustomTreeView; Node: TTreeNode;
  State: TCustomDrawState; var DefaultDraw: Boolean);
var
  mInfo: TAtlasEvalItemInfo;
  mCanvas: TCanvas;
begin
  DefaultDraw := True;
  mCanvas := Sender.Canvas;
  // Darstellung steht am Baumknoten (FState.Sync): Zeichnen sucht nicht in der Liste.
  mInfo := FState.Sync.InfoOf(Node);
  mCanvas.Font.Style := [];
  if mInfo.Bold then
  begin
    mCanvas.Font.Style := [fsBold];
  end;
  if cdsSelected in State then
  begin
    mCanvas.Brush.Color := TreeColor(Self, clHighlight);
    mCanvas.Font.Color := TreeColor(Self, clHighlightText);
    Exit;
  end;
  mCanvas.Brush.Color := TreeColor(Self, FParts.Tree.Color);
  case mInfo.Look of
    TAtlasEvalLook.Changed:
      mCanvas.Font.Color := ColorToRGB(TColor(TAtlasColors.ForBackground(TAtlasColor(ColorToRGB(
        mCanvas.Brush.Color))).Warn));
    TAtlasEvalLook.Gray:
      mCanvas.Font.Color := TreeColor(Self, clGrayText);
  else
    mCanvas.Font.Color := TreeColor(Self, FParts.Tree.Font.Color);
  end;
end;

procedure TAtlasDebugEvaluateFrame.InputKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_RETURN) and (Shift = []) then
  begin
    Key := 0;
    SubmitInput(Self, Hooks.Add);
  end
  else if (Key = VK_RETURN) and (Shift = [ssCtrl]) then
  begin
    Key := 0;
    SubmitInput(Self, Hooks.PinExpression);
  end
  else if (Key = VK_DOWN) and (Shift = []) and (FParts.Input.Text = '') then
  begin
    Key := 0;
    ShowHistory;
  end;
end;

procedure TAtlasDebugEvaluateFrame.TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  mNode: TAtlasEvalNode;
  mAction: TTreeKeyAction;
begin
  mNode := Selected;
  mAction := TreeKeyAction(Key, Shift);
  if (mNode <> nil) and (mAction <> TTreeKeyAction.KeyNone) then
  begin
    Key := 0;
    RunTreeKey(Self, mAction, mNode);
  end;
end;

procedure TAtlasDebugEvaluateFrame.TreeExpanding(Sender: TObject; Node: TTreeNode; var AllowExpansion: Boolean);
var
  mEvalNode: TAtlasEvalNode;
begin
  AllowExpansion := True;
  mEvalNode := NodeOf(Self, Node);
  if FState.Filling or (mEvalNode = nil) then
  begin
    Exit;
  end;
  mEvalNode.Expanded := True;
  if not mEvalNode.ChildrenLoaded and Assigned(Hooks.Expand) then
  begin
    // Felder kommen später; Refresh baut dann mit aufgeklapptem Knoten neu auf. Hooks.Expand darf Refresh nicht
    // sofort rufen: Der Baum steckt noch in der Benachrichtigung für diesen Knoten.
    AllowExpansion := False;
    Hooks.Expand(mEvalNode);
  end;
end;

procedure TAtlasDebugEvaluateFrame.TreeCollapsing(Sender: TObject; Node: TTreeNode; var AllowCollapse: Boolean);
var
  mEvalNode: TAtlasEvalNode;
begin
  AllowCollapse := True;
  mEvalNode := NodeOf(Self, Node);
  if not FState.Filling and (mEvalNode <> nil) then
  begin
    mEvalNode.Expanded := False;
  end;
end;

procedure TAtlasDebugEvaluateFrame.TreeChange(Sender: TObject; Node: TTreeNode);
begin
  if FState.Filling then
  begin
    Exit;
  end;
  UpdateButtons(Self);
  UpdateDetail(Self);
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
  ModifyRow(Self, Selected);
end;

procedure TAtlasDebugEvaluateFrame.PinClick(Sender: TObject);
begin
  PinRow(Self, Selected);
end;

procedure TAtlasDebugEvaluateFrame.IdeDialogClick(Sender: TObject);
begin
  if Assigned(Hooks.IdeDialog) then
  begin
    Hooks.IdeDialog();
  end;
end;

procedure TAtlasDebugEvaluateFrame.SideEffectsClick(Sender: TObject);
begin
  if Assigned(Hooks.SideEffects) then
  begin
    Hooks.SideEffects(FParts.SideEffectsCheck.Checked);
  end;
end;

end.
