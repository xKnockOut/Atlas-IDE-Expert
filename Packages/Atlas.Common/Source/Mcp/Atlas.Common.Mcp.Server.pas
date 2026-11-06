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

  /// <summary>Name, Version und Hinweis des Servers für initialize.</summary>
  TMcpServerInfo = record
    Name: string;
    Version: string;
    Instructions: string;
  end;

  /// <summary>Was der Server anbietet; die Listen gehören TMcpServer.</summary>
  TMcpServerCatalog = record
    Tools: TList<TMcpTool>;
    Resources: TList<TMcpResource>;
    Prompts: TList<TMcpPrompt>;
    Templates: TList<TMcpResourceTemplate>;
  end;

  /// <summary>Ereignisse von TMcpServer (siehe die gleichnamigen Eigenschaften).</summary>
  TMcpServerEvents = record
    OnBeforeToolCall: TProc;
    OnDisabledTools: TFunc<TArray<string>>;
    OnAudit: TProc<string>;
    OnPrompts: TFunc<TArray<TMcpPrompt>>;
    OnPromptsEnabled: TFunc<Boolean>;
  end;

  TMcpServer = class
  public const
    cDefaultProtocolVersion = '2025-06-18';
  private
    FInfo: TMcpServerInfo;
    FCatalog: TMcpServerCatalog;
    FEvents: TMcpServerEvents;
    FRestricted: Boolean;
    /// <summary>Text des Werkzeugs; True bei isError (abgeschaltet, eingeschränkt, EMcpToolError).</summary>
    function Execute(const ATool: TMcpTool; const AArguments: TJSONObject; out AText: string): Boolean;
  public
    constructor Create(const AName, AVersion: string);
    destructor Destroy; override;
    procedure AddTool(const AName, ADescription, AInputSchema: string; const AHandler: TMcpToolHandler;
      AKind: TMcpToolKind); overload;
    /// <summary>Wie oben mit AKind = Read.</summary>
    procedure AddTool(const AName, ADescription, AInputSchema: string; const AHandler: TMcpToolHandler); overload;
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
    class function StringSchema(const ANames, ADescriptions: array of string; ARequired: Integer): string;
      overload; static;
    /// <summary>Wie oben mit ARequired = -1.</summary>
    class function StringSchema(const ANames, ADescriptions: array of string): string; overload; static;
    /// <summary>Pflichtargument als Text; EMcpToolError wenn es fehlt oder leer ist.</summary>
    class function RequiredString(const AArguments: TJSONObject; const AName: string): string; static;
    /// <summary>Optionales Argument als Text; '' wenn es fehlt.</summary>
    class function OptionalString(const AArguments: TJSONObject; const AName: string): string; static;
    /// <summary>Hinweis an das Modell in der Antwort auf initialize.</summary>
    property Instructions: string read FInfo.Instructions write FInfo.Instructions;
    /// <summary>Läuft vor jedem Werkzeugaufruf, z. B. um den Index aktuell zu halten (#48).</summary>
    property OnBeforeToolCall: TProc read FEvents.OnBeforeToolCall write FEvents.OnBeforeToolCall;
    /// <summary>Eingeschränkter Modus (#186): nur lesende Werkzeuge.</summary>
    property Restricted: Boolean read FRestricted write FRestricted;
    /// <summary>Abgeschaltete Werkzeuge (mcp.disabledTools), bei jedem Aufruf neu gelesen.</summary>
    property OnDisabledTools: TFunc<TArray<string>> read FEvents.OnDisabledTools write FEvents.OnDisabledTools;
    property OnAudit: TProc<string> read FEvents.OnAudit write FEvents.OnAudit;
    /// <summary>Weitere Prompts, bei jedem Aufruf neu gelesen, z. B. mcp.customPrompts aus atlas.json.</summary>
    property OnPrompts: TFunc<TArray<TMcpPrompt>> read FEvents.OnPrompts write FEvents.OnPrompts;
    /// <summary>mcp.prompts, bei jedem Aufruf neu gelesen; ohne Ereignis an.</summary>
    property OnPromptsEnabled: TFunc<Boolean> read FEvents.OnPromptsEnabled write FEvents.OnPromptsEnabled;
  end;

implementation

uses
  Atlas.Text.Uris,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Text.LogMarks,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TServerText = (ToolDoesNotExistIn, NameOfThePromptMissing, PromptArgumentMissing, PromptsAreSwitchedOffMcp,
    UriMissing, ToolIsOffInRestricted, ToolIsSwitchedOffIn, ToolNameMissing, ParameterMissing, UnknownPrompt,
    UnknownResource, UnknownTool);

const
  cTexts: array[TServerText] of TAtlasText = (
    (De: 'Werkzeug "%s" gibt es in diesem Server nicht.'; En: 'Tool "%s" does not exist in this server.'),
    (De: 'Name des Prompts fehlt'; En: 'Name of the prompt missing'),
    (De: 'Prompt "%s": Argument "%s" fehlt (%s)'; En: 'Prompt "%s": argument "%s" missing (%s)'),
    (De: 'Prompts sind abgeschaltet (mcp.prompts).'; En: 'Prompts are switched off (mcp.prompts).'),
    (De: 'uri fehlt'; En: 'uri missing'),
    (De: 'Werkzeug "%s" ist im eingeschränkten Modus aus (nur lesende Werkzeuge).';
     En: 'Tool "%s" is off in restricted mode (read-only tools only).'),
    (De: 'Werkzeug "%s" ist in atlas.json abgeschaltet (mcp.disabledTools).';
     En: 'Tool "%s" is switched off in atlas.json (mcp.disabledTools).'),
    (De: 'Werkzeugname fehlt'; En: 'Tool name missing'),
    (De: 'Parameter "%s" fehlt'; En: 'Parameter "%s" missing'),
    (De: 'Unbekannter Prompt "%s"'; En: 'Unknown prompt "%s"'),
    (De: 'Unbekannte Ressource "%s"'; En: 'Unknown resource "%s"'),
    (De: 'Unbekanntes Werkzeug "%s"'; En: 'Unknown tool "%s"'));

{$SCOPEDENUMS OFF}

const
  // Methoden des MCP-Protokolls.
  cInitializeMethod = 'initialize';
  cInitializedMethod = 'notifications/initialized';
  cPingMethod = 'ping';
  cListToolsMethod = 'tools/list';
  cCallToolMethod = 'tools/call';
  cListResourcesMethod = 'resources/list';
  cReadResourceMethod = 'resources/read';
  cListResourceTemplatesMethod = 'resources/templates/list';
  cListPromptsMethod = 'prompts/list';
  cGetPromptMethod = 'prompts/get';

function FindToolIn(ATools: TList<TMcpTool>; const AName: string; out ATool: TMcpTool): Boolean;
var
  mTool: TMcpTool;
begin
  ATool := Default(TMcpTool);
  for mTool in ATools do
  begin
    if mTool.Name = AName then
    begin
      ATool := mTool;
      Exit(True);
    end;
  end;
  Result := False;
end;

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
  begin
    Exit;
  end;
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
  FInfo.Name := AName;
  FInfo.Version := AVersion;
  FCatalog.Tools := TList<TMcpTool>.Create;
  FCatalog.Resources := TList<TMcpResource>.Create;
  FCatalog.Prompts := TList<TMcpPrompt>.Create;
  FCatalog.Templates := TList<TMcpResourceTemplate>.Create;
end;

destructor TMcpServer.Destroy;
begin
  FCatalog.Templates.Free;
  FCatalog.Prompts.Free;
  FCatalog.Resources.Free;
  FCatalog.Tools.Free;
  inherited;
end;

procedure TMcpServer.AddTool(const AName, ADescription, AInputSchema: string; const AHandler: TMcpToolHandler);
begin
  AddTool(AName, ADescription, AInputSchema, AHandler, TMcpToolKind.Read);
end;

procedure TMcpServer.AddTool(const AName, ADescription, AInputSchema: string; const AHandler: TMcpToolHandler;
  AKind: TMcpToolKind);
var
  mTool: TMcpTool;
begin
  mTool.Name := AName;
  mTool.Description := ADescription;
  mTool.InputSchema := AInputSchema;
  mTool.Handler := AHandler;
  mTool.Kind := AKind;
  FCatalog.Tools.Add(mTool);
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
  FCatalog.Resources.Add(NewResource(AUri, AName, ADescription, AMimeType, AHandler, False));
end;

procedure TMcpServer.AddPromptResource(const AUri, AName, ADescription, AMimeType: string;
  const AHandler: TFunc<string>);
begin
  FCatalog.Resources.Add(NewResource(AUri, AName, ADescription, AMimeType, AHandler, True));
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
  FCatalog.Templates.Add(mTemplate);
end;

procedure TMcpServer.AddPrompt(const APrompt: TMcpPrompt);
begin
  FCatalog.Prompts.Add(APrompt);
end;

function TMcpServer.PromptsEnabled: Boolean;
begin
  Result := not Assigned(FEvents.OnPromptsEnabled) or FEvents.OnPromptsEnabled();
end;

function TMcpServer.Prompts: TArray<TMcpPrompt>;
var
  mPrompt, mKnown: TMcpPrompt;
  mDuplicate: Boolean;
begin
  Result := nil;
  if not PromptsEnabled then
  begin
    Exit;
  end;
  Result := FCatalog.Prompts.ToArray;
  if not Assigned(FEvents.OnPrompts) then
  begin
    Exit;
  end;
  for mPrompt in FEvents.OnPrompts() do
  begin
    // Eingebaute Namen gehen vor: Ein eigener Prompt kann keinen eingebauten verdecken.
    mDuplicate := False;
    for mKnown in Result do
    begin
      if SameText(mKnown.Name, mPrompt.Name) then
      begin
        mDuplicate := True;
      end;
    end;
    if not mDuplicate then
    begin
      Result := Result + [mPrompt];
    end;
  end;
end;

function TMcpServer.ToolAvailable(const AName: string): Boolean;
var
  mTool: TMcpTool;
begin
  Result := FindToolIn(FCatalog.Tools, AName, mTool) and Available(mTool);
end;

function TMcpServer.InvokeTool(const AName: string; const AArguments: TJSONObject; out AText: string): Boolean;
var
  mTool: TMcpTool;
begin
  if not FindToolIn(FCatalog.Tools, AName, mTool) then
  begin
    AText := cTexts[TServerText.ToolDoesNotExistIn].Fmt([AName]);
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

/// <summary>Name des Prompts aus den Parametern von prompts/get; EJsonRpcError ohne.</summary>
function PromptNameOf(const AParams: TJSONValue): string;
begin
  if not (AParams is TJSONObject) or not (TJSONObject(AParams).GetValue('name') is TJSONString) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[TServerText.NameOfThePromptMissing].Text);
  end;
  Result := TJSONObject(AParams).GetValue('name').Value;
end;

/// <summary>Wert eines Arguments als Text: Texte gekürzt, null leer, sonst als JSON.</summary>
function ArgumentText(AValue: TJSONValue): string;
begin
  if AValue is TJSONString then
  begin
    Result := Trim(AValue.Value);
  end
  else if AValue is TJSONNull then
  begin
    Result := '';
  end
  else
  begin
    Result := Trim(AValue.ToJSON);
  end;
end;

/// <summary>Nicht leere Argumente aus "arguments" der Parameter in AArguments.</summary>
procedure ReadPromptArguments(const AParams: TJSONValue; AArguments: TDictionary<string, string>);
var
  mPair: TJSONPair;
  mValue: string;
begin
  if not (TJSONObject(AParams).GetValue('arguments') is TJSONObject) then
  begin
    Exit;
  end;
  for mPair in TJSONObject(TJSONObject(AParams).GetValue('arguments')) do
  begin
    mValue := ArgumentText(mPair.JsonValue);
    if mValue <> '' then
    begin
      AArguments.AddOrSetValue(mPair.JsonString.Value, mValue);
    end;
  end;
end;

/// <summary>EJsonRpcError, wenn ein Pflichtargument von APrompt fehlt.</summary>
procedure CheckPromptArguments(const APrompt: TMcpPrompt; AArguments: TDictionary<string, string>);
var
  mInfo: TMcpPromptArgument;
begin
  for mInfo in APrompt.Arguments do
  begin
    if mInfo.Required and not AArguments.ContainsKey(mInfo.Name) then
    begin
      raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
        cTexts[TServerText.PromptArgumentMissing].Fmt([APrompt.Name, mInfo.Name, mInfo.Description]));
    end;
  end;
end;

/// <summary>Text des Prompts; ein fachlicher Fehler wird zu EJsonRpcError(InvalidParams).</summary>
function PromptText(const APrompt: TMcpPrompt; AArguments: TDictionary<string, string>): string;
begin
  try
    Result := APrompt.Handler(AArguments);
  except
    on E: EMcpToolError do
      raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, E.Message);
  end;
end;

/// <summary>Antwort auf prompts/get: eine Nachricht der Rolle user mit AText.</summary>
function PromptResult(const APrompt: TMcpPrompt; const AText: string): TJSONObject;
var
  mMessages: TJSONArray;
  mMessage, mContent: TJSONObject;
begin
  mContent := TJSONObject.Create;
  mContent.AddPair('type', 'text');
  mContent.AddPair('text', AText);
  mMessage := TJSONObject.Create;
  mMessage.AddPair('role', 'user');
  mMessage.AddPair('content', mContent);
  mMessages := TJSONArray.Create;
  mMessages.Add(mMessage);
  Result := TJSONObject.Create;
  Result.AddPair('description', APrompt.Description);
  Result.AddPair('messages', mMessages);
end;

function FindPromptIn(const APrompts: TArray<TMcpPrompt>; const AName: string; out APrompt: TMcpPrompt): Boolean;
var
  mPrompt: TMcpPrompt;
begin
  APrompt := Default(TMcpPrompt);
  for mPrompt in APrompts do
  begin
    if mPrompt.Name = AName then
    begin
      APrompt := mPrompt;
      Exit(True);
    end;
  end;
  Result := False;
end;

function TMcpServer.GetPrompt(const AParams: TJSONValue): TJSONObject;
var
  mName, mText: string;
  mPrompt: TMcpPrompt;
  mArguments: TDictionary<string, string>;
begin
  mName := PromptNameOf(AParams);
  if not PromptsEnabled then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TServerText.PromptsAreSwitchedOffMcp].Text);
  end;
  if not FindPromptIn(Prompts, mName, mPrompt) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[TServerText.UnknownPrompt].Fmt([mName]));
  end;
  mArguments := TDictionary<string, string>.Create;
  try
    ReadPromptArguments(AParams, mArguments);
    CheckPromptArguments(mPrompt, mArguments);
    // Wie vor jedem Werkzeugaufruf: geänderte Units nachladen (#48), einmal für alle eingebetteten Werkzeuge.
    if Assigned(FEvents.OnBeforeToolCall) then
    begin
      FEvents.OnBeforeToolCall();
    end;
    mText := PromptText(mPrompt, mArguments);
  finally
    mArguments.Free;
  end;
  Result := PromptResult(mPrompt, mText);
end;

function TMcpServer.Available(const ATool: TMcpTool): Boolean;
var
  mName: string;
begin
  if FRestricted and (ATool.Kind <> TMcpToolKind.Read) then
  begin
    Exit(False);
  end;
  if Assigned(FEvents.OnDisabledTools) then
  begin
    for mName in FEvents.OnDisabledTools() do
    begin
      if SameText(Trim(mName), ATool.Name) then
      begin
        Exit(False);
      end;
    end;
  end;
  Result := True;
end;

procedure TMcpServer.Audit(const AText: string);
begin
  if Assigned(FEvents.OnAudit) then
  begin
    FEvents.OnAudit(AText);
  end;
end;

function TMcpServer.ListResources: TJSONObject;
var
  mItems: TJSONArray;
  mItem: TJSONObject;
  mResource: TMcpResource;
begin
  mItems := TJSONArray.Create;
  for mResource in FCatalog.Resources do
  begin
    if mResource.WithPrompts and not PromptsEnabled then
    begin
      Continue;
    end;
    mItem := TJSONObject.Create;
    mItem.AddPair('uri', mResource.Uri);
    mItem.AddPair('name', mResource.Name);
    mItem.AddPair('description', mResource.Description);
    mItem.AddPair('mimeType', mResource.MimeType);
    mItems.Add(mItem);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('resources', mItems);
end;

function ResourceJson(const AUri, AMimeType, AText: string): TJSONObject;
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

/// <summary>uri aus den Parametern von resources/read; EJsonRpcError ohne.</summary>
function ResourceUriOf(const AParams: TJSONValue): string;
begin
  if not (AParams is TJSONObject) or not (TJSONObject(AParams).GetValue('uri') is TJSONString) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[TServerText.UriMissing].Text);
  end;
  Result := TJSONObject(AParams).GetValue('uri').Value;
end;

/// <summary>Feste Ressource AUri aus AResources; mit Prompts verbundene nur, wenn APromptsEnabled.</summary>
function FindResource(AResources: TList<TMcpResource>; const AUri: string; APromptsEnabled: Boolean;
  out AResource: TMcpResource): Boolean;
var
  mResource: TMcpResource;
begin
  AResource := Default(TMcpResource);
  for mResource in AResources do
  begin
    if SameText(mResource.Uri, AUri) and (not mResource.WithPrompts or APromptsEnabled) then
    begin
      AResource := mResource;
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Vorlage aus ATemplates, auf die AUri passt; AValue ist der Wert der Variablen.</summary>
function FindTemplate(ATemplates: TList<TMcpResourceTemplate>; const AUri: string;
  out ATemplate: TMcpResourceTemplate; out AValue: string): Boolean;
var
  mTemplate: TMcpResourceTemplate;
begin
  ATemplate := Default(TMcpResourceTemplate);
  AValue := '';
  for mTemplate in ATemplates do
  begin
    if mTemplate.Match(AUri, AValue) then
    begin
      ATemplate := mTemplate;
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Text der Vorlage zu AValue; ein fachlicher Fehler wird zu EJsonRpcError(InvalidParams).</summary>
function TemplateText(const ATemplate: TMcpResourceTemplate; const AValue: string): string;
begin
  try
    Result := ATemplate.Handler(AValue);
  except
    // Mit Begründung an den Client, z. B. „liegt außerhalb des Arbeitsbereichs“ (#99).
    on E: EMcpToolError do
      raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, E.Message);
  end;
end;

function TMcpServer.ReadResource(const AParams: TJSONValue): TJSONObject;
var
  mUri, mValue: string;
  mResource: TMcpResource;
  mTemplate: TMcpResourceTemplate;
begin
  mUri := ResourceUriOf(AParams);
  if FindResource(FCatalog.Resources, mUri, PromptsEnabled, mResource) then
  begin
    if Assigned(FEvents.OnBeforeToolCall) then
    begin
      FEvents.OnBeforeToolCall();
    end;
    Exit(ResourceJson(mResource.Uri, mResource.MimeType, mResource.Handler()));
  end;
  if not (PromptsEnabled and FindTemplate(FCatalog.Templates, mUri, mTemplate, mValue)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[TServerText.UnknownResource].Fmt([mUri]));
  end;
  if Assigned(FEvents.OnBeforeToolCall) then
  begin
    FEvents.OnBeforeToolCall();
  end;
  Result := ResourceJson(mUri, mTemplate.MimeType, TemplateText(mTemplate, mValue));
end;

function TMcpServer.ReadResourceText(const AUri: string; out AText: string): Boolean;
var
  mResource: TMcpResource;
begin
  AText := '';
  Result := FindResource(FCatalog.Resources, AUri, PromptsEnabled, mResource);
  if Result then
  begin
    AText := mResource.Handler();
  end;
end;

function TMcpServer.ListResourceTemplates: TJSONObject;
var
  mItems: TJSONArray;
  mItem: TJSONObject;
  mTemplate: TMcpResourceTemplate;
begin
  mItems := TJSONArray.Create;
  if PromptsEnabled then
  begin
    for mTemplate in FCatalog.Templates do
    begin
      mItem := TJSONObject.Create;
      mItem.AddPair('uriTemplate', mTemplate.UriTemplate);
      mItem.AddPair('name', mTemplate.Name);
      mItem.AddPair('description', mTemplate.Description);
      mItem.AddPair('mimeType', mTemplate.MimeType);
      mItems.Add(mItem);
    end;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('resourceTemplates', mItems);
end;

procedure TMcpServer.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterRequest(cInitializeMethod,
    function(const AParams: TJSONValue): TJSONValue
    begin
      Result := Initialize(AParams);
    end);
  ADispatcher.RegisterNotification(cInitializedMethod,
    procedure(const AParams: TJSONValue)
    begin
    end);
  ADispatcher.RegisterRequest(cPingMethod,
    function(const AParams: TJSONValue): TJSONValue
    begin
      Result := TJSONObject.Create;
    end);
  ADispatcher.RegisterRequest(cListToolsMethod,
    function(const AParams: TJSONValue): TJSONValue
    begin
      Result := ListTools;
    end);
  ADispatcher.RegisterRequest(cCallToolMethod,
    function(const AParams: TJSONValue): TJSONValue
    begin
      Result := CallTool(AParams);
    end);
  ADispatcher.RegisterRequest(cListResourcesMethod,
    function(const AParams: TJSONValue): TJSONValue
    begin
      Result := ListResources;
    end);
  ADispatcher.RegisterRequest(cReadResourceMethod,
    function(const AParams: TJSONValue): TJSONValue
    begin
      Result := ReadResource(AParams);
    end);
  ADispatcher.RegisterRequest(cListResourceTemplatesMethod,
    function(const AParams: TJSONValue): TJSONValue
    begin
      Result := ListResourceTemplates;
    end);
  ADispatcher.RegisterRequest(cListPromptsMethod,
    function(const AParams: TJSONValue): TJSONValue
    begin
      Result := ListPrompts;
    end);
  ADispatcher.RegisterRequest(cGetPromptMethod,
    function(const AParams: TJSONValue): TJSONValue
    begin
      Result := GetPrompt(AParams);
    end);
end;

function TMcpServer.Initialize(const AParams: TJSONValue): TJSONObject;
var
  mVersion: string;
  mCapabilities, mInfo: TJSONObject;
begin
  // Die vom Client gewünschte Version übernehmen; der Server nutzt nur Werkzeuge,
  // die in allen bisherigen Versionen gleich aussehen.
  mVersion := cDefaultProtocolVersion;
  if (AParams is TJSONObject) and (TJSONObject(AParams).GetValue('protocolVersion') is TJSONString) then
  begin
    mVersion := TJSONObject(AParams).GetValue('protocolVersion').Value;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('protocolVersion', mVersion);
  mCapabilities := TJSONObject.Create;
  mCapabilities.AddPair('tools', TJSONObject.Create);
  if (FCatalog.Resources.Count > 0) or (FCatalog.Templates.Count > 0) then
  begin
    mCapabilities.AddPair('resources', TJSONObject.Create);
  end;
  // Immer melden, wenn es Prompts geben kann: Clients fragen die Liste sonst nie ab, auch wenn mcp.prompts
  // später eingeschaltet wird (#1357).
  if (FCatalog.Prompts.Count > 0) or Assigned(FEvents.OnPrompts) then
  begin
    mCapabilities.AddPair('prompts', TJSONObject.Create);
  end;
  Result.AddPair('capabilities', mCapabilities);
  mInfo := TJSONObject.Create;
  mInfo.AddPair('name', FInfo.Name);
  mInfo.AddPair('version', FInfo.Version);
  Result.AddPair('serverInfo', mInfo);
  if FInfo.Instructions <> '' then
  begin
    Result.AddPair('instructions', FInfo.Instructions);
  end;
end;

function TMcpServer.ListTools: TJSONObject;
var
  mTools: TJSONArray;
  mItem: TJSONObject;
  mTool: TMcpTool;
  mSchema: TJSONValue;
begin
  mTools := TJSONArray.Create;
  for mTool in FCatalog.Tools do
  begin
    if not Available(mTool) then
    begin
      Continue;
    end;
    mItem := TJSONObject.Create;
    mItem.AddPair('name', mTool.Name);
    mItem.AddPair('description', mTool.Description);
    mSchema := TJSONObject.ParseJSONValue(mTool.InputSchema);
    if mSchema = nil then
    begin
      mSchema := TJSONObject.ParseJSONValue('{"type":"object"}');
    end;
    mItem.AddPair('inputSchema', mSchema);
    mTools.Add(mItem);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('tools', mTools);
end;

function TMcpServer.Execute(const ATool: TMcpTool; const AArguments: TJSONObject; out AText: string): Boolean;
begin
  Result := False;
  if not Available(ATool) then
  begin
    if FRestricted and (ATool.Kind <> TMcpToolKind.Read) then
    begin
      AText := cTexts[TServerText.ToolIsOffInRestricted].Fmt([ATool.Name]);
    end
    else
    begin
      AText := cTexts[TServerText.ToolIsSwitchedOffIn].Fmt([ATool.Name]);
    end;
    Exit(True);
  end;
  try
    if ATool.Kind <> TMcpToolKind.Read then
    begin
      if AArguments <> nil then
      begin
        Audit(Format('MCP %s %s', [ATool.Name, TLogMarks.Text(AArguments.ToJSON)]));
      end
      else
      begin
        Audit(Format('MCP %s', [ATool.Name]));
      end;
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
  mName, mText: string;
  mTool: TMcpTool;
  mArguments: TJSONObject;
  mIsError: Boolean;
  mContent: TJSONArray;
  mItem: TJSONObject;
begin
  if not (AParams is TJSONObject) or not (TJSONObject(AParams).GetValue('name') is TJSONString) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[TServerText.ToolNameMissing].Text);
  end;
  mName := TJSONObject(AParams).GetValue('name').Value;
  if not FindToolIn(FCatalog.Tools, mName, mTool) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[TServerText.UnknownTool].Fmt([mName]));
  end;
  mArguments := nil;
  if TJSONObject(AParams).GetValue('arguments') is TJSONObject then
  begin
    mArguments := TJSONObject(TJSONObject(AParams).GetValue('arguments'));
  end;
  // Z. B. geänderte Units nachladen (#48); ein Fehler dort trifft den Aufruf wie einer des Werkzeugs.
  try
    if Available(mTool) and Assigned(FEvents.OnBeforeToolCall) then
    begin
      FEvents.OnBeforeToolCall();
    end;
    mIsError := Execute(mTool, mArguments, mText);
  except
    on E: EMcpToolError do
    begin
      mText := E.Message;
      mIsError := True;
    end;
  end;
  mContent := TJSONArray.Create;
  mItem := TJSONObject.Create;
  mItem.AddPair('type', 'text');
  mItem.AddPair('text', mText);
  mContent.Add(mItem);
  Result := TJSONObject.Create;
  Result.AddPair('content', mContent);
  Result.AddPair('isError', TJSONBool.Create(mIsError));
end;

function JsonText(const AText: string): string;
var
  mValue: TJSONString;
begin
  mValue := TJSONString.Create(AText);
  try
    Result := mValue.ToJSON;
  finally
    mValue.Free;
  end;
end;

class function TMcpServer.StringSchema(const ANames, ADescriptions: array of string): string;
begin
  Result := StringSchema(ANames, ADescriptions, -1);
end;

class function TMcpServer.StringSchema(const ANames, ADescriptions: array of string; ARequired: Integer): string;
var
  mIndex, mCount: Integer;
  mProperties, mRequired: string;
begin
  // ARequired = -1: alle Parameter sind Pflicht, sonst nur die ersten ARequired.
  mCount := ARequired;
  if mCount < 0 then
  begin
    mCount := Length(ANames);
  end;
  mProperties := '';
  mRequired := '';
  for mIndex := 0 to High(ANames) do
  begin
    if mProperties <> '' then
    begin
      mProperties := mProperties + ',';
    end;
    mProperties := mProperties + JsonText(ANames[mIndex]) + ':{"type":"string","description":' +
      JsonText(ADescriptions[mIndex]) + '}';
    if mIndex < mCount then
    begin
      if mRequired <> '' then
      begin
        mRequired := mRequired + ',';
      end;
      mRequired := mRequired + JsonText(ANames[mIndex]);
    end;
  end;
  Result := '{"type":"object","properties":{' + mProperties + '},"required":[' + mRequired + ']}';
end;

class function TMcpServer.OptionalString(const AArguments: TJSONObject; const AName: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  if AArguments = nil then
  begin
    Exit;
  end;
  mValue := AArguments.GetValue(AName);
  if (mValue <> nil) and not (mValue is TJSONNull) then
  begin
    Result := Trim(mValue.Value);
  end;
end;

class function TMcpServer.RequiredString(const AArguments: TJSONObject; const AName: string): string;
begin
  Result := OptionalString(AArguments, AName);
  if Result = '' then
  begin
    raise EMcpToolError.CreateFmt(cTexts[TServerText.ParameterMissing].Text, [AName]);
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Mcp.Server', cTexts);

end.
