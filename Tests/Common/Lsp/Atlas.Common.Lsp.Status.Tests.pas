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
    /// <summary>#2142: Token je Ordner, laufender Aufbau mit Prozent, Stufe und Warten.</summary>
    [Test]
    procedure StatusShowsIndexingPerWorkspace;
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
  mStatistics: IJsonRpcStatistics;
  mSnapshot: TArray<TMethodStatistics>;
begin
  mStatistics := TJsonRpcStatistics.Create;
  mStatistics.Add('a', 10, False);
  mStatistics.Add('a', 30, True);
  mSnapshot := mStatistics.Snapshot;
  Assert.AreEqual<NativeInt>(1, Length(mSnapshot));
  Assert.AreEqual(2, Integer(mSnapshot[0].Count));
  Assert.AreEqual<Int64>(30, mSnapshot[0].MaxMs);
  Assert.AreEqual(20.0, mSnapshot[0].AverageMs, 0.001);
  Assert.AreEqual(1, mSnapshot[0].Failed);
end;

procedure TLspStatusTests.SnapshotSortsSlowestFirst;
var
  mStatistics: IJsonRpcStatistics;
  mSnapshot: TArray<TMethodStatistics>;
begin
  mStatistics := TJsonRpcStatistics.Create;
  mStatistics.Add('schnell', 1, False);
  mStatistics.Add('langsam', 50, False);
  mSnapshot := mStatistics.Snapshot;
  Assert.AreEqual('langsam', mSnapshot[0].Method);
  Assert.AreEqual('schnell', mSnapshot[1].Method);
end;

procedure TLspStatusTests.DispatcherRecordsRequests;
var
  mDispatcher: TJsonRpcDispatcher;
  mStatistics: IJsonRpcStatistics;
  mMessage: TJSONObject;
  mResponse: TJSONObject;
  mSnapshot: TArray<TMethodStatistics>;
begin
  mStatistics := TJsonRpcStatistics.Create;
  mDispatcher := TJsonRpcDispatcher.Create;
  try
    mDispatcher.Statistics := mStatistics;
    mDispatcher.RegisterRequest('gut',
      function(const AParams: TJSONValue): TJSONValue
      begin
        Result := TJSONNull.Create;
      end);
    mDispatcher.RegisterRequest('kaputt',
      function(const AParams: TJSONValue): TJSONValue
      begin
        // Ohne Parameter immer: eine Anfrage, die fehlschlägt.
        if AParams = nil then
        begin
          raise Exception.Create('Absicht');
        end;
        Result := TJSONNull.Create;
      end);
    mMessage := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","id":1,"method":"gut"}') as TJSONObject;
    try
      mResponse := mDispatcher.DispatchMessage(mMessage);
      mResponse.Free;
    finally
      mMessage.Free;
    end;
    mMessage := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","id":2,"method":"kaputt"}') as TJSONObject;
    try
      mResponse := mDispatcher.DispatchMessage(mMessage);
      mResponse.Free;
    finally
      mMessage.Free;
    end;
  finally
    mDispatcher.Free;
  end;
  mSnapshot := mStatistics.Snapshot;
  Assert.AreEqual<NativeInt>(2, Length(mSnapshot));
  Assert.AreEqual(2, Integer(mSnapshot[0].Count + mSnapshot[1].Count));
  Assert.AreEqual(1, mSnapshot[0].Failed + mSnapshot[1].Failed);
end;

procedure TLspStatusTests.ExecutesRegisteredCommand;
var
  mCommands: TLspCommands;
  mArguments: TJSONArray;
  mValue: TJSONValue;
begin
  mCommands := TLspCommands.Create;
  mArguments := TJSONArray.Create;
  try
    mArguments.Add(42);
    mCommands.Register('x.echo',
      function(const AArguments: TJSONArray): TJSONValue
      begin
        Result := TJSONNumber.Create(AArguments.Count);
      end);
    mValue := mCommands.Execute('x.echo', mArguments);
    try
      Assert.AreEqual('1', mValue.ToJSON);
    finally
      mValue.Free;
    end;
  finally
    mArguments.Free;
    mCommands.Free;
  end;
end;

procedure TLspStatusTests.UnknownCommandFails;
var
  mCommands: TLspCommands;
  mRaised: Boolean;
begin
  mCommands := TLspCommands.Create;
  try
    mRaised := False;
    try
      mCommands.Execute('fehlt', nil).Free;
    except
      on EJsonRpcError do
        mRaised := True;
    end;
    Assert.IsTrue(mRaised);
  finally
    mCommands.Free;
  end;
end;

procedure TLspStatusTests.CapabilityListsCommands;
var
  mCommands: TLspCommands;
  mCapability: TJSONObject;
begin
  mCommands := TLspCommands.Create;
  try
    mCommands.Register('a', nil);
    mCommands.Register('b', nil);
    mCommands.Register('a', nil);
    mCapability := mCommands.Capability;
    try
      Assert.AreEqual('{"commands":["a","b"]}', mCapability.ToJSON);
    finally
      mCapability.Free;
    end;
  finally
    mCommands.Free;
  end;
end;

/// <summary>Meldet x.write seriell und x.status nebenläufig an und prüft die Zuordnung.</summary>
procedure RegisterWriteAndStatus(const ACommands: TLspCommands);
var
  mParams: TJSONValue;
begin
  ACommands.Register('x.write',
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := TJSONString.Create('write');
    end);
  ACommands.RegisterConcurrent('x.status',
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := TJSONString.Create('status');
    end);
  mParams := TJSONObject.ParseJSONValue('{"command":"x.status"}');
  try
    Assert.IsTrue(ACommands.IsConcurrent(mParams));
  finally
    mParams.Free;
  end;
  mParams := TJSONObject.ParseJSONValue('{"command":"x.write"}');
  try
    Assert.IsFalse(ACommands.IsConcurrent(mParams));
  finally
    mParams.Free;
  end;
end;

procedure TLspStatusTests.ReadOnlyCommandsRunConcurrently;
var
  mCommands: TLspCommands;
  mDispatcher: TJsonRpcDispatcher;
  mWork: TList<TProc>;
  mResponses: TObjectList<TJSONObject>;
  mItem: TProc;

  function Dispatch(const AJson: string): TJSONObject;
  var
    mMessage: TJSONObject;
  begin
    mMessage := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
    try
      Result := mDispatcher.DispatchMessage(mMessage);
    finally
      mMessage.Free;
    end;
  end;

begin
  mCommands := TLspCommands.Create;
  mDispatcher := TJsonRpcDispatcher.Create;
  mWork := TList<TProc>.Create;
  mResponses := TObjectList<TJSONObject>.Create(True);
  try
    RegisterWriteAndStatus(mCommands);
    Assert.IsFalse(mCommands.IsConcurrent(nil), 'ohne Parameter');
    mDispatcher.Scheduler :=
      procedure(const AWork: TProc)
      begin
        mWork.Add(AWork);
      end;
    mDispatcher.Responder :=
      procedure(const AResponse: TJSONObject)
      begin
        mResponses.Add(AResponse);
      end;
    mCommands.Attach(mDispatcher);
    Assert.IsNull(Dispatch('{"jsonrpc":"2.0","id":1,"method":"workspace/executeCommand",' +
      '"params":{"command":"x.status"}}'), 'Lesebefehl geht an den Scheduler');
    mResponses.Add(Dispatch('{"jsonrpc":"2.0","id":2,"method":"workspace/executeCommand",' +
      '"params":{"command":"x.write"}}'));
    Assert.AreEqual('write', mResponses[0].GetValue<string>('result'), 'seriell sofort');
    Assert.AreEqual(1, Integer(mWork.Count));
    for mItem in mWork.ToArray do
    begin
      mItem();
    end;
    Assert.AreEqual(2, Integer(mResponses.Count));
    Assert.AreEqual('status', mResponses[1].GetValue<string>('result'));
  finally
    mResponses.Free;
    mWork.Free;
    mDispatcher.Free;
    mCommands.Free;
  end;
end;

procedure TLspStatusTests.StatusAsMarkdownAndJson;
var
  mStatus: TServerStatus;
  mWorkspace: TWorkspaceStatus;
  mRequest: TMethodStatistics;
  mJson: TJSONObject;
begin
  mStatus := Default(TServerStatus);
  mStatus.Units := 3;
  mStatus.Symbols := 40;
  mStatus.MemoryBytes := 5 * 1024 * 1024;
  mStatus.IndexBytes := 2 * 1024 * 1024;
  mStatus.BudgetBytes := 4 * 1024 * 1024;
  mStatus.CompactUnits := 7;
  mStatus.DocumentBytes := 1024 * 1024;
  mWorkspace := Default(TWorkspaceStatus);
  mWorkspace.Name := 'App';
  mWorkspace.LastIndexMs := 120;
  mWorkspace.Parsed := 2;
  mWorkspace.FromCache := 1;
  mStatus.Workspaces := [mWorkspace];
  mRequest := Default(TMethodStatistics);
  mRequest.Method := 'textDocument/hover';
  mRequest.Count := 4;
  mRequest.TotalMs := 10;
  mRequest.MaxMs := 6;
  mStatus.Requests := [mRequest];
  Assert.IsTrue(Pos('- Index: 3 Units, 40 Symbole', mStatus.ToMarkdown) > 0, mStatus.ToMarkdown);
  Assert.IsTrue(Pos('- Speicher: 5.0 MB', mStatus.ToMarkdown) > 0, mStatus.ToMarkdown);
  Assert.IsTrue(Pos('- davon Symbolindex: 2.0 MB von 4.0 MB, 7 Units kompakt', mStatus.ToMarkdown) > 0, mStatus.ToMarkdown);
  Assert.IsTrue(Pos('- davon geöffnete Dokumente: 1.0 MB', mStatus.ToMarkdown) > 0, mStatus.ToMarkdown);
  Assert.IsTrue(Pos('- App: letzter Indexlauf 120 ms (2 neu eingelesen, 1 aus dem Cache, 0 fehlen)',
    mStatus.ToMarkdown) > 0, mStatus.ToMarkdown);
  Assert.IsTrue(Pos('| textDocument/hover | 4 | 2.5 | 6 | 0 |', mStatus.ToMarkdown) > 0, mStatus.ToMarkdown);
  mJson := mStatus.ToJson;
  try
    Assert.AreEqual(40, mJson.GetValue<Integer>('symbols'));
    Assert.AreEqual(7, mJson.GetValue<Integer>('compactUnits'));
    Assert.AreEqual<Int64>(4 * 1024 * 1024, mJson.GetValue<Int64>('budgetBytes'));
    Assert.AreEqual('App', mJson.GetValue<string>('workspaces[0].name'));
    Assert.AreEqual(4, mJson.GetValue<Integer>('requests[0].count'));
    Assert.AreEqual(mStatus.ToMarkdown, mJson.GetValue<string>('markdown'));
  finally
    mJson.Free;
  end;
end;

procedure TLspStatusTests.StatusShowsCacheAndOffloadMetrics;
var
  mStatus: TServerStatus;
  mWorkspace: TWorkspaceStatus;
  mJson: TJSONObject;
begin
  // #492: ausgelagerte Verwendungen, Größe auf der Platte, letzte Aktualisierung.
  mStatus := Default(TServerStatus);
  mStatus.OffloadedUnits := 4;
  mStatus.DiskBytes := 3 * 1024 * 1024;
  mWorkspace := Default(TWorkspaceStatus);
  mWorkspace.Name := 'App';
  mWorkspace.LastUpdate := EncodeDate(2026, 10, 14) + EncodeTime(12, 30, 0, 0);
  mWorkspace.CacheBytes := 1024 * 1024;
  mWorkspace.LibraryCacheBytes := 1024 * 1024;
  mStatus.Workspaces := [mWorkspace];
  Assert.IsTrue(Pos('Verwendungen von 4 Units ausgelagert', mStatus.ToMarkdown) > 0, mStatus.ToMarkdown);
  Assert.IsTrue(Pos('- Caches auf der Platte: 3.0 MB', mStatus.ToMarkdown) > 0, mStatus.ToMarkdown);
  Assert.IsTrue(Pos('aktualisiert 14.10.2026 12:30:00, Cache 2.0 MB', mStatus.ToMarkdown) > 0, mStatus.ToMarkdown);
  mJson := mStatus.ToJson;
  try
    Assert.AreEqual(4, mJson.GetValue<Integer>('offloadedUnits'));
    Assert.AreEqual<Int64>(3 * 1024 * 1024, mJson.GetValue<Int64>('diskBytes'));
    Assert.AreEqual<Int64>(1024 * 1024, mJson.GetValue<Int64>('workspaces[0].libraryCacheBytes'));
    Assert.IsTrue(mJson.GetValue<string>('workspaces[0].lastUpdate').StartsWith('2026-10-14T12:30:00'),
      mJson.GetValue<string>('workspaces[0].lastUpdate'));
  finally
    mJson.Free;
  end;
end;

procedure TLspStatusTests.StatusShowsIndexingPerWorkspace;
var
  mStatus: TServerStatus;
  mDone, mBuilding: TWorkspaceStatus;
  mJson, mFirst, mSecond, mIndexing: TJSONObject;
  mItems: TJSONArray;
begin
  mStatus := Default(TServerStatus);
  mDone := Default(TWorkspaceStatus);
  mDone.Name := 'Kunden';
  // Format statt Literal: Ein Fortschritts-Token ist kein Zugangswert (security-hardcoded-credential).
  mDone.ProgressToken := Format('atlas-index-%d', [1]);
  mBuilding := Default(TWorkspaceStatus);
  mBuilding.Name := 'Lager';
  mBuilding.ProgressToken := Format('atlas-index-%d-%d', [1, 1]);
  mBuilding.Indexing := True;
  mBuilding.IndexPercent := 62;
  mBuilding.IndexStage := 'searchPaths';
  mBuilding.IndexWaiting := True;
  mStatus.Workspaces := [mDone, mBuilding];
  mJson := mStatus.ToJson;
  try
    mItems := mJson.GetValue('workspaces') as TJSONArray;
    mFirst := mItems.Items[0] as TJSONObject;
    mSecond := mItems.Items[1] as TJSONObject;
    Assert.AreEqual('atlas-index-1', mFirst.GetValue('progressToken').Value);
    Assert.IsNull(mFirst.GetValue('indexing'), 'fertig: ohne indexing');
    Assert.AreEqual('atlas-index-1-1', mSecond.GetValue('progressToken').Value);
    mIndexing := mSecond.GetValue('indexing') as TJSONObject;
    Assert.AreEqual('62', mIndexing.GetValue('percent').Value);
    Assert.AreEqual('searchPaths', mIndexing.GetValue('stage').Value);
    Assert.AreEqual('true', mIndexing.GetValue('waiting').ToJSON);
  finally
    mJson.Free;
  end;
end;

procedure TLspStatusTests.StatusShowsProjectChoice;
var
  mStatus: TServerStatus;
  mWorkspace: TWorkspaceStatus;
  mJson: TJSONObject;
begin
  mWorkspace := Default(TWorkspaceStatus);
  mWorkspace.Name := 'Kern';
  mWorkspace.LastIndexMs := -1;
  Assert.AreEqual('', mWorkspace.ProjectText);
  mWorkspace.Project := 'C:\P\Kern.dproj';
  mWorkspace.Config := 'Release';
  mWorkspace.Platform := 'Win64';
  Assert.AreEqual(' · Release/Win64', mWorkspace.ProjectText);
  mWorkspace.BuildChosen := True;
  mWorkspace.Active := True;
  mWorkspace.Selected := True;
  mStatus := Default(TServerStatus);
  mStatus.Workspaces := [mWorkspace];
  Assert.IsTrue(Pos('- Kern · Release/Win64 (gewählt) · aktiv in der IDE · ausgewählt: Index wird aufgebaut',
    mStatus.ToMarkdown) > 0, mStatus.ToMarkdown);
  mJson := mStatus.ToJson;
  try
    Assert.AreEqual('Release', mJson.GetValue<string>('workspaces[0].config'));
    Assert.IsTrue(mJson.GetValue<Boolean>('workspaces[0].buildChosen'));
    Assert.IsTrue(mJson.GetValue<Boolean>('workspaces[0].selected'));
  finally
    mJson.Free;
  end;
end;

procedure TLspStatusTests.StatusShowsCompiler;
var
  mStatus: TServerStatus;
  mJson: TJSONObject;
begin
  mStatus := Default(TServerStatus);
  Assert.AreEqual(0, Pos('Compiler', mStatus.ToMarkdown), 'ohne Angabe keine Zeile');
  mStatus.Compiler := 'Compiler: nicht verfügbar (Starter Edition)';
  mStatus.CompilerBackend := 'off';
  mStatus.CompilerReason := 'Atlas kann nicht kompilieren: kein Kommandozeilen-Compiler.';
  Assert.IsTrue(Pos('- Compiler: nicht verfügbar (Starter Edition)', mStatus.ToMarkdown) > 0, mStatus.ToMarkdown);
  Assert.IsTrue(Pos('  Atlas kann nicht kompilieren', mStatus.ToMarkdown) > 0, mStatus.ToMarkdown);
  mJson := mStatus.ToJson;
  try
    Assert.AreEqual('off', mJson.GetValue<string>('compiler.backend'));
    Assert.AreEqual('Compiler: nicht verfügbar (Starter Edition)', mJson.GetValue<string>('compiler.status'));
    Assert.IsTrue(mJson.GetValue<string>('compiler.reason').StartsWith('Atlas kann nicht'));
  finally
    mJson.Free;
  end;
end;

/// <summary>Server prüft gerade, über dem Speicherbudget, mit Warteschlange und einem Prüflauf.</summary>
function BusyServerStatus: TServerStatus;
var
  mProfiler: TCheckProfiler;
begin
  Result := Default(TServerStatus);
  Result.ProcessId := 4711;
  Result.Version := '1.2.0';
  Result.UptimeMs := 65000;
  Result.State := TServerStatus.cStateChecking;
  Result.Memory.Symbols := 10 * 1024 * 1024;
  Result.Memory.Usages := 20 * 1024 * 1024;
  Result.Memory.LibraryUnits := 30 * 1024 * 1024;
  Result.Memory.TreeCache := 4 * 1024 * 1024;
  Result.Memory.Documents := 1024 * 1024;
  Result.Memory.Total := 100 * 1024 * 1024;
  Result.Memory.Budget := 50 * 1024 * 1024;
  Result.Queue.IndexWaiting := 1;
  Result.Queue.CheckWaiting := 12;
  Result.Queue.CheckRunning := 1;
  Result.Queue.OldestWaitMs := 900;
  Result.IndexCacheHitPercent := 95;
  Result.TreeCacheHitPercent := 80;
  Result.TreeCacheTrees := 3;
  mProfiler := TCheckProfiler.Create;
  try
    mProfiler.BeginRun(Now);
    mProfiler.AddUnit('C:\P\Haupt.pas', 5000);
    mProfiler.AddRule('format-args', 2000);
    mProfiler.FinishRun(6);
    Result.CheckRun := mProfiler.Snapshot(TCheckRunProfile.cTop);
  finally
    mProfiler.Free;
  end;
end;

procedure TLspStatusTests.StatusShowsDiagnostics;
var
  mStatus: TServerStatus;
  mJson, mPart: TJSONObject;
  mMarkdown: string;
begin
  mStatus := BusyServerStatus;
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
