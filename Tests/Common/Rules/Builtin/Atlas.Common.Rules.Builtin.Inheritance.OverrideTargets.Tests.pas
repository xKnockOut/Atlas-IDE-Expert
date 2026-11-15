unit Atlas.Common.Rules.Builtin.Inheritance.OverrideTargets.Tests;

// Tests der Teilunit override-target-missing: override ohne virtuelle Methode im Vorfahren, sealed-Vorfahr.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TInheritanceOverrideTargetsTests = class
  public
    [Test]
    procedure MissingTargetIsReported;
    [Test]
    procedure SealedAncestorIsReported;
    [Test]
    procedure MatchingOverrideIsSilent;
    [Test]
    procedure AncestorFromUsedUnitWins;
  end;


implementation

uses
  Atlas.Common.Rules.Contract,

  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Rules.Builtin.Inheritance.OverrideTargets,
  Atlas.Tests.RuleAssert;


{ TInheritanceOverrideTargetsTests }

procedure TInheritanceOverrideTargetsTests.MissingTargetIsReported;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TOverrideTargetMissingRule.Create,
    'unit U;'#10'interface'#10'type'#10'  TBasis = class'#10'  public'#10'    procedure Lauf; virtual;'#10 +
    '  end;'#10'  TAbleitung = class(TBasis)'#10'  public'#10'    procedure Laufen; override;'#10'  end;'#10 +
    'implementation'#10'procedure TBasis.Lauf;'#10'begin'#10'end;'#10'procedure TAbleitung.Laufen;'#10 +
    'begin'#10'end;'#10'end.'#10);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('override-target-missing', mFindings[0].RuleId);
end;

procedure TInheritanceOverrideTargetsTests.SealedAncestorIsReported;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TOverrideTargetMissingRule.Create,
    'unit U;'#10'interface'#10'type'#10'  TBasis = class sealed'#10'  end;'#10 +
    '  TAbleitung = class(TBasis)'#10'  end;'#10'implementation'#10'end.'#10);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('override-target-missing', mFindings[0].RuleId);
end;

procedure TInheritanceOverrideTargetsTests.MatchingOverrideIsSilent;
begin
  TRuleAssert.Silent(TOverrideTargetMissingRule.Create,
    'unit U;'#10'interface'#10'type'#10'  TBasis = class'#10'  public'#10'    procedure Lauf; virtual;'#10 +
    '  end;'#10'  TAbleitung = class(TBasis)'#10'  public'#10'    procedure Lauf; override;'#10'  end;'#10 +
    'implementation'#10'procedure TBasis.Lauf;'#10'begin'#10'end;'#10'procedure TAbleitung.Lauf;'#10 +
    'begin'#10'end;'#10'end.'#10);
end;

/// <summary>FP mORMot: TSQLRestServerDB = class(TSQLRestServer) aus der eingebundenen Unit mORMot; eine andere Unit
/// des Projekts (SynCrossPlatformREST) deklariert ebenfalls TSQLRestServer, ohne die virtuelle Methode. Der Vorfahr
/// kommt aus der Unit im uses, nicht aus irgendeiner gleichnamigen Klasse des Index.</summary>
procedure TInheritanceOverrideTargetsTests.AncestorFromUsedUnitWins;
const
  cSources: array[0..1] of string = (
    'unit Fremd;'#10'interface'#10'type'#10'  TBasis = class'#10'  end;'#10'implementation'#10'end.',
    'unit Bibliothek;'#10'interface'#10'type'#10'  TBasis = class'#10'  public'#10'    procedure Lauf; virtual;'#10 +
    '  end;'#10'implementation'#10'procedure TBasis.Lauf;'#10'begin'#10'end;'#10'end.');
  cFiles: array[0..1] of string = ('C:\Quellen\Fremd.pas', 'C:\Quellen\Bibliothek.pas');
  cSource = 'unit Nutzer;'#10'interface'#10'uses'#10'  Bibliothek;'#10'type'#10'  TAbleitung = class(TBasis)'#10 +
    '  public'#10'    procedure Lauf; override;'#10'  end;'#10'implementation'#10'procedure TAbleitung.Lauf;'#10 +
    'begin'#10'end;'#10'end.'#10;
var
  mIndex: ISymbolIndex;
  mTree: TSyntaxTree;
  mPosition: Integer;
begin
  mIndex := TSymbolIndex.Create;
  for mPosition := 0 to High(cSources) do
  begin
    mTree := TPascalParser.Parse(cSources[mPosition]);
    try
      mIndex.AddUnit(TIndexExtractor.Extract(mTree, cFiles[mPosition]));
    finally
      mTree.Free;
    end;
  end;
  Assert.AreEqual(0, Integer(Length(TRuleAssert.IndexFindings(TOverrideTargetMissingRule.Create, cSource, mIndex, '',
    'C:\Quellen\Nutzer.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TInheritanceOverrideTargetsTests);

end.
