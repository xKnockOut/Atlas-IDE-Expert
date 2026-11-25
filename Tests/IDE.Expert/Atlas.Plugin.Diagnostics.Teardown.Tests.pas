unit Atlas.Plugin.Diagnostics.Teardown.Tests;

// Abbau in Schritten (#886): Eine Ausnahme hält die folgenden Schritte nicht an.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTeardownTests = class
  public
    [Test]
    procedure RunsAllStepsAfterFailure;
    [Test]
    procedure SummaryWithoutFailures;
    [Test]
    procedure KeepsOnlyClassNotMessage;
    [Test]
    procedure AddsForeignFailures;
    /// <summary>Die Ausnahme eines Schritts geht samt Ort an die Senke von TReporting (Protokoll mit Stacktrace).
    /// </summary>
    [Test]
    procedure ReportsFailureWithStep;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.Reporting,
  Atlas.Plugin.Diagnostics.Teardown;

{ TTeardownTests }

procedure TTeardownTests.RunsAllStepsAfterFailure;
var
  mTeardown: TAtlasTeardown;
  mLog: string;
begin
  mLog := '';
  mTeardown := TAtlasTeardown.Create;
  mTeardown.Step('A',
    procedure
    begin
      mLog := mLog + 'A';
    end);
  mTeardown.Step('B',
    procedure
    begin
      raise EArgumentException.Create('kaputt');
    end);
  mTeardown.Step('C',
    procedure
    begin
      mLog := mLog + 'C';
    end);
  Assert.AreEqual('AC', mLog);
  Assert.AreEqual(1, Integer(Length(mTeardown.Failures)));
  Assert.AreEqual('B: EArgumentException', mTeardown.Summary);
end;

procedure TTeardownTests.SummaryWithoutFailures;
var
  mTeardown: TAtlasTeardown;
begin
  mTeardown := TAtlasTeardown.Create;
  mTeardown.Step('A', nil);
  Assert.AreEqual('keine', mTeardown.Summary);
  Assert.AreEqual(0, Integer(Length(mTeardown.Failures)));
end;

procedure TTeardownTests.KeepsOnlyClassNotMessage;
var
  mTeardown: TAtlasTeardown;
begin
  // Anonymes Protokoll: Der Meldungstext kann Pfade enthalten.
  mTeardown := TAtlasTeardown.Create;
  mTeardown.Step('Datei',
    procedure
    begin
      raise EFileNotFoundException.Create('C:\Users\Name\geheim.pas');
    end);
  Assert.AreEqual('Datei: EFileNotFoundException', mTeardown.Summary);
  Assert.IsFalse(mTeardown.Summary.Contains('geheim'));
end;

procedure TTeardownTests.AddsForeignFailures;
var
  mTeardown: TAtlasTeardown;
  mForeign: TArray<string>;
begin
  mTeardown := TAtlasTeardown.Create;
  mForeign := nil;
  SetLength(mForeign, 1);
  mForeign[0] := 'Feature: EAccessViolation';
  mTeardown.AddFailures(mForeign);
  mTeardown.Step('B',
    procedure
    begin
      raise EAbort.Create('');
    end);
  Assert.AreEqual('Feature: EAccessViolation, B: EAbort', mTeardown.Summary);
end;

procedure TTeardownTests.ReportsFailureWithStep;
var
  mTeardown: TAtlasTeardown;
  mOld: TReportingSink;
  mSeen: string;
begin
  mSeen := '';
  mTeardown := TAtlasTeardown.Create;
  mOld := TReporting.ReplaceSink(
    procedure(const AWhere: string; AE: Exception)
    begin
      mSeen := mSeen + AWhere + ': ' + AE.ClassName + ';';
    end);
  try
    mTeardown.Step('StatusField',
      procedure
      begin
        raise EAccessViolation.Create('Zugriffsverletzung');
      end);
    mTeardown.Step('Options', nil);
  finally
    TReporting.ReplaceSink(mOld);
  end;
  Assert.AreEqual('Abbau StatusField: EAccessViolation;', mSeen);
  Assert.AreEqual('StatusField: EAccessViolation', mTeardown.Summary);
  mSeen := '';
end;

initialization
  TDUnitX.RegisterTestFixture(TTeardownTests);

end.
