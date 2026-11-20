unit Atlas.Core.Foundation.Calls.Tests;

// Tests zu TAtlasCalls: gesetzte Rückrufe laufen, nicht gesetzte nicht.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasCallsTests = class
  public
    [Test]
    procedure CallRunsAssignedProc;
    [Test]
    procedure CallWithoutProcDoesNothing;
    [Test]
    procedure SendPassesText;
    [Test]
    procedure SendWithoutSinkDoesNothing;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Foundation.Calls;

procedure TAtlasCallsTests.CallRunsAssignedProc;
var
  mCount: Integer;
begin
  mCount := 0;
  TAtlasCalls.Call(
    procedure
    begin
      Inc(mCount);
    end);
  Assert.AreEqual(1, mCount);
end;

procedure TAtlasCallsTests.CallWithoutProcDoesNothing;
var
  mProc: TProc;
begin
  mProc := nil;
  TAtlasCalls.Call(mProc);
  Assert.Pass('ohne Rückruf keine Ausnahme');
end;

procedure TAtlasCallsTests.SendPassesText;
var
  mText: string;
begin
  mText := '';
  TAtlasCalls.Send(
    procedure(AText: string)
    begin
      mText := mText + AText + ';';
    end, 'Größe');
  Assert.AreEqual('Größe;', mText);
  mText := '';
end;

procedure TAtlasCallsTests.SendWithoutSinkDoesNothing;
var
  mSink: TProc<string>;
begin
  mSink := nil;
  TAtlasCalls.Send(mSink, 'x');
  Assert.Pass('ohne Meldungsziel keine Ausnahme');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasCallsTests);

end.
