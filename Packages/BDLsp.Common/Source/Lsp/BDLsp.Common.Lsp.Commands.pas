unit BDLsp.Common.Lsp.Commands;

// Befehle des Servers über workspace/executeCommand (#28). Features melden
// ihre Befehle vor Attach an; die Capability nennt alle Namen.

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  BDLsp.Common.JsonRpc.Contract,
  BDLsp.Common.JsonRpc.Dispatcher;

type
  /// <summary>Führt einen Befehl aus; AArguments darf nil sein. Ergebnis geht an den Aufrufer.</summary>
  TLspCommandHandler = reference to function(const AArguments: TJSONArray): TJSONValue;

  TLspCommands = class
  public const
    Method = 'workspace/executeCommand';
  private
    FHandlers: TDictionary<string, TLspCommandHandler>;
    FNames: TList<string>;
    function HandleExecute(const AParams: TJSONValue): TJSONValue;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Register(const ACommand: string; const AHandler: TLspCommandHandler);
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>executeCommandProvider mit allen Befehlen. Der Aufrufer übernimmt das Objekt.</summary>
    function Capability: TJSONObject;
    /// <summary>Führt ACommand aus; EJsonRpcError bei unbekanntem Befehl.</summary>
    function Execute(const ACommand: string; const AArguments: TJSONArray): TJSONValue;
  end;

implementation

constructor TLspCommands.Create;
begin
  inherited Create;
  FHandlers := TDictionary<string, TLspCommandHandler>.Create;
  FNames := TList<string>.Create;
end;

destructor TLspCommands.Destroy;
begin
  FNames.Free;
  FHandlers.Free;
  inherited;
end;

procedure TLspCommands.Register(const ACommand: string; const AHandler: TLspCommandHandler);
begin
  if not FHandlers.ContainsKey(ACommand) then
    FNames.Add(ACommand);
  FHandlers.AddOrSetValue(ACommand, AHandler);
end;

procedure TLspCommands.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterRequest(Method, HandleExecute);
end;

function TLspCommands.Capability: TJSONObject;
var
  Commands: TJSONArray;
  Name: string;
begin
  Commands := TJSONArray.Create;
  for Name in FNames do
    Commands.Add(Name);
  Result := TJSONObject.Create;
  Result.AddPair('commands', Commands);
end;

function TLspCommands.Execute(const ACommand: string; const AArguments: TJSONArray): TJSONValue;
var
  Handler: TLspCommandHandler;
begin
  if not FHandlers.TryGetValue(ACommand, Handler) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Unbekannter Befehl: ' + ACommand);
  Result := Handler(AArguments);
  if Result = nil then
    Result := TJSONNull.Create;
end;

function TLspCommands.HandleExecute(const AParams: TJSONValue): TJSONValue;
var
  Command: string;
  Arguments: TJSONValue;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('command', Command)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Feld "command" fehlt in ' + Method);
  Arguments := TJSONObject(AParams).GetValue('arguments');
  if Arguments is TJSONArray then
    Result := Execute(Command, TJSONArray(Arguments))
  else
    Result := Execute(Command, nil);
end;

end.
