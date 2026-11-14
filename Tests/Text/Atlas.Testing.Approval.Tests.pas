unit Atlas.Testing.Approval.Tests;

// Test der mitgelieferten Unit Atlas.Testing.Approval (#1881): Vergleich mit
// angeglichenen Zeilenenden, erste abweichende Zeile, received-Datei bei neu und
// abweichend, Ordner aus atlas.json bzw. neben der Projektdatei.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasTestingApprovalTests = class
  private
    FFolder: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure LineEndsAreNoDifference;
    [Test]
    procedure FirstDifferenceIsALine;
    [Test]
    procedure NewThenApprovedThenDifferent;
    [Test]
    procedure VerifyFailsWithTheMessage;
    [Test]
    procedure FolderFromSettingsOrProject;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Atlas.Testing.Approval;

procedure WriteFile(const AFileName, AText: string);
begin
  ForceDirectories(ExtractFileDir(AFileName));
  TFile.WriteAllText(AFileName, AText, TEncoding.UTF8);
end;

{ TAtlasTestingApprovalTests }

procedure TAtlasTestingApprovalTests.Setup;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'atlas-approval-' + IntToStr(Random(MaxInt)));
  TApproval.Folder := '';
  TApproval.English := False;
end;

procedure TAtlasTestingApprovalTests.TearDown;
begin
  if TDirectory.Exists(FFolder) then
  begin
    TDirectory.Delete(FFolder, True);
  end;
  TApproval.Folder := '';
  TApproval.English := False;
  FFolder := '';
end;

procedure TAtlasTestingApprovalTests.LineEndsAreNoDifference;
begin
  Assert.AreEqual('a'#10'b'#10'c', TApproval.Normalized('a'#13#10'b'#13'c'));
  Assert.AreEqual(0, TApproval.FirstDifference(TApproval.Normalized('x'#13#10'y'), TApproval.Normalized('x'#10'y')));
end;

procedure TAtlasTestingApprovalTests.FirstDifferenceIsALine;
begin
  Assert.AreEqual(2, TApproval.FirstDifference('a'#10'b'#10'c', 'a'#10'B'#10'c'));
  Assert.AreEqual(3, TApproval.FirstDifference('a'#10'b', 'a'#10'b'#10'c'), 'eine Zeile mehr');
  Assert.AreEqual(1, TApproval.FirstDifference('', 'a'));
end;

procedure TAtlasTestingApprovalTests.NewThenApprovedThenDifferent;
var
  mMessage, mApproved, mReceived: string;
begin
  mApproved := TApproval.FileOf(FFolder, 'TReport.Writes', TApproval.cApproved, '.json');
  mReceived := TApproval.FileOf(FFolder, 'TReport.Writes', TApproval.cReceived, 'json');
  Assert.AreEqual(TPath.Combine(FFolder, 'TReport.Writes.approved.json'), mApproved);
  // Neu: received schreiben, Meldung nennt beide Dateien.
  Assert.AreEqual<TApprovalOutcome>(TApprovalOutcome.New,
    TApproval.Compare('{"a": 1}'#13#10, FFolder, 'TReport.Writes', '.json', mMessage));
  Assert.IsTrue(FileExists(mReceived));
  Assert.AreEqual('Approval: neu, bitte prüfen: "' + mReceived + '" (erwartet: "' + mApproved + '")', mMessage);
  // Übernehmen wie im Plugin: received wird approved; dann grün und ohne received.
  TFile.Move(mReceived, mApproved);
  WriteFile(mReceived, 'alt');
  Assert.AreEqual<TApprovalOutcome>(TApprovalOutcome.Same,
    TApproval.Compare('{"a": 1}'#10, FFolder, 'TReport.Writes', '.json', mMessage));
  Assert.AreEqual('', mMessage);
  Assert.IsFalse(FileExists(mReceived), 'überholte received-Datei gelöscht');
  // Abweichung in Zeile 2.
  TApproval.English := True;
  Assert.AreEqual<TApprovalOutcome>(TApprovalOutcome.Different,
    TApproval.Compare('{"a": 1}'#10'{"b": 2}', FFolder, 'TReport.Writes', '.json', mMessage));
  Assert.AreEqual('Approval: difference from line 2, see "' + mReceived + '" (expected: "' + mApproved + '")',
    mMessage);
  Assert.AreEqual('{"a": 1}'#10'{"b": 2}', TApproval.Normalized(TFile.ReadAllText(mReceived, TEncoding.UTF8)));
end;

procedure TAtlasTestingApprovalTests.VerifyFailsWithTheMessage;
begin
  TApproval.Folder := FFolder;
  Assert.WillRaise(
    procedure
    begin
      TApproval.Verify('Wert', 'TBeispiel.Neu');
    end, ETestFailure);
  Assert.IsTrue(FileExists(TPath.Combine(FFolder, 'TBeispiel.Neu.received.txt')));
  Assert.WillRaise(
    procedure
    begin
      TApproval.Verify('{}', 'TBeispiel.Json', '.json');
    end, ETestFailure);
  Assert.IsTrue(FileExists(TPath.Combine(FFolder, 'TBeispiel.Json.received.json')));
  WriteFile(TPath.Combine(FFolder, 'TBeispiel.Neu.approved.txt'), 'WERT');
  Assert.WillNotRaise(
    procedure
    begin
      TApproval.Verify('wert', 'TBeispiel.Neu', '.txt',
        function(const AText: string): string
        begin
          Result := UpperCase(AText);
        end);
    end);
end;

procedure TAtlasTestingApprovalTests.FolderFromSettingsOrProject;
var
  mProject, mOutput: string;
begin
  mProject := TPath.Combine(FFolder, 'Kasse');
  mOutput := TPath.Combine(TPath.Combine(mProject, 'Win32'), 'Debug');
  ForceDirectories(mOutput);
  // Ohne atlas.json: neben der nächsten Projektdatei.
  WriteFile(TPath.Combine(mProject, 'Kasse.Tests.dproj'), '<Project/>');
  Assert.AreEqual(TPath.Combine(TPath.Combine(mProject, 'Tests'), 'Erwartet'), TApproval.FolderFrom(mOutput));
  // atlas.json darüber gilt, mit ihrem Eintrag relativ zu ihrem Ordner.
  WriteFile(TPath.Combine(FFolder, 'atlas.json'), '{"tests": {"approvalFolder": "Gold/Kasse"}}');
  Assert.AreEqual(TPath.Combine(TPath.Combine(FFolder, 'Gold'), 'Kasse'), TApproval.FolderFrom(mOutput));
  // Ohne Eintrag die Vorgabe neben der atlas.json.
  Assert.AreEqual(TPath.Combine(TPath.Combine(FFolder, 'Tests'), 'Erwartet'),
    TApproval.FolderOfSettings('{"tests": {}}', FFolder));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTestingApprovalTests);

end.
