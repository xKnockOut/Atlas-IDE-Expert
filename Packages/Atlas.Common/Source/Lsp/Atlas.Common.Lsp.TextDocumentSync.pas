unit Atlas.Common.Lsp.TextDocumentSync;

// Dokumentsynchronisation des LSP: didOpen, didChange (inkrementell und
// vollständig), didSave und didClose landen im Dokumentspeicher.
// Die Benachrichtigungen laufen in der Nachrichtenschleife nacheinander, die
// Reihenfolge der Änderungen bleibt also erhalten.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract;

type
  TLspTextDocumentSync = class
  private
    FStore: IDocumentStore;
    procedure HandleDidOpen(const AParams: TJSONValue);
    procedure HandleDidChange(const AParams: TJSONValue);
    procedure HandleDidSave(const AParams: TJSONValue);
    procedure HandleDidClose(const AParams: TJSONValue);
  public
    constructor Create(const AStore: IDocumentStore);
    /// <summary>Registriert die Benachrichtigungen am Dispatcher.</summary>
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Wert der Capability textDocumentSync. Der Aufrufer übernimmt das Objekt.</summary>
    class function Capability: TJSONObject; static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Lsp.Positions;

function RequireObject(const AValue: TJSONValue; const AContext: string): TJSONObject;
begin
  if not (AValue is TJSONObject) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Parameter fehlen in ' + AContext);
  Result := TJSONObject(AValue);
end;

function RequireString(const AObject: TJSONObject; const APath, AContext: string): string;
begin
  if not AObject.TryGetValue<string>(APath, Result) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Feld "' + APath + '" fehlt in ' + AContext);
end;

function RequireInteger(const AObject: TJSONObject; const APath, AContext: string): Integer;
begin
  if not AObject.TryGetValue<Integer>(APath, Result) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Feld "' + APath + '" fehlt oder ist keine Zahl in ' + AContext);
end;

function ReadChanges(const AParams: TJSONObject): TArray<TTextChange>;
var
  Changes: TJSONArray;
  Item: TJSONValue;
  Entry: TJSONObject;
  Range: TJSONValue;
  Text: string;
begin
  if not AParams.TryGetValue<TJSONArray>('contentChanges', Changes) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Feld "contentChanges" fehlt in ' + TLspTextDocumentMethod.DidChange);
  Result := nil;
  for Item in Changes do
  begin
    Entry := RequireObject(Item, TLspTextDocumentMethod.DidChange);
    Text := RequireString(Entry, 'text', TLspTextDocumentMethod.DidChange);
    Range := Entry.GetValue('range');
    if Range = nil then
      Result := Result + [TTextChange.Full(Text)]
    else
      Result := Result + [TTextChange.Ranged(TLspPositions.ReadRange(Range), Text)];
  end;
end;

{ TLspTextDocumentSync }

constructor TLspTextDocumentSync.Create(const AStore: IDocumentStore);
begin
  inherited Create;
  FStore := AStore;
end;

procedure TLspTextDocumentSync.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterNotification(TLspTextDocumentMethod.DidOpen, HandleDidOpen);
  ADispatcher.RegisterNotification(TLspTextDocumentMethod.DidChange, HandleDidChange);
  ADispatcher.RegisterNotification(TLspTextDocumentMethod.DidSave, HandleDidSave);
  ADispatcher.RegisterNotification(TLspTextDocumentMethod.DidClose, HandleDidClose);
end;

class function TLspTextDocumentSync.Capability: TJSONObject;
var
  Save: TJSONObject;
begin
  Save := TJSONObject.Create;
  Save.AddPair('includeText', TJSONBool.Create(False));
  Result := TJSONObject.Create;
  Result.AddPair('openClose', TJSONBool.Create(True));
  Result.AddPair('change', TJSONNumber.Create(TLspTextDocumentSyncKind.Incremental));
  Result.AddPair('save', Save);
end;

procedure TLspTextDocumentSync.HandleDidOpen(const AParams: TJSONValue);
var
  Params: TJSONObject;
begin
  Params := RequireObject(AParams, TLspTextDocumentMethod.DidOpen);
  FStore.Open(
    RequireString(Params, 'textDocument.uri', TLspTextDocumentMethod.DidOpen),
    RequireString(Params, 'textDocument.languageId', TLspTextDocumentMethod.DidOpen),
    RequireInteger(Params, 'textDocument.version', TLspTextDocumentMethod.DidOpen),
    RequireString(Params, 'textDocument.text', TLspTextDocumentMethod.DidOpen));
end;

procedure TLspTextDocumentSync.HandleDidChange(const AParams: TJSONValue);
var
  Params: TJSONObject;
begin
  Params := RequireObject(AParams, TLspTextDocumentMethod.DidChange);
  FStore.Change(
    RequireString(Params, 'textDocument.uri', TLspTextDocumentMethod.DidChange),
    RequireInteger(Params, 'textDocument.version', TLspTextDocumentMethod.DidChange),
    ReadChanges(Params));
end;

procedure TLspTextDocumentSync.HandleDidSave(const AParams: TJSONValue);
var
  Params: TJSONObject;
begin
  Params := RequireObject(AParams, TLspTextDocumentMethod.DidSave);
  FStore.Save(RequireString(Params, 'textDocument.uri', TLspTextDocumentMethod.DidSave));
end;

procedure TLspTextDocumentSync.HandleDidClose(const AParams: TJSONValue);
var
  Params: TJSONObject;
begin
  Params := RequireObject(AParams, TLspTextDocumentMethod.DidClose);
  FStore.Close(RequireString(Params, 'textDocument.uri', TLspTextDocumentMethod.DidClose));
end;

end.
