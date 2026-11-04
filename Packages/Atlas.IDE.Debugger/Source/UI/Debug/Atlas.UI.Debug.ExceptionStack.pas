unit Atlas.UI.Debug.ExceptionStack;

// Aufrufstapel des gewählten Eintrags im Seitenfenster „Exception-Verlauf“
// (#517, #578), reine VCL: Liste mit Rahmen und Ort, darüber ein Teiler. Mit
// JustMyCode sind Bibliotheksrahmen grau, zwei und mehr in Folge stehen als
// „… n Bibliotheksrahmen“ (Doppelklick oder Enter klappt auf); Doppelklick
// oder Enter auf einem Rahmen mit Quelltext springt (OnOpenFrame).
// TAtlasDebugExceptionsFrame legt den Stapel an und zeigt ihn mit ShowFor.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Debug.OwnCode;

type
  TAtlasDebugExceptionStack = class(TComponent)
  private
    FList: TListView;
    FSplitter: TSplitter;
    FFrames: TAtlasDebugFrames;
    FRows: TAtlasDebugStackRows;
    /// <summary>Aufgeklappte Gruppen (Startindex) des gezeigten Stapels; neu bei anderem Eintrag.</summary>
    FExpanded: TArray<Integer>;
    FKey: string;
    FJustMyCode: Boolean;
    FOnOpenFrame: TProc<TAtlasDebugFrame>;
    procedure Fill;
    procedure SetJustMyCode(AValue: Boolean);
    function RowFaded(AItem: TListItem): Boolean;
    procedure ListDblClick(Sender: TObject);
    procedure ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ListCustomDrawItem(Sender: TCustomListView; Item: TListItem; State: TCustomDrawState;
      var DefaultDraw: Boolean);
    procedure ListCustomDrawSubItem(Sender: TCustomListView; Item: TListItem; SubItem: Integer;
      State: TCustomDrawState; var DefaultDraw: Boolean);
  public
    /// <summary>Liste und Teiler unten in AParent (nach der Summe, vor der Liste der Exceptions anlegen).</summary>
    constructor CreateIn(AParent: TWinControl);
    /// <summary>Stapel AFrames des Eintrags AKey zeigen ('' ohne Auswahl); anderer Eintrag: Gruppen zu.</summary>
    procedure ShowFor(const AKey: string; const AFrames: TAtlasDebugFrames);
    /// <summary>Liste und Teiler zeigen bzw. verstecken.</summary>
    procedure SetShown(AValue: Boolean);
    /// <summary>Stapelzeile ausführen: Gruppe aufklappen bzw. zum Rahmen springen (OnOpenFrame).</summary>
    procedure OpenRow(AIndex: Integer);
    /// <summary>Text einer Stapelzeile: Kopf bzw. „… n Bibliotheksrahmen“ und Ort.</summary>
    class function Cells(const AFrames: TAtlasDebugFrames; const ARow: TAtlasDebugStackRow): TArray<string>;
      static;
    /// <summary>Zeilenfarben aus dem Stil von AList (wie die Lesezeichenliste), sonst im dunklen Thema weiße
    /// Zellen; AGray: Schrift grau.</summary>
    class procedure RowColors(ACanvas: TCanvas; AList: TListView; AState: TCustomDrawState; AGray: Boolean);
      static;
    property List: TListView read FList;
    property Rows: TAtlasDebugStackRows read FRows;
    /// <summary>Bibliotheksrahmen abgeschwächt und zusammengefasst (debug.justMyCode, #578).</summary>
    property JustMyCode: Boolean read FJustMyCode write SetJustMyCode;
    property OnOpenFrame: TProc<TAtlasDebugFrame> read FOnOpenFrame write FOnOpenFrame;
  end;

implementation

uses
  Winapi.Windows,
  Vcl.Themes,
  Atlas.UI.Debug.Strings;

/// <summary>Spalte mit ACaption und AWidth (logische Pixel) an AList.</summary>
procedure AddColumn(AList: TListView; const ACaption: string; AWidth: Integer);
var
  mColumn: TListColumn;
begin
  mColumn := AList.Columns.Add;
  mColumn.Caption := ACaption;
  mColumn.Width := MulDiv(AWidth, AList.CurrentPPI, 96);
end;

/// <summary>Farbe AColor im Stil von AList, nicht im globalen: Die IDE themt ihre Fenster je Formular.</summary>
function ListColor(AList: TListView; AColor: TColor): TColor;
begin
  Result := ColorToRGB(StyleServices(AList).GetSystemColor(AColor));
end;

{ TAtlasDebugExceptionStack }

constructor TAtlasDebugExceptionStack.CreateIn(AParent: TWinControl);
begin
  inherited Create(AParent);
  FList := TListView.Create(Self);
  FList.Parent := AParent;
  FList.Align := alBottom;
  FList.AlignWithMargins := True;
  FList.Height := MulDiv(140, AParent.CurrentPPI, 96);
  FList.ViewStyle := vsReport;
  FList.RowSelect := True;
  FList.HideSelection := False;
  FList.ReadOnly := True;
  FList.MultiSelect := False;
  FList.ColumnClick := False;
  AddColumn(FList, TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugExceptionsStackCaption), 330);
  AddColumn(FList, TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugExceptionsColumnLocation), 170);
  FList.OnDblClick := ListDblClick;
  FList.OnKeyDown := ListKeyDown;
  FList.OnCustomDrawItem := ListCustomDrawItem;
  FList.OnCustomDrawSubItem := ListCustomDrawSubItem;

  FSplitter := TSplitter.Create(Self);
  FSplitter.Parent := AParent;
  FSplitter.Align := alBottom;
  FSplitter.Top := FList.Top - 1;
  FSplitter.MinSize := MulDiv(40, AParent.CurrentPPI, 96);
end;

procedure TAtlasDebugExceptionStack.SetShown(AValue: Boolean);
begin
  FList.Visible := AValue;
  FSplitter.Visible := AValue;
end;

procedure TAtlasDebugExceptionStack.SetJustMyCode(AValue: Boolean);
begin
  if FJustMyCode = AValue then
  begin
    Exit;
  end;
  FJustMyCode := AValue;
  FExpanded := nil;
  Fill;
end;

class function TAtlasDebugExceptionStack.Cells(const AFrames: TAtlasDebugFrames;
  const ARow: TAtlasDebugStackRow): TArray<string>;
var
  mFrame: TAtlasDebugFrame;
  mWhere: string;
begin
  if ARow.Kind = TAtlasDebugStackRowKind.LibraryGroup then
  begin
    Result := TArray<string>.Create(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugExceptionsStackLibrary,
      [ARow.Count]), '');
    Exit;
  end;
  mFrame := AFrames[ARow.First];
  mWhere := '';
  if mFrame.HasSource then
  begin
    mWhere := ExtractFileName(mFrame.FileName) + ':' + IntToStr(mFrame.Line);
  end;
  Result := TArray<string>.Create(mFrame.Header, mWhere);
end;

procedure TAtlasDebugExceptionStack.ShowFor(const AKey: string; const AFrames: TAtlasDebugFrames);
begin
  if (AKey = '') or (AKey <> FKey) then
  begin
    FExpanded := nil;
  end;
  FKey := AKey;
  FFrames := AFrames;
  Fill;
end;

procedure TAtlasDebugExceptionStack.Fill;
var
  mRow: TAtlasDebugStackRow;
  mTexts: TArray<string>;
  mItem: TListItem;
begin
  FRows := TAtlasDebugOwnCode.Rows(FFrames, FJustMyCode, FExpanded);
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for mRow in FRows do
    begin
      mTexts := Cells(FFrames, mRow);
      mItem := FList.Items.Add;
      mItem.Caption := mTexts[0];
      mItem.SubItems.Add(mTexts[1]);
    end;
    if (FRows = nil) and (FKey <> '') then
    begin
      FList.Items.Add.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugExceptionsStackEmpty);
    end;
  finally
    FList.Items.EndUpdate;
  end;
end;

procedure TAtlasDebugExceptionStack.OpenRow(AIndex: Integer);
var
  mRow: TAtlasDebugStackRow;
begin
  if (AIndex < 0) or (AIndex > High(FRows)) then
  begin
    Exit;
  end;
  mRow := FRows[AIndex];
  if mRow.Kind = TAtlasDebugStackRowKind.LibraryGroup then
  begin
    FExpanded := FExpanded + [mRow.First];
    Fill;
    if AIndex < FList.Items.Count then
    begin
      FList.Items[AIndex].Selected := True;
    end;
    Exit;
  end;
  if FFrames[mRow.First].HasSource and Assigned(FOnOpenFrame) then
  begin
    FOnOpenFrame(FFrames[mRow.First]);
  end;
end;

procedure TAtlasDebugExceptionStack.ListDblClick(Sender: TObject);
begin
  if FList.Selected <> nil then
  begin
    OpenRow(FList.Selected.Index);
  end;
end;

procedure TAtlasDebugExceptionStack.ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_RETURN) and (FList.Selected <> nil) then
  begin
    OpenRow(FList.Selected.Index);
    Key := 0;
  end;
end;

function TAtlasDebugExceptionStack.RowFaded(AItem: TListItem): Boolean;
begin
  Result := (AItem <> nil) and (AItem.Index <= High(FRows)) and FRows[AItem.Index].Faded;
end;

procedure TAtlasDebugExceptionStack.ListCustomDrawItem(Sender: TCustomListView; Item: TListItem;
  State: TCustomDrawState; var DefaultDraw: Boolean);
begin
  DefaultDraw := True;
  RowColors(Sender.Canvas, FList, State, RowFaded(Item));
end;

procedure TAtlasDebugExceptionStack.ListCustomDrawSubItem(Sender: TCustomListView; Item: TListItem;
  SubItem: Integer; State: TCustomDrawState; var DefaultDraw: Boolean);
begin
  DefaultDraw := True;
  RowColors(Sender.Canvas, FList, State, RowFaded(Item));
end;

class procedure TAtlasDebugExceptionStack.RowColors(ACanvas: TCanvas; AList: TListView; AState: TCustomDrawState;
  AGray: Boolean);
begin
  if cdsSelected in AState then
  begin
    ACanvas.Brush.Color := ListColor(AList, clHighlight);
    ACanvas.Font.Color := ListColor(AList, clHighlightText);
  end
  else
  begin
    ACanvas.Brush.Color := ListColor(AList, AList.Color);
    if AGray then
    begin
      ACanvas.Font.Color := ListColor(AList, clGrayText);
    end
    else
    begin
      ACanvas.Font.Color := ListColor(AList, AList.Font.Color);
    end;
  end;
end;

end.
