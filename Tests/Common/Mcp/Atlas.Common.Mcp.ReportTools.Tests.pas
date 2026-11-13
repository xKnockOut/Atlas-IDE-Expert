unit Atlas.Common.Mcp.ReportTools.Tests;

// Tests für resolve_address und analyze_report (#74): Adressen lesen und über die Map auflösen, Prüfung
// Map gegen EXE in der Ausgabe, Absturzbericht mit betroffener Stelle im Projekt, Stapelzeilen ohne
// Debug-Informationen über die Map, Leckbericht mit und ohne Aufrufstapel, fremder Text.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpReportToolsTests = class
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ParsesAddresses;
    [Test]
    procedure RejectsBadAddresses;
    [Test]
    procedure ResolvesAbsoluteAndOffset;
    [Test]
    procedure NamesOtherModule;
    [Test]
    procedure ReportsMapMismatch;
    [Test]
    procedure ResolveWithoutMapFails;
    [Test]
    procedure AnalyzesMadExceptWithProjectSite;
    [Test]
    procedure AnalyzesFramesWithoutDebugInfoViaMap;
    [Test]
    procedure AnalyzesExceptionTextViaMap;
    [Test]
    procedure AnalyzesFastMMLeaks;
    [Test]
    procedure AnalyzesRtlLeakDialog;
    [Test]
    procedure OtherTextFails;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.MapFile,
  Atlas.Text.PeImage,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Mcp.ReportTools,
  Atlas.Common.Localization.Texts;

const
  cNl = #13#10;

  cMap =
    ' Start         Length     Name                   Class' + cNl +
    ' 0001:00401000 0000A000H .text                   CODE' + cNl + cNl +
    '  Address             Publics by Value' + cNl + cNl +
    ' 0001:00000000       System.TObject.Create' + cNl +
    ' 0001:00000100       Kunden.Liste.TKundenListe.Lade' + cNl +
    ' 0001:00000200       Main.TMainForm.FormCreate' + cNl + cNl +
    'Line numbers for Kunden.Liste(Kunden.Liste.pas) segment .text' + cNl + cNl +
    '    40 0001:00000100    42 0001:00000110    44 0001:00000130' + cNl + cNl +
    'Line numbers for Main(Main.pas) segment .text' + cNl + cNl +
    '    17 0001:00000200' + cNl + cNl +
    'Program entry point at 0001:00000200' + cNl;

  cMadExcept =
    'madExcept version  : 5.1.3' + cNl +
    'exception class    : EAccessViolation' + cNl +
    'exception message  : Access violation at address 00401112 in module ''Kunden.exe''. Read of address 0.' + cNl +
    cNl +
    'main thread ($1a2c):' + cNl +
    '00401112 +012 Kunden.exe   System.SysUtils   900 +1 RaiseIt' + cNl +
    '00401112 +012 Kunden.exe   Kunden.Liste       42 +3 TKundenListe.Lade' + cNl +
    '00401200 +000 Kunden.exe   Main               17 +0 TMainForm.FormCreate' + cNl +
    cNl +
    'thread $2b3c (TSyncWorker):' + cNl +
    '770a2f1c +00c ntdll.dll                          NtWaitForSingleObject' + cNl;

  cJclWithoutDebugInfo =
    'Exception EAccessViolation in module Kunden.exe' + cNl +
    '[00501112]{Kunden.exe}' + cNl +
    '[00501200]{Kunden.exe}' + cNl +
    '[76B0F989]{KERNEL32.DLL} BaseThreadInitThunk' + cNl;

  cSeparator = '--------------------------------2026/11/13 10:00:00--------------------------------';

  cFastMM =
    cSeparator + cNl +
    'A memory block has been leaked. The size is: 20' + cNl + cNl +
    'This block was allocated by thread 0x1A2C, and the stack trace (return addresses) at the time was:' + cNl +
    '4068F6 [System.pas][System][@GetMem$qqri][4843]' + cNl +
    '40A3C3 [System.pas][System][TObject.NewInstance][17926]' + cNl +
    '4C2B10 [Kunden.Liste.pas][Kunden.Liste][TKundenListe.Lade][42]' + cNl + cNl +
    'The block is currently used for an object of class: TStringList' + cNl + cNl +
    cSeparator + cNl +
    'This application has leaked memory. The small block leaks are (excluding expected leaks registered by ' +
    'pointer):' + cNl + cNl +
    '13 - 20 bytes: TStringList x 1' + cNl;

  cRtlDialog =
    'An unexpected memory leak has occurred. The unexpected small block leaks are:' + cNl + cNl +
    '1 - 12 bytes: TKunde x 3, UnicodeString x 5' + cNl + cNl +
    'The sizes of unexpected leaked medium and large blocks are: 40100' + cNl;

/// <summary>Projekt kennt nur Kunden.Liste und Main.</summary>
function ProjectFile(const AUnitName, AFileName: string): string;
begin
  Result := '';
  if SameText(AUnitName, 'Kunden.Liste') or SameText(AFileName, 'Kunden.Liste.pas') then
  begin
    Result := 'C:\Projekt\Kunden.Liste.pas';
  end
  else if SameText(AUnitName, 'Main') then
  begin
    Result := 'C:\Projekt\Main.pas';
  end;
end;

function Symbols(AMap: TMapFile; AMatch: TMapImageMatch): TMcpSymbols;
begin
  Result := Default(TMcpSymbols);
  Result.Map := AMap;
  Result.MapName := 'Kunden.map';
  Result.Module := 'Kunden.exe';
  Result.Match := AMatch;
end;

procedure TMcpReportToolsTests.Setup;
begin
  TAtlasLocale.Use(TTextLanguage.German);
end;

procedure TMcpReportToolsTests.TearDown;
begin
  TAtlasLocale.Use(TTextLanguage.German);
end;

procedure TMcpReportToolsTests.ParsesAddresses;
var
  mAddresses: TArray<TMcpAddress>;
begin
  mAddresses := TMcpReportTools.ParseAddresses('00401112, $401200;Kunden.exe+$1110' + cNl + '0x401000');
  Assert.AreEqual(4, Integer(Length(mAddresses)));
  Assert.AreEqual<UInt64>($401112, mAddresses[0].Value);
  Assert.IsFalse(mAddresses[0].IsOffset);
  Assert.AreEqual<UInt64>($401200, mAddresses[1].Value);
  Assert.IsTrue(mAddresses[2].IsOffset);
  Assert.AreEqual('Kunden.exe', mAddresses[2].Module);
  Assert.AreEqual<UInt64>($1110, mAddresses[2].Value);
  Assert.AreEqual<UInt64>($401000, mAddresses[3].Value);
end;

procedure TMcpReportToolsTests.RejectsBadAddresses;
begin
  Assert.WillRaise(
    procedure
    begin
      TMcpReportTools.ParseAddresses('00401112 Zeile');
    end, EMcpToolError);
  Assert.WillRaise(
    procedure
    begin
      TMcpReportTools.ParseAddresses(' , ');
    end, EMcpToolError);
end;

procedure TMcpReportToolsTests.ResolvesAbsoluteAndOffset;
var
  mMap: TMapFile;
  mText: string;
begin
  mMap := TMapFile.Create(cMap);
  try
    mText := TMcpReportTools.ResolveAddresses(TMcpReportTools.ParseAddresses('00401112 Kunden.exe+$1200 00409000'),
      Symbols(mMap, TMapImageMatch.Matches), ProjectFile);
    Assert.IsTrue(mText.Contains('Map: Kunden.map (passt zur EXE)'), mText);
    Assert.IsTrue(mText.Contains('00401112'), mText);
    Assert.IsTrue(mText.Contains('Kunden.Liste.TKundenListe.Lade, Zeile 42 (C:\Projekt\Kunden.Liste.pas)'), mText);
    Assert.IsTrue(mText.Contains('Kunden.exe+$1200'), mText);
    Assert.IsTrue(mText.Contains('Main.TMainForm.FormCreate, Zeile 17 (C:\Projekt\Main.pas)'), mText);
    Assert.IsTrue(mText.Contains('00409000'), mText);
    Assert.IsTrue(mText.Contains('Main.TMainForm.FormCreate'), mText);
  finally
    mMap.Free;
  end;
end;

procedure TMcpReportToolsTests.NamesOtherModule;
var
  mMap: TMapFile;
  mText: string;
begin
  mMap := TMapFile.Create(cMap);
  try
    mText := TMcpReportTools.ResolveAddresses(TMcpReportTools.ParseAddresses('ntdll.dll+$12F1C 7FFE0000'),
      Symbols(mMap, TMapImageMatch.Unknown), nil);
    Assert.IsTrue(mText.Contains('ohne EXE nicht geprüft'), mText);
    Assert.IsTrue(mText.Contains('ntdll.dll+$12F1C'), mText);
    Assert.IsTrue(mText.Contains('anderes Modul (ntdll.dll), Map gehört zu Kunden.exe'), mText);
    Assert.IsTrue(mText.Contains('7FFE0000'), mText);
    Assert.IsTrue(mText.Contains('nicht in der Map'), mText);
  finally
    mMap.Free;
  end;
end;

procedure TMcpReportToolsTests.ReportsMapMismatch;
var
  mMap: TMapFile;
begin
  TAtlasLocale.Use(TTextLanguage.English);
  mMap := TMapFile.Create(cMap);
  try
    Assert.IsTrue(TMcpReportTools.MapStatus(Symbols(mMap, TMapImageMatch.EntryPointDiffers))
      .Contains('DOES NOT BELONG TO THE EXE: different entry point'));
    Assert.IsTrue(TMcpReportTools.MapStatus(Symbols(mMap, TMapImageMatch.CodeSizeDiffers))
      .Contains('different code size'));
    Assert.AreEqual('', TMcpReportTools.MapStatus(Default(TMcpSymbols)));
  finally
    mMap.Free;
    end;
end;

procedure TMcpReportToolsTests.ResolveWithoutMapFails;
begin
  Assert.WillRaise(
    procedure
    begin
      TMcpReportTools.ResolveAddresses(TMcpReportTools.ParseAddresses('00401112'), Default(TMcpSymbols), nil);
    end, EMcpToolError);
end;

procedure TMcpReportToolsTests.AnalyzesMadExceptWithProjectSite;
var
  mText: string;
begin
  mText := TMcpReportTools.AnalyzeReport(cMadExcept, Default(TMcpSymbols), ProjectFile);
  Assert.IsTrue(mText.Contains('Absturzbericht (madExcept): EAccessViolation'), mText);
  Assert.IsTrue(mText.Contains('Absturzadresse: 00401112 (Kunden.exe)'), mText);
  Assert.IsTrue(mText.Contains('System.SysUtils.RaiseIt, Zeile 900'), mText);
  // Erste Zeile mit Datei im Projekt, nicht die RTL-Zeile davor.
  Assert.IsTrue(mText.Contains(
    'Betroffene Stelle: Kunden.Liste.TKundenListe.Lade, Zeile 42 (C:\Projekt\Kunden.Liste.pas)'), mText);
  Assert.IsTrue(mText.Contains('Keine Map-Datei'), mText);
  Assert.IsTrue(mText.Contains('Aufrufstapel (main thread ($1a2c)):'), mText);
  Assert.IsTrue(mText.Contains(
    '  3. 00401200 Kunden.exe Main.TMainForm.FormCreate, Zeile 17 (C:\Projekt\Main.pas)'), mText);
  Assert.IsTrue(mText.Contains('Weitere Threads: thread $2b3c (TSyncWorker)'), mText);
end;

procedure TMcpReportToolsTests.AnalyzesFramesWithoutDebugInfoViaMap;
var
  mMap: TMapFile;
  mSymbols: TMcpSymbols;
  mText: string;
begin
  mMap := TMapFile.Create(cMap);
  try
    // Programm war bei $500000 statt $400000 geladen (base).
    mSymbols := Symbols(mMap, TMapImageMatch.Matches);
    mSymbols.Base := $500000;
    mText := TMcpReportTools.AnalyzeReport(cJclWithoutDebugInfo, mSymbols, ProjectFile);
    Assert.IsTrue(mText.Contains('Absturzbericht (JclDebug)'), mText);
    Assert.IsTrue(mText.Contains(
      'Betroffene Stelle: Kunden.Liste.TKundenListe.Lade, Zeile 42 (C:\Projekt\Kunden.Liste.pas)'), mText);
    Assert.IsTrue(mText.Contains('  2. 00501200 Kunden.exe Main.TMainForm.FormCreate, Zeile 17'), mText);
    Assert.IsTrue(mText.Contains('  3. 76B0F989 KERNEL32.DLL BaseThreadInitThunk'), mText);
  finally
    mMap.Free;
  end;
end;

procedure TMcpReportToolsTests.AnalyzesExceptionTextViaMap;
var
  mMap: TMapFile;
  mText: string;
begin
  mMap := TMapFile.Create(cMap);
  try
    mText := TMcpReportTools.AnalyzeReport(
      'Zugriffsverletzung bei Adresse 00401130 in Modul ''Kunden.exe''. Lesen von Adresse 00000000.',
      Symbols(mMap, TMapImageMatch.Matches), ProjectFile);
    Assert.IsTrue(mText.Contains('Absturzbericht (Exception)'), mText);
    Assert.IsTrue(mText.Contains('Absturzadresse: 00401130 (Kunden.exe)'), mText);
    Assert.IsTrue(mText.Contains('Kunden.Liste.TKundenListe.Lade, Zeile 44'), mText);
    Assert.IsTrue(mText.Contains('Betroffene Stelle: Kunden.Liste.TKundenListe.Lade, Zeile 44'), mText);
  finally
    mMap.Free;
  end;
end;

procedure TMcpReportToolsTests.AnalyzesFastMMLeaks;
var
  mText: string;
begin
  mText := TMcpReportTools.AnalyzeReport(cFastMM, Default(TMcpSymbols), ProjectFile);
  Assert.IsTrue(mText.Contains('Leckbericht: 1 Lecks (1 Arten)'), mText);
  Assert.IsTrue(mText.Contains('1. TStringList × 1 (20 Bytes)'), mText);
  Assert.IsTrue(mText.Contains(
    'erzeugt in Kunden.Liste.TKundenListe.Lade, Zeile 42 (C:\Projekt\Kunden.Liste.pas)'), mText);
end;

procedure TMcpReportToolsTests.AnalyzesRtlLeakDialog;
var
  mText: string;
begin
  mText := TMcpReportTools.AnalyzeReport(cRtlDialog, Default(TMcpSymbols), nil);
  Assert.IsTrue(mText.Contains('Leckbericht: 9 Lecks (2 Arten)'), mText);
  Assert.IsTrue(mText.Contains('Ohne Aufrufstapel'), mText);
  Assert.IsTrue(mText.Contains('- UnicodeString × 5'), mText);
  Assert.IsTrue(mText.Contains('Mittlere und große Blöcke: 40100 Bytes'), mText);
end;

procedure TMcpReportToolsTests.OtherTextFails;
begin
  Assert.WillRaise(
    procedure
    begin
      TMcpReportTools.AnalyzeReport('unit Main; interface end.', Default(TMcpSymbols), nil);
    end, EMcpToolError);
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpReportToolsTests);

end.
