unit Atlas.Core.Assistants.Activity.Tests;

// Anzeige „KI-Assistent aktiv“ (#1906): Pause geht vor, dann ein laufender Build, dann eine kürzlich angewendete
// Änderung; danach verschwindet das Feld.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Assistants')]
  TAtlasAssistantsActivityTests = class
  public
    [Test]
    procedure NothingHappenedIsIdle;
    [Test]
    procedure RunningBuildShowsProjectAndClient;
    [Test]
    procedure EndedBuildIsIdle;
    [Test]
    procedure EditIsShownForAWhile;
    [Test]
    procedure PauseGoesFirst;
    [Test]
    procedure BuildGoesBeforeEdit;
    [Test]
    procedure ClockBeforeEditIsIdle;
  end;

implementation

uses
  Atlas.Core.Assistants.Activity;

{ TAtlasAssistantsActivityTests }

procedure TAtlasAssistantsActivityTests.NothingHappenedIsIdle;
var
  mActivity: TAtlasAssistantsActivity;
begin
  mActivity := TAtlasAssistantsActivity.Create;
  try
    Assert.AreEqual<TAtlasAssistantsActivityKind>(TAtlasAssistantsActivityKind.Idle, mActivity.View(1000).Kind);
    Assert.IsFalse(mActivity.Building);
  finally
    mActivity.Free;
  end;
end;

procedure TAtlasAssistantsActivityTests.RunningBuildShowsProjectAndClient;
var
  mActivity: TAtlasAssistantsActivity;
  mView: TAtlasAssistantsActivityView;
begin
  mActivity := TAtlasAssistantsActivity.Create;
  try
    mActivity.BuildStarted('C:\Projekte\Atlas\Atlas.Tests.dproj', 'Assistent A');
    mView := mActivity.View(1000);
    Assert.AreEqual<TAtlasAssistantsActivityKind>(TAtlasAssistantsActivityKind.Building, mView.Kind);
    Assert.AreEqual('Atlas.Tests.dproj', mView.Subject, 'ohne Pfad');
    Assert.AreEqual('Assistent A', mView.Client);
    Assert.IsTrue(mActivity.Building);
  finally
    mActivity.Free;
  end;
end;

procedure TAtlasAssistantsActivityTests.EndedBuildIsIdle;
var
  mActivity: TAtlasAssistantsActivity;
begin
  mActivity := TAtlasAssistantsActivity.Create;
  try
    mActivity.BuildStarted('/src/A.dproj', '');
    mActivity.BuildEnded;
    Assert.AreEqual<TAtlasAssistantsActivityKind>(TAtlasAssistantsActivityKind.Idle, mActivity.View(1000).Kind);
    Assert.IsFalse(mActivity.Building);
  finally
    mActivity.Free;
  end;
end;

procedure TAtlasAssistantsActivityTests.EditIsShownForAWhile;
var
  mActivity: TAtlasAssistantsActivity;
  mView: TAtlasAssistantsActivityView;
begin
  mActivity := TAtlasAssistantsActivity.Create;
  try
    mActivity.EditApplied('C:\Src\Run.pas', '', 5000);
    mView := mActivity.View(5000 + TAtlasAssistantsActivity.cEditShownMs - 1);
    Assert.AreEqual<TAtlasAssistantsActivityKind>(TAtlasAssistantsActivityKind.Edited, mView.Kind);
    Assert.AreEqual('Run.pas', mView.Subject);
    Assert.AreEqual('', mView.Client, 'unbekannter Assistent');
    Assert.AreEqual<TAtlasAssistantsActivityKind>(TAtlasAssistantsActivityKind.Idle,
      mActivity.View(5000 + TAtlasAssistantsActivity.cEditShownMs).Kind, 'danach verschwindet das Feld');
  finally
    mActivity.Free;
  end;
end;

procedure TAtlasAssistantsActivityTests.PauseGoesFirst;
var
  mActivity: TAtlasAssistantsActivity;
  mView: TAtlasAssistantsActivityView;
begin
  mActivity := TAtlasAssistantsActivity.Create;
  try
    mActivity.BuildStarted('A.dproj', 'Assistent A');
    mActivity.Paused := True;
    mView := mActivity.View(1000);
    Assert.AreEqual<TAtlasAssistantsActivityKind>(TAtlasAssistantsActivityKind.Paused, mView.Kind);
    Assert.AreEqual('', mView.Subject);
    Assert.IsTrue(mActivity.Building, 'der laufende Build läuft zu Ende');
    mActivity.Paused := False;
    Assert.AreEqual<TAtlasAssistantsActivityKind>(TAtlasAssistantsActivityKind.Building, mActivity.View(1000).Kind);
  finally
    mActivity.Free;
  end;
end;

procedure TAtlasAssistantsActivityTests.BuildGoesBeforeEdit;
var
  mActivity: TAtlasAssistantsActivity;
begin
  mActivity := TAtlasAssistantsActivity.Create;
  try
    mActivity.EditApplied('Run.pas', 'Assistent B', 1000);
    mActivity.BuildStarted('A.dproj', 'Assistent A');
    Assert.AreEqual('A.dproj', mActivity.View(1000).Subject);
    mActivity.BuildEnded;
    Assert.AreEqual('Run.pas', mActivity.View(1000).Subject, 'danach wieder die Änderung');
    Assert.AreEqual('Assistent B', mActivity.View(1000).Client);
  finally
    mActivity.Free;
  end;
end;

procedure TAtlasAssistantsActivityTests.ClockBeforeEditIsIdle;
var
  mActivity: TAtlasAssistantsActivity;
begin
  mActivity := TAtlasAssistantsActivity.Create;
  try
    mActivity.EditApplied('Run.pas', '', 5000);
    Assert.AreEqual<TAtlasAssistantsActivityKind>(TAtlasAssistantsActivityKind.Idle, mActivity.View(4000).Kind,
      'Zähler übergelaufen oder zurückgesetzt: nicht ewig zeigen');
  finally
    mActivity.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasAssistantsActivityTests);

end.
