unit Argus.Common.Editing.UsesClause.Tests;

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
    procedure ReadsReferencesWithPositions;
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
    [Test]
    procedure OrganizeRemovesDuplicates;
    [Test]
    procedure OrganizeSortsMultilineList;
    [Test]
    procedure OrganizeDropsEmptiedClause;
    [Test]
    procedure OrganizeKeepsListsWithDirectives;
    [Test]
    procedure OrganizeWithoutChangeGivesNothing;
  end;

implementation

uses
  System.SysUtils,
  Argus.Common.Documents.Contract,
  Argus.Common.Pascal.Contract,
  Argus.Common.Pascal.Lexer,
  Argus.Common.Rules.Contract,
  Argus.Common.Editing.UsesClause;

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

procedure TUsesClauseTests.ReadsReferencesWithPositions;
var
  References: TArray<TUsesReference>;
  Name: string;
begin
  // Zeile 2: "uses A, B.C in 'b.pas';" – Position über alle Namensteile, ohne Pfad.
  References := TUsesClauses.References(TPascalLexer.Tokenize(
    'unit U;'#10'interface'#10'uses A, B.C in ''b.pas'';'#10'implementation'#10'end.'));
  Assert.AreEqual(2, Integer(Length(References)));
  Name := References[1].Name;
  Assert.AreEqual('B.C', Name);
  Assert.AreEqual(2, References[1].Range.StartPos.Line);
  Assert.AreEqual(8, References[1].Range.StartPos.Character);
  Assert.AreEqual(11, References[1].Range.EndPos.Character);
  // Packages: requires und contains, auch wenn sie als Bezeichner gelesen werden.
  References := TUsesClauses.References(TPascalLexer.Tokenize(
    'package P;'#10'requires rtl;'#10'contains X in ''x.pas'', Y;'#10'end.'));
  Assert.AreEqual(3, Integer(Length(References)));
  Name := References[2].Name;
  Assert.AreEqual('Y', Name);
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

/// <summary>Offset ab 0 zu einer Position; Zeilenwechsel #10.</summary>
function TextOffset(const AText: string; const APosition: TTextPosition): Integer;
var
  Line: Integer;
begin
  Result := 0;
  Line := 0;
  while Line < APosition.Line do
  begin
    Inc(Result);
    if AText[Result] = #10 then
      Inc(Line);
  end;
  Result := Result + APosition.Character;
end;

/// <summary>Edits (auch Ersetzungen) von hinten nach vorn anwenden, damit die Positionen gültig bleiben.</summary>
function ApplyAll(const AText: string; const AEdits: TArray<TRuleEdit>): string;
var
  Index, StartOffset, EndOffset: Integer;
begin
  Result := AText;
  for Index := High(AEdits) downto 0 do
  begin
    StartOffset := TextOffset(Result, AEdits[Index].Range.StartPos);
    EndOffset := TextOffset(Result, AEdits[Index].Range.EndPos);
    Result := Copy(Result, 1, StartOffset) + AEdits[Index].NewText + Copy(Result, EndOffset + 1, MaxInt);
  end;
end;

function Organized(const AText: string; ASort: Boolean): string;
var
  Edits: TArray<TRuleEdit>;
begin
  if TUsesClauses.Organize(TPascalLexer.Tokenize(AText), AText, ASort, #10, Edits) then
    Result := ApplyAll(AText, Edits)
  else
    Result := AText;
end;

procedure TUsesClauseTests.OrganizeRemovesDuplicates;
begin
  Assert.AreEqual('unit A;'#10'interface'#10'uses B, C;'#10'implementation'#10'uses D;'#10'end.',
    Organized('unit A;'#10'interface'#10'uses B, C, b;'#10'implementation'#10'uses C, D;'#10'end.', False));
end;

procedure TUsesClauseTests.OrganizeSortsMultilineList;
begin
  Assert.AreEqual('program P;'#10'uses'#10'  Alpha,'#10'  Main in ''Main.pas'' {Form1},'#10'  Zeta;'#10'begin end.',
    Organized('program P;'#10'uses'#10'  Zeta,'#10'  Main in ''Main.pas'' {Form1},'#10'  Alpha;'#10'begin end.', True));
end;

procedure TUsesClauseTests.OrganizeDropsEmptiedClause;
begin
  Assert.AreEqual('unit A;'#10'interface'#10'uses B;'#10'implementation'#10#10'end.',
    Organized('unit A;'#10'interface'#10'uses B;'#10'implementation'#10'uses B;'#10'end.', False));
end;

procedure TUsesClauseTests.OrganizeKeepsListsWithDirectives;
const
  Text = 'unit A;'#10'interface'#10'uses Z, {$IFDEF X} Y, {$ENDIF} A;'#10'implementation'#10'end.';
begin
  Assert.AreEqual(Text, Organized(Text, True));
end;

procedure TUsesClauseTests.OrganizeWithoutChangeGivesNothing;
var
  Edits: TArray<TRuleEdit>;
const
  Text = 'unit A;'#10'interface'#10'uses A1, B2;'#10'implementation'#10'end.';
begin
  Assert.IsFalse(TUsesClauses.Organize(TPascalLexer.Tokenize(Text), Text, True, #10, Edits));
end;

initialization
  TDUnitX.RegisterTestFixture(TUsesClauseTests);

end.
