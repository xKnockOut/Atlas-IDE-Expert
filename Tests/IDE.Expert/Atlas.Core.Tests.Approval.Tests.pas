unit Atlas.Core.Tests.Approval.Tests;

// Tests der Vergleichsdateien im Plugin (#1881) ohne IDE: Meldung der
// Hilfs-Unit erkennen (deutsch, englisch, neu), received übernehmen, Ordner
// aus atlas.json, liegengebliebene received-Dateien und .gitignore.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tests')]
  TAtlasTestApprovalTests = class
  private
    FFolder: string;
    function PathOf(const AName: string): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ParsesGermanDifference;
    [Test]
    procedure ParsesEnglishNew;
    [Test]
    procedure IgnoresOtherMessages;
    [Test]
    procedure AcceptReplacesApproved;
    [Test]
    procedure AcceptWithoutReceived;
    [Test]
    procedure ReadSideAlignsLineEnds;
    [Test]
    procedure FolderFromSettingsOrDefault;
    [Test]
    procedure LeftoversAreReceivedOnly;
    [Test]
    procedure IgnoreFileAndEntry;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Core.Tests.Approval;

procedure WriteFile(const AFileName, AText: string);
begin
  ForceDirectories(ExtractFileDir(AFileName));
  TFile.WriteAllText(AFileName, AText, TEncoding.UTF8);
end;

{ TAtlasTestApprovalTests }

procedure TAtlasTestApprovalTests.Setup;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'atlas-approval-plugin-' + IntToStr(Random(MaxInt)));
end;

procedure TAtlasTestApprovalTests.TearDown;
begin
  if TDirectory.Exists(FFolder) then
  begin
    TDirectory.Delete(FFolder, True);
  end;
  FFolder := '';
end;

function TAtlasTestApprovalTests.PathOf(const AName: string): string;
begin
  Result := IncludeTrailingPathDelimiter(FFolder) + AName;
end;

procedure TAtlasTestApprovalTests.ParsesGermanDifference;
var
  mHit: TAtlasApprovalHit;
begin
  Assert.IsTrue(TAtlasTestApproval.Parse('Approval: Abweichung ab Zeile 12, siehe ' +
    '"C:\P\Tests\Erwartet\T.M.received.txt" (erwartet: "C:\P\Tests\Erwartet\T.M.approved.txt")', mHit));
  Assert.AreEqual(Ord(TAtlasApprovalKind.Different), Ord(mHit.Kind));
  Assert.AreEqual(12, mHit.Line);
  Assert.AreEqual('C:\P\Tests\Erwartet\T.M.received.txt', mHit.Received);
  Assert.AreEqual('C:\P\Tests\Erwartet\T.M.approved.txt', mHit.Approved);
end;

procedure TAtlasTestApprovalTests.ParsesEnglishNew;
var
  mHit: TAtlasApprovalHit;
begin
  // DUnitX setzt vor die Meldung gern weiteren Text, etwa den Namen des Tests.
  Assert.IsTrue(TAtlasTestApproval.Parse('Fail: Approval: new, please review: "D:\X 2\A.B.received.json" (expected: ' +
    '"D:\X 2\A.B.approved.json")', mHit));
  Assert.AreEqual(Ord(TAtlasApprovalKind.Added), Ord(mHit.Kind));
  Assert.AreEqual(0, mHit.Line);
  Assert.AreEqual('D:\X 2\A.B.received.json', mHit.Received);
  Assert.AreEqual('D:\X 2\A.B.approved.json', mHit.Approved);
end;

procedure TAtlasTestApprovalTests.IgnoresOtherMessages;
var
  mHit: TAtlasApprovalHit;
begin
  Assert.IsFalse(TAtlasTestApproval.Parse('Expected 4 but got 3', mHit));
  Assert.IsFalse(TAtlasTestApproval.Parse('Approval: siehe "a.txt" (erwartet: "b.txt")', mHit), 'ohne Dateiarten');
  Assert.IsFalse(TAtlasTestApproval.Parse('Approval: neu, bitte prüfen: "x.received.txt"', mHit), 'nur eine Datei');
  Assert.AreEqual('', mHit.Received);
end;

procedure TAtlasTestApprovalTests.AcceptReplacesApproved;
var
  mHit: TAtlasApprovalHit;
begin
  mHit := Default(TAtlasApprovalHit);
  mHit.Received := PathOf('Erwartet' + PathDelim + 'T.M.received.txt');
  mHit.Approved := PathOf('Erwartet' + PathDelim + 'T.M.approved.txt');
  WriteFile(mHit.Received, 'neu');
  WriteFile(mHit.Approved, 'alt');
  Assert.AreEqual(Ord(TAtlasApprovalAccept.Done), Ord(TAtlasTestApproval.Accept(mHit)));
  Assert.IsFalse(FileExists(mHit.Received), 'received ist weg');
  Assert.AreEqual('neu', TAtlasTestApproval.ReadSide(mHit.Approved));
  // Erste Erwartung: Der Ordner der approved-Datei darf noch fehlen.
  mHit.Received := PathOf('A.B.received.txt');
  mHit.Approved := PathOf('Neu' + PathDelim + 'A.B.approved.txt');
  WriteFile(mHit.Received, 'erste');
  Assert.AreEqual(Ord(TAtlasApprovalAccept.Done), Ord(TAtlasTestApproval.Accept(mHit)));
  Assert.AreEqual('erste', TAtlasTestApproval.ReadSide(mHit.Approved));
end;

procedure TAtlasTestApprovalTests.AcceptWithoutReceived;
var
  mHit: TAtlasApprovalHit;
begin
  mHit := Default(TAtlasApprovalHit);
  mHit.Received := PathOf('fehlt.received.txt');
  mHit.Approved := PathOf('fehlt.approved.txt');
  Assert.AreEqual(Ord(TAtlasApprovalAccept.Missing), Ord(TAtlasTestApproval.Accept(mHit)));
  Assert.IsFalse(FileExists(mHit.Approved));
end;

procedure TAtlasTestApprovalTests.ReadSideAlignsLineEnds;
begin
  WriteFile(PathOf('x.approved.txt'), 'a'#13#10'b'#13'c');
  Assert.AreEqual('a'#10'b'#10'c', TAtlasTestApproval.ReadSide(PathOf('x.approved.txt')));
  Assert.AreEqual('', TAtlasTestApproval.ReadSide(PathOf('gibt-es-nicht.txt')));
end;

procedure TAtlasTestApprovalTests.FolderFromSettingsOrDefault;
var
  mProject: string;
begin
  mProject := PathOf('Repo' + PathDelim + 'Tests' + PathDelim + 'P.dproj');
  WriteFile(mProject, '');
  Assert.AreEqual(ExpandFileName(PathOf('Repo' + PathDelim + 'Tests' + PathDelim + 'Tests' + PathDelim + 'Erwartet')),
    TAtlasTestApproval.FolderOf(mProject), 'ohne atlas.json neben der Projektdatei');
  WriteFile(PathOf('Repo' + PathDelim + 'atlas.json'), '{"tests": {"approvalFolder": "Daten/Gold"}}');
  Assert.AreEqual(ExpandFileName(PathOf('Repo' + PathDelim + 'Daten' + PathDelim + 'Gold')),
    TAtlasTestApproval.FolderOf(mProject), 'atlas.json weiter oben gilt');
end;

procedure TAtlasTestApprovalTests.LeftoversAreReceivedOnly;
var
  mFound: TArray<string>;
begin
  Assert.AreEqual(0, Integer(Length(TAtlasTestApproval.Leftovers(PathOf('fehlt')))));
  WriteFile(PathOf('B.M.received.txt'), '');
  WriteFile(PathOf('B.M.approved.txt'), '');
  WriteFile(PathOf('Unter' + PathDelim + 'A.M.received.json'), '');
  mFound := TAtlasTestApproval.Leftovers(FFolder);
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual(PathOf('B.M.received.txt'), mFound[0]);
  Assert.AreEqual(PathOf('Unter' + PathDelim + 'A.M.received.json'), mFound[1]);
end;

procedure TAtlasTestApprovalTests.IgnoreFileAndEntry;
begin
  ForceDirectories(PathOf('Repo' + PathDelim + '.git'));
  ForceDirectories(PathOf('Repo' + PathDelim + 'Tests'));
  WriteFile(PathOf('.gitignore'), '');
  Assert.AreEqual('', TAtlasTestApproval.IgnoreFileFrom(PathOf('Repo' + PathDelim + 'Tests')),
    'nicht über den Ordner mit .git hinaus');
  WriteFile(PathOf('Repo' + PathDelim + '.gitignore'), '*.dcu');
  Assert.AreEqual(PathOf('Repo' + PathDelim + '.gitignore'),
    TAtlasTestApproval.IgnoreFileFrom(PathOf('Repo' + PathDelim + 'Tests')));
  Assert.IsFalse(TAtlasTestApproval.HasIgnoreEntry('*.dcu'#13#10'# *.received.*'));
  Assert.IsTrue(TAtlasTestApproval.HasIgnoreEntry('*.dcu'#13#10 + TAtlasTestApproval.cIgnorePattern + #13#10));
end;

end.
