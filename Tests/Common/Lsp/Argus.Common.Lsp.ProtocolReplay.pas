unit Argus.Common.Lsp.ProtocolReplay;

// Spielt aufgezeichnete Nachrichtenfolgen gegen den Server ab und vergleicht
// die Antworten mit Sollwerten. Eine Aufzeichnung ist eine JSON-Datei:
//
//   { "description": "...",
//     "steps": [ { "send": { Nachricht } },
//                { "expect": { Sollwerte } }, ... ] }
//
// "send" verarbeitet eine Nachricht; Antworten und Benachrichtigungen des
// Servers landen in einer Warteschlange. "expect" nimmt die nächste Nachricht
// aus der Warteschlange und vergleicht sie: Jedes Feld der Sollwerte muss
// vorhanden und gleich sein, weitere Felder sind erlaubt; Arrays müssen gleich
// lang sein. Am Ende darf keine Nachricht übrig sein.
//
// Der Server ist wie in Shell.Composition zusammengesetzt, aber ohne Threads:
// Syntaxdiagnosen kommen ohne Verzögerung, die Reihenfolge ist also fest.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Argus.Common.JsonRpc.Contract,
  Argus.Common.JsonRpc.Dispatcher,
  Argus.Common.Documents.Contract,
  Argus.Common.Lsp.Lifecycle,
  Argus.Common.Lsp.TextDocumentSync,
  Argus.Common.Lsp.SyntaxDiagnostics,
  Argus.Common.Lsp.DocumentSymbols,
  Argus.Common.Lsp.FoldingRanges,
  Argus.Common.Lsp.SelectionRanges;

type
  /// <summary>Transport, der geschriebene Nachrichten in eine Warteschlange stellt.</summary>
  TQueueTransport = class(TInterfacedObject, IJsonRpcTransport)
  private
    FQueue: TObjectQueue<TJSONObject>;
  public
    constructor Create(AQueue: TObjectQueue<TJSONObject>);
    function ReadMessage: TJSONObject;
    procedure WriteMessage(const AMessage: TJSONObject);
  end;

  TProtocolReplay = class
  private
    FOutput: TObjectQueue<TJSONObject>;
    FTransport: IJsonRpcTransport;
    FDispatcher: TJsonRpcDispatcher;
    FLifecycle: TLspLifecycle;
    FDocuments: IDocumentStore;
    FTextDocumentSync: TLspTextDocumentSync;
    FSyntaxDiagnostics: TLspSyntaxDiagnostics;
    FDocumentSymbols: TLspDocumentSymbols;
    FFoldingRanges: TLspFoldingRanges;
    FSelectionRanges: TLspSelectionRanges;
    procedure Send(const AMessage: TJSONObject);
    procedure Expect(const AExpected: TJSONObject; AStep: Integer);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Spielt eine Aufzeichnung ab; Abweichungen lösen EProtocolMismatch aus.</summary>
    procedure Run(const ARecording: TJSONObject);
    /// <summary>Ordner Tests\Data\Protocol, gesucht ab dem Ordner der Test-EXE aufwärts.</summary>
    class function DataDirectory: string; static;
    /// <summary>
    /// Vergleicht AActual mit den Sollwerten AExpected (siehe Kopfkommentar).
    /// Liefert '' bei Gleichheit, sonst eine Beschreibung der ersten Abweichung.
    /// </summary>
    class function Mismatch(const AExpected, AActual: TJSONValue; const APath: string): string; static;
  end;

  EProtocolMismatch = class(Exception);

implementation

uses
  System.IOUtils,
  Argus.Common.Documents.Providers.DocumentStore;

{ TQueueTransport }

constructor TQueueTransport.Create(AQueue: TObjectQueue<TJSONObject>);
begin
  inherited Create;
  FQueue := AQueue;
end;

function TQueueTransport.ReadMessage: TJSONObject;
begin
  raise EJsonRpcTransportClosed.Create('Keine Eingabe');
end;

procedure TQueueTransport.WriteMessage(const AMessage: TJSONObject);
begin
  FQueue.Enqueue(TJSONObject(AMessage.Clone));
end;

{ TProtocolReplay }

constructor TProtocolReplay.Create;
begin
  inherited Create;
  FOutput := TObjectQueue<TJSONObject>.Create(True);
  FTransport := TQueueTransport.Create(FOutput);
  FDispatcher := TJsonRpcDispatcher.Create;
  FLifecycle := TLspLifecycle.Create('Argus', 'Test',
    function: TJSONObject
    begin
      Result := TJSONObject.Create;
      Result.AddPair('textDocumentSync', TLspTextDocumentSync.Capability);
      Result.AddPair('documentSymbolProvider', TJSONBool.Create(True));
      Result.AddPair('foldingRangeProvider', TJSONBool.Create(True));
      Result.AddPair('selectionRangeProvider', TJSONBool.Create(True));
    end);
  FLifecycle.Attach(FDispatcher);
  FDocuments := TDocumentStore.Create;
  FTextDocumentSync := TLspTextDocumentSync.Create(FDocuments);
  FTextDocumentSync.Attach(FDispatcher);
  FSyntaxDiagnostics := TLspSyntaxDiagnostics.Create(FDocuments, FTransport, 0);
  FSyntaxDiagnostics.Attach;
  FDocumentSymbols := TLspDocumentSymbols.Create(FDocuments);
  FDocumentSymbols.Attach(FDispatcher);
  FFoldingRanges := TLspFoldingRanges.Create(FDocuments);
  FFoldingRanges.Attach(FDispatcher);
  FSelectionRanges := TLspSelectionRanges.Create(FDocuments);
  FSelectionRanges.Attach(FDispatcher);
end;

destructor TProtocolReplay.Destroy;
begin
  FSelectionRanges.Free;
  FFoldingRanges.Free;
  FDocumentSymbols.Free;
  FSyntaxDiagnostics.Free;
  FTextDocumentSync.Free;
  FDocuments := nil;
  FLifecycle.Free;
  FDispatcher.Free;
  FTransport := nil;
  FOutput.Free;
  inherited;
end;

class function TProtocolReplay.DataDirectory: string;
var
  Directory: string;
  Candidate: string;
begin
  Directory := ExtractFileDir(ParamStr(0));
  while Directory <> '' do
  begin
    Candidate := TPath.Combine(Directory, TPath.Combine('Tests', TPath.Combine('Data', 'Protocol')));
    if TDirectory.Exists(Candidate) then
      Exit(Candidate);
    if ExtractFileDir(Directory) = Directory then
      Break;
    Directory := ExtractFileDir(Directory);
  end;
  raise EProtocolMismatch.Create('Ordner Tests\Data\Protocol nicht gefunden');
end;

class function TProtocolReplay.Mismatch(const AExpected, AActual: TJSONValue; const APath: string): string;
var
  Pair: TJSONPair;
  ActualValue: TJSONValue;
  Index: Integer;
begin
  Result := '';
  if AExpected is TJSONObject then
  begin
    if not (AActual is TJSONObject) then
      Exit(Format('%s: Objekt erwartet, %s gefunden', [APath, AActual.ToJSON]));
    for Pair in TJSONObject(AExpected) do
    begin
      ActualValue := TJSONObject(AActual).GetValue(Pair.JsonString.Value);
      if ActualValue = nil then
        Exit(Format('%s.%s fehlt', [APath, Pair.JsonString.Value]));
      Result := Mismatch(Pair.JsonValue, ActualValue, APath + '.' + Pair.JsonString.Value);
      if Result <> '' then
        Exit;
    end;
  end
  else if AExpected is TJSONArray then
  begin
    if not (AActual is TJSONArray) then
      Exit(Format('%s: Array erwartet, %s gefunden', [APath, AActual.ToJSON]));
    if TJSONArray(AExpected).Count <> TJSONArray(AActual).Count then
      Exit(Format('%s: %d Elemente erwartet, %d gefunden: %s',
        [APath, TJSONArray(AExpected).Count, TJSONArray(AActual).Count, AActual.ToJSON]));
    for Index := 0 to TJSONArray(AExpected).Count - 1 do
    begin
      Result := Mismatch(TJSONArray(AExpected).Items[Index], TJSONArray(AActual).Items[Index],
        Format('%s[%d]', [APath, Index]));
      if Result <> '' then
        Exit;
    end;
  end
  else if AExpected.ToJSON <> AActual.ToJSON then
    Result := Format('%s: %s erwartet, %s gefunden', [APath, AExpected.ToJSON, AActual.ToJSON]);
end;

procedure TProtocolReplay.Send(const AMessage: TJSONObject);
var
  Response: TJSONObject;
begin
  Response := FDispatcher.DispatchMessage(AMessage);
  if Response <> nil then
    FOutput.Enqueue(Response);
end;

procedure TProtocolReplay.Expect(const AExpected: TJSONObject; AStep: Integer);
var
  Actual: TJSONObject;
  Difference: string;
begin
  if FOutput.Count = 0 then
    raise EProtocolMismatch.CreateFmt('Schritt %d: keine Nachricht vom Server, erwartet %s',
      [AStep, AExpected.ToJSON]);
  Actual := FOutput.Extract;
  try
    Difference := Mismatch(AExpected, Actual, '$');
    if Difference <> '' then
      raise EProtocolMismatch.CreateFmt('Schritt %d: %s', [AStep, Difference]);
  finally
    Actual.Free;
  end;
end;

procedure TProtocolReplay.Run(const ARecording: TJSONObject);
var
  Steps: TJSONArray;
  Step: TJSONObject;
  Index: Integer;
  Value: TJSONObject;
begin
  if not ARecording.TryGetValue<TJSONArray>('steps', Steps) then
    raise EProtocolMismatch.Create('Feld "steps" fehlt');
  for Index := 0 to Steps.Count - 1 do
  begin
    Step := Steps.Items[Index] as TJSONObject;
    if Step.TryGetValue<TJSONObject>('send', Value) then
      Send(Value)
    else if Step.TryGetValue<TJSONObject>('expect', Value) then
      Expect(Value, Index)
    else
      raise EProtocolMismatch.CreateFmt('Schritt %d: "send" oder "expect" fehlt', [Index]);
  end;
  if FOutput.Count > 0 then
    raise EProtocolMismatch.CreateFmt('Unerwartete Nachricht vom Server: %s', [FOutput.Peek.ToJSON]);
end;

end.
