unit Shell.Composition.DiagnosticsArea;

// Teilwurzel Diagnosen der Komposition: Syntaxprüfung beim Tippen, Pull-Diagnosen mit Projektprüfung und das Tor,
// das die Projektprüfung je Indexaufbau nur einmal neu startet. Sie entsteht vor dem Kern; alles, was aus dem Kern,
// dem Index oder den Compilerläufen kommt, fragt sie erst beim Aufruf.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Logging.Contract,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Lsp.SyntaxDiagnostics,
  Atlas.Common.Lsp.PullDiagnostics,
  Atlas.Common.Lsp.WorkspaceCheck,
  Shell.Composition.Core,
  Shell.Composition.Folders;

type
  /// <summary>Der Kern; nil, solange er noch nicht besteht.</summary>
  TShellDiagnosticsCoreFunc = reference to function: TShellCore;
  /// <summary>Compilermeldungen zur Datei AFileName (#1247).</summary>
  TShellDiagnosticsMessagesFunc = reference to function(const AFileName: string): TArray<TCompilerMessage>;

  /// <summary>Was die Diagnosen von der Komposition brauchen; die Funktionen fragen erst beim Aufruf.</summary>
  TShellDiagnosticsAreaServices = record
    Logger: ILogger;
    Transport: IJsonRpcTransport;
    Dispatcher: TJsonRpcDispatcher;
    Documents: IDocumentStore;
    Core: TShellDiagnosticsCoreFunc;
    Index: TShellFoldersIndexFunc;
    CompilerMessages: TShellDiagnosticsMessagesFunc;
    /// <summary>Ungenutzte uses (#621): dieselbe Analyse wie die uses-Aktionen.</summary>
    UsesContext: TUsesContextProvider;
    /// <summary>Unit im Diagnoselog nur anonym (#1094).</summary>
    FileLabel: TPullFileLabel;
    /// <summary>Long-Polling endet vor dem Zeitlimit des Watchdogs.</summary>
    RequestTimeout: TPullTimeout;
  end;

  /// <summary>Hält Syntaxprüfung, Pull-Diagnosen und das Tor der Projektprüfung.</summary>
  TShellDiagnosticsArea = class
  private
    FServices: TShellDiagnosticsAreaServices;
    FSyntax: TLspSyntaxDiagnostics;
    FPull: TLspPullDiagnostics;
    // Projektprüfung je Indexaufbau nur einmal neu starten (29.10.2026).
    FIndexRecheck: TWorkspaceCheckIndexGate;
    function Providers: TSyntaxDiagnosticsProviders;
    procedure CheckFailed(AError: Exception);
    function CheckFiles: TArray<string>;
    function IndexPending: Boolean;
    /// <summary>Units, die AFileName in uses haben (#1247).</summary>
    function DependentUnitsOf(const AFileName: string): TArray<string>;
    procedure LogInfo(const AMessage: string);
    procedure WirePull;
  public
    /// <summary>Legt Syntaxprüfung und Pull-Diagnosen an und meldet sie an Dokumenten und Verteiler an.</summary>
    constructor Create(const AServices: TShellDiagnosticsAreaServices);
    /// <summary>Gibt das Tor frei; vorher FreeChecks.</summary>
    destructor Destroy; override;
    /// <summary>Beenden: gibt Pull-Diagnosen und Syntaxprüfung frei, vor den Ordnern, denn der Hintergrund-Thread
    /// der Syntaxprüfung fragt ihre Symbole ab. Das Tor bleibt, bis die Index-Threads der Ordner fertig sind.</summary>
    procedure FreeChecks;
    /// <summary>Pull-Diagnosen nur für Clients, die sie können; sonst bleibt es bei publishDiagnostics (#82).
    /// Ergänzt ACapabilities um diagnosticProvider.</summary>
    procedure ApplyClientCapabilities(const AInitializeParams: TJSONObject; ACapabilities: TJSONObject);
    property Syntax: TLspSyntaxDiagnostics read FSyntax;
    property Pull: TLspPullDiagnostics read FPull;
    property IndexRecheck: TWorkspaceCheckIndexGate read FIndexRecheck;
  end;

implementation

uses
  System.IOUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Text.LogMarks;

/// <summary>Zeitstempel einer Datei in Millisekunden (UTC); False, wenn sie fehlt.</summary>
function FileStampOf(const AFileName: string; out AStamp: Int64): Boolean;
begin
  Result := TFile.Exists(AFileName);
  AStamp := 0;
  if Result then
  begin
    AStamp := Round(TFile.GetLastWriteTimeUtc(AFileName) * MSecsPerDay);
  end;
end;

/// <summary>Liest eine vorhandene Datei mit erkannter Kodierung; False, wenn sie fehlt.</summary>
function LoadExistingFile(const AFileName: string; out AText: string): Boolean;
var
  mFileFormat: TFileFormat;
begin
  Result := TFile.Exists(AFileName);
  AText := '';
  if Result then
  begin
    AText := TFileEncoding.LoadFromFile(AFileName, mFileFormat);
  end;
end;

constructor TShellDiagnosticsArea.Create(const AServices: TShellDiagnosticsAreaServices);
begin
  inherited Create;
  FServices := AServices;
  FSyntax := TLspSyntaxDiagnostics.Create(FServices.Documents, FServices.Transport, Providers);
  FSyntax.OnError := CheckFailed;
  FSyntax.Attach;
  FIndexRecheck := TWorkspaceCheckIndexGate.Create;
  WirePull;
end;

destructor TShellDiagnosticsArea.Destroy;
begin
  FreeChecks;
  FreeAndNil(FIndexRecheck);
  inherited;
end;

procedure TShellDiagnosticsArea.FreeChecks;
begin
  FreeAndNil(FPull);
  FreeAndNil(FSyntax);
end;

procedure TShellDiagnosticsArea.WirePull;
var
  mPull: TLspPullDiagnostics;
begin
  FPull := TLspPullDiagnostics.Create(FServices.Documents, FSyntax, FServices.Transport, CheckFiles, FileStampOf,
    LoadExistingFile);
  mPull := FPull;
  FPull.Busy := IndexPending;
  FPull.FileLabel := FServices.FileLabel;
  FPull.RequestTimeout := FServices.RequestTimeout;
  FPull.Attach(FServices.Dispatcher);
  // Als anonyme Methode statt der Methode selbst: Free Pascal (Linux-Bau) bricht an der Zuweisung einer
  // Methode an eine Methodenreferenz intern ab.
  FSyntax.OnPullChanged :=
    procedure
    begin
      mPull.Changed;
    end;
  // Neue Compilermeldungen (#1247): nur ihre Dateien neu prüfen, nicht alle Units.
  FSyntax.OnPullFilesChanged :=
    procedure(AFiles: TArray<string>)
    begin
      mPull.FilesChanged(AFiles);
    end;
  // Nach dem Speichern prüft die Projektprüfung auch die Units, die die Datei in uses haben (#1247).
  FPull.Check.Dependents := DependentUnitsOf;
  FPull.Check.OnLog := LogInfo;
end;

function TShellDiagnosticsArea.Providers: TSyntaxDiagnosticsProviders;
var
  mCore: TShellDiagnosticsCoreFunc;
  mMessages: TShellDiagnosticsMessagesFunc;
begin
  mCore := FServices.Core;
  mMessages := FServices.CompilerMessages;
  Result := Default(TSyntaxDiagnosticsProviders);
  Result.Defines :=
    function(const AUri: string; out ADefines: TArray<string>): Boolean
    begin
      Result := mCore().Directives.Defines()(AUri, ADefines);
    end;
  // Sprachstand (#1126): minDelphiVersion begrenzt, was die Regeln als verfügbar ansehen.
  Result.Version :=
    function(const AUri: string): string
    begin
      Result := mCore().FileOptions.LanguageLevelFor(AUri);
    end;
  Result.BuildTarget :=
    function(const AUri: string; out APlatform, AConfig: string): Boolean
    begin
      Result := mCore().Directives.BuildTarget()(AUri, APlatform, AConfig);
    end;
  Result.Rules :=
    function(const AUri: string; out AContext: TRuleCheckContext): Boolean
    begin
      Result := mCore().RuleContext.LiveRuleContextFor(AUri, AContext);
    end;
  Result.CompilerMessages :=
    function(const AFileName: string): TArray<TCompilerMessage>
    begin
      Result := mMessages(AFileName);
    end;
  Result.UsesContext := FServices.UsesContext;
end;

procedure TShellDiagnosticsArea.CheckFailed(AError: Exception);
begin
  FServices.Logger.Error(Format('Fehler beim Prüfen der Syntax: %s: %s', [AError.ClassName,
    TLogMarks.Text(AError.Message)]));
end;

function TShellDiagnosticsArea.CheckFiles: TArray<string>;
begin
  Result := FServices.Core().CheckFiles;
end;

function TShellDiagnosticsArea.IndexPending: Boolean;
begin
  Result := FServices.Core().Workspaces.ProjectIndexPending;
end;

function TShellDiagnosticsArea.DependentUnitsOf(const AFileName: string): TArray<string>;
var
  mIndex: ISymbolIndex;
begin
  Result := nil;
  mIndex := FServices.Index();
  if mIndex <> nil then
  begin
    Result := TLspWorkspaceCheck.DependentsOf(mIndex.Units, AFileName);
  end;
end;

procedure TShellDiagnosticsArea.LogInfo(const AMessage: string);
begin
  FServices.Logger.Info(AMessage);
end;

procedure TShellDiagnosticsArea.ApplyClientCapabilities(const AInitializeParams: TJSONObject;
  ACapabilities: TJSONObject);
begin
  if TLspPullProtocol.ClientSupportsPull(AInitializeParams) then
  begin
    ACapabilities.AddPair('diagnosticProvider', TLspPullProtocol.Capability);
    FPull.RefreshSupport := TLspPullProtocol.ClientSupportsRefresh(AInitializeParams);
    FSyntax.PullMode := True;
  end;
end;

end.
