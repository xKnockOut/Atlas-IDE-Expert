unit Atlas.Common.Lsp.PullDiagnostics.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspPullDiagnosticsTests = class
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure DetectsClientSupport;
    [Test]
    procedure OffersWorkspaceDiagnostics;
    [Test]
    procedure ReportsOpenDocumentThenUnchanged;
    [Test]
    procedure ChangeStartsNewGeneration;
    [Test]
    procedure ReportsClosedFilesInWorkspace;
    [Test]
    procedure WorkspaceSkipsKnownAndOpenFiles;
    [Test]
    procedure WorkspaceWaitsWhileIndexLoads;
    [Test]
    procedure WorkspaceStartsWhenIndexFinishes;
    /// <summary>Gleiche Datei im gleichen Stand ohne previousResultId: nicht neu prüfen.</summary>
    [Test]
    procedure ReusesReportForSameState;
    /// <summary>Eine zweite gleichzeitige workspace/diagnostic-Anfrage prüft nicht noch einmal.</summary>
    [Test]
    procedure WorkspaceRequestDoesNotCompute;
    /// <summary>Ein Abbruch wirkt vor der nächsten Prüfregel, nicht erst am Ende (Diagnoselog 15.10.2026).</summary>
    [Test]
    procedure CancelStopsRuleChecks;
    /// <summary>#1761: Dauert die Prüfung einer geöffneten Datei länger als OpenJobs.WaitMs, antwortet die Anfrage
    /// mit ServerCancelled statt ins Zeitlimit zu laufen; die Prüfung rechnet zu Ende und legt ab, die nächste
    /// Anfrage prüft nicht neu.</summary>
    [Test]
    procedure SlowOpenDocumentAnswersBeforeTimeout;
    /// <summary>Zwei gleichzeitige Anfragen für denselben Stand prüfen nur einmal.</summary>
    [Test]
    procedure ParallelRequestsForSameStateComputeOnce;
    /// <summary>Long-Polling endet vor dem Zeitlimit des Watchdogs.</summary>
    [Test]
    procedure LongPollFollowsRequestTimeout;
    [Test]
    procedure WorkspaceWaitEndsBeforeRequestTimeout;
    /// <summary>Changed weckt die prüfende und die zweite, wartende Anfrage sofort.</summary>
    [Test]
    procedure SecondWorkspaceRequestWakesOnChange;
    /// <summary>#1094: Scheitert eine Datei, überspringt workspace/diagnostic sie und prüft die übrigen; das
    /// Diagnoselog nennt die Unit anonym.</summary>
    [Test]
    procedure WorkspaceSkipsFailingFile;
    /// <summary>#1094: Endet textDocument/diagnostic mit einem Fehler, bleibt die Unit für das Diagnoselog
    /// offen.</summary>
    [Test]
    procedure DocumentErrorKeepsUnitForLog;
    /// <summary>#1220: Eine Datei über der Frist blockiert nichts; der Hintergrund prüft sie zu Ende, die nächste
    /// Antwort bringt sie aus dem Cache.</summary>
    [Test]
    procedure SlowFileFinishesAtEndOfRun;
    [Test]
    procedure CompilerMessagesRecheckOnlyTheirFiles;
    [Test]
    procedure ClientPausesRun;
    [Test]
    procedure WorkspaceReportCarriesRun;
    /// <summary>Während eines Laufs bündelt eine Anfrage die Befunde mehrerer Units, statt je Unit zu antworten
    /// (Diagnoselog 29.10.2026: 970 Anfragen mit je einem Befund).</summary>
    [Test]
    procedure WorkspaceBundlesReportsDuringRun;
  end;

implementation

uses
  System.Generics.Collections,
  System.SysUtils,
  System.Diagnostics,
  System.Classes,
  System.SyncObjs,
  System.JSON,
  Atlas.Common.Configuration.Contract,
  Atlas.Tests.RuleAssert,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.PendingRequests,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Lsp.SyntaxDiagnostics,
  Atlas.Common.Lsp.PullDiagnostics,
  Atlas.Common.Diagnostics.RequestScope;

const
  cOpenFile = 'C:\P\Offen.pas';
  cClosedFile = 'C:\P\Zu.pas';
  // Syntaxfehler: fehlendes "then".
  cBroken = 'unit Zu;'#10'interface'#10'implementation'#10'procedure X;'#10'begin'#10'  if True'#10'  X;'#10'end;'#10'end.';
  cValid = 'unit Offen;'#10'interface'#10'implementation'#10'end.';

type
  TFixture = record
    Store: IDocumentStore;
    Diagnostics: TLspSyntaxDiagnostics;
    Pull: TLspPullDiagnostics;
    procedure Init; overload;
    /// <summary>Mit Prüfregeln aus ARules.</summary>
    procedure Init(const ARules: TRuleContextProvider); overload;
    procedure Done;
  end;

procedure TFixture.Init;
begin
  Init(nil);
end;

procedure TFixture.Init(const ARules: TRuleContextProvider);
var
  mProviders: TSyntaxDiagnosticsProviders;
begin
  Store := TDocumentStore.Create;
  Store.Open(TDocumentUris.FromPath(cOpenFile), 'objectpascal', 1, cValid);
  mProviders := Default(TSyntaxDiagnosticsProviders);
  mProviders.Rules := ARules;
  Diagnostics := TLspSyntaxDiagnostics.Create(Store, nil, mProviders, 0);
  Diagnostics.PullMode := True;
  Pull := TLspPullDiagnostics.Create(Store, Diagnostics, nil,
    function: TArray<string>
    begin
      Result := [cOpenFile, cClosedFile];
    end,
    function(const AFileName: string; out AStamp: Int64): Boolean
    begin
      AStamp := 42;
      Result := True;
    end,
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := cBroken;
      Result := SameText(AFileName, cClosedFile);
    end);
  Pull.WaitMs := 0;
end;

procedure TFixture.Done;
begin
  Pull.Free;
  Diagnostics.Free;
end;

function Token: IJsonRpcCancellationToken;
begin
  Result := TJsonRpcCancellation.Create;
end;

procedure TLspPullDiagnosticsTests.WarmUpFirstUse;
begin
  CancelStopsRuleChecks;
end;

procedure TLspPullDiagnosticsTests.DetectsClientSupport;
var
  mParams: TJSONObject;
begin
  mParams := TJSONObject.ParseJSONValue(
    '{"capabilities":{"textDocument":{"diagnostic":{}},"workspace":{"diagnostics":{"refreshSupport":true}}}}')
    as TJSONObject;
  try
    Assert.IsTrue(TLspPullProtocol.ClientSupportsPull(mParams));
    Assert.IsTrue(TLspPullProtocol.ClientSupportsRefresh(mParams));
  finally
    mParams.Free;
  end;
  mParams := TJSONObject.ParseJSONValue('{"capabilities":{"textDocument":{}}}') as TJSONObject;
  try
    Assert.IsFalse(TLspPullProtocol.ClientSupportsPull(mParams));
    Assert.IsFalse(TLspPullProtocol.ClientSupportsRefresh(mParams));
  finally
    mParams.Free;
  end;
  Assert.IsFalse(TLspPullProtocol.ClientSupportsPull(nil));
end;

procedure TLspPullDiagnosticsTests.OffersWorkspaceDiagnostics;
var
  mCapability: TJSONObject;
begin
  mCapability := TLspPullProtocol.Capability;
  try
    Assert.IsTrue(mCapability.GetValue<Boolean>('workspaceDiagnostics'));
    Assert.IsTrue(mCapability.GetValue<Boolean>('interFileDependencies'));
  finally
    mCapability.Free;
  end;
end;

procedure TLspPullDiagnosticsTests.ReportsOpenDocumentThenUnchanged;
var
  mFixture: TFixture;
  mReport: TJSONObject;
  mResultId: string;
begin
  mFixture.Init;
  try
    mReport := mFixture.Pull.DocumentReport(TDocumentUris.FromPath(cOpenFile), '', nil);
    try
      Assert.AreEqual('full', mReport.GetValue<string>('kind'));
      Assert.AreEqual(0, mReport.GetValue<TJSONArray>('items').Count);
      mResultId := mReport.GetValue<string>('resultId');
    finally
      mReport.Free;
    end;
    mReport := mFixture.Pull.DocumentReport(TDocumentUris.FromPath(cOpenFile), mResultId, nil);
    try
      Assert.AreEqual('unchanged', mReport.GetValue<string>('kind'));
      Assert.IsNull(mReport.GetValue('items'));
    finally
      mReport.Free;
    end;
  finally
    mFixture.Done;
  end;
end;

procedure TLspPullDiagnosticsTests.ChangeStartsNewGeneration;
var
  mFixture: TFixture;
  mReport: TJSONObject;
  mResultId: string;
begin
  mFixture.Init;
  try
    mReport := mFixture.Pull.DocumentReport(TDocumentUris.FromPath(cClosedFile), '', nil);
    try
      Assert.IsTrue(mReport.GetValue<TJSONArray>('items').Count > 0, 'Syntaxfehler der geschlossenen Datei');
      mResultId := mReport.GetValue<string>('resultId');
    finally
      mReport.Free;
    end;
    mFixture.Pull.Changed;
    mReport := mFixture.Pull.DocumentReport(TDocumentUris.FromPath(cClosedFile), mResultId, nil);
    try
      Assert.AreEqual('full', mReport.GetValue<string>('kind'));
    finally
      mReport.Free;
    end;
  finally
    mFixture.Done;
  end;
end;

procedure TLspPullDiagnosticsTests.ReportsClosedFilesInWorkspace;
var
  mFixture: TFixture;
  mResult_: TJSONValue;
  mItems: TJSONArray;
begin
  mFixture.Init;
  try
    // Die Projektprüfung rechnet im eigenen Thread; das Long-Polling wartet auf ihr Ergebnis.
    mFixture.Pull.WaitMs := 5000;
    mResult_ := mFixture.Pull.WorkspaceReport(nil, Token);
    try
      mItems := (mResult_ as TJSONObject).GetValue<TJSONArray>('items');
      Assert.AreEqual(1, Integer(mItems.Count), 'nur die geschlossene Datei');
      Assert.AreEqual(TDocumentUris.FromPath(cClosedFile), mItems.Items[0].GetValue<string>('uri'));
      Assert.AreEqual('full', mItems.Items[0].GetValue<string>('kind'));
      Assert.IsTrue(mItems.Items[0].GetValue<TJSONArray>('items').Count > 0);
    finally
      mResult_.Free;
    end;
  finally
    mFixture.Done;
  end;
end;

/// <summary>previousResultIds mit AUri und AId.</summary>
function PreviousParams(const AUri, AId: string): TJSONObject;
var
  mEntry: TJSONObject;
begin
  mEntry := TJSONObject.Create;
  mEntry.AddPair('uri', AUri);
  mEntry.AddPair('value', AId);
  Result := TJSONObject.Create;
  Result.AddPair('previousResultIds', TJSONArray.Create(mEntry));
end;

procedure TLspPullDiagnosticsTests.WorkspaceSkipsKnownAndOpenFiles;
var
  mFixture: TFixture;
  mParams: TJSONObject;
  mResult_: TJSONValue;
  mId: string;
begin
  mFixture.Init;
  try
    mFixture.Pull.WorkspaceReport(nil, Token).Free;
    Assert.IsTrue(mFixture.Pull.Check.WaitIdle(5000));
    mResult_ := mFixture.Pull.WorkspaceReport(nil, Token);
    try
      mId := (mResult_ as TJSONObject).GetValue<TJSONArray>('items').Items[0].GetValue<string>('resultId');
    finally
      mResult_.Free;
    end;
    mParams := PreviousParams(TDocumentUris.FromPath(cClosedFile), mId);
    try
      mResult_ := mFixture.Pull.WorkspaceReport(mParams, Token);
      try
        Assert.AreEqual(0, (mResult_ as TJSONObject).GetValue<TJSONArray>('items').Count);
      finally
        mResult_.Free;
      end;
    finally
      mParams.Free;
    end;
  finally
    mFixture.Done;
  end;
end;

procedure TLspPullDiagnosticsTests.WorkspaceWaitsWhileIndexLoads;
var
  mFixture: TFixture;
  mResult_: TJSONValue;
begin
  // Während des Indexaufbaus keine Befunde: Sie wären voller nicht gefundener Units (#647).
  mFixture.Init;
  try
    mFixture.Pull.Busy :=
      function: Boolean
      begin
        Result := True;
      end;
    mFixture.Pull.WorkspaceReport(nil, Token).Free;
    Sleep(300);
    mResult_ := mFixture.Pull.WorkspaceReport(nil, Token);
    try
      Assert.AreEqual(0, (mResult_ as TJSONObject).GetValue<TJSONArray>('items').Count);
      Assert.AreEqual('index', (mResult_ as TJSONObject).GetValue<string>('atlas.run.paused'));
    finally
      mResult_.Free;
    end;
    Assert.AreEqual(0, mFixture.Pull.Computed);
  finally
    mFixture.Done;
  end;
end;

procedure TLspPullDiagnosticsTests.WorkspaceStartsWhenIndexFinishes;
var
  mFixture: TFixture;
  mResult_: TJSONValue;
  mCalls, mAttempts: Integer;
begin
  // Wird der Index während des Wartens fertig, kommen die Befunde, sobald die Prüfung sie hat.
  mFixture.Init;
  try
    mCalls := 0;
    mFixture.Pull.WaitMs := 5000;
    mFixture.Pull.Busy :=
      function: Boolean
      begin
        Inc(mCalls);
        Result := mCalls < 3;
      end;
    // Antworten ohne Befunde melden Beginn und Ende der Pause; der Client fragt gleich wieder.
    mResult_ := mFixture.Pull.WorkspaceReport(nil, Token);
    try
      mAttempts := 1;
      while ((mResult_ as TJSONObject).GetValue<TJSONArray>('items').Count = 0) and (mAttempts < 5) do
      begin
        mResult_.Free;
        mResult_ := nil;
        mResult_ := mFixture.Pull.WorkspaceReport(nil, Token);
        Inc(mAttempts);
      end;
      Assert.AreEqual(1, (mResult_ as TJSONObject).GetValue<TJSONArray>('items').Count);
    finally
      mResult_.Free;
    end;
  finally
    mFixture.Done;
  end;
end;

procedure TLspPullDiagnosticsTests.ReusesReportForSameState;
var
  mFixture: TFixture;
  mFirst, mSecond: TJSONObject;
begin
  mFixture.Init;
  try
    mFirst := mFixture.Pull.DocumentReport(TDocumentUris.FromPath(cClosedFile), '', nil);
    mSecond := mFixture.Pull.DocumentReport(TDocumentUris.FromPath(cClosedFile), '', nil);
    try
      Assert.AreEqual(1, mFixture.Pull.Computed, 'einmal geprüft');
      Assert.AreEqual('full', mSecond.GetValue<string>('kind'));
      Assert.AreEqual(mFirst.GetValue<TJSONArray>('items').ToJSON, mSecond.GetValue<TJSONArray>('items').ToJSON);
      // Neue Generation: wieder prüfen.
      mFixture.Pull.Changed;
      mSecond.Free;
      mSecond := mFixture.Pull.DocumentReport(TDocumentUris.FromPath(cClosedFile), '', nil);
      Assert.AreEqual(2, mFixture.Pull.Computed, 'nach Changed neu geprüft');
    finally
      mSecond.Free;
      mFirst.Free;
    end;
  finally
    mFixture.Done;
  end;
end;

procedure TLspPullDiagnosticsTests.WorkspaceRequestDoesNotCompute;
var
  mFixture: TFixture;
  mResult_: TJSONValue;
begin
  // Anfragen liefern nur gespeicherte Befunde (#1247): auch gleichzeitige oder wiederholte rechnen nicht.
  mFixture.Init;
  try
    mFixture.Pull.WorkspaceReport(nil, Token).Free;
    Assert.IsTrue(mFixture.Pull.Check.WaitIdle(5000));
    Assert.AreEqual(1, mFixture.Pull.Computed);
    mResult_ := mFixture.Pull.WorkspaceReport(nil, Token);
    try
      Assert.AreEqual(1, (mResult_ as TJSONObject).GetValue<TJSONArray>('items').Count);
    finally
      mResult_.Free;
    end;
    mFixture.Pull.WorkspaceReport(nil, Token).Free;
    Assert.AreEqual(1, mFixture.Pull.Computed, 'nicht neu geprüft');
  finally
    mFixture.Done;
  end;
end;

procedure TLspPullDiagnosticsTests.CancelStopsRuleChecks;
var
  mFixture: TFixture;
  mRules: TRuleContextProvider;
  mSource: IJsonRpcCancellationSource;
  mRuns: Integer;
begin
  mRules :=
    function(const AUri: string; out AContext: TRuleCheckContext): Boolean
    begin
      AContext := Default(TRuleCheckContext);
      AContext.Settings := TServerSettings.Default;
      AContext.Rules := [
        TCallbackRule.Create('erste',
          procedure
          begin
            Inc(mRuns);
            mSource.Cancel;
          end),
        TCallbackRule.Create('zweite',
          procedure
          begin
            Inc(mRuns);
          end)];
      Result := True;
    end;
  mFixture.Init(mRules);
  try
    mRuns := 0;
    mSource := TJsonRpcCancellation.Create;
    // Datei von der Platte: Geöffnete Dateien prüft ein eigener Thread zu Ende (#1761).
    Assert.WillRaise(
      procedure
      begin
        mFixture.Pull.DocumentReport(TDocumentUris.FromPath(cClosedFile), '', mSource).Free;
      end, EJsonRpcRequestCancelled);
    Assert.AreEqual(1, mRuns);
    Assert.AreEqual(0, mFixture.Pull.Computed);
  finally
    mFixture.Done;
  end;
end;

procedure TLspPullDiagnosticsTests.SlowOpenDocumentAnswersBeforeTimeout;
var
  mFixture: TFixture;
  mRules: TRuleContextProvider;
  mGo: TEvent;
  mCode: Integer;
  mClock: TStopwatch;
  mReport: TJSONObject;
  mUri: string;
begin
  mGo := TEvent.Create(nil, True, False, '');
  try
    mRules :=
      function(const AUri: string; out AContext: TRuleCheckContext): Boolean
      begin
        AContext := Default(TRuleCheckContext);
        AContext.Settings := TServerSettings.Default;
        AContext.Rules := [
          TCallbackRule.Create('langsam',
            procedure
            begin
              mGo.WaitFor(10000);
            end)];
        Result := True;
      end;
    mFixture.Init(mRules);
    try
      mFixture.Pull.OpenJobs.WaitMs := 50;
      mUri := TDocumentUris.FromPath(cOpenFile);
      mCode := 0;
      try
        mFixture.Pull.DocumentReport(mUri, '', Token).Free;
      except
        on E: EJsonRpcError do
          mCode := E.Code;
      end;
      Assert.AreEqual(TLspErrorCode.cServerCancelled, mCode, 'Antwort vor dem Zeitlimit');
      Assert.AreEqual(0, mFixture.Pull.Computed);
      // Die Prüfung rechnet weiter und legt ab.
      mGo.SetEvent;
      mClock := TStopwatch.StartNew;
      while (mFixture.Pull.Computed = 0) and (mClock.ElapsedMilliseconds < 10000) do
      begin
        Sleep(10);
      end;
      Assert.AreEqual(1, mFixture.Pull.Computed);
      mReport := mFixture.Pull.DocumentReport(mUri, '', Token);
      try
        Assert.AreEqual('full', mReport.GetValue<string>('kind'));
      finally
        mReport.Free;
      end;
      Assert.AreEqual(1, mFixture.Pull.Computed, 'aus dem Speicher');
    finally
      mFixture.Done;
    end;
  finally
    mGo.Free;
  end;
end;

procedure TLspPullDiagnosticsTests.ParallelRequestsForSameStateComputeOnce;
var
  mFixture: TFixture;
  mRules: TRuleContextProvider;
  mRuns: Integer;
  mWorker: TThread;
  mMine, mOther: TJSONObject;
begin
  mRules :=
    function(const AUri: string; out AContext: TRuleCheckContext): Boolean
    begin
      AContext := Default(TRuleCheckContext);
      AContext.Settings := TServerSettings.Default;
      AContext.Rules := [
        TCallbackRule.Create('langsam',
          procedure
          begin
            TInterlocked.Increment(mRuns);
            Sleep(300);
          end)];
      Result := True;
    end;
  mFixture.Init(mRules);
  try
    mRuns := 0;
    mOther := nil;
    mWorker := TThread.CreateAnonymousThread(
      procedure
      begin
        mOther := mFixture.Pull.DocumentReport(TDocumentUris.FromPath(cOpenFile), '', Token);
      end);
    mWorker.FreeOnTerminate := False;
    mWorker.Start;
    try
      Sleep(100);
      mMine := mFixture.Pull.DocumentReport(TDocumentUris.FromPath(cOpenFile), '', Token);
      mWorker.WaitFor;
    finally
      mWorker.Free;
    end;
    try
      Assert.AreEqual(1, mRuns);
      Assert.AreEqual(1, mFixture.Pull.Computed);
      Assert.IsNotNull(mOther);
      Assert.AreEqual(mOther.GetValue('resultId').Value, mMine.GetValue('resultId').Value);
    finally
      mMine.Free;
      mOther.Free;
    end;
  finally
    mFixture.Done;
  end;
end;

procedure TLspPullDiagnosticsTests.LongPollFollowsRequestTimeout;
begin
  Assert.AreEqual<Cardinal>(8000, TLspPullProtocol.LongPollMs(10000, 10000));
  Assert.AreEqual<Cardinal>(10000, TLspPullProtocol.LongPollMs(10000, 60000));
  Assert.AreEqual<Cardinal>(500, TLspPullProtocol.LongPollMs(10000, 1000));
  Assert.AreEqual<Cardinal>(10000, TLspPullProtocol.LongPollMs(10000, 0));
  Assert.AreEqual<Cardinal>(0, TLspPullProtocol.LongPollMs(0, 10000));
end;

procedure TLspPullDiagnosticsTests.WorkspaceWaitEndsBeforeRequestTimeout;
var
  mFixture: TFixture;
  mResult_: TJSONValue;
  mClock: TStopwatch;
begin
  mFixture.Init;
  try
    mFixture.Pull.WaitMs := 10000;
    // Index lädt: nichts zu prüfen, die Anfrage wartet bis zum Zeitrahmen (1000 ms Limit -> 500 ms).
    mFixture.Pull.Busy :=
      function: Boolean
      begin
        Result := True;
      end;
    mFixture.Pull.RequestTimeout :=
      function: Cardinal
      begin
        Result := 1000;
      end;
    // Die erste Anfrage meldet den Beginn des Laufs; die zweite hat nichts Neues und wartet.
    mFixture.Pull.WorkspaceReport(nil, Token).Free;
    Sleep(300);
    mClock := TStopwatch.StartNew;
    mResult_ := mFixture.Pull.WorkspaceReport(nil, Token);
    try
      Assert.AreEqual(0, (mResult_ as TJSONObject).GetValue<TJSONArray>('items').Count);
    finally
      mResult_.Free;
    end;
    Assert.IsTrue(mClock.ElapsedMilliseconds >= 400, IntToStr(mClock.ElapsedMilliseconds));
    Assert.IsTrue(mClock.ElapsedMilliseconds <= 900, IntToStr(mClock.ElapsedMilliseconds));
  finally
    mFixture.Done;
  end;
end;

procedure TLspPullDiagnosticsTests.SecondWorkspaceRequestWakesOnChange;
var
  mFixture: TFixture;
  mPull: TLspPullDiagnostics;
  mLoading: Boolean;
  mFirst, mSecond: TThread;
  mFirstMs, mSecondMs: Int64;
  mClock: TStopwatch;
begin
  mFixture.Init;
  try
    mPull := mFixture.Pull;
    mPull.WaitMs := 5000;
    mLoading := True;
    mPull.Busy :=
      function: Boolean
      begin
        Result := mLoading;
      end;
    mFirstMs := -1;
    mSecondMs := -1;
    mClock := TStopwatch.StartNew;
    mFirst := TThread.CreateAnonymousThread(
      procedure
      begin
        mPull.WorkspaceReport(nil, Token).Free;
        mFirstMs := mClock.ElapsedMilliseconds;
      end);
    mFirst.FreeOnTerminate := False;
    mSecond := TThread.CreateAnonymousThread(
      procedure
      begin
        mPull.WorkspaceReport(nil, Token).Free;
        mSecondMs := mClock.ElapsedMilliseconds;
      end);
    mSecond.FreeOnTerminate := False;
    try
      mFirst.Start;
      // Die erste hält den Platz; die zweite wartet nur.
      Sleep(50);
      mSecond.Start;
      Sleep(200);
      // Index fertig: Changed weckt beide.
      mLoading := False;
      mPull.Changed;
      mFirst.WaitFor;
      mSecond.WaitFor;
    finally
      mFirst.Free;
      mSecond.Free;
    end;
    Assert.IsTrue((mFirstMs >= 0) and (mFirstMs < 1000), IntToStr(mFirstMs));
    Assert.IsTrue((mSecondMs >= 0) and (mSecondMs < 1000), IntToStr(mSecondMs));
  finally
    mFixture.Done;
  end;
end;

const
  cFailingFile = 'C:\P\Kaputt.pas';

/// <summary>Regeln für alle Dateien; für FailingFile scheitert schon das Bereitstellen.</summary>
function FailingRules: TRuleContextProvider;
begin
  Result :=
    function(const AUri: string; out AContext: TRuleCheckContext): Boolean
    begin
      if SameText(TDocumentUris.ToPath(AUri), cFailingFile) then
      begin
        raise EArgumentException.Create('Unit kaputt');
      end;
      AContext := Default(TRuleCheckContext);
      AContext.Settings := TServerSettings.Default;
      Result := True;
    end;
end;

function LabelOfFile(const AFileName: string): string;
begin
  Result := 'unit#2';
  if SameText(AFileName, cFailingFile) then
  begin
    Result := 'unit#1';
  end;
end;

/// <summary>Abfrage mit der kaputten Datei vorn; Protokollzeilen landen in ALogged.</summary>
function CreateFailingFirstPull(const AStore: IDocumentStore; const ADiagnostics: TLspSyntaxDiagnostics;
  const ALogged: TStringList): TLspPullDiagnostics;
begin
  Result := TLspPullDiagnostics.Create(AStore, ADiagnostics, nil,
    function: TArray<string>
    begin
      Result := [cFailingFile, cClosedFile];
    end,
    function(const AFileName: string; out AStamp: Int64): Boolean
    begin
      AStamp := 42;
      Result := True;
    end,
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := cBroken;
      Result := True;
    end);
  Result.WaitMs := 0;
  Result.FileLabel := LabelOfFile;
  Result.Check.OnLog :=
    procedure(const AMessage: string)
    begin
      TMonitor.Enter(ALogged);
      try
        ALogged.Add(AMessage);
      finally
        TMonitor.Exit(ALogged);
      end;
    end;
end;

/// <summary>Zwei Einträge: die kaputte Datei leer übersprungen, die nächste mit Befunden.</summary>
procedure AssertFailingFileSkipped(const AReport: TJSONValue);
var
  mItems: TJSONArray;
  mItem: TJSONValue;
  mEmpty, mFound: Integer;
begin
  mItems := (AReport as TJSONObject).GetValue<TJSONArray>('items');
  Assert.AreEqual(2, Integer(mItems.Count));
  mEmpty := 0;
  mFound := 0;
  for mItem in mItems do
  begin
    if mItem.GetValue<TJSONArray>('items').Count = 0 then
    begin
      Inc(mEmpty);
      Assert.AreEqual(TDocumentUris.FromPath(cFailingFile), mItem.GetValue<string>('uri'), 'übersprungen');
    end
    else
    begin
      Inc(mFound);
    end;
  end;
  Assert.AreEqual(1, mEmpty);
  Assert.AreEqual(1, mFound, 'die nächste Datei läuft weiter');
end;

procedure TLspPullDiagnosticsTests.WorkspaceSkipsFailingFile;
var
  mStore: IDocumentStore;
  mDiagnostics: TLspSyntaxDiagnostics;
  mProviders: TSyntaxDiagnosticsProviders;
  mPull: TLspPullDiagnostics;
  mResult_: TJSONValue;
  mLogged: TStringList;
begin
  mStore := TDocumentStore.Create;
  mProviders := Default(TSyntaxDiagnosticsProviders);
  mProviders.Rules := FailingRules();
  mDiagnostics := TLspSyntaxDiagnostics.Create(mStore, nil, mProviders, 0);
  mLogged := TStringList.Create;
  mPull := nil;
  try
    mDiagnostics.PullMode := True;
    // Die kaputte Datei steht vorn: früher scheiterte daran jede Anfrage, bis der Server starb.
    mPull := CreateFailingFirstPull(mStore, mDiagnostics, mLogged);
    mPull.WorkspaceReport(nil, Token).Free;
    Assert.IsTrue(mPull.Check.WaitIdle(5000));
    mResult_ := mPull.WorkspaceReport(nil, Token);
    try
      AssertFailingFileSkipped(mResult_);
    finally
      mResult_.Free;
    end;
    Assert.AreEqual(1, mPull.Check.Skipped);
    Assert.Contains(mLogged.Text, 'unit#1 übersprungen (EArgumentException)');
    Assert.DoesNotContain(mLogged.Text, 'Kaputt.pas');
  finally
    mPull.Free;
    mDiagnostics.Free;
    mLogged.Free;
  end;
end;

procedure TLspPullDiagnosticsTests.DocumentErrorKeepsUnitForLog;
var
  mFixture: TFixture;
  mRules: TRuleContextProvider;
  mNotes: TRequestNotes;
begin
  mRules :=
    function(const AUri: string; out AContext: TRuleCheckContext): Boolean
    begin
      AContext := Default(TRuleCheckContext);
      raise EArgumentException.Create('Unit kaputt');
    end;
  mFixture.Init(mRules);
  try
    mFixture.Pull.FileLabel := LabelOfFile;
    TRequestDiagnostics.Open;
    try
      Assert.WillRaise(
        procedure
        begin
          mFixture.Pull.DocumentReport(TDocumentUris.FromPath(cOpenFile), '', Token).Free;
        end, EArgumentException);
    finally
      mNotes := TRequestDiagnostics.Close;
    end;
    Assert.AreEqual('unit#2', mNotes.Subject);
  finally
    mFixture.Done;
  end;
end;

procedure TLspPullDiagnosticsTests.SlowFileFinishesAtEndOfRun;
var
  mFixture: TFixture;
  mRules: TRuleContextProvider;
  mAnswer: TJSONValue;
begin
  mRules :=
    function(const AUri: string; out AContext: TRuleCheckContext): Boolean
    begin
      AContext := Default(TRuleCheckContext);
      AContext.Settings := TServerSettings.Default;
      AContext.Rules := [
        TCallbackRule.Create('langsam',
          procedure
          begin
            Sleep(200);
          end),
        TCallbackRule.Create('danach',
          procedure
          begin
          end)];
      Result := True;
    end;
  mFixture.Init(mRules);
  try
    // Über der Frist (#1220): Die Datei kommt ans Ende des Laufs und wird ohne Frist zu Ende geprüft.
    mFixture.Pull.Check.FileLimitMs := 50;
    mFixture.Pull.WorkspaceReport(nil, Token).Free;
    Assert.IsTrue(mFixture.Pull.Check.WaitIdle(5000));
    mAnswer := mFixture.Pull.WorkspaceReport(nil, Token);
    try
      Assert.AreEqual(1, TJSONObject(mAnswer).GetValue<TJSONArray>('items').Count);
    finally
      mAnswer.Free;
    end;
  finally
    mFixture.Done;
  end;
end;

procedure TLspPullDiagnosticsTests.CompilerMessagesRecheckOnlyTheirFiles;
var
  mFixture: TFixture;
  mPull: TLspPullDiagnostics;
  mGeneration: Integer;
begin
  mFixture.Init;
  try
    mFixture.Pull.WorkspaceReport(nil, Token).Free;
    Assert.IsTrue(mFixture.Pull.Check.WaitIdle(5000));
    Assert.AreEqual(1, mFixture.Pull.Computed);
    mGeneration := mFixture.Pull.Generation;
    // Verdrahtung wie in der Composition.
    mPull := mFixture.Pull;
    mFixture.Diagnostics.OnPullFilesChanged :=
      procedure(AFiles: TArray<string>)
      begin
        mPull.FilesChanged(AFiles);
      end;
    // Neue Compilermeldungen nur für die geschlossene Datei: Nur sie wird neu geprüft (#1247).
    mFixture.Diagnostics.RefreshFiles(TArray<string>.Create(cClosedFile));
    Assert.IsTrue(mFixture.Pull.Check.WaitIdle(5000));
    Assert.AreEqual(2, mFixture.Pull.Computed);
    Assert.AreEqual(1, mFixture.Pull.Check.Run.Total);
    Assert.AreEqual(mGeneration + 1, mFixture.Pull.Generation, 'geöffnete Dateien holt der Client neu');
  finally
    mFixture.Done;
  end;
end;

procedure Notify(ADispatcher: TJsonRpcDispatcher; const AMethod, AParams: string);
var
  mMessage: TJSONObject;
begin
  mMessage := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","method":"' + AMethod + '","params":' + AParams + '}')
    as TJSONObject;
  try
    ADispatcher.DispatchMessage(mMessage).Free;
  finally
    mMessage.Free;
  end;
end;

procedure TLspPullDiagnosticsTests.ClientPausesRun;
var
  mFixture: TFixture;
  mDispatcher: TJsonRpcDispatcher;
begin
  // Beim Debuggen ruht die Projektprüfung (#1241); das Plugin meldet es mit atlas/workspaceCheck/pause.
  mFixture.Init;
  mDispatcher := TJsonRpcDispatcher.Create;
  try
    mFixture.Pull.Attach(mDispatcher);
    Notify(mDispatcher, TLspPullDiagnostics.cPauseMethod, '{"reason":"debug","paused":true}');
    mFixture.Pull.WorkspaceReport(nil, Token).Free;
    Sleep(300);
    Assert.AreEqual(0, mFixture.Pull.Computed);
    Assert.AreEqual('debug', mFixture.Pull.Check.Run.Paused);
    Notify(mDispatcher, TLspPullDiagnostics.cPauseMethod, '{"reason":"debug","paused":false}');
    Assert.IsTrue(mFixture.Pull.Check.WaitIdle(5000));
    Assert.AreEqual(1, mFixture.Pull.Computed);
  finally
    mDispatcher.Free;
    mFixture.Done;
  end;
end;

procedure TLspPullDiagnosticsTests.WorkspaceReportCarriesRun;
var
  mFixture: TFixture;
  mAnswer: TJSONValue;
begin
  mFixture.Init;
  try
    mFixture.Pull.WorkspaceReport(nil, Token).Free;
    Assert.IsTrue(mFixture.Pull.Check.WaitIdle(5000));
    mAnswer := mFixture.Pull.WorkspaceReport(nil, Token);
    try
      Assert.IsFalse(TJSONObject(mAnswer).GetValue<Boolean>('atlas.run.active'));
      Assert.AreEqual(2, TJSONObject(mAnswer).GetValue<Integer>('atlas.run.done'));
      Assert.AreEqual(2, TJSONObject(mAnswer).GetValue<Integer>('atlas.run.total'));
    finally
      mAnswer.Free;
    end;
  finally
    mFixture.Done;
  end;
end;

const
  cWorkspaceBundlescFileCount = 12;

/// <summary>Regeln, bei denen jede Unit etwas Zeit braucht, wie im echten Lauf.</summary>
function SlowRuleProviders: TSyntaxDiagnosticsProviders;
begin
  Result := Default(TSyntaxDiagnosticsProviders);
  Result.Rules :=
    function(const AUri: string; out AContext: TRuleCheckContext): Boolean
    begin
      AContext := Default(TRuleCheckContext);
      AContext.Settings := TServerSettings.Default;
      AContext.Rules := [
        TCallbackRule.Create('langsam',
          procedure
          begin
            Sleep(30);
          end)];
      Result := True;
    end;
end;

procedure TLspPullDiagnosticsTests.WorkspaceBundlesReportsDuringRun;
var
  mStore: IDocumentStore;
  mProviders: TSyntaxDiagnosticsProviders;
  mDiagnostics: TLspSyntaxDiagnostics;
  mPull: TLspPullDiagnostics;
  mFiles: TArray<string>;
  mIndex: Integer;
  mAnswer: TJSONValue;
begin
  mFiles := nil;
  for mIndex := 1 to cWorkspaceBundlescFileCount do
  begin
    mFiles := mFiles + [Format('C:\P\U%d.pas', [mIndex])];
  end;
  mStore := TDocumentStore.Create;
  mProviders := SlowRuleProviders;
  mDiagnostics := TLspSyntaxDiagnostics.Create(mStore, nil, mProviders, 0);
  try
    mDiagnostics.PullMode := True;
    mPull := TLspPullDiagnostics.Create(mStore, mDiagnostics, nil,
      function: TArray<string>
      begin
        Result := mFiles;
      end,
      function(const AFileName: string; out AStamp: Int64): Boolean
      begin
        AStamp := 42;
        Result := True;
      end,
      function(const AFileName: string; out AText: string): Boolean
      begin
        AText := cBroken;
        Result := True;
      end);
    try
      mPull.WaitMs := 5000;
      mAnswer := mPull.WorkspaceReport(nil, Token);
      try
        Assert.IsTrue(TJSONObject(mAnswer).GetValue<TJSONArray>('items').Count > 1,
          IntToStr(TJSONObject(mAnswer).GetValue<TJSONArray>('items').Count));
      finally
        mAnswer.Free;
      end;
    finally
      mPull.Free;
    end;
  finally
    mDiagnostics.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspPullDiagnosticsTests);

end.
