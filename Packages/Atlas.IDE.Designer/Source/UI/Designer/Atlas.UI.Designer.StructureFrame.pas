unit Atlas.UI.Designer.StructureFrame;

// Inhalt des Fensters „Atlas-Struktur“ (#609), reine VCL:
//   [+] [−] | [Nach Klasse] [Nach Art]          [x] Bilder
//   [Filter nach Name oder Klasse        ]
//   ▾ Steuerelemente (7)
//     ▾ MainForm: TMainForm
//         CenterPanel: TPanel
//   ▾ Nichtvisuelle Komponenten (6)
//     ▾ TPopupMenu (3)
//       ▸ PopupMenu2
//           ← PopupMenu: SchemaCombo
//   Klick: wählen · Doppelklick: Editor · Rechtsklick: Befehle
// - Filter und Gruppierung meldet OnChanged (Filtertext, nach Art).
// - Zeilen aus TAtlasStructure.Nodes; Symbole über Images (setzt die
//   IDE-Seite) und die Funktion an ShowNodes. Bereiche, Gruppen und
//   Steuerelemente sind anfangs offen, die Verknüpfungen einer Komponente
//   zu. Was der Benutzer auf- oder zuklappt, bleibt über ShowNodes hinweg
//   erhalten (nach dem Schlüssel der Zeile).
// - Befunde (leerer Pflichtverweis, unbenutzt) rot, Verknüpfungen grau.
// - Klick auf eine Komponente meldet OnSelect mit ihrem Namen, auf eine
//   Verknüpfung mit dem Ziel; Doppelklick OnOpen, Rechtsklick OnMenu (mit
//   Bildschirmpunkt). Ziehen auf den Baum meldet OnDrop, wenn OnCanDrop
//   zustimmt (Komponente aus der Palette).

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Buttons,
  Vcl.ComCtrls,
  Vcl.ImgList,
  Atlas.Core.Designer.Structure;

type
  TAtlasStructureFrame = class(TFrame)
  private
    FByKind: TSpeedButton;
    FShowImages: TCheckBox;
    FFilter: TEdit;
    FTree: TTreeView;
    FImages: TCustomImageList;
    FNodes: TArray<TAtlasStructureNode>;
    FOpen: TDictionary<string, Boolean>;
    FUpdating: Boolean;
    FOnSelect: TProc<string>;
    FOnOpen: TProc<string>;
    FOnMenu: TProc<string, TPoint>;
    FOnCanDrop: TFunc<Boolean>;
    FOnDrop: TProc;
    FOnChanged: TProc<string, Boolean>;
    function NodeOf(ATreeNode: TTreeNode): Integer;
    function NameOf(ATreeNode: TTreeNode): string;
    procedure SetImages(AImages: TCustomImageList);
    procedure RestoreOpen;
    procedure Changed(Sender: TObject);
    procedure ExpandClick(Sender: TObject);
    procedure ImagesClick(Sender: TObject);
    procedure TreeChange(Sender: TObject; Node: TTreeNode);
    procedure TreeToggled(Sender: TObject; Node: TTreeNode);
    procedure TreeDblClick(Sender: TObject);
    procedure TreeMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure TreeCustomDraw(Sender: TCustomTreeView; Node: TTreeNode; State: TCustomDrawState;
      var DefaultDraw: Boolean);
    procedure TreeDragOver(Sender, Source: TObject; X, Y: Integer; State: TDragState; var Accept: Boolean);
    procedure TreeDragDrop(Sender, Source: TObject; X, Y: Integer);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Zeilen zeigen; AImageIndex liefert das Symbol je Zeile (-1 ohne).</summary>
    procedure ShowNodes(const ANodes: TArray<TAtlasStructureNode>;
      const AImageIndex: TFunc<TAtlasStructureNode, Integer>);
    /// <summary>Markiert die Komponente AName ohne OnSelect; '' hebt die Markierung auf.</summary>
    procedure MarkName(const AName: string);
    property Images: TCustomImageList read FImages write SetImages;
    property OnSelect: TProc<string> read FOnSelect write FOnSelect;
    property OnOpen: TProc<string> read FOnOpen write FOnOpen;
    property OnMenu: TProc<string, TPoint> read FOnMenu write FOnMenu;
    property OnCanDrop: TFunc<Boolean> read FOnCanDrop write FOnCanDrop;
    property OnDrop: TProc read FOnDrop write FOnDrop;
    /// <summary>Filter oder Gruppierung geändert (Filtertext, nach Art statt Klasse): neu füllen.</summary>
    property OnChanged: TProc<string, Boolean> read FOnChanged write FOnChanged;
  end;

implementation

uses
  Vcl.Graphics,
  Atlas.Core.Style.Signal,
  Atlas.UI.Foundation.Theme,
  Atlas.UI.Designer.ViewStrings;

const
  cBasePpi = 96;
  cBarHeight = 30;
  cSmallButton = 26;
  cWideButton = 84;
  cGroupTexts: array[TAtlasStructureKind] of TAtlasDesignerViewTextId = (TAtlasDesignerViewTextId.StGroupData,
    TAtlasDesignerViewTextId.StGroupActions, TAtlasDesignerViewTextId.StGroupDialogs,
    TAtlasDesignerViewTextId.StGroupImages, TAtlasDesignerViewTextId.StGroupOther);
  cArrows: array[Boolean] of string = ('→', '←');
  cCountFormat = '%s (%d)';
  cLinkFormat = '%s %s: %s';
  cItemFormat = '%s: %s';
  cUnusedFormat = '%s – %s';
  cLinkColor = clGrayText;

{ Hilfen }

function NewButton(ABar: TPanel; const ACaption, AHint: string; AWidth: Integer): TSpeedButton;
begin
  Result := TSpeedButton.Create(ABar.Owner);
  Result.Parent := ABar;
  Result.Align := alLeft;
  Result.AlignWithMargins := True;
  Result.Left := ABar.Width;
  Result.Width := MulDiv(AWidth, ABar.CurrentPPI, cBasePpi);
  Result.Flat := True;
  Result.Caption := ACaption;
  Result.Hint := AHint;
  Result.ShowHint := AHint <> '';
end;

function CountText(AId: TAtlasDesignerViewTextId; ACount: Integer): string;
begin
  Result := Format(cCountFormat, [TAtlasDesignerViewStrings.Text(AId), ACount]);
end;

function TextOf(const ANode: TAtlasStructureNode): string;
begin
  case ANode.Kind of
    TAtlasStructureNodeKind.Controls:
      Result := CountText(TAtlasDesignerViewTextId.StControls, ANode.Count);
    TAtlasStructureNodeKind.NonVisual:
      Result := CountText(TAtlasDesignerViewTextId.StNonVisual, ANode.Count);
    TAtlasStructureNodeKind.Group:
      if ANode.ClassName <> '' then
      begin
        Result := Format(cCountFormat, [ANode.ClassName, ANode.Count]);
      end
      else
      begin
        Result := CountText(cGroupTexts[ANode.StructureKind], ANode.Count);
      end;
    TAtlasStructureNodeKind.Link:
      if ANode.Finding = TAtlasStructureFinding.Empty then
      begin
        Result := Format(cLinkFormat, [cArrows[ANode.Incoming], ANode.Prop,
          TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.StEmpty)]);
      end
      else
      begin
        Result := Format(cLinkFormat, [cArrows[ANode.Incoming], ANode.Prop, ANode.Name]);
      end;
  else
    Result := Format(cItemFormat, [ANode.Name, ANode.ClassName]);
    if ANode.Finding = TAtlasStructureFinding.Unused then
    begin
      Result := Format(cUnusedFormat, [Result, TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.StUnused)]);
    end;
  end;
end;

/// <summary>Hinweiszeile unten: Klick, Doppelklick, Rechtsklick.</summary>
procedure AddStatus(AFrame: TFrame);
var
  mStatus: TLabel;
begin
  mStatus := TLabel.Create(AFrame);
  mStatus.Parent := AFrame;
  mStatus.Align := alBottom;
  mStatus.AlignWithMargins := True;
  mStatus.Caption := TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.StStatus);
end;

/// <summary>Verknüpfungen einer Komponente sind anfangs zu, alles andere offen.</summary>
function DefaultOpen(const ANode: TAtlasStructureNode): Boolean;
begin
  Result := ANode.Kind <> TAtlasStructureNodeKind.Component;
end;

{ TAtlasStructureFrame }

constructor TAtlasStructureFrame.Create(AOwner: TComponent);
var
  mBar: TPanel;
  mButton: TSpeedButton;
begin
  inherited Create(AOwner);
  FOpen := TDictionary<string, Boolean>.Create;
  mBar := TPanel.Create(Self);
  mBar.Parent := Self;
  mBar.Align := alTop;
  mBar.Height := MulDiv(cBarHeight, CurrentPPI, cBasePpi);
  mBar.BevelOuter := bvNone;
  mBar.ShowCaption := False;
  mButton := NewButton(mBar, '+', TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.StExpandAll), cSmallButton);
  mButton.Tag := 1;
  mButton.OnClick := ExpandClick;
  mButton := NewButton(mBar, '−', TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.StCollapseAll),
    cSmallButton);
  mButton.OnClick := ExpandClick;
  mButton := NewButton(mBar, TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.StByClass), '', cWideButton);
  mButton.GroupIndex := 1;
  mButton.Down := True;
  mButton.OnClick := Changed;
  FByKind := NewButton(mBar, TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.StByKind), '', cWideButton);
  FByKind.GroupIndex := 1;
  FByKind.OnClick := Changed;
  FShowImages := TCheckBox.Create(Self);
  FShowImages.Parent := mBar;
  FShowImages.Align := alRight;
  FShowImages.AlignWithMargins := True;
  FShowImages.Caption := TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.StShowImages);
  FShowImages.Checked := True;
  FShowImages.OnClick := ImagesClick;
  FFilter := TEdit.Create(Self);
  FFilter.Parent := Self;
  FFilter.Align := alTop;
  FFilter.Top := mBar.Height;
  FFilter.AlignWithMargins := True;
  FFilter.TextHint := TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.StFilter);
  FFilter.OnChange := Changed;
  AddStatus(Self);
  FTree := TTreeView.Create(Self);
  FTree.Parent := Self;
  FTree.Align := alClient;
  FTree.ReadOnly := True;
  FTree.HideSelection := False;
  FTree.RowSelect := True;
  FTree.DragMode := dmManual;
  FTree.OnChange := TreeChange;
  FTree.OnExpanded := TreeToggled;
  FTree.OnCollapsed := TreeToggled;
  FTree.OnDblClick := TreeDblClick;
  FTree.OnMouseUp := TreeMouseUp;
  FTree.OnCustomDrawItem := TreeCustomDraw;
  FTree.OnDragOver := TreeDragOver;
  FTree.OnDragDrop := TreeDragDrop;
end;

destructor TAtlasStructureFrame.Destroy;
begin
  FOpen.Free;
  inherited Destroy;
end;

procedure TAtlasStructureFrame.SetImages(AImages: TCustomImageList);
begin
  if FImages <> nil then
  begin
    FImages.RemoveFreeNotification(Self);
  end;
  FImages := AImages;
  if FImages <> nil then
  begin
    FImages.FreeNotification(Self);
  end;
  if FShowImages.Checked then
  begin
    FTree.Images := AImages;
  end;
end;

procedure TAtlasStructureFrame.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FImages) then
  begin
    FImages := nil;
  end;
end;

function TAtlasStructureFrame.NodeOf(ATreeNode: TTreeNode): Integer;
begin
  Result := -1;
  if (ATreeNode <> nil) and (NativeInt(ATreeNode.Data) <= High(FNodes)) then
  begin
    Result := NativeInt(ATreeNode.Data);
  end;
end;

function TAtlasStructureFrame.NameOf(ATreeNode: TTreeNode): string;
var
  mIndex: Integer;
begin
  Result := '';
  mIndex := NodeOf(ATreeNode);
  if (mIndex >= 0) and (FNodes[mIndex].Kind in [TAtlasStructureNodeKind.Control, TAtlasStructureNodeKind.Component,
    TAtlasStructureNodeKind.Link]) then
  begin
    Result := FNodes[mIndex].Name;
  end;
end;

procedure TAtlasStructureFrame.ShowNodes(const ANodes: TArray<TAtlasStructureNode>;
  const AImageIndex: TFunc<TAtlasStructureNode, Integer>);
var
  mSelected: string;
  mParents: TArray<TTreeNode>;
  mIndex: Integer;
  mNode: TTreeNode;
begin
  mSelected := NameOf(FTree.Selected);
  FUpdating := True;
  FTree.Items.BeginUpdate;
  try
    FTree.Items.Clear;
    FNodes := ANodes;
    SetLength(mParents, 1);
    mParents[0] := nil;
    for mIndex := 0 to High(ANodes) do
    begin
      SetLength(mParents, ANodes[mIndex].Level + 2);
      mNode := FTree.Items.AddChildObject(mParents[ANodes[mIndex].Level], TextOf(ANodes[mIndex]),
        Pointer(NativeInt(mIndex)));
      mNode.ImageIndex := -1;
      if Assigned(AImageIndex) then
      begin
        mNode.ImageIndex := AImageIndex(ANodes[mIndex]);
      end;
      mNode.SelectedIndex := mNode.ImageIndex;
      mParents[ANodes[mIndex].Level + 1] := mNode;
    end;
    RestoreOpen;
  finally
    FTree.Items.EndUpdate;
    FUpdating := False;
  end;
  MarkName(mSelected);
end;

procedure TAtlasStructureFrame.RestoreOpen;
var
  mIndex: Integer;
  mNode: TTreeNode;
  mOpen: Boolean;
begin
  for mIndex := 0 to FTree.Items.Count - 1 do
  begin
    mNode := FTree.Items[mIndex];
    if not mNode.HasChildren or (NodeOf(mNode) < 0) then
    begin
      Continue;
    end;
    if not FOpen.TryGetValue(FNodes[NodeOf(mNode)].Key, mOpen) then
    begin
      mOpen := DefaultOpen(FNodes[NodeOf(mNode)]);
    end;
    mNode.Expanded := mOpen;
  end;
end;

procedure TAtlasStructureFrame.MarkName(const AName: string);
var
  mIndex: Integer;
  mNode: TTreeNode;
begin
  if SameText(NameOf(FTree.Selected), AName) then
  begin
    Exit;
  end;
  FUpdating := True;
  try
    FTree.Selected := nil;
    for mIndex := 0 to FTree.Items.Count - 1 do
    begin
      mNode := FTree.Items[mIndex];
      if (AName <> '') and (NodeOf(mNode) >= 0) and (FNodes[NodeOf(mNode)].Kind <> TAtlasStructureNodeKind.Link) and
        SameText(FNodes[NodeOf(mNode)].Name, AName) then
      begin
        FTree.Selected := mNode;
        Break;
      end;
    end;
  finally
    FUpdating := False;
  end;
end;

procedure TAtlasStructureFrame.Changed(Sender: TObject);
begin
  if Assigned(FOnChanged) then
  begin
    FOnChanged(FFilter.Text, FByKind.Down);
  end;
end;

procedure TAtlasStructureFrame.ExpandClick(Sender: TObject);
begin
  // Tag 1: alle aufklappen, sonst alle zuklappen.
  if (Sender as TComponent).Tag = 1 then
  begin
    FTree.FullExpand;
  end
  else
  begin
    FTree.FullCollapse;
  end;
end;

procedure TAtlasStructureFrame.TreeToggled(Sender: TObject; Node: TTreeNode);
begin
  if not FUpdating and (NodeOf(Node) >= 0) then
  begin
    FOpen.AddOrSetValue(FNodes[NodeOf(Node)].Key, Node.Expanded);
  end;
end;

procedure TAtlasStructureFrame.ImagesClick(Sender: TObject);
begin
  if FShowImages.Checked then
  begin
    FTree.Images := FImages;
  end
  else
  begin
    FTree.Images := nil;
  end;
end;

procedure TAtlasStructureFrame.TreeChange(Sender: TObject; Node: TTreeNode);
begin
  if not FUpdating and Assigned(FOnSelect) and (NameOf(Node) <> '') then
  begin
    FOnSelect(NameOf(Node));
  end;
end;

procedure TAtlasStructureFrame.TreeDblClick(Sender: TObject);
begin
  if Assigned(FOnOpen) and (NameOf(FTree.Selected) <> '') then
  begin
    FOnOpen(NameOf(FTree.Selected));
  end;
end;

procedure TAtlasStructureFrame.TreeMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  mNode: TTreeNode;
begin
  mNode := FTree.GetNodeAt(X, Y);
  if (Button <> mbRight) or (NameOf(mNode) = '') or not Assigned(FOnMenu) then
  begin
    Exit;
  end;
  FTree.Selected := mNode;
  FOnMenu(NameOf(mNode), FTree.ClientToScreen(Point(X, Y)));
end;

procedure TAtlasStructureFrame.TreeCustomDraw(Sender: TCustomTreeView; Node: TTreeNode; State: TCustomDrawState;
  var DefaultDraw: Boolean);
var
  mIndex: Integer;
begin
  DefaultDraw := True;
  mIndex := NodeOf(Node);
  if (mIndex < 0) or (cdsSelected in State) then
  begin
    Exit;
  end;
  if FNodes[mIndex].Finding <> TAtlasStructureFinding.None then
  begin
    Sender.Canvas.Font.Color := TAtlasUiTheme.TextColor(TAtlasSignalKind.Error);
  end
  else if FNodes[mIndex].Kind = TAtlasStructureNodeKind.Link then
  begin
    Sender.Canvas.Font.Color := cLinkColor;
  end;
end;

procedure TAtlasStructureFrame.TreeDragOver(Sender, Source: TObject; X, Y: Integer; State: TDragState;
  var Accept: Boolean);
begin
  Accept := (Source <> nil) and Assigned(FOnCanDrop) and FOnCanDrop;
end;

procedure TAtlasStructureFrame.TreeDragDrop(Sender, Source: TObject; X, Y: Integer);
begin
  if Assigned(FOnDrop) then
  begin
    FOnDrop();
  end;
end;

end.
