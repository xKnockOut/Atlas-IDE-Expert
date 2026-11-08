unit Atlas.Core.Files.ProcessLeftovers.Tests;

// Reste beendeter IDE-Prozesse: Prozessnummer aus dem Namen und Auswahl dessen, was weg darf.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasProcessLeftoversTests = class
  public
    [Test]
    procedure ReadsPidFromDirtyFile;
    [Test]
    procedure RejectsOtherNames;
    [Test]
    procedure ReadsPidFromFolderName;
    [Test]
    procedure KeepsRunningAndOwnProcess;
    [Test]
    procedure RemovesReusedPid;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Files.ProcessLeftovers;

procedure TAtlasProcessLeftoversTests.ReadsPidFromDirtyFile;
var
  mPid: Cardinal;
begin
  Assert.IsTrue(TAtlasProcessLeftovers.PidOf('editor-dirty-4711.json', TAtlasProcessLeftovers.cDirtyPrefix,
    TAtlasProcessLeftovers.cDirtySuffix, mPid));
  Assert.AreEqual(Cardinal(4711), mPid);
  Assert.IsTrue(TAtlasProcessLeftovers.PidOf('EDITOR-DIRTY-12.JSON', TAtlasProcessLeftovers.cDirtyPrefix,
    TAtlasProcessLeftovers.cDirtySuffix, mPid), 'Groß- und Kleinschreibung egal');
  Assert.AreEqual(Cardinal(12), mPid);
end;

procedure TAtlasProcessLeftoversTests.RejectsOtherNames;
var
  mPid: Cardinal;
begin
  Assert.IsFalse(TAtlasProcessLeftovers.PidOf('editor-dirty-.json', TAtlasProcessLeftovers.cDirtyPrefix,
    TAtlasProcessLeftovers.cDirtySuffix, mPid));
  Assert.IsFalse(TAtlasProcessLeftovers.PidOf('editor-dirty-abc.json', TAtlasProcessLeftovers.cDirtyPrefix,
    TAtlasProcessLeftovers.cDirtySuffix, mPid));
  Assert.IsFalse(TAtlasProcessLeftovers.PidOf('editor-dirty--5.json', TAtlasProcessLeftovers.cDirtyPrefix,
    TAtlasProcessLeftovers.cDirtySuffix, mPid));
  Assert.IsFalse(TAtlasProcessLeftovers.PidOf('editor-dirty-0.json', TAtlasProcessLeftovers.cDirtyPrefix,
    TAtlasProcessLeftovers.cDirtySuffix, mPid));
  Assert.IsFalse(TAtlasProcessLeftovers.PidOf('settings.json', TAtlasProcessLeftovers.cDirtyPrefix,
    TAtlasProcessLeftovers.cDirtySuffix, mPid));
end;

procedure TAtlasProcessLeftoversTests.ReadsPidFromFolderName;
var
  mPid: Cardinal;
begin
  Assert.IsTrue(TAtlasProcessLeftovers.PidOf('20912', '', '', mPid));
  Assert.AreEqual(Cardinal(20912), mPid);
  Assert.IsFalse(TAtlasProcessLeftovers.PidOf('alt', '', '', mPid));
end;

procedure TAtlasProcessLeftoversTests.KeepsRunningAndOwnProcess;
var
  mStale: TArray<string>;
begin
  // 1 läuft, 2 ist der eigene Prozess (gilt als beendet, bleibt trotzdem), 3 ist beendet.
  mStale := TAtlasProcessLeftovers.Stale([TAtlasLeftover.Create('a', 1, 0), TAtlasLeftover.Create('b', 2, 0),
    TAtlasLeftover.Create('c', 3, 0)], 2,
    function(APid: Cardinal; AStamp: TDateTime): Boolean
    begin
      Result := APid = 1;
    end);
  Assert.AreEqual(1, Integer(Length(mStale)));
  Assert.AreEqual('c', mStale[0]);
end;

procedure TAtlasProcessLeftoversTests.RemovesReusedPid;
var
  mStale: TArray<string>;
begin
  // Die Nummer 7 trägt inzwischen ein Prozess, der nach dem Eintrag gestartet ist: Der Eintrag ist ein Rest.
  mStale := TAtlasProcessLeftovers.Stale([TAtlasLeftover.Create('alt', 7, EncodeDate(2026, 11, 1))], 1,
    function(APid: Cardinal; AStamp: TDateTime): Boolean
    begin
      Result := AStamp >= EncodeDate(2026, 11, 8);
    end);
  Assert.AreEqual(1, Integer(Length(mStale)));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasProcessLeftoversTests);

end.
