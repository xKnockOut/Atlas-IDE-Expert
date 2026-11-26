unit Adapters.Mcp.BoundaryCases.Tests;

// Tests für den Host-Adapter zwischen Mcp und Editing (suggest_test_cases): Text, Anfrage und Bericht gehen
// unverändert durch.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpBoundaryCasesAdapterTests = class
  public
    [Test]
    procedure PassesRequestAndReport;
  end;

implementation

uses
  Atlas.Common.Mcp.Contract.BoundaryCases,
  Atlas.Common.Editing.Contract.BoundaryCases,
  Adapters.Mcp.BoundaryCases;

type
  /// <summary>Merkt die Anfrage und antwortet fest.</summary>
  TFakeBoundaryCases = class(TInterfacedObject, IEditingBoundaryCases)
  public
    Request: TEditingBoundaryRequest;
    function Report(const ARequest: TEditingBoundaryRequest; out AReport: string): Boolean;
  end;

function TFakeBoundaryCases.Report(const ARequest: TEditingBoundaryRequest; out AReport: string): Boolean;
begin
  Request := ARequest;
  AReport := 'Bericht';
  Result := ARequest.Routine <> '';
end;

{ TMcpBoundaryCasesAdapterTests }

procedure TMcpBoundaryCasesAdapterTests.PassesRequestAndReport;
var
  mFake: TFakeBoundaryCases;
  mEditing: IEditingBoundaryCases;
  mAdapter: IMcpBoundaryCases;
  mRequest: TMcpBoundaryRequest;
  mReport: string;
begin
  mFake := TFakeBoundaryCases.Create;
  mEditing := mFake;
  mAdapter := TMcpBoundaryCasesAdapter.Create(mEditing);
  mRequest := Default(TMcpBoundaryRequest);
  mRequest.FileName := 'Src/U.pas';
  mRequest.Line := 4;
  mRequest.Routine := 'TFoo.Bar';
  mRequest.Max := 7;
  mRequest.Json := True;
  Assert.IsTrue(mAdapter.Report('unit U;', mRequest, mReport));
  Assert.AreEqual('Bericht', mReport);
  Assert.AreEqual('unit U;', mFake.Request.Text);
  Assert.AreEqual('Src/U.pas', mFake.Request.FileName);
  Assert.AreEqual(4, mFake.Request.Line);
  Assert.AreEqual('TFoo.Bar', mFake.Request.Routine);
  Assert.AreEqual(7, mFake.Request.Max);
  Assert.IsTrue(mFake.Request.Json);
  mRequest.Routine := '';
  Assert.IsFalse(mAdapter.Report('unit U;', mRequest, mReport));
end;

end.
