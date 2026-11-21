unit Atlas.Text.Reporting.Tests;

// Melder ohne Empfänger für ihren eigenen Fehler: Aufruf, Ausnahme endet still und zählt, nil bleibt ohne Folgen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TReportingTests = class
  public
    [Test]
    procedure QuietlyCallsReport;
    [Test]
    procedure QuietlyCountsFailedReport;
    [Test]
    procedure QuietlyIgnoresNil;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.Reporting;

{ TReportingTests }

procedure TReportingTests.QuietlyCallsReport;
var
  mCalled: Boolean;
  mLost: Integer;
begin
  mCalled := False;
  mLost := TReporting.Lost;
  TReporting.Quietly(
    procedure
    begin
      mCalled := True;
    end);
  Assert.IsTrue(mCalled);
  Assert.AreEqual(mLost, TReporting.Lost, 'gelungene Meldung zählt nicht');
end;

procedure TReportingTests.QuietlyCountsFailedReport;
var
  mLost: Integer;
begin
  mLost := TReporting.Lost;
  TReporting.Quietly(
    procedure
    begin
      raise EInOutError.Create('Senke voll');
    end);
  Assert.AreEqual(mLost + 1, TReporting.Lost, 'gescheiterte Meldung zählt');
end;

procedure TReportingTests.QuietlyIgnoresNil;
var
  mLost: Integer;
begin
  mLost := TReporting.Lost;
  TReporting.Quietly(nil);
  Assert.AreEqual(mLost, TReporting.Lost);
end;

initialization
  TDUnitX.RegisterTestFixture(TReportingTests);

end.
