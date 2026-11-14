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
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
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
  Atlas.UI.Diagnostics.Strings,
  Atlas.UI.Diagnostics.ReportDialog;

const
  cUser = 'mmuster';

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
  Result.SettingsJson := '{"ServerPath": "C:\\Users\\' + cUser + '\\Atlas.exe", "VisibleRows": 10}';
  Result.LastDataFile := TPath.Combine(AFolder, 'atlas-diagnosemodus.txt');
  Result.Roots := [];
  Result.Identity := [cUser];
  Result.Created := EncodeDate(2026, 10, 15);
end;

{ TAtlasReportDialogTests }

procedure TAtlasReportDialogTests.WarmUpFirstUse;
begin
  Setup;
  try
    PreviewFollowsChecks;
  finally
    TearDown;
  end;
end;

procedure TAtlasReportDialogTests.Setup;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'AtlasReport' + IntToStr(Random(1000000)));
  ForceDirectories(FFolder);
  TFile.WriteAllText(TPath.Combine(FFolder, 'atlas.log'), 'Start bei C:\Users\' + cUser + '\Atlas' + sLineBreak,
    TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(FFolder, 'diag-20261015-4711.log'), '{"m":"hover","ms":12}' + sLineBreak,
    TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(FFolder, 'atlas-diagnosemodus.txt'), '# Diagnosemodus' + sLineBreak,
    TEncoding.UTF8);
end;

procedure TAtlasReportDialogTests.TearDown;
begin
  if TDirectory.Exists(FFolder) then
  begin
    TDirectory.Delete(FFolder, True);
  end;
  // Der Leckmonitor misst den Saldo von Setup und TearDown.
  FFolder := '';
end;

procedure TAtlasReportDialogTests.PreviewFollowsChecks;
var
  mLog: TReportLog;
  mDialog: TAtlasReportDialog;
begin
  mLog := TReportLog.Create;
  try
    mDialog := TAtlasReportDialog.CreateDialog(nil, Input(FFolder), FFolder,
      TAtlasPluginSettings.cDefaultHelpReportUrl, mLog.Actions);
    try
      // Vorgabe: Logs, Versionen, Einstellungen; die Diagnosedaten nur auf Wunsch.
      Assert.IsTrue(mDialog.Check(TAtlasPackagePart.Logs).Checked);
      Assert.IsTrue(mDialog.Check(TAtlasPackagePart.Versions).Checked);
      Assert.IsTrue(mDialog.Check(TAtlasPackagePart.Settings).Checked);
      Assert.IsFalse(mDialog.Check(TAtlasPackagePart.LastData).Checked);
      Assert.IsTrue(mDialog.Check(TAtlasPackagePart.LastData).Enabled, 'Datei vorhanden');
      Assert.AreEqual(4, Integer(Length(mDialog.Files)));
      Assert.AreEqual(4, Integer(mDialog.List.Items.Count), 'jede Datei in der Vorschau');
      Assert.AreEqual(TAtlasDiagnosticPackage.cInfoFileName, mDialog.List.Items[0].Caption);
      Assert.AreEqual(TAtlasReportDialog.SizeText(mDialog.Files[0].Size), mDialog.List.Items[0].SubItems[0]);
      Assert.IsTrue(mDialog.ZipButton.Enabled);
      Assert.AreNotEqual(TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.ReportEmpty),
        mDialog.SummaryLabel.Caption);
      // Ohne Logs: nur Info und Einstellungen.
      mDialog.Check(TAtlasPackagePart.Logs).Checked := False;
      mDialog.Reload;
      Assert.AreEqual(2, Integer(mDialog.List.Items.Count));
      Assert.AreEqual(TAtlasDiagnosticPackage.cSettingsFileName, mDialog.List.Items[1].Caption);
      // Mit den letzten Diagnosedaten.
      mDialog.Check(TAtlasPackagePart.LastData).Checked := True;
      mDialog.Reload;
      Assert.AreEqual(3, Integer(mDialog.List.Items.Count));
      Assert.AreEqual(TAtlasDiagnosticPackage.cLastDataFileName, mDialog.List.Items[2].Caption);
      // Nichts gewählt: nichts anzulegen.
      mDialog.Check(TAtlasPackagePart.Versions).Checked := False;
      mDialog.Check(TAtlasPackagePart.Settings).Checked := False;
      mDialog.Check(TAtlasPackagePart.LastData).Checked := False;
      mDialog.Reload;
      Assert.AreEqual(0, Integer(mDialog.List.Items.Count));
      Assert.IsFalse(mDialog.ZipButton.Enabled);
      Assert.AreEqual(TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.ReportEmpty), mDialog.SummaryLabel.Caption);
      Assert.IsFalse(mDialog.CreateZip, 'leeres Paket wird nicht angelegt');
    finally
      mDialog.Free;
    end;
  finally
    mLog.Free;
  end;
end;

procedure TAtlasReportDialogTests.LastDataNeedsFile;
var
  mLog: TReportLog;
  mDialog: TAtlasReportDialog;
  mData: TAtlasPackageInput;
begin
  mLog := TReportLog.Create;
  try
    mData := Input(FFolder);
    mData.LastDataFile := TPath.Combine(FFolder, 'fehlt.txt');
    mDialog := TAtlasReportDialog.CreateDialog(nil, mData, FFolder, TAtlasPluginSettings.cDefaultHelpReportUrl,
      mLog.Actions);
    try
      Assert.IsFalse(mDialog.Check(TAtlasPackagePart.LastData).Enabled, 'ohne Diagnosedaten ausgegraut');
      Assert.AreEqual(TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.ReportPartLastDataMissing),
        mDialog.Check(TAtlasPackagePart.LastData).Caption);
      mDialog.Check(TAtlasPackagePart.LastData).Checked := True;
      mDialog.Reload;
      Assert.IsFalse(TAtlasPackagePart.LastData in mDialog.Parts, 'ausgegraut zählt nicht');
      Assert.AreEqual(4, Integer(Length(mDialog.Files)));
    finally
      mDialog.Free;
    end;
  finally
    mLog.Free;
  end;
end;

procedure TAtlasReportDialogTests.ViewFileShowsContent;
var
  mLog: TReportLog;
  mDialog: TAtlasReportDialog;
  mIndex: Integer;
  mText: string;
begin
  mLog := TReportLog.Create;
  try
    mDialog := TAtlasReportDialog.CreateDialog(nil, Input(FFolder), FFolder,
      TAtlasPluginSettings.cDefaultHelpReportUrl, mLog.Actions);
    try
      for mIndex := 0 to High(mDialog.Files) do
      begin
        mText := mDialog.ViewFile(mIndex);
        Assert.AreEqual(mDialog.Files[mIndex].Text, mText);
        Assert.IsFalse(ContainsText(mText, cUser), 'angesehen wird, was ins ZIP kommt: anonym');
      end;
      Assert.AreEqual(Integer(Length(mDialog.Files)), Integer(Length(mLog.Viewed)), 'jede Datei lässt sich ansehen');
      Assert.AreEqual(mDialog.Files[0].Name, mLog.Viewed[0]);
      Assert.AreEqual('', mDialog.ViewFile(99));
      Assert.AreEqual(Integer(Length(mDialog.Files)), Integer(Length(mLog.Viewed)), 'außerhalb: nichts');
    finally
      mDialog.Free;
    end;
  finally
    mLog.Free;
  end;
end;

procedure TAtlasReportDialogTests.CreateZipWritesIntoFolder;
var
  mLog: TReportLog;
  mDialog: TAtlasReportDialog;
  mTarget, mFirst: string;
begin
  mLog := TReportLog.Create;
  try
    mTarget := TPath.Combine(FFolder, 'Ablage');
    mDialog := TAtlasReportDialog.CreateDialog(nil, Input(FFolder), mTarget,
      TAtlasPluginSettings.cDefaultHelpReportUrl, mLog.Actions);
    try
      Assert.AreEqual('', mDialog.ZipFile);
      Assert.IsTrue(mDialog.CreateZip);
      mFirst := mDialog.ZipFile;
      Assert.IsTrue(FileExists(mFirst), 'Ordner wird angelegt');
      Assert.AreEqual(IncludeTrailingPathDelimiter(mTarget), ExtractFilePath(mFirst));
      Assert.IsTrue(StartsText(TAtlasDiagnosticPackage.cZipPrefix, ExtractFileName(mFirst)));
      Assert.IsTrue(EndsText('.zip', mFirst));
      Assert.AreEqual(1, Integer(Length(mLog.Shown)), 'im Explorer zeigen');
      Assert.AreEqual(mFirst, mLog.Shown[0]);
      Assert.IsTrue(ContainsText(mDialog.StatusLabel.Caption, ExtractFileName(mFirst)));
      Assert.AreEqual(0, Integer(Length(mLog.Opened)), 'kein Browser');
      Assert.AreEqual(0, Integer(Length(mLog.Copied)), 'keine Zwischenablage');
      // Zweites Paket überschreibt das erste nicht.
      Assert.IsTrue(mDialog.CreateZip);
      Assert.AreNotEqual(mFirst, mDialog.ZipFile);
      Assert.IsTrue(FileExists(mFirst));
      // Neue Auswahl: Die angelegte ZIP passt nicht mehr.
      mDialog.Check(TAtlasPackagePart.Settings).Checked := False;
      mDialog.Reload;
      Assert.AreEqual('', mDialog.ZipFile);
    finally
      mDialog.Free;
    end;
  finally
    mLog.Free;
  end;
end;

procedure TAtlasReportDialogTests.OpenIssueCopiesTemplateAndOpensWebAddress;
var
  mLog: TReportLog;
  mDialog: TAtlasReportDialog;
begin
  mLog := TReportLog.Create;
  try
    mDialog := TAtlasReportDialog.CreateDialog(nil, Input(FFolder), FFolder, 'https://example.org/issues/new',
      mLog.Actions);
    try
      mDialog.Description.Text := 'Absturz beim Öffnen von C:\Users\' + cUser + '\Projekt.dproj';
      Assert.IsTrue(mDialog.CreateZip);
      mDialog.OpenIssue;
      Assert.AreEqual(1, Integer(Length(mLog.Copied)));
      Assert.IsTrue(ContainsText(mLog.Copied[0], 'Absturz beim Öffnen'), 'Beschreibung');
      Assert.IsFalse(ContainsText(mLog.Copied[0], cUser), 'anonym');
      Assert.IsTrue(ContainsText(mLog.Copied[0], 'Delphi 13 (37.0)'), 'Versionen');
      Assert.IsTrue(ContainsText(mLog.Copied[0], ExtractFileName(mDialog.ZipFile)), 'Hinweis auf das ZIP');
      Assert.AreEqual(mDialog.IssueText, mLog.Copied[0]);
      Assert.AreEqual(1, Integer(Length(mLog.Opened)));
      Assert.AreEqual('https://example.org/issues/new', mLog.Opened[0]);
      Assert.AreEqual(TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.ReportIssueDone),
        mDialog.StatusLabel.Caption);
    finally
      mDialog.Free;
    end;
    // Keine Webadresse: die Issue-Seite des Atlas-Repositorys statt eines Programms.
    mDialog := TAtlasReportDialog.CreateDialog(nil, Input(FFolder), FFolder, 'C:\Windows\System32\cmd.exe',
      mLog.Actions);
    try
      mDialog.Check(TAtlasPackagePart.Versions).Checked := False;
      mDialog.Reload;
      mDialog.OpenIssue;
      Assert.AreEqual(2, Integer(Length(mLog.Opened)));
      Assert.AreEqual(TAtlasPluginSettings.cDefaultHelpReportUrl, mLog.Opened[1]);
      Assert.IsFalse(ContainsText(mLog.Copied[1], 'Delphi 13 (37.0)'), 'Versionen nur mit Häkchen');
    finally
      mDialog.Free;
    end;
  finally
    mLog.Free;
  end;
end;

procedure TAtlasReportDialogTests.SizeTextUsesUnits;
var
  mSaved: TAtlasLanguage;
begin
  mSaved := TAtlasStrings.Language;
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
    TAtlasStrings.Language := mSaved;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasReportDialogTests);

end.
