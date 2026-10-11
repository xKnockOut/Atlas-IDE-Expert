unit Atlas.Common.Lsp.PullDiagnostics;

// Pull-Diagnosen nach LSP 3.17 (#82):
//
//   textDocument/diagnostic   Befunde einer Datei, geöffnet oder von der Platte
//   workspace/diagnostic      Befunde aller nicht geöffneten Projektdateien
//
// Unterstützt der Client das nicht, bleibt es bei publishDiagnostics
// (TLspSyntaxDiagnostics). Ergebnis-Ids bestehen aus einer Generation, die bei
// geänderten Einstellungen, Index oder Compilerlauf steigt, und dem Stand der
// Datei (Version bzw. Zeitstempel); unveränderte Dateien kosten so nichts.
//
// workspace/diagnostic arbeitet pro Anfrage höchstens BudgetMs und liefert den
// Rest bei der nächsten Anfrage. Gibt es nichts Neues, wartet die Anfrage bis
// WaitMs auf eine Änderung (Long-Polling), damit der Client nicht ständig fragt.

interface

uses
  System.SysUtils,
  System.JSON,
  System.SyncObjs,
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Lsp.SyntaxDiagnostics;

type
  /// <summary>Dateien, deren Befunde workspace/diagnostic meldet.</summary>
  TPullFilesProvider = reference to function: TArray<string>;
  /// <summary>Zeitstempel einer Datei; False, wenn sie fehlt.</summary>
  TPullFileStamp = reference to function(const AFileName: string; out AStamp: Int64): Boolean;
  /// <summary>Text einer Datei von der Platte.</summary>
  TPullReadText = reference to function(const AFileName: string; out AText: string): Boolean;

  TLspPullDiagnostics = class
  public const
    DocumentMethod = 'textDocument/diagnostic';
    WorkspaceMethod = 'workspace/diagnostic';
    RefreshMethod = 'workspace/diagnostic/refresh';
    Identifier = 'atlas';
    DefaultBudgetMs = 3000;
    DefaultWaitMs = 5000;
  private
    FStore: IDocumentStore;
    FDiagnostics: TLspSyntaxDiagnostics;
    FTransport: IJsonRpcTransport;
    FFiles: TPullFilesProvider;
    FStamp: TPullFileStamp;
    FReadText: TPullReadText;
    FGeneration: Integer;
    FChanged: TEvent;
    FRefreshSupport: Boolean;
    FRefreshCounter: Integer;
    FBudgetMs: Cardinal;
    FWaitMs: Cardinal;
    function HandleDocument(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    function CollectWorkspace(const APrevious: TDictionary<string, string>;
      const ACancellation: IJsonRpcCancellationToken; out AComplete: Boolean): TJSONArray;
  public
    constructor Create(const AStore: IDocumentStore; ADiagnostics: TLspSyntaxDiagnostics;
      const ATransport: IJsonRpcTransport; const AFiles: TPullFilesProvider; const AStamp: TPullFileStamp;
      const AReadText: TPullReadText);
    destructor Destroy; override;
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>True, wenn der Client laut initialize-Parametern Pull-Diagnosen kann.</summary>
    class function ClientSupportsPull(const AInitializeParams: TJSONObject): Boolean; static;
    class function ClientSupportsRefresh(const AInitializeParams: TJSONObject): Boolean; static;
    /// <summary>Eintrag diagnosticProvider für die Server-Capabilities.</summary>
    class function Capability: TJSONObject; static;
    /// <summary>Einstellungen, Index oder Compilermeldungen haben sich geändert. Threadsicher.</summary>
    procedure Changed;
    /// <summary>Ergebnis zu einer Datei: {kind, resultId[, items]}. Threadsicher.</summary>
    function DocumentReport(const AUri, APreviousResultId: string): TJSONObject;
    /// <summary>Antwort auf workspace/diagnostic; wartet ohne Neuigkeiten bis WaitMs.</summary>
    function WorkspaceReport(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    property Generation: Integer read FGeneration;
    property RefreshSupport: Boolean read FRefreshSupport write FRefreshSupport;
    property BudgetMs: Cardinal read FBudgetMs write FBudgetMs;
    property WaitMs: Cardinal read FWaitMs write FWaitMs;
  end;

implementation

uses
  System.Diagnostics,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.TextDocument;

{ TLspPullDiagnostics }

constructor TLspPullDiagnostics.Create(const AStore: IDocumentStore; ADiagnostics: TLspSyntaxDiagnostics;
  const ATransport: IJsonRpcTransport; const AFiles: TPullFilesProvider; const AStamp: TPullFileStamp;
  const AReadText: TPullReadText);
begin
  inherited Create;
  FStore := AStore;
  FDiagnostics := ADiagnostics;
  FTransport := ATransport;
  FFiles := AFiles;
  FStamp := AStamp;
  FReadText := AReadText;
  FGeneration := 1;
  FChanged := TEvent.Create(nil, False, False, '');
  FBudgetMs := DefaultBudgetMs;
  FWaitMs := DefaultWaitMs;
end;

destructor TLspPullDiagnostics.Destroy;
begin
  FChanged.Free;
  inherited;
end;

procedure TLspPullDiagnostics.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(DocumentMethod, HandleDocument);
  ADispatcher.RegisterConcurrentRequest(WorkspaceMethod, WorkspaceReport);
end;

class function TLspPullDiagnostics.ClientSupportsPull(const AInitializeParams: TJSONObject): Boolean;
begin
  Result := (AInitializeParams <> nil) and (AInitializeParams.FindValue('capabilities.textDocument.diagnostic') <> nil);
end;

class function TLspPullDiagnostics.ClientSupportsRefresh(const AInitializeParams: TJSONObject): Boolean;
var
  Value: Boolean;
begin
  Result := (AInitializeParams <> nil) and
    AInitializeParams.TryGetValue<Boolean>('capabilities.workspace.diagnostics.refreshSupport', Value) and Value;
end;

class function TLspPullDiagnostics.Capability: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('identifier', Identifier);
  Result.AddPair('interFileDependencies', TJSONBool.Create(True));
  Result.AddPair('workspaceDiagnostics', TJSONBool.Create(True));
end;

procedure TLspPullDiagnostics.Changed;
var
  Request: TJSONObject;
  Counter: Integer;
begin
  TInterlocked.Increment(FGeneration);
  FChanged.SetEvent;
  if not FRefreshSupport or (FTransport = nil) then
    Exit;
  // Geöffnete Dokumente holt der Client nach refresh neu ab (z. B. nach einem Compilerlauf).
  Counter := TInterlocked.Increment(FRefreshCounter);
  Request := TJSONObject.Create;
  try
    Request.AddPair('jsonrpc', '2.0');
    Request.AddPair('id', Format('atlas/diagnostic-refresh-%d', [Counter]));
    Request.AddPair('method', RefreshMethod);
    FTransport.WriteMessage(Request);
  finally
    Request.Free;
  end;
end;

function Diagnose(ADiagnostics: TLspSyntaxDiagnostics; const ADocument: ITextDocument): TJSONArray;
var
  Params: TJSONObject;
begin
  Params := ADiagnostics.Compute(ADocument);
  try
    Result := Params.GetValue('diagnostics').Clone as TJSONArray;
  finally
    Params.Free;
  end;
end;

function TLspPullDiagnostics.DocumentReport(const AUri, APreviousResultId: string): TJSONObject;
var
  Document: ITextDocument;
  FileName, Text, ResultId: string;
  Stamp: Int64;
begin
  FileName := TDocumentUris.ToPath(AUri);
  // atlas.json prüft TLspConfiguration und meldet weiter per publishDiagnostics.
  if SameText(ExtractFileExt(FileName), '.json') then
    ResultId := ''
  else if FStore.TryGet(AUri, Document) then
    ResultId := Format('%d:v%d', [FGeneration, Document.Version])
  else if Assigned(FStamp) and FStamp(FileName, Stamp) and FReadText(FileName, Text) then
  begin
    ResultId := Format('%d:t%d', [FGeneration, Stamp]);
    Document := TTextDocument.Create(AUri, 'objectpascal', 0, Text);
  end
  else
    ResultId := '';
  Result := TJSONObject.Create;
  if (ResultId <> '') and (ResultId = APreviousResultId) then
  begin
    Result.AddPair('kind', 'unchanged');
    Result.AddPair('resultId', ResultId);
    Exit;
  end;
  Result.AddPair('kind', 'full');
  if ResultId <> '' then
    Result.AddPair('resultId', ResultId);
  if Document = nil then
    Result.AddPair('items', TJSONArray.Create)
  else
    Result.AddPair('items', Diagnose(FDiagnostics, Document));
end;

function TLspPullDiagnostics.HandleDocument(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Uri, Previous: string;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Feld "textDocument.uri" fehlt in ' + DocumentMethod);
  if not TJSONObject(AParams).TryGetValue<string>('previousResultId', Previous) then
    Previous := '';
  ACancellation.ThrowIfCancellationRequested;
  Result := DocumentReport(Uri, Previous);
end;

function TLspPullDiagnostics.CollectWorkspace(const APrevious: TDictionary<string, string>;
  const ACancellation: IJsonRpcCancellationToken; out AComplete: Boolean): TJSONArray;
var
  FileName, Uri, Text, ResultId, Known: string;
  Stamp: Int64;
  Document, Disk: ITextDocument;
  Report: TJSONObject;
  Clock: TStopwatch;
begin
  Result := TJSONArray.Create;
  AComplete := True;
  if not Assigned(FFiles) then
    Exit;
  Clock := TStopwatch.StartNew;
  try
    for FileName in FFiles() do
    begin
      ACancellation.ThrowIfCancellationRequested;
      Uri := TDocumentUris.FromPath(FileName);
      // Geöffnete Dateien laufen über textDocument/diagnostic.
      if FStore.TryGet(Uri, Document) then
        Continue;
      if not FStamp(FileName, Stamp) then
        Continue;
      ResultId := Format('%d:t%d', [FGeneration, Stamp]);
      if APrevious.TryGetValue(Uri, Known) and (Known = ResultId) then
        Continue;
      if Clock.ElapsedMilliseconds > FBudgetMs then
      begin
        AComplete := False;
        Break;
      end;
      if not FReadText(FileName, Text) then
        Continue;
      // Erst in einer Variablen halten: Bei Übergabe als const würde das Objekt nie freigegeben.
      Disk := TTextDocument.Create(Uri, 'objectpascal', 0, Text);
      Report := TJSONObject.Create;
      Report.AddPair('uri', Uri);
      Report.AddPair('version', TJSONNull.Create);
      Report.AddPair('kind', 'full');
      Report.AddPair('resultId', ResultId);
      Report.AddPair('items', Diagnose(FDiagnostics, Disk));
      Result.AddElement(Report);
      APrevious.AddOrSetValue(Uri, ResultId);
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TLspPullDiagnostics.WorkspaceReport(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Previous: TDictionary<string, string>;
  PreviousIds: TJSONArray;
  Entry: TJSONValue;
  Uri, Value: string;
  Items: TJSONArray;
  Complete: Boolean;
  Waited: Cardinal;
  Generation: Integer;
begin
  Previous := TDictionary<string, string>.Create;
  try
    if (AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<TJSONArray>('previousResultIds', PreviousIds) then
      for Entry in PreviousIds do
        if Entry.TryGetValue<string>('uri', Uri) and Entry.TryGetValue<string>('value', Value) then
          Previous.AddOrSetValue(Uri, Value);
    Generation := FGeneration;
    Items := CollectWorkspace(Previous, ACancellation, Complete);
    // Nichts Neues: auf eine Änderung warten, statt sofort leer zu antworten.
    Waited := 0;
    while (Items.Count = 0) and Complete and (Waited < FWaitMs) and not ACancellation.IsCancellationRequested do
    begin
      FChanged.WaitFor(100);
      if FGeneration <> Generation then
      begin
        Items.Free;
        Generation := FGeneration;
        Items := CollectWorkspace(Previous, ACancellation, Complete);
      end;
      Inc(Waited, 100);
    end;
    Result := TJSONObject.Create;
    TJSONObject(Result).AddPair('items', Items);
  finally
    Previous.Free;
  end;
end;

end.
