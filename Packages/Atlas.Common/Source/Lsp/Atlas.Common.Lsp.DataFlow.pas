unit Atlas.Common.Lsp.DataFlow;

// Datenfluss (#690, atlas/dataFlow): „Woher kommt der Wert?“ und „Wohin geht der Wert?“ für das Symbol an
// einer Position (Variable, Feld, Parameter, Property, Funktion; Result steht für die umgebende Funktion).
//
// Die Referenzsuche liefert alle Vorkommen; jedes wird am Syntaxbaum eingeordnet:
//   - Woher (Sources): Zuweisungen (:=), var- und out-Argumente, Read/ReadLn (externe Eingabe),
//     Initialisierungen (var X := …, X: T = …), Schleifenvariablen, Schreiben über eine Property (write FFeld
//     bzw. Setter), Inc/Dec und Verwandte. Ein Parameter führt zu den Argumenten aller Aufrufer (auch über
//     eine Property mit diesem Setter), eine Funktion zu den Zuweisungen an Result bzw. ihren Namen und zu
//     Exit(Wert), eine Property zusätzlich zum gelesenen Feld bzw. Getter.
//   - Wohin (Targets): Zuweisungen, Argumente (an den Parameter des Aufgerufenen), Rückgaben (Result, Exit),
//     Initialisierungen, Schleifen und Properties, die das Feld lesen; sonst eine Verwendung (Bedingung,
//     Index, verworfenes Ergebnis) als Blatt. Über Routinen außerhalb des Projekts und Typumwandlungen
//     (IntToStr(X), Integer(X)) geht der Wert weiter nach außen.
// Jede Stelle nennt die Symbole, aus denen ihr Wert kommt bzw. in die er geht. Der Editor fragt sie beim
// Aufklappen einzeln nach und schickt die Schlüssel der Vorfahren mit (Path); ein Symbol, das dort schon
// steht, ist ein Zyklus. Blätter: Literale, Konstanten, externe Eingaben und Ausgaben, Stellen außerhalb
// des Projekts. Unsichere Kanten (Zeiger, absolute, Move, FillChar, Adressen) sind markiert. Gleiche Stellen
// (Art, Ausdruck, Quellen) werden zu einem Knoten mit mehreren Fundorten zusammengefasst.
//
// Aufbau: Typen in .Types (hier als Aliase), Hilfen am Baum in .Syntax, Dateien des Laufs in .Files; der Lauf
// ist die Klassenkette .Base (Auflösen, Sammeln) → .Sources (Woher) → .Targets (Wohin, TDataFlowRun).

interface

uses
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Index.Contract,
  Atlas.Common.Lsp.References,
  Atlas.Common.Lsp.DataFlow.Types;

type
  TDataFlowDirection = Atlas.Common.Lsp.DataFlow.Types.TDataFlowDirection;
  TDataFlowKind = Atlas.Common.Lsp.DataFlow.Types.TDataFlowKind;
  TDataFlowLeaf = Atlas.Common.Lsp.DataFlow.Types.TDataFlowLeaf;
  TDataFlowSymbol = Atlas.Common.Lsp.DataFlow.Types.TDataFlowSymbol;
  TDataFlowPlace = Atlas.Common.Lsp.DataFlow.Types.TDataFlowPlace;
  TDataFlowNode = Atlas.Common.Lsp.DataFlow.Types.TDataFlowNode;
  TDataFlowOptions = Atlas.Common.Lsp.DataFlow.Types.TDataFlowOptions;
  TDataFlowResult = Atlas.Common.Lsp.DataFlow.Types.TDataFlowResult;
  TDataFlowRequest = Atlas.Common.Lsp.DataFlow.Types.TDataFlowRequest;

  TLspDataFlow = class
  public const
    Method = 'atlas/dataFlow';
    /// <summary>Höchstzahl der Knoten einer Antwort.</summary>
    MaxNodes = cMaxDataFlowNodes;
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    FEnsureUnit: TEnsureUnitFunc;
    FReadText: TReferenceReadText;
    FFiles: TReferenceFilesProvider;
    FNamespaces: TArray<string>;
    function HandleDataFlow(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    /// <summary>Baum des Dokuments: aus dem Speicher (AShared hält ihn) oder gelesen (AOwnTree, gibt der
    /// Aufrufer frei); nil, wenn es sich nicht lesen lässt.</summary>
    function TreeOf(const AUri: string; const ACancellation: IPascalCancellation; out AShared: ISharedSyntaxTree;
      out AOwnTree: TSyntaxTree): TSyntaxTree;
    function Answer(ATree: TSyntaxTree; const AUri: string; AParams: TJSONObject;
      const ACancellation: IJsonRpcCancellationToken): TDataFlowResult;
  private
    /// <summary>Unter TLspNamespaces gelesen und ersetzt wie bei den übrigen Anfragen (Code-Review A-03).</summary>
    function GetNamespaces: TArray<string>;
    procedure SetNamespaces(const AValue: TArray<string>);
  public
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex; const AReadText: TReferenceReadText;
      const AFiles: TReferenceFilesProvider; const AEnsureUnit: TEnsureUnitFunc);
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Datenfluss des Symbols an ARequest.Position in ARequest.Tree.</summary>
    class function Analyze(const ARequest: TDataFlowRequest): TDataFlowResult; static;
    /// <summary>Antwort von atlas/dataFlow. Der Aufrufer übernimmt das Objekt.</summary>
    class function ToJson(const AResult: TDataFlowResult): TJSONObject; static;
    /// <summary>Name der Art im Protokoll ("assignment", "callerArgument" …).</summary>
    class function KindName(AKind: TDataFlowKind): string; static;
    class function LeafName(ALeaf: TDataFlowLeaf): string; static;
    property Namespaces: TArray<string> read GetNamespaces write SetNamespaces;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Lsp.Internals.Namespaces,
  Atlas.Common.Lsp.Internals.Cancellation,
  Atlas.Common.Lsp.DataFlow.Targets,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TDataFlowText = (FieldsTextDocumentUriAndPosition);

const
  cTexts: array[TDataFlowText] of TAtlasText = (
    (De: 'Felder "textDocument.uri" und "position" fehlen in ';
     En: 'Fields "textDocument.uri" and "position" missing in '));

{$SCOPEDENUMS OFF}

/// <summary>Filter und Pfad der Anfrage (excludeTests, onlyProject, path).</summary>
function ReadOptions(AParams: TJSONObject): TDataFlowOptions;
var
  mPath, mItem: TJSONValue;
begin
  Result := Default(TDataFlowOptions);
  if not AParams.TryGetValue<Boolean>('excludeTests', Result.ExcludeTests) then
  begin
    Result.ExcludeTests := False;
  end;
  if not AParams.TryGetValue<Boolean>('onlyProject', Result.OnlyProject) then
  begin
    Result.OnlyProject := False;
  end;
  if AParams.TryGetValue<TJSONValue>('path', mPath) and (mPath is TJSONArray) then
  begin
    for mItem in TJSONArray(mPath) do
    begin
      Result.Path := Result.Path + [mItem.Value];
    end;
  end;
end;

function ReadDirection(AParams: TJSONObject): TDataFlowDirection;
var
  mDirection: string;
begin
  Result := TDataFlowDirection.Sources;
  if AParams.TryGetValue<string>('direction', mDirection) and SameText(mDirection, 'targets') then
  begin
    Result := TDataFlowDirection.Targets;
  end;
end;

{ TLspDataFlow }

function TLspDataFlow.GetNamespaces: TArray<string>;
begin
  Result := TLspNamespaces.Read(FNamespaces);
end;

procedure TLspDataFlow.SetNamespaces(const AValue: TArray<string>);
begin
  TLspNamespaces.Write(FNamespaces, AValue);
end;

constructor TLspDataFlow.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AReadText: TReferenceReadText; const AFiles: TReferenceFilesProvider; const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create;
  FStore := AStore;
  FIndex := AIndex;
  FReadText := AReadText;
  FFiles := AFiles;
  FEnsureUnit := AEnsureUnit;
end;

procedure TLspDataFlow.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(Method, HandleDataFlow);
end;

class function TLspDataFlow.Analyze(const ARequest: TDataFlowRequest): TDataFlowResult;
var
  mRun: TDataFlowRun;
begin
  mRun := TDataFlowRun.Create(ARequest);
  try
    Result := mRun.Run(ARequest);
  finally
    mRun.Free;
  end;
end;

class function TLspDataFlow.KindName(AKind: TDataFlowKind): string;
const
  Names: array[TDataFlowKind] of string = ('assignment', 'varArgument', 'outArgument', 'input', 'initialization',
    'loop', 'callerArgument', 'return', 'propertyWrite', 'propertyRead', 'modify', 'argument', 'output', 'use',
    'constant', 'outside', 'address');
begin
  Result := Names[AKind];
end;

class function TLspDataFlow.LeafName(ALeaf: TDataFlowLeaf): string;
const
  Names: array[TDataFlowLeaf] of string = ('', 'constant', 'outside', 'cycle');
begin
  Result := Names[ALeaf];
end;

function SymbolToJson(const ASymbol: TDataFlowSymbol): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', ASymbol.Name);
  Result.AddPair('uri', TDocumentUris.FromPath(ASymbol.FileName));
  Result.AddPair('line', TJSONNumber.Create(ASymbol.Position.Line));
  Result.AddPair('character', TJSONNumber.Create(ASymbol.Position.Character));
  Result.AddPair('key', ASymbol.Key);
  Result.AddPair('symbolKind', TJSONNumber.Create(Ord(ASymbol.SymbolKind)));
  if ASymbol.Leaf <> TDataFlowLeaf.None then
  begin
    Result.AddPair('leaf', TLspDataFlow.LeafName(ASymbol.Leaf));
  end;
end;

class function TLspDataFlow.ToJson(const AResult: TDataFlowResult): TJSONObject;
var
  Nodes, Places, Sources: TJSONArray;
  Node: TDataFlowNode;
  Item, Entry: TJSONObject;
  Place: TDataFlowPlace;
  Source: TDataFlowSymbol;
begin
  Result := TJSONObject.Create;
  Result.AddPair('found', TJSONBool.Create(AResult.Found));
  if not AResult.Found then
  begin
    Exit;
  end;
  Result.AddPair('symbol', SymbolToJson(AResult.Symbol));
  Nodes := TJSONArray.Create;
  Result.AddPair('nodes', Nodes);
  for Node in AResult.Nodes do
  begin
    Item := TJSONObject.Create;
    Nodes.AddElement(Item);
    Item.AddPair('kind', KindName(Node.Kind));
    Item.AddPair('detail', Node.Detail);
    if Node.Via <> '' then
    begin
      Item.AddPair('via', Node.Via);
    end;
    if Node.Literal then
    begin
      Item.AddPair('literal', TJSONBool.Create(True));
    end;
    if Node.Unsafe then
    begin
      Item.AddPair('unsafe', TJSONBool.Create(True));
      Item.AddPair('unsafeReason', Node.UnsafeReason);
    end;
    Places := TJSONArray.Create;
    Item.AddPair('places', Places);
    for Place in Node.Places do
    begin
      Entry := TJSONObject.Create;
      Places.AddElement(Entry);
      Entry.AddPair('uri', TDocumentUris.FromPath(Place.FileName));
      Entry.AddPair('line', TJSONNumber.Create(Place.Position.Line));
      Entry.AddPair('character', TJSONNumber.Create(Place.Position.Character));
      Entry.AddPair('lineText', Place.LineText);
    end;
    Sources := TJSONArray.Create;
    Item.AddPair('sources', Sources);
    for Source in Node.Sources do
    begin
      Sources.AddElement(SymbolToJson(Source));
    end;
  end;
end;

function TLspDataFlow.TreeOf(const AUri: string; const ACancellation: IPascalCancellation;
  out AShared: ISharedSyntaxTree; out AOwnTree: TSyntaxTree): TSyntaxTree;
var
  mDocument: ITextDocument;
  mText: string;
begin
  Result := nil;
  AShared := nil;
  AOwnTree := nil;
  if FStore.TryGet(AUri, mDocument) then
  begin
    AShared := TSyntaxTreeCache.Get(mDocument, ACancellation);
    Result := AShared.Tree;
  end
  else if Assigned(FReadText) and FReadText(TDocumentUris.ToPath(AUri), mText) then
  begin
    AOwnTree := TSyntaxTreeCache.Parse(mText, ACancellation);
    Result := AOwnTree;
  end;
end;

function TLspDataFlow.Answer(ATree: TSyntaxTree; const AUri: string; AParams: TJSONObject;
  const ACancellation: IJsonRpcCancellationToken): TDataFlowResult;
var
  mRequest: TDataFlowRequest;
  mPosition: TJSONValue;
begin
  mRequest := Default(TDataFlowRequest);
  mRequest.Index := FIndex;
  mRequest.Tree := ATree;
  mRequest.FileName := TDocumentUris.ToPath(AUri);
  if AParams.TryGetValue<TJSONValue>('position', mPosition) then
  begin
    mRequest.Position := TLspPositions.ReadPosition(mPosition);
  end;
  mRequest.Direction := ReadDirection(AParams);
  mRequest.Options := ReadOptions(AParams);
  if Assigned(FFiles) then
  begin
    mRequest.Files := FFiles();
  end;
  mRequest.ReadText := FReadText;
  mRequest.Cancellation := ACancellation;
  ACancellation.ThrowIfCancellationRequested;
  mRequest.Resolver := TNameResolver.Create(FIndex, FEnsureUnit);
  try
    mRequest.Resolver.Namespaces := Namespaces;
    Result := Analyze(mRequest);
  finally
    mRequest.Resolver.Free;
  end;
end;

function TLspDataFlow.HandleDataFlow(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  mUri: string;
  mPosition: TJSONValue;
  mCancellation: IPascalCancellation;
  mShared: ISharedSyntaxTree;
  mTree, mOwnTree: TSyntaxTree;
  mAnalysis: TDataFlowResult;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', mUri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('position', mPosition)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      cTexts[TDataFlowText.FieldsTextDocumentUriAndPosition].Text + Method);
  end;
  mCancellation := TRequestCancellation.Create(ACancellation);
  mTree := TreeOf(mUri, mCancellation, mShared, mOwnTree);
  if mTree = nil then
  begin
    Exit(TJSONNull.Create);
  end;
  try
    mAnalysis := Answer(mTree, mUri, TJSONObject(AParams), ACancellation);
  finally
    mOwnTree.Free;
  end;
  Result := ToJson(mAnalysis);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.DataFlow', cTexts);

end.
