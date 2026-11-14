unit Atlas.Common.Lsp.Protocol.Tests;

// Protokolltests: spielt alle Aufzeichnungen aus Tests\Data\Protocol ab.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspProtocolTests = class
  public
    [Test]
    procedure ReplaysAllRecordings;
    [Test]
    procedure MismatchReportsFirstDifference;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Lsp.ProtocolReplay;

{ TLspProtocolTests }

procedure TLspProtocolTests.ReplaysAllRecordings;
var
  mFileName: string;
  mRecording: TJSONValue;
  mReplay: TProtocolReplay;
  mCount: Integer;
begin
  mCount := 0;
  for mFileName in TDirectory.GetFiles(TProtocolReplay.DataDirectory, '*.json') do
  begin
    mRecording := TJSONObject.ParseJSONValue(TFile.ReadAllText(mFileName, TEncoding.UTF8));
    try
      Assert.IsTrue(mRecording is TJSONObject, 'Kein JSON-Objekt: ' + mFileName);
      mReplay := TProtocolReplay.Create;
      try
        try
          mReplay.Run(TJSONObject(mRecording));
        except
          on E: EProtocolMismatch do
            Assert.Fail(ExtractFileName(mFileName) + ': ' + E.Message);
        end;
      finally
        mReplay.Free;
      end;
    finally
      mRecording.Free;
    end;
    Inc(mCount);
  end;
  Assert.IsTrue(mCount > 0, 'Keine Aufzeichnungen gefunden');
end;

procedure TLspProtocolTests.MismatchReportsFirstDifference;
var
  mExpected: TJSONValue;
  mActual: TJSONValue;
begin
  mExpected := TJSONObject.ParseJSONValue('{"id":1,"result":{"items":[1,2]}}');
  mActual := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","id":1,"result":{"items":[1,3],"more":true}}');
  try
    Assert.AreEqual('$.result.items[1]: 2 erwartet, 3 gefunden', TProtocolReplay.Mismatch(mExpected, mActual, '$'));
    Assert.AreEqual('', TProtocolReplay.Mismatch(mExpected, mExpected, '$'));
  finally
    mActual.Free;
    mExpected.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspProtocolTests);

end.
