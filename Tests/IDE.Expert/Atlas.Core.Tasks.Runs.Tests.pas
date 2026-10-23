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
  Index: Integer;
  Finding: TAtlasTaskFinding;
begin
  Result := Default(TAtlasTaskRun);
  Result.Name := AName;
  Result.Outcome := TAtlasTaskOutcome.Finished;
  Result.ExitCode := AExitCode;
  for Index := 1 to AErrors do
  begin
    Finding := Default(TAtlasTaskFinding);
    Finding.Severity := TAtlasTaskSeverity.Error;
    Result.Findings := Result.Findings + [Finding];
  end;
  for Index := 1 to AWarnings do
  begin
    Finding := Default(TAtlasTaskFinding);
    Finding.Severity := TAtlasTaskSeverity.Warning;
    Result.Findings := Result.Findings + [Finding];
  end;
end;

function Entry(AMode: TAtlasTaskBeforeBuild; const ARun: TAtlasTaskRun): TAtlasTaskGateEntry;
begin
  Result.Mode := AMode;
  Result.Run := ARun;
end;

procedure TAtlasTaskRunsTests.LinesAreSplitAcrossChunks;
var
  Lines: TAtlasTaskLines;
  Got: TArray<string>;
  Data: TBytes;
begin
  Lines := TAtlasTaskLines.Create(0);
  try
    Data := Bytes('eins'#13#10'zw');
    Got := Lines.Feed(Data, Length(Data));
    Assert.AreEqual('eins', string.Join('|', Got), 'CR fällt weg, „zw“ wartet');
    Data := Bytes('ei'#10#10#27'[31mrot'#27'[0m'#10'Ende');
    Got := Lines.Feed(Data, Length(Data));
    Assert.AreEqual('zwei||rot', string.Join('|', Got), 'leere Zeile bleibt, Farbfolgen fallen weg');
    // Nur ein Teil des Puffers gilt.
    Data := Bytes('!xyz');
    Got := Lines.Feed(Data, 1);
    Assert.AreEqual(0, Integer(Length(Got)));
    Assert.AreEqual('Ende!', string.Join('|', Lines.Flush));
    Assert.AreEqual(0, Integer(Length(Lines.Flush)), 'Rest nur einmal');
    // UTF-8 über die Grenze zweier Stücke: ü = C3 BC.
    Data := TBytes.Create($50, $72, $C3);
    Lines.Feed(Data, Length(Data));
    Data := TBytes.Create($BC, $66, 10);
    Got := Lines.Feed(Data, Length(Data));
    Assert.AreEqual('Prüf', string.Join('|', Got));
    // Fenstertitel (OSC) und einzelne Steuerzeichen am Ende.
    Assert.AreEqual('ab', TAtlasTaskLines.Clean('a'#27']0;Titel'#7'b'));
    Assert.AreEqual('ab', TAtlasTaskLines.Clean('a'#27']0;T'#27'\b'#27));
    Assert.AreEqual('Fehler', TAtlasTaskLines.Clean(#27'[1;31;40mFehler'#27'[K'#13));
  finally
    Lines.Free;
  end;
end;

procedure TAtlasTaskRunsTests.NonUtf8LinesUseTheCodePage;
var
  Lines: TAtlasTaskLines;
  Data: TBytes;
begin
  Assert.IsTrue(TAtlasTaskLines.IsUtf8(Bytes('Prüfung ✓'), 0, Length(Bytes('Prüfung ✓'))));
  Data := TBytes.Create($50, $72, $FC, $66);
  Assert.IsFalse(TAtlasTaskLines.IsUtf8(Data, 0, Length(Data)), 'ü als ein Byte');
  Data := TBytes.Create($C0, $80);
  Assert.IsFalse(TAtlasTaskLines.IsUtf8(Data, 0, Length(Data)), 'überlange Form');
  Data := TBytes.Create($E2, $9C);
  Assert.IsFalse(TAtlasTaskLines.IsUtf8(Data, 0, Length(Data)), 'abgeschnitten');
  // 1252: FC = ü.
  Lines := TAtlasTaskLines.Create(1252);
  try
    Data := TBytes.Create($50, $72, $FC, $66, 10);
    Assert.AreEqual('Prüf', string.Join('|', Lines.Feed(Data, Length(Data))));
  finally
    Lines.Free;
  end;
  Assert.AreEqual('ab', TAtlasTaskLines.Clean(#27'[1;32ma'#27'[0mb'#13));
end;

procedure TAtlasTaskRunsTests.CountsAndPassed;
var
  Value: TAtlasTaskRun;
  Last: TAtlasTaskLastRun;
begin
  Value := Run('A', 0, 2, 1);
  Assert.AreEqual(2, Value.Counts.Errors);
  Assert.AreEqual(1, Value.Counts.Warnings);
  Assert.AreEqual(3, Value.Counts.Total);
  Assert.IsTrue(Value.ExitedCleanly);
  Assert.IsFalse(Value.Passed, 'Fehler-Befunde');
  Assert.IsTrue(Run('A', 0, 0, 3).Passed, 'nur Warnungen');
  Assert.IsFalse(Run('A', 1, 0, 0).Passed, 'Exit-Code 1');
  Value := Run('A', 0, 0, 0);
  Value.Outcome := TAtlasTaskOutcome.TimedOut;
  Assert.IsFalse(Value.Passed);
  Last := TAtlasTaskLastRun.From(Run('B', 0, 0, 2));
  Assert.AreEqual('B', Last.Name);
  Assert.AreEqual(2, Last.Counts.Warnings);
  Assert.IsTrue(Last.Passed);
end;

procedure TAtlasTaskRunsTests.WarnNeverBlocksBlockStopsOnErrorsOrExitCode;
var
  Decision: TAtlasTaskGateDecision;
  Missing: TAtlasTaskRun;
begin
  Decision := TAtlasTaskGate.Decide([Entry(TAtlasTaskBeforeBuild.Warn, Run('Delphi-12-Prüfung', 1, 2, 0))]);
  Assert.IsFalse(Decision.Block, 'warn: Build läuft');
  Assert.AreEqual(1, Integer(Length(Decision.Warnings)));
  Decision := TAtlasTaskGate.Decide([Entry(TAtlasTaskBeforeBuild.Block, Run('Delphi-12-Prüfung', 1, 2, 0)),
    Entry(TAtlasTaskBeforeBuild.Block, Run('Konsole', 0, 0, 4))]);
  Assert.IsTrue(Decision.Block);
  Assert.AreEqual(1, Integer(Length(Decision.Blocking)), 'Warnungen allein sperren nicht');
  Assert.AreEqual('Delphi-12-Prüfung', Decision.Blocking[0].Name);
  Decision := TAtlasTaskGate.Decide([Entry(TAtlasTaskBeforeBuild.Block, Run('Skript', 3, 0, 0))]);
  Assert.IsTrue(Decision.Block, 'Exit-Code ohne Befunde sperrt');
  Decision := TAtlasTaskGate.Decide([Entry(TAtlasTaskBeforeBuild.Block, Run('Gut', 0, 0, 0))]);
  Assert.IsFalse(Decision.Block);
  Assert.AreEqual(0, Integer(Length(Decision.Warnings)));
  Missing := Run('Fehlt', -1, 0, 0);
  Missing.Outcome := TAtlasTaskOutcome.ProgramMissing;
  Decision := TAtlasTaskGate.Decide([Entry(TAtlasTaskBeforeBuild.Block, Missing)]);
  Assert.IsTrue(Decision.Block, 'fehlendes Programm sperrt bei block');
  Decision := TAtlasTaskGate.Decide([Entry(TAtlasTaskBeforeBuild.Off, Missing)]);
  Assert.IsFalse(Decision.Block);
  Assert.AreEqual(0, Integer(Length(Decision.Warnings)));
end;

procedure TAtlasTaskRunsTests.HistoryKeepsLastRunAndHiddenPerProject;
var
  History: TAtlasTaskHistory;
  Value: TAtlasTaskRun;
  Last: TAtlasTaskLastRun;
begin
  History := TAtlasTaskHistory.Create;
  try
    Value := Run('Prüfung', 1, 2, 0);
    Value.FinishedAt := EncodeDateTime(2026, 10, 23, 12, 3, 0, 0);
    History.Remember('C:\P\App.dproj', Value);
    Value := Run('Prüfung', 0, 0, 0);
    Value.FinishedAt := EncodeDateTime(2026, 10, 23, 12, 5, 0, 0);
    History.Remember('c:/p/app.dproj', Value);
    Assert.IsTrue(History.LastRun('C:\P\APP.dproj', 'prüfung', Last));
    Assert.AreEqual(0, Last.ExitCode, 'der neue Lauf ersetzt den alten');
    Assert.AreEqual(1, Integer(Length(History.LastRuns('C:\P\App.dproj'))));
    Assert.IsFalse(History.LastRun('C:\Q\Other.dproj', 'Prüfung', Last));
    History.SetHidden('C:\P\App.dproj', 'Lint', True);
    History.SetHidden('C:\P\App.dproj', 'lint', True);
    Assert.AreEqual(1, Integer(Length(History.HiddenNames('C:\P\App.dproj'))));
    Assert.IsTrue(History.IsHidden('C:\P\App.dproj', 'LINT'));
    Assert.IsFalse(History.IsHidden('C:\Q\Other.dproj', 'Lint'));
    History.SetHidden('C:\P\App.dproj', 'Lint', False);
    Assert.IsFalse(History.IsHidden('C:\P\App.dproj', 'Lint'));
  finally
    History.Free;
  end;
end;

procedure TAtlasTaskRunsTests.HistoryRoundTripAndBrokenText;
var
  History, Loaded: TAtlasTaskHistory;
  Value: TAtlasTaskRun;
  Last: TAtlasTaskLastRun;
begin
  History := TAtlasTaskHistory.Create;
  Loaded := TAtlasTaskHistory.Create;
  try
    Value := Run('Delphi-12-Prüfung', 1, 2, 1);
    Value.Outcome := TAtlasTaskOutcome.TimedOut;
    Value.DurationMs := 1234;
    Value.FinishedAt := EncodeDateTime(2026, 10, 23, 12, 3, 4, 0);
    History.Remember('C:\P\App.dproj', Value);
    History.SetHidden('C:\P\App.dproj', 'Lint', True);
    Assert.IsTrue(Loaded.FromJson(History.ToJson));
    Assert.IsTrue(Loaded.LastRun('C:\P\App.dproj', 'Delphi-12-Prüfung', Last));
    Assert.IsTrue(Last.Outcome = TAtlasTaskOutcome.TimedOut);
    Assert.AreEqual(1, Last.ExitCode);
    Assert.AreEqual(2, Last.Counts.Errors);
    Assert.AreEqual(1, Last.Counts.Warnings);
    Assert.AreEqual(Int64(1234), Last.DurationMs);
    Assert.AreEqual(EncodeDateTime(2026, 10, 23, 12, 3, 4, 0), Last.FinishedAt, 1 / SecsPerDay);
    Assert.IsTrue(Loaded.IsHidden('C:\P\App.dproj', 'Lint'));
    Assert.IsFalse(Loaded.FromJson('{ kaputt'));
    Assert.AreEqual(0, Integer(Length(Loaded.LastRuns('C:\P\App.dproj'))), 'ungültig: leer');
    Assert.IsTrue(Loaded.FromJson('{"projects":{"c:\\p\\a.dproj":{"last":{"X":7}}}}'), 'falsche Einträge entfallen');
    Assert.AreEqual(0, Integer(Length(Loaded.LastRuns('C:\P\A.dproj'))));
  finally
    Loaded.Free;
    History.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTaskRunsTests);

end.
