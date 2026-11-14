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
    /// <summary>Wie dcc: Units der Packages, die ein requires-Package verlangt, sind ebenfalls vorhanden
    /// (Atlas.Windows → Atlas.Common → Atlas.Text).</summary>
    [Test]
    procedure IndirectRequiresProvideUnit;
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
  cPackageKasse =
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
  begin
    Result := Result + 'uses ' + AUses + ';'#10;
  end;
  Result := Result + 'implementation'#10'end.';
end;

function NewIndex: ISymbolIndex;
var
  mLibrary_: TUnitIndex;
begin
  Result := TSymbolIndex.Create;
  Result.AddUnit(TIndexExtractor.ExtractText(UnitText('uBeleg', 'System.Classes'), 'C:\P\uBeleg.pas', nil));
  Result.AddUnit(TIndexExtractor.ExtractText(UnitText('uSteuer', 'uRunden, uBasis, uBeleg'), 'C:\P\uSteuer.pas',
    nil));
  Result.AddUnit(TIndexExtractor.ExtractText(UnitText('uRunden', 'uMathe'), 'C:\P\uRunden.pas', nil));
  Result.AddUnit(TIndexExtractor.ExtractText(UnitText('uMathe', ''), 'C:\P\uMathe.pas', nil));
  Result.AddUnit(TIndexExtractor.ExtractText(UnitText('uBasis', ''), 'C:\B\uBasis.pas', nil));
  mLibrary_ := TIndexExtractor.ExtractText(UnitText('System.Classes', 'uMathe'), 'C:\BDS\System.Classes.pas', nil);
  mLibrary_.Library_ := True;
  Result.AddUnit(mLibrary_);
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
      begin
        Result := TRulePackageAnswer.Yes;
      end
      else if SameText(APackage, 'Basis') then
      begin
        if AUnknown then
        begin
          Result := TRulePackageAnswer.Unknown;
        end
        else if SameText(AUnitName, 'uBasis') then
        begin
          Result := TRulePackageAnswer.Yes;
        end;
      end;
    end;
end;

function Run(const ASource: string; const AProvides: TRulePackageProvides;
  const ARequires: TRulePackageRequires): TArray<TRuleFinding>; overload;
var
  mContext: TRuleContext;
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(ASource);
  try
    mContext := Default(TRuleContext);
    mContext.RelativePath := 'KasseCore.dpk';
    mContext.UnitName := 'KasseCore';
    mContext.Text := ASource;
    mContext.Tree := mTree;
    mContext.Index := NewIndex;
    mContext.FileName := 'C:\P\KasseCore.dpk';
    mContext.PackageProvides := AProvides;
    mContext.PackageRequires := ARequires;
    Result := TRuleEngine.Run([IRule(TImplicitPackageImportRule.Create)], TServerSettings.Default, mContext);
  finally
    mTree.Free;
  end;
end;

function Run(const ASource: string; const AProvides: TRulePackageProvides): TArray<TRuleFinding>; overload;
var
  mContext: TRuleContext;
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(ASource);
  try
    mContext := Default(TRuleContext);
    mContext.RelativePath := 'KasseCore.dpk';
    mContext.UnitName := 'KasseCore';
    mContext.Text := ASource;
    mContext.Tree := mTree;
    mContext.Index := NewIndex;
    mContext.FileName := 'C:\P\KasseCore.dpk';
    mContext.PackageProvides := AProvides;
    Result := TRuleEngine.Run([IRule(TImplicitPackageImportRule.Create)], TServerSettings.Default, mContext);
  finally
    mTree.Free;
  end;
end;

function Messages(const AFindings: TArray<TRuleFinding>): string;
var
  mFinding: TRuleFinding;
begin
  Result := '';
  for mFinding in AFindings do
  begin
    Result := Result + Format('%d:%d %s|', [mFinding.Range.StartPos.Line, mFinding.Range.StartPos.Character,
      mFinding.Message]);
  end;
end;

{ TPackageRulesTests }

procedure TPackageRulesTests.ReportsImplicitUnitsWithFix;
var
  mFindings: TArray<TRuleFinding>;
  mFinding: TRuleFinding;
  mText: string;
begin
  mFindings := Run(cPackageKasse, Provides(False));
  mText := Messages(mFindings);
  Assert.AreEqual(2, Integer(Length(mFindings)), mText);
  Assert.IsTrue(mText.Contains('5:2 "uRunden" wird implizit ins Package gezogen: uSteuer verwendet uRunden'), mText);
  // uMathe kommt über uRunden mit; gemeldet am selben contains-Eintrag.
  Assert.IsTrue(mText.Contains('5:2 "uMathe" wird implizit ins Package gezogen: uRunden verwendet uMathe'), mText);
  Assert.IsFalse(mText.Contains('System.Classes'), mText);
  Assert.IsFalse(mText.Contains('uBasis'), mText);
  mFinding := mFindings[0];
  Assert.AreEqual(cImplicitPackageImportRuleId, mFinding.RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFinding.Severity));
  Assert.AreEqual(1, Integer(Length(mFinding.Fixes)));
  Assert.AreEqual('"uRunden" in contains aufnehmen', mFinding.Fixes[0].Title);
  Assert.AreEqual(5, mFinding.Fixes[0].Edits[0].Range.StartPos.Line);
  // Vor dem Semikolon hinter dem letzten contains-Eintrag.
  Assert.AreEqual(26, mFinding.Fixes[0].Edits[0].Range.StartPos.Character);
  Assert.IsTrue(mFinding.Fixes[0].Edits[0].NewText.StartsWith(','#10'  uRunden in '''),
    mFinding.Fixes[0].Edits[0].NewText);
  Assert.IsTrue(mFinding.Fixes[0].Edits[0].NewText.EndsWith('uRunden.pas'''), mFinding.Fixes[0].Edits[0].NewText);
end;

procedure TPackageRulesTests.RequiredPackageProvidesUnit;
begin
  // uBasis kommt aus dem Package Basis; ohne Basis in requires wäre es implizit.
  Assert.IsFalse(Messages(Run(cPackageKasse, Provides(False))).Contains('uBasis'));
  Assert.IsTrue(Messages(Run(cPackageKasse.Replace(', Basis;', ';'), Provides(False))).Contains(
    '"uBasis" wird implizit'));
end;

procedure TPackageRulesTests.IndirectRequiresProvideUnit;
var
  mSource: string;
  mRequires: TRulePackageRequires;
begin
  // KasseCore verlangt nur Mitte, Mitte verlangt Basis, Basis liefert uBasis.
  mSource := cPackageKasse.Replace(', Basis;', ', Mitte;');
  mRequires :=
    function(const APackage: string): TArray<string>
    begin
      Result := nil;
      if SameText(APackage, 'Mitte') then
      begin
        Result := ['Basis'];
      end;
    end;
  Assert.IsFalse(Messages(Run(mSource, Provides(False), mRequires)).Contains('uBasis'));
  // Ohne die Kette (nur direkte requires) wäre uBasis implizit.
  Assert.IsTrue(Messages(Run(mSource, Provides(False), nil)).Contains('"uBasis" wird implizit'));
end;

procedure TPackageRulesTests.UnknownPackageIsSilent;
var
  mFindings: TArray<TRuleFinding>;
begin
  // Ist ein Package aus requires nicht auffindbar, könnte jede Unit darin stehen.
  mFindings := Run(cPackageKasse, Provides(True));
  Assert.AreEqual(0, Integer(Length(mFindings)), Messages(mFindings));
end;

procedure TPackageRulesTests.SilentWithoutPackageInfo;
begin
  Assert.AreEqual(0, Integer(Length(Run(cPackageKasse, nil))));
end;

procedure TPackageRulesTests.UnitsAreNotChecked;
begin
  Assert.AreEqual(0, Integer(Length(Run(UnitText('uSteuer', 'uRunden'), Provides(False)))));
end;

procedure TPackageRulesTests.RuleIsRegistered;
var
  mRule: IRule;
  mFound: Boolean;
begin
  mFound := False;
  for mRule in BuiltinRules do
  begin
    if mRule.Descriptor.Id = cImplicitPackageImportRuleId then
    begin
      mFound := True;
    end;
  end;
  Assert.IsTrue(mFound);
end;

end.
