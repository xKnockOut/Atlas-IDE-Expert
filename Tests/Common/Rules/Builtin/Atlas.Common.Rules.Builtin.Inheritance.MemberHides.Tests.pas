unit Atlas.Common.Rules.Builtin.Inheritance.MemberHides.Tests;

// Tests der Teilunit member-hides-ancestor: Feld oder Property heißt wie ein Member des Vorfahren.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TInheritanceMemberHidesTests = class
  public
    [Test]
    procedure FieldHidesFieldIsReported;
    [Test]
    procedure OtherNameIsSilent;
    [Test]
    procedure InterfaceMethodIsSilent;
  end;

implementation

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Inheritance.MemberHides,
  Atlas.Tests.RuleAssert;

procedure TInheritanceMemberHidesTests.FieldHidesFieldIsReported;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TMemberHidesAncestorRule.Create,
    'unit U;'#10'interface'#10'type'#10'  TBasis = class'#10'  protected'#10'    FWert: Integer;'#10 +
    '  end;'#10'  TAbleitung = class(TBasis)'#10'  protected'#10'    FWert: Integer;'#10'  end;'#10 +
    'implementation'#10'end.'#10);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('member-hides-ancestor', mFindings[0].RuleId);
end;

procedure TInheritanceMemberHidesTests.OtherNameIsSilent;
begin
  TRuleAssert.Silent(TMemberHidesAncestorRule.Create,
    'unit U;'#10'interface'#10'type'#10'  TBasis = class'#10'  protected'#10'    FWert: Integer;'#10 +
    '  end;'#10'  TAbleitung = class(TBasis)'#10'  protected'#10'    FZahl: Integer;'#10'  end;'#10 +
    'implementation'#10'end.'#10);
end;

/// <summary>QueryInterface über TInterfacedObject (Atlas.IDE.CodeInsight.Manager) und eine Methode eines eigenen
/// Interfaces verdecken gewollt; ohne Interface in der Liste bleibt die Meldung.</summary>
procedure TInheritanceMemberHidesTests.InterfaceMethodIsSilent;
const
  cBase = 'unit U;'#10'interface'#10'type'#10'  IFoo = interface'#10'    procedure Run;'#10'  end;'#10 +
    '  TBasis = class(TObject, IInterface)'#10'  public'#10 +
    '    function QueryInterface(const IID: TGUID; out Obj): HResult; stdcall;'#10 +
    '    procedure Run;'#10'  end;'#10;
  cMembers = '  public'#10'    function QueryInterface(const IID: TGUID; out Obj): HResult; stdcall;'#10 +
    '    procedure Run;'#10'  end;'#10'implementation'#10'end.'#10;
var
  mFindings: TArray<TRuleFinding>;
begin
  TRuleAssert.Silent(TMemberHidesAncestorRule.Create,
    cBase + '  TAbleitung = class(TBasis, IFoo)'#10 + cMembers);
  // Methoden meldet die Regel mit niedriger Konfidenz.
  mFindings := TRuleAssert.Findings(TMemberHidesAncestorRule.Create,
    cBase + '  TAbleitung = class(TBasis)'#10 + cMembers, '{"minConfidence": "low"}', 'U.pas');
  Assert.AreEqual(2, Integer(Length(mFindings)));
end;

initialization
  TDUnitX.RegisterTestFixture(TInheritanceMemberHidesTests);

end.
