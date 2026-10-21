unit Atlas.Common.Rules.Builtin.Packages.Tests;

// Tests der Regel implicit-package-import (#46): Units, die über contains
// erreicht werden, aber weder in contains noch in einem requires-Package
// stehen, mit Korrektur; Bibliothek, unbekannte Packages und fehlender
// Package-Inhalt bleiben still.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TPackageRulesTests = class
  public
    [Test]
    procedure ReportsImplicitUnitsWithFix;
    [Test]
    procedure RequiredPackageProvidesUnit;
    [Test]
    procedure UnknownPackageIsSilent;
    [Test]
    procedure SilentWithoutPackageInfo;
    [Test]
    procedure UnitsAreNotChecked;
    [Test]
    procedure RuleIsRegistered;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Builtin.Packages;

const
  PackageKasse =
    'package KasseCore;'#10 +
    'requires'#10 +
    '  rtl, vcl, Basis;'#10 +
    'contains'#10 +
    '  uBeleg in ''uBeleg.pas'','#10 +
    '  uSteuer in ''uSteuer.pas'';'#10 +
    'end.';

function UnitText(const AName, AUses: string): string;
begin
  Result := 'unit ' + AName + ';'#10'interface'#10;
  if AUses <> '' then
    Result := Result + 'uses ' + AUses + ';'#10;
  Result := Result + 'implementation'#10'end.';
end;

function NewIndex: ISymbolIndex;
var
  Library_: TUnitIndex;
begin
  Result := TSymbolIndex.Create;
  Result.AddUnit(TIndexExtractor.ExtractText(UnitText('uBeleg', 'System.Classes'), 'C:\P\uBeleg.pas', nil));
  Result.AddUnit(TIndexExtractor.ExtractText(UnitText('uSteuer', 'uRunden, uBasis, uBeleg'), 'C:\P\uSteuer.pas',
    nil));
  Result.AddUnit(TIndexExtractor.ExtractText(UnitText('uRunden', 'uMathe'), 'C:\P\uRunden.pas', nil));
  Result.AddUnit(TIndexExtractor.ExtractText(UnitText('uMathe', ''), 'C:\P\uMathe.pas', nil));
  Result.AddUnit(TIndexExtractor.ExtractText(UnitText('uBasis', ''), 'C:\B\uBasis.pas', nil));
  Library_ := TIndexExtractor.ExtractText(UnitText('System.Classes', 'uMathe'), 'C:\BDS\System.Classes.pas', nil);
  Library_.Library_ := True;
  Result.AddUnit(Library_);
end;

/// <summary>rtl liefert System.*, Basis liefert uBasis, vcl ist leer; AUnknown = Basis ist nicht auffindbar.
/// </summary>
function Provides(AUnknown: Boolean): TRulePackageProvides;
begin
  Result :=
    function(const APackage, AUnitName: string): TRulePackageAnswer
    begin
      Result := TRulePackageAnswer.No;
      if SameText(APackage, 'rtl') and AUnitName.StartsWith('System.') then
        Result := TRulePackageAnswer.Yes
      else if SameText(APackage, 'Basis') then
      begin
        if AUnknown then
          Result := TRulePackageAnswer.Unknown
        else if SameText(AUnitName, 'uBasis') then
          Result := TRulePackageAnswer.Yes;
      end;
    end;
end;

function Run(const ASource: string; const AProvides: TRulePackageProvides): TArray<TRuleFinding>;
var
  Context: TRuleContext;
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(ASource);
  try
    Context := Default(TRuleContext);
    Context.RelativePath := 'KasseCore.dpk';
    Context.UnitName := 'KasseCore';
    Context.Text := ASource;
    Context.Tree := Tree;
    Context.Index := NewIndex;
    Context.FileName := 'C:\P\KasseCore.dpk';
    Context.PackageProvides := AProvides;
    Result := TRuleEngine.Run([IRule(TImplicitPackageImportRule.Create)], TServerSettings.Default, Context);
  finally
    Tree.Free;
  end;
end;

function Messages(const AFindings: TArray<TRuleFinding>): string;
var
  Finding: TRuleFinding;
begin
  Result := '';
  for Finding in AFindings do
    Result := Result + Format('%d:%d %s|', [Finding.Range.StartPos.Line, Finding.Range.StartPos.Character,
      Finding.Message]);
end;

{ TPackageRulesTests }

procedure TPackageRulesTests.ReportsImplicitUnitsWithFix;
var
  Findings: TArray<TRuleFinding>;
  Finding: TRuleFinding;
  Text: string;
begin
  Findings := Run(PackageKasse, Provides(False));
  Text := Messages(Findings);
  Assert.AreEqual(2, Integer(Length(Findings)), Text);
  Assert.IsTrue(Text.Contains('5:2 "uRunden" wird implizit ins Package gezogen: uSteuer verwendet uRunden'), Text);
  // uMathe kommt über uRunden mit; gemeldet am selben contains-Eintrag.
  Assert.IsTrue(Text.Contains('5:2 "uMathe" wird implizit ins Package gezogen: uRunden verwendet uMathe'), Text);
  Assert.IsFalse(Text.Contains('System.Classes'), Text);
  Assert.IsFalse(Text.Contains('uBasis'), Text);
  Finding := Findings[0];
  Assert.AreEqual(ImplicitPackageImportRuleId, Finding.RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Finding.Severity));
  Assert.AreEqual(1, Integer(Length(Finding.Fixes)));
  Assert.AreEqual('"uRunden" in contains aufnehmen', Finding.Fixes[0].Title);
  Assert.AreEqual(5, Finding.Fixes[0].Edits[0].Range.StartPos.Line);
  // Vor dem Semikolon hinter dem letzten contains-Eintrag.
  Assert.AreEqual(26, Finding.Fixes[0].Edits[0].Range.StartPos.Character);
  Assert.IsTrue(Finding.Fixes[0].Edits[0].NewText.StartsWith(','#10'  uRunden in '''),
    Finding.Fixes[0].Edits[0].NewText);
  Assert.IsTrue(Finding.Fixes[0].Edits[0].NewText.EndsWith('uRunden.pas'''), Finding.Fixes[0].Edits[0].NewText);
end;

procedure TPackageRulesTests.RequiredPackageProvidesUnit;
begin
  // uBasis kommt aus dem Package Basis; ohne Basis in requires wäre es implizit.
  Assert.IsFalse(Messages(Run(PackageKasse, Provides(False))).Contains('uBasis'));
  Assert.IsTrue(Messages(Run(PackageKasse.Replace(', Basis;', ';'), Provides(False))).Contains(
    '"uBasis" wird implizit'));
end;

procedure TPackageRulesTests.UnknownPackageIsSilent;
var
  Findings: TArray<TRuleFinding>;
begin
  // Ist ein Package aus requires nicht auffindbar, könnte jede Unit darin stehen.
  Findings := Run(PackageKasse, Provides(True));
  Assert.AreEqual(0, Integer(Length(Findings)), Messages(Findings));
end;

procedure TPackageRulesTests.SilentWithoutPackageInfo;
begin
  Assert.AreEqual(0, Integer(Length(Run(PackageKasse, nil))));
end;

procedure TPackageRulesTests.UnitsAreNotChecked;
begin
  Assert.AreEqual(0, Integer(Length(Run(UnitText('uSteuer', 'uRunden'), Provides(False)))));
end;

procedure TPackageRulesTests.RuleIsRegistered;
var
  Rule: IRule;
  Found: Boolean;
begin
  Found := False;
  for Rule in BuiltinRules do
    if Rule.Descriptor.Id = ImplicitPackageImportRuleId then
      Found := True;
  Assert.IsTrue(Found);
end;

end.
