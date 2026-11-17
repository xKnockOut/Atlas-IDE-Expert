unit Atlas.Core.Welcome.ContinueQueries.Tests;

// Tests des Abfragestands im Bereich „Weiterarbeiten“ (#755, #571): HEAD je Ziel mit Sperre für laufende
// Abfragen und Zeitfenster, eingehende Commits nur zum Schlüssel der letzten Abfrage.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Welcome.Continue,
  Atlas.Core.Welcome.ContinueQueries;

type
  [TestFixture]
  [Category('Atlas.IDE.Welcome')]
  TAtlasContinueQueriesTests = class
  public
    [Test]
    procedure HeadQueryBlocksUntilArrived;
    [Test]
    procedure HeadQueryExpiresAfterLimit;
    [Test]
    procedure HeadArrivedStoresOnlyWithOk;
    [Test]
    procedure HeadRecentAfterNotStarted;
    [Test]
    procedure IncomingArrivedNeedsSameKey;
    [Test]
    procedure IncomingFailureKeepsProjectOnly;
    [Test]
    procedure IncomingOutdateMakesDue;
    [Test]
    procedure IncomingOtherKeyDropsCommits;
    [Test]
    procedure IncomingSameProjectIgnoresSpelling;
  end;

implementation

function Found(const AProject: string): TAtlasContinueIncoming;
begin
  Result := Default(TAtlasContinueIncoming);
  Result.Available := True;
  Result.Project := AProject;
  Result.Upstream := 'origin/main';
end;

procedure TAtlasContinueQueriesTests.HeadQueryBlocksUntilArrived;
var
  mHeads: TAtlasContinueHeads;
begin
  mHeads := TAtlasContinueHeads.Create;
  try
    Assert.IsFalse(mHeads.Querying('a', 1000), 'ohne Abfrage frei');
    mHeads.Started('a', 1000);
    Assert.IsTrue(mHeads.Querying('a', 2000), 'laufende Abfrage sperrt');
    Assert.IsFalse(mHeads.Querying('b', 2000), 'anderes Ziel frei');
    mHeads.Arrived('a', 1000, 3000, False, TAtlasWorkState.Empty);
    Assert.IsFalse(mHeads.Querying('a', 3000), 'nach dem Ergebnis frei');
  finally
    mHeads.Free;
  end;
end;

procedure TAtlasContinueQueriesTests.HeadQueryExpiresAfterLimit;
var
  mHeads: TAtlasContinueHeads;
begin
  mHeads := TAtlasContinueHeads.Create;
  try
    mHeads.Started('a', 1000);
    Assert.IsFalse(mHeads.Querying('a', 1000 + TAtlasWelcomeContinue.cQueryLimitMs + 1), 'hängende Abfrage vergessen');
  finally
    mHeads.Free;
  end;
end;

procedure TAtlasContinueQueriesTests.HeadArrivedStoresOnlyWithOk;
var
  mHeads: TAtlasContinueHeads;
  mHead, mRead: TAtlasWorkState;
begin
  mHeads := TAtlasContinueHeads.Create;
  try
    mHead := TAtlasWorkState.Empty;
    mHead.Head := 'feature';
    mHeads.Started('a', 1000);
    mHeads.Arrived('a', 1000, 2000, False, mHead);
    Assert.IsFalse(mHeads.TryHead('a', mRead), 'Fehler speichert nichts');
    mHeads.Arrived('a', 1000, 2000, True, mHead);
    Assert.IsTrue(mHeads.TryHead('a', mRead), 'Ergebnis gespeichert');
    Assert.AreEqual('feature', mRead.Head);
    Assert.IsTrue(mHeads.Recent('a', 2500, 1000), 'eben gefragt');
  finally
    mHeads.Free;
  end;
end;

procedure TAtlasContinueQueriesTests.HeadRecentAfterNotStarted;
var
  mHeads: TAtlasContinueHeads;
begin
  mHeads := TAtlasContinueHeads.Create;
  try
    mHeads.Started('a', 1000);
    mHeads.NotStarted('a', 1500);
    Assert.IsFalse(mHeads.Querying('a', 1600), 'keine laufende Abfrage');
    Assert.IsTrue(mHeads.Recent('a', 1600, 1000), 'als gefragt gemerkt');
    Assert.IsFalse(mHeads.Recent('a', 3000, 1000), 'Zeitfenster vorbei');
  finally
    mHeads.Free;
  end;
end;

procedure TAtlasContinueQueriesTests.IncomingArrivedNeedsSameKey;
var
  mQueries: TAtlasContinueIncomingQueries;
begin
  mQueries := TAtlasContinueIncomingQueries.Create;
  try
    mQueries.Started('A.dproj', 1000);
    Assert.IsTrue(mQueries.Running(2000), 'Abfrage läuft');
    mQueries.Started('B.dproj', 1500);
    Assert.IsFalse(mQueries.Arrived('A.dproj', 1000, 2000, True, Found('A.dproj')), 'veraltete Abfrage');
    Assert.IsTrue(mQueries.Running(2000), 'Abfrage zu b läuft weiter');
    Assert.IsTrue(mQueries.Arrived('B.dproj', 1500, 2500, True, Found('B.dproj')), 'passende Abfrage');
    Assert.IsFalse(mQueries.Running(2600), 'fertig');
    Assert.AreEqual('origin/main', mQueries.Current('B.dproj').Upstream);
  finally
    mQueries.Free;
  end;
end;

procedure TAtlasContinueQueriesTests.IncomingFailureKeepsProjectOnly;
var
  mQueries: TAtlasContinueIncomingQueries;
  mData: TAtlasContinueIncoming;
begin
  mQueries := TAtlasContinueIncomingQueries.Create;
  try
    mQueries.Started('A.dproj', 1000);
    Assert.IsTrue(mQueries.Arrived('A.dproj', 1000, 2000, False, Found('A.dproj')), 'Ergebnis übernommen');
    mData := mQueries.Current('A.dproj');
    Assert.IsFalse(mData.Available, 'ohne Abschnitt');
    Assert.AreEqual('', mData.Upstream);
  finally
    mQueries.Free;
  end;
end;

procedure TAtlasContinueQueriesTests.IncomingOutdateMakesDue;
var
  mQueries: TAtlasContinueIncomingQueries;
begin
  mQueries := TAtlasContinueIncomingQueries.Create;
  try
    mQueries.Started('A.dproj', 1000);
    mQueries.Arrived('A.dproj', 1000, 2000, True, Found('A.dproj'));
    Assert.IsFalse(mQueries.Due(False, 'A.dproj', 3000), 'frisches Ergebnis');
    Assert.IsTrue(mQueries.Due(True, 'A.dproj', 3000), 'erzwungen');
    Assert.IsTrue(mQueries.Due(False, 'B.dproj', 3000), 'anderer Eintrag');
    mQueries.Outdate('B.dproj');
    Assert.IsFalse(mQueries.Due(False, 'A.dproj', 3000), 'anderes Projekt ändert nichts');
    mQueries.Outdate('A.dproj');
    Assert.IsTrue(mQueries.Due(False, 'A.dproj', 3000), 'neuer Stand geschrieben');
  finally
    mQueries.Free;
  end;
end;

procedure TAtlasContinueQueriesTests.IncomingOtherKeyDropsCommits;
var
  mQueries: TAtlasContinueIncomingQueries;
begin
  mQueries := TAtlasContinueIncomingQueries.Create;
  try
    mQueries.Started('A.dproj', 1000);
    mQueries.Arrived('A.dproj', 1000, 2000, True, Found('A.dproj'));
    mQueries.Started('B.dproj', 3000);
    Assert.IsTrue(mQueries.Concerns('B.dproj'), 'Abfrage zu b');
    Assert.IsFalse(mQueries.Concerns('A.dproj'), 'nicht mehr zu a');
    Assert.IsFalse(mQueries.Current('A.dproj').Available, 'alte Commits verworfen');
    mQueries.NotStarted(3100);
    Assert.IsFalse(mQueries.Running(3200), 'nicht in Gang');
  finally
    mQueries.Free;
  end;
end;

procedure TAtlasContinueQueriesTests.IncomingSameProjectIgnoresSpelling;
var
  mQueries: TAtlasContinueIncomingQueries;
begin
  mQueries := TAtlasContinueIncomingQueries.Create;
  try
    mQueries.Started('C:/Src/A.dproj', 1000);
    Assert.IsTrue(mQueries.Arrived('c:\src\a.DPROJ', 1000, 2000, True, Found('C:\Src\A.dproj')),
      'gleiches Projekt, andere Schreibweise');
    Assert.IsTrue(mQueries.Concerns(' C:\SRC\A.dproj '), 'Leerzeichen und Groß-/Kleinschreibung zählen nicht');
    Assert.AreEqual('origin/main', mQueries.Current('C:/src/a.dproj').Upstream);
  finally
    mQueries.Free;
  end;
end;

end.
