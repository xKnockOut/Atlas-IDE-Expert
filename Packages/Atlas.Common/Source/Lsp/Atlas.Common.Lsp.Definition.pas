unit Atlas.Common.Lsp.Definition;

// Gehe zu Definition und Gehe zu Deklaration (textDocument/definition,
// textDocument/declaration) über die Namensauflösung; die Ziele rechnet
// Atlas.Common.Semantics.Definitions.
//
// Bei Routinen und Methoden mit getrennter Deklaration und Implementierung:
//   - declaration springt immer zur Deklaration (interface bzw. Klasse),
//   - definition springt zur Implementierung; steht der Cursor bereits auf
//     dem Namen der Implementierung, zurück zur Deklaration. So wechselt
//     dieselbe Taste zwischen beiden.
// Bei Überladungen gehören nur Deklaration und Implementierung derselben
// Variante (gleiche Parametertypen) zusammen; steht der Cursor auf einer
// Routine der Datei, gilt deren Variante. Vorher galt immer die erste
// Überladung (Hover auf der zweiten zeigte die erste).
// Unit-Namen (z. B. in uses) führen an den Anfang der Unit-Datei.
// textDocument/typeDefinition springt von Variablen, Feldern, Parametern,
// Properties und Funktionen zur Deklaration ihres Typs.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Dfm.Navigation,
  Atlas.Common.Lsp.Internals.Feature,
  Atlas.Common.Semantics.Definitions;

type
  TDefinitionRequestKind = (Definition, Declaration, TypeDefinition);

  TLspDefinition = class(TLspIndexFeature)
  public const
    cDefinitionMethod = 'textDocument/definition';
    cDeclarationMethod = 'textDocument/declaration';
    cTypeDefinitionMethod = 'textDocument/typeDefinition';
  private
    FNamespaces: TArray<string>;
    FReadText: TDfmReadText;
    function FormTargets(const AText, AUri: string; const APosition: TTextPosition): TJSONValue;
    function Handle(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken;
      AKind: TDefinitionRequestKind): TJSONValue;
    function HandleDefinition(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    function HandleDeclaration(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    function HandleTypeDefinition(const AParams: TJSONValue;
      const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  private
    /// <summary>Unter TLspNamespaces gelesen und ersetzt: Die Komposition setzt sie
    /// beim Laden eines Projekts, Anfragen lesen sie in Worker-Threads.</summary>
    function GetNamespaces: TArray<string>;
    procedure SetNamespaces(const AValue: TArray<string>);
  public
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
      const AEnsureUnit: TEnsureUnitFunc); overload;
    /// <summary>Wie oben mit AEnsureUnit = nil.</summary>
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex); overload;
    /// <summary>Registriert beide Anfragen am Dispatcher.</summary>
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>LocationLink[] des LSP ohne Ziele in Ersatz-Units der IDE. Der Aufrufer übernimmt das Objekt.
    /// </summary>
    class function ToJson(const ATargets: TArray<TDefinitionTarget>): TJSONArray; static;
    /// <summary>Unit-Namespaces des Projekts (DCC_Namespace).</summary>
    property Namespaces: TArray<string> read GetNamespaces write SetNamespaces;
    /// <summary>Liest die Unit neben einer Formulardatei (#44); ohne sie gibt es dort keine Sprünge.</summary>
    property ReadText: TDfmReadText read FReadText write FReadText;
  end;

implementation

uses
  Atlas.Common.Pascal.SyntaxTree,
  System.Generics.Collections,
  Atlas.Common.Lsp.Internals.Namespaces,
  Atlas.Common.Documents.Uris,
  Atlas.Common.JsonRpc.Positions,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Lsp.Internals.Cancellation,
  Atlas.Common.Dfm.Parser,
  Atlas.Common.Lsp.IdeUnits,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TDefinitionText = (FieldsTextDocumentUriAndPosition);

const
  cTexts: array[TDefinitionText] of TAtlasText = (
    (De: 'Felder "textDocument.uri" und "position" fehlen'; En: 'Fields "textDocument.uri" and "position" missing'));

{$SCOPEDENUMS OFF}

{ TLspDefinition }

constructor TLspDefinition.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create(AStore, AIndex, AEnsureUnit);
end;

constructor TLspDefinition.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex);
begin
  Create(AStore, AIndex, nil);
end;

function TLspDefinition.GetNamespaces: TArray<string>;
begin
  Result := TLspNamespaces.Read(FNamespaces);
end;

procedure TLspDefinition.SetNamespaces(const AValue: TArray<string>);
begin
  TLspNamespaces.Write(FNamespaces, AValue);
end;

function TLspDefinition.FormTargets(const AText, AUri: string; const APosition: TTextPosition): TJSONValue;
var
  mFound: TArray<TDfmTarget>;
  mTargets: TArray<TDefinitionTarget>;
  mIndex: Integer;
begin
  if not Assigned(FReadText) then
  begin
    Exit(TJSONNull.Create);
  end;
  mFound := TDfmNavigation.Targets(AText, TDocumentUris.ToPath(AUri), APosition, FReadText);
  SetLength(mTargets, Length(mFound));
  for mIndex := 0 to High(mFound) do
  begin
    mTargets[mIndex] := TDefinitionTarget.Create(mFound[mIndex].FileName, mFound[mIndex].Range,
      mFound[mIndex].SelectionRange);
  end;
  Result := ToJson(mTargets);
end;

function TLspDefinition.Handle(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken;
  AKind: TDefinitionRequestKind): TJSONValue;
var
  mCancellation: IPascalCancellation;
  mUri: string;
  mPositionValue: TJSONValue;
  mDocument: ITextDocument;
  mTree: TSyntaxTree;
  mShared: ISharedSyntaxTree;
  mResolver: TNameResolver;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', mUri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('position', mPositionValue)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TDefinitionText.FieldsTextDocumentUriAndPosition].Text);
  end;
  if not FStore.TryGet(mUri, mDocument) then
  begin
    Exit(TJSONNull.Create);
  end;
  if TDfmParser.IsFormFile(mUri) then
  begin
    Exit(FormTargets(mDocument.Text, mUri, TLspPositions.ReadPosition(mPositionValue)));
  end;
  // Erst in einer Variablen halten: Bei Übergabe als const würde das Objekt nie freigegeben.
  mCancellation := TRequestCancellation.Create(ACancellation);
  mShared := TSyntaxTreeCache.Get(mDocument, mCancellation);
  mTree := mShared.Tree;
  ACancellation.ThrowIfCancellationRequested;
  // Je Anfrage ein eigener Resolver: er hält Zustand pro Aufruf.
  mResolver := TNameResolver.Create(FIndex, FEnsureUnit);
  try
    mResolver.Namespaces := Namespaces;
    if AKind = TDefinitionRequestKind.TypeDefinition then
    begin
      Result := ToJson(TDefinitions.TypeTargets(mResolver, mTree, TDocumentUris.ToPath(mUri),
        TLspPositions.ReadPosition(mPositionValue)));
    end
    else
    begin
      Result := ToJson(TDefinitions.Targets(mResolver, FIndex, mTree, TDocumentUris.ToPath(mUri),
        TLspPositions.ReadPosition(mPositionValue), AKind = TDefinitionRequestKind.Declaration));
    end;
  finally
    mResolver.Free;
  end;
end;

function TLspDefinition.HandleDefinition(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
begin
  Result := Handle(AParams, ACancellation, TDefinitionRequestKind.Definition);
end;

function TLspDefinition.HandleDeclaration(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
begin
  Result := Handle(AParams, ACancellation, TDefinitionRequestKind.Declaration);
end;

function TLspDefinition.HandleTypeDefinition(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
begin
  Result := Handle(AParams, ACancellation, TDefinitionRequestKind.TypeDefinition);
end;

procedure TLspDefinition.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(cDefinitionMethod, HandleDefinition);
  ADispatcher.RegisterConcurrentRequest(cDeclarationMethod, HandleDeclaration);
  ADispatcher.RegisterConcurrentRequest(cTypeDefinitionMethod, HandleTypeDefinition);
end;

class function TLspDefinition.ToJson(const ATargets: TArray<TDefinitionTarget>): TJSONArray;
var
  mItem: TDefinitionTarget;
  mLocation: TJSONObject;
begin
  Result := TJSONArray.Create;
  for mItem in ATargets do
  begin
    // Ersatz-Units der IDE (atlas-ide:…) gibt es nicht als Datei: kein Sprungziel für Strg+Klick.
    if TIdeUnits.IsIdePath(mItem.FileName) then
    begin
      Continue;
    end;
    mLocation := TJSONObject.Create;
    mLocation.AddPair('uri', TDocumentUris.FromPath(mItem.FileName));
    mLocation.AddPair('range', TLspPositions.RangeToJson(mItem.SelectionRange));
    Result.AddElement(mLocation);
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.Definition', cTexts);

end.
