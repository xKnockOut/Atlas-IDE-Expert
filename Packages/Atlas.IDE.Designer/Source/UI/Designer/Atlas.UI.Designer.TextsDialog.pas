unit Atlas.UI.Designer.TextsDialog;

// Dialog „Texte des Formulars“ (#728), reine VCL:
//   [Filter          ] [ ] Nur mit Hinweisen              12 Texte, 2 mit Hinweis
//   Komponente  Klasse   Eigenschaft  Text        Länge  Hinweise
//   btnSave     TButton  Caption      &Speichern  10     Tastenkürzel doppelt (&S: btnSearch)
//   [Text der markierten Zeile                         ] [Übernehmen] [Schließen]
// Klick auf eine Spalte sortiert, ein Klick auf eine Zeile meldet die
// Komponente (Auswahl im Designer). F2 oder Lostippen in der Liste bearbeitet
// den Text; Enter übernimmt und springt zur nächsten Zeile, Esc schließt.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Atlas.Core.Designer.FormTexts,
  Atlas.UI.Designer.Dialog;

type
  /// <summary>Text von Eintrag AIndex auf AText setzen; liefert alle Einträge neu geprüft.</summary>
  TAtlasTextsChange = reference to function(AIndex: Integer; const AText: string): TArray<TAtlasTextEntry>;

  TAtlasTextsDialog = class(TAtlasDesignerDialog)
  public const
    cDialogWidth = 760;
    cListHeight = 380;
  private
    FEntries: TArray<TAtlasTextEntry>;
    FRows: TArray<Integer>;
    FSortColumn: Integer;
    FFilter: TEdit;
    FOnlyFindings: TCheckBox;
    FCount: TLabel;
    FList: TListView;
    FText: TEdit;
    FOnSelect: TProc<string>;
    FOnChange: TAtlasTextsChange;
    procedure AddTop;
    procedure AddList;
    procedure AddBottom;
    procedure Fill(ASelect: Integer);
    procedure SortRows;
    function CurrentEntry: Integer;
    procedure FilterChange(Sender: TObject);
    procedure ListSelect(Sender: TObject; AItem: TListItem; ASelected: Boolean);
    procedure ListColumnClick(Sender: TObject; AColumn: TListColumn);
    procedure ListKeyDown(Sender: TObject; var AKey: Word; AShift: TShiftState);
    procedure ListKeyPress(Sender: TObject; var AKey: Char);
    procedure TextKeyPress(Sender: TObject; var AKey: Char);
    procedure ApplyClick(Sender: TObject);
  public
    constructor CreateDialog(AOwner: TComponent; const AForm: string; const AEntries: TArray<TAtlasTextEntry>;
      const AOnSelect: TProc<string>; const AOnChange: TAtlasTextsChange);
    /// <summary>Text der Spalte AColumn (0 Komponente … 5 Hinweise).</summary>
    class function Cell(const AEntry: TAtlasTextEntry; AColumn: Integer): string; static;
    /// <summary>Hinweise als Text, durch „; “ getrennt.</summary>
    class function FindingsText(const AEntry: TAtlasTextEntry): string; static;
    /// <summary>Modal zeigen.</summary>
    class procedure Execute(const AForm: string; const AEntries: TArray<TAtlasTextEntry>;
      const AOnSelect: TProc<string>; const AOnChange: TAtlasTextsChange); static;
    property List: TListView read FList;
    property Filter: TEdit read FFilter;
    property OnlyFindings: TCheckBox read FOnlyFindings;
    property TextEdit: TEdit read FText;
  end;

implementation

uses
  System.Generics.Defaults,
  System.Generics.Collections,
  Winapi.Windows,
  Atlas.UI.Designer.Strings;

const
  cColumnWidths: array [0 .. 4] of Integer = (120, 100, 140, 180, 50);
  cComponentColumn = 0;
  cClassColumn = 1;
  cPropertyColumn = 2;
  cTextColumn = 3;
  cLengthColumn = 4;
  cFindingsColumn = 5;
  cVerticalGaps = 4;

function FindingText(const AFinding: TAtlasTextFinding): string;
const
  cIds: array [TAtlasTextCheck] of TAtlasDesignerTextId = (TAtlasDesignerTextId.TextFindingAccelerators,
    TAtlasDesignerTextId.TextFindingVariants, TAtlasDesignerTextId.TextFindingTruncated,
    TAtlasDesignerTextId.TextFindingWhitespace, TAtlasDesignerTextId.TextFindingLabelColon);
begin
  Result := TAtlasDesignerStrings.Fmt(cIds[AFinding.Check], [AFinding.Detail]);
end;

{ TAtlasTextsDialog }

class function TAtlasTextsDialog.FindingsText(const AEntry: TAtlasTextEntry): string;
var
  mFinding: TAtlasTextFinding;
begin
  Result := '';
  for mFinding in AEntry.Findings do
  begin
    if Result <> '' then
    begin
      Result := Result + '; ';
    end;
    Result := Result + FindingText(mFinding);
  end;
end;

class function TAtlasTextsDialog.Cell(const AEntry: TAtlasTextEntry; AColumn: Integer): string;
begin
  case AColumn of
    cComponentColumn:
      Result := AEntry.Component;
    cClassColumn:
      Result := AEntry.ClassName;
    cPropertyColumn:
      Result := AEntry.Path;
    cTextColumn:
      Result := AEntry.Text;
    cLengthColumn:
      Result := IntToStr(Length(AEntry.Text));
  else
    Result := FindingsText(AEntry);
  end;
end;

constructor TAtlasTextsDialog.CreateDialog(AOwner: TComponent; const AForm: string;
  const AEntries: TArray<TAtlasTextEntry>; const AOnSelect: TProc<string>; const AOnChange: TAtlasTextsChange);
begin
  inherited CreateNew(AOwner);
  FEntries := AEntries;
  FOnSelect := AOnSelect;
  FOnChange := AOnChange;
  FSortColumn := -1;
  InitDialog(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerTextsTitle, [AForm]), cDialogWidth, bsSizeToolWin);
  AddTop;
  AddBottom;
  AddList;
  // Abstände über dem Filter, über und unter der Liste und unter dem Textfeld.
  ClientHeight := ScaleValue(cListHeight) + FFilter.Height + FText.Height + cVerticalGaps * cGap;
  Fill(-1);
  ActiveControl := FList;
end;

procedure TAtlasTextsDialog.AddTop;
var
  mPanel: TPanel;
begin
  mPanel := TPanel.Create(Self);
  mPanel.Parent := Self;
  mPanel.Align := alTop;
  mPanel.BevelOuter := bvNone;
  mPanel.AlignWithMargins := True;
  mPanel.Margins.SetBounds(cGap, cGap, cGap, 0);
  FFilter := TEdit.Create(Self);
  FFilter.Parent := mPanel;
  FFilter.Align := alLeft;
  FFilter.Width := ScaleValue(cColumnWidths[cComponentColumn] * 2);
  FFilter.TextHint := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerTextsFilter);
  FFilter.OnChange := FilterChange;
  mPanel.Height := FFilter.Height;
  FOnlyFindings := TCheckBox.Create(Self);
  FOnlyFindings.Parent := mPanel;
  FOnlyFindings.Align := alLeft;
  FOnlyFindings.AlignWithMargins := True;
  FOnlyFindings.Margins.SetBounds(cGap, 0, 0, 0);
  FOnlyFindings.Left := FFilter.Width + 1;
  FOnlyFindings.Width := ScaleValue(cColumnWidths[cTextColumn]);
  FOnlyFindings.Caption := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerTextsOnlyFindings);
  FOnlyFindings.OnClick := FilterChange;
  FCount := TLabel.Create(Self);
  FCount.Parent := mPanel;
  FCount.Align := alRight;
  FCount.Layout := tlCenter;
  FCount.ShowAccelChar := False;
end;

procedure TAtlasTextsDialog.AddList;
var
  mColumn: TListColumn;
  mIndex: Integer;
begin
  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.AlignWithMargins := True;
  FList.Margins.SetBounds(cGap, cGap, cGap, 0);
  FList.ViewStyle := vsReport;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  FList.HideSelection := False;
  for mIndex := 0 to cFindingsColumn do
  begin
    mColumn := FList.Columns.Add;
    if mIndex < cFindingsColumn then
    begin
      mColumn.Width := ScaleValue(cColumnWidths[mIndex]);
    end
    else
    begin
      mColumn.AutoSize := True;
    end;
  end;
  FList.Columns[cComponentColumn].Caption := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerTextsComponent);
  FList.Columns[cClassColumn].Caption := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerTextsClass);
  FList.Columns[cPropertyColumn].Caption := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerTextsProperty);
  FList.Columns[cTextColumn].Caption := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerTextsText);
  FList.Columns[cLengthColumn].Caption := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerTextsLength);
  FList.Columns[cFindingsColumn].Caption := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerTextsFindings);
  FList.OnSelectItem := ListSelect;
  FList.OnColumnClick := ListColumnClick;
  FList.OnKeyDown := ListKeyDown;
  FList.OnKeyPress := ListKeyPress;
end;

procedure TAtlasTextsDialog.AddBottom;
var
  mPanel: TPanel;
  mButton: TButton;
begin
  mPanel := TPanel.Create(Self);
  mPanel.Parent := Self;
  mPanel.Align := alBottom;
  mPanel.BevelOuter := bvNone;
  mPanel.AlignWithMargins := True;
  mPanel.Margins.SetBounds(cGap, cGap, cGap, cGap);
  mButton := TButton.Create(Self);
  mButton.Parent := mPanel;
  mButton.Align := alRight;
  mButton.Caption := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerTextsClose);
  mButton.Cancel := True;
  mButton.ModalResult := mrCancel;
  mButton := TButton.Create(Self);
  mButton.Parent := mPanel;
  mButton.Align := alRight;
  mButton.AlignWithMargins := True;
  mButton.Margins.SetBounds(cGap, 0, cGap, 0);
  mButton.Caption := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerTextsApply);
  mButton.OnClick := ApplyClick;
  FText := TEdit.Create(Self);
  FText.Parent := mPanel;
  FText.Align := alClient;
  FText.OnKeyPress := TextKeyPress;
  mPanel.Height := FText.Height;
end;

procedure TAtlasTextsDialog.SortRows;
var
  mColumn: Integer;
begin
  if FSortColumn < 0 then
  begin
    Exit;
  end;
  mColumn := FSortColumn;
  TArray.Sort<Integer>(FRows, TComparer<Integer>.Construct(
    function(const ALeft, ARight: Integer): Integer
    begin
      if mColumn = cLengthColumn then
      begin
        Result := Length(FEntries[ALeft].Text) - Length(FEntries[ARight].Text);
      end
      else
      begin
        Result := CompareText(Cell(FEntries[ALeft], mColumn), Cell(FEntries[ARight], mColumn));
      end;
      if Result = 0 then
      begin
        Result := ALeft - ARight;
      end;
    end));
end;

procedure TAtlasTextsDialog.Fill(ASelect: Integer);
var
  mIndex, mColumn, mFindings: Integer;
  mItem: TListItem;
begin
  FRows := nil;
  mFindings := 0;
  for mIndex := 0 to High(FEntries) do
  begin
    if FEntries[mIndex].HasFindings then
    begin
      Inc(mFindings);
    end;
    if TAtlasFormTexts.Matches(FEntries[mIndex], FFilter.Text, FOnlyFindings.Checked) then
    begin
      FRows := FRows + [mIndex];
    end;
  end;
  SortRows;
  FCount.Caption := TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerTextsCount, [Length(FEntries), mFindings]);
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for mIndex in FRows do
    begin
      mItem := FList.Items.Add;
      mItem.Caption := Cell(FEntries[mIndex], 0);
      for mColumn := 1 to cFindingsColumn do
      begin
        mItem.SubItems.Add(Cell(FEntries[mIndex], mColumn));
      end;
      if mIndex = ASelect then
      begin
        mItem.Selected := True;
        mItem.Focused := True;
        mItem.MakeVisible(False);
      end;
    end;
  finally
    FList.Items.EndUpdate;
  end;
end;

function TAtlasTextsDialog.CurrentEntry: Integer;
begin
  Result := -1;
  if (FList.Selected <> nil) and (FList.Selected.Index <= High(FRows)) then
  begin
    Result := FRows[FList.Selected.Index];
  end;
end;

procedure TAtlasTextsDialog.FilterChange(Sender: TObject);
begin
  Fill(CurrentEntry);
end;

procedure TAtlasTextsDialog.ListSelect(Sender: TObject; AItem: TListItem; ASelected: Boolean);
begin
  if not ASelected or (CurrentEntry < 0) then
  begin
    Exit;
  end;
  FText.Text := FEntries[CurrentEntry].Text;
  if Assigned(FOnSelect) then
  begin
    FOnSelect(FEntries[CurrentEntry].Component);
  end;
end;

procedure TAtlasTextsDialog.ListColumnClick(Sender: TObject; AColumn: TListColumn);
begin
  FSortColumn := AColumn.Index;
  Fill(CurrentEntry);
end;

procedure TAtlasTextsDialog.ListKeyDown(Sender: TObject; var AKey: Word; AShift: TShiftState);
begin
  if (AKey = VK_F2) and (CurrentEntry >= 0) then
  begin
    AKey := 0;
    FText.SetFocus;
    FText.SelectAll;
  end;
end;

procedure TAtlasTextsDialog.ListKeyPress(Sender: TObject; var AKey: Char);
begin
  // Lostippen ersetzt den Text der markierten Zeile.
  if (AKey >= ' ') and (CurrentEntry >= 0) then
  begin
    FText.SetFocus;
    FText.Text := AKey;
    FText.SelStart := Length(FText.Text);
    AKey := #0;
  end;
end;

procedure TAtlasTextsDialog.TextKeyPress(Sender: TObject; var AKey: Char);
begin
  if AKey = #13 then
  begin
    AKey := #0;
    ApplyClick(Sender);
  end;
end;

procedure TAtlasTextsDialog.ApplyClick(Sender: TObject);
var
  mEntry, mRow: Integer;
begin
  mEntry := CurrentEntry;
  if (mEntry < 0) or not Assigned(FOnChange) then
  begin
    Exit;
  end;
  mRow := FList.Selected.Index;
  if FText.Text <> FEntries[mEntry].Text then
  begin
    FEntries := FOnChange(mEntry, FText.Text);
    Fill(mEntry);
  end;
  // Nächste Zeile; fällt die bearbeitete aus dem Filter, steht die nächste schon an ihrer Stelle.
  if FList.Selected <> nil then
  begin
    mRow := FList.Selected.Index + 1;
  end;
  if mRow <= High(FRows) then
  begin
    FList.Items[mRow].Selected := True;
    FList.Items[mRow].Focused := True;
    FList.Items[mRow].MakeVisible(False);
  end;
  FList.SetFocus;
end;

class procedure TAtlasTextsDialog.Execute(const AForm: string; const AEntries: TArray<TAtlasTextEntry>;
  const AOnSelect: TProc<string>; const AOnChange: TAtlasTextsChange);
var
  mDialog: TAtlasTextsDialog;
begin
  mDialog := TAtlasTextsDialog.CreateDialog(nil, AForm, AEntries, AOnSelect, AOnChange);
  try
    mDialog.ShowModal;
  finally
    mDialog.Free;
  end;
end;

end.
