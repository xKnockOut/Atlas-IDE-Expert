unit Atlas.UI.Search.ReplaceFrame;

// Inhalt des Fensters „Atlas-Suche: Ersetzen“ (#893), reine VCL: die Treffer
// einer Suche über Dateien mit Häkchen zum Ersetzen. Oben Kopfzeile (Suche,
// Ersatz, Anzahl), darunter eine Zeile mit Hinweis (etwa „12 Ersetzungen in
// 3 Dateien“ oder übersprungene Dateien) und rechts dem Knopf „Ausgewählte
// ersetzen“. Knopf und Hinweis stehen in einer eigenen Zeile, deren Höhe aus
// dem Knopf folgt: Die VCL richtet alTop vor alRight aus, neben zwei
// Beschriftungen mit alTop blieben dem Knopf sonst nur wenige Pixel. Darunter die
// Liste aus TAtlasReplaceList.Rows: je Datei eine Kopfzeile, darunter ihre
// Treffer mit Zeile, Zeilentext und bei Regex der Vorschau „vorher →
// nachher“. Die erste Spalte ist das Häkchen (☑/☐): Klick darauf oder
// Leertaste schaltet um, das Häkchen einer Datei gilt für alle ihre Treffer.
// Doppelklick bzw. Enter auf einem Treffer meldet OnOpen (Sprung in den
// Editor). Die Liste ist virtuell (OwnerData) und braucht kein Fenster zum
// Füllen. Das Modell gehört dem Aufrufer (Atlas.IDE.Search.ReplaceWindow).
// Die DFM ist leer, weil TCustomFrame.Create für abgeleitete Frames eine
// Ressource verlangt; aufgebaut wird im Code.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Vcl.Forms,
  Atlas.Core.Search.ReplaceList;

type
  TAtlasReplaceOpen = reference to procedure(const AFileName: string; ALine, ACharacter: Integer);

  TAtlasSearchReplaceFrame = class(TFrame)
  private
    FTitle: TLabel;
    FBar: TPanel;
    FReplace: TButton;
    FNotice: TLabel;
    FList: TListView;
    FModel: TAtlasReplaceList;
    FRows: TArray<TAtlasReplaceRow>;
    FOnReplace: TProc;
    FOnOpen: TAtlasReplaceOpen;
    procedure ListData(Sender: TObject; Item: TListItem);
    procedure ListMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure ListDblClick(Sender: TObject);
    procedure ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ReplaceClick(Sender: TObject);
    procedure Toggle(AIndex: Integer);
    procedure Open(AIndex: Integer);
    procedure UpdateTitle;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Modell zeigen (nil = leer); nach jeder Änderung am Modell erneut aufrufen.</summary>
    procedure SetModel(AModel: TAtlasReplaceList);
    procedure SetNotice(const AText: string);
    /// <summary>Zeile umschalten wie ein Klick auf das Häkchen (für Tests).</summary>
    procedure ToggleRow(AIndex: Integer);
    property Rows: TArray<TAtlasReplaceRow> read FRows;
    property List: TListView read FList;
    property ReplaceButton: TButton read FReplace;
    property Title: TLabel read FTitle;
    property Notice: TLabel read FNotice;
    /// <summary>„Ausgewählte ersetzen“.</summary>
    property OnReplace: TProc read FOnReplace write FOnReplace;
    property OnOpen: TAtlasReplaceOpen read FOnOpen write FOnOpen;
  end;

implementation

uses
  Winapi.Windows,
  Vcl.Graphics,
  Atlas.UI.Search.Strings;

{$R *.dfm}

const
  CheckOn = '☑';
  CheckOff = '☐';
  CheckWidth = 32;
  ReplaceWidth = 170;

constructor TAtlasSearchReplaceFrame.Create(AOwner: TComponent);
var
  Column: TListColumn;
begin
  inherited Create(AOwner);
  FTitle := TLabel.Create(Self);
  FTitle.Parent := Self;
  FTitle.Align := alTop;
  FTitle.AlignWithMargins := True;
  FTitle.ShowAccelChar := False;
  FTitle.Font.Style := [fsBold];

  // Eigene Zeile für Hinweis und Knopf, unter der Kopfzeile.
  FBar := TPanel.Create(Self);
  FBar.Parent := Self;
  FBar.Align := alTop;
  FBar.Top := FTitle.Top + FTitle.Height + 1;
  FBar.BevelOuter := bvNone;
  FBar.ShowCaption := False;

  FReplace := TButton.Create(Self);
  FReplace.Parent := FBar;
  FReplace.Align := alRight;
  FReplace.AlignWithMargins := True;
  FReplace.Width := ReplaceWidth;
  FReplace.Caption := TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchReplaceSelectedButton);
  FReplace.OnClick := ReplaceClick;
  // Höhe aus dem Knopf: ChangeScale skaliert beide gleich.
  FBar.Height := FReplace.Height + FReplace.Margins.Top + FReplace.Margins.Bottom;

  FNotice := TLabel.Create(Self);
  FNotice.Parent := FBar;
  FNotice.Align := alClient;
  FNotice.AlignWithMargins := True;
  FNotice.Layout := tlCenter;
  FNotice.ShowAccelChar := False;

  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.AlignWithMargins := True;
  FList.ViewStyle := vsReport;
  FList.OwnerData := True;
  FList.RowSelect := True;
  FList.HideSelection := False;
  FList.ReadOnly := True;
  FList.OnData := ListData;
  FList.OnMouseDown := ListMouseDown;
  FList.OnDblClick := ListDblClick;
  FList.OnKeyDown := ListKeyDown;
  Column := FList.Columns.Add;
  Column.Caption := '';
  Column.Width := CheckWidth;
  Column := FList.Columns.Add;
  Column.Caption := TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchReplaceColumnPlace);
  Column.Width := 220;
  Column := FList.Columns.Add;
  Column.Caption := TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchReplaceColumnText);
  Column.Width := 360;
  Column := FList.Columns.Add;
  Column.Caption := TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchReplaceColumnPreview);
  Column.Width := 300;
  UpdateTitle;
end;

procedure TAtlasSearchReplaceFrame.SetModel(AModel: TAtlasReplaceList);
begin
  FModel := AModel;
  FRows := nil;
  if FModel <> nil then
  begin
    FRows := FModel.Rows;
  end;
  FList.Items.Count := Length(FRows);
  FList.Invalidate;
  UpdateTitle;
end;

procedure TAtlasSearchReplaceFrame.SetNotice(const AText: string);
begin
  FNotice.Caption := AText;
end;

procedure TAtlasSearchReplaceFrame.UpdateTitle;
var
  Files: Integer;
begin
  if FModel = nil then
  begin
    FTitle.Caption := TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchReplaceEmpty);
    FReplace.Enabled := False;
    Exit;
  end;
  Files := Length(FModel.Results);
  FTitle.Caption := TAtlasSearchStrings.Fmt(TAtlasSearchTextId.SearchReplaceListTitle,
    [FModel.Query.Text, FModel.Replace,
    FModel.CheckedCount, FModel.HitCount, Files]);
  FReplace.Enabled := FModel.CheckedCount > 0;
end;

procedure TAtlasSearchReplaceFrame.ListData(Sender: TObject; Item: TListItem);
var
  Row: TAtlasReplaceRow;
  Check: string;
begin
  if (Item.Index < 0) or (Item.Index > High(FRows)) then
  begin
    Exit;
  end;
  Row := FRows[Item.Index];
  Check := CheckOff;
  if Row.Checked then
  begin
    Check := CheckOn;
  end;
  if Row.Kind = TAtlasReplaceRowKind.FileRow then
  begin
    Item.Caption := Check;
    Item.SubItems.Add(Row.Text);
    Item.SubItems.Add(ExtractFileDir(Row.FileName));
    Item.SubItems.Add('');
  end
  else
  begin
    // Treffer eingerückt unter ihrer Datei.
    Item.Caption := '   ' + Check;
    Item.SubItems.Add('   ' + TAtlasSearchStrings.Fmt(TAtlasSearchTextId.SearchReplaceLine, [Row.Line]));
    Item.SubItems.Add(Row.Text);
    Item.SubItems.Add(Row.Preview);
  end;
end;

procedure TAtlasSearchReplaceFrame.ToggleRow(AIndex: Integer);
begin
  Toggle(AIndex);
end;

procedure TAtlasSearchReplaceFrame.Toggle(AIndex: Integer);
var
  Row: TAtlasReplaceRow;
begin
  if (FModel = nil) or (AIndex < 0) or (AIndex > High(FRows)) then
  begin
    Exit;
  end;
  Row := FRows[AIndex];
  if Row.Kind = TAtlasReplaceRowKind.FileRow then
  begin
    FModel.SetFileChecked(Row.FileIndex, not Row.Checked);
  end
  else
  begin
    FModel.SetHitChecked(Row.FileIndex, Row.HitIndex, not Row.Checked);
  end;
  // Zeilen neu aus dem Modell: Die Kopfzeile folgt ihren Treffern und umgekehrt.
  FRows := FModel.Rows;
  FList.Invalidate;
  UpdateTitle;
end;

procedure TAtlasSearchReplaceFrame.Open(AIndex: Integer);
var
  Row: TAtlasReplaceRow;
  Hit: Integer;
begin
  if (FModel = nil) or (AIndex < 0) or (AIndex > High(FRows)) or not Assigned(FOnOpen) then
  begin
    Exit;
  end;
  Row := FRows[AIndex];
  Hit := Row.HitIndex;
  if Hit < 0 then
  begin
    Hit := 0;
  end;
  if (Row.FileIndex > High(FModel.Results)) or (Hit > High(FModel.Results[Row.FileIndex].Hits)) then
  begin
    Exit;
  end;
  FOnOpen(Row.FileName, FModel.Results[Row.FileIndex].Hits[Hit].Line,
    FModel.Results[Row.FileIndex].Hits[Hit].Character);
end;

procedure TAtlasSearchReplaceFrame.ListMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  Item: TListItem;
begin
  if (Button <> mbLeft) or (X >= FList.Columns[0].Width) or (ssDouble in Shift) then
  begin
    Exit;
  end;
  Item := FList.GetItemAt(X, Y);
  if Item <> nil then
  begin
    Toggle(Item.Index);
  end;
end;

procedure TAtlasSearchReplaceFrame.ListDblClick(Sender: TObject);
begin
  if FList.Selected <> nil then
  begin
    Open(FList.Selected.Index);
  end;
end;

procedure TAtlasSearchReplaceFrame.ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if FList.Selected = nil then
  begin
    Exit;
  end;
  case Key of
    VK_SPACE:
      begin
        Key := 0;
        Toggle(FList.Selected.Index);
      end;
    VK_RETURN:
      begin
        Key := 0;
        Open(FList.Selected.Index);
      end;
  end;
end;

procedure TAtlasSearchReplaceFrame.ReplaceClick(Sender: TObject);
begin
  if Assigned(FOnReplace) then
  begin
    FOnReplace();
  end;
end;

end.
