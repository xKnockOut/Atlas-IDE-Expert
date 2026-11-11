unit Atlas.Common.Lsp.Definition;

// Gehe zu Definition und Gehe zu Deklaration (textDocument/definition,
// textDocument/declaration) über die Namensauflösung.
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
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Dfm.Navigation;

type
  TDefinitionTarget = record
    FileName: string;
    Range: TTextRange;
    SelectionRange: TTextRange;
  end;

  TDefinitionRequestKind = (Definition, Declaration, TypeDefinition);

  /// <summary>Stelle einer Sprungabfrage: Baum, Datei, Position und ob zur Deklaration.</summary>
  TDefinitionQuery = record
    Tree: TSyntaxTree;
    FileName: string;
    Position: TTextPosition;
    /// <summary>Immer zur Deklaration springen (sonst wechselt die Taste zwischen beiden).</summary>
    Declaration: Boolean;
    class function Create(ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition;
      ADeclaration: Boolean): TDefinitionQuery; static;
  end;

  TLspDefinition = class
  public const
    cDefinitionMethod = 'textDocument/definition';
    cDeclarationMethod = 'textDocument/declaration';
    cTypeDefinitionMethod = 'textDocument/typeDefinition';
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    FEnsureUnit: TEnsureUnitFunc;
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
    /// <summary>Unter TLspNamespaces gelesen und ersetzt (Code-Review A-03): Die Komposition setzt sie
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
    /// <summary>Sprungziele für den Bezeichner an APosition; leer, wenn er nicht auflösbar ist.</summary>
    class function Targets(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName: string; const APosition: TTextPosition; ADeclaration: Boolean): TArray<TDefinitionTarget>;
        static;
    /// <summary>Wie Targets, für ein schon aufgelöstes Symbol (etwa einen Kandidaten aus ResolveAll, #1119).
    /// </summary>
    class function TargetsOf(AResolver: TNameResolver; const AIndex: ISymbolIndex; const AQuery: TDefinitionQuery;
      const AResolved: TResolvedSymbol): TArray<TDefinitionTarget>; static;
    /// <summary>Deklaration des Typs des Bezeichners an APosition; leer, wenn er keinen bekannten Typ hat.</summary>
    class function TypeTargets(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
      const APosition: TTextPosition): TArray<TDefinitionTarget>; static;
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
  System.Generics.Collections,
  Atlas.Common.Lsp.Internals.Namespaces,
  Atlas.Common.Index.Files,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.Positions,
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

const
  cRoutineKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine];

function Within(const APosition: TTextPosition; const ARange: TTextRange): Boolean;
begin
  Result :=
    ((APosition.Line > ARange.StartPos.Line) or
     ((APosition.Line = ARange.StartPos.Line) and (APosition.Character >= ARange.StartPos.Character))) and
    ((APosition.Line < ARange.EndPos.Line) or
     ((APosition.Line = ARange.EndPos.Line) and (APosition.Character <= ARange.EndPos.Character)));
end;

/// <summary>Gleiche Parametertypen (Groß-/Kleinschreibung egal): dieselbe Variante einer Überladung.</summary>
function SameParams(const A, B: TArray<string>): Boolean;
var
  mIndex: Integer;
begin
  Result := Length(A) = Length(B);
  if not Result then
  begin
    Exit;
  end;
  for mIndex := 0 to High(A) do
  begin
    if not SameText(A[mIndex], B[mIndex]) then
    begin
      Exit(False);
    end;
  end;
end;

function Target(const AFileName: string; const ARange, ASelectionRange: TTextRange): TDefinitionTarget;
begin
  Result.FileName := AFileName;
  Result.Range := ARange;
  Result.SelectionRange := ASelectionRange;
end;

{ TDefinitionQuery }

class function TDefinitionQuery.Create(ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition;
  ADeclaration: Boolean): TDefinitionQuery;
begin
  Result.Tree := ATree;
  Result.FileName := AFileName;
  Result.Position := APosition;
  Result.Declaration := ADeclaration;
end;

{ TLspDefinition }

function TLspDefinition.GetNamespaces: TArray<string>;
begin
  Result := TLspNamespaces.Read(FNamespaces);
end;

procedure TLspDefinition.SetNamespaces(const AValue: TArray<string>);
begin
  TLspNamespaces.Write(FNamespaces, AValue);
end;

constructor TLspDefinition.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex);
begin
  Create(AStore, AIndex, nil);
end;

constructor TLspDefinition.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create;
  FStore := AStore;
  FIndex := AIndex;
  FEnsureUnit := AEnsureUnit;
end;

procedure TLspDefinition.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(cDefinitionMethod, HandleDefinition);
  ADispatcher.RegisterConcurrentRequest(cDeclarationMethod, HandleDeclaration);
  ADispatcher.RegisterConcurrentRequest(cTypeDefinitionMethod, HandleTypeDefinition);
end;

class function TLspDefinition.Targets(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName: string; const APosition: TTextPosition; ADeclaration: Boolean): TArray<TDefinitionTarget>;
begin
  Result := TargetsOf(AResolver, AIndex, TDefinitionQuery.Create(ATree, AFileName, APosition, ADeclaration),
    AResolver.Resolve(ATree, AFileName, APosition));
end;

/// <summary>Die Deklaration unter dem Cursor in der eigenen Datei; Kind None, wenn dort keine steht.</summary>
function DeclarationAt(AResolver: TNameResolver; const AQuery: TDefinitionQuery): TResolvedSymbol;
var
  mOwnerUnit: TUnitIndex;
  mSymbol: TIndexSymbol;
begin
  Result := Default(TResolvedSymbol);
  // Über den Resolver: bei gepinntem Baum ohne neue Auswertung (Code-Review P-01).
  mOwnerUnit := AResolver.ExtractedUnit(AQuery.Tree, AQuery.FileName);
  for mSymbol in mOwnerUnit.Symbols do
  begin
    if SameText(mOwnerUnit.SymbolFile(mSymbol), AQuery.FileName) and
      Within(AQuery.Position, mSymbol.SelectionRange) then
    begin
      Result.Kind := TResolvedKind.Symbol;
      Result.Name := mSymbol.Name;
      Result.Container := mSymbol.Container;
      Result.SymbolKind := mSymbol.Kind;
      Result.FileName := AQuery.FileName;
      Result.Range := mSymbol.Range;
      Result.SelectionRange := mSymbol.SelectionRange;
      Result.ParamTypes := mSymbol.ParamTypes;
      Exit;
    end;
  end;
end;

/// <summary>Parametertypen der gemeinten Variante: die der Routine unter dem Cursor in AHere, sonst die von
/// AResolved.</summary>
function VariantParams(AHere: TUnitIndex; const AResolved: TResolvedSymbol;
  const APosition: TTextPosition): TArray<string>;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in AHere.Symbols do
  begin
    if (mSymbol.Kind in cRoutineKinds) and SameText(mSymbol.Name, AResolved.Name) and
      Within(APosition, mSymbol.SelectionRange) then
    begin
      Exit(mSymbol.ParamTypes);
    end;
  end;
  Result := AResolved.ParamTypes;
end;

/// <summary>Fundstellen der Routine AResolved in AOwner: erst die Variante mit AParams, ohne zweite Fundstelle
/// das einzige Paar ohne Überladungen (die Implementierung darf ihre Parameter weglassen). False ohne Paar.
/// </summary>
function RoutinePair(AOwner: TUnitIndex; const AResolved: TResolvedSymbol; const AParams: TArray<string>;
  out AVariant: TArray<TIndexSymbol>): Boolean;
var
  mSymbol: TIndexSymbol;
  mSame: TArray<TIndexSymbol>;
begin
  mSame := nil;
  AVariant := nil;
  for mSymbol in AOwner.Symbols do
  begin
    if (mSymbol.Kind in cRoutineKinds) and SameText(mSymbol.Container, AResolved.Container) and
      SameText(mSymbol.Name, AResolved.Name) then
    begin
      mSame := mSame + [mSymbol];
      if SameParams(mSymbol.ParamTypes, AParams) then
      begin
        AVariant := AVariant + [mSymbol];
      end;
    end;
  end;
  if (Length(AVariant) < 2) and (Length(mSame) = 2) then
  begin
    AVariant := mSame;
  end;
  Result := Length(AVariant) >= 2;
end;

/// <summary>Ziel einer Routine: Deklaration und Implementierung derselben Variante. Steht der Cursor auf einer
/// Routine dieser Datei (Deklaration oder Implementierung), gilt deren Variante. Ohne Paar das Symbol selbst.
/// </summary>
function RoutineTargets(AResolver: TNameResolver; const AIndex: ISymbolIndex; const AQuery: TDefinitionQuery;
  const AResolved: TResolvedSymbol): TArray<TDefinitionTarget>;
var
  mHere, mOwnerUnit: TUnitIndex;
  mVariant: TArray<TIndexSymbol>;
  mFirst, mLast, mChosen: TIndexSymbol;
  mFound: Boolean;
begin
  Result := [Target(AResolved.FileName, AResolved.Range, AResolved.SelectionRange)];
  mHere := AResolver.ExtractedUnit(AQuery.Tree, AQuery.FileName);
  mOwnerUnit := mHere;
  mFound := SameText(AResolved.FileName, AQuery.FileName) or TIndexFiles.UnitOf(AIndex, AResolved.FileName,
    mOwnerUnit);
  if not mFound or not RoutinePair(mOwnerUnit, AResolved, VariantParams(mHere, AResolved, AQuery.Position),
    mVariant) then
  begin
    Exit;
  end;
  mFirst := mVariant[0];
  mLast := mVariant[High(mVariant)];
  // Mit Include-Dateien (#500) kann jede Fundstelle in einer anderen Datei stehen.
  mChosen := mLast;
  if AQuery.Declaration or (SameText(mOwnerUnit.SymbolFile(mLast), AQuery.FileName) and
    Within(AQuery.Position, mLast.SelectionRange)) then
  begin
    mChosen := mFirst;
  end;
  Result := [Target(mOwnerUnit.SymbolFile(mChosen), mChosen.Range, mChosen.SelectionRange)];
end;

class function TLspDefinition.TargetsOf(AResolver: TNameResolver; const AIndex: ISymbolIndex;
  const AQuery: TDefinitionQuery; const AResolved: TResolvedSymbol): TArray<TDefinitionTarget>;
var
  mResolved: TResolvedSymbol;
  mEmpty: TTextRange;
begin
  // Namen in Deklarationen (z. B. Methoden in der Klasse) sind keine Verwendungen:
  // dann gilt die Deklaration unter dem Cursor selbst. Zuerst prüfen: Die
  // Namensauflösung liest einen solchen Namen sonst wie eine Verwendung und nimmt
  // bei Überladungen die erste (Hover auf der zweiten zeigte die erste).
  // Das Ergebnis erst zuweisen statt Exit([...]): In der früheren Form brach dcc64 (Delphi 13) ohne Meldung ab.
  mResolved := DeclarationAt(AResolver, AQuery);
  // Sonst die schon aufgelöste Verwendung des Aufrufers (TargetsOf, #1119).
  if mResolved.Kind = TResolvedKind.None then
  begin
    mResolved := AResolved;
  end;
  case mResolved.Kind of
    TResolvedKind.None:
      Result := nil;
    TResolvedKind.UnitName:
      begin
        mEmpty := TTextRange.Create(TTextPosition.Create(0, 0), TTextPosition.Create(0, 0));
        Result := [Target(mResolved.FileName, mEmpty, mEmpty)];
      end;
    TResolvedKind.Local:
      Result := [Target(AQuery.FileName, mResolved.Range, mResolved.SelectionRange)];
  else
    if mResolved.SymbolKind in cRoutineKinds then
    begin
      Result := RoutineTargets(AResolver, AIndex, AQuery, mResolved);
    end
    else
    begin
      Result := [Target(mResolved.FileName, mResolved.Range, mResolved.SelectionRange)];
    end;
  end;
end;

class function TLspDefinition.TypeTargets(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition): TArray<TDefinitionTarget>;
var
  mTypeInfo: TResolvedSymbol;
begin
  mTypeInfo := AResolver.ResolveType(ATree, AFileName, APosition);
  if mTypeInfo.Kind = TResolvedKind.Symbol then
  begin
    Result := [Target(mTypeInfo.FileName, mTypeInfo.Range, mTypeInfo.SelectionRange)];
  end
  else
  begin
    Result := nil;
  end;
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
      Result := ToJson(TypeTargets(mResolver, mTree, TDocumentUris.ToPath(mUri),
        TLspPositions.ReadPosition(mPositionValue)));
    end
    else
    begin
      Result := ToJson(Targets(mResolver, FIndex, mTree, TDocumentUris.ToPath(mUri),
        TLspPositions.ReadPosition(mPositionValue), AKind = TDefinitionRequestKind.Declaration));
    end;
  finally
    mResolver.Free;
  end;
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
    mTargets[mIndex] := Target(mFound[mIndex].FileName, mFound[mIndex].Range, mFound[mIndex].SelectionRange);
  end;
  Result := ToJson(mTargets);
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

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.Definition', cTexts);

end.
