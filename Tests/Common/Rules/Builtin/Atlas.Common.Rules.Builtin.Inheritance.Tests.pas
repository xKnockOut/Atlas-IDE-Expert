unit Atlas.Common.Rules.Builtin.Inheritance.Tests;

// Tests für die Vererbungsregeln (#125).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TInheritanceRulesTests = class
  public
    [Test]
    procedure DestroyWithoutOverrideReportsPreferredFix;
    [Test]
    procedure DestroyWithOverrideIsSilent;
    [Test]
    procedure ComponentCreateResolvedFromIndexReports;
    [Test]
    procedure CreateOutsideComponentIsSilent;
    [Test]
    procedure UnresolvableAncestorIsSilent;
    [Test]
    procedure HidesVirtualOffersTwoAlternatives;
    [Test]
    procedure HidesVirtualWithOtherSignatureIsMedium;
    [Test]
    procedure ReintroduceSilencesAllRules;
    [Test]
    procedure OverloadWithOtherSignatureIsSilent;
    [Test]
    procedure VirtualInsteadOfOverrideReplacesDirective;
    [Test]
    procedure NewVirtualMethodIsSilent;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Rules.Builtin.Inheritance,
  Atlas.Tests.RuleAssert;

const
  // Ausschnitte aus RTL und VCL, wie sie der Index aus den Quellen liest.
  ClassesSource =
    'unit System.Classes;'#10'interface'#10'type'#10 +
    '  TPersistent = class(TObject)'#10'  end;'#10 +
    '  TComponent = class(TPersistent)'#10'  public'#10 +
    '    constructor Create(AOwner: TComponent); virtual;'#10'  end;'#10 +
    'implementation'#10'end.';
  ControlsSource =
    'unit Vcl.Controls;'#10'interface'#10'type'#10 +
    '  TControl = class(TComponent)'#10'  end;'#10 +
    '  TCustomControl = class(TControl)'#10'  end;'#10 +
    'implementation'#10'end.';

function ClassUnit(const AMembers: string; const AHead: string = 'TFoo = class(TBasis)'): string;
begin
  Result := 'unit U;'#10'interface'#10'type'#10 +
    '  TBasis = class'#10'  public'#10'    procedure Lauf(A: Integer); virtual;'#10'  end;'#10 +
    '  ' + AHead + #10'  public'#10 + AMembers + #10'  end;'#10'implementation'#10'end.';
end;

function IndexWith(const ASources: array of string): ISymbolIndex;
var
  Index: Integer;
  Tree: TSyntaxTree;
begin
  Result := TSymbolIndex.Create;
  for Index := 0 to High(ASources) do
  begin
    Tree := TPascalParser.Parse(ASources[Index]);
    try
      Result.AddUnit(TIndexExtractor.Extract(Tree, Format('C:\Quellen\Unit%d.pas', [Index])));
    finally
      Tree.Free;
    end;
  end;
end;

function Run(const ARule: IRule; const ASource: string; const AIndex: ISymbolIndex): TArray<TRuleFinding>;
var
  Context: TRuleContext;
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(ASource);
  try
    Context := Default(TRuleContext);
    Context.Text := ASource;
    Context.Tree := Tree;
    Context.Index := AIndex;
    Result := TRuleEngine.Run([ARule], TServerSettings.Default, Context);
  finally
    Tree.Free;
  end;
end;

procedure TInheritanceRulesTests.DestroyWithoutOverrideReportsPreferredFix;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TDestroyWithoutOverrideRule.Create, ClassUnit('    destructor Destroy;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.IsFalse(Findings[0].Fixes[0].Alternative);
  Assert.AreEqual(' override;', Findings[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual(9, Findings[0].Fixes[0].Edits[0].Range.StartPos.Line);
  Assert.AreEqual(23, Findings[0].Fixes[0].Edits[0].Range.StartPos.Character);
end;

procedure TInheritanceRulesTests.DestroyWithOverrideIsSilent;
begin
  TRuleAssert.Silent(TDestroyWithoutOverrideRule.Create, ClassUnit('    destructor Destroy; override;'));
end;

procedure TInheritanceRulesTests.ComponentCreateResolvedFromIndexReports;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := Run(TComponentCreateWithoutOverrideRule.Create,
    ClassUnit('    constructor Create(AOwner: TComponent);', 'TFoo = class(TCustomControl)'),
    IndexWith([ClassesSource, ControlsSource]));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(' override;', Findings[0].Fixes[0].Edits[0].NewText);
  // Ohne override verdeckt der Konstruktor TComponent.Create, das meldet aber nur diese Regel.
  Assert.AreEqual(0, Integer(Length(Run(THidesVirtualRule.Create,
    ClassUnit('    constructor Create(AOwner: TComponent);', 'TFoo = class(TCustomControl)'),
    IndexWith([ClassesSource, ControlsSource])))));
end;

procedure TInheritanceRulesTests.CreateOutsideComponentIsSilent;
begin
  Assert.AreEqual(0, Integer(Length(Run(TComponentCreateWithoutOverrideRule.Create,
    ClassUnit('    constructor Create(AOwner: TComponent);'), IndexWith([ClassesSource])))));
end;

procedure TInheritanceRulesTests.UnresolvableAncestorIsSilent;
begin
  // TCustomControl fehlt im Index: keine Aussage.
  Assert.AreEqual(0, Integer(Length(Run(TComponentCreateWithoutOverrideRule.Create,
    ClassUnit('    constructor Create(AOwner: TComponent);', 'TFoo = class(TCustomControl)'),
    IndexWith([ClassesSource])))));
  Assert.AreEqual(0, Integer(Length(Run(THidesVirtualRule.Create,
    ClassUnit('    procedure Lauf(A: Integer);', 'TFoo = class(TUnbekannt)'), nil))));
end;

procedure TInheritanceRulesTests.HidesVirtualOffersTwoAlternatives;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(THidesVirtualRule.Create, ClassUnit('    procedure Lauf(A: Integer);'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual(2, Integer(Length(Findings[0].Fixes)));
  Assert.IsTrue(Findings[0].Fixes[0].Alternative);
  Assert.IsTrue(Findings[0].Fixes[1].Alternative);
  Assert.AreEqual(' override;', Findings[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual(' reintroduce;', Findings[0].Fixes[1].Edits[0].NewText);
end;

procedure TInheritanceRulesTests.HidesVirtualWithOtherSignatureIsMedium;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(THidesVirtualRule.Create, ClassUnit('    procedure Lauf(const S: string);'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
  // override passt nicht zur Signatur; nur reintroduce.
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
end;

procedure TInheritanceRulesTests.ReintroduceSilencesAllRules;
var
  Source: string;
begin
  Source := ClassUnit('    procedure Lauf(A: Integer); reintroduce;'#10'    destructor Destroy; reintroduce;');
  TRuleAssert.Silent(THidesVirtualRule.Create, Source);
  TRuleAssert.Silent(TDestroyWithoutOverrideRule.Create, Source);
  TRuleAssert.Silent(TVirtualInsteadOfOverrideRule.Create, Source);
  TRuleAssert.Silent(TComponentCreateWithoutOverrideRule.Create, Source);
end;

procedure TInheritanceRulesTests.OverloadWithOtherSignatureIsSilent;
begin
  TRuleAssert.Silent(THidesVirtualRule.Create, ClassUnit('    procedure Lauf(const S: string); overload;'));
end;

procedure TInheritanceRulesTests.VirtualInsteadOfOverrideReplacesDirective;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TVirtualInsteadOfOverrideRule.Create,
    ClassUnit('    procedure Lauf(A: Integer); virtual;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('override', Findings[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual(9, Findings[0].Fixes[0].Edits[0].Range.StartPos.Line);
  Assert.AreEqual(32, Findings[0].Fixes[0].Edits[0].Range.StartPos.Character);
  TRuleAssert.Silent(THidesVirtualRule.Create, ClassUnit('    procedure Lauf(A: Integer); virtual;'));
end;

procedure TInheritanceRulesTests.NewVirtualMethodIsSilent;
begin
  TRuleAssert.Silent(TVirtualInsteadOfOverrideRule.Create, ClassUnit('    procedure Neu; virtual;'));
  TRuleAssert.Silent(THidesVirtualRule.Create, ClassUnit('    procedure Neu; virtual;'));
end;

initialization
  TDUnitX.RegisterTestFixture(TInheritanceRulesTests);

end.
