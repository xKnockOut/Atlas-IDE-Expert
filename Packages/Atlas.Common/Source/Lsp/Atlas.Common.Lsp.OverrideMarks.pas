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
    cCommand = 'atlas.server.overrideMarks';
    /// <summary>Höchstens so viele Nachfahren je Methode; mehr bremsen nur das Zeichnen.</summary>
    cMaxTargets = 100;
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
  cRoutineKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine];
  cTypeKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
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
  Result := (ASymbol.Kind in cRoutineKinds) and SameText(ASymbol.Container, AContainer) and
    SameText(ASymbol.Name, AName);
end;

/// <summary>Rumpf (bzw. ohne Rumpf die Deklaration) der Methode AContainer.AName in AOwner, wenn sie override
/// trägt.</summary>
function OverridingBody(const AOwner: TUnitIndex; const AContainer, AName: string; out ABody: TIndexSymbol): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  Result := False;
  ABody := Default(TIndexSymbol);
  for mSymbol in AOwner.Symbols do
  begin
    if IsRoutineOf(mSymbol, AContainer, AName) then
    begin
      // Die erste Fundstelle ist die Deklaration, die letzte bei mehreren der Rumpf.
      ABody := mSymbol;
      Result := Result or mSymbol.HasDirective('override');
    end;
  end;
end;

/// <summary>Überschreibende Methoden AName in allen Nachfahren von ATypeName.</summary>
function OverridingIn(const AIndex: ISymbolIndex; const ACurrent: TUnitIndex; const ATypeName,
  AName: string): TArray<TOverrideMarkTarget>;
var
  mLocation: TSymbolLocation;
  mOwner: TUnitIndex;
  mBody: TIndexSymbol;
begin
  Result := nil;
  for mLocation in TLspImplementations.AllDescendantsOf(AIndex, ATypeName) do
  begin
    if Length(Result) >= TLspOverrideMarks.cMaxTargets then
    begin
      Break;
    end;
    if UnitOf(AIndex, ACurrent, mLocation.FileName, mOwner) and
      OverridingBody(mOwner, mLocation.Symbol.QualifiedName, AName, mBody) then
    begin
      Result := Result + [MarkTarget(mLocation.Symbol.Name + '.' + AName, mOwner.FileName, mBody.SelectionRange)];
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
    if mSymbol.Kind in cTypeKinds then
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
  if not (ASymbol.Kind in cRoutineKinds) or (ASymbol.Container = '') or
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
  mTarget: TOverrideMarkTarget;
  mItem: TJSONObject;
begin
  Result := TJSONArray.Create;
  for mTarget in ATargets do
  begin
    mItem := TJSONObject.Create;
    Result.AddElement(mItem);
    mItem.AddPair('name', mTarget.Name);
    mItem.AddPair('uri', TDocumentUris.FromPath(mTarget.FileName));
    mItem.AddPair('line', TJSONNumber.Create(mTarget.Range.StartPos.Line));
    mItem.AddPair('character', TJSONNumber.Create(mTarget.Range.StartPos.Character));
  end;
end;

class function TLspOverrideMarks.Json(const AMarks: TArray<TOverrideMark>): TJSONObject;
var
  mLines: TJSONArray;
  mItem: TJSONObject;
  mMark: TOverrideMark;
begin
  Result := TJSONObject.Create;
  mLines := TJSONArray.Create;
  Result.AddPair('lines', mLines);
  for mMark in AMarks do
  begin
    mItem := TJSONObject.Create;
    mLines.AddElement(mItem);
    mItem.AddPair('line', TJSONNumber.Create(mMark.Line));
    mItem.AddPair('overrides', TargetsJson(mMark.Overrides));
    mItem.AddPair('overridden', TargetsJson(mMark.Overridden));
  end;
end;

class function TLspOverrideMarks.Execute(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AEnsureUnit: TEnsureUnitFunc; const ANamespaces: TArray<string>; const AArguments: TJSONArray): TJSONValue;
var
  mUri: string;
  mDocument: ITextDocument;
  mShared: ISharedSyntaxTree;
  mResolver: TNameResolver;
begin
  if (AArguments = nil) or (AArguments.Count < 1) or not (AArguments.Items[0] is TJSONString) then
  begin
    Exit(Json(nil));
  end;
  mUri := AArguments.Items[0].Value;
  if not AStore.TryGet(mUri, mDocument) then
  begin
    Exit(Json(nil));
  end;
  mShared := TSyntaxTreeCache.Get(mDocument);
  mResolver := TNameResolver.Create(AIndex, AEnsureUnit);
  try
    mResolver.Namespaces := ANamespaces;
    Result := Json(Marks(mResolver, AIndex, mShared.Tree, TDocumentUris.ToPath(mUri)));
  finally
    mResolver.Free;
  end;
end;

end.
