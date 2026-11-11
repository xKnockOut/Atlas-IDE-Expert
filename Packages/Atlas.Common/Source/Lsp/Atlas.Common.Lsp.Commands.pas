unit Atlas.Common.Lsp.Commands;

// Befehle des Servers über workspace/executeCommand (#28). Features melden
// ihre Befehle vor Attach an; die Capability nennt alle Namen.
// Befehle aus RegisterConcurrent (#874) lesen nur und sind threadsicher: Sie
// laufen nebenläufig und warten nicht hinter einem Neuladen oder Indexstart
// in der Nachrichtenschleife. Alle anderen laufen weiter in der Reihenfolge
// der Nachrichten.
// Abbruch: Läuft eine Anfrage in ihr Zeitlimit oder bricht der Client sie mit
// $/cancelRequest ab, signalisiert der Dispatcher ihr Token. Befehle, die lange
// rechnen (etwa ganze Dateien), melden sich mit RegisterCancellable bzw.
// RegisterConcurrentCancellable an und bekommen das Token als Parameter; sie
// prüfen es regelmäßig und enden mit RequestCancelled, statt nach der Antwort
// des Watchdogs weiter CPU zu belegen. Ohne laufende Anfrage (Execute direkt)
// ist das Token nil.

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
  /// <summary>Wie TLspCommandHandler, mit dem Abbruchsignal der Anfrage (nil ohne Anfrage). Der Handler prüft es
  /// regelmäßig und löst über ThrowIfCancellationRequested RequestCancelled aus.</summary>
  TLspCancellableCommandHandler = reference to function(const AArguments: TJSONArray;
    const ACancellation: IJsonRpcCancellationToken): TJSONValue;

  TLspCommands = class
  public const
    cMethod = 'workspace/executeCommand';
  private
    FHandlers: TDictionary<string, TLspCancellableCommandHandler>;
    FNames: TList<string>;
    FConcurrent: TDictionary<string, Boolean>;
    function HandleExecute(const AParams: TJSONValue): TJSONValue;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Register(const ACommand: string; const AHandler: TLspCommandHandler);
    /// <summary>Wie Register für einen threadsicheren Befehl, der nur liest; er läuft nebenläufig (#874).</summary>
    procedure RegisterConcurrent(const ACommand: string; const AHandler: TLspCommandHandler);
    /// <summary>Wie Register; der Handler bekommt das Abbruchsignal der Anfrage.</summary>
    procedure RegisterCancellable(const ACommand: string; const AHandler: TLspCancellableCommandHandler);
    /// <summary>Wie RegisterConcurrent; der Handler bekommt das Abbruchsignal der Anfrage.</summary>
    procedure RegisterConcurrentCancellable(const ACommand: string; const AHandler: TLspCancellableCommandHandler);
    /// <summary>Läuft AParams (Parameter von executeCommand) nebenläufig? False bei unbekanntem Befehl.</summary>
    function IsConcurrent(const AParams: TJSONValue): Boolean;
    /// <summary>Ist ACommand mit RegisterConcurrent angemeldet?</summary>
    function IsConcurrentCommand(const ACommand: string): Boolean;
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>executeCommandProvider mit allen Befehlen. Der Aufrufer übernimmt das Objekt.</summary>
    function Capability: TJSONObject;
    /// <summary>Führt ACommand mit dem Abbruchsignal der laufenden Anfrage aus (TJsonRpcCurrentRequest, nil ohne);
    /// EJsonRpcError bei unbekanntem Befehl.</summary>
    function Execute(const ACommand: string; const AArguments: TJSONArray): TJSONValue; overload;
    /// <summary>Wie oben mit dem Abbruchsignal ACancellation.</summary>
    function Execute(const ACommand: string; const AArguments: TJSONArray;
      const ACancellation: IJsonRpcCancellationToken): TJSONValue; overload;
  end;

implementation

uses
  Atlas.Common.JsonRpc.CurrentRequest,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TCommandsText = (FieldCommandMissingIn, UnknownCommand);

const
  cTexts: array[TCommandsText] of TAtlasText = (
    (De: 'Feld "command" fehlt in '; En: 'Field "command" missing in '),
    (De: 'Unbekannter Befehl: '; En: 'Unknown command: '));

{$SCOPEDENUMS OFF}

constructor TLspCommands.Create;
begin
  inherited Create;
  FHandlers := TDictionary<string, TLspCancellableCommandHandler>.Create;
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

/// <summary>AHandler in der Form eines Handlers mit Abbruchsignal; das Signal fragen dann nur tiefe Aufrufe über
/// TJsonRpcCurrentRequest.</summary>
function Cancellable(const AHandler: TLspCommandHandler): TLspCancellableCommandHandler;
var
  mHandler: TLspCommandHandler;
begin
  mHandler := AHandler;
  Result :=
    function(const AArguments: TJSONArray; const ACancellation: IJsonRpcCancellationToken): TJSONValue
    begin
      Result := mHandler(AArguments);
    end;
end;

procedure TLspCommands.Register(const ACommand: string; const AHandler: TLspCommandHandler);
begin
  RegisterCancellable(ACommand, Cancellable(AHandler));
end;

procedure TLspCommands.RegisterConcurrent(const ACommand: string; const AHandler: TLspCommandHandler);
begin
  RegisterConcurrentCancellable(ACommand, Cancellable(AHandler));
end;

procedure TLspCommands.RegisterCancellable(const ACommand: string; const AHandler: TLspCancellableCommandHandler);
begin
  if not FHandlers.ContainsKey(ACommand) then
  begin
    FNames.Add(ACommand);
  end;
  FHandlers.AddOrSetValue(ACommand, AHandler);
  FConcurrent.Remove(ACommand);
end;

procedure TLspCommands.RegisterConcurrentCancellable(const ACommand: string;
  const AHandler: TLspCancellableCommandHandler);
begin
  RegisterCancellable(ACommand, AHandler);
  FConcurrent.AddOrSetValue(ACommand, True);
end;

function TLspCommands.IsConcurrent(const AParams: TJSONValue): Boolean;
var
  mCommand: string;
begin
  Result := (AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('command', mCommand) and
    IsConcurrentCommand(mCommand);
end;

function TLspCommands.IsConcurrentCommand(const ACommand: string): Boolean;
begin
  Result := FConcurrent.ContainsKey(ACommand);
end;

procedure TLspCommands.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  // Nach Attach ändert sich FConcurrent nicht mehr; IsConcurrent liest nur.
  ADispatcher.RegisterConditionalRequest(cMethod, HandleExecute, IsConcurrent);
end;

function TLspCommands.Capability: TJSONObject;
var
  mCommands: TJSONArray;
  mName: string;
begin
  mCommands := TJSONArray.Create;
  for mName in FNames do
  begin
    mCommands.Add(mName);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('commands', mCommands);
end;

function TLspCommands.Execute(const ACommand: string; const AArguments: TJSONArray): TJSONValue;
begin
  Result := Execute(ACommand, AArguments, TJsonRpcCurrentRequest.Token);
end;

function TLspCommands.Execute(const ACommand: string; const AArguments: TJSONArray;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  mHandler: TLspCancellableCommandHandler;
begin
  if not FHandlers.TryGetValue(ACommand, mHandler) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[TCommandsText.UnknownCommand].Text + ACommand);
  end;
  Result := mHandler(AArguments, ACancellation);
  if Result = nil then
  begin
    Result := TJSONNull.Create;
  end;
end;

function TLspCommands.HandleExecute(const AParams: TJSONValue): TJSONValue;
var
  mCommand: string;
  mArguments: TJSONValue;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('command', mCommand)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[TCommandsText.FieldCommandMissingIn].Text +
      cMethod);
  end;
  mArguments := TJSONObject(AParams).GetValue('arguments');
  if mArguments is TJSONArray then
  begin
    Result := Execute(mCommand, TJSONArray(mArguments));
  end
  else
  begin
    Result := Execute(mCommand, nil);
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.Commands', cTexts);

end.
