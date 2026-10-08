unit BDLsp.Common.Lsp.SyntaxDiagnostics;

// Meldet Syntaxfehler des Parsers als textDocument/publishDiagnostics.
// Nach didOpen und didChange wird das Dokument nach einer kurzen Verzögerung
// geparst (Debouncing beim Tippen); bei didClose werden die Meldungen gelöscht.
// Jede Meldung trägt Zeile, Spalte und Endposition in UTF-16.
// Sind die Symbole des Projekts bekannt (DefinesProvider), kommen inaktive
// {$IFDEF}-Bereiche als Hinweise mit dem Tag Unnecessary dazu; der Editor
// blendet sie ab. Ohne Projekt wird nichts abgeblendet, weil die aktiven
// Symbole dann nicht bekannt sind.
// Ist die Delphi-Version bekannt (VersionProvider), werden Sprachmerkmale,
// die diese Version noch nicht kennt, als Warnung gemeldet.

interface

uses
  System.SysUtils,
  System.JSON,
  BDLsp.Common.JsonRpc.Contract,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Lsp.Internals.Debouncer;

type
  /// <summary>Symbole für das Dokument AUri; False, wenn kein Projekt sie festlegt.
  /// Wird im Hintergrund-Thread aufgerufen.</summary>
  TDefinesProvider = reference to function(const AUri: string; out ADefines: TArray<string>): Boolean;
  /// <summary>Eingestellte Delphi-Version für AUri; '' = unbekannt. Hintergrund-Thread.</summary>
  TDelphiVersionProvider = reference to function(const AUri: string): string;

  TLspSyntaxDiagnostics = class
  public const
    /// <summary>Verzögerung nach dem letzten Tastendruck; mit Parsen bleibt es unter 200 ms.</summary>
    DefaultDelayMs = 100;
    Source = 'BetterDelphiLSP';
    InactiveMessage = 'Inaktiver Bereich (bedingte Kompilierung)';
  private
    FStore: IDocumentStore;
    FTransport: IJsonRpcTransport;
    FDebouncer: TDebouncer;
    /// <summary>Hält Prüfen und Senden zusammen, damit nach dem Schließen nichts Veraltetes mehr kommt.</summary>
    FSendLock: TObject;
    FDefinesLock: TObject;
    FDefinesProvider: TDefinesProvider;
    FVersionProvider: TDelphiVersionProvider;
    procedure HandleDocumentEvent(AKind: TDocumentEventKind; const ADocument: ITextDocument);
    procedure ScheduleParse(const ADocument: ITextDocument);
    procedure Publish(const ADocument: ITextDocument);
    function IsCurrent(const ADocument: ITextDocument): Boolean;
    function GetOnError: TProc<Exception>;
    procedure SetOnError(const AValue: TProc<Exception>);
    function CurrentDefines(const AUri: string; out ADefines: TArray<string>): Boolean;
    procedure SetDefinesProvider(const AValue: TDefinesProvider);
    function CurrentVersion(const AUri: string): string;
    procedure SetVersionProvider(const AValue: TDelphiVersionProvider);
  public
    /// <summary>Bei ADelayMs = 0 wird sofort im Thread der Nachrichtenschleife geparst.</summary>
    constructor Create(const AStore: IDocumentStore; const ATransport: IJsonRpcTransport;
      ADelayMs: Cardinal = DefaultDelayMs);
    destructor Destroy; override;
    /// <summary>Meldet sich am Dokumentspeicher an.</summary>
    procedure Attach;
    /// <summary>Parameter für publishDiagnostics. Der Aufrufer übernimmt das Objekt.</summary>
    class function BuildParams(const ADocument: ITextDocument): TJSONObject; overload; static;
    /// <summary>Wie oben, zusätzlich mit inaktiven Bereichen als Hinweise (Tag Unnecessary).</summary>
    class function BuildParams(const ADocument: ITextDocument;
      const AInactive: TArray<TTextRange>): TJSONObject; overload; static;
    /// <summary>Wie oben, zusätzlich mit Sprachmerkmalen, die ADelphiVersion nicht kennt.</summary>
    class function BuildParams(const ADocument: ITextDocument; const AInactive: TArray<TTextRange>;
      const ADelphiVersion: string): TJSONObject; overload; static;
    /// <summary>Prüft alle geöffneten Dokumente neu, z. B. nach geänderten Symbolen.</summary>
    procedure Refresh;
    /// <summary>Parameter mit leerer Liste, z. B. nach dem Schließen. Der Aufrufer übernimmt das Objekt.</summary>
    class function BuildEmptyParams(const AUri: string): TJSONObject; static;
    /// <summary>Wird bei Ausnahmen beim Parsen im Hintergrund aufgerufen.</summary>
    property OnError: TProc<Exception> read GetOnError write SetOnError;
    /// <summary>Liefert die Symbole für das Abblenden inaktiver Bereiche.</summary>
    property DefinesProvider: TDefinesProvider write SetDefinesProvider;
    property VersionProvider: TDelphiVersionProvider write SetVersionProvider;
  end;

implementation

uses
  BDLsp.Common.JsonRpc.Messages,
  BDLsp.Common.Lsp.Contract,
  BDLsp.Common.Lsp.Positions,
  BDLsp.Common.Pascal.SyntaxTree,
  BDLsp.Common.Pascal.Parser,
  BDLsp.Common.Pascal.LanguageFeatures,
  BDLsp.Common.Lsp.InactiveRegions;

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
  FDefinesLock := TObject.Create;
  FDebouncer := TDebouncer.Create(ADelayMs);
end;

destructor TLspSyntaxDiagnostics.Destroy;
begin
  FDebouncer.Free;
  FSendLock.Free;
  FDefinesLock.Free;
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

function TLspSyntaxDiagnostics.CurrentDefines(const AUri: string; out ADefines: TArray<string>): Boolean;
var
  Provider: TDefinesProvider;
begin
  TMonitor.Enter(FDefinesLock);
  try
    Provider := FDefinesProvider;
  finally
    TMonitor.Exit(FDefinesLock);
  end;
  ADefines := nil;
  Result := Assigned(Provider) and Provider(AUri, ADefines);
end;

procedure TLspSyntaxDiagnostics.SetDefinesProvider(const AValue: TDefinesProvider);
begin
  TMonitor.Enter(FDefinesLock);
  try
    FDefinesProvider := AValue;
  finally
    TMonitor.Exit(FDefinesLock);
  end;
end;

function TLspSyntaxDiagnostics.CurrentVersion(const AUri: string): string;
var
  Provider: TDelphiVersionProvider;
begin
  TMonitor.Enter(FDefinesLock);
  try
    Provider := FVersionProvider;
  finally
    TMonitor.Exit(FDefinesLock);
  end;
  if Assigned(Provider) then
    Result := Provider(AUri)
  else
    Result := '';
end;

procedure TLspSyntaxDiagnostics.SetVersionProvider(const AValue: TDelphiVersionProvider);
begin
  TMonitor.Enter(FDefinesLock);
  try
    FVersionProvider := AValue;
  finally
    TMonitor.Exit(FDefinesLock);
  end;
end;

procedure TLspSyntaxDiagnostics.Refresh;
var
  Document: ITextDocument;
begin
  for Document in FStore.Documents do
    if not SameText(ExtractFileExt(Document.Uri), '.json') then
      ScheduleParse(Document);
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
  Defines: TArray<string>;
  Inactive: TArray<TTextRange>;
begin
  Inactive := nil;
  if CurrentDefines(ADocument.Uri, Defines) then
    Inactive := TLspInactiveRegions.Ranges(ADocument.Text, Defines);
  Params := BuildParams(ADocument, Inactive, CurrentVersion(ADocument.Uri));
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
begin
  Result := BuildParams(ADocument, nil);
end;

class function TLspSyntaxDiagnostics.BuildParams(const ADocument: ITextDocument;
  const AInactive: TArray<TTextRange>): TJSONObject;
begin
  Result := BuildParams(ADocument, AInactive, '');
end;

class function TLspSyntaxDiagnostics.BuildParams(const ADocument: ITextDocument;
  const AInactive: TArray<TTextRange>; const ADelphiVersion: string): TJSONObject;
var
  Finding: TLanguageFeatureFinding;
  Range: TTextRange;
  Tags: TJSONArray;
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
    for Finding in TLanguageFeatures.Check(Tree, ADelphiVersion) do
    begin
      Item := TJSONObject.Create;
      Item.AddPair('range', TLspPositions.RangeToJson(TTextRange.Create(Finding.StartPos, Finding.EndPos)));
      Item.AddPair('severity', TJSONNumber.Create(TLspDiagnosticSeverity.Warning));
      Item.AddPair('source', Source);
      Item.AddPair('message', Finding.Message);
      Items.AddElement(Item);
    end;
  finally
    Tree.Free;
  end;
  for Range in AInactive do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('range', TLspPositions.RangeToJson(Range));
    Item.AddPair('severity', TJSONNumber.Create(TLspDiagnosticSeverity.Hint));
    Item.AddPair('source', Source);
    Item.AddPair('message', InactiveMessage);
    Tags := TJSONArray.Create;
    // DiagnosticTag.Unnecessary
    Tags.Add(1);
    Item.AddPair('tags', Tags);
    Items.AddElement(Item);
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
