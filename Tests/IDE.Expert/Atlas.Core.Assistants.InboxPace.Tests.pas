unit Atlas.Core.Assistants.InboxPace.Tests;

// Takt der Auftragseingänge (#1984): aufgelistet wird nur nach einem Signal,
// bei liegen gebliebenen Aufträgen, beim ersten Takt und als Sicherheitsnetz.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Assistants')]
  TAtlasInboxPaceTests = class
  public
    [Test]
    procedure FirstTickLists;
    [Test]
    procedure QuietFolderWaitsForSafetyNet;
    [Test]
    procedure SignalListsAtOnce;
    [Test]
    procedure BacklogListsAgain;
  end;

implementation

uses
  Atlas.Core.Assistants.InboxPace;

procedure TAtlasInboxPaceTests.FirstTickLists;
var
  mPace: TAtlasInboxPace;
begin
  mPace := Default(TAtlasInboxPace);
  Assert.IsTrue(mPace.Due(False, 1000));
end;

procedure TAtlasInboxPaceTests.QuietFolderWaitsForSafetyNet;
var
  mPace: TAtlasInboxPace;
begin
  mPace := Default(TAtlasInboxPace);
  mPace.Listed(1000, False);
  Assert.IsFalse(mPace.Due(False, 1100), 'ohne Signal kein Auflisten');
  Assert.IsFalse(mPace.Due(False, 1000 + TAtlasInboxPace.cSafetyMs - 1));
  Assert.IsTrue(mPace.Due(False, 1000 + TAtlasInboxPace.cSafetyMs), 'Sicherheitsnetz');
end;

procedure TAtlasInboxPaceTests.SignalListsAtOnce;
var
  mPace: TAtlasInboxPace;
begin
  mPace := Default(TAtlasInboxPace);
  mPace.Listed(1000, False);
  Assert.IsTrue(mPace.Due(True, 1100));
end;

procedure TAtlasInboxPaceTests.BacklogListsAgain;
var
  mPace: TAtlasInboxPace;
begin
  mPace := Default(TAtlasInboxPace);
  mPace.Listed(1000, True);
  Assert.IsTrue(mPace.Due(False, 1100), 'liegen gebliebene Aufträge');
  mPace.Listed(1100, False);
  Assert.IsFalse(mPace.Due(False, 1200));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasInboxPaceTests);

end.
