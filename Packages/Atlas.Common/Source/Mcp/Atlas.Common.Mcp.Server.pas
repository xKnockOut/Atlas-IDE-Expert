unit Atlas.Common.Mcp.Server;

// Model Context Protocol (#48): Werkzeugverwaltung und Methoden des
// Protokolls auf dem vorhandenen JSON-RPC-Dispatcher.
//
//   initialize                 Version, Fähigkeiten (nur tools), Serverinfo
//   notifications/initialized  ohne Wirkung
//   ping                       leeres Ergebnis
//   tools/list                 alle registrierten Werkzeuge mit Schema
//   tools/call                 {name, arguments} → {content:[{type:"text"}], isError}
//   resources/list, resources/read  Ressourcen als Text (#272), auch über Vorlagen
//   resources/templates/list   Ressourcenvorlagen wie delphi://unit/{name} (#1357)
//   prompts/list, prompts/get  fertige Arbeitsabläufe, in Claude Code Schrägstrich-Befehle (#1357)
//
// Prompts, Vorlagen und Ressourcen, die zu ihnen gehören (AddPromptResource),
// gibt es nur, solange OnPromptsEnabled True liefert (mcp.prompts);
// sonst sind prompts/list und resources/templates/list leer. Ein Prompt holt
// seine Daten über InvokeTool von denselben Werkzeugen wie tools/call, mit
// denselben Regeln: abgeschaltete und im eingeschränkten Modus nicht lesende
// Werkzeuge liefert er nicht.
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
    /// <summary>Nur angeboten, solange Prompts an sind (#1357), z. B. delphi://build/last.</summary>
    WithPrompts: Boolean;
  end;

  /// <summary>AValue: Wert der Variablen aus der URI, dekodiert und nicht leer. Fachliche Fehler (Unit nicht
  /// gefunden, Pfad außerhalb des Arbeitsbereichs) mit EMcpToolError; sie werden zum JSON-RPC-Fehler.</summary>
  TMcpTemplateHandler = reference to function(const AValue: string): string;

  /// <summary>Ressourcenvorlage nach RFC 6570 mit genau einer Variablen, z. B. delphi://unit/{name} (#1357).
  /// </summary>
  TMcpResourceTemplate = record
    UriTemplate: string;
    Name: string;
    Description: string;
    MimeType: string;
    Handler: TMcpTemplateHandler;
    /// <summary>Passt AUri zur Vorlage? AValue ist dann der Wert der Variablen, %XX dekodiert (UTF-8).</summary>
    function Match(const AUri: string; out AValue: string): Boolean;
  end;

  TMcpPromptArgument = record
    Name: string;
    Description: string;
    Required: Boolean;
    class function Create(const AName, ADescription: string; ARequired: Boolean): TMcpPromptArgument; static;
  end;

  /// <summary>AArguments: Argumente aus prompts/get als Text, ohne Leerraum am Rand, leere fehlen; gehört dem
  /// Aufrufer. Liefert den Text der Nachricht. Fachliche Fehler mit EMcpToolError.</summary>
  TMcpPromptHandler = reference to function(const AArguments: TDictionary<string, string>): string;

  TMcpPrompt = record
    Name: string;
    Description: string;
    Arguments: TArray<TMcpPromptArgument>;
    Handler: TMcpPromptHandler;
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
    ListPromptsMethod = 'prompts/list';
    GetPromptMethod = 'prompts/get';
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
    FPrompts: TList<TMcpPrompt>;
    FTemplates: TList<TMcpResourceTemplate>;
    FOnPrompts: TFunc<TArray<TMcpPrompt>>;
    FOnPromptsEnabled: TFunc<Boolean>;
    function FindTool(const AName: string; out ATool: TMcpTool): Boolean;
    function FindPrompt(const AName: string; out APrompt: TMcpPrompt): Boolean;
    /// <summary>Text des Werkzeugs; True bei isError (abgeschaltet, eingeschränkt, EMcpToolError).</summary>
    function Execute(const ATool: TMcpTool; const AArguments: TJSONObject; out AText: string): Boolean;
    function ResourceText(const AUri, AMimeType, AText: string): TJSONObject;
  public
    constructor Create(const AName, AVersion: string);
    destructor Destroy; override;
    procedure AddTool(const AName, ADescription, AInputSchema: string; const AHandler: TMcpToolHandler;
      AKind: TMcpToolKind = TMcpToolKind.Read);
    procedure AddResource(const AUri, AName, ADescription, AMimeType: string; const AHandler: TFunc<string>);
    /// <summary>Wie AddResource, aber nur angeboten, solange Prompts an sind (#1357).</summary>
    procedure AddPromptResource(const AUri, AName, ADescription, AMimeType: string; const AHandler: TFunc<string>);
    /// <summary>Ressourcenvorlage mit genau einer Variablen in geschweiften Klammern (#1357).</summary>
    procedure AddResourceTemplate(const AUriTemplate, AName, ADescription, AMimeType: string;
      const AHandler: TMcpTemplateHandler);
    procedure AddPrompt(const APrompt: TMcpPrompt);
    /// <summary>Prompts und Vorlagen an (OnPromptsEnabled, ohne Ereignis an).</summary>
    function PromptsEnabled: Boolean;
    /// <summary>Angebotene Prompts: die registrierten, dann die aus OnPrompts ohne doppelte Namen; leer, wenn
    /// Prompts aus sind.</summary>
    function Prompts: TArray<TMcpPrompt>;
    /// <summary>Werkzeug AName gibt es und es ist angeboten (Available).</summary>
    function ToolAvailable(const AName: string): Boolean;
    /// <summary>Ruft ein Werkzeug für einen Prompt auf, mit den Regeln von tools/call, aber ohne
    /// OnBeforeToolCall. False mit Begründung in AText, wenn es fehlt, nicht angeboten ist oder einen
    /// fachlichen Fehler meldet. AArguments kann nil sein und gehört dem Aufrufer.</summary>
    function InvokeTool(const AName: string; const AArguments: TJSONObject; out AText: string): Boolean;
    function ListPrompts: TJSONObject;
    /// <summary>EJsonRpcError(InvalidParams) bei unbekanntem Prompt, fehlendem Pflichtargument, abgeschalteten
    /// Prompts oder fachlichem Fehler.</summary>
    function GetPrompt(const AParams: TJSONValue): TJSONObject;
    /// <summary>Angeboten? Nicht abgeschaltet und im eingeschränkten Modus nur lesend.</summary>
    function Available(const ATool: TMcpTool): Boolean;
    /// <summary>Eintrag ins Protokoll schreibender Aufrufe (#99).</summary>
    procedure Audit(const AText: string);
    function ListResources: TJSONObject;
    /// <summary>EJsonRpcError(InvalidParams) bei unbekannter Ressource.</summary>
    function ReadResource(const AParams: TJSONValue): TJSONObject;
    /// <summary>Text der festen Ressource AUri für einen Prompt, ohne OnBeforeToolCall; False, wenn es sie nicht gibt.
    /// </summary>
    function ReadResourceText(const AUri: string; out AText: string): Boolean;
    /// <summary>Die Ressourcenvorlagen; leer, wenn Prompts aus sind. Clients wie der MCP Inspector fragen die
    /// Vorlagen ab, sobald der Server resources anbietet; ohne Methode sähen sie einen Fehler (#1125).</summary>
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
    /// <summary>Weitere Prompts, bei jedem Aufruf neu gelesen, z. B. mcp.customPrompts aus atlas.json.</summary>
    property OnPrompts: TFunc<TArray<TMcpPrompt>> read FOnPrompts write FOnPrompts;
    /// <summary>mcp.prompts, bei jedem Aufruf neu gelesen; ohne Ereignis an.</summary>
    property OnPromptsEnabled: TFunc<Boolean> read FOnPromptsEnabled write FOnPromptsEnabled;
  end;

implementation

uses
  Atlas.Text.Uris,
  Atlas.Common.JsonRpc.Contract;

{ TMcpResourceTemplate }

function TMcpResourceTemplate.Match(const AUri: string; out AValue: string): Boolean;
var
  mOpen, mClose: Integer;
  mPrefix, mSuffix: string;
begin
  AValue := '';
  mOpen := Pos('{', UriTemplate);
  mClose := Pos('}', UriTemplate);
  Result := (mOpen > 0) and (mClose > mOpen);
  if not Result then
    Exit;
  mPrefix := Copy(UriTemplate, 1, mOpen - 1);
  mSuffix := Copy(UriTemplate, mClose + 1, MaxInt);
  Result := (Length(AUri) > Length(mPrefix) + Length(mSuffix)) and SameText(Copy(AUri, 1, Length(mPrefix)), mPrefix)
    and SameText(Copy(AUri, Length(AUri) - Length(mSuffix) + 1, Length(mSuffix)), mSuffix);
  if Result then
  begin
    AValue := Trim(TTextUris.PercentDecode(Copy(AUri, Length(mPrefix) + 1, Length(AUri) - Length(mPrefix) -
      Length(mSuffix))));
    Result := AValue <> '';
  end;
end;

{ TMcpPromptArgument }

class function TMcpPromptArgument.Create(const AName, ADescription: string; ARequired: Boolean): TMcpPromptArgument;
begin
  Result.Name := AName;
  Result.Description := ADescription;
  Result.Required := ARequired;
end;

{ TMcpServer }

constructor TMcpServer.Create(const AName, AVersion: string);
begin
  inherited Create;
  FName := AName;
  FVersion := AVersion;
  FTools := TList<TMcpTool>.Create;
  FResources := TList<TMcpResource>.Create;
  FPrompts := TList<TMcpPrompt>.Create;
  FTemplates := TList<TMcpResourceTemplate>.Create;
end;

destructor TMcpServer.Destroy;
begin
  FTemplates.Free;
  FPrompts.Free;
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

function NewResource(const AUri, AName, ADescription, AMimeType: string; const AHandler: TFunc<string>;
  AWithPrompts: Boolean): TMcpResource;
begin
  Result.Uri := AUri;
  Result.Name := AName;
  Result.Description := ADescription;
  Result.MimeType := AMimeType;
  Result.Handler := AHandler;
  Result.WithPrompts := AWithPrompts;
end;

procedure TMcpServer.AddResource(const AUri, AName, ADescription, AMimeType: string; const AHandler: TFunc<string>);
begin
  FResources.Add(NewResource(AUri, AName, ADescription, AMimeType, AHandler, False));
end;

procedure TMcpServer.AddPromptResource(const AUri, AName, ADescription, AMimeType: string;
  const AHandler: TFunc<string>);
begin
  FResources.Add(NewResource(AUri, AName, ADescription, AMimeType, AHandler, True));
end;

procedure TMcpServer.AddResourceTemplate(const AUriTemplate, AName, ADescription, AMimeType: string;
  const AHandler: TMcpTemplateHandler);
var
  mTemplate: TMcpResourceTemplate;
begin
  mTemplate.UriTemplate := AUriTemplate;
  mTemplate.Name := AName;
  mTemplate.Description := ADescription;
  mTemplate.MimeType := AMimeType;
  mTemplate.Handler := AHandler;
  FTemplates.Add(mTemplate);
end;

procedure TMcpServer.AddPrompt(const APrompt: TMcpPrompt);
begin
  FPrompts.Add(APrompt);
end;

function TMcpServer.PromptsEnabled: Boolean;
begin
  Result := not Assigned(FOnPromptsEnabled) or FOnPromptsEnabled();
end;

function TMcpServer.Prompts: TArray<TMcpPrompt>;
var
  mPrompt, mKnown: TMcpPrompt;
  mDuplicate: Boolean;
begin
  Result := nil;
  if not PromptsEnabled then
    Exit;
  Result := FPrompts.ToArray;
  if not Assigned(FOnPrompts) then
    Exit;
  for mPrompt in FOnPrompts() do
  begin
    // Eingebaute Namen gehen vor: Ein eigener Prompt kann keinen eingebauten verdecken.
    mDuplicate := False;
    for mKnown in Result do
      if SameText(mKnown.Name, mPrompt.Name) then
        mDuplicate := True;
    if not mDuplicate then
      Result := Result + [mPrompt];
  end;
end;

function TMcpServer.FindPrompt(const AName: string; out APrompt: TMcpPrompt): Boolean;
var
  mPrompt: TMcpPrompt;
begin
  for mPrompt in Prompts do
    if mPrompt.Name = AName then
    begin
      APrompt := mPrompt;
      Exit(True);
    end;
  Result := False;
end;

function TMcpServer.ToolAvailable(const AName: string): Boolean;
var
  mTool: TMcpTool;
begin
  Result := FindTool(AName, mTool) and Available(mTool);
end;

function TMcpServer.InvokeTool(const AName: string; const AArguments: TJSONObject; out AText: string): Boolean;
var
  mTool: TMcpTool;
begin
  if not FindTool(AName, mTool) then
  begin
    AText := Format('Werkzeug "%s" gibt es in diesem Server nicht.', [AName]);
    Exit(False);
  end;
  Result := not Execute(mTool, AArguments, AText);
end;

function TMcpServer.ListPrompts: TJSONObject;
var
  mItems, mArguments: TJSONArray;
  mItem, mArgument: TJSONObject;
  mPrompt: TMcpPrompt;
  mInfo: TMcpPromptArgument;
begin
  mItems := TJSONArray.Create;
  for mPrompt in Prompts do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('name', mPrompt.Name);
    mItem.AddPair('description', mPrompt.Description);
    mArguments := TJSONArray.Create;
    for mInfo in mPrompt.Arguments do
    begin
      mArgument := TJSONObject.Create;
      mArgument.AddPair('name', mInfo.Name);
      mArgument.AddPair('description', mInfo.Description);
      mArgument.AddPair('required', TJSONBool.Create(mInfo.Required));
      mArguments.Add(mArgument);
    end;
    mItem.AddPair('arguments', mArguments);
    mItems.Add(mItem);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('prompts', mItems);
end;

function TMcpServer.GetPrompt(const AParams: TJSONValue): TJSONObject;
var
  mName, mText, mValue: string;
  mPrompt: TMcpPrompt;
  mInfo: TMcpPromptArgument;
  mArguments: TDictionary<string, string>;
  mGiven: TJSONObject;
  mPair: TJSONPair;
  mMessages: TJSONArray;
  mMessage, mContent: TJSONObject;
begin
  if not (AParams is TJSONObject) or not (TJSONObject(AParams).GetValue('name') is TJSONString) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Name des Prompts fehlt');
  mName := TJSONObject(AParams).GetValue('name').Value;
  if not PromptsEnabled then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Prompts sind abgeschaltet (mcp.prompts).');
  if not FindPrompt(mName, mPrompt) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, Format('Unbekannter Prompt "%s"', [mName]));
  mArguments := TDictionary<string, string>.Create;
  try
    if TJSONObject(AParams).GetValue('arguments') is TJSONObject then
    begin
      mGiven := TJSONObject(TJSONObject(AParams).GetValue('arguments'));
      for mPair in mGiven do
      begin
        if mPair.JsonValue is TJSONString then
          mValue := Trim(mPair.JsonValue.Value)
        else if mPair.JsonValue is TJSONNull then
          mValue := ''
        else
          mValue := Trim(mPair.JsonValue.ToJSON);
        if mValue <> '' then
          mArguments.AddOrSetValue(mPair.JsonString.Value, mValue);
      end;
    end;
    for mInfo in mPrompt.Arguments do
      if mInfo.Required and not mArguments.ContainsKey(mInfo.Name) then
        raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
          Format('Prompt "%s": Argument "%s" fehlt (%s)', [mName, mInfo.Name, mInfo.Description]));
    // Wie vor jedem Werkzeugaufruf: geänderte Units nachladen (#48), einmal für alle eingebetteten Werkzeuge.
    if Assigned(FOnBeforeToolCall) then
      FOnBeforeToolCall();
    try
      mText := mPrompt.Handler(mArguments);
    except
      on E: EMcpToolError do
        raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, E.Message);
    end;
  finally
    mArguments.Free;
  end;
  mContent := TJSONObject.Create;
  mContent.AddPair('type', 'text');
  mContent.AddPair('text', mText);
  mMessage := TJSONObject.Create;
  mMessage.AddPair('role', 'user');
  mMessage.AddPair('content', mContent);
  mMessages := TJSONArray.Create;
  mMessages.Add(mMessage);
  Result := TJSONObject.Create;
  Result.AddPair('description', mPrompt.Description);
  Result.AddPair('messages', mMessages);
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
    if Resource.WithPrompts and not PromptsEnabled then
      Continue;
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

function TMcpServer.ResourceText(const AUri, AMimeType, AText: string): TJSONObject;
var
  mContents: TJSONArray;
  mItem: TJSONObject;
begin
  mItem := TJSONObject.Create;
  mItem.AddPair('uri', AUri);
  mItem.AddPair('mimeType', AMimeType);
  mItem.AddPair('text', AText);
  mContents := TJSONArray.Create;
  mContents.Add(mItem);
  Result := TJSONObject.Create;
  Result.AddPair('contents', mContents);
end;

function TMcpServer.ReadResource(const AParams: TJSONValue): TJSONObject;
var
  Uri, mValue, mText: string;
  Resource: TMcpResource;
  mTemplate: TMcpResourceTemplate;
begin
  if not (AParams is TJSONObject) or not (TJSONObject(AParams).GetValue('uri') is TJSONString) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'uri fehlt');
  Uri := TJSONObject(AParams).GetValue('uri').Value;
  for Resource in FResources do
    if SameText(Resource.Uri, Uri) and (not Resource.WithPrompts or PromptsEnabled) then
    begin
      if Assigned(FOnBeforeToolCall) then
        FOnBeforeToolCall();
      Exit(ResourceText(Resource.Uri, Resource.MimeType, Resource.Handler()));
    end;
  if PromptsEnabled then
    for mTemplate in FTemplates do
      if mTemplate.Match(Uri, mValue) then
      begin
        if Assigned(FOnBeforeToolCall) then
          FOnBeforeToolCall();
        try
          mText := mTemplate.Handler(mValue);
        except
          // Mit Begründung an den Client, z. B. „liegt außerhalb des Arbeitsbereichs“ (#99).
          on E: EMcpToolError do
            raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, E.Message);
        end;
        Exit(ResourceText(Uri, mTemplate.MimeType, mText));
      end;
  raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, Format('Unbekannte Ressource "%s"', [Uri]));
end;

function TMcpServer.ReadResourceText(const AUri: string; out AText: string): Boolean;
var
  mResource: TMcpResource;
begin
  AText := '';
  for mResource in FResources do
    if SameText(mResource.Uri, AUri) and (not mResource.WithPrompts or PromptsEnabled) then
    begin
      AText := mResource.Handler();
      Exit(True);
    end;
  Result := False;
end;

function TMcpServer.ListResourceTemplates: TJSONObject;
var
  mItems: TJSONArray;
  mItem: TJSONObject;
  mTemplate: TMcpResourceTemplate;
begin
  mItems := TJSONArray.Create;
  if PromptsEnabled then
    for mTemplate in FTemplates do
    begin
      mItem := TJSONObject.Create;
      mItem.AddPair('uriTemplate', mTemplate.UriTemplate);
      mItem.AddPair('name', mTemplate.Name);
      mItem.AddPair('description', mTemplate.Description);
      mItem.AddPair('mimeType', mTemplate.MimeType);
      mItems.Add(mItem);
    end;
  Result := TJSONObject.Create;
  Result.AddPair('resourceTemplates', mItems);
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
  ADispatcher.RegisterRequest(ListPromptsMethod,
    function(const AParams: TJSONValue): TJSONValue
    begin
      Result := ListPrompts;
    end);
  ADispatcher.RegisterRequest(GetPromptMethod,
    function(const AParams: TJSONValue): TJSONValue
    begin
      Result := GetPrompt(AParams);
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
  if (FResources.Count > 0) or (FTemplates.Count > 0) then
    Capabilities.AddPair('resources', TJSONObject.Create);
  // Immer melden, wenn es Prompts geben kann: Clients fragen die Liste sonst nie ab, auch wenn mcp.prompts
  // später eingeschaltet wird (#1357).
  if (FPrompts.Count > 0) or Assigned(FOnPrompts) then
    Capabilities.AddPair('prompts', TJSONObject.Create);
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

function TMcpServer.Execute(const ATool: TMcpTool; const AArguments: TJSONObject; out AText: string): Boolean;
begin
  Result := False;
  if not Available(ATool) then
  begin
    if FRestricted and (ATool.Kind <> TMcpToolKind.Read) then
      AText := Format('Werkzeug "%s" ist im eingeschränkten Modus aus (nur lesende Werkzeuge).', [ATool.Name])
    else
      AText := Format('Werkzeug "%s" ist in atlas.json abgeschaltet (mcp.disabledTools).', [ATool.Name]);
    Exit(True);
  end;
  try
    if ATool.Kind <> TMcpToolKind.Read then
    begin
      if AArguments <> nil then
        Audit(Format('MCP %s %s', [ATool.Name, AArguments.ToJSON]))
      else
        Audit(Format('MCP %s', [ATool.Name]));
    end;
    AText := ATool.Handler(AArguments);
  except
    on E: EMcpToolError do
    begin
      AText := E.Message;
      Result := True;
    end;
  end;
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
  // Z. B. geänderte Units nachladen (#48); ein Fehler dort trifft den Aufruf wie einer des Werkzeugs.
  try
    if Available(Tool) and Assigned(FOnBeforeToolCall) then
      FOnBeforeToolCall();
    IsError := Execute(Tool, Arguments, Text);
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
