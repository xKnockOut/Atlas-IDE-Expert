unit Atlas.Core.Problems.Tests;

// Tests für Probleme im Editor (#398): Diagnosen lesen, Speicher mit
// mitwandernden Markierungen und Compilermeldungen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasProblemsTests = class
  public
    [Test]
    procedure ReadsLspDiagnostics;
    [Test]
    procedure LinesBetweenDirectivesAreInactive;
    [Test]
    procedure InactiveSpansCoverPartsOfLines;
    [Test]
    procedure InactiveAtExcludesDirectives;
    [Test]
    procedure ReadsInactiveConditionAndBuildsHint;
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
  Atlas.Core.Problems.Contract,
  Atlas.Core.Problems.Store,
  Atlas.Core.Lsp.Session;

function Problem(ALine, ACharacter: Integer; const AMessage: string; const ASource: string = 'Atlas';
  ASeverity: TAtlasProblemSeverity = TAtlasProblemSeverity.Error): TAtlasProblem;
begin
  Result := Default(TAtlasProblem);
  Result.StartLine := ALine;
  Result.StartCharacter := ACharacter;
  Result.EndLine := ALine;
  Result.EndCharacter := ACharacter + 3;
  Result.Message := AMessage;
  Result.Source := ASource;
  Result.Severity := ASeverity;
end;

procedure TAtlasProblemsTests.ReadsLspDiagnostics;
var
  Items: TJSONArray;
  Problems: TArray<TAtlasProblem>;
begin
  Items := TJSONObject.ParseJSONValue('[' +
    '{"range":{"start":{"line":3,"character":2},"end":{"line":3,"character":9}},"severity":2,' +
    '"code":"unused-variable","source":"Atlas","message":"Variable X wird nicht verwendet",' +
    '"data":{"confidence":"medium"}},' +
    '{"range":{"start":{"line":5,"character":0},"end":{"line":5,"character":1}},"severity":1,' +
    '"code":"E2003","source":"dcc","message":"Undeklarierter Bezeichner"},' +
    '{"range":{"start":{"line":7,"character":0},"end":{"line":9,"character":0}},"severity":4,' +
    '"tags":[1],"source":"Atlas","message":"Inaktiver Bereich"},' +
    '{"range":{"start":{"line":1,"character":0},"end":{"line":1,"character":0}},"code":42,"message":"x"},' +
    '17]') as TJSONArray;
  try
    Problems := TAtlasProblem.ListFromJson(Items);
  finally
    Items.Free;
  end;
  Assert.AreEqual(4, Integer(Length(Problems)));
  Assert.AreEqual(3, Problems[0].StartLine);
  Assert.AreEqual(9, Problems[0].EndCharacter);
  Assert.IsTrue(Problems[0].Severity = TAtlasProblemSeverity.Warning);
  Assert.AreEqual('Variable X wird nicht verwendet (unused-variable)', Problems[0].Caption);
  Assert.IsFalse(Problems[0].IsCompiler);
  Assert.AreEqual('medium', Problems[0].Confidence);
  Assert.AreEqual('', Problems[1].Confidence);
  Assert.IsTrue(Problems[1].IsCompiler);
  Assert.IsTrue(Problems[1].Severity = TAtlasProblemSeverity.Error);
  Assert.IsTrue(Problems[2].Unnecessary);
  Assert.IsTrue(Problems[2].Severity = TAtlasProblemSeverity.Hint);
  Assert.AreEqual('42', Problems[3].Code);
  Assert.IsTrue(Problems[3].Severity = TAtlasProblemSeverity.Error, 'ohne severity: Fehler');
end;

procedure TAtlasProblemsTests.ContainsTreatsEmptyRangeAsOneCharacter;
var
  Item: TAtlasProblem;
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

procedure TAtlasProblemsTests.ReadsDiagnosticReports;
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

procedure TAtlasProblemsTests.ProblemsMoveWithInsertedLinesAndTurnStaleWhereEdited;
var
  Store: TAtlasProblemStore;
  Problems: TArray<TAtlasProblem>;
  Version: Integer;
begin
  Store := TAtlasProblemStore.Create;
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

procedure TAtlasProblemsTests.CompilerMessagesStayShiftedUntilReplaced;
var
  Store: TAtlasProblemStore;
  Problems: TArray<TAtlasProblem>;
begin
  Store := TAtlasProblemStore.Create;
  try
    // Erste Meldung: Compilermeldungen werden übernommen.
    Store.Update('C:\P\A.pas', 'a'#10'b'#10'c', True, [Problem(2, 0, 'E2003', 'dcc')], '1', False);
    Store.Edit('C:\P\A.pas', 'neu'#10'a'#10'b'#10'c');
    Problems := Store.ForFile('C:\P\A.pas');
    Assert.AreEqual(3, Problems[0].StartLine);
    Assert.IsTrue(Problems[0].Stale, 'nach jeder Änderung blass bis zum nächsten Compile');
    // Neue Atlas-Diagnosen mit der alten dcc-Zeile des Servers: die mitgewanderte bleibt.
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

procedure TAtlasProblemsTests.LinesBetweenDirectivesAreInactive;
var
  Store: TAtlasProblemStore;
  Inactive: TAtlasProblem;
begin
  // {$IFDEF WIN64} in Zeile 1, Inhalt in 2 und 3, {$ENDIF} in Zeile 4 (#615).
  Inactive := Problem(1, 14, 'inaktiv');
  Inactive.EndLine := 4;
  Inactive.EndCharacter := 2;
  Inactive.Unnecessary := True;
  Store := TAtlasProblemStore.Create;
  try
    Store.Update('C:\P\B.pas', 'type'#13#10'  {$IFDEF WIN64}'#13#10'  TNur64 = class end;'#13#10'  // x'#13#10 +
      '  {$ENDIF}', True, [Inactive, Problem(2, 2, 'echt')], '1', True);
    Assert.IsFalse(Store.LineInactive('C:\P\B.pas', 1), 'Zeile der Direktive');
    Assert.IsTrue(Store.LineInactive('C:\P\B.pas', 2));
    Assert.IsTrue(Store.LineInactive('C:\P\B.pas', 3));
    Assert.IsFalse(Store.LineInactive('C:\P\B.pas', 4), 'Zeile von $ENDIF');
    Assert.AreEqual(1, Integer(Length(Store.Inactive('C:\P\B.pas'))));
    Assert.IsFalse(Store.LineInactive('C:\P\Fremd.pas', 2));
  finally
    Store.Free;
  end;
end;

procedure TAtlasProblemsTests.InactiveSpansCoverPartsOfLines;
var
  Store: TAtlasProblemStore;
  OneLine, Block: TAtlasProblem;
  Spans: TArray<TAtlasColumnSpan>;
begin
  // Zweig innerhalb einer Zeile (#615): "x := 1; {$IFDEF X} a := 2; {$ENDIF} y;"
  OneLine := Problem(0, 18, 'inaktiv');
  OneLine.EndCharacter := 27;
  OneLine.Unnecessary := True;
  // Über mehrere Zeilen, beginnt hinter der Direktive und endet vor eingerücktem {$ENDIF}.
  Block := Problem(1, 10, 'inaktiv');
  Block.EndLine := 3;
  Block.EndCharacter := 2;
  Block.Unnecessary := True;
  Store := TAtlasProblemStore.Create;
  try
    Store.Update('C:\P\C.pas', 'x := 1; {$IFDEF X} a := 2; {$ENDIF} y;'#10'{$IFDEF A} x'#10'y'#10'  {$ENDIF}', True,
      [OneLine, Block], '1', True);
    Spans := Store.InactiveSpans('C:\P\C.pas', 0, 4);
    Assert.AreEqual(1, Integer(Length(Spans)));
    Assert.AreEqual(19, Spans[0].First);
    Assert.AreEqual(27, Spans[0].Last);
    Assert.IsFalse(TAtlasColumnSpan.Contains(Spans, 18), 'Direktive bleibt normal');
    Assert.IsTrue(TAtlasColumnSpan.Covers(Spans, 20, 6));
    Assert.IsFalse(TAtlasColumnSpan.Covers(Spans, 26, 3));
    Spans := Store.InactiveSpans('C:\P\C.pas', 1, 4);
    Assert.AreEqual(11, Spans[0].First);
    Assert.AreEqual(12, Spans[0].Last);
    Spans := Store.InactiveSpans('C:\P\C.pas', 2, 4);
    Assert.AreEqual(1, Spans[0].First);
    Assert.AreEqual(MaxInt, Spans[0].Last);
    Spans := Store.InactiveSpans('C:\P\C.pas', 3, 4);
    Assert.AreEqual(1, Spans[0].First);
    Assert.AreEqual(2, Spans[0].Last);
    Assert.AreEqual(0, Integer(Length(Store.InactiveSpans('C:\P\Fremd.pas', 2, 4))));
    // Nach einer Änderung in der ersten Zeile: dort nichts mehr, bis neue Diagnosen kommen.
    Store.Edit('C:\P\C.pas', 'x := 1; {$IFDEF X} b := 2; {$ENDIF} y;'#10'{$IFDEF A} x'#10'y'#10'  {$ENDIF}');
    Assert.AreEqual(0, Integer(Length(Store.InactiveSpans('C:\P\C.pas', 0, 4))));
    Assert.AreEqual(1, Integer(Length(Store.InactiveSpans('C:\P\C.pas', 2, 4))));
  finally
    Store.Free;
  end;
end;

procedure TAtlasProblemsTests.InactiveAtExcludesDirectives;
var
  Store: TAtlasProblemStore;
  Block: TAtlasProblem;
begin
  Block := Problem(1, 10, 'inaktiv');
  Block.EndLine := 3;
  Block.EndCharacter := 2;
  Block.Unnecessary := True;
  Store := TAtlasProblemStore.Create;
  try
    Store.Update('C:\P\C.pas', 'type'#10'{$IFDEF A} x'#10'y'#10'  {$ENDIF}', True, [Block, Problem(2, 0, 'echt')], '1', True);
    Assert.AreEqual(0, Integer(Length(Store.InactiveAt('C:\P\C.pas', 1, 9))), 'in der Direktive');
    Assert.AreEqual(1, Integer(Length(Store.InactiveAt('C:\P\C.pas', 1, 11))));
    Assert.AreEqual(1, Integer(Length(Store.InactiveAt('C:\P\C.pas', 2, 0))), 'nur der Bereich, kein Problem');
    Assert.AreEqual(1, Integer(Length(Store.InactiveAt('C:\P\C.pas', 3, 1))));
    Assert.AreEqual(0, Integer(Length(Store.InactiveAt('C:\P\C.pas', 3, 2))), 'Anfang von $ENDIF');
  finally
    Store.Free;
  end;
end;

procedure TAtlasProblemsTests.ReadsInactiveConditionAndBuildsHint;
var
  Item: TJSONObject;
  Inactive: TAtlasProblem;
begin
  Item := TJSONObject.ParseJSONValue('{"range":{"start":{"line":2,"character":0},"end":{"line":4,"character":0}},' +
    '"severity":4,"tags":[1],"source":"Atlas","message":"Inaktiv: Bedingung WIN64 nicht erfüllt",' +
    '"data":{"inactive":{"condition":"WIN64","platform":"Win32","config":"Debug"}}}') as TJSONObject;
  try
    Inactive := TAtlasProblem.FromJson(Item);
  finally
    Item.Free;
  end;
  Assert.IsTrue(Inactive.Unnecessary);
  Assert.AreEqual('WIN64', Inactive.InactiveCondition);
  Assert.AreEqual('Win32', Inactive.InactivePlatform);
  Assert.AreEqual('Debug', Inactive.InactiveConfig);
  Assert.AreEqual('Inactive: condition WIN64 not met (target platform Win32 · Debug)',
    Inactive.InactiveHint('Inactive: condition %s not met', ' (target platform %s · %s)', 'x'));
  Inactive.InactiveConfig := '';
  Assert.AreEqual('C WIN64 (Win32 · ?)', Inactive.InactiveHint('C %s', ' (%s · %s)', 'x'));
  Inactive.InactivePlatform := '';
  Assert.AreEqual('C WIN64', Inactive.InactiveHint('C %s', ' (%s · %s)', 'x'));
  Inactive.InactiveCondition := '';
  Assert.AreEqual('Inaktiver Bereich', Inactive.InactiveHint('C %s', ' (%s · %s)', 'Inaktiver Bereich'));
end;

procedure TAtlasProblemsTests.ForFileHidesInactiveRangesAndDuplicatesAndSorts;
var
  Store: TAtlasProblemStore;
  Inactive: TAtlasProblem;
  Problems: TArray<TAtlasProblem>;
  Text: string;
begin
  Inactive := Problem(0, 0, 'inaktiv');
  Inactive.Unnecessary := True;
  Store := TAtlasProblemStore.Create;
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
    // AllFiles: alle geprüften Dateien, auch ohne Probleme, sortiert (#592).
    Assert.AreEqual(2, Integer(Length(Store.AllFiles)));
    Assert.AreEqual('C:\P\B.pas', Store.AllFiles[0]);
    Assert.AreEqual('C:\P\C.pas', Store.AllFiles[1]);
    Store.Remove('C:\P\B.pas');
    Assert.AreEqual(0, Integer(Length(Store.Files)));
    Assert.AreEqual(1, Integer(Length(Store.AllFiles)));
  finally
    Store.Free;
  end;
end;

procedure TAtlasProblemsTests.DiskResultsAdoptTheEditorText;
var
  Store: TAtlasProblemStore;
  Problems: TArray<TAtlasProblem>;
begin
  Store := TAtlasProblemStore.Create;
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
  TDUnitX.RegisterTestFixture(TAtlasProblemsTests);

end.
