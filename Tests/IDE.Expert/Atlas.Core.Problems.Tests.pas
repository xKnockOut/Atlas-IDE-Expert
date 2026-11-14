unit Atlas.Core.Problems.Tests;

// Tests für Probleme im Editor (#398): Diagnosen lesen, Speicher mit
// mitwandernden Markierungen und Compilermeldungen, fehlgeschlagene Tests
// als dritte Art (#69).

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
    /// <summary>#1818: Mit DropDeletedLines verschwinden Meldungen gelöschter Zeilen, statt blass auf die
    /// Folgezeile zu rutschen; ohne bleibt es wie bisher.</summary>
    [Test]
    procedure DeletedLinesDropTheirProblems;
    [Test]
    procedure CompilerMessagesStayShiftedUntilReplaced;
    /// <summary>#1024: Bestätigt der Build einen Atlas-Befund (gleiche Zeile, Code aus data.compilerCodes),
    /// bleibt mit Zusammenführen nur der Atlas-Befund; mit both beide.</summary>
    [Test]
    procedure ConfirmedCompilerMessagesMerge;
    [Test]
    procedure ReadsCompilerCodesAndStripsThem;
    [Test]
    procedure ForFileHidesInactiveRangesAndDuplicatesAndSorts;
    [Test]
    procedure DiskResultsAdoptTheEditorText;
    [Test]
    procedure TestFailuresStayBesideServerDiagnostics;
    [Test]
    procedure TaskProblemsReplacePerTaskAndVanishOnEditedLines;
    [Test]
    procedure HiddenTasksAreLeftOutAndFilesOnlyWithTasksDrop;
    [Test]
    procedure ClearTestsDropsFilesOnlyWithTests;
    [Test]
    procedure ProblemColorErrorIsError;
    [Test]
    procedure ProblemColorFadedMixesSurface;
    [Test]
    procedure ProblemColorHintMuted;
    /// <summary>#621: uses-Hinweise aus data.uses; nur ungenutzte werden abgeblendet, keiner ist ein Problem
    /// oder inaktiver Zweig.</summary>
    [Test]
    procedure UsesHintsAreKeptApart;
    /// <summary>Große Units: Tausende Befunde und 30.000 Zeilen; Ändern und ForFile laufen nach jeder Änderung
    /// im Hauptthread und dürfen nicht quadratisch wachsen.</summary>
    [Test]
    [Category('Benchmark')]
    procedure ManyProblemsInLargeUnitStayFast;
  end;

implementation

uses
  System.SysUtils,
  System.Diagnostics,
  System.JSON,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Problems.Colors,
  Atlas.Core.Problems.Store,
  Atlas.Core.Lsp.Session,
  System.Generics.Collections;

function Problem(ALine, ACharacter: Integer; const AMessage: string; const ASource: string;
  ASeverity: TAtlasProblemSeverity): TAtlasProblem; overload;
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

function Problem(ALine, ACharacter: Integer; const AMessage: string): TAtlasProblem; overload;
begin
  Result := Problem(ALine, ACharacter, AMessage, 'Atlas', TAtlasProblemSeverity.Error);
end;

function Problem(ALine, ACharacter: Integer; const AMessage: string; const ASource: string): TAtlasProblem; overload;
begin
  Result := Problem(ALine, ACharacter, AMessage, ASource, TAtlasProblemSeverity.Error);
end;

procedure TAtlasProblemsTests.ReadsLspDiagnostics;
var
  mItems: TJSONArray;
  mProblems: TArray<TAtlasProblem>;
begin
  mItems := TJSONObject.ParseJSONValue('[' +
    '{"range":{"start":{"line":3,"character":2},"end":{"line":3,"character":9}},"severity":2,' +
    '"code":"unused-variable","source":"Atlas","message":"Variable X wird nicht verwendet",' +
    '"data":{"confidence":"medium","details":"Durchsucht: 3 Dateien der Projektgruppe"}},' +
    '{"range":{"start":{"line":5,"character":0},"end":{"line":5,"character":1}},"severity":1,' +
    '"code":"E2003","source":"dcc","message":"Undeklarierter Bezeichner"},' +
    '{"range":{"start":{"line":7,"character":0},"end":{"line":9,"character":0}},"severity":4,' +
    '"tags":[1],"source":"Atlas","message":"Inaktiver Bereich"},' +
    '{"range":{"start":{"line":1,"character":0},"end":{"line":1,"character":0}},"code":42,"message":"x",' +
    '"tags":[2]},' +
    '17]') as TJSONArray;
  try
    mProblems := TAtlasProblem.ListFromJson(mItems);
  finally
    mItems.Free;
  end;
  Assert.AreEqual(4, Integer(Length(mProblems)));
  Assert.AreEqual(3, mProblems[0].StartLine);
  Assert.AreEqual(9, mProblems[0].EndCharacter);
  Assert.AreEqual<TAtlasProblemSeverity>(TAtlasProblemSeverity.Warning, mProblems[0].Severity);
  Assert.AreEqual('Variable X wird nicht verwendet (unused-variable)', mProblems[0].Caption);
  Assert.IsFalse(mProblems[0].IsCompiler);
  Assert.AreEqual('medium', mProblems[0].Confidence);
  Assert.AreEqual('', mProblems[1].Confidence);
  // Zusatz für den Befund-Hover (#1102).
  Assert.AreEqual('Durchsucht: 3 Dateien der Projektgruppe', mProblems[0].Details);
  Assert.AreEqual('', mProblems[1].Details);
  Assert.IsTrue(mProblems[1].IsCompiler);
  Assert.AreEqual<TAtlasProblemSeverity>(TAtlasProblemSeverity.Error, mProblems[1].Severity);
  Assert.IsTrue(mProblems[2].Unnecessary);
  Assert.IsFalse(mProblems[2].Deprecated);
  // Veraltetes Symbol (#38).
  Assert.IsTrue(mProblems[3].Deprecated);
  Assert.IsFalse(mProblems[3].Unnecessary);
  Assert.AreEqual<TAtlasProblemSeverity>(TAtlasProblemSeverity.Hint, mProblems[2].Severity);
  Assert.AreEqual('42', mProblems[3].Code);
  Assert.AreEqual<TAtlasProblemSeverity>(TAtlasProblemSeverity.Error, mProblems[3].Severity, 'ohne severity: Fehler');
end;

procedure TAtlasProblemsTests.ContainsTreatsEmptyRangeAsOneCharacter;
var
  mItem: TAtlasProblem;
begin
  mItem := Problem(2, 4, 'x');
  Assert.IsTrue(mItem.Contains(2, 4));
  Assert.IsTrue(mItem.Contains(2, 7), 'Ende gehört dazu');
  Assert.IsFalse(mItem.Contains(2, 3));
  Assert.IsFalse(mItem.Contains(1, 5));
  mItem.EndCharacter := mItem.StartCharacter;
  Assert.IsTrue(mItem.Contains(2, 5), 'leerer Bereich: ein Zeichen');
  Assert.IsFalse(mItem.Contains(2, 6));
  mItem.EndLine := 4;
  mItem.EndCharacter := 1;
  Assert.IsTrue(mItem.Contains(3, 99), 'mittlere Zeile ganz');
  Assert.IsFalse(mItem.Contains(4, 2));
end;

procedure TAtlasProblemsTests.ReadsDiagnosticReports;
var
  mJson: TJSONObject;
  mReport: TLspDiagnosticReport;
begin
  mJson := TJSONObject.ParseJSONValue('{"uri":"file:///c%3A/P/A.pas","kind":"full","resultId":"3:v2",' +
    '"items":[{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":4}},"message":"m"}]}')
    as TJSONObject;
  try
    mReport := TLspDiagnosticReport.FromJson(mJson, '');
  finally
    mJson.Free;
  end;
  Assert.AreEqual('c:\P\A.pas', mReport.FileName);
  Assert.AreEqual('3:v2', mReport.ResultId);
  Assert.IsFalse(mReport.Unchanged);
  Assert.AreEqual(1, Integer(Length(mReport.Problems)));
  mJson := TJSONObject.ParseJSONValue('{"kind":"unchanged","resultId":"3:v2"}') as TJSONObject;
  try
    mReport := TLspDiagnosticReport.FromJson(mJson, 'C:\P\B.pas');
  finally
    mJson.Free;
  end;
  Assert.AreEqual('C:\P\B.pas', mReport.FileName);
  Assert.IsTrue(mReport.Unchanged);
  Assert.AreEqual(0, Integer(Length(mReport.Problems)));
end;

procedure TAtlasProblemsTests.DeletedLinesDropTheirProblems;
var
  mStore: TAtlasProblemStore;
  mProblems: TArray<TAtlasProblem>;
begin
  mStore := TAtlasProblemStore.Create;
  try
    mStore.DropDeletedLines := True;
    mStore.Update('C:\P\A.pas', 'a'#10'b'#10'c'#10'd', True,
      [Problem(0, 0, 'oben'), Problem(1, 0, 'weg'), Problem(3, 0, 'unten')], '1', False);
    mStore.Edit('C:\P\A.pas', 'a'#10'c'#10'd');
    mProblems := mStore.ForFile('C:\P\A.pas');
    Assert.AreEqual(2, Integer(Length(mProblems)), 'Meldung der gelöschten Zeile fehlt');
    Assert.AreEqual('oben', mProblems[0].Message);
    Assert.AreEqual(2, mProblems[1].StartLine);
    Assert.AreEqual(0, Integer(Length(mStore.OnLine('C:\P\A.pas', 1))), 'keine Marke auf der Folgezeile');
    // Geänderte Zeile: bleibt blass wie bisher.
    mStore.Edit('C:\P\A.pas', 'A'#10'c'#10'd');
    mProblems := mStore.ForFile('C:\P\A.pas');
    Assert.AreEqual(2, Integer(Length(mProblems)));
    Assert.IsTrue(mProblems[0].Stale);
    // Ausgeschaltet: blass auf der Folgezeile.
    mStore.DropDeletedLines := False;
    mStore.Update('C:\P\A.pas', 'a'#10'b'#10'c', True, [Problem(1, 0, 'bleibt')], '2', False);
    mStore.Edit('C:\P\A.pas', 'a'#10'c');
    mProblems := mStore.ForFile('C:\P\A.pas');
    Assert.AreEqual(1, Integer(Length(mProblems)));
    Assert.IsTrue(mProblems[0].Stale);
  finally
    mStore.Free;
  end;
end;

procedure TAtlasProblemsTests.ProblemsMoveWithInsertedLinesAndTurnStaleWhereEdited;
var
  mStore: TAtlasProblemStore;
  mProblems: TArray<TAtlasProblem>;
  mVersion: Integer;
begin
  mStore := TAtlasProblemStore.Create;
  try
    mStore.Update('C:\P\A.pas', 'a'#10'b'#10'c'#10'd', True,
      [Problem(0, 0, 'oben'), Problem(2, 0, 'mitte'), Problem(3, 0, 'unten')], '1', False);
    mVersion := mStore.Version;
    // Zwei Zeilen nach "a" eingefügt, "c" geändert.
    mStore.Edit('c:\p\a.pas', 'a'#10'neu'#10'neu'#10'b'#10'C'#10'd');
    Assert.AreNotEqual(mVersion, mStore.Version);
    mProblems := mStore.ForFile('C:\P\A.pas');
    Assert.AreEqual(3, Integer(Length(mProblems)));
    Assert.AreEqual(0, mProblems[0].StartLine);
    Assert.IsFalse(mProblems[0].Stale, 'vor der Änderung');
    Assert.AreEqual(2, mProblems[1].StartLine, 'in der geänderten Stelle bleibt die Zeile');
    Assert.IsTrue(mProblems[1].Stale);
    Assert.AreEqual(5, mProblems[2].StartLine, 'dahinter um zwei verschoben');
    Assert.IsFalse(mProblems[2].Stale);
    Assert.AreEqual(1, Integer(Length(mStore.OnLine('C:\P\A.pas', 5))));
    Assert.AreEqual(1, Integer(Length(mStore.At('C:\P\A.pas', 5, 1))));
    // Gleicher Text: nichts ändert sich.
    mVersion := mStore.Version;
    mStore.Edit('C:\P\A.pas', 'a'#10'neu'#10'neu'#10'b'#10'C'#10'd');
    Assert.AreEqual(mVersion, mStore.Version);
  finally
    mStore.Free;
  end;
end;

procedure TAtlasProblemsTests.CompilerMessagesStayShiftedUntilReplaced;
var
  mStore: TAtlasProblemStore;
  mProblems: TArray<TAtlasProblem>;
begin
  mStore := TAtlasProblemStore.Create;
  try
    // Erste Meldung: Compilermeldungen werden übernommen.
    mStore.Update('C:\P\A.pas', 'a'#10'b'#10'c', True, [Problem(2, 0, 'E2003', 'dcc')], '1', False);
    mStore.Edit('C:\P\A.pas', 'neu'#10'a'#10'b'#10'c');
    mProblems := mStore.ForFile('C:\P\A.pas');
    Assert.AreEqual(3, mProblems[0].StartLine);
    Assert.IsTrue(mProblems[0].Stale, 'nach jeder Änderung blass bis zum nächsten Compile');
    // Neue Atlas-Diagnosen mit der alten dcc-Zeile des Servers: die mitgewanderte bleibt.
    mStore.Update('C:\P\A.pas', 'neu'#10'a'#10'b'#10'c', True,
      [Problem(2, 0, 'E2003', 'dcc'), Problem(1, 0, 'Regel')], '2', False);
    mProblems := mStore.ForFile('C:\P\A.pas');
    Assert.AreEqual(2, Integer(Length(mProblems)));
    Assert.AreEqual('Regel', mProblems[0].Message);
    Assert.AreEqual(3, mProblems[1].StartLine);
    Assert.IsTrue(mProblems[1].Stale);
    // Nach refresh (neuer Compile): ersetzt.
    mStore.Update('C:\P\A.pas', 'neu'#10'a'#10'b'#10'c', True, [Problem(3, 0, 'E2003', 'dcc')], '3', True);
    mProblems := mStore.ForFile('C:\P\A.pas');
    Assert.AreEqual(1, Integer(Length(mProblems)));
    Assert.AreEqual(3, mProblems[0].StartLine);
    Assert.IsFalse(mProblems[0].Stale);
  finally
    mStore.Free;
  end;
end;

procedure TAtlasProblemsTests.ConfirmedCompilerMessagesMerge;
var
  mStore: TAtlasProblemStore;
  mProblems: TArray<TAtlasProblem>;
  mRule, mSame, mOther, mElsewhere: TAtlasProblem;
begin
  mRule := Problem(1, 2, 'Suchen erwartet 1 Argumente, übergeben sind 0; AName fehlt (wie E2035).');
  mRule.Code := 'argument-count-mismatch';
  mRule.CompilerCodes := ['E2034', 'E2035'];
  mSame := Problem(1, 8, 'Nicht genügend wirkliche Parameter', 'dcc');
  mSame.Code := 'E2035';
  mOther := Problem(1, 8, 'Inkompatible Typen', 'dcc');
  mOther.Code := 'E2010';
  mElsewhere := Problem(2, 0, 'Nicht genügend wirkliche Parameter', 'dcc');
  mElsewhere.Code := 'E2035';
  mStore := TAtlasProblemStore.Create;
  try
    Assert.IsTrue(mStore.CompilerMerge, 'Vorgabe merge');
    mStore.Update('C:\P\A.pas', 'a'#10'b'#10'c', True, [mRule, mSame, mOther, mElsewhere], '1', True);
    mProblems := mStore.ForFile('C:\P\A.pas');
    // Gleiche Zeile und Code: eine Meldung; anderer Code bzw. andere Zeile bleiben.
    Assert.AreEqual(3, Integer(Length(mProblems)));
    Assert.AreEqual('argument-count-mismatch', mProblems[0].Code);
    Assert.IsTrue(mProblems[0].Confirmed);
    Assert.AreEqual('E2035', mProblems[0].ConfirmedCode);
    Assert.AreEqual('E2035', mProblems[0].CompilerCodeText);
    Assert.AreEqual('E2010', mProblems[1].Code);
    Assert.AreEqual(2, mProblems[2].StartLine);
    // both: beide Meldungen, der Atlas-Befund bleibt bestätigt.
    mStore.CompilerMerge := False;
    mProblems := mStore.ForFile('C:\P\A.pas');
    Assert.AreEqual(4, Integer(Length(mProblems)));
    Assert.IsTrue(mProblems[0].Confirmed or mProblems[1].Confirmed);
    // Nach dem nächsten Build ohne die Meldung: nur der Atlas-Befund, nicht mehr bestätigt.
    mStore.CompilerMerge := True;
    mStore.Update('C:\P\A.pas', 'a'#10'b'#10'c', True, [mRule], '2', True);
    mProblems := mStore.ForFile('C:\P\A.pas');
    Assert.AreEqual(1, Integer(Length(mProblems)));
    Assert.IsFalse(mProblems[0].Confirmed);
    Assert.AreEqual('E2034, E2035', mProblems[0].CompilerCodeText);
  finally
    mStore.Free;
  end;
end;

procedure TAtlasProblemsTests.ReadsCompilerCodesAndStripsThem;
var
  mItem: TJSONValue;
  mProblem: TAtlasProblem;
begin
  mItem := TJSONObject.ParseJSONValue('{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":4}},' +
    '"severity":1,"code":"argument-count-mismatch","source":"Atlas","message":"X erwartet 1 Argumente (wie E2035).",' +
    '"data":{"compilerCodes":["E2034","E2035"]}}');
  try
    mProblem := TAtlasProblem.FromJson(mItem as TJSONObject);
    Assert.AreEqual(2, Integer(Length(mProblem.CompilerCodes)));
    Assert.AreEqual('E2034, E2035', mProblem.CompilerCodeText);
  finally
    mItem.Free;
  end;
  Assert.AreEqual('X erwartet 1 Argumente.', TAtlasProblem.WithoutCompilerCode('X erwartet 1 Argumente (wie E2035).'));
  Assert.AreEqual('A und B.', TAtlasProblem.WithoutCompilerCode('A (wie E2034, E2035) und B (wie W1000' + #$2013 +
    'W1007).'));
  // Anderer Text in Klammern bleibt.
  Assert.AreEqual('Wert (wie oben) fehlt.', TAtlasProblem.WithoutCompilerCode('Wert (wie oben) fehlt.'));
  Assert.AreEqual('Ohne Code', TAtlasProblem.WithoutCompilerCode('Ohne Code'));
end;

procedure TAtlasProblemsTests.LinesBetweenDirectivesAreInactive;
var
  mStore: TAtlasProblemStore;
  mInactive: TAtlasProblem;
begin
  // {$IFDEF WIN64} in Zeile 1, Inhalt in 2 und 3, {$ENDIF} in Zeile 4 (#615).
  mInactive := Problem(1, 14, 'inaktiv');
  mInactive.EndLine := 4;
  mInactive.EndCharacter := 2;
  mInactive.Unnecessary := True;
  mStore := TAtlasProblemStore.Create;
  try
    mStore.Update('C:\P\B.pas', 'type'#13#10'  {$IFDEF WIN64}'#13#10'  TNur64 = class end;'#13#10'  // x'#13#10 +
      '  {$ENDIF}', True, [mInactive, Problem(2, 2, 'echt')], '1', True);
    Assert.IsFalse(mStore.LineInactive('C:\P\B.pas', 1), 'Zeile der Direktive');
    Assert.IsTrue(mStore.LineInactive('C:\P\B.pas', 2));
    Assert.IsTrue(mStore.LineInactive('C:\P\B.pas', 3));
    Assert.IsFalse(mStore.LineInactive('C:\P\B.pas', 4), 'Zeile von $ENDIF');
    Assert.AreEqual(1, Integer(Length(mStore.Inactive('C:\P\B.pas'))));
    Assert.IsFalse(mStore.LineInactive('C:\P\Fremd.pas', 2));
  finally
    mStore.Free;
  end;
end;

procedure TAtlasProblemsTests.InactiveSpansCoverPartsOfLines;
var
  mStore: TAtlasProblemStore;
  mOneLine, mBlock: TAtlasProblem;
  mSpans: TArray<TAtlasColumnSpan>;
begin
  // Zweig innerhalb einer Zeile (#615): "x := 1; {$IFDEF X} a := 2; {$ENDIF} y;"
  mOneLine := Problem(0, 18, 'inaktiv');
  mOneLine.EndCharacter := 27;
  mOneLine.Unnecessary := True;
  // Über mehrere Zeilen, beginnt hinter der Direktive und endet vor eingerücktem {$ENDIF}.
  mBlock := Problem(1, 10, 'inaktiv');
  mBlock.EndLine := 3;
  mBlock.EndCharacter := 2;
  mBlock.Unnecessary := True;
  mStore := TAtlasProblemStore.Create;
  try
    mStore.Update('C:\P\C.pas', 'x := 1; {$IFDEF X} a := 2; {$ENDIF} y;'#10'{$IFDEF A} x'#10'y'#10'  {$ENDIF}', True,
      [mOneLine, mBlock], '1', True);
    mSpans := mStore.InactiveSpans('C:\P\C.pas', 0, 4);
    Assert.AreEqual(1, Integer(Length(mSpans)));
    Assert.AreEqual(19, mSpans[0].First);
    Assert.AreEqual(27, mSpans[0].Last);
    Assert.IsFalse(TAtlasColumnSpan.Contains(mSpans, 18), 'Direktive bleibt normal');
    Assert.IsTrue(TAtlasColumnSpan.Covers(mSpans, 20, 6));
    Assert.IsFalse(TAtlasColumnSpan.Covers(mSpans, 26, 3));
    mSpans := mStore.InactiveSpans('C:\P\C.pas', 1, 4);
    Assert.AreEqual(11, mSpans[0].First);
    Assert.AreEqual(12, mSpans[0].Last);
    mSpans := mStore.InactiveSpans('C:\P\C.pas', 2, 4);
    Assert.AreEqual(1, mSpans[0].First);
    Assert.AreEqual(MaxInt, mSpans[0].Last);
    mSpans := mStore.InactiveSpans('C:\P\C.pas', 3, 4);
    Assert.AreEqual(1, mSpans[0].First);
    Assert.AreEqual(2, mSpans[0].Last);
    Assert.AreEqual(0, Integer(Length(mStore.InactiveSpans('C:\P\Fremd.pas', 2, 4))));
    // Nach einer Änderung in der ersten Zeile: dort nichts mehr, bis neue Diagnosen kommen.
    mStore.Edit('C:\P\C.pas', 'x := 1; {$IFDEF X} b := 2; {$ENDIF} y;'#10'{$IFDEF A} x'#10'y'#10'  {$ENDIF}');
    Assert.AreEqual(0, Integer(Length(mStore.InactiveSpans('C:\P\C.pas', 0, 4))));
    Assert.AreEqual(1, Integer(Length(mStore.InactiveSpans('C:\P\C.pas', 2, 4))));
  finally
    mStore.Free;
  end;
end;

procedure TAtlasProblemsTests.InactiveAtExcludesDirectives;
var
  mStore: TAtlasProblemStore;
  mBlock: TAtlasProblem;
begin
  mBlock := Problem(1, 10, 'inaktiv');
  mBlock.EndLine := 3;
  mBlock.EndCharacter := 2;
  mBlock.Unnecessary := True;
  mStore := TAtlasProblemStore.Create;
  try
    mStore.Update('C:\P\C.pas', 'type'#10'{$IFDEF A} x'#10'y'#10'  {$ENDIF}', True, [mBlock, Problem(2, 0, 'echt')], '1', True);
    Assert.AreEqual(0, Integer(Length(mStore.InactiveAt('C:\P\C.pas', 1, 9))), 'in der Direktive');
    Assert.AreEqual(1, Integer(Length(mStore.InactiveAt('C:\P\C.pas', 1, 11))));
    Assert.AreEqual(1, Integer(Length(mStore.InactiveAt('C:\P\C.pas', 2, 0))), 'nur der Bereich, kein Problem');
    Assert.AreEqual(1, Integer(Length(mStore.InactiveAt('C:\P\C.pas', 3, 1))));
    Assert.AreEqual(0, Integer(Length(mStore.InactiveAt('C:\P\C.pas', 3, 2))), 'Anfang von $ENDIF');
  finally
    mStore.Free;
  end;
end;

procedure TAtlasProblemsTests.ReadsInactiveConditionAndBuildsHint;
var
  mItem: TJSONObject;
  mInactive: TAtlasProblem;
begin
  mItem := TJSONObject.ParseJSONValue('{"range":{"start":{"line":2,"character":0},"end":{"line":4,"character":0}},' +
    '"severity":4,"tags":[1],"source":"Atlas","message":"Inaktiv: Bedingung WIN64 nicht erfüllt",' +
    '"data":{"inactive":{"condition":"WIN64","platform":"Win32","config":"Debug"}}}') as TJSONObject;
  try
    mInactive := TAtlasProblem.FromJson(mItem);
  finally
    mItem.Free;
  end;
  Assert.IsTrue(mInactive.Unnecessary);
  Assert.AreEqual('WIN64', mInactive.InactiveCondition);
  Assert.AreEqual('Win32', mInactive.InactivePlatform);
  Assert.AreEqual('Debug', mInactive.InactiveConfig);
  Assert.AreEqual('Inactive: condition WIN64 not met (target platform Win32 · Debug)',
    mInactive.InactiveHint('Inactive: condition %s not met', ' (target platform %s · %s)', 'x'));
  mInactive.InactiveConfig := '';
  Assert.AreEqual('C WIN64 (Win32 · ?)', mInactive.InactiveHint('C %s', ' (%s · %s)', 'x'));
  mInactive.InactivePlatform := '';
  Assert.AreEqual('C WIN64', mInactive.InactiveHint('C %s', ' (%s · %s)', 'x'));
  mInactive.InactiveCondition := '';
  Assert.AreEqual('Inaktiver Bereich', mInactive.InactiveHint('C %s', ' (%s · %s)', 'Inaktiver Bereich'));
end;

procedure TAtlasProblemsTests.ForFileHidesInactiveRangesAndDuplicatesAndSorts;
var
  mStore: TAtlasProblemStore;
  mInactive: TAtlasProblem;
  mProblems: TArray<TAtlasProblem>;
  mText: string;
begin
  mInactive := Problem(0, 0, 'inaktiv');
  mInactive.Unnecessary := True;
  mStore := TAtlasProblemStore.Create;
  try
    mStore.Update('C:\P\B.pas', 'x'#13#10'y'#13#10'z', True, [Problem(2, 0, 'z'), mInactive, Problem(1, 0, 'y'),
      Problem(1, 0, 'y', 'dcc')], '1', True);
    mProblems := mStore.ForFile('C:\P\B.pas');
    Assert.AreEqual(2, Integer(Length(mProblems)));
    Assert.AreEqual('y', mProblems[0].Message);
    Assert.AreEqual('z', mProblems[1].Message);
    Assert.IsTrue(mStore.LineText('C:\P\B.pas', 1, mText));
    Assert.AreEqual('y', mText, 'ohne #13');
    Assert.IsFalse(mStore.LineText('C:\P\B.pas', 3, mText));
    Assert.AreEqual(1, Integer(Length(mStore.Files)));
    mStore.Update('C:\P\C.pas', '', True, [], '1', True);
    Assert.AreEqual(1, Integer(Length(mStore.Files)), 'ohne Probleme nicht in der Liste');
    // AllFiles: alle geprüften Dateien, auch ohne Probleme, sortiert (#592).
    Assert.AreEqual(2, Integer(Length(mStore.AllFiles)));
    Assert.AreEqual('C:\P\B.pas', mStore.AllFiles[0]);
    Assert.AreEqual('C:\P\C.pas', mStore.AllFiles[1]);
    mStore.Remove('C:\P\B.pas');
    Assert.AreEqual(0, Integer(Length(mStore.Files)));
    Assert.AreEqual(1, Integer(Length(mStore.AllFiles)));
  finally
    mStore.Free;
  end;
end;

procedure TAtlasProblemsTests.DiskResultsAdoptTheEditorText;
var
  mStore: TAtlasProblemStore;
  mProblems: TArray<TAtlasProblem>;
begin
  mStore := TAtlasProblemStore.Create;
  try
    mStore.Update('C:\P\D.pas', '', False, [Problem(1, 0, 'Platte')], '1', True);
    Assert.AreEqual('', mStore.TextOf('C:\P\D.pas'));
    mStore.Edit('C:\P\D.pas', 'a'#10'b');
    mProblems := mStore.ForFile('C:\P\D.pas');
    Assert.AreEqual(1, mProblems[0].StartLine);
    Assert.IsFalse(mProblems[0].Stale, 'unbekannter Text: übernehmen statt verschieben');
    Assert.AreEqual('a'#10'b', mStore.TextOf('C:\P\D.pas'));
  finally
    mStore.Free;
  end;
end;

procedure TAtlasProblemsTests.TestFailuresStayBesideServerDiagnostics;
var
  mStore: TAtlasProblemStore;
  mShown: TArray<TAtlasProblem>;
begin
  mStore := TAtlasProblemStore.Create;
  try
    mStore.SetTests([TPair<string, TAtlasProblem>.Create('C:\P\T.pas', Problem(4, 2, 'Erwartet 3, erhalten 4'))]);
    Assert.IsFalse(mStore.Contains('C:\P\T.pas'), 'nur Tests: für den Server neu');
    Assert.AreEqual(0, Integer(Length(mStore.AllFiles)), 'nur Tests: nicht vom Server geprüft');
    Assert.AreEqual(1, Integer(Length(mStore.ForFile('c:\p\t.pas'))));
    Assert.AreEqual(TAtlasProblemStore.cTestSource, mStore.ForFile('C:\P\T.pas')[0].Source);
    // Erste Diagnosen des Servers ersetzen Compilermeldungen wie bei einer neuen Datei und lassen Tests stehen.
    mStore.Update('C:\P\T.pas', 'a'#10'b'#10'c'#10'd'#10'e', True,
      [Problem(1, 0, 'Undeklariert', TAtlasProblem.cCompilerSource)], '1', False);
    mShown := mStore.ForFile('C:\P\T.pas');
    Assert.AreEqual(2, Integer(Length(mShown)));
    Assert.AreEqual('Undeklariert', mShown[0].Message);
    Assert.AreEqual('Erwartet 3, erhalten 4', mShown[1].Message);
    Assert.IsTrue(mStore.Contains('C:\P\T.pas'));
    // Zwei Zeilen davor eingefügt: der Test wandert mit.
    mStore.Edit('C:\P\T.pas', 'x'#10'y'#10'a'#10'b'#10'c'#10'd'#10'e');
    mShown := mStore.ForFile('C:\P\T.pas');
    Assert.AreEqual(6, mShown[1].StartLine);
    Assert.IsFalse(mShown[1].Stale, 'unverändert: nicht blass');
  finally
    mStore.Free;
  end;
end;

procedure TAtlasProblemsTests.TaskProblemsReplacePerTaskAndVanishOnEditedLines;
var
  mStore: TAtlasProblemStore;
  mShown: TArray<TAtlasProblem>;
begin
  mStore := TAtlasProblemStore.Create;
  try
    mStore.Update('C:\P\A.pas', 'a'#10'b'#10'c'#10'd', True, [Problem(0, 0, 'Regel')], '1', True);
    mStore.SetTaskProblems('Delphi-12-Prüfung', [TPair<string, TAtlasProblem>.Create('C:\P\A.pas',
      Problem(2, 0, '"is not" gibt es erst ab Delphi 13')), TPair<string, TAtlasProblem>.Create('C:\P\A.pas',
      Problem(3, 0, 'zweiter Verstoß'))]);
    mStore.SetTaskProblems('Konsole', [TPair<string, TAtlasProblem>.Create('C:\P\A.pas', Problem(1, 0, 'stdout'))]);
    mShown := mStore.ForFile('C:\P\A.pas');
    Assert.AreEqual(4, Integer(Length(mShown)));
    Assert.AreEqual('Delphi-12-Prüfung', mShown[2].Source, 'Quelle = Name der Aufgabe');
    Assert.AreEqual(2, mStore.TaskCount('delphi-12-prüfung'));
    Assert.AreEqual('Delphi-12-Prüfung|Konsole', string.Join('|', mStore.TaskNames));
    // Neuer Lauf ersetzt nur die Befunde dieser Aufgabe.
    mStore.SetTaskProblems('Delphi-12-Prüfung', [TPair<string, TAtlasProblem>.Create('C:\P\A.pas',
      Problem(3, 0, 'zweiter Verstoß'))]);
    Assert.AreEqual(1, mStore.TaskCount('Delphi-12-Prüfung'));
    Assert.AreEqual(1, mStore.TaskCount('Konsole'));
    // Zeile 3 („d“) geändert: ihr Befund fällt weg, der Befund in Zeile 1 bleibt.
    mStore.Edit('C:\P\A.pas', 'a'#10'b'#10'c'#10'dd');
    Assert.AreEqual(0, mStore.TaskCount('Delphi-12-Prüfung'));
    Assert.AreEqual(1, mStore.TaskCount('Konsole'));
    // Zeile davor eingefügt: der übrige Befund wandert mit.
    mStore.Edit('C:\P\A.pas', 'neu'#10'a'#10'b'#10'c'#10'dd');
    mShown := mStore.ForFile('C:\P\A.pas');
    Assert.AreEqual(2, Integer(Length(mShown)));
    Assert.AreEqual('stdout', mShown[1].Message);
    Assert.AreEqual(2, mShown[1].StartLine);
    // Server liefert neu: Aufgabenbefunde bleiben.
    mStore.Update('C:\P\A.pas', 'neu'#10'a'#10'b'#10'c'#10'dd', True, nil, '2', True);
    Assert.AreEqual(1, mStore.TaskCount('Konsole'));
    mStore.ClearTask('Konsole');
    Assert.AreEqual(0, Integer(Length(mStore.TaskNames)));
  finally
    mStore.Free;
  end;
end;

procedure TAtlasProblemsTests.HiddenTasksAreLeftOutAndFilesOnlyWithTasksDrop;
var
  mStore: TAtlasProblemStore;
  mVersion: Integer;
begin
  mStore := TAtlasProblemStore.Create;
  try
    mStore.SetTaskProblems('Lint', [TPair<string, TAtlasProblem>.Create('C:\P\B.pas', Problem(0, 0, 'x'))]);
    mStore.SetTests([TPair<string, TAtlasProblem>.Create('C:\P\B.pas', Problem(1, 0, 'Test'))]);
    Assert.IsFalse(mStore.Contains('C:\P\B.pas'), 'nur Aufgaben und Tests: nicht vom Server');
    Assert.AreEqual(2, Integer(Length(mStore.ForFile('C:\P\B.pas'))));
    mVersion := mStore.Version;
    mStore.SetTaskHidden('lint', True);
    Assert.IsTrue(mStore.Version > mVersion);
    Assert.IsTrue(mStore.TaskHidden('LINT'));
    Assert.AreEqual(1, Integer(Length(mStore.ForFile('C:\P\B.pas'))), 'ausgeblendet');
    Assert.AreEqual(1, mStore.TaskCount('Lint'), 'gezählt wird auch ausgeblendet');
    mStore.SetTaskHidden('Lint', False);
    Assert.AreEqual(2, Integer(Length(mStore.ForFile('C:\P\B.pas'))));
    // Tests weg: die Datei bleibt wegen der Aufgabe.
    mStore.ClearTests;
    Assert.AreEqual(1, Integer(Length(mStore.Files)));
    mStore.ClearTasks;
    Assert.AreEqual(0, Integer(Length(mStore.Files)), 'Datei nur mit Aufgaben fällt weg');
  finally
    mStore.Free;
  end;
end;

procedure TAtlasProblemsTests.ClearTestsDropsFilesOnlyWithTests;
var
  mStore: TAtlasProblemStore;
  mVersion: Integer;
begin
  mStore := TAtlasProblemStore.Create;
  try
    mStore.Update('C:\P\A.pas', 'a', True, [Problem(0, 0, 'Regel')], '1', True);
    mStore.SetTests([TPair<string, TAtlasProblem>.Create('C:\P\A.pas', Problem(0, 0, 'Test A')),
      TPair<string, TAtlasProblem>.Create('C:\P\B.pas', Problem(2, 0, 'Test B'))]);
    Assert.AreEqual(2, Integer(Length(mStore.Files)));
    mVersion := mStore.Version;
    mStore.SetTests([TPair<string, TAtlasProblem>.Create('C:\P\B.pas', Problem(3, 0, 'Test B neu'))]);
    Assert.IsTrue(mStore.Version > mVersion);
    Assert.AreEqual(1, Integer(Length(mStore.ForFile('C:\P\A.pas'))), 'Test A ersetzt, Regel bleibt');
    Assert.AreEqual('Test B neu', mStore.ForFile('C:\P\B.pas')[0].Message);
    mStore.ClearTests;
    Assert.IsFalse(mStore.Contains('C:\P\B.pas'));
    Assert.AreEqual(1, Integer(Length(mStore.Files)), 'Datei nur mit Tests fällt weg');
    mVersion := mStore.Version;
    mStore.ClearTests;
    Assert.AreEqual(mVersion, mStore.Version, 'nichts zu entfernen: keine neue Version');
  finally
    mStore.Free;
  end;
end;

procedure TAtlasProblemsTests.ProblemColorErrorIsError;
var
  mColors: TAtlasColors;
begin
  mColors := TAtlasColors.Light;
  Assert.AreEqual(mColors.Error, ProblemColor(mColors, Problem(0, 0, 'x')));
  Assert.AreEqual(mColors.Warn, ProblemColor(mColors, Problem(0, 0, 'x', 'Atlas', TAtlasProblemSeverity.Warning)));
  Assert.AreEqual(mColors.Accent,
    ProblemColor(mColors, Problem(0, 0, 'x', 'Atlas', TAtlasProblemSeverity.Information)));
end;

procedure TAtlasProblemsTests.ProblemColorFadedMixesSurface;
var
  mColors: TAtlasColors;
  mFaded: TAtlasProblem;
begin
  // Editor und Hover gleich blass.
  mColors := TAtlasColors.Dark;
  mFaded := Problem(0, 0, 'x', 'Atlas', TAtlasProblemSeverity.Warning);
  mFaded.Stale := True;
  Assert.AreEqual(TAtlasColorMath.Mix(mColors.Warn, mColors.Surface, cAtlasMixFaded), ProblemColor(mColors, mFaded));
  Assert.AreEqual(0.55, cAtlasMixFaded, 0.0001);
end;

procedure TAtlasProblemsTests.UsesHintsAreKeptApart;
var
  mItem: TJSONObject;
  mUnused, mKept, mInactive: TAtlasProblem;
  mStore: TAtlasProblemStore;
  mSpans: TArray<TAtlasColumnSpan>;
begin
  mItem := TJSONObject.ParseJSONValue('{"range":{"start":{"line":3,"character":2},"end":{"line":3,"character":11}},' +
    '"severity":4,"tags":[1],"source":"Atlas","message":"Aus Vcl.Grids wird nichts verwendet",' +
    '"data":{"uses":{"unit":"Vcl.Grids","state":"unused"}}}') as TJSONObject;
  try
    mUnused := TAtlasProblem.FromJson(mItem);
  finally
    mItem.Free;
  end;
  Assert.IsTrue(mUnused.IsUses);
  Assert.IsTrue(mUnused.Unnecessary);
  Assert.AreEqual('Vcl.Grids', mUnused.UsesUnit);
  Assert.AreEqual(TAtlasProblem.cUsesUnused, mUnused.UsesState);
  mKept := Problem(3, 13, 'Units.Reg wird wegen initialization nicht als ungenutzt gezeigt', 'Atlas',
    TAtlasProblemSeverity.Hint);
  mKept.EndCharacter := 22;
  mKept.UsesUnit := 'Units.Reg';
  mKept.UsesState := TAtlasProblem.cUsesInitialization;
  mInactive := Problem(5, 0, 'inaktiv');
  mInactive.EndLine := 6;
  mInactive.Unnecessary := True;
  mStore := TAtlasProblemStore.Create;
  try
    mStore.Update('C:\P\U.pas', 'unit U;'#10'interface'#10'uses'#10'  Vcl.Grids, Units.Reg;'#10'implementation'#10 +
      'x'#10'end.', True, [mUnused, mKept, mInactive, Problem(4, 0, 'echt')], '1', True);
    Assert.AreEqual(1, Integer(Length(mStore.ForFile('C:\P\U.pas'))), 'nur das echte Problem');
    Assert.AreEqual(1, Integer(Length(mStore.Inactive('C:\P\U.pas'))), 'nur der Zweig');
    Assert.AreEqual(1, Integer(Length(mStore.UnusedUses('C:\P\U.pas'))));
    mSpans := mStore.UsesSpans('C:\P\U.pas', 3, 4);
    Assert.AreEqual(1, Integer(Length(mSpans)));
    Assert.AreEqual(3, mSpans[0].First);
    Assert.AreEqual(11, mSpans[0].Last);
    Assert.AreEqual(0, Integer(Length(mStore.InactiveSpans('C:\P\U.pas', 3, 4))), 'kein inaktiver Zweig');
    Assert.AreEqual(1, Integer(Length(mStore.UsesAt('C:\P\U.pas', 3, 5))));
    Assert.AreEqual(TAtlasProblem.cUsesInitialization, mStore.UsesAt('C:\P\U.pas', 3, 15)[0].UsesState);
    Assert.AreEqual(0, Integer(Length(mStore.UsesAt('C:\P\U.pas', 4, 1))));
    // Nach einer Änderung in der Zeile: nichts abgeblendet, bis neue Diagnosen kommen.
    mStore.Edit('C:\P\U.pas', 'unit U;'#10'interface'#10'uses'#10'  Vcl.Grids, Units.Re;'#10'implementation'#10 +
      'x'#10'end.');
    Assert.AreEqual(0, Integer(Length(mStore.UsesSpans('C:\P\U.pas', 3, 4))));
  finally
    mStore.Free;
  end;
end;

procedure TAtlasProblemsTests.ProblemColorHintMuted;
var
  mColors: TAtlasColors;
begin
  mColors := TAtlasColors.Light;
  Assert.AreEqual(mColors.Muted, ProblemColor(mColors, Problem(0, 0, 'x', 'Atlas', TAtlasProblemSeverity.Hint)));
end;

procedure TAtlasProblemsTests.ManyProblemsInLargeUnitStayFast;
const
  cLines = 30000;
  cProblems = 20000;
var
  mStore: TAtlasProblemStore;
  mProblems: TArray<TAtlasProblem>;
  mBuilder: TStringBuilder;
  mText: string;
  mIndex: Integer;
  mWatch: TStopwatch;
begin
  mBuilder := TStringBuilder.Create;
  try
    for mIndex := 0 to cLines - 1 do
    begin
      mBuilder.Append('  mWert := mWert + ').Append(mIndex).Append(';').Append(#10);
    end;
    mText := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
  // Jeder zweite Befund doppelt (andere Schreibweise): Er fällt weg.
  SetLength(mProblems, cProblems);
  for mIndex := 0 to cProblems - 1 do
  begin
    mProblems[mIndex] := Problem(mIndex div 2, 2, 'Befund ' + IntToStr(mIndex div 2));
    if Odd(mIndex) then
    begin
      mProblems[mIndex].Message := UpperCase(mProblems[mIndex].Message);
    end;
  end;
  mStore := TAtlasProblemStore.Create;
  try
    mStore.Update('C:\P\Gross.pas', mText, True, mProblems, '1', False);
    mWatch := TStopwatch.StartNew;
    for mIndex := 1 to 5 do
    begin
      mStore.Edit('C:\P\Gross.pas', Copy(mText, 1, 1000) + 'x' + Copy(mText, 1001, MaxInt));
      mProblems := mStore.ForFile('C:\P\Gross.pas');
      mStore.Edit('C:\P\Gross.pas', mText);
      mProblems := mStore.ForFile('C:\P\Gross.pas');
    end;
    mWatch.Stop;
    Assert.AreEqual(cProblems div 2, Integer(Length(mProblems)));
    Assert.IsTrue(mWatch.ElapsedMilliseconds < 1000, 'Dauer ' + IntToStr(mWatch.ElapsedMilliseconds) + ' ms');
  finally
    mStore.Free;
  end;
  mProblems := nil;
  mText := '';
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasProblemsTests);

end.
