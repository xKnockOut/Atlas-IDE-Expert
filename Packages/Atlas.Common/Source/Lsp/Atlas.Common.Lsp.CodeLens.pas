unit Atlas.Common.Lsp.CodeLens;

// Code Lens über Klassen und Methoden (textDocument/codeLens, codeLens/resolve):
//   - "5 Referenzen" (erst bei codeLens/resolve gezählt, weil die Suche das Projekt liest),
//   - "überschreibt TControl.Paint" bei Methoden, die ein Vorfahr schon deklariert,
//   - "3 Nachfahren" bei Klassen und Interfaces,
//   - "behandelt WM_PAINT (… auch in TWinControl)" bei Klassen mit Message-Handlern,
//   - Code-Metriken über jeder implementierten Methode (#66, Einstellung codeLens.metrics):
//     "12 Zeilen · Tiefe 2 · zyklomatisch 4 · kognitiv 3 · 2 Parameter · Operanden 2 · 3 lokale · 1 Ausstiege";
//     über Klassen Member und mit Index die Vererbungstiefe ohne RTL und VCL (#939, #980); ohne Klickziel.
// Ein Klick ruft atlas.showLocations im Editor auf (Argumente: URI, Position, Locations).

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Metrics.Contract,
  Atlas.Common.Lsp.References;

type
  TCodeLensKind = (References, Overrides, Descendants, Messages, Metrics);

  /// <summary>Grenzwerte für die Metrik-Linsen der Datei AUri; False = Metrik-Linsen aus.</summary>
  TCodeLensMetricsFunc = reference to function(const AUri: string; out ALimits: TMetricLimits): Boolean;

  TCodeLensLocation = record
    FileName: string;
    Range: TTextRange;
  end;

  /// <summary>Vorfahr, dessen Routine eine Methode überschreibt.</summary>
  TCodeLensOverride = record
    /// <summary>Name des Vorfahren.</summary>
    Owner: string;
    /// <summary>Deklaration der Routine im Vorfahren.</summary>
    Target: TCodeLensLocation;
  end;

  /// <summary>Unit, deren Linsen gesucht werden, samt allem, was zum Auflösen der Namen nötig ist.</summary>
  TCodeLensSource = record
    Resolver: TNameResolver;
    Index: ISymbolIndex;
    Tree: TSyntaxTree;
    FileName: string;
    /// <summary>Quelltext anderer Units; darf nil sein.</summary>
    ReadText: TReferenceReadText;
  end;

  TCodeLensEntry = record
    Kind: TCodeLensKind;
    /// <summary>Name des Symbols; die Linse steht über dieser Zeile.</summary>
    Range: TTextRange;
    /// <summary>'' bis codeLens/resolve (nur References).</summary>
    Title: string;
    Targets: TArray<TCodeLensLocation>;
  end;

  TLspCodeLens = class
  public const
    LensMethod = 'textDocument/codeLens';
    ResolveMethod = 'codeLens/resolve';
    ShowLocationsCommand = 'atlas.showLocations';
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    FEnsureUnit: TEnsureUnitFunc;
    FReadText: TReferenceReadText;
    FFiles: TReferenceFilesProvider;
    FNamespaces: TArray<string>;
    FMetricsFor: TCodeLensMetricsFunc;
    function NewResolver: TNameResolver;
    function HandleLens(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    function HandleResolve(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  private
    /// <summary>Unter TLspNamespaces gelesen und ersetzt (Code-Review A-03): Die Komposition setzt sie
    /// beim Laden eines Projekts, Anfragen lesen sie in Worker-Threads.</summary>
    function GetNamespaces: TArray<string>;
    procedure SetNamespaces(const AValue: TArray<string>);
  public
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex; const AReadText: TReferenceReadText;
      const AFiles: TReferenceFilesProvider; const AEnsureUnit: TEnsureUnitFunc); overload;
    /// <summary>Wie oben mit AEnsureUnit = nil.</summary>
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex; const AReadText: TReferenceReadText;
      const AFiles: TReferenceFilesProvider); overload;
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    class function Capability: TJSONObject; static;
    /// <summary>Alle Linsen der Datei; Referenzen noch ohne Titel.</summary>
    class function Lenses(const ASource: TCodeLensSource): TArray<TCodeLensEntry>; static;
    /// <summary>Metrik-Linse über dem Namen jeder implementierten Methode (#66), über jeder Klasse (Member), über
    /// dem Unit-Namen (Zeilen) und über dem ersten uses (Units im uses, #939); der Aufbau zuerst.</summary>
    class function MetricLenses(ATree: TSyntaxTree; const ALimits: TMetricLimits): TArray<TCodeLensEntry>;
      overload; static;
    /// <summary>Wie oben, dazu die Vererbungstiefe jeder Klasse mit eigenen Vorfahren über AIndex (#980); AFileName
    /// für den Index der Datei.</summary>
    class function MetricLenses(ATree: TSyntaxTree; const ALimits: TMetricLimits; const AIndex: ISymbolIndex;
      const AFileName: string): TArray<TCodeLensEntry>; overload; static;
    /// <summary>Nächster Vorfahr von AType, der die Routine AName deklariert (auch für die Zeilenleiste #768);
    /// AFound nennt ihn und die Deklaration. False, wenn keiner im Index steht.</summary>
    class function OverriddenAncestor(AResolver: TNameResolver; const AIndex: ISymbolIndex;
      const ACurrent: TUnitIndex; const AType: TIndexSymbol; const AName: string;
      out AFound: TCodeLensOverride): Boolean; static;
    /// <summary>Zählt die Referenzen auf das Symbol der Linse.</summary>
    class function ResolveReferences(const ASource: TCodeLensSource; const AEntry: TCodeLensEntry;
      const AFiles: TArray<string>; const ACancellation: IJsonRpcCancellationToken): TCodeLensEntry; overload; static;
    /// <summary>Wie oben ohne Abbruch (ACancellation = nil).</summary>
    class function ResolveReferences(const ASource: TCodeLensSource; const AEntry: TCodeLensEntry;
      const AFiles: TArray<string>): TCodeLensEntry; overload; static;
    /// <summary>CodeLens des LSP; ohne Titel mit data für codeLens/resolve. Der Aufrufer übernimmt das Objekt.</summary>
    class function ToJson(const AEntry: TCodeLensEntry; const AFileName: string): TJSONObject; static;
    property Namespaces: TArray<string> read GetNamespaces write SetNamespaces;
    /// <summary>Einstellung und Grenzwerte der Metrik-Linsen; nil = keine.</summary>
    property MetricsFor: TCodeLensMetricsFunc read FMetricsFor write FMetricsFor;
  end;

implementation

uses
  Atlas.Common.Lsp.Internals.Namespaces,
  System.Generics.Collections,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.MessageHandlers,
  Atlas.Common.Lsp.Internals.Cancellation,
  Atlas.Common.Metrics.Calculator,
  Atlas.Common.Metrics.Report,
  Atlas.Common.Rules.Builtin.Metrics;

const
  RoutineKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine];
  LensTypeKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.InterfaceType];
  MaxDepth = 32;

function PositionKey(const APosition: TTextPosition): string;
begin
  Result := IntToStr(APosition.Line) + ':' + IntToStr(APosition.Character);
end;

function Location(const AFileName: string; const ARange: TTextRange): TCodeLensLocation;
begin
  Result.FileName := AFileName;
  Result.Range := ARange;
end;

function Plural(ACount: Integer; const AOne, AMany: string): string;
begin
  if ACount = 1 then
  begin
    Result := '1 ' + AOne;
  end
  else
  begin
    Result := IntToStr(ACount) + ' ' + AMany;
  end;
end;

function UnitOf(const AIndex: ISymbolIndex; const ACurrent: TUnitIndex; const AFileName: string;
  out AUnit: TUnitIndex): Boolean;
begin
  if SameText(AFileName, ACurrent.FileName) then
  begin
    AUnit := ACurrent;
    Exit(True);
  end;
  Result := AIndex.FindFile(AFileName, AUnit);
end;

/// <summary>Nächster Vorfahr, der AName deklariert; False, wenn keiner im Index steht.</summary>
function FindOverridden(AResolver: TNameResolver; const AIndex: ISymbolIndex; const ACurrent: TUnitIndex;
  const AType: TIndexSymbol; const AName: string; out AFound: TCodeLensOverride): Boolean;
var
  Ancestors: TArray<string>;
  FromUnit, OwnerUnit: TUnitIndex;
  Ancestor: TResolvedSymbol;
  Symbol: TIndexSymbol;
  Depth: Integer;
  Name: string;
begin
  Result := False;
  FromUnit := ACurrent;
  Ancestors := AType.Ancestors;
  for Depth := 1 to MaxDepth do
  begin
    if Length(Ancestors) = 0 then
    begin
      Exit;
    end;
    Name := Ancestors[0];
    if (Pos('<', Name) > 0) or not AResolver.ResolveTypeFrom(FromUnit, Name, Ancestor) or
      not UnitOf(AIndex, ACurrent, Ancestor.FileName, OwnerUnit) then
    begin
      Exit;
    end;
    for Symbol in OwnerUnit.Symbols do
    begin
      if (Symbol.Kind in RoutineKinds) and SameText(Symbol.Container, Ancestor.QualifiedName) and
        SameText(Symbol.Name, AName) then
      begin
        AFound.Owner := Ancestor.Name;
        AFound.Target := Location(OwnerUnit.FileName, Symbol.SelectionRange);
        Exit(True);
      end;
    end;
    FromUnit := OwnerUnit;
    Ancestors := Ancestor.Ancestors;
  end;
end;

function IsRoutineKeyword(const AToken: TPascalToken): Boolean;
const
  cKeywords: array[0..4] of string = ('procedure', 'function', 'constructor', 'destructor', 'operator');
var
  mKeyword: string;
begin
  for mKeyword in cKeywords do
  begin
    if AToken.IsKeyword(mKeyword) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Namen in Köpfen von Implementierungen (procedure TFoo.Bar): keine Verwendungen.</summary>
function HeaderNames(ATree: TSyntaxTree): TDictionary<string, Boolean>;
var
  Tokens: TArray<TPascalToken>;
  Index, Back: Integer;
begin
  Result := TDictionary<string, Boolean>.Create;
  Tokens := ATree.Tokens;
  for Index := 2 to High(Tokens) do
  begin
    if not (Tokens[Index - 1].IsSymbol('.') and (Tokens[Index].Kind = TPascalTokenKind.Identifier)) then
    begin
      Continue;
    end;
    Back := Index - 2;
    while (Back >= 2) and (Tokens[Back].Kind = TPascalTokenKind.Identifier) and Tokens[Back - 1].IsSymbol('.') do
    begin
      Dec(Back, 2);
    end;
    if (Back >= 1) and (Tokens[Back].Kind = TPascalTokenKind.Identifier) and IsRoutineKeyword(Tokens[Back - 1]) then
    begin
      Result.AddOrSetValue(PositionKey(Tokens[Index].StartPos), True);
    end;
  end;
end;

{ TLspCodeLens }

function TLspCodeLens.GetNamespaces: TArray<string>;
begin
  Result := TLspNamespaces.Read(FNamespaces);
end;

procedure TLspCodeLens.SetNamespaces(const AValue: TArray<string>);
begin
  TLspNamespaces.Write(FNamespaces, AValue);
end;

constructor TLspCodeLens.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AReadText: TReferenceReadText; const AFiles: TReferenceFilesProvider);
begin
  Create(AStore, AIndex, AReadText, AFiles, nil);
end;

constructor TLspCodeLens.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AReadText: TReferenceReadText; const AFiles: TReferenceFilesProvider; const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create;
  FStore := AStore;
  FIndex := AIndex;
  FReadText := AReadText;
  FFiles := AFiles;
  FEnsureUnit := AEnsureUnit;
end;

procedure TLspCodeLens.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(LensMethod, HandleLens);
  ADispatcher.RegisterConcurrentRequest(ResolveMethod, HandleResolve);
end;

class function TLspCodeLens.Capability: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('resolveProvider', TJSONBool.Create(True));
end;

function NewEntry(AKind: TCodeLensKind; const ARange: TTextRange; const ATitle: string): TCodeLensEntry;
begin
  Result := Default(TCodeLensEntry);
  Result.Kind := AKind;
  Result.Range := ARange;
  Result.Title := ATitle;
end;

/// <summary>Nachfahren einer Klasse oder eines Interfaces.</summary>
procedure AddDescendantLens(const AIndex: ISymbolIndex; const ASymbol: TIndexSymbol; AList: TList<TCodeLensEntry>);
var
  mDescendants: TArray<TSymbolLocation>;
  mDescendant: TSymbolLocation;
  mEntry: TCodeLensEntry;
begin
  mDescendants := AIndex.Descendants(ASymbol.QualifiedName);
  if Length(mDescendants) = 0 then
  begin
    Exit;
  end;
  mEntry := NewEntry(TCodeLensKind.Descendants, ASymbol.SelectionRange,
    Plural(Length(mDescendants), 'Nachfahre', 'Nachfahren'));
  for mDescendant in mDescendants do
  begin
    mEntry.Targets := mEntry.Targets + [Location(mDescendant.FileName, mDescendant.Symbol.SelectionRange)];
  end;
  AList.Add(mEntry);
end;

/// <summary>Nachrichtenbehandlung einer Klasse auf oberster Ebene.</summary>
procedure AddMessageLens(const ASource: TCodeLensSource; const ASymbol: TIndexSymbol; AList: TList<TCodeLensEntry>);
var
  mReadText: TReferenceReadText;
  mOverview: TMessageOverview;
  mHandler: TMessageHandler;
  mEntry: TCodeLensEntry;
begin
  mReadText := ASource.ReadText;
  mOverview := TMessageHandlers.Overview(ASource.Resolver, ASource.Tree, ASource.FileName, ASymbol.Name,
    function(const AName: string; out AText: string): Boolean
    begin
      Result := Assigned(mReadText) and mReadText(AName, AText);
    end);
  if not mOverview.Found then
  begin
    Exit;
  end;
  mEntry := NewEntry(TCodeLensKind.Messages, ASymbol.SelectionRange, mOverview.Title);
  for mHandler in mOverview.Own do
  begin
    mEntry.Targets := mEntry.Targets + [Location(mHandler.FileName, mHandler.SelectionRange)];
  end;
  AList.Add(mEntry);
end;

procedure AddTypeLenses(const ASource: TCodeLensSource; const ASymbol: TIndexSymbol; AList: TList<TCodeLensEntry>);
begin
  AList.Add(NewEntry(TCodeLensKind.References, ASymbol.SelectionRange, ''));
  if ASymbol.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.InterfaceType] then
  begin
    AddDescendantLens(ASource.Index, ASymbol, AList);
  end;
  if (ASymbol.Kind = TIndexSymbolKind.ClassType) and (ASymbol.Container = '') then
  begin
    AddMessageLens(ASource, ASymbol, AList);
  end;
end;

procedure AddRoutineLenses(const ASource: TCodeLensSource; const ACurrent: TUnitIndex;
  const AType, ASymbol: TIndexSymbol; AList: TList<TCodeLensEntry>);
var
  mFound: TCodeLensOverride;
  mEntry: TCodeLensEntry;
begin
  AList.Add(NewEntry(TCodeLensKind.References, ASymbol.SelectionRange, ''));
  if FindOverridden(ASource.Resolver, ASource.Index, ACurrent, AType, ASymbol.Name, mFound) then
  begin
    mEntry := NewEntry(TCodeLensKind.Overrides, ASymbol.SelectionRange,
      'überschreibt ' + mFound.Owner + '.' + ASymbol.Name);
    mEntry.Targets := [mFound.Target];
    AList.Add(mEntry);
  end;
end;

/// <summary>Typen der Unit, die Linsen bekommen, nach großgeschriebenem qualifiziertem Namen.</summary>
function LensTypes(const ACurrent: TUnitIndex): TDictionary<string, TIndexSymbol>;
var
  mSymbol: TIndexSymbol;
begin
  Result := TDictionary<string, TIndexSymbol>.Create;
  for mSymbol in ACurrent.Symbols do
  begin
    if mSymbol.Kind in LensTypeKinds then
    begin
      Result.AddOrSetValue(UpperCase(mSymbol.QualifiedName), mSymbol);
    end;
  end;
end;

class function TLspCodeLens.Lenses(const ASource: TCodeLensSource): TArray<TCodeLensEntry>;
var
  mCurrent: TUnitIndex;
  mSymbol, mTypeSymbol: TIndexSymbol;
  mTypes: TDictionary<string, TIndexSymbol>;
  mHeaders: TDictionary<string, Boolean>;
  mList: TList<TCodeLensEntry>;
begin
  mCurrent := TIndexExtractor.Extract(ASource.Tree, ASource.FileName);
  mList := TList<TCodeLensEntry>.Create;
  mTypes := LensTypes(mCurrent);
  // Rümpfe (procedure TFoo.Bar) bekommen keine eigene Linse.
  mHeaders := HeaderNames(ASource.Tree);
  try
    for mSymbol in mCurrent.Symbols do
    begin
      if mHeaders.ContainsKey(PositionKey(mSymbol.SelectionRange.StartPos)) then
      begin
        Continue;
      end;
      if mSymbol.Kind in LensTypeKinds then
      begin
        AddTypeLenses(ASource, mSymbol, mList);
      end
      else if (mSymbol.Kind in RoutineKinds) and (mSymbol.Container <> '') and
        mTypes.TryGetValue(UpperCase(mSymbol.Container), mTypeSymbol) then
      begin
        AddRoutineLenses(ASource, mCurrent, mTypeSymbol, mSymbol, mList);
      end;
    end;
    Result := mList.ToArray;
  finally
    mHeaders.Free;
    mTypes.Free;
    mList.Free;
  end;
end;

class function TLspCodeLens.OverriddenAncestor(AResolver: TNameResolver; const AIndex: ISymbolIndex;
  const ACurrent: TUnitIndex; const AType: TIndexSymbol; const AName: string;
  out AFound: TCodeLensOverride): Boolean;
begin
  Result := FindOverridden(AResolver, AIndex, ACurrent, AType, AName, AFound);
end;

class function TLspCodeLens.MetricLenses(ATree: TSyntaxTree; const ALimits: TMetricLimits): TArray<TCodeLensEntry>;
var
  Routine: TRoutineMetrics;
  Item: TStructureMetrics;
  Entry: TCodeLensEntry;
begin
  Result := nil;
  for Item in TMetricsCalculator.Structure(ATree) do
  begin
    Entry := Default(TCodeLensEntry);
    Entry.Kind := TCodeLensKind.Metrics;
    Entry.Range := Item.NameRange;
    Entry.Title := TMetricsReport.StructureLensPart(Item.Kind, Item.Value, ALimits);
    Result := Result + [Entry];
  end;
  for Routine in TMetricsCalculator.Routines(ATree) do
  begin
    Entry := Default(TCodeLensEntry);
    Entry.Kind := TCodeLensKind.Metrics;
    Entry.Range := Routine.NameRange;
    Entry.Title := TMetricsReport.LensTitle(Routine.Values, ALimits);
    Result := Result + [Entry];
  end;
end;

class function TLspCodeLens.MetricLenses(ATree: TSyntaxTree; const ALimits: TMetricLimits;
  const AIndex: ISymbolIndex; const AFileName: string): TArray<TCodeLensEntry>;
var
  Item: TStructureMetrics;
  Entry: TCodeLensEntry;
begin
  Result := MetricLenses(ATree, ALimits);
  for Item in TMetricRules.InheritanceDepths(ATree, AIndex, TIndexExtractor.Extract(ATree, AFileName)) do
  begin
    Entry := Default(TCodeLensEntry);
    Entry.Kind := TCodeLensKind.Metrics;
    Entry.Range := Item.NameRange;
    Entry.Title := TMetricsReport.StructureLensPart(Item, ALimits);
    Result := Result + [Entry];
  end;
end;

class function TLspCodeLens.ResolveReferences(const ASource: TCodeLensSource; const AEntry: TCodeLensEntry;
  const AFiles: TArray<string>): TCodeLensEntry;
begin
  Result := ResolveReferences(ASource, AEntry, AFiles, nil);
end;

class function TLspCodeLens.ResolveReferences(const ASource: TCodeLensSource; const AEntry: TCodeLensEntry;
  const AFiles: TArray<string>; const ACancellation: IJsonRpcCancellationToken): TCodeLensEntry;
var
  mFound: TReferenceLocation;
  mHeaders: TDictionary<string, Boolean>;
begin
  Result := AEntry;
  Result.Targets := nil;
  mHeaders := HeaderNames(ASource.Tree);
  try
    for mFound in TLspReferences.Find(ASource.Resolver, ASource.Index, ASource.Tree,
      TReferenceSearch.Create(ASource.FileName, AEntry.Range.StartPos, False, AFiles, ASource.ReadText),
      ACancellation) do
    begin
      if not (SameText(mFound.FileName, ASource.FileName) and
        mHeaders.ContainsKey(PositionKey(mFound.Range.StartPos))) then
      begin
        Result.Targets := Result.Targets + [Location(mFound.FileName, mFound.Range)];
      end;
    end;
  finally
    mHeaders.Free;
  end;
  Result.Title := Plural(Length(Result.Targets), 'Referenz', 'Referenzen');
end;

class function TLspCodeLens.ToJson(const AEntry: TCodeLensEntry; const AFileName: string): TJSONObject;
var
  Command, Data: TJSONObject;
  Arguments, Locations: TJSONArray;
  Target: TCodeLensLocation;
  Item: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('range', TLspPositions.RangeToJson(AEntry.Range));
  if AEntry.Kind = TCodeLensKind.Metrics then
  begin
    // Nur Anzeige: ein leerer Befehl macht die Linse in VS Code zu reinem Text.
    Command := TJSONObject.Create;
    Command.AddPair('title', AEntry.Title);
    Command.AddPair('command', '');
    Result.AddPair('command', Command);
    Exit;
  end;
  if AEntry.Title = '' then
  begin
    Data := TJSONObject.Create;
    Data.AddPair('uri', TDocumentUris.FromPath(AFileName));
    Data.AddPair('line', TJSONNumber.Create(AEntry.Range.StartPos.Line));
    Data.AddPair('character', TJSONNumber.Create(AEntry.Range.StartPos.Character));
    Data.AddPair('endLine', TJSONNumber.Create(AEntry.Range.EndPos.Line));
    Data.AddPair('endCharacter', TJSONNumber.Create(AEntry.Range.EndPos.Character));
    Result.AddPair('data', Data);
    Exit;
  end;
  Locations := TJSONArray.Create;
  for Target in AEntry.Targets do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('uri', TDocumentUris.FromPath(Target.FileName));
    Item.AddPair('range', TLspPositions.RangeToJson(Target.Range));
    Locations.AddElement(Item);
  end;
  Arguments := TJSONArray.Create;
  Arguments.Add(TDocumentUris.FromPath(AFileName));
  Arguments.AddElement(TLspPositions.PositionToJson(AEntry.Range.StartPos));
  Arguments.AddElement(Locations);
  Command := TJSONObject.Create;
  Command.AddPair('title', AEntry.Title);
  Command.AddPair('command', ShowLocationsCommand);
  Command.AddPair('arguments', Arguments);
  Result.AddPair('command', Command);
end;

function TLspCodeLens.NewResolver: TNameResolver;
begin
  Result := TNameResolver.Create(FIndex, FEnsureUnit);
  Result.Namespaces := Namespaces;
end;

function TLspCodeLens.HandleLens(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  mCancellation: IPascalCancellation;
  mUri: string;
  mDocument: ITextDocument;
  mShared: ISharedSyntaxTree;
  mSource: TCodeLensSource;
  mEntry: TCodeLensEntry;
  mLimits: TMetricLimits;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', mUri)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Feld "textDocument.uri" fehlt');
  end;
  if not FStore.TryGet(mUri, mDocument) then
  begin
    Exit(TJSONNull.Create);
  end;
  mCancellation := TRequestCancellation.Create(ACancellation);
  mShared := TSyntaxTreeCache.Get(mDocument, mCancellation);
  ACancellation.ThrowIfCancellationRequested;
  mSource.Index := FIndex;
  mSource.Tree := mShared.Tree;
  mSource.FileName := TDocumentUris.ToPath(mUri);
  mSource.ReadText := FReadText;
  mSource.Resolver := NewResolver;
  try
    Result := TJSONArray.Create;
    for mEntry in Lenses(mSource) do
    begin
      TJSONArray(Result).AddElement(ToJson(mEntry, mSource.FileName));
    end;
    if Assigned(FMetricsFor) and FMetricsFor(mUri, mLimits) then
    begin
      for mEntry in MetricLenses(mSource.Tree, mLimits, FIndex, mSource.FileName) do
      begin
        TJSONArray(Result).AddElement(ToJson(mEntry, mSource.FileName));
      end;
    end;
  finally
    mSource.Resolver.Free;
  end;
end;

/// <summary>Stelle APrefix.line/APrefix.character in data der Linse.</summary>
function DataPosition(AParams: TJSONObject; const ALine, ACharacter: string; out APosition: TTextPosition): Boolean;
var
  mLine, mCharacter: Integer;
begin
  Result := AParams.TryGetValue<Integer>(ALine, mLine) and AParams.TryGetValue<Integer>(ACharacter, mCharacter);
  if Result then
  begin
    APosition := TTextPosition.Create(mLine, mCharacter);
  end;
end;

/// <summary>Linse aus data von codeLens/resolve; EJsonRpcError, wenn data fehlt oder unvollständig ist.</summary>
function ResolveEntry(const AParams: TJSONValue; out AUri: string): TCodeLensEntry;
var
  mStart, mEnd: TTextPosition;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('data.uri', AUri) and
    DataPosition(TJSONObject(AParams), 'data.line', 'data.character', mStart) and
    DataPosition(TJSONObject(AParams), 'data.endLine', 'data.endCharacter', mEnd)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Feld "data" der Linse fehlt oder ist unvollständig');
  end;
  Result := NewEntry(TCodeLensKind.References, TTextRange.Create(mStart, mEnd), '');
end;

function TLspCodeLens.HandleResolve(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  mCancellation: IPascalCancellation;
  mUri: string;
  mDocument: ITextDocument;
  mShared: ISharedSyntaxTree;
  mSource: TCodeLensSource;
  mEntry: TCodeLensEntry;
  mFiles: TArray<string>;
begin
  mEntry := ResolveEntry(AParams, mUri);
  mSource := Default(TCodeLensSource);
  mSource.FileName := TDocumentUris.ToPath(mUri);
  mFiles := nil;
  if Assigned(FFiles) then
  begin
    mFiles := FFiles();
  end;
  if not FStore.TryGet(mUri, mDocument) then
  begin
    mEntry.Title := Plural(0, 'Referenz', 'Referenzen');
    Exit(ToJson(mEntry, mSource.FileName));
  end;
  mCancellation := TRequestCancellation.Create(ACancellation);
  mShared := TSyntaxTreeCache.Get(mDocument, mCancellation);
  mSource.Index := FIndex;
  mSource.Tree := mShared.Tree;
  mSource.ReadText := FReadText;
  mSource.Resolver := NewResolver;
  try
    mEntry := ResolveReferences(mSource, mEntry, mFiles, ACancellation);
  finally
    mSource.Resolver.Free;
  end;
  Result := ToJson(mEntry, mSource.FileName);
end;

end.
