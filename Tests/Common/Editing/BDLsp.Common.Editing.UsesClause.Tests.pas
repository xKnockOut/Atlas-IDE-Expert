unit BDLsp.Common.Editing.UsesClause.Tests;

// Tests für das Lesen und Ergänzen von uses-Listen (#180).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TUsesClauseTests = class
  public
    [Test]
    procedure ReadsUsedUnitsOfBothSections;
    [Test]
    procedure ReadsOwnName;
    [Test]
    procedure KnowsUnitsWithoutNamespace;
    [Test]
    procedure AppendsToSingleLineUses;
    [Test]
    procedure AppendsToMultiLineUsesOnOwnLine;
    [Test]
    procedure ChoosesImplementationSectionByOffset;
    [Test]
    procedure CreatesUsesWhenMissing;
    [Test]
    procedure AddsToProgramUses;
    [Test]
    procedure FailsWithoutSection;
  end;

implementation

uses
  System.SysUtils,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Pascal.Contract,
  BDLsp.Common.Pascal.Lexer,
  BDLsp.Common.Rules.Contract,
  BDLsp.Common.Editing.UsesClause;

const
  UnitText =
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

function Apply(const AText: string; const AEdit: TRuleEdit): string;
var
  Lines: TArray<string>;
  Line: string;
begin
  // Einfügungen (StartPos = EndPos) in die Zeile übernehmen; die Tests brauchen nur das.
  Lines := AText.Split([#10]);
  Line := Lines[AEdit.Range.StartPos.Line];
  Insert(AEdit.NewText, Line, AEdit.Range.StartPos.Character + 1);
  Lines[AEdit.Range.StartPos.Line] := Line;
  Result := string.Join(#10, Lines);
end;

function OffsetOf(const AText, AMarker: string): Integer;
begin
  Result := Pos(AMarker, AText) - 1;
end;

procedure TUsesClauseTests.ReadsUsedUnitsOfBothSections;
begin
  Assert.AreEqual('System.SysUtils Werkzeug Classes Daten.Kunden',
    string.Join(' ', TUsesClauses.UsedUnits(TPascalLexer.Tokenize(UnitText))));
end;

procedure TUsesClauseTests.ReadsOwnName;
begin
  Assert.AreEqual('Haupt', TUsesClauses.OwnName(TPascalLexer.Tokenize(UnitText)));
  Assert.AreEqual('App.Main', TUsesClauses.OwnName(TPascalLexer.Tokenize('program App.Main;'#10'begin'#10'end.')));
end;

procedure TUsesClauseTests.KnowsUnitsWithoutNamespace;
begin
  Assert.IsTrue(TUsesClauses.IsUsed(['SysUtils'], 'System.SysUtils', ['System', 'Vcl']));
  Assert.IsTrue(TUsesClauses.IsUsed(['system.sysutils'], 'System.SysUtils', nil));
  Assert.IsFalse(TUsesClauses.IsUsed(['SysUtils'], 'System.SysUtils', nil));
  Assert.IsFalse(TUsesClauses.IsUsed(['Classes'], 'System.SysUtils', ['System']));
end;

procedure TUsesClauseTests.AppendsToSingleLineUses;
var
  Edit: TRuleEdit;
begin
  Assert.IsTrue(TUsesClauses.AddUnit(TPascalLexer.Tokenize(UnitText), OffsetOf(UnitText, 'interface'),
    'Vcl.Forms', #10, Edit));
  Assert.AreEqual('uses System.SysUtils, Werkzeug in ''Werkzeug.pas'', Vcl.Forms;', Apply(UnitText, Edit).Split([#10])[2]);
end;

procedure TUsesClauseTests.AppendsToMultiLineUsesOnOwnLine;
var
  Edit: TRuleEdit;
begin
  Assert.IsTrue(TUsesClauses.AddUnit(TPascalLexer.Tokenize(UnitText), OffsetOf(UnitText, 'begin'), 'Vcl.Forms',
    #10, Edit));
  Assert.IsTrue(Pos('uses'#10'  Classes,'#10'  Daten.Kunden,'#10'  Vcl.Forms;'#10'procedure',
    Apply(UnitText, Edit)) > 0, Apply(UnitText, Edit));
end;

procedure TUsesClauseTests.ChoosesImplementationSectionByOffset;
var
  Edit: TRuleEdit;
begin
  Assert.IsTrue(TUsesClauses.AddUnit(TPascalLexer.Tokenize(UnitText), OffsetOf(UnitText, 'Rechne'), 'X', #10, Edit));
  Assert.AreEqual(6, Edit.Range.StartPos.Line);
  Assert.IsTrue(TUsesClauses.AddUnit(TPascalLexer.Tokenize(UnitText), OffsetOf(UnitText, 'uses System'), 'X', #10, Edit));
  Assert.AreEqual(2, Edit.Range.StartPos.Line);
end;

procedure TUsesClauseTests.CreatesUsesWhenMissing;
const
  Text = 'unit A;'#10'interface'#10'implementation'#10'end.';
var
  Edit: TRuleEdit;
begin
  Assert.IsTrue(TUsesClauses.AddUnit(TPascalLexer.Tokenize(Text), OffsetOf(Text, 'end.'), 'B', #10, Edit));
  Assert.AreEqual('unit A;'#10'interface'#10'implementation'#10#10'uses'#10'  B;'#10'end.', Apply(Text, Edit));
end;

procedure TUsesClauseTests.AddsToProgramUses;
const
  Text = 'program App;'#10'uses A;'#10'begin'#10'end.';
var
  Edit: TRuleEdit;
begin
  Assert.IsTrue(TUsesClauses.AddUnit(TPascalLexer.Tokenize(Text), OffsetOf(Text, 'end.'), 'B', #10, Edit));
  Assert.AreEqual('program App;'#10'uses A, B;'#10'begin'#10'end.', Apply(Text, Edit));
end;

procedure TUsesClauseTests.FailsWithoutSection;
var
  Edit: TRuleEdit;
begin
  Assert.IsFalse(TUsesClauses.AddUnit(TPascalLexer.Tokenize(''), 0, 'B', #10, Edit));
  Assert.IsFalse(TUsesClauses.AddUnit(TPascalLexer.Tokenize('unit A;'#10'type'), 0, 'B', #10, Edit));
end;

initialization
  TDUnitX.RegisterTestFixture(TUsesClauseTests);

end.
