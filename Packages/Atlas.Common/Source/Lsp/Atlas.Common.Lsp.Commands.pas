unit Atlas.Common.Lsp.Commands;

// Befehle des Servers über workspace/executeCommand (#28). Features melden
// ihre Befehle vor Attach an; die Capability nennt alle Namen.
// Befehle aus RegisterConcurrent (#874) lesen nur und sind threadsicher: Sie
// laufen nebenläufig und warten nicht hinter einem Neuladen oder Indexstart
// in der Nachrichtenschleife. Alle anderen laufen weiter in der Reihenfolge
// der Nachrichten.

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher;

type
  /// <summary>Führt einen Befehl aus; AArguments darf nil sein. Ergebnis geht an den Aufrufer.</summary>
  TLspCommandHandler = reference to function(const AArguments: TJSONArray): TJSONValue;

  TLspCommands = class
  public const
    Method = 'workspace/executeCommand';
  private
    FHandlers: TDictionary<string, TLspCommandHandler>;
    FNames: TList<string>;
    FConcurrent: TDictionary<string, Boolean>;
    function HandleExecute(const AParams: TJSONValue): TJSONValue;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Register(const ACommand: string; const AHandler: TLspCommandHandler);
    /// <summary>Wie Register für einen threadsicheren Befehl, der nur liest; er läuft nebenläufig (#874).</summary>
    procedure RegisterConcurrent(const ACommand: string; const AHandler: TLspCommandHandler);
    /// <summary>Läuft AParams (Parameter von executeCommand) nebenläufig? False bei unbekanntem Befehl.</summary>
    function IsConcurrent(const AParams: TJSONValue): Boolean;
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
  FConcurrent := TDictionary<string, Boolean>.Create;
end;

destructor TLspCommands.Destroy;
begin
  FConcurrent.Free;
  FNames.Free;
  FHandlers.Free;
  inherited;
end;

procedure TLspCommands.Register(const ACommand: string; const AHandler: TLspCommandHandler);
begin
  if not FHandlers.ContainsKey(ACommand) then
    FNames.Add(ACommand);
  FHandlers.AddOrSetValue(ACommand, AHandler);
  FConcurrent.Remove(ACommand);
end;

procedure TLspCommands.RegisterConcurrent(const ACommand: string; const AHandler: TLspCommandHandler);
begin
  Register(ACommand, AHandler);
  FConcurrent.AddOrSetValue(ACommand, True);
end;

function TLspCommands.IsConcurrent(const AParams: TJSONValue): Boolean;
var
  Command: string;
begin
  Result := (AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('command', Command) and
    FConcurrent.ContainsKey(Command);
end;

procedure TLspCommands.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  // Nach Attach ändert sich FConcurrent nicht mehr; IsConcurrent liest nur.
  ADispatcher.RegisterConditionalRequest(Method, HandleExecute, IsConcurrent);
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
