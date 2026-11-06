unit Atlas.Common.Lsp.OverrideMarks;

// Befehl atlas.server.overrideMarks (#768): Überschreibungen für die
// Atlas-Spalte in der Zeilenleiste des IDE-Plugins.
// Argumente: [uri]
// Antwort (Zeilen und Zeichen ab 0 wie im Protokoll), je Zeile mit dem Namen
// einer Methode (Deklaration und Rumpf):
//   {"lines": [{"line": 12,
//               "overrides":  [{"name": "TControl.Paint", "uri": "file:///…", "line": 30, "character": 14}],
//               "overridden": [{"name": "TKnopf.Paint", "uri": "file:///…", "line": 8, "character": 14}]}]}
// - overrides: Die Methode ist mit override deklariert; Ziel ist die
//   Deklaration im nächsten Vorfahren, der sie deklariert (wie die Code Lens
//   „überschreibt …“).
// - overridden: Die Methode ist virtual, dynamic, abstract oder override, und
//   Nachfahren über alle Stufen deklarieren sie mit override; Ziel ist je
//   Nachfahre der Rumpf, ohne Rumpf die Deklaration (wie Gehe zu
//   Implementierung).
// Zeilen ohne beides fehlen. Ist das Dokument nicht geöffnet, ist die Liste leer.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver;

type
  TOverrideMarkTarget = record
    /// <summary>Typ und Methode, z. B. "TControl.Paint".</summary>
    Name: string;
    FileName: string;
    /// <summary>Name der Methode im Ziel.</summary>
    Range: TTextRange;
  end;

  TOverrideMark = record
    /// <summary>0-basiert.</summary>
    Line: Integer;
    Overrides: TArray<TOverrideMarkTarget>;
    Overridden: TArray<TOverrideMarkTarget>;
  end;

  TLspOverrideMarks = class
  public const
    Command = 'atlas.server.overrideMarks';
    /// <summary>Höchstens so viele Nachfahren je Methode; mehr bremsen nur das Zeichnen.</summary>
    MaxTargets = 100;
  public
    /// <summary>Marken der Datei AFileName mit dem Baum ATree, nach Zeilen sortiert.</summary>
    class function Marks(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName: string): TArray<TOverrideMark>; static;
    /// <summary>Antwort für AMarks (siehe Kopf der Unit); der Aufrufer übernimmt das Objekt.</summary>
    class function Json(const AMarks: TArray<TOverrideMark>): TJSONObject; static;
    /// <summary>Befehl atlas.server.overrideMarks; der Aufrufer übernimmt das Ergebnis.</summary>
    class function Execute(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
      const AEnsureUnit: TEnsureUnitFunc; const ANamespaces: TArray<string>; const AArguments: TJSONArray): TJSONValue;
      static;
  end;

implementation

uses
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.CodeLens,
  Atlas.Common.Lsp.Implementations;

const
  RoutineKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine];
  TypeKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.InterfaceType];

function MarkTarget(const AName, AFileName: string; const ARange: TTextRange): TOverrideMarkTarget;
begin
  Result.Name := AName;
  Result.FileName := AFileName;
  Result.Range := ARange;
end;

function UnitOf(const AIndex: ISymbolIndex; const ACurrent: TUnitIndex; const AFileName: string;
  out AUnit: TUnitIndex): Boolean;
begin
  // Die eigene Datei aus dem Editor, nicht aus dem Index.
  if SameText(AFileName, ACurrent.FileName) then
  begin
    AUnit := ACurrent;
    Exit(True);
  end;
  Result := AIndex.FindFile(AFileName, AUnit);
end;

function IsRoutineOf(const ASymbol: TIndexSymbol; const AContainer, AName: string): Boolean;
begin
  Result := (ASymbol.Kind in RoutineKinds) and SameText(ASymbol.Container, AContainer) and
    SameText(ASymbol.Name, AName);
end;

/// <summary>Rumpf (bzw. ohne Rumpf die Deklaration) der Methode AContainer.AName in AOwner, wenn sie override
/// trägt.</summary>
function OverridingBody(const AOwner: TUnitIndex; const AContainer, AName: string; out ABody: TIndexSymbol): Boolean;
var
  Symbol: TIndexSymbol;
begin
  Result := False;
  ABody := Default(TIndexSymbol);
  for Symbol in AOwner.Symbols do
  begin
    if IsRoutineOf(Symbol, AContainer, AName) then
    begin
      // Die erste Fundstelle ist die Deklaration, die letzte bei mehreren der Rumpf.
      ABody := Symbol;
      Result := Result or Symbol.HasDirective('override');
    end;
  end;
end;

/// <summary>Überschreibende Methoden AName in allen Nachfahren von ATypeName.</summary>
function OverridingIn(const AIndex: ISymbolIndex; const ACurrent: TUnitIndex; const ATypeName,
  AName: string): TArray<TOverrideMarkTarget>;
var
  Location: TSymbolLocation;
  Owner: TUnitIndex;
  Body: TIndexSymbol;
begin
  Result := nil;
  for Location in TLspImplementations.AllDescendantsOf(AIndex, ATypeName) do
  begin
    if Length(Result) >= TLspOverrideMarks.MaxTargets then
    begin
      Break;
    end;
    if UnitOf(AIndex, ACurrent, Location.FileName, Owner) and
      OverridingBody(Owner, Location.Symbol.QualifiedName, AName, Body) then
    begin
      Result := Result + [MarkTarget(Location.Symbol.Name + '.' + AName, Owner.FileName, Body.SelectionRange)];
    end;
  end;
end;

type
  /// <summary>Marken einer Datei: je Zeile die überschriebenen und überschreibenden Methoden.</summary>
  TMarkScan = class
  private
    FResolver: TNameResolver;
    FIndex: ISymbolIndex;
    FCurrent: TUnitIndex;
    FTypes: TDictionary<string, TIndexSymbol>;
    FDone: TDictionary<string, Boolean>;
    FLines: TDictionary<Integer, TOverrideMark>;
    procedure Directives(const ASymbol: TIndexSymbol; out AOverride, AVirtual: Boolean);
    procedure AddLines(const ASymbol: TIndexSymbol; const AOverrides, AOverridden: TArray<TOverrideMarkTarget>);
    procedure AddSymbol(const ASymbol: TIndexSymbol);
  public
    constructor Create(AResolver: TNameResolver; const AIndex: ISymbolIndex; const ACurrent: TUnitIndex);
    destructor Destroy; override;
    procedure Run;
    function Sorted: TArray<TOverrideMark>;
  end;

constructor TMarkScan.Create(AResolver: TNameResolver; const AIndex: ISymbolIndex; const ACurrent: TUnitIndex);
var
  mSymbol: TIndexSymbol;
begin
  inherited Create;
  FResolver := AResolver;
  FIndex := AIndex;
  FCurrent := ACurrent;
  FTypes := TDictionary<string, TIndexSymbol>.Create;
  FDone := TDictionary<string, Boolean>.Create;
  FLines := TDictionary<Integer, TOverrideMark>.Create;
  for mSymbol in FCurrent.Symbols do
  begin
    if mSymbol.Kind in TypeKinds then
    begin
      FTypes.AddOrSetValue(UpperCase(mSymbol.QualifiedName), mSymbol);
    end;
  end;
end;

destructor TMarkScan.Destroy;
begin
  FLines.Free;
  FDone.Free;
  FTypes.Free;
  inherited;
end;

procedure TMarkScan.Directives(const ASymbol: TIndexSymbol; out AOverride, AVirtual: Boolean);
var
  mOther: TIndexSymbol;
begin
  AOverride := False;
  AVirtual := False;
  for mOther in FCurrent.Symbols do
  begin
    if IsRoutineOf(mOther, ASymbol.Container, ASymbol.Name) then
    begin
      AOverride := AOverride or mOther.HasDirective('override');
      AVirtual := AVirtual or mOther.IsVirtual;
    end;
  end;
end;

procedure TMarkScan.AddLines(const ASymbol: TIndexSymbol; const AOverrides, AOverridden: TArray<TOverrideMarkTarget>);
var
  mOther: TIndexSymbol;
  mMark: TOverrideMark;
  mLine: Integer;
begin
  for mOther in FCurrent.Symbols do
  begin
    if IsRoutineOf(mOther, ASymbol.Container, ASymbol.Name) then
    begin
      mLine := mOther.SelectionRange.StartPos.Line;
      if not FLines.TryGetValue(mLine, mMark) then
      begin
        mMark := Default(TOverrideMark);
        mMark.Line := mLine;
      end;
      mMark.Overrides := mMark.Overrides + AOverrides;
      mMark.Overridden := mMark.Overridden + AOverridden;
      FLines.AddOrSetValue(mLine, mMark);
    end;
  end;
end;

procedure TMarkScan.AddSymbol(const ASymbol: TIndexSymbol);
var
  mTypeSymbol: TIndexSymbol;
  mKey: string;
  mAncestor: TCodeLensOverride;
  mOverrides, mOverridden: TArray<TOverrideMarkTarget>;
  mHasOverride, mHasVirtual: Boolean;
begin
  if not (ASymbol.Kind in RoutineKinds) or (ASymbol.Container = '') or
    not FTypes.TryGetValue(UpperCase(ASymbol.Container), mTypeSymbol) then
  begin
    Exit;
  end;
  // Deklaration und Rumpf (und Überladungen) gehören zusammen: einmal je Typ und Name.
  mKey := UpperCase(ASymbol.Container + '.' + ASymbol.Name);
  if FDone.ContainsKey(mKey) then
  begin
    Exit;
  end;
  FDone.Add(mKey, True);
  Directives(ASymbol, mHasOverride, mHasVirtual);
  mOverrides := nil;
  if mHasOverride and TLspCodeLens.OverriddenAncestor(FResolver, FIndex, FCurrent, mTypeSymbol, ASymbol.Name,
    mAncestor) then
  begin
    mOverrides := [MarkTarget(mAncestor.Owner + '.' + ASymbol.Name, mAncestor.Target.FileName,
      mAncestor.Target.Range)];
  end;
  mOverridden := nil;
  if mHasVirtual and (mTypeSymbol.Kind <> TIndexSymbolKind.RecordType) then
  begin
    mOverridden := OverridingIn(FIndex, FCurrent, mTypeSymbol.QualifiedName, ASymbol.Name);
  end;
  if (mOverrides <> nil) or (mOverridden <> nil) then
  begin
    AddLines(ASymbol, mOverrides, mOverridden);
  end;
end;

procedure TMarkScan.Run;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in FCurrent.Symbols do
  begin
    AddSymbol(mSymbol);
  end;
end;

function TMarkScan.Sorted: TArray<TOverrideMark>;
var
  mSorted: TList<TOverrideMark>;
begin
  mSorted := TList<TOverrideMark>.Create(TComparer<TOverrideMark>.Construct(
    function(const ALeft, ARight: TOverrideMark): Integer
    begin
      Result := ALeft.Line - ARight.Line;
    end));
  try
    mSorted.AddRange(FLines.Values);
    mSorted.Sort;
    Result := mSorted.ToArray;
  finally
    mSorted.Free;
  end;
end;

{ TLspOverrideMarks }

class function TLspOverrideMarks.Marks(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName: string): TArray<TOverrideMark>;
var
  mScan: TMarkScan;
begin
  Result := nil;
  if ATree = nil then
  begin
    Exit;
  end;
  mScan := TMarkScan.Create(AResolver, AIndex, TIndexExtractor.Extract(ATree, AFileName));
  try
    mScan.Run;
    Result := mScan.Sorted;
  finally
    mScan.Free;
  end;
end;

function TargetsJson(const ATargets: TArray<TOverrideMarkTarget>): TJSONArray;
var
  Target: TOverrideMarkTarget;
  Item: TJSONObject;
begin
  Result := TJSONArray.Create;
  for Target in ATargets do
  begin
    Item := TJSONObject.Create;
    Result.AddElement(Item);
    Item.AddPair('name', Target.Name);
    Item.AddPair('uri', TDocumentUris.FromPath(Target.FileName));
    Item.AddPair('line', TJSONNumber.Create(Target.Range.StartPos.Line));
    Item.AddPair('character', TJSONNumber.Create(Target.Range.StartPos.Character));
  end;
end;

class function TLspOverrideMarks.Json(const AMarks: TArray<TOverrideMark>): TJSONObject;
var
  Lines: TJSONArray;
  Item: TJSONObject;
  Mark: TOverrideMark;
begin
  Result := TJSONObject.Create;
  Lines := TJSONArray.Create;
  Result.AddPair('lines', Lines);
  for Mark in AMarks do
  begin
    Item := TJSONObject.Create;
    Lines.AddElement(Item);
    Item.AddPair('line', TJSONNumber.Create(Mark.Line));
    Item.AddPair('overrides', TargetsJson(Mark.Overrides));
    Item.AddPair('overridden', TargetsJson(Mark.Overridden));
  end;
end;

class function TLspOverrideMarks.Execute(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AEnsureUnit: TEnsureUnitFunc; const ANamespaces: TArray<string>; const AArguments: TJSONArray): TJSONValue;
var
  Uri: string;
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
begin
  if (AArguments = nil) or (AArguments.Count < 1) or not (AArguments.Items[0] is TJSONString) then
  begin
    Exit(Json(nil));
  end;
  Uri := AArguments.Items[0].Value;
  if not AStore.TryGet(Uri, Document) then
  begin
    Exit(Json(nil));
  end;
  Shared := TSyntaxTreeCache.Get(Document);
  Resolver := TNameResolver.Create(AIndex, AEnsureUnit);
  try
    Resolver.Namespaces := ANamespaces;
    Result := Json(Marks(Resolver, AIndex, Shared.Tree, TDocumentUris.ToPath(Uri)));
  finally
    Resolver.Free;
  end;
end;

end.
