unit Atlas.Core.Build.Target.Tests;

// Tests für den Abgleich von Konfiguration, Zielplattform und Defines der IDE
// mit dem Server (#615).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasBuildTargetTests = class
  public
    [Test]
    procedure ParsesDefinesOfTheIde;
    [Test]
    procedure ComparesTargets;
    [Test]
    procedure QueriesFirstThenSelectsOnChange;
    [Test]
    procedure SendsChangedDefines;
    [Test]
    procedure IgnoresProjectsUnknownToTheServer;
    [Test]
    procedure ResetStartsOver;
    [Test]
    procedure BuildsCommandArguments;
    [Test]
    procedure ReadsServerSelection;
  end;

implementation

uses
  System.Generics.Collections,
  System.JSON,
  Atlas.Core.Build.Target;

const
  cProject = 'C:\P\App.dproj';

procedure TAtlasBuildTargetTests.ParsesDefinesOfTheIde;
var
  mDefines: TArray<string>;
begin
  mDefines := TAtlasBuildTarget.ParseDefines('DEBUG; $(DCC_Define);;Foo;debug');
  Assert.AreEqual(2, Integer(Length(mDefines)));
  Assert.AreEqual('DEBUG', mDefines[0]);
  Assert.AreEqual('FOO', mDefines[1]);
  Assert.AreEqual(0, Integer(Length(TAtlasBuildTarget.ParseDefines(''))));
end;

procedure TAtlasBuildTargetTests.ComparesTargets;
var
  A, B: TAtlasBuildTarget;
begin
  A := TAtlasBuildTarget.Create(cProject, 'Debug', 'Win32', ['DEBUG', 'FOO']);
  B := TAtlasBuildTarget.Create('c:\p\app.dproj', 'debug', 'WIN32', ['FOO', 'DEBUG']);
  Assert.IsTrue(A.SameAs(B), 'Reihenfolge und Groß/klein egal');
  B.Platform := 'Win64';
  Assert.IsFalse(A.SameAs(B));
  B := A;
  B.Defines := ['DEBUG'];
  Assert.IsFalse(A.SameAs(B));
end;

procedure TAtlasBuildTargetTests.QueriesFirstThenSelectsOnChange;
var
  mTracker: TAtlasBuildTargetTracker;
  mCurrent: TAtlasBuildTarget;
begin
  mTracker := TAtlasBuildTargetTracker.Create;
  try
    mCurrent := TAtlasBuildTarget.Create(cProject, 'Debug', 'Win32', ['DEBUG']);
    Assert.AreEqual<TAtlasBuildTargetAction>(TAtlasBuildTargetAction.Query, mTracker.Decide(mCurrent));
    // Während die Anfrage läuft, nichts Neues.
    Assert.AreEqual<TAtlasBuildTargetAction>(TAtlasBuildTargetAction.None, mTracker.Decide(mCurrent));
    mTracker.Baseline(cProject, 'Debug', 'Win32', ['DEBUG'], True);
    mTracker.Finished;
    Assert.AreEqual<TAtlasBuildTargetAction>(TAtlasBuildTargetAction.None,
      mTracker.Decide(mCurrent), 'Server hat dieselbe Auswahl');
    // Wechsel auf Win64 in der Projektverwaltung.
    mCurrent.Platform := 'Win64';
    Assert.AreEqual<TAtlasBuildTargetAction>(TAtlasBuildTargetAction.Select, mTracker.Decide(mCurrent));
    Assert.IsTrue(mTracker.Pending);
    mTracker.Finished;
    Assert.AreEqual<TAtlasBuildTargetAction>(TAtlasBuildTargetAction.None,
      mTracker.Decide(mCurrent), 'nur einmal senden');
    // Server startete mit anderer Auswahl als die IDE.
    mCurrent := TAtlasBuildTarget.Create('C:\P\Other.dproj', 'Release', 'Win32', nil);
    Assert.AreEqual<TAtlasBuildTargetAction>(TAtlasBuildTargetAction.Query, mTracker.Decide(mCurrent));
    mTracker.Baseline(mCurrent.Project, 'Debug', 'Win32', nil, True);
    mTracker.Finished;
    Assert.AreEqual<TAtlasBuildTargetAction>(TAtlasBuildTargetAction.Select, mTracker.Decide(mCurrent));
  finally
    mTracker.Free;
  end;
end;

procedure TAtlasBuildTargetTests.SendsChangedDefines;
var
  mTracker: TAtlasBuildTargetTracker;
  mCurrent: TAtlasBuildTarget;
begin
  mTracker := TAtlasBuildTargetTracker.Create;
  try
    mCurrent := TAtlasBuildTarget.Create(cProject, 'Debug', 'Win32', ['DEBUG']);
    mTracker.Decide(mCurrent);
    mTracker.Baseline(cProject, 'Debug', 'Win32', mCurrent.Defines, True);
    mTracker.Finished;
    // Neues Symbol in den Projektoptionen, noch nicht gespeichert.
    mCurrent.Defines := ['DEBUG', 'TRACE'];
    Assert.AreEqual<TAtlasBuildTargetAction>(TAtlasBuildTargetAction.Select, mTracker.Decide(mCurrent));
  finally
    mTracker.Free;
  end;
end;

procedure TAtlasBuildTargetTests.IgnoresProjectsUnknownToTheServer;
var
  mTracker: TAtlasBuildTargetTracker;
  mCurrent: TAtlasBuildTarget;
begin
  mTracker := TAtlasBuildTargetTracker.Create;
  try
    mCurrent := TAtlasBuildTarget.Create(cProject, 'Debug', 'Win32', nil);
    Assert.AreEqual<TAtlasBuildTargetAction>(TAtlasBuildTargetAction.Query, mTracker.Decide(mCurrent));
    mTracker.Baseline(cProject, '', '', nil, False);
    mTracker.Finished;
    mCurrent.Platform := 'Win64';
    Assert.AreEqual<TAtlasBuildTargetAction>(TAtlasBuildTargetAction.None, mTracker.Decide(mCurrent));
    // Ohne Projekt nichts tun.
    Assert.AreEqual<TAtlasBuildTargetAction>(TAtlasBuildTargetAction.None, mTracker.Decide(Default(TAtlasBuildTarget)));
  finally
    mTracker.Free;
  end;
end;

procedure TAtlasBuildTargetTests.ResetStartsOver;
var
  mTracker: TAtlasBuildTargetTracker;
  mCurrent: TAtlasBuildTarget;
begin
  mTracker := TAtlasBuildTargetTracker.Create;
  try
    mCurrent := TAtlasBuildTarget.Create(cProject, 'Debug', 'Win32', nil);
    mTracker.Decide(mCurrent);
    mTracker.Reset;
    Assert.IsFalse(mTracker.Pending);
    Assert.AreEqual<TAtlasBuildTargetAction>(TAtlasBuildTargetAction.Query, mTracker.Decide(mCurrent));
  finally
    mTracker.Free;
  end;
end;

procedure TAtlasBuildTargetTests.BuildsCommandArguments;
var
  mTarget: TAtlasBuildTarget;
  mArguments: TJSONArray;
  mOptions: TJSONObject;
  mDefines: TJSONArray;
begin
  mTarget := TAtlasBuildTarget.Create(cProject, 'Release', 'Win64', ['RELEASE', 'TRACE']);
  mArguments := mTarget.SelectArguments('file:///C:/P/App.dproj', TAtlasBuildTargetAction.Query);
  try
    Assert.AreEqual(1, Integer(mArguments.Count));
    mOptions := mArguments.Items[0] as TJSONObject;
    Assert.AreEqual('file:///C:/P/App.dproj', mOptions.GetValue<string>('uri'));
    Assert.IsNull(mOptions.GetValue('config'), 'Query fragt nur');
  finally
    mArguments.Free;
  end;
  mArguments := mTarget.SelectArguments('file:///C:/P/App.dproj', TAtlasBuildTargetAction.Select);
  try
    mOptions := mArguments.Items[0] as TJSONObject;
    Assert.AreEqual('Release', mOptions.GetValue<string>('config'));
    Assert.AreEqual('Win64', mOptions.GetValue<string>('platform'));
    mDefines := mOptions.GetValue('defines') as TJSONArray;
    Assert.AreEqual(2, Integer(mDefines.Count));
    Assert.AreEqual('TRACE', mDefines.Items[1].Value);
  finally
    mArguments.Free;
  end;
end;

procedure TAtlasBuildTargetTests.ReadsServerSelection;
var
  mAnswer: TJSONValue;
  mConfig, mPlatform: string;
begin
  mAnswer := TJSONObject.ParseJSONValue('{"projects":[{"project":"C:\\P\\Lib.dproj","config":"Debug","platform":"Win32"},' +
    '{"project":"c:\\p\\app.dproj","config":"Release","platform":"Win64"}]}');
  try
    Assert.IsTrue(TAtlasBuildTarget.FromSelection(mAnswer, cProject, mConfig, mPlatform));
    Assert.AreEqual('Release', mConfig);
    Assert.AreEqual('Win64', mPlatform);
    Assert.IsFalse(TAtlasBuildTarget.FromSelection(mAnswer, 'C:\P\Fremd.dproj', mConfig, mPlatform));
    Assert.IsFalse(TAtlasBuildTarget.FromSelection(nil, cProject, mConfig, mPlatform));
  finally
    mAnswer.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBuildTargetTests);

end.
