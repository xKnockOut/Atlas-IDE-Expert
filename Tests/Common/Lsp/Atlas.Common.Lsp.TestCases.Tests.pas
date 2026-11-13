unit Atlas.Common.Lsp.TestCases.Tests;

// Befehl atlas.server.testCases (#1879): Tabelle als JSON, Vorschlag mit Edit und Fehlern je Zelle, null ohne
// [TestCase]-Methode, Fehler ohne URI oder bei unlesbarem Dokument.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspTestCasesTests = class
  public
    [Test]
    procedure TableAsJson;
    [Test]
    procedure ProposalWithEdit;
    [Test]
    procedure ProposalRefusedNamesReason;
    [Test]
    procedure NullWithoutTestCases;
    [Test]
    procedure InvalidArguments;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Lsp.TestCases;

const
  cUri = 'file:///C:/P/Fall.Tests.pas';
  cBreak = #13#10;
  cText = 'unit Fall.Tests;' + cBreak + 'interface' + cBreak + 'uses' + cBreak + '  DUnitX.TestFramework;' + cBreak +
    'type' + cBreak + '  [TestFixture]' + cBreak + '  TFallTests = class' + cBreak + '  public' + cBreak +
    '    [TestCase(''Eins'', ''1,x'')]' + cBreak + '    [TestCase(''Zwei'', ''2,3'')]' + cBreak +
    '    procedure Pruefe(A, B: Integer);' + cBreak + '  end;' + cBreak + 'implementation' + cBreak +
    'procedure TFallTests.Pruefe(A, B: Integer);' + cBreak + 'begin' + cBreak + 'end;' + cBreak + 'end.';

/// <summary>Führt den Befehl mit AArguments (JSON-Text) auf cText aus; der Aufrufer gibt das Ergebnis frei.
/// </summary>
function Run(const AArguments: string): TJSONValue;
var
  mArguments: TJSONArray;
begin
  mArguments := TJSONObject.ParseJSONValue(AArguments) as TJSONArray;
  try
    Result := TLspTestCases.Execute(mArguments,
      function(const AUri: string; out AText: string): Boolean
      begin
        AText := cText;
        Result := AUri = cUri;
      end);
  finally
    mArguments.Free;
  end;
end;

/// <summary>Element AIndex des Arrays AName von AObject (ohne Pfade mit [n], die FPC nicht kennt).</summary>
function Item(AObject: TJSONObject; const AName: string; AIndex: Integer): TJSONValue;
begin
  Result := (AObject.GetValue(AName) as TJSONArray).Items[AIndex];
end;

function Entry(AObject: TJSONObject; const AName: string; AIndex: Integer): TJSONObject;
begin
  Result := Item(AObject, AName, AIndex) as TJSONObject;
end;

{ TLspTestCasesTests }

procedure TLspTestCasesTests.TableAsJson;
var
  mResult: TJSONValue;
  mObject, mRow: TJSONObject;
begin
  mResult := Run('["' + cUri + '", 10]');
  try
    mObject := mResult as TJSONObject;
    Assert.AreEqual('TFallTests', mObject.GetValue<string>('fixture'));
    Assert.AreEqual('Pruefe', mObject.GetValue<string>('method'));
    Assert.AreEqual(10, mObject.GetValue<Integer>('methodLine'));
    Assert.AreEqual(8, mObject.GetValue<Integer>('firstLine'));
    Assert.IsTrue(mObject.GetValue<Boolean>('editable'));
    Assert.AreEqual('integer', Entry(mObject, 'columns', 1).GetValue<string>('kind'));
    Assert.AreEqual('B', Entry(mObject, 'columns', 1).GetValue<string>('name'));
    mRow := Entry(mObject, 'rows', 0);
    Assert.AreEqual('Eins', mRow.GetValue<string>('name'));
    Assert.AreEqual('x', Item(mRow, 'values', 1).Value);
    Assert.AreEqual('classic', mRow.GetValue<string>('form'));
    Assert.AreEqual(8, mRow.GetValue<Integer>('line'));
    Assert.AreEqual('', mRow.GetValue<string>('problem'));
    Assert.AreEqual('', Item(mRow, 'cells', 0).Value);
    Assert.AreNotEqual('', Item(mRow, 'cells', 1).Value);
  finally
    mResult.Free;
  end;
end;

procedure TLspTestCasesTests.ProposalWithEdit;
var
  mResult: TJSONValue;
  mObject, mEdit: TJSONObject;
begin
  mResult := Run('["' + cUri + '", 8, [{"from": 1, "name": "Zwei", "values": ["2", "4"]}, ' +
    '{"from": -1, "name": "Neu", "values": ["5", "y"]}]]');
  try
    mObject := mResult as TJSONObject;
    mEdit := Entry(mObject.GetValue<TJSONObject>('edit.changes'), cUri, 0);
    Assert.AreEqual(8, mEdit.GetValue<Integer>('range.start.line'));
    Assert.AreEqual(4, mEdit.GetValue<Integer>('range.start.character'));
    Assert.AreEqual(9, mEdit.GetValue<Integer>('range.end.line'));
    Assert.AreEqual('[TestCase(''Zwei'', ''2,4'')]' + cBreak + '    [TestCase(''Neu'', ''5,y'')]',
      mEdit.GetValue<string>('newText'));
    Assert.AreEqual('', Item(Entry(mObject, 'proposed', 0), 'cells', 1).Value);
    Assert.AreNotEqual('', Item(Entry(mObject, 'proposed', 1), 'cells', 1).Value);
    Assert.AreEqual('', mObject.GetValue<string>('editReason'));
  finally
    mResult.Free;
  end;
end;

procedure TLspTestCasesTests.ProposalRefusedNamesReason;
var
  mResult: TJSONValue;
  mObject: TJSONObject;
begin
  mResult := Run('["' + cUri + '", 8, [{"from": 0, "name": "Eins", "values": ["1,5", "2"]}]]');
  try
    mObject := mResult as TJSONObject;
    Assert.IsTrue(mObject.GetValue('edit') is TJSONNull);
    Assert.AreNotEqual('', mObject.GetValue<string>('editReason'));
    Assert.AreNotEqual('', Item(Entry(mObject, 'proposed', 0), 'cells', 0).Value);
  finally
    mResult.Free;
  end;
end;

procedure TLspTestCasesTests.NullWithoutTestCases;
var
  mResult: TJSONValue;
begin
  mResult := Run('["' + cUri + '", 2]');
  try
    Assert.IsTrue(mResult is TJSONNull);
  finally
    mResult.Free;
  end;
end;

procedure TLspTestCasesTests.InvalidArguments;
begin
  Assert.WillRaise(
    procedure
    begin
      Run('["' + cUri + '"]').Free;
    end, EJsonRpcError);
  Assert.WillRaise(
    procedure
    begin
      Run('["file:///C:/P/Andere.pas", 8]').Free;
    end, EJsonRpcError);
end;

end.
