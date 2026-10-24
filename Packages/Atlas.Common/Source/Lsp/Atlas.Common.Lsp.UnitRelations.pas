unit Atlas.Common.Lsp.UnitRelations;

// Unit-Beziehungen (#593) im LSP-Server.
//
// Anfrage atlas/unitRelations (nebenläufig im Arbeitsthread):
//   params {"uri": Datei der Unit, "depth": 1 (Vorgabe, direkt), n Ebenen
//           oder 0 (alle Ebenen)}
//   Antwort TUnitRelationsBuilder.ToJson samt "generation" (Index-Stand, an
//   dem das Plugin seinen Zwischenspeicher misst): "found", "unit", "file",
//   "recompileCount", "dependencies", "dependents", "inCycle",
//   "cyclePath", "uses" und "usedBy" mit je "name", "file", "section"
//   (interface/implementation), "library", "cycle", "cyclePath", "unused",
//   "onlyImplementation" (interface-Eintrag, der nur im implementation-Teil
//   gebraucht wird, #554), "repeated", "location" {file, line, character}
//   und "children".
// Befehl atlas.unitRelations: Argumente [uri, {"depth": n}], Antwort wie oben
//   (für RunCommandAsync des Plugins).
// Befehl atlas.server.moveUses: Argumente [uri, Unit, "interface" |
//   "implementation"] verschiebt den Eintrag in die andere Liste
//   (TUsesActions, #284); Antwort {"edit": WorkspaceEdit}, das der Client
//   anwendet (#397). Fehler, wenn der Eintrag nicht in der anderen Liste
//   steht oder eine Liste nicht schlicht ist.
// Befehl atlas.server.removeUses: Argumente [uri, Unit] streicht einen
//   ungenutzten Eintrag (dieselbe Analyse wie die abgeblendeten uses, #621);
//   Antwort {"edit": …}. Benutzte Einträge lehnt er ab.
// Befehl atlas.interfaceCost (#554): Argumente [uri] liefert die Kosten einer
//   Änderung im interface-Teil für die Statusleiste: {"found", "unit",
//   "file", "recompileCount", "units" (die ersten CostUnits Namen),
//   "generation"}. Ohne Text, Fundstellen und Bäume, also billig genug, um
//   beim Tippen nachzufragen.
//
// Der Graph enthält Bibliotheks-Units (soweit im Index), damit „Verwendet“
// sie mit Datei zeigt; Namensräume kommen je Datei aus OptionsFor.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Editing.UsesActions,
  Atlas.Common.Architecture.UsesGraph,
  Atlas.Common.Architecture.UsesLocator,
  Atlas.Common.Architecture.UsesService,
  Atlas.Common.Architecture.UnitRelations,
  Atlas.Common.Lsp.SyntaxDiagnostics;

type
  /// <summary>Optionen des Graphen für die Datei (Namensräume und Wurzel ihres Projekts).</summary>
  TLspUnitRelationsOptionsFunc = reference to function(const AFileName: string): TUsesGraphOptions;

  TLspUnitRelations = class
  public const
    Method = 'atlas/unitRelations';
    Command = 'atlas.unitRelations';
    MoveCommand = 'atlas.server.moveUses';
    RemoveCommand = 'atlas.server.removeUses';
    CostCommand = 'atlas.interfaceCost';
    /// <summary>So viele Namen nennt atlas.interfaceCost höchstens.</summary>
    CostUnits = 10;
  private
    FGraph: TUsesGraphService;
    FLocator: TUsesLocator;
    FReader: TUsesTextReader;
    FDefines: TUsesDefinesFunc;
    FUsesContextFor: TUsesContextProvider;
    FOptionsFor: TLspUnitRelationsOptionsFunc;
    function TextOf(const AFileName: string): string;
    function DefinesOf(const AFileName: string): TArray<string>;
    procedure EntriesOf(const AFileName, AText: string; out AUnused, AOnlyImplementation: TArray<string>);
    procedure EnsureOptions(const AFileName: string);
    function FileOf(const AArguments: TJSONArray; AIndex: Integer): string;
  public
    /// <summary>AGraph gehört dem Aufrufer; AUsesContextFor wie bei den Code-Aktionen (für Unused).</summary>
    constructor Create(AGraph: TUsesGraphService; const AReader: TUsesTextReader; const ADefines: TUsesDefinesFunc;
      const AUsesContextFor: TUsesContextProvider; const AOptionsFor: TLspUnitRelationsOptionsFunc);
    destructor Destroy; override;
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Antwort auf atlas/unitRelations; der Aufrufer übernimmt das Ergebnis.</summary>
    function Request(const AParams: TJSONValue): TJSONValue;
    /// <summary>Befehl atlas.unitRelations [uri, Optionen].</summary>
    function Execute(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Befehl atlas.server.moveUses [uri, Unit, Ziel].</summary>
    function Move(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Befehl atlas.server.removeUses [uri, Unit].</summary>
    function Remove(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Befehl atlas.interfaceCost [uri] (#554).</summary>
    function Cost(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Edits, die AUnit in den Abschnitt ATarget verschieben; False mit AError.</summary>
    class function MoveEdits(const AText, AUnit: string; ATarget: TUsesSection; out AEdits: TArray<TTextEdit>;
      out AError: string): Boolean; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Lsp.ApplyEdit,
  Atlas.Common.Lsp.InactiveRegions,
  Atlas.Text.Lines;

function PathOf(const AText: string): string;
begin
  if StartsText('file:', AText) then
    Result := TDocumentUris.ToPath(AText)
  else
    Result := AText;
end;

function SameOptions(const A, B: TUsesGraphOptions): Boolean;
begin
  Result := (A.IncludeLibrary = B.IncludeLibrary) and SameText(A.Root, B.Root) and
    SameText(string.Join(#1, A.Exclude), string.Join(#1, B.Exclude)) and
    SameText(string.Join(#1, A.Namespaces), string.Join(#1, B.Namespaces));
end;

{ TLspUnitRelations }

constructor TLspUnitRelations.Create(AGraph: TUsesGraphService; const AReader: TUsesTextReader;
  const ADefines: TUsesDefinesFunc; const AUsesContextFor: TUsesContextProvider;
  const AOptionsFor: TLspUnitRelationsOptionsFunc);
begin
  inherited Create;
  FGraph := AGraph;
  FReader := AReader;
  FDefines := ADefines;
  FUsesContextFor := AUsesContextFor;
  FOptionsFor := AOptionsFor;
  FLocator := TUsesLocator.Create(AReader, ADefines);
end;

destructor TLspUnitRelations.Destroy;
begin
  FLocator.Free;
  inherited;
end;

procedure TLspUnitRelations.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(Method,
    function(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue
    begin
      Result := Request(AParams);
    end);
end;

function TLspUnitRelations.TextOf(const AFileName: string): string;
begin
  if not (Assigned(FReader) and FReader(AFileName, Result)) then
    Result := '';
end;

function TLspUnitRelations.DefinesOf(const AFileName: string): TArray<string>;
begin
  Result := nil;
  if Assigned(FDefines) then
    Result := FDefines(AFileName);
end;

procedure TLspUnitRelations.EntriesOf(const AFileName, AText: string; out AUnused,
  AOnlyImplementation: TArray<string>);
var
  Context: TUsesContext;
  Entry: TUsesEntry;
begin
  AUnused := nil;
  AOnlyImplementation := nil;
  if (AText = '') or not Assigned(FUsesContextFor) or
    not FUsesContextFor(TDocumentUris.FromPath(AFileName), Context) or not Assigned(Context.Info) then
    Exit;
  // Dieselbe Analyse wie die abgeblendeten uses im Editor (#621).
  for Entry in TUsesActions.Entries(TPascalLexer.Tokenize(AText), TLspInactiveRegions.Ranges(AText,
    DefinesOf(AFileName)), Context.Info, Context.Keep) do
    if Entry.State = TUsesEntryState.Unused then
      AUnused := AUnused + [Entry.Name]
    else if Entry.State = TUsesEntryState.OnlyImplementation then
      AOnlyImplementation := AOnlyImplementation + [Entry.Name];
end;

procedure TLspUnitRelations.EnsureOptions(const AFileName: string);
var
  Options: TUsesGraphOptions;
begin
  if not Assigned(FOptionsFor) then
    Exit;
  Options := FOptionsFor(AFileName);
  // Bibliotheks-Units immer: „Verwendet“ zeigt sie mit Datei, soweit der Index sie kennt.
  Options.IncludeLibrary := True;
  if not SameOptions(Options, FGraph.Options) then
    FGraph.SetOptions(Options);
end;

function TLspUnitRelations.FileOf(const AArguments: TJSONArray; AIndex: Integer): string;
begin
  Result := '';
  if (AArguments <> nil) and (AArguments.Count > AIndex) and (AArguments.Items[AIndex] is TJSONString) then
    Result := PathOf(Trim(AArguments.Items[AIndex].Value));
  if Result = '' then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Datei fehlt');
end;

function TLspUnitRelations.Request(const AParams: TJSONValue): TJSONValue;
var
  Params, Answer: TJSONObject;
  FileName, Text: string;
  Depth: Integer;
  Number: Double;
  Unused, OnlyImplementation: TArray<string>;
  Relations: TUnitRelations;
begin
  if not (AParams is TJSONObject) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, '"uri" fehlt');
  Params := TJSONObject(AParams);
  FileName := '';
  if Params.GetValue('uri') is TJSONString then
    FileName := PathOf(Trim(Params.GetValue('uri').Value));
  if FileName = '' then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, '"uri" fehlt');
  Depth := 1;
  if Params.TryGetValue<Double>('depth', Number) then
    Depth := Trunc(Number);
  if Depth < 0 then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, '"depth" ist 0 (alle Ebenen) oder größer');
  Text := TextOf(FileName);
  EntriesOf(FileName, Text, Unused, OnlyImplementation);
  EnsureOptions(FileName);
  Answer := nil;
  FGraph.Read(
    procedure(const AGraph: TUsesGraph)
    var
      Builder: TUnitRelationsBuilder;
    begin
      Builder := TUnitRelationsBuilder.Create(AGraph, FLocator, FReader, FDefines);
      try
        Relations := Builder.Build(FileName, Depth, Unused, OnlyImplementation);
      finally
        Builder.Free;
      end;
      Answer := TUnitRelationsBuilder.ToJson(Relations);
    end);
  Answer.AddPair('generation', TJSONNumber.Create(FGraph.Generation));
  Answer.AddPair('depth', TJSONNumber.Create(Depth));
  Result := Answer;
end;

function TLspUnitRelations.Execute(const AArguments: TJSONArray): TJSONValue;
var
  Params: TJSONObject;
  Options: TJSONObject;
  Pair: TJSONPair;
begin
  Params := TJSONObject.Create;
  try
    Params.AddPair('uri', FileOf(AArguments, 0));
    if (AArguments.Count > 1) and (AArguments.Items[1] is TJSONObject) then
    begin
      Options := TJSONObject(AArguments.Items[1]);
      for Pair in Options do
        if Pair.JsonString.Value <> 'uri' then
          Params.AddPair(Pair.JsonString.Value, TJSONValue(Pair.JsonValue.Clone));
    end;
    Result := Request(Params);
  finally
    Params.Free;
  end;
end;

function TLspUnitRelations.Cost(const AArguments: TJSONArray): TJSONValue;
var
  FileName: string;
  Answer: TJSONObject;
begin
  FileName := FileOf(AArguments, 0);
  EnsureOptions(FileName);
  Answer := nil;
  FGraph.Read(
    procedure(const AGraph: TUsesGraph)
    begin
      Answer := TUnitRelationsBuilder.CostToJson(TUnitRelationsBuilder.InterfaceCost(AGraph, FileName, CostUnits));
    end);
  Answer.AddPair('generation', TJSONNumber.Create(FGraph.Generation));
  Result := Answer;
end;

class function TLspUnitRelations.MoveEdits(const AText, AUnit: string; ATarget: TUsesSection;
  out AEdits: TArray<TTextEdit>; out AError: string): Boolean;
var
  Tokens: TArray<TPascalToken>;
  Reference: TUsesReference;
  Found: Boolean;
  Name: string;
begin
  AEdits := nil;
  AError := '';
  Tokens := TPascalLexer.Tokenize(AText);
  // Den Eintrag in der anderen Liste suchen, Schreibweise wie im Quelltext.
  Found := False;
  Name := AUnit;
  for Reference in TUsesClauses.References(Tokens) do
    if (Reference.List = TUsesListKind.UsesList) and SameText(Reference.Name, AUnit) then
    begin
      if Reference.InInterface = (ATarget = TUsesSection.Interface_) then
      begin
        AError := Format('%s steht schon im %s-uses', [AUnit, TUnitRelationsBuilder.SectionName(ATarget)]);
        Exit(False);
      end;
      Found := True;
      Name := Reference.Name;
    end;
  if not Found then
  begin
    AError := Format('%s steht in keiner uses-Liste', [AUnit]);
    Exit(False);
  end;
  if ATarget = TUsesSection.Implementation_ then
    Result := TUsesActions.MoveUnits(Tokens, AText, [Name], TTextLines.LineBreakOf(AText), AEdits)
  else
    Result := TUsesActions.MoveUnitsToInterface(Tokens, AText, [Name], TTextLines.LineBreakOf(AText), AEdits);
  if not Result then
    AError := 'Die uses-Listen lassen sich nicht umschreiben (Direktive, Kommentar oder Programm)';
end;

function TLspUnitRelations.Move(const AArguments: TJSONArray): TJSONValue;
var
  FileName, UnitName, Target, Error, Extension: string;
  Section: TUsesSection;
  Edits: TArray<TTextEdit>;
  Answer: TJSONObject;
begin
  FileName := FileOf(AArguments, 0);
  if (AArguments.Count < 3) or not (AArguments.Items[1] is TJSONString) or
    not (AArguments.Items[2] is TJSONString) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Argumente: [uri, Unit, interface|implementation]');
  UnitName := Trim(AArguments.Items[1].Value);
  Target := Trim(AArguments.Items[2].Value);
  if SameText(Target, 'interface') then
    Section := TUsesSection.Interface_
  else if SameText(Target, 'implementation') then
    Section := TUsesSection.Implementation_
  else
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Ziel ist interface oder implementation');
  Extension := LowerCase(ExtractFileExt(FileName));
  if (Extension = '.dpr') or (Extension = '.dpk') then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Programme und Packages haben nur ein uses');
  if not MoveEdits(TextOf(FileName), UnitName, Section, Edits, Error) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, Error);
  Answer := TJSONObject.Create;
  Answer.AddPair('edit', TLspApplyEdit.TextEdits(FileName, Edits));
  Result := Answer;
end;

function TLspUnitRelations.Remove(const AArguments: TJSONArray): TJSONValue;
var
  FileName, UnitName, Text: string;
  Entry: TUsesEntry;
  Context: TUsesContext;
  Edit: TTextEdit;
  Answer: TJSONObject;
  Found: Boolean;
begin
  FileName := FileOf(AArguments, 0);
  if (AArguments.Count < 2) or not (AArguments.Items[1] is TJSONString) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Argumente: [uri, Unit]');
  UnitName := Trim(AArguments.Items[1].Value);
  Text := TextOf(FileName);
  if (Text = '') or not Assigned(FUsesContextFor) or
    not FUsesContextFor(TDocumentUris.FromPath(FileName), Context) or not Assigned(Context.Info) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Ohne Index lässt sich nicht prüfen, ob ' +
      UnitName + ' ungenutzt ist');
  Found := False;
  for Entry in TUsesActions.Entries(TPascalLexer.Tokenize(Text), TLspInactiveRegions.Ranges(Text,
    DefinesOf(FileName)), Context.Info, Context.Keep) do
    if (Entry.State = TUsesEntryState.Unused) and SameText(Entry.Name, UnitName) then
    begin
      if not TUsesActions.RemoveEntries(Text, [Entry.Range], Edit) then
        raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, UnitName + ' lässt sich nicht entfernen');
      Found := True;
      Break;
    end;
  if not Found then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, UnitName + ' wird verwendet oder fehlt');
  Answer := TJSONObject.Create;
  Answer.AddPair('edit', TLspApplyEdit.TextEdits(FileName, [Edit]));
  Result := Answer;
end;

end.
