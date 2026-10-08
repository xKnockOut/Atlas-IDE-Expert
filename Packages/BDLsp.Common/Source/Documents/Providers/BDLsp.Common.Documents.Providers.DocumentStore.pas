unit BDLsp.Common.Documents.Providers.DocumentStore;

// Speicher der geöffneten Dokumente. Ändern ist für den Thread der
// Nachrichtenschleife gedacht, Lesen (TryGet, Documents) geht aus jedem Thread.
// Listener werden außerhalb der Sperre aufgerufen.
//
// Schlüssel ist TDocumentUris.Key: verschiedene Schreibweisen derselben Datei
// (c%3A/C:, Umlaute kodiert oder nicht, Groß-/Kleinschreibung) führen zum
// selben Dokument. Das Dokument behält die URI, mit der der Client es öffnete.

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Documents.Uris;

type
  TDocumentStore = class(TInterfacedObject, IDocumentStore)
  private
    FLock: TCriticalSection;
    FDocuments: TDictionary<string, ITextDocument>;
    FListeners: TList<TDocumentListener>;
    FCanonicalize: TPathCanonicalizer;
    // URI → Schlüssel; spart den Plattenzugriff des Canonicalizers je Änderung.
    FKeys: TDictionary<string, string>;
    function KeyOf(const AUri: string): string;
    procedure Notify(AKind: TDocumentEventKind; const ADocument: ITextDocument);
    function Take(const AUri: string; out ADocument: ITextDocument): Boolean;
  public
    constructor Create; overload;
    /// <summary>Mit Auflösung von Symlinks und Junctions für die Schlüssel.</summary>
    constructor Create(const ACanonicalize: TPathCanonicalizer); overload;
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
  FKeys := TDictionary<string, string>.Create;
end;

constructor TDocumentStore.Create(const ACanonicalize: TPathCanonicalizer);
begin
  Create;
  FCanonicalize := ACanonicalize;
end;

function TDocumentStore.KeyOf(const AUri: string): string;
var
  Found: Boolean;
begin
  FLock.Enter;
  try
    Found := FKeys.TryGetValue(AUri, Result);
  finally
    FLock.Leave;
  end;
  if Found then
    Exit;
  Result := TDocumentUris.Key(AUri, FCanonicalize);
  FLock.Enter;
  try
    FKeys.AddOrSetValue(AUri, Result);
  finally
    FLock.Leave;
  end;
end;

destructor TDocumentStore.Destroy;
begin
  FKeys.Free;
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
var
  Key: string;
begin
  Key := KeyOf(AUri);
  FLock.Enter;
  try
    Result := FDocuments.TryGetValue(Key, ADocument);
    if Result then
    begin
      FDocuments.Remove(Key);
      FKeys.Remove(AUri);
    end;
  finally
    FLock.Leave;
  end;
end;

function TDocumentStore.Open(const AUri, ALanguageId: string; AVersion: Integer;
  const AText: string): ITextDocument;
var
  Key: string;
begin
  Key := KeyOf(AUri);
  Result := TTextDocument.Create(AUri, ALanguageId, AVersion, AText);
  FLock.Enter;
  try
    FDocuments.AddOrSetValue(Key, Result);
  finally
    FLock.Leave;
  end;
  Notify(TDocumentEventKind.Opened, Result);
end;

function TDocumentStore.Change(const AUri: string; AVersion: Integer;
  const AChanges: TArray<TTextChange>): ITextDocument;
var
  Current: ITextDocument;
  Key: string;
begin
  if not TryGet(AUri, Current) then
    raise EDocumentError.CreateFmt('Dokument ist nicht geöffnet: %s', [AUri]);
  Key := KeyOf(AUri);
  Result := Current.ApplyChanges(AChanges, AVersion);
  FLock.Enter;
  try
    FDocuments.AddOrSetValue(Key, Result);
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
var
  Key: string;
begin
  Key := KeyOf(AUri);
  FLock.Enter;
  try
    Result := FDocuments.TryGetValue(Key, ADocument);
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
