unit Atlas.Common.Lsp.ProtocolReplay;

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
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Lsp.Lifecycle,
  Atlas.Common.Lsp.TextDocumentSync,
  Atlas.Common.Lsp.SyntaxDiagnostics,
  Atlas.Common.Lsp.DocumentSymbols,
  Atlas.Common.Lsp.FoldingRanges,
  Atlas.Common.Lsp.SelectionRanges;

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
  Atlas.Common.Documents.Providers.DocumentStore;

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
  FLifecycle := TLspLifecycle.Create('Atlas', 'Test',
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
  FSyntaxDiagnostics := TLspSyntaxDiagnostics.Create(FDocuments, FTransport, Default(TSyntaxDiagnosticsProviders), 0);
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
  mDirectory: string;
  mCandidate: string;
begin
  mDirectory := ExtractFileDir(ParamStr(0));
  while mDirectory <> '' do
  begin
    mCandidate := TPath.Combine(mDirectory, TPath.Combine('Tests', TPath.Combine('Data', 'Protocol')));
    if TDirectory.Exists(mCandidate) then
    begin
      Exit(mCandidate);
    end;
    if ExtractFileDir(mDirectory) = mDirectory then
    begin
      Break;
    end;
    mDirectory := ExtractFileDir(mDirectory);
  end;
  raise EProtocolMismatch.Create('Ordner Tests\Data\Protocol nicht gefunden');
end;

/// <summary>Erste Abweichung zwischen den Objekten AExpected und AActual (AActual darf mehr Felder haben).
/// </summary>
function ObjectMismatch(AExpected: TJSONObject; AActual: TJSONValue; const APath: string): string;
var
  mPair: TJSONPair;
  mActualValue: TJSONValue;
begin
  Result := '';
  if not (AActual is TJSONObject) then
  begin
    Exit(Format('%s: Objekt erwartet, %s gefunden', [APath, AActual.ToJSON]));
  end;
  for mPair in AExpected do
  begin
    mActualValue := TJSONObject(AActual).GetValue(mPair.JsonString.Value);
    if mActualValue = nil then
    begin
      Exit(Format('%s.%s fehlt', [APath, mPair.JsonString.Value]));
    end;
    Result := TProtocolReplay.Mismatch(mPair.JsonValue, mActualValue, APath + '.' + mPair.JsonString.Value);
    if Result <> '' then
    begin
      Exit;
    end;
  end;
end;

/// <summary>Erste Abweichung zwischen den Arrays AExpected und AActual.</summary>
function ArrayMismatch(AExpected: TJSONArray; AActual: TJSONValue; const APath: string): string;
var
  mIndex: Integer;
begin
  Result := '';
  if not (AActual is TJSONArray) then
  begin
    Exit(Format('%s: Array erwartet, %s gefunden', [APath, AActual.ToJSON]));
  end;
  if AExpected.Count <> TJSONArray(AActual).Count then
  begin
    Exit(Format('%s: %d Elemente erwartet, %d gefunden: %s',
      [APath, AExpected.Count, TJSONArray(AActual).Count, AActual.ToJSON]));
  end;
  for mIndex := 0 to AExpected.Count - 1 do
  begin
    Result := TProtocolReplay.Mismatch(AExpected.Items[mIndex], TJSONArray(AActual).Items[mIndex],
      Format('%s[%d]', [APath, mIndex]));
    if Result <> '' then
    begin
      Exit;
    end;
  end;
end;

class function TProtocolReplay.Mismatch(const AExpected, AActual: TJSONValue; const APath: string): string;
begin
  Result := '';
  if AExpected is TJSONObject then
  begin
    Result := ObjectMismatch(TJSONObject(AExpected), AActual, APath);
  end
  else if AExpected is TJSONArray then
  begin
    Result := ArrayMismatch(TJSONArray(AExpected), AActual, APath);
  end
  else if AExpected.ToJSON <> AActual.ToJSON then
  begin
    Result := Format('%s: %s erwartet, %s gefunden', [APath, AExpected.ToJSON, AActual.ToJSON]);
  end;
end;

procedure TProtocolReplay.Send(const AMessage: TJSONObject);
var
  mResponse: TJSONObject;
begin
  mResponse := FDispatcher.DispatchMessage(AMessage);
  if mResponse <> nil then
  begin
    FOutput.Enqueue(mResponse);
  end;
end;

procedure TProtocolReplay.Expect(const AExpected: TJSONObject; AStep: Integer);
var
  mActual: TJSONObject;
  mDifference: string;
begin
  if FOutput.Count = 0 then
  begin
    raise EProtocolMismatch.CreateFmt('Schritt %d: keine Nachricht vom Server, erwartet %s',
      [AStep, AExpected.ToJSON]);
  end;
  mActual := FOutput.Extract;
  try
    mDifference := Mismatch(AExpected, mActual, '$');
    if mDifference <> '' then
    begin
      raise EProtocolMismatch.CreateFmt('Schritt %d: %s', [AStep, mDifference]);
    end;
  finally
    mActual.Free;
  end;
end;

procedure TProtocolReplay.Run(const ARecording: TJSONObject);
var
  mSteps: TJSONArray;
  mStep: TJSONObject;
  mIndex: Integer;
  mValue: TJSONObject;
begin
  if not ARecording.TryGetValue<TJSONArray>('steps', mSteps) then
  begin
    raise EProtocolMismatch.Create('Feld "steps" fehlt');
  end;
  for mIndex := 0 to mSteps.Count - 1 do
  begin
    mStep := mSteps.Items[mIndex] as TJSONObject;
    if mStep.TryGetValue<TJSONObject>('send', mValue) then
    begin
      Send(mValue);
    end
    else if mStep.TryGetValue<TJSONObject>('expect', mValue) then
    begin
      Expect(mValue, mIndex);
    end
    else
    begin
      raise EProtocolMismatch.CreateFmt('Schritt %d: "send" oder "expect" fehlt', [mIndex]);
    end;
  end;
  if FOutput.Count > 0 then
  begin
    raise EProtocolMismatch.CreateFmt('Unerwartete Nachricht vom Server: %s', [FOutput.Peek.ToJSON]);
  end;
end;

end.
