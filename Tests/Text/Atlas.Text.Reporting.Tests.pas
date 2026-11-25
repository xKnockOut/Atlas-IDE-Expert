unit Atlas.Text.Reporting.Tests;

// Melder ohne Empfänger für ihren eigenen Fehler: Aufruf, Ausnahme endet still und zählt, nil bleibt ohne Folgen.
// Failed: Fehler an die eingetragene Senke; ohne Senke oder bei scheiternder Senke zählt er.

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
    [Test]
    procedure FailedGoesToSink;
    [Test]
    procedure FailedWithoutSinkCounts;
    [Test]
    procedure FailedSinkErrorCounts;
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

procedure SinkRaises(const AWhere: string; AE: Exception);
begin
  raise EInOutError.Create('Senke voll');
end;

procedure TReportingTests.FailedGoesToSink;
var
  mOld, mSink: TReportingSink;
  mWhere, mMessage: string;
  mError: Exception;
  mLost: Integer;
begin
  mSink :=
    procedure(const AWhere: string; AE: Exception)
    begin
      mWhere := AWhere;
      mMessage := AE.Message;
    end;
  mOld := TReporting.ReplaceSink(mSink);
  mError := EInOutError.Create('kaputt');
  try
    mLost := TReporting.Lost;
    TReporting.Failed('Beobachter', mError);
    Assert.AreEqual('Beobachter', mWhere);
    Assert.AreEqual('kaputt', mMessage);
    Assert.AreEqual(mLost, TReporting.Lost, 'angekommene Meldung zählt nicht');
  finally
    mError.Free;
    TReporting.ReplaceSink(mOld);
  end;
  mWhere := '';
  mMessage := '';
end;

procedure TReportingTests.FailedWithoutSinkCounts;
var
  mOld: TReportingSink;
  mError: Exception;
  mLost: Integer;
begin
  mOld := TReporting.ReplaceSink(nil);
  mError := EInOutError.Create('kaputt');
  try
    mLost := TReporting.Lost;
    TReporting.Failed('Beobachter', mError);
    Assert.AreEqual(mLost + 1, TReporting.Lost);
  finally
    mError.Free;
    TReporting.ReplaceSink(mOld);
  end;
end;

procedure TReportingTests.FailedSinkErrorCounts;
var
  mOld: TReportingSink;
  mError: Exception;
  mLost: Integer;
begin
  mOld := TReporting.ReplaceSink(SinkRaises);
  mError := EInOutError.Create('kaputt');
  try
    mLost := TReporting.Lost;
    TReporting.Failed('Beobachter', mError);
    Assert.AreEqual(mLost + 1, TReporting.Lost, 'gescheiterte Senke zählt');
  finally
    mError.Free;
    TReporting.ReplaceSink(mOld);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TReportingTests);

end.
