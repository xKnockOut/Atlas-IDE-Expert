unit Adapters.Lsp.OwnershipReport.Tests;

// Tests für den Host-Adapter, der dem Sprachserver die Antwort von atlas.server.ownership aus den Prüfregeln gibt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspOwnershipReportAdapterTests = class
  public
    [Test]
    procedure DelegatesToRules;
    [Test]
    procedure WrapOfNilIsNil;
  end;

implementation

uses
  System.JSON,
  Atlas.Common.Lsp.Contract,
  Rules.Contract.Api,
  Rules.Providers.OwnershipReport,
  Adapters.Lsp.OwnershipReport;

const
  cUri = 'file:///C:/P/U.pas';

{ TLspOwnershipReportAdapterTests }

procedure TLspOwnershipReportAdapterTests.DelegatesToRules;
var
  mRules: IRuleOwnershipReport;
  mLsp: ILspOwnershipReport;
  mAnswer: TJSONObject;
begin
  mRules := TRuleOwnershipReport.Create(nil);
  mLsp := TLspOwnershipReportAdapter.Wrap(mRules);
  mAnswer := mLsp.Report(cUri);
  try
    Assert.AreEqual(cUri, mAnswer.GetValue('uri').Value);
    Assert.AreEqual(0, Integer((mAnswer.GetValue('sites') as TJSONArray).Count));
  finally
    mAnswer.Free;
  end;
end;

procedure TLspOwnershipReportAdapterTests.WrapOfNilIsNil;
var
  mLsp: IInterface;
begin
  mLsp := TLspOwnershipReportAdapter.Wrap(nil);
  Assert.IsNull(mLsp);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspOwnershipReportAdapterTests);

end.
