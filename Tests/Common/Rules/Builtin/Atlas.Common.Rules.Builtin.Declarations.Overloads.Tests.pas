unit Atlas.Common.Rules.Builtin.Declarations.Overloads.Tests;

// Tests der Teilunit overload-directive-missing: verschachtelte Routinen gleichen Namens ohne overload.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDeclarationOverloadsTests = class
  public
    [Test]
    procedure IsReported;
    [Test]
    procedure IsSilent;
    /// <summary>Implementierung mit Integer zur Deklaration mit Int32 (eingebauter Alias) und mit Unit.Typ zur
    /// Deklaration mit Typ: kein E2254; Int32 und Integer als zwei Überladungen sind dieselbe Signatur (E2252).
    /// </summary>
    [Test]
    procedure BuiltinAliasMatchesDeclaration;
  end;

implementation

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Declarations.Overloads,
  Atlas.Tests.RuleAssert;

{ TDeclarationOverloadsTests }

procedure TDeclarationOverloadsTests.IsReported;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TOverloadDirectiveMissingRule.Create, 'unit U;'#10'interface'#10'implementation'#10'procedure Aussen;'#10'  procedure Innen; begin end;'#10 +
    '  procedure Innen(X: Integer); begin end;'#10'begin'#10'end;'#10'end.');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('overload-directive-missing', mFindings[0].RuleId);
end;

procedure TDeclarationOverloadsTests.IsSilent;
begin
  TRuleAssert.Silent(TOverloadDirectiveMissingRule.Create, 'unit U;'#10'interface'#10'implementation'#10'procedure Aussen;'#10 +
    '  procedure Innen; overload; begin end;'#10'  procedure Innen(X: Integer); overload; begin end;'#10'begin'#10 +
    'end;'#10'end.');
end;

procedure TDeclarationOverloadsTests.BuiltinAliasMatchesDeclaration;
var
  mFindings: TArray<TRuleFinding>;
begin
  TRuleAssert.Silent(TOverloadDirectiveMissingRule.Create, 'unit U;'#10'interface'#10 +
    'function Wende(const A: UInt16): UInt16; overload;'#10'function Wende(const A: Int32): Int32; overload;'#10 +
    'implementation'#10'function Wende(const A: UInt16): UInt16;'#10'begin'#10'  Result := A;'#10'end;'#10 +
    'function Wende(const A: Integer): Integer;'#10'begin'#10'  Result := A;'#10'end;'#10'end.');
  TRuleAssert.Silent(TOverloadDirectiveMissingRule.Create, 'unit U;'#10'interface'#10'uses Texte;'#10 +
    'procedure Schreibe(P: PText; T: DWORD); overload;'#10'procedure Schreibe(const S: string); overload;'#10 +
    'implementation'#10'procedure Schreibe(P: Texte.PText; T: Cardinal);'#10'begin'#10'end;'#10 +
    'procedure Schreibe(const S: string);'#10'begin'#10'end;'#10'end.');
  mFindings := TRuleAssert.Findings(TOverloadDirectiveMissingRule.Create, 'unit U;'#10'interface'#10 +
    'procedure Lauf(A: Integer); overload;'#10'procedure Lauf(A: Int32); overload;'#10'implementation'#10 +
    'procedure Lauf(A: Integer);'#10'begin'#10'end;'#10'end.');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.Contains(mFindings[0].Message, 'E2252');
end;

initialization
  TDUnitX.RegisterTestFixture(TDeclarationOverloadsTests);

end.
