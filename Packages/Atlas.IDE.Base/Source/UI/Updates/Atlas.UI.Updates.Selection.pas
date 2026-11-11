unit Atlas.UI.Updates.Selection;

// Auswahl der Module eines Updates (#1519, Mockup 6): eine Liste mit
// Häkchen. Kern und Verträge sind gewählt und nicht abwählbar, neue Module
// tragen „(neu)“. Vorgewählt ist der Vorschlag von AtlasUpdate.exe
// (bisherige Module ja, neue nach updates.newModules).

interface

uses
  System.Classes,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.CheckLst,
  Atlas.Text.UpdateRun,
  Atlas.UI.Foundation.Dialog;

type
  TAtlasUpdateSelectionDialog = class(TAtlasDialog)
  private
    FText: TLabel;
    FList: TCheckListBox;
    FApply: TButton;
    FCancel: TButton;
    FCandidates: TArray<TUpdateCandidate>;
    procedure ListClickCheck(Sender: TObject);
  public
    constructor CreateSelection(AOwner: TComponent; const AVersion: string;
      const ACandidates: TArray<TUpdateCandidate>);
    /// <summary>Liste füllen (braucht ein Fenster); Choose ruft es vor dem Zeigen.</summary>
    procedure Fill;
    /// <summary>Gewählte Namen in der Reihenfolge der Kandidaten.</summary>
    function Chosen: TArray<string>;
    property List: TCheckListBox read FList;
    property ApplyButton: TButton read FApply;
    property CancelButton: TButton read FCancel;
    /// <summary>Modal fragen; False bei Abbrechen.</summary>
    class function Choose(const AVersion: string; const ACandidates: TArray<TUpdateCandidate>;
      out AChosen: TArray<string>): Boolean; static;
  end;

implementation

uses
  System.UITypes,
  Vcl.Controls,
  Atlas.UI.Updates.Strings;

const
  cGap = 8;
  cWidth = 420;
  cListHeight = 220;
  cButtonWidth = 110;

{ TAtlasUpdateSelectionDialog }

constructor TAtlasUpdateSelectionDialog.CreateSelection(AOwner: TComponent; const AVersion: string;
  const ACandidates: TArray<TUpdateCandidate>);
begin
  inherited CreateDialog(AOwner, '', cWidth);
  FCandidates := ACandidates;
  Caption := TAtlasUpdatesStrings.Fmt(TAtlasUpdatesTextId.UpdatesSelectionTitle, [AVersion]);
  FText := TLabel.Create(Self);
  FText.Parent := Self;
  FText.WordWrap := True;
  FText.SetBounds(ScaleValue(cGap), ScaleValue(cGap), ScaleValue(cWidth - 2 * cGap), ScaleValue(48));
  FText.Caption := TAtlasUpdatesStrings.Text(TAtlasUpdatesTextId.UpdatesSelectionText);
  FList := TCheckListBox.Create(Self);
  FList.Parent := Self;
  FList.SetBounds(ScaleValue(cGap), FText.Top + FText.Height + ScaleValue(cGap), ScaleValue(cWidth - 2 * cGap),
    ScaleValue(cListHeight));
  FList.OnClickCheck := ListClickCheck;
  FCancel := TButton.Create(Self);
  FCancel.Parent := Self;
  FCancel.Caption := TAtlasUpdatesStrings.Text(TAtlasUpdatesTextId.UpdatesSelectionCancel);
  FCancel.ModalResult := mrCancel;
  FCancel.Cancel := True;
  FCancel.SetBounds(ClientWidth - ScaleValue(cGap + cButtonWidth), FList.Top + FList.Height + ScaleValue(cGap),
    ScaleValue(cButtonWidth), ScaleValue(25));
  FApply := TButton.Create(Self);
  FApply.Parent := Self;
  FApply.Caption := TAtlasUpdatesStrings.Text(TAtlasUpdatesTextId.UpdatesSelectionApply);
  FApply.ModalResult := mrOk;
  FApply.Default := True;
  FApply.SetBounds(FCancel.Left - ScaleValue(cGap + cButtonWidth), FCancel.Top, ScaleValue(cButtonWidth),
    FCancel.Height);
  ClientHeight := FCancel.Top + FCancel.Height + ScaleValue(cGap);
end;

procedure TAtlasUpdateSelectionDialog.Fill;
var
  mCandidate: TUpdateCandidate;
  mCaption: string;
  mIndex: Integer;
begin
  // Die Liste braucht ein Fenster, bevor sie Einträge und Häkchen annimmt.
  FList.HandleNeeded;
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for mCandidate in FCandidates do
    begin
      mCaption := mCandidate.Name;
      if mCandidate.Required then
      begin
        mCaption := TAtlasUpdatesStrings.Fmt(TAtlasUpdatesTextId.UpdatesSelectionRequired, [mCandidate.Name]);
      end
      else if mCandidate.IsNew then
      begin
        mCaption := TAtlasUpdatesStrings.Fmt(TAtlasUpdatesTextId.UpdatesSelectionNew, [mCandidate.Name]);
      end;
      mIndex := FList.Items.Add(mCaption);
      FList.Checked[mIndex] := mCandidate.Selected or mCandidate.Required;
      FList.ItemEnabled[mIndex] := not mCandidate.Required;
    end;
  finally
    FList.Items.EndUpdate;
  end;
end;

procedure TAtlasUpdateSelectionDialog.ListClickCheck(Sender: TObject);
var
  mIndex: Integer;
begin
  // Pflicht-Packages bleiben gewählt, auch über die Leertaste.
  for mIndex := 0 to FList.Items.Count - 1 do
  begin
    if FCandidates[mIndex].Required then
    begin
      FList.Checked[mIndex] := True;
    end;
  end;
end;

function TAtlasUpdateSelectionDialog.Chosen: TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to FList.Items.Count - 1 do
  begin
    if FList.Checked[mIndex] then
    begin
      Result := Result + [FCandidates[mIndex].Name];
    end;
  end;
end;

class function TAtlasUpdateSelectionDialog.Choose(const AVersion: string;
  const ACandidates: TArray<TUpdateCandidate>; out AChosen: TArray<string>): Boolean;
var
  mDialog: TAtlasUpdateSelectionDialog;
begin
  AChosen := nil;
  mDialog := TAtlasUpdateSelectionDialog.CreateSelection(nil, AVersion, ACandidates);
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
