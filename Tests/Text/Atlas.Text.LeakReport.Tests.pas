unit Atlas.Text.LeakReport.Tests;

// Tests für das Lesen von Leckberichten (#1875, #74): Meldungsfenster der RTL,
// Logdatei von FastMM4 und FastMM5 mit und ohne Aufrufstapel, mehrere Läufe in
// einer Datei, Fehlermeldungen von FastMM, Erzeugungsstelle und Gruppen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLeakReportTests = class
  public
    [Test]
    procedure ReadsRtlDialog;
    [Test]
    procedure ReadsLargeBlocksOnly;
    [Test]
    procedure ReadsFastMM4LogWithStacks;
    [Test]
    procedure ReadsFastMM5Summary;
    [Test]
    procedure KeepsOnlyLastRun;
    [Test]
    procedure IgnoresFastMMErrors;
    [Test]
    procedure CountsBlocksWithoutSummary;
    [Test]
    procedure GroupsSameStacks;
    [Test]
    procedure ParsesFrames;
    [Test]
    procedure SiteSkipsRtlAndFastMM;
    [Test]
    procedure KindsOfNames;
    [Test]
    procedure OtherTextIsEmpty;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.LeakReport;

const
  cNl = #13#10;

  // Meldungsfenster von ReportMemoryLeaksOnShutdown (Text über GetWindowText).
  cRtlDialog =
    'An unexpected memory leak has occurred. The unexpected small block leaks are:' + cNl + cNl +
    '1 - 12 bytes: TKunde x 3, UnicodeString x 5' + cNl +
    '13 - 20 bytes: TStringList x 2, Unknown x 1, UnicodeString x 1' + cNl + cNl +
    'The sizes of unexpected leaked medium and large blocks are: 40100, 80000' + cNl;

  cSeparator = '--------------------------------2026/11/13 10:00:00--------------------------------';

  // Ein Eintrag von FastMM4 im FullDebugMode (FastMM_FullDebugMode.dll mit Debug-Informationen).
  cFastMM4Block =
    cSeparator + cNl +
    'A memory block has been leaked. The size is: 20' + cNl + cNl +
    'This block was allocated by thread 0x1A2C, and the stack trace (return addresses) at the time was:' + cNl +
    '4068F6 [System.pas][System][@GetMem$qqri][4843]' + cNl +
    '40A3C3 [System.pas][System][TObject.NewInstance][17926]' + cNl +
    '40B1D2 [System.pas][System][@ClassCreate$qqrpvzc][19162]' + cNl +
    '4C2B10 [Kunden.pas][Kunden][TKundenListe.Lade][42]' + cNl +
    '4C3F00 [Main.pas][Main][TMainForm.FormCreate][17]' + cNl + cNl +
    'The block is currently used for an object of class: TStringList' + cNl + cNl +
    'The allocation number is: 1234' + cNl + cNl +
    'Current memory dump of 256 bytes starting at pointer address 7EF8A4B0:' + cNl +
    'B8 4F 40 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00' + cNl +
    '.  O  @  .  .  .  .  .  .  .  .  .  .  .  .  .  .  .  .  .  .  .  .  .' + cNl;

  cFastMM4Summary =
    cSeparator + cNl +
    'This application has leaked memory. The small block leaks are (excluding expected leaks registered by ' +
    'pointer):' + cNl + cNl +
    '13 - 20 bytes: TStringList x 2' + cNl + cNl +
    'Note: Memory leak detail is logged to a text file in the same folder as this application. To disable this ' +
    'memory leak check, undefine "EnableMemoryLeakReporting".' + cNl;

  cFastMMError =
    cSeparator + cNl +
    'FastMM has detected an error during a FreeMem operation. The block header has been corrupted.' + cNl + cNl +
    'The current thread ID is 0x1A2C, and the stack trace (return addresses) leading to this error is:' + cNl +
    '4068F6 [System.pas][System][@FreeMem$qqrpv][4900]' + cNl +
    '4C2B10 [Kunden.pas][Kunden][TKundenListe.Leere][60]' + cNl + cNl +
    'The previous block size was: 20' + cNl;

function Block(AAddress: string): string;
begin
  Result := StringReplace(cFastMM4Block, '4C2B10', AAddress, []);
end;

procedure TLeakReportTests.ReadsRtlDialog;
var
  mReport: TLeakReport;
begin
  mReport := TLeakReports.Parse(cRtlDialog);
  Assert.AreEqual(4, Integer(Length(mReport.Counts)));
  // Nach Anzahl: UnicodeString 6, TKunde 3, TStringList 2, Unknown 1.
  Assert.AreEqual('UnicodeString', mReport.Counts[0].Name);
  Assert.AreEqual(6, mReport.Counts[0].Count);
  Assert.AreEqual(1, mReport.Counts[0].MinSize);
  Assert.AreEqual(20, mReport.Counts[0].MaxSize);
  Assert.IsTrue(mReport.Counts[0].Kind = TLeakKind.Text);
  Assert.AreEqual('TKunde', mReport.Counts[1].Name);
  Assert.IsTrue(mReport.Counts[1].Kind = TLeakKind.Instance);
  Assert.AreEqual(2, mReport.CountOf('tstringlist'));
  Assert.IsTrue(mReport.Counts[3].Kind = TLeakKind.Unknown);
  Assert.AreEqual(2, Integer(Length(mReport.LargeSizes)));
  Assert.AreEqual(Int64(80000), mReport.LargeSizes[1]);
  Assert.IsFalse(mReport.HasStacks);
  Assert.IsFalse(mReport.IsEmpty);
end;

procedure TLeakReportTests.ReadsLargeBlocksOnly;
var
  mReport: TLeakReport;
begin
  mReport := TLeakReports.Parse('An unexpected memory leak has occurred. The sizes of unexpected leaked medium and ' +
    'large blocks are: 40100');
  Assert.AreEqual(0, Integer(Length(mReport.Counts)));
  Assert.AreEqual(1, Integer(Length(mReport.LargeSizes)));
  Assert.AreEqual(Int64(40100), mReport.LargeSizes[0]);
end;

procedure TLeakReportTests.ReadsFastMM4LogWithStacks;
var
  mReport: TLeakReport;
begin
  mReport := TLeakReports.Parse(cFastMM4Block + Block('4C2B20') + cFastMM4Summary);
  Assert.AreEqual(2, Integer(Length(mReport.Blocks)));
  Assert.AreEqual(20, mReport.Blocks[0].Size);
  Assert.AreEqual('TStringList', mReport.Blocks[0].Name);
  Assert.AreEqual(5, Integer(Length(mReport.Blocks[0].Frames)), 'Speicherauszug zählt nicht als Stapel');
  Assert.AreEqual('Kunden.pas', mReport.Blocks[0].Frames[3].FileName);
  Assert.AreEqual(42, mReport.Blocks[0].Frames[3].Line);
  Assert.IsTrue(mReport.HasStacks);
  Assert.AreEqual(1, Integer(Length(mReport.Counts)), 'Zusammenfassung zählt');
  Assert.AreEqual(2, mReport.CountOf('TStringList'));
end;

procedure TLeakReportTests.ReadsFastMM5Summary;
var
  mReport: TLeakReport;
begin
  mReport := TLeakReports.Parse(cSeparator + cNl +
    'This application has leaked memory (excluding expected leaks registered by pointer). The leaked small ' +
    'blocks are:' + cNl + '20 bytes: TKunde x 1' + cNl + '36 bytes: UnicodeString x 2' + cNl);
  Assert.AreEqual(2, Integer(Length(mReport.Counts)));
  Assert.AreEqual('UnicodeString', mReport.Counts[0].Name);
  Assert.AreEqual(36, mReport.Counts[0].MinSize);
  Assert.AreEqual(1, mReport.CountOf('TKunde'));
end;

procedure TLeakReportTests.KeepsOnlyLastRun;
var
  mReport: TLeakReport;
begin
  mReport := TLeakReports.Parse(cFastMM4Block + cFastMM4Summary +
    StringReplace(Block('4C2B30'), 'TStringList', 'TKunde', []) + StringReplace(cFastMM4Summary,
    'TStringList x 2', 'TKunde x 1', []));
  Assert.AreEqual(1, Integer(Length(mReport.Blocks)));
  Assert.AreEqual('TKunde', mReport.Blocks[0].Name);
  Assert.AreEqual(0, mReport.CountOf('TStringList'), 'erster Lauf vergessen');
  Assert.AreEqual(1, mReport.CountOf('TKunde'));
end;

procedure TLeakReportTests.IgnoresFastMMErrors;
var
  mReport: TLeakReport;
begin
  mReport := TLeakReports.Parse(cFastMMError + cFastMM4Block);
  Assert.AreEqual(1, Integer(Length(mReport.Blocks)));
  Assert.AreEqual(0, Integer(Length(mReport.LargeSizes)));
  Assert.IsTrue(TLeakReports.Parse(cFastMMError).IsEmpty);
end;

procedure TLeakReportTests.CountsBlocksWithoutSummary;
var
  mReport: TLeakReport;
begin
  mReport := TLeakReports.Parse(cFastMM4Block + Block('4C2B40'));
  Assert.AreEqual(1, Integer(Length(mReport.Counts)));
  Assert.AreEqual(2, mReport.Counts[0].Count);
  Assert.AreEqual(20, mReport.Counts[0].MaxSize);
end;

procedure TLeakReportTests.GroupsSameStacks;
var
  mGroups: TArray<TLeakGroup>;
begin
  mGroups := TLeakReports.Parse(Block('4C2B50') + cFastMM4Block + cFastMM4Block).Groups;
  Assert.AreEqual(2, Integer(Length(mGroups)));
  Assert.AreEqual(2, mGroups[0].Count, 'gleicher Stapel zusammen, häufigster zuerst');
  Assert.AreEqual(Int64(40), mGroups[0].TotalSize);
  Assert.AreEqual(3, mGroups[0].Site);
  Assert.IsTrue(mGroups[0].Frames[mGroups[0].Site].Address = $4C2B10, 'Adresse der Stelle');
  Assert.AreEqual(1, mGroups[1].Count);
end;

procedure TLeakReportTests.ParsesFrames;
var
  mFrame: TLeakFrame;
begin
  Assert.IsTrue(TLeakReports.ParseFrame('  000000000040A3C3 [System.pas][System][System.TObject.NewInstance][7542]',
    mFrame));
  Assert.IsTrue(mFrame.Address = $40A3C3, 'Adresse');
  Assert.AreEqual('System', mFrame.UnitName);
  Assert.AreEqual('System.TObject.NewInstance', mFrame.Routine);
  Assert.AreEqual(7542, mFrame.Line);
  Assert.IsTrue(TLeakReports.ParseFrame('4068F6', mFrame), 'ohne Debug-Informationen nur die Adresse');
  Assert.AreEqual('', mFrame.UnitName);
  Assert.IsFalse(TLeakReports.ParseFrame('B8 4F 40 00 00 00', mFrame), 'Speicherauszug');
  Assert.IsFalse(TLeakReports.ParseFrame('Decade 2026', mFrame));
  Assert.IsFalse(TLeakReports.ParseFrame('', mFrame));
end;

procedure TLeakReportTests.SiteSkipsRtlAndFastMM;
var
  mFrames: TArray<TLeakFrame>;
begin
  SetLength(mFrames, 4);
  mFrames[0].UnitName := 'FastMM5';
  mFrames[1].UnitName := 'System';
  mFrames[2].UnitName := 'System.Classes';
  mFrames[3].UnitName := 'Main';
  Assert.AreEqual(3, TLeakReports.SiteOf(mFrames));
  SetLength(mFrames, 3);
  Assert.AreEqual(-1, TLeakReports.SiteOf(mFrames));
  Assert.AreEqual(-1, TLeakReports.SiteOf(nil));
end;

procedure TLeakReportTests.KindsOfNames;
begin
  Assert.IsTrue(TLeakReports.KindOf('AnsiString') = TLeakKind.Text);
  Assert.IsTrue(TLeakReports.KindOf('unknown') = TLeakKind.Unknown);
  Assert.IsTrue(TLeakReports.KindOf('TKunde') = TLeakKind.Instance);
end;

procedure TLeakReportTests.OtherTextIsEmpty;
begin
  Assert.IsTrue(TLeakReports.Parse('').IsEmpty);
  Assert.IsTrue(TLeakReports.Parse('Access violation at address 004068F6. Read of address 00000000.').IsEmpty);
  Assert.IsTrue(TLeakReports.Parse('Zeit: 12:30' + cNl + 'Wert: 3').IsEmpty);
end;

initialization
  TDUnitX.RegisterTestFixture(TLeakReportTests);

end.
