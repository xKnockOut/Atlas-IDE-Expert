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
    procedure SecondWorkspaceRequestDoesNotCollect;
    /// <summary>Ein Abbruch wirkt vor der nächsten Prüfregel, nicht erst am Ende (Diagnoselog 15.10.2026).</summary>
    [Test]
    procedure CancelStopsRuleChecks;
    /// <summary>Zwei gleichzeitige Anfragen für denselben Stand prüfen nur einmal.</summary>
    [Test]
    procedure ParallelRequestsForSameStateComputeOnce;
    /// <summary>Code-Review P-14: Long-Polling endet vor dem Zeitlimit des Watchdogs.</summary>
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
    /// <summary>#1094: Endet textDocument/diagnostic mit einem Fehler, bleibt die Unit für das Diagnoselog offen.</summary>
    [Test]
    procedure DocumentErrorKeepsUnitForLog;
    /// <summary>#1220: Eine Datei über der Frist blockiert nichts; der Hintergrund prüft sie zu Ende, die nächste
    /// Antwort bringt sie aus dem Cache.</summary>
    [Test]
    procedure SlowFileFinishesInBackground;
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
  Atlas.Common.Rules.Contract,
  Atlas.Tests.RuleAssert,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.PendingRequests,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Lsp.SyntaxDiagnostics,
  Atlas.Common.Lsp.PullDiagnostics,
  Atlas.Common.Diagnostics.RequestScope;

const
  OpenFile = 'C:\P\Offen.pas';
  ClosedFile = 'C:\P\Zu.pas';
  // Syntaxfehler: fehlendes "then".
  Broken = 'unit Zu;'#10'interface'#10'implementation'#10'procedure X;'#10'begin'#10'  if True'#10'  X;'#10'end;'#10'end.';
  Valid = 'unit Offen;'#10'interface'#10'implementation'#10'end.';

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
  Providers: TSyntaxDiagnosticsProviders;
begin
  Store := TDocumentStore.Create;
  Store.Open(TDocumentUris.FromPath(OpenFile), 'objectpascal', 1, Valid);
  Providers := Default(TSyntaxDiagnosticsProviders);
  Providers.Rules := ARules;
  Diagnostics := TLspSyntaxDiagnostics.Create(Store, nil, Providers, 0);
  Diagnostics.PullMode := True;
  Pull := TLspPullDiagnostics.Create(Store, Diagnostics, nil,
    function: TArray<string>
    begin
      Result := [OpenFile, ClosedFile];
    end,
    function(const AFileName: string; out AStamp: Int64): Boolean
    begin
      AStamp := 42;
      Result := True;
    end,
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := Broken;
      Result := SameText(AFileName, ClosedFile);
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
  Params: TJSONObject;
begin
  Params := TJSONObject.ParseJSONValue(
    '{"capabilities":{"textDocument":{"diagnostic":{}},"workspace":{"diagnostics":{"refreshSupport":true}}}}')
    as TJSONObject;
  try
    Assert.IsTrue(TLspPullDiagnostics.ClientSupportsPull(Params));
    Assert.IsTrue(TLspPullDiagnostics.ClientSupportsRefresh(Params));
  finally
    Params.Free;
  end;
  Params := TJSONObject.ParseJSONValue('{"capabilities":{"textDocument":{}}}') as TJSONObject;
  try
    Assert.IsFalse(TLspPullDiagnostics.ClientSupportsPull(Params));
    Assert.IsFalse(TLspPullDiagnostics.ClientSupportsRefresh(Params));
  finally
    Params.Free;
  end;
  Assert.IsFalse(TLspPullDiagnostics.ClientSupportsPull(nil));
end;

procedure TLspPullDiagnosticsTests.OffersWorkspaceDiagnostics;
var
  Capability: TJSONObject;
begin
  Capability := TLspPullDiagnostics.Capability;
  try
    Assert.IsTrue(Capability.GetValue<Boolean>('workspaceDiagnostics'));
    Assert.IsTrue(Capability.GetValue<Boolean>('interFileDependencies'));
  finally
    Capability.Free;
  end;
end;

procedure TLspPullDiagnosticsTests.ReportsOpenDocumentThenUnchanged;
var
  Fixture: TFixture;
  Report: TJSONObject;
  ResultId: string;
begin
  Fixture.Init;
  try
    Report := Fixture.Pull.DocumentReport(TDocumentUris.FromPath(OpenFile), '');
    try
      Assert.AreEqual('full', Report.GetValue<string>('kind'));
      Assert.AreEqual(0, Report.GetValue<TJSONArray>('items').Count);
      ResultId := Report.GetValue<string>('resultId');
    finally
      Report.Free;
    end;
    Report := Fixture.Pull.DocumentReport(TDocumentUris.FromPath(OpenFile), ResultId);
    try
      Assert.AreEqual('unchanged', Report.GetValue<string>('kind'));
      Assert.IsNull(Report.GetValue('items'));
    finally
      Report.Free;
    end;
  finally
    Fixture.Done;
  end;
end;

procedure TLspPullDiagnosticsTests.ChangeStartsNewGeneration;
var
  Fixture: TFixture;
  Report: TJSONObject;
  ResultId: string;
begin
  Fixture.Init;
  try
    Report := Fixture.Pull.DocumentReport(TDocumentUris.FromPath(ClosedFile), '');
    try
      Assert.IsTrue(Report.GetValue<TJSONArray>('items').Count > 0, 'Syntaxfehler der geschlossenen Datei');
      ResultId := Report.GetValue<string>('resultId');
    finally
      Report.Free;
    end;
    Fixture.Pull.Changed;
    Report := Fixture.Pull.DocumentReport(TDocumentUris.FromPath(ClosedFile), ResultId);
    try
      Assert.AreEqual('full', Report.GetValue<string>('kind'));
    finally
      Report.Free;
    end;
  finally
    Fixture.Done;
  end;
end;

procedure TLspPullDiagnosticsTests.ReportsClosedFilesInWorkspace;
var
  Fixture: TFixture;
  Result_: TJSONValue;
  Items: TJSONArray;
begin
  Fixture.Init;
  try
    Result_ := Fixture.Pull.WorkspaceReport(nil, Token);
    try
      Items := (Result_ as TJSONObject).GetValue<TJSONArray>('items');
      Assert.AreEqual(1, Integer(Items.Count), 'nur die geschlossene Datei');
      Assert.AreEqual(TDocumentUris.FromPath(ClosedFile), Items.Items[0].GetValue<string>('uri'));
      Assert.AreEqual('full', Items.Items[0].GetValue<string>('kind'));
      Assert.IsTrue(Items.Items[0].GetValue<TJSONArray>('items').Count > 0);
    finally
      Result_.Free;
    end;
  finally
    Fixture.Done;
  end;
end;

procedure TLspPullDiagnosticsTests.WorkspaceSkipsKnownAndOpenFiles;
var
  Fixture: TFixture;
  Params, Entry: TJSONObject;
  Result_: TJSONValue;
begin
  Fixture.Init;
  try
    Entry := TJSONObject.Create;
    Entry.AddPair('uri', TDocumentUris.FromPath(ClosedFile));
    Entry.AddPair('value', Format('%d:t42', [Fixture.Pull.Generation]));
    Params := TJSONObject.Create;
    Params.AddPair('previousResultIds', TJSONArray.Create(Entry));
    try
      Result_ := Fixture.Pull.WorkspaceReport(Params, Token);
      try
        Assert.AreEqual(0, (Result_ as TJSONObject).GetValue<TJSONArray>('items').Count);
      finally
        Result_.Free;
      end;
    finally
      Params.Free;
    end;
  finally
    Fixture.Done;
  end;
end;

procedure TLspPullDiagnosticsTests.WorkspaceWaitsWhileIndexLoads;
var
  Fixture: TFixture;
  Result_: TJSONValue;
begin
  // Während des Indexaufbaus keine Befunde: Sie wären voller nicht gefundener Units (#647).
  Fixture.Init;
  try
    Fixture.Pull.Busy :=
      function: Boolean
      begin
        Result := True;
      end;
    Result_ := Fixture.Pull.WorkspaceReport(nil, Token);
    try
      Assert.AreEqual(0, (Result_ as TJSONObject).GetValue<TJSONArray>('items').Count);
    finally
      Result_.Free;
    end;
  finally
    Fixture.Done;
  end;
end;

procedure TLspPullDiagnosticsTests.WorkspaceStartsWhenIndexFinishes;
var
  Fixture: TFixture;
  Result_: TJSONValue;
  Calls: Integer;
begin
  // Wird der Index während des Wartens fertig, kommen die Befunde noch in derselben Antwort.
  Fixture.Init;
  try
    Calls := 0;
    Fixture.Pull.WaitMs := 5000;
    Fixture.Pull.Busy :=
      function: Boolean
      begin
        Inc(Calls);
        Result := Calls < 3;
      end;
    Result_ := Fixture.Pull.WorkspaceReport(nil, Token);
    try
      Assert.AreEqual(1, (Result_ as TJSONObject).GetValue<TJSONArray>('items').Count);
    finally
      Result_.Free;
    end;
  finally
    Fixture.Done;
  end;
end;

procedure TLspPullDiagnosticsTests.ReusesReportForSameState;
var
  Fixture: TFixture;
  First, Second: TJSONObject;
begin
  Fixture.Init;
  try
    First := Fixture.Pull.DocumentReport(TDocumentUris.FromPath(ClosedFile), '');
    Second := Fixture.Pull.DocumentReport(TDocumentUris.FromPath(ClosedFile), '');
    try
      Assert.AreEqual(1, Fixture.Pull.Computed, 'einmal geprüft');
      Assert.AreEqual('full', Second.GetValue<string>('kind'));
      Assert.AreEqual(First.GetValue<TJSONArray>('items').ToJSON, Second.GetValue<TJSONArray>('items').ToJSON);
      // Neue Generation: wieder prüfen.
      Fixture.Pull.Changed;
      Second.Free;
      Second := Fixture.Pull.DocumentReport(TDocumentUris.FromPath(ClosedFile), '');
      Assert.AreEqual(2, Fixture.Pull.Computed, 'nach Changed neu geprüft');
    finally
      Second.Free;
      First.Free;
    end;
  finally
    Fixture.Done;
  end;
end;

procedure TLspPullDiagnosticsTests.SecondWorkspaceRequestDoesNotCollect;
var
  Fixture: TFixture;
  Outer, Inner: TJSONValue;
  InnerCount, Calls: Integer;
  Pull: TLspPullDiagnostics;
begin
  Fixture.Init;
  try
    Calls := 0;
    InnerCount := -1;
    Pull := Fixture.Pull;
    // Die erste Anfrage fragt Busy, während sie den Platz hält: Darin kommt die zweite.
    Pull.Busy :=
      function: Boolean
      begin
        Inc(Calls);
        if Calls = 1 then
        begin
          Inner := Pull.WorkspaceReport(nil, Token);
          try
            InnerCount := (Inner as TJSONObject).GetValue<TJSONArray>('items').Count;
          finally
            Inner.Free;
          end;
        end;
        Result := False;
      end;
    Outer := Pull.WorkspaceReport(nil, Token);
    try
      Assert.AreEqual(0, InnerCount, 'zweite Anfrage leer');
      Assert.AreEqual(1, Calls, 'zweite Anfrage fragt den Index nicht');
      Assert.AreEqual(1, (Outer as TJSONObject).GetValue<TJSONArray>('items').Count, 'erste prüft');
    finally
      Outer.Free;
    end;
  finally
    Fixture.Done;
  end;
end;

procedure TLspPullDiagnosticsTests.CancelStopsRuleChecks;
var
  Fixture: TFixture;
  Rules: TRuleContextProvider;
  Source: IJsonRpcCancellationSource;
  Runs: Integer;
begin
  Rules :=
    function(const AUri: string; out AContext: TRuleCheckContext): Boolean
    begin
      AContext := Default(TRuleCheckContext);
      AContext.Settings := TServerSettings.Default;
      AContext.Rules := [
        TCallbackRule.Create('erste',
          procedure
          begin
            Inc(Runs);
            Source.Cancel;
          end),
        TCallbackRule.Create('zweite',
          procedure
          begin
            Inc(Runs);
          end)];
      Result := True;
    end;
  Fixture.Init(Rules);
  try
    Runs := 0;
    Source := TJsonRpcCancellation.Create;
    Assert.WillRaise(
      procedure
      begin
        Fixture.Pull.DocumentReport(TDocumentUris.FromPath(OpenFile), '', Source).Free;
      end, EJsonRpcRequestCancelled);
    Assert.AreEqual(1, Runs);
    Assert.AreEqual(0, Fixture.Pull.Computed);
  finally
    Fixture.Done;
  end;
end;

procedure TLspPullDiagnosticsTests.ParallelRequestsForSameStateComputeOnce;
var
  Fixture: TFixture;
  Rules: TRuleContextProvider;
  Runs: Integer;
  Worker: TThread;
  Mine, Other: TJSONObject;
begin
  Rules :=
    function(const AUri: string; out AContext: TRuleCheckContext): Boolean
    begin
      AContext := Default(TRuleCheckContext);
      AContext.Settings := TServerSettings.Default;
      AContext.Rules := [
        TCallbackRule.Create('langsam',
          procedure
          begin
            TInterlocked.Increment(Runs);
            Sleep(300);
          end)];
      Result := True;
    end;
  Fixture.Init(Rules);
  try
    Runs := 0;
    Other := nil;
    Worker := TThread.CreateAnonymousThread(
      procedure
      begin
        Other := Fixture.Pull.DocumentReport(TDocumentUris.FromPath(OpenFile), '', Token);
      end);
    Worker.FreeOnTerminate := False;
    Worker.Start;
    try
      Sleep(100);
      Mine := Fixture.Pull.DocumentReport(TDocumentUris.FromPath(OpenFile), '', Token);
      Worker.WaitFor;
    finally
      Worker.Free;
    end;
    try
      Assert.AreEqual(1, Runs);
      Assert.AreEqual(1, Fixture.Pull.Computed);
      Assert.IsNotNull(Other);
      Assert.AreEqual(Other.GetValue('resultId').Value, Mine.GetValue('resultId').Value);
    finally
      Mine.Free;
      Other.Free;
    end;
  finally
    Fixture.Done;
  end;
end;

procedure TLspPullDiagnosticsTests.LongPollFollowsRequestTimeout;
begin
  Assert.AreEqual<Cardinal>(8000, TLspPullDiagnostics.LongPollMs(10000, 10000));
  Assert.AreEqual<Cardinal>(10000, TLspPullDiagnostics.LongPollMs(10000, 60000));
  Assert.AreEqual<Cardinal>(500, TLspPullDiagnostics.LongPollMs(10000, 1000));
  Assert.AreEqual<Cardinal>(10000, TLspPullDiagnostics.LongPollMs(10000, 0));
  Assert.AreEqual<Cardinal>(0, TLspPullDiagnostics.LongPollMs(0, 10000));
end;

procedure TLspPullDiagnosticsTests.WorkspaceWaitEndsBeforeRequestTimeout;
var
  Fixture: TFixture;
  Result_: TJSONValue;
  Clock: TStopwatch;
begin
  Fixture.Init;
  try
    Fixture.Pull.WaitMs := 10000;
    // Index lädt: nichts zu prüfen, die Anfrage wartet bis zum Zeitrahmen (1000 ms Limit -> 500 ms).
    Fixture.Pull.Busy :=
      function: Boolean
      begin
        Result := True;
      end;
    Fixture.Pull.RequestTimeout :=
      function: Cardinal
      begin
        Result := 1000;
      end;
    Clock := TStopwatch.StartNew;
    Result_ := Fixture.Pull.WorkspaceReport(nil, Token);
    try
      Assert.AreEqual(0, (Result_ as TJSONObject).GetValue<TJSONArray>('items').Count);
    finally
      Result_.Free;
    end;
    Assert.IsTrue(Clock.ElapsedMilliseconds >= 400, IntToStr(Clock.ElapsedMilliseconds));
    Assert.IsTrue(Clock.ElapsedMilliseconds <= 900, IntToStr(Clock.ElapsedMilliseconds));
  finally
    Fixture.Done;
  end;
end;

procedure TLspPullDiagnosticsTests.SecondWorkspaceRequestWakesOnChange;
var
  Fixture: TFixture;
  Pull: TLspPullDiagnostics;
  Loading: Boolean;
  First, Second: TThread;
  FirstMs, SecondMs: Int64;
  Clock: TStopwatch;
begin
  Fixture.Init;
  try
    Pull := Fixture.Pull;
    Pull.WaitMs := 5000;
    Loading := True;
    Pull.Busy :=
      function: Boolean
      begin
        Result := Loading;
      end;
    FirstMs := -1;
    SecondMs := -1;
    Clock := TStopwatch.StartNew;
    First := TThread.CreateAnonymousThread(
      procedure
      begin
        Pull.WorkspaceReport(nil, Token).Free;
        FirstMs := Clock.ElapsedMilliseconds;
      end);
    First.FreeOnTerminate := False;
    Second := TThread.CreateAnonymousThread(
      procedure
      begin
        Pull.WorkspaceReport(nil, Token).Free;
        SecondMs := Clock.ElapsedMilliseconds;
      end);
    Second.FreeOnTerminate := False;
    try
      First.Start;
      // Die erste hält den Platz; die zweite wartet nur.
      Sleep(50);
      Second.Start;
      Sleep(200);
      // Index fertig: Changed weckt beide.
      Loading := False;
      Pull.Changed;
      First.WaitFor;
      Second.WaitFor;
    finally
      First.Free;
      Second.Free;
    end;
    Assert.IsTrue((FirstMs >= 0) and (FirstMs < 1000), IntToStr(FirstMs));
    Assert.IsTrue((SecondMs >= 0) and (SecondMs < 1000), IntToStr(SecondMs));
  finally
    Fixture.Done;
  end;
end;

const
  FailingFile = 'C:\P\Kaputt.pas';

/// <summary>Regeln für alle Dateien; für FailingFile scheitert schon das Bereitstellen.</summary>
function FailingRules: TRuleContextProvider;
begin
  Result :=
    function(const AUri: string; out AContext: TRuleCheckContext): Boolean
    begin
      if SameText(TDocumentUris.ToPath(AUri), FailingFile) then
        raise EArgumentException.Create('Unit kaputt');
      AContext := Default(TRuleCheckContext);
      AContext.Settings := TServerSettings.Default;
      Result := True;
    end;
end;

function LabelOfFile(const AFileName: string): string;
begin
  Result := 'unit#2';
  if SameText(AFileName, FailingFile) then
    Result := 'unit#1';
end;

procedure TLspPullDiagnosticsTests.WorkspaceSkipsFailingFile;
var
  Store: IDocumentStore;
  Diagnostics: TLspSyntaxDiagnostics;
  Providers: TSyntaxDiagnosticsProviders;
  Pull: TLspPullDiagnostics;
  Result_: TJSONValue;
  Items: TJSONArray;
  Notes: TRequestNotes;
  Joined: string;
begin
  Store := TDocumentStore.Create;
  Providers := Default(TSyntaxDiagnosticsProviders);
  Providers.Rules := FailingRules();
  Diagnostics := TLspSyntaxDiagnostics.Create(Store, nil, Providers, 0);
  Pull := nil;
  try
    Diagnostics.PullMode := True;
    // Die kaputte Datei steht vorn: früher scheiterte daran jede Anfrage, bis der Server starb.
    Pull := TLspPullDiagnostics.Create(Store, Diagnostics, nil,
      function: TArray<string>
      begin
        Result := [FailingFile, ClosedFile];
      end,
      function(const AFileName: string; out AStamp: Int64): Boolean
      begin
        AStamp := 42;
        Result := True;
      end,
      function(const AFileName: string; out AText: string): Boolean
      begin
        AText := Broken;
        Result := True;
      end);
    Pull.WaitMs := 0;
    Pull.FileLabel := LabelOfFile;
    TRequestDiagnostics.Open;
    try
      Result_ := Pull.WorkspaceReport(nil, Token);
    finally
      Notes := TRequestDiagnostics.Close;
    end;
    try
      Items := (Result_ as TJSONObject).GetValue<TJSONArray>('items');
      Assert.AreEqual(2, Integer(Items.Count));
      Assert.AreEqual(TDocumentUris.FromPath(FailingFile), Items.Items[0].GetValue<string>('uri'));
      Assert.AreEqual(0, Integer(Items.Items[0].GetValue<TJSONArray>('items').Count), 'übersprungen');
      Assert.AreEqual(TDocumentUris.FromPath(ClosedFile), Items.Items[1].GetValue<string>('uri'));
      Assert.IsTrue(Items.Items[1].GetValue<TJSONArray>('items').Count > 0, 'die nächste Datei läuft weiter');
    finally
      Result_.Free;
    end;
    Assert.AreEqual(1, Pull.Skipped);
    Joined := ' ' + string.Join(' ', Notes.Notes) + ' ';
    Assert.Contains(Joined, ' failedUnits=1 ');
    Assert.Contains(Joined, ' failUnit=unit#1 ');
    Assert.Contains(Joined, ' failUnitClass=EArgumentException ');
    Assert.DoesNotContain(Joined, 'Kaputt.pas');
    Assert.AreEqual('', Notes.Subject, 'nach dem Lauf keine Unit mehr offen');
  finally
    Pull.Free;
    Diagnostics.Free;
  end;
end;

procedure TLspPullDiagnosticsTests.DocumentErrorKeepsUnitForLog;
var
  Fixture: TFixture;
  Rules: TRuleContextProvider;
  Notes: TRequestNotes;
begin
  Rules :=
    function(const AUri: string; out AContext: TRuleCheckContext): Boolean
    begin
      AContext := Default(TRuleCheckContext);
      raise EArgumentException.Create('Unit kaputt');
    end;
  Fixture.Init(Rules);
  try
    Fixture.Pull.FileLabel := LabelOfFile;
    TRequestDiagnostics.Open;
    try
      Assert.WillRaise(
        procedure
        begin
          Fixture.Pull.DocumentReport(TDocumentUris.FromPath(OpenFile), '', Token).Free;
        end, EArgumentException);
    finally
      Notes := TRequestDiagnostics.Close;
    end;
    Assert.AreEqual('unit#2', Notes.Subject);
  finally
    Fixture.Done;
  end;
end;

procedure TLspPullDiagnosticsTests.SlowFileFinishesInBackground;
var
  Fixture: TFixture;
  Rules: TRuleContextProvider;
  Answer: TJSONValue;
  Params: TJSONObject;
  Waited: Integer;
begin
  Rules :=
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
  Fixture.Init(Rules);
  Params := TJSONObject.Create;
  try
    Fixture.Pull.FileLimitMs := 50;
    // Erste Antwort: Die Datei ist über der Frist, nichts wird verworfen oder blockiert.
    Answer := Fixture.Pull.WorkspaceReport(Params, Token);
    try
      Assert.AreEqual(0, TJSONObject(Answer).GetValue<TJSONArray>('items').Count);
    finally
      Answer.Free;
    end;
    Waited := 0;
    while (Fixture.Pull.Background > 0) and (Waited < 5000) do
    begin
      Sleep(20);
      Inc(Waited, 20);
    end;
    Assert.AreEqual(0, Fixture.Pull.Background, 'Hintergrund fertig');
    // Zweite Antwort: aus dem Cache, ohne erneute Frist.
    Answer := Fixture.Pull.WorkspaceReport(Params, Token);
    try
      Assert.AreEqual(1, TJSONObject(Answer).GetValue<TJSONArray>('items').Count);
    finally
      Answer.Free;
    end;
  finally
    Params.Free;
    Fixture.Done;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspPullDiagnosticsTests);

end.
