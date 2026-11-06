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
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TTextDocumentSyncText = (FieldMissingIn, FieldMissingOrNotA, FieldContentChangesMissingIn, ParametersMissingIn);

const
  cTexts: array[TTextDocumentSyncText] of TAtlasText = (
    (De: 'Feld "%s" fehlt in '; En: 'Field "%s" missing in '),
    (De: 'Feld "%s" fehlt oder ist keine Zahl in '; En: 'Field "%s" missing or not a number in '),
    (De: 'Feld "contentChanges" fehlt in '; En: 'Field "contentChanges" missing in '),
    (De: 'Parameter fehlen in '; En: 'Parameters missing in '));

{$SCOPEDENUMS OFF}

function RequireObject(const AValue: TJSONValue; const AContext: string): TJSONObject;
begin
  if not (AValue is TJSONObject) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TTextDocumentSyncText.ParametersMissingIn].Text + AContext);
  end;
  Result := TJSONObject(AValue);
end;

function RequireString(const AObject: TJSONObject; const APath, AContext: string): string;
begin
  if not AObject.TryGetValue<string>(APath, Result) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TTextDocumentSyncText.FieldMissingIn].Fmt([APath]) + AContext);
  end;
end;

function RequireInteger(const AObject: TJSONObject; const APath, AContext: string): Integer;
begin
  if not AObject.TryGetValue<Integer>(APath, Result) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TTextDocumentSyncText.FieldMissingOrNotA].Fmt([APath]) + AContext);
  end;
end;

function ReadChanges(const AParams: TJSONObject): TArray<TTextChange>;
var
  mChanges: TJSONArray;
  mItem: TJSONValue;
  mEntry: TJSONObject;
  mRange: TJSONValue;
  mText: string;
begin
  if not AParams.TryGetValue<TJSONArray>('contentChanges', mChanges) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TTextDocumentSyncText.FieldContentChangesMissingIn].Text + TLspTextDocumentMethod.cDidChange);
  end;
  Result := nil;
  for mItem in mChanges do
  begin
    mEntry := RequireObject(mItem, TLspTextDocumentMethod.cDidChange);
    mText := RequireString(mEntry, 'text', TLspTextDocumentMethod.cDidChange);
    mRange := mEntry.GetValue('range');
    if mRange = nil then
    begin
      Result := Result + [TTextChange.Full(mText)];
    end
    else
    begin
      Result := Result + [TTextChange.Ranged(TLspPositions.ReadRange(mRange), mText)];
    end;
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
  ADispatcher.RegisterNotification(TLspTextDocumentMethod.cDidOpen, HandleDidOpen);
  ADispatcher.RegisterNotification(TLspTextDocumentMethod.cDidChange, HandleDidChange);
  ADispatcher.RegisterNotification(TLspTextDocumentMethod.cDidSave, HandleDidSave);
  ADispatcher.RegisterNotification(TLspTextDocumentMethod.cDidClose, HandleDidClose);
end;

class function TLspTextDocumentSync.Capability: TJSONObject;
var
  mSave: TJSONObject;
begin
  mSave := TJSONObject.Create;
  mSave.AddPair('includeText', TJSONBool.Create(False));
  Result := TJSONObject.Create;
  Result.AddPair('openClose', TJSONBool.Create(True));
  Result.AddPair('change', TJSONNumber.Create(TLspTextDocumentSyncKind.cIncremental));
  Result.AddPair('save', mSave);
end;

procedure TLspTextDocumentSync.HandleDidOpen(const AParams: TJSONValue);
var
  mParams: TJSONObject;
begin
  mParams := RequireObject(AParams, TLspTextDocumentMethod.cDidOpen);
  FStore.Open(
    RequireString(mParams, 'textDocument.uri', TLspTextDocumentMethod.cDidOpen),
    RequireString(mParams, 'textDocument.languageId', TLspTextDocumentMethod.cDidOpen),
    RequireInteger(mParams, 'textDocument.version', TLspTextDocumentMethod.cDidOpen),
    RequireString(mParams, 'textDocument.text', TLspTextDocumentMethod.cDidOpen));
end;

procedure TLspTextDocumentSync.HandleDidChange(const AParams: TJSONValue);
var
  mParams: TJSONObject;
begin
  mParams := RequireObject(AParams, TLspTextDocumentMethod.cDidChange);
  FStore.Change(
    RequireString(mParams, 'textDocument.uri', TLspTextDocumentMethod.cDidChange),
    RequireInteger(mParams, 'textDocument.version', TLspTextDocumentMethod.cDidChange),
    ReadChanges(mParams));
end;

procedure TLspTextDocumentSync.HandleDidSave(const AParams: TJSONValue);
var
  mParams: TJSONObject;
begin
  mParams := RequireObject(AParams, TLspTextDocumentMethod.cDidSave);
  FStore.Save(RequireString(mParams, 'textDocument.uri', TLspTextDocumentMethod.cDidSave));
end;

procedure TLspTextDocumentSync.HandleDidClose(const AParams: TJSONValue);
var
  mParams: TJSONObject;
begin
  mParams := RequireObject(AParams, TLspTextDocumentMethod.cDidClose);
  FStore.Close(RequireString(mParams, 'textDocument.uri', TLspTextDocumentMethod.cDidClose));
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.TextDocumentSync', cTexts);

end.
