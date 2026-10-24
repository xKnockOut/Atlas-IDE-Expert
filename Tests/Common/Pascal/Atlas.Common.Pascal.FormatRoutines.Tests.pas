unit Atlas.Common.Pascal.FormatRoutines.Tests;

// Tests der gemeinsamen Liste der Formatroutinen (#56, #451).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFormatRoutinesTests = class
  public
    [Test]
    procedure DefaultsKnowTheirFormatIndex;
    [Test]
    procedure SameTailFromDotBoundary;
    [Test]
    procedure CustomEntries;
  end;

implementation

uses
  Atlas.Common.Pascal.FormatRoutines;

procedure TFormatRoutinesTests.DefaultsKnowTheirFormatIndex;
var
  mRoutine: TFormatRoutine;
begin
  Assert.IsTrue(TFormatRoutines.FindQualified(TFormatRoutines.Defaults, 'System.SysUtils.Format', mRoutine));
  Assert.AreEqual(0, mRoutine.FormatIndex);
  Assert.IsFalse(mRoutine.IsMethod);
  Assert.IsTrue(TFormatRoutines.FindQualified(TFormatRoutines.Defaults, 'System.SysUtils.FormatBuf', mRoutine));
  Assert.AreEqual(2, mRoutine.FormatIndex);
  Assert.IsTrue(TFormatRoutines.FindQualified(TFormatRoutines.Defaults, 'System.SysUtils.Exception.CreateFmt',
    mRoutine));
  Assert.IsTrue(mRoutine.IsMethod);
  // Eine eigene Unit mit einer Routine Format ist keine Formatroutine der RTL.
  Assert.IsFalse(TFormatRoutines.FindQualified(TFormatRoutines.Defaults, 'Bericht.Format', mRoutine));
  Assert.IsFalse(TFormatRoutines.FindQualified(TFormatRoutines.Defaults, 'System.SysUtils.FormatFloat', mRoutine));
end;

procedure TFormatRoutinesTests.SameTailFromDotBoundary;
begin
  Assert.IsTrue(TFormatRoutines.SameTail('System.SysUtils.Format', 'SysUtils.Format'));
  Assert.IsTrue(TFormatRoutines.SameTail('Protokoll', 'Haupt.Protokoll'));
  Assert.IsTrue(TFormatRoutines.SameTail('tlogger.logfmt', 'Logs.TLogger.LogFmt'));
  Assert.IsFalse(TFormatRoutines.SameTail('System.SysUtils.Format', 'MyFormat'));
  Assert.IsFalse(TFormatRoutines.SameTail('Log', 'Haupt.Protokoll'));
end;

procedure TFormatRoutinesTests.CustomEntries;
var
  mRoutine: TFormatRoutine;
begin
  mRoutine := TFormatRoutines.Custom(' TLogger.LogFmt ', -1);
  Assert.AreEqual('TLogger.LogFmt', mRoutine.Name);
  Assert.IsTrue(mRoutine.IsMethod);
  Assert.AreEqual(-1, mRoutine.FormatIndex);
  mRoutine := TFormatRoutines.Custom('Protokoll', 1);
  Assert.IsFalse(mRoutine.IsMethod);
  Assert.AreEqual(1, mRoutine.FormatIndex);
end;

initialization
  TDUnitX.RegisterTestFixture(TFormatRoutinesTests);

end.
