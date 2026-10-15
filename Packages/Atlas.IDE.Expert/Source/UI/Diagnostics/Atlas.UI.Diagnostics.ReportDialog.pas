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
    Gap = 8;
  private
    FInput: TAtlasPackageInput;
    FActions: TAtlasReportActions;
    FFolder: string;
    FReportUrl: string;
    FFiles: TAtlasPackageFiles;
    FZipFile: string;
    FLastDataAvailable: Boolean;
    FDescription: TMemo;
    FChecks: array[TAtlasPackagePart] of TCheckBox;
    FList: TListView;
    FSummary: TLabel;
    FFolderLabel: TLabel;
    FStatus: TLabel;
    FViewButton: TButton;
    FFolderButton: TButton;
    FZipButton: TButton;
    FIssueButton: TButton;
    FCloseButton: TButton;
    function AddLabel(AParent: TWinControl; const ACaption: string): TLabel;
    function AddButton(AParent: TWinControl; const ACaption: string; AWidth: Integer;
      const AClick: TNotifyEvent): TButton;
    procedure PartClick(Sender: TObject);
    procedure FootResize(Sender: TObject);
    procedure ListDblClick(Sender: TObject);
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
    procedure Refresh;
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
    property Folder: string read FFolder;
    property ReportUrl: string read FReportUrl;
    property Description: TMemo read FDescription;
    property List: TListView read FList;
    property SummaryLabel: TLabel read FSummary;
    property StatusLabel: TLabel read FStatus;
    property ZipButton: TButton read FZipButton;
    property IssueButton: TButton read FIssueButton;
    property ViewButton: TButton read FViewButton;
  end;

implementation

uses
  System.Math,
  Vcl.Dialogs,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Strings;

/// <summary>Eingebautes Fenster für den Inhalt einer Datei.</summary>
procedure ShowTextWindow(const AName, AText: string);
var
  Viewer: TForm;
  Memo: TMemo;
  Bottom: TPanel;
  Button: TButton;
begin
  Viewer := TForm.CreateNew(nil);
  try
    Viewer.Caption := TAtlasStrings.Fmt(TAtlasTextId.ReportViewerTitle, [AName]);
    Viewer.BorderStyle := bsSizeable;
    Viewer.Position := poMainFormCenter;
    Viewer.Width := 900;
    Viewer.Height := 600;
    Bottom := TPanel.Create(Viewer);
    Bottom.Parent := Viewer;
    Bottom.Align := alBottom;
    Bottom.Height := 44;
    Bottom.BevelOuter := bvNone;
    Button := TButton.Create(Viewer);
    Button.Parent := Bottom;
    Button.Width := 100;
    Button.Align := alRight;
    Button.AlignWithMargins := True;
    Button.Margins.SetBounds(8, 8, 8, 8);
    Button.Caption := TAtlasStrings.Text(TAtlasTextId.ReportClose);
    Button.Cancel := True;
    Button.Default := True;
    Button.ModalResult := mrOk;
    Memo := TMemo.Create(Viewer);
    Memo.Parent := Viewer;
    Memo.Align := alClient;
    Memo.AlignWithMargins := True;
    Memo.ReadOnly := True;
    Memo.ScrollBars := ssBoth;
    Memo.WordWrap := False;
    Memo.Font.Name := 'Consolas';
    Memo.Font.Size := 9;
    Memo.Lines.Text := AText;
    Viewer.ShowModal;
  finally
    Viewer.Free;
  end;
end;

{ TAtlasReportDialog }

constructor TAtlasReportDialog.CreateDialog(AOwner: TComponent; const AInput: TAtlasPackageInput; const AFolder,
  AReportUrl: string; const AActions: TAtlasReportActions);
var
  Foot: TPanel;
  Part: TAtlasPackagePart;
  Heading: TLabel;
  Column: TListColumn;
begin
  inherited CreateNew(AOwner);
  FInput := AInput;
  FActions := AActions;
  FFolder := AFolder;
  FReportUrl := AReportUrl;
  FLastDataAvailable := (AInput.LastDataFile <> '') and FileExists(AInput.LastDataFile);
  Caption := TAtlasStrings.Text(TAtlasTextId.ReportTitle);
  BorderStyle := bsSizeable;
  Position := poMainFormCenter;
  Width := 760;
  Height := 660;

  // Von oben nach unten gestapelt: alTop ordnet nach Top, daher wachsende Werte.
  Heading := AddLabel(Self, TAtlasStrings.Text(TAtlasTextId.ReportHint));
  Heading.WordWrap := True;
  Heading.Top := 0;
  Heading := AddLabel(Self, TAtlasStrings.Text(TAtlasTextId.ReportDescription));
  Heading.Top := 100;
  FDescription := TMemo.Create(Self);
  FDescription.Parent := Self;
  FDescription.Align := alTop;
  FDescription.AlignWithMargins := True;
  FDescription.Margins.SetBounds(Gap, 0, Gap, Gap);
  FDescription.Height := 72;
  FDescription.ScrollBars := ssVertical;
  FDescription.Top := 200;
  Heading := AddLabel(Self, TAtlasStrings.Text(TAtlasTextId.ReportParts));
  Heading.Top := 300;
  for Part := Low(TAtlasPackagePart) to High(TAtlasPackagePart) do
  begin
    FChecks[Part] := TCheckBox.Create(Self);
    FChecks[Part].Parent := Self;
    FChecks[Part].Align := alTop;
    FChecks[Part].AlignWithMargins := True;
    FChecks[Part].Margins.SetBounds(Gap * 2, 0, Gap, 2);
    FChecks[Part].Top := 400 + Ord(Part);
    // Vor OnClick setzen: Ein Wechsel von Checked löst OnClick aus, die Vorschau gibt es noch nicht.
    // Optional (#479): die letzten Diagnosedaten sind nicht vorausgewählt.
    FChecks[Part].Checked := Part <> TAtlasPackagePart.LastData;
    FChecks[Part].OnClick := PartClick;
  end;
  FChecks[TAtlasPackagePart.Logs].Caption := TAtlasStrings.Text(TAtlasTextId.ReportPartLogs);
  FChecks[TAtlasPackagePart.Versions].Caption := TAtlasStrings.Text(TAtlasTextId.ReportPartVersions);
  FChecks[TAtlasPackagePart.Settings].Caption := TAtlasStrings.Text(TAtlasTextId.ReportPartSettings);
  // Optional (#479): nur mit vorhandenen Daten.
  FChecks[TAtlasPackagePart.LastData].Enabled := FLastDataAvailable;
  if FLastDataAvailable then
    FChecks[TAtlasPackagePart.LastData].Caption := TAtlasStrings.Text(TAtlasTextId.ReportPartLastData)
  else
    FChecks[TAtlasPackagePart.LastData].Caption := TAtlasStrings.Text(TAtlasTextId.ReportPartLastDataMissing);
  Heading := AddLabel(Self, TAtlasStrings.Text(TAtlasTextId.ReportPreview));
  Heading.Top := 500;

  // Fuß mit festen Zeilen: Summe und „Ansehen“, Ordner, Status, Knöpfe.
  // Die Lage nach der Breite setzt FootResize (die Breite steht erst nach dem Ausrichten fest).
  Foot := TPanel.Create(Self);
  Foot.Parent := Self;
  Foot.Align := alBottom;
  Foot.Height := 136;
  Foot.BevelOuter := bvNone;
  Foot.ShowCaption := False;
  FSummary := AddLabel(Foot, '');
  FSummary.Align := alNone;
  FSummary.AutoSize := False;
  FViewButton := AddButton(Foot, TAtlasStrings.Text(TAtlasTextId.ReportView), 110, ViewClick);
  FFolderLabel := AddLabel(Foot, '');
  FFolderLabel.Align := alNone;
  FFolderLabel.AutoSize := False;
  FFolderLabel.EllipsisPosition := epPathEllipsis;
  FFolderButton := AddButton(Foot, TAtlasStrings.Text(TAtlasTextId.ReportFolderChange), 110, FolderClick);
  FStatus := AddLabel(Foot, '');
  FStatus.Align := alNone;
  FStatus.AutoSize := False;
  FZipButton := AddButton(Foot, TAtlasStrings.Text(TAtlasTextId.ReportCreateZip), 130, ZipClick);
  FIssueButton := AddButton(Foot, TAtlasStrings.Text(TAtlasTextId.ReportOpenIssue), 160, IssueClick);
  FCloseButton := AddButton(Foot, TAtlasStrings.Text(TAtlasTextId.ReportClose), 100, nil);
  FCloseButton.Cancel := True;
  FCloseButton.ModalResult := mrCancel;
  Foot.OnResize := FootResize;
  FootResize(Foot);

  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.AlignWithMargins := True;
  FList.Margins.SetBounds(Gap, 0, Gap, 0);
  FList.ViewStyle := vsReport;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  FList.HideSelection := False;
  Column := FList.Columns.Add;
  Column.Caption := TAtlasStrings.Text(TAtlasTextId.ReportColumnFile);
  Column.Width := 480;
  Column := FList.Columns.Add;
  Column.Caption := TAtlasStrings.Text(TAtlasTextId.ReportColumnSize);
  Column.Width := 120;
  Column.Alignment := taRightJustify;
  FList.OnDblClick := ListDblClick;
  FList.OnSelectItem := ListSelectItem;

  ShowFolder;
  Refresh;
end;

function TAtlasReportDialog.AddLabel(AParent: TWinControl; const ACaption: string): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := AParent;
  Result.Align := alTop;
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(Gap, Gap, Gap, 2);
  Result.ShowAccelChar := False;
  Result.Caption := ACaption;
end;

function TAtlasReportDialog.AddButton(AParent: TWinControl; const ACaption: string; AWidth: Integer;
  const AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(0, 8, AWidth, 28);
  Result.Caption := ACaption;
  Result.OnClick := AClick;
end;

function TAtlasReportDialog.Check(APart: TAtlasPackagePart): TCheckBox;
begin
  Result := FChecks[APart];
end;

function TAtlasReportDialog.Parts: TAtlasPackageParts;
var
  Part: TAtlasPackagePart;
begin
  Result := [];
  for Part := Low(TAtlasPackagePart) to High(TAtlasPackagePart) do
    if FChecks[Part].Checked and FChecks[Part].Enabled then
      Include(Result, Part);
end;

class function TAtlasReportDialog.SizeText(ABytes: Int64): string;
begin
  if ABytes < 1024 then
    Result := TAtlasStrings.Fmt(TAtlasTextId.ReportSizeBytes, [ABytes])
  else if ABytes < 1024 * 1024 then
    Result := TAtlasStrings.Fmt(TAtlasTextId.ReportSizeKb, [FormatFloat('0.0', ABytes / 1024)])
  else
    Result := TAtlasStrings.Fmt(TAtlasTextId.ReportSizeMb, [FormatFloat('0.0', ABytes / (1024 * 1024))]);
end;

procedure TAtlasReportDialog.Refresh;
var
  Item: TAtlasPackageFile;
  Row: TListItem;
begin
  if FList = nil then
    Exit;
  FFiles := TAtlasDiagnosticPackage.Build(FInput, Parts);
  // Eine vorher angelegte ZIP passt nicht mehr zur Auswahl.
  FZipFile := '';
  FStatus.Caption := '';
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for Item in FFiles do
    begin
      Row := FList.Items.Add;
      Row.Caption := Item.Name;
      Row.SubItems.Add(SizeText(Item.Size));
    end;
  finally
    FList.Items.EndUpdate;
  end;
  if Length(FFiles) = 0 then
    FSummary.Caption := TAtlasStrings.Text(TAtlasTextId.ReportEmpty)
  else
    FSummary.Caption := TAtlasStrings.Fmt(TAtlasTextId.ReportSummary, [Length(FFiles),
      SizeText(TAtlasDiagnosticPackage.TotalSize(FFiles))]);
  FZipButton.Enabled := Length(FFiles) > 0;
  FViewButton.Enabled := FList.Selected <> nil;
end;

procedure TAtlasReportDialog.ShowFolder;
begin
  FFolderLabel.Caption := TAtlasStrings.Fmt(TAtlasTextId.ReportFolder, [FFolder]);
end;

procedure TAtlasReportDialog.PartClick(Sender: TObject);
begin
  Refresh;
end;

procedure TAtlasReportDialog.FootResize(Sender: TObject);
var
  Right: Integer;
begin
  Right := (Sender as TPanel).ClientWidth - Gap;
  FViewButton.SetBounds(Right - 110, 4, 110, 28);
  FSummary.SetBounds(Gap, 10, Max(0, FViewButton.Left - 2 * Gap), 17);
  FFolderButton.SetBounds(Right - 110, 38, 110, 28);
  FFolderLabel.SetBounds(Gap, 44, Max(0, FFolderButton.Left - 2 * Gap), 17);
  FStatus.SetBounds(Gap, 74, Max(0, Right - Gap), 17);
  FZipButton.SetBounds(Gap, 98, 130, 28);
  FIssueButton.SetBounds(2 * Gap + 130, 98, 160, 28);
  FCloseButton.SetBounds(Right - 100, 98, 100, 28);
end;

procedure TAtlasReportDialog.ListSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  FViewButton.Enabled := FList.Selected <> nil;
end;

function TAtlasReportDialog.ViewFile(AIndex: Integer): string;
begin
  Result := '';
  if (AIndex < 0) or (AIndex >= Length(FFiles)) then
    Exit;
  Result := FFiles[AIndex].Text;
  if Assigned(FActions.ShowText) then
    FActions.ShowText(FFiles[AIndex].Name, Result)
  else
    ShowTextWindow(FFiles[AIndex].Name, Result);
end;

procedure TAtlasReportDialog.ListDblClick(Sender: TObject);
begin
  if FList.Selected <> nil then
    ViewFile(FList.Selected.Index);
end;

procedure TAtlasReportDialog.ViewClick(Sender: TObject);
begin
  if FList.Selected <> nil then
    ViewFile(FList.Selected.Index);
end;

procedure TAtlasReportDialog.FolderClick(Sender: TObject);
var
  Picked: string;
  Dialog: TFileOpenDialog;
begin
  Picked := '';
  if Assigned(FActions.PickFolder) then
    Picked := FActions.PickFolder(FFolder)
  else
  begin
    Dialog := TFileOpenDialog.Create(Self);
    try
      Dialog.Options := Dialog.Options + [fdoPickFolders, fdoPathMustExist];
      Dialog.DefaultFolder := FFolder;
      if Dialog.Execute then
        Picked := Dialog.FileName;
    finally
      Dialog.Free;
    end;
  end;
  if Picked = '' then
    Exit;
  FFolder := Picked;
  ShowFolder;
end;

function TAtlasReportDialog.CreateZip: Boolean;
var
  Target: string;
begin
  Result := False;
  if Length(FFiles) = 0 then
    Exit;
  try
    ForceDirectories(FFolder);
    Target := TAtlasDiagnosticPackage.ZipTarget(FFolder, Now,
      function(AFileName: string): Boolean
      begin
        Result := FileExists(AFileName);
      end);
    TAtlasDiagnosticPackage.WriteZip(FFiles, Target);
  except
    on E: Exception do
    begin
      FStatus.Caption := TAtlasStrings.Fmt(TAtlasTextId.ReportZipFailed, [E.Message]);
      Exit;
    end;
  end;
  FZipFile := Target;
  FStatus.Caption := TAtlasStrings.Fmt(TAtlasTextId.ReportZipDone, [ExtractFileName(Target)]);
  if Assigned(FActions.ShowFile) then
    FActions.ShowFile(Target);
  Result := True;
end;

function TAtlasReportDialog.IssueText: string;
begin
  Result := TAtlasDiagnosticPackage.IssueTemplate(FDescription.Text, FInput, Parts, ExtractFileName(FZipFile),
    TAtlasStrings.Language = TAtlasLanguage.English);
end;

procedure TAtlasReportDialog.OpenIssue;
var
  Url: string;
begin
  Url := FReportUrl;
  // Nur Webadressen an den Browser; sonst die Issue-Seite des Atlas-Repositorys.
  if not TAtlasDiagnosticPackage.IsWebUrl(Url) then
    Url := TAtlasPluginSettings.DefaultHelpReportUrl;
  if Assigned(FActions.CopyText) then
    FActions.CopyText(IssueText);
  if Assigned(FActions.OpenUrl) then
    FActions.OpenUrl(Url);
  FStatus.Caption := TAtlasStrings.Text(TAtlasTextId.ReportIssueDone);
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
  Dialog: TAtlasReportDialog;
begin
  Dialog := TAtlasReportDialog.CreateDialog(nil, AInput, AFolder, AReportUrl, AActions);
  try
    Dialog.ShowModal;
  finally
    Dialog.Free;
  end;
end;

end.
