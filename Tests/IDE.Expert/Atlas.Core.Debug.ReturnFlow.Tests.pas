unit Atlas.Core.Debug.ReturnFlow.Tests;

// Tests für den Ablauf beim Abholen der Rückgabewerte (#844): über eine Zeile mit Rückkehr und Fortsetzen, bis zur
// Rückkehr, Rekursion (tiefere Rahmen laufen weiter) und Halte, die dem Benutzer gehören.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Debug.ReturnFlow;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasReturnFlowTests = class
  private
    FFlow: TAtlasReturnFlow;
    procedure StartStepOver;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure StepOverEvaluatesReturnsAndContinues;
    [Test]
    procedure DeeperFrameResumes;
    [Test]
    procedure ShallowerFrameAtWatchPasses;
    [Test]
    procedure OtherStopPasses;
    [Test]
    procedure UnknownDepthPasses;
    [Test]
    procedure ReturnLandingElsewherePasses;
    [Test]
    procedure RunUntilReturnUsesOwnFrame;
    [Test]
    procedure StartWithoutWatchesStaysIdle;
    [Test]
    procedure RoundsAreLimited;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Debug.ReturnValues;

function Watch(const AName, AFileName: string; AEndLine: Integer): TAtlasReturnWatch;
begin
  Result.Name := AName;
  Result.FileName := AFileName;
  Result.EndLine := AEndLine;
end;

function Stop(const AFileName: string; ALine, ADepth: Integer): TAtlasReturnStop;
begin
  Result := TAtlasReturnStop.Create(AFileName, ALine, ADepth);
end;

{ TAtlasReturnFlowTests }

procedure TAtlasReturnFlowTests.Setup;
begin
  FFlow := TAtlasReturnFlow.Create;
end;

procedure TAtlasReturnFlowTests.TearDown;
begin
  FreeAndNil(FFlow);
end;

procedure TAtlasReturnFlowTests.StartStepOver;
begin
  // F8 in Kasse.pas Zeile 40 auf Tiefe 3; die Zeile ruft BerechneNetto (end in Zeile 12) und Runden (end in 23).
  FFlow.Start(TAtlasReturnMode.StepOver, Stop('Kasse.pas', 40, 3),
    TArray<TAtlasReturnWatch>.Create(Watch('BerechneNetto', 'Preise.pas', 12), Watch('Runden', 'Preise.pas', 23)));
end;

procedure TAtlasReturnFlowTests.StepOverEvaluatesReturnsAndContinues;
begin
  StartStepOver;
  Assert.IsTrue(FFlow.Active);
  Assert.AreEqual<TAtlasReturnAction>(TAtlasReturnAction.Evaluate, FFlow.Stopped(Stop('preise.pas', 12, 4)));
  Assert.AreEqual('BerechneNetto', FFlow.Current.Name);
  Assert.AreEqual<TAtlasReturnAction>(TAtlasReturnAction.Return, FFlow.Returned);
  // Zurück in der Aufrufzeile: weiter über die Zeile, die zweite Funktion folgt.
  Assert.AreEqual<TAtlasReturnAction>(TAtlasReturnAction.StepOver, FFlow.Stopped(Stop('Kasse.pas', 40, 3)));
  Assert.AreEqual<TAtlasReturnAction>(TAtlasReturnAction.Evaluate, FFlow.Stopped(Stop('Preise.pas', 23, 4)));
  Assert.AreEqual('Runden', FFlow.Current.Name);
  Assert.AreEqual<TAtlasReturnAction>(TAtlasReturnAction.Return, FFlow.Returned);
  Assert.AreEqual<TAtlasReturnAction>(TAtlasReturnAction.StepOver, FFlow.Stopped(Stop('Kasse.pas', 40, 3)));
  // Der Schritt endet in der nächsten Zeile: Der Halt gehört dem Benutzer.
  Assert.AreEqual<TAtlasReturnAction>(TAtlasReturnAction.Pass, FFlow.Stopped(Stop('Kasse.pas', 41, 3)));
  Assert.IsFalse(FFlow.Active);
  Assert.AreEqual(0, Integer(Length(FFlow.Watches)));
end;

procedure TAtlasReturnFlowTests.DeeperFrameResumes;
begin
  StartStepOver;
  // Rekursion: tiefere Rahmen derselben Funktion laufen weiter.
  Assert.AreEqual<TAtlasReturnAction>(TAtlasReturnAction.Resume, FFlow.Stopped(Stop('Preise.pas', 12, 7)));
  Assert.AreEqual<TAtlasReturnAction>(TAtlasReturnAction.Resume, FFlow.Stopped(Stop('Preise.pas', 12, 5)));
  Assert.AreEqual<TAtlasReturnAction>(TAtlasReturnAction.Evaluate, FFlow.Stopped(Stop('Preise.pas', 12, 4)));
end;

procedure TAtlasReturnFlowTests.ShallowerFrameAtWatchPasses;
begin
  StartStepOver;
  Assert.AreEqual<TAtlasReturnAction>(TAtlasReturnAction.Pass, FFlow.Stopped(Stop('Preise.pas', 12, 3)));
  Assert.IsFalse(FFlow.Active);
end;

procedure TAtlasReturnFlowTests.OtherStopPasses;
begin
  StartStepOver;
  // Haltepunkt des Benutzers in der Funktion: greift wie gewohnt.
  Assert.AreEqual<TAtlasReturnAction>(TAtlasReturnAction.Pass, FFlow.Stopped(Stop('Preise.pas', 11, 4)));
  Assert.IsFalse(FFlow.Active);
  // Ohne Ablauf gehört jeder Halt dem Benutzer.
  Assert.AreEqual<TAtlasReturnAction>(TAtlasReturnAction.Pass, FFlow.Stopped(Stop('Preise.pas', 12, 4)));
  Assert.AreEqual<TAtlasReturnAction>(TAtlasReturnAction.Pass, FFlow.Returned);
end;

procedure TAtlasReturnFlowTests.UnknownDepthPasses;
begin
  StartStepOver;
  Assert.AreEqual<TAtlasReturnAction>(TAtlasReturnAction.Pass, FFlow.Stopped(Stop('Preise.pas', 12, -1)));
end;

procedure TAtlasReturnFlowTests.ReturnLandingElsewherePasses;
begin
  StartStepOver;
  Assert.AreEqual<TAtlasReturnAction>(TAtlasReturnAction.Evaluate, FFlow.Stopped(Stop('Preise.pas', 12, 4)));
  Assert.AreEqual<TAtlasReturnAction>(TAtlasReturnAction.Return, FFlow.Returned);
  Assert.AreEqual<TAtlasReturnAction>(TAtlasReturnAction.Pass, FFlow.Stopped(Stop('Kasse.pas', 41, 3)));
  Assert.IsFalse(FFlow.Active);
end;

procedure TAtlasReturnFlowTests.RunUntilReturnUsesOwnFrame;
begin
  // Umschalt+F8 in IstRabattfaehig (end in Zeile 30) auf Tiefe 4.
  FFlow.Start(TAtlasReturnMode.RunUntilReturn, Stop('Preise.pas', 27, 4),
    TArray<TAtlasReturnWatch>.Create(Watch('IstRabattfaehig', 'Preise.pas', 30)));
  Assert.AreEqual<TAtlasReturnAction>(TAtlasReturnAction.Resume, FFlow.Stopped(Stop('Preise.pas', 30, 5)));
  Assert.AreEqual<TAtlasReturnAction>(TAtlasReturnAction.Evaluate, FFlow.Stopped(Stop('Preise.pas', 30, 4)));
  Assert.AreEqual<TAtlasReturnAction>(TAtlasReturnAction.Return, FFlow.Returned);
  // Halt in der Aufrufzeile: Ende, die Anzeige gehört dorthin.
  Assert.AreEqual<TAtlasReturnAction>(TAtlasReturnAction.Pass, FFlow.Stopped(Stop('Kasse.pas', 40, 3)));
  Assert.AreEqual<TAtlasReturnMode>(TAtlasReturnMode.RunUntilReturn, FFlow.Mode);
end;

procedure TAtlasReturnFlowTests.StartWithoutWatchesStaysIdle;
begin
  FFlow.Start(TAtlasReturnMode.StepOver, Stop('Kasse.pas', 40, 3), nil);
  Assert.IsFalse(FFlow.Active);
  FFlow.Start(TAtlasReturnMode.StepOver, Stop('Kasse.pas', 40, -1),
    TArray<TAtlasReturnWatch>.Create(Watch('BerechneNetto', 'Preise.pas', 12)));
  Assert.IsFalse(FFlow.Active);
end;

procedure TAtlasReturnFlowTests.RoundsAreLimited;
var
  mIndex: Integer;
begin
  StartStepOver;
  for mIndex := 1 to TAtlasReturnFlow.cMaxRounds do
  begin
    Assert.AreEqual<TAtlasReturnAction>(TAtlasReturnAction.Resume, FFlow.Stopped(Stop('Preise.pas', 12, 9)));
  end;
  Assert.AreEqual<TAtlasReturnAction>(TAtlasReturnAction.Pass, FFlow.Stopped(Stop('Preise.pas', 12, 9)));
  Assert.IsFalse(FFlow.Active);
end;

end.
