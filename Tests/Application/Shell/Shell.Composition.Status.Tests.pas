unit Shell.Composition.Status.Tests;

// Status, Prozesse und Fehlerbericht der Komposition ohne Arbeitsbereiche: Zustände kommen über die Dienste,
// der Fehlerbericht enthält die Version und meldet sich im Log.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Scheduler,
  Atlas.Common.Lsp.Status,
  Atlas.Common.Lsp.WorkspaceCheck,
  Shell.Workspace,
  Shell.Composition.Status;

type
  [TestFixture]
  TShellStatusReportsTests = class
  private
    FLog: TArray<string>;
    FCompilerAsked: Integer;
    FCheckAsked: Integer;
    FQueueAsked: Integer;
    function NewServices: TShellStatusServices;
    procedure Logged(const AText: string);
    procedure VisitNone(const AVisit: TShellStatusWorkspacesProc);
    procedure CompilerStatus(var AStatus: TServerStatus);
    procedure CheckStatus(var AStatus: TServerStatus; out AQueue: TWorkspaceCheckQueue);
    function IndexQueue: TIndexSchedulerQueue;
  public
    [TearDown]
    procedure TearDown;
    /// <summary>Der anonyme Status fragt Compiler, Prüflauf und Index-Warteschlange und schreibt ins Log.</summary>
    [Test]
    procedure StatusAsksAllStates;
    /// <summary>Ohne Arbeitsbereiche gibt es keine Prozesse am Index-Cache.</summary>
    [Test]
    procedure NoProcessesWithoutWorkspaces;
    /// <summary>Der Fehlerbericht liefert Text mit der Serverversion und meldet sich im Log.</summary>
    [Test]
    procedure BugReportHasVersion;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Logging.Providers.RecentSink,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.JsonRpc.Statistics,
  Atlas.Common.JsonRpc.TracingTransport,
  Atlas.Common.Diagnostics.Anonymizer,
  Atlas.Common.Diagnostics.BugReport,
  Atlas.Common.Product.Version,
  Atlas.Common.Lsp.Commands;

type
  TLogLineProc = reference to procedure(const AText: string);

  /// <summary>Sammelt Logzeilen über eine Methodenreferenz.</summary>
  TCollectingLogger = class(TInterfacedObject, ILogger)
  private
    FSink: TLogLineProc;
  public
    constructor Create(const ASink: TLogLineProc);
    procedure Log(ALevel: TLogLevel; const AText: string);
    procedure Debug(const AText: string);
    procedure Info(const AText: string);
    procedure Warning(const AText: string);
    procedure Error(const AText: string);
  end;

constructor TCollectingLogger.Create(const ASink: TLogLineProc);
begin
  inherited Create;
  FSink := ASink;
end;

procedure TCollectingLogger.Log(ALevel: TLogLevel; const AText: string);
begin
  FSink(AText);
end;

procedure TCollectingLogger.Debug(const AText: string);
begin
  FSink(AText);
end;

procedure TCollectingLogger.Info(const AText: string);
begin
  FSink(AText);
end;

procedure TCollectingLogger.Warning(const AText: string);
begin
  FSink(AText);
end;

procedure TCollectingLogger.Error(const AText: string);
begin
  FSink(AText);
end;

procedure TShellStatusReportsTests.TearDown;
begin
  FLog := nil;
end;

procedure TShellStatusReportsTests.Logged(const AText: string);
begin
  FLog := FLog + [AText];
end;

procedure TShellStatusReportsTests.VisitNone(const AVisit: TShellStatusWorkspacesProc);
begin
  AVisit(nil);
end;

procedure TShellStatusReportsTests.CompilerStatus(var AStatus: TServerStatus);
begin
  Inc(FCompilerAsked);
end;

procedure TShellStatusReportsTests.CheckStatus(var AStatus: TServerStatus; out AQueue: TWorkspaceCheckQueue);
begin
  Inc(FCheckAsked);
  AQueue := Default(TWorkspaceCheckQueue);
end;

function TShellStatusReportsTests.IndexQueue: TIndexSchedulerQueue;
begin
  Inc(FQueueAsked);
  Result := Default(TIndexSchedulerQueue);
end;

function TShellStatusReportsTests.NewServices: TShellStatusServices;
begin
  Result := Default(TShellStatusServices);
  Result.Logger := TCollectingLogger.Create(Logged);
  Result.Index := TSymbolIndex.Create;
  Result.Documents := TDocumentStore.Create;
  Result.Statistics := TJsonRpcStatistics.Create;
  Result.VisitWorkspaces := VisitNone;
  Result.EditorSettings :=
    function: string
    begin
      Result := '';
    end;
  Result.RecentLog :=
    function: IRecentLogLines
    begin
      Result := nil;
    end;
  Result.Tracing :=
    function: TJsonRpcTracingTransport
    begin
      Result := nil;
    end;
  Result.Anonymizer :=
    function: ILogAnonymizer
    begin
      Result := nil;
    end;
  Result.CompilerStatus := CompilerStatus;
  Result.CheckStatus := CheckStatus;
  Result.IndexQueue := IndexQueue;
end;

procedure TShellStatusReportsTests.StatusAsksAllStates;
var
  mReports: TShellStatusReports;
  mStatus: TJSONObject;
begin
  mReports := TShellStatusReports.Create(NewServices);
  try
    // Anonym: schreibt keine Statusdatei in den Cache-Ordner des Benutzers.
    mStatus := mReports.StatusJson(True);
    try
      Assert.IsNotNull(mStatus);
    finally
      mStatus.Free;
    end;
  finally
    mReports.Free;
  end;
  Assert.AreEqual(1, FCompilerAsked);
  Assert.AreEqual(1, FCheckAsked);
  Assert.AreEqual(1, FQueueAsked);
  Assert.AreEqual(1, Integer(Length(FLog)));
  Assert.StartsWith('Status:', FLog[0]);
end;

procedure TShellStatusReportsTests.NoProcessesWithoutWorkspaces;
var
  mReports: TShellStatusReports;
begin
  mReports := TShellStatusReports.Create(NewServices);
  try
    Assert.AreEqual(0, Integer(Length(mReports.CollectProcesses)));
  finally
    mReports.Free;
  end;
end;

procedure TShellStatusReportsTests.BugReportHasVersion;
var
  mReports: TShellStatusReports;
  mCommands: TLspCommands;
  mArguments: TJSONArray;
  mAnswer: TJSONValue;
  mText: string;
begin
  mReports := TShellStatusReports.Create(NewServices);
  mCommands := TLspCommands.Create;
  mArguments := TJSONArray.Create;
  try
    mReports.RegisterCommands(mCommands);
    mAnswer := mCommands.Execute(TBugReport.Command, mArguments);
    try
      Assert.IsTrue(mAnswer is TJSONObject);
      mText := TJSONObject(mAnswer).GetValue<string>('text', '');
    finally
      mAnswer.Free;
    end;
  finally
    mArguments.Free;
    mCommands.Free;
    mReports.Free;
  end;
  Assert.IsTrue(Pos(TProductVersion.Version, mText) > 0);
  Assert.AreEqual('Fehlerbericht erstellt', FLog[High(FLog)]);
end;

initialization
  TDUnitX.RegisterTestFixture(TShellStatusReportsTests);

end.
