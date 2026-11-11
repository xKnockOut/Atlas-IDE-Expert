unit Atlas.UI.Designer.PaintDialog;

// Dialog „Eigenschaften aufnehmen“ des Format-Pinsels (#726), reine VCL:
// eine Liste mit Häkchen, je Gruppe eine Überschrift, verschachtelte
// Eigenschaften eingerückt unter ihrem Knoten („Font“); ein Häkchen am
// Knoten setzt oder löscht alle Kinder.
//   Schrift
//     [x] Font
//       [x] Font.Name
//   Größe
//     [x] Width
//                                       [OK] [Abbrechen]
// Enter bestätigt, Esc verwirft. Zeilen und Vorauswahl kommen aus
// TAtlasPropertyPainter.

interface

uses
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.CheckLst,
  Atlas.Core.Designer.PropertyPainter;

type
  TAtlasPaintDialog = class(TForm)
  public const
    cDialogWidth = 360;
    cListHeight = 360;
  private
    FRows: TArray<TAtlasPaintRow>;
    FList: TCheckListBox;
    procedure ListClickCheck(Sender: TObject);
    procedure AddButtons;
  public
    constructor CreateDialog(AOwner: TComponent; const ASource: string; const ARows: TArray<TAtlasPaintRow>;
      const AChecked: TArray<Boolean>);
    function Checked: TArray<Boolean>;
    /// <summary>Modal zeigen; True nach OK, AChecked dann mit den Häkchen.</summary>
    class function Execute(const ASource: string; const ARows: TArray<TAtlasPaintRow>;
      var AChecked: TArray<Boolean>): Boolean; static;
    property List: TCheckListBox read FList;
  end;

implementation

uses
  Atlas.UI.Designer.Strings;

const
  cGap = 10;
  cIndent = '    ';

function GroupCaption(AGroup: TAtlasPaintGroup): string;
const
  cIds: array [TAtlasPaintGroup] of TAtlasDesignerTextId = (TAtlasDesignerTextId.PaintGroupFont,
    TAtlasDesignerTextId.PaintGroupColors, TAtlasDesignerTextId.PaintGroupSize, TAtlasDesignerTextId.PaintGroupPosition,
    TAtlasDesignerTextId.PaintGroupLayout, TAtlasDesignerTextId.PaintGroupText, TAtlasDesignerTextId.PaintGroupBehavior,
    TAtlasDesignerTextId.PaintGroupEvents, TAtlasDesignerTextId.PaintGroupOther);
begin
  Result := TAtlasDesignerStrings.Text(cIds[AGroup]);
end;

{ TAtlasPaintDialog }

constructor TAtlasPaintDialog.CreateDialog(AOwner: TComponent; const ASource: string;
  const ARows: TArray<TAtlasPaintRow>; const AChecked: TArray<Boolean>);
var
  mIndex: Integer;
  mCaption: string;
begin
  inherited CreateNew(AOwner);
  FRows := ARows;
  Caption := TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerPaintTitle, [ASource]);
  BorderStyle := bsDialog;
  Position := poMainFormCenter;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  ClientWidth := ScaleValue(cDialogWidth);
  FList := TCheckListBox.Create(Self);
  FList.Parent := Self;
  FList.Align := alTop;
  FList.AlignWithMargins := True;
  FList.Margins.SetBounds(cGap, cGap, cGap, 0);
  FList.Height := ScaleValue(cListHeight);
  FList.OnClickCheck := ListClickCheck;
  for mIndex := 0 to High(ARows) do
  begin
    case ARows[mIndex].Kind of
      TAtlasPaintRowKind.Header:
        mCaption := GroupCaption(ARows[mIndex].Group);
      TAtlasPaintRowKind.Node:
        mCaption := cIndent + ARows[mIndex].Path;
    else
      mCaption := cIndent + ARows[mIndex].Path;
      if ARows[mIndex].Parent >= 0 then
      begin
        mCaption := cIndent + mCaption;
      end;
    end;
    FList.Items.Add(mCaption);
    FList.Header[mIndex] := ARows[mIndex].Kind = TAtlasPaintRowKind.Header;
    FList.Checked[mIndex] := (mIndex <= High(AChecked)) and AChecked[mIndex];
  end;
  AddButtons;
  ActiveControl := FList;
end;

procedure TAtlasPaintDialog.ListClickCheck(Sender: TObject);
var
  mIndex, mChild: Integer;
begin
  mIndex := FList.ItemIndex;
  if (mIndex < 0) or (mIndex > High(FRows)) or (FRows[mIndex].Kind <> TAtlasPaintRowKind.Node) then
  begin
    Exit;
  end;
  for mChild := 0 to High(FRows) do
  begin
    if FRows[mChild].Parent = mIndex then
    begin
      FList.Checked[mChild] := FList.Checked[mIndex];
    end;
  end;
end;

procedure TAtlasPaintDialog.AddButtons;
var
  mButtons: TFlowPanel;
  mButton: TButton;
begin
  mButtons := TFlowPanel.Create(Self);
  mButtons.Parent := Self;
  mButtons.Align := alTop;
  mButtons.AutoSize := True;
  mButtons.BevelOuter := bvNone;
  mButtons.AlignWithMargins := True;
  mButtons.Margins.SetBounds(cGap, cGap, cGap, cGap);
  mButtons.Top := FList.Top + FList.Height + 1;
  mButton := TButton.Create(Self);
  mButton.Parent := mButtons;
  mButton.Caption := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSpaceOk);
  mButton.Default := True;
  mButton.ModalResult := mrOk;
  mButton.AlignWithMargins := True;
  mButton.Margins.SetBounds(0, 0, cGap, 0);
  mButton := TButton.Create(Self);
  mButton.Parent := mButtons;
  mButton.Caption := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerDuplicateCancel);
  mButton.Cancel := True;
  mButton.ModalResult := mrCancel;
  ClientHeight := mButtons.Top + mButtons.Height + ScaleValue(cGap);
end;

function TAtlasPaintDialog.Checked: TArray<Boolean>;
var
  mIndex: Integer;
begin
  SetLength(Result, FList.Count);
  for mIndex := 0 to FList.Count - 1 do
  begin
    Result[mIndex] := FList.Checked[mIndex] and not FList.Header[mIndex];
  end;
end;

class function TAtlasPaintDialog.Execute(const ASource: string; const ARows: TArray<TAtlasPaintRow>;
  var AChecked: TArray<Boolean>): Boolean;
var
  mDialog: TAtlasPaintDialog;
begin
  mDialog := TAtlasPaintDialog.CreateDialog(nil, ASource, ARows, AChecked);
  try
    Result := mDialog.ShowModal = mrOk;
    if Result then
    begin
      AChecked := mDialog.Checked;
    end;
  finally
    mDialog.Free;
  end;
end;

end.
