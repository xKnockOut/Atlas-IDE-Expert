unit Atlas.Core.Tracker.Files.Tests;

// Anmeldung von Platte und Shell des Trackers (#1455 Paket 2d): ohne
// Anmeldung leere Umsetzungen, angemeldete Umsetzung bis zum Abmelden,
// Join ohne Plattenzugriff.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasTrackerFilesTests = class
  public
    [TearDown]
    procedure TearDown;
    /// <summary>Abnahme: Ohne Anmeldung liest, schreibt und öffnet nichts (Regel 3 nach dem Abmelden).</summary>
    [Test]
    procedure WithoutInstallNothingHappens;
    [Test]
    procedure InstalledUntilUninstall;
    [Test]
    procedure JoinWithAndWithoutFolder;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Tracker.Contract.Files,
  Atlas.Core.Tracker.Files,
  Atlas.Core.Tracker.Adapters.LocalFiles;

type
  /// <summary>Shell, die nur mitschreibt.</summary>
  TAtlasRecordingShell = class(TInterfacedObject, IAtlasTrackerShell)
  private
    FOpened: string;
  public
    function Open(const ATarget: string): Boolean;
    function OpenFile(const AFileName: string): Boolean;
    function Reveal(const AFileName: string): Boolean;
    property Opened: string read FOpened;
  end;

function TAtlasRecordingShell.Open(const ATarget: string): Boolean;
begin
  FOpened := FOpened + 'open:' + ATarget + ';';
  Result := True;
end;

function TAtlasRecordingShell.OpenFile(const AFileName: string): Boolean;
begin
  FOpened := FOpened + 'file:' + AFileName + ';';
  Result := True;
end;

function TAtlasRecordingShell.Reveal(const AFileName: string): Boolean;
begin
  FOpened := FOpened + 'reveal:' + AFileName + ';';
  Result := True;
end;

{ TAtlasTrackerFilesTests }

procedure TAtlasTrackerFilesTests.TearDown;
begin
  TAtlasTrackerFiles.Uninstall;
end;

procedure TAtlasTrackerFilesTests.WithoutInstallNothingHappens;
var
  mFiles: IAtlasTrackerFiles;
  mText: string;
  mData: TBytes;
  mCut: Boolean;
begin
  TAtlasTrackerFiles.Uninstall;
  mFiles := TAtlasTrackerFiles.Files;
  Assert.IsNotNull(mFiles);
  Assert.IsFalse(mFiles.FileExists(ParamStr(0)), 'die Testanwendung gibt es, aber ohne Anmeldung nicht');
  Assert.IsFalse(mFiles.ReadText(ParamStr(0), mText));
  Assert.AreEqual('', mText);
  Assert.IsFalse(mFiles.ReadTail(ParamStr(0), 0, mData, mCut));
  Assert.AreEqual(Integer(0), Integer(Length(mData)));
  Assert.IsFalse(mFiles.WriteText('x.json', '{}'));
  Assert.IsNull(mFiles.Lock('x.lock', 0));
  Assert.AreEqual('', mFiles.TempFolder);
  Assert.IsFalse(TAtlasTrackerFiles.Shell.Open('https://example.com'));
end;

procedure TAtlasTrackerFilesTests.InstalledUntilUninstall;
var
  mShell: TAtlasRecordingShell;
  mRef: IAtlasTrackerShell;
begin
  mShell := TAtlasRecordingShell.Create;
  mRef := mShell;
  TAtlasTrackerFiles.Install(TAtlasTrackerLocalFiles.Create, mRef);
  Assert.IsTrue(TAtlasTrackerFiles.Files.FileExists(ParamStr(0)));
  Assert.IsTrue(TAtlasTrackerFiles.Shell.Open('https://example.com'));
  TAtlasTrackerFiles.Shell.Reveal('a.txt');
  Assert.AreEqual('open:https://example.com;reveal:a.txt;', mShell.Opened);
  TAtlasTrackerFiles.Uninstall;
  Assert.IsFalse(TAtlasTrackerFiles.Files.FileExists(ParamStr(0)));
  Assert.IsFalse(TAtlasTrackerFiles.Shell.Open('https://example.com'));
  Assert.AreEqual('open:https://example.com;reveal:a.txt;', mShell.Opened, 'nach dem Abmelden nicht mehr erreicht');
end;

procedure TAtlasTrackerFilesTests.JoinWithAndWithoutFolder;
begin
  Assert.AreEqual('a' + PathDelim + 'b.json', TAtlasTrackerFiles.Join('a', 'b.json'));
  Assert.AreEqual('a' + PathDelim + 'b.json', TAtlasTrackerFiles.Join('a' + PathDelim, 'b.json'));
  Assert.AreEqual('b.json', TAtlasTrackerFiles.Join('', 'b.json'));
end;

end.
