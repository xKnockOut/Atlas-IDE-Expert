unit Atlas.UI.Diagnostics.ReportDialog;

// Dialog „Problem melden“ (#766), ohne Open Tools API:
//   Hinweis (nichts wird automatisch gesendet)
//   Kurzbeschreibung [Memo]
//   Ins Paket kommen: [x] Logs  [x] Versionen  [x] Einstellungen  [ ] Diagnosedaten
//   Vorschau: Datei | Größe       (Doppelklick oder „Ansehen“ zeigt den Inhalt)
//   3 Dateien, zusammen 41,2 KB
//   Ordner: C:\Users\…\Desktop                                  [Ordner …]
//   Angelegt: Atlas-Diagnose-2026-10-15.zip
//   [ZIP anlegen] [Issue-Seite öffnen]                           [Schließen]
// Die Vorschau zeigt genau die Dateien, die TAtlasDiagnosticPackage.Build für
// die gewählten Teile liefert, und wird bei jedem Häkchen neu gebaut.
// „ZIP anlegen“ schreibt Atlas-Diagnose-<Datum>.zip in den Ordner und zeigt
// ihn im Explorer; „Issue-Seite öffnen“ legt die ausgefüllte Vorlage in die
// Zwischenablage und öffnet die Zieladresse im Browser. Atlas selbst greift
// nicht aufs Netz zu und sendet nichts. Explorer, Zwischenablage, Browser und
// Ordnerwahl kommen über TAtlasReportActions aus der IDE-Schicht (Tests
// setzen eigene).

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Vcl.Graphics,
  Atlas.Core.Diagnostics.Package;

type
  TAtlasReportActions = record
    /// <summary>Datei im Explorer zeigen.</summary>
    ShowFile: TProc<string>;
    /// <summary>Text in die Zwischenablage legen.</summary>
    CopyText: TProc<string>;
    /// <summary>Webadresse im Browser öffnen.</summary>
    OpenUrl: TProc<string>;
    /// <summary>Ordner wählen, ausgehend vom übergebenen; '' = abgebrochen. nil = Auswahl der VCL.</summary>
    PickFolder: TFunc<string, string>;
    /// <summary>Inhalt einer Datei zeigen (Name, Text). nil = eingebautes Fenster.</summary>
    ShowText: TProc<string, string>;
  end;

  TAtlasReportDialog = class(TForm)
  public const
    cGap = 8;
  private type
    /// <summary>Steuerelemente des Dialogs.</summary>
    TParts = record
      Description: TMemo;
      Checks: array[TAtlasPackagePart] of TCheckBox;
      List: TListView;
      Summary: TLabel;
      FolderLabel: TLabel;
      Status: TLabel;
      ViewButton: TButton;
      FolderButton: TButton;
      ZipButton: TButton;
      IssueButton: TButton;
      CloseButton: TButton;
    end;
  private
    FInput: TAtlasPackageInput;
    FActions: TAtlasReportActions;
    FFolder: string;
    FReportUrl: string;
    FFiles: TAtlasPackageFiles;
    FZipFile: string;
    FLastDataAvailable: Boolean;
    FParts: TParts;
    /// <summary>Hinweis, Kurzbeschreibung und Überschrift der Teile (von oben gestapelt).</summary>
    procedure CreateHead;
    /// <summary>Ein Häkchen je Teil des Pakets.</summary>
    procedure CreateChecks;
    /// <summary>Fuß mit Summe, Ordner, Status und Knöpfen.</summary>
    procedure CreateFoot;
    /// <summary>Vorschau der Dateien.</summary>
    procedure CreateList;
    procedure PartClick(Sender: TObject);
    procedure FootResize(Sender: TObject);
    procedure ListSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure ViewClick(Sender: TObject);
    procedure FolderClick(Sender: TObject);
    procedure ZipClick(Sender: TObject);
    procedure IssueClick(Sender: TObject);
    procedure ShowFolder;
  public
    /// <summary>AInput: alles außer den gewählten Teilen; AFolder: Ziel der ZIP; AReportUrl: Seite für neue
    /// Issues.</summary>
    constructor CreateDialog(AOwner: TComponent; const AInput: TAtlasPackageInput; const AFolder,
      AReportUrl: string; const AActions: TAtlasReportActions);
    /// <summary>Gewählte Teile.</summary>
    function Parts: TAtlasPackageParts;
    /// <summary>Vorschau neu bauen (nach einem Häkchen).</summary>
    procedure Reload;
    /// <summary>Inhalt der Datei AIndex zeigen; liefert ihn.</summary>
    function ViewFile(AIndex: Integer): string;
    /// <summary>„ZIP anlegen“: True, wenn die Datei geschrieben ist.</summary>
    function CreateZip: Boolean;
    /// <summary>„Issue-Seite öffnen“: Vorlage in die Zwischenablage, Zieladresse im Browser.</summary>
    procedure OpenIssue;
    /// <summary>Ausgefüllte Issue-Vorlage für die aktuelle Auswahl.</summary>
    function IssueText: string;
    /// <summary>„812 Bytes“, „4,2 KB“, „1,3 MB“.</summary>
    class function SizeText(ABytes: Int64): string; static;
    class procedure Execute(const AInput: TAtlasPackageInput; const AFolder, AReportUrl: string;
      const AActions: TAtlasReportActions); static;
    function Check(APart: TAtlasPackagePart): TCheckBox;
    property Files: TAtlasPackageFiles read FFiles;
    property ZipFile: string read FZipFile;
    property Description: TMemo read FParts.Description;
    property List: TListView read FParts.List;
    property SummaryLabel: TLabel read FParts.Summary;
    property StatusLabel: TLabel read FParts.Status;
    property ZipButton: TButton read FParts.ZipButton;
    property IssueButton: TButton read FParts.IssueButton;
    property ViewButton: TButton read FParts.ViewButton;
  end;

implementation

uses
  System.Math,
  Vcl.Dialogs,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Strings,
  Atlas.UI.Diagnostics.Strings;

const
  // Vorläufige Lage der Überschriften; die Ausrichtung ordnet sie danach in dieser Reihenfolge an.
  cPartsTop = 300;
  cPreviewTop = 500;
  // Breiten der Knöpfe in der Fußleiste.
  cViewButtonWidth = 110;
  cFolderButtonWidth = 110;
  cZipButtonWidth = 130;
  cIssueButtonWidth = 160;
  cBytesPerKb = 1024;
  cBytesPerMb = cBytesPerKb * cBytesPerKb;

/// <summary>Eingebautes Fenster für den Inhalt einer Datei.</summary>
procedure ShowTextWindow(const AName, AText: string);
var
  mViewer: TForm;
  mMemo: TMemo;
  mBottom: TPanel;
  mButton: TButton;
begin
  mViewer := TForm.CreateNew(nil);
  try
    mViewer.Caption := TAtlasDiagnosticsStrings.Fmt(TAtlasDiagnosticsTextId.ReportViewerTitle, [AName]);
    mViewer.BorderStyle := bsSizeable;
    mViewer.Position := poMainFormCenter;
    mViewer.Width := mViewer.ScaleValue(900);
    mViewer.Height := mViewer.ScaleValue(600);
    mBottom := TPanel.Create(mViewer);
    mBottom.Parent := mViewer;
    mBottom.Align := alBottom;
    mBottom.Height := mBottom.ScaleValue(44);
    mBottom.BevelOuter := bvNone;
    mButton := TButton.Create(mViewer);
    mButton.Parent := mBottom;
    mButton.Width := mButton.ScaleValue(100);
    mButton.Align := alRight;
    mButton.AlignWithMargins := True;
    mButton.Margins.SetBounds(8, 8, 8, 8);
    mButton.Caption := TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.ReportClose);
    mButton.Cancel := True;
    mButton.Default := True;
    mButton.ModalResult := mrOk;
    mMemo := TMemo.Create(mViewer);
    mMemo.Parent := mViewer;
    mMemo.Align := alClient;
    mMemo.AlignWithMargins := True;
    mMemo.ReadOnly := True;
    mMemo.ScrollBars := ssBoth;
    mMemo.WordWrap := False;
    mMemo.Font.Name := 'Consolas';
    mMemo.Font.Size := 9;
    mMemo.Lines.Text := AText;
    mViewer.ShowModal;
  finally
    mViewer.Free;
  end;
end;

function NewLabel(AOwner: TComponent; AParent: TWinControl; const ACaption: string): TLabel;
begin
  Result := TLabel.Create(AOwner);
  Result.Parent := AParent;
  Result.Align := alTop;
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(TAtlasReportDialog.cGap, TAtlasReportDialog.cGap, TAtlasReportDialog.cGap, 2);
  Result.ShowAccelChar := False;
  Result.Caption := ACaption;
end;

/// <summary>Beschriftung im Fuß: ohne Ausrichtung und feste Größe, die Lage setzt FootResize.</summary>
function NewFootLabel(AOwner: TComponent; AParent: TWinControl): TLabel;
begin
  Result := NewLabel(AOwner, AParent, '');
  Result.Align := alNone;
  Result.AutoSize := False;
end;

function NewButton(AOwner: TComponent; AParent: TWinControl; const ACaption: string; AWidth: Integer;
  const AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(AOwner);
  Result.Parent := AParent;
  Result.SetBounds(0, 8, AWidth, 28);
  Result.Caption := ACaption;
  Result.OnClick := AClick;
end;

{ TAtlasReportDialog }

constructor TAtlasReportDialog.CreateDialog(AOwner: TComponent; const AInput: TAtlasPackageInput; const AFolder,
  AReportUrl: string; const AActions: TAtlasReportActions);
begin
  inherited CreateNew(AOwner);
  FInput := AInput;
  FActions := AActions;
  FFolder := AFolder;
  FReportUrl := AReportUrl;
  FLastDataAvailable := (AInput.LastDataFile <> '') and FileExists(AInput.LastDataFile);
  Caption := TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.ReportTitle);
  BorderStyle := bsSizeable;
  Position := poMainFormCenter;
  Width := ScaleValue(760);
  Height := ScaleValue(660);
  CreateHead;
  CreateChecks;
  NewLabel(Self, Self, TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.ReportPreview)).Top :=
    ScaleValue(cPreviewTop);
  CreateFoot;
  CreateList;
  ShowFolder;
  Reload;
end;

procedure TAtlasReportDialog.CreateHead;
var
  mHeading: TLabel;
begin
  // Von oben nach unten gestapelt: alTop ordnet nach Top, daher wachsende Werte.
  mHeading := NewLabel(Self, Self, TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.ReportHint));
  mHeading.WordWrap := True;
  mHeading.Top := 0;
  NewLabel(Self, Self, TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.ReportDescription)).Top := ScaleValue(100);
  FParts.Description := TMemo.Create(Self);
  FParts.Description.Parent := Self;
  FParts.Description.Align := alTop;
  FParts.Description.AlignWithMargins := True;
  FParts.Description.Margins.SetBounds(cGap, 0, cGap, cGap);
  FParts.Description.Height := FParts.Description.ScaleValue(72);
  FParts.Description.ScrollBars := ssVertical;
  FParts.Description.Top := FParts.Description.ScaleValue(200);
  NewLabel(Self, Self, TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.ReportParts)).Top := ScaleValue(cPartsTop);
end;

procedure TAtlasReportDialog.CreateChecks;
var
  mPart: TAtlasPackagePart;
  mCheck: TCheckBox;
begin
  for mPart := Low(TAtlasPackagePart) to High(TAtlasPackagePart) do
  begin
    mCheck := TCheckBox.Create(Self);
    mCheck.Parent := Self;
    mCheck.Align := alTop;
    mCheck.AlignWithMargins := True;
    mCheck.Margins.SetBounds(cGap * 2, 0, cGap, 2);
    mCheck.Top := mCheck.ScaleValue(400) + Ord(mPart);
    // Vor OnClick setzen: Ein Wechsel von Checked löst OnClick aus, die Vorschau gibt es noch nicht.
    // Optional (#479): die letzten Diagnosedaten sind nicht vorausgewählt.
    mCheck.Checked := mPart <> TAtlasPackagePart.LastData;
    mCheck.OnClick := PartClick;
    FParts.Checks[mPart] := mCheck;
  end;
  FParts.Checks[TAtlasPackagePart.Logs].Caption := TAtlasDiagnosticsStrings.Text(
    TAtlasDiagnosticsTextId.ReportPartLogs);
  FParts.Checks[TAtlasPackagePart.Versions].Caption := TAtlasDiagnosticsStrings.Text(
    TAtlasDiagnosticsTextId.ReportPartVersions);
  FParts.Checks[TAtlasPackagePart.Settings].Caption := TAtlasDiagnosticsStrings.Text(
    TAtlasDiagnosticsTextId.ReportPartSettings);
  // Optional (#479): nur mit vorhandenen Daten.
  FParts.Checks[TAtlasPackagePart.LastData].Enabled := FLastDataAvailable;
  if FLastDataAvailable then
  begin
    FParts.Checks[TAtlasPackagePart.LastData].Caption := TAtlasDiagnosticsStrings.Text(
      TAtlasDiagnosticsTextId.ReportPartLastData);
  end
  else
  begin
    FParts.Checks[TAtlasPackagePart.LastData].Caption := TAtlasDiagnosticsStrings.Text(
      TAtlasDiagnosticsTextId.ReportPartLastDataMissing);
  end;
end;

procedure TAtlasReportDialog.CreateFoot;
var
  mFoot: TPanel;
begin
  // Fuß mit festen Zeilen: Summe und „Ansehen“, Ordner, Status, Knöpfe.
  // Die Lage nach der Breite setzt FootResize (die Breite steht erst nach dem Ausrichten fest).
  mFoot := TPanel.Create(Self);
  mFoot.Parent := Self;
  mFoot.Align := alBottom;
  mFoot.Height := mFoot.ScaleValue(136);
  mFoot.BevelOuter := bvNone;
  mFoot.ShowCaption := False;
  FParts.Summary := NewFootLabel(Self, mFoot);
  FParts.ViewButton := NewButton(Self, mFoot, TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.ReportView),
    cViewButtonWidth,
    ViewClick);
  FParts.FolderLabel := NewFootLabel(Self, mFoot);
  FParts.FolderLabel.EllipsisPosition := epPathEllipsis;
  FParts.FolderButton := NewButton(Self, mFoot,
    TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.ReportFolderChange), cFolderButtonWidth,
    FolderClick);
  FParts.Status := NewFootLabel(Self, mFoot);
  FParts.ZipButton := NewButton(Self, mFoot, TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.ReportCreateZip),
    cZipButtonWidth, ZipClick);
  FParts.IssueButton := NewButton(Self, mFoot, TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.ReportOpenIssue),
    cIssueButtonWidth, IssueClick);
  FParts.CloseButton := NewButton(Self, mFoot, TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.ReportClose), 100,
    nil);
  FParts.CloseButton.Cancel := True;
  FParts.CloseButton.ModalResult := mrCancel;
  mFoot.OnResize := FootResize;
  FootResize(mFoot);
end;

procedure TAtlasReportDialog.CreateList;
var
  mColumn: TListColumn;
  mList: TListView;
begin
  mList := TListView.Create(Self);
  mList.Parent := Self;
  mList.Align := alClient;
  mList.AlignWithMargins := True;
  mList.Margins.SetBounds(cGap, 0, cGap, 0);
  mList.ViewStyle := vsReport;
  mList.ReadOnly := True;
  mList.RowSelect := True;
  mList.HideSelection := False;
  mColumn := mList.Columns.Add;
  mColumn.Caption := TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.ReportColumnFile);
  mColumn.Width := mList.ScaleValue(480);
  mColumn := mList.Columns.Add;
  mColumn.Caption := TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.ReportColumnSize);
  mColumn.Width := mList.ScaleValue(120);
  mColumn.Alignment := taRightJustify;
  // Doppelklick wie „Ansehen“.
  mList.OnDblClick := ViewClick;
  mList.OnSelectItem := ListSelectItem;
  FParts.List := mList;
end;

function TAtlasReportDialog.Check(APart: TAtlasPackagePart): TCheckBox;
begin
  Result := FParts.Checks[APart];
end;

function TAtlasReportDialog.Parts: TAtlasPackageParts;
var
  mPart: TAtlasPackagePart;
begin
  Result := [];
  for mPart := Low(TAtlasPackagePart) to High(TAtlasPackagePart) do
  begin
    if FParts.Checks[mPart].Checked and FParts.Checks[mPart].Enabled then
    begin
      Include(Result, mPart);
    end;
  end;
end;

class function TAtlasReportDialog.SizeText(ABytes: Int64): string;
begin
  if ABytes < 1024 then
  begin
    Result := TAtlasDiagnosticsStrings.Fmt(TAtlasDiagnosticsTextId.ReportSizeBytes, [ABytes]);
  end
  else if ABytes < 1024 * 1024 then
  begin
    Result := TAtlasDiagnosticsStrings.Fmt(TAtlasDiagnosticsTextId.ReportSizeKb, [FormatFloat('0.0', ABytes / cBytesPerKb,
      FormatSettings)]);
  end
  else
  begin
    Result := TAtlasDiagnosticsStrings.Fmt(TAtlasDiagnosticsTextId.ReportSizeMb, [FormatFloat('0.0',
      ABytes / cBytesPerMb, FormatSettings)]);
  end;
end;

procedure TAtlasReportDialog.Reload;
var
  mItem: TAtlasPackageFile;
  mRow: TListItem;
begin
  if FParts.List = nil then
  begin
    Exit;
  end;
  FFiles := TAtlasDiagnosticPackage.Build(FInput, Parts);
  // Eine vorher angelegte ZIP passt nicht mehr zur Auswahl.
  FZipFile := '';
  FParts.Status.Caption := '';
  FParts.List.Items.BeginUpdate;
  try
    FParts.List.Items.Clear;
    for mItem in FFiles do
    begin
      mRow := FParts.List.Items.Add;
      mRow.Caption := mItem.Name;
      mRow.SubItems.Add(SizeText(mItem.Size));
    end;
  finally
    FParts.List.Items.EndUpdate;
  end;
  if Length(FFiles) = 0 then
  begin
    FParts.Summary.Caption := TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.ReportEmpty);
  end
  else
  begin
    FParts.Summary.Caption := TAtlasDiagnosticsStrings.Fmt(TAtlasDiagnosticsTextId.ReportSummary, [Length(FFiles),
      SizeText(TAtlasDiagnosticPackage.TotalSize(FFiles))]);
  end;
  FParts.ZipButton.Enabled := Length(FFiles) > 0;
  FParts.ViewButton.Enabled := FParts.List.Selected <> nil;
end;

procedure TAtlasReportDialog.ShowFolder;
begin
  FParts.FolderLabel.Caption := TAtlasDiagnosticsStrings.Fmt(TAtlasDiagnosticsTextId.ReportFolder, [FFolder]);
end;

procedure TAtlasReportDialog.PartClick(Sender: TObject);
begin
  Reload;
end;

procedure TAtlasReportDialog.FootResize(Sender: TObject);
var
  mRight: Integer;
begin
  mRight := (Sender as TPanel).ClientWidth - cGap;
  FParts.ViewButton.SetBounds(mRight - 110, 4, 110, 28);
  FParts.Summary.SetBounds(cGap, 10, Max(0, FParts.ViewButton.Left - 2 * cGap), 17);
  FParts.FolderButton.SetBounds(mRight - 110, 38, 110, 28);
  FParts.FolderLabel.SetBounds(cGap, 44, Max(0, FParts.FolderButton.Left - 2 * cGap), 17);
  FParts.Status.SetBounds(cGap, 74, Max(0, mRight - cGap), 17);
  FParts.ZipButton.SetBounds(cGap, 98, 130, 28);
  FParts.IssueButton.SetBounds(2 * cGap + 130, 98, 160, 28);
  FParts.CloseButton.SetBounds(mRight - 100, 98, 100, 28);
end;

procedure TAtlasReportDialog.ListSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  FParts.ViewButton.Enabled := FParts.List.Selected <> nil;
end;

function TAtlasReportDialog.ViewFile(AIndex: Integer): string;
begin
  Result := '';
  if (AIndex < 0) or (AIndex >= Length(FFiles)) then
  begin
    Exit;
  end;
  Result := FFiles[AIndex].Text;
  if Assigned(FActions.ShowText) then
  begin
    FActions.ShowText(FFiles[AIndex].Name, Result);
  end
  else
  begin
    ShowTextWindow(FFiles[AIndex].Name, Result);
  end;
end;

procedure TAtlasReportDialog.ViewClick(Sender: TObject);
begin
  if FParts.List.Selected <> nil then
  begin
    ViewFile(FParts.List.Selected.Index);
  end;
end;

procedure TAtlasReportDialog.FolderClick(Sender: TObject);
var
  mPicked: string;
  mDialog: TFileOpenDialog;
begin
  mPicked := '';
  if Assigned(FActions.PickFolder) then
  begin
    mPicked := FActions.PickFolder(FFolder);
  end
  else
  begin
    mDialog := TFileOpenDialog.Create(Self);
    try
      mDialog.Options := mDialog.Options + [fdoPickFolders, fdoPathMustExist];
      mDialog.DefaultFolder := FFolder;
      if mDialog.Execute then
      begin
        mPicked := mDialog.FileName;
      end;
    finally
      mDialog.Free;
    end;
  end;
  if mPicked = '' then
  begin
    Exit;
  end;
  FFolder := mPicked;
  ShowFolder;
end;

function TAtlasReportDialog.CreateZip: Boolean;
var
  mTarget: string;
begin
  Result := False;
  if Length(FFiles) = 0 then
  begin
    Exit;
  end;
  try
    ForceDirectories(FFolder);
    mTarget := TAtlasDiagnosticPackage.ZipTarget(FFolder, Now,
      function(AFileName: string): Boolean
      begin
        Result := FileExists(AFileName);
      end);
    TAtlasDiagnosticPackage.WriteZip(FFiles, mTarget);
  except
    on E: Exception do
    begin
      FParts.Status.Caption := TAtlasDiagnosticsStrings.Fmt(TAtlasDiagnosticsTextId.ReportZipFailed, [E.Message]);
      Exit;
    end;
  end;
  FZipFile := mTarget;
  FParts.Status.Caption := TAtlasDiagnosticsStrings.Fmt(TAtlasDiagnosticsTextId.ReportZipDone,
    [ExtractFileName(mTarget)]);
  if Assigned(FActions.ShowFile) then
  begin
    FActions.ShowFile(mTarget);
  end;
  Result := True;
end;

function TAtlasReportDialog.IssueText: string;
begin
  Result := TAtlasDiagnosticPackage.IssueTemplate(FParts.Description.Text, FInput, Parts, ExtractFileName(FZipFile),
    TAtlasStrings.Language = TAtlasLanguage.English);
end;

procedure TAtlasReportDialog.OpenIssue;
var
  mUrl: string;
begin
  mUrl := FReportUrl;
  // Nur Webadressen an den Browser; sonst die Issue-Seite des Atlas-Repositorys.
  if not TAtlasDiagnosticPackage.IsWebUrl(mUrl) then
  begin
    mUrl := TAtlasPluginSettings.cDefaultHelpReportUrl;
  end;
  if Assigned(FActions.CopyText) then
  begin
    FActions.CopyText(IssueText);
  end;
  if Assigned(FActions.OpenUrl) then
  begin
    FActions.OpenUrl(mUrl);
  end;
  FParts.Status.Caption := TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.ReportIssueDone);
end;

procedure TAtlasReportDialog.ZipClick(Sender: TObject);
begin
  CreateZip;
end;

procedure TAtlasReportDialog.IssueClick(Sender: TObject);
begin
  OpenIssue;
end;

class procedure TAtlasReportDialog.Execute(const AInput: TAtlasPackageInput; const AFolder, AReportUrl: string;
  const AActions: TAtlasReportActions);
var
  mDialog: TAtlasReportDialog;
begin
  mDialog := TAtlasReportDialog.CreateDialog(nil, AInput, AFolder, AReportUrl, AActions);
  try
    mDialog.ShowModal;
  finally
    mDialog.Free;
  end;
end;

end.
