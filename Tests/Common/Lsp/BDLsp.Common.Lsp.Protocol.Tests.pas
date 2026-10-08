unit BDLsp.Common.Lsp.Protocol.Tests;

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
  BDLsp.Common.Lsp.ProtocolReplay;

{ TLspProtocolTests }

procedure TLspProtocolTests.ReplaysAllRecordings;
var
  FileName: string;
  Recording: TJSONValue;
  Replay: TProtocolReplay;
  Count: Integer;
begin
  Count := 0;
  for FileName in TDirectory.GetFiles(TProtocolReplay.DataDirectory, '*.json') do
  begin
    Recording := TJSONObject.ParseJSONValue(TFile.ReadAllText(FileName, TEncoding.UTF8));
    try
      Assert.IsTrue(Recording is TJSONObject, 'Kein JSON-Objekt: ' + FileName);
      Replay := TProtocolReplay.Create;
      try
        try
          Replay.Run(TJSONObject(Recording));
        except
          on E: EProtocolMismatch do
            Assert.Fail(ExtractFileName(FileName) + ': ' + E.Message);
        end;
      finally
        Replay.Free;
      end;
    finally
      Recording.Free;
    end;
    Inc(Count);
  end;
  Assert.IsTrue(Count > 0, 'Keine Aufzeichnungen gefunden');
end;

procedure TLspProtocolTests.MismatchReportsFirstDifference;
var
  Expected: TJSONValue;
  Actual: TJSONValue;
begin
  Expected := TJSONObject.ParseJSONValue('{"id":1,"result":{"items":[1,2]}}');
  Actual := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","id":1,"result":{"items":[1,3],"more":true}}');
  try
    Assert.AreEqual('$.result.items[1]: 2 erwartet, 3 gefunden', TProtocolReplay.Mismatch(Expected, Actual, '$'));
    Assert.AreEqual('', TProtocolReplay.Mismatch(Expected, Expected, '$'));
  finally
    Actual.Free;
    Expected.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspProtocolTests);

end.
