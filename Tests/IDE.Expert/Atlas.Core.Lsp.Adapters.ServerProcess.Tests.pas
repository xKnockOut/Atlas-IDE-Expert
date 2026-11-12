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
function ProcessHandleCount(hProcess: THandle; var pdwHandleCount: DWORD): BOOL; stdcall;
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
  Missing = 'C:\nicht\vorhanden\AtlasServer.exe';
var
  Before, After: DWORD;
  Index: Integer;
begin
  // Vorlauf außerhalb der Messung: einmalige Handles der RTL (Ausnahmen, Codepages) vorwegnehmen.
  Assert.WillRaise(
    procedure
    begin
      TLspServerProcess.Create(Missing, '').Free;
    end, EOSError);
  Before := 0;
  After := 0;
  Assert.IsTrue(ProcessHandleCount(GetCurrentProcess, Before));
  for Index := 1 to 10 do
  begin
    Assert.WillRaise(
      procedure
      begin
        TLspServerProcess.Create(Missing, '').Free;
      end, EOSError);
  end;
  Assert.IsTrue(ProcessHandleCount(GetCurrentProcess, After));
  // Je Lauf vier Pipe-Enden und die stderr-Datei; ein Leck zeigte sich als Zuwachs um mindestens zehn.
  Assert.IsTrue(Integer(After) - Integer(Before) < 5, Format('Handles vorher %d, nachher %d', [Before, After]));
end;
procedure TLspServerProcessTests.EndReportsExitCodeAndStderr;
var
  Server: IAtlasLspServer;
  Watch: TStopwatch;
  Info: TLspCloseInfo;
  Text: string;
begin
  // Ein „Server“, der eine Zeile auf stderr schreibt und mit Code 3 endet.
  Server := TLspServerProcess.Create(GetEnvironmentVariable('ComSpec'), '/c echo Testausgabe auf stderr 1>&2 & exit 3');
  Watch := TStopwatch.StartNew;
  while not Server.Client.Closed and (Watch.ElapsedMilliseconds < 10000) do
  begin
    Sleep(20);
  end;
  Assert.IsTrue(Server.Client.Closed, 'Verbindung nach dem Ende des Prozesses geschlossen');
  Info := Server.Client.CloseInfo;
  Assert.IsTrue(Info.ExitKnown, 'Exit-Code bekannt');
  Assert.AreEqual(Int64(3), Int64(Info.ExitCode));
  Assert.AreEqual(1, Info.ErrorLines);
  Assert.IsTrue(Info.RuntimeMs >= 0);
  Server := nil;
  Text := TFile.ReadAllText(TAtlasServerExits.StderrFileName(TAtlasGuard.RotatingLog.Folder), TEncoding.UTF8);
  Assert.Contains(Text, 'Serverstart');
  Assert.Contains(Text, 'Testausgabe auf stderr');
end;
{ TLspServerProcessTests }

procedure TLspServerProcessTests.HoverAndDefinitionAgainstServer;
const
  UnitText =
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
  ServerExe, FileName: string;
  Server: TLspServerProcess;
  Session: TLspSession;
  Location: TLspLocation;
begin
  ServerExe := TPath.Combine(ExtractFilePath(ParamStr(0)), 'AtlasServer.exe');
  if not FileExists(ServerExe) then
  begin
    Assert.Pass('Server nicht neben dem Testprogramm gebaut: ' + ServerExe);
  end;
  FileName := TPath.Combine(TPath.GetTempPath, 'AtlasPluginProbe.pas');
  Server := TLspServerProcess.Create(ServerExe, '');
  try
    Session := TLspSession.Create(Server.Client, 5000);
    try
      Session.Initialize;
      Assert.IsTrue(Server.Running);
      Assert.AreEqual('FWert: Integer;', Session.Hover(FileName, UnitText, 10, 3, 0));
      Assert.IsTrue(Session.Definition(FileName, UnitText, 10, 3, Location));
      Assert.AreEqual(4, Location.Line);
      Assert.IsTrue(SameText(FileName, Location.FileName), Location.FileName);
    finally
      Session.Free;
    end;
  finally
    Server.Free;
  end;
end;
procedure TLspServerProcessTests.PullsDiagnosticsAgainstServer;
const
  UnitText =
    'unit ProbeFehler;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'begin'#13#10 +
    '  if then'#13#10 +
    'end;'#13#10 +
    'end.';
var
  ServerExe, FileName: string;
  Server: TLspServerProcess;
  Session: TLspSession;
  Report, Again: TLspDiagnosticReport;
begin
  ServerExe := TPath.Combine(ExtractFilePath(ParamStr(0)), 'AtlasServer.exe');
  if not FileExists(ServerExe) then
  begin
    Assert.Pass('Server nicht neben dem Testprogramm gebaut: ' + ServerExe);
  end;
  FileName := TPath.Combine(TPath.GetTempPath, 'AtlasPluginProbeFehler.pas');
  Server := TLspServerProcess.Create(ServerExe, '');
  try
    Session := TLspSession.Create(Server.Client, 5000);
    try
      Session.Initialize;
      Session.Sync(FileName, UnitText);
      Report := Session.DocumentDiagnostics(FileName, '', 10000);
      Assert.IsFalse(Report.Unchanged);
      Assert.IsTrue(Length(Report.Problems) > 0, 'Syntaxfehler gemeldet');
      Assert.IsTrue(Report.Problems[0].Severity = TAtlasProblemSeverity.Error);
      Assert.AreEqual(5, Report.Problems[0].StartLine);
      Assert.AreNotEqual('', Report.ResultId);
      Again := Session.DocumentDiagnostics(FileName, Report.ResultId, 10000);
      Assert.IsTrue(Again.Unchanged, 'gleiche Version: unverändert');
    finally
      Session.Free;
    end;
  finally
    Server.Free;
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
  ServerExe, FileName: string;
  Server: TLspServerProcess;
  Session: TLspSession;
  Report: TLspDiagnosticReport;
  Params: TJSONObject;
  Waited: Integer;
  Problem: TAtlasProblem;
  Found: Boolean;
begin
  ServerExe := TPath.Combine(ExtractFilePath(ParamStr(0)), 'AtlasServer.exe');
  if not FileExists(ServerExe) then
  begin
    Assert.Pass('Server nicht neben dem Testprogramm gebaut: ' + ServerExe);
  end;
  FileName := TPath.Combine(TPath.GetTempPath, 'AtlasPluginProbeCompiler.pas');
  Server := TLspServerProcess.Create(ServerExe, '');
  try
    Session := TLspSession.Create(Server.Client, 5000);
    try
      Session.Initialize;
      Session.Sync(FileName, cCompilerMessagesUnitText);
      Params := TJSONObject.ParseJSONValue(Format('{"project":"","platform":"Win32","success":false,"background":true,' +
        '"messages":[{"file":"%s","line":6,"column":3,"severity":"error","code":"E2003",' +
        '"text":"Undeklarierter Bezeichner: ''Gibtsnicht''"}]}', [StringReplace(FileName, '\', '\\', [rfReplaceAll])]))
        as TJSONObject;
      Session.Notify('atlas/compilerMessages', Params);
      // Der Server bittet danach um neues Holen.
      Waited := 0;
      while (Session.RefreshCount = 0) and (Waited < 5000) do
      begin
        Sleep(50);
        Inc(Waited, 50);
      end;
      Assert.AreEqual(1, Session.RefreshCount, 'workspace/diagnostic/refresh');
      Report := Session.DocumentDiagnostics(FileName, '', 10000);
      Found := False;
      for Problem in Report.Problems do
      begin
        if Problem.IsCompiler and (Problem.Code = 'E2003') then
        begin
          Found := True;
          Assert.AreEqual(5, Problem.StartLine);
          Assert.IsTrue(Problem.Severity = TAtlasProblemSeverity.Error);
        end;
      end;
      Assert.IsTrue(Found, 'dcc-Meldung in den Diagnosen der geöffneten Datei');
    finally
      Session.Free;
    end;
  finally
    Server.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspServerProcessTests);

end.
