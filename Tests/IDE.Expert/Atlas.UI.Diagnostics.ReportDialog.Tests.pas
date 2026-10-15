unit Atlas.UI.Diagnostics.ReportDialog.Tests;

// Dialog „Problem melden“ (#766): Die Vorschau folgt den Häkchen, die letzten
// Diagnosedaten nur mit Datei, jede Datei lässt sich ansehen, „ZIP anlegen“
// schreibt Atlas-Diagnose-<Datum>.zip in den Ordner und zeigt sie,
// „Issue-Seite öffnen“ legt die Vorlage in die Zwischenablage und öffnet nur
// eine Webadresse; Größenangaben.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasReportDialogTests = class
  private
    FFolder: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure PreviewFollowsChecks;
    [Test]
    procedure LastDataNeedsFile;
    [Test]
    procedure ViewFileShowsContent;
    [Test]
    procedure CreateZipWritesIntoFolder;
    [Test]
    procedure OpenIssueCopiesTemplateAndOpensWebAddress;
    [Test]
    procedure SizeTextUsesUnits;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Diagnostics.Package,
  Atlas.UI.Strings,
  Atlas.UI.Diagnostics.ReportDialog;

const
  User = 'mmuster';

type
  /// <summary>Merkt sich, was der Dialog an Explorer, Zwischenablage, Browser und Anzeige gibt.</summary>
  TReportLog = class
  public
    Shown: TArray<string>;
    Copied: TArray<string>;
    Opened: TArray<string>;
    Viewed: TArray<string>;
    function Actions: TAtlasReportActions;
  end;

function TReportLog.Actions: TAtlasReportActions;
begin
  Result := Default(TAtlasReportActions);
  Result.ShowFile :=
    procedure(AFileName: string)
    begin
      Shown := Shown + [AFileName];
    end;
  Result.CopyText :=
    procedure(AText: string)
    begin
      Copied := Copied + [AText];
    end;
  Result.OpenUrl :=
    procedure(AUrl: string)
    begin
      Opened := Opened + [AUrl];
    end;
  Result.PickFolder :=
    function(AFolder: string): string
    begin
      Result := '';
    end;
  Result.ShowText :=
    procedure(AName, AText: string)
    begin
      Viewed := Viewed + [AName];
    end;
end;

function Input(const AFolder: string): TAtlasPackageInput;
begin
  Result := Default(TAtlasPackageInput);
  Result.AtlasVersion := '0.1.0';
  Result.IdeVersion := 'Delphi 13 (37.0)';
  Result.WindowsVersion := 'Windows 11';
  Result.Platform := 'Win32';
  Result.PluginLog := TPath.Combine(AFolder, 'atlas.log');
  Result.ServerLogs := [TPath.Combine(AFolder, 'diag-20261015-4711.log')];
  Result.SettingsJson := '{"ServerPath": "C:\\Users\\' + User + '\\Atlas.exe", "VisibleRows": 10}';
  Result.LastDataFile := TPath.Combine(AFolder, 'atlas-diagnosemodus.txt');
  Result.Roots := [];
  Result.Identity := [User];
  Result.Created := EncodeDate(2026, 10, 15);
end;

{ TAtlasReportDialogTests }

procedure TAtlasReportDialogTests.Setup;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'AtlasReport' + IntToStr(Random(1000000)));
  ForceDirectories(FFolder);
  TFile.WriteAllText(TPath.Combine(FFolder, 'atlas.log'), 'Start bei C:\Users\' + User + '\Atlas' + sLineBreak,
    TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(FFolder, 'diag-20261015-4711.log'), '{"m":"hover","ms":12}' + sLineBreak,
    TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(FFolder, 'atlas-diagnosemodus.txt'), '# Diagnosemodus' + sLineBreak,
    TEncoding.UTF8);
end;

procedure TAtlasReportDialogTests.TearDown;
begin
  if TDirectory.Exists(FFolder) then
    TDirectory.Delete(FFolder, True);
end;

procedure TAtlasReportDialogTests.PreviewFollowsChecks;
var
  Log: TReportLog;
  Dialog: TAtlasReportDialog;
begin
  Log := TReportLog.Create;
  try
    Dialog := TAtlasReportDialog.CreateDialog(nil, Input(FFolder), FFolder,
      TAtlasPluginSettings.DefaultHelpReportUrl, Log.Actions);
    try
      // Vorgabe: Logs, Versionen, Einstellungen; die Diagnosedaten nur auf Wunsch.
      Assert.IsTrue(Dialog.Check(TAtlasPackagePart.Logs).Checked);
      Assert.IsTrue(Dialog.Check(TAtlasPackagePart.Versions).Checked);
      Assert.IsTrue(Dialog.Check(TAtlasPackagePart.Settings).Checked);
      Assert.IsFalse(Dialog.Check(TAtlasPackagePart.LastData).Checked);
      Assert.IsTrue(Dialog.Check(TAtlasPackagePart.LastData).Enabled, 'Datei vorhanden');
      Assert.AreEqual(4, Integer(Length(Dialog.Files)));
      Assert.AreEqual(4, Dialog.List.Items.Count, 'jede Datei in der Vorschau');
      Assert.AreEqual(TAtlasDiagnosticPackage.InfoFileName, Dialog.List.Items[0].Caption);
      Assert.AreEqual(TAtlasReportDialog.SizeText(Dialog.Files[0].Size), Dialog.List.Items[0].SubItems[0]);
      Assert.IsTrue(Dialog.ZipButton.Enabled);
      Assert.AreNotEqual(TAtlasStrings.Text(TAtlasTextId.ReportEmpty), Dialog.SummaryLabel.Caption);
      // Ohne Logs: nur Info und Einstellungen.
      Dialog.Check(TAtlasPackagePart.Logs).Checked := False;
      Dialog.Refresh;
      Assert.AreEqual(2, Dialog.List.Items.Count);
      Assert.AreEqual(TAtlasDiagnosticPackage.SettingsFileName, Dialog.List.Items[1].Caption);
      // Mit den letzten Diagnosedaten.
      Dialog.Check(TAtlasPackagePart.LastData).Checked := True;
      Dialog.Refresh;
      Assert.AreEqual(3, Dialog.List.Items.Count);
      Assert.AreEqual(TAtlasDiagnosticPackage.LastDataFileName, Dialog.List.Items[2].Caption);
      // Nichts gewählt: nichts anzulegen.
      Dialog.Check(TAtlasPackagePart.Versions).Checked := False;
      Dialog.Check(TAtlasPackagePart.Settings).Checked := False;
      Dialog.Check(TAtlasPackagePart.LastData).Checked := False;
      Dialog.Refresh;
      Assert.AreEqual(0, Dialog.List.Items.Count);
      Assert.IsFalse(Dialog.ZipButton.Enabled);
      Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.ReportEmpty), Dialog.SummaryLabel.Caption);
      Assert.IsFalse(Dialog.CreateZip, 'leeres Paket wird nicht angelegt');
    finally
      Dialog.Free;
    end;
  finally
    Log.Free;
  end;
end;

procedure TAtlasReportDialogTests.LastDataNeedsFile;
var
  Log: TReportLog;
  Dialog: TAtlasReportDialog;
  Data: TAtlasPackageInput;
begin
  Log := TReportLog.Create;
  try
    Data := Input(FFolder);
    Data.LastDataFile := TPath.Combine(FFolder, 'fehlt.txt');
    Dialog := TAtlasReportDialog.CreateDialog(nil, Data, FFolder, TAtlasPluginSettings.DefaultHelpReportUrl,
      Log.Actions);
    try
      Assert.IsFalse(Dialog.Check(TAtlasPackagePart.LastData).Enabled, 'ohne Diagnosedaten ausgegraut');
      Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.ReportPartLastDataMissing),
        Dialog.Check(TAtlasPackagePart.LastData).Caption);
      Dialog.Check(TAtlasPackagePart.LastData).Checked := True;
      Dialog.Refresh;
      Assert.IsFalse(TAtlasPackagePart.LastData in Dialog.Parts, 'ausgegraut zählt nicht');
      Assert.AreEqual(4, Integer(Length(Dialog.Files)));
    finally
      Dialog.Free;
    end;
  finally
    Log.Free;
  end;
end;

procedure TAtlasReportDialogTests.ViewFileShowsContent;
var
  Log: TReportLog;
  Dialog: TAtlasReportDialog;
  Index: Integer;
  Text: string;
begin
  Log := TReportLog.Create;
  try
    Dialog := TAtlasReportDialog.CreateDialog(nil, Input(FFolder), FFolder,
      TAtlasPluginSettings.DefaultHelpReportUrl, Log.Actions);
    try
      for Index := 0 to High(Dialog.Files) do
      begin
        Text := Dialog.ViewFile(Index);
        Assert.AreEqual(Dialog.Files[Index].Text, Text);
        Assert.IsFalse(ContainsText(Text, User), 'angesehen wird, was ins ZIP kommt: anonym');
      end;
      Assert.AreEqual(Integer(Length(Dialog.Files)), Integer(Length(Log.Viewed)), 'jede Datei lässt sich ansehen');
      Assert.AreEqual(Dialog.Files[0].Name, Log.Viewed[0]);
      Assert.AreEqual('', Dialog.ViewFile(99));
      Assert.AreEqual(Integer(Length(Dialog.Files)), Integer(Length(Log.Viewed)), 'außerhalb: nichts');
    finally
      Dialog.Free;
    end;
  finally
    Log.Free;
  end;
end;

procedure TAtlasReportDialogTests.CreateZipWritesIntoFolder;
var
  Log: TReportLog;
  Dialog: TAtlasReportDialog;
  Target, First: string;
begin
  Log := TReportLog.Create;
  try
    Target := TPath.Combine(FFolder, 'Ablage');
    Dialog := TAtlasReportDialog.CreateDialog(nil, Input(FFolder), Target,
      TAtlasPluginSettings.DefaultHelpReportUrl, Log.Actions);
    try
      Assert.AreEqual('', Dialog.ZipFile);
      Assert.IsTrue(Dialog.CreateZip);
      First := Dialog.ZipFile;
      Assert.IsTrue(FileExists(First), 'Ordner wird angelegt');
      Assert.AreEqual(IncludeTrailingPathDelimiter(Target), ExtractFilePath(First));
      Assert.IsTrue(StartsText(TAtlasDiagnosticPackage.ZipPrefix, ExtractFileName(First)));
      Assert.IsTrue(EndsText('.zip', First));
      Assert.AreEqual(1, Integer(Length(Log.Shown)), 'im Explorer zeigen');
      Assert.AreEqual(First, Log.Shown[0]);
      Assert.IsTrue(ContainsText(Dialog.StatusLabel.Caption, ExtractFileName(First)));
      Assert.AreEqual(0, Integer(Length(Log.Opened)), 'kein Browser');
      Assert.AreEqual(0, Integer(Length(Log.Copied)), 'keine Zwischenablage');
      // Zweites Paket überschreibt das erste nicht.
      Assert.IsTrue(Dialog.CreateZip);
      Assert.AreNotEqual(First, Dialog.ZipFile);
      Assert.IsTrue(FileExists(First));
      // Neue Auswahl: Die angelegte ZIP passt nicht mehr.
      Dialog.Check(TAtlasPackagePart.Settings).Checked := False;
      Dialog.Refresh;
      Assert.AreEqual('', Dialog.ZipFile);
    finally
      Dialog.Free;
    end;
  finally
    Log.Free;
  end;
end;

procedure TAtlasReportDialogTests.OpenIssueCopiesTemplateAndOpensWebAddress;
var
  Log: TReportLog;
  Dialog: TAtlasReportDialog;
begin
  Log := TReportLog.Create;
  try
    Dialog := TAtlasReportDialog.CreateDialog(nil, Input(FFolder), FFolder, 'https://example.org/issues/new',
      Log.Actions);
    try
      Dialog.Description.Text := 'Absturz beim Öffnen von C:\Users\' + User + '\Projekt.dproj';
      Assert.IsTrue(Dialog.CreateZip);
      Dialog.OpenIssue;
      Assert.AreEqual(1, Integer(Length(Log.Copied)));
      Assert.IsTrue(ContainsText(Log.Copied[0], 'Absturz beim Öffnen'), 'Beschreibung');
      Assert.IsFalse(ContainsText(Log.Copied[0], User), 'anonym');
      Assert.IsTrue(ContainsText(Log.Copied[0], 'Delphi 13 (37.0)'), 'Versionen');
      Assert.IsTrue(ContainsText(Log.Copied[0], ExtractFileName(Dialog.ZipFile)), 'Hinweis auf das ZIP');
      Assert.AreEqual(Dialog.IssueText, Log.Copied[0]);
      Assert.AreEqual(1, Integer(Length(Log.Opened)));
      Assert.AreEqual('https://example.org/issues/new', Log.Opened[0]);
      Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.ReportIssueDone), Dialog.StatusLabel.Caption);
    finally
      Dialog.Free;
    end;
    // Keine Webadresse: die Issue-Seite des Atlas-Repositorys statt eines Programms.
    Dialog := TAtlasReportDialog.CreateDialog(nil, Input(FFolder), FFolder, 'C:\Windows\System32\cmd.exe',
      Log.Actions);
    try
      Dialog.Check(TAtlasPackagePart.Versions).Checked := False;
      Dialog.Refresh;
      Dialog.OpenIssue;
      Assert.AreEqual(2, Integer(Length(Log.Opened)));
      Assert.AreEqual(TAtlasPluginSettings.DefaultHelpReportUrl, Log.Opened[1]);
      Assert.IsFalse(ContainsText(Log.Copied[1], 'Delphi 13 (37.0)'), 'Versionen nur mit Häkchen');
    finally
      Dialog.Free;
    end;
  finally
    Log.Free;
  end;
end;

procedure TAtlasReportDialogTests.SizeTextUsesUnits;
var
  Saved: TAtlasLanguage;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Assert.AreEqual('812 Bytes', TAtlasReportDialog.SizeText(812));
    Assert.IsTrue(EndsText(' KB', TAtlasReportDialog.SizeText(4300)));
    Assert.IsTrue(StartsText('4', TAtlasReportDialog.SizeText(4300)));
    Assert.IsTrue(EndsText(' MB', TAtlasReportDialog.SizeText(1363149)));
    Assert.IsTrue(StartsText('1', TAtlasReportDialog.SizeText(1363149)));
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.AreEqual('812 bytes', TAtlasReportDialog.SizeText(812));
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasReportDialogTests);

end.
