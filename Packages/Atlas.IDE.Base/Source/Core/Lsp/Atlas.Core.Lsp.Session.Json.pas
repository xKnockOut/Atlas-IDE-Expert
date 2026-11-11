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
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Projects.Contract,
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

  /// <summary>Abwählbarer Teil einer Code-Aktion aus data.choices (#2054).</summary>
  TLspCodeActionChoice = record
    Title: string;
    /// <summary>0-basiert.</summary>
    Line: Integer;
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
    /// <summary>Abwählbare Teile aus data.choices (#2054); nil ohne.</summary>
    Choices: TArray<TLspCodeActionChoice>;
    /// <summary>Je Edit der einen Datei die Teile, die alle gewählt sein müssen (data.editChoices).</summary>
    EditChoices: TArray<TArray<Integer>>;
    /// <summary>Aus einem Eintrag der Antwort: CodeAction oder Command; False bei anderem.</summary>
    class function FromJson(const AValue: TJSONValue; out AAction: TLspCodeAction): Boolean; static;
    /// <summary>Die Aktion nur mit den Edits, deren Teile alle in AChosen gewählt sind (#2054). Ohne Teile oder
    /// bei mehr als einer Datei unverändert.</summary>
    function WithChoices(const AChosen: TArray<Boolean>): TLspCodeAction;
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
  /// <summary>Eigene Benachrichtigungen des Servers (atlas/…, etwa atlas/crashCase #1355, atlas/ideMembersWanted);
  /// läuft im Lese-Thread, AParams gehört dem Aufrufer.</summary>
  TLspAtlasNotificationProc = reference to procedure(const AMethod: string; const AParams: TJSONValue);

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
    /// <summary>Zeichenindex (0-basiert) zur Editorspalte (1-basiert); Tabs springen zur nächsten
    /// Tabulatorposition.</summary>
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
  System.StrUtils,
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
  mContents: TJSONValue;
  mItem: TJSONValue;
begin
  Result := '';
  if not (AHover is TJSONObject) then
  begin
    Exit;
  end;
  mContents := TJSONObject(AHover).GetValue('contents');
  if mContents is TJSONString then
  begin
    Result := TJSONString(mContents).Value;
  end
  else if mContents is TJSONObject then
  begin
    Result := TJSONObject(mContents).GetValue<string>('value', '');
  end
  else if mContents is TJSONArray then
  begin
    for mItem in TJSONArray(mContents) do
    begin
      if Result <> '' then
      begin
        Result := Result + sLineBreak;
      end;
      if mItem is TJSONString then
      begin
        Result := Result + TJSONString(mItem).Value;
      end
      else if mItem is TJSONObject then
      begin
        Result := Result + TJSONObject(mItem).GetValue<string>('value', '');
      end;
    end;
  end;
end;

class function TLspSessionJson.ColumnToIndex(const ALine: string; AColumn, ATabWidth: Integer): Integer;
var
  mVisual: Integer;
begin
  // Spalte 1 = erstes Zeichen. Tabs springen zur nächsten Tabulatorposition.
  Result := 0;
  mVisual := 1;
  while (Result < Length(ALine)) and (mVisual < AColumn) do
  begin
    if ALine[Result + 1] = #9 then
    begin
      mVisual := ((mVisual - 1) div ATabWidth + 1) * ATabWidth + 1;
    end
    else
    begin
      Inc(mVisual);
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
  mTextDocument, mHover: TJSONObject;
  mFormats: TJSONArray;
begin
  mFormats := TJSONArray.Create;
  mFormats.Add('plaintext');
  mHover := TJSONObject.Create;
  mHover.AddPair('contentFormat', mFormats);
  mTextDocument := TJSONObject.Create;
  mTextDocument.AddPair('hover', mHover);
  // Dokumentation der Vervollständigung als Klartext (#408). Snippets setzt das Plugin selbst mit Platzhalter-Modus
  // ein (#51); ob sie in der Liste erscheinen, regelt completion.snippets im Plugin.
  mTextDocument.AddPair('completion', TJSONObject.Create(TJSONPair.Create('completionItem',
    TJSONObject.Create.AddPair('snippetSupport', TJSONBool.Create(True))
      .AddPair('documentationFormat', TJSONArray.Create.Add('plaintext')))));
  // Diagnosen holt das Plugin selbst (#398); der Server bittet per refresh um neues Holen.
  mTextDocument.AddPair('diagnostic', TJSONObject.Create.AddPair('dynamicRegistration', TJSONBool.Create(False))
    .AddPair('relatedDocumentSupport', TJSONBool.Create(False)));
  Result := TJSONObject.Create;
  Result.AddPair('textDocument', mTextDocument);
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
  mOptions: TJSONObject;
  mContexts: TJSONArray;
  mContext: TAtlasProjectContext;
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
  mOptions := nil;
  if AServerSettings <> '' then
  begin
    mOptions := SettingsParams(AServerSettings);
  end;
  if Length(AContexts) > 0 then
  begin
    mContexts := TJSONArray.Create;
    for mContext in AContexts do
    begin
      mContexts.AddElement(mContext.ToJson);
    end;
    if mOptions = nil then
    begin
      mOptions := TJSONObject.Create;
    end;
    mOptions.AddPair('projectContexts', mContexts);
  end;
  // Sprache der Oberfläche (#1458): eigener Schlüssel für Atlas und das Feld locale aus LSP 3.16.
  if ALocale <> '' then
  begin
    Result.AddPair('locale', ALocale);
    if mOptions = nil then
    begin
      mOptions := TJSONObject.Create;
    end;
    mOptions.AddPair('locale', ALocale);
  end;
  if mOptions <> nil then
  begin
    Result.AddPair('initializationOptions', mOptions);
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
    mLocation: TLspLocation;
    mUri, mPrefix: string;
  begin
    if not (AItem is TJSONObject) then
    begin
      Exit;
    end;
    // LocationLink: targetUri und targetSelectionRange; Location: uri und range.
    mPrefix := 'range';
    if TJSONObject(AItem).TryGetValue<string>('targetUri', mUri) then
    begin
      mPrefix := 'targetSelectionRange';
    end
    else
    begin
      mUri := TJSONObject(AItem).GetValue<string>('uri', '');
    end;
    mLocation.FileName := UriToPath(mUri);
    mLocation.Line := TJSONObject(AItem).GetValue<Integer>(mPrefix + '.start.line', 0);
    mLocation.Character := TJSONObject(AItem).GetValue<Integer>(mPrefix + '.start.character', 0);
    mLocation.Confidence := TAtlasConfidence.FromJson(AItem);
    if mLocation.FileName <> '' then
    begin
      Result := Result + [mLocation];
    end;
  end;

var
  mItem: TJSONValue;
begin
  Result := nil;
  if AResponse is TJSONArray then
  begin
    for mItem in TJSONArray(AResponse) do
    begin
      Add(mItem);
    end;
  end
  else
  begin
    Add(AResponse);
  end;
end;

class function TLspSessionJson.IndexToColumn(const ALine: string; AIndex, ATabWidth: Integer): Integer;
var
  mIndex: Integer;
begin
  // Wie ColumnToIndex: Tabs springen zur nächsten Tabulatorposition, hinter dem Zeilenende je Zeichen eine Spalte.
  Result := 1;
  for mIndex := 1 to AIndex do
  begin
    if (mIndex <= Length(ALine)) and (ALine[mIndex] = #9) and (ATabWidth > 0) then
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
  mFound: TArray<TAtlasSymbol>;

  procedure AddAll(const AItems: TJSONValue; const AContainer: string);
  var
    mItem: TJSONValue;
    mEntry: TJSONObject;
    mSymbol: TAtlasSymbol;
    mLocations: TArray<TLspLocation>;
  begin
    if not (AItems is TJSONArray) then
    begin
      Exit;
    end;
    for mItem in TJSONArray(AItems) do
    begin
      if not (mItem is TJSONObject) then
      begin
        Continue;
      end;
      mEntry := TJSONObject(mItem);
      mSymbol := Default(TAtlasSymbol);
      mSymbol.Name := mEntry.GetValue<string>('name', '');
      mSymbol.Kind := mEntry.GetValue<Integer>('kind', 0);
      mSymbol.FileName := AFileName;
      if mEntry.GetValue('location') <> nil then
      begin
        // SymbolInformation: Ort und Container stehen am Eintrag.
        mSymbol.Container := mEntry.GetValue<string>('containerName', '');
        mLocations := LocationsOf(mEntry.GetValue('location'));
        if Length(mLocations) > 0 then
        begin
          mSymbol.FileName := mLocations[0].FileName;
          mSymbol.Line := mLocations[0].Line;
          mSymbol.Character := mLocations[0].Character;
        end;
      end
      else
      begin
        mSymbol.Container := AContainer;
        mSymbol.Line := mEntry.GetValue<Integer>('selectionRange.start.line',
          mEntry.GetValue<Integer>('range.start.line', 0));
        mSymbol.Character := mEntry.GetValue<Integer>('selectionRange.start.character',
          mEntry.GetValue<Integer>('range.start.character', 0));
      end;
      if mSymbol.Name <> '' then
      begin
        mFound := mFound + [mSymbol];
      end;
      AddAll(mEntry.GetValue('children'), mSymbol.Name);
    end;
  end;

begin
  mFound := nil;
  AddAll(AResponse, '');
  Result := mFound;
end;

class function TLspSessionJson.HierarchyItemOf(const AValue: TJSONValue): TAtlasHierarchyItem;
var
  mEntry: TJSONObject;
begin
  Result := Default(TAtlasHierarchyItem);
  if not (AValue is TJSONObject) then
  begin
    Exit;
  end;
  mEntry := TJSONObject(AValue);
  Result.Name := mEntry.GetValue<string>('name', '');
  Result.Detail := mEntry.GetValue<string>('detail', '');
  Result.Kind := mEntry.GetValue<Integer>('kind', 0);
  Result.FileName := UriToPath(mEntry.GetValue<string>('uri', ''));
  Result.Line := mEntry.GetValue<Integer>('selectionRange.start.line', 0);
  Result.Character := mEntry.GetValue<Integer>('selectionRange.start.character', 0);
  Result.Raw := mEntry.ToJSON;
end;

function ImpactFormsOf(const AValue: TJSONValue): TArray<TAtlasImpactForm>;
var
  mItem: TJSONValue;
  mForm: TAtlasImpactForm;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(AValue) do
  begin
    if mItem is TJSONObject then
    begin
      mForm.FileName := TLspSessionJson.UriToPath(TJSONObject(mItem).GetValue<string>('uri', ''));
      mForm.Line := TJSONObject(mItem).GetValue<Integer>('range.start.line', 0);
      mForm.Character := TJSONObject(mItem).GetValue<Integer>('range.start.character', 0);
      mForm.Text := TJSONObject(mItem).GetValue<string>('text', '');
      Result := Result + [mForm];
    end;
  end;
end;

/// <summary>Namen aus einem JSON-Array von Strings; ohne Einträge AFallback allein.</summary>
function RunNamesOf(const AValue: TJSONValue; const AFallback: string): TArray<string>;
var
  mName: TJSONValue;
begin
  Result := nil;
  if AValue is TJSONArray then
  begin
    for mName in TJSONArray(AValue) do
    begin
      Result := Result + [mName.Value];
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
  mRanges, mFirst: TJSONValue;
begin
  Result := Default(TAtlasImpactPlace);
  Result.Item := TLspSessionJson.HierarchyItemOf(AEntry.GetValue('item'));
  Result.Item.Confidence := TAtlasConfidence.FromJson(AEntry);
  Result.Level := AEntry.GetValue<Integer>('level', 0);
  Result.Edge := AEntry.GetValue<string>('edge', '');
  Result.Cause := AEntry.GetValue<Integer>('cause', -1);
  Result.UseLine := Result.Item.Line;
  Result.UseCharacter := Result.Item.Character;
  mRanges := AEntry.GetValue('ranges');
  if (mRanges is TJSONArray) and (TJSONArray(mRanges).Count > 0) then
  begin
    Result.UseCount := TJSONArray(mRanges).Count;
    mFirst := TJSONArray(mRanges).Items[0];
    Result.UseLine := mFirst.GetValue<Integer>('start.line', Result.UseLine);
    Result.UseCharacter := mFirst.GetValue<Integer>('start.character', Result.UseCharacter);
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
  mItem: TJSONValue;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(AValue) do
  begin
    if mItem is TJSONObject then
    begin
      Result := Result + [TJSONObject(mItem)];
    end;
  end;
end;

class function TLspSessionJson.ImpactFromJson(const AValue: TJSONValue): TAtlasImpact;
var
  mRoot, mEntry: TJSONObject;
begin
  Result := Default(TAtlasImpact);
  if not (AValue is TJSONObject) then
  begin
    Exit;
  end;
  mRoot := TJSONObject(AValue);
  Result.Symbol := HierarchyItemOf(mRoot.GetValue('symbol'));
  Result.SymbolForms := ImpactFormsOf(mRoot.GetValue('symbolForms'));
  Result.Depth := mRoot.GetValue<Integer>('depth', 0);
  Result.DepthReached := mRoot.GetValue<Boolean>('limits.depth', False);
  Result.CountReached := mRoot.GetValue<Boolean>('limits.count', False);
  Result.TimeReached := mRoot.GetValue<Boolean>('limits.time', False);
  Result.Unexpanded := mRoot.GetValue<Integer>('unexpanded', 0);
  Result.MaxPlaces := mRoot.GetValue<Integer>('maxPlaces', 0);
  Result.TimeoutMs := mRoot.GetValue<Integer>('timeoutMs', 0);
  for mEntry in ObjectsOf(mRoot.GetValue('places')) do
  begin
    Result.Places := Result.Places + [ImpactPlaceOf(mEntry)];
  end;
  for mEntry in ObjectsOf(mRoot.GetValue('tests')) do
  begin
    Result.Tests := Result.Tests + [ImpactTestOf(mEntry)];
  end;
end;

/// <summary>Die Werte eines JSON-Arrays als Text; kein Array ergibt nichts.</summary>
function ValuesOf(const AValue: TJSONValue): TArray<string>;
var
  mItem: TJSONValue;
begin
  Result := nil;
  if AValue is TJSONArray then
  begin
    for mItem in TJSONArray(AValue) do
    begin
      Result := Result + [mItem.Value];
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
  mReason: TJSONObject;
begin
  Result := Default(TAtlasAffectedTest);
  Result.Name := AEntry.GetValue<string>('name', '');
  Result.RunNames := RunNamesOf(AEntry.GetValue('run'), Result.Name);
  Result.FileName := TLspSessionJson.UriToPath(AEntry.GetValue<string>('uri', ''));
  Result.Line := AEntry.GetValue<Integer>('line', 0);
  for mReason in ObjectsOf(AEntry.GetValue('reasons')) do
  begin
    Result.Reasons := Result.Reasons + [AffectedReasonOf(mReason)];
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
  mItem: TJSONValue;
  mEntry: TJSONObject;
  mName: string;
begin
  Result := nil;
  if not (AResponse is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(AResponse) do
  begin
    if not (mItem is TJSONObject) then
    begin
      Continue;
    end;
    mEntry := TJSONObject(mItem);
    // InlineValueText (text) und InlineValueEvaluatableExpression (expression) wertet Atlas nicht aus.
    mName := mEntry.GetValue<string>('variableName', '');
    if mName = '' then
    begin
      Continue;
    end;
    Result := Result + [TAtlasInlineValueRef.Create(mEntry.GetValue<Integer>('range.start.line', -1),
      mEntry.GetValue<Integer>('range.start.character', 0), mName, mEntry.GetValue<string>('atlasType', ''))];
  end;
end;

class function TLspSessionJson.SettingsParams(const AJson: string): TJSONObject;
var
  mValue: TJSONValue;
begin
  mValue := TJSONObject.ParseJSONValue(AJson);
  if not (mValue is TJSONObject) then
  begin
    mValue.Free;
    mValue := TJSONObject.Create;
  end;
  Result := TJSONObject.Create(TJSONPair.Create('settings', TJSONObject.Create(TJSONPair.Create('atlas', mValue))));
end;

class function TLspSessionJson.ProjectFolders(const AProjects: TArray<string>): TJSONArray;
var
  mProject: string;
begin
  Result := TJSONArray.Create;
  for mProject in AProjects do
  begin
    Result.AddElement(TJSONObject.Create.AddPair('uri', PathToUri(mProject))
      .AddPair('name', ChangeFileExt(ExtractFileName(mProject), '')));
  end;
end;

class procedure TLspSessionJson.ProjectChanges(const AOld, ANew: TArray<string>; out AAdded, ARemoved: TArray<string>);
var
  mProject: string;
begin
  AAdded := nil;
  ARemoved := nil;
  for mProject in ANew do
  begin
    if not MatchText(mProject, AOld) and not MatchText(mProject, AAdded) then
    begin
      AAdded := AAdded + [mProject];
    end;
  end;
  for mProject in AOld do
  begin
    if not MatchText(mProject, ANew) and not MatchText(mProject, ARemoved) then
    begin
      ARemoved := ARemoved + [mProject];
    end;
  end;
end;

{ TLspCodeAction }

/// <summary>Ganzzahl aus AValue; -1, wenn es keine Zahl ist.</summary>
function NumberOf(AValue: TJSONValue): Integer;
begin
  Result := -1;
  if AValue is TJSONNumber then
  begin
    Result := TJSONNumber(AValue).AsInt;
  end;
end;

/// <summary>data.choices und data.editChoices (#2054).</summary>
procedure ReadChoices(AItem: TJSONObject; var AAction: TLspCodeAction);
var
  mChoices, mEditChoices: TJSONArray;
  mIndex, mInner: Integer;
  mChoice: TLspCodeActionChoice;
  mValue: TJSONValue;
  mNeeded: TArray<Integer>;
begin
  if not AItem.TryGetValue<TJSONArray>('data.choices', mChoices) then
  begin
    Exit;
  end;
  for mIndex := 0 to mChoices.Count - 1 do
  begin
    mChoice.Title := mChoices.Items[mIndex].GetValue<string>('title', '');
    mChoice.Line := mChoices.Items[mIndex].GetValue<Integer>('range.start.line', 0);
    AAction.Choices := AAction.Choices + [mChoice];
  end;
  if not AItem.TryGetValue<TJSONArray>('data.editChoices', mEditChoices) then
  begin
    Exit;
  end;
  SetLength(AAction.EditChoices, mEditChoices.Count);
  for mIndex := 0 to mEditChoices.Count - 1 do
  begin
    mNeeded := nil;
    mValue := mEditChoices.Items[mIndex];
    if mValue is TJSONArray then
    begin
      for mInner := 0 to TJSONArray(mValue).Count - 1 do
      begin
        mNeeded := mNeeded + [NumberOf(TJSONArray(mValue).Items[mInner])];
      end;
    end;
    AAction.EditChoices[mIndex] := mNeeded;
  end;
end;

/// <summary>Sind alle Teile in ANeeded in AChosen gewählt?</summary>
function AllChosen(const ANeeded: TArray<Integer>; const AChosen: TArray<Boolean>): Boolean;
var
  mChoice: Integer;
begin
  Result := True;
  for mChoice in ANeeded do
  begin
    Result := Result and (mChoice >= 0) and (mChoice <= High(AChosen)) and AChosen[mChoice];
  end;
end;

function TLspCodeAction.WithChoices(const AChosen: TArray<Boolean>): TLspCodeAction;
var
  mIndex: Integer;
  mKept: TArray<TLspTextEdit>;
begin
  Result := Self;
  if (Choices = nil) or (Length(Edit.Files) <> 1) then
  begin
    Exit;
  end;
  mKept := nil;
  for mIndex := 0 to High(Edit.Files[0].Edits) do
  begin
    if (mIndex > High(EditChoices)) or AllChosen(EditChoices[mIndex], AChosen) then
    begin
      mKept := mKept + [Edit.Files[0].Edits[mIndex]];
    end;
  end;
  // Eigene Kopie des Arrays: Result teilt sonst die Dateiliste mit Self.
  Result.Edit.Files := Copy(Edit.Files);
  Result.Edit.Files[0].Edits := mKept;
end;

class function TLspCodeAction.FromJson(const AValue: TJSONValue; out AAction: TLspCodeAction): Boolean;
var
  mItem, mCommand: TJSONObject;
  mArguments: TJSONArray;
  mValue: TJSONValue;
begin
  AAction := Default(TLspCodeAction);
  AAction.ArgumentsJson := '[]';
  Result := (AValue is TJSONObject) and TJSONObject(AValue).TryGetValue<string>('title', AAction.Title);
  if not Result then
  begin
    Exit;
  end;
  mItem := TJSONObject(AValue);
  // Ein Command hat "command" als String, eine CodeAction als Objekt.
  mValue := mItem.GetValue('command');
  if mValue is TJSONString then
  begin
    mCommand := mItem;
  end
  else if mValue is TJSONObject then
  begin
    mCommand := TJSONObject(mValue);
  end
  else
  begin
    mCommand := nil;
  end;
  if mCommand <> nil then
  begin
    AAction.Command := mCommand.GetValue<string>('command', '');
    if mCommand.TryGetValue<TJSONArray>('arguments', mArguments) then
    begin
      AAction.ArgumentsJson := mArguments.ToJSON;
    end;
  end;
  if mCommand = mItem then
  begin
    Exit;
  end;
  AAction.Kind := mItem.GetValue<string>('kind', '');
  AAction.Preferred := mItem.GetValue<Boolean>('isPreferred', False);
  AAction.Disabled := mItem.GetValue<string>('disabled.reason', '');
  AAction.Edit := TLspWorkspaceEdit.FromJson(mItem.GetValue('edit'));
  AAction.Tag := mItem.GetValue<string>('data.tag', '');
  AAction.Preview := mItem.GetValue<string>('data.preview', '');
  ReadChoices(mItem, AAction);
  if mItem.TryGetValue<TJSONArray>('diagnostics', mArguments) and (mArguments.Count > 0) and
    (mArguments.Items[0] is TJSONObject) then
  begin
    AAction.Rule := TJSONObject(mArguments.Items[0]).GetValue<string>('code', '');
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
  mItems: TJSONValue;
  mUri: string;
begin
  Result := Default(TLspDiagnosticReport);
  mUri := AReport.GetValue<string>('uri', '');
  if mUri <> '' then
  begin
    Result.FileName := TLspSessionJson.UriToPath(mUri);
  end
  else
  begin
    Result.FileName := AFileName;
  end;
  Result.ResultId := AReport.GetValue<string>('resultId', '');
  Result.Unchanged := AReport.GetValue<string>('kind', 'full') = 'unchanged';
  mItems := AReport.GetValue('items');
  if mItems is TJSONArray then
  begin
    Result.Problems := TAtlasProblem.ListFromJson(TJSONArray(mItems));
  end;
end;

{ TLspHoverParts }

function TLspHoverParts.Found: Boolean;
begin
  Result := Declaration <> '';
end;

class function TLspHoverParts.FromHover(const AHover: TJSONValue): TLspHoverParts;
var
  mParts: TJSONValue;
  mText: string;
  mParagraphs: TArray<string>;
begin
  Result := Default(TLspHoverParts);
  if not (AHover is TJSONObject) then
  begin
    Exit;
  end;
  mParts := TJSONObject(AHover).GetValue('atlas');
  if mParts is TJSONObject then
  begin
    Result.Declaration := TJSONObject(mParts).GetValue<string>('declaration', '');
    Result.UnitName := TJSONObject(mParts).GetValue<string>('unit', '');
    // Seit #654 ist "documentation" strukturiert; der Klartext steht in "documentationText".
    if not TJSONObject(mParts).TryGetValue<string>('documentationText', Result.Documentation) and
      (TJSONObject(mParts).GetValue('documentation') is TJSONString) then
    begin
      Result.Documentation := TJSONObject(mParts).GetValue('documentation').Value;
    end;
    Result.Value := TJSONObject(mParts).GetValue<string>('value', '');
    Result.Deprecation := TJSONObject(mParts).GetValue<string>('deprecation', '');
    Exit;
  end;
  // Ältere Server: Klartext, erster Absatz ist die Deklaration, der Rest Doku.
  mText := TLspSessionJson.HoverText(AHover).Replace(#13#10, #10).Trim;
  if mText = '' then
  begin
    Exit;
  end;
  mParagraphs := mText.Split([#10#10], 2);
  Result.Declaration := mParagraphs[0];
  if Length(mParagraphs) > 1 then
  begin
    Result.Documentation := mParagraphs[1];
  end;
end;

{ TLspFormatOptions }

class function TLspFormatOptions.Create(ATabSize: Integer; AInsertSpaces: Boolean): TLspFormatOptions;
begin
  Result.TabSize := ATabSize;
  Result.InsertSpaces := AInsertSpaces;
end;

end.
