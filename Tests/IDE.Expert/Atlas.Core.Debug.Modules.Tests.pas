unit Atlas.Core.Debug.Modules.Tests;

// Tests zum Modul der Fehleradresse (#1820): Adresse und Modul aus der Meldung, Zuordnung über Adressbereich,
// Namen und Kopfzeile, Einstufung (Programm, RTL/VCL, Windows, Fremdmodul) und die letzte eigene Stelle.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Debug.Modules;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasDebugModulesTests = class
  private
    function Modules: TAtlasDebugModuleList;
    function Environment: TAtlasDebugModuleEnvironment;
  public
    [Test]
    procedure ParsesRtlMessageGerman;
    [Test]
    procedure ParsesRtlMessageEnglish64;
    [Test]
    procedure ParsesDebuggerMessage;
    [Test]
    procedure ParsesNothingWithoutAddress;
    [Test]
    procedure FindsModuleByAddress;
    [Test]
    procedure FindsModuleByName;
    [Test]
    procedure FindsModuleByHeader;
    [Test]
    procedure RecognizesRuntimePackages;
    [Test]
    procedure ClassifiesModules;
    [Test]
    procedure ResolvesOwnProgram;
    [Test]
    procedure ResolvesVclWithLastOwnFrame;
    [Test]
    procedure ResolvesForeignDllWithoutDebugInfo;
    [Test]
    procedure ResolvesLoadedLibraryByAddress;
    [Test]
    procedure ResolvesNameOnlyWithoutModuleList;
    [Test]
    procedure ResolvesNothingWithoutHints;
  end;

implementation

uses
  Atlas.Core.Debug.CallStack;


{ TAtlasDebugModulesTests }

function TAtlasDebugModulesTests.Modules: TAtlasDebugModuleList;
begin
  Result := [TAtlasDebugLoadedModule.Create('C:\Projekte\Demo\Win32\Debug\Demo.exe', $00400000, $00200000),
    TAtlasDebugLoadedModule.Create('C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\vcl370.bpl', $50000000, $00400000),
    TAtlasDebugLoadedModule.Create('C:\Windows\SysWOW64\KERNELBASE.dll', $77000000, $00200000),
    TAtlasDebugLoadedModule.Create('C:\Projekte\Demo\Win32\Debug\Fremd.dll', $10000000, $00010000)];
end;

function TAtlasDebugModulesTests.Environment: TAtlasDebugModuleEnvironment;
begin
  Result := Default(TAtlasDebugModuleEnvironment);
  Result.ProgramFile := 'C:\Projekte\Demo\Win32\Debug\Demo.exe';
  Result.BdsDir := 'C:\Program Files (x86)\Embarcadero\Studio\37.0';
  Result.WindowsDir := 'C:\Windows';
end;

procedure TAtlasDebugModulesTests.ParsesRtlMessageGerman;
var
  mFault: TAtlasDebugFault;
begin
  mFault := TAtlasDebugFault.Parse(
    'Zugriffsverletzung bei Adresse 0040ABCD in Modul ''Demo.exe''. Lesen von Adresse 0000001C.');
  Assert.IsTrue(mFault.CodeAddressKnown);
  Assert.IsTrue(mFault.CodeAddress = UInt64($0040ABCD), 'Adresse des Codes');
  Assert.AreEqual('Demo.exe', mFault.ModuleName);
end;

procedure TAtlasDebugModulesTests.ParsesRtlMessageEnglish64;
var
  mFault: TAtlasDebugFault;
begin
  mFault := TAtlasDebugFault.Parse(
    'Access violation at address 00007FFA12345678 in module ''vcl370.bpl''. Read of address 0000000000000008.');
  Assert.IsTrue(mFault.CodeAddressKnown);
  Assert.IsTrue(mFault.CodeAddress = UInt64($00007FFA12345678), 'Adresse des Codes');
  Assert.AreEqual('vcl370.bpl', mFault.ModuleName);
end;

procedure TAtlasDebugModulesTests.ParsesDebuggerMessage;
var
  mFault: TAtlasDebugFault;
begin
  mFault := TAtlasDebugFault.Parse('access violation at 0x10001234: read of address 0x0000001c');
  Assert.IsTrue(mFault.CodeAddressKnown);
  Assert.IsTrue(mFault.CodeAddress = UInt64($10001234), 'Adresse des Codes');
  Assert.AreEqual('', mFault.ModuleName, 'Der Debugger nennt kein Modul');
  mFault := TAtlasDebugFault.Parse('Zugriffsverletzung bei 0x50001000: Schreiben von Adresse 0x00000000');
  Assert.IsTrue(mFault.CodeAddress = UInt64($50001000), 'Adresse des Codes');
end;

procedure TAtlasDebugModulesTests.ParsesNothingWithoutAddress;
var
  mFault: TAtlasDebugFault;
begin
  mFault := TAtlasDebugFault.Parse('Ungültige Typumwandlung');
  Assert.IsFalse(mFault.CodeAddressKnown);
  Assert.AreEqual('', mFault.ModuleName);
end;

procedure TAtlasDebugModulesTests.FindsModuleByAddress;
begin
  Assert.AreEqual(0, TAtlasDebugModuleMap.IndexOfAddress(Modules, $0040ABCD));
  Assert.AreEqual(1, TAtlasDebugModuleMap.IndexOfAddress(Modules, $503FFFFF), 'letztes Byte gehört dazu');
  Assert.AreEqual(-1, TAtlasDebugModuleMap.IndexOfAddress(Modules, $50400000), 'erstes Byte dahinter nicht');
  Assert.AreEqual(-1, TAtlasDebugModuleMap.IndexOfAddress(Modules, $1C));
end;

procedure TAtlasDebugModulesTests.FindsModuleByName;
begin
  Assert.AreEqual(2, TAtlasDebugModuleMap.IndexOfName(Modules, 'kernelbase.dll'));
  Assert.AreEqual(2, TAtlasDebugModuleMap.IndexOfName(Modules, 'KERNELBASE'), 'ohne Endung');
  Assert.AreEqual(-1, TAtlasDebugModuleMap.IndexOfName(Modules, 'kernelbase.exe'), 'andere Endung');
  Assert.AreEqual(-1, TAtlasDebugModuleMap.IndexOfName(Modules, ''));
end;

procedure TAtlasDebugModulesTests.FindsModuleByHeader;
begin
  Assert.AreEqual(2, TAtlasDebugModuleMap.IndexOfHeader(Modules, ':7714C3E2 KERNELBASE.RaiseException + 0x62'));
  Assert.AreEqual(3, TAtlasDebugModuleMap.IndexOfHeader(Modules, ':10001234 Fremd.dll'));
  Assert.AreEqual(-1, TAtlasDebugModuleMap.IndexOfHeader(Modules, 'Unit1.TForm1.Button1Click(Self=$02A3F2C0)'),
    'Rahmen mit Symbolen nennen kein Modul');
  Assert.AreEqual(-1, TAtlasDebugModuleMap.IndexOfHeader(Modules, ':50001000 Vcl.Controls.TControl.Perform'),
    'Unit-Namen sind keine Module');
end;

procedure TAtlasDebugModulesTests.RecognizesRuntimePackages;
begin
  Assert.IsTrue(TAtlasDebugModuleMap.IsRuntimePackageName('vcl290.bpl'));
  Assert.IsTrue(TAtlasDebugModuleMap.IsRuntimePackageName('C:\App\vclwinx370.bpl'));
  Assert.IsTrue(TAtlasDebugModuleMap.IsRuntimePackageName('RTL370.BPL'));
  Assert.IsFalse(TAtlasDebugModuleMap.IsRuntimePackageName('vcl290.dll'), 'nur Pakete');
  Assert.IsFalse(TAtlasDebugModuleMap.IsRuntimePackageName('vclMeineKomponenten.bpl'), 'ohne Paketversion');
  Assert.IsFalse(TAtlasDebugModuleMap.IsRuntimePackageName('Kunde290.bpl'));
  Assert.IsTrue(TAtlasDebugModuleMap.IsSystemName('NTDLL.DLL'));
  Assert.IsFalse(TAtlasDebugModuleMap.IsSystemName('Fremd.dll'));
end;

procedure TAtlasDebugModulesTests.ClassifiesModules;
var
  mModules: TAtlasDebugModuleList;
begin
  mModules := Modules;
  Assert.AreEqual(Ord(TAtlasDebugModuleKind.ProgramFile), Ord(TAtlasDebugModuleMap.Classify(mModules[0], Environment)));
  Assert.AreEqual(Ord(TAtlasDebugModuleKind.Runtime), Ord(TAtlasDebugModuleMap.Classify(mModules[1], Environment)));
  Assert.AreEqual(Ord(TAtlasDebugModuleKind.OperatingSystem),
    Ord(TAtlasDebugModuleMap.Classify(mModules[2], Environment)));
  Assert.AreEqual(Ord(TAtlasDebugModuleKind.Foreign), Ord(TAtlasDebugModuleMap.Classify(mModules[3], Environment)));
  Assert.AreEqual(Ord(TAtlasDebugModuleKind.Runtime), Ord(TAtlasDebugModuleMap.Classify(
    TAtlasDebugLoadedModule.Create('C:\Projekte\Demo\Win32\Debug\rtl370.bpl', 0, 0), Environment)),
    'mitgeliefertes Laufzeitpaket neben dem Programm');
  Assert.AreEqual(Ord(TAtlasDebugModuleKind.Unknown), Ord(TAtlasDebugModuleMap.Classify(
    Default(TAtlasDebugLoadedModule), Environment)));
end;

procedure TAtlasDebugModulesTests.ResolvesOwnProgram;
var
  mFrames: TAtlasDebugFrames;
  mResult: TAtlasDebugFaultModule;
begin
  mFrames := [TAtlasDebugFrame.Create('Unit1.TForm1.Button1Click(Self=$02A3F2C0)', 'C:\Projekte\Demo\Unit1.pas', 42)];
  mFrames[0].Own := True;
  mResult := TAtlasDebugModuleMap.Resolve(
    'Zugriffsverletzung bei Adresse 0040ABCD in Modul ''Demo.exe''. Lesen von Adresse 0000001C.', mFrames, Modules,
    Environment);
  Assert.IsTrue(mResult.Known);
  Assert.AreEqual('Demo.exe', mResult.Name);
  Assert.AreEqual(Ord(TAtlasDebugModuleKind.ProgramFile), Ord(mResult.Kind));
  Assert.IsFalse(mResult.NoDebugInfo);
  Assert.AreEqual(0, mResult.OwnFrame);
end;

procedure TAtlasDebugModulesTests.ResolvesVclWithLastOwnFrame;
var
  mFrames: TAtlasDebugFrames;
  mResult: TAtlasDebugFaultModule;
begin
  mFrames := [TAtlasDebugFrame.Create(':50001000 Vcl.Controls.TControl.GetText', '', 0),
    TAtlasDebugFrame.Create('Vcl.Controls.TControl.Perform', 'Vcl.Controls.pas', 0),
    TAtlasDebugFrame.Create('Unit1.TForm1.Button1Click(Self=$02A3F2C0)', 'C:\Projekte\Demo\Unit1.pas', 42),
    TAtlasDebugFrame.Create('Unit1.TForm1.Run', 'C:\Projekte\Demo\Unit1.pas', 30)];
  mFrames[2].Own := True;
  mFrames[3].Own := True;
  mResult := TAtlasDebugModuleMap.Resolve(
    'Access violation at address 50001000 in module ''vcl370.bpl''. Read of address 0000001C.', mFrames, Modules,
    Environment);
  Assert.AreEqual('vcl370.bpl', mResult.Name);
  Assert.AreEqual(Ord(TAtlasDebugModuleKind.Runtime), Ord(mResult.Kind));
  Assert.IsFalse(mResult.NoDebugInfo, 'RTL/VCL heißt nicht „keine Debug-Infos“');
  Assert.AreEqual(2, mResult.OwnFrame, 'zuletzt durchlaufene eigene Stelle');
end;

procedure TAtlasDebugModulesTests.ResolvesForeignDllWithoutDebugInfo;
var
  mFrames: TAtlasDebugFrames;
  mResult: TAtlasDebugFaultModule;
begin
  mFrames := [TAtlasDebugFrame.Create(':10001234 Fremd.dll', '', 0)];
  mResult := TAtlasDebugModuleMap.Resolve('access violation at 0x10001234: read of address 0x00000000', mFrames,
    Modules, Environment);
  Assert.AreEqual('Fremd.dll', mResult.Name);
  Assert.AreEqual('C:\Projekte\Demo\Win32\Debug\Fremd.dll', mResult.FileName);
  Assert.AreEqual(Ord(TAtlasDebugModuleKind.Foreign), Ord(mResult.Kind));
  Assert.IsTrue(mResult.NoDebugInfo);
  Assert.AreEqual(-1, mResult.OwnFrame);
end;

procedure TAtlasDebugModulesTests.ResolvesLoadedLibraryByAddress;
var
  mModules: TAtlasDebugModuleList;
  mResult: TAtlasDebugFaultModule;
begin
  // Mit LoadLibrary nachgeladen: steht in der beim Halt gelesenen Liste, die Meldung nennt kein Modul.
  mModules := Modules + [TAtlasDebugLoadedModule.Create('D:\Plugins\Nachgeladen.dll', $20000000, $1000)];
  mResult := TAtlasDebugModuleMap.Resolve('access violation at 0x20000010: write of address 0x00000004', nil,
    mModules, Environment);
  Assert.AreEqual('Nachgeladen.dll', mResult.Name);
  Assert.AreEqual(Ord(TAtlasDebugModuleKind.Foreign), Ord(mResult.Kind));
  Assert.IsTrue(mResult.NoDebugInfo, 'ohne Stapel kein Quelltext');
end;

procedure TAtlasDebugModulesTests.ResolvesNameOnlyWithoutModuleList;
var
  mResult: TAtlasDebugFaultModule;
begin
  // Liste nicht lesbar (32-Bit-IDE und 64-Bit-Programm): der Name aus der Meldung genügt.
  mResult := TAtlasDebugModuleMap.Resolve(
    'Access violation at address 00007FFA12345678 in module ''vcl370.bpl''. Read of address 0000000000000008.', nil,
    nil, Environment);
  Assert.IsTrue(mResult.Known);
  Assert.AreEqual('vcl370.bpl', mResult.Name);
  Assert.AreEqual('', mResult.FileName);
  Assert.AreEqual(Ord(TAtlasDebugModuleKind.Runtime), Ord(mResult.Kind));
  mResult := TAtlasDebugModuleMap.Resolve(
    'Access violation at address 00412345 in module ''Demo.exe''. Read of address 00000008.', nil, nil, Environment);
  Assert.AreEqual(Ord(TAtlasDebugModuleKind.ProgramFile), Ord(mResult.Kind));
end;

procedure TAtlasDebugModulesTests.ResolvesNothingWithoutHints;
var
  mResult: TAtlasDebugFaultModule;
begin
  mResult := TAtlasDebugModuleMap.Resolve('access violation at 0x7FFE0000: read of address 0x00000000', nil, Modules,
    Environment);
  Assert.IsFalse(mResult.Known);
  Assert.AreEqual(Ord(TAtlasDebugModuleKind.Unknown), Ord(mResult.Kind));
end;

end.
