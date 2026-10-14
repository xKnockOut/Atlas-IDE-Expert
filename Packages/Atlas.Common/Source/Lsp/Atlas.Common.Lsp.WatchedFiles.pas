unit Atlas.Common.Lsp.WatchedFiles;

// Dateiänderungen außerhalb des Editors (workspace/didChangeWatchedFiles).
//
// Nach initialized meldet RegisterWatchers per client/registerCapability
// Dateibeobachter für Quelltexte und Projektdateien an, sofern der Client
// das dynamisch unterstützt. Eingehende Änderungen werden in Pfade
// übersetzt und über OnChanged weitergegeben; die Komposition aktualisiert
// damit den Index oder lädt bei Projektdateien das Projekt neu. Dazu gehören
// atlas.json und die globale Benutzerdatei (#227); für Clients ohne Beobachter
// (RAD-Studio-IDE) beobachtet der Server sie selbst und stellt die Änderungen
// als Notification (Notification) in die eigene Nachrichtenschleife.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Index.Contract;

type
  TWatchedFilesEvent = reference to procedure(const AChanges: TArray<TFileChange>);

  TLspWatchedFiles = class
  public const
    Method = 'workspace/didChangeWatchedFiles';
    RegisterMethod = 'client/registerCapability';
    GlobPattern = '**/*.{pas,inc,dpr,dpk,dfm,dproj,groupproj,json}';
  private
    FTransport: IJsonRpcTransport;
    FOnChanged: TWatchedFilesEvent;
    procedure HandleChanged(const AParams: TJSONValue);
  public
    constructor Create(const ATransport: IJsonRpcTransport);
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Meldet die Beobachter an, wenn der Client dynamische Registrierung kann.</summary>
    procedure RegisterWatchers(const AInitializeParams: TJSONObject);
    /// <summary>Ob der Client Beobachter dynamisch registrieren lässt.</summary>
    class function SupportsDynamicRegistration(const AInitializeParams: TJSONObject): Boolean; static;
    /// <summary>Anfrage client/registerCapability. Der Aufrufer übernimmt das Objekt.</summary>
    class function BuildRegistration: TJSONObject; static;
    /// <summary>Änderungen aus den Parametern der Notification; unbekannte Einträge entfallen.</summary>
    class function ParseChanges(const AParams: TJSONValue): TArray<TFileChange>; static;
    /// <summary>Projekt- oder Gruppendatei (.dproj, .dpk, .groupproj).</summary>
    class function IsProjectFile(const AFileName: string): Boolean; static;
    /// <summary>Notification workspace/didChangeWatchedFiles mit AFiles als geändert (Typ 2). Der Aufrufer
    /// übernimmt das Objekt.</summary>
    class function Notification(const AFiles: TArray<string>): TJSONObject; static;
    property OnChanged: TWatchedFilesEvent read FOnChanged write FOnChanged;
  end;

implementation

uses
  Atlas.Common.Documents.Uris;

{ TLspWatchedFiles }

constructor TLspWatchedFiles.Create(const ATransport: IJsonRpcTransport);
begin
  inherited Create;
  FTransport := ATransport;
end;

procedure TLspWatchedFiles.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterNotification(Method, HandleChanged);
end;

class function TLspWatchedFiles.SupportsDynamicRegistration(const AInitializeParams: TJSONObject): Boolean;
var
  Value: Boolean;
begin
  Result := (AInitializeParams <> nil) and
    AInitializeParams.TryGetValue<Boolean>('capabilities.workspace.didChangeWatchedFiles.dynamicRegistration', Value) and
    Value;
end;

class function TLspWatchedFiles.BuildRegistration: TJSONObject;
var
  Watcher, Options, Registration, Params: TJSONObject;
  Watchers, Registrations: TJSONArray;
begin
  Watcher := TJSONObject.Create;
  Watcher.AddPair('globPattern', GlobPattern);
  Watchers := TJSONArray.Create;
  Watchers.AddElement(Watcher);
  Options := TJSONObject.Create;
  Options.AddPair('watchers', Watchers);
  Registration := TJSONObject.Create;
  Registration.AddPair('id', 'atlas/watchedFiles');
  Registration.AddPair('method', Method);
  Registration.AddPair('registerOptions', Options);
  Registrations := TJSONArray.Create;
  Registrations.AddElement(Registration);
  Params := TJSONObject.Create;
  Params.AddPair('registrations', Registrations);
  Result := TJSONObject.Create;
  Result.AddPair('jsonrpc', '2.0');
  Result.AddPair('id', 'atlas/registerWatchers');
  Result.AddPair('method', RegisterMethod);
  Result.AddPair('params', Params);
end;

procedure TLspWatchedFiles.RegisterWatchers(const AInitializeParams: TJSONObject);
var
  Request: TJSONObject;
begin
  // Die Antwort des Clients wird nicht ausgewertet.
  if not SupportsDynamicRegistration(AInitializeParams) then
    Exit;
  Request := BuildRegistration;
  try
    FTransport.WriteMessage(Request);
  finally
    Request.Free;
  end;
end;

class function TLspWatchedFiles.ParseChanges(const AParams: TJSONValue): TArray<TFileChange>;
var
  Changes: TJSONArray;
  Item: TJSONValue;
  Uri, Path: string;
  ChangeType: Integer;
begin
  Result := nil;
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<TJSONArray>('changes', Changes)) then
    Exit;
  for Item in Changes do
  begin
    if not (Item.TryGetValue<string>('uri', Uri) and Item.TryGetValue<Integer>('type', ChangeType)) then
      Continue;
    Path := TDocumentUris.ToPath(Uri);
    if Path = '' then
      Continue;
    // FileChangeType des LSP: 1 Created, 2 Changed, 3 Deleted.
    case ChangeType of
      1: Result := Result + [TFileChange.Create(Path, TFileChangeKind.Created)];
      2: Result := Result + [TFileChange.Create(Path, TFileChangeKind.Changed)];
      3: Result := Result + [TFileChange.Create(Path, TFileChangeKind.Deleted)];
    end;
  end;
end;

class function TLspWatchedFiles.IsProjectFile(const AFileName: string): Boolean;
var
  Extension: string;
begin
  Extension := LowerCase(ExtractFileExt(AFileName));
  Result := (Extension = '.dproj') or (Extension = '.dpk') or (Extension = '.groupproj');
end;

class function TLspWatchedFiles.Notification(const AFiles: TArray<string>): TJSONObject;
var
  Changes: TJSONArray;
  Change, Params: TJSONObject;
  FileName: string;
begin
  Changes := TJSONArray.Create;
  for FileName in AFiles do
  begin
    // Auch neu angelegte oder gelöschte Dateien als „geändert“: Der Empfänger liest sie neu ein.
    Change := TJSONObject.Create;
    Change.AddPair('uri', TDocumentUris.FromPath(FileName));
    Change.AddPair('type', TJSONNumber.Create(2));
    Changes.AddElement(Change);
  end;
  Params := TJSONObject.Create;
  Params.AddPair('changes', Changes);
  Result := TJSONObject.Create;
  Result.AddPair('jsonrpc', '2.0');
  Result.AddPair('method', Method);
  Result.AddPair('params', Params);
end;

procedure TLspWatchedFiles.HandleChanged(const AParams: TJSONValue);
var
  Changes: TArray<TFileChange>;
begin
  Changes := ParseChanges(AParams);
  if (Length(Changes) > 0) and Assigned(FOnChanged) then
    FOnChanged(Changes);
end;

end.
