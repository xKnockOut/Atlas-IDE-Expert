unit Atlas.Core.Lsp.Providers.ServerProcess.Tests;

// Tests des Serverprozesses (Start, Ende, Handles).

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.Providers.ServerProcess;

type
  [TestFixture]
  TLspServerProcessTests = class
  public
    // Startet den echten Server neben dem Testprogramm.
    [Test]
    procedure HoverAndDefinitionAgainstServer;
    [Test]
    procedure PullsDiagnosticsAgainstServer;
    [Test]
    procedure CompilerMessagesReachPulledDiagnostics;
    /// <summary>Scheitert der Start, bleiben keine Handles offen.</summary>
    [Test]
    procedure StartFailureLeavesNoHandles;
    /// <summary>Endet der Prozess, kennt der Client Exit-Code und Zeilen auf stderr; stderr steht in
    /// server-stderr.log.</summary>
    [Test]
    procedure EndReportsExitCodeAndStderr;
  end;

/// <summary>Startet AExeName mit AArguments wie die IDE; AClient ist der Client der Verbindung und lebt so lange wie
/// der Prozess. Löst bei Fehlern EOSError aus.</summary>
function StartLspServer(const AExeName, AArguments: string; out AClient: TLspClient): TLspServerProcess;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  Atlas.Plugin.Diagnostics.Guard,
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Lsp.Crashes,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Problems.Contract,
  Atlas.Tests.Wait;

/// <summary>Zahl der offenen Handles des Prozesses (eigene Deklaration, unabhängig von der Delphi-Version).</summary>
function ProcessHandleCount(AHProcess: THandle; var APdwHandleCount: DWORD): BOOL; stdcall;
  external kernel32 name 'GetProcessHandleCount';
const
  cCompilerMessagesUnitText =
    'unit ProbeCompiler;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'begin'#13#10 +
    '  Gibtsnicht.Create;'#13#10 +
    'end;'#13#10 +
    'end.';

function StartLspServer(const AExeName, AArguments: string; out AClient: TLspClient): TLspServerProcess;
var
  mClient: TLspClient;
begin
  mClient := nil;
  Result := TLspServerProcess.Create(AExeName, AArguments,
    function(const ASend: TLspSendProc): IAtlasLspConnection
    begin
      Result := TLspClientConnection.Open(ASend, mClient);
    end);
  AClient := mClient;
end;

{ TLspServerProcessTests }

procedure TLspServerProcessTests.HoverAndDefinitionAgainstServer;
const
  cUnitText =
    'unit Probe;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TFoo = class'#13#10 +
    '    FWert: Integer;'#13#10 +
    '    procedure Setze;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'procedure TFoo.Setze;'#13#10 +
    'begin'#13#10 +
    '  FWert := 1;'#13#10 +
    'end;'#13#10 +
    'end.';
var
  mServerExe, mFileName: string;
  mServer: TLspServerProcess;
  mClient: TLspClient;
  mSession: TLspSession;
  mLocation: TLspLocation;
begin
  mServerExe := TPath.Combine(ExtractFilePath(ParamStr(0)), 'AtlasServer.exe');
  if not FileExists(mServerExe) then
  begin
    Assert.Pass('Server nicht neben dem Testprogramm gebaut: ' + mServerExe);
  end;
  mFileName := TPath.Combine(TPath.GetTempPath, 'AtlasPluginProbe.pas');
  mServer := StartLspServer(mServerExe, '', mClient);
  try
    mSession := TLspSession.Create(mClient, 5000);
    try
      mSession.Initialize;
      Assert.IsTrue(mServer.Running);
      Assert.AreEqual('FWert: Integer;', mSession.Hover(mFileName, cUnitText, 10, 3, 0));
      Assert.IsTrue(mSession.Definition(mFileName, cUnitText, 10, 3, mLocation));
      Assert.AreEqual(4, mLocation.Line);
      Assert.IsTrue(SameText(mFileName, mLocation.FileName), mLocation.FileName);
    finally
      mSession.Free;
    end;
  finally
    mServer.Free;
  end;
end;
procedure TLspServerProcessTests.PullsDiagnosticsAgainstServer;
const
  cUnitText =
    'unit ProbeFehler;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'begin'#13#10 +
    '  if then'#13#10 +
    'end;'#13#10 +
    'end.';
var
  mServerExe, mFileName: string;
  mServer: TLspServerProcess;
  mClient: TLspClient;
  mSession: TLspSession;
  mReport, mAgain: TLspDiagnosticReport;
begin
  mServerExe := TPath.Combine(ExtractFilePath(ParamStr(0)), 'AtlasServer.exe');
  if not FileExists(mServerExe) then
  begin
    Assert.Pass('Server nicht neben dem Testprogramm gebaut: ' + mServerExe);
  end;
  mFileName := TPath.Combine(TPath.GetTempPath, 'AtlasPluginProbeFehler.pas');
  mServer := StartLspServer(mServerExe, '', mClient);
  try
    mSession := TLspSession.Create(mClient, 5000);
    try
      mSession.Initialize;
      mSession.Sync(mFileName, cUnitText);
      mReport := mSession.DocumentDiagnostics(mFileName, '', 10000);
      Assert.IsFalse(mReport.Unchanged);
      Assert.IsTrue(Length(mReport.Problems) > 0, 'Syntaxfehler gemeldet');
      Assert.AreEqual<TAtlasProblemSeverity>(TAtlasProblemSeverity.Error, mReport.Problems[0].Severity);
      Assert.AreEqual(5, mReport.Problems[0].StartLine);
      Assert.AreNotEqual('', mReport.ResultId);
      mAgain := mSession.DocumentDiagnostics(mFileName, mReport.ResultId, 10000);
      Assert.IsTrue(mAgain.Unchanged, 'gleiche Version: unverändert');
    finally
      mSession.Free;
    end;
  finally
    mServer.Free;
  end;
end;
{ TLspServerProcessTests }

procedure TLspServerProcessTests.CompilerMessagesReachPulledDiagnostics;
var
  mServerExe, mFileName: string;
  mServer: TLspServerProcess;
  mClient: TLspClient;
  mSession: TLspSession;
  mReport: TLspDiagnosticReport;
  mParams: TJSONObject;
  mWaited: Integer;
  mProblem: TAtlasProblem;
  mFound: Boolean;
begin
  mServerExe := TPath.Combine(ExtractFilePath(ParamStr(0)), 'AtlasServer.exe');
  if not FileExists(mServerExe) then
  begin
    Assert.Pass('Server nicht neben dem Testprogramm gebaut: ' + mServerExe);
  end;
  mFileName := TPath.Combine(TPath.GetTempPath, 'AtlasPluginProbeCompiler.pas');
  mServer := StartLspServer(mServerExe, '', mClient);
  try
    mSession := TLspSession.Create(mClient, 5000);
    try
      mSession.Initialize;
      mSession.Sync(mFileName, cCompilerMessagesUnitText);
      mParams := TJSONObject.ParseJSONValue(Format('{"project":"","platform":"Win32","success":false,"background":true,' +
        '"messages":[{"file":"%s","line":6,"column":3,"severity":"error","code":"E2003",' +
        '"text":"Undeklarierter Bezeichner: ''Gibtsnicht''"}]}', [StringReplace(mFileName, '\', '\\', [rfReplaceAll])]))
        as TJSONObject;
      mSession.Notify('atlas/compilerMessages', mParams);
      // Der Server bittet danach um neues Holen.
      mWaited := 0;
      while (mSession.RefreshCount = 0) and (mWaited < 5000) do
      begin
        Sleep(50);
        Inc(mWaited, 50);
      end;
      Assert.AreEqual(1, mSession.RefreshCount, 'workspace/diagnostic/refresh');
      mReport := mSession.DocumentDiagnostics(mFileName, '', 10000);
      mFound := False;
      for mProblem in mReport.Problems do
      begin
        if mProblem.IsCompiler and (mProblem.Code = 'E2003') then
        begin
          mFound := True;
          Assert.AreEqual(5, mProblem.StartLine);
          Assert.AreEqual<TAtlasProblemSeverity>(TAtlasProblemSeverity.Error, mProblem.Severity);
        end;
      end;
      Assert.IsTrue(mFound, 'dcc-Meldung in den Diagnosen der geöffneten Datei');
    finally
      mSession.Free;
    end;
  finally
    mServer.Free;
  end;
end;
procedure TLspServerProcessTests.StartFailureLeavesNoHandles;
const
  cMissing = 'C:\nicht\vorhanden\AtlasServer.exe';
var
  mBefore, mAfter: DWORD;
  mIndex: Integer;
begin
  // Vorlauf außerhalb der Messung: einmalige Handles der RTL (Ausnahmen, Codepages) vorwegnehmen.
  Assert.WillRaise(
    procedure
    var
      mClient: TLspClient;
    begin
      StartLspServer(cMissing, '', mClient).Free;
    end, EOSError);
  mBefore := 0;
  mAfter := 0;
  Assert.IsTrue(ProcessHandleCount(GetCurrentProcess, mBefore));
  for mIndex := 1 to 10 do
  begin
    Assert.WillRaise(
      procedure
      var
        mClient: TLspClient;
      begin
        StartLspServer(cMissing, '', mClient).Free;
      end, EOSError);
  end;
  Assert.IsTrue(ProcessHandleCount(GetCurrentProcess, mAfter));
  // Je Lauf vier Pipe-Enden und die stderr-Datei; ein Leck zeigte sich als Zuwachs um mindestens zehn.
  Assert.IsTrue(Integer(mAfter) - Integer(mBefore) < 5, Format('Handles vorher %d, nachher %d', [mBefore, mAfter]));
end;

/// <summary>Ist die Verbindung von AClient geschlossen? Eigene Routine, damit die anonyme Methode nur AClient
/// einfängt.</summary>
function ClientClosed(AClient: TLspClient): TFunc<Boolean>;
begin
  Result :=
    function: Boolean
    begin
      Result := AClient.Closed;
    end;
end;

procedure TLspServerProcessTests.EndReportsExitCodeAndStderr;
var
  mServer: IAtlasLspServer;
  mClient: TLspClient;
  mInfo: TLspCloseInfo;
  mText: string;
begin
  // Ein „Server“, der eine Zeile auf stderr schreibt und mit Code 3 endet.
  mServer := StartLspServer(GetEnvironmentVariable('ComSpec'), '/c echo Testausgabe auf stderr 1>&2 & exit 3',
    mClient);
  Assert.IsTrue(TTestWait.Reached(ClientClosed(mClient), 10000),
    'Verbindung nach dem Ende des Prozesses geschlossen');
  mInfo := mClient.CloseInfo;
  Assert.IsTrue(mInfo.ExitKnown, 'Exit-Code bekannt');
  Assert.AreEqual(Int64(3), Int64(mInfo.ExitCode));
  Assert.AreEqual(1, mInfo.ErrorLines);
  Assert.IsTrue(mInfo.RuntimeMs >= 0);
  mServer := nil;
  mText := TFile.ReadAllText(TAtlasServerExits.StderrFileName(TAtlasGuard.RotatingLog.Folder), TEncoding.UTF8);
  Assert.Contains(mText, 'Serverstart');
  Assert.Contains(mText, 'Testausgabe auf stderr');
end;

initialization
  TDUnitX.RegisterTestFixture(TLspServerProcessTests);

end.
