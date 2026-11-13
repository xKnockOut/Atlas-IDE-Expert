unit Atlas.UI.Tests.LeakSetup;

// Dialog „Leckprüfung einrichten …“ (#1880), reine VCL: oben der Stand des
// Projekts (✓/✗ je Punkt), darunter die Varianten Einfach, FastMM4 und
// FastMM5 (nur wählbar, was geht; fehlt FastMM, steht die Bezugsquelle da),
// „Bericht als Datei“ und die Knöpfe „Einrichten …“ und „Schließen“. Daten
// und Regeln in Atlas.Core.Tests.LeakSetup.

interface

uses
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Atlas.UI.Foundation.Dialog,
  Atlas.Core.Tests.LeakSetup;

type
  TAtlasLeakSetupDialog = class(TAtlasDialog)
  private const
    cWidth = 560;
    cLineHeight = 20;
  private
    FChoices: array[TAtlasLeakChoice] of TRadioButton;
    FFileReport: TCheckBox;
    FSetUp: TButton;
    procedure AddStatus(const AInfo: TAtlasLeakSetupInfo);
    procedure AddChoices(const AInfo: TAtlasLeakSetupInfo);
    procedure ChoiceClick(Sender: TObject);
    function Chosen: TAtlasLeakChoice;
  public
    constructor CreateFor(AOwner: TComponent; const AInfo: TAtlasLeakSetupInfo);
    /// <summary>Modal zeigen; True mit Variante und Wunsch „Bericht als Datei“, wenn „Einrichten …“.</summary>
    class function Execute(const AInfo: TAtlasLeakSetupInfo; out AChoice: TAtlasLeakChoice;
      out AFileReport: Boolean): Boolean; static;
    /// <summary>Text einer Zeile des Stands mit ✓ bzw. ✗ davor.</summary>
    class function StatusText(const AStatus: TAtlasLeakStatus): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.UITypes,
  Vcl.Forms,
  Atlas.UI.Tests.Strings;

const
  cOkMark = #$2713;
  cMissingMark = #$2717;

type
  TLeakTexts = array[Boolean] of TAtlasTestsTextId;

const
  // Je Zeilenart: [nicht erfüllt, erfüllt].
  cStatusTexts: array[TAtlasLeakLine] of TLeakTexts = (
    (TAtlasTestsTextId.LeakPackage, TAtlasTestsTextId.LeakPackage),
    (TAtlasTestsTextId.LeakSource4Missing, TAtlasTestsTextId.LeakSource4Found),
    (TAtlasTestsTextId.LeakSource5Missing, TAtlasTestsTextId.LeakSource5Found),
    (TAtlasTestsTextId.LeakUsesMissing, TAtlasTestsTextId.LeakUsesFound),
    (TAtlasTestsTextId.LeakUsesNotFirst, TAtlasTestsTextId.LeakUsesNotFirst),
    (TAtlasTestsTextId.LeakUsesNotDebug, TAtlasTestsTextId.LeakUsesNotDebug),
    (TAtlasTestsTextId.LeakReportMissing, TAtlasTestsTextId.LeakReportFound),
    (TAtlasTestsTextId.LeakReportNotDebug, TAtlasTestsTextId.LeakReportNotDebug),
    (TAtlasTestsTextId.LeakDefineMissing, TAtlasTestsTextId.LeakDefineFound),
    (TAtlasTestsTextId.LeakFileReportOff, TAtlasTestsTextId.LeakFileReportOn),
    (TAtlasTestsTextId.LeakDllMissing, TAtlasTestsTextId.LeakDllFound),
    (TAtlasTestsTextId.LeakMonitorMissing, TAtlasTestsTextId.LeakMonitorFound),
    (TAtlasTestsTextId.LeakMonitorMissing, TAtlasTestsTextId.LeakMonitorFound));

  cChoiceTexts: array[TAtlasLeakChoice] of TAtlasTestsTextId = (TAtlasTestsTextId.LeakChoiceSimple,
    TAtlasTestsTextId.LeakChoiceFastMM4, TAtlasTestsTextId.LeakChoiceFastMM5);

class function TAtlasLeakSetupDialog.StatusText(const AStatus: TAtlasLeakStatus): string;
var
  mMark: string;
begin
  if AStatus.Ok then
  begin
    mMark := cOkMark;
  end
  else
  begin
    mMark := cMissingMark;
  end;
  Result := mMark + ' ' + TAtlasTestsStrings.Fmt(cStatusTexts[AStatus.Line][AStatus.Ok], [AStatus.Value]);
end;

constructor TAtlasLeakSetupDialog.CreateFor(AOwner: TComponent; const AInfo: TAtlasLeakSetupInfo);
var
  mRow: TAtlasButtonRow;
  mClose: TButton;
begin
  inherited CreateDialog(AOwner, TAtlasTestsStrings.Fmt(TAtlasTestsTextId.LeakSetupTitle,
    [ExtractFileName(AInfo.Project)]), cWidth);
  AddStatus(AInfo);
  AddChoices(AInfo);
  mRow := AddButtonRow;
  FSetUp := mRow.AddButton(TAtlasTestsStrings.Text(TAtlasTestsTextId.LeakSetupButton),
    TAtlasButtonKind.Default);
  FSetUp.ModalResult := mrOk;
  mClose := mRow.AddButton(TAtlasTestsStrings.Text(TAtlasTestsTextId.LeakCloseButton),
    TAtlasButtonKind.Cancel);
  mClose.ModalResult := mrCancel;
  ChoiceClick(nil);
  FitHeight;
end;

procedure TAtlasLeakSetupDialog.AddStatus(const AInfo: TAtlasLeakSetupInfo);
var
  mStatus: TAtlasLeakStatus;
  mLabel: TLabel;
begin
  AddLabel(AddRow(cLineHeight), TAtlasTestsStrings.Fmt(TAtlasTestsTextId.LeakStatusCaption,
    [ExtractFileName(AInfo.MainSource), AInfo.Platform]));
  for mStatus in AInfo.Status do
  begin
    mLabel := AddLabel(AddRow(cLineHeight), StatusText(mStatus));
    // Lange Pfade: abgeschnitten, ganz im Hinweis.
    mLabel.AutoSize := False;
    mLabel.Width := ScaleValue(cWidth);
    mLabel.EllipsisPosition := epPathEllipsis;
    mLabel.Hint := mLabel.Caption;
    mLabel.ShowHint := True;
  end;
end;

procedure TAtlasLeakSetupDialog.AddChoices(const AInfo: TAtlasLeakSetupInfo);
var
  mChoice: TAtlasLeakChoice;
  mCaption: string;
begin
  for mChoice := Low(TAtlasLeakChoice) to High(TAtlasLeakChoice) do
  begin
    mCaption := TAtlasTestsStrings.Text(cChoiceTexts[mChoice]);
    if not AInfo.Available(mChoice) then
    begin
      mCaption := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.LeakChoiceUnavailable, [mCaption]);
    end;
    FChoices[mChoice] := TRadioButton.Create(Self);
    FChoices[mChoice].Parent := AddRow(cLineHeight);
    FChoices[mChoice].Align := alClient;
    FChoices[mChoice].Caption := mCaption;
    FChoices[mChoice].Enabled := AInfo.Available(mChoice);
    FChoices[mChoice].OnClick := ChoiceClick;
  end;
  if AInfo.Available(AInfo.Preselect) then
  begin
    FChoices[AInfo.Preselect].Checked := True;
  end;
  if (AInfo.Sources[TAtlasLeakChoice.FastMM4].FileName = '') or
    (AInfo.Sources[TAtlasLeakChoice.FastMM5].FileName = '') then
  begin
    AddLabel(AddRow(cLineHeight), TAtlasTestsStrings.Text(TAtlasTestsTextId.LeakDownloadHint));
  end;
  FFileReport := TCheckBox.Create(Self);
  FFileReport.Parent := AddRow(cLineHeight);
  FFileReport.Align := alClient;
  FFileReport.Caption := TAtlasTestsStrings.Text(TAtlasTestsTextId.LeakFileReportOption);
  FFileReport.Checked := AInfo.FileReport;
end;

function TAtlasLeakSetupDialog.Chosen: TAtlasLeakChoice;
var
  mChoice: TAtlasLeakChoice;
begin
  Result := TAtlasLeakChoice.Simple;
  for mChoice := Low(TAtlasLeakChoice) to High(TAtlasLeakChoice) do
  begin
    if FChoices[mChoice].Checked then
    begin
      Result := mChoice;
    end;
  end;
end;

procedure TAtlasLeakSetupDialog.ChoiceClick(Sender: TObject);
var
  mAny: Boolean;
  mChoice: TAtlasLeakChoice;
begin
  mAny := False;
  for mChoice := Low(TAtlasLeakChoice) to High(TAtlasLeakChoice) do
  begin
    mAny := mAny or FChoices[mChoice].Checked;
  end;
  // Bericht als Datei gibt es nur mit FastMM; der Speichermanager der RTL zeigt immer ein Meldungsfenster.
  FFileReport.Enabled := mAny and (Chosen <> TAtlasLeakChoice.Simple);
  FSetUp.Enabled := mAny;
end;

class function TAtlasLeakSetupDialog.Execute(const AInfo: TAtlasLeakSetupInfo; out AChoice: TAtlasLeakChoice;
  out AFileReport: Boolean): Boolean;
var
  mDialog: TAtlasLeakSetupDialog;
begin
  AChoice := TAtlasLeakChoice.Simple;
  AFileReport := False;
  mDialog := TAtlasLeakSetupDialog.CreateFor(Application, AInfo);
  try
    Result := mDialog.ShowModal = mrOk;
    if Result then
    begin
      AChoice := mDialog.Chosen;
      AFileReport := mDialog.FFileReport.Enabled and mDialog.FFileReport.Checked;
    end;
  finally
    mDialog.Free;
  end;
end;

end.
