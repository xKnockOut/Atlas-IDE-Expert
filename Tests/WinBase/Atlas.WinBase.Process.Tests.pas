unit Atlas.WinBase.Process.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.WinBase.Process;

type
  [TestFixture]
  TAtlasProcessLauncherTests = class
  public
    [Test]
    procedure InheritListSkipsEmptyAndDuplicateHandles;
    [Test]
    procedure LaunchWithoutHandlesReturnsExitCode;
    [Test]
    procedure ReadsOutputThroughPipe;
    [Test]
    procedure ChildHandlesAreNotInheritableAfterLaunch;
    [Test]
    procedure MissingProgramFailsWithLastError;
    /// <summary>Code-Review R-101: Ein kurzer Prozess sieht sein Dateiende sofort, auch wenn ein zweiter Thread
    /// gleichzeitig lange Prozesse mit eigenen Pipes startet. Ohne Handle-Liste erbte der lange Prozess gelegentlich
    /// das Schreib-Ende des kurzen, und dessen Leser wartete bis zum Ende des langen.</summary>
    [Test]
    procedure ShortProcessEndsWhileLongProcessesStart;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Diagnostics;

const
  /// <summary>Großzügig für langsame Rechner; der lange Prozess läuft rund zwei Sekunden.</summary>
  cMaxEofMs = 1000;
  cShortRuns = 25;

function Shell: string;
begin
  Result := GetEnvironmentVariable('ComSpec');
  if Result = '' then
  begin
    Result := 'cmd.exe';
  end;
end;

/// <summary>Startet ACommand (über cmd /c) mit einer Pipe für stdout und stderr, liest bis zum Dateiende und liefert
/// die Ausgabe; AEofMs: Millisekunden vom Start bis zum Dateiende.</summary>
function RunToEof(const ACommand: string; out AEofMs: Int64): string;
var
  mRead, mWrite: THandle;
  mInfo: TProcessInformation;
  mBuffer: array[0..1023] of AnsiChar;
  mCount: DWORD;
  mOutput, mChunk: AnsiString;
  mWatch: TStopwatch;
begin
  if not CreatePipe(mRead, mWrite, nil, 0) then
  begin
    RaiseLastOSError;
  end;
  try
    mWatch := TStopwatch.StartNew;
    if not TAtlasProcessLauncher.Launch(TAtlasProcessLaunch.Create(Shell, '"' + Shell + '" /d /c ' + ACommand, '', 0,
      mWrite, mWrite), mInfo) then
    begin
      RaiseLastOSError;
    end;
    CloseHandle(mWrite);
    mWrite := 0;
    mOutput := '';
    while ReadFile(mRead, mBuffer[0], SizeOf(mBuffer), mCount, nil) and (mCount > 0) do
    begin
      SetString(mChunk, PAnsiChar(@mBuffer[0]), mCount);
      mOutput := mOutput + mChunk;
    end;
    AEofMs := mWatch.ElapsedMilliseconds;
    WaitForSingleObject(mInfo.hProcess, 10000);
    CloseHandle(mInfo.hThread);
    CloseHandle(mInfo.hProcess);
    Result := Trim(string(mOutput));
  finally
    CloseHandle(mRead);
    if mWrite <> 0 then
    begin
      CloseHandle(mWrite);
    end;
  end;
end;

type
  /// <summary>Startet bis zum Ende immer wieder einen Prozess, der rund zwei Sekunden läuft.</summary>
  TLongStarter = class(TThread)
  protected
    procedure Execute; override;
  end;

procedure TLongStarter.Execute;
var
  mEofMs: Int64;
begin
  while not Terminated do
  begin
    RunToEof('ping -n 3 127.0.0.1', mEofMs);
  end;
end;

{ TAtlasProcessLauncherTests }

procedure TAtlasProcessLauncherTests.InheritListSkipsEmptyAndDuplicateHandles;
var
  mLaunch: TAtlasProcessLaunch;
  mList: TArray<THandle>;
begin
  mLaunch := TAtlasProcessLaunch.Create('', 'x', '', 0, 0, 0);
  Assert.AreEqual(0, Integer(Length(TAtlasProcessLauncher.InheritList(mLaunch))));
  mLaunch := TAtlasProcessLaunch.Create('', 'x', '', INVALID_HANDLE_VALUE, 12, 12);
  mList := TAtlasProcessLauncher.InheritList(mLaunch);
  Assert.AreEqual(1, Integer(Length(mList)));
  Assert.AreEqual<THandle>(12, mList[0]);
  mLaunch := TAtlasProcessLaunch.Create('', 'x', '', 4, 8, 12);
  mList := TAtlasProcessLauncher.InheritList(mLaunch);
  Assert.AreEqual(3, Integer(Length(mList)));
  Assert.IsTrue((mList[0] = 4) and (mList[1] = 8) and (mList[2] = 12));
end;

procedure TAtlasProcessLauncherTests.LaunchWithoutHandlesReturnsExitCode;
var
  mInfo: TProcessInformation;
  mExitCode: DWORD;
begin
  Assert.IsTrue(TAtlasProcessLauncher.Launch(TAtlasProcessLaunch.Create(Shell, '"' + Shell + '" /d /c exit 7', '', 0,
    0, 0), mInfo));
  try
    Assert.AreEqual(Cardinal(WAIT_OBJECT_0), Cardinal(WaitForSingleObject(mInfo.hProcess, 10000)));
    Assert.IsTrue(GetExitCodeProcess(mInfo.hProcess, mExitCode));
    Assert.AreEqual(7, Integer(mExitCode));
  finally
    CloseHandle(mInfo.hThread);
    CloseHandle(mInfo.hProcess);
  end;
end;

procedure TAtlasProcessLauncherTests.ReadsOutputThroughPipe;
var
  mEofMs: Int64;
begin
  Assert.AreEqual('Atlas', RunToEof('echo Atlas', mEofMs));
end;

procedure TAtlasProcessLauncherTests.ChildHandlesAreNotInheritableAfterLaunch;
var
  mRead, mWrite: THandle;
  mInfo: TProcessInformation;
  mFlags: DWORD;
begin
  Assert.IsTrue(CreatePipe(mRead, mWrite, nil, 0));
  try
    Assert.IsTrue(TAtlasProcessLauncher.Launch(TAtlasProcessLaunch.Create(Shell, '"' + Shell + '" /d /c exit', '', 0,
      mWrite, mWrite), mInfo));
    WaitForSingleObject(mInfo.hProcess, 10000);
    CloseHandle(mInfo.hThread);
    CloseHandle(mInfo.hProcess);
    Assert.IsTrue(GetHandleInformation(mWrite, mFlags));
    Assert.AreEqual(0, Integer(mFlags and HANDLE_FLAG_INHERIT));
  finally
    CloseHandle(mRead);
    CloseHandle(mWrite);
  end;
end;

procedure TAtlasProcessLauncherTests.MissingProgramFailsWithLastError;
var
  mInfo: TProcessInformation;
  mRead, mWrite: THandle;
  mStarted: Boolean;
  mError: DWORD;
begin
  Assert.IsTrue(CreatePipe(mRead, mWrite, nil, 0));
  try
    mStarted := TAtlasProcessLauncher.Launch(TAtlasProcessLaunch.Create('C:\gibt-es-nicht\atlas.exe', 'atlas.exe',
      '', 0, mWrite, mWrite), mInfo);
    mError := GetLastError;
    Assert.IsFalse(mStarted);
    Assert.AreNotEqual<DWORD>(0, mError);
    Assert.AreEqual<THandle>(0, mInfo.hProcess);
  finally
    CloseHandle(mRead);
    CloseHandle(mWrite);
  end;
end;

procedure TAtlasProcessLauncherTests.ShortProcessEndsWhileLongProcessesStart;
var
  mLong: TLongStarter;
  mIndex: Integer;
  mEofMs, mWorstMs: Int64;
begin
  mWorstMs := 0;
  mLong := TLongStarter.Create(False);
  try
    Sleep(100);
    for mIndex := 1 to cShortRuns do
    begin
      RunToEof('exit', mEofMs);
      if mEofMs > mWorstMs then
      begin
        mWorstMs := mEofMs;
      end;
    end;
  finally
    mLong.Terminate;
    mLong.WaitFor;
    mLong.Free;
  end;
  Assert.IsTrue(mWorstMs < cMaxEofMs, Format('Dateiende erst nach %d ms', [mWorstMs]));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasProcessLauncherTests);

end.
