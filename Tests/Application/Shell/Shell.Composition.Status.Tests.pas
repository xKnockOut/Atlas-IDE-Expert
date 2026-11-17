unit Shell.Composition.Status.Tests;

// Status und Fehlerbericht der Komposition ohne Arbeitsbereiche: Zustände kommen über die Dienste,
// der Fehlerbericht enthält die Version und meldet sich im Log.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Scheduler,
  Atlas.Common.Lsp.Status,
  Atlas.Common.Lsp.WorkspaceCheck,
  Shell.Workspace,
  Shell.Composition.Contract,
  Shell.Composition.Status.Contract,
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
    procedure VisitNone(const AVisit: TShellWorkspacesProc);
    procedure CompilerStatus(var AStatus: TServerStatus);
    procedure CheckStatus(var AStatus: TServerStatus; out AQueue: TWorkspaceCheckQueue);
    function IndexQueue: TIndexSchedulerQueue;
  public
    /// <summary>PROBE (nicht mergen): misst je Schritt erste und zweite Belegung.</summary>
    [Test]
    procedure AProbeFirstUse;
    [TearDown]
    procedure TearDown;
    /// <summary>Der anonyme Status fragt Compiler, Prüflauf und Index-Warteschlange und schreibt ins Log.</summary>
    [Test]
    procedure StatusAsksAllStates;
    /// <summary>Der Fehlerbericht liefert Text mit der Serverversion und meldet sich im Log.</summary>
    [Test]
    procedure BugReportHasVersion;
  end;

implementation

uses
  System.Generics.Collections, // Inline-Funktionen von TJSONArray (H2443)
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
  Atlas.Common.Lsp.Commands,
  System.Classes,
  System.IOUtils,
  System.Diagnostics,
  Atlas.Common.Diagnostics.ShutdownLeaks,
  Atlas.Common.Index.Adapters.CacheDirectory,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Projects.PackageLocator,
  Atlas.Text.LogMarks,
  Shell.Platform;

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

{ TCollectingLogger }

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

{ TShellStatusReportsTests }

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

procedure TShellStatusReportsTests.Logged(const AText: string);
begin
  FLog := FLog + [AText];
end;

procedure TShellStatusReportsTests.VisitNone(const AVisit: TShellWorkspacesProc);
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

type
  TProbeStep = reference to procedure;

function ProbeMarkValue(AKind: TLogMarkKind; const AValue: string): string;
begin
  Result := TLogMarks.Mark(AKind, AValue);
end;

procedure TShellStatusReportsTests.AProbeFirstUse;
var
  mLines: TStringList;
  mNames: TArray<string>;
  mSteps: TArray<TProbeStep>;
  mIndex, mRound: Integer;
  mBefore: Int64;
  mDelta: array[0..1] of Int64;
  mSelf: TShellStatusReportsTests;

  procedure Add(const AName: string; const AStep: TProbeStep);
  begin
    SetLength(mNames, Length(mNames) + 1);
    mNames[High(mNames)] := AName;
    SetLength(mSteps, Length(mSteps) + 1);
    mSteps[High(mSteps)] := AStep;
  end;

begin
  mSelf := Self;
  mNames := nil;
  mSteps := nil;
  Add('GetCachePath', procedure begin TPath.GetCachePath; end);
  Add('DefaultRoot', procedure begin TIndexCacheDirectory.DefaultRoot; end);
  Add('TotalSize', procedure begin TIndexCacheDirectory.TotalSize(TIndexCacheDirectory.DefaultRoot); end);
  Add('AllocatedBytes', procedure begin TShutdownLeaks.AllocatedBytes; end);
  Add('TreeStats', procedure begin TSyntaxTreeCache.Stats; end);
  Add('PackageBytes', procedure begin TPackageCompiledFiles.Bytes; end);
  Add('Stopwatch', procedure var mWatch: TStopwatch; begin mWatch := TStopwatch.StartNew; mWatch.ElapsedMilliseconds; end);
  Add('ProcessId', procedure begin TShellPlatform.CurrentProcessId; end);
  Add('FormatFloat', procedure begin FormatFloat('0.0', 1.5, TFormatSettings.Invariant); end);
  Add('StatusMarkdown', procedure var mStatus: TServerStatus; begin mStatus := Default(TServerStatus);
    mStatus.ProcessId := 1; mStatus.Mapped(ProbeMarkValue).ToMarkdown; end);
  Add('StatusJsonRecord', procedure var mStatus: TServerStatus; begin mStatus := Default(TServerStatus);
    mStatus.ProcessId := 1; mStatus.ToJson.Free; end);
  Add('NewServices', procedure begin mSelf.NewServices; end);
  Add('StatusJsonFull', procedure var mReports: TShellStatusReports; begin
    mReports := TShellStatusReports.Create(mSelf.NewServices);
    try mReports.StatusJson(True).Free; finally mReports.Free; end; end);
  mLines := TStringList.Create;
  try
    for mIndex := 0 to High(mSteps) do
    begin
      for mRound := 0 to 1 do
      begin
        mBefore := TShutdownLeaks.AllocatedBytes;
        mSteps[mIndex]();
        mDelta[mRound] := TShutdownLeaks.AllocatedBytes - mBefore;
      end;
      mLines.Add(Format('%s: erster %d, zweiter %d', [mNames[mIndex], mDelta[0], mDelta[1]]));
    end;
    mLines.SaveToFile(TPath.Combine(TPath.GetTempPath, 'atlas-probe-status.txt'));
  finally
    mLines.Free;
  end;
  mSteps := nil;
  mNames := nil;
  FLog := nil;
  Assert.IsTrue(True);
end;

procedure TShellStatusReportsTests.TearDown;
begin
  FLog := nil;
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
    mAnswer := mCommands.Execute(TBugReport.cCommand, mArguments);
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
  Assert.IsTrue(Pos(TProductVersion.cVersion, mText) > 0);
  Assert.AreEqual('Fehlerbericht erstellt', FLog[High(FLog)]);
end;

initialization
  TDUnitX.RegisterTestFixture(TShellStatusReportsTests);

end.
