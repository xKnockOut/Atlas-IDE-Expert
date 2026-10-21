unit Atlas.Core.Diagnostics.Teardown.Tests;

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
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Diagnostics.Teardown;

procedure TTeardownTests.RunsAllStepsAfterFailure;
var
  Teardown: TAtlasTeardown;
  Log: string;
begin
  Log := '';
  Teardown := TAtlasTeardown.Create;
  Teardown.Step('A',
    procedure
    begin
      Log := Log + 'A';
    end);
  Teardown.Step('B',
    procedure
    begin
      raise EArgumentException.Create('kaputt');
    end);
  Teardown.Step('C',
    procedure
    begin
      Log := Log + 'C';
    end);
  Assert.AreEqual('AC', Log);
  Assert.AreEqual(1, Integer(Length(Teardown.Failures)));
  Assert.AreEqual('B: EArgumentException', Teardown.Summary);
end;

procedure TTeardownTests.SummaryWithoutFailures;
var
  Teardown: TAtlasTeardown;
begin
  Teardown := TAtlasTeardown.Create;
  Teardown.Step('A', nil);
  Assert.AreEqual('keine', Teardown.Summary);
  Assert.AreEqual(0, Integer(Length(Teardown.Failures)));
end;

procedure TTeardownTests.KeepsOnlyClassNotMessage;
var
  Teardown: TAtlasTeardown;
begin
  // Anonymes Protokoll: Der Meldungstext kann Pfade enthalten.
  Teardown := TAtlasTeardown.Create;
  Teardown.Step('Datei',
    procedure
    begin
      raise EFileNotFoundException.Create('C:\Users\Name\geheim.pas');
    end);
  Assert.AreEqual('Datei: EFileNotFoundException', Teardown.Summary);
  Assert.IsFalse(Teardown.Summary.Contains('geheim'));
end;

procedure TTeardownTests.AddsForeignFailures;
var
  Teardown: TAtlasTeardown;
  Foreign: TArray<string>;
begin
  Teardown := TAtlasTeardown.Create;
  Foreign := nil;
  SetLength(Foreign, 1);
  Foreign[0] := 'Feature: EAccessViolation';
  Teardown.AddFailures(Foreign);
  Teardown.Step('B',
    procedure
    begin
      raise EAbort.Create('');
    end);
  Assert.AreEqual('Feature: EAccessViolation, B: EAbort', Teardown.Summary);
end;

initialization
  TDUnitX.RegisterTestFixture(TTeardownTests);

end.
