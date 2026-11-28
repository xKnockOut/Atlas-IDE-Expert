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

  /// <summary>Steuerelemente des Fensters.</summary>
  TAtlasDataSetFormParts = record
    Header: TLabel;
    ConsentNote: TLabel;
    ConsentRow: TFlowPanel;
    ConsentButton: TButton;
    CurrentButton: TButton;
    Hint: TLabel;
    List: TAtlasListView;
    Bar: TFlowPanel;
    Status: TLabel;
    LoadMoreButton: TButton;
    GoToButton: TButton;
    EditButton: TButton;
    CopyCsvButton: TButton;
    CopyJsonButton: TButton;
    RefreshButton: TButton;
    CancelButton: TButton;
  end;

  /// <summary>Was die Knöpfe auslösen; nil: nichts.</summary>
  TAtlasDataSetFormEvents = record
    OnLoadMore: TProc;
    OnGoTo: TProc<Int64>;
    OnEdit: TAtlasDataSetCellProc;
    /// <summary>True: Cursor bewegen und lesen; False: nur aktueller Datensatz.</summary>
    OnConsent: TProc<Boolean>;
    OnRefresh: TProc;
    OnCancel: TProc;
    /// <summary>Das Fenster schließt und gibt sich frei.</summary>
    OnClosed: TProc;
  end;

  TAtlasDebugDataSetForm = class(TAtlasDialog)
  private
    FParts: TAtlasDataSetFormParts;
    FEvents: TAtlasDataSetFormEvents;
    FNames: TArray<string>;
    FRows: TArray<TAtlasDataSetRow>;
    FCurrentRecNo: Int64;
    FClickedField: Integer;
    FReading: Boolean;
    FCanLoadMore: Boolean;
    FCanMove: Boolean;
    FEmbedded: Boolean;
    procedure BuildTop;
    procedure BuildBottom;
    procedure ListData(Sender: TObject; AItem: TListItem);
    procedure ListMouseDown(Sender: TObject; AButton: TMouseButton; AShift: TShiftState; AX, AY: Integer);
    procedure ListKeyDown(Sender: TObject; var AKey: Word; AShift: TShiftState);
    procedure ListSelect(Sender: TObject; AItem: TListItem; ASelected: Boolean);
    procedure ButtonClick(Sender: TObject);
    /// <summary>„Zum Datensatz springen“ und „Wert ändern …“ für den markierten Datensatz.</summary>
    procedure RecordClick(Sender: TObject);
    procedure ConsentClick(Sender: TObject);
    procedure FormClosed(Sender: TObject; var AAction: TCloseAction);
    procedure SetConsentVisible(AVisible: Boolean);
    function SelectedRecNo: Int64;
    function RowText(AIndex: Integer): string;
  public
    constructor CreateTable(AOwner: TComponent);
    /// <summary>Meldet OnClosed auch, wenn die Fläche, in der die Tabelle steckt, sie freigibt.</summary>
    destructor Destroy; override;
    /// <summary>Ohne Rahmen in AHost einsetzen (Ansicht „Tabelle“ im Fenster „Auswerten“); Esc schließt dann nicht.
    /// </summary>
    procedure EmbedIn(AHost: TWinControl);
    /// <summary>Ereignisse der Knöpfe setzen; Default(TAtlasDataSetFormEvents) löst alle.</summary>
    procedure Connect(const AEvents: TAtlasDataSetFormEvents);
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
    property Parts: TAtlasDataSetFormParts read FParts;
    /// <summary>Zuletzt angeklicktes Feld (ab 0); -1 ohne.</summary>
    property ClickedField: Integer read FClickedField write FClickedField;
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
  Atlas.Plugin.Calls.Optional,
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

procedure CopyText(const AText: string);
begin
  if AText <> '' then
  begin
    Clipboard.AsText := AText;
  end;
end;

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
  FParts.List := TAtlasListView.Create(Self);
  FParts.List.Parent := Self;
  FParts.List.Align := alClient;
  FParts.List.AlignWithMargins := True;
  FParts.List.Margins.SetBounds(ScaleValue(cGap), ScaleValue(cGap), ScaleValue(cGap), 0);
  FParts.List.OwnerData := True;
  FParts.List.ReadOnly := True;
  FParts.List.RowSelect := True;
  FParts.List.MultiSelect := True;
  FParts.List.HideSelection := False;
  FParts.List.OnData := ListData;
  FParts.List.OnMouseDown := ListMouseDown;
  FParts.List.OnKeyDown := ListKeyDown;
  FParts.List.OnSelectItem := ListSelect;
  SetReading(False);
end;

procedure TAtlasDebugDataSetForm.BuildTop;
begin
  FParts.Header := TAtlasWrapLabel.Create(Self);
  FParts.Header.Parent := Self;
  FParts.Header.Align := alTop;
  FParts.Header.AlignWithMargins := True;
  FParts.Header.Margins.SetBounds(ScaleValue(cGap), ScaleValue(cGap), ScaleValue(cGap), 0);
  FParts.Header.ShowAccelChar := False;
  FParts.Header.Font.Style := [fsBold];

  // Hinweis über den Knöpfen; bricht mit der Fensterbreite um.
  FParts.ConsentNote := TAtlasWrapLabel.Create(Self);
  FParts.ConsentNote.Top := FParts.Header.Top + FParts.Header.Height + 1;
  FParts.ConsentNote.Parent := Self;
  FParts.ConsentNote.Align := alTop;
  FParts.ConsentNote.AlignWithMargins := True;
  FParts.ConsentNote.Margins.SetBounds(ScaleValue(cGap), ScaleValue(cGap), ScaleValue(cGap), 0);
  FParts.ConsentNote.ShowAccelChar := False;
  FParts.ConsentRow := NewFlowRow(cGap);
  FParts.ConsentRow.Top := FParts.ConsentNote.Top + FParts.ConsentNote.Height + 1;
  FParts.ConsentButton := NewTextButton(FParts.ConsentRow, '', cButtonPadding, cGap);
  FParts.ConsentButton.OnClick := ConsentClick;
  FParts.CurrentButton := NewTextButton(FParts.ConsentRow,
    TAtlasDataSetTableStrings.Text(TAtlasDataSetTableTextId.ConsentCurrentOnly), cButtonPadding, cGap);
  FParts.CurrentButton.OnClick := ConsentClick;
  SetConsentVisible(False);

  FParts.Hint := TAtlasWrapLabel.Create(Self);
  FParts.Hint.Top := FParts.ConsentRow.Top + FParts.ConsentRow.Height + 1;
  FParts.Hint.Parent := Self;
  FParts.Hint.Align := alTop;
  FParts.Hint.AlignWithMargins := True;
  FParts.Hint.Margins.SetBounds(ScaleValue(cGap), ScaleValue(cGap div 2), ScaleValue(cGap), 0);
  FParts.Hint.ShowAccelChar := False;
  FParts.Hint.Caption := TAtlasDataSetTableStrings.Text(TAtlasDataSetTableTextId.HelperHint);
  FParts.Hint.Visible := False;
end;

/// <summary>Unten der Stand, darüber die Knöpfe (fließend: Bei schmalem Fenster brechen sie um).</summary>
procedure TAtlasDebugDataSetForm.BuildBottom;
begin
  FParts.Status := TAtlasWrapLabel.Create(Self);
  FParts.Status.Parent := Self;
  FParts.Status.Align := alBottom;
  FParts.Status.AlignWithMargins := True;
  FParts.Status.Margins.SetBounds(ScaleValue(cGap), 0, ScaleValue(cGap), ScaleValue(cGap));
  FParts.Status.ShowAccelChar := False;

  FParts.Bar := TFlowPanel.Create(Self);
  FParts.Bar.Top := FParts.Status.Top - 1;
  FParts.Bar.Parent := Self;
  FParts.Bar.Align := alBottom;
  FParts.Bar.AlignWithMargins := True;
  FParts.Bar.Margins.SetBounds(ScaleValue(cGap), ScaleValue(cGap), ScaleValue(cGap), 0);
  FParts.Bar.BevelOuter := bvNone;
  FParts.Bar.ShowCaption := False;
  FParts.Bar.ParentBackground := True;
  FParts.Bar.AutoWrap := True;
  FParts.Bar.AutoSize := True;
  FParts.LoadMoreButton := NewTextButton(FParts.Bar, TAtlasDataSetTableStrings.Fmt(TAtlasDataSetTableTextId.LoadMore,
    [cDefaultDataSetTablePageSize]), cButtonPadding, cGap);
  FParts.GoToButton := NewTextButton(FParts.Bar, TAtlasDataSetTableStrings.Text(TAtlasDataSetTableTextId.GoToRecord),
    cButtonPadding, cGap);
  FParts.EditButton := NewTextButton(FParts.Bar, TAtlasDataSetTableStrings.Text(TAtlasDataSetTableTextId.EditValue),
    cButtonPadding, cGap);
  FParts.CopyCsvButton := NewTextButton(FParts.Bar, TAtlasDataSetTableStrings.Text(TAtlasDataSetTableTextId.CopyCsv),
    cButtonPadding, cGap);
  FParts.CopyJsonButton := NewTextButton(FParts.Bar, TAtlasDataSetTableStrings.Text(TAtlasDataSetTableTextId.CopyJson),
    cButtonPadding, cGap);
  FParts.RefreshButton := NewTextButton(FParts.Bar, TAtlasDataSetTableStrings.Text(TAtlasDataSetTableTextId.Refresh),
    cButtonPadding, cGap);
  FParts.CancelButton := NewTextButton(FParts.Bar, TAtlasDataSetTableStrings.Text(TAtlasDataSetTableTextId.Cancel),
    cButtonPadding, cGap);
  FParts.LoadMoreButton.OnClick := ButtonClick;
  FParts.GoToButton.OnClick := RecordClick;
  FParts.EditButton.OnClick := RecordClick;
  FParts.CopyCsvButton.OnClick := ButtonClick;
  FParts.CopyJsonButton.OnClick := ButtonClick;
  FParts.RefreshButton.OnClick := ButtonClick;
  FParts.CancelButton.OnClick := ButtonClick;
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
  if ListView_SubItemHitTest(FParts.List.Handle, @mHit) >= 0 then
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
  else if (AKey = VK_ESCAPE) and (AShift = []) and not FEmbedded then
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
  if Sender = FParts.LoadMoreButton then
  begin
    TAtlasCalls.Call(FEvents.OnLoadMore);
  end
  else if Sender = FParts.CopyCsvButton then
  begin
    CopyText(TAtlasDataSetTable.ToCsv(FNames, FRows));
  end
  else if Sender = FParts.CopyJsonButton then
  begin
    CopyText(TAtlasDataSetTable.ToJson(FNames, FRows));
  end
  else if Sender = FParts.RefreshButton then
  begin
    TAtlasCalls.Call(FEvents.OnRefresh);
  end
  else if Sender = FParts.CancelButton then
  begin
    TAtlasCalls.Call(FEvents.OnCancel);
  end;
end;

procedure TAtlasDebugDataSetForm.RecordClick(Sender: TObject);
begin
  if SelectedRecNo <= 0 then
  begin
    Exit;
  end;
  if (Sender = FParts.GoToButton) and Assigned(FEvents.OnGoTo) then
  begin
    FEvents.OnGoTo(SelectedRecNo);
  end
  else if (Sender = FParts.EditButton) and Assigned(FEvents.OnEdit) and (FClickedField >= 0) then
  begin
    FEvents.OnEdit(SelectedRecNo, FClickedField);
  end;
end;

procedure TAtlasDebugDataSetForm.SetConsentVisible(AVisible: Boolean);
begin
  FParts.ConsentNote.Visible := AVisible;
  FParts.ConsentRow.Visible := AVisible;
end;

procedure TAtlasDebugDataSetForm.ConsentClick(Sender: TObject);
begin
  SetConsentVisible(False);
  if Assigned(FEvents.OnConsent) then
  begin
    FEvents.OnConsent(Sender = FParts.ConsentButton);
  end;
end;

procedure TAtlasDebugDataSetForm.FormClosed(Sender: TObject; var AAction: TCloseAction);
begin
  AAction := caFree;
  TAtlasCalls.Call(FEvents.OnClosed);
  // Einmal melden: Destroy folgt gleich und darf es nicht wiederholen.
  FEvents.OnClosed := nil;
end;

destructor TAtlasDebugDataSetForm.Destroy;
var
  mClosed: TProc;
begin
  // Eingebettet gibt die Fläche (das Fenster „Auswerten“) die Tabelle frei, ohne sie zu schließen.
  mClosed := FEvents.OnClosed;
  FEvents := Default(TAtlasDataSetFormEvents);
  TAtlasCalls.Call(mClosed);
  inherited Destroy;
end;

procedure TAtlasDebugDataSetForm.EmbedIn(AHost: TWinControl);
begin
  FEmbedded := True;
  BorderStyle := bsNone;
  Parent := AHost;
  Align := alClient;
  Visible := True;
end;

procedure TAtlasDebugDataSetForm.Connect(const AEvents: TAtlasDataSetFormEvents);
begin
  FEvents := AEvents;
end;

function TAtlasDebugDataSetForm.SelectedRecNo: Int64;
begin
  Result := 0;
  if (FParts.List.Selected <> nil) and (FParts.List.Selected.Index < Length(FRows)) then
  begin
    Result := FRows[FParts.List.Selected.Index].RecNo;
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
    mItem := FParts.List.Selected;
    while mItem <> nil do
    begin
      mLines.Add(RowText(mItem.Index));
      mItem := FParts.List.GetNextItem(mItem, sdAll, [isSelected]);
    end;
    Result := TrimRight(mLines.Text);
  finally
    mLines.Free;
  end;
end;

procedure TAtlasDebugDataSetForm.ShowHeader(const AExpression, AHeader: string);
begin
  Caption := TAtlasDataSetTableStrings.Fmt(TAtlasDataSetTableTextId.Title, [AExpression]);
  FParts.Header.Caption := AHeader;
  FParts.Header.Enabled := True;
end;

procedure TAtlasDebugDataSetForm.SetColumns(const ANames: TArray<string>);
var
  mName: string;
begin
  FNames := Copy(ANames);
  FRows := nil;
  FClickedField := -1;
  FParts.List.Items.BeginUpdate;
  try
    FParts.List.Items.Count := 0;
    FParts.List.Columns.Clear;
    FParts.List.AddColumn(TAtlasDataSetTableStrings.Text(TAtlasDataSetTableTextId.ColumnRecord), cRecNoWidth,
      taRightJustify);
    for mName in FNames do
    begin
      FParts.List.AddColumn(mName, cFieldWidth);
    end;
    FParts.List.FillColumn(FParts.List.Columns.Count - 1, cFillMinWidth);
    FParts.List.ShowColumnHeaders := True;
  finally
    FParts.List.Items.EndUpdate;
  end;
end;

procedure TAtlasDebugDataSetForm.SetRows(const ARows: TArray<TAtlasDataSetRow>; ACurrentRecNo: Int64;
  ACanLoadMore, ACanMove: Boolean);
begin
  FRows := Copy(ARows);
  FCurrentRecNo := ACurrentRecNo;
  FCanLoadMore := ACanLoadMore;
  FCanMove := ACanMove;
  FParts.List.Enabled := True;
  if FParts.List.HandleAllocated then
  begin
    FParts.List.Items.Count := Length(FRows);
    FParts.List.Invalidate;
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
  FParts.ConsentNote.Caption := ANote;
  FParts.ConsentButton.Caption := TAtlasDataSetTableStrings.Fmt(TAtlasDataSetTableTextId.ConsentRead, [APageSize]);
  FParts.ConsentButton.Width := TextWidth(FParts.ConsentButton.Font, FParts.ConsentButton.Caption) +
    ScaleValue(cButtonPadding);
end;

procedure TAtlasDebugDataSetForm.ShowHint(AVisible: Boolean);
begin
  FParts.Hint.Visible := AVisible;
end;

procedure TAtlasDebugDataSetForm.SetStatus(const AText: string);
begin
  FParts.Status.Caption := AText;
end;

procedure TAtlasDebugDataSetForm.SetPageSize(APageSize: Integer);
begin
  FParts.LoadMoreButton.Caption := TAtlasDataSetTableStrings.Fmt(TAtlasDataSetTableTextId.LoadMore, [APageSize]);
  FParts.LoadMoreButton.Width := TextWidth(FParts.LoadMoreButton.Font, FParts.LoadMoreButton.Caption) +
    ScaleValue(cButtonPadding);
end;

procedure TAtlasDebugDataSetForm.SetReading(AValue: Boolean);
var
  mSelected: Boolean;
begin
  FReading := AValue;
  mSelected := SelectedRecNo > 0;
  FParts.LoadMoreButton.Enabled := not AValue and FCanLoadMore;
  FParts.GoToButton.Enabled := not AValue and FCanMove and mSelected;
  FParts.EditButton.Enabled := not AValue and mSelected and (FClickedField >= 0) and (FClickedField < Length(FNames));
  FParts.CopyCsvButton.Enabled := not AValue and (FRows <> nil);
  FParts.CopyJsonButton.Enabled := FParts.CopyCsvButton.Enabled;
  FParts.RefreshButton.Enabled := not AValue;
  FParts.CancelButton.Enabled := AValue;
  FParts.ConsentButton.Enabled := not AValue;
  FParts.CurrentButton.Enabled := not AValue;
end;

procedure TAtlasDebugDataSetForm.MarkUnavailable(const AReason: string);
begin
  FParts.Header.Enabled := False;
  FParts.List.Enabled := False;
  SetConsentVisible(False);
  FCanLoadMore := False;
  FCanMove := False;
  SetReading(False);
  FParts.RefreshButton.Enabled := False;
  FParts.EditButton.Enabled := False;
  FParts.Status.Caption := AReason;
end;

end.
