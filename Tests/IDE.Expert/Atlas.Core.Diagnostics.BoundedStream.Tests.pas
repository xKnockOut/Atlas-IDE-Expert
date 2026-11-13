unit Atlas.Core.Diagnostics.BoundedStream.Tests;

// Antwort-Stream mit Größengrenze (Code-Review F-105): bis zur Grenze wie
// TBytesStream, darüber Ausnahme ohne zu schreiben.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasBoundedStreamTests = class
  public
    [Test]
    procedure WritesUpToLimit;
    [Test]
    procedure RaisesBeyondLimitWithoutWriting;
    [Test]
    procedure ClearAllowsWritingAgain;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Diagnostics.BoundedStream;

procedure TAtlasBoundedStreamTests.WritesUpToLimit;
var
  mStream: TAtlasBoundedStream;
  mBytes: TBytes;
begin
  mBytes := TEncoding.UTF8.GetBytes('abcd');
  mStream := TAtlasBoundedStream.Create(8);
  try
    mStream.WriteBuffer(mBytes[0], Length(mBytes));
    mStream.WriteBuffer(mBytes[0], Length(mBytes));
    Assert.AreEqual(8, Integer(mStream.Size));
    Assert.IsFalse(mStream.Exceeded);
  finally
    mStream.Free;
  end;
  mBytes := nil;
end;

procedure TAtlasBoundedStreamTests.RaisesBeyondLimitWithoutWriting;
var
  mStream: TAtlasBoundedStream;
  mBytes: TBytes;
begin
  mBytes := TEncoding.UTF8.GetBytes('abcdef');
  mStream := TAtlasBoundedStream.Create(8);
  try
    mStream.WriteBuffer(mBytes[0], Length(mBytes));
    Assert.WillRaise(
      procedure
      begin
        mStream.WriteBuffer(mBytes[0], Length(mBytes));
      end, EAtlasStreamLimit);
    Assert.IsTrue(mStream.Exceeded);
    Assert.AreEqual(6, Integer(mStream.Size));
  finally
    mStream.Free;
  end;
  mBytes := nil;
end;

procedure TAtlasBoundedStreamTests.ClearAllowsWritingAgain;
var
  mStream: TAtlasBoundedStream;
  mBytes: TBytes;
begin
  mBytes := TEncoding.UTF8.GetBytes('abcdef');
  mStream := TAtlasBoundedStream.Create(8);
  try
    mStream.WriteBuffer(mBytes[0], Length(mBytes));
    mStream.Clear;
    mStream.WriteBuffer(mBytes[0], Length(mBytes));
    Assert.AreEqual(6, Integer(mStream.Size));
    Assert.IsFalse(mStream.Exceeded);
  finally
    mStream.Free;
  end;
  mBytes := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBoundedStreamTests);

end.
