unit Atlas.Core.Lsp.Adapters.ServerProcess.Tests;

// Tests des Serverprozesses (Start, Ende, Handles).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspServerProcessTests = class
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
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

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  System.Diagnostics,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.Crashes,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Lsp.Adapters.ServerProcess,
  Atlas.Core.Problems.Contract;

/// <summary>Zahl der offenen Handles des Prozesses (eigene Deklaration, unabhängig von der Delphi-Version).</summary>
function ProcessHandleCount(AHProcess: THandle; var APdwHandleCount: DWORD): BOOL; stdcall;
  external kernel32 name 'GetProcessHandleCount';
{ TLspServerProcessTests }

procedure TLspServerProcessTests.WarmUpFirstUse;
begin
  StartFailureLeavesNoHandles;
  // Erster echter Start (Pipes, Lese- und Schreib-Thread, Sitzung) ungemessen statt [IgnoreMemoryLeaks]
  //. Ohne Server neben dem Testprogramm überspringen die Tests ohnehin.
  if FileExists(TPath.Combine(ExtractFilePath(ParamStr(0)), 'AtlasServer.exe')) then
    try
      HoverAndDefinitionAgainstServer;
    except
      // Scheitert der Lauf, meldet das der Test selbst; das Aufwärmen hält die übrigen Tests nicht auf.
      on Exception do
        ;
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
    begin
      TLspServerProcess.Create(cMissing, '').Free;
    end, EOSError);
  mBefore := 0;
  mAfter := 0;
  Assert.IsTrue(ProcessHandleCount(GetCurrentProcess, mBefore));
  for mIndex := 1 to 10 do
  begin
    Assert.WillRaise(
      procedure
      begin
        TLspServerProcess.Create(cMissing, '').Free;
      end, EOSError);
  end;
  Assert.IsTrue(ProcessHandleCount(GetCurrentProcess, mAfter));
  // Je Lauf vier Pipe-Enden und die stderr-Datei; ein Leck zeigte sich als Zuwachs um mindestens zehn.
  Assert.IsTrue(Integer(mAfter) - Integer(mBefore) < 5, Format('Handles vorher %d, nachher %d', [mBefore, mAfter]));
end;
procedure TLspServerProcessTests.EndReportsExitCodeAndStderr;
var
  mServer: IAtlasLspServer;
  mWatch: TStopwatch;
  mInfo: TLspCloseInfo;
  mText: string;
begin
  // Ein „Server“, der eine Zeile auf stderr schreibt und mit Code 3 endet.
  mServer := TLspServerProcess.Create(GetEnvironmentVariable('ComSpec'), '/c echo Testausgabe auf stderr 1>&2 & exit 3');
  mWatch := TStopwatch.StartNew;
  while not mServer.Client.Closed and (mWatch.ElapsedMilliseconds < 10000) do
  begin
    Sleep(20);
  end;
  Assert.IsTrue(mServer.Client.Closed, 'Verbindung nach dem Ende des Prozesses geschlossen');
  mInfo := mServer.Client.CloseInfo;
  Assert.IsTrue(mInfo.ExitKnown, 'Exit-Code bekannt');
  Assert.AreEqual(Int64(3), Int64(mInfo.ExitCode));
  Assert.AreEqual(1, mInfo.ErrorLines);
  Assert.IsTrue(mInfo.RuntimeMs >= 0);
  mServer := nil;
  mText := TFile.ReadAllText(TAtlasServerExits.StderrFileName(TAtlasGuard.RotatingLog.Folder), TEncoding.UTF8);
  Assert.Contains(mText, 'Serverstart');
  Assert.Contains(mText, 'Testausgabe auf stderr');
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
  mSession: TLspSession;
  mLocation: TLspLocation;
begin
  mServerExe := TPath.Combine(ExtractFilePath(ParamStr(0)), 'AtlasServer.exe');
  if not FileExists(mServerExe) then
  begin
    Assert.Pass('Server nicht neben dem Testprogramm gebaut: ' + mServerExe);
  end;
  mFileName := TPath.Combine(TPath.GetTempPath, 'AtlasPluginProbe.pas');
  mServer := TLspServerProcess.Create(mServerExe, '');
  try
    mSession := TLspSession.Create(mServer.Client, 5000);
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
  mSession: TLspSession;
  mReport, mAgain: TLspDiagnosticReport;
begin
  mServerExe := TPath.Combine(ExtractFilePath(ParamStr(0)), 'AtlasServer.exe');
  if not FileExists(mServerExe) then
  begin
    Assert.Pass('Server nicht neben dem Testprogramm gebaut: ' + mServerExe);
  end;
  mFileName := TPath.Combine(TPath.GetTempPath, 'AtlasPluginProbeFehler.pas');
  mServer := TLspServerProcess.Create(mServerExe, '');
  try
    mSession := TLspSession.Create(mServer.Client, 5000);
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

procedure TLspServerProcessTests.CompilerMessagesReachPulledDiagnostics;
var
  mServerExe, mFileName: string;
  mServer: TLspServerProcess;
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
  mServer := TLspServerProcess.Create(mServerExe, '');
  try
    mSession := TLspSession.Create(mServer.Client, 5000);
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

initialization
  TDUnitX.RegisterTestFixture(TLspServerProcessTests);

end.
