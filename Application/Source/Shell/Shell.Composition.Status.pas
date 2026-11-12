unit Shell.Composition.Status;

// Internals-Rolle Shell: Status des Servers (#28, #1356), Fehlerbericht (#108) und Diagnosepaket (#1356). Die
// Komposition reicht Index, Dokumente, Arbeitsbereiche (unter ihrer Sperre), Protokoll, Mitschnitt und die
// Zustände von Compiler, Prüflauf und Index-Warteschlange als Dienste herein.

interface

uses
  System.JSON,
  System.Diagnostics,
  Atlas.Common.Lsp.Commands,
  Atlas.Common.Lsp.Status,
  Atlas.Common.Lsp.ServerActivity,
  Atlas.Text.LogMarks,
  Shell.Workspace,
  Shell.Composition.Status.Contract;

type
  /// <summary>Status, Prozesse, Fehlerbericht und Diagnosepaket.</summary>
  TShellStatusReports = class
  private
    FServices: TShellStatusServices;
    FStartedAt: TDateTime;
    FUptime: TStopwatch;
    function Workspaces: TArray<TShellWorkspace>;
    function WorkspaceRoots: TArray<string>;
    function RecentLines: TArray<string>;
    /// <summary>Protokoll der Sitzung, mit AAnonymize über den Anonymisierer, sonst im Klartext.</summary>
    function SessionLines(AAnonymize: Boolean): TArray<string>;
    /// <summary>Ersatz eines Namens oder Pfads im anonymen Status (Anonymisierer des Servers).</summary>
    function AnonymousMap: TLogMarkMap;
    function CollectStatus: TServerStatus;
    procedure CollectDiagnosticsStatus(var AStatus: TServerStatus);
    function ConfigurationReport: string;
    function BugReport(const AArguments: TJSONArray): TJSONValue;
    function DiagnosticPackage(const AArguments: TJSONArray): TJSONValue;
  public
    constructor Create(const AServices: TShellStatusServices);
    /// <summary>Fehlerbericht und Diagnosepaket, nebenläufig (#874).</summary>
    procedure RegisterCommands(ACommands: TLspCommands);
    /// <summary>Status als JSON und ins Log.</summary>
    function StatusJson(AAnonymize: Boolean): TJSONObject;
    /// <summary>Ausführlicher Status für die Statusdatei (#1356, #1901): Wurzeln, Status im Klartext (gehört dem
    /// Aufrufer) und Zustand; ohne Protokollzeile, weil TServerStatusHeartbeat ihn alle paar Sekunden holt.</summary>
    function FileDetails: TServerDetails;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.IOUtils,
  System.Math,
  Atlas.Common.Product.Version,
  Atlas.Common.Logging.Providers.RecentSink,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Scheduler,
  Atlas.Common.JsonRpc.TracingTransport,
  Atlas.Common.Diagnostics.Anonymizer,
  Atlas.Common.Lsp.WorkspaceCheck,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Diagnostics.ShutdownLeaks,
  Atlas.Common.Diagnostics.BugReport,
  Atlas.Common.Diagnostics.CheckProfile,
  Atlas.Common.Diagnostics.ServerPackage,
  Atlas.Common.Index.Adapters.CacheDirectory,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Projects.PackageLocator,
  Atlas.Text.Anonymize,
  Shell.Platform;

const
  /// <summary>So viele Zeilen des Protokolls im Fehlerbericht (#108); das Diagnosepaket nimmt alle (#1356).</summary>
  cBugReportLogLines = 200;

/// <summary>Die letzten ACount Einträge von ALines.</summary>
function LastLines(const ALines: TArray<string>; ACount: Integer): TArray<string>;
begin
  if Length(ALines) <= ACount then
  begin
    Result := ALines;
    Exit;
  end;
  Result := Copy(ALines, Length(ALines) - ACount, ACount);
end;

/// <summary>Optionen des Fehlerberichts aus dem ersten Argument: anonymize, client, target.</summary>
procedure ReadBugReportOptions(const AArguments: TJSONArray; var AInput: TBugReportInput; out ATarget: string);
var
  mOptions: TJSONObject;
begin
  ATarget := '';
  if (AArguments = nil) or (AArguments.Count = 0) or not (AArguments.Items[0] is TJSONObject) then
  begin
    Exit;
  end;
  mOptions := TJSONObject(AArguments.Items[0]);
  if mOptions.GetValue('anonymize') is TJSONBool then
  begin
    AInput.Anonymize := TJSONBool(mOptions.GetValue('anonymize')).AsBoolean;
  end;
  if mOptions.GetValue('client') is TJSONString then
  begin
    AInput.Client := mOptions.GetValue('client').Value;
  end;
  if mOptions.GetValue('target') is TJSONString then
  begin
    ATarget := mOptions.GetValue('target').Value;
  end;
end;

/// <summary>Optionen des Diagnosepakets aus dem ersten Argument: anonymize, traceMinutes.</summary>
procedure ReadPackageOptions(const AArguments: TJSONArray; var AInput: TServerPackageInput);
var
  mOptions: TJSONObject;
begin
  if (AArguments = nil) or (AArguments.Count = 0) or not (AArguments.Items[0] is TJSONObject) then
  begin
    Exit;
  end;
  mOptions := TJSONObject(AArguments.Items[0]);
  if mOptions.GetValue('anonymize') is TJSONBool then
  begin
    AInput.Anonymize := TJSONBool(mOptions.GetValue('anonymize')).AsBoolean;
  end;
  if mOptions.GetValue('traceMinutes') is TJSONNumber then
  begin
    AInput.TraceMinutes := TJSONNumber(mOptions.GetValue('traceMinutes')).AsInt;
  end;
end;

/// <summary>JSON aus AText, sonst der Text als Zeichenkette; leer als null.</summary>
function JsonOrText(const AText: string): TJSONValue;
begin
  Result := nil;
  if AText.Trim <> '' then
  begin
    Result := TJSONObject.ParseJSONValue(AText);
  end;
  if (Result = nil) and (AText.Trim <> '') then
  begin
    Result := TJSONString.Create(AText);
  end;
  if Result = nil then
  begin
    Result := TJSONNull.Create;
  end;
end;

/// <summary>Wirksame Einstellungen eines Arbeitsbereichs für den Fehlerbericht.</summary>
function EffectiveSettings(const ASettings: TServerSettings): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('delphiVersion', ASettings.DelphiVersion);
  Result.AddPair('language', ASettings.Language);
  Result.AddPair('defaultEncoding', TJSONNumber.Create(ASettings.DefaultEncoding));
  Result.AddPair('project', ASettings.Project);
  Result.AddPair('config', ASettings.Config);
  Result.AddPair('platform', ASettings.Platform);
  Result.AddPair('profile', ASettings.Profile);
  Result.AddPair('rules', TJSONNumber.Create(Length(ASettings.Rules)));
  Result.AddPair('excludeTests', TJSONBool.Create(ASettings.ExcludeTests));
  Result.AddPair('exclude', TJSONNumber.Create(Length(ASettings.Exclude)));
end;

constructor TShellStatusReports.Create(const AServices: TShellStatusServices);
begin
  inherited Create;
  FServices := AServices;
  FStartedAt := Now;
  FUptime := TStopwatch.StartNew;
end;

procedure TShellStatusReports.RegisterCommands(ACommands: TLspCommands);
begin
  ACommands.RegisterConcurrent(TServerPackage.cCommand, DiagnosticPackage);
  ACommands.RegisterConcurrent(TBugReport.cCommand, BugReport);
end;

function TShellStatusReports.Workspaces: TArray<TShellWorkspace>;
var
  mResult: TArray<TShellWorkspace>;
begin
  mResult := nil;
  FServices.VisitWorkspaces(
    procedure(const AWorkspaces: TArray<TShellWorkspace>)
    begin
      mResult := AWorkspaces;
    end);
  Result := mResult;
end;

function TShellStatusReports.WorkspaceRoots: TArray<string>;
var
  mWorkspace: TShellWorkspace;
begin
  Result := nil;
  for mWorkspace in Workspaces do
  begin
    Result := Result + [mWorkspace.Root];
  end;
end;

function TShellStatusReports.RecentLines: TArray<string>;
var
  mRecentLog: IRecentLogLines;
begin
  Result := nil;
  mRecentLog := FServices.RecentLog();
  if mRecentLog <> nil then
  begin
    Result := mRecentLog.Lines;
  end;
end;

function TShellStatusReports.SessionLines(AAnonymize: Boolean): TArray<string>;
var
  mAnonymizer: ILogAnonymizer;
  mIndex: Integer;
  mRoots: TArray<string>;
begin
  // Die Zeilen tragen Kennzeichen für Namen, Pfade und fremden Text (#1478): anonym über den Anonymisierer des
  // Servers (dieselben name#N wie im Status und in --log), sonst im Klartext.
  Result := RecentLines;
  mAnonymizer := nil;
  mRoots := nil;
  if AAnonymize then
  begin
    mAnonymizer := FServices.Anonymizer();
    mRoots := WorkspaceRoots;
  end;
  for mIndex := 0 to High(Result) do
  begin
    if mAnonymizer <> nil then
    begin
      Result[mIndex] := mAnonymizer.Anonymize(Result[mIndex]);
    end
    else if AAnonymize then
    begin
      Result[mIndex] := TTextAnonymizer.RedactMarks(Result[mIndex], mRoots);
    end
    else
    begin
      Result[mIndex] := TLogMarks.Plain(Result[mIndex]);
    end;
  end;
end;

/// <summary>Kennzeichnet AValue nach seiner Art, für die Protokollzeile des Status.</summary>
function MarkValue(AKind: TLogMarkKind; const AValue: string): string;
begin
  Result := TLogMarks.Mark(AKind, AValue);
end;

function TShellStatusReports.AnonymousMap: TLogMarkMap;
var
  mAnonymizer: ILogAnonymizer;
  mRoots: TArray<string>;
begin
  mAnonymizer := FServices.Anonymizer();
  mRoots := WorkspaceRoots;
  Result :=
    function(AKind: TLogMarkKind; const AValue: string): string
    begin
      if mAnonymizer <> nil then
      begin
        Result := mAnonymizer.Anonymize(TLogMarks.Mark(AKind, AValue));
      end
      else
      begin
        Result := TTextAnonymizer.RedactMarks(TLogMarks.Mark(AKind, AValue), mRoots);
      end;
    end;
end;

function TShellStatusReports.ConfigurationReport: string;
var
  mRoot, mItem, mChoice: TJSONObject;
  mItems: TJSONArray;
  mWorkspace: TShellWorkspace;
  mStatus: TWorkspaceStatus;
begin
  mRoot := TJSONObject.Create;
  try
    // Eingaben der Schichtung (Editor, dann atlas.json mit Vorrang) und die wichtigsten Ergebnisse.
    mRoot.AddPair('editor', JsonOrText(FServices.EditorSettings()));
    mItems := TJSONArray.Create;
    mRoot.AddPair('workspaces', mItems);
    for mWorkspace in Workspaces do
    begin
      mItem := TJSONObject.Create;
      mItems.AddElement(mItem);
      mItem.AddPair('root', mWorkspace.Root);
      mItem.AddPair('file', ExtractFileName(mWorkspace.Configuration.Files.Read));
      mItem.AddPair('fileContent', JsonOrText(mWorkspace.Configuration.Texts.Workspace));
      mItem.AddPair('effective', EffectiveSettings(mWorkspace.Configuration.Settings));
      // Projektwahl (#46): geladen, gewählt, aktiv, ausgewählt; Vorrang atlas.json < selectBuild < IDE.
      mStatus := mWorkspace.IndexStatus;
      mChoice := TJSONObject.Create;
      mItem.AddPair('projectChoice', mChoice);
      mChoice.AddPair('project', mStatus.Project);
      mChoice.AddPair('config', mStatus.Config);
      mChoice.AddPair('platform', mStatus.Platform);
      mChoice.AddPair('buildChosen', TJSONBool.Create(mStatus.BuildChosen));
      mChoice.AddPair('active', TJSONBool.Create((mStatus.Project <> '') and
        SameText(mStatus.Project, FServices.ActiveProject())));
      mChoice.AddPair('selected', TJSONBool.Create(FServices.IsSelectedProject(mWorkspace)));
    end;
    Result := mRoot.Format(2);
  finally
    mRoot.Free;
  end;
end;

function TShellStatusReports.BugReport(const AArguments: TJSONArray): TJSONValue;
var
  mInput: TBugReportInput;
  mTarget, mText: string;
  mAnswer: TJSONObject;
begin
  mInput := Default(TBugReportInput);
  mInput.Anonymize := True;
  ReadBugReportOptions(AArguments, mInput, mTarget);
  mInput.ServerVersion := TProductVersion.cVersion;
  mInput.Created := Now;
  mInput.Configuration := ConfigurationReport;
  mInput.LogLines := LastLines(SessionLines(mInput.Anonymize), cBugReportLogLines);
  mInput.Requests := FServices.Statistics.Recent;
  mInput.Workspaces := WorkspaceRoots;
  mInput.Identity := TProcessInfo.IdentityNames;
  mText := TBugReport.Build(mInput);
  mAnswer := TJSONObject.Create;
  mAnswer.AddPair('text', mText);
  if mTarget <> '' then
  begin
    ForceDirectories(ExtractFileDir(mTarget));
    TFile.WriteAllText(mTarget, mText, TEncoding.UTF8);
    mAnswer.AddPair('file', mTarget);
  end;
  FServices.Logger.Info('Fehlerbericht erstellt');
  Result := mAnswer;
end;

function TShellStatusReports.CollectStatus: TServerStatus;
var
  mDocument: ITextDocument;
  mStatus: TServerStatus;
begin
  mStatus := Default(TServerStatus);
  mStatus.Units := FServices.Index.UnitCount;
  mStatus.Symbols := FServices.Index.SymbolCount;
  mStatus.MemoryBytes := TShutdownLeaks.AllocatedBytes;
  mStatus.IndexBytes := FServices.Index.MemoryBytes;
  mStatus.CompactUnits := FServices.Index.CompactCount;
  mStatus.OffloadedUnits := FServices.Index.OffloadedCount;
  mStatus.DiskBytes := TIndexCacheDirectory.TotalSize(TIndexCacheDirectory.DefaultRoot);
  mStatus.BudgetBytes := FServices.Index.Budget;
  for mDocument in FServices.Documents.Documents do
  begin
    mStatus.DocumentBytes := mStatus.DocumentBytes + Length(mDocument.Text) * SizeOf(Char);
  end;
  // Unter der Sperre der Arbeitsbereiche: Projektwahl (#46), aktiv in der IDE und per selectProject ausgewählt.
  FServices.VisitWorkspaces(
    procedure(const AWorkspaces: TArray<TShellWorkspace>)
    var
      mWorkspace: TShellWorkspace;
    begin
      for mWorkspace in AWorkspaces do
      begin
        mStatus.Workspaces := mStatus.Workspaces + [mWorkspace.IndexStatus];
        mStatus.Workspaces[High(mStatus.Workspaces)].Active := (mWorkspace.State.ProjectFileName <> '') and
          SameText(mWorkspace.State.ProjectFileName, FServices.ActiveProject());
        mStatus.Workspaces[High(mStatus.Workspaces)].Selected := FServices.IsSelectedProject(mWorkspace);
      end;
    end);
  mStatus.Requests := FServices.Statistics.Snapshot;
  FServices.CompilerStatus(mStatus);
  CollectDiagnosticsStatus(mStatus);
  Result := mStatus;
end;

procedure TShellStatusReports.CollectDiagnosticsStatus(var AStatus: TServerStatus);
var
  mParts: TIndexMemoryParts;
  mTrees: TSyntaxTreeCacheStats;
  mIndexQueue: TIndexSchedulerQueue;
  mCheckQueue: TWorkspaceCheckQueue;
  mWorkspace: TWorkspaceStatus;
begin
  // Fenster „Atlas-Server“ (#1356): Prozess, Speicher je Bereich, Prüflauf, Warteschlangen, Cache-Treffer.
  AStatus.ProcessId := TShellPlatform.CurrentProcessId;
  AStatus.Version := TProductVersion.cVersion;
  AStatus.Started := FStartedAt;
  AStatus.UptimeMs := FUptime.ElapsedMilliseconds;
  mParts := FServices.Index.MemoryParts;
  mTrees := TSyntaxTreeCache.Stats;
  AStatus.Memory.Symbols := mParts.ProjectBytes;
  AStatus.Memory.Usages := mParts.UsageBytes;
  AStatus.Memory.LibraryUnits := mParts.LibraryBytes;
  AStatus.Memory.TreeCache := mTrees.Bytes;
  AStatus.Memory.Documents := AStatus.DocumentBytes;
  AStatus.Memory.Packages := TPackageCompiledFiles.Bytes;
  AStatus.Memory.Total := AStatus.MemoryBytes;
  AStatus.Memory.Budget := AStatus.BudgetBytes;
  AStatus.IndexCacheHitPercent := TServerStatus.CacheHitPercent(AStatus.Workspaces);
  AStatus.TreeCacheHitPercent := mTrees.HitPercent;
  AStatus.TreeCacheTrees := mTrees.Trees;
  FServices.CheckStatus(AStatus, mCheckQueue);
  mIndexQueue := FServices.IndexQueue();
  AStatus.Queue.IndexWaiting := mIndexQueue.Waiting;
  AStatus.Queue.IndexRunning := mIndexQueue.Running;
  AStatus.Queue.CheckWaiting := mCheckQueue.Waiting;
  AStatus.Queue.CheckRunning := mCheckQueue.Running;
  AStatus.Queue.OldestWaitMs := Max(mIndexQueue.OldestWaitMs, mCheckQueue.OldestWaitMs);
  // Zustand: lädt, solange ein Arbeitsbereich seinen Index aufbaut; prüft, solange ein Prüflauf aktiv ist.
  AStatus.State := TServerStatus.cStateReady;
  if AStatus.CheckRun.Active then
  begin
    AStatus.State := TServerStatus.cStateChecking;
  end;
  for mWorkspace in AStatus.Workspaces do
  begin
    if mWorkspace.LastIndexMs < 0 then
    begin
      AStatus.State := TServerStatus.cStateLoading;
    end;
  end;
end;

function TShellStatusReports.StatusJson(AAnonymize: Boolean): TJSONObject;
var
  mStatus: TServerStatus;
begin
  mStatus := CollectStatus;
  // Namen und Pfade gekennzeichnet: Das Log schreibt sie anonym, das Ausgabefenster im Klartext (#1478).
  FServices.Logger.Info('Status:' + sLineBreak + mStatus.Mapped(MarkValue).ToMarkdown);
  if AAnonymize then
  begin
    // Ordner, Projekt, Caches, eigene Konfiguration und langsame Units, nicht nur die Units (#1478).
    mStatus := mStatus.Mapped(AnonymousMap());
  end;
  Result := mStatus.ToJson;
end;

function TShellStatusReports.FileDetails: TServerDetails;
var
  mStatus: TServerStatus;
begin
  // Für get_server_status und AtlasMonitor: dieselben Zahlen wie das Fenster, nur lokal und nie anonym.
  mStatus := CollectStatus;
  Result := Default(TServerDetails);
  Result.Roots := WorkspaceRoots;
  Result.State := mStatus.State;
  Result.Status := mStatus.ToJson;
end;

function TShellStatusReports.DiagnosticPackage(const AArguments: TJSONArray): TJSONValue;
var
  mInput: TServerPackageInput;
  mStatus: TJSONObject;
  mTracing: TJsonRpcTracingTransport;
begin
  mInput := Default(TServerPackageInput);
  mInput.Anonymize := True;
  mInput.TraceMinutes := TServerPackage.cDefaultTraceMinutes;
  ReadPackageOptions(AArguments, mInput);
  mStatus := StatusJson(mInput.Anonymize);
  try
    mInput.StatusJson := mStatus.ToJSON([]);
  finally
    mStatus.Free;
  end;
  mInput.LogLines := SessionLines(mInput.Anonymize);
  mTracing := FServices.Tracing();
  mInput.Tracing := mTracing <> nil;
  if mTracing <> nil then
  begin
    mInput.TraceLines := mTracing.RecentLines(mInput.TraceMinutes, Now);
  end;
  mInput.Workspaces := WorkspaceRoots;
  mInput.Identity := TProcessInfo.IdentityNames;
  Result := TServerPackage.ToJson(TServerPackage.Build(mInput));
  FServices.Logger.Info('Diagnosepaket des Servers erstellt');
end;

end.
