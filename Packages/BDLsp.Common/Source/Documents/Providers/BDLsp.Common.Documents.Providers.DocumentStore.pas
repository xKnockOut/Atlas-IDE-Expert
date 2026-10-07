unit BDLsp.Common.Documents.Providers.DocumentStore;

// Speicher der geöffneten Dokumente. Ändern ist für den Thread der
// Nachrichtenschleife gedacht, Lesen (TryGet, Documents) geht aus jedem Thread.
// Listener werden außerhalb der Sperre aufgerufen.

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections,
  BDLsp.Common.Documents.Contract;

type
  TDocumentStore = class(TInterfacedObject, IDocumentStore)
  private
    FLock: TCriticalSection;
    FDocuments: TDictionary<string, ITextDocument>;
    FListeners: TList<TDocumentListener>;
    procedure Notify(AKind: TDocumentEventKind; const ADocument: ITextDocument);
    function Take(const AUri: string; out ADocument: ITextDocument): Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    { IDocumentStore }
    function Open(const AUri, ALanguageId: string; AVersion: Integer; const AText: string): ITextDocument;
    function Change(const AUri: string; AVersion: Integer; const AChanges: TArray<TTextChange>): ITextDocument;
    procedure Save(const AUri: string);
    procedure Close(const AUri: string);
    function TryGet(const AUri: string; out ADocument: ITextDocument): Boolean;
    function Documents: TArray<ITextDocument>;
    procedure Subscribe(const AListener: TDocumentListener);
  end;

implementation

uses
  BDLsp.Common.Documents.TextDocument;

{ TDocumentStore }

constructor TDocumentStore.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FDocuments := TDictionary<string, ITextDocument>.Create;
  FListeners := TList<TDocumentListener>.Create;
end;

destructor TDocumentStore.Destroy;
begin
  FListeners.Free;
  FDocuments.Free;
  FLock.Free;
  inherited;
end;

procedure TDocumentStore.Notify(AKind: TDocumentEventKind; const ADocument: ITextDocument);
var
  Listeners: TArray<TDocumentListener>;
  Listener: TDocumentListener;
begin
  FLock.Enter;
  try
    Listeners := FListeners.ToArray;
  finally
    FLock.Leave;
  end;
  for Listener in Listeners do
    Listener(AKind, ADocument);
end;

function TDocumentStore.Take(const AUri: string; out ADocument: ITextDocument): Boolean;
begin
  FLock.Enter;
  try
    Result := FDocuments.TryGetValue(AUri, ADocument);
    if Result then
      FDocuments.Remove(AUri);
  finally
    FLock.Leave;
  end;
end;

function TDocumentStore.Open(const AUri, ALanguageId: string; AVersion: Integer;
  const AText: string): ITextDocument;
begin
  Result := TTextDocument.Create(AUri, ALanguageId, AVersion, AText);
  FLock.Enter;
  try
    FDocuments.AddOrSetValue(AUri, Result);
  finally
    FLock.Leave;
  end;
  Notify(TDocumentEventKind.Opened, Result);
end;

function TDocumentStore.Change(const AUri: string; AVersion: Integer;
  const AChanges: TArray<TTextChange>): ITextDocument;
var
  Current: ITextDocument;
begin
  if not TryGet(AUri, Current) then
    raise EDocumentError.CreateFmt('Dokument ist nicht geöffnet: %s', [AUri]);
  Result := Current.ApplyChanges(AChanges, AVersion);
  FLock.Enter;
  try
    FDocuments.AddOrSetValue(AUri, Result);
  finally
    FLock.Leave;
  end;
  Notify(TDocumentEventKind.Changed, Result);
end;

procedure TDocumentStore.Save(const AUri: string);
var
  Document: ITextDocument;
begin
  if TryGet(AUri, Document) then
    Notify(TDocumentEventKind.Saved, Document);
end;

procedure TDocumentStore.Close(const AUri: string);
var
  Document: ITextDocument;
begin
  if Take(AUri, Document) then
    Notify(TDocumentEventKind.Closed, Document);
end;

function TDocumentStore.TryGet(const AUri: string; out ADocument: ITextDocument): Boolean;
begin
  FLock.Enter;
  try
    Result := FDocuments.TryGetValue(AUri, ADocument);
  finally
    FLock.Leave;
  end;
end;

function TDocumentStore.Documents: TArray<ITextDocument>;
begin
  FLock.Enter;
  try
    Result := FDocuments.Values.ToArray;
  finally
    FLock.Leave;
  end;
end;

procedure TDocumentStore.Subscribe(const AListener: TDocumentListener);
begin
  FLock.Enter;
  try
    FListeners.Add(AListener);
  finally
    FLock.Leave;
  end;
end;

end.
