unit Atlas.Common.Rules.Providers.InheritanceDepths.Tests;

// Tests des Anbieters der Vererbungstiefe (#980) für andere Features: dieselben Werte wie die Regel
// metric-inheritance-depth, mit und ohne Index.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRuleInheritanceDepthsTests = class
  public
    [Test]
    procedure DepthsWithinFile;
    [Test]
    procedure UnitWithoutClassesHasNone;
  end;

implementation

uses
  Atlas.Common.Metrics.Contract,
  Atlas.Common.Rules.Contract.Api,
  Atlas.Common.Rules.Providers.InheritanceDepths;

const
  cFile = 'C:\P\Kette.pas';
  cKette = 'unit Kette;'#10'interface'#10'type'#10'  TA = class'#10'  end;'#10'  TB = class(TA)'#10'  end;'#10 +
    '  TC = class(TB)'#10'  end;'#10'implementation'#10'end.';

{ TRuleInheritanceDepthsTests }

procedure TRuleInheritanceDepthsTests.DepthsWithinFile;
var
  mDepths: IRuleInheritanceDepths;
  mItems: TArray<TStructureMetrics>;
begin
  mDepths := TRuleInheritanceDepths.Create;
  mItems := mDepths.Depths(cFile, cKette, nil);
  // TA hat keine eigenen Vorfahren und fehlt; TB erbt von TA, TC von TB und TA.
  Assert.AreEqual(2, Integer(Length(mItems)));
  Assert.AreEqual('TB', mItems[0].Name);
  Assert.AreEqual(1, mItems[0].Value);
  Assert.AreEqual('TC', mItems[1].Name);
  Assert.AreEqual(2, mItems[1].Value);
  Assert.AreEqual(Ord(TStructureKind.InheritanceDepth), Ord(mItems[1].Kind));
end;

procedure TRuleInheritanceDepthsTests.UnitWithoutClassesHasNone;
var
  mDepths: IRuleInheritanceDepths;
begin
  mDepths := TRuleInheritanceDepths.Create;
  Assert.AreEqual(0, Integer(Length(mDepths.Depths(cFile, 'unit Leer;'#10'interface'#10'implementation'#10'end.',
    nil))));
end;

end.
