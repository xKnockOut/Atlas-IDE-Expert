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
// - Thema und Schrift über TAtlasDialog (folgt jedem Themenwechsel), Spalten
//   in logischen Pixeln über TAtlasListView; die letzte Spalte füllt den Rest.
// - Das Bild zeichnet TAtlasDebugViewerImage (Atlas.UI.Debug.ViewerImage).

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
  Atlas.Core.Debug.Visualizers,
  Atlas.UI.Foundation.Dialog,
  Atlas.UI.Foundation.ListView,
  Atlas.UI.Debug.ViewerImage;

type
  TAtlasDebugViewer = class(TAtlasDialog)
  private
    FHeader: TLabel;
    FNote: TLabel;
    FAllFields: TCheckBox;
    FList: TAtlasListView;
    FTree: TTreeView;
    FImage: TAtlasDebugViewerImage;
    FColor: TPanel;
    FText: TMemo;
    FMenu: TPopupMenu;
    FView: TAtlasVisualizerView;
    FOnClosed: TNotifyEvent;
    procedure BuildListAndTree;
    procedure BuildImageAndText;
    procedure ListData(Sender: TObject; AItem: TListItem);
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
    /// <summary>Inhalt zeigen; AExpression steht im Titel.</summary>
    procedure ShowView(const AExpression: string; const AView: TAtlasVisualizerView);
    /// <summary>Inhalt ausgrauen, AReason darüber.</summary>
    procedure MarkUnavailable(const AReason: string);
    /// <summary>Markierte Zeilen bzw. Knoten als Text; '' ohne Markierung.</summary>
    function SelectedText: string;
    property View: TAtlasVisualizerView read FView;
    property HeaderLabel: TLabel read FHeader;
    property NoteLabel: TLabel read FNote;
    property List: TAtlasListView read FList;
    property AllFieldsCheck: TCheckBox read FAllFields;
    property Tree: TTreeView read FTree;
    property Image: TAtlasDebugViewerImage read FImage;
    property OnClosed: TNotifyEvent read FOnClosed write FOnClosed;
  end;

implementation

uses
  Atlas.Core.Debug.Visualizers.Format,
  System.Types,
  System.Math,
  Vcl.Clipbrd,
  Atlas.UI.Debug.Values.Strings,
  Atlas.UI.Foundation.WrapLabel;

const
  cViewerWidth = 560;
  cViewerHeight = 420;
  cGap = 8;
  cColorSize = 96;
  /// <summary>Spaltenbreiten der Tabelle (Index, übrige) und Mindestbreite der füllenden letzten Spalte, logische
  /// Pixel.</summary>
  cIndexWidth = 56;
  cColumnWidth = 160;
  cFillMinWidth = 120;

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
  Result := TAtlasWrapLabel.Create(AForm);
  PlaceTop(Result, AForm, ATopGap);
  Result.ShowAccelChar := False;
end;

/// <summary>Kontextmenü mit „Kopieren“ (Strg+C).</summary>
function CopyMenu(AForm: TForm; const AOnCopy: TNotifyEvent): TPopupMenu;
var
  mItem: TMenuItem;
begin
  Result := TPopupMenu.Create(AForm);
  mItem := TMenuItem.Create(Result);
  mItem.Caption := TAtlasValuesStrings.Text(TAtlasValuesTextId.DebugViewerCopy);
  mItem.ShortCut := ShortCut(Ord('C'), [ssCtrl]);
  mItem.OnClick := AOnCopy;
  Result.Items.Add(mItem);
end;

/// <summary>Überschrift der Tabellenspalte AColumn.</summary>
function ColumnCaption(AColumn: TAtlasVisualizerColumn): string;
begin
  case AColumn of
    TAtlasVisualizerColumn.Index:
      Result := TAtlasValuesStrings.Text(TAtlasValuesTextId.DebugViewerColumnIndex);
    TAtlasVisualizerColumn.Key:
      Result := TAtlasValuesStrings.Text(TAtlasValuesTextId.DebugViewerColumnKey);
    TAtlasVisualizerColumn.Field:
      Result := TAtlasValuesStrings.Text(TAtlasValuesTextId.DebugViewerColumnField);
    TAtlasVisualizerColumn.FieldType:
      Result := TAtlasValuesStrings.Text(TAtlasValuesTextId.DebugViewerColumnFieldType);
    TAtlasVisualizerColumn.OldValue:
      Result := TAtlasValuesStrings.Text(TAtlasValuesTextId.DebugViewerColumnOldValue);
  else
    Result := TAtlasValuesStrings.Text(TAtlasValuesTextId.DebugViewerColumnValue);
  end;
end;

{ TAtlasDebugViewer }

constructor TAtlasDebugViewer.CreateViewer(AOwner: TComponent);
begin
  inherited CreateDialog(AOwner, '', cViewerWidth);
  BorderStyle := bsSizeable;
  BorderIcons := [biSystemMenu, biMaximize];
  // Der Aufrufer setzt die Lage (neben dem Ausdruck).
  Position := poDesigned;
  ClientHeight := ScaleValue(cViewerHeight);
  OnClose := ViewerClose;
  FMenu := CopyMenu(Self, CopyClick);

  FHeader := TopLabel(Self, cGap);
  FHeader.Font.Style := [fsBold];

  FNote := TopLabel(Self, cGap div 2);
  FNote.Visible := False;
  FNote.Top := FHeader.Top + FHeader.Height + 1;

  FAllFields := TCheckBox.Create(Self);
  PlaceTop(FAllFields, Self, cGap div 2);
  FAllFields.Caption := TAtlasValuesStrings.Text(TAtlasValuesTextId.DebugViewerAllFields);
  FAllFields.Visible := False;
  FAllFields.Top := FNote.Top + FNote.Height + 1;
  FAllFields.OnClick := AllFieldsClick;

  BuildListAndTree;
  BuildImageAndText;
  HideContent;
end;

procedure TAtlasDebugViewer.BuildListAndTree;
begin
  FList := TAtlasListView.Create(Self);
  PlaceClient(FList, Self);
  FList.OwnerData := True;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  FList.MultiSelect := True;
  FList.HideSelection := False;
  FList.OnData := ListData;
  FList.OnKeyDown := ContentKeyDown;
  FList.PopupMenu := FMenu;

  FTree := TTreeView.Create(Self);
  PlaceClient(FTree, Self);
  FTree.ReadOnly := True;
  FTree.HideSelection := False;
  FTree.OnKeyDown := ContentKeyDown;
  FTree.PopupMenu := FMenu;
end;

procedure TAtlasDebugViewer.BuildImageAndText;
begin
  FImage := TAtlasDebugViewerImage.Create(Self);
  PlaceClient(FImage, Self);

  FColor := TPanel.Create(Self);
  PlaceTop(FColor, Self, cGap);
  FColor.Height := ScaleValue(cColorSize);
  FColor.BevelOuter := bvNone;
  FColor.ParentBackground := False;
  // Die Fläche zeigt die Farbe des Werts, nicht die des Themas.
  FColor.StyleElements := [];

  FText := TMemo.Create(Self);
  PlaceClient(FText, Self);
  FText.ReadOnly := True;
  FText.ScrollBars := ssBoth;
  FText.WordWrap := False;
  FText.Font.Name := 'Consolas';
end;

procedure TAtlasDebugViewer.ListData(Sender: TObject; AItem: TListItem);
var
  mRows: TArray<TArray<string>>;
  mCells: TArray<string>;
  mIndex: Integer;
begin
  if FView.Mode = TAtlasVisualizerViewMode.Hex then
  begin
    AItem.Caption := TAtlasVisualizerFormat.HexLineAt(FView.Bytes, AItem.Index);
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

procedure TAtlasDebugViewer.AllFieldsClick(Sender: TObject);
begin
  if FView.Mode = TAtlasVisualizerViewMode.Table then
  begin
    ShowTable;
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
  FImage.Visible := False;
  FColor.Visible := False;
  FText.Visible := False;
end;

procedure TAtlasDebugViewer.ShowTable;
var
  mColumn: TAtlasVisualizerColumn;
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
      if mColumn = TAtlasVisualizerColumn.Index then
      begin
        FList.AddColumn(ColumnCaption(mColumn), cIndexWidth);
      end
      else
      begin
        FList.AddColumn(ColumnCaption(mColumn), cColumnWidth);
      end;
    end;
    // Die letzte Spalte füllt den Rest.
    FList.FillColumn(FList.Columns.Count - 1, cFillMinWidth);
    FList.ShowColumnHeaders := True;
    FList.Items.Count := Length(CurrentRows);
  finally
    FList.Items.EndUpdate;
  end;
  FList.Visible := True;
end;

procedure TAtlasDebugViewer.ShowHex;
begin
  FList.Items.BeginUpdate;
  try
    FList.Items.Count := 0;
    FList.Columns.Clear;
    FList.Font.Name := 'Consolas';
    FList.AddColumn('', cFillMinWidth);
    FList.FillColumn(0, cFillMinWidth);
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
begin
  FImage.ShowPixels(FView.Width, FView.Height, FView.Pixels);
  FImage.Visible := True;
end;

procedure TAtlasDebugViewer.ShowColor;
begin
  FColor.Color := TColor(TAtlasVisualizerFormat.RgbToColor(FView.Color));
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
    Result := TAtlasVisualizerFormat.HexLineAt(FView.Bytes, AIndex);
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

procedure TAtlasDebugViewer.ShowView(const AExpression: string; const AView: TAtlasVisualizerView);
begin
  FView := AView;
  Caption := Format(TAtlasValuesStrings.Text(TAtlasValuesTextId.DebugViewerTitle), [AExpression]);
  FHeader.Caption := AView.Summary;
  FHeader.Enabled := True;
  FNote.Visible := AView.NeedsMore;
  FNote.Caption := TAtlasValuesStrings.Text(TAtlasValuesTextId.DebugViewerNeedsMore);
  FAllFields.Visible := (AView.Mode = TAtlasVisualizerViewMode.Table) and (AView.AllRows <> nil);
  FAllFields.Enabled := True;
  HideContent;
  FList.Enabled := True;
  FTree.Enabled := True;
  FImage.Enabled := True;
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
      FText.Text := TAtlasValuesStrings.Text(TAtlasValuesTextId.DebugViewerEmpty);
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
  FImage.Enabled := False;
  FText.Enabled := False;
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

end.
