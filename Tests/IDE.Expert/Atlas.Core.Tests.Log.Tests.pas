unit Atlas.Core.Tests.Log.Tests;

// Tests des Protokolls je Test (#2168): Zuordnung der Zeilen aus Seitendatei
// und Konsole zu Tests (Setup/TearDown der Fixture, verschachtelte Fixtures,
// [TestCase], nach Testende), Grenze tests.log.maxLines, Lauf ohne Logger,
// Erkennung der Verweise und Anzeige.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tests')]
  TAtlasTestLogTests = class
  public
    [Test]
    procedure ThreeLogLinesOnlyOfOwnTest;
    [Test]
    procedure TimeRelativeToTestStartWithLevels;
    [Test]
    procedure FixtureSetupAndTearDownOwnEntry;
    [Test]
    procedure NestedFixturesKeepOuterFixture;
    [Test]
    procedure TestCasesShownUnderTheirMethod;
    [Test]
    procedure LinesBetweenTestsMarkedAfterEnd;
    [Test]
    procedure ConsoleLinesBetweenMarksInOrder;
    [Test]
    procedure WithoutLoggerHintAndWholeOutput;
    [Test]
    procedure CutAtMaxLinesWithHint;
    [Test]
    procedure NewRunReplacesEntriesOfItsTests;
    [Test]
    procedure ReferenceFileAndLine;
    [Test]
    procedure ReferenceRoutineWithoutLine;
    [Test]
    procedure NoReferenceInPlainText;
    [Test]
    procedure RoutineLineInImplementation;
    [Test]
    procedure SideFileNextToReport;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Tests.Log;

const
  cTab = #9;
  cFixture = 'Kunden.Tests.TKundenTests';
  cFirst = 'Kunden.Tests.TKundenTests.Laedt';
  cSecond = 'Kunden.Tests.TKundenTests.Speichert';

function Line(AMs: Integer; const AKind, AText: string): string;
begin
  Result := IntToStr(AMs) + cTab + AKind + cTab + AText + #10;
end;

function Head: string;
begin
  Result := Line(0, 'A', '1');
end;

function Texts: TAtlasTestLogTexts;
begin
  Result := Default(TAtlasTestLogTexts);
  Result.Start := 'Start';
  Result.Finish := 'Ende';
  Result.Warning := 'Warnung: %s';
  Result.Error := 'Fehler: %s';
  Result.Console := 'Konsole: %s';
  Result.AfterEnd := '%s (nach Testende)';
  Result.Dropped := '%d abgeschnitten';
  Result.Fixture := 'Fixture:';
  Result.NoLogger := 'Kein Logger' + #10 + 'So einschalten';
  Result.Output := 'Ausgabe:';
  Result.Empty := 'Leer';
  Result.DecimalSeparator := ',';
end;

function Units: TArray<TAtlasTestLogUnit>;
begin
  SetLength(Result, 2);
  Result[0].UnitName := 'Kunden';
  Result[0].FileName := 'C:\Projekt\Kunden.pas';
  Result[1].UnitName := 'Atlas.Core.Tracker.Queue';
  Result[1].FileName := 'C:\Projekt\Atlas.Core.Tracker.Queue.pas';
end;

/// <summary>Texte der Zeilen von ARows.</summary>
function TextsOf(const ARows: TArray<TAtlasTestLogRow>): string;
var
  mRow: TAtlasTestLogRow;
begin
  Result := '';
  for mRow in ARows do
  begin
    Result := Result + mRow.Text + '|';
  end;
end;

/// <summary>Zwei Tests einer Fixture, der erste mit drei Log-Meldungen, der zweite mit einer.</summary>
function TwoTests: string;
begin
  Result := Head + Line(0, 'F+', cFixture) + Line(10, 'T+', cFirst) + Line(12, 'I', 'eins') +
    Line(15, 'W', 'zwei') + Line(1200, 'E', 'drei') + Line(1210, 'T-', '') + Line(1220, 'T+', cSecond) +
    Line(1225, 'I', 'fremd') + Line(1230, 'T-', '') + Line(1240, 'F-', '');
end;

procedure TAtlasTestLogTests.ThreeLogLinesOnlyOfOwnTest;
var
  mRun: TAtlasTestLogRun;
  mRows: TArray<TAtlasTestLogRow>;
begin
  mRun := TAtlasTestLog.Parse(TwoTests, '', 2000);
  Assert.IsTrue(mRun.HasLogger);
  mRows := TAtlasTestLog.Rows(mRun, cFirst, Units, Texts);
  Assert.AreEqual(5, Integer(Length(mRows)), TextsOf(mRows));
  Assert.IsTrue(mRows[0].Text.EndsWith('Start'));
  Assert.IsTrue(mRows[1].Text.EndsWith('eins'));
  Assert.IsTrue(mRows[4].Text.EndsWith('Ende'));
  Assert.AreEqual(0, Pos('fremd', TextsOf(mRows)), 'keine Zeilen anderer Tests');
  Assert.AreEqual(3, TAtlasTestLog.CountOf(mRun, cFirst), 'ohne Start und Ende');
  Assert.AreEqual(1, TAtlasTestLog.CountOf(mRun, cSecond));
end;

procedure TAtlasTestLogTests.TimeRelativeToTestStartWithLevels;
var
  mRows: TArray<TAtlasTestLogRow>;
begin
  mRows := TAtlasTestLog.Rows(TAtlasTestLog.Parse(TwoTests, '', 2000), cFirst, Units, Texts);
  Assert.AreEqual('00,000  Start', mRows[0].Text);
  Assert.AreEqual('00,002  eins', mRows[1].Text);
  Assert.AreEqual('00,005  Warnung: zwei', mRows[2].Text);
  Assert.AreEqual('01,190  Fehler: drei', mRows[3].Text);
  Assert.AreEqual('01,200  Ende', mRows[4].Text);
end;

procedure TAtlasTestLogTests.FixtureSetupAndTearDownOwnEntry;
var
  mRun: TAtlasTestLogRun;
  mText: string;
begin
  mRun := TAtlasTestLog.Parse(Head + Line(0, 'F+', cFixture) + Line(1, 'S+', '') + Line(2, 'I', 'Datenbank auf') +
    Line(3, 'S-', '') + Line(10, 'T+', cFirst) + Line(11, 'I', 'im Test') + Line(12, 'T-', '') + Line(20, 'S+', '') +
    Line(21, 'I', 'Datenbank zu') + Line(22, 'S-', '') + Line(23, 'F-', ''), '', 2000);
  mText := TextsOf(TAtlasTestLog.Rows(mRun, cFixture, Units, Texts));
  Assert.IsTrue(mText.StartsWith('Fixture:|'), mText);
  Assert.IsTrue(Pos('Datenbank auf', mText) > 0, mText);
  Assert.IsTrue(Pos('Datenbank zu', mText) > 0, 'TearDown der Fixture gehört nicht zum letzten Test');
  Assert.AreEqual(0, Pos('im Test', mText));
  Assert.AreEqual(1, TAtlasTestLog.CountOf(mRun, cFirst));
end;

procedure TAtlasTestLogTests.NestedFixturesKeepOuterFixture;
var
  mRun: TAtlasTestLogRun;
  mText: string;
begin
  mRun := TAtlasTestLog.Parse(Head + Line(0, 'F+', cFixture) + Line(1, 'F+', cFixture + '.TInnen') +
    Line(2, 'T+', cFixture + '.TInnen.Rechnet') + Line(3, 'I', 'innen') + Line(4, 'T-', '') + Line(5, 'F-', '') +
    Line(6, 'S+', '') + Line(7, 'I', 'aussen aufgeraeumt') + Line(8, 'S-', '') + Line(9, 'F-', ''), '', 2000);
  Assert.AreEqual(1, TAtlasTestLog.CountOf(mRun, cFixture + '.TInnen.Rechnet'));
  mText := TextsOf(TAtlasTestLog.Rows(mRun, cFixture, Units, Texts));
  Assert.IsTrue(Pos('aussen aufgeraeumt', mText) > 0, mText);
end;

procedure TAtlasTestLogTests.TestCasesShownUnderTheirMethod;
var
  mRun: TAtlasTestLogRun;
  mText: string;
begin
  mRun := TAtlasTestLog.Parse(Head + Line(0, 'F+', cFixture) + Line(1, 'T+', cFirst + '.Eins') +
    Line(2, 'I', 'Fall eins') + Line(3, 'T-', '') + Line(4, 'T+', cFirst + '(1,2)') + Line(5, 'I', 'Fall zwei') +
    Line(6, 'T-', '') + Line(7, 'F-', ''), '', 2000);
  mText := TextsOf(TAtlasTestLog.Rows(mRun, cFirst, Units, Texts));
  Assert.IsTrue(Pos(cFirst + '.Eins|', mText) > 0, 'Überschrift je Fall: ' + mText);
  Assert.IsTrue(Pos('Fall eins', mText) > 0);
  Assert.IsTrue(Pos('Fall zwei', mText) > 0, 'AutoNameTestCase „Methode(1,2)“');
  Assert.AreEqual(2, TAtlasTestLog.CountOf(mRun, cFirst));
  Assert.AreEqual(1, TAtlasTestLog.CountOf(mRun, cFirst + '.Eins'));
end;

procedure TAtlasTestLogTests.LinesBetweenTestsMarkedAfterEnd;
var
  mRun: TAtlasTestLogRun;
  mRows: TArray<TAtlasTestLogRow>;
begin
  mRun := TAtlasTestLog.Parse(Head + Line(0, 'F+', cFixture) + Line(10, 'T+', cFirst) + Line(20, 'T-', '') +
    Line(25, 'I', 'Thread meldet sich spaet') + Line(30, 'T+', cSecond) + Line(40, 'T-', '') + Line(50, 'F-', ''),
    '', 2000);
  mRows := TAtlasTestLog.Rows(mRun, cFirst, Units, Texts);
  Assert.AreEqual('00,015  Thread meldet sich spaet (nach Testende)', mRows[High(mRows)].Text);
  Assert.AreEqual(0, TAtlasTestLog.CountOf(mRun, cSecond));
end;

procedure TAtlasTestLogTests.ConsoleLinesBetweenMarksInOrder;
var
  mRun: TAtlasTestLogRun;
  mRows: TArray<TAtlasTestLogRow>;
  mConsole: string;
begin
  mConsole := 'Banner vor allen Tests' + #13#10 + TAtlasTestLog.cConsoleBegin + cFirst + #13#10 +
    'vor dem ersten Log' + #13#10 + TAtlasTestLog.cConsoleLog + #13#10 + '  eins' + #13#10 +
    'nach dem ersten Log' + #13#10 + TAtlasTestLog.cConsoleLog + #13#10 + TAtlasTestLog.cConsoleLog + #13#10 +
    TAtlasTestLog.cConsoleEnd + #13#10 + 'zwischen den Tests' + #13#10;
  mRun := TAtlasTestLog.Parse(TwoTests, mConsole, 2000);
  mRows := TAtlasTestLog.Rows(mRun, cFirst, Units, Texts);
  Assert.AreEqual(7, Integer(Length(mRows)), TextsOf(mRows));
  Assert.AreEqual('        Konsole: vor dem ersten Log', mRows[1].Text);
  Assert.IsTrue(mRows[2].Text.EndsWith('eins'));
  Assert.AreEqual('        Konsole: nach dem ersten Log', mRows[3].Text);
  Assert.AreEqual(0, Pos('Banner', TextsOf(mRows)));
  Assert.AreEqual(0, Pos('zwischen den Tests', TextsOf(mRows)));
  Assert.AreEqual(5, TAtlasTestLog.CountOf(mRun, cFirst), 'Wiederholung der Meldung durch die Konsole entfällt');
end;

procedure TAtlasTestLogTests.WithoutLoggerHintAndWholeOutput;
var
  mRun: TAtlasTestLogRun;
  mRows: TArray<TAtlasTestLogRow>;
begin
  mRun := TAtlasTestLog.Parse('', 'Zeile 1' + #13#10 + 'Fehler in Kunden.pas:42' + #13#10, 2000);
  Assert.IsFalse(mRun.HasLogger);
  mRows := TAtlasTestLog.Rows(mRun, cFirst, Units, Texts);
  Assert.AreEqual('Kein Logger|So einschalten|Ausgabe:|Zeile 1|Fehler in Kunden.pas:42|', TextsOf(mRows));
  Assert.AreEqual('C:\Projekt\Kunden.pas', mRows[4].FileName);
  Assert.AreEqual(41, mRows[4].Line);
  Assert.AreEqual(0, TAtlasTestLog.CountOf(mRun, cFirst));
end;

procedure TAtlasTestLogTests.CutAtMaxLinesWithHint;
var
  mSide: string;
  mIndex: Integer;
  mRun: TAtlasTestLogRun;
  mRows: TArray<TAtlasTestLogRow>;
begin
  mSide := Head + Line(0, 'T+', cFirst);
  for mIndex := 1 to 105 do
  begin
    mSide := mSide + Line(mIndex, 'I', 'Zeile ' + IntToStr(mIndex));
  end;
  mSide := mSide + Line(200, 'T-', '');
  mRun := TAtlasTestLog.Parse(mSide, '', 100);
  Assert.AreEqual(100, Integer(Length(mRun.Entries[0].Lines)));
  Assert.AreEqual(7, mRun.Entries[0].Dropped, 'sechs Meldungen und das Ende');
  mRows := TAtlasTestLog.Rows(mRun, cFirst, Units, Texts);
  Assert.AreEqual('7 abgeschnitten', mRows[High(mRows)].Text);
  // Unter der Untergrenze gilt die Untergrenze.
  Assert.AreEqual(100, Integer(Length(TAtlasTestLog.Parse(mSide, '', 5).Entries[0].Lines)));
end;

procedure TAtlasTestLogTests.NewRunReplacesEntriesOfItsTests;
var
  mOld, mNew, mMerged: TAtlasTestLogRun;
begin
  mOld := TAtlasTestLog.Parse(TwoTests, '', 2000);
  mNew := TAtlasTestLog.Parse(Head + Line(0, 'T+', cSecond) + Line(1, 'I', 'neu') + Line(2, 'I', 'neu2') +
    Line(3, 'T-', ''), '', 2000);
  mMerged := TAtlasTestLog.Merged(mOld, mNew);
  Assert.AreEqual(3, TAtlasTestLog.CountOf(mMerged, cFirst), 'Tests ohne neuen Lauf behalten ihr Protokoll');
  Assert.AreEqual(2, TAtlasTestLog.CountOf(mMerged, cSecond));
end;

procedure TAtlasTestLogTests.ReferenceFileAndLine;
var
  mFile, mRoutine: string;
  mLine: Integer;
begin
  Assert.IsTrue(TAtlasTestLog.Reference('bei Kunden.pas:42', Units, mFile, mLine, mRoutine));
  Assert.AreEqual('C:\Projekt\Kunden.pas', mFile);
  Assert.AreEqual(41, mLine);
  Assert.IsTrue(TAtlasTestLog.Reference('Fehler in Kunden.pas(7)', Units, mFile, mLine, mRoutine));
  Assert.AreEqual(6, mLine);
  Assert.IsTrue(TAtlasTestLog.Reference('bei Atlas.Core.Tracker.Queue.pas:218', Units, mFile, mLine, mRoutine));
  Assert.AreEqual('C:\Projekt\Atlas.Core.Tracker.Queue.pas', mFile, 'der längste passende Unitname gilt');
  Assert.AreEqual(217, mLine);
end;

procedure TAtlasTestLogTests.ReferenceRoutineWithoutLine;
var
  mFile, mRoutine: string;
  mLine: Integer;
begin
  Assert.IsTrue(TAtlasTestLog.Reference('Ausnahme in Atlas.Core.Tracker.Queue.TQueue.Sync: Zeitlimit', Units, mFile,
    mLine, mRoutine));
  Assert.AreEqual('C:\Projekt\Atlas.Core.Tracker.Queue.pas', mFile);
  Assert.AreEqual(-1, mLine);
  Assert.AreEqual('TQueue.Sync', mRoutine);
end;

procedure TAtlasTestLogTests.NoReferenceInPlainText;
var
  mFile, mRoutine: string;
  mLine: Integer;
begin
  Assert.IsFalse(TAtlasTestLog.Reference('Kunden 3 geladen', Units, mFile, mLine, mRoutine));
  Assert.IsFalse(TAtlasTestLog.Reference('Datei Andere.pas:12', Units, mFile, mLine, mRoutine),
    'nur Units des Testprojekts');
  Assert.AreEqual('', mFile);
end;

procedure TAtlasTestLogTests.RoutineLineInImplementation;
var
  mLines: TArray<string>;
begin
  mLines := TArray<string>.Create('unit Atlas.Core.Tracker.Queue;', 'interface', 'type',
    '  TQueue = class', '    procedure Sync;', '  end;', 'implementation', '', 'procedure TQueue.SyncAll;',
    'begin', 'end;', '', 'procedure TQueue.Sync;', 'begin', 'end;', 'end.');
  Assert.AreEqual(12, TAtlasTestLog.RoutineLine(mLines, 'TQueue.Sync'));
  Assert.AreEqual(8, TAtlasTestLog.RoutineLine(mLines, 'tqueue.syncall'));
  Assert.AreEqual(-1, TAtlasTestLog.RoutineLine(mLines, 'TQueue.Fehlt'));
end;

procedure TAtlasTestLogTests.SideFileNextToReport;
begin
  Assert.AreEqual('C:\Temp\atlas-tests-1.atlas-log', TAtlasTestLog.SideFileOf('C:\Temp\atlas-tests-1.xml'));
  Assert.AreEqual('00,000', TAtlasTestLog.TimeText(0, ','));
  Assert.AreEqual('12.034', TAtlasTestLog.TimeText(12034, '.'));
  Assert.AreEqual('      ', TAtlasTestLog.TimeText(-1, ','));
end;

end.
