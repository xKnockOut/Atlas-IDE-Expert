unit Atlas.UI.Debug.Viewer;

// Ansichtsfenster der Visualisierer (#835), reine VCL: zeigt eine
// TAtlasVisualizerView, die der Kern aus dem angehaltenen Programm liest.
// - Oben die Zusammenfassung (wie der Ersatztext, ungekürzt), darunter je nach
//   Art eine Tabelle (Liste, Dictionary, Datensatz mit altem Wert), Hex-Zeilen
//   (Adresse, Bytes, Text), ein Baum (JSON), ein Bild (in Originalgröße, mit
//   Rollbalken), ein Farbfeld oder Text.
// - Tabelle und Hex sind virtuell (OwnerData): Auch 16 MB Bytes oder 1000
//   Zeilen kosten nur die sichtbaren Zeilen.
// - Strg+C bzw. „Kopieren“ im Kontextmenü kopiert die markierten Zeilen
//   (Spalten durch Tabulator getrennt), im Baum den Knoten.
// - Läuft das Programm weiter oder ist der Ausdruck nicht mehr gültig, bleibt
//   der letzte Inhalt sichtbar, ausgegraut, mit dem Grund darüber
//   (MarkUnavailable); ShowView nach dem nächsten Halt füllt neu.
// - Eigene Wertdarstellung (#854): Zeigt die Tabelle nur die Unterelemente aus
//   atlas-debug-children (AllRows gesetzt), schaltet „Alle Felder“ auf die
//   ganze Feldliste um; die Wahl bleibt beim nächsten Halt erhalten.
// - Schließen gibt das Fenster frei und meldet OnClosed.

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.ExtCtrls,
  Vcl.Graphics,
  Vcl.Menus,
  Atlas.Core.Debug.Visualizers;

type
  TAtlasDebugViewer = class(TForm)
  private
    FHeader: TLabel;
    FNote: TLabel;
    FAllFields: TCheckBox;
    FList: TListView;
    FTree: TTreeView;
    FImageBox: TScrollBox;
    FImage: TPaintBox;
    FColor: TPanel;
    FText: TMemo;
    FMenu: TPopupMenu;
    FView: TAtlasVisualizerView;
    FBitmap: TBitmap;
    FOnClosed: TNotifyEvent;
    procedure ListData(Sender: TObject; AItem: TListItem);
    procedure ImagePaint(Sender: TObject);
    procedure AllFieldsClick(Sender: TObject);
    /// <summary>Angezeigte Tabellenzeilen: AllRows mit „Alle Felder“, sonst Rows.</summary>
    function CurrentRows: TArray<TArray<string>>;
    procedure ContentKeyDown(Sender: TObject; var AKey: Word; AShift: TShiftState);
    procedure CopyClick(Sender: TObject);
    procedure ViewerClose(Sender: TObject; var AAction: TCloseAction);
    procedure HideContent;
    procedure ShowTable;
    procedure ShowHex;
    procedure ShowTree;
    procedure ShowImage;
    procedure ShowColor;
    procedure ShowText;
    function RowText(AIndex: Integer): string;
  public
    constructor CreateViewer(AOwner: TComponent);
    destructor Destroy; override;
    /// <summary>Inhalt zeigen; AExpression steht im Titel.</summary>
    procedure ShowView(const AExpression: string; const AView: TAtlasVisualizerView);
    /// <summary>Inhalt ausgrauen, AReason darüber.</summary>
    procedure MarkUnavailable(const AReason: string);
    /// <summary>Markierte Zeilen bzw. Knoten als Text; '' ohne Markierung.</summary>
    function SelectedText: string;
    property View: TAtlasVisualizerView read FView;
    property HeaderLabel: TLabel read FHeader;
    property NoteLabel: TLabel read FNote;
    property List: TListView read FList;
    property AllFieldsCheck: TCheckBox read FAllFields;
    property Tree: TTreeView read FTree;
    property OnClosed: TNotifyEvent read FOnClosed write FOnClosed;
  end;

implementation

uses
  Atlas.Core.Debug.Visualizers.Format,
  System.Types,
  System.Math,
  Vcl.Clipbrd,
  Atlas.UI.Debug.Strings;

const
  cViewerWidth = 560;
  cViewerHeight = 420;
  cGap = 8;
  cColorSize = 96;

/// <summary>AControl oben in AForm, mit Rand Gap seitlich und ATopGap oben.</summary>
procedure PlaceTop(AControl: TControl; AForm: TForm; ATopGap: Integer);
begin
  AControl.Parent := AForm;
  AControl.Align := alTop;
  AControl.AlignWithMargins := True;
  AControl.Margins.SetBounds(AForm.ScaleValue(cGap), AForm.ScaleValue(ATopGap), AForm.ScaleValue(cGap), 0);
end;

/// <summary>AControl füllt AForm, mit Rand Gap ringsum.</summary>
procedure PlaceClient(AControl: TControl; AForm: TForm);
begin
  AControl.Parent := AForm;
  AControl.Align := alClient;
  AControl.AlignWithMargins := True;
  AControl.Margins.SetBounds(AForm.ScaleValue(cGap), AForm.ScaleValue(cGap), AForm.ScaleValue(cGap),
    AForm.ScaleValue(cGap));
end;

/// <summary>Umbrechende Beschriftung oben in AForm.</summary>
function TopLabel(AForm: TForm; ATopGap: Integer): TLabel;
begin
  Result := TLabel.Create(AForm);
  PlaceTop(Result, AForm, ATopGap);
  Result.WordWrap := True;
  Result.ShowAccelChar := False;
end;

/// <summary>Kontextmenü mit „Kopieren“ (Strg+C).</summary>
function CopyMenu(AForm: TForm; const AOnCopy: TNotifyEvent): TPopupMenu;
var
  mItem: TMenuItem;
begin
  Result := TPopupMenu.Create(AForm);
  mItem := TMenuItem.Create(Result);
  mItem.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugViewerCopy);
  mItem.ShortCut := ShortCut(Ord('C'), [ssCtrl]);
  mItem.OnClick := AOnCopy;
  Result.Items.Add(mItem);
end;

/// <summary>Tabelle und Baum des Betrachters AViewer.</summary>
procedure CreateListAndTree(AViewer: TAtlasDebugViewer);
begin
  AViewer.FList := TListView.Create(AViewer);
  PlaceClient(AViewer.FList, AViewer);
  AViewer.FList.ViewStyle := vsReport;
  AViewer.FList.OwnerData := True;
  AViewer.FList.ReadOnly := True;
  AViewer.FList.RowSelect := True;
  AViewer.FList.MultiSelect := True;
  AViewer.FList.HideSelection := False;
  AViewer.FList.OnData := AViewer.ListData;
  AViewer.FList.OnKeyDown := AViewer.ContentKeyDown;
  AViewer.FList.PopupMenu := AViewer.FMenu;

  AViewer.FTree := TTreeView.Create(AViewer);
  PlaceClient(AViewer.FTree, AViewer);
  AViewer.FTree.ReadOnly := True;
  AViewer.FTree.HideSelection := False;
  AViewer.FTree.OnKeyDown := AViewer.ContentKeyDown;
  AViewer.FTree.PopupMenu := AViewer.FMenu;
end;

/// <summary>Bild, Farbfläche und Text des Betrachters AViewer.</summary>
procedure CreateImageAndText(AViewer: TAtlasDebugViewer);
begin
  AViewer.FImageBox := TScrollBox.Create(AViewer);
  PlaceClient(AViewer.FImageBox, AViewer);
  AViewer.FImageBox.BorderStyle := bsNone;
  AViewer.FImage := TPaintBox.Create(AViewer);
  AViewer.FImage.Parent := AViewer.FImageBox;
  AViewer.FImage.OnPaint := AViewer.ImagePaint;

  AViewer.FColor := TPanel.Create(AViewer);
  PlaceTop(AViewer.FColor, AViewer, cGap);
  AViewer.FColor.Height := AViewer.ScaleValue(cColorSize);
  AViewer.FColor.BevelOuter := bvNone;
  AViewer.FColor.ParentBackground := False;

  AViewer.FText := TMemo.Create(AViewer);
  PlaceClient(AViewer.FText, AViewer);
  AViewer.FText.ReadOnly := True;
  AViewer.FText.ScrollBars := ssBoth;
  AViewer.FText.WordWrap := False;
  AViewer.FText.Font.Name := 'Consolas';
end;

/// <summary>Überschrift der Tabellenspalte AColumn.</summary>
function ColumnCaption(AColumn: TAtlasVisualizerColumn): string;
begin
  case AColumn of
    TAtlasVisualizerColumn.Index:
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugViewerColumnIndex);
    TAtlasVisualizerColumn.Key:
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugViewerColumnKey);
    TAtlasVisualizerColumn.Field:
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugViewerColumnField);
    TAtlasVisualizerColumn.FieldType:
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugViewerColumnFieldType);
    TAtlasVisualizerColumn.OldValue:
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugViewerColumnOldValue);
  else
    Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugViewerColumnValue);
  end;
end;

{ TAtlasDebugViewer }

constructor TAtlasDebugViewer.CreateViewer(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  BorderStyle := bsSizeable;
  BorderIcons := [biSystemMenu, biMaximize];
  Position := poDesigned;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  Width := ScaleValue(cViewerWidth);
  Height := ScaleValue(cViewerHeight);
  OnClose := ViewerClose;
  FMenu := CopyMenu(Self, CopyClick);

  FHeader := TopLabel(Self, cGap);
  FHeader.Font.Style := [fsBold];

  FNote := TopLabel(Self, cGap div 2);
  FNote.Visible := False;
  FNote.Top := FHeader.Top + FHeader.Height + 1;

  FAllFields := TCheckBox.Create(Self);
  PlaceTop(FAllFields, Self, cGap div 2);
  FAllFields.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugViewerAllFields);
  FAllFields.Visible := False;
  FAllFields.Top := FNote.Top + FNote.Height + 1;
  FAllFields.OnClick := AllFieldsClick;

  CreateListAndTree(Self);
  CreateImageAndText(Self);
  HideContent;
end;

destructor TAtlasDebugViewer.Destroy;
begin
  FBitmap.Free;
  inherited;
end;

procedure TAtlasDebugViewer.ViewerClose(Sender: TObject; var AAction: TCloseAction);
begin
  AAction := caFree;
  if Assigned(FOnClosed) then
  begin
    FOnClosed(Self);
  end;
end;

procedure TAtlasDebugViewer.HideContent;
begin
  FList.Visible := False;
  FTree.Visible := False;
  FImageBox.Visible := False;
  FColor.Visible := False;
  FText.Visible := False;
end;

procedure TAtlasDebugViewer.ShowView(const AExpression: string; const AView: TAtlasVisualizerView);
begin
  FView := AView;
  Caption := Format(TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugViewerTitle), [AExpression]);
  FHeader.Caption := AView.Summary;
  FHeader.Enabled := True;
  FNote.Visible := AView.NeedsMore;
  FNote.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugViewerNeedsMore);
  FAllFields.Visible := (AView.Mode = TAtlasVisualizerViewMode.Table) and (AView.AllRows <> nil);
  FAllFields.Enabled := True;
  HideContent;
  FList.Enabled := True;
  FTree.Enabled := True;
  FImageBox.Enabled := True;
  FText.Enabled := True;
  case AView.Mode of
    TAtlasVisualizerViewMode.Table:
      ShowTable;
    TAtlasVisualizerViewMode.Hex:
      ShowHex;
    TAtlasVisualizerViewMode.Tree:
      ShowTree;
    TAtlasVisualizerViewMode.Image:
      ShowImage;
    TAtlasVisualizerViewMode.Color:
      ShowColor;
    TAtlasVisualizerViewMode.Text:
      ShowText;
  else
    begin
      FText.Text := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugViewerEmpty);
      FText.Visible := True;
    end;
  end;
end;

procedure TAtlasDebugViewer.MarkUnavailable(const AReason: string);
begin
  FNote.Caption := AReason;
  FNote.Visible := True;
  FHeader.Enabled := False;
  FAllFields.Enabled := False;
  FList.Enabled := False;
  FTree.Enabled := False;
  FImageBox.Enabled := False;
  FText.Enabled := False;
end;

procedure TAtlasDebugViewer.ShowTable;
var
  mColumn: TAtlasVisualizerColumn;
  mListColumn: TListColumn;
  mIndex: Integer;
begin
  FList.Items.BeginUpdate;
  try
    FList.Items.Count := 0;
    FList.Columns.Clear;
    FList.Font.Name := Font.Name;
    for mIndex := 0 to High(FView.Columns) do
    begin
      mColumn := FView.Columns[mIndex];
      mListColumn := FList.Columns.Add;
      mListColumn.Caption := ColumnCaption(mColumn);
      if mColumn = TAtlasVisualizerColumn.Index then
      begin
        mListColumn.Width := ScaleValue(56);
      end
      else
      begin
        mListColumn.Width := ScaleValue(160);
      end;
    end;
    // Die letzte Spalte füllt den Rest.
    if FList.Columns.Count > 0 then
    begin
      FList.Columns[FList.Columns.Count - 1].AutoSize := True;
    end;
    FList.ShowColumnHeaders := True;
    FList.Items.Count := Length(CurrentRows);
  finally
    FList.Items.EndUpdate;
  end;
  FList.Visible := True;
end;

procedure TAtlasDebugViewer.ShowHex;
var
  mListColumn: TListColumn;
begin
  FList.Items.BeginUpdate;
  try
    FList.Items.Count := 0;
    FList.Columns.Clear;
    FList.Font.Name := 'Consolas';
    mListColumn := FList.Columns.Add;
    mListColumn.AutoSize := True;
    FList.ShowColumnHeaders := False;
    FList.Items.Count := TAtlasVisualizerFormat.HexLineCount(Length(FView.Bytes));
  finally
    FList.Items.EndUpdate;
  end;
  FList.Visible := True;
end;

procedure TAtlasDebugViewer.ShowTree;
var
  mParents: array of TTreeNode;
  mNode: TTreeNode;
  mIndex, mLevel: Integer;
begin
  FTree.Items.BeginUpdate;
  try
    FTree.Items.Clear;
    SetLength(mParents, 1);
    mParents[0] := nil;
    for mIndex := 0 to High(FView.Nodes) do
    begin
      mLevel := EnsureRange(FView.Nodes[mIndex].Level, 0, High(mParents));
      mNode := FTree.Items.AddChild(mParents[mLevel], FView.Nodes[mIndex].Text);
      SetLength(mParents, mLevel + 2);
      mParents[mLevel + 1] := mNode;
    end;
    if FTree.Items.Count > 0 then
    begin
      FTree.Items[0].Expand(False);
      FTree.Selected := FTree.Items[0];
    end;
  finally
    FTree.Items.EndUpdate;
  end;
  FTree.Visible := True;
end;

procedure TAtlasDebugViewer.ShowImage;
var
  mRow: Integer;
begin
  FreeAndNil(FBitmap);
  if (FView.Width > 0) and (FView.Height > 0) and (Length(FView.Pixels) = FView.Width * FView.Height) then
  begin
    FBitmap := TBitmap.Create;
    FBitmap.PixelFormat := pf32bit;
    FBitmap.SetSize(FView.Width, FView.Height);
    // $AARRGGBB liegt im Speicher als B, G, R, A: genau die Zeile eines 32-Bit-DIB.
    for mRow := 0 to FView.Height - 1 do
    begin
      Move(FView.Pixels[mRow * FView.Width], FBitmap.ScanLine[mRow]^, FView.Width * SizeOf(Cardinal));
    end;
    FImage.SetBounds(0, 0, FView.Width, FView.Height);
  end
  else
  begin
    FImage.SetBounds(0, 0, 0, 0);
  end;
  FImageBox.Visible := True;
  FImage.Invalidate;
end;

procedure TAtlasDebugViewer.ImagePaint(Sender: TObject);
const
  cCell = 8;
var
  X, Y: Integer;
begin
  if FBitmap = nil then
  begin
    Exit;
  end;
  // Schachbrett hinter dem Bild, damit Transparenz und Weiß erkennbar sind.
  for Y := 0 to (FImage.Height - 1) div cCell do
  begin
    for X := 0 to (FImage.Width - 1) div cCell do
    begin
      if Odd(X + Y) then
      begin
        FImage.Canvas.Brush.Color := $00E0E0E0;
      end
      else
      begin
        FImage.Canvas.Brush.Color := clWhite;
      end;
      FImage.Canvas.FillRect(Rect(X * cCell, Y * cCell, (X + 1) * cCell, (Y + 1) * cCell));
    end;
  end;
  FImage.Canvas.Draw(0, 0, FBitmap);
end;

procedure TAtlasDebugViewer.ShowColor;
begin
  // $RRGGBB → TColor ($00BBGGRR).
  FColor.Color := TColor(((FView.Color and $FF) shl 16) or (FView.Color and $FF00) or
    ((FView.Color shr 16) and $FF));
  FColor.Caption := '';
  FColor.Visible := True;
  FText.Text := FView.Text;
  FText.Visible := FView.Text <> '';
end;

procedure TAtlasDebugViewer.ShowText;
begin
  FText.Text := FView.Text;
  FText.Visible := True;
end;

function TAtlasDebugViewer.RowText(AIndex: Integer): string;
begin
  if FView.Mode = TAtlasVisualizerViewMode.Hex then
  begin
    Result := TAtlasVisualizerFormat.HexLine(FView.Bytes, AIndex * 16);
  end
  else if (AIndex >= 0) and (AIndex < Length(CurrentRows)) then
  begin
    Result := string.Join(#9, CurrentRows[AIndex]);
  end
  else
  begin
    Result := '';
  end;
end;

function TAtlasDebugViewer.CurrentRows: TArray<TArray<string>>;
begin
  if FAllFields.Visible and FAllFields.Checked then
  begin
    Result := FView.AllRows;
  end
  else
  begin
    Result := FView.Rows;
  end;
end;

procedure TAtlasDebugViewer.AllFieldsClick(Sender: TObject);
begin
  if FView.Mode = TAtlasVisualizerViewMode.Table then
  begin
    ShowTable;
  end;
end;

procedure TAtlasDebugViewer.ListData(Sender: TObject; AItem: TListItem);
var
  mRows: TArray<TArray<string>>;
  mCells: TArray<string>;
  mIndex: Integer;
begin
  if FView.Mode = TAtlasVisualizerViewMode.Hex then
  begin
    AItem.Caption := TAtlasVisualizerFormat.HexLine(FView.Bytes, AItem.Index * 16);
    Exit;
  end;
  mRows := CurrentRows;
  if (AItem.Index < 0) or (AItem.Index >= Length(mRows)) then
  begin
    Exit;
  end;
  mCells := mRows[AItem.Index];
  if Length(mCells) = 0 then
  begin
    Exit;
  end;
  AItem.Caption := mCells[0];
  for mIndex := 1 to High(mCells) do
  begin
    AItem.SubItems.Add(mCells[mIndex]);
  end;
end;

function TAtlasDebugViewer.SelectedText: string;
var
  mLines: TStringList;
  mItem: TListItem;
begin
  Result := '';
  if FTree.Visible then
  begin
    if FTree.Selected <> nil then
    begin
      Result := FTree.Selected.Text;
    end;
    Exit;
  end;
  if FText.Visible then
  begin
    Result := FText.SelText;
    if Result = '' then
    begin
      Result := FText.Text;
    end;
    Exit;
  end;
  if not FList.Visible then
  begin
    Exit;
  end;
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

procedure TAtlasDebugViewer.CopyClick(Sender: TObject);
var
  mText: string;
begin
  mText := SelectedText;
  if mText <> '' then
  begin
    Clipboard.AsText := mText;
  end;
end;

procedure TAtlasDebugViewer.ContentKeyDown(Sender: TObject; var AKey: Word; AShift: TShiftState);
begin
  if (AKey = Ord('C')) and (AShift = [ssCtrl]) then
  begin
    CopyClick(Sender);
    AKey := 0;
  end
  else if (AKey = VK_ESCAPE) and (AShift = []) then
  begin
    AKey := 0;
    Close;
  end;
end;

end.
