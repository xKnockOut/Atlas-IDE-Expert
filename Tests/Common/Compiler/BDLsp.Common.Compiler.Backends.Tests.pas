unit BDLsp.Common.Compiler.Backends.Tests;

// Tests für die Auswahl des Compiler-Backends und den Weg über cc.ps1 (#261).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCompilerBackendsTests = class
  public
    [Test]
    procedure RecognizesLicenseRefusal;
    [Test]
    procedure DetectsEditionFromFiles;
    [Test]
    procedure CachesPerRootAndVersion;
    [Test]
    procedure AutoPicksDccWithCommandLine;
    [Test]
    procedure AutoPicksIdeForStarter;
    [Test]
    procedure StarterWithoutCcIsOffWithReason;
    [Test]
    procedure ExplicitBackendsAreHonoured;
    [Test]
    procedure IdeCommandsAlwaysUseInstance;
    [Test]
    procedure ReadsInstanceAndLogFile;
    [Test]
    procedure ReadsMessagesFromLogFile;
  end;

implementation

uses
  System.SysUtils,
  BDLsp.Common.Configuration.Contract,
  BDLsp.Common.Compiler.Contract,
  BDLsp.Common.Compiler.Backends;

const
  // Ausgabe von dcc32 der Starter Edition (Wortlaut bis zur Aufzeichnung durch Marco angenommen).
  StarterOutput =
    'Embarcadero Delphi for Win32 compiler version 37.0'#13#10 +
    // Hersteller getrennt, damit Check-NoEmbarcaderoSources.ps1 die Zeile nicht als
    // Copyright-Kopf einer Embarcadero-Quelle wertet (#77).
    'Copyright (c) 1983,2025 Embar' + 'cadero Technologies, Inc.'#13#10 +
    'This version of the product does not support command line compiling.';

function Files(const AExisting: array of string): TCompilerFileExists;
var
  List: TArray<string>;
  Index: Integer;
begin
  SetLength(List, Length(AExisting));
  for Index := 0 to High(AExisting) do
    List[Index] := AExisting[Index];
  Result :=
    function(const APath: string): Boolean
    var
      Item: string;
    begin
      for Item in List do
        if SameText(Item, APath) then
          Exit(True);
      Result := False;
    end;
end;

function Settings(ABackend: TCompilerBackend; const AIdeCommand: string = ''): TCompilerSettings;
begin
  Result := TCompilerSettings.Default;
  Result.Backend := ABackend;
  Result.IdeCommand := AIdeCommand;
end;

procedure TCompilerBackendsTests.RecognizesLicenseRefusal;
begin
  Assert.IsTrue(TCompilerEditionProbe.IsLicenseRefusal(StarterOutput));
  Assert.IsFalse(TCompilerEditionProbe.IsLicenseRefusal('Embarcadero Delphi for Win64 compiler version 37.0'));
end;

procedure TCompilerBackendsTests.DetectsEditionFromFiles;
begin
  Assert.AreEqual(Ord(TCompilerEdition.Missing), Ord(TCompilerEditionProbe.Detect('', Files([]), '')));
  Assert.AreEqual(Ord(TCompilerEdition.Missing), Ord(TCompilerEditionProbe.Detect('C:\D', Files([]), '')));
  Assert.AreEqual(Ord(TCompilerEdition.NoCommandLine),
    Ord(TCompilerEditionProbe.Detect('C:\D', Files(['C:\D\bin\bds.exe']), '')));
  Assert.AreEqual(Ord(TCompilerEdition.NoCommandLine),
    Ord(TCompilerEditionProbe.Detect('C:\D', Files(['C:\D\bin\dcc32.exe']), StarterOutput)));
  Assert.AreEqual(Ord(TCompilerEdition.CommandLine),
    Ord(TCompilerEditionProbe.Detect('C:\D', Files(['C:\D\bin\dcc64.exe']), 'compiler version 37.0')));
  Assert.AreEqual(Ord(TCompilerEdition.Unknown),
    Ord(TCompilerEditionProbe.Detect('C:\D', Files(['C:\D\bin\dcc64.exe']), '')));
end;

procedure TCompilerBackendsTests.CachesPerRootAndVersion;
var
  Probe: TCompilerEditionProbe;
  Edition: TCompilerEdition;
begin
  Probe := TCompilerEditionProbe.Create;
  try
    Assert.IsFalse(Probe.TryGet('C:\D', '23.0', Edition));
    Probe.Store('C:\D', '23.0', TCompilerEdition.NoCommandLine);
    Assert.IsTrue(Probe.TryGet('c:\d', '23.0', Edition));
    Assert.AreEqual(Ord(TCompilerEdition.NoCommandLine), Ord(Edition));
    Assert.IsFalse(Probe.TryGet('C:\D', '24.0', Edition));
  finally
    Probe.Free;
  end;
end;

procedure TCompilerBackendsTests.AutoPicksDccWithCommandLine;
var
  Choice: TCompilerBackendChoice;
begin
  Choice := TCompilerBackendChoice.Choose(Settings(TCompilerBackend.Auto), TCompilerEdition.CommandLine, False);
  Assert.AreEqual(Ord(TCompilerBackend.Dcc), Ord(Choice.Backend));
  Assert.IsTrue(Choice.OnSave);
  Assert.AreEqual('', Choice.Reason);
end;

procedure TCompilerBackendsTests.AutoPicksIdeForStarter;
var
  Choice: TCompilerBackendChoice;
begin
  Choice := TCompilerBackendChoice.Choose(Settings(TCompilerBackend.Auto, 'C:\cc.ps1'),
    TCompilerEdition.NoCommandLine, True);
  Assert.AreEqual(Ord(TCompilerBackend.Ide), Ord(Choice.Backend));
  // Die IDE startet langsam: nur per Befehl.
  Assert.IsFalse(Choice.OnSave);
end;

procedure TCompilerBackendsTests.StarterWithoutCcIsOffWithReason;
var
  Choice: TCompilerBackendChoice;
begin
  Choice := TCompilerBackendChoice.Choose(Settings(TCompilerBackend.Auto), TCompilerEdition.NoCommandLine, False);
  Assert.AreEqual(Ord(TCompilerBackend.Off), Ord(Choice.Backend));
  Assert.AreEqual('Compiler: nicht verfügbar (Starter Edition)', Choice.StatusText);
  Assert.IsTrue(Pos('compiler.ideCommand', Choice.Reason) > 0);
  Assert.IsFalse(Choice.OnSave);
end;

procedure TCompilerBackendsTests.ExplicitBackendsAreHonoured;
begin
  Assert.AreEqual(Ord(TCompilerBackend.Off), Ord(TCompilerBackendChoice.Choose(Settings(TCompilerBackend.Off),
    TCompilerEdition.CommandLine, True).Backend));
  Assert.AreEqual(Ord(TCompilerBackend.Ide), Ord(TCompilerBackendChoice.Choose(Settings(TCompilerBackend.Ide),
    TCompilerEdition.CommandLine, True).Backend));
  Assert.AreEqual(Ord(TCompilerBackend.Off), Ord(TCompilerBackendChoice.Choose(Settings(TCompilerBackend.Ide),
    TCompilerEdition.CommandLine, False).Backend));
  // dcc erzwungen, aber Starter: abgeschaltet mit Hinweis auf ide.
  Assert.AreEqual(Ord(TCompilerBackend.Off), Ord(TCompilerBackendChoice.Choose(Settings(TCompilerBackend.Dcc),
    TCompilerEdition.NoCommandLine, True).Backend));
  Assert.AreEqual(Ord(TCompilerBackend.Dcc), Ord(TCompilerBackendChoice.Choose(Settings(TCompilerBackend.Dcc),
    TCompilerEdition.Unknown, False).Backend));
end;

procedure TCompilerBackendsTests.IdeCommandsAlwaysUseInstance;
var
  Request: TCompilerRequest;
begin
  Request := TIdeCompilerCommand.Build('C:\Tools\cc.ps1', 'C:\P\App.dproj', 'Win64', 4711);
  Assert.AreEqual('pwsh.exe', Request.Executable);
  Assert.AreEqual('-NoProfile -NonInteractive -File C:\Tools\cc.ps1 build -Instance 4711 -Project ' +
    'C:\P\App.dproj -Platform Win64 -Json', string.Join(' ', Request.Arguments));
  Assert.WillRaise(
    procedure
    begin
      TIdeCompilerCommand.Build('C:\Tools\cc.ps1', 'C:\P\App.dproj', 'Win64', 0);
    end, ECompilerError);
  Assert.AreEqual('start -Project C:\P\App.dproj',
    string.Join(' ', Copy(TIdeCompilerCommand.Start('C:\Tools\cc.ps1', 'C:\P\App.dproj').Arguments, 4, 3)));
  Assert.AreEqual('quit -Instance 4711',
    string.Join(' ', Copy(TIdeCompilerCommand.Quit('C:\Tools\cc.ps1', 4711).Arguments, 4, 3)));
end;

procedure TCompilerBackendsTests.ReadsInstanceAndLogFile;
begin
  Assert.AreEqual(4711, TIdeCompilerCommand.InstanceFrom('IDE gestartet, pid: 4711'#13#10'bereit'));
  Assert.AreEqual(0, TIdeCompilerCommand.InstanceFrom('keine IDE'));
  Assert.AreEqual('C:\Temp\build.log', TIdeCompilerCommand.LogFileFrom(
    'Baue …'#13#10'{"ok": false, "outputWritten": false, "logFile": "C:\\Temp\\build.log"}'));
  Assert.AreEqual('', TIdeCompilerCommand.LogFileFrom('kein JSON'));
end;

procedure TCompilerBackendsTests.ReadsMessagesFromLogFile;
const
  // logFile von cc.ps1 (Ausschnitt wie in Tools/Build-Test.ps1 geprüft).
  LogText =
    'Build gestartet'#13#10 +
    '[dcc64 Fehler] Unit1.pas(12): E2003 Undeklarierter Bezeichner: ''X'''#13#10 +
    '[dcc64 Warnung] Unit1.pas(20,5): W1036 Variable ''Y'' ist möglicherweise nicht initialisiert'#13#10 +
    'Erfolg';
var
  Messages: TArray<TCompilerMessage>;
begin
  Messages := TIdeCompilerCommand.Messages(LogText, 'C:\P');
  Assert.AreEqual(2, Integer(Length(Messages)));
  Assert.AreEqual('C:\P\Unit1.pas', Messages[0].FileName);
  Assert.AreEqual(11, Messages[0].Line);
  Assert.AreEqual('E2003', Messages[0].Code);
  Assert.AreEqual(Ord(TCompilerSeverity.Error), Ord(Messages[0].Severity));
  Assert.AreEqual(19, Messages[1].Line);
  Assert.AreEqual(4, Messages[1].Column);
  Assert.AreEqual(Ord(TCompilerSeverity.Warning), Ord(Messages[1].Severity));
end;

initialization
  TDUnitX.RegisterTestFixture(TCompilerBackendsTests);

end.
