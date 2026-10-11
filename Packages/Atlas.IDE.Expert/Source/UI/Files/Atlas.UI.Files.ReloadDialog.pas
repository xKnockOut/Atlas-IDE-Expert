unit Atlas.UI.Files.ReloadDialog;

// Sammeldialog für extern geänderte Dateien mit ungespeicherten Änderungen
// (#536): statt je Datei eine Rückfrage der IDE eine Liste. Jede Datei hat ein
// Häkchen; die gewählte zeigt unten den Unterschied zwischen Puffer und
// Platte („Vergleichen“). Knöpfe: „Ausgewählte neu laden“, „Alle neu laden“,
// „Behalten“. Gelöschte Dateien stehen mit Hinweis in der Liste und lassen
// sich nicht neu laden. Im Code aufgebaut, reine VCL.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.ExtCtrls,
  Vcl.Graphics;

type
  TAtlasReloadItem = record
    FileName: string;
    Deleted: Boolean;
    /// <summary>Unterschied Puffer → Platte, je Zeile; leer bei gelöschten Dateien.</summary>
    Diff: TArray<string>;
  end;

  TAtlasReloadDialog = class
  public
    /// <summary>Zeigt den Dialog; liefert die Dateien, die neu geladen werden sollen (leer = alle behalten).</summary>
    class function Execute(const AItems: TArray<TAtlasReloadItem>): TArray<string>; static;
  end;

implementation

uses
  Atlas.UI.Strings;

type
  TReloadForm = class(TForm)
  private
    FItems: TArray<TAtlasReloadItem>;
    FList: TListView;
    FDiff: TMemo;
    procedure ListSelect(Sender: TObject; Item: TListItem; Selected: Boolean);
  public
    constructor CreateFor(const AItems: TArray<TAtlasReloadItem>);
    function Checked(AAll: Boolean): TArray<string>;
  end;

constructor TReloadForm.CreateFor(const AItems: TArray<TAtlasReloadItem>);
var
  Item: TAtlasReloadItem;
  Row: TListItem;
  Column: TListColumn;
  Hint: TLabel;
  Buttons: TPanel;
  Button: TButton;

  function AddButton(const ACaption: string; AResult: TModalResult; ALeft: Integer): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := Buttons;
    Result.Caption := ACaption;
    Result.ModalResult := AResult;
    Result.Left := ALeft;
    Result.Top := 8;
    Result.Width := 170;
  end;

begin
  inherited CreateNew(nil);
  FItems := AItems;
  Caption := TAtlasStrings.Text(TAtlasTextId.ReloadDialogTitle);
  Position := poMainFormCenter;
  BorderIcons := [biSystemMenu];
  Width := 760;
  Height := 520;
  Hint := TLabel.Create(Self);
  Hint.Parent := Self;
  Hint.Align := alTop;
  Hint.AlignWithMargins := True;
  Hint.WordWrap := True;
  Hint.Caption := TAtlasStrings.Text(TAtlasTextId.ReloadDialogHint);
  Buttons := TPanel.Create(Self);
  Buttons.Parent := Self;
  Buttons.Align := alBottom;
  Buttons.Height := 44;
  Buttons.BevelOuter := bvNone;
  Button := AddButton(TAtlasStrings.Text(TAtlasTextId.ReloadDialogSelected), mrOk, 8);
  Button.Default := True;
  AddButton(TAtlasStrings.Text(TAtlasTextId.ReloadDialogAll), mrAll, 186);
  Button := AddButton(TAtlasStrings.Text(TAtlasTextId.ReloadDialogKeep), mrCancel, 364);
  Button.Cancel := True;
  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alTop;
  FList.AlignWithMargins := True;
  FList.Height := 170;
  FList.ViewStyle := vsReport;
  FList.Checkboxes := True;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  FList.HideSelection := False;
  Column := FList.Columns.Add;
  Column.Caption := TAtlasStrings.Text(TAtlasTextId.ReloadDialogFile);
  Column.Width := 520;
  Column := FList.Columns.Add;
  Column.Caption := TAtlasStrings.Text(TAtlasTextId.ReloadDialogState);
  Column.Width := 190;
  for Item in AItems do
  begin
    Row := FList.Items.Add;
    Row.Caption := Item.FileName;
    if Item.Deleted then
      Row.SubItems.Add(TAtlasStrings.Text(TAtlasTextId.ReloadDialogDeleted))
    else
      Row.SubItems.Add(TAtlasStrings.Text(TAtlasTextId.ReloadDialogModified));
    // Vorgabe: behalten; gelöschte lassen sich nicht neu laden.
    Row.Checked := False;
  end;
  FDiff := TMemo.Create(Self);
  FDiff.Parent := Self;
  FDiff.Align := alClient;
  FDiff.AlignWithMargins := True;
  FDiff.ReadOnly := True;
  FDiff.ScrollBars := ssBoth;
  FDiff.WordWrap := False;
  FDiff.Font.Name := 'Consolas';
  FList.OnSelectItem := ListSelect;
  if FList.Items.Count > 0 then
    FList.Items[0].Selected := True;
end;

procedure TReloadForm.ListSelect(Sender: TObject; Item: TListItem; Selected: Boolean);
var
  Line: string;
begin
  if not Selected or (Item = nil) then
    Exit;
  FDiff.Lines.BeginUpdate;
  try
    FDiff.Lines.Clear;
    if FItems[Item.Index].Deleted then
      FDiff.Lines.Add(TAtlasStrings.Text(TAtlasTextId.ReloadDialogDeleted))
    else if Length(FItems[Item.Index].Diff) = 0 then
      FDiff.Lines.Add(TAtlasStrings.Text(TAtlasTextId.ReloadDialogSame))
    else
      for Line in FItems[Item.Index].Diff do
        FDiff.Lines.Add(Line);
  finally
    FDiff.Lines.EndUpdate;
  end;
end;

function TReloadForm.Checked(AAll: Boolean): TArray<string>;
var
  Index: Integer;
begin
  Result := nil;
  for Index := 0 to FList.Items.Count - 1 do
    if not FItems[Index].Deleted and (AAll or FList.Items[Index].Checked) then
      Result := Result + [FItems[Index].FileName];
end;

class function TAtlasReloadDialog.Execute(const AItems: TArray<TAtlasReloadItem>): TArray<string>;
var
  Form: TReloadForm;
begin
  Result := nil;
  if Length(AItems) = 0 then
    Exit;
  Form := TReloadForm.CreateFor(AItems);
  try
    case Form.ShowModal of
      mrOk:
        Result := Form.Checked(False);
      mrAll:
        Result := Form.Checked(True);
    end;
  finally
    Form.Free;
  end;
end;

end.
