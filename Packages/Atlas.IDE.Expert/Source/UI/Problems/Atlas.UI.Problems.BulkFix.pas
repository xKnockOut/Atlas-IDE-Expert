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
  Atlas.Core.Problems.BulkFix;

type
  TAtlasBulkFixDialog = class(TForm)
  private
    FPreview: TAtlasBulkFixPreview;
    FSummary: TLabel;
    FFiles: TCheckListBox;
    FDiff: TMemo;
    FSelection: TLabel;
    FApply: TButton;
    FCancel: TButton;
    FUpdating: Boolean;
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
  Atlas.UI.Strings;

const
  Gap = 8;

{ TAtlasBulkFixDialog }

constructor TAtlasBulkFixDialog.CreateDialog(AOwner: TComponent; APreview: TAtlasBulkFixPreview);
var
  mBottom, mTop: TPanel;
  mSplitter: TSplitter;
begin
  inherited CreateNew(AOwner);
  FPreview := APreview;
  Caption := TAtlasStrings.Fmt(TAtlasTextId.FixPreviewTitle, [APreview.Rule]);
  BorderStyle := bsSizeable;
  BorderIcons := [biSystemMenu, biMaximize];
  Position := poMainFormCenter;
  KeyPreview := True;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  ClientWidth := ScaleValue(860);
  ClientHeight := ScaleValue(520);

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
  FSummary.Margins.SetBounds(ScaleValue(Gap), ScaleValue(Gap), ScaleValue(Gap), ScaleValue(Gap div 2));
  FSummary.ShowAccelChar := False;
  FSummary.WordWrap := True;
  FSummary.Caption := APreview.Summary;

  mBottom := TPanel.Create(Self);
  mBottom.Parent := Self;
  mBottom.Align := alBottom;
  mBottom.Height := ScaleValue(44);
  mBottom.BevelOuter := bvNone;
  mBottom.ShowCaption := False;
  FCancel := TButton.Create(Self);
  FCancel.Parent := mBottom;
  FCancel.Caption := TAtlasStrings.Text(TAtlasTextId.FixPreviewCancel);
  FCancel.Width := ScaleValue(100);
  FCancel.Height := ScaleValue(28);
  FCancel.Top := ScaleValue(Gap);
  FCancel.Left := mBottom.ClientWidth - FCancel.Width - ScaleValue(Gap);
  FCancel.Anchors := [akTop, akRight];
  FCancel.Cancel := True;
  FCancel.OnClick := CancelClick;
  FApply := TButton.Create(Self);
  FApply.Parent := mBottom;
  FApply.Caption := TAtlasStrings.Text(TAtlasTextId.FixPreviewApply);
  FApply.Width := ScaleValue(100);
  FApply.Height := ScaleValue(28);
  FApply.Top := ScaleValue(Gap);
  FApply.Left := FCancel.Left - FApply.Width - ScaleValue(Gap);
  FApply.Anchors := [akTop, akRight];
  FApply.Default := True;
  FApply.OnClick := ApplyClick;
  FSelection := TLabel.Create(Self);
  FSelection.Parent := mBottom;
  FSelection.Left := ScaleValue(Gap);
  FSelection.Top := ScaleValue(Gap + 6);
  FSelection.ShowAccelChar := False;

  FFiles := TCheckListBox.Create(Self);
  FFiles.Parent := Self;
  FFiles.Align := alLeft;
  FFiles.AlignWithMargins := True;
  FFiles.Margins.SetBounds(ScaleValue(Gap), 0, 0, 0);
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
  FDiff.Margins.SetBounds(0, 0, ScaleValue(Gap), 0);
  FDiff.ReadOnly := True;
  FDiff.ScrollBars := ssBoth;
  FDiff.WordWrap := False;
  FDiff.Font.Name := 'Consolas';
  FDiff.Font.Size := 9;
  ActiveControl := FFiles;
end;

function TAtlasBulkFixDialog.FileCaption(AIndex: Integer): string;
var
  mFile: TAtlasBulkFixFile;
begin
  mFile := FPreview.Files[AIndex];
  if mFile.Rejected then
    Result := TAtlasStrings.Fmt(TAtlasTextId.FixPreviewRejected, [ExtractFileName(mFile.FileName)])
  else
    Result := Format('%s (%d)', [ExtractFileName(mFile.FileName), mFile.Fixes]);
end;

procedure TAtlasBulkFixDialog.Fill;
var
  mIndex: Integer;
begin
  if FFiles.Items.Count > 0 then
    Exit;
  FUpdating := True;
  try
    for mIndex := 0 to FPreview.Count - 1 do
    begin
      FFiles.Items.Add(FileCaption(mIndex));
      FFiles.Checked[mIndex] := FPreview.Files[mIndex].Checked;
      FFiles.ItemEnabled[mIndex] := FPreview.Files[mIndex].Checked;
    end;
  finally
    FUpdating := False;
  end;
  if FFiles.Items.Count > 0 then
    FFiles.ItemIndex := 0;
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
    FDiff.Lines.Text := ''
  else
    FDiff.Lines.Text := FPreview.Files[FFiles.ItemIndex].Diff;
end;

procedure TAtlasBulkFixDialog.UpdateSelection;
begin
  FSelection.Caption := TAtlasStrings.Fmt(TAtlasTextId.FixPreviewSelection, [FPreview.SelectedFixes,
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
    Exit;
  for mIndex := 0 to FFiles.Items.Count - 1 do
    FPreview.SetChecked(mIndex, FFiles.Checked[mIndex]);
  UpdateSelection;
end;

procedure TAtlasBulkFixDialog.ApplyClick(Sender: TObject);
begin
  if FPreview.SelectedCount > 0 then
    ModalResult := mrOk;
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
