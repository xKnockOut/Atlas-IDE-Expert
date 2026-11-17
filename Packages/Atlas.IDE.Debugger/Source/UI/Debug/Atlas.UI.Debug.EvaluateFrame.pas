unit Atlas.UI.Debug.EvaluateFrame;

// Inhalt des Fensters „Auswerten“ (#784), reine VCL: oben die Eingabezeile
// (TAtlasEvalInputBar), darunter der Baum der Ausdrücke aus TAtlasEvalList:
// „Name = Wert“, Objekte, Records und Arrays klappen auf (beim ersten
// Aufklappen holt die IDE-Schicht die Felder, Hooks.Expand), seit dem letzten
// Halt geänderte Werte stehen in der Warnfarbe, festgeheftete fett, Fehler
// grau. Entf entfernt eine Zeile, Strg+Enter heftet fest bzw. löst, F2 ändert.
// Unten die Ansicht des gewählten Werts mit ihrer Leiste
// (TAtlasEvalDetailPanel), darunter die Tastenhilfe. Der Frame hält den Baum
// und sagt den Teilen, welcher Knoten gewählt ist. Die Farben kommen aus dem
// Stil des Baums, hell wie dunkel. Die DFM ist leer, weil TCustomFrame.Create
// für abgeleitete Frames eine Ressource verlangt; aufgebaut wird im Code.

interface

uses
  System.Classes,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.Forms,
  Atlas.Core.Debug.Evaluate,
  Atlas.UI.Debug.EvaluateTreeView,
  Atlas.UI.Debug.EvaluatePanels;

type
  TAtlasDebugEvaluateFrame = class(TFrame)
  private
    FHooks: TAtlasEvalFrameHooks;
    FInputBar: TAtlasEvalInputBar;
    FView: TAtlasEvalTreeView;
    FDetail: TAtlasEvalDetailPanel;
    FKeys: TLabel;
    procedure BuildKeys;
    procedure BuildSplitter;
    procedure BuildTree;
    /// <summary>Höhe der Tastenhilfe für ihre jetzige Breite (Zeilen umbrochen wie beim Zeichnen).</summary>
    procedure FitKeys;
    /// <summary>Entf: nur ganze Zeilen; Felder gehören zum Ausdruck.</summary>
    procedure DeleteRow(ANode: TAtlasEvalNode);
    procedure TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure TreeChange(Sender: TObject; Node: TTreeNode);
    function GetTree: TTreeView;
  protected
    procedure CreateWnd; override;
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Liste, die der Baum zeigt; gehört der IDE-Schicht.</summary>
    procedure SetList(AList: TAtlasEvalList);
    /// <summary>Nach jeder Änderung der Liste: Baum neu aufbauen, wenn sich Zeilen geändert haben, sonst nur Texte.
    /// </summary>
    procedure Refresh;
    /// <summary>Gewählter Knoten; nil ohne Auswahl.</summary>
    function Selected: TAtlasEvalNode;
    /// <summary>Knoten mit AKey wählen.</summary>
    procedure Select(const AKey: string);
    /// <summary>Meldungen an die IDE-Schicht.</summary>
    property Hooks: TAtlasEvalFrameHooks read FHooks;
    /// <summary>Eingabefeld und „Nebenwirkungen erlauben“.</summary>
    property InputBar: TAtlasEvalInputBar read FInputBar;
    property Tree: TTreeView read GetTree;
    /// <summary>Ansicht des gewählten Werts mit ihren Knöpfen.</summary>
    property Detail: TAtlasEvalDetailPanel read FDetail;
    property Keys: TLabel read FKeys;
  end;

implementation

uses
  System.SysUtils,
  Winapi.Windows,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.ExtCtrls,
  Atlas.UI.Debug.Evaluate.Strings,
  Atlas.UI.Foundation.WrapLabel;

{$R *.dfm}

const
  /// <summary>Höhe des Teilers über der Ansicht bei 96 dpi.</summary>
  cSplitterHeight = 4;

type
  /// <summary>Was eine Taste im Baum auslöst.</summary>
  TTreeKeyAction = (KeyNone, KeyDelete, KeyPin, KeyModify);

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

{ TAtlasDebugEvaluateFrame }

constructor TAtlasDebugEvaluateFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Der Name aus der DFM stört, wenn mehrere Frames denselben Besitzer haben.
  Name := '';
  FHooks := TAtlasEvalFrameHooks.Create;
  // Reihenfolge zählt: Unten ausgerichtete Teile stapeln sich von unten nach oben, der Baum füllt den Rest.
  FInputBar := TAtlasEvalInputBar.CreateIn(Self, FHooks);
  BuildKeys;
  FDetail := TAtlasEvalDetailPanel.CreateIn(Self, FHooks, Selected);
  BuildSplitter;
  BuildTree;
  FDetail.UpdateButtons;
end;

destructor TAtlasDebugEvaluateFrame.Destroy;
begin
  // Der Baum entsteht und vergeht als Komponente des Frames: Beim Löschen seiner Knoten im inherited darf er nicht
  // mehr hierher und zu FView fragen.
  if FView <> nil then
  begin
    FView.Tree.OnChange := nil;
  end;
  FreeAndNil(FView);
  // Eingabezeile und Ansicht vergehen erst im inherited; beim Freigeben melden sie nichts mehr.
  FreeAndNil(FHooks);
  inherited Destroy;
end;

/// <summary>Ganz unten die Tastenhilfe. Die Höhe setzt FitKeys bei jeder Größenänderung: Mit AutoSize rechnet
/// TLabel sie nur bei Text- und Schriftwechsel aus, hier also bei der Anfangsbreite von 65 Pixeln (viele Zeilen),
/// und behält sie, wenn das Fenster breiter wird. Der Rest blieb als leerer Streifen unten stehen, Baum und Ansicht
/// wuchsen nicht mit.</summary>
procedure TAtlasDebugEvaluateFrame.BuildKeys;
begin
  FKeys := TAtlasWrapLabel.Create(Self);
  FKeys.Parent := Self;
  FKeys.AutoSize := False;
  FKeys.Align := alBottom;
  FKeys.AlignWithMargins := True;
  FKeys.ShowAccelChar := False;
  FKeys.Font.Color := clGrayText;
  FKeys.Caption := TAtlasEvaluateStrings.Text(TAtlasEvaluateTextId.DebugEvaluateKeys);
end;

/// <summary>Teiler über der Ansicht.</summary>
procedure TAtlasDebugEvaluateFrame.BuildSplitter;
var
  mSplitter: TSplitter;
begin
  mSplitter := TSplitter.Create(Self);
  mSplitter.Parent := Self;
  mSplitter.Height := MulDiv(cSplitterHeight, CurrentPPI, 96);
  // Erst über die Ansicht stellen, dann ausrichten: sonst landet der Teiler unter ihr.
  mSplitter.Top := FDetail.Top - mSplitter.Height;
  mSplitter.Align := alBottom;
end;

procedure TAtlasDebugEvaluateFrame.BuildTree;
var
  mTree: TTreeView;
begin
  mTree := TTreeView.Create(Self);
  mTree.Parent := Self;
  mTree.Align := alClient;
  mTree.AlignWithMargins := True;
  mTree.ReadOnly := True;
  mTree.HideSelection := False;
  mTree.OnKeyDown := TreeKeyDown;
  mTree.OnChange := TreeChange;
  FView := TAtlasEvalTreeView.Create(mTree);
  FView.OnExpand :=
    procedure(ANode: TAtlasEvalNode)
    begin
      if Assigned(FHooks.Expand) then
      begin
        FHooks.Expand(ANode);
      end;
    end;
end;

function TAtlasDebugEvaluateFrame.GetTree: TTreeView;
begin
  Result := FView.Tree;
end;

procedure TAtlasDebugEvaluateFrame.FitKeys;
var
  mRect: TRect;
begin
  if (FKeys = nil) or not HandleAllocated or (FKeys.Width <= 0) then
  begin
    Exit;
  end;
  mRect := Rect(0, 0, FKeys.Width, 0);
  FKeys.Canvas.Font := FKeys.Font;
  DrawText(FKeys.Canvas.Handle, PChar(FKeys.Caption), -1, mRect, DT_CALCRECT or DT_WORDBREAK or DT_NOPREFIX);
  if FKeys.Height <> mRect.Height then
  begin
    FKeys.Height := mRect.Height;
  end;
  // Eine Höhenänderung kann sie über die Ansicht schieben; die Tastenhilfe bleibt ganz unten.
  if FKeys.Top < FDetail.Top then
  begin
    FKeys.Top := ClientHeight;
  end;
end;

procedure TAtlasDebugEvaluateFrame.DeleteRow(ANode: TAtlasEvalNode);
var
  mRoot: TAtlasEvalNode;
begin
  mRoot := ANode;
  while mRoot.Parent <> nil do
  begin
    mRoot := mRoot.Parent;
  end;
  if Assigned(FHooks.Delete) then
  begin
    FHooks.Delete(mRoot);
  end;
end;

procedure TAtlasDebugEvaluateFrame.CreateWnd;
begin
  inherited CreateWnd;
  FitKeys;
  // TTreeView.Items braucht ein Fenster.
  Refresh;
end;

procedure TAtlasDebugEvaluateFrame.Resize;
begin
  inherited Resize;
  // Breiter oder schmaler: Die Tastenhilfe braucht weniger oder mehr Zeilen, Baum und Ansicht bekommen den Rest.
  FitKeys;
end;

procedure TAtlasDebugEvaluateFrame.TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  mNode: TAtlasEvalNode;
  mAction: TTreeKeyAction;
begin
  mNode := Selected;
  mAction := TreeKeyAction(Key, Shift);
  if (mNode = nil) or (mAction = TTreeKeyAction.KeyNone) then
  begin
    Exit;
  end;
  Key := 0;
  case mAction of
    TTreeKeyAction.KeyDelete:
      DeleteRow(mNode);
    TTreeKeyAction.KeyPin:
      FDetail.PinNode(mNode);
    TTreeKeyAction.KeyModify:
      FDetail.ModifyNode(mNode);
    TTreeKeyAction.KeyNone: ;
  end;
end;

procedure TAtlasDebugEvaluateFrame.TreeChange(Sender: TObject; Node: TTreeNode);
begin
  if FView.Filling then
  begin
    Exit;
  end;
  FDetail.UpdateButtons;
  FDetail.ShowSelected;
end;

procedure TAtlasDebugEvaluateFrame.SetList(AList: TAtlasEvalList);
begin
  FView.List := AList;
  FDetail.InvalidateLines;
  Refresh;
end;

procedure TAtlasDebugEvaluateFrame.Refresh;
begin
  if HandleAllocated then
  begin
    FView.Refresh;
  end;
  FDetail.UpdateButtons;
  FDetail.ShowSelected;
end;

function TAtlasDebugEvaluateFrame.Selected: TAtlasEvalNode;
begin
  Result := FView.SelectedNode;
end;

procedure TAtlasDebugEvaluateFrame.Select(const AKey: string);
begin
  if not HandleAllocated then
  begin
    Exit;
  end;
  FView.Select(AKey);
end;

end.
