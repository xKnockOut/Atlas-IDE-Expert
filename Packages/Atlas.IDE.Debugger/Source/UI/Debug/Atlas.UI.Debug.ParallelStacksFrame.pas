unit Atlas.UI.Debug.ParallelStacksFrame;

// Inhalt des Seitenfensters „Parallele Aufrufstapel“ (#837), reine VCL: oben die Filter „Nur eigener Code“ und
// „Wartend“ und die Statuszeile, darunter der Baum (Wurzeln = Thread-Start, aufgeklappt bis zum obersten Rahmen),
// unten die Threads des gewählten Knotens und die Tastenhinweise. Knoten des aktuellen Threads stehen fett, Knoten,
// in denen alle Threads warten, in der Warnfarbe. Enter oder Doppelklick meldet den Knoten (OnOpen); die Filter
// melden sich über OnFilter. Die IDE-Schicht ruft nach jedem Halt SetTree. Die DFM ist leer; aufgebaut wird im
// Code, gefüllt erst mit Fenster (CreateWnd).

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Vcl.Forms,
  Atlas.Core.Debug.Threads,
  Atlas.Core.Debug.ParallelStacks;

type
  TAtlasDebugParallelStacksFrame = class(TFrame)
  private
    FOwnOnly: TCheckBox;
    FWaitingOnly: TCheckBox;
    FStatus: TLabel;
    FTree: TTreeView;
    FThreads: TLabel;
    FFooter: TLabel;
    FStacks: TAtlasDebugThreadStacks;
    FData: TAtlasDebugStackTree;
    FFilled: Boolean;
    FOnOpen: TProc<Integer>;
    FOnFilter: TProc;
    procedure Fill;
    procedure AddNodes(AParent: TTreeNode; const AIndexes: TArray<Integer>);
    procedure FilterClick(Sender: TObject);
    procedure TreeDblClick(Sender: TObject);
    procedure TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure TreeChange(Sender: TObject; Node: TTreeNode);
    procedure TreeCustomDrawItem(Sender: TCustomTreeView; Node: TTreeNode; State: TCustomDrawState;
      var DefaultDraw: Boolean);
  protected
    procedure CreateWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Stapel und Baum zeigen; AStatus ersetzt die Statuszeile ('' = Zahl der Threads).</summary>
    procedure SetTree(const AStacks: TAtlasDebugThreadStacks; const ATree: TAtlasDebugStackTree;
      const AStatus: string);
    /// <summary>Nur eine Zeile (Programm läuft, Stapel werden gelesen); der Baum ist leer.</summary>
    procedure ShowStatus(const AText: string);
    /// <summary>Gewählte Filter.</summary>
    function Filter: TAtlasDebugStackFilter;
    /// <summary>Index des gewählten Knotens; -1 ohne.</summary>
    function SelectedNode: Integer;
    procedure OpenSelected;
    property Tree: TTreeView read FTree;
    property OwnOnlyCheck: TCheckBox read FOwnOnly;
    property WaitingOnlyCheck: TCheckBox read FWaitingOnly;
    property StatusLabel: TLabel read FStatus;
    property ThreadsLabel: TLabel read FThreads;
    property Data: TAtlasDebugStackTree read FData;
    property Stacks: TAtlasDebugThreadStacks read FStacks;
    property OnOpen: TProc<Integer> read FOnOpen write FOnOpen;
    property OnFilter: TProc read FOnFilter write FOnFilter;
  end;

implementation

uses
  Winapi.Windows,
  Atlas.UI.Debug.Strings,
  Atlas.UI.Debug.ParallelStacks;

{$R *.dfm}

const
  cBarHeight = 26;
  cGap = 6;
  cCheckWidth = 140;
  cBasePpi = 96;
  cWaitingColor = TColor($0050A0E0);

{ TAtlasDebugParallelStacksFrame }

constructor TAtlasDebugParallelStacksFrame.Create(AOwner: TComponent);
var
  mBar: TPanel;
begin
  inherited Create(AOwner);
  mBar := TPanel.Create(Self);
  mBar.Height := MulDiv(cBarHeight, CurrentPPI, cBasePpi);
  mBar.BevelOuter := bvNone;
  mBar.Align := alTop;
  mBar.Parent := Self;
  FOwnOnly := TCheckBox.Create(Self);
  FOwnOnly.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.ParallelStacksOwnOnly);
  FOwnOnly.SetBounds(MulDiv(cGap, CurrentPPI, cBasePpi), MulDiv(cGap, CurrentPPI, cBasePpi) div 2,
    MulDiv(cCheckWidth, CurrentPPI, cBasePpi), MulDiv(cBarHeight - cGap, CurrentPPI, cBasePpi));
  FOwnOnly.OnClick := FilterClick;
  FOwnOnly.Parent := mBar;
  FWaitingOnly := TCheckBox.Create(Self);
  FWaitingOnly.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.ParallelStacksWaitingOnly);
  FWaitingOnly.SetBounds(FOwnOnly.Left + FOwnOnly.Width + MulDiv(cGap, CurrentPPI, cBasePpi), FOwnOnly.Top,
    MulDiv(cCheckWidth, CurrentPPI, cBasePpi), FOwnOnly.Height);
  FWaitingOnly.OnClick := FilterClick;
  FWaitingOnly.Parent := mBar;
  FStatus := TLabel.Create(Self);
  FStatus.Left := FWaitingOnly.Left + FWaitingOnly.Width + MulDiv(cGap, CurrentPPI, cBasePpi);
  FStatus.Top := FOwnOnly.Top + MulDiv(cGap, CurrentPPI, cBasePpi) div 2;
  FStatus.Parent := mBar;
  FFooter := TLabel.Create(Self);
  FFooter.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.ParallelStacksFooter);
  FFooter.Align := alBottom;
  FFooter.Parent := Self;
  FThreads := TLabel.Create(Self);
  FThreads.Align := alBottom;
  FThreads.Parent := Self;
  FTree := TTreeView.Create(Self);
  FTree.Align := alClient;
  FTree.ReadOnly := True;
  FTree.HideSelection := False;
  FTree.RowSelect := True;
  FTree.OnDblClick := TreeDblClick;
  FTree.OnKeyDown := TreeKeyDown;
  FTree.OnChange := TreeChange;
  FTree.OnCustomDrawItem := TreeCustomDrawItem;
  FTree.Parent := Self;
end;

procedure TAtlasDebugParallelStacksFrame.CreateWnd;
begin
  inherited CreateWnd;
  if not FFilled then
  begin
    Fill;
  end;
end;

procedure TAtlasDebugParallelStacksFrame.SetTree(const AStacks: TAtlasDebugThreadStacks;
  const ATree: TAtlasDebugStackTree; const AStatus: string);
begin
  FStacks := AStacks;
  FData := ATree;
  FStatus.Caption := AStatus;
  if AStatus = '' then
  begin
    FStatus.Caption := TAtlasParallelStacksTexts.StatusText(ATree);
  end;
  FFilled := False;
  if HandleAllocated then
  begin
    Fill;
  end;
end;

procedure TAtlasDebugParallelStacksFrame.ShowStatus(const AText: string);
begin
  SetTree(nil, Default(TAtlasDebugStackTree), AText);
end;

procedure TAtlasDebugParallelStacksFrame.AddNodes(AParent: TTreeNode; const AIndexes: TArray<Integer>);
var
  mIndex: Integer;
  mNode: TTreeNode;
begin
  for mIndex in AIndexes do
  begin
    mNode := FTree.Items.AddChildObject(AParent, TAtlasParallelStacksTexts.NodeText(FData.Nodes[mIndex]),
      Pointer(NativeInt(mIndex)));
    AddNodes(mNode, FData.Nodes[mIndex].Children);
  end;
end;

procedure TAtlasDebugParallelStacksFrame.Fill;
begin
  FFilled := True;
  FThreads.Caption := '';
  FTree.HandleNeeded;
  FTree.Items.BeginUpdate;
  try
    FTree.Items.Clear;
    AddNodes(nil, FData.Roots);
    FTree.FullExpand;
  finally
    FTree.Items.EndUpdate;
  end;
end;

function TAtlasDebugParallelStacksFrame.Filter: TAtlasDebugStackFilter;
begin
  Result := Default(TAtlasDebugStackFilter);
  Result.OwnCodeOnly := FOwnOnly.Checked;
  Result.WaitingOnly := FWaitingOnly.Checked;
end;

function TAtlasDebugParallelStacksFrame.SelectedNode: Integer;
begin
  Result := -1;
  if FTree.Selected <> nil then
  begin
    Result := Integer(NativeInt(FTree.Selected.Data));
  end;
end;

procedure TAtlasDebugParallelStacksFrame.OpenSelected;
begin
  if (SelectedNode >= 0) and Assigned(FOnOpen) then
  begin
    FOnOpen(SelectedNode);
  end;
end;

procedure TAtlasDebugParallelStacksFrame.FilterClick(Sender: TObject);
begin
  if Assigned(FOnFilter) then
  begin
    FOnFilter();
  end;
end;

procedure TAtlasDebugParallelStacksFrame.TreeDblClick(Sender: TObject);
begin
  OpenSelected;
end;

procedure TAtlasDebugParallelStacksFrame.TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    Key := 0;
    OpenSelected;
  end;
end;

procedure TAtlasDebugParallelStacksFrame.TreeChange(Sender: TObject; Node: TTreeNode);
begin
  if (Node = nil) or (SelectedNode < 0) then
  begin
    FThreads.Caption := '';
    Exit;
  end;
  FThreads.Caption := TAtlasParallelStacksTexts.ThreadsText(FData.Nodes[SelectedNode], FStacks);
end;

procedure TAtlasDebugParallelStacksFrame.TreeCustomDrawItem(Sender: TCustomTreeView; Node: TTreeNode;
  State: TCustomDrawState; var DefaultDraw: Boolean);
var
  mIndex: Integer;
begin
  DefaultDraw := True;
  mIndex := Integer(NativeInt(Node.Data));
  if (mIndex < 0) or (mIndex > High(FData.Nodes)) then
  begin
    Exit;
  end;
  if FData.Nodes[mIndex].Current then
  begin
    Sender.Canvas.Font.Style := [fsBold];
  end;
  if FData.Nodes[mIndex].AllWaiting and not (cdsSelected in State) then
  begin
    Sender.Canvas.Font.Color := cWaitingColor;
  end;
end;

end.
