unit Atlas.Core.Lsp.Session;

// LSP-Sitzung des IDE-Plugins (ADR 0006): initialize, Dokumentabgleich und die
// Anfragen, die die IDE über den Code Insight-Manager stellt.
// Abgleich: Vor jeder Anfrage wird der aktuelle Editortext geschickt, beim
// ersten Mal als didOpen, danach als didChange mit dem ganzen Text, aber nur,
// wenn er sich geändert hat. Positionen sind 0-basiert in UTF-16-Einheiten
// (Delphi-String-Indizes), wie LSP sie erwartet.
// Diagnosen (#398) holt das Plugin selbst (Pull: textDocument/diagnostic und
// workspace/diagnostic); eine Anfrage workspace/diagnostic/refresh des Servers
// zählt RefreshCount hoch.
// Projektgruppe (#648): SetProjects vor Initialize schickt die Projekte als
// workspaceFolders (uri ist die .dproj, aktives Projekt zuerst); danach meldet
// es Änderungen als workspace/didChangeWorkspaceFolders.

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.Progress,
  Atlas.Core.Hover.Contract,
  Atlas.Core.Problems.Contract;

type
  TLspLocation = record
    FileName: string;
    /// <summary>0-basiert.</summary>
    Line: Integer;
    /// <summary>0-basiert.</summary>
    Character: Integer;
  end;

  /// <summary>Teile eines Hovers für den Atlas-Tooltip (#442).</summary>
  TLspHoverParts = record
    Declaration: string;
    UnitName: string;
    Documentation: string;
    Value: string;
    Deprecation: string;
    function Found: Boolean;
    /// <summary>Aus einer Hover-Antwort: das Feld "atlas" des Servers, sonst erster Absatz als Deklaration.</summary>
    class function FromHover(const AHover: TJSONValue): TLspHoverParts; static;
  end;

  /// <summary>Diagnosebericht einer Datei (#398).</summary>
  TLspDiagnosticReport = record
    FileName: string;
    ResultId: string;
    /// <summary>Seit der vorigen Ergebnis-Id unverändert; Problems ist dann leer.</summary>
    Unchanged: Boolean;
    Problems: TArray<TAtlasProblem>;
    /// <summary>Aus einem Bericht des Servers ({kind, resultId, items}); AFileName, wenn er keine uri hat.</summary>
    class function FromJson(const AReport: TJSONObject; const AFileName: string): TLspDiagnosticReport; static;
  end;

  /// <summary>Zähler, den der Lese-Thread erhöht; überlebt die Sitzung, solange der Client ihn hält.</summary>
  ILspSignal = interface
    ['{6B0C1E57-3A44-4E0B-9A63-2F7A5C0D8E11}']
    function Count: Integer;
    procedure Signal;
  end;

  TLspSession = class
  private type
    TDocumentState = record
      FileName: string;
      Version: Integer;
      Text: string;
    end;
  private
    FClient: TLspClient;
    FRefresh: ILspSignal;
    FProgress: ILspProgress;
    FTimeoutMs: Cardinal;
    FDocuments: TDictionary<string, TDocumentState>;
    // Schützt FDocuments samt Reihenfolge der didOpen/didChange (#493): Sync läuft auch aus
    // Hintergrund-Threads (Zeitlimit für Quellen).
    FDocLock: TObject;
    FInitialized: Boolean;
    FProjects: TArray<string>;
    FServerSettings: string;
    procedure SyncLocked(const AFileName, AText: string);
    procedure CloseLocked(const AFileName: string);
    function PositionParams(const AFileName: string; ALine, ACharacter: Integer): TJSONObject;
  public
    /// <summary>AClient gehört weiter dem Aufrufer.</summary>
    constructor Create(AClient: TLspClient; ATimeoutMs: Cardinal = 3000);
    destructor Destroy; override;
    class function PathToUri(const APath: string): string; static;
    class function UriToPath(const AUri: string): string; static;
    /// <summary>Text aus contents einer Hover-Antwort: String, MarkupContent oder MarkedString-Liste.</summary>
    class function HoverText(const AHover: TJSONValue): string; static;
    /// <summary>Zeichenindex (0-basiert) zur Editorspalte (1-basiert); Tabs springen zur nächsten Tabulatorposition.</summary>
    class function ColumnToIndex(const ALine: string; AColumn, ATabWidth: Integer): Integer; static;
    /// <summary>workspaceFolders-Einträge zu Projektdateien: uri der Datei, Name ohne Endung (#648).</summary>
    class function ProjectFolders(const AProjects: TArray<string>): TJSONArray; static;
    /// <summary>Hinzugekommene und weggefallene Projekte, Groß- und Kleinschreibung egal (#648).</summary>
    class procedure ProjectChanges(const AOld, ANew: TArray<string>; out AAdded, ARemoved: TArray<string>); static;
    /// <summary>Projekte der Gruppe, aktives zuerst. Vor Initialize nur gemerkt, danach als
    /// didChangeWorkspaceFolders gemeldet, falls sich etwas geändert hat (#648).</summary>
    procedure SetProjects(const AProjects: TArray<string>);
    /// <summary>{"settings": {"atlas": AJson}} für initializationOptions und didChangeConfiguration (#652);
    /// leeres oder ungültiges AJson ergibt ein leeres atlas-Objekt.</summary>
    class function SettingsParams(const AJson: string): TJSONObject; static;
    procedure Initialize;
    /// <summary>Einstellungen der Atlas-Optionen im Format von atlas.json (#652), vor Initialize setzen;
    /// gehen als initializationOptions mit, damit schon der erste Indexaufbau sie nutzt.</summary>
    property ServerSettings: string read FServerSettings write FServerSettings;
    /// <summary>Schickt AText, falls neu oder geändert.</summary>
    procedure Sync(const AFileName, AText: string);
    function Hover(const AFileName, AText: string; ALine, ACharacter: Integer): string;
    /// <summary>Hover in Teilen (#442).</summary>
    function HoverParts(const AFileName, AText: string; ALine, ACharacter: Integer): TLspHoverParts;
    /// <summary>Hover mit allen Teilen für den Tooltip (#588): Art, Fundort, Links, Vererbungskette.</summary>
    function HoverData(const AFileName, AText: string; ALine, ACharacter: Integer): TAtlasHoverData;
    /// <summary>Hover an einem Fundort ohne Abgleich: Der Server liest nicht geöffnete Dateien selbst (#588).</summary>
    function HoverDataAt(const AFileName: string; ALine, ACharacter: Integer): TAtlasHoverData;
    /// <summary>Verwendungen des Symbols am Fundort ohne die Deklaration (textDocument/references).</summary>
    function References(const AFileName: string; ALine, ACharacter: Integer): TArray<TLspLocation>;
    function Definition(const AFileName, AText: string; ALine, ACharacter: Integer;
      out ALocation: TLspLocation): Boolean;
    /// <summary>
    /// textDocument/completion ohne Abgleich: Sync vorher im Hauptthread. Darf aus einem
    /// anderen Thread kommen, solange die Sitzung lebt. Liefert die Antwort (CompletionList,
    /// CompletionItem[] oder nil); der Aufrufer gibt sie frei.
    /// </summary>
    function Completion(const AFileName: string; ALine, ACharacter: Integer; ATimeoutMs: Cardinal): TJSONValue;
      overload;
    /// <summary>Wie oben, gestaffelt (#616): AOnPartial bekommt Teilergebnisse (CompletionItem[]) im
    /// Lese-Thread, bevor die Antwort den Rest bringt.</summary>
    function Completion(const AFileName: string; ALine, ACharacter: Integer; ATimeoutMs: Cardinal;
      const AOnPartial: TLspPartialProc): TJSONValue; overload;
    /// <summary>textDocument/signatureHelp ohne Abgleich, wie Completion.</summary>
    function SignatureHelp(const AFileName: string; ALine, ACharacter: Integer; ATimeoutMs: Cardinal): TJSONValue;
    /// <summary>completionItem/resolve für AItem (wird übernommen); threadsicher wie Completion.</summary>
    function ResolveCompletion(AItem: TJSONObject; ATimeoutMs: Cardinal): TJSONValue;
    /// <summary>Benachrichtigung ohne Antwort, z. B. atlas/compileStarted (#527); übernimmt AParams.</summary>
    procedure Notify(const AMethod: string; AParams: TJSONObject);
    /// <summary>Diagnosen einer Datei (textDocument/diagnostic) ohne Abgleich; threadsicher wie Completion.</summary>
    function DocumentDiagnostics(const AFileName, APreviousResultId: string; ATimeoutMs: Cardinal): TLspDiagnosticReport;
    /// <summary>Diagnosen aller Projektdateien außer den geöffneten (workspace/diagnostic, Long-Polling);
    /// APrevious mit FileName und ResultId der bekannten Stände. Threadsicher wie Completion.</summary>
    function WorkspaceDiagnostics(const APrevious: TArray<TLspDiagnosticReport>;
      ATimeoutMs: Cardinal): TArray<TLspDiagnosticReport>;
    /// <summary>didClose für eine abgeglichene Datei; danach liest der Server sie wieder von der Platte.</summary>
    procedure Close(const AFileName: string);
    /// <summary>didSave für eine abgeglichene Datei: Der Server prüft dann mit dcc (compiler.onSave, #40).</summary>
    procedure Saved(const AFileName: string);
    /// <summary>Abgeglichene Dateien (Hauptthread).</summary>
    function SyncedFiles: TArray<string>;
    /// <summary>Zuletzt geschickter Text einer Datei (Hauptthread).</summary>
    function SyncedText(const AFileName: string; out AText: string): Boolean;
    /// <summary>Anzahl der workspace/diagnostic/refresh-Anfragen des Servers.</summary>
    function RefreshCount: Integer;
    /// <summary>Laufende Indizierung o. Ä. des Servers ("Index 45 %"); '' ohne (#492).</summary>
    function ProgressText: string;
    /// <summary>Statusleiste: "Atlas indiziert … (45 %)"; '' ohne laufenden Vorgang (#492).</summary>
    function IndexingText: string;
    /// <summary>workspace/executeCommand; Ergebnis gehört dem Aufrufer (nil bei Fehler oder Zeitlimit).</summary>
    function ExecuteCommand(const ACommand: string; ATimeoutMs: Cardinal): TJSONValue; overload;
    /// <summary>Wie oben mit Argumenten; übernimmt AArguments.</summary>
    function ExecuteCommand(const ACommand: string; AArguments: TJSONArray; ATimeoutMs: Cardinal): TJSONValue;
      overload;
    property Initialized: Boolean read FInitialized;
  end;

implementation

uses
  System.SyncObjs;

const
  Unreserved = ['A'..'Z', 'a'..'z', '0'..'9', '-', '.', '_', '~', '/'];

type
  TLspSignal = class(TInterfacedObject, ILspSignal)
  private
    FCount: Integer;
  public
    function Count: Integer;
    procedure Signal;
  end;

{ TLspSignal }

function TLspSignal.Count: Integer;
begin
  Result := TInterlocked.CompareExchange(FCount, 0, 0);
end;

procedure TLspSignal.Signal;
begin
  TInterlocked.Increment(FCount);
end;

{ TLspSession }

constructor TLspSession.Create(AClient: TLspClient; ATimeoutMs: Cardinal);
begin
  inherited Create;
  FClient := AClient;
  FTimeoutMs := ATimeoutMs;
  FDocuments := TDictionary<string, TDocumentState>.Create;
  FDocLock := TObject.Create;
  FRefresh := TLspSignal.Create;
  FProgress := TLspProgress.Create;
end;

destructor TLspSession.Destroy;
begin
  FDocuments.Free;
  FDocLock.Free;
  inherited;
end;

class function TLspSession.PathToUri(const APath: string): string;
var
  Path: string;
  Bytes: TBytes;
  B: Byte;
  Builder: TStringBuilder;
begin
  Path := StringReplace(APath, '\', '/', [rfReplaceAll]);
  if Path.StartsWith('//') then
    Path := Path.Substring(2)
  else
    Path := '/' + Path;
  Bytes := TEncoding.UTF8.GetBytes(Path);
  Builder := TStringBuilder.Create;
  try
    for B in Bytes do
      if (B < $80) and CharInSet(Char(B), Unreserved) then
        Builder.Append(Char(B))
      else
        Builder.Append('%').Append(IntToHex(B, 2));
    // c:\x → file:///c%3A/x; \\server\share → file://server/share
    Result := 'file://' + Builder.ToString;
  finally
    Builder.Free;
  end;
end;

class function TLspSession.UriToPath(const AUri: string): string;
var
  Rest: string;
  Bytes: TBytes;
  Count, Index, Code: Integer;
  Chunk: TBytes;
begin
  if not AUri.StartsWith('file://', True) then
    Exit('');
  Rest := AUri.Substring(Length('file://'));
  SetLength(Bytes, Length(Rest) * 3);
  Count := 0;
  Index := 1;
  while Index <= Length(Rest) do
  begin
    if (Rest[Index] = '%') and (Index + 2 <= Length(Rest)) then
    begin
      Code := StrToIntDef('$' + Copy(Rest, Index + 1, 2), -1);
      if Code >= 0 then
      begin
        Bytes[Count] := Code;
        Inc(Count);
        Inc(Index, 3);
        Continue;
      end;
    end;
    Chunk := TEncoding.UTF8.GetBytes(Rest[Index]);
    Move(Chunk[0], Bytes[Count], Length(Chunk));
    Inc(Count, Length(Chunk));
    Inc(Index);
  end;
  Result := TEncoding.UTF8.GetString(Bytes, 0, Count);
  if Result.StartsWith('/') then
  begin
    // file:///c:/x → c:\x; file://server/share → \\server\share
    if (Length(Result) >= 3) and (Result[3] = ':') then
      Result := Result.Substring(1)
    else
      Result := '/' + Result;
  end
  else
    Result := '//' + Result;
  Result := StringReplace(Result, '/', '\', [rfReplaceAll]);
end;

class function TLspSession.HoverText(const AHover: TJSONValue): string;
var
  Contents: TJSONValue;
  Item: TJSONValue;
begin
  Result := '';
  if not (AHover is TJSONObject) then
    Exit;
  Contents := TJSONObject(AHover).GetValue('contents');
  if Contents is TJSONString then
    Result := TJSONString(Contents).Value
  else if Contents is TJSONObject then
    Result := TJSONObject(Contents).GetValue<string>('value', '')
  else if Contents is TJSONArray then
    for Item in TJSONArray(Contents) do
    begin
      if Result <> '' then
        Result := Result + sLineBreak;
      if Item is TJSONString then
        Result := Result + TJSONString(Item).Value
      else if Item is TJSONObject then
        Result := Result + TJSONObject(Item).GetValue<string>('value', '');
    end;
end;

class function TLspSession.ColumnToIndex(const ALine: string; AColumn, ATabWidth: Integer): Integer;
var
  Visual: Integer;
begin
  // Spalte 1 = erstes Zeichen. Tabs springen zur nächsten Tabulatorposition.
  Result := 0;
  Visual := 1;
  while (Result < Length(ALine)) and (Visual < AColumn) do
  begin
    if ALine[Result + 1] = #9 then
      Visual := ((Visual - 1) div ATabWidth + 1) * ATabWidth + 1
    else
      Inc(Visual);
    Inc(Result);
  end;
end;

procedure TLspSession.Initialize;
var
  Params, Capabilities, TextDocument, Hover: TJSONObject;
  Formats: TJSONArray;
  Response: TJSONValue;
  Refresh: ILspSignal;
  Progress: ILspProgress;
begin
  Formats := TJSONArray.Create;
  Formats.Add('plaintext');
  Hover := TJSONObject.Create;
  Hover.AddPair('contentFormat', Formats);
  TextDocument := TJSONObject.Create;
  TextDocument.AddPair('hover', Hover);
  // Dokumentation der Vervollständigung als Klartext, keine Snippets (#408).
  TextDocument.AddPair('completion', TJSONObject.Create(TJSONPair.Create('completionItem',
    TJSONObject.Create.AddPair('snippetSupport', TJSONBool.Create(False))
      .AddPair('documentationFormat', TJSONArray.Create.Add('plaintext')))));
  // Diagnosen holt das Plugin selbst (#398); der Server bittet per refresh um neues Holen.
  TextDocument.AddPair('diagnostic', TJSONObject.Create.AddPair('dynamicRegistration', TJSONBool.Create(False))
    .AddPair('relatedDocumentSupport', TJSONBool.Create(False)));
  Capabilities := TJSONObject.Create;
  Capabilities.AddPair('textDocument', TextDocument);
  Capabilities.AddPair('workspace', TJSONObject.Create(TJSONPair.Create('diagnostics',
    TJSONObject.Create(TJSONPair.Create('refreshSupport', TJSONBool.Create(True)))))
    .AddPair('workspaceFolders', TJSONBool.Create(True)));
  Params := TJSONObject.Create;
  Params.AddPair('processId', TJSONNull.Create);
  Params.AddPair('rootUri', TJSONNull.Create);
  Params.AddPair('clientInfo', TJSONObject.Create(TJSONPair.Create('name', 'Atlas IDE Expert')));
  Params.AddPair('capabilities', Capabilities);
  if Length(FProjects) > 0 then
    Params.AddPair('workspaceFolders', ProjectFolders(FProjects));
  if FServerSettings <> '' then
    Params.AddPair('initializationOptions', SettingsParams(FServerSettings));
  // Nur den Zähler einfangen, nicht die Sitzung: Der Lese-Thread kann die Sitzung überleben.
  Refresh := FRefresh;
  Progress := FProgress;
  FClient.OnServerMessage :=
    procedure(const AMethod: string; const AParams: TJSONValue)
    begin
      if AMethod = 'workspace/diagnostic/refresh' then
        Refresh.Signal
      else if AMethod = '$/progress' then
        Progress.Handle(AParams);
    end;
  // Ohne Arbeitsbereich leitet der Server ihn aus den geöffneten Dateien ab, ebenso für Dateien
  // außerhalb der gemeldeten Projekte.
  Response := FClient.Request('initialize', Params, 15000);
  Response.Free;
  FClient.Notify('initialized', TJSONObject.Create);
  FInitialized := True;
end;

procedure TLspSession.Sync(const AFileName, AText: string);
begin
  TMonitor.Enter(FDocLock);
  try
    SyncLocked(AFileName, AText);
  finally
    TMonitor.Exit(FDocLock);
  end;
end;

procedure TLspSession.SyncLocked(const AFileName, AText: string);
var
  State: TDocumentState;
  Key: string;
  Params, Document, Change: TJSONObject;
  Changes: TJSONArray;
begin
  Key := AnsiLowerCase(AFileName);
  Document := TJSONObject.Create;
  Document.AddPair('uri', PathToUri(AFileName));
  if not FDocuments.TryGetValue(Key, State) then
  begin
    State.FileName := AFileName;
    State.Version := 1;
    State.Text := AText;
    FDocuments.Add(Key, State);
    Document.AddPair('languageId', 'delphi');
    Document.AddPair('version', TJSONNumber.Create(State.Version));
    Document.AddPair('text', AText);
    FClient.Notify('textDocument/didOpen', TJSONObject.Create(TJSONPair.Create('textDocument', Document)));
    Exit;
  end;
  if State.Text = AText then
  begin
    Document.Free;
    Exit;
  end;
  Inc(State.Version);
  State.Text := AText;
  FDocuments[Key] := State;
  Document.AddPair('version', TJSONNumber.Create(State.Version));
  Change := TJSONObject.Create;
  Change.AddPair('text', AText);
  Changes := TJSONArray.Create;
  Changes.AddElement(Change);
  Params := TJSONObject.Create;
  Params.AddPair('textDocument', Document);
  Params.AddPair('contentChanges', Changes);
  FClient.Notify('textDocument/didChange', Params);
end;

function TLspSession.PositionParams(const AFileName: string; ALine, ACharacter: Integer): TJSONObject;
var
  Position: TJSONObject;
begin
  Position := TJSONObject.Create;
  Position.AddPair('line', TJSONNumber.Create(ALine));
  Position.AddPair('character', TJSONNumber.Create(ACharacter));
  Result := TJSONObject.Create;
  Result.AddPair('textDocument', TJSONObject.Create(TJSONPair.Create('uri', PathToUri(AFileName))));
  Result.AddPair('position', Position);
end;

function TLspSession.Hover(const AFileName, AText: string; ALine, ACharacter: Integer): string;
var
  Response: TJSONValue;
begin
  Sync(AFileName, AText);
  Response := FClient.Request('textDocument/hover', PositionParams(AFileName, ALine, ACharacter), FTimeoutMs);
  try
    Result := HoverText(Response);
  finally
    Response.Free;
  end;
end;

function TLspSession.HoverParts(const AFileName, AText: string; ALine, ACharacter: Integer): TLspHoverParts;
var
  Response: TJSONValue;
begin
  Sync(AFileName, AText);
  Response := FClient.Request('textDocument/hover', PositionParams(AFileName, ALine, ACharacter), FTimeoutMs);
  try
    Result := TLspHoverParts.FromHover(Response);
  finally
    Response.Free;
  end;
end;

function TLspSession.HoverData(const AFileName, AText: string; ALine, ACharacter: Integer): TAtlasHoverData;
begin
  Sync(AFileName, AText);
  Result := HoverDataAt(AFileName, ALine, ACharacter);
end;

function TLspSession.HoverDataAt(const AFileName: string; ALine, ACharacter: Integer): TAtlasHoverData;
var
  Response: TJSONValue;
begin
  Response := FClient.Request('textDocument/hover', PositionParams(AFileName, ALine, ACharacter), FTimeoutMs);
  try
    Result := TAtlasHoverData.FromHover(Response);
  finally
    Response.Free;
  end;
end;

function TLspSession.References(const AFileName: string; ALine, ACharacter: Integer): TArray<TLspLocation>;
var
  Params: TJSONObject;
  Context: TJSONObject;
  Response, Item: TJSONValue;
  Location: TLspLocation;
begin
  Result := nil;
  Params := PositionParams(AFileName, ALine, ACharacter);
  Context := TJSONObject.Create;
  Context.AddPair('includeDeclaration', TJSONBool.Create(False));
  Params.AddPair('context', Context);
  // Die Suche geht über das ganze Projekt; dafür mehr Zeit als für einen Hover.
  Response := FClient.Request('textDocument/references', Params, FTimeoutMs * 10);
  try
    if Response is TJSONArray then
      for Item in TJSONArray(Response) do
        if Item is TJSONObject then
        begin
          Location.FileName := UriToPath(TJSONObject(Item).GetValue<string>('uri', ''));
          Location.Line := TJSONObject(Item).GetValue<Integer>('range.start.line', 0);
          Location.Character := TJSONObject(Item).GetValue<Integer>('range.start.character', 0);
          if Location.FileName <> '' then
            Result := Result + [Location];
        end;
  finally
    Response.Free;
  end;
end;

function TLspSession.DocumentDiagnostics(const AFileName, APreviousResultId: string;
  ATimeoutMs: Cardinal): TLspDiagnosticReport;
var
  Params: TJSONObject;
  Response: TJSONValue;
begin
  Params := TJSONObject.Create;
  Params.AddPair('textDocument', TJSONObject.Create(TJSONPair.Create('uri', PathToUri(AFileName))));
  if APreviousResultId <> '' then
    Params.AddPair('previousResultId', APreviousResultId);
  Response := FClient.Request('textDocument/diagnostic', Params, ATimeoutMs);
  try
    if Response is TJSONObject then
      Result := TLspDiagnosticReport.FromJson(TJSONObject(Response), AFileName)
    else
    begin
      Result := Default(TLspDiagnosticReport);
      Result.FileName := AFileName;
    end;
  finally
    Response.Free;
  end;
end;

function TLspSession.WorkspaceDiagnostics(const APrevious: TArray<TLspDiagnosticReport>;
  ATimeoutMs: Cardinal): TArray<TLspDiagnosticReport>;
var
  Params: TJSONObject;
  Previous: TJSONArray;
  Known: TLspDiagnosticReport;
  Response, Items, Item: TJSONValue;
  Report: TLspDiagnosticReport;
begin
  Result := nil;
  Previous := TJSONArray.Create;
  for Known in APrevious do
    if Known.ResultId <> '' then
      Previous.AddElement(TJSONObject.Create.AddPair('uri', PathToUri(Known.FileName))
        .AddPair('value', Known.ResultId));
  Params := TJSONObject.Create;
  Params.AddPair('previousResultIds', Previous);
  Response := FClient.Request('workspace/diagnostic', Params, ATimeoutMs);
  try
    if not (Response is TJSONObject) then
      Exit;
    Items := TJSONObject(Response).GetValue('items');
    if Items is TJSONArray then
      for Item in TJSONArray(Items) do
        if Item is TJSONObject then
        begin
          Report := TLspDiagnosticReport.FromJson(TJSONObject(Item), '');
          if Report.FileName <> '' then
            Result := Result + [Report];
        end;
  finally
    Response.Free;
  end;
end;

procedure TLspSession.Close(const AFileName: string);
begin
  TMonitor.Enter(FDocLock);
  try
    CloseLocked(AFileName);
  finally
    TMonitor.Exit(FDocLock);
  end;
end;

procedure TLspSession.CloseLocked(const AFileName: string);
var
  Key: string;
begin
  Key := AnsiLowerCase(AFileName);
  if not FDocuments.ContainsKey(Key) then
    Exit;
  FDocuments.Remove(Key);
  FClient.Notify('textDocument/didClose', TJSONObject.Create(TJSONPair.Create('textDocument',
    TJSONObject.Create(TJSONPair.Create('uri', PathToUri(AFileName))))));
end;

procedure TLspSession.Saved(const AFileName: string);
var
  Known: Boolean;
begin
  TMonitor.Enter(FDocLock);
  try
    Known := FDocuments.ContainsKey(AnsiLowerCase(AFileName));
  finally
    TMonitor.Exit(FDocLock);
  end;
  if not Known then
    Exit;
  FClient.Notify('textDocument/didSave', TJSONObject.Create(TJSONPair.Create('textDocument',
    TJSONObject.Create(TJSONPair.Create('uri', PathToUri(AFileName))))));
end;

function TLspSession.SyncedFiles: TArray<string>;
var
  State: TDocumentState;
begin
  Result := nil;
  TMonitor.Enter(FDocLock);
  try
    for State in FDocuments.Values do
      Result := Result + [State.FileName];
  finally
    TMonitor.Exit(FDocLock);
  end;
end;

function TLspSession.SyncedText(const AFileName: string; out AText: string): Boolean;
var
  State: TDocumentState;
begin
  TMonitor.Enter(FDocLock);
  try
    Result := FDocuments.TryGetValue(AnsiLowerCase(AFileName), State);
  finally
    TMonitor.Exit(FDocLock);
  end;
  if Result then
    AText := State.Text
  else
    AText := '';
end;

function TLspSession.ProgressText: string;
begin
  Result := FProgress.Text;
end;

function TLspSession.IndexingText: string;
begin
  Result := FProgress.IndexingText;
end;

function TLspSession.ExecuteCommand(const ACommand: string; ATimeoutMs: Cardinal): TJSONValue;
begin
  Result := ExecuteCommand(ACommand, TJSONArray.Create, ATimeoutMs);
end;

function TLspSession.ExecuteCommand(const ACommand: string; AArguments: TJSONArray; ATimeoutMs: Cardinal): TJSONValue;
begin
  try
    Result := FClient.Request('workspace/executeCommand',
      TJSONObject.Create.AddPair('command', ACommand).AddPair('arguments', AArguments), ATimeoutMs);
  except
    Result := nil;
  end;
end;

function TLspSession.RefreshCount: Integer;
begin
  Result := FRefresh.Count;
end;

{ TLspDiagnosticReport }

class function TLspDiagnosticReport.FromJson(const AReport: TJSONObject; const AFileName: string): TLspDiagnosticReport;
var
  Items: TJSONValue;
  Uri: string;
begin
  Result := Default(TLspDiagnosticReport);
  Uri := AReport.GetValue<string>('uri', '');
  if Uri <> '' then
    Result.FileName := TLspSession.UriToPath(Uri)
  else
    Result.FileName := AFileName;
  Result.ResultId := AReport.GetValue<string>('resultId', '');
  Result.Unchanged := AReport.GetValue<string>('kind', 'full') = 'unchanged';
  Items := AReport.GetValue('items');
  if Items is TJSONArray then
    Result.Problems := TAtlasProblem.ListFromJson(TJSONArray(Items));
end;

{ TLspHoverParts }

function TLspHoverParts.Found: Boolean;
begin
  Result := Declaration <> '';
end;

class function TLspHoverParts.FromHover(const AHover: TJSONValue): TLspHoverParts;
var
  Parts: TJSONValue;
  Text: string;
  Paragraphs: TArray<string>;
begin
  Result := Default(TLspHoverParts);
  if not (AHover is TJSONObject) then
    Exit;
  Parts := TJSONObject(AHover).GetValue('atlas');
  if Parts is TJSONObject then
  begin
    Result.Declaration := TJSONObject(Parts).GetValue<string>('declaration', '');
    Result.UnitName := TJSONObject(Parts).GetValue<string>('unit', '');
    // Seit #654 ist "documentation" strukturiert; der Klartext steht in "documentationText".
    if not TJSONObject(Parts).TryGetValue<string>('documentationText', Result.Documentation) and
      (TJSONObject(Parts).GetValue('documentation') is TJSONString) then
      Result.Documentation := TJSONObject(Parts).GetValue('documentation').Value;
    Result.Value := TJSONObject(Parts).GetValue<string>('value', '');
    Result.Deprecation := TJSONObject(Parts).GetValue<string>('deprecation', '');
    Exit;
  end;
  // Ältere Server: Klartext, erster Absatz ist die Deklaration, der Rest Doku.
  Text := TLspSession.HoverText(AHover).Replace(#13#10, #10).Trim;
  if Text = '' then
    Exit;
  Paragraphs := Text.Split([#10#10], 2);
  Result.Declaration := Paragraphs[0];
  if Length(Paragraphs) > 1 then
    Result.Documentation := Paragraphs[1];
end;

function TLspSession.Definition(const AFileName, AText: string; ALine, ACharacter: Integer;
  out ALocation: TLspLocation): Boolean;
var
  Response, Item: TJSONValue;
  Location: TJSONObject;
  Uri: string;
  Range: TJSONObject;
begin
  ALocation := Default(TLspLocation);
  Sync(AFileName, AText);
  Response := FClient.Request('textDocument/definition', PositionParams(AFileName, ALine, ACharacter), FTimeoutMs);
  try
    // Location, Location[] oder LocationLink[].
    Item := Response;
    if (Item is TJSONArray) and (TJSONArray(Item).Count > 0) then
      Item := TJSONArray(Item).Items[0];
    if not (Item is TJSONObject) then
      Exit(False);
    Location := TJSONObject(Item);
    if not Location.TryGetValue<string>('uri', Uri) then
      Uri := Location.GetValue<string>('targetUri', '');
    Range := Location.GetValue('range') as TJSONObject;
    if Range = nil then
      Range := Location.GetValue('targetSelectionRange') as TJSONObject;
    if (Uri = '') or (Range = nil) then
      Exit(False);
    ALocation.FileName := UriToPath(Uri);
    ALocation.Line := Range.GetValue<Integer>('start.line', 0);
    ALocation.Character := Range.GetValue<Integer>('start.character', 0);
    Result := ALocation.FileName <> '';
  finally
    Response.Free;
  end;
end;

function TLspSession.Completion(const AFileName: string; ALine, ACharacter: Integer;
  ATimeoutMs: Cardinal): TJSONValue;
begin
  Result := FClient.Request('textDocument/completion', PositionParams(AFileName, ALine, ACharacter), ATimeoutMs);
end;

function TLspSession.Completion(const AFileName: string; ALine, ACharacter: Integer; ATimeoutMs: Cardinal;
  const AOnPartial: TLspPartialProc): TJSONValue;
begin
  Result := FClient.Request('textDocument/completion', PositionParams(AFileName, ALine, ACharacter), ATimeoutMs,
    AOnPartial);
end;

function TLspSession.SignatureHelp(const AFileName: string; ALine, ACharacter: Integer;
  ATimeoutMs: Cardinal): TJSONValue;
begin
  Result := FClient.Request('textDocument/signatureHelp', PositionParams(AFileName, ALine, ACharacter), ATimeoutMs);
end;

function TLspSession.ResolveCompletion(AItem: TJSONObject; ATimeoutMs: Cardinal): TJSONValue;
begin
  Result := FClient.Request('completionItem/resolve', AItem, ATimeoutMs);
end;

class function TLspSession.SettingsParams(const AJson: string): TJSONObject;
var
  Value: TJSONValue;
begin
  Value := TJSONObject.ParseJSONValue(AJson);
  if not (Value is TJSONObject) then
  begin
    Value.Free;
    Value := TJSONObject.Create;
  end;
  Result := TJSONObject.Create(TJSONPair.Create('settings', TJSONObject.Create(TJSONPair.Create('atlas', Value))));
end;

procedure TLspSession.Notify(const AMethod: string; AParams: TJSONObject);
begin
  FClient.Notify(AMethod, AParams);
end;

class function TLspSession.ProjectFolders(const AProjects: TArray<string>): TJSONArray;
var
  Project: string;
begin
  Result := TJSONArray.Create;
  for Project in AProjects do
    Result.AddElement(TJSONObject.Create.AddPair('uri', PathToUri(Project))
      .AddPair('name', ChangeFileExt(ExtractFileName(Project), '')));
end;

function ContainsText_(const AValues: TArray<string>; const AValue: string): Boolean;
var
  Value: string;
begin
  for Value in AValues do
    if SameText(Value, AValue) then
      Exit(True);
  Result := False;
end;

class procedure TLspSession.ProjectChanges(const AOld, ANew: TArray<string>; out AAdded, ARemoved: TArray<string>);
var
  Project: string;
begin
  AAdded := nil;
  ARemoved := nil;
  for Project in ANew do
    if not ContainsText_(AOld, Project) and not ContainsText_(AAdded, Project) then
      AAdded := AAdded + [Project];
  for Project in AOld do
    if not ContainsText_(ANew, Project) and not ContainsText_(ARemoved, Project) then
      ARemoved := ARemoved + [Project];
end;

procedure TLspSession.SetProjects(const AProjects: TArray<string>);
var
  Added, Removed: TArray<string>;
begin
  if not FInitialized then
  begin
    FProjects := AProjects;
    Exit;
  end;
  ProjectChanges(FProjects, AProjects, Added, Removed);
  FProjects := AProjects;
  if (Length(Added) = 0) and (Length(Removed) = 0) then
    Exit;
  FClient.Notify('workspace/didChangeWorkspaceFolders', TJSONObject.Create(TJSONPair.Create('event',
    TJSONObject.Create.AddPair('added', ProjectFolders(Added)).AddPair('removed', ProjectFolders(Removed)))));
end;

end.
