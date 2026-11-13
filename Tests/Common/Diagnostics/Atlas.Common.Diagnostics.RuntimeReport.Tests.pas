unit Atlas.Common.Diagnostics.RuntimeReport.Tests;

// Laufzeitberichte als Stapel (#74): Leckgruppen mit Erzeugungsstelle im Projekt, Lecks ohne Aufrufstapel,
// Absturz mit Thread der Exception zuerst, Stapelzeilen ohne Debug-Informationen über die Map, fremder Text,
// Zustand der Map.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRuntimeReportTests = class
  public
    [Test]
    procedure LeakGroupsWithProjectSite;
    [Test]
    procedure LeaksWithoutStacks;
    [Test]
    procedure CrashedThreadFirst;
    [Test]
    procedure FramesWithoutDebugInfoViaMap;
    [Test]
    procedure OtherTextIsNone;
    [Test]
    procedure MapStates;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.MapFile,
  Atlas.Text.PeImage,
  Atlas.Text.LeakReport,
  Atlas.Common.Diagnostics.RuntimeReport;

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
    '770a2f1c +00c ntdll.dll                          NtWaitForSingleObject' + cNl +
    '00401200 +000 Kunden.exe   Main               17 +0 TMainForm.FormCreate' + cNl;

  cJclWithoutDebugInfo =
    'Exception EAccessViolation in module Kunden.exe' + cNl +
    '[00501112]{Kunden.exe}' + cNl +
    '[00501200]{Kunden.exe}' + cNl +
    '[76B0F989]{KERNEL32.DLL} BaseThreadInitThunk' + cNl;

  cSeparator = '--------------------------------2026/11/13 10:00:00--------------------------------';

  cFastMMBlock =
    cSeparator + cNl +
    'A memory block has been leaked. The size is: 20' + cNl + cNl +
    'This block was allocated by thread 0x1A2C, and the stack trace (return addresses) at the time was:' + cNl +
    '4068F6 [System.pas][System][@GetMem$qqri][4843]' + cNl +
    '40A3C3 [System.pas][System][TObject.NewInstance][17926]' + cNl +
    '4C2B10 [Kunden.Hilfe.pas][Kunden.Hilfe][TKundenHilfe.Neu][12]' + cNl +
    '4C2C10 [Kunden.Liste.pas][Kunden.Liste][TKundenListe.Lade][42]' + cNl + cNl +
    'The block is currently used for an object of class: TStringList' + cNl + cNl;

  cRtlDialog =
    'An unexpected memory leak has occurred. The unexpected small block leaks are:' + cNl + cNl +
    '1 - 12 bytes: TKunde x 3, UnicodeString x 5' + cNl;

/// <summary>Projekt kennt nur Kunden.Liste und Main; Kunden.Hilfe liegt außerhalb.</summary>
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

procedure TRuntimeReportTests.LeakGroupsWithProjectSite;
var
  mReport: TRuntimeReport;
  mStack: TRuntimeStack;
begin
  mReport := TRuntimeReports.Build(cFastMMBlock + cFastMMBlock, Default(TReportSymbols), ProjectFile);
  Assert.AreEqual<TRuntimeReportKind>(TRuntimeReportKind.Leaks, mReport.Kind);
  Assert.AreEqual('FastMM', mReport.Source);
  Assert.AreEqual(1, Integer(Length(mReport.Stacks)));
  mStack := mReport.Stacks[0];
  Assert.AreEqual('TStringList', mStack.Name);
  Assert.AreEqual(2, mStack.Count);
  Assert.AreEqual<Int64>(40, mStack.Size);
  // Kunden.Hilfe steht weiter oben, gehört aber nicht zum Projekt.
  Assert.AreEqual(3, mStack.Site);
  Assert.IsTrue(mStack.HasProjectSite);
  Assert.AreEqual('C:\Projekt\Kunden.Liste.pas', mStack.Frames[3].ProjectFile);
  Assert.AreEqual(42, mStack.Frames[3].Line);
  Assert.AreEqual('', mStack.Frames[2].ProjectFile);
  Assert.AreEqual<UInt64>($4C2C10, mStack.Frames[3].Address);
end;

procedure TRuntimeReportTests.LeaksWithoutStacks;
var
  mReport: TRuntimeReport;
begin
  mReport := TRuntimeReports.Build(cRtlDialog, Default(TReportSymbols), ProjectFile);
  Assert.AreEqual<TRuntimeReportKind>(TRuntimeReportKind.Leaks, mReport.Kind);
  Assert.AreEqual(2, Integer(Length(mReport.Stacks)));
  Assert.AreEqual('UnicodeString', mReport.Stacks[0].Name);
  Assert.AreEqual(5, mReport.Stacks[0].Count);
  Assert.AreEqual<TLeakKind>(TLeakKind.Text, mReport.Stacks[0].LeakKind);
  Assert.AreEqual(-1, mReport.Stacks[1].Site);
  Assert.IsFalse(mReport.Stacks[1].HasProjectSite);
  Assert.AreEqual(0, Integer(Length(mReport.Stacks[1].Frames)));
end;

procedure TRuntimeReportTests.CrashedThreadFirst;
var
  mReport: TRuntimeReport;
begin
  mReport := TRuntimeReports.Build(cMadExcept, Default(TReportSymbols), ProjectFile);
  Assert.AreEqual<TRuntimeReportKind>(TRuntimeReportKind.Crash, mReport.Kind);
  Assert.AreEqual('madExcept', mReport.Source);
  Assert.AreEqual('EAccessViolation', mReport.ExceptionClass);
  Assert.AreEqual<UInt64>($401112, mReport.Address);
  Assert.AreEqual('Kunden.exe', mReport.Module);
  Assert.AreEqual(2, Integer(Length(mReport.Stacks)));
  Assert.AreEqual('main thread ($1a2c)', mReport.Stacks[0].Name);
  Assert.IsTrue(mReport.Stacks[0].Crashed);
  Assert.AreEqual(1, mReport.Stacks[0].Site);
  Assert.AreEqual('C:\Projekt\Kunden.Liste.pas', mReport.Stacks[0].Frames[1].ProjectFile);
  Assert.AreEqual('C:\Projekt\Main.pas', mReport.Stacks[0].Frames[2].ProjectFile);
  Assert.AreEqual('', mReport.Stacks[0].Frames[0].ProjectFile);
  Assert.IsFalse(mReport.Stacks[1].Crashed);
  Assert.AreEqual(1, mReport.Stacks[1].Site);
end;

procedure TRuntimeReportTests.FramesWithoutDebugInfoViaMap;
var
  mMap: TMapFile;
  mSymbols: TReportSymbols;
  mReport: TRuntimeReport;
begin
  mMap := TMapFile.Create(cMap);
  try
    mSymbols := Default(TReportSymbols);
    mSymbols.Map := mMap;
    mSymbols.Module := 'Kunden.exe';
    mSymbols.Base := $500000;
    mReport := TRuntimeReports.Build(cJclWithoutDebugInfo, mSymbols, ProjectFile);
    Assert.AreEqual('JclDebug', mReport.Source);
    Assert.AreEqual(0, mReport.Stacks[0].Site);
    Assert.AreEqual('Kunden.Liste', mReport.Stacks[0].Frames[0].UnitName);
    Assert.AreEqual(42, mReport.Stacks[0].Frames[0].Line);
    Assert.AreEqual('C:\Projekt\Kunden.Liste.pas', mReport.Stacks[0].Frames[0].ProjectFile);
    Assert.AreEqual(17, mReport.Stacks[0].Frames[1].Line);
    Assert.AreEqual('', mReport.Stacks[0].Frames[2].ProjectFile);
  finally
    mMap.Free;
  end;
end;

procedure TRuntimeReportTests.OtherTextIsNone;
var
  mReport: TRuntimeReport;
begin
  mReport := TRuntimeReports.Build('unit Main; interface end.', Default(TReportSymbols), nil);
  Assert.AreEqual<TRuntimeReportKind>(TRuntimeReportKind.None, mReport.Kind);
  Assert.AreEqual(0, Integer(Length(mReport.Stacks)));
end;

procedure TRuntimeReportTests.MapStates;
var
  mSymbols: TReportSymbols;
  mMap: TMapFile;
begin
  TRuntimeReports.LoadSymbols('', '', 0, mSymbols);
  Assert.AreEqual<TReportMapState>(TReportMapState.None, mSymbols.MapState);
  TRuntimeReports.LoadSymbols('', 'gibt-es-nicht' + PathDelim + 'Kunden.exe', 0, mSymbols);
  Assert.AreEqual<TReportMapState>(TReportMapState.Missing, mSymbols.MapState);
  Assert.AreEqual('gibt-es-nicht' + PathDelim + 'Kunden.map', mSymbols.MapName);
  Assert.IsNull(mSymbols.Map);
  mMap := TMapFile.Create(cMap);
  try
    mSymbols.Map := mMap;
    mSymbols.Match := TMapImageMatch.EntryPointDiffers;
    Assert.AreEqual<TReportMapState>(TReportMapState.EntryPointDiffers, mSymbols.MapState);
  finally
    mMap.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TRuntimeReportTests);

end.
