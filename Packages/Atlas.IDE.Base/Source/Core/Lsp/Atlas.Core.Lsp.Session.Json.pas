unit Atlas.Core.Lsp.Session.Json;

// Typen und JSON der LSP-Sitzung ohne Zustand (aus Atlas.Core.Lsp.Session ausgelagert): Parameter für initialize,
// Lesen der Antworten (Orte, Symbole, Auswirkungen, betroffene Tests, Code-Aktionen, Diagnosen, Hover).
// TLspSessionJson ist Vorfahr von TLspSession; die Typen stehen dort auch als Aliase.

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
  Atlas.Core.Lsp.WorkspaceEdits;

type
  TLspLocation = record
    FileName: string;
    /// <summary>0-basiert.</summary>
    Line: Integer;
    /// <summary>0-basiert.</summary>
    Character: Integer;
    /// <summary>Referenzsuche (#1119): sicher oder erschlossen; sonst sicher.</summary>
    Confidence: TAtlasConfidence;
  end;

  /// <summary>Code-Aktion oder Befehl aus textDocument/codeAction (#399).</summary>
  TLspCodeAction = record
    Title: string;
    Kind: string;
    Preferred: Boolean;
    /// <summary>Grund, warum die Aktion gerade nicht geht; leer, wenn sie geht.</summary>
    Disabled: string;
    /// <summary>Erst Edit anwenden, dann Command ausführen (LSP).</summary>
    Edit: TLspWorkspaceEdit;
    /// <summary>Befehl ohne Edit oder nach dem Edit; leer ohne.</summary>
    Command: string;
    /// <summary>Argumente des Befehls als JSON-Array; '[]' ohne.</summary>
    ArgumentsJson: string;
    /// <summary>Kennung aus data.tag, z. B. "uses.remove" (#621); '' ohne.</summary>
    Tag: string;
    /// <summary>Vorschau aus data.preview (#663): vor dem Übernehmen zeigen; '' ohne.</summary>
    Preview: string;
    /// <summary>Regel des behobenen Treffers aus diagnostics[0].code (#909); '' ohne.</summary>
    Rule: string;
    /// <summary>Aus einem Eintrag der Antwort: CodeAction oder Command; False bei anderem.</summary>
    class function FromJson(const AValue: TJSONValue; out AAction: TLspCodeAction): Boolean; static;
  end;

  /// <summary>Teile eines Hovers für den Atlas-Tooltip (#442).</summary>
  TLspHoverParts = record
    Declaration: string;
    UnitName: string;
    Documentation: string;
    Value: string;
    Deprecation: string;
    function Found: Boolean;
    /// <summary>Aus einer Hover-Antwort: das Feld "atlas" des Servers, sonst erster Absatz als Deklaration.</summary>
    class function FromHover(const AHover: TJSONValue): TLspHoverParts; static;
  end;

  /// <summary>Diagnosebericht einer Datei (#398).</summary>
  TLspDiagnosticReport = record
    FileName: string;
    ResultId: string;
    /// <summary>Seit der vorigen Ergebnis-Id unverändert; Problems ist dann leer.</summary>
    Unchanged: Boolean;
    Problems: TArray<TAtlasProblem>;
    /// <summary>Aus einem Bericht des Servers ({kind, resultId, items}); AFileName, wenn er keine uri hat.</summary>
    class function FromJson(const AReport: TJSONObject; const AFileName: string): TLspDiagnosticReport; static;
  end;

  /// <summary>Stand der Projektprüfung des Servers (#1247) aus "atlas.run" der Antwort auf workspace/diagnostic.
  /// </summary>
  TLspWorkspaceRun = record
    /// <summary>Der Server hat einen Stand gemeldet (ältere Server nicht).</summary>
    Known: Boolean;
    Serial: Integer;
    Active: Boolean;
    Done: Integer;
    Total: Integer;
    Skipped: Integer;
    /// <summary>"compile", "debug", "index" oder ''.</summary>
    Paused: string;
    ElapsedMs: Int64;
    /// <summary>Aus der ganzen Antwort; Known = False ohne "atlas.run".</summary>
    class function FromJson(const AResponse: TJSONValue): TLspWorkspaceRun; static;
  end;

  /// <summary>Zähler, den der Lese-Thread erhöht; überlebt die Sitzung, solange der Client ihn hält.</summary>
  ILspSignal = interface
    ['{6B0C1E57-3A44-4E0B-9A63-2F7A5C0D8E11}']
    function Count: Integer;
    procedure Signal;
  end;

  /// <summary>Abgeglichenes Dokument mit dem zuletzt geschickten Text (#393).</summary>
  TLspOpenDocument = record
    FileName: string;
    Text: string;
  end;

  /// <summary>Antwort auf workspace/applyEdit; nur einmal aufrufen.</summary>
  TLspApplyEditReply = reference to procedure(AApplied: Boolean; const AFailureReason: string);
  /// <summary>workspace/applyEdit des Servers (#397); läuft im Lese-Thread. AEdit ist schon gelesen.</summary>
  TLspApplyEditProc = reference to procedure(const AEdit: TLspWorkspaceEdit; const AReply: TLspApplyEditReply);
  /// <summary>window/showMessage des Servers (#121); läuft im Lese-Thread. AType: 1 Fehler, 2 Warnung,
  /// 3 Information, 4 Protokoll.</summary>
  TLspShowMessageProc = reference to procedure(AType: Integer; const AMessage: string);
  /// <summary>atlas/crashCase bzw. atlas/crashSkip des Servers (#1355); läuft im Lese-Thread, AParams gehört dem
  /// Aufrufer.</summary>
  TLspCrashNotificationProc = reference to procedure(const AMethod: string; const AParams: TJSONValue);

  /// <summary>Einrückung für onTypeFormatting und formatting (FormattingOptions).</summary>
  TLspFormatOptions = record
    TabSize: Integer;
    InsertSpaces: Boolean;
    class function Create(ATabSize: Integer; AInsertSpaces: Boolean): TLspFormatOptions; static;
  end;

  /// <summary>JSON der LSP-Sitzung ohne Zustand: Parameter bauen und Antworten lesen. Vorfahr von TLspSession,
  /// damit Aufrufer weiter TLspSession.PathToUri usw. schreiben.</summary>
  TLspSessionJson = class
  protected
    /// <summary>capabilities für initialize; AApplyEdit: workspace.applyEdit ankündigen.</summary>
    class function ClientCapabilities(AApplyEdit: Boolean): TJSONObject; static;
    /// <summary>Element einer Typ- oder Aufrufhierarchie aus seinem JSON (Raw behält das ganze Element).</summary>
    class function HierarchyItemOf(const AValue: TJSONValue): TAtlasHierarchyItem; static;
  public
    class function PathToUri(const APath: string): string; static;
    class function UriToPath(const AUri: string): string; static;
    /// <summary>Text aus contents einer Hover-Antwort: String, MarkupContent oder MarkedString-Liste.</summary>
    class function HoverText(const AHover: TJSONValue): string; static;
    /// <summary>Zeichenindex (0-basiert) zur Editorspalte (1-basiert); Tabs springen zur nächsten Tabulatorposition.</summary>
    class function ColumnToIndex(const ALine: string; AColumn, ATabWidth: Integer): Integer; static;
    /// <summary>Editorspalte (1-basiert) zum Zeichenindex (0-basiert); Umkehrung von ColumnToIndex.</summary>
    class function IndexToColumn(const ALine: string; AIndex, ATabWidth: Integer): Integer; static;
    /// <summary>workspaceFolders-Einträge zu Projektdateien: uri der Datei, Name ohne Endung (#648).</summary>
    class function ProjectFolders(const AProjects: TArray<string>): TJSONArray; static;
    /// <summary>Hinzugekommene und weggefallene Projekte, Groß- und Kleinschreibung egal (#648).</summary>
    class procedure ProjectChanges(const AOld, ANew: TArray<string>; out AAdded, ARemoved: TArray<string>); static;
    /// <summary>Parameter von initialize (#396, #397, #408, #648, #652). AApplyEdit: workspace.applyEdit
    /// ankündigen. Gehört dem Aufrufer.</summary>
    class function InitializeParams(const AProjects: TArray<string>; const AServerSettings: string;
      const AContexts: TArray<TAtlasProjectContext>; AApplyEdit: Boolean): TJSONObject; overload; static;
    /// <summary>Wie oben, dazu die Sprache der Oberfläche ALocale ("de", "en"; '' = keine) als
    /// initializationOptions.locale und locale (#1458): Befunde, Code-Aktionen und Hover kommen in dieser
    /// Sprache, solange settings.json keine language vorgibt.</summary>
    class function InitializeParams(const AProjects: TArray<string>; const AServerSettings: string;
      const AContexts: TArray<TAtlasProjectContext>; AApplyEdit: Boolean;
      const ALocale: string): TJSONObject; overload; static;
    /// <summary>Antwort auf workspace/applyEdit ({applied, failureReason}). Gehört dem Aufrufer.</summary>
    class function ApplyEditAnswer(AApplied: Boolean; const AFailureReason: string): TJSONObject; static;
    /// <summary>type und message aus den Parametern von window/showMessage; False ohne Text.</summary>
    class function ShowMessageParams(const AParams: TJSONValue; out AType: Integer;
      out AMessage: string): Boolean; static;
    /// <summary>{"settings": {"atlas": AJson}} für initializationOptions und didChangeConfiguration (#652);
    /// leeres oder ungültiges AJson ergibt ein leeres atlas-Objekt.</summary>
    class function SettingsParams(const AJson: string): TJSONObject; static;
    /// <summary>Location, Location[] oder LocationLink[] einer Antwort (#400).</summary>
    class function LocationsOf(const AResponse: TJSONValue): TArray<TLspLocation>; static;
    /// <summary>DocumentSymbol[] (mit children; Container = Name des Elternsymbols) oder SymbolInformation[]
    /// einer documentSymbol-Antwort, flach; AFileName für Symbole ohne Ort.</summary>
    class function SymbolsOfDocument(const AResponse: TJSONValue; const AFileName: string): TArray<TAtlasSymbol>;
      static;
    /// <summary>Antwort von atlas/impact (#1120); ohne Objekt leer (kein Symbol am Cursor).</summary>
    class function ImpactFromJson(const AValue: TJSONValue): TAtlasImpact; static;
    /// <summary>Antwort von atlas/affectedTests (#1353); ohne Objekt leer.</summary>
    class function AffectedTestsFromJson(const AValue: TJSONValue): TAtlasAffectedTests; static;
    /// <summary>Bezeichner aus der Antwort auf textDocument/inlineValue; nur InlineValueVariableLookup mit
    /// variableName.</summary>
    class function InlineValueRefsOf(const AResponse: TJSONValue): TAtlasInlineValueRefs; static;
  end;

implementation

uses
  Atlas.Core.Lsp.Uris;

class function TLspSessionJson.PathToUri(const APath: string): string;
begin
  Result := TLspUris.FromPath(APath);
end;

class function TLspSessionJson.UriToPath(const AUri: string): string;
begin
  Result := TLspUris.ToPath(AUri);
end;

class function TLspSessionJson.HoverText(const AHover: TJSONValue): string;
var
  Contents: TJSONValue;
  Item: TJSONValue;
begin
  Result := '';
  if not (AHover is TJSONObject) then
  begin
    Exit;
  end;
  Contents := TJSONObject(AHover).GetValue('contents');
  if Contents is TJSONString then
  begin
    Result := TJSONString(Contents).Value;
  end
  else if Contents is TJSONObject then
  begin
    Result := TJSONObject(Contents).GetValue<string>('value', '');
  end
  else if Contents is TJSONArray then
  begin
    for Item in TJSONArray(Contents) do
    begin
      if Result <> '' then
      begin
        Result := Result + sLineBreak;
      end;
      if Item is TJSONString then
      begin
        Result := Result + TJSONString(Item).Value;
      end
      else if Item is TJSONObject then
      begin
        Result := Result + TJSONObject(Item).GetValue<string>('value', '');
      end;
    end;
  end;
end;

class function TLspSessionJson.ColumnToIndex(const ALine: string; AColumn, ATabWidth: Integer): Integer;
var
  Visual: Integer;
begin
  // Spalte 1 = erstes Zeichen. Tabs springen zur nächsten Tabulatorposition.
  Result := 0;
  Visual := 1;
  while (Result < Length(ALine)) and (Visual < AColumn) do
  begin
    if ALine[Result + 1] = #9 then
    begin
      Visual := ((Visual - 1) div ATabWidth + 1) * ATabWidth + 1;
    end
    else
    begin
      Inc(Visual);
    end;
    Inc(Result);
  end;
end;

class function TLspSessionJson.ShowMessageParams(const AParams: TJSONValue; out AType: Integer;
  out AMessage: string): Boolean;
begin
  AType := 3;
  AMessage := '';
  if not (AParams is TJSONObject) then
  begin
    Exit(False);
  end;
  AMessage := TJSONObject(AParams).GetValue<string>('message', '');
  AType := TJSONObject(AParams).GetValue<Integer>('type', 3);
  Result := AMessage <> '';
end;

class function TLspSessionJson.ClientCapabilities(AApplyEdit: Boolean): TJSONObject;
var
  TextDocument, Hover: TJSONObject;
  Formats: TJSONArray;
begin
  Formats := TJSONArray.Create;
  Formats.Add('plaintext');
  Hover := TJSONObject.Create;
  Hover.AddPair('contentFormat', Formats);
  TextDocument := TJSONObject.Create;
  TextDocument.AddPair('hover', Hover);
  // Dokumentation der Vervollständigung als Klartext (#408). Snippets setzt das Plugin selbst mit Platzhalter-Modus
  // ein (#51); ob sie in der Liste erscheinen, regelt completion.snippets im Plugin.
  TextDocument.AddPair('completion', TJSONObject.Create(TJSONPair.Create('completionItem',
    TJSONObject.Create.AddPair('snippetSupport', TJSONBool.Create(True))
      .AddPair('documentationFormat', TJSONArray.Create.Add('plaintext')))));
  // Diagnosen holt das Plugin selbst (#398); der Server bittet per refresh um neues Holen.
  TextDocument.AddPair('diagnostic', TJSONObject.Create.AddPair('dynamicRegistration', TJSONBool.Create(False))
    .AddPair('relatedDocumentSupport', TJSONBool.Create(False)));
  Result := TJSONObject.Create;
  Result.AddPair('textDocument', TextDocument);
  Result.AddPair('workspace', TJSONObject.Create(TJSONPair.Create('diagnostics',
    TJSONObject.Create(TJSONPair.Create('refreshSupport', TJSONBool.Create(True)))))
    .AddPair('workspaceFolders', TJSONBool.Create(True))
    .AddPair('applyEdit', TJSONBool.Create(AApplyEdit)));
end;

class function TLspSessionJson.InitializeParams(const AProjects: TArray<string>; const AServerSettings: string;
  const AContexts: TArray<TAtlasProjectContext>; AApplyEdit: Boolean): TJSONObject;
begin
  Result := InitializeParams(AProjects, AServerSettings, AContexts, AApplyEdit, '');
end;

class function TLspSessionJson.InitializeParams(const AProjects: TArray<string>; const AServerSettings: string;
  const AContexts: TArray<TAtlasProjectContext>; AApplyEdit: Boolean; const ALocale: string): TJSONObject;
var
  Options: TJSONObject;
  Contexts: TJSONArray;
  Context: TAtlasProjectContext;
begin
  Result := TJSONObject.Create;
  Result.AddPair('processId', TJSONNull.Create);
  Result.AddPair('rootUri', TJSONNull.Create);
  Result.AddPair('clientInfo', TJSONObject.Create(TJSONPair.Create('name', 'Atlas IDE Expert')));
  Result.AddPair('capabilities', ClientCapabilities(AApplyEdit));
  if Length(AProjects) > 0 then
  begin
    Result.AddPair('workspaceFolders', ProjectFolders(AProjects));
  end;
  // Einstellungen der Atlas-Optionen (#652) und Projektkontexte vor dem ersten Laden der Projekte, sonst
  // indiziert der Server sie zweimal (#396).
  Options := nil;
  if AServerSettings <> '' then
  begin
    Options := SettingsParams(AServerSettings);
  end;
  if Length(AContexts) > 0 then
  begin
    Contexts := TJSONArray.Create;
    for Context in AContexts do
    begin
      Contexts.AddElement(Context.ToJson);
    end;
    if Options = nil then
    begin
      Options := TJSONObject.Create;
    end;
    Options.AddPair('projectContexts', Contexts);
  end;
  // Sprache der Oberfläche (#1458): eigener Schlüssel für Atlas und das Feld locale aus LSP 3.16.
  if ALocale <> '' then
  begin
    Result.AddPair('locale', ALocale);
    if Options = nil then
    begin
      Options := TJSONObject.Create;
    end;
    Options.AddPair('locale', ALocale);
  end;
  if Options <> nil then
  begin
    Result.AddPair('initializationOptions', Options);
  end;
end;

class function TLspSessionJson.ApplyEditAnswer(AApplied: Boolean; const AFailureReason: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('applied', TJSONBool.Create(AApplied));
  if AFailureReason <> '' then
  begin
    Result.AddPair('failureReason', AFailureReason);
  end;
end;

class function TLspSessionJson.LocationsOf(const AResponse: TJSONValue): TArray<TLspLocation>;

  procedure Add(const AItem: TJSONValue);
  var
    Location: TLspLocation;
    Uri, Prefix: string;
  begin
    if not (AItem is TJSONObject) then
    begin
      Exit;
    end;
    // LocationLink: targetUri und targetSelectionRange; Location: uri und range.
    Prefix := 'range';
    if TJSONObject(AItem).TryGetValue<string>('targetUri', Uri) then
    begin
      Prefix := 'targetSelectionRange';
    end
    else
    begin
      Uri := TJSONObject(AItem).GetValue<string>('uri', '');
    end;
    Location.FileName := UriToPath(Uri);
    Location.Line := TJSONObject(AItem).GetValue<Integer>(Prefix + '.start.line', 0);
    Location.Character := TJSONObject(AItem).GetValue<Integer>(Prefix + '.start.character', 0);
    Location.Confidence := TAtlasConfidence.FromJson(AItem);
    if Location.FileName <> '' then
    begin
      Result := Result + [Location];
    end;
  end;

var
  Item: TJSONValue;
begin
  Result := nil;
  if AResponse is TJSONArray then
  begin
    for Item in TJSONArray(AResponse) do
    begin
      Add(Item);
    end;
  end
  else
  begin
    Add(AResponse);
  end;
end;

class function TLspSessionJson.IndexToColumn(const ALine: string; AIndex, ATabWidth: Integer): Integer;
var
  Index: Integer;
begin
  // Wie ColumnToIndex: Tabs springen zur nächsten Tabulatorposition, hinter dem Zeilenende je Zeichen eine Spalte.
  Result := 1;
  for Index := 1 to AIndex do
  begin
    if (Index <= Length(ALine)) and (ALine[Index] = #9) and (ATabWidth > 0) then
    begin
      Result := ((Result - 1) div ATabWidth + 1) * ATabWidth + 1;
    end
    else
    begin
      Inc(Result);
    end;
  end;
end;

class function TLspSessionJson.SymbolsOfDocument(const AResponse: TJSONValue;
  const AFileName: string): TArray<TAtlasSymbol>;
var
  Found: TArray<TAtlasSymbol>;

  procedure AddAll(const AItems: TJSONValue; const AContainer: string);
  var
    Item: TJSONValue;
    Entry: TJSONObject;
    Symbol: TAtlasSymbol;
    Locations: TArray<TLspLocation>;
  begin
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
      Entry := TJSONObject(Item);
      Symbol := Default(TAtlasSymbol);
      Symbol.Name := Entry.GetValue<string>('name', '');
      Symbol.Kind := Entry.GetValue<Integer>('kind', 0);
      Symbol.FileName := AFileName;
      if Entry.GetValue('location') <> nil then
      begin
        // SymbolInformation: Ort und Container stehen am Eintrag.
        Symbol.Container := Entry.GetValue<string>('containerName', '');
        Locations := LocationsOf(Entry.GetValue('location'));
        if Length(Locations) > 0 then
        begin
          Symbol.FileName := Locations[0].FileName;
          Symbol.Line := Locations[0].Line;
          Symbol.Character := Locations[0].Character;
        end;
      end
      else
      begin
        Symbol.Container := AContainer;
        Symbol.Line := Entry.GetValue<Integer>('selectionRange.start.line',
          Entry.GetValue<Integer>('range.start.line', 0));
        Symbol.Character := Entry.GetValue<Integer>('selectionRange.start.character',
          Entry.GetValue<Integer>('range.start.character', 0));
      end;
      if Symbol.Name <> '' then
      begin
        Found := Found + [Symbol];
      end;
      AddAll(Entry.GetValue('children'), Symbol.Name);
    end;
  end;

begin
  Found := nil;
  AddAll(AResponse, '');
  Result := Found;
end;

class function TLspSessionJson.HierarchyItemOf(const AValue: TJSONValue): TAtlasHierarchyItem;
var
  Entry: TJSONObject;
begin
  Result := Default(TAtlasHierarchyItem);
  if not (AValue is TJSONObject) then
  begin
    Exit;
  end;
  Entry := TJSONObject(AValue);
  Result.Name := Entry.GetValue<string>('name', '');
  Result.Detail := Entry.GetValue<string>('detail', '');
  Result.Kind := Entry.GetValue<Integer>('kind', 0);
  Result.FileName := UriToPath(Entry.GetValue<string>('uri', ''));
  Result.Line := Entry.GetValue<Integer>('selectionRange.start.line', 0);
  Result.Character := Entry.GetValue<Integer>('selectionRange.start.character', 0);
  Result.Raw := Entry.ToJSON;
end;

function ImpactFormsOf(const AValue: TJSONValue): TArray<TAtlasImpactForm>;
var
  Item: TJSONValue;
  Form: TAtlasImpactForm;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
  begin
    Exit;
  end;
  for Item in TJSONArray(AValue) do
  begin
    if Item is TJSONObject then
    begin
      Form.FileName := TLspSessionJson.UriToPath(TJSONObject(Item).GetValue<string>('uri', ''));
      Form.Line := TJSONObject(Item).GetValue<Integer>('range.start.line', 0);
      Form.Character := TJSONObject(Item).GetValue<Integer>('range.start.character', 0);
      Form.Text := TJSONObject(Item).GetValue<string>('text', '');
      Result := Result + [Form];
    end;
  end;
end;

/// <summary>Namen aus einem JSON-Array von Strings; ohne Einträge AFallback allein.</summary>
function RunNamesOf(const AValue: TJSONValue; const AFallback: string): TArray<string>;
var
  Name: TJSONValue;
begin
  Result := nil;
  if AValue is TJSONArray then
  begin
    for Name in TJSONArray(AValue) do
    begin
      Result := Result + [Name.Value];
    end;
  end;
  if Result = nil then
  begin
    Result := TArray<string>.Create(AFallback);
  end;
end;

/// <summary>Eine betroffene Stelle aus places der Antwort auf atlas/impact.</summary>
function ImpactPlaceOf(AEntry: TJSONObject): TAtlasImpactPlace;
var
  Ranges, First: TJSONValue;
begin
  Result := Default(TAtlasImpactPlace);
  Result.Item := TLspSessionJson.HierarchyItemOf(AEntry.GetValue('item'));
  Result.Item.Confidence := TAtlasConfidence.FromJson(AEntry);
  Result.Level := AEntry.GetValue<Integer>('level', 0);
  Result.Edge := AEntry.GetValue<string>('edge', '');
  Result.Cause := AEntry.GetValue<Integer>('cause', -1);
  Result.UseLine := Result.Item.Line;
  Result.UseCharacter := Result.Item.Character;
  Ranges := AEntry.GetValue('ranges');
  if (Ranges is TJSONArray) and (TJSONArray(Ranges).Count > 0) then
  begin
    Result.UseCount := TJSONArray(Ranges).Count;
    First := TJSONArray(Ranges).Items[0];
    Result.UseLine := First.GetValue<Integer>('start.line', Result.UseLine);
    Result.UseCharacter := First.GetValue<Integer>('start.character', Result.UseCharacter);
  end;
  Result.Forms := ImpactFormsOf(AEntry.GetValue('forms'));
  Result.Terminal := AEntry.GetValue<Boolean>('terminal', False);
  Result.Test := AEntry.GetValue<string>('test', '');
end;

/// <summary>Ein betroffener Test aus tests der Antwort auf atlas/impact.</summary>
function ImpactTestOf(AEntry: TJSONObject): TAtlasImpactTest;
begin
  Result := Default(TAtlasImpactTest);
  Result.Name := AEntry.GetValue<string>('name', '');
  Result.RunNames := RunNamesOf(AEntry.GetValue('run'), Result.Name);
  Result.FileName := TLspSessionJson.UriToPath(AEntry.GetValue<string>('uri', ''));
  Result.Line := AEntry.GetValue<Integer>('line', 0);
  Result.Level := AEntry.GetValue<Integer>('level', 0);
end;

/// <summary>Die Objekte eines JSON-Arrays; anderes und Nicht-Arrays ergeben nichts.</summary>
function ObjectsOf(const AValue: TJSONValue): TArray<TJSONObject>;
var
  Item: TJSONValue;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
  begin
    Exit;
  end;
  for Item in TJSONArray(AValue) do
  begin
    if Item is TJSONObject then
    begin
      Result := Result + [TJSONObject(Item)];
    end;
  end;
end;

class function TLspSessionJson.ImpactFromJson(const AValue: TJSONValue): TAtlasImpact;
var
  Root, Entry: TJSONObject;
begin
  Result := Default(TAtlasImpact);
  if not (AValue is TJSONObject) then
  begin
    Exit;
  end;
  Root := TJSONObject(AValue);
  Result.Symbol := HierarchyItemOf(Root.GetValue('symbol'));
  Result.SymbolForms := ImpactFormsOf(Root.GetValue('symbolForms'));
  Result.Depth := Root.GetValue<Integer>('depth', 0);
  Result.DepthReached := Root.GetValue<Boolean>('limits.depth', False);
  Result.CountReached := Root.GetValue<Boolean>('limits.count', False);
  Result.TimeReached := Root.GetValue<Boolean>('limits.time', False);
  Result.Unexpanded := Root.GetValue<Integer>('unexpanded', 0);
  Result.MaxPlaces := Root.GetValue<Integer>('maxPlaces', 0);
  Result.TimeoutMs := Root.GetValue<Integer>('timeoutMs', 0);
  for Entry in ObjectsOf(Root.GetValue('places')) do
  begin
    Result.Places := Result.Places + [ImpactPlaceOf(Entry)];
  end;
  for Entry in ObjectsOf(Root.GetValue('tests')) do
  begin
    Result.Tests := Result.Tests + [ImpactTestOf(Entry)];
  end;
end;

/// <summary>Die Werte eines JSON-Arrays als Text; kein Array ergibt nichts.</summary>
function ValuesOf(const AValue: TJSONValue): TArray<string>;
var
  Item: TJSONValue;
begin
  Result := nil;
  if AValue is TJSONArray then
  begin
    for Item in TJSONArray(AValue) do
    begin
      Result := Result + [Item.Value];
    end;
  end;
end;

/// <summary>Grund eines betroffenen Tests: der Weg ab der geänderten Stelle, ohne Weg nur sie; erschlossene
/// Gründe mit Zusatz.</summary>
function AffectedReasonOf(AReason: TJSONObject): string;
begin
  // Der Weg beginnt mit der geänderten Stelle; ohne Weg nur sie.
  Result := string.Join(' → ', ValuesOf(AReason.GetValue('path')));
  if Result = '' then
  begin
    Result := AReason.GetValue<string>('change', '');
  end;
  if AReason.GetValue<Boolean>('inferred', False) then
  begin
    Result := Result + ' (erschlossen)';
  end;
end;

/// <summary>Ein Test aus tests der Antwort auf atlas/affectedTests.</summary>
function AffectedTestOf(AEntry: TJSONObject): TAtlasAffectedTest;
var
  Reason: TJSONObject;
begin
  Result := Default(TAtlasAffectedTest);
  Result.Name := AEntry.GetValue<string>('name', '');
  Result.RunNames := RunNamesOf(AEntry.GetValue('run'), Result.Name);
  Result.FileName := TLspSessionJson.UriToPath(AEntry.GetValue<string>('uri', ''));
  Result.Line := AEntry.GetValue<Integer>('line', 0);
  for Reason in ObjectsOf(AEntry.GetValue('reasons')) do
  begin
    Result.Reasons := Result.Reasons + [AffectedReasonOf(Reason)];
  end;
end;

class function TLspSessionJson.AffectedTestsFromJson(const AValue: TJSONValue): TAtlasAffectedTests;
var
  mRoot, mEntry: TJSONObject;
begin
  Result := Default(TAtlasAffectedTests);
  if not (AValue is TJSONObject) then
  begin
    Exit;
  end;
  mRoot := TJSONObject(AValue);
  Result.Base := mRoot.GetValue<string>('base', '');
  Result.Depth := mRoot.GetValue<Integer>('depth', 0);
  Result.All := mRoot.GetValue<Boolean>('all', False);
  Result.AllReason := mRoot.GetValue<string>('reason', '');
  Result.Run := ValuesOf(mRoot.GetValue('run'));
  for mEntry in ObjectsOf(mRoot.GetValue('changes')) do
  begin
    Result.Changes := Result.Changes + [mEntry.GetValue<string>('name', '')];
  end;
  for mEntry in ObjectsOf(mRoot.GetValue('tests')) do
  begin
    Result.Tests := Result.Tests + [AffectedTestOf(mEntry)];
  end;
end;

class function TLspSessionJson.InlineValueRefsOf(const AResponse: TJSONValue): TAtlasInlineValueRefs;
var
  Item: TJSONValue;
  Entry: TJSONObject;
  Name: string;
begin
  Result := nil;
  if not (AResponse is TJSONArray) then
  begin
    Exit;
  end;
  for Item in TJSONArray(AResponse) do
  begin
    if not (Item is TJSONObject) then
    begin
      Continue;
    end;
    Entry := TJSONObject(Item);
    // InlineValueText (text) und InlineValueEvaluatableExpression (expression) wertet Atlas nicht aus.
    Name := Entry.GetValue<string>('variableName', '');
    if Name = '' then
    begin
      Continue;
    end;
    Result := Result + [TAtlasInlineValueRef.Create(Entry.GetValue<Integer>('range.start.line', -1),
      Entry.GetValue<Integer>('range.start.character', 0), Name, Entry.GetValue<string>('atlasType', ''))];
  end;
end;

class function TLspSessionJson.SettingsParams(const AJson: string): TJSONObject;
var
  Value: TJSONValue;
begin
  Value := TJSONObject.ParseJSONValue(AJson);
  if not (Value is TJSONObject) then
  begin
    Value.Free;
    Value := TJSONObject.Create;
  end;
  Result := TJSONObject.Create(TJSONPair.Create('settings', TJSONObject.Create(TJSONPair.Create('atlas', Value))));
end;

class function TLspSessionJson.ProjectFolders(const AProjects: TArray<string>): TJSONArray;
var
  Project: string;
begin
  Result := TJSONArray.Create;
  for Project in AProjects do
  begin
    Result.AddElement(TJSONObject.Create.AddPair('uri', PathToUri(Project))
      .AddPair('name', ChangeFileExt(ExtractFileName(Project), '')));
  end;
end;

function ContainsText_(const AValues: TArray<string>; const AValue: string): Boolean;
var
  Value: string;
begin
  for Value in AValues do
  begin
    if SameText(Value, AValue) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class procedure TLspSessionJson.ProjectChanges(const AOld, ANew: TArray<string>; out AAdded, ARemoved: TArray<string>);
var
  Project: string;
begin
  AAdded := nil;
  ARemoved := nil;
  for Project in ANew do
  begin
    if not ContainsText_(AOld, Project) and not ContainsText_(AAdded, Project) then
    begin
      AAdded := AAdded + [Project];
    end;
  end;
  for Project in AOld do
  begin
    if not ContainsText_(ANew, Project) and not ContainsText_(ARemoved, Project) then
    begin
      ARemoved := ARemoved + [Project];
    end;
  end;
end;

{ TLspCodeAction }

class function TLspCodeAction.FromJson(const AValue: TJSONValue; out AAction: TLspCodeAction): Boolean;
var
  Item, Command: TJSONObject;
  Arguments: TJSONArray;
  Value: TJSONValue;
begin
  AAction := Default(TLspCodeAction);
  AAction.ArgumentsJson := '[]';
  Result := (AValue is TJSONObject) and TJSONObject(AValue).TryGetValue<string>('title', AAction.Title);
  if not Result then
  begin
    Exit;
  end;
  Item := TJSONObject(AValue);
  // Ein Command hat "command" als String, eine CodeAction als Objekt.
  Value := Item.GetValue('command');
  if Value is TJSONString then
  begin
    Command := Item;
  end
  else if Value is TJSONObject then
  begin
    Command := TJSONObject(Value);
  end
  else
  begin
    Command := nil;
  end;
  if Command <> nil then
  begin
    AAction.Command := Command.GetValue<string>('command', '');
    if Command.TryGetValue<TJSONArray>('arguments', Arguments) then
    begin
      AAction.ArgumentsJson := Arguments.ToJSON;
    end;
  end;
  if Command = Item then
  begin
    Exit;
  end;
  AAction.Kind := Item.GetValue<string>('kind', '');
  AAction.Preferred := Item.GetValue<Boolean>('isPreferred', False);
  AAction.Disabled := Item.GetValue<string>('disabled.reason', '');
  AAction.Edit := TLspWorkspaceEdit.FromJson(Item.GetValue('edit'));
  AAction.Tag := Item.GetValue<string>('data.tag', '');
  AAction.Preview := Item.GetValue<string>('data.preview', '');
  if Item.TryGetValue<TJSONArray>('diagnostics', Arguments) and (Arguments.Count > 0) and
    (Arguments.Items[0] is TJSONObject) then
  begin
    AAction.Rule := TJSONObject(Arguments.Items[0]).GetValue<string>('code', '');
  end;
end;

{ TLspWorkspaceRun }

class function TLspWorkspaceRun.FromJson(const AResponse: TJSONValue): TLspWorkspaceRun;
var
  mRun: TJSONObject;
begin
  Result := Default(TLspWorkspaceRun);
  if not ((AResponse is TJSONObject) and TJSONObject(AResponse).TryGetValue<TJSONObject>('atlas.run', mRun)) then
  begin
    Exit;
  end;
  Result.Known := True;
  Result.Serial := mRun.GetValue<Integer>('serial', 0);
  Result.Active := mRun.GetValue<Boolean>('active', False);
  Result.Done := mRun.GetValue<Integer>('done', 0);
  Result.Total := mRun.GetValue<Integer>('total', 0);
  Result.Skipped := mRun.GetValue<Integer>('skipped', 0);
  Result.Paused := mRun.GetValue<string>('paused', '');
  Result.ElapsedMs := mRun.GetValue<Int64>('elapsedMs', 0);
end;

{ TLspDiagnosticReport }

class function TLspDiagnosticReport.FromJson(const AReport: TJSONObject; const AFileName: string): TLspDiagnosticReport;
var
  Items: TJSONValue;
  Uri: string;
begin
  Result := Default(TLspDiagnosticReport);
  Uri := AReport.GetValue<string>('uri', '');
  if Uri <> '' then
  begin
    Result.FileName := TLspSessionJson.UriToPath(Uri);
  end
  else
  begin
    Result.FileName := AFileName;
  end;
  Result.ResultId := AReport.GetValue<string>('resultId', '');
  Result.Unchanged := AReport.GetValue<string>('kind', 'full') = 'unchanged';
  Items := AReport.GetValue('items');
  if Items is TJSONArray then
  begin
    Result.Problems := TAtlasProblem.ListFromJson(TJSONArray(Items));
  end;
end;

{ TLspHoverParts }

function TLspHoverParts.Found: Boolean;
begin
  Result := Declaration <> '';
end;

class function TLspHoverParts.FromHover(const AHover: TJSONValue): TLspHoverParts;
var
  Parts: TJSONValue;
  Text: string;
  Paragraphs: TArray<string>;
begin
  Result := Default(TLspHoverParts);
  if not (AHover is TJSONObject) then
  begin
    Exit;
  end;
  Parts := TJSONObject(AHover).GetValue('atlas');
  if Parts is TJSONObject then
  begin
    Result.Declaration := TJSONObject(Parts).GetValue<string>('declaration', '');
    Result.UnitName := TJSONObject(Parts).GetValue<string>('unit', '');
    // Seit #654 ist "documentation" strukturiert; der Klartext steht in "documentationText".
    if not TJSONObject(Parts).TryGetValue<string>('documentationText', Result.Documentation) and
      (TJSONObject(Parts).GetValue('documentation') is TJSONString) then
    begin
      Result.Documentation := TJSONObject(Parts).GetValue('documentation').Value;
    end;
    Result.Value := TJSONObject(Parts).GetValue<string>('value', '');
    Result.Deprecation := TJSONObject(Parts).GetValue<string>('deprecation', '');
    Exit;
  end;
  // Ältere Server: Klartext, erster Absatz ist die Deklaration, der Rest Doku.
  Text := TLspSessionJson.HoverText(AHover).Replace(#13#10, #10).Trim;
  if Text = '' then
  begin
    Exit;
  end;
  Paragraphs := Text.Split([#10#10], 2);
  Result.Declaration := Paragraphs[0];
  if Length(Paragraphs) > 1 then
  begin
    Result.Documentation := Paragraphs[1];
  end;
end;

{ TLspFormatOptions }

class function TLspFormatOptions.Create(ATabSize: Integer; AInsertSpaces: Boolean): TLspFormatOptions;
begin
  Result.TabSize := ATabSize;
  Result.InsertSpaces := AInsertSpaces;
end;

end.
