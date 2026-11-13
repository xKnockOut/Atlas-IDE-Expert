unit Atlas.Text.CrashReport.Tests;

// Tests für das Lesen von Absturzberichten (#74): eingecheckte Beispielberichte
// von madExcept, EurekaLog 6 und 7 und JclDebug unter Tests\Data\CrashReports,
// dazu die Meldung einer Exception allein, Stapelzeilen, Erzeugungsstelle und
// Hexzahlen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCrashReportTests = class
  public
    [Test]
    procedure ReadsMadExcept;
    [Test]
    procedure ReadsMadExceptModules;
    [Test]
    procedure ReadsEurekaLog7;
    [Test]
    procedure ReadsEurekaLog6;
    [Test]
    procedure ReadsJclDebug;
    [Test]
    procedure ReadsExceptionTextOnly;
    [Test]
    procedure ReadsGermanExceptionText;
    [Test]
    procedure ReadsPastedMadExceptStack;
    [Test]
    procedure ParsesMadExceptFrames;
    [Test]
    procedure ParsesJclFrames;
    [Test]
    procedure SiteSkipsLibraries;
    [Test]
    procedure ParsesHex;
    [Test]
    procedure OtherTextIsEmpty;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Text.CrashReport;

/// <summary>Bericht aus Tests\Data\CrashReports, gesucht ab dem Ordner des Testprogramms aufwärts.</summary>
function Sample(const AName: string): string;
var
  mDirectory, mFileName: string;
begin
  mDirectory := ExtractFileDir(ParamStr(0));
  while mDirectory <> '' do
  begin
    mFileName := TPath.Combine(mDirectory, TPath.Combine('Tests', TPath.Combine('Data',
      TPath.Combine('CrashReports', AName))));
    if TFile.Exists(mFileName) then
    begin
      Exit(TFile.ReadAllText(mFileName, TEncoding.UTF8));
    end;
    if ExtractFileDir(mDirectory) = mDirectory then
    begin
      Break;
    end;
    mDirectory := ExtractFileDir(mDirectory);
  end;
  raise EFileNotFoundException.Create('Tests\Data\CrashReports\' + AName + ' nicht gefunden');
end;

procedure AssertFrame(const AFrame: TCrashFrame; const AUnit, ARoutine: string; ALine: Integer);
begin
  Assert.AreEqual(AUnit, AFrame.UnitName);
  Assert.AreEqual(ARoutine, AFrame.Routine);
  Assert.AreEqual(ALine, AFrame.Line);
end;

procedure TCrashReportTests.ReadsMadExcept;
var
  mReport: TCrashReport;
  mFrames: TArray<TCrashFrame>;
begin
  mReport := TCrashReports.Parse(Sample('madexcept.txt'));
  Assert.AreEqual<TCrashReportKind>(TCrashReportKind.MadExcept, mReport.Kind);
  Assert.AreEqual('EAccessViolation', mReport.ExceptionClass);
  Assert.AreEqual<UInt64>($45A1B2, mReport.Address);
  Assert.AreEqual('Kunden.exe', mReport.Module);
  Assert.AreEqual(2, Integer(Length(mReport.Threads)));
  Assert.IsTrue(mReport.Threads[0].Crashed);
  Assert.IsFalse(mReport.Threads[1].Crashed);
  mFrames := mReport.CrashFrames;
  Assert.AreEqual(5, Integer(Length(mFrames)));
  AssertFrame(mFrames[0], 'Kunden.Liste', 'TKundenListe.Lade', 42);
  Assert.AreEqual('Kunden.exe', mFrames[0].Module);
  AssertFrame(mFrames[2], 'Vcl.Forms', 'TCustomForm.DoCreate', 0);
  AssertFrame(mFrames[4], '', 'BaseThreadInitThunk', 0);
  Assert.AreEqual('KERNEL32.DLL', mFrames[4].Module);
  Assert.AreEqual(0, TCrashReports.SiteOf(mFrames));
end;

procedure TCrashReportTests.ReadsMadExceptModules;
var
  mReport: TCrashReport;
  mBase: UInt64;
begin
  mReport := TCrashReports.Parse(Sample('madexcept.txt'));
  Assert.AreEqual(4, Integer(Length(mReport.Modules)));
  Assert.IsTrue(mReport.TryBaseOf('kunden.core.bpl', mBase));
  Assert.AreEqual<UInt64>($50000000, mBase);
  Assert.IsTrue(mReport.TryBaseOf('C:\Projekte\Kunden\Kunden.exe', mBase));
  Assert.AreEqual<UInt64>($400000, mBase);
  Assert.IsFalse(mReport.TryBaseOf('fehlt.dll', mBase));
end;

procedure TCrashReportTests.ReadsEurekaLog7;
var
  mReport: TCrashReport;
  mFrames: TArray<TCrashFrame>;
begin
  mReport := TCrashReports.Parse(Sample('eurekalog7.txt'));
  Assert.AreEqual<TCrashReportKind>(TCrashReportKind.EurekaLog, mReport.Kind);
  Assert.AreEqual('EAccessViolation', mReport.ExceptionClass);
  Assert.AreEqual<UInt64>($45A1B2, mReport.Address);
  Assert.AreEqual('Kunden.exe', mReport.Module);
  Assert.AreEqual(2, Integer(Length(mReport.Threads)));
  Assert.IsFalse(mReport.Threads[0].Crashed);
  Assert.IsTrue(mReport.Threads[1].Crashed);
  mFrames := mReport.CrashFrames;
  Assert.AreEqual(3, Integer(Length(mFrames)));
  AssertFrame(mFrames[0], 'Kunden.Liste', 'TKundenListe.Lade', 42);
  AssertFrame(mFrames[1], 'Main', 'TMainForm.FormCreate', 17);
  AssertFrame(mFrames[2], 'Vcl.Forms', 'TCustomForm.DoCreate', 4300);
  Assert.AreEqual(2, Integer(Length(mReport.Modules)));
  Assert.AreEqual('KERNEL32.DLL', mReport.Modules[1].Name);
  Assert.AreEqual<UInt64>($76AF0000, mReport.Modules[1].Base);
end;

procedure TCrashReportTests.ReadsEurekaLog6;
var
  mReport: TCrashReport;
  mFrames: TArray<TCrashFrame>;
begin
  mReport := TCrashReports.Parse(Sample('eurekalog6.txt'));
  Assert.AreEqual<TCrashReportKind>(TCrashReportKind.EurekaLog, mReport.Kind);
  Assert.AreEqual('Kunden.exe', mReport.Module);
  mFrames := mReport.CrashFrames;
  Assert.AreEqual(3, Integer(Length(mFrames)));
  AssertFrame(mFrames[0], 'KundenListe', 'TKundenListe.Lade', 42);
  Assert.AreEqual('KundenListe.pas', mFrames[0].FileName);
  AssertFrame(mFrames[2], 'Forms', 'TCustomForm.DoCreate', 0);
  Assert.AreEqual(0, TCrashReports.SiteOf(mFrames));
end;

procedure TCrashReportTests.ReadsJclDebug;
var
  mReport: TCrashReport;
  mFrames: TArray<TCrashFrame>;
begin
  mReport := TCrashReports.Parse(Sample('jcldebug.txt'));
  Assert.AreEqual<TCrashReportKind>(TCrashReportKind.JclDebug, mReport.Kind);
  Assert.AreEqual<UInt64>($45A1B2, mReport.Address);
  Assert.AreEqual('Kunden.exe', mReport.Module);
  Assert.IsTrue(mReport.ExceptionMessage.StartsWith('Exception EAccessViolation'));
  mFrames := mReport.CrashFrames;
  Assert.AreEqual(4, Integer(Length(mFrames)));
  AssertFrame(mFrames[0], 'Kunden.Liste', 'TKundenListe.Lade', 42);
  Assert.AreEqual('Kunden.Liste.pas', mFrames[0].FileName);
  AssertFrame(mFrames[2], '', 'Vcl.Forms.TCustomForm.DoCreate', 0);
  Assert.AreEqual('KERNEL32.DLL', mFrames[3].Module);
  Assert.AreEqual('BaseThreadInitThunk', mFrames[3].Routine);
end;

procedure TCrashReportTests.ReadsExceptionTextOnly;
var
  mReport: TCrashReport;
begin
  mReport := TCrashReports.Parse('Fehler beim Start' + sLineBreak +
    'Access violation at address 0045A1B2 in module ''Kunden.exe''. Read of address 00000000.');
  Assert.AreEqual<TCrashReportKind>(TCrashReportKind.ExceptionText, mReport.Kind);
  Assert.AreEqual<UInt64>($45A1B2, mReport.Address);
  Assert.AreEqual('Kunden.exe', mReport.Module);
  Assert.AreEqual(0, Integer(Length(mReport.CrashFrames)));
end;

procedure TCrashReportTests.ReadsGermanExceptionText;
var
  mReport: TCrashReport;
begin
  mReport := TCrashReports.Parse(
    'Zugriffsverletzung bei Adresse 50012A3C in Modul ''Kunden.Core.bpl''. Lesen von Adresse 00000004.');
  Assert.AreEqual<TCrashReportKind>(TCrashReportKind.ExceptionText, mReport.Kind);
  Assert.AreEqual<UInt64>($50012A3C, mReport.Address);
  Assert.AreEqual('Kunden.Core.bpl', mReport.Module);
end;

procedure TCrashReportTests.ReadsPastedMadExceptStack;
var
  mReport: TCrashReport;
begin
  // Nur die Stapelzeilen aus dem Bericht kopiert, ohne Kopf und Thread-Zeile.
  mReport := TCrashReports.Parse(
    '0045a1b2 +012 Kunden.exe   Kunden.Liste       42   +3 TKundenListe.Lade' + sLineBreak +
    '0045b3c4 +02c Kunden.exe   Main               17   +1 TMainForm.FormCreate');
  Assert.AreEqual<TCrashReportKind>(TCrashReportKind.MadExcept, mReport.Kind);
  Assert.AreEqual(2, Integer(Length(mReport.CrashFrames)));
  Assert.AreEqual<UInt64>($45A1B2, mReport.Address);
  Assert.AreEqual('Kunden.exe', mReport.Module);
end;

procedure TCrashReportTests.ParsesMadExceptFrames;
var
  mFrame: TCrashFrame;
begin
  Assert.IsTrue(TCrashReports.ParseMadExceptFrame('0045a1b2 +012 Kunden.exe Main 17 +1 TMainForm.FormCreate', mFrame));
  Assert.AreEqual<UInt64>($45A1B2, mFrame.Address);
  AssertFrame(mFrame, 'Main', 'TMainForm.FormCreate', 17);
  Assert.IsTrue(mFrame.HasLocation);
  Assert.IsTrue(TCrashReports.ParseMadExceptFrame('00000001400a1b2c +012 Kunden.exe Main TMainForm.Show', mFrame));
  Assert.AreEqual<UInt64>($1400A1B2C, mFrame.Address);
  AssertFrame(mFrame, 'Main', 'TMainForm.Show', 0);
  Assert.IsFalse(TCrashReports.ParseMadExceptFrame('exception class : EAccessViolation', mFrame));
  Assert.IsFalse(TCrashReports.ParseMadExceptFrame('0045a1b2 012 Kunden.exe Main', mFrame));
  Assert.IsFalse(TCrashReports.ParseMadExceptFrame('', mFrame));
end;

procedure TCrashReportTests.ParsesJclFrames;
var
  mFrame: TCrashFrame;
begin
  Assert.IsTrue(TCrashReports.ParseJclFrame('[0045B3C4]{Kunden.exe} Main.TMainForm.FormCreate (Line 17, "Main.pas" + 1)',
    mFrame));
  Assert.AreEqual<UInt64>($45B3C4, mFrame.Address);
  Assert.AreEqual('Kunden.exe', mFrame.Module);
  AssertFrame(mFrame, 'Main', 'TMainForm.FormCreate', 17);
  Assert.IsFalse(TCrashReports.ParseJclFrame('[Main]{x} y', mFrame));
  Assert.IsFalse(TCrashReports.ParseJclFrame('[0045B3C4] ohne Modul', mFrame));
end;

procedure TCrashReportTests.SiteSkipsLibraries;
var
  mFrames: TArray<TCrashFrame>;
begin
  SetLength(mFrames, 3);
  mFrames[0].UnitName := 'System.SysUtils';
  mFrames[0].Line := 10;
  mFrames[1].UnitName := 'Kunden.Liste';
  mFrames[2].UnitName := 'Main';
  mFrames[2].Line := 17;
  Assert.AreEqual(2, TCrashReports.SiteOf(mFrames));
  Assert.IsTrue(TCrashReports.IsLibraryUnit('Vcl.Controls'));
  Assert.IsTrue(TCrashReports.IsLibraryUnit('SysInit'));
  Assert.IsTrue(TCrashReports.IsLibraryUnit('madExcept'));
  Assert.IsFalse(TCrashReports.IsLibraryUnit('Systematik'));
  Assert.IsFalse(TCrashReports.IsLibraryUnit('Kunden.Liste'));
  Assert.AreEqual(-1, TCrashReports.SiteOf(nil));
  mFrames := nil;
end;

procedure TCrashReportTests.ParsesHex;
var
  mValue: UInt64;
begin
  Assert.IsTrue(TCrashReports.TryParseHex('0045a1b2', mValue));
  Assert.AreEqual<UInt64>($45A1B2, mValue);
  Assert.IsTrue(TCrashReports.TryParseHex('$1A', mValue));
  Assert.AreEqual<UInt64>($1A, mValue);
  Assert.IsTrue(TCrashReports.TryParseHex('0x7FFE0000', mValue));
  Assert.AreEqual<UInt64>($7FFE0000, mValue);
  Assert.IsTrue(TCrashReports.TryParseHex('FFFFFFFFFFFFFFFF', mValue));
  Assert.AreEqual<UInt64>(High(UInt64), mValue);
  Assert.IsFalse(TCrashReports.TryParseHex('12G4', mValue));
  Assert.IsFalse(TCrashReports.TryParseHex('', mValue));
  Assert.IsFalse(TCrashReports.TryParseHex('$', mValue));
  Assert.IsFalse(TCrashReports.TryParseHex('10000000000000000', mValue));
end;

procedure TCrashReportTests.OtherTextIsEmpty;
var
  mReport: TCrashReport;
begin
  mReport := TCrashReports.Parse('unit Main;' + sLineBreak + 'interface' + sLineBreak + 'end.');
  Assert.IsTrue(mReport.IsEmpty);
  Assert.IsTrue(TCrashReports.Parse('').IsEmpty);
end;

initialization
  TDUnitX.RegisterTestFixture(TCrashReportTests);

end.
