unit Atlas.Windows.Process.Instances.Tests;

// Tests für laufende Prozesse nach Programmname (#261): Vor dem Start der
// eigenen IDE merkt sich der Server alle laufenden bds.exe.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TProcessInstancesTests = class
  public
    [Test]
    procedure FindsOwnProcess;
    [Test]
    procedure UnknownProgramHasNoInstances;
    [Test]
    procedure OwnProcessIsRunning;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  Atlas.Windows.Process.Instances;

procedure TProcessInstancesTests.FindsOwnProcess;
var
  mIds: TArray<Cardinal>;
  mId: Cardinal;
  mFound: Boolean;
begin
  // Groß- und Kleinschreibung egal.
  mIds := TProcessInstances.IdsOf(UpperCase(ExtractFileName(ParamStr(0))));
  mFound := False;
  for mId in mIds do
  begin
    if mId = GetCurrentProcessId then
    begin
      mFound := True;
    end;
  end;
  Assert.IsTrue(mFound, 'eigener Prozess fehlt');
end;

procedure TProcessInstancesTests.UnknownProgramHasNoInstances;
begin
  Assert.AreEqual(0, Integer(Length(TProcessInstances.IdsOf('atlas-gibt-es-nicht-261.exe'))));
end;

procedure TProcessInstancesTests.OwnProcessIsRunning;
begin
  Assert.IsTrue(TProcessInstances.Running(GetCurrentProcessId));
  Assert.IsFalse(TProcessInstances.Running(0));
end;

initialization
  TDUnitX.RegisterTestFixture(TProcessInstancesTests);

end.
