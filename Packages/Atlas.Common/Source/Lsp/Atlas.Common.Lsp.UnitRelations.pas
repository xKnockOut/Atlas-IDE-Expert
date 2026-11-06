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
// Befehl atlas.useUnitInfo (#786, „Unit verwenden“, Alt+F11): Argumente
//   [uri] liefert {"found", "unit", "file", "inUses" (die Einträge beider
//   uses-Listen, wie geschrieben, nach den aktiven Defines), "cycles" (je
//   Unit, die die Unit schon verwendet: "name", "file", "path" und, wenn der
//   Rückweg nur über interface-uses führt, "interfacePath"), "generation"}.
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
  Atlas.Common.Editing.Contract,
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
    UseUnitCommand = 'atlas.useUnitInfo';
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
    /// <summary>Befehl atlas.useUnitInfo [uri] (#786).</summary>
    function UseUnitInfo(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Edits, die AUnit in den Abschnitt ATarget verschieben; False mit AError.</summary>
    class function MoveEdits(const AText, AUnit: string; ATarget: TUsesSection; out AEdits: TArray<TTextEdit>;
      out AError: string): Boolean; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.StrUtils,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Lsp.ApplyEdit,
  Atlas.Common.Lsp.InactiveRegions,
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TUnitRelationsText = (FileMissing, UriMissing, DepthIs0AllLevels, TheUsesListsCannotBe,
    TargetIsInterfaceOrImplementation, ProgramsAndPackagesHaveOnly, WithoutAnIndexItCannot, CannotBeRemoved,
    IsUsedOrMissing, IsAlreadyInTheUses, IsInNoUsesList, ArgumentsUriUnit);

const
  cTexts: array[TUnitRelationsText] of TAtlasText = (
    (De: 'Datei fehlt'; En: 'File missing'),
    (De: '"uri" fehlt'; En: '"uri" missing'),
    (De: '"depth" ist 0 (alle Ebenen) oder größer'; En: '"depth" is 0 (all levels) or greater'),
    (De: 'Die uses-Listen lassen sich nicht umschreiben (Direktive, Kommentar oder Programm)';
     En: 'The uses lists cannot be rewritten (directive, comment or program)'),
    (De: 'Ziel ist interface oder implementation'; En: 'Target is interface or implementation'),
    (De: 'Programme und Packages haben nur ein uses'; En: 'Programs and packages have only one uses'),
    (De: 'Ohne Index lässt sich nicht prüfen, ob %s ungenutzt ist';
     En: 'Without an index it cannot be checked whether %s is unused'),
    (De: ' lässt sich nicht entfernen'; En: ' cannot be removed'),
    (De: ' wird verwendet oder fehlt'; En: ' is used or missing'),
    (De: '%s steht schon im %s-uses'; En: '%s is already in the %s uses'),
    (De: '%s steht in keiner uses-Liste'; En: '%s is in no uses list'),
    (De: 'Argumente: [uri, Unit]'; En: 'Arguments: [uri, unit]'));

{$SCOPEDENUMS OFF}

function PathOf(const AText: string): string;
begin
  if StartsText('file:', AText) then
  begin
    Result := TDocumentUris.ToPath(AText);
  end
  else
  begin
    Result := AText;
  end;
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
  begin
    Result := '';
  end;
end;

function TLspUnitRelations.DefinesOf(const AFileName: string): TArray<string>;
begin
  Result := nil;
  if Assigned(FDefines) then
  begin
    Result := FDefines(AFileName);
  end;
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
  begin
    Exit;
  end;
  // Dieselbe Analyse wie die abgeblendeten uses im Editor (#621).
  for Entry in TUsesActions.Entries(TPascalLexer.Tokenize(AText), TLspInactiveRegions.Ranges(AText,
    DefinesOf(AFileName)), Context.Info, Context.Keep) do
  begin
    if Entry.State = TUsesEntryState.Unused then
    begin
      AUnused := AUnused + [Entry.Name];
    end
    else if Entry.State = TUsesEntryState.OnlyImplementation then
    begin
      AOnlyImplementation := AOnlyImplementation + [Entry.Name];
    end;
  end;
end;

procedure TLspUnitRelations.EnsureOptions(const AFileName: string);
var
  Options: TUsesGraphOptions;
begin
  if not Assigned(FOptionsFor) then
  begin
    Exit;
  end;
  Options := FOptionsFor(AFileName);
  // Bibliotheks-Units immer: „Verwendet“ zeigt sie mit Datei, soweit der Index sie kennt.
  Options.IncludeLibrary := True;
  if not SameOptions(Options, FGraph.Options) then
  begin
    FGraph.SetOptions(Options);
  end;
end;

function TLspUnitRelations.FileOf(const AArguments: TJSONArray; AIndex: Integer): string;
begin
  Result := '';
  if (AArguments <> nil) and (AArguments.Count > AIndex) and (AArguments.Items[AIndex] is TJSONString) then
  begin
    Result := PathOf(Trim(AArguments.Items[AIndex].Value));
  end;
  if Result = '' then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, cTexts[TUnitRelationsText.FileMissing].Text);
  end;
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
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, cTexts[TUnitRelationsText.UriMissing].Text);
  end;
  Params := TJSONObject(AParams);
  FileName := '';
  if Params.GetValue('uri') is TJSONString then
  begin
    FileName := PathOf(Trim(Params.GetValue('uri').Value));
  end;
  if FileName = '' then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, cTexts[TUnitRelationsText.UriMissing].Text);
  end;
  Depth := 1;
  if Params.TryGetValue<Double>('depth', Number) then
  begin
    Depth := Trunc(Number);
  end;
  if Depth < 0 then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, cTexts[TUnitRelationsText.DepthIs0AllLevels].Text);
  end;
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
      begin
        if Pair.JsonString.Value <> 'uri' then
        begin
          Params.AddPair(Pair.JsonString.Value, TJSONValue(Pair.JsonValue.Clone));
        end;
      end;
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

function TLspUnitRelations.UseUnitInfo(const AArguments: TJSONArray): TJSONValue;
var
  FileName: string;
  Answer: TJSONObject;
  List: TJSONArray;
  Reference: TUsesReference;
begin
  FileName := FileOf(AArguments, 0);
  EnsureOptions(FileName);
  Answer := nil;
  FGraph.Read(
    procedure(const AGraph: TUsesGraph)
    begin
      Answer := TUnitRelationsBuilder.UseInfoToJson(TUnitRelationsBuilder.UseCandidates(AGraph, FileName));
    end);
  // „schon in uses“ aus dem Text, wie ihn der Editor gerade hat.
  List := TJSONArray.Create;
  for Reference in TUsesLocator.UsesReferences(TextOf(FileName), DefinesOf(FileName)) do
  begin
    List.Add(Reference.Name);
  end;
  Answer.AddPair('inUses', List);
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
  begin
    if (Reference.List = TUsesListKind.UsesList) and SameText(Reference.Name, AUnit) then
    begin
      if Reference.InInterface = (ATarget = TUsesSection.Interface_) then
      begin
        AError := cTexts[TUnitRelationsText.IsAlreadyInTheUses].Fmt([AUnit,
          TUnitRelationsBuilder.SectionName(ATarget)]);
        Exit(False);
      end;
      Found := True;
      Name := Reference.Name;
    end;
  end;
  if not Found then
  begin
    AError := cTexts[TUnitRelationsText.IsInNoUsesList].Fmt([AUnit]);
    Exit(False);
  end;
  if ATarget = TUsesSection.Implementation_ then
  begin
    Result := TUsesActions.MoveUnits(Tokens, AText, [Name], TTextLines.LineBreakOf(AText), AEdits);
  end
  else
  begin
    Result := TUsesActions.MoveUnitsToInterface(Tokens, AText, [Name], TTextLines.LineBreakOf(AText), AEdits);
  end;
  if not Result then
  begin
    AError := cTexts[TUnitRelationsText.TheUsesListsCannotBe].Text;
  end;
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
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Argumente: [uri, Unit, interface|implementation]');
  end;
  UnitName := Trim(AArguments.Items[1].Value);
  Target := Trim(AArguments.Items[2].Value);
  if SameText(Target, 'interface') then
  begin
    Section := TUsesSection.Interface_;
  end
  else if SameText(Target, 'implementation') then
  begin
    Section := TUsesSection.Implementation_;
  end
  else
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      cTexts[TUnitRelationsText.TargetIsInterfaceOrImplementation].Text);
  end;
  Extension := LowerCase(ExtractFileExt(FileName));
  if (Extension = '.dpr') or (Extension = '.dpk') then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      cTexts[TUnitRelationsText.ProgramsAndPackagesHaveOnly].Text);
  end;
  if not MoveEdits(TextOf(FileName), UnitName, Section, Edits, Error) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, Error);
  end;
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
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, cTexts[TUnitRelationsText.ArgumentsUriUnit].Text);
  end;
  UnitName := Trim(AArguments.Items[1].Value);
  Text := TextOf(FileName);
  if (Text = '') or not Assigned(FUsesContextFor) or
    not FUsesContextFor(TDocumentUris.FromPath(FileName), Context) or not Assigned(Context.Info) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, cTexts[TUnitRelationsText.WithoutAnIndexItCannot].Fmt([
      UnitName]));
  end;
  Found := False;
  for Entry in TUsesActions.Entries(TPascalLexer.Tokenize(Text), TLspInactiveRegions.Ranges(Text,
    DefinesOf(FileName)), Context.Info, Context.Keep) do
  begin
    if (Entry.State = TUsesEntryState.Unused) and SameText(Entry.Name, UnitName) then
    begin
      if not TUsesActions.RemoveEntries(Text, [Entry.Range], Edit) then
      begin
        raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, UnitName +
          cTexts[TUnitRelationsText.CannotBeRemoved].Text);
      end;
      Found := True;
      Break;
    end;
  end;
  if not Found then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, UnitName +
      cTexts[TUnitRelationsText.IsUsedOrMissing].Text);
  end;
  Answer := TJSONObject.Create;
  Answer.AddPair('edit', TLspApplyEdit.TextEdits(FileName, [Edit]));
  Result := Answer;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.UnitRelations', cTexts);

end.
