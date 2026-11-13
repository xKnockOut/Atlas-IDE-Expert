unit Atlas.UI.Debug.ProcessChoice;

// Auswahl beim erneuten Anhängen (#2171), Fensterteil (nur VCL), im
// IDE-Thema über TAtlasDialog: mehrere passende Prozesse mit Kennung,
// Startzeit und Befehlszeile; Doppelklick oder „Anhängen“ wählt.
//     Erneut an Kunden.exe anhängen
//     PID    Gestartet            Befehlszeile
//     4711   13.11.2026 10:15:02  "C:\Bin\Kunden.exe" -demo
//     4802   13.11.2026 10:17:40  "C:\Alt\Kunden.exe"
//                                     [Anhängen] [Abbrechen]

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Atlas.Core.Debug.Reattach,
  Atlas.UI.Foundation.Dialog,
  Atlas.UI.Foundation.ListView;

type
  TAtlasProcessChoiceDialog = class(TAtlasDialog)
  public const
    cWidth = 640;
    cListHeight = 200;
    cPidWidth = 70;
    cStartWidth = 150;
    cCommandMinWidth = 240;
  private
    FProcesses: TAtlasReattachProcesses;
    FList: TAtlasListView;
    FAttach: TButton;
    FFilled: Boolean;
    procedure Fill;
    procedure ListDblClick(Sender: TObject);
    procedure ListSelect(Sender: TObject; Item: TListItem; Selected: Boolean);
  protected
    procedure DoShow; override;
  public
    constructor CreateFor(AOwner: TComponent; const AName: string; const AProcesses: TAtlasReattachProcesses);
    /// <summary>Gewählter Index in AProcesses oder -1 (abgebrochen).</summary>
    class function Execute(const AName: string; const AProcesses: TAtlasReattachProcesses): Integer; static;
    property List: TAtlasListView read FList;
  end;

implementation

uses
  Vcl.Forms,
  Atlas.UI.Debug.Strings;

{ TAtlasProcessChoiceDialog }

constructor TAtlasProcessChoiceDialog.CreateFor(AOwner: TComponent; const AName: string;
  const AProcesses: TAtlasReattachProcesses);
var
  mRow: TWinControl;
  mButtons: TAtlasButtonRow;
begin
  inherited CreateDialog(AOwner, TAtlasDebugStrings.Fmt(TAtlasDebugTextId.ReattachCommand, [AName]), cWidth);
  FProcesses := AProcesses;
  mRow := AddRow(cListHeight);
  FList := TAtlasListView.Create(Self);
  FList.Parent := mRow;
  FList.Align := alClient;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  FList.HideSelection := False;
  FList.AddColumn(TAtlasDebugStrings.Text(TAtlasDebugTextId.ReattachPid), cPidWidth, taRightJustify);
  FList.AddColumn(TAtlasDebugStrings.Text(TAtlasDebugTextId.ReattachStarted), cStartWidth);
  FList.AddColumn(TAtlasDebugStrings.Text(TAtlasDebugTextId.ReattachCommandLine), cCommandMinWidth);
  FList.FillColumn(2, cCommandMinWidth);
  FList.OnDblClick := ListDblClick;
  FList.OnSelectItem := ListSelect;
  mButtons := AddButtonRow;
  FAttach := mButtons.AddButton(TAtlasDebugStrings.Text(TAtlasDebugTextId.ReattachAttach), TAtlasButtonKind.Default);
  FAttach.Enabled := False;
  mButtons.AddButton(TAtlasDebugStrings.Text(TAtlasDebugTextId.ReattachCancel), TAtlasButtonKind.Cancel);
  FitHeight;
  AllowResize(mRow);
  ActiveControl := FList;
end;

procedure TAtlasProcessChoiceDialog.Fill;
var
  mProcess: TAtlasReattachProcess;
  mItem: TListItem;
  mCells: TArray<string>;
begin
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for mProcess in FProcesses do
    begin
      mCells := TAtlasReattach.Cells(mProcess, FormatSettings);
      mItem := FList.Items.Add;
      mItem.Caption := mCells[0];
      mItem.SubItems.Add(mCells[1]);
      mItem.SubItems.Add(mCells[2]);
    end;
  finally
    FList.Items.EndUpdate;
  end;
  if FList.Items.Count > 0 then
  begin
    FList.Items[0].Selected := True;
    FList.Items[0].Focused := True;
  end;
end;

procedure TAtlasProcessChoiceDialog.DoShow;
begin
  inherited;
  // Die Liste braucht ein Fenster; nach dem Thema (VisibleChanging) ist es da.
  if not FFilled then
  begin
    FFilled := True;
    Fill;
  end;
end;

procedure TAtlasProcessChoiceDialog.ListDblClick(Sender: TObject);
begin
  if FList.Selected <> nil then
  begin
    ModalResult := mrOk;
  end;
end;

procedure TAtlasProcessChoiceDialog.ListSelect(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  FAttach.Enabled := FList.Selected <> nil;
end;

class function TAtlasProcessChoiceDialog.Execute(const AName: string;
  const AProcesses: TAtlasReattachProcesses): Integer;
var
  mDialog: TAtlasProcessChoiceDialog;
begin
  Result := -1;
  mDialog := TAtlasProcessChoiceDialog.CreateFor(nil, AName, AProcesses);
  try
    if (mDialog.ShowModal = mrOk) and (mDialog.List.Selected <> nil) then
    begin
      Result := mDialog.List.Selected.Index;
    end;
  finally
    mDialog.Free;
  end;
end;

end.
