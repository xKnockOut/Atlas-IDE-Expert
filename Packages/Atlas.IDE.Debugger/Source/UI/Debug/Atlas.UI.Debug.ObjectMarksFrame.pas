unit Atlas.UI.Debug.ObjectMarksFrame;

// Inhalt des Fensters „Markierte Objekte“ (#839), reine VCL: oben „Etikett ändern …“, „Farbe wechseln“ und
// „Entfernen“, darunter die Liste (Etikett in seiner Farbe, Klasse, Adresse, zuletzt gesehen, Zustand), unten der
// Tastenhinweis. Vermutlich freigegebene Objekte stehen grau. Entf entfernt, F2 ändert das Etikett, die Leertaste
// wechselt die Farbe; gemeldet wird die Adresse (OnRemove, OnRename, OnColor). Die IDE-Schicht ruft SetMarks. Die
// DFM ist leer; aufgebaut wird im Code, gefüllt erst mit Fenster (CreateWnd).

interface

uses
  System.SysUtils,
  System.Classes,
  System.UITypes,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Vcl.Forms,
  Atlas.Core.Debug.ObjectMarks;

type
  TAtlasObjectMarkEvent = reference to procedure(AAddress: UInt64);

  TAtlasDebugObjectMarksFrame = class(TFrame)
  public const
    /// <summary>Farben der Etiketten in der Reihenfolge der Vergabe; gut lesbar auf hellem und dunklem Grund.
    /// </summary>
    cColors: array[0..TAtlasObjectMarks.cColorCount - 1] of TColor = ($003C78D8, $00009E3B, $00C06000, $002B8FD9,
      $00A0349B, $00008B8B, $005A5AC8, $00808000);
  private
    FRename: TButton;
    FColor: TButton;
    FRemove: TButton;
    FList: TListView;
    FFooter: TLabel;
    FMarks: TArray<TAtlasObjectMark>;
    FOnRemove: TAtlasObjectMarkEvent;
    FOnRename: TAtlasObjectMarkEvent;
    FOnColor: TAtlasObjectMarkEvent;
    function AddButton(ABar: TWinControl; ALeft: Integer; const ACaption: string; AOnClick: TNotifyEvent): TButton;
    procedure AddColumns;
    procedure Fill;
    procedure UpdateButtons;
    procedure ReportSelected(const AEvent: TAtlasObjectMarkEvent);
    procedure RenameClick(Sender: TObject);
    procedure ColorClick(Sender: TObject);
    procedure RemoveClick(Sender: TObject);
    procedure ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ListSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure ListCustomDrawItem(Sender: TCustomListView; Item: TListItem; State: TCustomDrawState;
      var DefaultDraw: Boolean);
  protected
    procedure CreateWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Markierungen zeigen; die Auswahl bleibt bei derselben Adresse.</summary>
    procedure SetMarks(const AMarks: TArray<TAtlasObjectMark>);
    /// <summary>Index der gewählten Markierung; -1 ohne.</summary>
    function SelectedMark: Integer;
    property List: TListView read FList;
    property Marks: TArray<TAtlasObjectMark> read FMarks;
    property OnRemove: TAtlasObjectMarkEvent read FOnRemove write FOnRemove;
    property OnRename: TAtlasObjectMarkEvent read FOnRename write FOnRename;
    property OnColor: TAtlasObjectMarkEvent read FOnColor write FOnColor;
  end;

implementation

uses
  Winapi.Windows,
  Atlas.Core.Debug.InstanceBreakpoint,
  Atlas.UI.Debug.ObjectMarks.Strings,
  Atlas.Vcl.Theme.Service;

{$R *.dfm}

const
  cBarHeight = 30;
  cGap = 6;
  cButtonWidth = 130;
  cBasePpi = 96;
  cColumnWidths: array[0..4] of Integer = (160, 140, 130, 220, 150);

{ TAtlasDebugObjectMarksFrame }

constructor TAtlasDebugObjectMarksFrame.Create(AOwner: TComponent);
var
  mBar: TPanel;
  mLeft: Integer;
begin
  inherited Create(AOwner);
  mBar := TPanel.Create(Self);
  mBar.Height := MulDiv(cBarHeight, CurrentPPI, cBasePpi);
  mBar.BevelOuter := bvNone;
  mBar.Align := alTop;
  mBar.Parent := Self;
  mLeft := MulDiv(cGap, CurrentPPI, cBasePpi);
  FRename := AddButton(mBar, mLeft, TAtlasObjectMarksStrings.Text(TAtlasObjectMarksTextId.ObjectMarksRename),
    RenameClick);
  FColor := AddButton(mBar, FRename.Left + FRename.Width + mLeft,
    TAtlasObjectMarksStrings.Text(TAtlasObjectMarksTextId.ObjectMarksColor), ColorClick);
  FRemove := AddButton(mBar, FColor.Left + FColor.Width + mLeft,
    TAtlasObjectMarksStrings.Text(TAtlasObjectMarksTextId.ObjectMarksRemove), RemoveClick);
  FFooter := TLabel.Create(Self);
  FFooter.Caption := TAtlasObjectMarksStrings.Text(TAtlasObjectMarksTextId.ObjectMarksFooter);
  FFooter.Align := alBottom;
  FFooter.Parent := Self;
  FList := TListView.Create(Self);
  FList.Align := alClient;
  FList.ViewStyle := vsReport;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  FList.HideSelection := False;
  FList.OnKeyDown := ListKeyDown;
  FList.OnSelectItem := ListSelectItem;
  FList.OnCustomDrawItem := ListCustomDrawItem;
  FList.Parent := Self;
end;

function TAtlasDebugObjectMarksFrame.AddButton(ABar: TWinControl; ALeft: Integer; const ACaption: string;
  AOnClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Caption := ACaption;
  Result.SetBounds(ALeft, MulDiv(cGap, CurrentPPI, cBasePpi) div 2, MulDiv(cButtonWidth, CurrentPPI, cBasePpi),
    MulDiv(cBarHeight - cGap, CurrentPPI, cBasePpi));
  Result.Enabled := False;
  Result.OnClick := AOnClick;
  Result.Parent := ABar;
end;

procedure TAtlasDebugObjectMarksFrame.AddColumns;
const
  cIds: array[0..4] of TAtlasObjectMarksTextId = (TAtlasObjectMarksTextId.ObjectMarksColumnLabel,
    TAtlasObjectMarksTextId.ObjectMarksColumnClass, TAtlasObjectMarksTextId.ObjectMarksColumnAddress,
    TAtlasObjectMarksTextId.ObjectMarksColumnSeen, TAtlasObjectMarksTextId.ObjectMarksColumnState);
var
  mIndex: Integer;
  mColumn: TListColumn;
begin
  if FList.Columns.Count > 0 then
  begin
    Exit;
  end;
  for mIndex := 0 to High(cIds) do
  begin
    mColumn := FList.Columns.Add;
    mColumn.Caption := TAtlasObjectMarksStrings.Text(cIds[mIndex]);
    mColumn.Width := MulDiv(cColumnWidths[mIndex], CurrentPPI, cBasePpi);
  end;
end;

procedure TAtlasDebugObjectMarksFrame.CreateWnd;
begin
  inherited CreateWnd;
  // Fill leert die Liste vorher; auch nach neu angelegtem Fenster stimmt sie so.
  Fill;
end;

/// <summary>„Ziel (Haupt.pas:14)“; ohne Stelle nur der Ausdruck.</summary>
function SeenText(const AMark: TAtlasObjectMark): string;
begin
  Result := AMark.LastExpression;
  if AMark.LastPlace <> '' then
  begin
    Result := TAtlasObjectMarksStrings.Fmt(TAtlasObjectMarksTextId.ObjectMarksSeen,
      [AMark.LastExpression, AMark.LastPlace]);
  end;
end;

procedure TAtlasDebugObjectMarksFrame.Fill;
var
  mMark: TAtlasObjectMark;
  mItem: TListItem;
  mState: string;
begin
  FList.HandleNeeded;
  AddColumns;
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for mMark in FMarks do
    begin
      mItem := FList.Items.Add;
      mItem.Caption := mMark.Caption;
      mItem.SubItems.Add(mMark.TypeName);
      mItem.SubItems.Add(TAtlasInstanceBreakpoint.AddressText(mMark.Address));
      mItem.SubItems.Add(SeenText(mMark));
      mState := '';
      if mMark.Freed then
      begin
        mState := TAtlasObjectMarksStrings.Text(TAtlasObjectMarksTextId.ObjectMarksFreed);
      end;
      mItem.SubItems.Add(mState);
    end;
  finally
    FList.Items.EndUpdate;
  end;
  if Length(FMarks) = 0 then
  begin
    FFooter.Caption := TAtlasObjectMarksStrings.Text(TAtlasObjectMarksTextId.ObjectMarksEmpty);
  end
  else
  begin
    FFooter.Caption := TAtlasObjectMarksStrings.Text(TAtlasObjectMarksTextId.ObjectMarksFooter);
  end;
  UpdateButtons;
end;

procedure TAtlasDebugObjectMarksFrame.SetMarks(const AMarks: TArray<TAtlasObjectMark>);
var
  mSelected: UInt64;
  mIndex: Integer;
begin
  mSelected := 0;
  mIndex := SelectedMark;
  if mIndex >= 0 then
  begin
    mSelected := FMarks[mIndex].Address;
  end;
  FMarks := Copy(AMarks);
  if not HandleAllocated then
  begin
    Exit;
  end;
  Fill;
  for mIndex := 0 to High(FMarks) do
  begin
    if (mSelected <> 0) and (FMarks[mIndex].Address = mSelected) then
    begin
      FList.Items[mIndex].Selected := True;
    end;
  end;
end;

function TAtlasDebugObjectMarksFrame.SelectedMark: Integer;
begin
  Result := -1;
  if FList.HandleAllocated and (FList.Selected <> nil) and (FList.Selected.Index <= High(FMarks)) then
  begin
    Result := FList.Selected.Index;
  end;
end;

procedure TAtlasDebugObjectMarksFrame.UpdateButtons;
var
  mIndex: Integer;
begin
  mIndex := SelectedMark;
  FRemove.Enabled := mIndex >= 0;
  // Freigegebene lassen sich nur noch entfernen.
  FRename.Enabled := (mIndex >= 0) and not FMarks[mIndex].Freed;
  FColor.Enabled := FRename.Enabled;
end;

procedure TAtlasDebugObjectMarksFrame.ReportSelected(const AEvent: TAtlasObjectMarkEvent);
var
  mIndex: Integer;
begin
  mIndex := SelectedMark;
  if (mIndex >= 0) and Assigned(AEvent) then
  begin
    AEvent(FMarks[mIndex].Address);
  end;
end;

procedure TAtlasDebugObjectMarksFrame.RenameClick(Sender: TObject);
begin
  if FRename.Enabled then
  begin
    ReportSelected(FOnRename);
  end;
end;

procedure TAtlasDebugObjectMarksFrame.ColorClick(Sender: TObject);
begin
  if FColor.Enabled then
  begin
    ReportSelected(FOnColor);
  end;
end;

procedure TAtlasDebugObjectMarksFrame.RemoveClick(Sender: TObject);
begin
  ReportSelected(FOnRemove);
end;

procedure TAtlasDebugObjectMarksFrame.ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_DELETE:
      RemoveClick(Sender);
    VK_F2:
      RenameClick(Sender);
    VK_SPACE:
      ColorClick(Sender);
  else
    Exit;
  end;
  Key := 0;
end;

procedure TAtlasDebugObjectMarksFrame.ListSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  UpdateButtons;
end;

procedure TAtlasDebugObjectMarksFrame.ListCustomDrawItem(Sender: TCustomListView; Item: TListItem;
  State: TCustomDrawState; var DefaultDraw: Boolean);
var
  mIndex: Integer;
begin
  DefaultDraw := True;
  mIndex := Item.Index;
  if (mIndex < 0) or (mIndex > High(FMarks)) or Item.Selected then
  begin
    Exit;
  end;
  if FMarks[mIndex].Freed then
  begin
    Sender.Canvas.Font.Color := TAtlasUiTheme.SystemColor(Sender, clGrayText);
  end
  else
  begin
    Sender.Canvas.Font.Color := cColors[FMarks[mIndex].Color];
  end;
end;

end.
