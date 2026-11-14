unit Atlas.Common.Editing.UsesClause.Tests;

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
    procedure ReadsUsedUnitsOfText;
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
    [Test]
    procedure DUnitXUses_IsTestUnit;
    [Test]
    procedure PlainUnit_IsNotTestUnit;
    [Test]
    procedure TestInsightNamespace_IsTestUnit;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Editing.UsesClause;

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

function Apply(const AText: string; const AEdit: TRuleEdit): string;
var
  mLines: TArray<string>;
  mLine: string;
begin
  // Einfügungen (StartPos = EndPos) in die Zeile übernehmen; die Tests brauchen nur das.
  mLines := AText.Split([#10]);
  mLine := mLines[AEdit.Range.StartPos.Line];
  Insert(AEdit.NewText, mLine, AEdit.Range.StartPos.Character + 1);
  mLines[AEdit.Range.StartPos.Line] := mLine;
  Result := string.Join(#10, mLines);
end;

function OffsetOf(const AText, AMarker: string): Integer;
begin
  Result := Pos(AMarker, AText) - 1;
end;

procedure TUsesClauseTests.ReadsUsedUnitsOfBothSections;
begin
  Assert.AreEqual('System.SysUtils Werkzeug Classes Daten.Kunden',
    string.Join(' ', TUsesClauses.UsedUnits(TPascalLexer.Tokenize(cUnitText))));
end;

procedure TUsesClauseTests.ReadsUsedUnitsOfText;
begin
  Assert.AreEqual('System.SysUtils Werkzeug Classes Daten.Kunden', string.Join(' ', TUsesClauses.UsedUnitsOf(cUnitText)));
  Assert.AreEqual(0, Integer(Length(TUsesClauses.UsedUnitsOf(''))));
end;

procedure TUsesClauseTests.ReadsReferencesWithPositions;
var
  mReferences: TArray<TUsesReference>;
  mName: string;
begin
  // Zeile 2: "uses A, B.C in 'b.pas';" – Position über alle Namensteile, ohne Pfad.
  mReferences := TUsesClauses.References(TPascalLexer.Tokenize(
    'unit U;'#10'interface'#10'uses A, B.C in ''b.pas'';'#10'implementation'#10'end.'));
  Assert.AreEqual(2, Integer(Length(mReferences)));
  mName := mReferences[1].Name;
  Assert.AreEqual('B.C', mName);
  Assert.AreEqual(2, mReferences[1].Range.StartPos.Line);
  Assert.AreEqual(8, mReferences[1].Range.StartPos.Character);
  Assert.AreEqual(11, mReferences[1].Range.EndPos.Character);
  // Packages: requires und contains, auch wenn sie als Bezeichner gelesen werden.
  mReferences := TUsesClauses.References(TPascalLexer.Tokenize(
    'package P;'#10'requires rtl;'#10'contains X in ''x.pas'', Y;'#10'end.'));
  Assert.AreEqual(3, Integer(Length(mReferences)));
  mName := mReferences[2].Name;
  Assert.AreEqual('Y', mName);
  // Art der Liste (#1109).
  Assert.AreEqual(Ord(TUsesListKind.RequiresList), Ord(mReferences[0].List));
  Assert.AreEqual(Ord(TUsesListKind.ContainsList), Ord(mReferences[1].List));
  Assert.AreEqual(Ord(TUsesListKind.ContainsList), Ord(mReferences[2].List));
  mReferences := TUsesClauses.References(TPascalLexer.Tokenize(
    'unit U;'#10'interface'#10'uses A, B.C in ''b.pas'';'#10'implementation'#10'end.'));
  Assert.AreEqual(Ord(TUsesListKind.UsesList), Ord(mReferences[0].List));
  // Abschnitt je Eintrag (#268): interface bis "implementation", in Packages und Programmen nie.
  Assert.IsTrue(mReferences[0].InInterface);
  mReferences := TUsesClauses.References(TPascalLexer.Tokenize(
    'unit U;'#10'interface'#10'uses A;'#10'type IX = interface end;'#10'implementation'#10'uses B;'#10'end.'));
  Assert.AreEqual(2, Integer(Length(mReferences)));
  Assert.IsTrue(mReferences[0].InInterface, 'A');
  Assert.IsFalse(mReferences[1].InInterface, 'B');
  mReferences := TUsesClauses.References(TPascalLexer.Tokenize('program P;'#10'uses A;'#10'begin end.'));
  Assert.IsFalse(mReferences[0].InInterface, 'Programm');
end;

procedure TUsesClauseTests.ReadsOwnName;
begin
  Assert.AreEqual('Haupt', TUsesClauses.OwnName(TPascalLexer.Tokenize(cUnitText)));
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
  mEdit: TRuleEdit;
begin
  Assert.IsTrue(TUsesClauses.AddUnit(TPascalLexer.Tokenize(cUnitText), OffsetOf(cUnitText, 'interface'),
    'Vcl.Forms', #10, mEdit));
  Assert.AreEqual('uses System.SysUtils, Werkzeug in ''Werkzeug.pas'', Vcl.Forms;', Apply(cUnitText, mEdit).Split([#10])[2]);
end;

procedure TUsesClauseTests.AppendsToMultiLineUsesOnOwnLine;
var
  mEdit: TRuleEdit;
begin
  Assert.IsTrue(TUsesClauses.AddUnit(TPascalLexer.Tokenize(cUnitText), OffsetOf(cUnitText, 'begin'), 'Vcl.Forms',
    #10, mEdit));
  Assert.IsTrue(Pos('uses'#10'  Classes,'#10'  Daten.Kunden,'#10'  Vcl.Forms;'#10'procedure',
    Apply(cUnitText, mEdit)) > 0, Apply(cUnitText, mEdit));
end;

procedure TUsesClauseTests.ChoosesImplementationSectionByOffset;
var
  mEdit: TRuleEdit;
begin
  Assert.IsTrue(TUsesClauses.AddUnit(TPascalLexer.Tokenize(cUnitText), OffsetOf(cUnitText, 'Rechne'), 'X', #10, mEdit));
  Assert.AreEqual(6, mEdit.Range.StartPos.Line);
  Assert.IsTrue(TUsesClauses.AddUnit(TPascalLexer.Tokenize(cUnitText), OffsetOf(cUnitText, 'uses System'), 'X', #10, mEdit));
  Assert.AreEqual(2, mEdit.Range.StartPos.Line);
end;

procedure TUsesClauseTests.CreatesUsesWhenMissing;
const
  cText = 'unit A;'#10'interface'#10'implementation'#10'end.';
var
  mEdit: TRuleEdit;
begin
  Assert.IsTrue(TUsesClauses.AddUnit(TPascalLexer.Tokenize(cText), OffsetOf(cText, 'end.'), 'B', #10, mEdit));
  Assert.AreEqual('unit A;'#10'interface'#10'implementation'#10#10'uses'#10'  B;'#10'end.', Apply(cText, mEdit));
end;

procedure TUsesClauseTests.AddsToProgramUses;
const
  cText = 'program App;'#10'uses A;'#10'begin'#10'end.';
var
  mEdit: TRuleEdit;
begin
  Assert.IsTrue(TUsesClauses.AddUnit(TPascalLexer.Tokenize(cText), OffsetOf(cText, 'end.'), 'B', #10, mEdit));
  Assert.AreEqual('program App;'#10'uses A, B;'#10'begin'#10'end.', Apply(cText, mEdit));
end;

procedure TUsesClauseTests.FailsWithoutSection;
var
  mEdit: TRuleEdit;
begin
  Assert.IsFalse(TUsesClauses.AddUnit(TPascalLexer.Tokenize(''), 0, 'B', #10, mEdit));
  Assert.IsFalse(TUsesClauses.AddUnit(TPascalLexer.Tokenize('unit A;'#10'type'), 0, 'B', #10, mEdit));
end;

/// <summary>Offset ab 0 zu einer Position; Zeilenwechsel #10.</summary>
function TextOffset(const AText: string; const APosition: TTextPosition): Integer;
var
  mLine: Integer;
begin
  Result := 0;
  mLine := 0;
  while mLine < APosition.Line do
  begin
    Inc(Result);
    if AText[Result] = #10 then
    begin
      Inc(mLine);
    end;
  end;
  Result := Result + APosition.Character;
end;

/// <summary>Edits (auch Ersetzungen) von hinten nach vorn anwenden, damit die Positionen gültig bleiben.</summary>
function ApplyAll(const AText: string; const AEdits: TArray<TRuleEdit>): string;
var
  mIndex, mStartOffset, mEndOffset: Integer;
begin
  Result := AText;
  for mIndex := High(AEdits) downto 0 do
  begin
    mStartOffset := TextOffset(Result, AEdits[mIndex].Range.StartPos);
    mEndOffset := TextOffset(Result, AEdits[mIndex].Range.EndPos);
    Result := Copy(Result, 1, mStartOffset) + AEdits[mIndex].NewText + Copy(Result, mEndOffset + 1, MaxInt);
  end;
end;

function Organized(const AText: string; ASort: Boolean): string;
var
  mEdits: TArray<TRuleEdit>;
begin
  if TUsesClauses.Organize(TPascalLexer.Tokenize(AText), AText, ASort, #10, mEdits) then
  begin
    Result := ApplyAll(AText, mEdits);
  end
  else
  begin
    Result := AText;
  end;
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
  cText = 'unit A;'#10'interface'#10'uses Z, {$IFDEF X} Y, {$ENDIF} A;'#10'implementation'#10'end.';
begin
  Assert.AreEqual(cText, Organized(cText, True));
end;

procedure TUsesClauseTests.OrganizeWithoutChangeGivesNothing;
var
  mEdits: TArray<TRuleEdit>;
const
  cText = 'unit A;'#10'interface'#10'uses A1, B2;'#10'implementation'#10'end.';
begin
  Assert.IsFalse(TUsesClauses.Organize(TPascalLexer.Tokenize(cText), cText, True, #10, mEdits));
end;

procedure TUsesClauseTests.DUnitXUses_IsTestUnit;
begin
  Assert.IsTrue(TUsesClauses.IsTestUnit(TPascalLexer.Tokenize(
    'unit A.Tests;'#10'interface'#10'uses DUnitX.TestFramework;'#10'implementation'#10'end.')));
  Assert.IsTrue(TUsesClauses.IsTestUnit(TPascalLexer.Tokenize(
    'unit A.Tests;'#10'interface'#10'implementation'#10'uses TestFramework;'#10'end.')));
end;

procedure TUsesClauseTests.PlainUnit_IsNotTestUnit;
begin
  Assert.IsFalse(TUsesClauses.IsTestUnit(TPascalLexer.Tokenize(
    'unit A;'#10'interface'#10'uses System.SysUtils, MyTestFrameworkHelper;'#10'implementation'#10'end.')));
end;

procedure TUsesClauseTests.TestInsightNamespace_IsTestUnit;
begin
  Assert.IsTrue(TUsesClauses.IsTestUnit(TPascalLexer.Tokenize(
    'program Tests;'#10'uses TestInsight.DUnitX;'#10'begin end.')));
end;

initialization
  TDUnitX.RegisterTestFixture(TUsesClauseTests);

end.
