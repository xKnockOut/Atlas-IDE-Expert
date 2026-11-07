unit Atlas.Core.Tasks.Runs.Tests;

// Tests für Läufe von Projektaufgaben (#900): Zeilen aus Bytes (UTF-8,
// Ersatz-Codepage, CR, Farbfolgen, Rest am Ende), Zählung der Befunde,
// Entscheidung warn/block vor dem Build, letzter Lauf und ausgeblendete
// Aufgaben als JSON.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Build')]
  TAtlasTaskRunsTests = class
  public
    [Test]
    procedure LinesAreSplitAcrossChunks;
    [Test]
    procedure NonUtf8LinesUseTheCodePage;
    [Test]
    procedure CountsAndPassed;
    [Test]
    procedure WarnNeverBlocksBlockStopsOnErrorsOrExitCode;
    [Test]
    procedure HistoryKeepsLastRunAndHiddenPerProject;
    [Test]
    procedure HistoryRoundTripAndBrokenText;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  Atlas.Core.Tasks.Definitions,
  Atlas.Core.Tasks.Matchers,
  Atlas.Core.Tasks.Runs;

function Bytes(const AText: string): TBytes;
begin
  Result := TEncoding.UTF8.GetBytes(AText);
end;

function Run(const AName: string; AExitCode, AErrors, AWarnings: Integer): TAtlasTaskRun;
var
  mIndex: Integer;
  mFinding: TAtlasTaskFinding;
begin
  Result := Default(TAtlasTaskRun);
  Result.Name := AName;
  Result.Outcome := TAtlasTaskOutcome.Finished;
  Result.ExitCode := AExitCode;
  for mIndex := 1 to AErrors do
  begin
    mFinding := Default(TAtlasTaskFinding);
    mFinding.Severity := TAtlasTaskSeverity.Error;
    Result.Findings := Result.Findings + [mFinding];
  end;
  for mIndex := 1 to AWarnings do
  begin
    mFinding := Default(TAtlasTaskFinding);
    mFinding.Severity := TAtlasTaskSeverity.Warning;
    Result.Findings := Result.Findings + [mFinding];
  end;
end;

function Entry(AMode: TAtlasTaskBeforeBuild; const ARun: TAtlasTaskRun): TAtlasTaskGateEntry;
begin
  Result.Mode := AMode;
  Result.Run := ARun;
end;

procedure TAtlasTaskRunsTests.LinesAreSplitAcrossChunks;
var
  mLines: TAtlasTaskLines;
  mGot: TArray<string>;
  mData: TBytes;
begin
  mLines := TAtlasTaskLines.Create(0);
  try
    mData := Bytes('eins'#13#10'zw');
    mGot := mLines.Feed(mData, Length(mData));
    Assert.AreEqual('eins', string.Join('|', mGot), 'CR fällt weg, „zw“ wartet');
    mData := Bytes('ei'#10#10#27'[31mrot'#27'[0m'#10'Ende');
    mGot := mLines.Feed(mData, Length(mData));
    Assert.AreEqual('zwei||rot', string.Join('|', mGot), 'leere Zeile bleibt, Farbfolgen fallen weg');
    // Nur ein Teil des Puffers gilt.
    mData := Bytes('!xyz');
    mGot := mLines.Feed(mData, 1);
    Assert.AreEqual(0, Integer(Length(mGot)));
    Assert.AreEqual('Ende!', string.Join('|', mLines.Flush));
    Assert.AreEqual(0, Integer(Length(mLines.Flush)), 'Rest nur einmal');
    // UTF-8 über die Grenze zweier Stücke: ü = C3 BC.
    mData := TBytes.Create($50, $72, $C3);
    mLines.Feed(mData, Length(mData));
    mData := TBytes.Create($BC, $66, 10);
    mGot := mLines.Feed(mData, Length(mData));
    Assert.AreEqual('Prüf', string.Join('|', mGot));
    // Fenstertitel (OSC) und einzelne Steuerzeichen am Ende.
    Assert.AreEqual('ab', TAtlasTaskLines.Clean('a'#27']0;Titel'#7'b'));
    Assert.AreEqual('ab', TAtlasTaskLines.Clean('a'#27']0;T'#27'\b'#27));
    Assert.AreEqual('Fehler', TAtlasTaskLines.Clean(#27'[1;31;40mFehler'#27'[K'#13));
  finally
    mLines.Free;
  end;
end;

procedure TAtlasTaskRunsTests.NonUtf8LinesUseTheCodePage;
var
  mLines: TAtlasTaskLines;
  mData: TBytes;
begin
  // Gültiges UTF-8 gewinnt auch mit Codepage; überlange Formen und abgeschnittene Folgen nicht.
  mLines := TAtlasTaskLines.Create(1252);
  try
    mData := Bytes('Prüfung ✓' + #10);
    Assert.AreEqual('Prüfung ✓', string.Join('|', mLines.Feed(mData, Length(mData))));
    mData := TBytes.Create($C0, $80, 10);
    Assert.AreEqual(#$00C0#$20AC, string.Join('|', mLines.Feed(mData, Length(mData))), 'überlange Form');
    mData := TBytes.Create($E2, $9C, 10);
    Assert.AreEqual(#$00E2#$0153, string.Join('|', mLines.Feed(mData, Length(mData))), 'abgeschnitten');
  finally
    mLines.Free;
  end;
  // 1252: FC = ü.
  mLines := TAtlasTaskLines.Create(1252);
  try
    mData := TBytes.Create($50, $72, $FC, $66, 10);
    Assert.AreEqual('Prüf', string.Join('|', mLines.Feed(mData, Length(mData))));
  finally
    mLines.Free;
  end;
  Assert.AreEqual('ab', TAtlasTaskLines.Clean(#27'[1;32ma'#27'[0mb'#13));
end;

procedure TAtlasTaskRunsTests.CountsAndPassed;
var
  mValue: TAtlasTaskRun;
  mLast: TAtlasTaskLastRun;
begin
  mValue := Run('A', 0, 2, 1);
  Assert.AreEqual(2, mValue.Counts.Errors);
  Assert.AreEqual(1, mValue.Counts.Warnings);
  Assert.AreEqual(3, mValue.Counts.Total);
  Assert.IsTrue(mValue.ExitedCleanly);
  Assert.IsFalse(mValue.Passed, 'Fehler-Befunde');
  Assert.IsTrue(Run('A', 0, 0, 3).Passed, 'nur Warnungen');
  Assert.IsFalse(Run('A', 1, 0, 0).Passed, 'Exit-Code 1');
  mValue := Run('A', 0, 0, 0);
  mValue.Outcome := TAtlasTaskOutcome.TimedOut;
  Assert.IsFalse(mValue.Passed);
  mLast := TAtlasTaskLastRun.From(Run('B', 0, 0, 2));
  Assert.AreEqual('B', mLast.Name);
  Assert.AreEqual(2, mLast.Counts.Warnings);
  Assert.IsTrue(mLast.Passed);
end;

procedure TAtlasTaskRunsTests.WarnNeverBlocksBlockStopsOnErrorsOrExitCode;
var
  mDecision: TAtlasTaskGateDecision;
  mMissing: TAtlasTaskRun;
begin
  mDecision := TAtlasTaskGate.Decide([Entry(TAtlasTaskBeforeBuild.Warn, Run('Delphi-12-Prüfung', 1, 2, 0))]);
  Assert.IsFalse(mDecision.Block, 'warn: Build läuft');
  Assert.AreEqual(1, Integer(Length(mDecision.Warnings)));
  mDecision := TAtlasTaskGate.Decide([Entry(TAtlasTaskBeforeBuild.Block, Run('Delphi-12-Prüfung', 1, 2, 0)),
    Entry(TAtlasTaskBeforeBuild.Block, Run('Konsole', 0, 0, 4))]);
  Assert.IsTrue(mDecision.Block);
  Assert.AreEqual(1, Integer(Length(mDecision.Blocking)), 'Warnungen allein sperren nicht');
  Assert.AreEqual('Delphi-12-Prüfung', mDecision.Blocking[0].Name);
  mDecision := TAtlasTaskGate.Decide([Entry(TAtlasTaskBeforeBuild.Block, Run('Skript', 3, 0, 0))]);
  Assert.IsTrue(mDecision.Block, 'Exit-Code ohne Befunde sperrt');
  mDecision := TAtlasTaskGate.Decide([Entry(TAtlasTaskBeforeBuild.Block, Run('Gut', 0, 0, 0))]);
  Assert.IsFalse(mDecision.Block);
  Assert.AreEqual(0, Integer(Length(mDecision.Warnings)));
  mMissing := Run('Fehlt', -1, 0, 0);
  mMissing.Outcome := TAtlasTaskOutcome.ProgramMissing;
  mDecision := TAtlasTaskGate.Decide([Entry(TAtlasTaskBeforeBuild.Block, mMissing)]);
  Assert.IsTrue(mDecision.Block, 'fehlendes Programm sperrt bei block');
  mDecision := TAtlasTaskGate.Decide([Entry(TAtlasTaskBeforeBuild.Off, mMissing)]);
  Assert.IsFalse(mDecision.Block);
  Assert.AreEqual(0, Integer(Length(mDecision.Warnings)));
end;

procedure TAtlasTaskRunsTests.HistoryKeepsLastRunAndHiddenPerProject;
var
  mHistory: TAtlasTaskHistory;
  mValue: TAtlasTaskRun;
  mLast: TAtlasTaskLastRun;
begin
  mHistory := TAtlasTaskHistory.Create;
  try
    mValue := Run('Prüfung', 1, 2, 0);
    mValue.FinishedAt := EncodeDateTime(2026, 10, 23, 12, 3, 0, 0);
    mHistory.Remember('C:\P\App.dproj', mValue);
    mValue := Run('Prüfung', 0, 0, 0);
    mValue.FinishedAt := EncodeDateTime(2026, 10, 23, 12, 5, 0, 0);
    mHistory.Remember('c:/p/app.dproj', mValue);
    Assert.IsTrue(mHistory.LastRun('C:\P\APP.dproj', 'prüfung', mLast));
    Assert.AreEqual(0, mLast.ExitCode, 'der neue Lauf ersetzt den alten');
    Assert.AreEqual(1, Integer(Length(mHistory.LastRuns('C:\P\App.dproj'))));
    Assert.IsFalse(mHistory.LastRun('C:\Q\Other.dproj', 'Prüfung', mLast));
    mHistory.SetHidden('C:\P\App.dproj', 'Lint', True);
    mHistory.SetHidden('C:\P\App.dproj', 'lint', True);
    Assert.AreEqual(1, Integer(Length(mHistory.HiddenNames('C:\P\App.dproj'))));
    Assert.IsTrue(mHistory.IsHidden('C:\P\App.dproj', 'LINT'));
    Assert.IsFalse(mHistory.IsHidden('C:\Q\Other.dproj', 'Lint'));
    mHistory.SetHidden('C:\P\App.dproj', 'Lint', False);
    Assert.IsFalse(mHistory.IsHidden('C:\P\App.dproj', 'Lint'));
  finally
    mHistory.Free;
  end;
end;

procedure TAtlasTaskRunsTests.HistoryRoundTripAndBrokenText;
var
  mHistory, mLoaded: TAtlasTaskHistory;
  mValue: TAtlasTaskRun;
  mLast: TAtlasTaskLastRun;
begin
  mHistory := TAtlasTaskHistory.Create;
  mLoaded := TAtlasTaskHistory.Create;
  try
    mValue := Run('Delphi-12-Prüfung', 1, 2, 1);
    mValue.Outcome := TAtlasTaskOutcome.TimedOut;
    mValue.DurationMs := 1234;
    mValue.FinishedAt := EncodeDateTime(2026, 10, 23, 12, 3, 4, 0);
    mHistory.Remember('C:\P\App.dproj', mValue);
    mHistory.SetHidden('C:\P\App.dproj', 'Lint', True);
    Assert.IsTrue(mLoaded.FromJson(mHistory.ToJson));
    Assert.IsTrue(mLoaded.LastRun('C:\P\App.dproj', 'Delphi-12-Prüfung', mLast));
    Assert.IsTrue(mLast.Outcome = TAtlasTaskOutcome.TimedOut);
    Assert.AreEqual(1, mLast.ExitCode);
    Assert.AreEqual(2, mLast.Counts.Errors);
    Assert.AreEqual(1, mLast.Counts.Warnings);
    Assert.AreEqual(Int64(1234), mLast.DurationMs);
    Assert.AreEqual(EncodeDateTime(2026, 10, 23, 12, 3, 4, 0), mLast.FinishedAt, 1 / SecsPerDay);
    Assert.IsTrue(mLoaded.IsHidden('C:\P\App.dproj', 'Lint'));
    Assert.IsFalse(mLoaded.FromJson('{ kaputt'));
    Assert.AreEqual(0, Integer(Length(mLoaded.LastRuns('C:\P\App.dproj'))), 'ungültig: leer');
    Assert.IsTrue(mLoaded.FromJson('{"projects":{"c:\\p\\a.dproj":{"last":{"X":7}}}}'), 'falsche Einträge entfallen');
    Assert.AreEqual(0, Integer(Length(mLoaded.LastRuns('C:\P\A.dproj'))));
  finally
    mLoaded.Free;
    mHistory.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTaskRunsTests);

end.
