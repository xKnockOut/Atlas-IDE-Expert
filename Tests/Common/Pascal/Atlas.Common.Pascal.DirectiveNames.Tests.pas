unit Atlas.Common.Pascal.DirectiveNames.Tests;

// Tests der Namen von Compiler-Direktiven und {$WARN}-Bezeichnern (#989):
// Inhalt einer Direktive, bekannte und unbekannte Namen, Tippfehler.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDirectiveNamesTests = class
  public
    [Test]
    procedure BodyAndLeadingName;
    [Test]
    procedure KnowsDirectivesAndSwitches;
    [Test]
    procedure KnowsWarnings;
    [Test]
    procedure ClosestFindsTypos;
    [Test]
    procedure ListsHaveNoDuplicates;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.DirectiveNames,
  Atlas.Text.Fuzzy;

procedure TDirectiveNamesTests.BodyAndLeadingName;
begin
  Assert.AreEqual('IFDEF DEBUG', TDirectiveNames.Body('{$IFDEF DEBUG}'));
  Assert.AreEqual('R+', TDirectiveNames.Body('(*$R+*)'));
  Assert.AreEqual('WARN', TDirectiveNames.LeadingName('WARN SYMBOL_PLATFORM OFF'));
  Assert.AreEqual('A', TDirectiveNames.LeadingName('A8'));
  Assert.AreEqual('', TDirectiveNames.LeadingName('+'));
end;

procedure TDirectiveNamesTests.KnowsDirectivesAndSwitches;
begin
  Assert.IsTrue(TDirectiveNames.IsDirective('ifdef'));
  Assert.IsTrue(TDirectiveNames.IsDirective('PUSHOPT'));
  Assert.IsTrue(TDirectiveNames.IsDirective('SetPEFlags'));
  Assert.IsTrue(TDirectiveNames.IsDirective('R'));
  Assert.IsTrue(TDirectiveNames.IsDirective('YD'));
  Assert.IsFalse(TDirectiveNames.IsDirective('IFDEFF'));
  Assert.IsFalse(TDirectiveNames.IsDirective('MODE'));
  Assert.IsFalse(TDirectiveNames.IsDirective(''));
end;

procedure TDirectiveNamesTests.KnowsWarnings;
begin
  Assert.IsTrue(TDirectiveNames.IsWarning('symbol_platform'));
  Assert.IsTrue(TDirectiveNames.IsWarning('ZERO_NIL_COMPAT'));
  Assert.IsTrue(TDirectiveNames.IsWarning('IMPLICIT_INTEGER_CAST_LOSS'));
  Assert.IsFalse(TDirectiveNames.IsWarning('UNKOWN'));
end;

procedure TDirectiveNamesTests.ClosestFindsTypos;
begin
  Assert.AreEqual('IFDEF', TTextFuzzy.Closest('IFDEFF', TDirectiveNames.Directives));
  Assert.AreEqual('ENDIF', TTextFuzzy.Closest('ENDIFF', TDirectiveNames.Directives));
  Assert.AreEqual('SYMBOL_PLATFORM', TTextFuzzy.Closest('SYMBOL_PLATFROM', TDirectiveNames.Warnings));
  Assert.AreEqual('', TTextFuzzy.Closest('XYZZY', TDirectiveNames.Directives));
  // Kurze Namen: höchstens die Hälfte darf abweichen.
  Assert.AreEqual('', TTextFuzzy.Closest('IX', TDirectiveNames.Directives));
end;

procedure TDirectiveNamesTests.ListsHaveNoDuplicates;

  procedure CheckList(const ANames: TArray<string>);
  var
    Outer, Inner: Integer;
  begin
    for Outer := 0 to High(ANames) do
    begin
      Assert.AreEqual(UpperCase(ANames[Outer]), ANames[Outer]);
      for Inner := Outer + 1 to High(ANames) do
        Assert.IsFalse(SameText(ANames[Outer], ANames[Inner]), ANames[Outer]);
    end;
  end;

begin
  CheckList(TDirectiveNames.Directives);
  CheckList(TDirectiveNames.Warnings);
end;

initialization
  TDUnitX.RegisterTestFixture(TDirectiveNamesTests);

end.
