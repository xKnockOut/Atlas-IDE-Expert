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

/// <summary>Überschreibende Methoden AName in allen Nachfahren von ATypeName.</summary>
function OverridingIn(const AIndex: ISymbolIndex; const ACurrent: TUnitIndex; const ATypeName,
  AName: string): TArray<TOverrideMarkTarget>;
var
  Location: TSymbolLocation;
  Owner: TUnitIndex;
  Symbol, Declaration, Body: TIndexSymbol;
  Found, Overrides: Boolean;
  Count: Integer;
begin
  Result := nil;
  for Location in TLspImplementations.AllDescendantsOf(AIndex, ATypeName) do
  begin
    if Length(Result) >= TLspOverrideMarks.MaxTargets then
      Break;
    if not UnitOf(AIndex, ACurrent, Location.FileName, Owner) then
      Continue;
    Found := False;
    Overrides := False;
    Count := 0;
    Declaration := Default(TIndexSymbol);
    Body := Default(TIndexSymbol);
    for Symbol in Owner.Symbols do
      if (Symbol.Kind in RoutineKinds) and SameText(Symbol.Container, Location.Symbol.QualifiedName) and
        SameText(Symbol.Name, AName) then
      begin
        // Die erste Fundstelle ist die Deklaration, die letzte bei mehreren der Rumpf.
        if not Found then
          Declaration := Symbol;
        Found := True;
        Body := Symbol;
        Inc(Count);
        if Symbol.HasDirective('override') then
          Overrides := True;
      end;
    if not Overrides then
      Continue;
    if Count < 2 then
      Body := Declaration;
    Result := Result + [MarkTarget(Location.Symbol.Name + '.' + AName, Owner.FileName, Body.SelectionRange)];
  end;
end;

{ TLspOverrideMarks }

class function TLspOverrideMarks.Marks(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName: string): TArray<TOverrideMark>;
var
  Current: TUnitIndex;
  Symbol, TypeSymbol, Other: TIndexSymbol;
  Types: TDictionary<string, TIndexSymbol>;
  Done: TDictionary<string, Boolean>;
  Lines: TDictionary<Integer, TOverrideMark>;
  Mark: TOverrideMark;
  Key, Owner: string;
  Ancestor: TCodeLensLocation;
  Overrides, Overridden: TArray<TOverrideMarkTarget>;
  HasOverride, HasVirtual: Boolean;
  Line: Integer;
  Sorted: TList<TOverrideMark>;
begin
  Result := nil;
  if ATree = nil then
    Exit;
  Current := TIndexExtractor.Extract(ATree, AFileName);
  Types := TDictionary<string, TIndexSymbol>.Create;
  Done := TDictionary<string, Boolean>.Create;
  Lines := TDictionary<Integer, TOverrideMark>.Create;
  try
    for Symbol in Current.Symbols do
      if Symbol.Kind in TypeKinds then
        Types.AddOrSetValue(UpperCase(Symbol.QualifiedName), Symbol);
    for Symbol in Current.Symbols do
    begin
      if not (Symbol.Kind in RoutineKinds) or (Symbol.Container = '') or
        not Types.TryGetValue(UpperCase(Symbol.Container), TypeSymbol) then
        Continue;
      // Deklaration und Rumpf (und Überladungen) gehören zusammen: einmal je Typ und Name.
      Key := UpperCase(Symbol.Container + '.' + Symbol.Name);
      if Done.ContainsKey(Key) then
        Continue;
      Done.Add(Key, True);
      HasOverride := False;
      HasVirtual := False;
      for Other in Current.Symbols do
        if (Other.Kind in RoutineKinds) and SameText(Other.Container, Symbol.Container) and
          SameText(Other.Name, Symbol.Name) then
        begin
          if Other.HasDirective('override') then
            HasOverride := True;
          if Other.IsVirtual then
            HasVirtual := True;
        end;
      Overrides := nil;
      if HasOverride and TLspCodeLens.OverriddenAncestor(AResolver, AIndex, Current, TypeSymbol, Symbol.Name, Owner,
        Ancestor) then
        Overrides := [MarkTarget(Owner + '.' + Symbol.Name, Ancestor.FileName, Ancestor.Range)];
      Overridden := nil;
      if HasVirtual and (TypeSymbol.Kind <> TIndexSymbolKind.RecordType) then
        Overridden := OverridingIn(AIndex, Current, TypeSymbol.QualifiedName, Symbol.Name);
      if (Length(Overrides) = 0) and (Length(Overridden) = 0) then
        Continue;
      for Other in Current.Symbols do
        if (Other.Kind in RoutineKinds) and SameText(Other.Container, Symbol.Container) and
          SameText(Other.Name, Symbol.Name) then
        begin
          Line := Other.SelectionRange.StartPos.Line;
          if not Lines.TryGetValue(Line, Mark) then
          begin
            Mark := Default(TOverrideMark);
            Mark.Line := Line;
          end;
          Mark.Overrides := Mark.Overrides + Overrides;
          Mark.Overridden := Mark.Overridden + Overridden;
          Lines.AddOrSetValue(Line, Mark);
        end;
    end;
    Sorted := TList<TOverrideMark>.Create(TComparer<TOverrideMark>.Construct(
      function(const ALeft, ARight: TOverrideMark): Integer
      begin
        Result := ALeft.Line - ARight.Line;
      end));
    try
      Sorted.AddRange(Lines.Values);
      Sorted.Sort;
      Result := Sorted.ToArray;
    finally
      Sorted.Free;
    end;
  finally
    Lines.Free;
    Done.Free;
    Types.Free;
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
    Exit(Json(nil));
  Uri := AArguments.Items[0].Value;
  if not AStore.TryGet(Uri, Document) then
    Exit(Json(nil));
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
