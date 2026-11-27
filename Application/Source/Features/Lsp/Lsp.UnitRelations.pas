unit Lsp.UnitRelations;

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
//   "generation", "graph"}. Ohne Text, Fundstellen und Bäume, also billig
//   genug, um beim Tippen nachzufragen. Wartet nie auf den Aufbau des
//   Graphen (#3075): Fehlt er für das Projekt der Datei oder rechnet gerade
//   ein anderer, antwortet der Befehl sofort {"pending": true} und der Graph
//   entsteht im Hintergrund; das Plugin fragt kurz darauf noch einmal.
//   "graph" (und im Diagnoselog usesGraph=) sagt, wie der Graph vorgefunden
//   wurde: current, updated, rebuilt, stale (älterer Stand, Abgleich läuft)
//   oder pending.
// Befehl atlas.useUnitInfo (#786, „Unit verwenden“, Alt+F11): Argumente
//   [uri] liefert {"found", "unit", "file", "inUses" (die Einträge beider
//   uses-Listen, wie geschrieben, nach den aktiven Defines), "cycles" (je
//   Unit, die die Unit schon verwendet: "name", "file", "path" und, wenn der
//   Rückweg nur über interface-uses führt, "interfacePath"), "generation"}.
//
// Der Graph enthält Bibliotheks-Units (soweit im Index), damit „Verwendet“
// sie mit Datei zeigt; Namensräume und Wurzel kommen je Datei aus OptionsFor.
// Je Optionssatz hält der Dienst einen eigenen Graphen (#3075), ein Wechsel
// zwischen Projekten der Gruppe baut ihn also nicht jedes Mal neu auf.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Architecture.UsesGraph,
  Atlas.Common.Architecture.UsesLocator,
  Atlas.Common.Architecture.UsesService,
  Lsp.SyntaxDiagnostics;

type
  /// <summary>Optionen des Graphen für die Datei (Namensräume und Wurzel ihres Projekts).</summary>
  TLspUnitRelationsOptionsFunc = reference to function(const AFileName: string): TUsesGraphOptions;

  TLspUnitRelations = class
  public const
    cMethod = 'atlas/unitRelations';
    cCommand = 'atlas.unitRelations';
    cMoveCommand = 'atlas.server.moveUses';
    cRemoveCommand = 'atlas.server.removeUses';
    cCostCommand = 'atlas.interfaceCost';
    cUseUnitCommand = 'atlas.useUnitInfo';
    /// <summary>So viele Namen nennt atlas.interfaceCost höchstens.</summary>
    cCostUnits = 10;
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
    function OptionsOf(const AFileName: string): TUsesGraphOptions;
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
    /// <summary>Befehl atlas.interfaceCost [uri] (#554); wartet nicht auf den Graphen (#3075).</summary>
    function Cost(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Befehl atlas.useUnitInfo [uri] (#786).</summary>
    function UseUnitInfo(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Edits, die AUnit in den Abschnitt ATarget verschieben; False mit AError.</summary>
    class function MoveEdits(const AText, AUnit: string; ATarget: TUsesSection; out AEdits: TArray<TTextEdit>;
      out AError: string): Boolean; static;
  end;

implementation

uses
  Atlas.Common.Semantics.UsesActions,
  Atlas.Common.Architecture.UnitRelations,
  System.Generics.Collections,
  System.StrUtils,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.UsesClauses,
  Atlas.Common.JsonRpc.ApplyEdit,
  Atlas.Common.Pascal.InactiveRegions,
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts,
  Atlas.Text.Names,
  Atlas.Common.Semantics.Contract,
  Atlas.Common.Diagnostics.RequestScope;

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

procedure NoteRead(const ARead: TUsesGraphRead);
begin
  TRequestDiagnostics.Note('usesGraph', ARead.KindName);
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
  mContext: TUsesContext;
  mEntry: TUsesEntry;
  mInactive: TArray<TTextRange>;
begin
  AUnused := nil;
  AOnlyImplementation := nil;
  if (AText = '') or not Assigned(FUsesContextFor) or
    not FUsesContextFor(TDocumentUris.FromPath(AFileName), mContext) or not Assigned(mContext.Info) then
  begin
    Exit;
  end;
  // Dieselbe Analyse wie die abgeblendeten uses im Editor (#621), mit Namensauflösung (#1925).
  mInactive := TInactiveRegions.Ranges(AText, DefinesOf(AFileName));
  for mEntry in TUsesActions.Entries(TPascalLexer.Tokenize(AText), mInactive, mContext.Info, mContext.Keep,
    mContext.Resolution(AText, mInactive)) do
  begin
    if mEntry.State = TUsesEntryState.Unused then
    begin
      AUnused := AUnused + [mEntry.Name];
    end
    else if mEntry.State = TUsesEntryState.OnlyImplementation then
    begin
      AOnlyImplementation := AOnlyImplementation + [mEntry.Name];
    end;
  end;
end;

function TLspUnitRelations.OptionsOf(const AFileName: string): TUsesGraphOptions;
begin
  Result := FGraph.Options;
  if Assigned(FOptionsFor) then
  begin
    Result := FOptionsFor(AFileName);
  end;
  // Bibliotheks-Units immer: „Verwendet“ zeigt sie mit Datei, soweit der Index sie kennt.
  Result.IncludeLibrary := True;
end;

function TLspUnitRelations.FileOf(const AArguments: TJSONArray; AIndex: Integer): string;
begin
  Result := '';
  if (AArguments <> nil) and (AArguments.Count > AIndex) and (AArguments.Items[AIndex] is TJSONString) then
  begin
    Result := TDocumentUris.PathOrSelf(Trim(AArguments.Items[AIndex].Value));
  end;
  if Result = '' then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[TUnitRelationsText.FileMissing].Text);
  end;
end;

procedure TLspUnitRelations.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentPlain(cMethod, Request);
end;

function TLspUnitRelations.Request(const AParams: TJSONValue): TJSONValue;
var
  mParams, mAnswer: TJSONObject;
  mFileName, mText: string;
  mDepth: Integer;
  mNumber: Double;
  mUnused, mOnlyImplementation: TArray<string>;
  mRelations: TUnitRelations;
  mRead: TUsesGraphRead;
begin
  if not (AParams is TJSONObject) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[TUnitRelationsText.UriMissing].Text);
  end;
  mParams := TJSONObject(AParams);
  mFileName := '';
  if mParams.GetValue('uri') is TJSONString then
  begin
    mFileName := TDocumentUris.PathOrSelf(Trim(mParams.GetValue('uri').Value));
  end;
  if mFileName = '' then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[TUnitRelationsText.UriMissing].Text);
  end;
  mDepth := 1;
  if mParams.TryGetValue<Double>('depth', mNumber) then
  begin
    mDepth := Trunc(mNumber);
  end;
  if mDepth < 0 then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[TUnitRelationsText.DepthIs0AllLevels].Text);
  end;
  mText := TextOf(mFileName);
  EntriesOf(mFileName, mText, mUnused, mOnlyImplementation);
  mAnswer := nil;
  mRead := FGraph.ReadWith(OptionsOf(mFileName),
    procedure(const AGraph: TUsesGraph)
    var
      Builder: TUnitRelationsBuilder;
    begin
      Builder := TUnitRelationsBuilder.Create(AGraph, FLocator, FReader, FDefines);
      try
        mRelations := Builder.Build(mFileName, mDepth, mUnused, mOnlyImplementation);
      finally
        Builder.Free;
      end;
      mAnswer := TUnitRelationsBuilder.ToJson(mRelations);
    end);
  NoteRead(mRead);
  mAnswer.AddPair('generation', TJSONNumber.Create(mRead.Generation));
  mAnswer.AddPair('depth', TJSONNumber.Create(mDepth));
  Result := mAnswer;
end;

function TLspUnitRelations.Execute(const AArguments: TJSONArray): TJSONValue;
var
  mParams: TJSONObject;
  mOptions: TJSONObject;
  mPair: TJSONPair;
begin
  mParams := TJSONObject.Create;
  try
    mParams.AddPair('uri', FileOf(AArguments, 0));
    if (AArguments.Count > 1) and (AArguments.Items[1] is TJSONObject) then
    begin
      mOptions := TJSONObject(AArguments.Items[1]);
      for mPair in mOptions do
      begin
        if mPair.JsonString.Value <> 'uri' then
        begin
          mParams.AddPair(mPair.JsonString.Value, TJSONValue(mPair.JsonValue.Clone));
        end;
      end;
    end;
    Result := Request(mParams);
  finally
    mParams.Free;
  end;
end;

function TLspUnitRelations.Move(const AArguments: TJSONArray): TJSONValue;
var
  mFileName, mUnitName, mTarget, mError, mExtension: string;
  mSection: TUsesSection;
  mEdits: TArray<TTextEdit>;
  mAnswer: TJSONObject;
begin
  mFileName := FileOf(AArguments, 0);
  if (AArguments.Count < 3) or not (AArguments.Items[1] is TJSONString) or
    not (AArguments.Items[2] is TJSONString) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, 'Argumente: [uri, Unit, interface|implementation]');
  end;
  mUnitName := Trim(AArguments.Items[1].Value);
  mTarget := Trim(AArguments.Items[2].Value);
  if SameText(mTarget, 'interface') then
  begin
    mSection := TUsesSection.Interface_;
  end
  else if SameText(mTarget, 'implementation') then
  begin
    mSection := TUsesSection.Implementation_;
  end
  else
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TUnitRelationsText.TargetIsInterfaceOrImplementation].Text);
  end;
  mExtension := LowerCase(ExtractFileExt(mFileName));
  if (mExtension = '.dpr') or (mExtension = '.dpk') then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TUnitRelationsText.ProgramsAndPackagesHaveOnly].Text);
  end;
  if not MoveEdits(TextOf(mFileName), mUnitName, mSection, mEdits, mError) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, mError);
  end;
  mAnswer := TJSONObject.Create;
  mAnswer.AddPair('edit', TApplyEdit.TextEdits(mFileName, mEdits));
  Result := mAnswer;
end;

function TLspUnitRelations.Remove(const AArguments: TJSONArray): TJSONValue;
var
  mFileName, mUnitName, mText: string;
  mEntry: TUsesEntry;
  mContext: TUsesContext;
  mEdit: TTextEdit;
  mAnswer: TJSONObject;
  mFound: Boolean;
  mInactive: TArray<TTextRange>;
begin
  mFileName := FileOf(AArguments, 0);
  if (AArguments.Count < 2) or not (AArguments.Items[1] is TJSONString) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[TUnitRelationsText.ArgumentsUriUnit].Text);
  end;
  mUnitName := Trim(AArguments.Items[1].Value);
  mText := TextOf(mFileName);
  if (mText = '') or not Assigned(FUsesContextFor) or
    not FUsesContextFor(TDocumentUris.FromPath(mFileName), mContext) or not Assigned(mContext.Info) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[TUnitRelationsText.WithoutAnIndexItCannot].Fmt([
      mUnitName]));
  end;
  mFound := False;
  mInactive := TInactiveRegions.Ranges(mText, DefinesOf(mFileName));
  for mEntry in TUsesActions.Entries(TPascalLexer.Tokenize(mText), mInactive, mContext.Info, mContext.Keep,
    mContext.Resolution(mText, mInactive)) do
  begin
    if (mEntry.State = TUsesEntryState.Unused) and SameText(mEntry.Name, mUnitName) then
    begin
      if not TUsesActions.RemoveEntries(mText, [mEntry.Range], mEdit) then
      begin
        raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, mUnitName +
          cTexts[TUnitRelationsText.CannotBeRemoved].Text);
      end;
      mFound := True;
      Break;
    end;
  end;
  if not mFound then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, mUnitName +
      cTexts[TUnitRelationsText.IsUsedOrMissing].Text);
  end;
  mAnswer := TJSONObject.Create;
  mAnswer.AddPair('edit', TApplyEdit.TextEdits(mFileName, [mEdit]));
  Result := mAnswer;
end;

function TLspUnitRelations.Cost(const AArguments: TJSONArray): TJSONValue;
var
  mFileName: string;
  mAnswer: TJSONObject;
  mRead: TUsesGraphRead;
begin
  mFileName := FileOf(AArguments, 0);
  mAnswer := nil;
  // Beim Tippen gefragt: nie auf den Aufbau warten (#3075), der lief sonst in das Zeitlimit.
  mRead := FGraph.TryRead(OptionsOf(mFileName),
    procedure(const AGraph: TUsesGraph)
    begin
      mAnswer := TUnitRelationsBuilder.CostToJson(TUnitRelationsBuilder.InterfaceCost(AGraph, mFileName, cCostUnits));
    end);
  NoteRead(mRead);
  if mAnswer = nil then
  begin
    mAnswer := TJSONObject.Create;
    mAnswer.AddPair('found', TJSONBool.Create(False));
    mAnswer.AddPair('pending', TJSONBool.Create(True));
  end;
  mAnswer.AddPair('graph', mRead.KindName);
  mAnswer.AddPair('generation', TJSONNumber.Create(mRead.Generation));
  Result := mAnswer;
end;

function TLspUnitRelations.UseUnitInfo(const AArguments: TJSONArray): TJSONValue;
var
  mFileName: string;
  mAnswer: TJSONObject;
  mList: TJSONArray;
  mReference: TUsesReference;
  mRead: TUsesGraphRead;
begin
  mFileName := FileOf(AArguments, 0);
  mAnswer := nil;
  mRead := FGraph.ReadWith(OptionsOf(mFileName),
    procedure(const AGraph: TUsesGraph)
    begin
      mAnswer := TUnitRelationsBuilder.UseInfoToJson(TUnitRelationsBuilder.UseCandidates(AGraph, mFileName));
    end);
  // „schon in uses“ aus dem Text, wie ihn der Editor gerade hat.
  mList := TJSONArray.Create;
  for mReference in TUsesLocator.UsesReferences(TextOf(mFileName), DefinesOf(mFileName)) do
  begin
    mList.Add(mReference.Name);
  end;
  mAnswer.AddPair('inUses', mList);
  NoteRead(mRead);
  mAnswer.AddPair('generation', TJSONNumber.Create(mRead.Generation));
  Result := mAnswer;
end;

class function TLspUnitRelations.MoveEdits(const AText, AUnit: string; ATarget: TUsesSection;
  out AEdits: TArray<TTextEdit>; out AError: string): Boolean;
var
  mTokens: TArray<TPascalToken>;
  mReference: TUsesReference;
  mFound: Boolean;
  mName: string;
begin
  AEdits := nil;
  AError := '';
  mTokens := TPascalLexer.Tokenize(AText);
  // Den Eintrag in der anderen Liste suchen, Schreibweise wie im Quelltext.
  mFound := False;
  mName := AUnit;
  for mReference in TPascalUses.References(mTokens) do
  begin
    if (mReference.List = TUsesListKind.UsesList) and SameText(mReference.Name, AUnit) then
    begin
      if mReference.InInterface = (ATarget = TUsesSection.Interface_) then
      begin
        AError := cTexts[TUnitRelationsText.IsAlreadyInTheUses].Fmt([AUnit,
          TTextNames.SectionKeyword(ATarget = TUsesSection.Interface_)]);
        Exit(False);
      end;
      mFound := True;
      mName := mReference.Name;
    end;
  end;
  if not mFound then
  begin
    AError := cTexts[TUnitRelationsText.IsInNoUsesList].Fmt([AUnit]);
    Exit(False);
  end;
  if ATarget = TUsesSection.Implementation_ then
  begin
    Result := TUsesActions.MoveUnits(mTokens, AText, [mName], TTextLines.LineBreakOf(AText), AEdits);
  end
  else
  begin
    Result := TUsesActions.MoveUnitsToInterface(mTokens, AText, [mName], TTextLines.LineBreakOf(AText), AEdits);
  end;
  if not Result then
  begin
    AError := cTexts[TUnitRelationsText.TheUsesListsCannotBe].Text;
  end;
end;

initialization
  TAtlasTextTables.Add('Lsp.UnitRelations', cTexts);

end.
