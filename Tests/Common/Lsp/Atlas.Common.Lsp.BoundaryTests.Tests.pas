unit Atlas.Common.Lsp.BoundaryTests.Tests;

// Grenzfälle in die Testunit übernehmen (#2173): neue Testmethode mit [TestCase] und AExpected, Anfügen an eine
// vorhandene Tabelle, Trennzeichen, Kommentar, Gründe ohne Testunit und bei var-Parametern, Befehl als JSON.

interface

uses
  DUnitX.TestFramework,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Lsp.TestUnits;

type
  [TestFixture]
  TLspBoundaryTestsTests = class
  private
    FStore: IDocumentStore;
    FFiles: TDictionary<string, string>;
    FTestUnits: TLspTestUnits;
    function Context: TTestUnitContext;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure SeparatorAvoidsValues;
    [Test]
    procedure NewMethodWithCases;
    [Test]
    procedure AppendsToExistingTable;
    [Test]
    procedure RefusesVarParameters;
    [Test]
    procedure CommandAnswersWithEdit;
    [Test]
    procedure CommandWithoutTestUnitNamesReason;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.JSON,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Editing.TestDrafts,
  Atlas.Common.Lsp.BoundaryTests;

const
  cKundenFile = 'C:\P\Quelle\Kunden.pas';
  cTestFile = 'C:\P\Quelle\Kunden.Tests.pas';
  cBreak = #13#10;
  cKundenText =
    'unit Kunden;' + cBreak +                                                    // 0
    'interface' + cBreak +                                                       // 1
    'type' + cBreak +                                                            // 2
    '  TKunde = class' + cBreak +                                                // 3
    '  public' + cBreak +                                                        // 4
    '    function Rabatt(AMenge: Integer; const AName: string): Integer;' + cBreak + // 5
    '    procedure Lade(var AName: string);' + cBreak +                          // 6
    '  end;' + cBreak +                                                          // 7
    'implementation' + cBreak +                                                  // 8
    'function TKunde.Rabatt(AMenge: Integer; const AName: string): Integer;' + cBreak + // 9
    'begin' + cBreak +                                                           // 10
    '  Result := 0;' + cBreak +                                                  // 11
    'end;' + cBreak +                                                            // 12
    'procedure TKunde.Lade(var AName: string);' + cBreak +                       // 13
    'begin' + cBreak +                                                           // 14
    'end;' + cBreak +                                                            // 15
    'end.';
  cTestText =
    'unit Kunden.Tests;' + cBreak +
    'interface' + cBreak +
    'uses' + cBreak +
    '  DUnitX.TestFramework,' + cBreak +
    '  Kunden;' + cBreak +
    'type' + cBreak +
    '  [TestFixture]' + cBreak +
    '  TKundeTests = class' + cBreak +
    '  public' + cBreak +
    '    [Test]' + cBreak +
    '    procedure TestRabatt;' + cBreak +
    '  end;' + cBreak +
    'implementation' + cBreak +
    'procedure TKundeTests.TestRabatt;' + cBreak +
    'begin' + cBreak +
    'end;' + cBreak +
    cBreak +
    'initialization' + cBreak +
    '  TDUnitX.RegisterTestFixture(TKundeTests);' + cBreak +
    'end.' + cBreak;

function DraftAt(ALine: Integer): TTestDraft;
begin
  Assert.IsTrue(TTestDrafts.DraftAt(cKundenText, TPascalLexer.Tokenize(cKundenText),
    TIndexExtractor.ExtractText(cKundenText, 'Kunden.pas', nil), ALine, Result));
  Result.Fixture := 'TKundeTests';
  Result.UnitName := 'Kunden';
end;

function Case_(const AName: string; const AValues: TArray<string>; const AExpected: string): TLspBoundaryTestCase;
begin
  Result.Name := AName;
  Result.Values := AValues;
  Result.Expected := AExpected;
end;

function Cases: TArray<TLspBoundaryTestCase>;
begin
  SetLength(Result, 2);
  Result[0] := Case_('AMenge 99', ['99', 'x'], '0');
  Result[1] := Case_('AMenge 100', ['100', 'a,b'], '5');
end;

{ TLspBoundaryTestsTests }

procedure TLspBoundaryTestsTests.Setup;
begin
  FStore := TDocumentStore.Create;
  FFiles := TDictionary<string, string>.Create;
  FFiles.Add('C:\P\Tests\Tests.dpr', 'program Tests;' + cBreak + 'uses' + cBreak + '  DUnitX.TestFramework;' +
    cBreak + 'begin' + cBreak + 'end.');
  FStore.Open(TDocumentUris.FromPath(cKundenFile), 'pascal', 1, cKundenText);
  FTestUnits := TLspTestUnits.Create(FStore,
    function(const AUri: string; out AContext: TTestUnitContext): Boolean
    begin
      AContext := Context;
      Result := True;
    end);
end;

procedure TLspBoundaryTestsTests.TearDown;
begin
  FTestUnits.Free;
  FFiles.Free;
  FStore := nil;
end;

function TLspBoundaryTestsTests.Context: TTestUnitContext;
var
  mFiles: TDictionary<string, string>;
begin
  mFiles := FFiles;
  Result := Default(TTestUnitContext);
  Result.Settings := TTestUnitSettings.Default;
  Result.Root := 'C:\P';
  Result.TestProgram := 'C:\P\Tests\Tests.dpr';
  Result.ReadText :=
    function(const AFileName: string): string
    begin
      if not mFiles.TryGetValue(AFileName, Result) then
      begin
        Result := '';
      end;
    end;
  Result.Exists :=
    function(const AFileName: string): Boolean
    begin
      Result := mFiles.ContainsKey(AFileName);
    end;
  Result.FindUnit :=
    function(const AUnitName: string): string
    begin
      Result := '';
      if SameText(AUnitName, 'Kunden') then
      begin
        Result := cKundenFile;
      end
      else if SameText(AUnitName, 'Kunden.Tests') and mFiles.ContainsKey(cTestFile) then
      begin
        Result := cTestFile;
      end;
    end;
end;

procedure TLspBoundaryTestsTests.SeparatorAvoidsValues;
var
  mCases: TArray<TLspBoundaryTestCase>;
begin
  mCases := Cases;
  Assert.AreEqual(';', TLspBoundaryTests.SeparatorFor(mCases));
  mCases[0].Expected := 'a;b|c#d';
  Assert.AreEqual('', TLspBoundaryTests.SeparatorFor(mCases));
  Assert.AreEqual('A 2', TLspBoundaryTests.Rows([Case_('A', ['1'], '')], ',', ['A'])[0].Name);
end;

procedure TLspBoundaryTestsTests.NewMethodWithCases;
var
  mPlan: TLspBoundaryPlan;
begin
  mPlan := TLspBoundaryTests.Plan(DraftAt(10), Cases, cTestText, 'heute');
  Assert.AreEqual('', mPlan.Reason);
  Assert.AreEqual('TestRabattCases', mPlan.Method);
  Assert.IsFalse(mPlan.Appended);
  Assert.IsTrue(ContainsStr(mPlan.NewText, '    // heute' + cBreak +
    '    [TestCase(''AMenge 99'', ''99;x;0'', '';'')]' + cBreak +
    '    [TestCase(''AMenge 100'', ''100;a,b;5'', '';'')]' + cBreak +
    '    procedure TestRabattCases(const AMenge: Integer; const AName: string; const AExpected: Integer);'),
    mPlan.NewText);
  Assert.IsTrue(ContainsStr(mPlan.NewText, '  Actual := FSubject.Rabatt(AMenge, AName);') or
    ContainsStr(mPlan.NewText, '    Actual := Subject.Rabatt(AMenge, AName);'), mPlan.NewText);
  Assert.IsTrue(ContainsStr(mPlan.NewText, 'Assert.AreEqual(AExpected, Actual);'), mPlan.NewText);
end;

procedure TLspBoundaryTestsTests.AppendsToExistingTable;
var
  mFirst, mSecond: TLspBoundaryPlan;
  mCases: TArray<TLspBoundaryTestCase>;
begin
  mFirst := TLspBoundaryTests.Plan(DraftAt(10), [Case_('Eins', ['1', 'x'], '0')], cTestText, '');
  mCases := [Case_('Eins', ['2', 'y'], '1')];
  mSecond := TLspBoundaryTests.Plan(DraftAt(10), mCases, mFirst.NewText, 'heute');
  Assert.AreEqual('', mSecond.Reason);
  Assert.IsTrue(mSecond.Appended);
  Assert.IsTrue(ContainsStr(mSecond.NewText, '    // heute' + cBreak + '    [TestCase(''Eins'', ''1,x,0'')]' + cBreak +
    '    [TestCase(''Eins 2'', ''2,y,1'')]' + cBreak + '    procedure TestRabattCases('), mSecond.NewText);
  // Mit dem Trennzeichen der Tabelle in einem Wert lehnt das Schreiben ab.
  mCases := [Case_('Drei', ['3', 'a,b'], '1')];
  Assert.AreNotEqual('', TLspBoundaryTests.Plan(DraftAt(10), mCases, mFirst.NewText, '').Reason);
end;

procedure TLspBoundaryTestsTests.RefusesVarParameters;
begin
  Assert.AreNotEqual('', TLspBoundaryTests.Plan(DraftAt(14), [Case_('A', ['x'], '')], cTestText, '').Reason);
  Assert.AreNotEqual('', TLspBoundaryTests.Plan(DraftAt(10), nil, cTestText, '').Reason);
end;

procedure TLspBoundaryTestsTests.CommandAnswersWithEdit;
var
  mArguments: TJSONArray;
  mResult: TJSONValue;
  mObject: TJSONObject;
begin
  FFiles.Add(cTestFile, cTestText);
  mArguments := TJSONObject.ParseJSONValue('["' + TDocumentUris.FromPath(cKundenFile) +
    '",11,[{"name":"A","values":["1","x"],"expected":"0"}],"heute"]') as TJSONArray;
  try
    mResult := TLspBoundaryTests.Execute(FTestUnits, mArguments);
  finally
    mArguments.Free;
  end;
  try
    mObject := mResult as TJSONObject;
    Assert.AreEqual('', mObject.GetValue<string>('reason'));
    Assert.AreEqual('TestRabattCases', mObject.GetValue<string>('method'));
    Assert.AreEqual(TDocumentUris.FromPath(cTestFile), mObject.GetValue<string>('uri'));
    Assert.IsTrue(mObject.GetValue('edit') is TJSONObject);
  finally
    mResult.Free;
  end;
end;

procedure TLspBoundaryTestsTests.CommandWithoutTestUnitNamesReason;
var
  mArguments: TJSONArray;
  mResult: TJSONValue;
begin
  mArguments := TJSONObject.ParseJSONValue('["' + TDocumentUris.FromPath(cKundenFile) +
    '",11,[{"name":"A","values":["1","x"],"expected":"0"}]]') as TJSONArray;
  try
    mResult := TLspBoundaryTests.Execute(FTestUnits, mArguments);
  finally
    mArguments.Free;
  end;
  try
    Assert.IsTrue(ContainsStr((mResult as TJSONObject).GetValue<string>('reason'), 'Kunden.Tests'));
    Assert.IsTrue((mResult as TJSONObject).GetValue('edit') is TJSONNull);
  finally
    mResult.Free;
  end;
end;

end.
