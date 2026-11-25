unit Atlas.Common.Semantics.SymbolPath.Request.Tests;

// Tests der Anfrage der Pfadsuche (#1117): Argumente lesen und ablehnen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TSymbolPathRequestsTests = class
  public
    [Test]
    procedure ReadsRequest;
    [Test]
    procedure RejectsInvalidRequest;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Semantics.SymbolPath.Search,
  Atlas.Common.Semantics.SymbolPath.Request;

function ParamsOf(const AJson: string): TJSONObject;
begin
  Result := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
end;

{ TSymbolPathRequestsTests }

procedure TSymbolPathRequestsTests.ReadsRequest;
var
  mParams: TJSONObject;
  mRequest: TSymbolPathRequest;
begin
  mParams := ParamsOf('{"from":"uA","to":"uC","via":["uses","library"],"maxSteps":3,"all":true}');
  try
    mRequest := TSymbolPathRequests.Read(mParams);
    Assert.AreEqual('uA', mRequest.From);
    Assert.AreEqual('uC', mRequest.To_);
    Assert.AreEqual<TSymbolPathEdgeKinds>([TSymbolPathEdgeKind.Uses_], mRequest.Via);
    Assert.IsTrue(mRequest.ThroughLibrary);
    Assert.AreEqual(3, mRequest.MaxSteps);
    Assert.IsTrue(mRequest.All);
  finally
    mParams.Free;
  end;
  // Ohne via: alle Kantenarten, Bibliothek kein Durchgang, Vorgabe 8 Schritte.
  mParams := ParamsOf('{"from":"uA","to":"uC"}');
  try
    mRequest := TSymbolPathRequests.Read(mParams);
    Assert.AreEqual<TSymbolPathEdgeKinds>(cAllSymbolPathEdges, mRequest.Via);
    Assert.IsFalse(mRequest.ThroughLibrary);
    Assert.AreEqual(TSymbolPathRequest.cDefaultSteps, mRequest.MaxSteps);
    Assert.IsFalse(mRequest.All);
  finally
    mParams.Free;
  end;
end;

procedure TSymbolPathRequestsTests.RejectsInvalidRequest;
const
  cInvalid: array[0..3] of string = ('{"from":"uA"}', '{"from":"uA","to":"uC","via":["foo"]}',
    '{"from":"uA","to":"uC","maxSteps":0}', '{"from":"uA","to":"uC","maxSteps":17}');
var
  mItem: string;
  mParams: TJSONObject;
begin
  for mItem in cInvalid do
  begin
    mParams := ParamsOf(mItem);
    try
      Assert.WillRaise(
        procedure
        begin
          TSymbolPathRequests.Read(mParams);
        end, EJsonRpcError, mItem);
    finally
      mParams.Free;
    end;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TSymbolPathRequestsTests);

end.
