unit Atlas.Core.Tests.AssertLine.Tests;

// Tests der Zeile eines Fehlschlags (#1771) ohne IDE: Stacktrace von JclDebug,
// madExcept und „Datei.pas:42“, Rückfall über den erwarteten Wert der
// Assert-Aufrufe, mehrdeutige Kandidaten und der Bereich der Anweisung.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tests')]
  TAtlasAssertLineTests = class
  private
    FLines: TArray<string>;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure JclStackTraceGivesLine;
    [Test]
    procedure MadExceptStackTraceGivesLine;
    [Test]
    procedure FileColonLineGivesLine;
    [Test]
    procedure StackTraceWithoutLineOrUnitGivesNone;
    [Test]
    procedure MatchingExpectedValuePicksAssert;
    [Test]
    procedure TwoMatchingAssertsPickNone;
    [Test]
    procedure SingleAssertWithoutValues;
    [Test]
    procedure ErrorWithoutStackTraceStaysAtHeader;
    [Test]
    procedure AssertsInCommentsDoNotCount;
    [Test]
    procedure FindPrefersStackTrace;
    [Test]
    procedure StatementRangeWithoutComment;
    [Test]
    procedure ValuesCompareAsNumbersAndStrings;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Tests.AssertLine,
  Atlas.Text.DUnitX,
  Atlas.Text.TestResults;

const
  cFile = 'C:\Projekt\Tests\Rechner.Tests.pas';

function Source: TArray<string>;
begin
  Result := TArray<string>.Create(
    'unit Rechner.Tests;',                                    // 0
    'interface',                                              // 1
    'uses DUnitX.TestFramework;',                             // 2
    'type',                                                   // 3
    '  [TestFixture]',                                        // 4
    '  TRechnerTests = class',                                // 5
    '  public',                                               // 6
    '    [Test]',                                             // 7
    '    procedure Addiert;',                                 // 8
    '    [Test]',                                             // 9
    '    procedure Doppelt;',                                 // 10
    '  end;',                                                 // 11
    'implementation',                                         // 12
    'procedure TRechnerTests.Addiert;',                       // 13
    'begin',                                                  // 14
    '  Assert.AreEqual(2, Summe(1, 1));',                     // 15
    '  Assert.AreEqual(4, Summe(2, 2)); // zweiter',          // 16
    '  // Assert.AreEqual(4, Alt(2, 2));',                    // 17
    '  { Assert.AreEqual(4, Alt(2, 2)); }',                   // 18
    '  Assert.AreEqual(''drei'', Name(3));',                  // 19
    'end;',                                                   // 20
    'procedure TRechnerTests.Doppelt;',                       // 21
    'begin',                                                  // 22
    '  Assert.AreEqual(4, Summe(2, 2));',                     // 23
    '  Assert.AreEqual(4, Produkt(2, 2));',                   // 24
    'end;',                                                   // 25
    'end.');                                                  // 26
end;

function Failure(const AMethod, AExpected, AActual, AStackTrace: string): TTestCaseResult;
begin
  Result := Default(TTestCaseResult);
  Result.UnitName := 'Rechner.Tests';
  Result.Fixture := 'TRechnerTests';
  Result.Method := AMethod;
  Result.Outcome := TTestOutcome.Failed;
  Result.Expected := AExpected;
  Result.Actual := AActual;
  Result.HasValues := AExpected <> '';
  Result.StackTrace := AStackTrace;
end;

procedure TAtlasAssertLineTests.Setup;
begin
  FLines := Source;
end;

procedure TAtlasAssertLineTests.TearDown;
begin
  FLines := nil;
end;

procedure TAtlasAssertLineTests.JclStackTraceGivesLine;
const
  cTrace = '[004B3F2A]{RechnerTests.exe} DUnitX.Assert.Assert.AreEqual (Line 312, "DUnitX.Assert.pas" + 4) + $1F'#13#10 +
    '[004C1234]{RechnerTests.exe} Rechner.Tests.TRechnerTests.Addiert (Line 17, "Rechner.Tests.pas" + 3) + $12'#13#10 +
    '[004C1300]{RechnerTests.exe} DUnitX.TestFixture.TDUnitXTestFixture.Execute (Line 80, "DUnitX.TestFixture.pas")';
begin
  Assert.AreEqual(16, TAtlasAssertLine.FromStackTrace(cTrace, 'Rechner.Tests', cFile, Length(FLines)),
    'erster Eintrag der Testunit, 0-basiert');
end;

procedure TAtlasAssertLineTests.MadExceptStackTraceGivesLine;
const
  cTrace = '0045a2b3 +01f RechnerTests.exe DUnitX.Assert        312  +4 Assert.AreEqual'#10 +
    '0045c111 +012 RechnerTests.exe Rechner.Tests         17  +3 TRechnerTests.Addiert'#10;
begin
  Assert.AreEqual(16, TAtlasAssertLine.FromStackTrace(cTrace, 'Rechner.Tests', cFile, Length(FLines)));
end;

procedure TAtlasAssertLineTests.FileColonLineGivesLine;
begin
  Assert.AreEqual(19, TAtlasAssertLine.FromStackTrace('at TRechnerTests.Addiert in Tests/Rechner.Tests.pas:20',
    'Rechner.Tests', cFile, Length(FLines)));
  Assert.AreEqual(19, TAtlasAssertLine.FromStackTrace('Rechner.Tests.pas(20) TRechnerTests.Addiert',
    'Rechner.Tests', cFile, Length(FLines)));
end;

procedure TAtlasAssertLineTests.StackTraceWithoutLineOrUnitGivesNone;
begin
  Assert.AreEqual(-1, TAtlasAssertLine.FromStackTrace('', 'Rechner.Tests', cFile, Length(FLines)), 'leer');
  Assert.AreEqual(-1, TAtlasAssertLine.FromStackTrace('[004B3F2A] DUnitX.Assert.Assert.AreEqual (Line 312)',
    'Rechner.Tests', cFile, Length(FLines)), 'nur DUnitX');
  Assert.AreEqual(-1, TAtlasAssertLine.FromStackTrace('[004C1234] Rechner.Tests.TRechnerTests.Addiert + $12',
    'Rechner.Tests', cFile, Length(FLines)), 'Testunit ohne Zeile');
  Assert.AreEqual(-1, TAtlasAssertLine.FromStackTrace('Rechner.TestsHilfe.Machen (Line 5)', 'Rechner.Tests', cFile,
    Length(FLines)), 'nur ein anderer Unit-Name mit gleichem Anfang');
  Assert.AreEqual(-1, TAtlasAssertLine.FromStackTrace('Rechner.Tests.TRechnerTests.Addiert (Line 900)',
    'Rechner.Tests', cFile, Length(FLines)), 'Zeile hinter dem Dateiende');
end;

procedure TAtlasAssertLineTests.MatchingExpectedValuePicksAssert;
begin
  Assert.AreEqual(16, TAtlasAssertLine.FromAsserts(FLines, 14, 20, '4', True, True), 'Zahl');
  Assert.AreEqual(19, TAtlasAssertLine.FromAsserts(FLines, 14, 20, 'drei', True, True), 'String-Literal');
end;

procedure TAtlasAssertLineTests.TwoMatchingAssertsPickNone;
begin
  Assert.AreEqual(-1, TAtlasAssertLine.FromAsserts(FLines, 22, 25, '4', True, True));
  Assert.AreEqual(-1, TAtlasAssertLine.FromAsserts(FLines, 14, 20, '7', True, True), 'kein Kandidat, drei Asserts');
end;

procedure TAtlasAssertLineTests.SingleAssertWithoutValues;
var
  mLines: TArray<string>;
begin
  mLines := TArray<string>.Create('begin', '  Assert.IsTrue(Fertig);', 'end;');
  Assert.AreEqual(1, TAtlasAssertLine.FromAsserts(mLines, 0, 2, '', False, True));
  Assert.AreEqual(1, TAtlasAssertLine.FromAsserts(mLines, 0, 2, '9', True, True), 'Wert passt nicht, einziges');
end;

procedure TAtlasAssertLineTests.ErrorWithoutStackTraceStaysAtHeader;
var
  mLines: TArray<string>;
begin
  // Eine Ausnahme kann aus jeder Anweisung kommen: ohne Stacktrace bleibt es beim Methodenkopf.
  mLines := TArray<string>.Create('begin', '  Lade;', '  Assert.IsTrue(Fertig);', 'end;');
  Assert.AreEqual(-1, TAtlasAssertLine.FromAsserts(mLines, 0, 3, '', False, False));
end;

procedure TAtlasAssertLineTests.AssertsInCommentsDoNotCount;
var
  mLines: TArray<string>;
begin
  mLines := TArray<string>.Create('begin', '  { Assert.AreEqual(4, X);', '    Assert.AreEqual(4, Y); }',
    '  (* Assert.AreEqual(4, Z); *)', '  Writeln(''Assert.AreEqual(4, W)'');', '  Assert.AreEqual(4, V);', 'end;');
  Assert.AreEqual(5, TAtlasAssertLine.FromAsserts(mLines, 0, 6, '4', True, True));
end;

procedure TAtlasAssertLineTests.FindPrefersStackTrace;
var
  mUnit: TDUnitXUnit;
begin
  mUnit := TDUnitXSource.Scan(FLines);
  Assert.AreEqual(15, TAtlasAssertLine.Find(Failure('Addiert', '4', '3',
    'Rechner.Tests.TRechnerTests.Addiert (Line 16, "Rechner.Tests.pas")'), mUnit, FLines, cFile), 'Stacktrace');
  Assert.AreEqual(16, TAtlasAssertLine.Find(Failure('Addiert', '4', '3', ''), mUnit, FLines, cFile), 'Rückfall');
  Assert.AreEqual(-1, TAtlasAssertLine.Find(Failure('Doppelt', '4', '5', ''), mUnit, FLines, cFile),
    'zwei passende');
  Assert.AreEqual(-1, TAtlasAssertLine.Find(Failure('Fehlt', '4', '5', ''), mUnit, FLines, cFile), 'unbekannt');
end;

procedure TAtlasAssertLineTests.StatementRangeWithoutComment;
var
  mStart, mEnd: Integer;
begin
  TAtlasAssertLine.Statement(FLines[16], mStart, mEnd);
  Assert.AreEqual(2, mStart);
  Assert.AreEqual(Integer(Length('  Assert.AreEqual(4, Summe(2, 2));')), mEnd);
  TAtlasAssertLine.Statement(FLines[19], mStart, mEnd);
  Assert.AreEqual(Integer(Length(FLines[19])), mEnd, 'ohne Kommentar ganze Zeile');
end;

procedure TAtlasAssertLineTests.ValuesCompareAsNumbersAndStrings;
begin
  Assert.IsTrue(TAtlasAssertLine.MatchesExpected('4', '4'));
  Assert.IsTrue(TAtlasAssertLine.MatchesExpected('4.5', '4,5'), 'Komma im Bericht');
  Assert.IsTrue(TAtlasAssertLine.MatchesExpected('''it''''s''', 'it''s'), 'Literal mit Hochkomma');
  Assert.IsTrue(TAtlasAssertLine.MatchesExpected('''abc''', '"abc"'), 'Bericht mit Anführungszeichen');
  Assert.IsFalse(TAtlasAssertLine.MatchesExpected('cErwartet', '4'), 'Konstante');
  Assert.IsFalse(TAtlasAssertLine.MatchesExpected('', ''), 'leer');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasAssertLineTests);

end.
