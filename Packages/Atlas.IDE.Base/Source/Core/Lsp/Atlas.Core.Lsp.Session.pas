unit Atlas.Core.Lsp.Session;

// LSP-Sitzung des IDE-Plugins (ADR 0006): initialize, Dokumentabgleich und die
// Anfragen, die die IDE über den Code Insight-Manager stellt.
// Abgleich: Vor jeder Anfrage wird der aktuelle Editortext geschickt, beim
// ersten Mal als didOpen, danach als didChange mit dem geänderten Bereich
// (#395, TLspTextChanges), aber nur, wenn er sich geändert hat. Positionen
// sind 0-basiert in UTF-16-Einheiten (Delphi-String-Indizes), wie LSP sie
// erwartet.
// Diagnosen (#398) holt das Plugin selbst (Pull: textDocument/diagnostic und
// workspace/diagnostic); eine Anfrage workspace/diagnostic/refresh des Servers
// zählt RefreshCount hoch.
// Projektgruppe (#648): SetProjects vor Initialize schickt die Projekte als
// workspaceFolders (uri ist die .dproj, aktives Projekt zuerst); danach meldet
// es Änderungen als workspace/didChangeWorkspaceFolders.
// Serverneustart (#393): OpenDocuments der alten Sitzung, Reopen in der neuen
// schickt sie sofort wieder als didOpen.
// Änderungen außerhalb der IDE (#395): FilesChanged meldet sie als
// workspace/didChangeWatchedFiles.
// Projektkontext (#396): SetProjectContexts vor Initialize schickt die
// Kontexte in initializationOptions.projectContexts, danach jeden geänderten
// als atlas/projectContext.
// workspace/applyEdit (#397): Mit OnApplyEdit kündigt die Sitzung applyEdit
// an; die Anfrage geht im Lese-Thread an OnApplyEdit, das später über AReply
// antwortet ({applied, failureReason}). Antwortet der Empfänger nicht (Sitzung
// beendet, Eintrag beim Entladen verworfen), gibt die Sitzung die Id frei
// (Code-Review S-07); nur die erste Antwort zählt.
// Ergebnisfenster (#400): Implementierungen, workspace/symbol sowie Typ- und
// Aufrufhierarchie; der Aufrufer gleicht die Puffer vorher ab.
// Bedienung im Editor (#399): Code-Aktionen, Befehle mit Argumenten,
// onTypeFormatting für Schnellbefehle und ///-Gerüste, selectionRange und
// typeDefinition; auch hier gleicht der Aufrufer vorher ab.
// Formatieren (#43): formatting bzw. rangeFormatting, Abgleich wie oben.

// Aufbau (Atlas-Metriken): TLspSessionJson (Atlas.Core.Lsp.Session.Json, JSON ohne Zustand) <- TLspSessionBase
// (.Base, Zustand und Abgleich) <- TLspSessionRequests (.Requests, Anfragen) <- TLspSession (hier).

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.Progress,
  Atlas.Core.Hover.Contract,
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Lsp.DataFlow,
  Atlas.Core.Lsp.AccessChains,
  Atlas.Core.Files.WatchedChanges,
  Atlas.Core.Projects.Contract,
  Atlas.Core.InlayHints.Store,
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Lsp.Session.Json,
  Atlas.Core.Lsp.Session.Base,
  Atlas.Core.Lsp.Session.Requests;

type
  // Aliase: Die Typen stehen in Atlas.Core.Lsp.Session.Json; Aufrufer binden weiter nur diese Unit ein.
  TLspLocation = Atlas.Core.Lsp.Session.Json.TLspLocation;
  TLspCodeAction = Atlas.Core.Lsp.Session.Json.TLspCodeAction;
  TLspHoverParts = Atlas.Core.Lsp.Session.Json.TLspHoverParts;
  TLspDiagnosticReport = Atlas.Core.Lsp.Session.Json.TLspDiagnosticReport;
  TLspWorkspaceRun = Atlas.Core.Lsp.Session.Json.TLspWorkspaceRun;
  ILspSignal = Atlas.Core.Lsp.Session.Json.ILspSignal;
  TLspOpenDocument = Atlas.Core.Lsp.Session.Json.TLspOpenDocument;
  TLspApplyEditReply = Atlas.Core.Lsp.Session.Json.TLspApplyEditReply;
  TLspApplyEditProc = Atlas.Core.Lsp.Session.Json.TLspApplyEditProc;
  TLspShowMessageProc = Atlas.Core.Lsp.Session.Json.TLspShowMessageProc;
  TLspCrashNotificationProc = Atlas.Core.Lsp.Session.Json.TLspCrashNotificationProc;
  TLspFormatOptions = Atlas.Core.Lsp.Session.Json.TLspFormatOptions;
  TLspInitializeOptions = Atlas.Core.Lsp.Session.Base.TLspInitializeOptions;

  /// <summary>LSP-Sitzung des Plugins: Zustand und Abgleich aus TLspSessionBase, Anfragen aus
  /// TLspSessionRequests, hier Hierarchien, Auswirkungen, betroffene Tests, Debug-Werte, Inlay Hints, Diagnosen,
  /// Fortschritt und Befehle.</summary>
  TLspSession = class(TLspSessionRequests)
  public
    /// <summary>Parameternamen (InlayHintKind 2) und Endmarken („// Name“ ohne kind, #620, EndLabel) in den Zeilen
    /// AFromLine..AToLine (0-basiert) ohne Abgleich: Sync vorher (#401). Namen ohne abschließenden Doppelpunkt,
    /// Endmarken ohne "//".</summary>
    function InlayHints(const AFileName: string; AFromLine, AToLine: Integer;
      ATimeoutMs: Cardinal): TArray<TAtlasInlayHint>; overload;
    /// <summary>Wie oben; AEndMarkerMinLines &gt; 0 setzt die Mindestlänge der Endmarken für diese Anfrage
    /// (#620, editor.blockEndLabels.minLines). Endmarken tragen den Blockanfang aus data.blockStart;
    /// Include-Symbole hinter {$I} (#860) kommen als DefineHint mit den Symbolen aus data.includeDefines.</summary>
    function InlayHints(const AFileName: string; AFromLine, AToLine, AEndMarkerMinLines: Integer;
      ATimeoutMs: Cardinal): TArray<TAtlasInlayHint>; overload;
    /// <summary>Bezeichner für Werte beim Debuggen (#508, textDocument/inlineValue) in den Zeilen
    /// AFromLine..AToLine (0-basiert), Halt an AStoppedLine; ohne Abgleich: Sync vorher im Hauptthread.
    /// Threadsicher wie Completion.</summary>
    function InlineValues(const AFileName: string; AFromLine, AToLine, AStoppedLine: Integer;
      ATimeoutMs: Cardinal): TAtlasInlineValueRefs;
    /// <summary>Wirksame Compiler-Schalter an ALine/ACharacter (0-basiert, #558, atlas/compilerSwitches); ohne
    /// Abgleich: Sync vorher im Hauptthread. Threadsicher wie Completion. Gehört dem Aufrufer; nil ohne Antwort.
    /// </summary>
    function CompilerSwitches(const AFileName: string; ALine, ACharacter: Integer; ATimeoutMs: Cardinal): TJSONValue;
    /// <summary>atlas/debugUnavailable (#840): Schalter D, L, O, Routine, Lebensdauer von AName und Korrekturen
    /// am Halt in ALine (0-basiert); gehört dem Aufrufer.</summary>
    function DebugUnavailable(const AFileName: string; ALine: Integer; const AName: string;
      ATimeoutMs: Cardinal): TJSONValue;
    /// <summary>atlas/expressionCompletion (#538): Vorschläge für AExpression im Gültigkeitsbereich der Zeile
    /// ALine (0-basiert) von AFileName, Schreibmarke ACharacter im Ausdruck. Ohne Abgleich; gehört dem Aufrufer.
    /// </summary>
    function ExpressionCompletion(const AFileName: string; ALine: Integer; const AExpression: string;
      ACharacter: Integer; ATimeoutMs: Cardinal): TJSONValue;
    /// <summary>atlas/accessChains (#865): Zugriffsketten der Anweisungen in ALine (0-basiert) von AFileName für
    /// einen Prozess mit APointerSize. Ohne Abgleich: Sync vorher im Hauptthread. Found = False ohne Antwort.
    /// </summary>
    function AccessChains(const AFileName: string; ALine, APointerSize: Integer; ATimeoutMs: Cardinal): TAtlasAvChains;
    /// <summary>Wurzeln einer Hierarchie am Fundort (prepareCallHierarchy bzw. prepareTypeHierarchy, #400).</summary>
    function PrepareHierarchy(ADirection: TAtlasHierarchyDirection; const AFileName: string; ALine,
      ACharacter: Integer): TArray<TAtlasHierarchyItem>;
    /// <summary>Nächste Ebene unter AItem in Richtung ADirection (#400).</summary>
    function HierarchyChildren(ADirection: TAtlasHierarchyDirection;
      const AItem: TAtlasHierarchyItem): TArray<TAtlasHierarchyItem>;
    /// <summary>Auswirkungen des Symbols am Fundort bis zur Tiefe ADepth (atlas/impact, #1120); ohne Symbol leer.
    /// </summary>
    function Impact(const AFileName: string; ALine, ACharacter, ADepth: Integer): TAtlasImpact;
    /// <summary>Betroffene Tests der Änderungen gegenüber ABase ('' = main bzw. BASE) im Arbeitsbereich von
    /// AFileName, mit nicht eingecheckten Änderungen (atlas/affectedTests, #1353). Ein Fehler des Servers
    /// (tests.affected aus, keine Arbeitskopie) kommt als Exception.</summary>
    function AffectedTests(const AFileName, ABase: string): TAtlasAffectedTests;
    /// <summary>Woher kommt bzw. wohin geht der Wert des Symbols an der Stelle (atlas/dataFlow, #690).</summary>
    function DataFlow(const ARequest: TAtlasDataFlowRequest): TAtlasDataFlowResult;
    /// <summary>Diagnosen einer Datei (textDocument/diagnostic) ohne Abgleich; threadsicher wie Completion.</summary>
    function DocumentDiagnostics(const AFileName, APreviousResultId: string; ATimeoutMs: Cardinal): TLspDiagnosticReport;
    /// <summary>Diagnosen aller Projektdateien außer den geöffneten (workspace/diagnostic, Long-Polling);
    /// APrevious mit FileName und ResultId der bekannten Stände. Threadsicher wie Completion.</summary>
    function WorkspaceDiagnostics(const APrevious: TArray<TLspDiagnosticReport>;
      ATimeoutMs: Cardinal): TArray<TLspDiagnosticReport>; overload;
    /// <summary>Wie oben, dazu der Stand der Projektprüfung (#1247).</summary>
    function WorkspaceDiagnostics(const APrevious: TArray<TLspDiagnosticReport>; ATimeoutMs: Cardinal;
      out ARun: TLspWorkspaceRun): TArray<TLspDiagnosticReport>; overload;
    /// <summary>Anzahl der workspace/diagnostic/refresh-Anfragen des Servers.</summary>
    function RefreshCount: Integer;
    /// <summary>Laufende Indizierung o. Ä. des Servers ("Index 45 %"); '' ohne (#492).</summary>
    function ProgressText: string;
    /// <summary>Statusleiste: "Atlas indiziert … (45 %)"; '' ohne laufenden Vorgang (#492).</summary>
    function IndexingText: string;
    /// <summary>Läuft eine Indizierung? APercent = Fortschritt, -1 = unbekannt (#591).</summary>
    function Indexing(out APercent: Integer): Boolean;
    /// <summary>Beobachter für $/progress, im Lese-Thread (#591).</summary>
    procedure SetOnProgress(const AProc: TProc);
    /// <summary>workspace/executeCommand; Ergebnis gehört dem Aufrufer (nil bei Fehler oder Zeitlimit).</summary>
    function ExecuteCommand(const ACommand: string; ATimeoutMs: Cardinal): TJSONValue; overload;
    /// <summary>Wie oben mit Argumenten; übernimmt AArguments.</summary>
    function ExecuteCommand(const ACommand: string; AArguments: TJSONArray; ATimeoutMs: Cardinal): TJSONValue;
      overload;
  end;

  /// <summary>Laufende Sitzung oder nil; startet nie einen Server (Code-Review A-01). Aus beliebigem Thread
  /// aufgerufen, meist im Zeitlimit-Arbeiter. Steht hier, damit Anbieter verschiedener Features sie ohne
  /// gegenseitigen Import teilen (Code-Review A-10).</summary>
  TAtlasSessionFunc = reference to function: TLspSession;

implementation

/// <summary>Die Werte von AValues mit Komma verbunden.</summary>
function JoinedValues(AValues: TJSONArray): string;
var
  Value: TJSONValue;
begin
  Result := '';
  for Value in AValues do
  begin
    if Result <> '' then
    begin
      Result := Result + ', ';
    end;
    Result := Result + Value.Value;
  end;
end;

/// <summary>Beschriftung eines Inlay Hints: label ist ein String oder eine Liste von InlayHintLabelPart.</summary>
function InlayLabelOf(AEntry: TJSONObject): string;
var
  Parts, Part: TJSONValue;
begin
  Parts := AEntry.GetValue('label');
  if not (Parts is TJSONArray) then
  begin
    Exit(Trim(AEntry.GetValue<string>('label', '')));
  end;
  Result := '';
  for Part in TJSONArray(Parts) do
  begin
    if Part is TJSONObject then
    begin
      Result := Result + TJSONObject(Part).GetValue<string>('value', '');
    end;
  end;
  Result := Trim(Result);
end;

/// <summary>Hinweis ohne kind: Include-Symbole (#860), Steuerzeichen (#862), Methode ohne Self (#686) oder
/// Endmarke „// …“ (#620); False für anderes. Die Beschriftung der ersten drei baut die Oberfläche in der
/// Sprache der IDE.</summary>
function ReadPlainInlayHint(AEntry: TJSONObject; var AHint: TAtlasInlayHint; var AText: string): Boolean;
var
  Names: TJSONArray;
begin
  Result := True;
  if AEntry.TryGetValue<TJSONArray>('data.includeDefines.names', Names) then
  begin
    AHint.DefineHint := True;
    AText := JoinedValues(Names);
  end
  else if AEntry.GetValue<Integer>('data.controlChar.code', -1) >= 0 then
  begin
    AHint.CharHint := True;
  end
  else if AEntry.GetValue<Boolean>('data.methodWithoutSelf', False) then
  begin
    AHint.MethodHint := True;
  end
  else
  begin
    Result := AText.StartsWith('//');
    AHint.EndLabel := Result;
    AText := Trim(Copy(AText, 3, MaxInt));
    // Blockanfang für den Sprung per Klick (#620).
    AHint.BlockLine := AEntry.GetValue<Integer>('data.blockStart.line', -1);
    AHint.BlockCharacter := AEntry.GetValue<Integer>('data.blockStart.character', 0);
    AHint.HasBlock := AHint.BlockLine >= 0;
  end;
end;

/// <summary>Ein Inlay Hint: Parameternamen (kind 2), Typmarken (kind 1, #453) und Hinweise ohne kind; False
/// für andere Arten, ohne Position oder ohne Beschriftung.</summary>
function InlayHintOf(AEntry: TJSONObject; out AHint: TAtlasInlayHint): Boolean;
var
  Text: string;
  Kind: Integer;
begin
  AHint := Default(TAtlasInlayHint);
  Kind := AEntry.GetValue<Integer>('kind', 0);
  Text := InlayLabelOf(AEntry);
  case Kind of
    0:
      if not ReadPlainInlayHint(AEntry, AHint, Text) then
      begin
        Exit(False);
      end;
    1:
      begin
        // ": TStringList" ohne Doppelpunkt.
        AHint.TypeHint := True;
        if Text.StartsWith(':') then
        begin
          Text := Trim(Copy(Text, 2, MaxInt));
        end;
      end;
    2:
      if Text.EndsWith(':') then
      begin
        Text := TrimRight(Copy(Text, 1, Length(Text) - 1));
      end;
  else
    Exit(False);
  end;
  AHint.Line := AEntry.GetValue<Integer>('position.line', -1);
  AHint.Character := AEntry.GetValue<Integer>('position.character', 0);
  AHint.Name := Text;
  Result := (AHint.Line >= 0) and (AHint.Name <> '');
end;

/// <summary>Parameter von textDocument/inlayHint für die Zeilen AFromLine bis AToLine.</summary>
function InlayHintParams(const AUri: string; AFromLine, AToLine, AEndMarkerMinLines: Integer): TJSONObject;
var
  Range: TJSONObject;
begin
  Range := TJSONObject.Create;
  Range.AddPair('start', TJSONObject.Create.AddPair('line', TJSONNumber.Create(AFromLine))
    .AddPair('character', TJSONNumber.Create(0)));
  Range.AddPair('end', TJSONObject.Create.AddPair('line', TJSONNumber.Create(AToLine + 1))
    .AddPair('character', TJSONNumber.Create(0)));
  Result := TJSONObject.Create;
  Result.AddPair('textDocument', TJSONObject.Create(TJSONPair.Create('uri', AUri)));
  Result.AddPair('range', Range);
  if AEndMarkerMinLines > 0 then
  begin
    Result.AddPair('atlas', TJSONObject.Create(TJSONPair.Create('endMarkerMinLines',
      TJSONNumber.Create(AEndMarkerMinLines))));
  end;
end;

function TLspSession.InlayHints(const AFileName: string; AFromLine, AToLine, AEndMarkerMinLines: Integer;
  ATimeoutMs: Cardinal): TArray<TAtlasInlayHint>;
var
  Response, Item: TJSONValue;
  Hint: TAtlasInlayHint;
begin
  Result := nil;
  Response := FClient.Request('textDocument/inlayHint',
    InlayHintParams(PathToUri(AFileName), AFromLine, AToLine, AEndMarkerMinLines), ATimeoutMs);
  try
    if not (Response is TJSONArray) then
    begin
      Exit;
    end;
    for Item in TJSONArray(Response) do
    begin
      if (Item is TJSONObject) and InlayHintOf(TJSONObject(Item), Hint) then
      begin
        Result := Result + [Hint];
      end;
    end;
  finally
    Response.Free;
  end;
end;

/// <summary>previousResultIds für workspace/diagnostic aus den bekannten Berichten.</summary>
function PreviousResultIds(const APrevious: TArray<TLspDiagnosticReport>): TJSONArray;
var
  Known: TLspDiagnosticReport;
begin
  Result := TJSONArray.Create;
  for Known in APrevious do
  begin
    if Known.ResultId <> '' then
    begin
      Result.AddElement(TJSONObject.Create.AddPair('uri', TLspSessionJson.PathToUri(Known.FileName))
        .AddPair('value', Known.ResultId));
    end;
  end;
end;

/// <summary>Berichte aus items der Antwort auf workspace/diagnostic; Berichte ohne Datei fallen weg.</summary>
function DiagnosticReportsOf(const AItems: TJSONValue): TArray<TLspDiagnosticReport>;
var
  Item: TJSONValue;
  Report: TLspDiagnosticReport;
begin
  Result := nil;
  if not (AItems is TJSONArray) then
  begin
    Exit;
  end;
  for Item in TJSONArray(AItems) do
  begin
    if not (Item is TJSONObject) then
    begin
      Continue;
    end;
    Report := TLspDiagnosticReport.FromJson(TJSONObject(Item), '');
    if Report.FileName <> '' then
    begin
      Result := Result + [Report];
    end;
  end;
end;

function TLspSession.WorkspaceDiagnostics(const APrevious: TArray<TLspDiagnosticReport>; ATimeoutMs: Cardinal;
  out ARun: TLspWorkspaceRun): TArray<TLspDiagnosticReport>;
var
  Response: TJSONValue;
begin
  Result := nil;
  ARun := Default(TLspWorkspaceRun);
  Response := FClient.Request('workspace/diagnostic',
    TJSONObject.Create(TJSONPair.Create('previousResultIds', PreviousResultIds(APrevious))), ATimeoutMs);
  try
    if Response is TJSONObject then
    begin
      ARun := TLspWorkspaceRun.FromJson(Response);
      Result := DiagnosticReportsOf(TJSONObject(Response).GetValue('items'));
    end;
  finally
    Response.Free;
  end;
end;

{ TLspSession }

function TLspSession.InlayHints(const AFileName: string; AFromLine, AToLine: Integer;
  ATimeoutMs: Cardinal): TArray<TAtlasInlayHint>;
begin
  Result := InlayHints(AFileName, AFromLine, AToLine, 0, ATimeoutMs);
end;

function TLspSession.InlineValues(const AFileName: string; AFromLine, AToLine, AStoppedLine: Integer;
  ATimeoutMs: Cardinal): TAtlasInlineValueRefs;
var
  Params, Range, Stopped: TJSONObject;
  Response: TJSONValue;
begin
  Range := TJSONObject.Create;
  Range.AddPair('start', TJSONObject.Create.AddPair('line', TJSONNumber.Create(AFromLine))
    .AddPair('character', TJSONNumber.Create(0)));
  Range.AddPair('end', TJSONObject.Create.AddPair('line', TJSONNumber.Create(AToLine + 1))
    .AddPair('character', TJSONNumber.Create(0)));
  Stopped := TJSONObject.Create;
  Stopped.AddPair('start', TJSONObject.Create.AddPair('line', TJSONNumber.Create(AStoppedLine))
    .AddPair('character', TJSONNumber.Create(0)));
  Stopped.AddPair('end', TJSONObject.Create.AddPair('line', TJSONNumber.Create(AStoppedLine))
    .AddPair('character', TJSONNumber.Create(0)));
  Params := TJSONObject.Create;
  Params.AddPair('textDocument', TJSONObject.Create(TJSONPair.Create('uri', PathToUri(AFileName))));
  Params.AddPair('range', Range);
  Params.AddPair('context', TJSONObject.Create.AddPair('frameId', TJSONNumber.Create(0))
    .AddPair('stoppedLocation', Stopped));
  Response := FClient.Request('textDocument/inlineValue', Params, ATimeoutMs);
  try
    Result := InlineValueRefsOf(Response);
  finally
    Response.Free;
  end;
end;

function TLspSession.CompilerSwitches(const AFileName: string; ALine, ACharacter: Integer;
  ATimeoutMs: Cardinal): TJSONValue;
var
  Params: TJSONObject;
begin
  Params := TJSONObject.Create;
  Params.AddPair('textDocument', TJSONObject.Create(TJSONPair.Create('uri', PathToUri(AFileName))));
  Params.AddPair('position', TJSONObject.Create.AddPair('line', TJSONNumber.Create(ALine))
    .AddPair('character', TJSONNumber.Create(ACharacter)));
  Result := FClient.Request('atlas/compilerSwitches', Params, ATimeoutMs);
end;

function TLspSession.DebugUnavailable(const AFileName: string; ALine: Integer; const AName: string;
  ATimeoutMs: Cardinal): TJSONValue;
var
  Params: TJSONObject;
begin
  Params := TJSONObject.Create;
  Params.AddPair('textDocument', TJSONObject.Create(TJSONPair.Create('uri', PathToUri(AFileName))));
  Params.AddPair('position', TJSONObject.Create.AddPair('line', TJSONNumber.Create(ALine))
    .AddPair('character', TJSONNumber.Create(0)));
  Params.AddPair('name', AName);
  Result := FClient.Request('atlas/debugUnavailable', Params, ATimeoutMs);
end;

function TLspSession.AccessChains(const AFileName: string; ALine, APointerSize: Integer;
  ATimeoutMs: Cardinal): TAtlasAvChains;
var
  Response: TJSONValue;
begin
  Response := FClient.Request(TAtlasAvJson.Method, TAtlasAvJson.Params(AFileName, ALine, APointerSize), ATimeoutMs);
  try
    Result := TAtlasAvJson.Parse(Response);
  finally
    Response.Free;
  end;
end;

function TLspSession.ExpressionCompletion(const AFileName: string; ALine: Integer; const AExpression: string;
  ACharacter: Integer; ATimeoutMs: Cardinal): TJSONValue;
var
  Params: TJSONObject;
begin
  Params := TJSONObject.Create;
  Params.AddPair('textDocument', TJSONObject.Create(TJSONPair.Create('uri', PathToUri(AFileName))));
  Params.AddPair('position', TJSONObject.Create.AddPair('line', TJSONNumber.Create(ALine))
    .AddPair('character', TJSONNumber.Create(0)));
  Params.AddPair('expression', AExpression);
  Params.AddPair('character', TJSONNumber.Create(ACharacter));
  Result := FClient.Request('atlas/expressionCompletion', Params, ATimeoutMs);
end;

function TLspSession.PrepareHierarchy(ADirection: TAtlasHierarchyDirection; const AFileName: string; ALine,
  ACharacter: Integer): TArray<TAtlasHierarchyItem>;
var
  Method: string;
  Response, Item: TJSONValue;
begin
  Result := nil;
  Method := 'textDocument/prepareTypeHierarchy';
  if ADirection in [TAtlasHierarchyDirection.Incoming, TAtlasHierarchyDirection.Outgoing] then
  begin
    Method := 'textDocument/prepareCallHierarchy';
  end;
  Response := FClient.Request(Method, PositionParams(AFileName, ALine, ACharacter), FTimeoutMs * 10);
  try
    if Response is TJSONArray then
    begin
      for Item in TJSONArray(Response) do
      begin
        if Item is TJSONObject then
        begin
          Result := Result + [HierarchyItemOf(Item)];
        end;
      end;
    end;
  finally
    Response.Free;
  end;
end;

function TLspSession.HierarchyChildren(ADirection: TAtlasHierarchyDirection;
  const AItem: TAtlasHierarchyItem): TArray<TAtlasHierarchyItem>;
const
  Methods: array[TAtlasHierarchyDirection] of string = ('callHierarchy/incomingCalls',
    'callHierarchy/outgoingCalls', 'typeHierarchy/supertypes', 'typeHierarchy/subtypes');
  // Aufrufe stecken in {from|to, fromRanges}; Typen kommen direkt.
  Members: array[TAtlasHierarchyDirection] of string = ('from', 'to', '', '');
var
  Raw, Response, Item, Inner: TJSONValue;
  Child: TAtlasHierarchyItem;
begin
  Result := nil;
  Raw := TJSONObject.ParseJSONValue(AItem.Raw);
  if not (Raw is TJSONObject) then
  begin
    Raw.Free;
    Exit;
  end;
  Response := FClient.Request(Methods[ADirection], TJSONObject.Create(TJSONPair.Create('item', Raw)), FTimeoutMs * 10);
  try
    if not (Response is TJSONArray) then
    begin
      Exit;
    end;
    for Item in TJSONArray(Response) do
    begin
      Inner := Item;
      if (Members[ADirection] <> '') and (Item is TJSONObject) then
      begin
        Inner := TJSONObject(Item).GetValue(Members[ADirection]);
      end;
      if Inner is TJSONObject then
      begin
        Child := HierarchyItemOf(Inner);
        // Eingehende Aufrufe (#1119): atlasConfidence steht am Aufruf, nicht am Element.
        Child.Confidence := TAtlasConfidence.FromJson(Item);
        // Aufruf über Interface oder virtuelle Methode (#1122), ebenfalls am Aufruf.
        if Item is TJSONObject then
        begin
          Child.Dispatch := TJSONObject(Item).GetValue<string>('atlasDispatch.kind', '');
          Child.Implementations := TJSONObject(Item).GetValue<Integer>('atlasDispatch.implementations', 0);
        end;
        Result := Result + [Child];
      end;
    end;
  finally
    Response.Free;
  end;
end;

function TLspSession.Impact(const AFileName: string; ALine, ACharacter, ADepth: Integer): TAtlasImpact;
var
  Params: TJSONObject;
  Response: TJSONValue;
begin
  Params := PositionParams(AFileName, ALine, ACharacter);
  Params.AddPair('depth', TJSONNumber.Create(ADepth));
  // Mehrere Referenzsuchen über das ganze Projekt; der Server begrenzt die Zeit selbst und meldet es.
  Response := FClient.Request('atlas/impact', Params, FTimeoutMs * 30);
  try
    Result := ImpactFromJson(Response);
  finally
    Response.Free;
  end;
end;

function TLspSession.AffectedTests(const AFileName, ABase: string): TAtlasAffectedTests;
var
  mParams: TJSONObject;
  mResponse: TJSONValue;
begin
  mParams := TJSONObject.Create;
  mParams.AddPair('textDocument', TJSONObject.Create(TJSONPair.Create('uri', PathToUri(AFileName))));
  mParams.AddPair('base', ABase);
  mParams.AddPair('includeUncommitted', TJSONBool.Create(True));
  // git bzw. svn und eine Auswirkungsanalyse je geänderter Routine; der Server begrenzt die Zeit selbst.
  mResponse := FClient.Request('atlas/affectedTests', mParams, FTimeoutMs * 30);
  try
    Result := AffectedTestsFromJson(mResponse);
  finally
    mResponse.Free;
  end;
end;

function TLspSession.DataFlow(const ARequest: TAtlasDataFlowRequest): TAtlasDataFlowResult;
var
  Response: TJSONValue;
begin
  // Projektweit über die Referenzsuche; dafür so viel Zeit wie für die Hierarchien.
  Response := FClient.Request(TAtlasDataFlowJson.Method, TAtlasDataFlowJson.Params(ARequest), FTimeoutMs * 10);
  try
    Result := TAtlasDataFlowJson.Parse(Response);
  finally
    Response.Free;
  end;
end;

function TLspSession.DocumentDiagnostics(const AFileName, APreviousResultId: string;
  ATimeoutMs: Cardinal): TLspDiagnosticReport;
var
  Params: TJSONObject;
  Response: TJSONValue;
begin
  Params := TJSONObject.Create;
  Params.AddPair('textDocument', TJSONObject.Create(TJSONPair.Create('uri', PathToUri(AFileName))));
  if APreviousResultId <> '' then
  begin
    Params.AddPair('previousResultId', APreviousResultId);
  end;
  Response := FClient.Request('textDocument/diagnostic', Params, ATimeoutMs);
  try
    if Response is TJSONObject then
    begin
      Result := TLspDiagnosticReport.FromJson(TJSONObject(Response), AFileName);
    end
    else
    begin
      Result := Default(TLspDiagnosticReport);
      Result.FileName := AFileName;
    end;
  finally
    Response.Free;
  end;
end;

function TLspSession.WorkspaceDiagnostics(const APrevious: TArray<TLspDiagnosticReport>;
  ATimeoutMs: Cardinal): TArray<TLspDiagnosticReport>;
var
  mRun: TLspWorkspaceRun;
begin
  Result := WorkspaceDiagnostics(APrevious, ATimeoutMs, mRun);
end;

function TLspSession.RefreshCount: Integer;
begin
  Result := FRefresh.Count;
end;

function TLspSession.ProgressText: string;
begin
  Result := FProgress.Text;
end;

function TLspSession.IndexingText: string;
begin
  Result := FProgress.IndexingText;
end;

function TLspSession.Indexing(out APercent: Integer): Boolean;
begin
  Result := FProgress.Active(APercent);
end;

procedure TLspSession.SetOnProgress(const AProc: TProc);
begin
  FProgress.SetOnChanged(AProc);
end;

function TLspSession.ExecuteCommand(const ACommand: string; ATimeoutMs: Cardinal): TJSONValue;
begin
  Result := ExecuteCommand(ACommand, TJSONArray.Create, ATimeoutMs);
end;

function TLspSession.ExecuteCommand(const ACommand: string; AArguments: TJSONArray; ATimeoutMs: Cardinal): TJSONValue;
begin
  try
    Result := FClient.Request('workspace/executeCommand',
      TJSONObject.Create.AddPair('command', ACommand).AddPair('arguments', AArguments), ATimeoutMs);
  except
    Result := nil;
  end;
end;

end.
