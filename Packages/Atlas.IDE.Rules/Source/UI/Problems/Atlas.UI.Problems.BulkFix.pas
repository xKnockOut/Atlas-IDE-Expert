unit Atlas.UI.Problems.BulkFix;

// Vorschau der Sammelkorrektur (#1352) aus dem Fenster „Atlas-Prüfung“:
// oben die Zusammenfassung des Servers, links die Dateien mit Anzahl der
// Korrekturen (abwählbar; verworfene Dateien grau und nicht wählbar), rechts
// der Diff der markierten Datei in Festbreitenschrift, unten die Auswahl
// („n Korrekturen in m Dateien gewählt“), „Korrigieren“ und „Abbrechen“.
// „Korrigieren“ ist nur mit mindestens einer gewählten Datei möglich. Reine
// VCL; das Modell (TAtlasBulkFixPreview) liefert der Aufrufer und behält es.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.CheckLst,
  Atlas.Core.Problems.BulkFix,
  Atlas.UI.Foundation.Dialog;

type
  TAtlasBulkFixDialog = class(TAtlasDialog)
  private
    FPreview: TAtlasBulkFixPreview;
    FSummary: TLabel;
    FFiles: TCheckListBox;
    FDiff: TMemo;
    FSelection: TLabel;
    FApply: TButton;
    FCancel: TButton;
    FUpdating: Boolean;
    procedure CreateSummary;
    procedure CreateButtons;
    procedure CreateLists;
    function FileCaption(AIndex: Integer): string;
    procedure ShowDiff;
    procedure UpdateSelection;
    procedure FilesClick(Sender: TObject);
    procedure FilesClickCheck(Sender: TObject);
    procedure ApplyClick(Sender: TObject);
    procedure CancelClick(Sender: TObject);
  protected
    procedure DoShow; override;
  public
    constructor CreateDialog(AOwner: TComponent; APreview: TAtlasBulkFixPreview);
    /// <summary>Liste füllen; braucht ein Fenster (DoShow, Tests nach HandleNeeded).</summary>
    procedure Fill;
    /// <summary>True mit „Korrigieren“; die Auswahl steht dann in APreview.</summary>
    class function Execute(APreview: TAtlasBulkFixPreview): Boolean; static;
    property SummaryLabel: TLabel read FSummary;
    property FileList: TCheckListBox read FFiles;
    property DiffMemo: TMemo read FDiff;
    property SelectionLabel: TLabel read FSelection;
    property ApplyButton: TButton read FApply;
  end;

implementation

uses
  Atlas.UI.Rules.Strings;

const
  cGap = 8;
  cDialogWidth = 860;

{ TAtlasBulkFixDialog }

constructor TAtlasBulkFixDialog.CreateDialog(AOwner: TComponent; APreview: TAtlasBulkFixPreview);
begin
  inherited CreateDialog(AOwner, '', cDialogWidth);
  FPreview := APreview;
  Caption := TAtlasRulesStrings.Fmt(TAtlasRulesTextId.FixPreviewTitle, [APreview.Rule]);
  BorderStyle := bsSizeable;
  BorderIcons := [biSystemMenu, biMaximize];
  KeyPreview := True;
  ClientHeight := ScaleValue(520);

  CreateSummary;
  CreateButtons;
  CreateLists;
  ActiveControl := FFiles;
end;

/// <summary>Oben die Zusammenfassung des Servers.</summary>
procedure TAtlasBulkFixDialog.CreateSummary;
var
  mTop: TPanel;
begin
  mTop := TPanel.Create(Self);
  mTop.Parent := Self;
  mTop.Align := alTop;
  mTop.BevelOuter := bvNone;
  mTop.ShowCaption := False;
  mTop.AutoSize := True;
  FSummary := TLabel.Create(Self);
  FSummary.Parent := mTop;
  FSummary.Align := alTop;
  FSummary.AlignWithMargins := True;
  FSummary.Margins.SetBounds(ScaleValue(cGap), ScaleValue(cGap), ScaleValue(cGap), ScaleValue(cGap div 2));
  FSummary.ShowAccelChar := False;
  FSummary.WordWrap := True;
  FSummary.Caption := FPreview.Summary;
end;

/// <summary>Unten die Auswahl, „Korrigieren“ und „Abbrechen“.</summary>
procedure TAtlasBulkFixDialog.CreateButtons;
var
  mBottom: TPanel;
begin
  mBottom := TPanel.Create(Self);
  mBottom.Parent := Self;
  mBottom.Align := alBottom;
  mBottom.Height := ScaleValue(44);
  mBottom.BevelOuter := bvNone;
  mBottom.ShowCaption := False;
  FCancel := TButton.Create(Self);
  FCancel.Parent := mBottom;
  FCancel.Caption := TAtlasRulesStrings.Text(TAtlasRulesTextId.FixPreviewCancel);
  FCancel.Width := ScaleValue(100);
  FCancel.Height := ScaleValue(28);
  FCancel.Top := ScaleValue(cGap);
  FCancel.Left := mBottom.ClientWidth - FCancel.Width - ScaleValue(cGap);
  FCancel.Anchors := [akTop, akRight];
  FCancel.Cancel := True;
  FCancel.OnClick := CancelClick;
  FApply := TButton.Create(Self);
  FApply.Parent := mBottom;
  FApply.Caption := TAtlasRulesStrings.Text(TAtlasRulesTextId.FixPreviewApply);
  FApply.Width := ScaleValue(100);
  FApply.Height := ScaleValue(28);
  FApply.Top := ScaleValue(cGap);
  FApply.Left := FCancel.Left - FApply.Width - ScaleValue(cGap);
  FApply.Anchors := [akTop, akRight];
  FApply.Default := True;
  FApply.OnClick := ApplyClick;
  FSelection := TLabel.Create(Self);
  FSelection.Parent := mBottom;
  FSelection.Left := ScaleValue(cGap);
  FSelection.Top := ScaleValue(cGap + 6);
  FSelection.ShowAccelChar := False;
end;

/// <summary>Links die Dateien, rechts der Diff der markierten Datei.</summary>
procedure TAtlasBulkFixDialog.CreateLists;
var
  mSplitter: TSplitter;
begin
  FFiles := TCheckListBox.Create(Self);
  FFiles.Parent := Self;
  FFiles.Align := alLeft;
  FFiles.AlignWithMargins := True;
  FFiles.Margins.SetBounds(ScaleValue(cGap), 0, 0, 0);
  FFiles.Width := ScaleValue(280);
  FFiles.OnClick := FilesClick;
  FFiles.OnClickCheck := FilesClickCheck;
  mSplitter := TSplitter.Create(Self);
  mSplitter.Parent := Self;
  mSplitter.Align := alLeft;
  mSplitter.Left := FFiles.Left + FFiles.Width + 1;
  FDiff := TMemo.Create(Self);
  FDiff.Parent := Self;
  FDiff.Align := alClient;
  FDiff.AlignWithMargins := True;
  FDiff.Margins.SetBounds(0, 0, ScaleValue(cGap), 0);
  FDiff.ReadOnly := True;
  FDiff.ScrollBars := ssBoth;
  FDiff.WordWrap := False;
  FDiff.Font.Name := 'Consolas';
  FDiff.Font.Size := 9;
end;

function TAtlasBulkFixDialog.FileCaption(AIndex: Integer): string;
var
  mFile: TAtlasBulkFixFile;
begin
  mFile := FPreview.Files[AIndex];
  if mFile.Rejected then
  begin
    Result := TAtlasRulesStrings.Fmt(TAtlasRulesTextId.FixPreviewRejected, [ExtractFileName(mFile.FileName)]);
  end
  else
  begin
    Result := Format('%s (%d)', [ExtractFileName(mFile.FileName), mFile.Fixes]);
  end;
end;

procedure TAtlasBulkFixDialog.Fill;
var
  mIndex: Integer;
begin
  if FFiles.Items.Count > 0 then
  begin
    Exit;
  end;
  FUpdating := True;
  try
    FFiles.Items.BeginUpdate;
    try
      for mIndex := 0 to FPreview.Count - 1 do
      begin
        FFiles.Items.Add(FileCaption(mIndex));
        FFiles.Checked[mIndex] := FPreview.Files[mIndex].Checked;
        FFiles.ItemEnabled[mIndex] := FPreview.Files[mIndex].Checked;
      end;
    finally
      FFiles.Items.EndUpdate;
    end;
  finally
    FUpdating := False;
  end;
  if FFiles.Items.Count > 0 then
  begin
    FFiles.ItemIndex := 0;
  end;
  ShowDiff;
  UpdateSelection;
end;

procedure TAtlasBulkFixDialog.DoShow;
begin
  inherited;
  // Die Liste braucht ein Fenster: erst hier füllen.
  Fill;
end;

procedure TAtlasBulkFixDialog.ShowDiff;
begin
  if (FFiles.ItemIndex < 0) or (FFiles.ItemIndex >= FPreview.Count) then
  begin
    FDiff.Lines.Text := '';
  end
  else
  begin
    FDiff.Lines.Text := FPreview.Files[FFiles.ItemIndex].Diff;
  end;
end;

procedure TAtlasBulkFixDialog.UpdateSelection;
begin
  FSelection.Caption := TAtlasRulesStrings.Fmt(TAtlasRulesTextId.FixPreviewSelection, [FPreview.SelectedFixes,
    FPreview.SelectedCount]);
  FApply.Enabled := FPreview.SelectedCount > 0;
end;

procedure TAtlasBulkFixDialog.FilesClick(Sender: TObject);
begin
  ShowDiff;
end;

procedure TAtlasBulkFixDialog.FilesClickCheck(Sender: TObject);
var
  mIndex: Integer;
begin
  if FUpdating then
  begin
    Exit;
  end;
  for mIndex := 0 to FFiles.Items.Count - 1 do
  begin
    FPreview.SetChecked(mIndex, FFiles.Checked[mIndex]);
  end;
  UpdateSelection;
end;

procedure TAtlasBulkFixDialog.ApplyClick(Sender: TObject);
begin
  if FPreview.SelectedCount > 0 then
  begin
    ModalResult := mrOk;
  end;
end;

procedure TAtlasBulkFixDialog.CancelClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

class function TAtlasBulkFixDialog.Execute(APreview: TAtlasBulkFixPreview): Boolean;
var
  mDialog: TAtlasBulkFixDialog;
begin
  mDialog := TAtlasBulkFixDialog.CreateDialog(nil, APreview);
  try
    Result := mDialog.ShowModal = mrOk;
  finally
    mDialog.Free;
  end;
end;

end.
