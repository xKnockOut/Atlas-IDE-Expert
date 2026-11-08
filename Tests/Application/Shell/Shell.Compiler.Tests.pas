unit Shell.Compiler.Tests;

// Tests für Kompilieren ohne Kommandozeilen-Compiler im Server (#261): Erkennen
// der Ausgabe mit Zwischenspeicher. Prozesse sind nachgestellt.

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

initialization
  TDUnitX.RegisterTestFixture(TShellCompilerTests);

end.
