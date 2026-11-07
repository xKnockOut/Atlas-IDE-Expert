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
  mOutput: TArray<string>;
  mLine: string;
begin
  FCalls.Add(Trim(ExtractFileName(ARequest.Executable) + ' ' + string.Join(' ', ARequest.Arguments)));
  mOutput := nil;
  Result := FAnswer(ARequest, mOutput);
  for mLine in mOutput do
  begin
    AOnLine(mLine);
  end;
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
  begin
    TDirectory.Delete(FFolder, True);
  end;
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
  mProcess: TFakeProcess;
  mKeep: ICompilerProcess;
  mEditions, mAgain: TShellCompilerEditions;
  mCacheFile, mExe: string;
begin
  mProcess := TFakeProcess.Create(StarterAnswer);
  mKeep := mProcess;
  mCacheFile := TPath.Combine(FFolder, 'compiler-editions.json');
  mExe := TPath.Combine(FFolder, TPath.Combine('bin', 'dcc32.exe'));
  mEditions := TShellCompilerEditions.Create(mKeep, Silent, mCacheFile);
  try
    Assert.AreEqual(Ord(TCompilerEdition.NoCommandLine), Ord(mEditions.Resolve(FFolder, '37.0', mExe)));
    Assert.AreEqual(Ord(TCompilerEdition.NoCommandLine), Ord(mEditions.Resolve(FFolder, '37.0', mExe)));
    Assert.AreEqual(1, Integer(mProcess.Calls.Count), 'nur ein Probelauf');
    Assert.AreEqual('dcc32.exe', mProcess.Calls[0], 'ohne Argumente');
  finally
    mEditions.Free;
  end;
  Assert.IsTrue(TFile.Exists(mCacheFile), 'gemerkt');
  // Neuer Server: aus der Datei, ohne Probelauf.
  mAgain := TShellCompilerEditions.Create(mKeep, Silent, mCacheFile);
  try
    Assert.AreEqual(Ord(TCompilerEdition.NoCommandLine), Ord(mAgain.Resolve(FFolder, '37.0', mExe)));
    Assert.AreEqual(1, Integer(mProcess.Calls.Count));
  finally
    mAgain.Free;
  end;
end;

procedure TShellCompilerTests.MissingCompilerNeedsNoProbe;
var
  mProcess: TFakeProcess;
  mKeep: ICompilerProcess;
  mEditions: TShellCompilerEditions;
begin
  mProcess := TFakeProcess.Create(StarterAnswer);
  mKeep := mProcess;
  mEditions := TShellCompilerEditions.Create(mKeep, Silent, '');
  try
    Assert.AreEqual(Ord(TCompilerEdition.Missing), Ord(mEditions.Resolve(FFolder, '37.0',
      TPath.Combine(FFolder, TPath.Combine('bin', 'dcc64.exe')))));
    Assert.AreEqual(0, Integer(mProcess.Calls.Count));
  finally
    mEditions.Free;
  end;
end;

procedure TShellCompilerTests.SilentProbeIsNotRemembered;
var
  mProcess: TFakeProcess;
  mKeep: ICompilerProcess;
  mEditions: TShellCompilerEditions;
  mExe: string;
begin
  mProcess := TFakeProcess.Create(
    function(const ARequest: TCompilerRequest; out AOutput: TArray<string>): Integer
    begin
      AOutput := nil;
      Result := 0;
    end);
  mKeep := mProcess;
  mExe := TPath.Combine(FFolder, TPath.Combine('bin', 'dcc32.exe'));
  mEditions := TShellCompilerEditions.Create(mKeep, Silent, '');
  try
    Assert.AreEqual(Ord(TCompilerEdition.Unknown), Ord(mEditions.Resolve(FFolder, '37.0', mExe)));
    Assert.AreEqual(Ord(TCompilerEdition.Unknown), Ord(mEditions.Resolve(FFolder, '37.0', mExe)));
    Assert.AreEqual(2, Integer(mProcess.Calls.Count), 'unklar: beim nächsten Mal erneut prüfen');
  finally
    mEditions.Free;
  end;
end;

procedure TShellCompilerTests.RemembersLicenseTextOfARealRun;
var
  mProcess: TFakeProcess;
  mKeep: ICompilerProcess;
  mEditions: TShellCompilerEditions;
  mExe: string;
begin
  mProcess := TFakeProcess.Create(
    function(const ARequest: TCompilerRequest; out AOutput: TArray<string>): Integer
    begin
      AOutput := TArray<string>.Create('Syntax: dcc32 [options] filename');
      Result := 0;
    end);
  mKeep := mProcess;
  mExe := TPath.Combine(FFolder, TPath.Combine('bin', 'dcc32.exe'));
  mEditions := TShellCompilerEditions.Create(mKeep, Silent, '');
  try
    Assert.AreEqual(Ord(TCompilerEdition.CommandLine), Ord(mEditions.Resolve(FFolder, '37.0', mExe)));
    mEditions.Remember(FFolder, '37.0', mExe, TCompilerEdition.NoCommandLine);
    Assert.AreEqual(Ord(TCompilerEdition.NoCommandLine), Ord(mEditions.Resolve(FFolder, '37.0', mExe)));
    Assert.AreEqual(1, Integer(mProcess.Calls.Count));
  finally
    mEditions.Free;
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
      begin
        Command := ARequest.Arguments[6];
      end;
      AOutput := nil;
      Result := 0;
      if Command = 'start' then
      begin
        AOutput := TArray<string>.Create('IDE started : pid ' + IntToStr(APid));
      end
      else if Command = 'build' then
      begin
        AOutput := TArray<string>.Create('{"ok": false, "outputWritten": false, "logFile": "' +
          StringReplace(ALog, '\', '\\', [rfReplaceAll]) + '"}');
      end;
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
  mProcess: TFakeProcess;
  mKeep: ICompilerProcess;
  mRunning: TList<Cardinal>;
  mIde: TShellIdeCompiler;
  mMessages: TArray<TCompilerMessage>;
  mSucceeded: Boolean;
  mError: string;
begin
  mProcess := TFakeProcess.Create(CcScript(900, 'C:\Temp\build.log'));
  mKeep := mProcess;
  mRunning := TList<Cardinal>.Create;
  mIde := Compiler(mProcess, TArray<Cardinal>.Create(100), mRunning);
  try
    mRunning.Add(100);
    mRunning.Add(900);
    Assert.IsTrue(mIde.Build('C:\T\cc.ps1', 'C:\P\App.dproj', 'Win32', mMessages, mSucceeded, mError), mError);
    Assert.AreEqual(Cardinal(900), mIde.Pid);
    Assert.IsFalse(mSucceeded);
    Assert.AreEqual(1, Integer(Length(mMessages)));
    Assert.AreEqual('C:\P\Main.pas', mMessages[0].FileName);
    Assert.AreEqual('E2003', mMessages[0].Code);
    Assert.IsTrue(mIde.Build('C:\T\cc.ps1', 'C:\P\App.dproj', 'Win32', mMessages, mSucceeded, mError), mError);
    Assert.AreEqual(3, Integer(mProcess.Calls.Count), 'einmal start, zweimal build');
    Assert.IsTrue(mProcess.Calls[0].EndsWith('cc.ps1 start -Project C:\P\App.dproj -TimeoutSec 180'), mProcess.Calls[0]);
    Assert.IsTrue(mProcess.Calls[2].EndsWith('build -Instance 900 -Project C:\P\App.dproj -Platform Win32 -Json'),
      mProcess.Calls[2]);
  finally
    mIde.Free;
    mRunning.Free;
  end;
end;

procedure TShellCompilerTests.NeverBuildsInTheUsersIde;
var
  mProcess: TFakeProcess;
  mKeep: ICompilerProcess;
  mRunning: TList<Cardinal>;
  mIde: TShellIdeCompiler;
  mMessages: TArray<TCompilerMessage>;
  mSucceeded: Boolean;
  mError, mCall: string;
begin
  // cc.ps1 nennt die pid einer IDE, die schon vorher lief (die des Benutzers): kein build.
  mProcess := TFakeProcess.Create(CcScript(100, 'C:\Temp\build.log'));
  mKeep := mProcess;
  mRunning := TList<Cardinal>.Create;
  mIde := Compiler(mProcess, TArray<Cardinal>.Create(100), mRunning);
  try
    mRunning.Add(100);
    Assert.IsFalse(mIde.Build('C:\T\cc.ps1', 'C:\P\App.dproj', '', mMessages, mSucceeded, mError));
    Assert.IsTrue(Pos('eigenen IDE', mError) > 0, mError);
    Assert.AreEqual(Cardinal(0), mIde.Pid);
    for mCall in mProcess.Calls do
    begin
      Assert.IsFalse(Pos(' build ', ' ' + mCall + ' ') > 0, mCall);
    end;
  finally
    mIde.Free;
    mRunning.Free;
  end;
end;

procedure TShellCompilerTests.StartsNewIdeWhenTheOldOneIsGone;
var
  mProcess: TFakeProcess;
  mKeep: ICompilerProcess;
  mRunning: TList<Cardinal>;
  mIde: TShellIdeCompiler;
  mMessages: TArray<TCompilerMessage>;
  mSucceeded: Boolean;
  mError: string;
begin
  mProcess := TFakeProcess.Create(CcScript(900, ''));
  mKeep := mProcess;
  mRunning := TList<Cardinal>.Create;
  mIde := Compiler(mProcess, nil, mRunning);
  try
    mRunning.Add(900);
    Assert.IsTrue(mIde.Build('C:\T\cc.ps1', 'C:\P\App.dproj', '', mMessages, mSucceeded, mError), mError);
    mProcess.Calls.Clear;
    Assert.IsTrue(mIde.Build('C:\T\cc.ps1', 'C:\P\App.dproj', '', mMessages, mSucceeded, mError), mError);
    Assert.AreEqual(1, Integer(mProcess.Calls.Count), 'läuft noch: kein neuer Start');
    // Die eigene IDE ist beendet: neue Instanz.
    mRunning.Clear;
    mProcess.Calls.Clear;
    Assert.IsTrue(mIde.Build('C:\T\cc.ps1', 'C:\P\App.dproj', '', mMessages, mSucceeded, mError), mError);
    Assert.IsTrue(mProcess.Calls[0].Contains(' start '), mProcess.Calls[0]);
  finally
    mIde.Free;
    mRunning.Free;
  end;
end;

procedure TShellCompilerTests.QuitEndsOwnIde;
var
  mProcess: TFakeProcess;
  mKeep: ICompilerProcess;
  mRunning: TList<Cardinal>;
  mIde: TShellIdeCompiler;
  mMessages: TArray<TCompilerMessage>;
  mSucceeded: Boolean;
  mError: string;
begin
  mProcess := TFakeProcess.Create(CcScript(900, ''));
  mKeep := mProcess;
  mRunning := TList<Cardinal>.Create;
  mIde := Compiler(mProcess, nil, mRunning);
  try
    mRunning.Add(900);
    Assert.IsTrue(mIde.Build('C:\T\cc.ps1', 'C:\P\App.dproj', '', mMessages, mSucceeded, mError), mError);
    mProcess.Calls.Clear;
    mIde.Quit(mKeep);
    Assert.AreEqual(1, Integer(mProcess.Calls.Count));
    Assert.IsTrue(mProcess.Calls[0].EndsWith('cc.ps1 quit -Instance 900'), mProcess.Calls[0]);
    Assert.AreEqual(Cardinal(0), mIde.Pid);
    mIde.Quit(mKeep);
    Assert.AreEqual(1, Integer(mProcess.Calls.Count), 'ohne eigene IDE nichts zu tun');
  finally
    mIde.Free;
    mRunning.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TShellCompilerTests);

end.
