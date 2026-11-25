unit Atlas.Common.Lsp.ParameterHeaders;

// Parameter einer Routine in ihren Köpfen (#2425). Ein Parameter steht im Kopf mit Rumpf und, wenn die Routine
// vorher deklariert ist, ein zweites Mal im Kopf ohne Rumpf: in der Klasse, im interface-Teil oder in der
// forward-Deklaration. Beide Köpfe und die Verwendungen im Rumpf sind ein Symbol. Der Namensauflöser kennt nur den
// Parameter im Kopf mit Rumpf; den zweiten Kopf findet diese Unit über das Paar der Routine (wie „Gehe zu
// Deklaration“ auf ihrem Namen) und die Stelle des Parameters in der Liste, wenn er dort gleich heißt.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver;

type
  /// <summary>Die Stellen eines Parameters in den Köpfen seiner Routine.</summary>
  TParameterHeaders = record
    /// <summary>Name des Parameters ohne &amp;.</summary>
    Name: string;
    /// <summary>Gibt es einen Kopf mit Rumpf, in dem der Parameter steht?</summary>
    HasBody: Boolean;
    /// <summary>Name des Parameters im Kopf mit Rumpf; nur mit HasBody.</summary>
    Body: TTextRange;
    /// <summary>Routine mit Rumpf vom Kopf bis zum end; nur mit HasBody. Verwendungen stehen nur darin.</summary>
    Routine: TTextRange;
    /// <summary>Name des Parameters in den Köpfen ohne Rumpf (Klasse, interface-Teil, forward).</summary>
    Declarations: TArray<TTextRange>;
    /// <summary>Steht an APosition ein Parameter einer Routine, im Kopf oder als Verwendung im Rumpf? Dann
    /// AHeaders mit seinen Köpfen in AFileName. False sonst, auch für Parameter anonymer Methoden und
    /// Prozedurtypen (sie haben nur einen Kopf).</summary>
    class function Find(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName: string; const APosition: TTextPosition; out AHeaders: TParameterHeaders): Boolean; static;
    /// <summary>Ist der Bezeichner ATokenIndex der Name eines Parameters in einem Routinenkopf? Solche Namen
    /// deklarieren nur und verwenden nichts.</summary>
    class function IsHeaderParameter(ATree: TSyntaxTree; ATokenIndex: Integer): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.TokenCursor,
  Atlas.Common.Lsp.Definition;

type
  /// <summary>Ein Parameter in einem Kopf: Kopf, Stelle in der Liste aller Namen und Token des Namens.</summary>
  THeaderParameter = record
    Header: TSyntaxNode;
    Position: Integer;
    Token: Integer;
  end;

/// <summary>Token der Namen des Parameterknotens AParameter (A, B: Integer), ohne Attribute und Modifizierer.
/// </summary>
function NameTokens(ATree: TSyntaxTree; AParameter: TSyntaxNode): TArray<Integer>;
var
  mIndex, mDepth, mCount: Integer;
  mFound: TArray<Integer>;
begin
  mFound := nil;
  mDepth := 0;
  for mIndex := ATree.FirstTokenFrom(AParameter.StartOffset) to High(ATree.Tokens) do
  begin
    if ATree.Tokens[mIndex].Offset >= AParameter.EndOffset then
    begin
      Break;
    end;
    if ATree.Tokens[mIndex].IsSymbol('[') or ATree.Tokens[mIndex].IsSymbol('(') then
    begin
      Inc(mDepth);
    end
    else if ATree.Tokens[mIndex].IsSymbol(']') or ATree.Tokens[mIndex].IsSymbol(')') then
    begin
      Dec(mDepth);
    end
    else if (mDepth = 0) and (ATree.Tokens[mIndex].IsSymbol(':') or ATree.Tokens[mIndex].IsSymbol('=')) then
    begin
      Break;
    end
    else if (mDepth = 0) and (ATree.Tokens[mIndex].Kind = TPascalTokenKind.Identifier) then
    begin
      mFound := mFound + [mIndex];
    end;
  end;
  // Davor steht höchstens out oder constref als Bezeichner; die Namen sind die letzten.
  mCount := Length(AParameter.Name.Split([',']));
  if Length(mFound) > mCount then
  begin
    mFound := Copy(mFound, Length(mFound) - mCount, mCount);
  end;
  Result := mFound;
end;

/// <summary>Token aller Parameternamen des Kopfs AHeader in ihrer Reihenfolge.</summary>
function HeaderNames(ATree: TSyntaxTree; AHeader: TSyntaxNode): TArray<Integer>;
var
  mParams: TSyntaxNode;
  mIndex: Integer;
begin
  Result := nil;
  mParams := AHeader.FindChild(TSyntaxKind.Parameters);
  if mParams = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mParams.ChildCount - 1 do
  begin
    if mParams[mIndex].Kind = TSyntaxKind.Parameter then
    begin
      Result := Result + NameTokens(ATree, mParams[mIndex]);
    end;
  end;
end;

/// <summary>Ist der Bezeichner ATokenIndex ein Parametername in einem Routinenkopf? Dann AFound.</summary>
function HeaderParameterAt(ATree: TSyntaxTree; ATokenIndex: Integer; out AFound: THeaderParameter): Boolean;
var
  mNode: TSyntaxNode;
  mNames: TArray<Integer>;
  mIndex: Integer;
begin
  AFound := Default(THeaderParameter);
  mNode := ATree.InnermostAt(ATree.Tokens[ATokenIndex].Offset);
  while (mNode <> nil) and (mNode.Kind <> TSyntaxKind.Parameter) do
  begin
    mNode := mNode.Parent;
  end;
  // Nur Parameter des Kopfs selbst, nicht die eines Prozedurtyps als Parametertyp.
  if (mNode = nil) or (mNode.Parent = nil) or (mNode.Parent.Kind <> TSyntaxKind.Parameters) or
    (mNode.Parent.Parent = nil) or (mNode.Parent.Parent.Kind <> TSyntaxKind.RoutineHeader) then
  begin
    Exit(False);
  end;
  AFound.Header := mNode.Parent.Parent;
  mNames := HeaderNames(ATree, AFound.Header);
  for mIndex := 0 to High(mNames) do
  begin
    if mNames[mIndex] = ATokenIndex then
    begin
      AFound.Position := mIndex;
      AFound.Token := ATokenIndex;
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Token des Routinennamens im Kopf AHeader (TKunde.Speichere → Speichere); -1 ohne Parameterliste.
/// </summary>
function RoutineNameToken(ATree: TSyntaxTree; AHeader: TSyntaxNode): Integer;
var
  mParams: TSyntaxNode;
  mIndex, mDepth: Integer;
begin
  Result := -1;
  mParams := AHeader.FindChild(TSyntaxKind.Parameters);
  if mParams = nil then
  begin
    Exit;
  end;
  mDepth := 0;
  for mIndex := ATree.FirstTokenFrom(AHeader.StartOffset) to High(ATree.Tokens) do
  begin
    if ATree.Tokens[mIndex].Offset >= mParams.StartOffset then
    begin
      Break;
    end;
    // Typparameter (TListe<T>.Add, Tausche<T>) überspringen.
    if ATree.Tokens[mIndex].IsSymbol('<') then
    begin
      Inc(mDepth);
    end
    else if ATree.Tokens[mIndex].IsSymbol('>') then
    begin
      Dec(mDepth);
    end
    else if (mDepth = 0) and (ATree.Tokens[mIndex].Kind = TPascalTokenKind.Identifier) then
    begin
      Result := mIndex;
    end;
  end;
end;

/// <summary>Hat der Kopf AHeader einen Rumpf? Dann ARoutine als Bereich der Routine.</summary>
function HasBody(AHeader: TSyntaxNode; out ARoutine: TTextRange): Boolean;
var
  mRoutine: TSyntaxNode;
begin
  mRoutine := AHeader.Parent;
  Result := (mRoutine <> nil) and (mRoutine.Kind = TSyntaxKind.RoutineDecl) and
    ((mRoutine.FindChild(TSyntaxKind.Block) <> nil) or (mRoutine.FindChild(TSyntaxKind.AsmBlock) <> nil));
  if Result then
  begin
    ARoutine := TTextRange.Create(mRoutine.StartPos, mRoutine.EndPos);
  end;
end;

function TokenRange(ATree: TSyntaxTree; ATokenIndex: Integer): TTextRange;
begin
  Result := TTextRange.Create(ATree.Tokens[ATokenIndex].StartPos, ATree.Tokens[ATokenIndex].EndPos);
end;

/// <summary>Der gleiche Parameter im anderen Kopf derselben Routine in derselben Datei; False ohne zweiten Kopf
/// oder wenn er dort an der Stelle anders heißt.</summary>
function Counterpart(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName: string; const AOwn: THeaderParameter; out AOther: THeaderParameter): Boolean;
var
  mName, mOther: Integer;
  mTargets: TArray<TDefinitionTarget>;
  mNames: TArray<Integer>;
  mNode: TSyntaxNode;
begin
  AOther := Default(THeaderParameter);
  mName := RoutineNameToken(ATree, AOwn.Header);
  if mName < 0 then
  begin
    Exit(False);
  end;
  // Wie „Gehe zu Definition“ auf dem Namen: vom Kopf ohne Rumpf zum Rumpf und umgekehrt, bei Überladungen die
  // Variante mit denselben Parametertypen.
  mTargets := TLspDefinition.Targets(AResolver, AIndex, ATree, AFileName, ATree.Tokens[mName].StartPos, False);
  if (Length(mTargets) = 0) or not SameText(mTargets[0].FileName, AFileName) or
    (mTargets[0].SelectionRange.StartPos = ATree.Tokens[mName].StartPos) then
  begin
    Exit(False);
  end;
  mOther := IdentifierAt(ATree.Tokens, mTargets[0].SelectionRange.StartPos);
  if mOther < 0 then
  begin
    Exit(False);
  end;
  mNode := ATree.InnermostAt(ATree.Tokens[mOther].Offset);
  while (mNode <> nil) and (mNode.Kind <> TSyntaxKind.RoutineHeader) do
  begin
    mNode := mNode.Parent;
  end;
  if (mNode = nil) or (mNode = AOwn.Header) then
  begin
    Exit(False);
  end;
  mNames := HeaderNames(ATree, mNode);
  Result := (AOwn.Position < Length(mNames)) and SameText(TPascalLexer.PlainName(ATree.Tokens[
    mNames[AOwn.Position]].Text), TPascalLexer.PlainName(ATree.Tokens[AOwn.Token].Text));
  if Result then
  begin
    AOther.Header := mNode;
    AOther.Position := AOwn.Position;
    AOther.Token := mNames[AOwn.Position];
  end;
end;

/// <summary>Den Parameter AParameter als Kopf mit oder ohne Rumpf in AHeaders eintragen.</summary>
procedure AddHeader(ATree: TSyntaxTree; const AParameter: THeaderParameter; var AHeaders: TParameterHeaders);
var
  mRoutine: TTextRange;
begin
  if not AHeaders.HasBody and HasBody(AParameter.Header, mRoutine) then
  begin
    AHeaders.HasBody := True;
    AHeaders.Body := TokenRange(ATree, AParameter.Token);
    AHeaders.Routine := mRoutine;
  end
  else
  begin
    AHeaders.Declarations := AHeaders.Declarations + [TokenRange(ATree, AParameter.Token)];
  end;
end;

/// <summary>Hat der Kopf der Routine ARoutine einen Parameter namens AName?</summary>
function HasParameterNamed(ATree: TSyntaxTree; ARoutine: TSyntaxNode; const AName: string): Boolean;
var
  mHeader: TSyntaxNode;
  mToken: Integer;
begin
  mHeader := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  if mHeader = nil then
  begin
    Exit(False);
  end;
  for mToken in HeaderNames(ATree, mHeader) do
  begin
    if SameText(TPascalLexer.PlainName(ATree.Tokens[mToken].Text), AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Hat eine Routine um den Bezeichner ATokenIndex einen Parameter mit seinem Namen? Ohne einen solchen
/// spart Find die Namensauflösung (Code Lens fragt für jede Methode).</summary>
function MayBeParameter(ATree: TSyntaxTree; ATokenIndex: Integer): Boolean;
var
  mNode: TSyntaxNode;
  mName: string;
begin
  mName := TPascalLexer.PlainName(ATree.Tokens[ATokenIndex].Text);
  mNode := ATree.InnermostAt(ATree.Tokens[ATokenIndex].Offset);
  while mNode <> nil do
  begin
    if (mNode.Kind = TSyntaxKind.RoutineDecl) and HasParameterNamed(ATree, mNode, mName) then
    begin
      Exit(True);
    end;
    mNode := mNode.Parent;
  end;
  Result := False;
end;

/// <summary>Der Parameter, den die Verwendung an APosition meint, als Name in seinem Kopf.</summary>
function UsedParameter(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition; out AFound: THeaderParameter): Boolean;
var
  mResolved: TResolvedSymbol;
  mToken: Integer;
begin
  AFound := Default(THeaderParameter);
  mToken := IdentifierAt(ATree.Tokens, APosition);
  if (mToken < 0) or not MayBeParameter(ATree, mToken) then
  begin
    Exit(False);
  end;
  mResolved := AResolver.Resolve(ATree, AFileName, APosition);
  if (mResolved.Kind <> TResolvedKind.Local) or not mResolved.IsParameter or
    not SameText(mResolved.FileName, AFileName) then
  begin
    Exit(False);
  end;
  mToken := IdentifierAt(ATree.Tokens, mResolved.SelectionRange.StartPos);
  Result := (mToken >= 0) and HeaderParameterAt(ATree, mToken, AFound);
end;

{ TParameterHeaders }

class function TParameterHeaders.Find(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName: string; const APosition: TTextPosition; out AHeaders: TParameterHeaders): Boolean;
var
  mToken: Integer;
  mOwn, mOther: THeaderParameter;
begin
  AHeaders := Default(TParameterHeaders);
  mToken := IdentifierAt(ATree.Tokens, APosition);
  if mToken < 0 then
  begin
    Exit(False);
  end;
  if not HeaderParameterAt(ATree, mToken, mOwn) and not UsedParameter(AResolver, ATree, AFileName, APosition, mOwn)
    then
  begin
    Exit(False);
  end;
  AHeaders.Name := TPascalLexer.PlainName(ATree.Tokens[mOwn.Token].Text);
  AddHeader(ATree, mOwn, AHeaders);
  if Counterpart(AResolver, AIndex, ATree, AFileName, mOwn, mOther) then
  begin
    AddHeader(ATree, mOther, AHeaders);
  end;
  Result := True;
end;

class function TParameterHeaders.IsHeaderParameter(ATree: TSyntaxTree; ATokenIndex: Integer): Boolean;
var
  mFound: THeaderParameter;
begin
  Result := (ATokenIndex >= 0) and (ATree.Tokens[ATokenIndex].Kind = TPascalTokenKind.Identifier) and
    HeaderParameterAt(ATree, ATokenIndex, mFound);
end;

end.
