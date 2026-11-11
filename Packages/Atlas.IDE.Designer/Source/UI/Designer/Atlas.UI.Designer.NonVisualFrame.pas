unit Atlas.UI.Designer.NonVisualFrame;

// Inhalt der Leiste für nichtvisuelle Komponenten (#609), reine VCL:
//   [Filter nach Namen            ]
//   ▾ Daten
//     [▣] dsKunden      TDataSource
//     [▣] qryKunden     TFDQuery
//   ▾ Dialoge
//     [▣] dlgOpen       TOpenDialog
// - Gruppen auf- und zuklappbar (ListView-Gruppen), Symbol aus der Palette
//   über SmallImages (setzt die IDE-Seite), Name, Klasse.
// - Klick meldet OnSelect, Doppelklick OnOpen, Rechtsklick OnMenu (mit
//   Bildschirmpunkt). Ziehen auf die Liste oder Klick auf eine freie Stelle
//   meldet OnDrop, wenn OnCanDrop zustimmt (Komponente aus der Palette).
// - ShowRows behält Auswahl und zugeklappte Gruppen bei.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Atlas.Core.Designer.NonVisual;

type
  TAtlasNonVisualFrame = class(TFrame)
  private
    FFilter: TEdit;
    FList: TListView;
    FNames: TArray<string>;
    FUpdating: Boolean;
    FOnSelect: TProc<string>;
    FOnOpen: TProc<string>;
    FOnMenu: TProc<string, TPoint>;
    FOnCanDrop: TFunc<Boolean>;
    FOnDrop: TProc;
    FOnFilter: TProc<string>;
    function NameAt(AItem: TListItem): string;
    procedure EnsureGroups;
    procedure FilterChanged(Sender: TObject);
    procedure ListSelect(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure ListDblClick(Sender: TObject);
    procedure ListMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure ListDragOver(Sender, Source: TObject; X, Y: Integer; State: TDragState; var Accept: Boolean);
    procedure ListDragDrop(Sender, Source: TObject; X, Y: Integer);
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Zeilen zeigen; AImageIndex liefert das Symbol je Zeile (-1 ohne).</summary>
    procedure ShowRows(const ARows: TArray<TAtlasTrayItem>; const AImageIndex: TFunc<TAtlasTrayItem, Integer>);
    /// <summary>Markiert die Zeile AName ohne OnSelect; '' hebt die Markierung auf.</summary>
    procedure MarkName(const AName: string);
    function FilterText: string;
    property List: TListView read FList;
    property OnSelect: TProc<string> read FOnSelect write FOnSelect;
    property OnOpen: TProc<string> read FOnOpen write FOnOpen;
    property OnMenu: TProc<string, TPoint> read FOnMenu write FOnMenu;
    property OnCanDrop: TFunc<Boolean> read FOnCanDrop write FOnCanDrop;
    property OnDrop: TProc read FOnDrop write FOnDrop;
    property OnFilter: TProc<string> read FOnFilter write FOnFilter;
  end;

implementation

uses
  Atlas.UI.Designer.ViewStrings;

const
  cBasePpi = 96;
  cNameWidth = 160;
  cClassWidth = 140;
  cGroupTexts: array[TAtlasTrayGroup] of TAtlasDesignerViewTextId = (TAtlasDesignerViewTextId.NvGroupData,
    TAtlasDesignerViewTextId.NvGroupActions, TAtlasDesignerViewTextId.NvGroupDialogs,
    TAtlasDesignerViewTextId.NvGroupImages, TAtlasDesignerViewTextId.NvGroupOther);

{ TAtlasNonVisualFrame }

constructor TAtlasNonVisualFrame.Create(AOwner: TComponent);
var
  mColumn: TListColumn;
begin
  inherited Create(AOwner);
  FFilter := TEdit.Create(Self);
  FFilter.Parent := Self;
  FFilter.Align := alTop;
  FFilter.AlignWithMargins := True;
  FFilter.TextHint := TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.NvFilter);
  FFilter.OnChange := FilterChanged;
  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.ViewStyle := vsReport;
  FList.RowSelect := True;
  FList.ReadOnly := True;
  FList.HideSelection := False;
  FList.GroupView := True;
  FList.DragMode := dmManual;
  mColumn := FList.Columns.Add;
  mColumn.Caption := TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.NvColName);
  mColumn.Width := MulDiv(cNameWidth, CurrentPPI, cBasePpi);
  mColumn := FList.Columns.Add;
  mColumn.Caption := TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.NvColClass);
  mColumn.Width := MulDiv(cClassWidth, CurrentPPI, cBasePpi);
  FList.OnSelectItem := ListSelect;
  FList.OnDblClick := ListDblClick;
  FList.OnMouseUp := ListMouseUp;
  FList.OnDragOver := ListDragOver;
  FList.OnDragDrop := ListDragDrop;
  EnsureGroups;
end;

procedure TAtlasNonVisualFrame.EnsureGroups;
var
  mGroup: TAtlasTrayGroup;
  mListGroup: TListGroup;
begin
  if FList.Groups.Count > 0 then
  begin
    Exit;
  end;
  for mGroup := Low(TAtlasTrayGroup) to High(TAtlasTrayGroup) do
  begin
    mListGroup := FList.Groups.Add;
    mListGroup.Header := TAtlasDesignerViewStrings.Text(cGroupTexts[mGroup]);
    mListGroup.GroupID := Ord(mGroup);
    mListGroup.State := [lgsCollapsible];
  end;
end;

function TAtlasNonVisualFrame.NameAt(AItem: TListItem): string;
begin
  Result := '';
  if (AItem <> nil) and (AItem.Index <= High(FNames)) then
  begin
    Result := FNames[AItem.Index];
  end;
end;

procedure TAtlasNonVisualFrame.ShowRows(const ARows: TArray<TAtlasTrayItem>;
  const AImageIndex: TFunc<TAtlasTrayItem, Integer>);
var
  mSelected: string;
  mRow: TAtlasTrayItem;
  mItem: TListItem;
begin
  mSelected := NameAt(FList.Selected);
  FUpdating := True;
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    FNames := nil;
    for mRow in ARows do
    begin
      mItem := FList.Items.Add;
      mItem.Caption := mRow.Name;
      mItem.SubItems.Add(mRow.ClassName);
      mItem.GroupID := Ord(mRow.Group);
      mItem.ImageIndex := -1;
      if Assigned(AImageIndex) then
      begin
        mItem.ImageIndex := AImageIndex(mRow);
      end;
      FNames := FNames + [mRow.Name];
      mItem.Selected := SameText(mRow.Name, mSelected);
    end;
  finally
    FList.Items.EndUpdate;
    FUpdating := False;
  end;
end;

procedure TAtlasNonVisualFrame.MarkName(const AName: string);
var
  mIndex: Integer;
begin
  FUpdating := True;
  try
    for mIndex := 0 to FList.Items.Count - 1 do
    begin
      FList.Items[mIndex].Selected := (AName <> '') and SameText(NameAt(FList.Items[mIndex]), AName);
    end;
  finally
    FUpdating := False;
  end;
end;

function TAtlasNonVisualFrame.FilterText: string;
begin
  Result := FFilter.Text;
end;

procedure TAtlasNonVisualFrame.FilterChanged(Sender: TObject);
begin
  if Assigned(FOnFilter) then
  begin
    FOnFilter(FFilter.Text);
  end;
end;

procedure TAtlasNonVisualFrame.ListSelect(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if not FUpdating and Selected and Assigned(FOnSelect) and (NameAt(Item) <> '') then
  begin
    FOnSelect(NameAt(Item));
  end;
end;

procedure TAtlasNonVisualFrame.ListDblClick(Sender: TObject);
begin
  if Assigned(FOnOpen) and (NameAt(FList.Selected) <> '') then
  begin
    FOnOpen(NameAt(FList.Selected));
  end;
end;

procedure TAtlasNonVisualFrame.ListMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  mItem: TListItem;
begin
  mItem := FList.GetItemAt(X, Y);
  if (Button = mbRight) and (mItem <> nil) and Assigned(FOnMenu) then
  begin
    mItem.Selected := True;
    FOnMenu(NameAt(mItem), FList.ClientToScreen(Point(X, Y)));
  end
  else if (Button = mbLeft) and (mItem = nil) and (htNowhere in FList.GetHitTestInfoAt(X, Y)) and
    Assigned(FOnCanDrop) and FOnCanDrop and Assigned(FOnDrop) then
  begin
    // Klick auf eine freie Stelle mit gewählter Palettenkomponente legt sie an.
    FOnDrop();
  end;
end;

procedure TAtlasNonVisualFrame.ListDragOver(Sender, Source: TObject; X, Y: Integer; State: TDragState;
  var Accept: Boolean);
begin
  Accept := (Source <> nil) and Assigned(FOnCanDrop) and FOnCanDrop;
end;

procedure TAtlasNonVisualFrame.ListDragDrop(Sender, Source: TObject; X, Y: Integer);
begin
  if Assigned(FOnDrop) then
  begin
    FOnDrop();
  end;
end;

end.
