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
    function ColumnCaption(AColumn: TAtlasVisualizerColumn): string;
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
  Winapi.Windows,
  System.Types,
  System.Math,
  Vcl.Clipbrd,
  Atlas.UI.Strings;

const
  ViewerWidth = 560;
  ViewerHeight = 420;
  Gap = 8;
  ColorSize = 96;

{ TAtlasDebugViewer }

constructor TAtlasDebugViewer.CreateViewer(AOwner: TComponent);
var
  Item: TMenuItem;
begin
  inherited CreateNew(AOwner);
  BorderStyle := bsSizeable;
  BorderIcons := [biSystemMenu, biMaximize];
  Position := poDesigned;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  Width := ScaleValue(ViewerWidth);
  Height := ScaleValue(ViewerHeight);
  OnClose := ViewerClose;

  FMenu := TPopupMenu.Create(Self);
  Item := TMenuItem.Create(FMenu);
  Item.Caption := TAtlasStrings.Text(TAtlasTextId.DebugViewerCopy);
  Item.ShortCut := ShortCut(Ord('C'), [ssCtrl]);
  Item.OnClick := CopyClick;
  FMenu.Items.Add(Item);

  FHeader := TLabel.Create(Self);
  FHeader.Parent := Self;
  FHeader.Align := alTop;
  FHeader.AlignWithMargins := True;
  FHeader.Margins.SetBounds(ScaleValue(Gap), ScaleValue(Gap), ScaleValue(Gap), 0);
  FHeader.WordWrap := True;
  FHeader.ShowAccelChar := False;
  FHeader.Font.Style := [fsBold];

  FNote := TLabel.Create(Self);
  FNote.Parent := Self;
  FNote.Align := alTop;
  FNote.AlignWithMargins := True;
  FNote.Margins.SetBounds(ScaleValue(Gap), ScaleValue(Gap div 2), ScaleValue(Gap), 0);
  FNote.WordWrap := True;
  FNote.ShowAccelChar := False;
  FNote.Visible := False;
  FNote.Top := FHeader.Top + FHeader.Height + 1;

  FAllFields := TCheckBox.Create(Self);
  FAllFields.Parent := Self;
  FAllFields.Align := alTop;
  FAllFields.AlignWithMargins := True;
  FAllFields.Margins.SetBounds(ScaleValue(Gap), ScaleValue(Gap div 2), ScaleValue(Gap), 0);
  FAllFields.Caption := TAtlasStrings.Text(TAtlasTextId.DebugViewerAllFields);
  FAllFields.Visible := False;
  FAllFields.Top := FNote.Top + FNote.Height + 1;
  FAllFields.OnClick := AllFieldsClick;

  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.AlignWithMargins := True;
  FList.Margins.SetBounds(ScaleValue(Gap), ScaleValue(Gap), ScaleValue(Gap), ScaleValue(Gap));
  FList.ViewStyle := vsReport;
  FList.OwnerData := True;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  FList.MultiSelect := True;
  FList.HideSelection := False;
  FList.OnData := ListData;
  FList.OnKeyDown := ContentKeyDown;
  FList.PopupMenu := FMenu;

  FTree := TTreeView.Create(Self);
  FTree.Parent := Self;
  FTree.Align := alClient;
  FTree.AlignWithMargins := True;
  FTree.Margins := FList.Margins;
  FTree.ReadOnly := True;
  FTree.HideSelection := False;
  FTree.OnKeyDown := ContentKeyDown;
  FTree.PopupMenu := FMenu;

  FImageBox := TScrollBox.Create(Self);
  FImageBox.Parent := Self;
  FImageBox.Align := alClient;
  FImageBox.AlignWithMargins := True;
  FImageBox.Margins := FList.Margins;
  FImageBox.BorderStyle := bsNone;
  FImage := TPaintBox.Create(Self);
  FImage.Parent := FImageBox;
  FImage.OnPaint := ImagePaint;

  FColor := TPanel.Create(Self);
  FColor.Parent := Self;
  FColor.Align := alTop;
  FColor.AlignWithMargins := True;
  FColor.Margins.SetBounds(ScaleValue(Gap), ScaleValue(Gap), ScaleValue(Gap), 0);
  FColor.Height := ScaleValue(ColorSize);
  FColor.BevelOuter := bvNone;
  FColor.ParentBackground := False;

  FText := TMemo.Create(Self);
  FText.Parent := Self;
  FText.Align := alClient;
  FText.AlignWithMargins := True;
  FText.Margins := FList.Margins;
  FText.ReadOnly := True;
  FText.ScrollBars := ssBoth;
  FText.WordWrap := False;
  FText.Font.Name := 'Consolas';
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
    FOnClosed(Self);
end;

procedure TAtlasDebugViewer.HideContent;
begin
  FList.Visible := False;
  FTree.Visible := False;
  FImageBox.Visible := False;
  FColor.Visible := False;
  FText.Visible := False;
end;

function TAtlasDebugViewer.ColumnCaption(AColumn: TAtlasVisualizerColumn): string;
begin
  case AColumn of
    TAtlasVisualizerColumn.Index:
      Result := TAtlasStrings.Text(TAtlasTextId.DebugViewerColumnIndex);
    TAtlasVisualizerColumn.Key:
      Result := TAtlasStrings.Text(TAtlasTextId.DebugViewerColumnKey);
    TAtlasVisualizerColumn.Field:
      Result := TAtlasStrings.Text(TAtlasTextId.DebugViewerColumnField);
    TAtlasVisualizerColumn.FieldType:
      Result := TAtlasStrings.Text(TAtlasTextId.DebugViewerColumnFieldType);
    TAtlasVisualizerColumn.OldValue:
      Result := TAtlasStrings.Text(TAtlasTextId.DebugViewerColumnOldValue);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.DebugViewerColumnValue);
  end;
end;

procedure TAtlasDebugViewer.ShowView(const AExpression: string; const AView: TAtlasVisualizerView);
begin
  FView := AView;
  Caption := Format(TAtlasStrings.Text(TAtlasTextId.DebugViewerTitle), [AExpression]);
  FHeader.Caption := AView.Summary;
  FHeader.Enabled := True;
  FNote.Visible := AView.NeedsMore;
  FNote.Caption := TAtlasStrings.Text(TAtlasTextId.DebugViewerNeedsMore);
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
      FText.Text := TAtlasStrings.Text(TAtlasTextId.DebugViewerEmpty);
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
  Column: TAtlasVisualizerColumn;
  ListColumn: TListColumn;
  Index: Integer;
begin
  FList.Items.BeginUpdate;
  try
    FList.Items.Count := 0;
    FList.Columns.Clear;
    FList.Font.Name := Font.Name;
    for Index := 0 to High(FView.Columns) do
    begin
      Column := FView.Columns[Index];
      ListColumn := FList.Columns.Add;
      ListColumn.Caption := ColumnCaption(Column);
      if Column = TAtlasVisualizerColumn.Index then
        ListColumn.Width := ScaleValue(56)
      else
        ListColumn.Width := ScaleValue(160);
    end;
    // Die letzte Spalte füllt den Rest.
    if FList.Columns.Count > 0 then
      FList.Columns[FList.Columns.Count - 1].AutoSize := True;
    FList.ShowColumnHeaders := True;
    FList.Items.Count := Length(CurrentRows);
  finally
    FList.Items.EndUpdate;
  end;
  FList.Visible := True;
end;

procedure TAtlasDebugViewer.ShowHex;
var
  ListColumn: TListColumn;
begin
  FList.Items.BeginUpdate;
  try
    FList.Items.Count := 0;
    FList.Columns.Clear;
    FList.Font.Name := 'Consolas';
    ListColumn := FList.Columns.Add;
    ListColumn.AutoSize := True;
    FList.ShowColumnHeaders := False;
    FList.Items.Count := TAtlasVisualizerFormat.HexLineCount(Length(FView.Bytes));
  finally
    FList.Items.EndUpdate;
  end;
  FList.Visible := True;
end;

procedure TAtlasDebugViewer.ShowTree;
var
  Parents: array of TTreeNode;
  Node: TTreeNode;
  Index, Level: Integer;
begin
  FTree.Items.BeginUpdate;
  try
    FTree.Items.Clear;
    SetLength(Parents, 1);
    Parents[0] := nil;
    for Index := 0 to High(FView.Nodes) do
    begin
      Level := EnsureRange(FView.Nodes[Index].Level, 0, High(Parents));
      Node := FTree.Items.AddChild(Parents[Level], FView.Nodes[Index].Text);
      SetLength(Parents, Level + 2);
      Parents[Level + 1] := Node;
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
  Row: Integer;
begin
  FreeAndNil(FBitmap);
  if (FView.Width > 0) and (FView.Height > 0) and (Length(FView.Pixels) = FView.Width * FView.Height) then
  begin
    FBitmap := TBitmap.Create;
    FBitmap.PixelFormat := pf32bit;
    FBitmap.SetSize(FView.Width, FView.Height);
    // $AARRGGBB liegt im Speicher als B, G, R, A: genau die Zeile eines 32-Bit-DIB.
    for Row := 0 to FView.Height - 1 do
      Move(FView.Pixels[Row * FView.Width], FBitmap.ScanLine[Row]^, FView.Width * SizeOf(Cardinal));
    FImage.SetBounds(0, 0, FView.Width, FView.Height);
  end
  else
    FImage.SetBounds(0, 0, 0, 0);
  FImageBox.Visible := True;
  FImage.Invalidate;
end;

procedure TAtlasDebugViewer.ImagePaint(Sender: TObject);
const
  Cell = 8;
var
  X, Y: Integer;
begin
  if FBitmap = nil then
    Exit;
  // Schachbrett hinter dem Bild, damit Transparenz und Weiß erkennbar sind.
  for Y := 0 to (FImage.Height - 1) div Cell do
    for X := 0 to (FImage.Width - 1) div Cell do
    begin
      if Odd(X + Y) then
        FImage.Canvas.Brush.Color := $00E0E0E0
      else
        FImage.Canvas.Brush.Color := clWhite;
      FImage.Canvas.FillRect(Rect(X * Cell, Y * Cell, (X + 1) * Cell, (Y + 1) * Cell));
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
    Result := TAtlasVisualizerFormat.HexLine(FView.Bytes, AIndex * 16)
  else if (AIndex >= 0) and (AIndex < Length(CurrentRows)) then
    Result := string.Join(#9, CurrentRows[AIndex])
  else
    Result := '';
end;

function TAtlasDebugViewer.CurrentRows: TArray<TArray<string>>;
begin
  if FAllFields.Visible and FAllFields.Checked then
    Result := FView.AllRows
  else
    Result := FView.Rows;
end;

procedure TAtlasDebugViewer.AllFieldsClick(Sender: TObject);
begin
  if FView.Mode = TAtlasVisualizerViewMode.Table then
    ShowTable;
end;

procedure TAtlasDebugViewer.ListData(Sender: TObject; AItem: TListItem);
var
  Rows: TArray<TArray<string>>;
  Cells: TArray<string>;
  Index: Integer;
begin
  if FView.Mode = TAtlasVisualizerViewMode.Hex then
  begin
    AItem.Caption := TAtlasVisualizerFormat.HexLine(FView.Bytes, AItem.Index * 16);
    Exit;
  end;
  Rows := CurrentRows;
  if (AItem.Index < 0) or (AItem.Index >= Length(Rows)) then
    Exit;
  Cells := Rows[AItem.Index];
  if Length(Cells) = 0 then
    Exit;
  AItem.Caption := Cells[0];
  for Index := 1 to High(Cells) do
    AItem.SubItems.Add(Cells[Index]);
end;

function TAtlasDebugViewer.SelectedText: string;
var
  Lines: TStringList;
  Item: TListItem;
begin
  Result := '';
  if FTree.Visible then
  begin
    if FTree.Selected <> nil then
      Result := FTree.Selected.Text;
    Exit;
  end;
  if FText.Visible then
  begin
    Result := FText.SelText;
    if Result = '' then
      Result := FText.Text;
    Exit;
  end;
  if not FList.Visible then
    Exit;
  Lines := TStringList.Create;
  try
    Item := FList.Selected;
    while Item <> nil do
    begin
      Lines.Add(RowText(Item.Index));
      Item := FList.GetNextItem(Item, sdAll, [isSelected]);
    end;
    Result := TrimRight(Lines.Text);
  finally
    Lines.Free;
  end;
end;

procedure TAtlasDebugViewer.CopyClick(Sender: TObject);
var
  Text: string;
begin
  Text := SelectedText;
  if Text <> '' then
    Clipboard.AsText := Text;
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
