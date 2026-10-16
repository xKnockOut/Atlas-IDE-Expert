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
  Ids: TArray<Cardinal>;
  Id: Cardinal;
  Found: Boolean;
begin
  // Groß- und Kleinschreibung egal.
  Ids := TProcessInstances.IdsOf(UpperCase(ExtractFileName(ParamStr(0))));
  Found := False;
  for Id in Ids do
    if Id = GetCurrentProcessId then
      Found := True;
  Assert.IsTrue(Found, 'eigener Prozess fehlt');
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
