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
    [Test]
    procedure StatusAsMarkdownAndJson;
    [Test]
    procedure StatusShowsCacheAndOffloadMetrics;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.JsonRpc.Statistics,
  Atlas.Common.Lsp.Commands,
  Atlas.Common.Lsp.Status;

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
  Assert.AreEqual(2, Snapshot[0].Count);
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
  Assert.AreEqual(2, Snapshot[0].Count + Snapshot[1].Count);
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

initialization
  TDUnitX.RegisterTestFixture(TLspStatusTests);

end.
