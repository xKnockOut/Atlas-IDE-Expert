unit Atlas.Core.Debug.LeakCapture.Tests;

// Tests für den Leckbericht am Ende einer Debug-Sitzung (#1875): Meldungsfenster
// unter den Fenstertexten, Logdatei neben der EXE und ihr Alter, Wahl zwischen
// beiden, Vergleich mit dem letzten Lauf, „bekannt“ und der Stand als Text.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasLeakCaptureTests = class
  public
    [Test]
    procedure LogFileNextToExe;
    [Test]
    procedure MessageBoxAmongWindowTexts;
    [Test]
    procedure LogFileOnlyWhenWrittenAfterStart;
    [Test]
    procedure ChoosePrefersStacks;
    [Test]
    procedure CompareMarksNewAndKnown;
    [Test]
    procedure HistoryRoundTripAndKnown;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.LeakReport,
  Atlas.Core.Debug.LeakCapture;

const
  cNl = #13#10;
  cBox = 'An unexpected memory leak has occurred. The unexpected small block leaks are:' + cNl + cNl +
    '1 - 12 bytes: TKunde x 3, UnicodeString x 5' + cNl +
    '13 - 20 bytes: TStringList x 2' + cNl;
  cSeparator = '--------------------------------2026/11/13 10:00:00--------------------------------';
  cLogWithStack = cSeparator + cNl +
    'A memory block has been leaked. The size is: 20' + cNl + cNl +
    'This block was allocated by thread 0x1A2C, and the stack trace (return addresses) at the time was:' + cNl +
    '4068F6 [System.pas][System][@GetMem$qqri][4843]' + cNl +
    '4C2B10 [Kunden.pas][Kunden][TKundenListe.Lade][42]' + cNl + cNl +
    'The block is currently used for an object of class: TStringList' + cNl + cNl +
    'The allocation number is: 1234' + cNl;

procedure TAtlasLeakCaptureTests.LogFileNextToExe;
begin
  Assert.AreEqual('C:\P\Win32\Debug\App_MemoryManager_EventLog.txt',
    TAtlasLeakCaptures.LogFileOf('C:\P\Win32\Debug\App.exe'));
end;

procedure TAtlasLeakCaptureTests.MessageBoxAmongWindowTexts;
var
  mCapture: TAtlasLeakCapture;
begin
  Assert.IsTrue(TAtlasLeakCaptures.FromWindowTexts(TArray<string>.Create('OK', 'Error', cBox), mCapture));
  Assert.IsTrue(mCapture.Source = TAtlasLeakSource.MessageBox);
  Assert.AreEqual(3, mCapture.Report.CountOf('TKunde'));
  Assert.IsFalse(TAtlasLeakCaptures.FromWindowTexts(TArray<string>.Create('OK'), mCapture));
  Assert.IsTrue(mCapture.IsEmpty);
end;

procedure TAtlasLeakCaptureTests.LogFileOnlyWhenWrittenAfterStart;
var
  mCapture: TAtlasLeakCapture;
  mStart: TDateTime;
begin
  mStart := EncodeDate(2026, 11, 13);
  Assert.IsFalse(TAtlasLeakCaptures.FromLogFile('a.txt', cLogWithStack, mStart - 1, mStart, mCapture), 'alt');
  Assert.IsTrue(TAtlasLeakCaptures.FromLogFile('a.txt', cLogWithStack, mStart + 1, mStart, mCapture));
  Assert.IsTrue(mCapture.Source = TAtlasLeakSource.LogFile);
  Assert.AreEqual('a.txt', mCapture.FileName);
  Assert.IsFalse(TAtlasLeakCaptures.FromLogFile('a.txt', 'nichts', mStart + 1, mStart, mCapture), 'ohne Bericht');
end;

procedure TAtlasLeakCaptureTests.ChoosePrefersStacks;
var
  mBox, mLog, mNone: TAtlasLeakCapture;
  mStart: TDateTime;
begin
  mStart := EncodeDate(2026, 11, 13);
  TAtlasLeakCaptures.FromWindowTexts(TArray<string>.Create(cBox), mBox);
  TAtlasLeakCaptures.FromLogFile('a.txt', cLogWithStack, mStart + 1, mStart, mLog);
  mNone := Default(TAtlasLeakCapture);
  Assert.IsTrue(TAtlasLeakCaptures.Choose(mBox, mLog).Source = TAtlasLeakSource.LogFile, 'mit Stapeln');
  Assert.IsTrue(TAtlasLeakCaptures.Choose(mBox, mNone).Source = TAtlasLeakSource.MessageBox);
  Assert.IsTrue(TAtlasLeakCaptures.Choose(mNone, mLog).Source = TAtlasLeakSource.LogFile);
  Assert.IsTrue(TAtlasLeakCaptures.Choose(mNone, mNone).IsEmpty);
end;

procedure TAtlasLeakCaptureTests.CompareMarksNewAndKnown;
var
  mReport: TLeakReport;
  mHistory: TAtlasLeakHistory;
  mEntries: TArray<TAtlasLeakEntry>;
  mEntry: TAtlasLeakEntry;
begin
  mReport := TLeakReports.Parse(cBox);
  mHistory := TAtlasLeakCaptures.HistoryFromText('count:TKunde=3' + cNl + 'count:TStringList=1' + cNl +
    'known:UnicodeString');
  mEntries := TAtlasLeakCaptures.Compare(mReport, mHistory);
  Assert.AreEqual(3, Integer(Length(mEntries)));
  for mEntry in mEntries do
  begin
    if mEntry.Name = 'TKunde' then
    begin
      Assert.IsFalse(mEntry.IsNew, 'gleich viele');
      Assert.AreEqual(3, mEntry.PreviousCount);
    end
    else if mEntry.Name = 'TStringList' then
    begin
      Assert.IsTrue(mEntry.IsNew, 'mehr geworden');
    end
    else
    begin
      Assert.AreEqual('UnicodeString', mEntry.Name);
      Assert.IsTrue(mEntry.IsNew);
      Assert.IsTrue(mEntry.Known);
    end;
  end;
end;

procedure TAtlasLeakCaptureTests.HistoryRoundTripAndKnown;
var
  mHistory: TAtlasLeakHistory;
begin
  mHistory := TAtlasLeakCaptures.NextHistory(TLeakReports.Parse(cBox), Default(TAtlasLeakHistory));
  mHistory := TAtlasLeakCaptures.MarkKnown(mHistory, 'TKunde', True);
  mHistory := TAtlasLeakCaptures.MarkKnown(mHistory, 'TKunde', True);
  mHistory := TAtlasLeakCaptures.HistoryFromText(TAtlasLeakCaptures.HistoryToText(mHistory) + cNl + 'murks');
  Assert.AreEqual(3, mHistory.CountOf('tkunde'));
  Assert.AreEqual(2, mHistory.CountOf('TStringList'));
  Assert.AreEqual(0, mHistory.CountOf('TAndere'));
  Assert.AreEqual(1, Integer(Length(mHistory.Known)));
  Assert.IsTrue(mHistory.IsKnown('TKunde'));
  mHistory := TAtlasLeakCaptures.NextHistory(TLeakReports.Parse(cBox), mHistory);
  Assert.IsTrue(mHistory.IsKnown('TKunde'), 'bekannt bleibt');
  mHistory := TAtlasLeakCaptures.MarkKnown(mHistory, 'TKunde', False);
  Assert.IsFalse(mHistory.IsKnown('TKunde'));
  Assert.AreEqual('leaks-debug-win64.txt', TAtlasLeakCaptures.HistoryFileName('Debug', 'Win64'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasLeakCaptureTests);

end.
