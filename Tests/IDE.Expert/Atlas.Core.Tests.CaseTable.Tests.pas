unit Atlas.Core.Tests.CaseTable.Tests;

// Daten der TestCase-Tabelle (#1879): Antwort des Servers lesen, Anfrage mit Zeilen bauen, Zeilen bearbeiten
// (Zelle, neu, löschen, verschieben), Fehler und Edit des Vorschlags übernehmen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tests')]
  TAtlasTestCaseTableTests = class
  public
    [Test]
    procedure ParsesTable;
    [Test]
    procedure NullIsNoTable;
    [Test]
    procedure ProposalRequestKeepsOrigin;
    [Test]
    procedure ParsesProposal;
    [Test]
    procedure EditsRows;
    [Test]
    procedure DetectsChanges;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Tests.CaseTable;

const
  cAnswer = '{"uri":"file:///C:/P/T.pas","fixture":"TFallTests","method":"Pruefe","methodLine":10,' +
    '"firstLine":8,"editable":true,"reason":"",' +
    '"columns":[{"name":"A","type":"Integer","kind":"integer","enumNames":""},' +
    '{"name":"F","type":"TFarbe","kind":"enum","enumNames":"Rot,Gruen"}],' +
    '"rows":[{"name":"Eins","values":["1","Rot"],"separator":",","form":"classic","line":8,"problem":"",' +
    '"cells":["",""]},{"name":"Zwei","values":["x","Rot","9"],"separator":",","form":"classic","line":9,' +
    '"problem":"3 Werte","cells":["Keine Ganzzahl","",""]}]}';

function Table: TAtlasTestCaseTable;
begin
  Assert.IsTrue(TAtlasTestCaseTables.Parse(cAnswer, Result));
end;

{ TAtlasTestCaseTableTests }

procedure TAtlasTestCaseTableTests.ParsesTable;
var
  mTable: TAtlasTestCaseTable;
begin
  mTable := Table;
  Assert.AreEqual('TFallTests', mTable.Fixture);
  Assert.AreEqual('Pruefe', mTable.Method);
  Assert.AreEqual(10, mTable.MethodLine);
  Assert.IsTrue(mTable.Editable);
  Assert.AreEqual('A: Integer', mTable.Header(0));
  Assert.AreEqual('Rot,Gruen', mTable.Columns[1].EnumNames);
  // Die zweite Zeile hat einen Wert zu viel: eine Spalte mehr als Parameter.
  Assert.AreEqual(3, mTable.ValueColumns);
  Assert.AreEqual('#3', mTable.Header(2));
  Assert.AreEqual(1, mTable.Rows[1].From);
  Assert.AreEqual(9, mTable.Rows[1].Line);
  Assert.AreEqual('9', mTable.Rows[1].Value(2));
  Assert.AreEqual('', mTable.Rows[0].Value(2));
  Assert.AreEqual('Keine Ganzzahl', mTable.Rows[1].CellProblem(0));
  Assert.AreEqual('3 Werte', mTable.Rows[1].Problem);
  Assert.IsTrue(TAtlasTestCaseTables.HasProblems(mTable.Rows));
end;

procedure TAtlasTestCaseTableTests.NullIsNoTable;
var
  mTable: TAtlasTestCaseTable;
begin
  Assert.IsFalse(TAtlasTestCaseTables.Parse('null', mTable));
  Assert.IsFalse(TAtlasTestCaseTables.Parse('kein JSON', mTable));
end;

procedure TAtlasTestCaseTableTests.ProposalRequestKeepsOrigin;
var
  mRows: TArray<TAtlasTestCaseRow>;
  mValue: TJSONValue;
  mArguments, mSent: TJSONArray;
  mFirst: TJSONObject;
begin
  Assert.AreEqual('["file:///C:/P/T.pas",8]', TAtlasTestCaseTables.RequestJson('file:///C:/P/T.pas', 8));
  mRows := Copy(Table.Rows);
  TAtlasTestCaseTables.Move(mRows, 1, -1);
  mValue := TJSONObject.ParseJSONValue(TAtlasTestCaseTables.ProposalJson('file:///C:/P/T.pas', 8, mRows));
  try
    mArguments := mValue as TJSONArray;
    Assert.AreEqual(3, mArguments.Count);
    mSent := mArguments.Items[2] as TJSONArray;
    mFirst := mSent.Items[0] as TJSONObject;
    Assert.AreEqual(1, mFirst.GetValue<Integer>('from'));
    Assert.AreEqual('Zwei', mFirst.GetValue<string>('name'));
    Assert.AreEqual(3, (mFirst.GetValue('values') as TJSONArray).Count);
  finally
    mValue.Free;
  end;
end;

procedure TAtlasTestCaseTableTests.ParsesProposal;
var
  mProposal: TAtlasTestCaseProposal;
  mRows: TArray<TAtlasTestCaseRow>;
begin
  Assert.IsTrue(TAtlasTestCaseTables.ParseProposal('{"proposed":[{"problem":"","cells":["",""]},' +
    '{"problem":"","cells":["","Kein Wert"]}],"edit":{"changes":{"file:///C:/P/T.pas":[]}},"editReason":""}',
    mProposal));
  Assert.Contains(mProposal.EditJson, 'changes');
  mRows := Copy(Table.Rows);
  TAtlasTestCaseTables.TakeProblems(mRows, mProposal);
  Assert.AreEqual('', mRows[1].Problem);
  Assert.AreEqual('', mRows[1].CellProblem(0));
  Assert.AreEqual('Kein Wert', mRows[1].CellProblem(1));
  Assert.IsTrue(TAtlasTestCaseTables.ParseProposal('{"proposed":[],"edit":null,"editReason":"Grund"}', mProposal));
  Assert.AreEqual('', mProposal.EditJson);
  Assert.AreEqual('Grund', mProposal.Reason);
end;

procedure TAtlasTestCaseTableTests.EditsRows;
var
  mTable: TAtlasTestCaseTable;
  mRows: TArray<TAtlasTestCaseRow>;
  mRow: TAtlasTestCaseRow;
begin
  mTable := Table;
  mRows := Copy(mTable.Rows);
  mRow := TAtlasTestCaseTables.NewRow(mTable);
  Assert.AreEqual(-1, mRow.From);
  Assert.AreEqual(2, Integer(Length(mRow.Values)));
  TAtlasTestCaseTables.SetValue(mRow, 3, 'z');
  Assert.AreEqual(4, Integer(Length(mRow.Values)));
  Assert.AreEqual('z', mRow.Value(3));
  mRows := mRows + [mRow];
  Assert.IsFalse(TAtlasTestCaseTables.Move(mRows, 0, -1), 'nach oben aus der Tabelle');
  Assert.IsTrue(TAtlasTestCaseTables.Move(mRows, 2, -2));
  Assert.AreEqual(-1, mRows[0].From);
  Assert.AreEqual('Eins', mRows[1].Name);
  Assert.IsTrue(TAtlasTestCaseTables.Delete(mRows, 0));
  Assert.IsTrue(TAtlasTestCaseTables.Delete(mRows, 0));
  Assert.IsFalse(TAtlasTestCaseTables.Delete(mRows, 0), 'die letzte Zeile bleibt');
  Assert.AreEqual('Zwei', mRows[0].Name);
end;

procedure TAtlasTestCaseTableTests.DetectsChanges;
var
  mTable: TAtlasTestCaseTable;
  mRows: TArray<TAtlasTestCaseRow>;
begin
  mTable := Table;
  mRows := Copy(mTable.Rows);
  Assert.IsFalse(TAtlasTestCaseTables.Changed(mTable, mRows));
  TAtlasTestCaseTables.SetValue(mRows[0], 0, '2');
  Assert.IsTrue(TAtlasTestCaseTables.Changed(mTable, mRows), 'Wert');
  mRows := Copy(mTable.Rows);
  TAtlasTestCaseTables.Move(mRows, 0, 1);
  Assert.IsTrue(TAtlasTestCaseTables.Changed(mTable, mRows), 'Reihenfolge');
end;

end.
