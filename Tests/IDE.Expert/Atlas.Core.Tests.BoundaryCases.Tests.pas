unit Atlas.Core.Tests.BoundaryCases.Tests;

// Daten von „Grenzfälle vorschlagen …“ (#2173): Vorschlag lesen (Namen, Vorauswahl), Anfrage der Übernahme
// bauen, Antwort lesen, heutiges Ergebnis in die Spalte AExpected eintragen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tests')]
  TAtlasBoundaryCasesTests = class
  public
    [Test]
    procedure ParsesSuggestion;
    [Test]
    procedure NullIsNoSuggestion;
    [Test]
    [TestCase('Zahl', 'AMenge,99,AMenge 99')]
    [TestCase('Komma', 'AWert,0.5,AWert 0_5')]
    [TestCase('Leer', 'AText,,AText leer')]
    procedure NamesCase(const AParameter, AValue, AExpected: string);
    [Test]
    procedure ApplyRequestHasChosenCases;
    [Test]
    procedure ParsesApplied;
    [Test]
    procedure TodayFillsOnlyOpenNewRows;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Text.TestResults,
  Atlas.Core.Tests.CaseTable,
  Atlas.Core.Tests.BoundaryCases;

const
  cAnswer = '{"uri":"file:///C:/P/Rabatt.pas","routine":"Rabatt","resultType":"Integer","line":3,' +
    '"truncated":true,"parameters":[{"name":"ABetrag","type":"Integer","kind":"ordinal","neutral":"0"},' +
    '{"name":"AKunde","type":"TObject","kind":"reference","neutral":"nil"}],' +
    '"cases":[{"parameter":0,"value":"99","reason":"ABetrag >= 100","line":6,"testCase":true,' +
    '"values":["99","0"]},{"parameter":1,"value":"nil","reason":"AKunde <> nil","line":6,"testCase":false,' +
    '"values":["0","nil"]}]}';

function Suggestion: TAtlasBoundarySuggestion;
begin
  Assert.IsTrue(TAtlasBoundaryCases.Parse(cAnswer, Result));
end;

{ TAtlasBoundaryCasesTests }

procedure TAtlasBoundaryCasesTests.ParsesSuggestion;
var
  mSuggestion: TAtlasBoundarySuggestion;
begin
  mSuggestion := Suggestion;
  Assert.AreEqual('Rabatt', mSuggestion.Routine);
  Assert.IsTrue(mSuggestion.HasResult);
  Assert.IsTrue(mSuggestion.Truncated);
  Assert.AreEqual(2, Integer(Length(mSuggestion.Parameters)));
  Assert.AreEqual('TObject', mSuggestion.Parameters[1].TypeName);
  Assert.AreEqual(2, Integer(Length(mSuggestion.Cases)));
  Assert.AreEqual('ABetrag 99', mSuggestion.Cases[0].Name);
  Assert.IsTrue(mSuggestion.Cases[0].Use, 'passt: vorab gewählt');
  Assert.IsFalse(mSuggestion.Cases[1].Use, 'nil passt in kein [TestCase]');
  Assert.AreEqual('nil', mSuggestion.Cases[1].Values[1]);
  Assert.AreEqual(1, Integer(Length(TAtlasBoundaryCases.Chosen(mSuggestion.Cases))));
end;

procedure TAtlasBoundaryCasesTests.NullIsNoSuggestion;
var
  mSuggestion: TAtlasBoundarySuggestion;
begin
  Assert.IsFalse(TAtlasBoundaryCases.Parse('null', mSuggestion));
  Assert.IsFalse(TAtlasBoundaryCases.Parse('', mSuggestion));
end;

procedure TAtlasBoundaryCasesTests.NamesCase(const AParameter, AValue, AExpected: string);
begin
  Assert.AreEqual(AExpected, TAtlasBoundaryCases.CaseName(AParameter, AValue));
end;

procedure TAtlasBoundaryCasesTests.ApplyRequestHasChosenCases;
var
  mCases: TArray<TAtlasBoundaryCase>;
  mOptions: TAtlasBoundaryApply;
  mValue: TJSONValue;
  mArray: TJSONArray;
  mCase: TJSONObject;
begin
  mCases := TAtlasBoundaryCases.Chosen(Suggestion.Cases);
  mCases[0].Expected := ' 5 ';
  mOptions := Default(TAtlasBoundaryApply);
  mOptions.Comment := 'heutiges Verhalten, nicht geprüft';
  mOptions.Placeholders := True;
  mValue := TJSONObject.ParseJSONValue(TAtlasBoundaryCases.ApplyJson('file:///C:/P/Rabatt.pas', 6, mCases,
    mOptions));
  try
    mArray := mValue as TJSONArray;
    Assert.AreEqual(5, mArray.Count);
    Assert.AreEqual(6, (mArray.Items[1] as TJSONNumber).AsInt);
    Assert.AreEqual(1, (mArray.Items[2] as TJSONArray).Count);
    mCase := (mArray.Items[2] as TJSONArray).Items[0] as TJSONObject;
    Assert.AreEqual('ABetrag 99', mCase.GetValue<string>('name'));
    Assert.AreEqual('5', mCase.GetValue<string>('expected'));
    Assert.AreEqual(2, (mCase.GetValue('values') as TJSONArray).Count);
    Assert.AreEqual('heutiges Verhalten, nicht geprüft', mArray.Items[3].Value);
    Assert.AreEqual('true', mArray.Items[4].ToJSON);
  finally
    mValue.Free;
  end;
end;

procedure TAtlasBoundaryCasesTests.ParsesApplied;
var
  mApplied: TAtlasBoundaryApplied;
begin
  Assert.IsTrue(TAtlasBoundaryCases.ParseApplied('{"uri":"file:///C:/P/T.pas","method":"TestRabattCases",' +
    '"appended":true,"edit":{"changes":{}},"reason":""}', mApplied));
  Assert.AreEqual('TestRabattCases', mApplied.Method);
  Assert.IsTrue(mApplied.Appended);
  Assert.AreEqual('{"changes":{}}', mApplied.EditJson);
  Assert.IsTrue(TAtlasBoundaryCases.ParseApplied('{"uri":"","method":"","appended":false,"edit":null,' +
    '"reason":"Keine Testunit"}', mApplied));
  Assert.AreEqual('', mApplied.EditJson);
  Assert.AreEqual('Keine Testunit', mApplied.Reason);
end;

function CaseResult(const AMethod, ACase, AActual: string; AHasValues: Boolean): TTestCaseResult;
begin
  Result := Default(TTestCaseResult);
  Result.Method := AMethod;
  Result.CaseName := ACase;
  Result.Outcome := TTestOutcome.Failed;
  Result.Expected := '0';
  Result.Actual := AActual;
  Result.HasValues := AHasValues;
end;

procedure TAtlasBoundaryCasesTests.TodayFillsOnlyOpenNewRows;
const
  cTable = '{"uri":"file:///C:/P/T.pas","fixture":"TRabattTests","method":"TestRabattCases","methodLine":12,' +
    '"editable":true,"reason":"","columns":[{"name":"ABetrag","type":"Integer","kind":"integer"},' +
    '{"name":"AExpected","type":"Integer","kind":"integer"}],"rows":[' +
    '{"name":"Alt","values":["1","0"]},{"name":"ABetrag 99","values":["99","0"]},' +
    '{"name":"ABetrag 100","values":["100","7"]},{"name":"ABetrag 101","values":["101","0"]}]}';
var
  mTable: TAtlasTestCaseTable;
  mRun: TTestRunResult;
  mRows: TArray<TAtlasTestCaseRow>;
  mFilled: Integer;
begin
  Assert.IsTrue(TAtlasTestCaseTables.Parse(cTable, mTable));
  Assert.AreEqual(1, TAtlasBoundaryCases.ExpectedColumn(mTable));
  mRun := Default(TTestRunResult);
  mRun.Cases := [CaseResult('TestRabattCases', 'Alt', '3', True),
    CaseResult('TestRabattCases', 'ABetrag 99', '0', False), CaseResult('TestRabattCases', 'ABetrag 100', '5', True),
    CaseResult('TestRabattCases', 'ABetrag 101', '5', True)];
  // Neu sind die letzten drei; „ABetrag 100“ hatte schon einen Wert, „ABetrag 99“ bestand mit dem Platzhalter.
  mRows := TAtlasBoundaryCases.TodayRows(mTable, [True, False, True], mRun, mFilled);
  Assert.AreEqual(1, mFilled);
  Assert.AreEqual('0', mRows[0].Value(1), 'alte Zeile bleibt');
  Assert.AreEqual('0', mRows[1].Value(1), 'ohne erhaltenen Wert');
  Assert.AreEqual('7', mRows[2].Value(1), 'eigener Wert bleibt');
  Assert.AreEqual('5', mRows[3].Value(1));
  mTable.Rows := nil;
  mRun.Cases := nil;
end;

end.
