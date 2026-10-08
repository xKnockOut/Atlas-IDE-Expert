unit BDLsp.Common.Lsp.SyntaxDiagnostics;

// Meldet Syntaxfehler des Parsers als textDocument/publishDiagnostics.
// Nach didOpen und didChange wird das Dokument nach einer kurzen Verzögerung
// geparst (Debouncing beim Tippen); bei didClose werden die Meldungen gelöscht.
// Jede Meldung trägt Zeile, Spalte und Endposition in UTF-16.

interface

uses
  System.SysUtils,
  System.JSON,
  BDLsp.Common.JsonRpc.Contract,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Lsp.Internals.Debouncer;

type
  TLspSyntaxDiagnostics = class
  public const
    /// <summary>Verzögerung nach dem letzten Tastendruck; mit Parsen bleibt es unter 200 ms.</summary>
    DefaultDelayMs = 100;
    Source = 'BetterDelphiLSP';
  private
    FStore: IDocumentStore;
    FTransport: IJsonRpcTransport;
    FDebouncer: TDebouncer;
    /// <summary>Hält Prüfen und Senden zusammen, damit nach dem Schließen nichts Veraltetes mehr kommt.</summary>
    FSendLock: TObject;
    procedure HandleDocumentEvent(AKind: TDocumentEventKind; const ADocument: ITextDocument);
    procedure ScheduleParse(const ADocument: ITextDocument);
    procedure Publish(const ADocument: ITextDocument);
    function IsCurrent(const ADocument: ITextDocument): Boolean;
    function GetOnError: TProc<Exception>;
    procedure SetOnError(const AValue: TProc<Exception>);
  public
    /// <summary>Bei ADelayMs = 0 wird sofort im Thread der Nachrichtenschleife geparst.</summary>
    constructor Create(const AStore: IDocumentStore; const ATransport: IJsonRpcTransport;
      ADelayMs: Cardinal = DefaultDelayMs);
    destructor Destroy; override;
    /// <summary>Meldet sich am Dokumentspeicher an.</summary>
    procedure Attach;
    /// <summary>Parameter für publishDiagnostics. Der Aufrufer übernimmt das Objekt.</summary>
    class function BuildParams(const ADocument: ITextDocument): TJSONObject; static;
    /// <summary>Parameter mit leerer Liste, z. B. nach dem Schließen. Der Aufrufer übernimmt das Objekt.</summary>
    class function BuildEmptyParams(const AUri: string): TJSONObject; static;
    /// <summary>Wird bei Ausnahmen beim Parsen im Hintergrund aufgerufen.</summary>
    property OnError: TProc<Exception> read GetOnError write SetOnError;
  end;

implementation

uses
  BDLsp.Common.JsonRpc.Messages,
  BDLsp.Common.Lsp.Contract,
  BDLsp.Common.Lsp.Positions,
  BDLsp.Common.Pascal.SyntaxTree,
  BDLsp.Common.Pascal.Parser;

// Übernimmt AParams.
procedure Send(const ATransport: IJsonRpcTransport; AParams: TJSONObject);
var
  Notification: TJSONObject;
begin
  Notification := TJsonRpcMessages.Notification(TLspTextDocumentMethod.PublishDiagnostics, AParams);
  try
    ATransport.WriteMessage(Notification);
  finally
    Notification.Free;
  end;
end;

{ TLspSyntaxDiagnostics }

constructor TLspSyntaxDiagnostics.Create(const AStore: IDocumentStore; const ATransport: IJsonRpcTransport;
  ADelayMs: Cardinal);
begin
  inherited Create;
  FStore := AStore;
  FTransport := ATransport;
  FSendLock := TObject.Create;
  FDebouncer := TDebouncer.Create(ADelayMs);
end;

destructor TLspSyntaxDiagnostics.Destroy;
begin
  FDebouncer.Free;
  FSendLock.Free;
  inherited;
end;

procedure TLspSyntaxDiagnostics.Attach;
begin
  FStore.Subscribe(HandleDocumentEvent);
end;

function TLspSyntaxDiagnostics.GetOnError: TProc<Exception>;
begin
  Result := FDebouncer.OnError;
end;

procedure TLspSyntaxDiagnostics.SetOnError(const AValue: TProc<Exception>);
begin
  FDebouncer.OnError := AValue;
end;

procedure TLspSyntaxDiagnostics.HandleDocumentEvent(AKind: TDocumentEventKind; const ADocument: ITextDocument);
begin
  // JSON-Dateien wie delphi-lsp.json prüft TLspConfiguration.
  if SameText(ExtractFileExt(ADocument.Uri), '.json') then
    Exit;
  case AKind of
    TDocumentEventKind.Opened, TDocumentEventKind.Changed:
      ScheduleParse(ADocument);
    TDocumentEventKind.Closed:
      begin
        TMonitor.Enter(FSendLock);
        try
          FDebouncer.Cancel(ADocument.Uri);
          Send(FTransport, BuildEmptyParams(ADocument.Uri));
        finally
          TMonitor.Exit(FSendLock);
        end;
      end;
  end;
end;

procedure TLspSyntaxDiagnostics.ScheduleParse(const ADocument: ITextDocument);
begin
  // Eigene Methode, damit die anonyme Methode genau diese Momentaufnahme festhält.
  FDebouncer.Schedule(ADocument.Uri,
    procedure
    begin
      Publish(ADocument);
    end);
end;

function TLspSyntaxDiagnostics.IsCurrent(const ADocument: ITextDocument): Boolean;
var
  Current: ITextDocument;
begin
  Result := FStore.TryGet(ADocument.Uri, Current) and (Current.Version = ADocument.Version);
end;

procedure TLspSyntaxDiagnostics.Publish(const ADocument: ITextDocument);
var
  Params: TJSONObject;
begin
  Params := BuildParams(ADocument);
  TMonitor.Enter(FSendLock);
  try
    // Inzwischen geändert oder geschlossen: Der neuere Stand meldet selbst.
    if IsCurrent(ADocument) then
      Send(FTransport, Params)
    else
      Params.Free;
  finally
    TMonitor.Exit(FSendLock);
  end;
end;

class function TLspSyntaxDiagnostics.BuildParams(const ADocument: ITextDocument): TJSONObject;
var
  Tree: TSyntaxTree;
  Diagnostic: TSyntaxDiagnostic;
  Items: TJSONArray;
  Item: TJSONObject;
begin
  Items := TJSONArray.Create;
  Tree := TPascalParser.Parse(ADocument.Text);
  try
    for Diagnostic in Tree.Diagnostics do
    begin
      Item := TJSONObject.Create;
      Item.AddPair('range', TLspPositions.RangeToJson(TTextRange.Create(Diagnostic.StartPos, Diagnostic.EndPos)));
      Item.AddPair('severity', TJSONNumber.Create(TLspDiagnosticSeverity.Error));
      Item.AddPair('source', Source);
      Item.AddPair('message', Diagnostic.Message);
      Items.AddElement(Item);
    end;
  finally
    Tree.Free;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('uri', ADocument.Uri);
  Result.AddPair('version', TJSONNumber.Create(ADocument.Version));
  Result.AddPair('diagnostics', Items);
end;

class function TLspSyntaxDiagnostics.BuildEmptyParams(const AUri: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('uri', AUri);
  Result.AddPair('diagnostics', TJSONArray.Create);
end;

end.
