unit Atlas.Common.Rules.Builtin.Testing.TestCaseTable.Tests;

// Tests der TestCase-Tabelle (#1879): Spalten und Zeilen lesen, Zeile zur Methode finden, eigenes Trennzeichen
// und weitere Argumente behalten, Hochkommas und Steuerzeichen schreiben, mehrzeilige Attribute, Attribute
// zwischen den Fällen, nicht bearbeitbare Formen und die Prüfung je Zelle und Zeile.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestCaseTableTests = class
  public
    [Test]
    procedure ReadsColumnsAndRows;
    [Test]
    procedure FindsMethodByLine;
    [Test]
    procedure WritesAllCasesAsOneEdit;
    [Test]
    procedure KeepsSeparatorAndTrim;
    [Test]
    procedure QuotesNamesAndValues;
    [Test]
    procedure MultilineAttributeBecomesOneLine;
    [Test]
    procedure OtherAttributesBetweenMoveBefore;
    [Test]
    procedure NotEditableForms;
    [Test]
    procedure CellAndRowProblems;
    [Test]
    procedure RefusesSeparatorInValueAndEmptyTable;
    [Test]
    procedure NewerFormsKeepTheirShape;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.TextChanges,
  Atlas.Common.Rules.Builtin.Testing.TestCases,
  Atlas.Common.Rules.Builtin.Testing.TestCaseTable;

const
  cLf = #10;

/// <summary>Testunit mit den Attributen AAttributes vor der Methode Pruefe(AParameters); die Attribute beginnen
/// in Zeile 10.</summary>
function TestUnit(const AAttributes, AParameters: string): string;
begin
  Result := 'unit Fall.Tests;'#10'interface'#10'uses'#10'  DUnitX.TestFramework;'#10'type'#10 +
    '  TFarbe = (Rot, Gruen);'#10'  TStufe = (Eins = 1, Zwei = 2);'#10 +
    '  [TestFixture]'#10'  TFallTests = class'#10'  public'#10 + AAttributes + '    procedure Pruefe' + AParameters +
    ';'#10'  end;'#10'implementation'#10'procedure TFallTests.Pruefe' + AParameters + ';'#10'begin'#10 +
    '  Assert.Pass;'#10'end;'#10'end.';
end;

/// <summary>Tabelle an Zeile 10; schlägt fehl ohne.</summary>
function TableOf(const AText: string): TTestCaseTable;
var
  mTree: TSyntaxTree;
begin
  mTree := TSyntaxTreeCache.Parse(AText);
  try
    Assert.IsTrue(TTestCaseTables.Find(mTree, AText, 10, Result), 'Tabelle an Zeile 10');
  finally
    mTree.Free;
  end;
end;

/// <summary>Text nach dem Schreiben von ARows; schlägt fehl, wenn nicht geschrieben wird.</summary>
function Written(const AText: string; const ATable: TTestCaseTable; const ARows: TArray<TTestCaseRow>): string;
var
  mEdit: TTextEdit;
  mReason: string;
begin
  Assert.IsTrue(TTestCaseTables.Write(ATable, ARows, cLf, mEdit, mReason), mReason);
  Result := TTextChanges.Apply(AText, [mEdit]);
end;

function Joined(const AValues: TArray<string>): string;
begin
  Result := string.Join('|', AValues);
end;

{ TTestCaseTableTests }

procedure TTestCaseTableTests.ReadsColumnsAndRows;
var
  mTable: TTestCaseTable;
begin
  mTable := TableOf(TestUnit('    [Test]'#10'    [TestCase(''Eins'', ''1,2,Rot'')]'#10 +
    '    [TestCase(''Zwei'', ''3,x,Gruen'')]'#10, '(A, B: Integer; const AFarbe: TFarbe)'));
  Assert.AreEqual('TFallTests', mTable.Fixture);
  Assert.AreEqual('Pruefe', mTable.Method);
  Assert.AreEqual(10, mTable.FirstLine);
  Assert.AreEqual(13, mTable.MethodLine);
  Assert.AreEqual(3, Integer(Length(mTable.Columns)));
  Assert.AreEqual('B', mTable.Columns[1].Name);
  Assert.AreEqual('Integer', mTable.Columns[1].TypeName);
  Assert.IsTrue(mTable.Columns[1].Kind = TDUnitXValueKind.Integer_);
  Assert.IsTrue(mTable.Columns[2].Kind = TDUnitXValueKind.Enum);
  Assert.AreEqual('Rot,Gruen', mTable.Columns[2].EnumNames);
  Assert.AreEqual(2, mTable.Count);
  Assert.AreEqual('Zwei', mTable.Rows[1].Name);
  Assert.AreEqual('3|x|Gruen', Joined(mTable.Rows[1].Values));
  Assert.AreEqual(12, mTable.Rows[1].Line);
  Assert.IsTrue(mTable.Rows[0].Form = TTestCaseForm.Classic);
  Assert.AreEqual('TestCase', mTable.Rows[0].AttributeName);
  Assert.IsTrue(mTable.Editable, mTable.Reason);
  Assert.AreEqual('    ', mTable.Indent);
  Assert.AreEqual(11, mTable.Range.StartPos.Line);
  Assert.AreEqual(4, mTable.Range.StartPos.Character);
  Assert.AreEqual(12, mTable.Range.EndPos.Line);
end;

procedure TTestCaseTableTests.FindsMethodByLine;
var
  mText: string;
  mTree: TSyntaxTree;
  mTable: TTestCaseTable;
begin
  mText := TestUnit('    [TestCase(''A'', ''1'')]'#10, '(A: Integer)');
  mTree := TSyntaxTreeCache.Parse(mText);
  try
    Assert.IsTrue(TTestCaseTables.Find(mTree, mText, 11, mTable), 'Zeile der Deklaration');
    Assert.IsFalse(TTestCaseTables.Find(mTree, mText, 9, mTable), 'Zeile davor');
    Assert.IsFalse(TTestCaseTables.Find(mTree, mText, 12, mTable), 'Zeile danach');
    Assert.AreEqual(1, Integer(Length(TTestCaseTables.All(mTree, mText))));
  finally
    mTree.Free;
  end;
  // Ohne DUnitX in uses keine Tabelle.
  mText := StringReplace(mText, 'DUnitX.TestFramework', 'System.SysUtils', []);
  mTree := TSyntaxTreeCache.Parse(mText);
  try
    Assert.AreEqual(0, Integer(Length(TTestCaseTables.All(mTree, mText))));
  finally
    mTree.Free;
  end;
end;

procedure TTestCaseTableTests.WritesAllCasesAsOneEdit;
var
  mText: string;
  mTable: TTestCaseTable;
  mRows: TArray<TTestCaseRow>;
begin
  mText := TestUnit('    [TestCase(''Eins'',''1,2'')]'#10'    [TestCase(''Zwei'',''3,4'')]'#10, '(A, B: Integer)');
  mTable := TableOf(mText);
  // Zweite Zeile ändern, erste löschen, eine neue anhängen.
  mRows := [mTable.Rows[1], TTestCaseTables.NewRow(mTable, 'Drei', ['5', '6'])];
  mRows[0].Values := ['30', '4'];
  Assert.AreEqual(TestUnit('    [TestCase(''Zwei'', ''30,4'')]'#10'    [TestCase(''Drei'', ''5,6'')]'#10,
    '(A, B: Integer)'), Written(mText, mTable, mRows));
end;

procedure TTestCaseTableTests.KeepsSeparatorAndTrim;
var
  mText: string;
  mTable: TTestCaseTable;
begin
  mText := TestUnit('    [TestCase(''A'', ''1;2'', '';'', True)]'#10, '(A, B: Integer)');
  mTable := TableOf(mText);
  Assert.AreEqual(';', mTable.Rows[0].Separator);
  Assert.AreEqual('1|2', Joined(mTable.Rows[0].Values));
  Assert.AreEqual(', True', mTable.Rows[0].Tail);
  mTable.Rows[0].Values := ['1,5', '2'];
  Assert.AreEqual('[TestCase(''A'', ''1,5;2'', '';'', True)]', TTestCaseTables.AttributeText(mTable.Rows[0]));
  // Eine neue Zeile übernimmt Trennzeichen und Argumente der letzten.
  Assert.AreEqual('[TestCase(''B'', ''3;4'', '';'', True)]',
    TTestCaseTables.AttributeText(TTestCaseTables.NewRow(mTable, 'B', ['3', '4'])));
  // Ein ausdrückliches Komma bleibt stehen.
  mTable := TableOf(TestUnit('    [TestCase(''A'', ''1,2'', '','')]'#10, '(A, B: Integer)'));
  Assert.AreEqual('[TestCase(''A'', ''1,2'', '','')]', TTestCaseTables.AttributeText(mTable.Rows[0]));
end;

procedure TTestCaseTableTests.QuotesNamesAndValues;
var
  mText: string;
  mTable: TTestCaseTable;
begin
  mText := TestUnit('    [TestCase(''it''''s'', ''a''#9''b,x'')]'#10, '(const A, B: string)');
  mTable := TableOf(mText);
  Assert.AreEqual('it''s', mTable.Rows[0].Name);
  Assert.AreEqual('a'#9'b|x', Joined(mTable.Rows[0].Values));
  Assert.AreEqual('[TestCase(''it''''s'', ''a''#9''b,x'')]', TTestCaseTables.AttributeText(mTable.Rows[0]));
  mTable.Rows[0].Values := ['', ''];
  Assert.AreEqual('[TestCase(''it''''s'', '','')]', TTestCaseTables.AttributeText(mTable.Rows[0]));
end;

procedure TTestCaseTableTests.MultilineAttributeBecomesOneLine;
var
  mText: string;
  mTable: TTestCaseTable;
begin
  mText := TestUnit('    [TestCase(''Lang'','#10'      ''1,2'')]'#10'    [TestCase(''Kurz'', ''3,4'')]'#10,
    '(A, B: Integer)');
  mTable := TableOf(mText);
  Assert.AreEqual(2, mTable.Count);
  Assert.AreEqual('1|2', Joined(mTable.Rows[0].Values));
  Assert.AreEqual(TestUnit('    [TestCase(''Lang'', ''1,2'')]'#10'    [TestCase(''Kurz'', ''3,4'')]'#10,
    '(A, B: Integer)'), Written(mText, mTable, mTable.Rows));
end;

procedure TTestCaseTableTests.OtherAttributesBetweenMoveBefore;
var
  mText: string;
  mTable: TTestCaseTable;
begin
  mText := TestUnit('    [TestCase(''A'', ''1'')]'#10'    [Category(''Langsam'')]'#10'    [TestCase(''B'', ''2'')]'#10,
    '(A: Integer)');
  mTable := TableOf(mText);
  Assert.IsTrue(mTable.Editable, mTable.Reason);
  Assert.AreEqual(TestUnit('    [Category(''Langsam'')]'#10'    [TestCase(''A'', ''1'')]'#10 +
    '    [TestCase(''B'', ''2'')]'#10, '(A: Integer)'), Written(mText, mTable, mTable.Rows));
end;

procedure TTestCaseTableTests.NotEditableForms;
var
  mTable: TTestCaseTable;
  mEdit: TTextEdit;
  mReason: string;
begin
  mTable := TableOf(TestUnit('    [Test, TestCase(''A'', ''1'')]'#10, '(A: Integer)'));
  Assert.IsFalse(mTable.Editable, 'gemeinsame Klammer');
  Assert.Contains(mTable.Reason, 'Test, TestCase');
  Assert.IsFalse(TTestCaseTables.Write(mTable, mTable.Rows, cLf, mEdit, mReason));
  Assert.AreEqual(mTable.Reason, mReason);
  mTable := TableOf(TestUnit('    [TestCase(''A'', cWerte)]'#10, '(A: Integer)'));
  Assert.IsFalse(mTable.Editable, 'Werte als Konstante');
  Assert.AreEqual(1, mTable.Count);
  mTable := TableOf(TestUnit('    [TestCase(cName, ''1'')]'#10, '(A: Integer)'));
  Assert.IsFalse(mTable.Editable, 'Name als Konstante');
  mTable := TableOf(TestUnit('    [TestCase(''A'', ''1'')]'#10'    // Kommentar'#10'    [TestCase(''B'', ''2'')]'#10,
    '(A: Integer)'));
  Assert.IsFalse(mTable.Editable, 'Kommentar dazwischen');
end;

procedure TTestCaseTableTests.CellAndRowProblems;
var
  mTable: TTestCaseTable;
begin
  mTable := TableOf(TestUnit('    [TestCase(''A'', ''1,2'')]'#10,
    '(A: Integer; B: Double; C: Boolean; D: TFarbe; E: string)'));
  Assert.AreEqual('', TTestCaseTables.CellProblem(mTable.Columns[0], '$FF', ','));
  Assert.AreNotEqual('', TTestCaseTables.CellProblem(mTable.Columns[0], 'x', ','));
  Assert.AreEqual('', TTestCaseTables.CellProblem(mTable.Columns[1], '1.5', ','));
  Assert.AreNotEqual('', TTestCaseTables.CellProblem(mTable.Columns[1], '1.5.1', ','));
  Assert.AreNotEqual('', TTestCaseTables.CellProblem(mTable.Columns[2], 'Ja', ','));
  Assert.Contains(TTestCaseTables.CellProblem(mTable.Columns[3], 'Blau', ','), 'Rot, Gruen');
  Assert.AreEqual('', TTestCaseTables.CellProblem(mTable.Columns[4], 'frei', ','));
  // Das Trennzeichen im Wert ist bei jedem Typ ein Fehler.
  Assert.Contains(TTestCaseTables.CellProblem(mTable.Columns[4], 'a,b', ','), ',');
  Assert.AreEqual('', TTestCaseTables.CellProblem(mTable.Columns[4], 'a,b', ';'));
  Assert.Contains(TTestCaseTables.RowProblem(mTable, mTable.Rows[0]), '2');
  mTable.Rows[0].Values := ['1', '2', 'True', 'Rot', 'x'];
  Assert.AreEqual('', TTestCaseTables.RowProblem(mTable, mTable.Rows[0]));
  mTable := TableOf(TestUnit('    [TestCase(''A'', ''1'')]'#10, ''));
  Assert.Contains(TTestCaseTables.RowProblem(mTable, mTable.Rows[0]), 'Pruefe');
end;

procedure TTestCaseTableTests.RefusesSeparatorInValueAndEmptyTable;
var
  mTable: TTestCaseTable;
  mEdit: TTextEdit;
  mReason: string;
begin
  mTable := TableOf(TestUnit('    [TestCase(''A'', ''1,2'')]'#10, '(const A, B: string)'));
  Assert.IsFalse(TTestCaseTables.Write(mTable, nil, cLf, mEdit, mReason), 'keine Zeile');
  Assert.AreNotEqual('', mReason);
  mTable.Rows[0].Values := ['a,b', 'c'];
  Assert.IsFalse(TTestCaseTables.Write(mTable, mTable.Rows, cLf, mEdit, mReason), 'Trennzeichen im Wert');
  Assert.Contains(mReason, ',');
end;

procedure TTestCaseTableTests.NewerFormsKeepTheirShape;
var
  mTable: TTestCaseTable;
begin
  mTable := TableOf(TestUnit('    [TestCase(''1,2'')]'#10'    [NamedTestCase(''N'', ''3;4'', '';'')]'#10,
    '(A, B: Integer)'));
  Assert.IsTrue(mTable.Rows[0].Form = TTestCaseForm.ValuesOnly);
  Assert.IsTrue(mTable.Rows[1].Form = TTestCaseForm.Named);
  Assert.AreEqual('[TestCase(''1,2'')]', TTestCaseTables.AttributeText(mTable.Rows[0]));
  Assert.AreEqual('[NamedTestCase(''N'', ''3;4'', '';'')]', TTestCaseTables.AttributeText(mTable.Rows[1]));
end;

end.
