unit Atlas.Common.Lsp.Lifecycle;

// Lebenszyklus eines Language Servers: initialize, initialized, shutdown, exit.
// Hängt sich als Guard und mit eigenen Handlern an einen JSON-RPC-Dispatcher
// und weist Nachrichten ab, die im aktuellen Zustand nicht erlaubt sind.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Lsp.Contract;

type
  TLspLifecycle = class
  private
    FServerName: string;
    FServerVersion: string;
    FCapabilities: TLspCapabilitiesFactory;
    FState: TLspServerState;
    FShutdownReceived: Boolean;
    FInitializeParams: TJSONObject;
    FOnExit: TProc;
    FOnInitialized: TProc;
    function HandleInitialize(const AParams: TJSONValue): TJSONValue;
    procedure HandleInitialized(const AParams: TJSONValue);
    function HandleShutdown(const AParams: TJSONValue): TJSONValue;
    procedure HandleExit(const AParams: TJSONValue);
    procedure CheckState(const AMethod: string; AIsRequest: Boolean);
    function GetExitCode: Integer;
  public
    /// <summary>ACapabilities liefert die Capabilities für die Antwort auf initialize.</summary>
    constructor Create(const AServerName, AServerVersion: string; const ACapabilities: TLspCapabilitiesFactory);
    destructor Destroy; override;
    /// <summary>Registriert die Handler des Lebenszyklus und setzt den Guard des Dispatchers.</summary>
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    property State: TLspServerState read FState;
    /// <summary>Parameter von initialize (Kopie), vorher nil.</summary>
    property InitializeParams: TJSONObject read FInitializeParams;
    /// <summary>0, wenn vor dem Beenden shutdown kam, sonst 1 (LSP-Spezifikation zu exit).</summary>
    property ExitCode: Integer read GetExitCode;
    /// <summary>Wird bei exit aufgerufen, z. B. um die Nachrichtenschleife zu beenden.</summary>
    property OnExit: TProc read FOnExit write FOnExit;
    /// <summary>Wird nach initialized aufgerufen, z. B. um den Arbeitsbereich zu laden.</summary>
    property OnInitialized: TProc read FOnInitialized write FOnInitialized;
  end;

implementation

uses
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TLifecycleText = (ServerIsNotInitializedYet, ServerIsAlreadyInitialized, ServerIsShuttingDown, ServerHasShutDown);

const
  cTexts: array[TLifecycleText] of TAtlasText = (
    (De: 'Server ist noch nicht initialisiert'; En: 'Server is not initialized yet'),
    (De: 'Server ist bereits initialisiert'; En: 'Server is already initialized'),
    (De: 'Server wird beendet'; En: 'Server is shutting down'),
    (De: 'Server ist beendet'; En: 'Server has shut down'));

{$SCOPEDENUMS OFF}

{ TLspLifecycle }

constructor TLspLifecycle.Create(const AServerName, AServerVersion: string;
  const ACapabilities: TLspCapabilitiesFactory);
begin
  inherited Create;
  FServerName := AServerName;
  FServerVersion := AServerVersion;
  FCapabilities := ACapabilities;
  FState := TLspServerState.Uninitialized;
end;

destructor TLspLifecycle.Destroy;
begin
  FInitializeParams.Free;
  inherited;
end;

procedure TLspLifecycle.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterRequest(TLspLifecycleMethod.cInitializeRequest, HandleInitialize);
  ADispatcher.RegisterNotification(TLspLifecycleMethod.cInitializedNotification, HandleInitialized);
  ADispatcher.RegisterRequest(TLspLifecycleMethod.cShutdownRequest, HandleShutdown);
  ADispatcher.RegisterNotification(TLspLifecycleMethod.cExitNotification, HandleExit);
  ADispatcher.Guard := CheckState;
end;

/// <summary>Fehler für AMethod im Zustand AState; '' = erlaubt. exit ist in jedem Zustand erlaubt.</summary>
function StateError(AState: TLspServerState; const AMethod: string; out ACode: Integer): string;
begin
  Result := '';
  ACode := TJsonRpcErrorCode.cInvalidRequest;
  if AMethod = TLspLifecycleMethod.cExitNotification then
  begin
    Exit;
  end;
  case AState of
    TLspServerState.Uninitialized:
      if AMethod <> TLspLifecycleMethod.cInitializeRequest then
      begin
        ACode := TLspErrorCode.cServerNotInitialized;
        Result := cTexts[TLifecycleText.ServerIsNotInitializedYet].Text;
      end;
    TLspServerState.Running:
      if AMethod = TLspLifecycleMethod.cInitializeRequest then
      begin
        Result := cTexts[TLifecycleText.ServerIsAlreadyInitialized].Text;
      end;
    TLspServerState.ShuttingDown:
      Result := cTexts[TLifecycleText.ServerIsShuttingDown].Text;
    TLspServerState.Exited:
      Result := cTexts[TLifecycleText.ServerHasShutDown].Text;
  end;
end;

procedure TLspLifecycle.CheckState(const AMethod: string; AIsRequest: Boolean);
var
  mCode: Integer;
  mMessage: string;
begin
  mMessage := StateError(FState, AMethod, mCode);
  if mMessage <> '' then
  begin
    raise EJsonRpcError.Create(mCode, mMessage);
  end;
end;

function TLspLifecycle.HandleInitialize(const AParams: TJSONValue): TJSONValue;
var
  mInitializeResult: TJSONObject;
  mCapabilities: TJSONObject;
  mServerInfo: TJSONObject;
begin
  FreeAndNil(FInitializeParams);
  if AParams is TJSONObject then
  begin
    FInitializeParams := TJSONObject(AParams.Clone);
  end;

  mCapabilities := nil;
  if Assigned(FCapabilities) then
  begin
    mCapabilities := FCapabilities();
  end;
  if mCapabilities = nil then
  begin
    mCapabilities := TJSONObject.Create;
  end;

  mServerInfo := TJSONObject.Create;
  mServerInfo.AddPair('name', FServerName);
  mServerInfo.AddPair('version', FServerVersion);

  mInitializeResult := TJSONObject.Create;
  mInitializeResult.AddPair('capabilities', mCapabilities);
  mInitializeResult.AddPair('serverInfo', mServerInfo);

  FState := TLspServerState.Running;
  Result := mInitializeResult;
end;

procedure TLspLifecycle.HandleInitialized(const AParams: TJSONValue);
begin
  // Der Client bestätigt die Initialisierung; jetzt dürfen Features den Arbeitsbereich laden.
  if Assigned(FOnInitialized) then
  begin
    FOnInitialized();
  end;
end;

function TLspLifecycle.HandleShutdown(const AParams: TJSONValue): TJSONValue;
begin
  FShutdownReceived := True;
  FState := TLspServerState.ShuttingDown;
  Result := TJSONNull.Create;
end;

procedure TLspLifecycle.HandleExit(const AParams: TJSONValue);
begin
  FState := TLspServerState.Exited;
  if Assigned(FOnExit) then
  begin
    FOnExit();
  end;
end;

function TLspLifecycle.GetExitCode: Integer;
begin
  if FShutdownReceived then
  begin
    Result := 0;
  end
  else
  begin
    Result := 1;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.Lifecycle', cTexts);

end.
