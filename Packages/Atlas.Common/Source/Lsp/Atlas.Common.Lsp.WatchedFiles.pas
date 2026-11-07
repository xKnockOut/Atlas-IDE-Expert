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
    cMethod = 'workspace/didChangeWatchedFiles';
    cRegisterMethod = 'client/registerCapability';
    cGlobPattern = '**/*.{pas,inc,dpr,dpk,dfm,dproj,groupproj,json}';
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
  System.Generics.Collections,
  Atlas.Common.Documents.Uris;

{ TLspWatchedFiles }

constructor TLspWatchedFiles.Create(const ATransport: IJsonRpcTransport);
begin
  inherited Create;
  FTransport := ATransport;
end;

procedure TLspWatchedFiles.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterNotification(cMethod, HandleChanged);
end;

class function TLspWatchedFiles.SupportsDynamicRegistration(const AInitializeParams: TJSONObject): Boolean;
var
  mValue: Boolean;
begin
  Result := (AInitializeParams <> nil) and
    AInitializeParams.TryGetValue<Boolean>('capabilities.workspace.didChangeWatchedFiles.dynamicRegistration', mValue) and
    mValue;
end;

class function TLspWatchedFiles.BuildRegistration: TJSONObject;
var
  mWatcher, mOptions, mRegistration, mParams: TJSONObject;
  mWatchers, mRegistrations: TJSONArray;
begin
  mWatcher := TJSONObject.Create;
  mWatcher.AddPair('globPattern', cGlobPattern);
  mWatchers := TJSONArray.Create;
  mWatchers.AddElement(mWatcher);
  mOptions := TJSONObject.Create;
  mOptions.AddPair('watchers', mWatchers);
  mRegistration := TJSONObject.Create;
  mRegistration.AddPair('id', 'atlas/watchedFiles');
  mRegistration.AddPair('method', cMethod);
  mRegistration.AddPair('registerOptions', mOptions);
  mRegistrations := TJSONArray.Create;
  mRegistrations.AddElement(mRegistration);
  mParams := TJSONObject.Create;
  mParams.AddPair('registrations', mRegistrations);
  Result := TJSONObject.Create;
  Result.AddPair('jsonrpc', '2.0');
  Result.AddPair('id', 'atlas/registerWatchers');
  Result.AddPair('method', cRegisterMethod);
  Result.AddPair('params', mParams);
end;

procedure TLspWatchedFiles.RegisterWatchers(const AInitializeParams: TJSONObject);
var
  mRequest: TJSONObject;
begin
  // Die Antwort des Clients wird nicht ausgewertet.
  if not SupportsDynamicRegistration(AInitializeParams) then
  begin
    Exit;
  end;
  mRequest := BuildRegistration;
  try
    FTransport.WriteMessage(mRequest);
  finally
    mRequest.Free;
  end;
end;

class function TLspWatchedFiles.ParseChanges(const AParams: TJSONValue): TArray<TFileChange>;
var
  mChanges: TJSONArray;
  mItem: TJSONValue;
  mUri, mPath: string;
  mChangeType: Integer;
begin
  Result := nil;
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<TJSONArray>('changes', mChanges)) then
  begin
    Exit;
  end;
  for mItem in mChanges do
  begin
    if not (mItem.TryGetValue<string>('uri', mUri) and mItem.TryGetValue<Integer>('type', mChangeType)) then
    begin
      Continue;
    end;
    mPath := TDocumentUris.ToPath(mUri);
    if mPath = '' then
    begin
      Continue;
    end;
    // FileChangeType des LSP: 1 Created, 2 Changed, 3 Deleted.
    case mChangeType of
      1: Result := Result + [TFileChange.Create(mPath, TFileChangeKind.Created)];
      2: Result := Result + [TFileChange.Create(mPath, TFileChangeKind.Changed)];
      3: Result := Result + [TFileChange.Create(mPath, TFileChangeKind.Deleted)];
    end;
  end;
end;

class function TLspWatchedFiles.IsProjectFile(const AFileName: string): Boolean;
var
  mExtension: string;
begin
  mExtension := LowerCase(ExtractFileExt(AFileName));
  Result := (mExtension = '.dproj') or (mExtension = '.dpk') or (mExtension = '.groupproj');
end;

class function TLspWatchedFiles.Notification(const AFiles: TArray<string>): TJSONObject;
var
  mChanges: TJSONArray;
  mChange, mParams: TJSONObject;
  mFileName: string;
begin
  mChanges := TJSONArray.Create;
  for mFileName in AFiles do
  begin
    // Auch neu angelegte oder gelöschte Dateien als „geändert“: Der Empfänger liest sie neu ein.
    mChange := TJSONObject.Create;
    mChange.AddPair('uri', TDocumentUris.FromPath(mFileName));
    mChange.AddPair('type', TJSONNumber.Create(2));
    mChanges.AddElement(mChange);
  end;
  mParams := TJSONObject.Create;
  mParams.AddPair('changes', mChanges);
  Result := TJSONObject.Create;
  Result.AddPair('jsonrpc', '2.0');
  Result.AddPair('method', cMethod);
  Result.AddPair('params', mParams);
end;

procedure TLspWatchedFiles.HandleChanged(const AParams: TJSONValue);
var
  mChanges: TArray<TFileChange>;
begin
  mChanges := ParseChanges(AParams);
  if (Length(mChanges) > 0) and Assigned(FOnChanged) then
  begin
    FOnChanged(mChanges);
  end;
end;

end.
