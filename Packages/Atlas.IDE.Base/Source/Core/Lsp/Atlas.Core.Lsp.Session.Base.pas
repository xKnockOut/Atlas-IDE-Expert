unit Atlas.Core.Lsp.Session.Base;

// Zustand der LSP-Sitzung (aus Atlas.Core.Lsp.Session ausgelagert): Client, initialize mit Projekten und
// Projektkontexten, Empfänger im Lese-Thread (refresh, $/progress, showMessage, Absturzfälle, applyEdit) und der
// Dokumentabgleich (didOpen, didChange mit geändertem Bereich, didClose). Anfragen stehen in
// Atlas.Core.Lsp.Session.Requests und Atlas.Core.Lsp.Session.

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.Progress,
  Atlas.Core.Projects.Contract,
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Lsp.Session.Json;

type
  /// <summary>Angaben für initialize, vor Initialize zu setzen.</summary>
  TLspInitializeOptions = record
    /// <summary>Einstellungen der Atlas-Optionen im Format von atlas.json (#652); gehen als initializationOptions
    /// mit, damit schon der erste Indexaufbau sie nutzt.</summary>
    Settings: string;
    /// <summary>Sprache der Oberfläche (#1458), "de" oder "en"; '' überlässt die Wahl dem Server.</summary>
    Locale: string;
    /// <summary>Angaben nur mit der Sprache ALocale.</summary>
    class function ForLocale(const ALocale: string): TLspInitializeOptions; static;
  end;

  /// <summary>Zustand der LSP-Sitzung: Client, Dokumentabgleich, Projekte und initialize. Vorfahr der
  /// Anfragen (TLspSessionRequests) und von TLspSession.</summary>
  TLspSessionBase = class(TLspSessionJson)
  private type
    TDocumentState = record
      FileName: string;
      Version: Integer;
      Text: string;
    end;
  private
    FDocuments: TDictionary<string, TDocumentState>;
    // Schützt FDocuments samt Reihenfolge der didOpen/didChange (#493): Sync läuft auch aus
    // Hintergrund-Threads (Zeitlimit für Quellen).
    FDocLock: TObject;
    FInitialized: Boolean;
    FProjects: TArray<string>;
    FProjectsRemoved: Integer;
    /// <summary>Projektkontexte für initialize (#396).</summary>
    FContexts: TArray<TAtlasProjectContext>;
    /// <summary>Zuletzt gemeldeter Schlüssel je Projekt (#396).</summary>
    FSentContexts: TDictionary<string, string>;
    FOnApplyEdit: TLspApplyEditProc;
    FOnShowMessage: TLspShowMessageProc;
    FOnAtlasNotification: TLspAtlasNotificationProc;
    FInitializeOptions: TLspInitializeOptions;
    FServerVersion: string;
    procedure SyncLocked(const AFileName, AText: string);
    procedure CloseLocked(const AFileName: string);
    /// <summary>Lese-Thread-Empfänger setzen; fängt nur Zähler, Client und Callbacks ein, nie Self.</summary>
    procedure AttachClientHandlers;
  protected
    FClient: TLspClient;
    FRefresh: ILspSignal;
    FProgress: ILspProgress;
    FTimeoutMs: Cardinal;
    function PositionParams(const AFileName: string; ALine, ACharacter: Integer): TJSONObject;
    /// <summary>ATimeoutMs, wenn gesetzt; sonst das Zeitlimit der Sitzung.</summary>
    function TimeoutOr(ATimeoutMs: Cardinal): Cardinal;
    /// <summary>Wurde AFileName abgeglichen und nicht geschlossen? Threadsicher.</summary>
    function IsSynced(const AFileName: string): Boolean;
  public
    /// <summary>AClient gehört weiter dem Aufrufer.</summary>
    constructor Create(AClient: TLspClient; ATimeoutMs: Cardinal); overload;
    /// <summary>Wie oben mit ATimeoutMs = 3000.</summary>
    constructor Create(AClient: TLspClient); overload;
    destructor Destroy; override;
    /// <summary>Projekte der Gruppe, aktives zuerst. Vor Initialize nur gemerkt, danach als
    /// didChangeWorkspaceFolders gemeldet, falls sich etwas geändert hat (#648).</summary>
    procedure SetProjects(const AProjects: TArray<string>);
    /// <summary>Zählt jedes Melden weggefallener Projekte (Projektgruppe geschlossen oder gewechselt): Befunde
    /// dieser Projekte liefert der Server nicht mehr, der Empfänger verwirft seine.</summary>
    property ProjectsRemoved: Integer read FProjectsRemoved;
    /// <summary>Projektkontexte aus der IDE (#396). Vor Initialize nur gemerkt, danach jeder neue oder
    /// geänderte als atlas/projectContext gemeldet. Vor SetProjects aufrufen, damit ein neues Projekt
    /// gleich mit seinem Kontext geladen wird. Ergebnis: die neu gemeldeten oder für initialize
    /// gemerkten Kontexte (fürs Diagnoseprotokoll).</summary>
    function SetProjectContexts(const AContexts: TArray<TAtlasProjectContext>): TArray<TAtlasProjectContext>;
    procedure Initialize;
    /// <summary>Vor Initialize setzen (#397): workspace/applyEdit des Servers annehmen.</summary>
    property OnApplyEdit: TLspApplyEditProc read FOnApplyEdit write FOnApplyEdit;
    /// <summary>Vor Initialize setzen (#121): Meldungen des Servers für den Benutzer.</summary>
    property OnShowMessage: TLspShowMessageProc read FOnShowMessage write FOnShowMessage;
    /// <summary>Vor Initialize setzen: Benachrichtigungen atlas/… des Servers (Absturzfälle #1355, IDE-Mitglieder).
    /// </summary>
    property OnAtlasNotification: TLspAtlasNotificationProc read FOnAtlasNotification write FOnAtlasNotification;
    /// <summary>Einstellungen und Sprache für initialize (#652, #1458), vor Initialize setzen.</summary>
    property InitializeOptions: TLspInitializeOptions read FInitializeOptions write FInitializeOptions;
    /// <summary>Schickt AText, falls neu oder geändert.</summary>
    procedure Sync(const AFileName, AText: string);
    /// <summary>didClose für eine abgeglichene Datei; danach liest der Server sie wieder von der Platte.</summary>
    procedure Close(const AFileName: string);
    /// <summary>Abgeglichene Dateien (Hauptthread).</summary>
    function SyncedFiles: TArray<string>;
    /// <summary>Zuletzt geschickter Text einer Datei (Hauptthread).</summary>
    function SyncedText(const AFileName: string; out AText: string): Boolean;
    /// <summary>Alle abgeglichenen Dokumente mit Text, etwa um sie nach einem Serverneustart
    /// erneut zu öffnen (#393). Hauptthread.</summary>
    function OpenDocuments: TArray<TLspOpenDocument>;
    /// <summary>Öffnet die Dokumente einer früheren Sitzung (didOpen, Version 1); schon
    /// abgeglichene bleiben unverändert. Erst nach Initialize aufrufen (#393).</summary>
    procedure Reopen(const ADocuments: TArray<TLspOpenDocument>);
    /// <summary>Version aus serverInfo der Antwort auf initialize; '' = unbekannt (#591).</summary>
    property ServerVersion: string read FServerVersion;
    property Initialized: Boolean read FInitialized;
  end;

implementation

uses
  System.SyncObjs;

type
  TLspSignal = class(TInterfacedObject, ILspSignal)
  private
    FCount: Integer;
  public
    function Count: Integer;
    procedure Signal;
  end;

{ TLspInitializeOptions }

class function TLspInitializeOptions.ForLocale(const ALocale: string): TLspInitializeOptions;
begin
  Result := Default(TLspInitializeOptions);
  Result.Locale := ALocale;
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

type
  /// <summary>Id einer Serveranfrage, auf die später geantwortet wird (#397). Wer zuerst Take ruft, antwortet;
  /// kommt keine Antwort, gibt der letzte Verweis die Id frei.</summary>
  ILspPendingId = interface
    ['{99D9B680-B103-49D4-AA8A-57D6CD498B8E}']
    function Take: TJSONValue;
  end;

  TLspPendingId = class(TInterfacedObject, ILspPendingId)
  private
    FId: TJSONValue;
  public
    constructor Create(AId: TJSONValue);
    destructor Destroy; override;
    function Take: TJSONValue;
  end;

{ TLspPendingId }

constructor TLspPendingId.Create(AId: TJSONValue);
begin
  inherited Create;
  FId := AId;
end;

destructor TLspPendingId.Destroy;
begin
  FId.Free;
  inherited Destroy;
end;

function TLspPendingId.Take: TJSONValue;
begin
  Result := TInterlocked.Exchange<TJSONValue>(FId, nil);
end;

/// <summary>Empfänger der Servernachrichten im Lese-Thread; fängt nur Zähler und Callbacks ein, nie die
/// Sitzung, denn der Lese-Thread kann sie überleben.</summary>
function ServerMessageHandler(const ARefresh: ILspSignal; const AProgress: ILspProgress;
  const AShowMessage: TLspShowMessageProc; const AAtlas: TLspAtlasNotificationProc): TLspServerMessageProc;
begin
  Result :=
    procedure(const AMethod: string; const AParams: TJSONValue)
    var
      MessageType: Integer;
      Text: string;
    begin
      if AMethod = 'workspace/diagnostic/refresh' then
      begin
        ARefresh.Signal;
      end
      else if AMethod = '$/progress' then
      begin
        AProgress.Handle(AParams);
      end
      else if (AMethod = 'window/showMessage') and Assigned(AShowMessage) and
        TLspSessionJson.ShowMessageParams(AParams, MessageType, Text) then
      begin
        AShowMessage(MessageType, Text);
      end
      else if AMethod.StartsWith('atlas/') and Assigned(AAtlas) then
      begin
        AAtlas(AMethod, AParams);
      end;
    end;
end;

/// <summary>Antwort auf workspace/applyEdit für APending; nur die erste zählt.</summary>
function ApplyEditReplyOf(const APending: ILspPendingId; AClient: TLspClient): TLspApplyEditReply;
begin
  Result :=
    procedure(AApplied: Boolean; const AFailureReason: string)
    var
      Id: TJSONValue;
    begin
      // Nur die erste Antwort zählt.
      Id := APending.Take;
      if Id <> nil then
      begin
        AClient.Respond(Id, TLspSessionJson.ApplyEditAnswer(AApplied, AFailureReason));
      end;
    end;
end;

/// <summary>Empfänger für workspace/applyEdit (#397); kennt nur Client und Empfänger, nicht die Sitzung.</summary>
function ApplyEditRequestHandler(const AApplyEdit: TLspApplyEditProc; AClient: TLspClient): TLspServerRequestFunc;
begin
  Result :=
    function(const AMethod: string; const AParams: TJSONValue; AId: TJSONValue): Boolean
    var
      Value: TJSONValue;
      Pending: ILspPendingId;
    begin
      Result := AMethod = 'workspace/applyEdit';
      if not Result then
      begin
        Exit;
      end;
      Value := nil;
      if AParams is TJSONObject then
      begin
        Value := TJSONObject(AParams).GetValue('edit');
      end;
      // Ab hier gehört AId der Sitzung; antwortet niemand, gibt Pending sie frei.
      Pending := TLspPendingId.Create(AId);
      try
        AApplyEdit(TLspWorkspaceEdit.FromJson(Value), ApplyEditReplyOf(Pending, AClient));
      except
        // Nicht angenommen: Der Client antwortet mit null und gibt seine Id selbst frei.
        Pending.Take;
        raise;
      end;
    end;
end;

procedure TLspSessionBase.AttachClientHandlers;
begin
  FClient.OnServerMessage := ServerMessageHandler(FRefresh, FProgress, FOnShowMessage, FOnAtlasNotification);
  if Assigned(FOnApplyEdit) then
  begin
    FClient.OnServerRequest := ApplyEditRequestHandler(FOnApplyEdit, FClient);
  end;
end;

{ TLspSessionBase }

constructor TLspSessionBase.Create(AClient: TLspClient);
begin
  Create(AClient, 3000);
end;

constructor TLspSessionBase.Create(AClient: TLspClient; ATimeoutMs: Cardinal);
begin
  inherited Create;
  FClient := AClient;
  FTimeoutMs := ATimeoutMs;
  FDocuments := TDictionary<string, TDocumentState>.Create;
  FSentContexts := TDictionary<string, string>.Create;
  FDocLock := TObject.Create;
  FRefresh := TLspSignal.Create;
  FProgress := TLspProgress.Create;
end;

destructor TLspSessionBase.Destroy;
begin
  FSentContexts.Free;
  FDocuments.Free;
  FDocLock.Free;
  inherited;
end;

procedure TLspSessionBase.Initialize;
var
  mParams: TJSONObject;
  mContext: TAtlasProjectContext;
  mResponse: TJSONValue;
begin
  mParams := InitializeParams(FProjects, FInitializeOptions.Settings, FContexts, Assigned(FOnApplyEdit),
    FInitializeOptions.Locale);
  // Gesendete Kontexte merken: SetProjectContexts schickt danach nur neue oder geänderte (#396).
  for mContext in FContexts do
  begin
    FSentContexts.AddOrSetValue(AnsiUpperCase(mContext.Project), mContext.Key);
  end;
  // Empfänger vor initialize setzen: Der Server darf gleich danach Nachrichten schicken.
  AttachClientHandlers;
  // Ohne Arbeitsbereich leitet der Server ihn aus den geöffneten Dateien ab, ebenso für Dateien
  // außerhalb der gemeldeten Projekte.
  mResponse := FClient.Request('initialize', mParams, 15000);
  try
    if mResponse is TJSONObject then
    begin
      FServerVersion := TJSONObject(mResponse).GetValue<string>('serverInfo.version', '');
    end;
  finally
    mResponse.Free;
  end;
  FClient.Notify('initialized', TJSONObject.Create);
  FInitialized := True;
end;

procedure TLspSessionBase.Sync(const AFileName, AText: string);
begin
  TMonitor.Enter(FDocLock);
  try
    SyncLocked(AFileName, AText);
  finally
    TMonitor.Exit(FDocLock);
  end;
end;

procedure TLspSessionBase.SyncLocked(const AFileName, AText: string);
var
  mState: TDocumentState;
  mKey: string;
  mParams, mDocument, mChange: TJSONObject;
  mChanges: TJSONArray;
  mEdit: TLspTextChange;
begin
  mKey := AnsiLowerCase(AFileName);
  mDocument := TJSONObject.Create;
  mDocument.AddPair('uri', PathToUri(AFileName));
  if not FDocuments.TryGetValue(mKey, mState) then
  begin
    mState.FileName := AFileName;
    mState.Version := 1;
    mState.Text := AText;
    FDocuments.Add(mKey, mState);
    mDocument.AddPair('languageId', 'delphi');
    mDocument.AddPair('version', TJSONNumber.Create(mState.Version));
    mDocument.AddPair('text', AText);
    FClient.Notify('textDocument/didOpen', TJSONObject.Create(TJSONPair.Create('textDocument', mDocument)));
    Exit;
  end;
  if mState.Text = AText then
  begin
    mDocument.Free;
    Exit;
  end;
  // Nur der geänderte Bereich (#395); der Server meldet textDocumentSync.change = Incremental.
  mEdit := TLspTextChanges.Between(mState.Text, AText);
  Inc(mState.Version);
  mState.Text := AText;
  FDocuments[mKey] := mState;
  mDocument.AddPair('version', TJSONNumber.Create(mState.Version));
  mChange := TJSONObject.Create;
  mChange.AddPair('range', TJSONObject.Create
    .AddPair('start', TJSONObject.Create
      .AddPair('line', TJSONNumber.Create(mEdit.StartPos.Line))
      .AddPair('character', TJSONNumber.Create(mEdit.StartPos.Character)))
    .AddPair('end', TJSONObject.Create
      .AddPair('line', TJSONNumber.Create(mEdit.EndPos.Line))
      .AddPair('character', TJSONNumber.Create(mEdit.EndPos.Character))));
  mChange.AddPair('text', mEdit.Text);
  mChanges := TJSONArray.Create;
  mChanges.AddElement(mChange);
  mParams := TJSONObject.Create;
  mParams.AddPair('textDocument', mDocument);
  mParams.AddPair('contentChanges', mChanges);
  FClient.Notify('textDocument/didChange', mParams);
end;

function TLspSessionBase.TimeoutOr(ATimeoutMs: Cardinal): Cardinal;
begin
  Result := FTimeoutMs;
  if ATimeoutMs > 0 then
  begin
    Result := ATimeoutMs;
  end;
end;

function TLspSessionBase.PositionParams(const AFileName: string; ALine, ACharacter: Integer): TJSONObject;
var
  mPosition: TJSONObject;
begin
  mPosition := TJSONObject.Create;
  mPosition.AddPair('line', TJSONNumber.Create(ALine));
  mPosition.AddPair('character', TJSONNumber.Create(ACharacter));
  Result := TJSONObject.Create;
  Result.AddPair('textDocument', TJSONObject.Create(TJSONPair.Create('uri', PathToUri(AFileName))));
  Result.AddPair('position', mPosition);
end;

function TLspSessionBase.IsSynced(const AFileName: string): Boolean;
begin
  TMonitor.Enter(FDocLock);
  try
    Result := FDocuments.ContainsKey(AnsiLowerCase(AFileName));
  finally
    TMonitor.Exit(FDocLock);
  end;
end;

procedure TLspSessionBase.Close(const AFileName: string);
begin
  TMonitor.Enter(FDocLock);
  try
    CloseLocked(AFileName);
  finally
    TMonitor.Exit(FDocLock);
  end;
end;

procedure TLspSessionBase.CloseLocked(const AFileName: string);
var
  mKey: string;
begin
  mKey := AnsiLowerCase(AFileName);
  if not FDocuments.ContainsKey(mKey) then
  begin
    Exit;
  end;
  FDocuments.Remove(mKey);
  FClient.Notify('textDocument/didClose', TJSONObject.Create(TJSONPair.Create('textDocument',
    TJSONObject.Create(TJSONPair.Create('uri', PathToUri(AFileName))))));
end;

function TLspSessionBase.SyncedFiles: TArray<string>;
var
  mState: TDocumentState;
begin
  Result := nil;
  TMonitor.Enter(FDocLock);
  try
    for mState in FDocuments.Values do
    begin
      Result := Result + [mState.FileName];
    end;
  finally
    TMonitor.Exit(FDocLock);
  end;
end;

function TLspSessionBase.SyncedText(const AFileName: string; out AText: string): Boolean;
var
  mState: TDocumentState;
begin
  TMonitor.Enter(FDocLock);
  try
    Result := FDocuments.TryGetValue(AnsiLowerCase(AFileName), mState);
  finally
    TMonitor.Exit(FDocLock);
  end;
  if Result then
  begin
    AText := mState.Text;
  end
  else
  begin
    AText := '';
  end;
end;

function TLspSessionBase.OpenDocuments: TArray<TLspOpenDocument>;
var
  mState: TDocumentState;
  mDocument: TLspOpenDocument;
begin
  Result := nil;
  for mState in FDocuments.Values do
  begin
    mDocument.FileName := mState.FileName;
    mDocument.Text := mState.Text;
    Result := Result + [mDocument];
  end;
end;

procedure TLspSessionBase.Reopen(const ADocuments: TArray<TLspOpenDocument>);
var
  mDocument: TLspOpenDocument;
begin
  for mDocument in ADocuments do
  begin
    if not FDocuments.ContainsKey(AnsiLowerCase(mDocument.FileName)) then
    begin
      Sync(mDocument.FileName, mDocument.Text);
    end;
  end;
end;

procedure TLspSessionBase.SetProjects(const AProjects: TArray<string>);
var
  mAdded, mRemoved: TArray<string>;
begin
  if not FInitialized then
  begin
    FProjects := AProjects;
    Exit;
  end;
  ProjectChanges(FProjects, AProjects, mAdded, mRemoved);
  FProjects := AProjects;
  if (Length(mAdded) = 0) and (Length(mRemoved) = 0) then
  begin
    Exit;
  end;
  if Length(mRemoved) > 0 then
  begin
    Inc(FProjectsRemoved);
  end;
  FClient.Notify('workspace/didChangeWorkspaceFolders', TJSONObject.Create(TJSONPair.Create('event',
    TJSONObject.Create.AddPair('added', ProjectFolders(mAdded)).AddPair('removed', ProjectFolders(mRemoved)))));
end;

function TLspSessionBase.SetProjectContexts(const AContexts: TArray<TAtlasProjectContext>):
  TArray<TAtlasProjectContext>;
var
  mContext: TAtlasProjectContext;
  mKnown: string;
begin
  Result := nil;
  if not FInitialized then
  begin
    FContexts := AContexts;
    Exit(AContexts);
  end;
  for mContext in AContexts do
  begin
    if not FSentContexts.TryGetValue(AnsiUpperCase(mContext.Project), mKnown) or (mKnown <> mContext.Key) then
    begin
      FSentContexts.AddOrSetValue(AnsiUpperCase(mContext.Project), mContext.Key);
      FClient.Notify('atlas/projectContext', mContext.ToJson);
      Result := Result + [mContext];
    end;
  end;
end;

end.
