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
  /// <summary>Stelle, deren Symbol gesucht wird.</summary>
  TQualifiedNameRequest = record
    FileName: string;
    Position: TTextPosition;
    /// <summary>Mit Parametertypen bei Routinen.</summary>
    WithParameters: Boolean;
    class function Create(const AFileName: string; const APosition: TTextPosition;
      AWithParameters: Boolean): TQualifiedNameRequest; static;
  end;

  TQualifiedNames = class
  public const
    Command = 'atlas.server.qualifiedName';
  public
    /// <summary>Qualifizierter Name von ASymbol. ATree und AFileName gehören zur Datei, in der gesucht wurde;
    /// sie liefern die umgebenden Routinen lokaler Symbole.</summary>
    class function Compose(const ASymbol: TResolvedSymbol; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName: string; AWithParameters: Boolean): string; static;
    /// <summary>Qualifizierter Name des Symbols an der Stelle ARequest; False mit AError, wenn dort keins steht.
    /// </summary>
    class function At(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const ARequest: TQualifiedNameRequest; out AName, AError: string): Boolean; static;
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
  Node, Child: TSyntaxNode;
begin
  // Schleife statt Rekursion (Bericht M1): dem ersten Kind folgen, das APosition enthält.
  Result := nil;
  Node := ANode;
  while Node <> nil do
  begin
    Child := nil;
    for Index := 0 to Node.ChildCount - 1 do
    begin
      if not Before(APosition, Node[Index].StartPos) and Before(APosition, Node[Index].EndPos) then
      begin
        Child := Node[Index];
        Break;
      end;
    end;
    // Der Name der Routine selbst gehört nicht zu ihrem Inhalt: erst ab dem Rumpf bzw. den Deklarationen.
    if (Child <> nil) and (Child.Kind = TSyntaxKind.RoutineDecl) and (Child.FindChild(TSyntaxKind.Block) <> nil) and
      (APosition.Line > Child.StartPos.Line) then
    begin
      Result := Result + [Child.Name];
    end;
    Node := Child;
  end;
end;

/// <summary>ATypeName mit &lt;Typparametern&gt;, wenn der Typ im Container AContainer der Unit generisch ist.</summary>
function WithTypeParams(const AUnit: TUnitIndex; AFound: Boolean; const AContainer, ATypeName: string): string;
var
  Symbol: TIndexSymbol;
begin
  Result := ATypeName;
  if not AFound then
  begin
    Exit;
  end;
  for Symbol in AUnit.Symbols do
  begin
    if SameText(Symbol.Name, ATypeName) and SameText(Symbol.Container, AContainer) and (Symbol.TypeParams <> '') and
      (Symbol.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
      TIndexSymbolKind.InterfaceType, TIndexSymbolKind.TypeAlias]) then
    begin
      Exit(ATypeName + '<' + StringReplace(Symbol.TypeParams, ',', ', ', [rfReplaceAll]) + '>');
    end;
  end;
end;

function InUses(ANode: TSyntaxNode; const APosition: TTextPosition): Boolean;
var
  Position: TTextPosition;
begin
  Position := APosition;
  // Search statt Rekursion (Bericht M1); in eine uses-Liste geht die Suche nicht weiter hinein.
  Result := ANode.Search(
    function(ACandidate: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if ACandidate.Kind <> TSyntaxKind.UsesClause then
      begin
        Exit;
      end;
      Result := TSyntaxSearchStep.Skip;
      if not Before(Position, ACandidate.StartPos) and Before(Position, ACandidate.EndPos) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end) <> nil;
end;

/// <summary>Bezeichner AIndex samt der Teile davor und danach, die mit Punkten anschließen.</summary>
function DottedName(const ATokens: TArray<TPascalToken>; AIndex: Integer): string;
var
  mFirst, mLast, mPart: Integer;
begin
  mFirst := AIndex;
  while (mFirst >= 2) and ATokens[mFirst - 1].IsSymbol('.') and
    (ATokens[mFirst - 2].Kind = TPascalTokenKind.Identifier) do
  begin
    Dec(mFirst, 2);
  end;
  mLast := AIndex;
  while (mLast + 2 <= High(ATokens)) and ATokens[mLast + 1].IsSymbol('.') and
    (ATokens[mLast + 2].Kind = TPascalTokenKind.Identifier) do
  begin
    Inc(mLast, 2);
  end;
  Result := '';
  for mPart := mFirst to mLast do
  begin
    Result := Result + ATokens[mPart].Text;
  end;
end;

/// <summary>Vollständiger Unit-Name (mit Punkten) aus einer uses-Liste an APosition; '' ohne.</summary>
function UsesUnitAt(ATree: TSyntaxTree; const APosition: TTextPosition): string;
var
  mTokens: TArray<TPascalToken>;
  mIndex: Integer;
begin
  Result := '';
  if (ATree.Root = nil) or not InUses(ATree.Root, APosition) then
  begin
    Exit;
  end;
  mTokens := ATree.Tokens;
  for mIndex := 0 to High(mTokens) do
  begin
    if (mTokens[mIndex].Kind = TPascalTokenKind.Identifier) and (mTokens[mIndex].StartPos.Line = APosition.Line) and
      (mTokens[mIndex].StartPos.Character <= APosition.Character) and
      (mTokens[mIndex].EndPos.Character >= APosition.Character) then
    begin
      Exit(DottedName(mTokens, mIndex));
    end;
  end;
end;

/// <summary>Ist ASymbol in der Datei AFileName mit dem Baum ATree deklariert?</summary>
function InOwnFile(const ASymbol: TResolvedSymbol; ATree: TSyntaxTree; const AFileName: string): Boolean;
begin
  Result := (ATree <> nil) and SameText(ASymbol.FileName, AFileName);
end;

/// <summary>Index der Unit von ASymbol: die eigene Datei frisch aus dem Baum, andere aus dem Index.</summary>
function UnitOf(const ASymbol: TResolvedSymbol; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName: string; out AUnit: TUnitIndex): Boolean;
begin
  if InOwnFile(ASymbol, ATree, AFileName) then
  begin
    AUnit := TIndexExtractor.Extract(ATree, AFileName);
    Exit(True);
  end;
  Result := (AIndex <> nil) and (ASymbol.FileName <> '') and AIndex.FindFile(ASymbol.FileName, AUnit);
end;

/// <summary>Umgebende Typen von ASymbol, je mit ihren Typparametern und führendem Punkt.</summary>
function ContainerPath(const ASymbol: TResolvedSymbol; const AUnit: TUnitIndex; AFound: Boolean): string;
var
  mContainer, mPart: string;
begin
  Result := '';
  mContainer := '';
  for mPart in ASymbol.Container.Split(['.']) do
  begin
    Result := Result + '.' + WithTypeParams(AUnit, AFound, mContainer, mPart);
    if mContainer <> '' then
    begin
      mContainer := mContainer + '.';
    end;
    mContainer := mContainer + mPart;
  end;
end;

/// <summary>Lokale Symbole: umgebende Routinen mit führendem Punkt, z. B. .Aussen.Innen oder .TFoo.Bar.</summary>
function RoutinePath(const ASymbol: TResolvedSymbol; ATree: TSyntaxTree): string;
var
  mRoutine: string;
begin
  Result := '';
  for mRoutine in EnclosingRoutines(ATree.Root, ASymbol.SelectionRange.StartPos) do
  begin
    Result := Result + '.' + mRoutine;
  end;
end;

/// <summary>Name von ASymbol samt Typparametern.</summary>
function NameOf(const ASymbol: TResolvedSymbol; const AUnit: TUnitIndex; AFound: Boolean): string;
begin
  Result := ASymbol.Name;
  if ASymbol.IsType then
  begin
    Result := WithTypeParams(AUnit, AFound, ASymbol.Container, Result);
  end
  else if ASymbol.TypeParams <> '' then
  begin
    Result := Result + '<' + StringReplace(ASymbol.TypeParams, ',', ', ', [rfReplaceAll]) + '>';
  end;
end;

class function TQualifiedNames.Compose(const ASymbol: TResolvedSymbol; const AIndex: ISymbolIndex;
  ATree: TSyntaxTree; const AFileName: string; AWithParameters: Boolean): string;
var
  mUnit: TUnitIndex;
  mFound: Boolean;
begin
  if ASymbol.Kind = TResolvedKind.UnitName then
  begin
    Exit(ASymbol.Name);
  end;
  if ASymbol.Builtin then
  begin
    Exit('System.' + ASymbol.Name);
  end;
  mFound := UnitOf(ASymbol, AIndex, ATree, AFileName, mUnit);
  Result := ASymbol.UnitName;
  if ASymbol.Container <> '' then
  begin
    Result := Result + ContainerPath(ASymbol, mUnit, mFound);
  end
  else if InOwnFile(ASymbol, ATree, AFileName) then
  begin
    Result := Result + RoutinePath(ASymbol, ATree);
  end;
  if Result <> '' then
  begin
    Result := Result + '.';
  end;
  Result := Result + NameOf(ASymbol, mUnit, mFound);
  if AWithParameters and (ASymbol.SymbolKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_,
    TIndexSymbolKind.Routine]) then
  begin
    Result := Result + '(' + string.Join(', ', ASymbol.ParamTypes) + ')';
  end;
end;

/// <summary>Deklaration der Datei an APosition (auch die richtige Überladung); False ohne.</summary>
function DeclarationAt(ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition;
  out ASymbol: TResolvedSymbol): Boolean;
var
  mUnit: TUnitIndex;
  mDeclared: TIndexSymbol;
begin
  ASymbol := Default(TResolvedSymbol);
  mUnit := TIndexExtractor.Extract(ATree, AFileName);
  for mDeclared in mUnit.Symbols do
  begin
    if (mDeclared.SelectionRange.StartPos.Line = APosition.Line) and
      (mDeclared.SelectionRange.StartPos.Character <= APosition.Character) and
      (mDeclared.SelectionRange.EndPos.Character >= APosition.Character) then
    begin
      ASymbol.Kind := TResolvedKind.Symbol;
      ASymbol.Name := mDeclared.Name;
      ASymbol.UnitName := mUnit.UnitName;
      ASymbol.FileName := AFileName;
      ASymbol.Range := mDeclared.Range;
      ASymbol.SelectionRange := mDeclared.SelectionRange;
      ASymbol.SymbolKind := mDeclared.Kind;
      ASymbol.Container := mDeclared.Container;
      ASymbol.TypeParams := mDeclared.TypeParams;
      ASymbol.ParamTypes := mDeclared.ParamTypes;
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TQualifiedNameRequest }

class function TQualifiedNameRequest.Create(const AFileName: string; const APosition: TTextPosition;
  AWithParameters: Boolean): TQualifiedNameRequest;
begin
  Result.FileName := AFileName;
  Result.Position := APosition;
  Result.WithParameters := AWithParameters;
end;

{ TQualifiedNames }

class function TQualifiedNames.At(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const ARequest: TQualifiedNameRequest; out AName, AError: string): Boolean;
var
  mSymbol: TResolvedSymbol;
begin
  AError := '';
  // Unit-Namen in uses stehen für sich.
  AName := UsesUnitAt(ATree, ARequest.Position);
  if AName <> '' then
  begin
    Exit(True);
  end;
  // Auf einer Deklaration der Datei genau diese, sonst die Namensauflösung.
  if not DeclarationAt(ATree, ARequest.FileName, ARequest.Position, mSymbol) then
  begin
    mSymbol := AResolver.Resolve(ATree, ARequest.FileName, ARequest.Position);
  end;
  Result := mSymbol.Found;
  if Result then
  begin
    AName := Compose(mSymbol, AIndex, ATree, ARequest.FileName, ARequest.WithParameters);
  end
  else
  begin
    AError := Format('An Zeile %d, Spalte %d steht kein bekanntes Symbol', [ARequest.Position.Line + 1,
      ARequest.Position.Character + 1]);
  end;
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
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Erwartet werden URI und Position');
  end;
  Uri := AArguments.Items[0].Value;
  WithParameters := (AArguments.Count > 2) and (AArguments.Items[2] is TJSONBool) and
    TJSONBool(AArguments.Items[2]).AsBoolean;
  if not AStore.TryGet(Uri, Document) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Dokument ist nicht geöffnet: ' + Uri);
  end;
  Shared := TSyntaxTreeCache.Get(Document);
  Resolver := TNameResolver.Create(AIndex, AEnsureUnit);
  try
    Resolver.Namespaces := ANamespaces;
    if not At(Resolver, AIndex, Shared.Tree, TQualifiedNameRequest.Create(TDocumentUris.ToPath(Uri),
      TLspPositions.ReadPosition(AArguments.Items[1]), WithParameters), Name, Error) then
    begin
      raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, Error);
    end;
  finally
    Resolver.Free;
  end;
  Result := TJSONString.Create(Name);
end;

end.
