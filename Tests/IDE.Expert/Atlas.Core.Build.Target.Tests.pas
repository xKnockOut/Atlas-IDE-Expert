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
  System.JSON,
  Atlas.Core.Build.Target;

const
  Project = 'C:\P\App.dproj';

procedure TAtlasBuildTargetTests.ParsesDefinesOfTheIde;
var
  Defines: TArray<string>;
begin
  Defines := TAtlasBuildTarget.ParseDefines('DEBUG; $(DCC_Define);;Foo;debug');
  Assert.AreEqual(2, Integer(Length(Defines)));
  Assert.AreEqual('DEBUG', Defines[0]);
  Assert.AreEqual('FOO', Defines[1]);
  Assert.AreEqual(0, Integer(Length(TAtlasBuildTarget.ParseDefines(''))));
end;

procedure TAtlasBuildTargetTests.ComparesTargets;
var
  A, B: TAtlasBuildTarget;
begin
  A := TAtlasBuildTarget.Create(Project, 'Debug', 'Win32', ['DEBUG', 'FOO']);
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
  Tracker: TAtlasBuildTargetTracker;
  Current: TAtlasBuildTarget;
begin
  Tracker := TAtlasBuildTargetTracker.Create;
  try
    Current := TAtlasBuildTarget.Create(Project, 'Debug', 'Win32', ['DEBUG']);
    Assert.IsTrue(Tracker.Decide(Current) = TAtlasBuildTargetAction.Query);
    // Während die Anfrage läuft, nichts Neues.
    Assert.IsTrue(Tracker.Decide(Current) = TAtlasBuildTargetAction.None);
    Tracker.Baseline(Project, 'Debug', 'Win32', ['DEBUG'], True);
    Tracker.Finished;
    Assert.IsTrue(Tracker.Decide(Current) = TAtlasBuildTargetAction.None, 'Server hat dieselbe Auswahl');
    // Wechsel auf Win64 in der Projektverwaltung.
    Current.Platform := 'Win64';
    Assert.IsTrue(Tracker.Decide(Current) = TAtlasBuildTargetAction.Select);
    Assert.IsTrue(Tracker.Pending);
    Tracker.Finished;
    Assert.IsTrue(Tracker.Decide(Current) = TAtlasBuildTargetAction.None, 'nur einmal senden');
    // Server startete mit anderer Auswahl als die IDE.
    Current := TAtlasBuildTarget.Create('C:\P\Other.dproj', 'Release', 'Win32', nil);
    Assert.IsTrue(Tracker.Decide(Current) = TAtlasBuildTargetAction.Query);
    Tracker.Baseline(Current.Project, 'Debug', 'Win32', nil, True);
    Tracker.Finished;
    Assert.IsTrue(Tracker.Decide(Current) = TAtlasBuildTargetAction.Select);
  finally
    Tracker.Free;
  end;
end;

procedure TAtlasBuildTargetTests.SendsChangedDefines;
var
  Tracker: TAtlasBuildTargetTracker;
  Current: TAtlasBuildTarget;
begin
  Tracker := TAtlasBuildTargetTracker.Create;
  try
    Current := TAtlasBuildTarget.Create(Project, 'Debug', 'Win32', ['DEBUG']);
    Tracker.Decide(Current);
    Tracker.Baseline(Project, 'Debug', 'Win32', Current.Defines, True);
    Tracker.Finished;
    // Neues Symbol in den Projektoptionen, noch nicht gespeichert.
    Current.Defines := ['DEBUG', 'TRACE'];
    Assert.IsTrue(Tracker.Decide(Current) = TAtlasBuildTargetAction.Select);
  finally
    Tracker.Free;
  end;
end;

procedure TAtlasBuildTargetTests.IgnoresProjectsUnknownToTheServer;
var
  Tracker: TAtlasBuildTargetTracker;
  Current: TAtlasBuildTarget;
begin
  Tracker := TAtlasBuildTargetTracker.Create;
  try
    Current := TAtlasBuildTarget.Create(Project, 'Debug', 'Win32', nil);
    Assert.IsTrue(Tracker.Decide(Current) = TAtlasBuildTargetAction.Query);
    Tracker.Baseline(Project, '', '', nil, False);
    Tracker.Finished;
    Current.Platform := 'Win64';
    Assert.IsTrue(Tracker.Decide(Current) = TAtlasBuildTargetAction.None);
    // Ohne Projekt nichts tun.
    Assert.IsTrue(Tracker.Decide(Default(TAtlasBuildTarget)) = TAtlasBuildTargetAction.None);
  finally
    Tracker.Free;
  end;
end;

procedure TAtlasBuildTargetTests.ResetStartsOver;
var
  Tracker: TAtlasBuildTargetTracker;
  Current: TAtlasBuildTarget;
begin
  Tracker := TAtlasBuildTargetTracker.Create;
  try
    Current := TAtlasBuildTarget.Create(Project, 'Debug', 'Win32', nil);
    Tracker.Decide(Current);
    Tracker.Reset;
    Assert.IsFalse(Tracker.Pending);
    Assert.IsTrue(Tracker.Decide(Current) = TAtlasBuildTargetAction.Query);
  finally
    Tracker.Free;
  end;
end;

procedure TAtlasBuildTargetTests.BuildsCommandArguments;
var
  Target: TAtlasBuildTarget;
  Arguments: TJSONArray;
  Options: TJSONObject;
  Defines: TJSONArray;
begin
  Target := TAtlasBuildTarget.Create(Project, 'Release', 'Win64', ['RELEASE', 'TRACE']);
  Arguments := Target.SelectArguments('file:///C:/P/App.dproj', TAtlasBuildTargetAction.Query);
  try
    Assert.AreEqual(1, Arguments.Count);
    Options := Arguments.Items[0] as TJSONObject;
    Assert.AreEqual('file:///C:/P/App.dproj', Options.GetValue<string>('uri'));
    Assert.IsNull(Options.GetValue('config'), 'Query fragt nur');
  finally
    Arguments.Free;
  end;
  Arguments := Target.SelectArguments('file:///C:/P/App.dproj', TAtlasBuildTargetAction.Select);
  try
    Options := Arguments.Items[0] as TJSONObject;
    Assert.AreEqual('Release', Options.GetValue<string>('config'));
    Assert.AreEqual('Win64', Options.GetValue<string>('platform'));
    Defines := Options.GetValue('defines') as TJSONArray;
    Assert.AreEqual(2, Defines.Count);
    Assert.AreEqual('TRACE', Defines.Items[1].Value);
  finally
    Arguments.Free;
  end;
end;

procedure TAtlasBuildTargetTests.ReadsServerSelection;
var
  Answer: TJSONValue;
  Config, Platform: string;
begin
  Answer := TJSONObject.ParseJSONValue('{"projects":[{"project":"C:\\P\\Lib.dproj","config":"Debug","platform":"Win32"},' +
    '{"project":"c:\\p\\app.dproj","config":"Release","platform":"Win64"}]}');
  try
    Assert.IsTrue(TAtlasBuildTarget.FromSelection(Answer, Project, Config, Platform));
    Assert.AreEqual('Release', Config);
    Assert.AreEqual('Win64', Platform);
    Assert.IsFalse(TAtlasBuildTarget.FromSelection(Answer, 'C:\P\Fremd.dproj', Config, Platform));
    Assert.IsFalse(TAtlasBuildTarget.FromSelection(nil, Project, Config, Platform));
  finally
    Answer.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBuildTargetTests);

end.
