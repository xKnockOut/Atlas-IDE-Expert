unit Atlas.Core.Assistants.LinkProtocol;

// Assistenten-Kopplung (#2377): das Protokoll eines verbundenen Kommandozeilen-Assistenten, MCP (JSON-RPC 2.0,
// Stand 2025-03-26) über WebSocket. Die IDE ist der Server: Der Client fragt mit initialize, tools/list und
// tools/call, die IDE meldet von sich aus selection_changed und at_mentioned. Die Namen der Werkzeuge, ihre
// Parameter und die Form der Antworten stehen nur hier; ändert der Client das Protokoll, betrifft das diese Unit.
// Angeboten werden openFile, openDiff, getCurrentSelection, getLatestSelection, getOpenEditors,
// getWorkspaceFolders, getDiagnostics, checkDocumentDirty, saveDocument, close_tab und closeAllDiffTabs;
// executeCode bewusst nicht (keine Ausführung von Code). openDiff fehlt, solange die Vorschau aus ist
// (assistants.link.diffPreview); seine Antwort geht erst nach der Entscheidung des Benutzers zurück.
// Ohne Sockets und Open Tools API: Was die IDE weiß und tut, kommt über IAtlasLinkIde, was hinausgeht, über
// IAtlasLinkPeer (Atlas.Core.Assistants.Contract.Link). Zeilen und Zeichen sind 0-basiert wie im LSP.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Assistants.Contract.Link;

type
  /// <summary>Eine Verbindung: beantwortet die Nachrichten des Clients.</summary>
  TAtlasLinkSession = class
  public const
    cProtocolVersion = '2025-03-26';
    cServerName = 'atlas-ide';
    cErrorParse = -32700;
    cErrorRequest = -32600;
    cErrorMethod = -32601;
    cErrorParams = -32602;
    /// <summary>Antworten von openDiff.</summary>
    cFileSaved = 'FILE_SAVED';
    cDiffRejected = 'DIFF_REJECTED';
    cTabClosed = 'TAB_CLOSED';
  private
    FIde: IAtlasLinkIde;
    FPeer: IAtlasLinkPeer;
    FVersion: string;
    FClientName: string;
    FInitialized: Boolean;
    FOffersDiffs: Boolean;
    function Route(const AMethod, AId: string; AParams: TJSONObject): string;
    function Initialize(AParams: TJSONObject): string;
    function CallTool(const AId: string; AParams: TJSONObject): string;
    function RunTool(const AName, AId: string; AArguments: TJSONObject; out ADeferred: Boolean): string;
    function OpenFile(AArguments: TJSONObject): string;
    function DocumentDirty(AArguments: TJSONObject): string;
    function SaveDocument(AArguments: TJSONObject): string;
    function Diagnostics(AArguments: TJSONObject): string;
    procedure OpenDiff(const AId: string; AArguments: TJSONObject);
  public
    /// <summary>AIde: Daten und Aktionen der IDE; APeer: Ausgang dieser Verbindung; AVersion: Version von Atlas.
    /// </summary>
    constructor Create(const AIde: IAtlasLinkIde; const APeer: IAtlasLinkPeer; const AVersion: string);
    /// <summary>Eine Nachricht des Clients; Antworten gehen über den Peer.</summary>
    procedure Handle(const AText: string);
    /// <summary>clientInfo.name aus initialize; '' vorher.</summary>
    property ClientName: string read FClientName;
    property Initialized: Boolean read FInitialized;
    /// <summary>openDiff anbieten (assistants.link.diffPreview); gilt ab dem nächsten tools/list.</summary>
    property OffersDiffs: Boolean read FOffersDiffs write FOffersDiffs;
  end;

  /// <summary>JSON der Nachrichten und Ergebnisse, auch für Tests.</summary>
  TAtlasLinkMessages = class
  public
    /// <summary>file:///… zu einem Pfad (Windows oder POSIX).</summary>
    class function UriOf(const AFileName: string): string; static;
    /// <summary>Pfad zu einer file-URI; andere Werte unverändert.</summary>
    class function FileNameOf(const AUri: string): string; static;
    class function LanguageOf(const AFileName: string): string; static;
    class function Answer(const AId, AResultJson: string): string; static;
    class function Error(const AId: string; ACode: Integer; const AMessage: string): string; static;
    class function Notification(const AMethod, AParamsJson: string): string; static;
    /// <summary>Ergebnis von tools/call mit den Texten ATexts; AIsError markiert einen Fehler.</summary>
    class function ToolResult(const ATexts: array of string; AIsError: Boolean): string; static;
    /// <summary>selection_changed für ASelection.</summary>
    class function SelectionChanged(const ASelection: TAtlasLinkSelection): string; static;
    /// <summary>at_mentioned für AFileName von ALineStart bis ALineEnd (0-basiert).</summary>
    class function AtMentioned(const AFileName: string; ALineStart, ALineEnd: Integer): string; static;
    /// <summary>Antwort von getCurrentSelection bzw. getLatestSelection; ANone ist der Text ohne Auswahl.</summary>
    class function SelectionResult(const ASelection: TAtlasLinkSelection; const ANone: string): string; static;
    class function TabsResult(const ATabs: TArray<TAtlasLinkTab>): string; static;
    class function FoldersResult(const AFolders: TArray<string>): string; static;
    class function DiagnosticsResult(const AItems: TArray<TAtlasLinkDiagnostic>): string; static;
    /// <summary>Die Werkzeuge für tools/list; AWithDiffs nimmt openDiff, close_tab und closeAllDiffTabs auf.
    /// </summary>
    class function Tools(AWithDiffs: Boolean): string; static;
  end;

implementation

uses
  // Inline-Funktionen von TJSONObject (H2443).
  System.Generics.Collections,
  System.StrUtils,
  Atlas.Text.Json;

const
  cNoEditor = 'No active editor found';
  cNoSelection = 'No selection available';
  cNotOpen = 'Document not open: %s';
  cPaused = 'The IDE paused AI assistants; nothing was changed.';
  cUriPrefix = 'file://';
  cUnreserved = ['A'..'Z', 'a'..'z', '0'..'9', '-', '.', '_', '~', '/', ':'];
  /// <summary>Bytes ab hier sind nicht ASCII und werden in der URI immer kodiert.</summary>
  cAsciiEnd = $80;
  /// <summary>Länge von %XX in einer URI.</summary>
  cEscapeLength = 3;
  /// <summary>/C: vorn im Pfad einer file-URI unter Windows.</summary>
  cDrivePrefixLength = 3;
  cPascalExtensions: array[0..4] of string = ('.pas', '.dpr', '.dpk', '.inc', '.pp');
  cXmlExtensions: array[0..2] of string = ('.dproj', '.groupproj', '.xml');
  cErrorParseText = 'Parse error';
  cErrorRequestText = 'Invalid request';
  cErrorMethodText = 'Method not found: ';
  cErrorNoToolText = 'Missing tool name';
  cErrorUnknownToolText = 'Unknown tool: ';
  cMissingFilePath = 'Missing filePath';
  cFileNotFound = 'File not found: ';
  cOpenedFile = 'Opened file: ';
  cMissingNewFilePath = 'Missing new_file_path';
  cClosedDiffTabs = 'CLOSED_%d_DIFF_TABS';
  /// <summary>Methoden des Clients.</summary>
  cMethods: array[0..5] of string = ('initialize', 'ping', 'tools/list', 'tools/call', 'resources/list',
    'prompts/list');
  cMethodInitialize = 0;
  cMethodPing = 1;
  cMethodToolsList = 2;
  cMethodToolsCall = 3;
  cMethodResources = 4;
  cMethodPrompts = 5;
  cNotificationPrefix = 'notifications/';
  /// <summary>Werkzeuge mit Beschreibung; die letzten drei nur mit Vorschau (assistants.link.diffPreview).
  /// </summary>
  cToolNames: array[0..10] of string = ('openFile', 'getCurrentSelection', 'getLatestSelection', 'getOpenEditors',
    'getWorkspaceFolders', 'getDiagnostics', 'checkDocumentDirty', 'saveDocument', 'openDiff', 'close_tab',
    'closeAllDiffTabs');
  cToolOpenFile = 0;
  cToolCurrentSelection = 1;
  cToolLatestSelection = 2;
  cToolOpenEditors = 3;
  cToolWorkspaceFolders = 4;
  cToolDiagnostics = 5;
  cToolDocumentDirty = 6;
  cToolSaveDocument = 7;
  cToolOpenDiff = 8;
  cToolCloseTab = 9;
  cToolCloseAllDiffs = 10;
  cToolDescriptions: array[0..10] of string = ('Open a file in RAD Studio and optionally select a text range.',
    'Selection in the active editor of RAD Studio.',
    'Most recent selection in RAD Studio, even if the editor lost focus.',
    'Files open in RAD Studio.',
    'Folders of the project group open in RAD Studio.',
    'Atlas findings and compiler messages of the open files.',
    'Whether a file has unsaved changes in RAD Studio.',
    'Save a file open in RAD Studio.',
    'Show a proposed change as a comparison in RAD Studio and wait until the user accepts or rejects it.',
    'Close a comparison shown by openDiff.',
    'Close all comparisons shown by openDiff.');

{ TAtlasLinkMessages }

class function TAtlasLinkMessages.UriOf(const AFileName: string): string;
var
  mPath: string;
  mBytes: TBytes;
  mByte: Byte;
begin
  mPath := StringReplace(AFileName, '\', '/', [rfReplaceAll]);
  if not mPath.StartsWith('/') then
  begin
    mPath := '/' + mPath;
  end;
  Result := cUriPrefix;
  mBytes := TEncoding.UTF8.GetBytes(mPath);
  for mByte in mBytes do
  begin
    if (mByte < cAsciiEnd) and CharInSet(Char(mByte), cUnreserved) then
    begin
      Result := Result + Char(mByte);
    end
    else
    begin
      Result := Result + '%' + IntToHex(mByte, 2);
    end;
  end;
end;

class function TAtlasLinkMessages.FileNameOf(const AUri: string): string;
var
  mPath: string;
  mBytes: TBytes;
  mCount: Integer;
  mIndex: Integer;
begin
  if not AUri.StartsWith(cUriPrefix, True) then
  begin
    Result := AUri;
    Exit;
  end;
  mPath := Copy(AUri, Length(cUriPrefix) + 1, MaxInt);
  mBytes := nil;
  SetLength(mBytes, Length(mPath));
  mCount := 0;
  mIndex := 1;
  while mIndex <= Length(mPath) do
  begin
    if (mPath[mIndex] = '%') and (mIndex + 2 <= Length(mPath)) then
    begin
      mBytes[mCount] := Byte(StrToIntDef('$' + Copy(mPath, mIndex + 1, 2), Ord('?')));
      Inc(mIndex, cEscapeLength);
    end
    else
    begin
      mBytes[mCount] := Byte(Ord(mPath[mIndex]));
      Inc(mIndex);
    end;
    Inc(mCount);
  end;
  Result := TEncoding.UTF8.GetString(mBytes, 0, mCount);
  // file:///C:/… ist unter Windows C:\…; ein POSIX-Pfad behält seinen Schrägstrich.
  if (Length(Result) >= cDrivePrefixLength) and (Result[1] = '/') and (Result[cDrivePrefixLength] = ':') then
  begin
    Result := StringReplace(Copy(Result, 2, MaxInt), '/', '\', [rfReplaceAll]);
  end;
end;

class function TAtlasLinkMessages.LanguageOf(const AFileName: string): string;
var
  mExtension: string;
begin
  mExtension := LowerCase(ExtractFileExt(AFileName));
  if IndexStr(mExtension, cPascalExtensions) >= 0 then
  begin
    Result := 'pascal';
  end
  else if IndexStr(mExtension, cXmlExtensions) >= 0 then
  begin
    Result := 'xml';
  end
  else if mExtension = '.json' then
  begin
    Result := 'json';
  end
  else if mExtension = '.md' then
  begin
    Result := 'markdown';
  end
  else
  begin
    Result := 'plaintext';
  end;
end;

class function TAtlasLinkMessages.Answer(const AId, AResultJson: string): string;
begin
  Result := '{"jsonrpc":"2.0","id":' + AId + ',"result":' + AResultJson + '}';
end;

class function TAtlasLinkMessages.Error(const AId: string; ACode: Integer; const AMessage: string): string;
var
  mId: string;
begin
  mId := AId;
  if mId = '' then
  begin
    mId := 'null';
  end;
  Result := '{"jsonrpc":"2.0","id":' + mId + ',"error":{"code":' + IntToStr(ACode) + ',"message":' +
    TJsonText.Quote(AMessage) + '}}';
end;

class function TAtlasLinkMessages.Notification(const AMethod, AParamsJson: string): string;
begin
  Result := '{"jsonrpc":"2.0","method":' + TJsonText.Quote(AMethod) + ',"params":' + AParamsJson + '}';
end;

class function TAtlasLinkMessages.ToolResult(const ATexts: array of string; AIsError: Boolean): string;
var
  mIndex: Integer;
begin
  Result := '{"content":[';
  for mIndex := 0 to High(ATexts) do
  begin
    if mIndex > 0 then
    begin
      Result := Result + ',';
    end;
    Result := Result + '{"type":"text","text":' + TJsonText.Quote(ATexts[mIndex]) + '}';
  end;
  Result := Result + ']';
  if AIsError then
  begin
    Result := Result + ',"isError":true';
  end;
  Result := Result + '}';
end;

function PositionJson(const APosition: TAtlasLinkPosition): string;
begin
  Result := Format('{"line":%d,"character":%d}', [APosition.Line, APosition.Character]);
end;

function RangeJson(const AStart, AStop: TAtlasLinkPosition): string;
begin
  Result := '{"start":' + PositionJson(AStart) + ',"end":' + PositionJson(AStop) + '}';
end;

function SelectionJson(const ASelection: TAtlasLinkSelection): string;
begin
  Result := '{"start":' + PositionJson(ASelection.Start) + ',"end":' + PositionJson(ASelection.Stop) +
    ',"isEmpty":' + TJsonText.Bool(ASelection.IsEmpty) + '}';
end;

class function TAtlasLinkMessages.SelectionChanged(const ASelection: TAtlasLinkSelection): string;
begin
  Result := Notification('selection_changed', '{"text":' + TJsonText.Quote(ASelection.Text) + ',"filePath":' +
    TJsonText.Quote(ASelection.FileName) + ',"fileUrl":' + TJsonText.Quote(UriOf(ASelection.FileName)) +
    ',"selection":' + SelectionJson(ASelection) + '}');
end;

class function TAtlasLinkMessages.AtMentioned(const AFileName: string; ALineStart, ALineEnd: Integer): string;
begin
  Result := Notification('at_mentioned', '{"filePath":' + TJsonText.Quote(AFileName) +
    Format(',"lineStart":%d,"lineEnd":%d}', [ALineStart, ALineEnd]));
end;

class function TAtlasLinkMessages.SelectionResult(const ASelection: TAtlasLinkSelection; const ANone: string): string;
begin
  if not ASelection.Known then
  begin
    Result := '{"success":false,"message":' + TJsonText.Quote(ANone) + '}';
    Exit;
  end;
  Result := '{"success":true,"text":' + TJsonText.Quote(ASelection.Text) + ',"filePath":' +
    TJsonText.Quote(ASelection.FileName) + ',"fileUrl":' + TJsonText.Quote(UriOf(ASelection.FileName)) +
    ',"selection":' + SelectionJson(ASelection) + '}';
end;

class function TAtlasLinkMessages.TabsResult(const ATabs: TArray<TAtlasLinkTab>): string;
var
  mIndex: Integer;
begin
  Result := '{"tabs":[';
  for mIndex := 0 to High(ATabs) do
  begin
    if mIndex > 0 then
    begin
      Result := Result + ',';
    end;
    Result := Result + '{"uri":' + TJsonText.Quote(UriOf(ATabs[mIndex].FileName)) + ',"isActive":' +
      TJsonText.Bool(ATabs[mIndex].Active) + ',"label":' + TJsonText.Quote(ExtractFileName(ATabs[mIndex].FileName)) +
      ',"languageId":' + TJsonText.Quote(LanguageOf(ATabs[mIndex].FileName)) + ',"isDirty":' +
      TJsonText.Bool(ATabs[mIndex].Dirty) + ',"fileName":' + TJsonText.Quote(ATabs[mIndex].FileName) + '}';
  end;
  Result := Result + ']}';
end;

class function TAtlasLinkMessages.FoldersResult(const AFolders: TArray<string>): string;
var
  mIndex: Integer;
  mRoot: string;
begin
  Result := '{"success":true,"folders":[';
  for mIndex := 0 to High(AFolders) do
  begin
    if mIndex > 0 then
    begin
      Result := Result + ',';
    end;
    Result := Result + '{"name":' + TJsonText.Quote(ExtractFileName(ExcludeTrailingPathDelimiter(AFolders[mIndex]))) +
      ',"uri":' + TJsonText.Quote(UriOf(AFolders[mIndex])) + ',"path":' + TJsonText.Quote(AFolders[mIndex]) + '}';
  end;
  mRoot := '';
  if Length(AFolders) > 0 then
  begin
    mRoot := AFolders[0];
  end;
  Result := Result + '],"rootPath":' + TJsonText.Quote(mRoot) + '}';
end;

class function TAtlasLinkMessages.DiagnosticsResult(const AItems: TArray<TAtlasLinkDiagnostic>): string;
var
  mFiles: TArray<string>;
  mFile: string;
  mItem: TAtlasLinkDiagnostic;
  mFirstFile: Boolean;
  mFirstItem: Boolean;
begin
  // Je Datei ein Eintrag in der Reihenfolge des ersten Auftretens.
  mFiles := nil;
  for mItem in AItems do
  begin
    if IndexStr(mItem.FileName, mFiles) < 0 then
    begin
      mFiles := mFiles + [mItem.FileName];
    end;
  end;
  Result := '[';
  mFirstFile := True;
  for mFile in mFiles do
  begin
    if not mFirstFile then
    begin
      Result := Result + ',';
    end;
    mFirstFile := False;
    Result := Result + '{"uri":' + TJsonText.Quote(UriOf(mFile)) + ',"diagnostics":[';
    mFirstItem := True;
    for mItem in AItems do
    begin
      if not SameFileName(mItem.FileName, mFile) then
      begin
        Continue;
      end;
      if not mFirstItem then
      begin
        Result := Result + ',';
      end;
      mFirstItem := False;
      Result := Result + '{"message":' + TJsonText.Quote(mItem.Message) + ',"severity":' +
        TJsonText.Quote(mItem.Severity) + ',"range":' + RangeJson(mItem.Start, mItem.Stop) + ',"source":' +
        TJsonText.Quote(mItem.Source) + ',"code":' + TJsonText.Quote(mItem.Code) + '}';
    end;
    Result := Result + ']}';
  end;
  Result := Result + ']';
end;

const
  cNoArguments = '{"type":"object","properties":{}}';
  cFileArgument = '{"type":"object","properties":{"filePath":{"type":"string","description":"Path of the file"}},' +
    '"required":["filePath"]}';
  cOpenFileArguments = '{"type":"object","properties":{"filePath":{"type":"string","description":"Path of the ' +
    'file to open"},"preview":{"type":"boolean","default":false},"startText":{"type":"string","description":' +
    '"Text where the selection starts"},"endText":{"type":"string","description":"Text where the selection ends"},' +
    '"selectToEndOfLine":{"type":"boolean","default":false},"makeFrontmost":{"type":"boolean","default":true}},' +
    '"required":["filePath"]}';
  cDiffArguments = '{"type":"object","properties":{"old_file_path":{"type":"string","description":"Path of the ' +
    'file before the change"},"new_file_path":{"type":"string","description":"Path of the file after the change"},' +
    '"new_file_contents":{"type":"string","description":"Proposed contents of the file"},"tab_name":{"type":' +
    '"string","description":"Name of the comparison"}},"required":["old_file_path","new_file_path",' +
    '"new_file_contents","tab_name"]}';
  cDiagnosticsArguments = '{"type":"object","properties":{"uri":{"type":"string","description":"File URI; ' +
    'without it all open files"}}}';
  cTabArguments = '{"type":"object","properties":{"tab_name":{"type":"string"}},"required":["tab_name"]}';

function ToolJson(const AName, ADescription, ASchema: string): string;
begin
  Result := '{"name":' + TJsonText.Quote(AName) + ',"description":' + TJsonText.Quote(ADescription) +
    ',"inputSchema":' + ASchema + '}';
end;

/// <summary>Schema der Argumente des Werkzeugs AIndex aus cToolNames.</summary>
function ToolArguments(AIndex: Integer): string;
begin
  case AIndex of
    cToolOpenFile:
      Result := cOpenFileArguments;
    cToolDiagnostics:
      Result := cDiagnosticsArguments;
    cToolDocumentDirty, cToolSaveDocument:
      Result := cFileArgument;
    cToolOpenDiff:
      Result := cDiffArguments;
    cToolCloseTab:
      Result := cTabArguments;
  else
    Result := cNoArguments;
  end;
end;

class function TAtlasLinkMessages.Tools(AWithDiffs: Boolean): string;
var
  mTools: TArray<string>;
  mIndex: Integer;
begin
  mTools := nil;
  for mIndex := cToolOpenFile to cToolSaveDocument do
  begin
    mTools := mTools + [ToolJson(cToolNames[mIndex], cToolDescriptions[mIndex], ToolArguments(mIndex))];
  end;
  if AWithDiffs then
  begin
    for mIndex := cToolOpenDiff to cToolCloseAllDiffs do
    begin
      mTools := mTools + [ToolJson(cToolNames[mIndex], cToolDescriptions[mIndex], ToolArguments(mIndex))];
    end;
  end;
  Result := '{"tools":[' + string.Join(',', mTools) + ']}';
end;

{ TAtlasLinkSession }

constructor TAtlasLinkSession.Create(const AIde: IAtlasLinkIde; const APeer: IAtlasLinkPeer; const AVersion: string);
begin
  inherited Create;
  FIde := AIde;
  FPeer := APeer;
  FVersion := AVersion;
  FOffersDiffs := True;
end;

procedure TAtlasLinkSession.Handle(const AText: string);
var
  mValue: TJSONValue;
  mRoot: TJSONObject;
  mId: string;
  mMethod: string;
  mReply: string;
begin
  mValue := TJsonRead.Parse(AText);
  try
    mRoot := TJsonRead.AsObject(mValue);
    if mRoot = nil then
    begin
      FPeer.Send(TAtlasLinkMessages.Error('', cErrorParse, cErrorParseText));
      Exit;
    end;
    mId := TJsonRead.Json(mRoot, 'id');
    mMethod := TJsonRead.StrictText(mRoot, 'method');
    if mMethod = '' then
    begin
      // Antworten des Clients auf Anfragen stellt die IDE nicht; sie werden übergangen.
      if (mId = '') and (TJsonRead.Value(mRoot, 'result') = nil) then
      begin
        FPeer.Send(TAtlasLinkMessages.Error('', cErrorRequest, cErrorRequestText));
      end;
      Exit;
    end;
    mReply := Route(mMethod, mId, TJsonRead.Obj(mRoot, 'params'));
    // Benachrichtigungen (ohne id) bekommen keine Antwort.
    if (mId <> '') and (mReply <> '') then
    begin
      FPeer.Send(mReply);
    end;
  finally
    mValue.Free;
  end;
end;

function TAtlasLinkSession.Route(const AMethod, AId: string; AParams: TJSONObject): string;
begin
  case IndexStr(AMethod, cMethods) of
    cMethodInitialize:
      Result := TAtlasLinkMessages.Answer(AId, Initialize(AParams));
    cMethodPing:
      Result := TAtlasLinkMessages.Answer(AId, '{}');
    cMethodToolsList:
      Result := TAtlasLinkMessages.Answer(AId, TAtlasLinkMessages.Tools(FOffersDiffs));
    cMethodToolsCall:
      Result := CallTool(AId, AParams);
    cMethodResources:
      Result := TAtlasLinkMessages.Answer(AId, '{"resources":[]}');
    cMethodPrompts:
      Result := TAtlasLinkMessages.Answer(AId, '{"prompts":[]}');
  else
    // Benachrichtigungen des Clients (notifications/initialized u. a.) brauchen keine Antwort.
    Result := '';
    if not AMethod.StartsWith(cNotificationPrefix) then
    begin
      Result := TAtlasLinkMessages.Error(AId, cErrorMethod, cErrorMethodText + AMethod);
    end;
  end;
end;

function TAtlasLinkSession.Initialize(AParams: TJSONObject): string;
var
  mVersion: string;
begin
  FClientName := TJsonRead.Text(TJsonRead.Obj(AParams, 'clientInfo'), 'name');
  FInitialized := True;
  mVersion := TJsonRead.Text(AParams, 'protocolVersion');
  if mVersion = '' then
  begin
    mVersion := cProtocolVersion;
  end;
  Result := '{"protocolVersion":' + TJsonText.Quote(mVersion) + ',"capabilities":{"tools":{"listChanged":true}},' +
    '"serverInfo":{"name":' + TJsonText.Quote(cServerName) + ',"version":' + TJsonText.Quote(FVersion) + '}}';
end;

function TAtlasLinkSession.CallTool(const AId: string; AParams: TJSONObject): string;
var
  mName: string;
  mDeferred: Boolean;
begin
  mName := TJsonRead.Text(AParams, 'name');
  if mName = '' then
  begin
    Result := TAtlasLinkMessages.Error(AId, cErrorParams, cErrorNoToolText);
    Exit;
  end;
  Result := RunTool(mName, AId, TJsonRead.Obj(AParams, 'arguments'), mDeferred);
  if mDeferred then
  begin
    Result := '';
  end
  else if Result = '' then
  begin
    Result := TAtlasLinkMessages.Error(AId, cErrorParams, cErrorUnknownToolText + mName);
  end
  else
  begin
    Result := TAtlasLinkMessages.Answer(AId, Result);
  end;
end;

function TAtlasLinkSession.RunTool(const AName, AId: string; AArguments: TJSONObject; out ADeferred: Boolean): string;
var
  mTool: Integer;
begin
  ADeferred := False;
  mTool := IndexStr(AName, cToolNames);
  // Ohne Vorschau gibt es die Werkzeuge des Vergleichs nicht.
  if not FOffersDiffs and (mTool >= cToolOpenDiff) then
  begin
    mTool := -1;
  end;
  case mTool of
    cToolOpenFile:
      Result := OpenFile(AArguments);
    cToolCurrentSelection:
      Result := TAtlasLinkMessages.ToolResult([TAtlasLinkMessages.SelectionResult(FIde.CurrentSelection, cNoEditor)],
        False);
    cToolLatestSelection:
      Result := TAtlasLinkMessages.ToolResult([TAtlasLinkMessages.SelectionResult(FIde.LatestSelection,
        cNoSelection)], False);
    cToolOpenEditors:
      Result := TAtlasLinkMessages.ToolResult([TAtlasLinkMessages.TabsResult(FIde.OpenTabs)], False);
    cToolWorkspaceFolders:
      Result := TAtlasLinkMessages.ToolResult([TAtlasLinkMessages.FoldersResult(FIde.WorkspaceFolders)], False);
    cToolDiagnostics:
      Result := Diagnostics(AArguments);
    cToolDocumentDirty:
      Result := DocumentDirty(AArguments);
    cToolSaveDocument:
      Result := SaveDocument(AArguments);
    cToolOpenDiff:
      begin
        Result := '';
        OpenDiff(AId, AArguments);
        ADeferred := True;
      end;
    cToolCloseTab:
      begin
        FIde.CloseTab(TJsonRead.Text(AArguments, 'tab_name'));
        Result := TAtlasLinkMessages.ToolResult([cTabClosed], False);
      end;
    cToolCloseAllDiffs:
      Result := TAtlasLinkMessages.ToolResult([Format(cClosedDiffTabs, [FIde.CloseAllDiffs])], False);
  else
    Result := '';
  end;
end;

function TAtlasLinkSession.OpenFile(AArguments: TJSONObject): string;
var
  mRequest: TAtlasLinkOpenRequest;
  mOpened: TAtlasLinkOpenResult;
begin
  mRequest := Default(TAtlasLinkOpenRequest);
  mRequest.FileName := TAtlasLinkMessages.FileNameOf(TJsonRead.Text(AArguments, 'filePath'));
  mRequest.StartText := TJsonRead.Text(AArguments, 'startText');
  mRequest.EndText := TJsonRead.Text(AArguments, 'endText');
  mRequest.SelectToEndOfLine := TJsonRead.Flag(AArguments, 'selectToEndOfLine');
  mRequest.MakeFrontmost := TJsonRead.FlagOr(AArguments, 'makeFrontmost', True);
  if mRequest.FileName = '' then
  begin
    Result := TAtlasLinkMessages.ToolResult([cMissingFilePath], True);
    Exit;
  end;
  mOpened := FIde.OpenFile(mRequest);
  if not mOpened.Opened then
  begin
    Result := TAtlasLinkMessages.ToolResult([cFileNotFound + mRequest.FileName], True);
  end
  else if mRequest.MakeFrontmost then
  begin
    Result := TAtlasLinkMessages.ToolResult([cOpenedFile + mRequest.FileName], False);
  end
  else
  begin
    Result := TAtlasLinkMessages.ToolResult(['{"success":true,"filePath":' + TJsonText.Quote(mRequest.FileName) +
      ',"languageId":' + TJsonText.Quote(TAtlasLinkMessages.LanguageOf(mRequest.FileName)) + ',"lineCount":' +
      IntToStr(mOpened.LineCount) + '}'], False);
  end;
end;

function TAtlasLinkSession.DocumentDirty(AArguments: TJSONObject): string;
var
  mFileName: string;
  mDocument: TAtlasLinkDocument;
begin
  mFileName := TAtlasLinkMessages.FileNameOf(TJsonRead.Text(AArguments, 'filePath'));
  mDocument := FIde.Document(mFileName);
  if not mDocument.Open then
  begin
    Result := TAtlasLinkMessages.ToolResult(['{"success":false,"message":' +
      TJsonText.Quote(Format(cNotOpen, [mFileName])) + '}'], False);
    Exit;
  end;
  Result := TAtlasLinkMessages.ToolResult(['{"success":true,"filePath":' + TJsonText.Quote(mFileName) +
    ',"isDirty":' + TJsonText.Bool(mDocument.Dirty) + ',"isUntitled":false}'], False);
end;

function TAtlasLinkSession.SaveDocument(AArguments: TJSONObject): string;
var
  mFileName: string;
begin
  mFileName := TAtlasLinkMessages.FileNameOf(TJsonRead.Text(AArguments, 'filePath'));
  if FIde.Paused then
  begin
    Result := TAtlasLinkMessages.ToolResult([cPaused], True);
  end
  else if not FIde.Document(mFileName).Open or not FIde.SaveDocument(mFileName) then
  begin
    Result := TAtlasLinkMessages.ToolResult(['{"success":false,"message":' +
      TJsonText.Quote(Format(cNotOpen, [mFileName])) + '}'], False);
  end
  else
  begin
    Result := TAtlasLinkMessages.ToolResult(['{"success":true,"filePath":' + TJsonText.Quote(mFileName) +
      ',"saved":true,"message":"Document saved successfully"}'], False);
  end;
end;

function TAtlasLinkSession.Diagnostics(AArguments: TJSONObject): string;
var
  mFileName: string;
begin
  mFileName := TAtlasLinkMessages.FileNameOf(TJsonRead.Text(AArguments, 'uri'));
  Result := TAtlasLinkMessages.ToolResult([TAtlasLinkMessages.DiagnosticsResult(FIde.Diagnostics(mFileName))],
    False);
end;

/// <summary>Rückruf für openDiff in eigener Routine: hält nur Peer und Kennung, nicht die Sitzung.</summary>
function DiffReply(const APeer: IAtlasLinkPeer; const AId, ATabName: string): TAtlasLinkDiffDone;
begin
  Result :=
    procedure(AAccepted: Boolean; const AText: string)
    begin
      if AAccepted then
      begin
        APeer.Send(TAtlasLinkMessages.Answer(AId, TAtlasLinkMessages.ToolResult(
          [TAtlasLinkSession.cFileSaved, AText], False)));
      end
      else
      begin
        APeer.Send(TAtlasLinkMessages.Answer(AId, TAtlasLinkMessages.ToolResult(
          [TAtlasLinkSession.cDiffRejected, ATabName], False)));
      end;
    end;
end;

procedure TAtlasLinkSession.OpenDiff(const AId: string; AArguments: TJSONObject);
var
  mRequest: TAtlasLinkDiffRequest;
begin
  mRequest := Default(TAtlasLinkDiffRequest);
  mRequest.OldFileName := TAtlasLinkMessages.FileNameOf(TJsonRead.Text(AArguments, 'old_file_path'));
  mRequest.NewFileName := TAtlasLinkMessages.FileNameOf(TJsonRead.Text(AArguments, 'new_file_path'));
  mRequest.NewText := TJsonRead.Text(AArguments, 'new_file_contents');
  mRequest.TabName := TJsonRead.Text(AArguments, 'tab_name');
  if mRequest.NewFileName = '' then
  begin
    mRequest.NewFileName := mRequest.OldFileName;
  end;
  if FIde.Paused then
  begin
    FPeer.Send(TAtlasLinkMessages.Answer(AId, TAtlasLinkMessages.ToolResult([cPaused], True)));
    Exit;
  end;
  if mRequest.NewFileName = '' then
  begin
    FPeer.Send(TAtlasLinkMessages.Answer(AId, TAtlasLinkMessages.ToolResult([cMissingNewFilePath], True)));
    Exit;
  end;
  FIde.OpenDiff(mRequest, DiffReply(FPeer, AId, mRequest.TabName));
end;

end.
