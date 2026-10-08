unit BDLsp.Common.Rules.Builtin.Declarations.Tests;

// Tests für declared-not-implemented und implemented-not-declared (#124).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDeclarationRulesTests = class
  public
    [Test]
    procedure MissingBodyReportsWithFix;
    [Test]
    procedure ImplementedMethodIsSilent;
    [Test]
    procedure MissingOverloadIsReported;
    [Test]
    procedure AbstractAndExternalAreSilent;
    [Test]
    procedure GenericTypeIsSilent;
    [Test]
    procedure ConditionalDeclarationIsSilent;
    [Test]
    procedure IncludeLowersConfidence;
    [Test]
    procedure BodyWithoutDeclarationReports;
    [Test]
    procedure FixAddsDeclarationToExistingPrivate;
    [Test]
    procedure FixCreatesPrivateSection;
    [Test]
    procedure GlobalRoutineIsSilent;
  end;

implementation

uses
  System.SysUtils,
  BDLsp.Common.Configuration.Contract,
  BDLsp.Common.Rules.Contract,
  BDLsp.Common.Pascal.SyntaxTree,
  BDLsp.Common.Pascal.Parser,
  BDLsp.Common.Rules.Builtin.Declarations,
  BDLsp.Tests.RuleAssert;

function ClassUnit(const AMembers, AImplementation: string; const AHead: string = 'TFoo = class'): string;
begin
  Result := 'unit U;'#10'interface'#10'type'#10'  ' + AHead + #10 + AMembers + #10'  end;'#10 +
    'implementation'#10 + AImplementation + #10'end.';
end;

/// <summary>Wendet die erste Korrektur des ersten Treffers an (Zeilen mit #10, Einfügung in einer Zeile).</summary>
function ApplyFirstFix(const AText: string; const AFindings: TArray<TRuleFinding>): string;
var
  Lines: TArray<string>;
  Edit: TRuleEdit;
  Line: string;
begin
  Edit := AFindings[0].Fixes[0].Edits[0];
  Lines := AText.Split([#10]);
  Line := Lines[Edit.Range.StartPos.Line];
  Lines[Edit.Range.StartPos.Line] := Copy(Line, 1, Edit.Range.StartPos.Character) + Edit.NewText +
    Copy(Line, Edit.Range.EndPos.Character + 1, MaxInt);
  Result := string.Join(#10, Lines);
end;

function ParsesCleanly(const AText: string): Boolean;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := Length(Tree.Diagnostics) = 0;
  finally
    Tree.Free;
  end;
end;

procedure TDeclarationRulesTests.MissingBodyReportsWithFix;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TDeclaredNotImplementedRule.Create,
    ClassUnit('    procedure Lauf(A: Integer);', ''));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Findings[0].Severity));
  Assert.Contains(Findings[0].Message, 'TFoo.Lauf');
  Assert.AreEqual(4, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.Contains(Findings[0].Fixes[0].Edits[0].NewText, 'procedure TFoo.Lauf(A: Integer);');
end;

procedure TDeclarationRulesTests.ImplementedMethodIsSilent;
begin
  TRuleAssert.Silent(TDeclaredNotImplementedRule.Create,
    ClassUnit('    procedure Lauf(A: Integer);', 'procedure TFoo.Lauf(A: Integer);'#10'begin'#10'end;'));
  TRuleAssert.Silent(TImplementedNotDeclaredRule.Create,
    ClassUnit('    procedure Lauf(A: Integer);', 'procedure TFoo.Lauf(A: Integer);'#10'begin'#10'end;'));
end;

procedure TDeclarationRulesTests.MissingOverloadIsReported;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TDeclaredNotImplementedRule.Create,
    ClassUnit('    procedure Lauf(A: Integer); overload;'#10'    procedure Lauf(const S: string); overload;',
      'procedure TFoo.Lauf(A: Integer);'#10'begin'#10'end;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(5, Findings[0].Range.StartPos.Line);
end;

procedure TDeclarationRulesTests.AbstractAndExternalAreSilent;
begin
  TRuleAssert.Silent(TDeclaredNotImplementedRule.Create,
    ClassUnit('    procedure Lauf; virtual; abstract;'#10'    procedure Fremd; external ''x.dll'';', ''));
end;

procedure TDeclarationRulesTests.GenericTypeIsSilent;
begin
  TRuleAssert.Silent(TDeclaredNotImplementedRule.Create,
    ClassUnit('    procedure Lauf(A: T);', '', 'TFoo<T> = class'));
end;

procedure TDeclarationRulesTests.ConditionalDeclarationIsSilent;
begin
  TRuleAssert.Silent(TDeclaredNotImplementedRule.Create,
    ClassUnit('{$IFDEF DEBUG}'#10'    procedure Lauf;'#10'{$ENDIF}', ''));
end;

procedure TDeclarationRulesTests.IncludeLowersConfidence;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TDeclaredNotImplementedRule.Create,
    ClassUnit('    procedure Lauf;', '{$I Teile.inc}'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
end;

procedure TDeclarationRulesTests.BodyWithoutDeclarationReports;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TImplementedNotDeclaredRule.Create,
    ClassUnit('    procedure Lauf;', 'procedure TFoo.Lauf;'#10'begin'#10'end;'#10 +
      'procedure TFoo.Extra(A: Integer);'#10'begin'#10'end;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.Contains(Findings[0].Message, 'TFoo.Extra');
end;

procedure TDeclarationRulesTests.FixAddsDeclarationToExistingPrivate;
var
  Source, Fixed: string;
begin
  Source := ClassUnit('  private'#10'    FWert: Integer;', 'function TFoo.Extra(A: Integer): string;'#10'begin'#10'end;');
  Fixed := ApplyFirstFix(Source, TRuleAssert.Findings(TImplementedNotDeclaredRule.Create, Source));
  Assert.AreEqual(ClassUnit('  private'#10'    function Extra(A: Integer): string;'#10'    FWert: Integer;',
    'function TFoo.Extra(A: Integer): string;'#10'begin'#10'end;'), Fixed);
  Assert.IsTrue(ParsesCleanly(Fixed));
end;

procedure TDeclarationRulesTests.FixCreatesPrivateSection;
var
  Source, Fixed: string;
begin
  Source := ClassUnit('  public'#10'    procedure Lauf;', 'procedure TFoo.Lauf;'#10'begin'#10'end;'#10 +
    'procedure TFoo.Extra;'#10'begin'#10'end;');
  Fixed := ApplyFirstFix(Source, TRuleAssert.Findings(TImplementedNotDeclaredRule.Create, Source));
  Assert.AreEqual(ClassUnit('  public'#10'    procedure Lauf;'#10'  private'#10'    procedure Extra;',
    'procedure TFoo.Lauf;'#10'begin'#10'end;'#10'procedure TFoo.Extra;'#10'begin'#10'end;'), Fixed);
  Assert.IsTrue(ParsesCleanly(Fixed));
  TRuleAssert.Silent(TImplementedNotDeclaredRule.Create, Fixed);
end;

procedure TDeclarationRulesTests.GlobalRoutineIsSilent;
begin
  TRuleAssert.Silent(TImplementedNotDeclaredRule.Create,
    'unit U;'#10'interface'#10'implementation'#10'procedure Hilfe;'#10'begin'#10'end;'#10'end.');
end;

initialization
  TDUnitX.RegisterTestFixture(TDeclarationRulesTests);

end.
