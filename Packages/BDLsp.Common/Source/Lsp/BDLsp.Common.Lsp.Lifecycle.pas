unit BDLsp.Common.Lsp.Lifecycle;

// Lebenszyklus eines Language Servers: initialize, initialized, shutdown, exit.
// Hängt sich als Guard und mit eigenen Handlern an einen JSON-RPC-Dispatcher
// und weist Nachrichten ab, die im aktuellen Zustand nicht erlaubt sind.

interface

uses
  System.SysUtils,
  System.JSON,
  BDLsp.Common.JsonRpc.Contract,
  BDLsp.Common.JsonRpc.Dispatcher,
  BDLsp.Common.Lsp.Contract;

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
  end;

implementation

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
  ADispatcher.RegisterRequest(TLspLifecycleMethod.InitializeRequest, HandleInitialize);
  ADispatcher.RegisterNotification(TLspLifecycleMethod.InitializedNotification, HandleInitialized);
  ADispatcher.RegisterRequest(TLspLifecycleMethod.ShutdownRequest, HandleShutdown);
  ADispatcher.RegisterNotification(TLspLifecycleMethod.ExitNotification, HandleExit);
  ADispatcher.Guard := CheckState;
end;

procedure TLspLifecycle.CheckState(const AMethod: string; AIsRequest: Boolean);
begin
  // exit ist in jedem Zustand erlaubt.
  if AMethod = TLspLifecycleMethod.ExitNotification then
    Exit;

  case FState of
    TLspServerState.Uninitialized:
      if AMethod <> TLspLifecycleMethod.InitializeRequest then
        raise EJsonRpcError.Create(TLspErrorCode.ServerNotInitialized, 'Server ist noch nicht initialisiert');
    TLspServerState.Running:
      if AMethod = TLspLifecycleMethod.InitializeRequest then
        raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidRequest, 'Server ist bereits initialisiert');
    TLspServerState.ShuttingDown:
      raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidRequest, 'Server wird beendet');
    TLspServerState.Exited:
      raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidRequest, 'Server ist beendet');
  end;
end;

function TLspLifecycle.HandleInitialize(const AParams: TJSONValue): TJSONValue;
var
  InitializeResult: TJSONObject;
  Capabilities: TJSONObject;
  ServerInfo: TJSONObject;
begin
  FreeAndNil(FInitializeParams);
  if AParams is TJSONObject then
    FInitializeParams := TJSONObject(AParams.Clone);

  Capabilities := nil;
  if Assigned(FCapabilities) then
    Capabilities := FCapabilities();
  if Capabilities = nil then
    Capabilities := TJSONObject.Create;

  ServerInfo := TJSONObject.Create;
  ServerInfo.AddPair('name', FServerName);
  ServerInfo.AddPair('version', FServerVersion);

  InitializeResult := TJSONObject.Create;
  InitializeResult.AddPair('capabilities', Capabilities);
  InitializeResult.AddPair('serverInfo', ServerInfo);

  FState := TLspServerState.Running;
  Result := InitializeResult;
end;

procedure TLspLifecycle.HandleInitialized(const AParams: TJSONValue);
begin
  // Der Client bestätigt die Initialisierung; hier gibt es vorerst nichts zu tun.
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
    FOnExit();
end;

function TLspLifecycle.GetExitCode: Integer;
begin
  if FShutdownReceived then
    Result := 0
  else
    Result := 1;
end;

end.
