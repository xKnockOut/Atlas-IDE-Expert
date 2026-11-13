unit Atlas.UI.Tests.Slowest;

// Fenster „Langsamste Tests“ (#1772), ohne Open Tools API:
//   Langsamste Tests
//   Dauer            | Test
//   1,2 s · langsam  | Demo.Tests.TRechnerTests.Laden
//   180 ms           | Demo.Tests.TRechnerTests.Summe.Gross
//   Doppelklick springt zum Test. Langsam ab 500 ms.          [Schließen]
// Die Zeilen kommen fertig aus Atlas.Core.Tests.Durations; Doppelklick bzw.
// Eingabetaste schließt das Fenster und nennt die gewählte Zeile, springen
// tut der Aufrufer (Editor erst nach dem modalen Fenster).

interface

uses
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.ExtCtrls,
  Atlas.Core.Tests.Durations,
  Atlas.UI.Foundation.ListView,
  Atlas.UI.Foundation.Dialog;

type
  TAtlasTestsSlowestDialog = class(TAtlasDialog)
  public const
    cDialogWidth = 720;
    cListHeight = 360;
    cDurationWidth = 130;
    cTestWidth = 520;
    cNoteHeight = 24;
  private
    FRows: TArray<TAtlasTestSlowRow>;
    FList: TAtlasListView;
    FClose: TButton;
    FChosen: Integer;
    procedure Fill;
    procedure Choose;
    procedure ListDblClick(Sender: TObject);
    procedure ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  protected
    procedure DoShow; override;
  public
    /// <summary>Liste ARows; ASlowMs nennt die Grenze im Hinweis.</summary>
    constructor CreateDialog(AOwner: TComponent; const ARows: TArray<TAtlasTestSlowRow>; ASlowMs: Integer);
    /// <summary>Zeilen eintragen, sobald die Liste ein Fenster hat (auch für Tests).</summary>
    procedure ShowRows;
    /// <summary>Modal zeigen; Ergebnis ist die per Doppelklick bzw. Eingabetaste gewählte Zeile, sonst -1.</summary>
    class function Execute(const ARows: TArray<TAtlasTestSlowRow>; ASlowMs: Integer): Integer; static;
    property List: TAtlasListView read FList;
    property Chosen: Integer read FChosen;
  end;

implementation

uses
  System.UITypes,
  Atlas.Core.Style.Signal,
  Atlas.UI.Tests.Strings;

{ TAtlasTestsSlowestDialog }

constructor TAtlasTestsSlowestDialog.CreateDialog(AOwner: TComponent; const ARows: TArray<TAtlasTestSlowRow>;
  ASlowMs: Integer);
var
  mRow: TPanel;
  mButtons: TAtlasButtonRow;
begin
  inherited CreateDialog(AOwner, TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsSlowestTitle), cDialogWidth);
  FRows := ARows;
  FChosen := -1;
  mRow := AddRow(cListHeight);
  FList := TAtlasListView.Create(Self);
  FList.Parent := mRow;
  FList.Align := alClient;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  FList.AddColumn(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsSlowestDuration), cDurationWidth);
  FList.AddColumn(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsSlowestTest), cTestWidth);
  FList.FillColumn(1, cTestWidth);
  FList.OnDblClick := ListDblClick;
  FList.OnKeyDown := ListKeyDown;
  AddNote(cNoteHeight).ShowNote(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsSlowestHint, [ASlowMs]),
    TAtlasSignalKind.Info);
  mButtons := AddButtonRow;
  FClose := mButtons.AddButton(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsCompareClose),
    TAtlasButtonKind.Cancel);
  ActiveControl := FList;
  FitHeight;
  AllowResize(mRow);
end;

procedure TAtlasTestsSlowestDialog.DoShow;
begin
  inherited;
  ShowRows;
end;

procedure TAtlasTestsSlowestDialog.ShowRows;
begin
  if FList.Items.Count = 0 then
  begin
    Fill;
  end;
end;

procedure TAtlasTestsSlowestDialog.Fill;
var
  mRow: TAtlasTestSlowRow;
  mItem: TListItem;
  mDuration: string;
begin
  FList.Items.BeginUpdate;
  try
    for mRow in FRows do
    begin
      mItem := FList.Items.Add;
      mDuration := mRow.DurationText;
      if mRow.Slow then
      begin
        mDuration := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsLensSlow, [mDuration]);
      end;
      mItem.Caption := mDuration;
      mItem.SubItems.Add(mRow.Test);
    end;
  finally
    FList.Items.EndUpdate;
  end;
  if FList.Items.Count > 0 then
  begin
    FList.Items[0].Selected := True;
    FList.Items[0].Focused := True;
  end;
  FList.FitColumns;
end;

procedure TAtlasTestsSlowestDialog.Choose;
begin
  if FList.Selected = nil then
  begin
    Exit;
  end;
  FChosen := FList.Selected.Index;
  ModalResult := mrOk;
end;

procedure TAtlasTestsSlowestDialog.ListDblClick(Sender: TObject);
begin
  Choose;
end;

procedure TAtlasTestsSlowestDialog.ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = vkReturn then
  begin
    Key := 0;
    Choose;
  end;
end;

class function TAtlasTestsSlowestDialog.Execute(const ARows: TArray<TAtlasTestSlowRow>; ASlowMs: Integer): Integer;
var
  mDialog: TAtlasTestsSlowestDialog;
begin
  mDialog := TAtlasTestsSlowestDialog.CreateDialog(nil, ARows, ASlowMs);
  try
    Result := -1;
    if mDialog.ShowModal = mrOk then
    begin
      Result := mDialog.Chosen;
    end;
  finally
    mDialog.Free;
  end;
end;

end.
