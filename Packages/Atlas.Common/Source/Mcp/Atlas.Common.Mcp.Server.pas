unit Atlas.Common.Mcp.Server;

// Model Context Protocol (#48): Werkzeugverwaltung und Methoden des
// Protokolls auf dem vorhandenen JSON-RPC-Dispatcher.
//
//   initialize                 Version, Fähigkeiten (nur tools), Serverinfo
//   notifications/initialized  ohne Wirkung
//   ping                       leeres Ergebnis
//   tools/list                 alle registrierten Werkzeuge mit Schema
//   tools/call                 {name, arguments} → {content:[{type:"text"}], isError}
//   resources/list, resources/read  Ressourcen als Text (#272)
//   resources/templates/list   leere Liste: Atlas hat keine Ressourcenvorlagen (#1125)
//
// Sicherheit (#99): Werkzeuge sind lesend, schreibend oder starten Prozesse.
// Abgeschaltete Werkzeuge (mcp.disabledTools) und im eingeschränkten Modus
// (--restricted, #186) alle nicht lesenden fehlen in tools/list; ein Aufruf
// ergibt isError mit Begründung. Jeder nicht lesende Aufruf geht mit Werkzeug
// und Parametern an OnAudit; die Werkzeuge melden geänderte Dateien selbst
// über Audit.
//
// Werkzeuge liefern Text. Fachliche Fehler (Symbol nicht gefunden, fehlender
// Parameter) melden sie mit EMcpToolError; sie gehen als isError=true an das
// Modell, damit es die Anfrage korrigieren kann.

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Dispatcher;

type
  /// <summary>Fachlicher Fehler eines Werkzeugs; wird zu isError=true.</summary>
  EMcpToolError = class(Exception);

  /// <summary>AArguments kann nil sein und gehört dem Aufrufer.</summary>
  TMcpToolHandler = reference to function(const AArguments: TJSONObject): string;

  {$SCOPEDENUMS ON}
  /// <summary>Lesend, schreibend (Dateien) oder mit Prozessstart (#99).</summary>
  TMcpToolKind = (Read, Write, Process);
  {$SCOPEDENUMS OFF}

  TMcpTool = record
    Name: string;
    Description: string;
    /// <summary>JSON-Schema der Argumente als Text.</summary>
    InputSchema: string;
    Handler: TMcpToolHandler;
    Kind: TMcpToolKind;
  end;

  TMcpResource = record
    Uri: string;
    Name: string;
    Description: string;
    MimeType: string;
    Handler: TFunc<string>;
  end;

  TMcpServer = class
  public const
    DefaultProtocolVersion = '2025-06-18';
    InitializeMethod = 'initialize';
    InitializedMethod = 'notifications/initialized';
    PingMethod = 'ping';
    ListToolsMethod = 'tools/list';
    CallToolMethod = 'tools/call';
    ListResourcesMethod = 'resources/list';
    ReadResourceMethod = 'resources/read';
    ListResourceTemplatesMethod = 'resources/templates/list';
  private
    FName: string;
    FVersion: string;
    FInstructions: string;
    FTools: TList<TMcpTool>;
    FOnBeforeToolCall: TProc;
    FResources: TList<TMcpResource>;
    FRestricted: Boolean;
    FOnDisabledTools: TFunc<TArray<string>>;
    FOnAudit: TProc<string>;
    function FindTool(const AName: string; out ATool: TMcpTool): Boolean;
  public
    constructor Create(const AName, AVersion: string);
    destructor Destroy; override;
    procedure AddTool(const AName, ADescription, AInputSchema: string; const AHandler: TMcpToolHandler;
      AKind: TMcpToolKind = TMcpToolKind.Read);
    procedure AddResource(const AUri, AName, ADescription, AMimeType: string; const AHandler: TFunc<string>);
    /// <summary>Angeboten? Nicht abgeschaltet und im eingeschränkten Modus nur lesend.</summary>
    function Available(const ATool: TMcpTool): Boolean;
    /// <summary>Eintrag ins Protokoll schreibender Aufrufe (#99).</summary>
    procedure Audit(const AText: string);
    function ListResources: TJSONObject;
    /// <summary>EJsonRpcError(InvalidParams) bei unbekannter Ressource.</summary>
    function ReadResource(const AParams: TJSONValue): TJSONObject;
    /// <summary>Immer leer. Clients wie der MCP Inspector fragen die Vorlagen ab, sobald der Server
    /// resources anbietet; ohne Methode sähen sie einen Fehler (#1125).</summary>
    function ListResourceTemplates: TJSONObject;
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
    /// <summary>Eingeschränkter Modus (#186): nur lesende Werkzeuge.</summary>
    property Restricted: Boolean read FRestricted write FRestricted;
    /// <summary>Abgeschaltete Werkzeuge (mcp.disabledTools), bei jedem Aufruf neu gelesen.</summary>
    property OnDisabledTools: TFunc<TArray<string>> read FOnDisabledTools write FOnDisabledTools;
    property OnAudit: TProc<string> read FOnAudit write FOnAudit;
  end;

implementation

uses
  Atlas.Common.JsonRpc.Contract;

{ TMcpServer }

constructor TMcpServer.Create(const AName, AVersion: string);
begin
  inherited Create;
  FName := AName;
  FVersion := AVersion;
  FTools := TList<TMcpTool>.Create;
  FResources := TList<TMcpResource>.Create;
end;

destructor TMcpServer.Destroy;
begin
  FResources.Free;
  FTools.Free;
  inherited;
end;

procedure TMcpServer.AddTool(const AName, ADescription, AInputSchema: string; const AHandler: TMcpToolHandler;
  AKind: TMcpToolKind);
var
  Tool: TMcpTool;
begin
  Tool.Name := AName;
  Tool.Description := ADescription;
  Tool.InputSchema := AInputSchema;
  Tool.Handler := AHandler;
  Tool.Kind := AKind;
  FTools.Add(Tool);
end;

procedure TMcpServer.AddResource(const AUri, AName, ADescription, AMimeType: string; const AHandler: TFunc<string>);
var
  Resource: TMcpResource;
begin
  Resource.Uri := AUri;
  Resource.Name := AName;
  Resource.Description := ADescription;
  Resource.MimeType := AMimeType;
  Resource.Handler := AHandler;
  FResources.Add(Resource);
end;

function TMcpServer.Available(const ATool: TMcpTool): Boolean;
var
  Name: string;
begin
  if FRestricted and (ATool.Kind <> TMcpToolKind.Read) then
    Exit(False);
  if Assigned(FOnDisabledTools) then
    for Name in FOnDisabledTools() do
      if SameText(Trim(Name), ATool.Name) then
        Exit(False);
  Result := True;
end;

procedure TMcpServer.Audit(const AText: string);
begin
  if Assigned(FOnAudit) then
    FOnAudit(AText);
end;

function TMcpServer.ListResources: TJSONObject;
var
  Items: TJSONArray;
  Item: TJSONObject;
  Resource: TMcpResource;
begin
  Items := TJSONArray.Create;
  for Resource in FResources do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('uri', Resource.Uri);
    Item.AddPair('name', Resource.Name);
    Item.AddPair('description', Resource.Description);
    Item.AddPair('mimeType', Resource.MimeType);
    Items.Add(Item);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('resources', Items);
end;

function TMcpServer.ReadResource(const AParams: TJSONValue): TJSONObject;
var
  Uri: string;
  Resource: TMcpResource;
  Contents: TJSONArray;
  Item: TJSONObject;
begin
  if not (AParams is TJSONObject) or not (TJSONObject(AParams).GetValue('uri') is TJSONString) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'uri fehlt');
  Uri := TJSONObject(AParams).GetValue('uri').Value;
  for Resource in FResources do
    if SameText(Resource.Uri, Uri) then
    begin
      if Assigned(FOnBeforeToolCall) then
        FOnBeforeToolCall();
      Item := TJSONObject.Create;
      Item.AddPair('uri', Resource.Uri);
      Item.AddPair('mimeType', Resource.MimeType);
      Item.AddPair('text', Resource.Handler());
      Contents := TJSONArray.Create;
      Contents.Add(Item);
      Result := TJSONObject.Create;
      Result.AddPair('contents', Contents);
      Exit;
    end;
  raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, Format('Unbekannte Ressource "%s"', [Uri]));
end;

function TMcpServer.ListResourceTemplates: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('resourceTemplates', TJSONArray.Create);
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
  ADispatcher.RegisterRequest(ListResourcesMethod,
    function(const AParams: TJSONValue): TJSONValue
    begin
      Result := ListResources;
    end);
  ADispatcher.RegisterRequest(ReadResourceMethod,
    function(const AParams: TJSONValue): TJSONValue
    begin
      Result := ReadResource(AParams);
    end);
  ADispatcher.RegisterRequest(ListResourceTemplatesMethod,
    function(const AParams: TJSONValue): TJSONValue
    begin
      Result := ListResourceTemplates;
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
  if FResources.Count > 0 then
    Capabilities.AddPair('resources', TJSONObject.Create);
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
    if not Available(Tool) then
      Continue;
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
  if not Available(Tool) then
  begin
    if FRestricted and (Tool.Kind <> TMcpToolKind.Read) then
      Text := Format('Werkzeug "%s" ist im eingeschränkten Modus aus (nur lesende Werkzeuge).', [Name])
    else
      Text := Format('Werkzeug "%s" ist in atlas.json abgeschaltet (mcp.disabledTools).', [Name]);
    IsError := True;
  end
  else
  try
    if Tool.Kind <> TMcpToolKind.Read then
    begin
      if Arguments <> nil then
        Audit(Format('MCP %s %s', [Name, Arguments.ToJSON]))
      else
        Audit(Format('MCP %s', [Name]));
    end;
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
