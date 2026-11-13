unit Atlas.UI.Debug.LeaksFrame;

// Inhalt des Seitenfensters „Atlas-Lecks“ (#1875), reine VCL: oben „Bekannte
// ausblenden“, „Als bekannt markieren“ und die Statuszeile, darunter der Baum
// (Name mit Anzahl und Vergleich, darunter Kandidaten bzw. Gruppen mit
// Erzeugungsstelle), unten der Tastenhinweis. Neue Namen stehen fett, bekannte
// grau. Enter oder Doppelklick meldet die Zeile (OnOpen), „Als bekannt
// markieren“ den Namen (OnMarkKnown), der Filter sich über OnFilter. Die
// IDE-Schicht ruft SetRows. Die DFM ist leer; aufgebaut wird im Code, gefüllt
// erst mit Fenster (CreateWnd).

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
  Atlas.Core.Debug.LeakView;

type
  TAtlasDebugLeaksFrame = class(TFrame)
  private
    FHideKnown: TCheckBox;
    FMarkKnown: TButton;
    FStatus: TLabel;
    FTree: TTreeView;
    FFooter: TLabel;
    FRows: TArray<TAtlasLeakRow>;
    FFilled: Boolean;
    FOnOpen: TProc<TAtlasLeakRow>;
    FOnMarkKnown: TProc<string>;
    FOnFilter: TProc;
    procedure Fill;
    procedure FilterClick(Sender: TObject);
    procedure MarkKnownClick(Sender: TObject);
    procedure TreeDblClick(Sender: TObject);
    procedure TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure TreeChange(Sender: TObject; Node: TTreeNode);
    procedure TreeCustomDrawItem(Sender: TCustomTreeView; Node: TTreeNode; State: TCustomDrawState;
      var DefaultDraw: Boolean);
  protected
    procedure CreateWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Zeilen und Statuszeile zeigen.</summary>
    procedure SetRows(const ARows: TArray<TAtlasLeakRow>; const AStatus: string);
    /// <summary>Index der gewählten Zeile in Rows; -1 ohne.</summary>
    function SelectedRow: Integer;
    procedure OpenSelected;
    function HideKnown: Boolean;
    property Tree: TTreeView read FTree;
    property HideKnownCheck: TCheckBox read FHideKnown;
    property MarkKnownButton: TButton read FMarkKnown;
    property StatusLabel: TLabel read FStatus;
    property Rows: TArray<TAtlasLeakRow> read FRows;
    property OnOpen: TProc<TAtlasLeakRow> read FOnOpen write FOnOpen;
    property OnMarkKnown: TProc<string> read FOnMarkKnown write FOnMarkKnown;
    property OnFilter: TProc read FOnFilter write FOnFilter;
  end;

implementation

uses
  Winapi.Windows,
  Atlas.UI.Debug.Strings,
  Atlas.UI.Debug.Leaks;

{$R *.dfm}

const
  cBarHeight = 30;
  cGap = 6;
  cCheckWidth = 150;
  cButtonWidth = 170;
  cBasePpi = 96;

{ TAtlasDebugLeaksFrame }

constructor TAtlasDebugLeaksFrame.Create(AOwner: TComponent);
var
  mBar: TPanel;
begin
  inherited Create(AOwner);
  mBar := TPanel.Create(Self);
  mBar.Height := MulDiv(cBarHeight, CurrentPPI, cBasePpi);
  mBar.BevelOuter := bvNone;
  mBar.Align := alTop;
  mBar.Parent := Self;
  FHideKnown := TCheckBox.Create(Self);
  FHideKnown.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.LeaksHideKnown);
  FHideKnown.SetBounds(MulDiv(cGap, CurrentPPI, cBasePpi), MulDiv(cGap, CurrentPPI, cBasePpi) div 2,
    MulDiv(cCheckWidth, CurrentPPI, cBasePpi), MulDiv(cBarHeight - cGap, CurrentPPI, cBasePpi));
  FHideKnown.Checked := True;
  FHideKnown.OnClick := FilterClick;
  FHideKnown.Parent := mBar;
  FMarkKnown := TButton.Create(Self);
  FMarkKnown.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.LeaksMarkKnown);
  FMarkKnown.SetBounds(FHideKnown.Left + FHideKnown.Width + MulDiv(cGap, CurrentPPI, cBasePpi), FHideKnown.Top,
    MulDiv(cButtonWidth, CurrentPPI, cBasePpi), FHideKnown.Height);
  FMarkKnown.Enabled := False;
  FMarkKnown.OnClick := MarkKnownClick;
  FMarkKnown.Parent := mBar;
  FStatus := TLabel.Create(Self);
  FStatus.Left := FMarkKnown.Left + FMarkKnown.Width + MulDiv(cGap, CurrentPPI, cBasePpi);
  FStatus.Top := FHideKnown.Top + MulDiv(cGap, CurrentPPI, cBasePpi) div 2;
  FStatus.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.LeaksEmpty);
  FStatus.Parent := mBar;
  FFooter := TLabel.Create(Self);
  FFooter.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.LeaksFooter);
  FFooter.Align := alBottom;
  FFooter.Parent := Self;
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

procedure TAtlasDebugLeaksFrame.CreateWnd;
begin
  inherited CreateWnd;
  if not FFilled then
  begin
    Fill;
  end;
end;

procedure TAtlasDebugLeaksFrame.SetRows(const ARows: TArray<TAtlasLeakRow>; const AStatus: string);
begin
  FRows := ARows;
  FStatus.Caption := AStatus;
  FFilled := False;
  if HandleAllocated then
  begin
    Fill;
  end;
end;

procedure TAtlasDebugLeaksFrame.Fill;
var
  mIndex: Integer;
  mParent: TTreeNode;
begin
  FFilled := True;
  FTree.HandleNeeded;
  FTree.Items.BeginUpdate;
  try
    FTree.Items.Clear;
    mParent := nil;
    for mIndex := 0 to High(FRows) do
    begin
      if FRows[mIndex].Kind = TAtlasLeakRowKind.Name then
      begin
        mParent := FTree.Items.AddObject(nil, TAtlasLeakTexts.RowText(FRows[mIndex]), Pointer(NativeInt(mIndex)));
      end
      else
      begin
        FTree.Items.AddChildObject(mParent, TAtlasLeakTexts.RowText(FRows[mIndex]), Pointer(NativeInt(mIndex)));
      end;
    end;
    FTree.FullExpand;
  finally
    FTree.Items.EndUpdate;
  end;
  FMarkKnown.Enabled := False;
end;

function TAtlasDebugLeaksFrame.SelectedRow: Integer;
begin
  Result := -1;
  if FTree.Selected <> nil then
  begin
    Result := Integer(NativeInt(FTree.Selected.Data));
  end;
end;

function TAtlasDebugLeaksFrame.HideKnown: Boolean;
begin
  Result := FHideKnown.Checked;
end;

procedure TAtlasDebugLeaksFrame.OpenSelected;
var
  mRow: Integer;
begin
  mRow := SelectedRow;
  if (mRow >= 0) and (mRow <= High(FRows)) and TAtlasLeakViews.CanOpen(FRows[mRow]) and Assigned(FOnOpen) then
  begin
    FOnOpen(FRows[mRow]);
  end;
end;

procedure TAtlasDebugLeaksFrame.FilterClick(Sender: TObject);
begin
  if Assigned(FOnFilter) then
  begin
    FOnFilter();
  end;
end;

procedure TAtlasDebugLeaksFrame.MarkKnownClick(Sender: TObject);
var
  mRow: Integer;
begin
  mRow := SelectedRow;
  if (mRow >= 0) and (mRow <= High(FRows)) and Assigned(FOnMarkKnown) then
  begin
    FOnMarkKnown(FRows[mRow].Entry.Name);
  end;
end;

procedure TAtlasDebugLeaksFrame.TreeDblClick(Sender: TObject);
begin
  OpenSelected;
end;

procedure TAtlasDebugLeaksFrame.TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    Key := 0;
    OpenSelected;
  end;
end;

procedure TAtlasDebugLeaksFrame.TreeChange(Sender: TObject; Node: TTreeNode);
var
  mRow: Integer;
begin
  mRow := SelectedRow;
  FMarkKnown.Enabled := (mRow >= 0) and (mRow <= High(FRows));
  if FMarkKnown.Enabled and FRows[mRow].Entry.Known then
  begin
    FMarkKnown.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.LeaksUnmarkKnown);
  end
  else
  begin
    FMarkKnown.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.LeaksMarkKnown);
  end;
end;

procedure TAtlasDebugLeaksFrame.TreeCustomDrawItem(Sender: TCustomTreeView; Node: TTreeNode;
  State: TCustomDrawState; var DefaultDraw: Boolean);
var
  mRow: Integer;
begin
  DefaultDraw := True;
  mRow := Integer(NativeInt(Node.Data));
  if (mRow < 0) or (mRow > High(FRows)) or (FRows[mRow].Kind <> TAtlasLeakRowKind.Name) then
  begin
    Exit;
  end;
  if FRows[mRow].Entry.IsNew then
  begin
    Sender.Canvas.Font.Style := [fsBold];
  end;
  if FRows[mRow].Entry.Known and not (cdsSelected in State) then
  begin
    Sender.Canvas.Font.Color := clGrayText;
  end;
end;

end.
