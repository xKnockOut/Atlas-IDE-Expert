unit Atlas.Common.Lsp.QualifiedNames;

// Voll qualifizierter Name des Symbols unter dem Cursor (#128), z. B. für
// Dokumentation, Commit-Nachrichten oder Anfragen an Claude Code. LSP hat
// keinen Zugriff auf die Zwischenablage: Der Befehl atlas.server.qualifiedName
// liefert den Namen als String, das Kopieren übernimmt der Client. Dasselbe gibt
// es als MCP-Werkzeug qualified_name.
//
// Format:
//   Vcl.Controls.TControl.Paint                       Unit-Namen bleiben vollständig
//   Unit.TAussen.TInnen.Methode                       verschachtelte Typen
//   System.Generics.Collections.TList<T>.Add          Typparameter der Deklaration
//   Unit.TKlasse.Methode(Integer, string)             mit Parametertypen auf Wunsch
//   Unit.Aussen.Innen                                 lokale Routinen mit der äußeren Routine

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver;

type
  TQualifiedNames = class
  public const
    Command = 'atlas.server.qualifiedName';
  public
    /// <summary>Qualifizierter Name von ASymbol. ATree und AFileName gehören zur Datei, in der gesucht wurde;
    /// sie liefern die umgebenden Routinen lokaler Symbole.</summary>
    class function Compose(const ASymbol: TResolvedSymbol; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName: string; AWithParameters: Boolean): string; static;
    /// <summary>Qualifizierter Name des Symbols an APosition; False mit AError, wenn dort keins steht.</summary>
    class function At(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName: string; const APosition: TTextPosition; AWithParameters: Boolean; out AName,
      AError: string): Boolean; static;
    /// <summary>Befehl atlas.server.qualifiedName mit den Argumenten URI, Position {line, character} und
    /// optional true für Parametertypen. Ergebnis ist der Name als String; EJsonRpcError ohne Symbol.</summary>
    class function Execute(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
      const AEnsureUnit: TEnsureUnitFunc; const ANamespaces: TArray<string>; const AArguments: TJSONArray): TJSONValue;
      static;
  end;

implementation

uses
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.Positions;

function Before(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Character < B.Character));
end;

/// <summary>Namen der Routinen mit Rumpf, in denen APosition liegt, von außen nach innen.</summary>
function EnclosingRoutines(ANode: TSyntaxNode; const APosition: TTextPosition): TArray<string>;
var
  Index: Integer;
  Child: TSyntaxNode;
begin
  Result := nil;
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    Child := ANode[Index];
    if Before(APosition, Child.StartPos) or not Before(APosition, Child.EndPos) then
      Continue;
    // Der Name der Routine selbst gehört nicht zu ihrem Inhalt: erst ab dem Rumpf bzw. den Deklarationen.
    if (Child.Kind = TSyntaxKind.RoutineDecl) and (Child.FindChild(TSyntaxKind.Block) <> nil) and
      (APosition.Line > Child.StartPos.Line) then
      Result := [Child.Name] + EnclosingRoutines(Child, APosition)
    else
      Result := EnclosingRoutines(Child, APosition);
    Exit;
  end;
end;

/// <summary>ATypeName mit &lt;Typparametern&gt;, wenn der Typ im Container AContainer der Unit generisch ist.</summary>
function WithTypeParams(const AUnit: TUnitIndex; AFound: Boolean; const AContainer, ATypeName: string): string;
var
  Symbol: TIndexSymbol;
begin
  Result := ATypeName;
  if not AFound then
    Exit;
  for Symbol in AUnit.Symbols do
    if SameText(Symbol.Name, ATypeName) and SameText(Symbol.Container, AContainer) and (Symbol.TypeParams <> '') and
      (Symbol.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
      TIndexSymbolKind.InterfaceType, TIndexSymbolKind.TypeAlias]) then
      Exit(ATypeName + '<' + StringReplace(Symbol.TypeParams, ',', ', ', [rfReplaceAll]) + '>');
end;

function InUses(ANode: TSyntaxNode; const APosition: TTextPosition): Boolean;
var
  Index: Integer;
begin
  if ANode.Kind = TSyntaxKind.UsesClause then
    Exit(not Before(APosition, ANode.StartPos) and Before(APosition, ANode.EndPos));
  for Index := 0 to ANode.ChildCount - 1 do
    if InUses(ANode[Index], APosition) then
      Exit(True);
  Result := False;
end;

/// <summary>Vollständiger Unit-Name (mit Punkten) aus einer uses-Liste an APosition; '' ohne.</summary>
function UsesUnitAt(ATree: TSyntaxTree; const APosition: TTextPosition): string;
var
  Tokens: TArray<TPascalToken>;
  Index, First, Last, Part: Integer;
begin
  Result := '';
  if (ATree.Root = nil) or not InUses(ATree.Root, APosition) then
    Exit;
  Tokens := ATree.Tokens;
  for Index := 0 to High(Tokens) do
    if (Tokens[Index].Kind = TPascalTokenKind.Identifier) and (Tokens[Index].StartPos.Line = APosition.Line) and
      (Tokens[Index].StartPos.Character <= APosition.Character) and
      (Tokens[Index].EndPos.Character >= APosition.Character) then
    begin
      First := Index;
      while (First >= 2) and Tokens[First - 1].IsSymbol('.') and
        (Tokens[First - 2].Kind = TPascalTokenKind.Identifier) do
        Dec(First, 2);
      Last := Index;
      while (Last + 2 <= High(Tokens)) and Tokens[Last + 1].IsSymbol('.') and
        (Tokens[Last + 2].Kind = TPascalTokenKind.Identifier) do
        Inc(Last, 2);
      for Part := First to Last do
        Result := Result + Tokens[Part].Text;
      Exit;
    end;
end;

class function TQualifiedNames.Compose(const ASymbol: TResolvedSymbol; const AIndex: ISymbolIndex;
  ATree: TSyntaxTree; const AFileName: string; AWithParameters: Boolean): string;
var
  UnitIndex: TUnitIndex;
  Found: Boolean;
  Parts: TArray<string>;
  Container, Name, Routine: string;
  Index: Integer;
begin
  if ASymbol.Kind = TResolvedKind.UnitName then
    Exit(ASymbol.Name);
  if ASymbol.Builtin then
    Exit('System.' + ASymbol.Name);
  // Die eigene Datei frisch aus dem Baum, andere aus dem Index.
  if (ATree <> nil) and SameText(ASymbol.FileName, AFileName) then
  begin
    UnitIndex := TIndexExtractor.Extract(ATree, AFileName);
    Found := True;
  end
  else
    Found := (AIndex <> nil) and (ASymbol.FileName <> '') and AIndex.FindFile(ASymbol.FileName, UnitIndex);
  Result := ASymbol.UnitName;
  // Umgebende Typen, je mit ihren Typparametern.
  Container := '';
  if ASymbol.Container <> '' then
  begin
    Parts := ASymbol.Container.Split(['.']);
    for Index := 0 to High(Parts) do
    begin
      Result := Result + '.' + WithTypeParams(UnitIndex, Found, Container, Parts[Index]);
      if Container <> '' then
        Container := Container + '.';
      Container := Container + Parts[Index];
    end;
  end
  else if (ATree <> nil) and SameText(ASymbol.FileName, AFileName) then
    // Lokale Symbole: umgebende Routinen, z. B. Unit.Aussen.Innen oder Unit.TFoo.Bar.Zaehler.
    for Routine in EnclosingRoutines(ATree.Root, ASymbol.SelectionRange.StartPos) do
      Result := Result + '.' + Routine;
  Name := ASymbol.Name;
  if ASymbol.IsType then
    Name := WithTypeParams(UnitIndex, Found, ASymbol.Container, Name)
  else if ASymbol.TypeParams <> '' then
    Name := Name + '<' + StringReplace(ASymbol.TypeParams, ',', ', ', [rfReplaceAll]) + '>';
  if Result = '' then
    Result := Name
  else
    Result := Result + '.' + Name;
  if AWithParameters and (ASymbol.SymbolKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_,
    TIndexSymbolKind.Routine]) then
    Result := Result + '(' + string.Join(', ', ASymbol.ParamTypes) + ')';
end;

class function TQualifiedNames.At(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName: string; const APosition: TTextPosition; AWithParameters: Boolean; out AName,
  AError: string): Boolean;
var
  Symbol: TResolvedSymbol;
  UnitIndex: TUnitIndex;
  Declared: TIndexSymbol;
begin
  AName := '';
  AError := '';
  // Unit-Namen in uses stehen für sich.
  AName := UsesUnitAt(ATree, APosition);
  if AName <> '' then
    Exit(True);
  // Auf einer Deklaration der Datei genau diese (auch die richtige Überladung), sonst die Namensauflösung.
  Symbol := Default(TResolvedSymbol);
  UnitIndex := TIndexExtractor.Extract(ATree, AFileName);
  for Declared in UnitIndex.Symbols do
    if (Declared.SelectionRange.StartPos.Line = APosition.Line) and
      (Declared.SelectionRange.StartPos.Character <= APosition.Character) and
      (Declared.SelectionRange.EndPos.Character >= APosition.Character) then
    begin
      Symbol.Kind := TResolvedKind.Symbol;
      Symbol.Name := Declared.Name;
      Symbol.UnitName := UnitIndex.UnitName;
      Symbol.FileName := AFileName;
      Symbol.Range := Declared.Range;
      Symbol.SelectionRange := Declared.SelectionRange;
      Symbol.SymbolKind := Declared.Kind;
      Symbol.Container := Declared.Container;
      Symbol.TypeParams := Declared.TypeParams;
      Symbol.ParamTypes := Declared.ParamTypes;
      Break;
    end;
  if not Symbol.Found then
    Symbol := AResolver.Resolve(ATree, AFileName, APosition);
  if not Symbol.Found then
  begin
    AError := Format('An Zeile %d, Spalte %d steht kein bekanntes Symbol', [APosition.Line + 1,
      APosition.Character + 1]);
    Exit(False);
  end;
  AName := Compose(Symbol, AIndex, ATree, AFileName, AWithParameters);
  Result := True;
end;

class function TQualifiedNames.Execute(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AEnsureUnit: TEnsureUnitFunc; const ANamespaces: TArray<string>; const AArguments: TJSONArray): TJSONValue;
var
  Uri, Name, Error: string;
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  WithParameters: Boolean;
begin
  if (AArguments = nil) or (AArguments.Count < 2) or not (AArguments.Items[0] is TJSONString) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Erwartet werden URI und Position');
  Uri := AArguments.Items[0].Value;
  WithParameters := (AArguments.Count > 2) and (AArguments.Items[2] is TJSONBool) and
    TJSONBool(AArguments.Items[2]).AsBoolean;
  if not AStore.TryGet(Uri, Document) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Dokument ist nicht geöffnet: ' + Uri);
  Shared := TSyntaxTreeCache.Get(Document);
  Resolver := TNameResolver.Create(AIndex, AEnsureUnit);
  try
    Resolver.Namespaces := ANamespaces;
    if not At(Resolver, AIndex, Shared.Tree, TDocumentUris.ToPath(Uri),
      TLspPositions.ReadPosition(AArguments.Items[1]), WithParameters, Name, Error) then
      raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, Error);
  finally
    Resolver.Free;
  end;
  Result := TJSONString.Create(Name);
end;

end.
