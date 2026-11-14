unit Atlas.Core.Debug.Profiler.Tests;

// Tests für den Profiler im Plugin (#2057) ohne IDE: Argumente und Antworten der drei Serverbefehle, Zeilen des
// Fensters „Atlas: Profil“ allein und im Vergleich, voriger Lauf und Titel eines Laufs.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasProfilerTests = class
  public
    [Test]
    procedure StartArgumentsNameTheProcess;
    [Test]
    procedure ReadsStartAnswer;
    [Test]
    procedure RejectsEmptyAnswers;
    [Test]
    procedure ReadsStatusAnswer;
    [Test]
    procedure ReadsStopAnswer;
    [Test]
    procedure FormatsPercentAndChange;
    [Test]
    procedure MethodRowsInOrderOfSelfShare;
    [Test]
    procedure OwnCodeOnlyFoldsLibraryFrames;
    [Test]
    procedure CompareRowsJumpToNewerRun;
    [Test]
    procedure PreviousRunIsTheNextOlderFile;
    [Test]
    procedure RunTitleFromFileName;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.Profile,
  Atlas.Core.Debug.Profiler;

function Invariant: TFormatSettings;
begin
  Result := TFormatSettings.Invariant;
end;

function Frame(const ARoutine: string; ALine: Integer): TAtlasProfileFrame;
begin
  Result := Default(TAtlasProfileFrame);
  Result.Routine := ARoutine;
  Result.UnitName := ARoutine.Substring(0, ARoutine.LastIndexOf('.'));
  Result.FileName := Result.UnitName + '.pas';
  Result.Line := ALine;
  Result.IsLibrary := TAtlasLibraryUnits.IsLibrary(Result.UnitName);
end;

procedure Add(ABuilder: TAtlasProfileBuilder; const AFrames: TArray<TAtlasProfileFrame>; ATimes: Integer);
var
  mIndex: Integer;
begin
  for mIndex := 1 to ATimes do
  begin
    ABuilder.AddSample(AFrames);
  end;
end;

/// <summary>Zehn Proben: App.Expensive AExpensive-mal (Zeile 48), System.JSON aus App.Load, Rest App.Main.
/// </summary>
function Run(AExpensive: Integer): TAtlasProfile;
var
  mBuilder: TAtlasProfileBuilder;
begin
  Result := Default(TAtlasProfile);
  mBuilder := TAtlasProfileBuilder.Create;
  try
    Add(mBuilder, TArray<TAtlasProfileFrame>.Create(Frame('App.Expensive', 48), Frame('App.Main', 90)), AExpensive);
    Add(mBuilder, TArray<TAtlasProfileFrame>.Create(Frame('System.JSON.Inner', 700), Frame('System.JSON.Parse', 300),
      Frame('App.Load', 20), Frame('App.Main', 91)), 3);
    Add(mBuilder, TArray<TAtlasProfileFrame>.Create(Frame('App.Main', 92)), 7 - AExpensive);
    mBuilder.FillProfile(Result);
  finally
    mBuilder.Free;
  end;
end;

function RowOf(const ARows: TArray<TAtlasProfileRow>; const ARoutine: string): TAtlasProfileRow;
var
  mRow: TAtlasProfileRow;
begin
  for mRow in ARows do
  begin
    if mRow.Routine = ARoutine then
    begin
      Result := mRow;
      Exit;
    end;
  end;
  Result := Default(TAtlasProfileRow);
end;

procedure TAtlasProfilerTests.StartArgumentsNameTheProcess;
var
  mTarget: TAtlasProfilerTarget;
  mJson: string;
begin
  mTarget := Default(TAtlasProfilerTarget);
  mTarget.ProcessId := 4711;
  mTarget.IntervalMs := 10;
  mTarget.ProgramName := 'C:\Projekt\App.exe';
  mTarget.Platform := 'Win64';
  mJson := TAtlasProfilerProtocol.StartArguments(mTarget);
  // Genau ein Argument-Objekt.
  Assert.IsTrue(mJson.StartsWith('[{') and mJson.EndsWith('}]'), mJson);
  Assert.IsTrue(mJson.Contains('"processId":4711'), mJson);
  Assert.IsTrue(mJson.Contains('"intervalMs":10'), mJson);
  Assert.IsTrue(mJson.Contains('"platform":"Win64"'), mJson);
  Assert.IsTrue(mJson.Contains('App.exe'), mJson);
  // Leere Angaben fehlen, damit der Server seine Vorgaben nimmt.
  Assert.IsFalse(mJson.Contains('"project"'), mJson);
end;

procedure TAtlasProfilerTests.ReadsStartAnswer;
var
  mAnswer: TAtlasProfilerStartAnswer;
begin
  Assert.IsTrue(TAtlasProfilerProtocol.ReadStart('{"started":true,"mapFile":"C:\\P\\App.map","routines":1234}',
    mAnswer));
  Assert.AreEqual('C:\P\App.map', mAnswer.MapFile);
  Assert.AreEqual(1234, mAnswer.Routines);
  Assert.IsFalse(TAtlasProfilerProtocol.ReadStart('{"started":false}', mAnswer), 'nicht gestartet');
end;

procedure TAtlasProfilerTests.RejectsEmptyAnswers;
var
  mStart: TAtlasProfilerStartAnswer;
  mStatus: TAtlasProfilerStatusAnswer;
  mStop: TAtlasProfilerStopAnswer;
begin
  // '' meldet Base bei Fehler (etwa „nur unter Windows“), Abbruch oder Zeitlimit.
  Assert.IsFalse(TAtlasProfilerProtocol.ReadStart('', mStart));
  Assert.IsFalse(TAtlasProfilerProtocol.ReadStatus('[1]', mStatus));
  Assert.IsFalse(TAtlasProfilerProtocol.ReadStop('kaputt', mStop));
  Assert.IsFalse(TAtlasProfilerProtocol.ReadStop('{"samples":3}', mStop), 'ohne Datei');
end;

procedure TAtlasProfilerTests.ReadsStatusAnswer;
var
  mAnswer: TAtlasProfilerStatusAnswer;
begin
  Assert.IsTrue(TAtlasProfilerProtocol.ReadStatus(
    '{"running":false,"processId":4711,"elapsedMs":12500,"samples":980,"lastFile":"profile-20261113-140522.json"}',
    mAnswer));
  Assert.IsFalse(mAnswer.Running);
  Assert.AreEqual(Cardinal(4711), mAnswer.ProcessId);
  Assert.AreEqual(Int64(12500), mAnswer.ElapsedMs);
  Assert.AreEqual(980, mAnswer.Samples);
  Assert.AreEqual('profile-20261113-140522.json', mAnswer.LastFile);
end;

procedure TAtlasProfilerTests.ReadsStopAnswer;
var
  mAnswer: TAtlasProfilerStopAnswer;
begin
  Assert.IsTrue(TAtlasProfilerProtocol.ReadStop('{"file":"profile-20261113-140522.json",' +
    '"path":"C:\\Cache\\profiles\\profile-20261113-140522.json","samples":980,"durationMs":12500}', mAnswer));
  Assert.AreEqual('profile-20261113-140522.json', mAnswer.FileName);
  Assert.AreEqual('C:\Cache\profiles\profile-20261113-140522.json', mAnswer.Path);
  Assert.AreEqual(980, mAnswer.Samples);
  Assert.AreEqual(Int64(12500), mAnswer.DurationMs);
end;

procedure TAtlasProfilerTests.FormatsPercentAndChange;
begin
  Assert.AreEqual('12.3 %', TAtlasProfileTable.PercentText(12.34, Invariant));
  Assert.AreEqual('+1.5 %', TAtlasProfileTable.ChangeText(1.5, Invariant));
  Assert.AreEqual('-0.4 %', TAtlasProfileTable.ChangeText(-0.4, Invariant));
  Assert.AreEqual('0.0 %', TAtlasProfileTable.ChangeText(-0.01, Invariant), 'gerundet ohne Vorzeichen');
end;

procedure TAtlasProfilerTests.MethodRowsInOrderOfSelfShare;
var
  mRows: TArray<TAtlasProfileRow>;
begin
  mRows := TAtlasProfileTable.MethodRows(Run(6), False, Invariant);
  Assert.AreEqual('App.Expensive', mRows[0].Routine);
  Assert.AreEqual(Integer(5), Integer(Length(mRows[0].Cells)));
  Assert.AreEqual('App', mRows[0].Cells[1]);
  Assert.AreEqual('60.0 %', mRows[0].Cells[2], 'eigen');
  Assert.AreEqual('60.0 %', mRows[0].Cells[3], 'gesamt');
  Assert.AreEqual('48', mRows[0].Cells[4], 'heißeste Zeile');
  Assert.AreEqual('App.pas', mRows[0].FileName);
  Assert.AreEqual(48, mRows[0].Line);
  Assert.AreEqual('100.0 %', RowOf(mRows, 'App.Main').Cells[3]);
  Assert.IsTrue(RowOf(mRows, 'System.JSON.Inner').IsLibrary);
end;

procedure TAtlasProfilerTests.OwnCodeOnlyFoldsLibraryFrames;
var
  mRows: TArray<TAtlasProfileRow>;
begin
  // System.JSON.Inner geht in System.JSON.Parse auf, die Routine, die der eigene Code aufgerufen hat.
  mRows := TAtlasProfileTable.MethodRows(Run(6), True, Invariant);
  Assert.AreEqual('', RowOf(mRows, 'System.JSON.Inner').Routine);
  Assert.AreEqual('30.0 %', RowOf(mRows, 'System.JSON.Parse').Cells[2]);
end;

procedure TAtlasProfilerTests.CompareRowsJumpToNewerRun;
var
  mRows: TArray<TAtlasProfileRow>;
  mRow: TAtlasProfileRow;
begin
  mRows := TAtlasProfileTable.CompareRows(Run(6), Run(2), False, Invariant);
  mRow := RowOf(mRows, 'App.Expensive');
  Assert.AreEqual(Integer(4), Integer(Length(mRow.Cells)));
  Assert.AreEqual('60.0 %', mRow.Cells[1], 'vorher');
  Assert.AreEqual('20.0 %', mRow.Cells[2], 'nachher');
  Assert.AreEqual('-40.0 %', mRow.Cells[3], 'Änderung');
  Assert.AreEqual('App.pas', mRow.FileName);
  Assert.AreEqual(48, mRow.Line);
  // Größte Änderung zuerst.
  Assert.AreEqual('App.Expensive', mRows[0].Routine);
end;

procedure TAtlasProfilerTests.PreviousRunIsTheNextOlderFile;
var
  mFiles: TArray<string>;
begin
  mFiles := TArray<string>.Create('C:\P\profile-20261113-100000.json', 'C:\P\profile-20261113-120000.json',
    'C:\P\notiz.json', 'C:\P\profile-20261112-235959.json');
  Assert.AreEqual('C:\P\profile-20261113-100000.json',
    TAtlasProfileTable.PreviousRun(mFiles, 'profile-20261113-120000.json'));
  Assert.AreEqual('C:\P\profile-20261112-235959.json',
    TAtlasProfileTable.PreviousRun(mFiles, 'C:\P\profile-20261113-100000.json'));
  Assert.AreEqual('', TAtlasProfileTable.PreviousRun(mFiles, 'profile-20261112-235959.json'), 'ältester');
  Assert.AreEqual('', TAtlasProfileTable.PreviousRun(mFiles, 'profile-20200101-000000.json'), 'unbekannt');
end;

procedure TAtlasProfilerTests.RunTitleFromFileName;
begin
  Assert.AreEqual('13.11.2026 14:05:22', TAtlasProfileTable.RunTitle('C:\P\profile-20261113-140522.json'));
  Assert.AreEqual('anders.json', TAtlasProfileTable.RunTitle('anders.json'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasProfilerTests);

end.
