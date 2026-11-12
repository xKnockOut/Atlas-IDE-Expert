unit Atlas.UI.Editor.ActionChoices;

// Auswahl der abwählbaren Teile einer Code-Aktion (#2054), etwa der weiteren gleichen Stellen bei „Methode
// extrahieren“: oben die Vorschau des Servers (neue Methode), darunter je Teil ein Häkchen (Vorgabe: an), dann
// „Weiter“ zur gewohnten Vorschau der Änderungen bzw. „Abbrechen“.

interface

uses
  System.Classes,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.CheckLst,
  Atlas.UI.Foundation.Dialog;

type
  TAtlasActionChoicesDialog = class(TAtlasDialog)
  private
    FHint: TLabel;
    FList: TCheckListBox;
    FApply: TButton;
    FCancel: TButton;
    FTitles: TArray<string>;
  public
    constructor CreateChoices(AOwner: TComponent; const ATitle, AHint: string; const ATitles: TArray<string>);
    /// <summary>Liste füllen, alle gewählt (braucht ein Fenster); Choose ruft es vor dem Zeigen.</summary>
    procedure Fill;
    /// <summary>Je Teil gewählt oder nicht, in der Reihenfolge von ATitles.</summary>
    function Chosen: TArray<Boolean>;
    property List: TCheckListBox read FList;
    property ApplyButton: TButton read FApply;
    property CancelButton: TButton read FCancel;
    /// <summary>Modal fragen; False bei Abbrechen.</summary>
    class function Choose(const ATitle, AHint: string; const ATitles: TArray<string>;
      out AChosen: TArray<Boolean>): Boolean; static;
  end;

implementation

uses
  System.UITypes,
  Vcl.Controls,
  Atlas.UI.Editor.Strings;

const
  cGap = 8;
  cWidth = 520;
  cHintHeight = 64;
  cListHeight = 160;
  cButtonWidth = 110;
  cButtonHeight = 25;

{ TAtlasActionChoicesDialog }

constructor TAtlasActionChoicesDialog.CreateChoices(AOwner: TComponent; const ATitle, AHint: string;
  const ATitles: TArray<string>);
begin
  inherited CreateDialog(AOwner, ATitle, cWidth);
  FTitles := ATitles;
  FHint := TLabel.Create(Self);
  FHint.Parent := Self;
  FHint.WordWrap := True;
  FHint.AutoSize := False;
  FHint.SetBounds(ScaleValue(cGap), ScaleValue(cGap), ScaleValue(cWidth - 2 * cGap), ScaleValue(cHintHeight));
  FHint.Caption := AHint + sLineBreak + sLineBreak + TAtlasEditorStrings.Text(TAtlasEditorTextId.ChoicesText);
  FList := TCheckListBox.Create(Self);
  FList.Parent := Self;
  FList.SetBounds(ScaleValue(cGap), FHint.Top + FHint.Height + ScaleValue(cGap), ScaleValue(cWidth - 2 * cGap),
    ScaleValue(cListHeight));
  FCancel := TButton.Create(Self);
  FCancel.Parent := Self;
  FCancel.Caption := TAtlasEditorStrings.Text(TAtlasEditorTextId.ChoicesCancel);
  FCancel.ModalResult := mrCancel;
  FCancel.Cancel := True;
  FCancel.SetBounds(ClientWidth - ScaleValue(cGap + cButtonWidth), FList.Top + FList.Height + ScaleValue(cGap),
    ScaleValue(cButtonWidth), ScaleValue(cButtonHeight));
  FApply := TButton.Create(Self);
  FApply.Parent := Self;
  FApply.Caption := TAtlasEditorStrings.Text(TAtlasEditorTextId.ChoicesApply);
  FApply.ModalResult := mrOk;
  FApply.Default := True;
  FApply.SetBounds(FCancel.Left - ScaleValue(cGap + cButtonWidth), FCancel.Top, ScaleValue(cButtonWidth),
    FCancel.Height);
  ClientHeight := FCancel.Top + FCancel.Height + ScaleValue(cGap);
end;

procedure TAtlasActionChoicesDialog.Fill;
var
  mTitle: string;
  mIndex: Integer;
begin
  // Die Liste braucht ein Fenster, bevor sie Einträge und Häkchen annimmt.
  FList.HandleNeeded;
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for mTitle in FTitles do
    begin
      mIndex := FList.Items.Add(mTitle);
      FList.Checked[mIndex] := True;
    end;
  finally
    FList.Items.EndUpdate;
  end;
end;

function TAtlasActionChoicesDialog.Chosen: TArray<Boolean>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(FTitles));
  for mIndex := 0 to High(Result) do
  begin
    Result[mIndex] := (mIndex < FList.Items.Count) and FList.Checked[mIndex];
  end;
end;

class function TAtlasActionChoicesDialog.Choose(const ATitle, AHint: string; const ATitles: TArray<string>;
  out AChosen: TArray<Boolean>): Boolean;
var
  mDialog: TAtlasActionChoicesDialog;
begin
  AChosen := nil;
  mDialog := TAtlasActionChoicesDialog.CreateChoices(nil, ATitle, AHint, ATitles);
  try
    mDialog.Fill;
    Result := mDialog.ShowModal = mrOk;
    if Result then
    begin
      AChosen := mDialog.Chosen;
    end;
  finally
    mDialog.Free;
  end;
end;

end.
