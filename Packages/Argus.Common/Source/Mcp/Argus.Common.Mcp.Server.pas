unit Argus.Common.Mcp.Server;

// Model Context Protocol (#48): Werkzeugverwaltung und Methoden des
// Protokolls auf dem vorhandenen JSON-RPC-Dispatcher.
//
//   initialize                 Version, Fähigkeiten (nur tools), Serverinfo
//   notifications/initialized  ohne Wirkung
//   ping                       leeres Ergebnis
//   tools/list                 alle registrierten Werkzeuge mit Schema
//   tools/call                 {name, arguments} → {content:[{type:"text"}], isError}
//
// Werkzeuge liefern Text. Fachliche Fehler (Symbol nicht gefunden, fehlender
// Parameter) melden sie mit EMcpToolError; sie gehen als isError=true an das
// Modell, damit es die Anfrage korrigieren kann.

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Argus.Common.JsonRpc.Dispatcher;

type
  /// <summary>Fachlicher Fehler eines Werkzeugs; wird zu isError=true.</summary>
  EMcpToolError = class(Exception);

  /// <summary>AArguments kann nil sein und gehört dem Aufrufer.</summary>
  TMcpToolHandler = reference to function(const AArguments: TJSONObject): string;

  TMcpTool = record
    Name: string;
    Description: string;
    /// <summary>JSON-Schema der Argumente als Text.</summary>
    InputSchema: string;
    Handler: TMcpToolHandler;
  end;

  TMcpServer = class
  public const
    DefaultProtocolVersion = '2025-06-18';
    InitializeMethod = 'initialize';
    InitializedMethod = 'notifications/initialized';
    PingMethod = 'ping';
    ListToolsMethod = 'tools/list';
    CallToolMethod = 'tools/call';
  private
    FName: string;
    FVersion: string;
    FInstructions: string;
    FTools: TList<TMcpTool>;
    FOnBeforeToolCall: TProc;
    function FindTool(const AName: string; out ATool: TMcpTool): Boolean;
  public
    constructor Create(const AName, AVersion: string);
    destructor Destroy; override;
    procedure AddTool(const AName, ADescription, AInputSchema: string; const AHandler: TMcpToolHandler);
    /// <summary>Registriert die MCP-Methoden am Dispatcher.</summary>
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    function Initialize(const AParams: TJSONValue): TJSONObject;
    function ListTools: TJSONObject;
    /// <summary>EJsonRpcError(InvalidParams) bei unbekanntem Werkzeug.</summary>
    function CallTool(const AParams: TJSONValue): TJSONObject;
    /// <summary>Schema mit Pflichtparametern vom Typ string, z. B. StringSchema(['name'], ['Symbolname']).</summary>
    class function StringSchema(const ANames, ADescriptions: array of string; ARequired: Integer = -1): string; static;
    /// <summary>Pflichtargument als Text; EMcpToolError wenn es fehlt oder leer ist.</summary>
    class function RequiredString(const AArguments: TJSONObject; const AName: string): string; static;
    /// <summary>Optionales Argument als Text; '' wenn es fehlt.</summary>
    class function OptionalString(const AArguments: TJSONObject; const AName: string): string; static;
    /// <summary>Hinweis an das Modell in der Antwort auf initialize.</summary>
    property Instructions: string read FInstructions write FInstructions;
    /// <summary>Läuft vor jedem Werkzeugaufruf, z. B. um den Index aktuell zu halten (#48).</summary>
    property OnBeforeToolCall: TProc read FOnBeforeToolCall write FOnBeforeToolCall;
  end;

implementation

uses
  Argus.Common.JsonRpc.Contract;

{ TMcpServer }

constructor TMcpServer.Create(const AName, AVersion: string);
begin
  inherited Create;
  FName := AName;
  FVersion := AVersion;
  FTools := TList<TMcpTool>.Create;
end;

destructor TMcpServer.Destroy;
begin
  FTools.Free;
  inherited;
end;

procedure TMcpServer.AddTool(const AName, ADescription, AInputSchema: string; const AHandler: TMcpToolHandler);
var
  Tool: TMcpTool;
begin
  Tool.Name := AName;
  Tool.Description := ADescription;
  Tool.InputSchema := AInputSchema;
  Tool.Handler := AHandler;
  FTools.Add(Tool);
end;

function TMcpServer.FindTool(const AName: string; out ATool: TMcpTool): Boolean;
var
  Tool: TMcpTool;
begin
  for Tool in FTools do
    if Tool.Name = AName then
    begin
      ATool := Tool;
      Exit(True);
    end;
  Result := False;
end;

procedure TMcpServer.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterRequest(InitializeMethod,
    function(const AParams: TJSONValue): TJSONValue
    begin
      Result := Initialize(AParams);
    end);
  ADispatcher.RegisterNotification(InitializedMethod,
    procedure(const AParams: TJSONValue)
    begin
    end);
  ADispatcher.RegisterRequest(PingMethod,
    function(const AParams: TJSONValue): TJSONValue
    begin
      Result := TJSONObject.Create;
    end);
  ADispatcher.RegisterRequest(ListToolsMethod,
    function(const AParams: TJSONValue): TJSONValue
    begin
      Result := ListTools;
    end);
  ADispatcher.RegisterRequest(CallToolMethod,
    function(const AParams: TJSONValue): TJSONValue
    begin
      Result := CallTool(AParams);
    end);
end;

function TMcpServer.Initialize(const AParams: TJSONValue): TJSONObject;
var
  Version: string;
  Capabilities, Info: TJSONObject;
begin
  // Die vom Client gewünschte Version übernehmen; der Server nutzt nur Werkzeuge,
  // die in allen bisherigen Versionen gleich aussehen.
  Version := DefaultProtocolVersion;
  if (AParams is TJSONObject) and (TJSONObject(AParams).GetValue('protocolVersion') is TJSONString) then
    Version := TJSONObject(AParams).GetValue('protocolVersion').Value;
  Result := TJSONObject.Create;
  Result.AddPair('protocolVersion', Version);
  Capabilities := TJSONObject.Create;
  Capabilities.AddPair('tools', TJSONObject.Create);
  Result.AddPair('capabilities', Capabilities);
  Info := TJSONObject.Create;
  Info.AddPair('name', FName);
  Info.AddPair('version', FVersion);
  Result.AddPair('serverInfo', Info);
  if FInstructions <> '' then
    Result.AddPair('instructions', FInstructions);
end;

function TMcpServer.ListTools: TJSONObject;
var
  Tools: TJSONArray;
  Item: TJSONObject;
  Tool: TMcpTool;
  Schema: TJSONValue;
begin
  Tools := TJSONArray.Create;
  for Tool in FTools do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('name', Tool.Name);
    Item.AddPair('description', Tool.Description);
    Schema := TJSONObject.ParseJSONValue(Tool.InputSchema);
    if Schema = nil then
      Schema := TJSONObject.ParseJSONValue('{"type":"object"}');
    Item.AddPair('inputSchema', Schema);
    Tools.Add(Item);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('tools', Tools);
end;

function TMcpServer.CallTool(const AParams: TJSONValue): TJSONObject;
var
  Name, Text: string;
  Tool: TMcpTool;
  Arguments: TJSONObject;
  IsError: Boolean;
  Content: TJSONArray;
  Item: TJSONObject;
begin
  if not (AParams is TJSONObject) or not (TJSONObject(AParams).GetValue('name') is TJSONString) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Werkzeugname fehlt');
  Name := TJSONObject(AParams).GetValue('name').Value;
  if not FindTool(Name, Tool) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, Format('Unbekanntes Werkzeug "%s"', [Name]));
  Arguments := nil;
  if TJSONObject(AParams).GetValue('arguments') is TJSONObject then
    Arguments := TJSONObject(TJSONObject(AParams).GetValue('arguments'));
  IsError := False;
  try
    // Z. B. geänderte Units nachladen (#48); ein Fehler dort trifft den Aufruf wie einer des Werkzeugs.
    if Assigned(FOnBeforeToolCall) then
      FOnBeforeToolCall();
    Text := Tool.Handler(Arguments);
  except
    on E: EMcpToolError do
    begin
      Text := E.Message;
      IsError := True;
    end;
  end;
  Content := TJSONArray.Create;
  Item := TJSONObject.Create;
  Item.AddPair('type', 'text');
  Item.AddPair('text', Text);
  Content.Add(Item);
  Result := TJSONObject.Create;
  Result.AddPair('content', Content);
  Result.AddPair('isError', TJSONBool.Create(IsError));
end;

function JsonText(const AText: string): string;
var
  Value: TJSONString;
begin
  Value := TJSONString.Create(AText);
  try
    Result := Value.ToJSON;
  finally
    Value.Free;
  end;
end;

class function TMcpServer.StringSchema(const ANames, ADescriptions: array of string; ARequired: Integer): string;
var
  Index, Count: Integer;
  Properties, Required: string;
begin
  // ARequired = -1: alle Parameter sind Pflicht, sonst nur die ersten ARequired.
  Count := ARequired;
  if Count < 0 then
    Count := Length(ANames);
  Properties := '';
  Required := '';
  for Index := 0 to High(ANames) do
  begin
    if Properties <> '' then
      Properties := Properties + ',';
    Properties := Properties + JsonText(ANames[Index]) + ':{"type":"string","description":' +
      JsonText(ADescriptions[Index]) + '}';
    if Index < Count then
    begin
      if Required <> '' then
        Required := Required + ',';
      Required := Required + JsonText(ANames[Index]);
    end;
  end;
  Result := '{"type":"object","properties":{' + Properties + '},"required":[' + Required + ']}';
end;

class function TMcpServer.OptionalString(const AArguments: TJSONObject; const AName: string): string;
var
  Value: TJSONValue;
begin
  Result := '';
  if AArguments = nil then
    Exit;
  Value := AArguments.GetValue(AName);
  if (Value <> nil) and not (Value is TJSONNull) then
    Result := Trim(Value.Value);
end;

class function TMcpServer.RequiredString(const AArguments: TJSONObject; const AName: string): string;
begin
  Result := OptionalString(AArguments, AName);
  if Result = '' then
    raise EMcpToolError.CreateFmt('Parameter "%s" fehlt', [AName]);
end;

end.
