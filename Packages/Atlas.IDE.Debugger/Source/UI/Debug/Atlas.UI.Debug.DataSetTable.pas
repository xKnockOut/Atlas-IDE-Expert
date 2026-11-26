unit Atlas.UI.Debug.DataSetTable;

// Fenster „Datenmenge als Tabelle“ (#3024), reine VCL. Öffnet der Knopf
// „Tabelle …“ im Fenster „Auswerten“; Inhalt liest die IDE-Schicht
// (Atlas.IDE.Debug.DataSetTable) über den Kern Atlas.Core.Debug.DataSetTable.
// - Oben die Kopfzeile (Ausdruck, Zustand, Datensatz x von y), darunter bei
//   Bedarf der Hinweis zur Cursorbewegung mit „n Zeilen lesen“ und „Nur
//   aktueller Datensatz“ und der Tipp zur Unit Atlas.Debug.DataSets.
// - Mitte die Tabelle: virtuell (OwnerData), erste Spalte die Nummer des
//   Datensatzes, der aktuelle mit ▶; NULL grau als „(NULL)“-Text.
// - Unten die Knöpfe „Weitere n laden“, „Zum Datensatz springen“, „Wert
//   ändern …“ (Spalte = zuletzt angeklickte Zelle), „Als CSV/JSON kopieren“,
//   „Aktualisieren“, „Abbrechen“ (während des Lesens), darunter der Stand.
// - Strg+C kopiert die markierten Zeilen (Tabulator), Esc schließt.
// Was ein Knopf auslöst, meldet das Fenster über seine Ereignisse; Rückfragen
// stellt die IDE-Schicht.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.ExtCtrls,
  Atlas.Core.Debug.DataSetTable,
  Atlas.Vcl.Forms.Dialog,
  Atlas.Vcl.Controls.ListView;

type
  /// <summary>Datensatz ARecNo (ab 1) und Feld AField (ab 0).</summary>
  TAtlasDataSetCellProc = reference to procedure(ARecNo: Int64; AField: Integer);

  TAtlasDebugDataSetForm = class(TAtlasDialog)
  private
    FHeader: TLabel;
    FConsentRow: TFlowPanel;
    FConsentNote: TLabel;
    FConsentButton: TButton;
    FCurrentButton: TButton;
    FHint: TLabel;
    FList: TAtlasListView;
    FBar: TFlowPanel;
    FStatus: TLabel;
    FLoadMoreButton: TButton;
    FGoToButton: TButton;
    FEditButton: TButton;
    FCopyCsvButton: TButton;
    FCopyJsonButton: TButton;
    FRefreshButton: TButton;
    FCancelButton: TButton;
    FNames: TArray<string>;
    FRows: TArray<TAtlasDataSetRow>;
    FCurrentRecNo: Int64;
    FClickedField: Integer;
    FReading: Boolean;
    FCanLoadMore: Boolean;
    FCanMove: Boolean;
    FOnLoadMore: TProc;
    FOnGoTo: TProc<Int64>;
    FOnEdit: TAtlasDataSetCellProc;
    FOnConsent: TProc<Boolean>;
    FOnRefresh: TProc;
    FOnCancel: TProc;
    FOnClosed: TNotifyEvent;
    procedure BuildTop;
    procedure BuildBottom;
    procedure ListData(Sender: TObject; AItem: TListItem);
    procedure ListMouseDown(Sender: TObject; AButton: TMouseButton; AShift: TShiftState; AX, AY: Integer);
    procedure ListKeyDown(Sender: TObject; var AKey: Word; AShift: TShiftState);
    procedure ListSelect(Sender: TObject; AItem: TListItem; ASelected: Boolean);
    procedure ButtonClick(Sender: TObject);
    procedure ConsentClick(Sender: TObject);
    procedure FormClosed(Sender: TObject; var AAction: TCloseAction);
    procedure CopyText(const AText: string);
    procedure SetConsentVisible(AVisible: Boolean);
    function SelectedRecNo: Int64;
    function RowText(AIndex: Integer): string;
  public
    constructor CreateTable(AOwner: TComponent);
    /// <summary>Titel und Kopfzeile.</summary>
    procedure ShowHeader(const AExpression, AHeader: string);
    /// <summary>Spalten neu (leert die Zeilen).</summary>
    procedure SetColumns(const ANames: TArray<string>);
    /// <summary>Zeilen zeigen; ACurrentRecNo bekommt ▶. ACanLoadMore gibt „Weitere laden“ frei, ACanMove Springen.
    /// </summary>
    procedure SetRows(const ARows: TArray<TAtlasDataSetRow>; ACurrentRecNo: Int64; ACanLoadMore, ACanMove: Boolean);
    /// <summary>Hinweis zur Cursorbewegung mit den beiden Knöpfen; '' blendet ihn aus.</summary>
    procedure ShowConsent(const ANote: string; APageSize: Integer);
    /// <summary>Tipp zur Unit Atlas.Debug.DataSets zeigen oder ausblenden.</summary>
    procedure ShowHint(AVisible: Boolean);
    procedure SetStatus(const AText: string);
    /// <summary>Beschriftung „Weitere n laden“.</summary>
    procedure SetPageSize(APageSize: Integer);
    /// <summary>Während des Lesens: nur „Abbrechen“ frei.</summary>
    procedure SetReading(AValue: Boolean);
    /// <summary>Programm läuft weiter: Tabelle ausgrauen, AReason in den Stand.</summary>
    procedure MarkUnavailable(const AReason: string);
    /// <summary>Markierte Zeilen als Text (Zellen durch Tabulator); '' ohne Markierung.</summary>
    function SelectedText: string;
    property Names: TArray<string> read FNames;
    property Rows: TArray<TAtlasDataSetRow> read FRows;
    property List: TAtlasListView read FList;
    property HeaderLabel: TLabel read FHeader;
    property StatusLabel: TLabel read FStatus;
    property ConsentRow: TFlowPanel read FConsentRow;
    property HintLabel: TLabel read FHint;
    property LoadMoreButton: TButton read FLoadMoreButton;
    property GoToButton: TButton read FGoToButton;
    property EditButton: TButton read FEditButton;
    property CancelButton: TButton read FCancelButton;
    /// <summary>Zuletzt angeklicktes Feld (ab 0); -1 ohne.</summary>
    property ClickedField: Integer read FClickedField write FClickedField;
    property OnLoadMore: TProc read FOnLoadMore write FOnLoadMore;
    property OnGoTo: TProc<Int64> read FOnGoTo write FOnGoTo;
    property OnEdit: TAtlasDataSetCellProc read FOnEdit write FOnEdit;
    /// <summary>True: Cursor bewegen und lesen; False: nur aktueller Datensatz.</summary>
    property OnConsent: TProc<Boolean> read FOnConsent write FOnConsent;
    property OnRefresh: TProc read FOnRefresh write FOnRefresh;
    property OnCancel: TProc read FOnCancel write FOnCancel;
    property OnClosed: TNotifyEvent read FOnClosed write FOnClosed;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.CommCtrl,
  System.Types,
  System.UITypes,
  Vcl.Graphics,
  Vcl.Clipbrd,
  Atlas.Core.Settings.Plugin.Debug,
  Atlas.Vcl.Controls.WrapLabel,
  Atlas.UI.Debug.DataSetTable.Strings;

const
  cFormWidth = 760;
  cFormHeight = 480;
  cGap = 8;
  cButtonPadding = 24;
  /// <summary>Spaltenbreiten (Nummer, Felder) und Mindestbreite der letzten Spalte, logische Pixel.</summary>
  cRecNoWidth = 64;
  cFieldWidth = 140;
  cFillMinWidth = 100;
  cCurrentMark = '▶ ';

{ TAtlasDebugDataSetForm }

constructor TAtlasDebugDataSetForm.CreateTable(AOwner: TComponent);
begin
  inherited CreateDialog(AOwner, '', cFormWidth);
  BorderStyle := bsSizeable;
  BorderIcons := [biSystemMenu, biMaximize];
  Position := poMainFormCenter;
  ClientHeight := ScaleValue(cFormHeight);
  OnClose := FormClosed;
  FClickedField := -1;
  BuildBottom;
  BuildTop;
  FList := TAtlasListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.AlignWithMargins := True;
  FList.Margins.SetBounds(ScaleValue(cGap), ScaleValue(cGap), ScaleValue(cGap), 0);
  FList.OwnerData := True;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  FList.MultiSelect := True;
  FList.HideSelection := False;
  FList.OnData := ListData;
  FList.OnMouseDown := ListMouseDown;
  FList.OnKeyDown := ListKeyDown;
  FList.OnSelectItem := ListSelect;
  SetReading(False);
end;

procedure TAtlasDebugDataSetForm.BuildTop;
begin
  FHeader := TAtlasWrapLabel.Create(Self);
  FHeader.Parent := Self;
  FHeader.Align := alTop;
  FHeader.AlignWithMargins := True;
  FHeader.Margins.SetBounds(ScaleValue(cGap), ScaleValue(cGap), ScaleValue(cGap), 0);
  FHeader.ShowAccelChar := False;
  FHeader.Font.Style := [fsBold];

  // Hinweis über den Knöpfen; bricht mit der Fensterbreite um.
  FConsentNote := TAtlasWrapLabel.Create(Self);
  FConsentNote.Top := FHeader.Top + FHeader.Height + 1;
  FConsentNote.Parent := Self;
  FConsentNote.Align := alTop;
  FConsentNote.AlignWithMargins := True;
  FConsentNote.Margins.SetBounds(ScaleValue(cGap), ScaleValue(cGap), ScaleValue(cGap), 0);
  FConsentNote.ShowAccelChar := False;
  FConsentRow := NewFlowRow(cGap);
  FConsentRow.Top := FConsentNote.Top + FConsentNote.Height + 1;
  FConsentButton := NewTextButton(FConsentRow, '', cButtonPadding, cGap);
  FConsentButton.OnClick := ConsentClick;
  FCurrentButton := NewTextButton(FConsentRow,
    TAtlasDataSetTableStrings.Text(TAtlasDataSetTableTextId.ConsentCurrentOnly), cButtonPadding, cGap);
  FCurrentButton.OnClick := ConsentClick;
  SetConsentVisible(False);

  FHint := TAtlasWrapLabel.Create(Self);
  FHint.Top := FConsentRow.Top + FConsentRow.Height + 1;
  FHint.Parent := Self;
  FHint.Align := alTop;
  FHint.AlignWithMargins := True;
  FHint.Margins.SetBounds(ScaleValue(cGap), ScaleValue(cGap div 2), ScaleValue(cGap), 0);
  FHint.ShowAccelChar := False;
  FHint.Caption := TAtlasDataSetTableStrings.Text(TAtlasDataSetTableTextId.HelperHint);
  FHint.Visible := False;
end;

/// <summary>Unten der Stand, darüber die Knöpfe (fließend: Bei schmalem Fenster brechen sie um).</summary>
procedure TAtlasDebugDataSetForm.BuildBottom;
begin
  FStatus := TAtlasWrapLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.Align := alBottom;
  FStatus.AlignWithMargins := True;
  FStatus.Margins.SetBounds(ScaleValue(cGap), 0, ScaleValue(cGap), ScaleValue(cGap));
  FStatus.ShowAccelChar := False;

  FBar := TFlowPanel.Create(Self);
  FBar.Top := FStatus.Top - 1;
  FBar.Parent := Self;
  FBar.Align := alBottom;
  FBar.AlignWithMargins := True;
  FBar.Margins.SetBounds(ScaleValue(cGap), ScaleValue(cGap), ScaleValue(cGap), 0);
  FBar.BevelOuter := bvNone;
  FBar.ShowCaption := False;
  FBar.ParentBackground := True;
  FBar.AutoWrap := True;
  FBar.AutoSize := True;
  FLoadMoreButton := NewTextButton(FBar, TAtlasDataSetTableStrings.Fmt(TAtlasDataSetTableTextId.LoadMore,
    [cDefaultDataSetTablePageSize]), cButtonPadding, cGap);
  FGoToButton := NewTextButton(FBar, TAtlasDataSetTableStrings.Text(TAtlasDataSetTableTextId.GoToRecord),
    cButtonPadding, cGap);
  FEditButton := NewTextButton(FBar, TAtlasDataSetTableStrings.Text(TAtlasDataSetTableTextId.EditValue),
    cButtonPadding, cGap);
  FCopyCsvButton := NewTextButton(FBar, TAtlasDataSetTableStrings.Text(TAtlasDataSetTableTextId.CopyCsv),
    cButtonPadding, cGap);
  FCopyJsonButton := NewTextButton(FBar, TAtlasDataSetTableStrings.Text(TAtlasDataSetTableTextId.CopyJson),
    cButtonPadding, cGap);
  FRefreshButton := NewTextButton(FBar, TAtlasDataSetTableStrings.Text(TAtlasDataSetTableTextId.Refresh),
    cButtonPadding, cGap);
  FCancelButton := NewTextButton(FBar, TAtlasDataSetTableStrings.Text(TAtlasDataSetTableTextId.Cancel),
    cButtonPadding, cGap);
  FLoadMoreButton.OnClick := ButtonClick;
  FGoToButton.OnClick := ButtonClick;
  FEditButton.OnClick := ButtonClick;
  FCopyCsvButton.OnClick := ButtonClick;
  FCopyJsonButton.OnClick := ButtonClick;
  FRefreshButton.OnClick := ButtonClick;
  FCancelButton.OnClick := ButtonClick;
end;

procedure TAtlasDebugDataSetForm.ListData(Sender: TObject; AItem: TListItem);
var
  mRow: TAtlasDataSetRow;
  mIndex: Integer;
  mCaption: string;
begin
  if (AItem.Index < 0) or (AItem.Index >= Length(FRows)) then
  begin
    Exit;
  end;
  mRow := FRows[AItem.Index];
  mCaption := IntToStr(mRow.RecNo);
  if mRow.RecNo = FCurrentRecNo then
  begin
    mCaption := cCurrentMark + mCaption;
  end;
  AItem.Caption := mCaption;
  for mIndex := 0 to High(mRow.Cells) do
  begin
    if (mIndex < Length(mRow.Nulls)) and mRow.Nulls[mIndex] then
    begin
      AItem.SubItems.Add(TAtlasDataSetTableStrings.Text(TAtlasDataSetTableTextId.NullValue));
    end
    else
    begin
      AItem.SubItems.Add(mRow.Cells[mIndex]);
    end;
  end;
end;

/// <summary>Spalte unter der Maus merken: „Wert ändern …“ gilt für sie.</summary>
procedure TAtlasDebugDataSetForm.ListMouseDown(Sender: TObject; AButton: TMouseButton; AShift: TShiftState;
  AX, AY: Integer);
var
  mHit: TLVHitTestInfo;
begin
  FillChar(mHit, SizeOf(mHit), 0);
  mHit.pt := System.Types.Point(AX, AY);
  if ListView_SubItemHitTest(FList.Handle, @mHit) >= 0 then
  begin
    // Spalte 0 ist die Nummer des Datensatzes.
    FClickedField := mHit.iSubItem - 1;
  end;
  SetReading(FReading);
end;

procedure TAtlasDebugDataSetForm.ListKeyDown(Sender: TObject; var AKey: Word; AShift: TShiftState);
begin
  if (AKey = Ord('C')) and (AShift = [ssCtrl]) then
  begin
    AKey := 0;
    CopyText(SelectedText);
  end
  else if (AKey = VK_ESCAPE) and (AShift = []) then
  begin
    AKey := 0;
    Close;
  end;
end;

procedure TAtlasDebugDataSetForm.ListSelect(Sender: TObject; AItem: TListItem; ASelected: Boolean);
begin
  SetReading(FReading);
end;

procedure TAtlasDebugDataSetForm.ButtonClick(Sender: TObject);
begin
  if (Sender = FLoadMoreButton) and Assigned(FOnLoadMore) then
  begin
    FOnLoadMore();
  end
  else if (Sender = FGoToButton) and Assigned(FOnGoTo) and (SelectedRecNo > 0) then
  begin
    FOnGoTo(SelectedRecNo);
  end
  else if (Sender = FEditButton) and Assigned(FOnEdit) and (SelectedRecNo > 0) and (FClickedField >= 0) then
  begin
    FOnEdit(SelectedRecNo, FClickedField);
  end
  else if Sender = FCopyCsvButton then
  begin
    CopyText(TAtlasDataSetTable.ToCsv(FNames, FRows));
  end
  else if Sender = FCopyJsonButton then
  begin
    CopyText(TAtlasDataSetTable.ToJson(FNames, FRows));
  end
  else if (Sender = FRefreshButton) and Assigned(FOnRefresh) then
  begin
    FOnRefresh();
  end
  else if (Sender = FCancelButton) and Assigned(FOnCancel) then
  begin
    FOnCancel();
  end;
end;

procedure TAtlasDebugDataSetForm.SetConsentVisible(AVisible: Boolean);
begin
  FConsentNote.Visible := AVisible;
  FConsentRow.Visible := AVisible;
end;

procedure TAtlasDebugDataSetForm.ConsentClick(Sender: TObject);
begin
  SetConsentVisible(False);
  if Assigned(FOnConsent) then
  begin
    FOnConsent(Sender = FConsentButton);
  end;
end;

procedure TAtlasDebugDataSetForm.FormClosed(Sender: TObject; var AAction: TCloseAction);
begin
  AAction := caFree;
  if Assigned(FOnClosed) then
  begin
    FOnClosed(Self);
  end;
end;

procedure TAtlasDebugDataSetForm.CopyText(const AText: string);
begin
  if AText <> '' then
  begin
    Clipboard.AsText := AText;
  end;
end;

function TAtlasDebugDataSetForm.SelectedRecNo: Int64;
begin
  Result := 0;
  if (FList.Selected <> nil) and (FList.Selected.Index < Length(FRows)) then
  begin
    Result := FRows[FList.Selected.Index].RecNo;
  end;
end;

function TAtlasDebugDataSetForm.RowText(AIndex: Integer): string;
begin
  Result := '';
  if (AIndex >= 0) and (AIndex < Length(FRows)) then
  begin
    Result := IntToStr(FRows[AIndex].RecNo) + #9 + string.Join(#9, FRows[AIndex].Cells);
  end;
end;

function TAtlasDebugDataSetForm.SelectedText: string;
var
  mLines: TStringList;
  mItem: TListItem;
begin
  mLines := TStringList.Create;
  try
    mItem := FList.Selected;
    while mItem <> nil do
    begin
      mLines.Add(RowText(mItem.Index));
      mItem := FList.GetNextItem(mItem, sdAll, [isSelected]);
    end;
    Result := TrimRight(mLines.Text);
  finally
    mLines.Free;
  end;
end;

procedure TAtlasDebugDataSetForm.ShowHeader(const AExpression, AHeader: string);
begin
  Caption := TAtlasDataSetTableStrings.Fmt(TAtlasDataSetTableTextId.Title, [AExpression]);
  FHeader.Caption := AHeader;
  FHeader.Enabled := True;
end;

procedure TAtlasDebugDataSetForm.SetColumns(const ANames: TArray<string>);
var
  mName: string;
begin
  FNames := Copy(ANames);
  FRows := nil;
  FClickedField := -1;
  FList.Items.BeginUpdate;
  try
    FList.Items.Count := 0;
    FList.Columns.Clear;
    FList.AddColumn(TAtlasDataSetTableStrings.Text(TAtlasDataSetTableTextId.ColumnRecord), cRecNoWidth,
      taRightJustify);
    for mName in FNames do
    begin
      FList.AddColumn(mName, cFieldWidth);
    end;
    FList.FillColumn(FList.Columns.Count - 1, cFillMinWidth);
    FList.ShowColumnHeaders := True;
  finally
    FList.Items.EndUpdate;
  end;
end;

procedure TAtlasDebugDataSetForm.SetRows(const ARows: TArray<TAtlasDataSetRow>; ACurrentRecNo: Int64;
  ACanLoadMore, ACanMove: Boolean);
begin
  FRows := Copy(ARows);
  FCurrentRecNo := ACurrentRecNo;
  FCanLoadMore := ACanLoadMore;
  FCanMove := ACanMove;
  FList.Enabled := True;
  if FList.HandleAllocated then
  begin
    FList.Items.Count := Length(FRows);
    FList.Invalidate;
  end;
  SetReading(FReading);
end;

procedure TAtlasDebugDataSetForm.ShowConsent(const ANote: string; APageSize: Integer);
begin
  SetConsentVisible(ANote <> '');
  if ANote = '' then
  begin
    Exit;
  end;
  FConsentNote.Caption := ANote;
  FConsentButton.Caption := TAtlasDataSetTableStrings.Fmt(TAtlasDataSetTableTextId.ConsentRead, [APageSize]);
  FConsentButton.Width := TextWidth(FConsentButton.Font, FConsentButton.Caption) + ScaleValue(cButtonPadding);
end;

procedure TAtlasDebugDataSetForm.ShowHint(AVisible: Boolean);
begin
  FHint.Visible := AVisible;
end;

procedure TAtlasDebugDataSetForm.SetStatus(const AText: string);
begin
  FStatus.Caption := AText;
end;

procedure TAtlasDebugDataSetForm.SetPageSize(APageSize: Integer);
begin
  FLoadMoreButton.Caption := TAtlasDataSetTableStrings.Fmt(TAtlasDataSetTableTextId.LoadMore, [APageSize]);
  FLoadMoreButton.Width := TextWidth(FLoadMoreButton.Font, FLoadMoreButton.Caption) + ScaleValue(cButtonPadding);
end;

procedure TAtlasDebugDataSetForm.SetReading(AValue: Boolean);
var
  mSelected: Boolean;
begin
  FReading := AValue;
  mSelected := SelectedRecNo > 0;
  FLoadMoreButton.Enabled := not AValue and FCanLoadMore;
  FGoToButton.Enabled := not AValue and FCanMove and mSelected;
  FEditButton.Enabled := not AValue and mSelected and (FClickedField >= 0) and (FClickedField < Length(FNames));
  FCopyCsvButton.Enabled := not AValue and (FRows <> nil);
  FCopyJsonButton.Enabled := FCopyCsvButton.Enabled;
  FRefreshButton.Enabled := not AValue;
  FCancelButton.Enabled := AValue;
  FConsentButton.Enabled := not AValue;
  FCurrentButton.Enabled := not AValue;
end;

procedure TAtlasDebugDataSetForm.MarkUnavailable(const AReason: string);
begin
  FHeader.Enabled := False;
  FList.Enabled := False;
  SetConsentVisible(False);
  FCanLoadMore := False;
  FCanMove := False;
  SetReading(False);
  FRefreshButton.Enabled := False;
  FEditButton.Enabled := False;
  FStatus.Caption := AReason;
end;

end.
