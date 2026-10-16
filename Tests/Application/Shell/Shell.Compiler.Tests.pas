unit Shell.Compiler.Tests;

// Tests für Kompilieren ohne Kommandozeilen-Compiler im Server (#261): Erkennen
// der Ausgabe mit Zwischenspeicher und die eigene IDE über cc.ps1. Prozesse,
// laufende IDEs und das logFile sind nachgestellt; die IDE des Benutzers
// (eine schon vorher laufende pid) wird nie angesprochen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TShellCompilerTests = class
  private
    FFolder: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ProbesOnceAndRemembersPerInstallation;
    [Test]
    procedure MissingCompilerNeedsNoProbe;
    [Test]
    procedure SilentProbeIsNotRemembered;
    [Test]
    procedure RemembersLicenseTextOfARealRun;
    [Test]
    procedure BuildsInOwnIdeAndReusesIt;
    [Test]
    procedure NeverBuildsInTheUsersIde;
    [Test]
    procedure StartsNewIdeWhenTheOldOneIsGone;
    [Test]
    procedure QuitEndsOwnIde;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Generics.Collections,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Compiler.Edition,
  Shell.Compiler;

type
  TFakeAnswer = reference to function(const ARequest: TCompilerRequest; out AOutput: TArray<string>): Integer;

  TFakeProcess = class(TInterfacedObject, ICompilerProcess)
  private
    FAnswer: TFakeAnswer;
    FCalls: TList<string>;
  public
    constructor Create(const AAnswer: TFakeAnswer);
    destructor Destroy; override;
    function Run(const ARequest: TCompilerRequest; const AOnLine: TCompilerLineEvent): Integer;
    procedure Cancel;
    property Calls: TList<string> read FCalls;
  end;

  TSilentLogger = class(TInterfacedObject, ILogger)
  public
    procedure Log(ALevel: TLogLevel; const AText: string);
    procedure Debug(const AText: string);
    procedure Info(const AText: string);
    procedure Warning(const AText: string);
    procedure Error(const AText: string);
  end;

constructor TFakeProcess.Create(const AAnswer: TFakeAnswer);
begin
  inherited Create;
  FAnswer := AAnswer;
  FCalls := TList<string>.Create;
end;

destructor TFakeProcess.Destroy;
begin
  FCalls.Free;
  inherited;
end;

function TFakeProcess.Run(const ARequest: TCompilerRequest; const AOnLine: TCompilerLineEvent): Integer;
var
  Output: TArray<string>;
  Line: string;
begin
  FCalls.Add(Trim(ExtractFileName(ARequest.Executable) + ' ' + string.Join(' ', ARequest.Arguments)));
  Output := nil;
  Result := FAnswer(ARequest, Output);
  for Line in Output do
    AOnLine(Line);
end;

procedure TFakeProcess.Cancel;
begin
end;

procedure TSilentLogger.Log(ALevel: TLogLevel; const AText: string);
begin
end;

procedure TSilentLogger.Debug(const AText: string);
begin
end;

procedure TSilentLogger.Info(const AText: string);
begin
end;

procedure TSilentLogger.Warning(const AText: string);
begin
end;

procedure TSilentLogger.Error(const AText: string);
begin
end;

/// <summary>Als Funktionsergebnis: nie ein frisches Objekt an einen const-Interface-Parameter.</summary>
function Silent: ILogger;
begin
  Result := TSilentLogger.Create;
end;

procedure TShellCompilerTests.Setup;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'Atlas-ShellCompiler-' + IntToStr(Random(MaxInt)));
  ForceDirectories(TPath.Combine(FFolder, 'bin'));
  TFile.WriteAllText(TPath.Combine(FFolder, TPath.Combine('bin', 'dcc32.exe')), 'kein Programm');
end;

procedure TShellCompilerTests.TearDown;
begin
  if TDirectory.Exists(FFolder) then
    TDirectory.Delete(FFolder, True);
  // Der Leckmonitor misst den Saldo von Setup und TearDown.
  FFolder := '';
end;

function StarterAnswer(const ARequest: TCompilerRequest; out AOutput: TArray<string>): Integer;
begin
  AOutput := TArray<string>.Create('Embarcadero Delphi for Win32 compiler version 37.0',
    'This version of the product does not support command line compiling.');
  Result := 1;
end;

procedure TShellCompilerTests.ProbesOnceAndRemembersPerInstallation;
var
  Process: TFakeProcess;
  Keep: ICompilerProcess;
  Editions, Again: TShellCompilerEditions;
  CacheFile, Exe: string;
begin
  Process := TFakeProcess.Create(StarterAnswer);
  Keep := Process;
  CacheFile := TPath.Combine(FFolder, 'compiler-editions.json');
  Exe := TPath.Combine(FFolder, TPath.Combine('bin', 'dcc32.exe'));
  Editions := TShellCompilerEditions.Create(Keep, Silent, CacheFile);
  try
    Assert.AreEqual(Ord(TCompilerEdition.NoCommandLine), Ord(Editions.Resolve(FFolder, '37.0', Exe)));
    Assert.AreEqual(Ord(TCompilerEdition.NoCommandLine), Ord(Editions.Resolve(FFolder, '37.0', Exe)));
    Assert.AreEqual(1, Integer(Process.Calls.Count), 'nur ein Probelauf');
    Assert.AreEqual('dcc32.exe', Process.Calls[0], 'ohne Argumente');
  finally
    Editions.Free;
  end;
  Assert.IsTrue(TFile.Exists(CacheFile), 'gemerkt');
  // Neuer Server: aus der Datei, ohne Probelauf.
  Again := TShellCompilerEditions.Create(Keep, Silent, CacheFile);
  try
    Assert.AreEqual(Ord(TCompilerEdition.NoCommandLine), Ord(Again.Resolve(FFolder, '37.0', Exe)));
    Assert.AreEqual(1, Integer(Process.Calls.Count));
  finally
    Again.Free;
  end;
end;

procedure TShellCompilerTests.MissingCompilerNeedsNoProbe;
var
  Process: TFakeProcess;
  Keep: ICompilerProcess;
  Editions: TShellCompilerEditions;
begin
  Process := TFakeProcess.Create(StarterAnswer);
  Keep := Process;
  Editions := TShellCompilerEditions.Create(Keep, Silent, '');
  try
    Assert.AreEqual(Ord(TCompilerEdition.Missing), Ord(Editions.Resolve(FFolder, '37.0',
      TPath.Combine(FFolder, TPath.Combine('bin', 'dcc64.exe')))));
    Assert.AreEqual(0, Integer(Process.Calls.Count));
  finally
    Editions.Free;
  end;
end;

procedure TShellCompilerTests.SilentProbeIsNotRemembered;
var
  Process: TFakeProcess;
  Keep: ICompilerProcess;
  Editions: TShellCompilerEditions;
  Exe: string;
begin
  Process := TFakeProcess.Create(
    function(const ARequest: TCompilerRequest; out AOutput: TArray<string>): Integer
    begin
      AOutput := nil;
      Result := 0;
    end);
  Keep := Process;
  Exe := TPath.Combine(FFolder, TPath.Combine('bin', 'dcc32.exe'));
  Editions := TShellCompilerEditions.Create(Keep, Silent, '');
  try
    Assert.AreEqual(Ord(TCompilerEdition.Unknown), Ord(Editions.Resolve(FFolder, '37.0', Exe)));
    Assert.AreEqual(Ord(TCompilerEdition.Unknown), Ord(Editions.Resolve(FFolder, '37.0', Exe)));
    Assert.AreEqual(2, Integer(Process.Calls.Count), 'unklar: beim nächsten Mal erneut prüfen');
  finally
    Editions.Free;
  end;
end;

procedure TShellCompilerTests.RemembersLicenseTextOfARealRun;
var
  Process: TFakeProcess;
  Keep: ICompilerProcess;
  Editions: TShellCompilerEditions;
  Exe: string;
begin
  Process := TFakeProcess.Create(
    function(const ARequest: TCompilerRequest; out AOutput: TArray<string>): Integer
    begin
      AOutput := TArray<string>.Create('Syntax: dcc32 [options] filename');
      Result := 0;
    end);
  Keep := Process;
  Exe := TPath.Combine(FFolder, TPath.Combine('bin', 'dcc32.exe'));
  Editions := TShellCompilerEditions.Create(Keep, Silent, '');
  try
    Assert.AreEqual(Ord(TCompilerEdition.CommandLine), Ord(Editions.Resolve(FFolder, '37.0', Exe)));
    Editions.Remember(FFolder, '37.0', Exe, TCompilerEdition.NoCommandLine);
    Assert.AreEqual(Ord(TCompilerEdition.NoCommandLine), Ord(Editions.Resolve(FFolder, '37.0', Exe)));
    Assert.AreEqual(1, Integer(Process.Calls.Count));
  finally
    Editions.Free;
  end;
end;

/// <summary>cc.ps1 nachgestellt: start nennt APid, build antwortet mit logFile ALog.</summary>
function CcScript(APid: Cardinal; const ALog: string): TFakeAnswer;
begin
  Result :=
    function(const ARequest: TCompilerRequest; out AOutput: TArray<string>): Integer
    var
      Command: string;
    begin
      Command := '';
      if Length(ARequest.Arguments) > 6 then
        Command := ARequest.Arguments[6];
      AOutput := nil;
      Result := 0;
      if Command = 'start' then
        AOutput := TArray<string>.Create('IDE started : pid ' + IntToStr(APid))
      else if Command = 'build' then
        AOutput := TArray<string>.Create('{"ok": false, "outputWritten": false, "logFile": "' +
          StringReplace(ALog, '\', '\\', [rfReplaceAll]) + '"}');
    end;
end;

function Compiler(AProcess: TFakeProcess; const AIdes: TArray<Cardinal>; const ARunning: TList<Cardinal>):
  TShellIdeCompiler;
begin
  Result := TShellIdeCompiler.Create(AProcess, Silent, 'pwsh.exe',
    function: TArray<Cardinal>
    begin
      Result := AIdes;
    end,
    function(APid: Cardinal): Boolean
    begin
      Result := ARunning.Contains(APid);
    end,
    function(const AFileName: string): TArray<string>
    begin
      Result := TArray<string>.Create('[dcc32 Fehler] Main.pas(3): E2003 Undeklarierter Bezeichner: ''Foo''');
    end);
end;

procedure TShellCompilerTests.BuildsInOwnIdeAndReusesIt;
var
  Process: TFakeProcess;
  Keep: ICompilerProcess;
  Running: TList<Cardinal>;
  Ide: TShellIdeCompiler;
  Messages: TArray<TCompilerMessage>;
  Succeeded: Boolean;
  Error: string;
begin
  Process := TFakeProcess.Create(CcScript(900, 'C:\Temp\build.log'));
  Keep := Process;
  Running := TList<Cardinal>.Create;
  Ide := Compiler(Process, TArray<Cardinal>.Create(100), Running);
  try
    Running.Add(100);
    Running.Add(900);
    Assert.IsTrue(Ide.Build('C:\T\cc.ps1', 'C:\P\App.dproj', 'Win32', Messages, Succeeded, Error), Error);
    Assert.AreEqual(Cardinal(900), Ide.Pid);
    Assert.IsFalse(Succeeded);
    Assert.AreEqual(1, Integer(Length(Messages)));
    Assert.AreEqual('C:\P\Main.pas', Messages[0].FileName);
    Assert.AreEqual('E2003', Messages[0].Code);
    Assert.IsTrue(Ide.Build('C:\T\cc.ps1', 'C:\P\App.dproj', 'Win32', Messages, Succeeded, Error), Error);
    Assert.AreEqual(3, Integer(Process.Calls.Count), 'einmal start, zweimal build');
    Assert.IsTrue(Process.Calls[0].EndsWith('cc.ps1 start -Project C:\P\App.dproj -TimeoutSec 180'), Process.Calls[0]);
    Assert.IsTrue(Process.Calls[2].EndsWith('build -Instance 900 -Project C:\P\App.dproj -Platform Win32 -Json'),
      Process.Calls[2]);
  finally
    Ide.Free;
    Running.Free;
  end;
end;

procedure TShellCompilerTests.NeverBuildsInTheUsersIde;
var
  Process: TFakeProcess;
  Keep: ICompilerProcess;
  Running: TList<Cardinal>;
  Ide: TShellIdeCompiler;
  Messages: TArray<TCompilerMessage>;
  Succeeded: Boolean;
  Error, Call: string;
begin
  // cc.ps1 nennt die pid einer IDE, die schon vorher lief (die des Benutzers): kein build.
  Process := TFakeProcess.Create(CcScript(100, 'C:\Temp\build.log'));
  Keep := Process;
  Running := TList<Cardinal>.Create;
  Ide := Compiler(Process, TArray<Cardinal>.Create(100), Running);
  try
    Running.Add(100);
    Assert.IsFalse(Ide.Build('C:\T\cc.ps1', 'C:\P\App.dproj', '', Messages, Succeeded, Error));
    Assert.IsTrue(Pos('eigenen IDE', Error) > 0, Error);
    Assert.AreEqual(Cardinal(0), Ide.Pid);
    for Call in Process.Calls do
      Assert.IsFalse(Pos(' build ', ' ' + Call + ' ') > 0, Call);
  finally
    Ide.Free;
    Running.Free;
  end;
end;

procedure TShellCompilerTests.StartsNewIdeWhenTheOldOneIsGone;
var
  Process: TFakeProcess;
  Keep: ICompilerProcess;
  Running: TList<Cardinal>;
  Ide: TShellIdeCompiler;
  Messages: TArray<TCompilerMessage>;
  Succeeded: Boolean;
  Error: string;
begin
  Process := TFakeProcess.Create(CcScript(900, ''));
  Keep := Process;
  Running := TList<Cardinal>.Create;
  Ide := Compiler(Process, nil, Running);
  try
    Running.Add(900);
    Assert.IsTrue(Ide.Build('C:\T\cc.ps1', 'C:\P\App.dproj', '', Messages, Succeeded, Error), Error);
    Process.Calls.Clear;
    Assert.IsTrue(Ide.Build('C:\T\cc.ps1', 'C:\P\App.dproj', '', Messages, Succeeded, Error), Error);
    Assert.AreEqual(1, Integer(Process.Calls.Count), 'läuft noch: kein neuer Start');
    // Die eigene IDE ist beendet: neue Instanz.
    Running.Clear;
    Process.Calls.Clear;
    Assert.IsTrue(Ide.Build('C:\T\cc.ps1', 'C:\P\App.dproj', '', Messages, Succeeded, Error), Error);
    Assert.IsTrue(Process.Calls[0].Contains(' start '), Process.Calls[0]);
  finally
    Ide.Free;
    Running.Free;
  end;
end;

procedure TShellCompilerTests.QuitEndsOwnIde;
var
  Process: TFakeProcess;
  Keep: ICompilerProcess;
  Running: TList<Cardinal>;
  Ide: TShellIdeCompiler;
  Messages: TArray<TCompilerMessage>;
  Succeeded: Boolean;
  Error: string;
begin
  Process := TFakeProcess.Create(CcScript(900, ''));
  Keep := Process;
  Running := TList<Cardinal>.Create;
  Ide := Compiler(Process, nil, Running);
  try
    Running.Add(900);
    Assert.IsTrue(Ide.Build('C:\T\cc.ps1', 'C:\P\App.dproj', '', Messages, Succeeded, Error), Error);
    Process.Calls.Clear;
    Ide.Quit(Keep);
    Assert.AreEqual(1, Integer(Process.Calls.Count));
    Assert.IsTrue(Process.Calls[0].EndsWith('cc.ps1 quit -Instance 900'), Process.Calls[0]);
    Assert.AreEqual(Cardinal(0), Ide.Pid);
    Ide.Quit(Keep);
    Assert.AreEqual(1, Integer(Process.Calls.Count), 'ohne eigene IDE nichts zu tun');
  finally
    Ide.Free;
    Running.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TShellCompilerTests);

end.
