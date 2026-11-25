unit Atlas.Common.Semantics.InferredTypes;

// Abgeleiteter Typ von Inline-Variablen, -Konstanten und for-in-Laufvariablen
// ohne Typangabe (#453): aus einem Literal, über die Namensauflösung (auch
// generisch, TList<TKunde>.Create), aus dem Ausdruck hinter := oder aus dem
// Elementtyp (Array, String, GetEnumerator.Current). Grundlage für Inlay Hints,
// „Typ ausschreiben“, „Variable befördern“ und Refactorings.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver;

type
  /// <summary>Abgeleiteter Typ einer Inline-Variablen ohne Typangabe (#453).</summary>
  TInferredType = record
    Name: string;
    NameStart: TTextPosition;
    /// <summary>Ende des Namens: Stelle der Marke und von ": Typ".</summary>
    NameEnd: TTextPosition;
    /// <summary>Typ wie im Quelltext, z. B. "TList&lt;TKunde&gt;".</summary>
    TypeName: string;
    /// <summary>Laufvariable in for var X in ….</summary>
    ForIn: Boolean;
    /// <summary>Unit der Typdeklaration, wenn die Namensauflösung sie kennt; '' sonst.</summary>
    TypeUnit: string;
    /// <summary>Symbol, von dessen Unit aus TypeName gilt (Funktion, Feld, Enumerator); Name '' ohne.</summary>
    Origin: TResolvedSymbol;
  end;

  TInferredTypes = record
  public
    /// <summary>Inline-Variablen, -Konstanten und for-in-Laufvariablen ohne Typangabe in ARange mit ihrem
    /// abgeleiteten Typ (#453).</summary>
    class function Find(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
      const ARange: TTextRange): TArray<TInferredType>; static;
    /// <summary>Abgeleiteter Typ der Inline-Variablen, auf deren Namen APosition steht; False ohne.</summary>
    class function At(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
      const APosition: TTextPosition; out AFound: TInferredType): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxNodes,
  Atlas.Common.Pascal.TokenCursor,
  Atlas.Common.Pascal.TypeTexts,
  Atlas.Text.Names;

type
  /// <summary>Woraus die Ableitung liest: Namensauflösung, Baum und Datei.</summary>
  TInferSource = record
    Resolver: TNameResolver;
    Tree: TSyntaxTree;
    FileName: string;
  end;

/// <summary>Typ wie im Quelltext: eingebaut mit Namen, generisch mit eingesetzten Typargumenten ohne Unit.</summary>
function TypeDisplay(AResolver: TNameResolver; const AType: TResolvedSymbol): string;
var
  mBinding: string;
  mValues: TArray<string>;
begin
  Result := AType.Name;
  if Length(AType.Bindings) = 0 then
  begin
    Exit;
  end;
  mValues := nil;
  for mBinding in AType.Bindings do
  begin
    mValues := mValues + [AResolver.Queries.UnqualifyType(Copy(mBinding, Pos('=', mBinding) + 1, MaxInt))];
  end;
  Result := Result + '<' + string.Join(', ', mValues) + '>';
end;

/// <summary>Typtext mit eingesetzten Bindungen ("T" wird zu "TKunde"), ohne Unit davor.</summary>
function BoundText(AResolver: TNameResolver; const AText: string; const ABindings: TArray<string>): string;
var
  mBinding: string;
  mUnqualified: TArray<string>;
begin
  mUnqualified := nil;
  for mBinding in ABindings do
  begin
    mUnqualified := mUnqualified + [Copy(mBinding, 1, Pos('=', mBinding)) +
      AResolver.Queries.UnqualifyType(Copy(mBinding, Pos('=', mBinding) + 1, MaxInt))];
  end;
  Result := TPascalTypeTexts.SubstituteWords(AText, mUnqualified);
end;

/// <summary>Namen der Kette A.B.C von AFirst bis ALast; False, wenn dort etwas anderes steht (z. B. ein Aufruf).
/// </summary>
function ChainNames(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer; out ANames: TArray<string>): Boolean;
var
  mIndex: Integer;
begin
  ANames := nil;
  mIndex := AFirst;
  Result := AFirst <= ALast;
  while Result and (mIndex <= ALast) do
  begin
    Result := ATokens[mIndex].Kind = TPascalTokenKind.Identifier;
    ANames := ANames + [TTextNames.WithoutAmpersand(ATokens[mIndex].Text)];
    mIndex := NextCodeAfter(ATokens, mIndex);
    if Result and (mIndex <= ALast) then
    begin
      Result := ATokens[mIndex].IsSymbol('.');
      mIndex := NextCodeAfter(ATokens, mIndex);
    end;
  end;
end;

/// <summary>Elementtyp eines Arrays oder Strings aus dem Typ der Kette; '' wenn er keiner ist.</summary>
function DirectElement(const AOwner, ATypeInfo: TResolvedSymbol; ATypeFound: Boolean): string;
var
  mOwnerType: string;
begin
  mOwnerType := AOwner.TypeName;
  if AOwner.TypeArgs <> '' then
  begin
    mOwnerType := mOwnerType + '<' + AOwner.TypeArgs + '>';
  end;
  Result := TPascalTypeTexts.ElementOf(mOwnerType);
  if (Result = '') and ATypeFound then
  begin
    Result := TPascalTypeTexts.ElementOf(ATypeInfo.TypeName);
  end;
  if (Result = '') and (TPascalTypeTexts.IsStringType(AOwner.TypeName) or
    (ATypeFound and ATypeInfo.Builtin and TPascalTypeTexts.IsStringType(ATypeInfo.Name))) then
  begin
    Result := 'Char';
  end;
end;

/// <summary>Enumerator: Current von GetEnumerator, mit eingesetzten Typparametern; '' ohne.</summary>
function EnumeratorElement(const ASource: TInferSource; const ANames: TArray<string>; AOffset: Integer;
  var AOrigin: TResolvedSymbol): string;
var
  mMember: TResolvedSymbol;
begin
  Result := '';
  for mMember in ASource.Resolver.Candidates.MemberCandidates(ASource.Tree, ASource.FileName, ANames + ['GetEnumerator'],
    AOffset) do
  begin
    if SameText(mMember.Name, 'Current') and (mMember.TypeName <> '') then
    begin
      AOrigin := mMember;
      Exit(BoundText(ASource.Resolver, mMember.TypeName, mMember.Bindings));
    end;
  end;
end;

/// <summary>Elementtyp für "for var X in Ausdruck" (#453): Kette A.B.C von AFirst bis ALast; Array-Typen, string
/// und GetEnumerator.Current.</summary>
function ForInElement(const ASource: TInferSource; AFirst, ALast: Integer; out AOrigin: TResolvedSymbol): string;
var
  mTokens: TArray<TPascalToken>;
  mNames: TArray<string>;
  mChain: TResolvedChainType;
begin
  Result := '';
  AOrigin := Default(TResolvedSymbol);
  mTokens := ASource.Tree.Tokens;
  // Nur eine Kette A.B.C ohne Aufruf.
  if not ChainNames(mTokens, AFirst, ALast, mNames) or not ASource.Resolver.ChainType(ASource.Tree, ASource.FileName,
    mNames, mTokens[ALast].Offset, mChain) then
  begin
    Exit;
  end;
  AOrigin := mChain.Owner;
  Result := DirectElement(mChain.Owner, mChain.TypeInfo, mChain.TypeFound);
  if (Result = '') and mChain.TypeFound and not mChain.TypeInfo.Builtin then
  begin
    Result := EnumeratorElement(ASource, mNames, mTokens[ALast].Offset, AOrigin);
  end;
end;

/// <summary>Trägt Name und Stelle des Tokens ANameToken in AFound ein.</summary>
procedure SetFoundName(var AFound: TInferredType; const AToken: TPascalToken);
begin
  AFound.NameStart := AToken.StartPos;
  AFound.NameEnd := AToken.EndPos;
  AFound.Name := TTextNames.WithoutAmpersand(AToken.Text);
end;

/// <summary>for var X in Ausdruck do: "var", Name, dann "in" ohne ":" dazwischen.</summary>
function InferForIn(const ASource: TInferSource; ANode: TSyntaxNode; var AFound: TInferredType): Boolean;
var
  mTokens: TArray<TPascalToken>;
  mIndex, mNameToken, mFirst, mLast: Integer;
begin
  mTokens := ASource.Tree.Tokens;
  mIndex := TokenFrom(mTokens, ANode.StartOffset);
  if (mIndex + 3 > High(mTokens)) or not mTokens[mIndex].IsKeyword('for') or
    not mTokens[NextCodeAfter(mTokens, mIndex)].IsKeyword('var') then
  begin
    Exit(False);
  end;
  mNameToken := NextCodeAfter(mTokens, NextCodeAfter(mTokens, mIndex));
  mFirst := NextCodeAfter(mTokens, mNameToken);
  if (mFirst > High(mTokens)) or not mTokens[mFirst].IsKeyword('in') or (NextCodeAfter(mTokens, mFirst) > High(mTokens))
  then
  begin
    Exit(False);
  end;
  mFirst := NextCodeAfter(mTokens, mFirst);
  mLast := mFirst;
  while (NextCodeAfter(mTokens, mLast) <= High(mTokens)) and not mTokens[NextCodeAfter(mTokens, mLast)].IsKeyword('do') and
    (mTokens[NextCodeAfter(mTokens, mLast)].Offset < ANode.EndOffset) do
  begin
    mLast := NextCodeAfter(mTokens, mLast);
  end;
  SetFoundName(AFound, mTokens[mNameToken]);
  AFound.ForIn := True;
  AFound.TypeName := ForInElement(ASource, mFirst, mLast, AFound.Origin);
  Result := AFound.TypeName <> '';
end;

/// <summary>var X := …: Name, dann ":=" ohne ":" davor; const X = … mit "=". False ohne Zuweisung oder mit
/// Typangabe.</summary>
function FindAssignment(const ATokens: TArray<TPascalToken>; ANode: TSyntaxNode;
  out ANameToken, AAssign: Integer): Boolean;
var
  mIndex: Integer;
  mTyped: Boolean;
begin
  ANameToken := -1;
  AAssign := -1;
  mTyped := False;
  mIndex := TokenFrom(ATokens, ANode.StartOffset);
  while (mIndex <= High(ATokens)) and (ATokens[mIndex].Offset < ANode.EndOffset) and (AAssign < 0) do
  begin
    if (ANameToken < 0) and (ATokens[mIndex].Kind = TPascalTokenKind.Identifier) then
    begin
      ANameToken := mIndex;
    end
    else if ATokens[mIndex].IsSymbol(':') then
    begin
      mTyped := True;
    end
    else if ATokens[mIndex].IsSymbol(':=') or ((ANode.Kind = TSyntaxKind.InlineConst) and
      ATokens[mIndex].IsSymbol('=')) then
    begin
      AAssign := mIndex;
    end;
    Inc(mIndex);
  end;
  Result := not mTyped and (ANameToken >= 0) and (AAssign >= 0);
end;

/// <summary>Typ eines einzelnen Literals (Zahl, String, Zeichen, True/False); '' sonst.</summary>
function LiteralType(const AToken: TPascalToken): string;
begin
  case AToken.Kind of
    TPascalTokenKind.Number:
      if CharInSet(AToken.Text[1], ['$', '%']) or ((Pos('.', AToken.Text) = 0) and
        (Pos('e', LowerCase(AToken.Text)) = 0)) then
      begin
        Result := 'Integer';
      end
      else
      begin
        Result := 'Extended';
      end;
    TPascalTokenKind.StringLiteral:
      if (Length(AToken.Text) = 3) or (AToken.Text = '''''''''') then
      begin
        Result := 'Char';
      end
      else
      begin
        Result := 'string';
      end;
    TPascalTokenKind.CharLiteral:
      Result := 'Char';
    TPascalTokenKind.Identifier:
      if SameText(AToken.Text, 'True') or SameText(AToken.Text, 'False') then
      begin
        Result := 'Boolean';
      end
      else
      begin
        Result := '';
      end;
  else
    // Andere Token haben keinen Literaltyp.
    Result := '';
  end;
end;

/// <summary>Typ der Variablen ANameToken über die Namensauflösung (#453): auch generisch, TList&lt;TKunde&gt;.Create.
/// </summary>
function ResolvedVariableType(const ASource: TInferSource; ANameToken, AEndOffset: Integer;
  var AFound: TInferredType): Boolean;
var
  mChain: TResolvedChainType;
begin
  Result := ASource.Resolver.ChainType(ASource.Tree, ASource.FileName,
    [TTextNames.WithoutAmpersand(ASource.Tree.Tokens[ANameToken].Text)], AEndOffset, mChain) and mChain.TypeFound and
    (mChain.TypeInfo.Name <> '');
  if not Result then
  begin
    Exit;
  end;
  AFound.TypeName := TypeDisplay(ASource.Resolver, mChain.TypeInfo);
  if not mChain.TypeInfo.Builtin then
  begin
    AFound.TypeUnit := mChain.TypeInfo.UnitName;
  end;
  AFound.Origin := mChain.TypeInfo;
end;

/// <summary>Index der schließenden Klammer zu der hinter AIndex (bis ALast); AIndex, wenn keine folgt.</summary>
function CallEnd(const ATokens: TArray<TPascalToken>; AIndex, ALast: Integer): Integer;
var
  mDepth: Integer;
begin
  Result := AIndex;
  if (Result >= ALast) or not ATokens[NextCodeAfter(ATokens, Result)].IsSymbol('(') then
  begin
    Exit;
  end;
  mDepth := 0;
  Result := NextCodeAfter(ATokens, Result);
  while Result <= ALast do
  begin
    if ATokens[Result].IsSymbol('(') then
    begin
      Inc(mDepth);
    end
    else if ATokens[Result].IsSymbol(')') then
    begin
      Dec(mDepth);
    end;
    if mDepth = 0 then
    begin
      Exit;
    end;
    Result := NextCodeAfter(ATokens, Result);
  end;
end;

/// <summary>Typ, den ein Ausdruck aus dem aufgelösten Symbol AResolved hat; '' wenn unbekannt.</summary>
function SymbolType(AResolver: TNameResolver; const AResolved: TResolvedSymbol): string;
begin
  Result := '';
  if AResolved.SymbolKind = TIndexSymbolKind.Constructor_ then
  begin
    Result := AResolved.Container;
  end
  else if AResolved.IsType then
  begin
    // Typumwandlung TFoo(X)
    Result := AResolved.Name;
  end
  else if AResolved.TypeName <> '' then
  begin
    Result := BoundText(AResolver, AResolved.TypeName, AResolved.Bindings);
  end
  else if AResolved.SymbolKind = TIndexSymbolKind.EnumMember then
  begin
    // Enum-Werte stehen im Index unter ihrem Typ.
    Result := AResolved.Container;
  end;
end;

/// <summary>Typ des Ausdrucks von AFirst bis ALast: Kette A.B.C, optional mit einem Aufruf (…) am Ende.</summary>
function ExpressionType(const ASource: TInferSource; AFirst, ALast: Integer; var AFound: TInferredType): Boolean;
var
  mTokens: TArray<TPascalToken>;
  mScan: Integer;
  mResolved: TResolvedSymbol;
begin
  mTokens := ASource.Tree.Tokens;
  Result := False;
  if mTokens[AFirst].Kind <> TPascalTokenKind.Identifier then
  begin
    Exit;
  end;
  mScan := NameChainEnd(mTokens, AFirst, ALast);
  if CallEnd(mTokens, mScan, ALast) <> ALast then
  begin
    Exit;
  end;
  mResolved := ASource.Resolver.Resolve(ASource.Tree, ASource.FileName, mTokens[mScan].StartPos);
  if mResolved.Found and (mResolved.Kind <> TResolvedKind.UnitName) then
  begin
    AFound.Origin := mResolved;
    AFound.TypeName := SymbolType(ASource.Resolver, mResolved);
    Result := AFound.TypeName <> '';
  end;
end;

/// <summary>Inline-Variable oder -Konstante ohne Typangabe: Typ aus Literal, Namensauflösung oder Ausdruck.
/// </summary>
function InferInline(const ASource: TInferSource; ANode: TSyntaxNode; var AFound: TInferredType): Boolean;
var
  mTokens: TArray<TPascalToken>;
  mNameToken, mAssign, mFirst, mLast: Integer;
begin
  mTokens := ASource.Tree.Tokens;
  if not FindAssignment(mTokens, ANode, mNameToken, mAssign) then
  begin
    Exit(False);
  end;
  mFirst := NextCodeAfter(mTokens, mAssign);
  if mFirst > High(mTokens) then
  begin
    Exit(False);
  end;
  mLast := mFirst;
  while (NextCodeAfter(mTokens, mLast) <= High(mTokens)) and (mTokens[NextCodeAfter(mTokens, mLast)].Offset < ANode.EndOffset)
    and not mTokens[NextCodeAfter(mTokens, mLast)].IsSymbol(';') do
  begin
    mLast := NextCodeAfter(mTokens, mLast);
  end;
  SetFoundName(AFound, mTokens[mNameToken]);
  if mFirst = mLast then
  begin
    AFound.TypeName := LiteralType(mTokens[mFirst]);
  end;
  Result := (AFound.TypeName <> '') or ResolvedVariableType(ASource, mNameToken, ANode.EndOffset, AFound) or
    ExpressionType(ASource, mFirst, mLast, AFound);
end;

class function TInferredTypes.Find(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const ARange: TTextRange): TArray<TInferredType>;
var
  mSource: TInferSource;
  mNodes: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
  mFound: TInferredType;
  mList: TList<TInferredType>;
  mOk: Boolean;
begin
  mSource.Resolver := AResolver;
  mSource.Tree := ATree;
  mSource.FileName := AFileName;
  mNodes := TList<TSyntaxNode>.Create;
  mList := TList<TInferredType>.Create;
  try
    mNodes.AddRange(TSyntaxNodes.OfKinds(ATree.Root, [TSyntaxKind.InlineVar, TSyntaxKind.InlineConst, TSyntaxKind.ForInStatement]));
    for mNode in mNodes do
    begin
      if not ARange.Encloses(mNode.StartPos) or (Pos(',', mNode.Name) > 0) then
      begin
        Continue;
      end;
      mFound := Default(TInferredType);
      if mNode.Kind = TSyntaxKind.ForInStatement then
      begin
        mOk := InferForIn(mSource, mNode, mFound);
      end
      else
      begin
        mOk := InferInline(mSource, mNode, mFound);
      end;
      if mOk then
      begin
        mList.Add(mFound);
      end;
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
    mNodes.Free;
  end;
end;

class function TInferredTypes.At(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition; out AFound: TInferredType): Boolean;
var
  mCandidate: TInferredType;
begin
  AFound := Default(TInferredType);
  for mCandidate in Find(AResolver, ATree, AFileName, TTextRange.Create(APosition.Line, 0,
    APosition.Line, MaxInt)) do
  begin
    if (mCandidate.NameStart.Line = APosition.Line) and (mCandidate.NameStart.Character <= APosition.Character) and
      (APosition.Character <= mCandidate.NameEnd.Character) then
    begin
      AFound := mCandidate;
      Exit(True);
    end;
  end;
  Result := False;
end;

end.
