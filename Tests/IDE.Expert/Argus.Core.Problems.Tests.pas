unit Argus.Core.Problems.Tests;

// Tests für Probleme im Editor (#398): Diagnosen lesen, Speicher mit
// mitwandernden Markierungen und Compilermeldungen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TArgusProblemsTests = class
  public
    [Test]
    procedure ReadsLspDiagnostics;
    [Test]
    procedure ContainsTreatsEmptyRangeAsOneCharacter;
    [Test]
    procedure ReadsDiagnosticReports;
    [Test]
    procedure ProblemsMoveWithInsertedLinesAndTurnStaleWhereEdited;
    [Test]
    procedure CompilerMessagesStayShiftedUntilReplaced;
    [Test]
    procedure ForFileHidesInactiveRangesAndDuplicatesAndSorts;
    [Test]
    procedure DiskResultsAdoptTheEditorText;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Argus.Core.Problems.Contract,
  Argus.Core.Problems.Store,
  Argus.Core.Lsp.Session;

function Problem(ALine, ACharacter: Integer; const AMessage: string; const ASource: string = 'Argus';
  ASeverity: TArgusProblemSeverity = TArgusProblemSeverity.Error): TArgusProblem;
begin
  Result := Default(TArgusProblem);
  Result.StartLine := ALine;
  Result.StartCharacter := ACharacter;
  Result.EndLine := ALine;
  Result.EndCharacter := ACharacter + 3;
  Result.Message := AMessage;
  Result.Source := ASource;
  Result.Severity := ASeverity;
end;

procedure TArgusProblemsTests.ReadsLspDiagnostics;
var
  Items: TJSONArray;
  Problems: TArray<TArgusProblem>;
begin
  Items := TJSONObject.ParseJSONValue('[' +
    '{"range":{"start":{"line":3,"character":2},"end":{"line":3,"character":9}},"severity":2,' +
    '"code":"unused-variable","source":"Argus","message":"Variable X wird nicht verwendet"},' +
    '{"range":{"start":{"line":5,"character":0},"end":{"line":5,"character":1}},"severity":1,' +
    '"code":"E2003","source":"dcc","message":"Undeklarierter Bezeichner"},' +
    '{"range":{"start":{"line":7,"character":0},"end":{"line":9,"character":0}},"severity":4,' +
    '"tags":[1],"source":"Argus","message":"Inaktiver Bereich"},' +
    '{"range":{"start":{"line":1,"character":0},"end":{"line":1,"character":0}},"code":42,"message":"x"},' +
    '17]') as TJSONArray;
  try
    Problems := TArgusProblem.ListFromJson(Items);
  finally
    Items.Free;
  end;
  Assert.AreEqual(4, Integer(Length(Problems)));
  Assert.AreEqual(3, Problems[0].StartLine);
  Assert.AreEqual(9, Problems[0].EndCharacter);
  Assert.IsTrue(Problems[0].Severity = TArgusProblemSeverity.Warning);
  Assert.AreEqual('Variable X wird nicht verwendet (unused-variable)', Problems[0].Caption);
  Assert.IsFalse(Problems[0].IsCompiler);
  Assert.IsTrue(Problems[1].IsCompiler);
  Assert.IsTrue(Problems[1].Severity = TArgusProblemSeverity.Error);
  Assert.IsTrue(Problems[2].Unnecessary);
  Assert.IsTrue(Problems[2].Severity = TArgusProblemSeverity.Hint);
  Assert.AreEqual('42', Problems[3].Code);
  Assert.IsTrue(Problems[3].Severity = TArgusProblemSeverity.Error, 'ohne severity: Fehler');
end;

procedure TArgusProblemsTests.ContainsTreatsEmptyRangeAsOneCharacter;
var
  Item: TArgusProblem;
begin
  Item := Problem(2, 4, 'x');
  Assert.IsTrue(Item.Contains(2, 4));
  Assert.IsTrue(Item.Contains(2, 7), 'Ende gehört dazu');
  Assert.IsFalse(Item.Contains(2, 3));
  Assert.IsFalse(Item.Contains(1, 5));
  Item.EndCharacter := Item.StartCharacter;
  Assert.IsTrue(Item.Contains(2, 5), 'leerer Bereich: ein Zeichen');
  Assert.IsFalse(Item.Contains(2, 6));
  Item.EndLine := 4;
  Item.EndCharacter := 1;
  Assert.IsTrue(Item.Contains(3, 99), 'mittlere Zeile ganz');
  Assert.IsFalse(Item.Contains(4, 2));
end;

procedure TArgusProblemsTests.ReadsDiagnosticReports;
var
  Json: TJSONObject;
  Report: TLspDiagnosticReport;
begin
  Json := TJSONObject.ParseJSONValue('{"uri":"file:///c%3A/P/A.pas","kind":"full","resultId":"3:v2",' +
    '"items":[{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":4}},"message":"m"}]}')
    as TJSONObject;
  try
    Report := TLspDiagnosticReport.FromJson(Json, '');
  finally
    Json.Free;
  end;
  Assert.AreEqual('c:\P\A.pas', Report.FileName);
  Assert.AreEqual('3:v2', Report.ResultId);
  Assert.IsFalse(Report.Unchanged);
  Assert.AreEqual(1, Integer(Length(Report.Problems)));
  Json := TJSONObject.ParseJSONValue('{"kind":"unchanged","resultId":"3:v2"}') as TJSONObject;
  try
    Report := TLspDiagnosticReport.FromJson(Json, 'C:\P\B.pas');
  finally
    Json.Free;
  end;
  Assert.AreEqual('C:\P\B.pas', Report.FileName);
  Assert.IsTrue(Report.Unchanged);
  Assert.AreEqual(0, Integer(Length(Report.Problems)));
end;

procedure TArgusProblemsTests.ProblemsMoveWithInsertedLinesAndTurnStaleWhereEdited;
var
  Store: TArgusProblemStore;
  Problems: TArray<TArgusProblem>;
  Version: Integer;
begin
  Store := TArgusProblemStore.Create;
  try
    Store.Update('C:\P\A.pas', 'a'#10'b'#10'c'#10'd', True,
      [Problem(0, 0, 'oben'), Problem(2, 0, 'mitte'), Problem(3, 0, 'unten')], '1', False);
    Version := Store.Version;
    // Zwei Zeilen nach "a" eingefügt, "c" geändert.
    Store.Edit('c:\p\a.pas', 'a'#10'neu'#10'neu'#10'b'#10'C'#10'd');
    Assert.AreNotEqual(Version, Store.Version);
    Problems := Store.ForFile('C:\P\A.pas');
    Assert.AreEqual(3, Integer(Length(Problems)));
    Assert.AreEqual(0, Problems[0].StartLine);
    Assert.IsFalse(Problems[0].Stale, 'vor der Änderung');
    Assert.AreEqual(2, Problems[1].StartLine, 'in der geänderten Stelle bleibt die Zeile');
    Assert.IsTrue(Problems[1].Stale);
    Assert.AreEqual(5, Problems[2].StartLine, 'dahinter um zwei verschoben');
    Assert.IsFalse(Problems[2].Stale);
    Assert.AreEqual(1, Integer(Length(Store.OnLine('C:\P\A.pas', 5))));
    Assert.AreEqual(1, Integer(Length(Store.At('C:\P\A.pas', 5, 1))));
    // Gleicher Text: nichts ändert sich.
    Version := Store.Version;
    Store.Edit('C:\P\A.pas', 'a'#10'neu'#10'neu'#10'b'#10'C'#10'd');
    Assert.AreEqual(Version, Store.Version);
  finally
    Store.Free;
  end;
end;

procedure TArgusProblemsTests.CompilerMessagesStayShiftedUntilReplaced;
var
  Store: TArgusProblemStore;
  Problems: TArray<TArgusProblem>;
begin
  Store := TArgusProblemStore.Create;
  try
    // Erste Meldung: Compilermeldungen werden übernommen.
    Store.Update('C:\P\A.pas', 'a'#10'b'#10'c', True, [Problem(2, 0, 'E2003', 'dcc')], '1', False);
    Store.Edit('C:\P\A.pas', 'neu'#10'a'#10'b'#10'c');
    Problems := Store.ForFile('C:\P\A.pas');
    Assert.AreEqual(3, Problems[0].StartLine);
    Assert.IsTrue(Problems[0].Stale, 'nach jeder Änderung blass bis zum nächsten Compile');
    // Neue Argus-Diagnosen mit der alten dcc-Zeile des Servers: die mitgewanderte bleibt.
    Store.Update('C:\P\A.pas', 'neu'#10'a'#10'b'#10'c', True,
      [Problem(2, 0, 'E2003', 'dcc'), Problem(1, 0, 'Regel')], '2', False);
    Problems := Store.ForFile('C:\P\A.pas');
    Assert.AreEqual(2, Integer(Length(Problems)));
    Assert.AreEqual('Regel', Problems[0].Message);
    Assert.AreEqual(3, Problems[1].StartLine);
    Assert.IsTrue(Problems[1].Stale);
    // Nach refresh (neuer Compile): ersetzt.
    Store.Update('C:\P\A.pas', 'neu'#10'a'#10'b'#10'c', True, [Problem(3, 0, 'E2003', 'dcc')], '3', True);
    Problems := Store.ForFile('C:\P\A.pas');
    Assert.AreEqual(1, Integer(Length(Problems)));
    Assert.AreEqual(3, Problems[0].StartLine);
    Assert.IsFalse(Problems[0].Stale);
  finally
    Store.Free;
  end;
end;

procedure TArgusProblemsTests.ForFileHidesInactiveRangesAndDuplicatesAndSorts;
var
  Store: TArgusProblemStore;
  Inactive: TArgusProblem;
  Problems: TArray<TArgusProblem>;
  Text: string;
begin
  Inactive := Problem(0, 0, 'inaktiv');
  Inactive.Unnecessary := True;
  Store := TArgusProblemStore.Create;
  try
    Store.Update('C:\P\B.pas', 'x'#13#10'y'#13#10'z', True, [Problem(2, 0, 'z'), Inactive, Problem(1, 0, 'y'),
      Problem(1, 0, 'y', 'dcc')], '1', True);
    Problems := Store.ForFile('C:\P\B.pas');
    Assert.AreEqual(2, Integer(Length(Problems)));
    Assert.AreEqual('y', Problems[0].Message);
    Assert.AreEqual('z', Problems[1].Message);
    Assert.IsTrue(Store.LineText('C:\P\B.pas', 1, Text));
    Assert.AreEqual('y', Text, 'ohne #13');
    Assert.IsFalse(Store.LineText('C:\P\B.pas', 3, Text));
    Assert.AreEqual(1, Integer(Length(Store.Files)));
    Store.Update('C:\P\C.pas', '', True, [], '1', True);
    Assert.AreEqual(1, Integer(Length(Store.Files)), 'ohne Probleme nicht in der Liste');
    Store.Remove('C:\P\B.pas');
    Assert.AreEqual(0, Integer(Length(Store.Files)));
  finally
    Store.Free;
  end;
end;

procedure TArgusProblemsTests.DiskResultsAdoptTheEditorText;
var
  Store: TArgusProblemStore;
  Problems: TArray<TArgusProblem>;
begin
  Store := TArgusProblemStore.Create;
  try
    Store.Update('C:\P\D.pas', '', False, [Problem(1, 0, 'Platte')], '1', True);
    Assert.AreEqual('', Store.TextOf('C:\P\D.pas'));
    Store.Edit('C:\P\D.pas', 'a'#10'b');
    Problems := Store.ForFile('C:\P\D.pas');
    Assert.AreEqual(1, Problems[0].StartLine);
    Assert.IsFalse(Problems[0].Stale, 'unbekannter Text: übernehmen statt verschieben');
    Assert.AreEqual('a'#10'b', Store.TextOf('C:\P\D.pas'));
  finally
    Store.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TArgusProblemsTests);

end.
