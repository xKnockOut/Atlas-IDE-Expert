unit Atlas.Common.Lsp.Status.Tests;

// Tests für den Status-Befehl (#28): Antwortzeiten, Befehle und Ausgabe.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspStatusTests = class
  public
    [Test]
    procedure StatisticsSumUpPerMethod;
    [Test]
    procedure SnapshotSortsSlowestFirst;
    [Test]
    procedure DispatcherRecordsRequests;
    [Test]
    procedure ExecutesRegisteredCommand;
    [Test]
    procedure UnknownCommandFails;
    [Test]
    procedure CapabilityListsCommands;
    /// <summary>#874: Lesebefehle laufen nebenläufig, alle anderen in der Reihenfolge der Nachrichten.</summary>
    [Test]
    procedure ReadOnlyCommandsRunConcurrently;
    [Test]
    procedure StatusAsMarkdownAndJson;
    [Test]
    procedure StatusShowsCacheAndOffloadMetrics;
    /// <summary>#46: Konfiguration, Plattform, aktives und ausgewähltes Projekt je Arbeitsbereich.</summary>
    [Test]
    procedure StatusShowsProjectChoice;
    /// <summary>#261: Weg zum Compiler mit Grund und Ausweg im Status.</summary>
    [Test]
    procedure StatusShowsCompiler;
    /// <summary>#1356: Prozess, Speicher je Bereich, Prüflauf, Warteschlange und Cache-Treffer.</summary>
    [Test]
    procedure StatusShowsDiagnostics;
    /// <summary>#1356: Ohne die neuen Angaben bleibt die Ausgabe wie bisher (ältere Clients).</summary>
    [Test]
    procedure StatusWithoutDiagnosticsKeepsOldKeys;
    [Test]
    procedure MemoryRestAndBudget;
    [Test]
    procedure CacheHitPercentOverWorkspaces;
  end;

implementation

uses
  System.Generics.Collections,
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.JsonRpc.Statistics,
  Atlas.Common.Lsp.Commands,
  Atlas.Common.Lsp.Status,
  Atlas.Common.Diagnostics.CheckProfile;

procedure TLspStatusTests.StatisticsSumUpPerMethod;
var
  Statistics: IJsonRpcStatistics;
  Snapshot: TArray<TMethodStatistics>;
begin
  Statistics := TJsonRpcStatistics.Create;
  Statistics.Add('a', 10, False);
  Statistics.Add('a', 30, True);
  Snapshot := Statistics.Snapshot;
  Assert.AreEqual<NativeInt>(1, Length(Snapshot));
  Assert.AreEqual(2, Integer(Snapshot[0].Count));
  Assert.AreEqual<Int64>(30, Snapshot[0].MaxMs);
  Assert.AreEqual(20.0, Snapshot[0].AverageMs, 0.001);
  Assert.AreEqual(1, Snapshot[0].Failed);
end;

procedure TLspStatusTests.SnapshotSortsSlowestFirst;
var
  Statistics: IJsonRpcStatistics;
  Snapshot: TArray<TMethodStatistics>;
begin
  Statistics := TJsonRpcStatistics.Create;
  Statistics.Add('schnell', 1, False);
  Statistics.Add('langsam', 50, False);
  Snapshot := Statistics.Snapshot;
  Assert.AreEqual('langsam', Snapshot[0].Method);
  Assert.AreEqual('schnell', Snapshot[1].Method);
end;

procedure TLspStatusTests.DispatcherRecordsRequests;
var
  Dispatcher: TJsonRpcDispatcher;
  Statistics: IJsonRpcStatistics;
  Message: TJSONObject;
  Response: TJSONObject;
  Snapshot: TArray<TMethodStatistics>;
begin
  Statistics := TJsonRpcStatistics.Create;
  Dispatcher := TJsonRpcDispatcher.Create;
  try
    Dispatcher.Statistics := Statistics;
    Dispatcher.RegisterRequest('gut',
      function(const AParams: TJSONValue): TJSONValue
      begin
        Result := TJSONNull.Create;
      end);
    Dispatcher.RegisterRequest('kaputt',
      function(const AParams: TJSONValue): TJSONValue
      begin
        // Ohne Parameter immer: eine Anfrage, die fehlschlägt.
        if AParams = nil then
          raise Exception.Create('Absicht');
        Result := TJSONNull.Create;
      end);
    Message := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","id":1,"method":"gut"}') as TJSONObject;
    try
      Response := Dispatcher.DispatchMessage(Message);
      Response.Free;
    finally
      Message.Free;
    end;
    Message := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","id":2,"method":"kaputt"}') as TJSONObject;
    try
      Response := Dispatcher.DispatchMessage(Message);
      Response.Free;
    finally
      Message.Free;
    end;
  finally
    Dispatcher.Free;
  end;
  Snapshot := Statistics.Snapshot;
  Assert.AreEqual<NativeInt>(2, Length(Snapshot));
  Assert.AreEqual(2, Integer(Snapshot[0].Count + Snapshot[1].Count));
  Assert.AreEqual(1, Snapshot[0].Failed + Snapshot[1].Failed);
end;

procedure TLspStatusTests.ExecutesRegisteredCommand;
var
  Commands: TLspCommands;
  Arguments: TJSONArray;
  Value: TJSONValue;
begin
  Commands := TLspCommands.Create;
  Arguments := TJSONArray.Create;
  try
    Arguments.Add(42);
    Commands.Register('x.echo',
      function(const AArguments: TJSONArray): TJSONValue
      begin
        Result := TJSONNumber.Create(AArguments.Count);
      end);
    Value := Commands.Execute('x.echo', Arguments);
    try
      Assert.AreEqual('1', Value.ToJSON);
    finally
      Value.Free;
    end;
  finally
    Arguments.Free;
    Commands.Free;
  end;
end;

procedure TLspStatusTests.UnknownCommandFails;
var
  Commands: TLspCommands;
  Raised: Boolean;
begin
  Commands := TLspCommands.Create;
  try
    Raised := False;
    try
      Commands.Execute('fehlt', nil).Free;
    except
      on EJsonRpcError do
        Raised := True;
    end;
    Assert.IsTrue(Raised);
  finally
    Commands.Free;
  end;
end;

procedure TLspStatusTests.CapabilityListsCommands;
var
  Commands: TLspCommands;
  Capability: TJSONObject;
begin
  Commands := TLspCommands.Create;
  try
    Commands.Register('a', nil);
    Commands.Register('b', nil);
    Commands.Register('a', nil);
    Capability := Commands.Capability;
    try
      Assert.AreEqual('{"commands":["a","b"]}', Capability.ToJSON);
    finally
      Capability.Free;
    end;
  finally
    Commands.Free;
  end;
end;

procedure TLspStatusTests.ReadOnlyCommandsRunConcurrently;
var
  Commands: TLspCommands;
  Dispatcher: TJsonRpcDispatcher;
  Work: TList<TProc>;
  Responses: TObjectList<TJSONObject>;
  Item: TProc;
  Params: TJSONValue;

  function Dispatch(const AJson: string): TJSONObject;
  var
    Message: TJSONObject;
  begin
    Message := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
    try
      Result := Dispatcher.DispatchMessage(Message);
    finally
      Message.Free;
    end;
  end;

begin
  Commands := TLspCommands.Create;
  Dispatcher := TJsonRpcDispatcher.Create;
  Work := TList<TProc>.Create;
  Responses := TObjectList<TJSONObject>.Create(True);
  try
    Commands.Register('x.write',
      function(const AArguments: TJSONArray): TJSONValue
      begin
        Result := TJSONString.Create('write');
      end);
    Commands.RegisterConcurrent('x.status',
      function(const AArguments: TJSONArray): TJSONValue
      begin
        Result := TJSONString.Create('status');
      end);
    Params := TJSONObject.ParseJSONValue('{"command":"x.status"}');
    try
      Assert.IsTrue(Commands.IsConcurrent(Params));
    finally
      Params.Free;
    end;
    Params := TJSONObject.ParseJSONValue('{"command":"x.write"}');
    try
      Assert.IsFalse(Commands.IsConcurrent(Params));
    finally
      Params.Free;
    end;
    Assert.IsFalse(Commands.IsConcurrent(nil), 'ohne Parameter');
    Dispatcher.Scheduler :=
      procedure(const AWork: TProc)
      begin
        Work.Add(AWork);
      end;
    Dispatcher.Responder :=
      procedure(const AResponse: TJSONObject)
      begin
        Responses.Add(AResponse);
      end;
    Commands.Attach(Dispatcher);
    Assert.IsNull(Dispatch('{"jsonrpc":"2.0","id":1,"method":"workspace/executeCommand",' +
      '"params":{"command":"x.status"}}'), 'Lesebefehl geht an den Scheduler');
    Responses.Add(Dispatch('{"jsonrpc":"2.0","id":2,"method":"workspace/executeCommand",' +
      '"params":{"command":"x.write"}}'));
    Assert.AreEqual('write', Responses[0].GetValue<string>('result'), 'seriell sofort');
    Assert.AreEqual(1, Integer(Work.Count));
    for Item in Work.ToArray do
      Item();
    Assert.AreEqual(2, Integer(Responses.Count));
    Assert.AreEqual('status', Responses[1].GetValue<string>('result'));
  finally
    Responses.Free;
    Work.Free;
    Dispatcher.Free;
    Commands.Free;
  end;
end;

procedure TLspStatusTests.StatusAsMarkdownAndJson;
var
  Status: TServerStatus;
  Workspace: TWorkspaceStatus;
  Request: TMethodStatistics;
  Json: TJSONObject;
begin
  Status := Default(TServerStatus);
  Status.Units := 3;
  Status.Symbols := 40;
  Status.MemoryBytes := 5 * 1024 * 1024;
  Status.IndexBytes := 2 * 1024 * 1024;
  Status.BudgetBytes := 4 * 1024 * 1024;
  Status.CompactUnits := 7;
  Status.DocumentBytes := 1024 * 1024;
  Workspace := Default(TWorkspaceStatus);
  Workspace.Name := 'App';
  Workspace.LastIndexMs := 120;
  Workspace.Parsed := 2;
  Workspace.FromCache := 1;
  Status.Workspaces := [Workspace];
  Request := Default(TMethodStatistics);
  Request.Method := 'textDocument/hover';
  Request.Count := 4;
  Request.TotalMs := 10;
  Request.MaxMs := 6;
  Status.Requests := [Request];
  Assert.IsTrue(Pos('- Index: 3 Units, 40 Symbole', Status.ToMarkdown) > 0, Status.ToMarkdown);
  Assert.IsTrue(Pos('- Speicher: 5.0 MB', Status.ToMarkdown) > 0, Status.ToMarkdown);
  Assert.IsTrue(Pos('- davon Symbolindex: 2.0 MB von 4.0 MB, 7 Units kompakt', Status.ToMarkdown) > 0, Status.ToMarkdown);
  Assert.IsTrue(Pos('- davon geöffnete Dokumente: 1.0 MB', Status.ToMarkdown) > 0, Status.ToMarkdown);
  Assert.IsTrue(Pos('- App: letzter Indexlauf 120 ms (2 neu eingelesen, 1 aus dem Cache, 0 fehlen)',
    Status.ToMarkdown) > 0, Status.ToMarkdown);
  Assert.IsTrue(Pos('| textDocument/hover | 4 | 2.5 | 6 | 0 |', Status.ToMarkdown) > 0, Status.ToMarkdown);
  Json := Status.ToJson;
  try
    Assert.AreEqual(40, Json.GetValue<Integer>('symbols'));
    Assert.AreEqual(7, Json.GetValue<Integer>('compactUnits'));
    Assert.AreEqual<Int64>(4 * 1024 * 1024, Json.GetValue<Int64>('budgetBytes'));
    Assert.AreEqual('App', Json.GetValue<string>('workspaces[0].name'));
    Assert.AreEqual(4, Json.GetValue<Integer>('requests[0].count'));
    Assert.AreEqual(Status.ToMarkdown, Json.GetValue<string>('markdown'));
  finally
    Json.Free;
  end;
end;

procedure TLspStatusTests.StatusShowsCacheAndOffloadMetrics;
var
  Status: TServerStatus;
  Workspace: TWorkspaceStatus;
  Json: TJSONObject;
begin
  // #492: ausgelagerte Verwendungen, Größe auf der Platte, letzte Aktualisierung.
  Status := Default(TServerStatus);
  Status.OffloadedUnits := 4;
  Status.DiskBytes := 3 * 1024 * 1024;
  Workspace := Default(TWorkspaceStatus);
  Workspace.Name := 'App';
  Workspace.LastUpdate := EncodeDate(2026, 10, 14) + EncodeTime(12, 30, 0, 0);
  Workspace.CacheBytes := 1024 * 1024;
  Workspace.LibraryCacheBytes := 1024 * 1024;
  Status.Workspaces := [Workspace];
  Assert.IsTrue(Pos('Verwendungen von 4 Units ausgelagert', Status.ToMarkdown) > 0, Status.ToMarkdown);
  Assert.IsTrue(Pos('- Caches auf der Platte: 3.0 MB', Status.ToMarkdown) > 0, Status.ToMarkdown);
  Assert.IsTrue(Pos('aktualisiert 14.10.2026 12:30:00, Cache 2.0 MB', Status.ToMarkdown) > 0, Status.ToMarkdown);
  Json := Status.ToJson;
  try
    Assert.AreEqual(4, Json.GetValue<Integer>('offloadedUnits'));
    Assert.AreEqual<Int64>(3 * 1024 * 1024, Json.GetValue<Int64>('diskBytes'));
    Assert.AreEqual<Int64>(1024 * 1024, Json.GetValue<Int64>('workspaces[0].libraryCacheBytes'));
    Assert.IsTrue(Json.GetValue<string>('workspaces[0].lastUpdate').StartsWith('2026-10-14T12:30:00'),
      Json.GetValue<string>('workspaces[0].lastUpdate'));
  finally
    Json.Free;
  end;
end;

procedure TLspStatusTests.StatusShowsProjectChoice;
var
  Status: TServerStatus;
  Workspace: TWorkspaceStatus;
  Json: TJSONObject;
begin
  Workspace := Default(TWorkspaceStatus);
  Workspace.Name := 'Kern';
  Workspace.LastIndexMs := -1;
  Assert.AreEqual('', Workspace.ProjectText);
  Workspace.Project := 'C:\P\Kern.dproj';
  Workspace.Config := 'Release';
  Workspace.Platform := 'Win64';
  Assert.AreEqual(' · Release/Win64', Workspace.ProjectText);
  Workspace.BuildChosen := True;
  Workspace.Active := True;
  Workspace.Selected := True;
  Status := Default(TServerStatus);
  Status.Workspaces := [Workspace];
  Assert.IsTrue(Pos('- Kern · Release/Win64 (gewählt) · aktiv in der IDE · ausgewählt: Index wird aufgebaut',
    Status.ToMarkdown) > 0, Status.ToMarkdown);
  Json := Status.ToJson;
  try
    Assert.AreEqual('Release', Json.GetValue<string>('workspaces[0].config'));
    Assert.IsTrue(Json.GetValue<Boolean>('workspaces[0].buildChosen'));
    Assert.IsTrue(Json.GetValue<Boolean>('workspaces[0].selected'));
  finally
    Json.Free;
  end;
end;

procedure TLspStatusTests.StatusShowsCompiler;
var
  Status: TServerStatus;
  Json: TJSONObject;
begin
  Status := Default(TServerStatus);
  Assert.IsTrue(Pos('Compiler', Status.ToMarkdown) = 0, 'ohne Angabe keine Zeile');
  Status.Compiler := 'Compiler: nicht verfügbar (Starter Edition)';
  Status.CompilerBackend := 'off';
  Status.CompilerReason := 'Atlas kann nicht kompilieren: kein Kommandozeilen-Compiler.';
  Assert.IsTrue(Pos('- Compiler: nicht verfügbar (Starter Edition)', Status.ToMarkdown) > 0, Status.ToMarkdown);
  Assert.IsTrue(Pos('  Atlas kann nicht kompilieren', Status.ToMarkdown) > 0, Status.ToMarkdown);
  Json := Status.ToJson;
  try
    Assert.AreEqual('off', Json.GetValue<string>('compiler.backend'));
    Assert.AreEqual('Compiler: nicht verfügbar (Starter Edition)', Json.GetValue<string>('compiler.status'));
    Assert.IsTrue(Json.GetValue<string>('compiler.reason').StartsWith('Atlas kann nicht'));
  finally
    Json.Free;
  end;
end;

procedure TLspStatusTests.StatusShowsDiagnostics;
var
  mStatus: TServerStatus;
  mProfiler: TCheckProfiler;
  mJson, mPart: TJSONObject;
  mMarkdown: string;
begin
  mStatus := Default(TServerStatus);
  mStatus.ProcessId := 4711;
  mStatus.Version := '1.2.0';
  mStatus.UptimeMs := 65000;
  mStatus.State := TServerStatus.StateChecking;
  mStatus.Memory.Symbols := 10 * 1024 * 1024;
  mStatus.Memory.Usages := 20 * 1024 * 1024;
  mStatus.Memory.LibraryUnits := 30 * 1024 * 1024;
  mStatus.Memory.TreeCache := 4 * 1024 * 1024;
  mStatus.Memory.Documents := 1024 * 1024;
  mStatus.Memory.Total := 100 * 1024 * 1024;
  mStatus.Memory.Budget := 50 * 1024 * 1024;
  mStatus.Queue.IndexWaiting := 1;
  mStatus.Queue.CheckWaiting := 12;
  mStatus.Queue.CheckRunning := 1;
  mStatus.Queue.OldestWaitMs := 900;
  mStatus.IndexCacheHitPercent := 95;
  mStatus.TreeCacheHitPercent := 80;
  mStatus.TreeCacheTrees := 3;
  mProfiler := TCheckProfiler.Create;
  try
    mProfiler.BeginRun(Now);
    mProfiler.AddUnit('C:\P\Haupt.pas', 5000);
    mProfiler.AddRule('format-args', 2000);
    mProfiler.FinishRun(6);
    mStatus.CheckRun := mProfiler.Snapshot(TCheckRunProfile.cTop);
  finally
    mProfiler.Free;
  end;
  mMarkdown := mStatus.ToMarkdown;
  Assert.IsTrue(mMarkdown.Contains('Prozess 4711, Version 1.2.0, läuft seit 65 s, prüft'), mMarkdown);
  Assert.IsTrue(mMarkdown.Contains('| Verwendungen | 20.0 MB |'), mMarkdown);
  Assert.IsTrue(mMarkdown.Contains('| Rest | 35.0 MB |'), mMarkdown);
  Assert.IsTrue(mMarkdown.Contains('Budget überschritten: Verwendungen werden ausgelagert.'), mMarkdown);
  Assert.IsTrue(mMarkdown.Contains('Prüfung 12 wartend, 1 laufend'), mMarkdown);
  Assert.IsTrue(mMarkdown.Contains('Index 95 %, Syntaxbäume 80 % (3 im Speicher)'), mMarkdown);
  Assert.IsTrue(mMarkdown.Contains('| Haupt | 5.0 |'), mMarkdown);
  mJson := mStatus.ToJson;
  try
    mPart := mJson.GetValue('process') as TJSONObject;
    Assert.AreEqual(4711, mPart.GetValue<Integer>('pid'));
    Assert.AreEqual('checking', mPart.GetValue<string>('state'));
    mPart := mJson.GetValue('memory') as TJSONObject;
    Assert.AreEqual<Int64>(20 * 1024 * 1024, mPart.GetValue<Int64>('usages'));
    Assert.AreEqual<Int64>(35 * 1024 * 1024, mPart.GetValue<Int64>('rest'));
    Assert.IsTrue(mPart.GetValue<Boolean>('overBudget'));
    mPart := mJson.GetValue('queue') as TJSONObject;
    Assert.AreEqual(12, mPart.GetValue<Integer>('checkWaiting'));
    mPart := mJson.GetValue('cacheHits') as TJSONObject;
    Assert.AreEqual(95, mPart.GetValue<Integer>('index'));
    mPart := mJson.GetValue('checkRun') as TJSONObject;
    Assert.AreEqual(1, mPart.GetValue<Integer>('units'));
  finally
    mJson.Free;
  end;
end;

procedure TLspStatusTests.StatusWithoutDiagnosticsKeepsOldKeys;
var
  mStatus: TServerStatus;
  mJson: TJSONObject;
begin
  mStatus := Default(TServerStatus);
  mStatus.Units := 3;
  mJson := mStatus.ToJson;
  try
    Assert.AreEqual(3, mJson.GetValue<Integer>('units'));
    Assert.IsTrue(mJson.GetValue('requests') is TJSONArray);
    Assert.IsTrue(mJson.GetValue('markdown') is TJSONString);
    Assert.IsNull(mJson.GetValue('process'));
    Assert.IsNull(mJson.GetValue('memory'));
  finally
    mJson.Free;
  end;
  Assert.IsFalse(mStatus.ToMarkdown.Contains('Prozess'), mStatus.ToMarkdown);
end;

procedure TLspStatusTests.MemoryRestAndBudget;
var
  mMemory: TServerMemory;
begin
  mMemory := Default(TServerMemory);
  mMemory.Symbols := 60;
  mMemory.Total := 50;
  // Schätzung über dem gemessenen Speicher: kein negativer Rest.
  Assert.AreEqual<Int64>(0, mMemory.Rest);
  mMemory.Total := -1;
  Assert.AreEqual<Int64>(0, mMemory.Rest);
  Assert.IsFalse(mMemory.OverBudget(0, 0), 'ohne Budget');
  mMemory.Budget := 100;
  Assert.IsFalse(mMemory.OverBudget(0, 0));
  Assert.IsTrue(mMemory.OverBudget(0, 1), 'schon ausgelagert');
  mMemory.Usages := 50;
  Assert.IsTrue(mMemory.OverBudget(0, 0));
end;

procedure TLspStatusTests.CacheHitPercentOverWorkspaces;
var
  mWorkspaces: TArray<TWorkspaceStatus>;
begin
  SetLength(mWorkspaces, 3);
  mWorkspaces[0] := Default(TWorkspaceStatus);
  mWorkspaces[0].LastIndexMs := 10;
  mWorkspaces[0].Parsed := 10;
  mWorkspaces[0].FromCache := 30;
  mWorkspaces[1] := Default(TWorkspaceStatus);
  mWorkspaces[1].LastIndexMs := 10;
  mWorkspaces[1].FromCache := 60;
  // Noch im Aufbau: zählt nicht.
  mWorkspaces[2] := Default(TWorkspaceStatus);
  mWorkspaces[2].LastIndexMs := -1;
  mWorkspaces[2].Parsed := 1000;
  Assert.AreEqual(90, TServerStatus.CacheHitPercent(mWorkspaces));
  Assert.AreEqual(-1, TServerStatus.CacheHitPercent(nil));
  mWorkspaces := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspStatusTests);

end.
