unit Atlas.Common.Pascal.UsesClauses.Tests;

// Tests für das Lesen von uses-, contains- und requires-Listen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TPascalUsesTests = class
  public
    [Test]
    procedure ReadsUsedUnitsOfBothSections;
    [Test]
    procedure ReadsUsedUnitsOfText;
    [Test]
    procedure ReadsOwnName;
    [Test]
    procedure ReadsReferencesWithPositions;
    [Test]
    procedure KnowsUnitsWithoutNamespace;
    [Test]
    procedure DUnitXUses_IsTestUnit;
    [Test]
    procedure PlainUnit_IsNotTestUnit;
    [Test]
    procedure TestInsightNamespace_IsTestUnit;
    [Test]
    procedure ActiveTokens_DropsTokensOfInactiveRanges;
    [Test]
    procedure ActiveTokens_WithoutRanges_KeepsAll;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.UsesClauses;

const
  cUnitText =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses System.SysUtils, Werkzeug in ''Werkzeug.pas'';'#10 +
    'implementation'#10 +
    'uses'#10 +
    '  Classes,'#10 +
    '  Daten.Kunden;'#10 +
    'procedure Rechne;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

{ TPascalUsesTests }

procedure TPascalUsesTests.ReadsUsedUnitsOfBothSections;
begin
  Assert.AreEqual('System.SysUtils Werkzeug Classes Daten.Kunden',
    string.Join(' ', TPascalUses.UsedUnits(TPascalLexer.Tokenize(cUnitText))));
end;

procedure TPascalUsesTests.ReadsUsedUnitsOfText;
begin
  Assert.AreEqual('System.SysUtils Werkzeug Classes Daten.Kunden', string.Join(' ', TPascalUses.UsedUnitsOf(cUnitText)));
  Assert.AreEqual(0, Integer(Length(TPascalUses.UsedUnitsOf(''))));
end;

procedure TPascalUsesTests.ReadsOwnName;
begin
  Assert.AreEqual('Haupt', TPascalUses.OwnName(TPascalLexer.Tokenize(cUnitText)));
  Assert.AreEqual('App.Main', TPascalUses.OwnName(TPascalLexer.Tokenize('program App.Main;'#10'begin'#10'end.')));
end;

procedure TPascalUsesTests.ReadsReferencesWithPositions;
var
  mReferences: TArray<TUsesReference>;
  mName: string;
begin
  // Zeile 2: "uses A, B.C in 'b.pas';" – Position über alle Namensteile, ohne Pfad.
  mReferences := TPascalUses.References(TPascalLexer.Tokenize(
    'unit U;'#10'interface'#10'uses A, B.C in ''b.pas'';'#10'implementation'#10'end.'));
  Assert.AreEqual(2, Integer(Length(mReferences)));
  mName := mReferences[1].Name;
  Assert.AreEqual('B.C', mName);
  Assert.AreEqual(2, mReferences[1].Range.StartPos.Line);
  Assert.AreEqual(8, mReferences[1].Range.StartPos.Character);
  Assert.AreEqual(11, mReferences[1].Range.EndPos.Character);
  // Packages: requires und contains, auch wenn sie als Bezeichner gelesen werden.
  mReferences := TPascalUses.References(TPascalLexer.Tokenize(
    'package P;'#10'requires rtl;'#10'contains X in ''x.pas'', Y;'#10'end.'));
  Assert.AreEqual(3, Integer(Length(mReferences)));
  mName := mReferences[2].Name;
  Assert.AreEqual('Y', mName);
  // Art der Liste (#1109).
  Assert.AreEqual(Ord(TUsesListKind.RequiresList), Ord(mReferences[0].List));
  Assert.AreEqual(Ord(TUsesListKind.ContainsList), Ord(mReferences[1].List));
  Assert.AreEqual(Ord(TUsesListKind.ContainsList), Ord(mReferences[2].List));
  mReferences := TPascalUses.References(TPascalLexer.Tokenize(
    'unit U;'#10'interface'#10'uses A, B.C in ''b.pas'';'#10'implementation'#10'end.'));
  Assert.AreEqual(Ord(TUsesListKind.UsesList), Ord(mReferences[0].List));
  // Abschnitt je Eintrag (#268): interface bis "implementation", in Packages und Programmen nie.
  Assert.IsTrue(mReferences[0].InInterface);
  mReferences := TPascalUses.References(TPascalLexer.Tokenize(
    'unit U;'#10'interface'#10'uses A;'#10'type IX = interface end;'#10'implementation'#10'uses B;'#10'end.'));
  Assert.AreEqual(2, Integer(Length(mReferences)));
  Assert.IsTrue(mReferences[0].InInterface, 'A');
  Assert.IsFalse(mReferences[1].InInterface, 'B');
  mReferences := TPascalUses.References(TPascalLexer.Tokenize('program P;'#10'uses A;'#10'begin end.'));
  Assert.IsFalse(mReferences[0].InInterface, 'Programm');
end;

procedure TPascalUsesTests.KnowsUnitsWithoutNamespace;
begin
  Assert.IsTrue(TPascalUses.IsUsed(['SysUtils'], 'System.SysUtils', ['System', 'Vcl']));
  Assert.IsTrue(TPascalUses.IsUsed(['system.sysutils'], 'System.SysUtils', nil));
  Assert.IsFalse(TPascalUses.IsUsed(['SysUtils'], 'System.SysUtils', nil));
  Assert.IsFalse(TPascalUses.IsUsed(['Classes'], 'System.SysUtils', ['System']));
end;

procedure TPascalUsesTests.DUnitXUses_IsTestUnit;
begin
  Assert.IsTrue(TPascalUses.IsTestUnit(TPascalLexer.Tokenize(
    'unit A.Tests;'#10'interface'#10'uses DUnitX.TestFramework;'#10'implementation'#10'end.')));
  Assert.IsTrue(TPascalUses.IsTestUnit(TPascalLexer.Tokenize(
    'unit A.Tests;'#10'interface'#10'implementation'#10'uses TestFramework;'#10'end.')));
end;

procedure TPascalUsesTests.PlainUnit_IsNotTestUnit;
begin
  Assert.IsFalse(TPascalUses.IsTestUnit(TPascalLexer.Tokenize(
    'unit A;'#10'interface'#10'uses System.SysUtils, MyTestFrameworkHelper;'#10'implementation'#10'end.')));
end;

procedure TPascalUsesTests.TestInsightNamespace_IsTestUnit;
begin
  Assert.IsTrue(TPascalUses.IsTestUnit(TPascalLexer.Tokenize(
    'program Tests;'#10'uses TestInsight.DUnitX;'#10'begin end.')));
end;

procedure TPascalUsesTests.ActiveTokens_DropsTokensOfInactiveRanges;
var
  mActive: TArray<TPascalToken>;
  mTokens: TArray<TPascalToken>;
  mInactive: TArray<TTextRange>;
begin
  // Zeile 1 "uses B;" ist inaktiv: Ihre Token beginnen im Bereich, das Ende ist ausgenommen.
  mTokens := TPascalLexer.Tokenize('uses A;'#10'uses B;'#10'uses C;');
  mInactive := [TTextRange.Create(1, 0, 2, 0)];
  mActive := TPascalUses.ActiveTokens(mTokens, mInactive);
  Assert.AreEqual('A C', string.Join(' ', TPascalUses.UsedUnits(mActive)));
  Assert.IsTrue(Length(mActive) < Length(mTokens), 'Token der inaktiven Zeile entfallen');
end;

procedure TPascalUsesTests.ActiveTokens_WithoutRanges_KeepsAll;
var
  mTokens: TArray<TPascalToken>;
begin
  mTokens := TPascalLexer.Tokenize('uses A;'#10'uses B;');
  Assert.AreEqual(Integer(Length(mTokens)), Integer(Length(TPascalUses.ActiveTokens(mTokens, nil))));
end;

initialization
  TDUnitX.RegisterTestFixture(TPascalUsesTests);

end.
