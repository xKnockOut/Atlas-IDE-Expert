unit Atlas.Common.Rules.Builtin.StringAddress;

// Adresse der Zeichen eines Strings (#1130, Gruppe „Fehler finden“):
//   first-char-address
//                     @S[1] bzw. @S[Low(S)] mit S vom Typ string,
//                     UnicodeString, WideString, AnsiString, RawByteString oder
//                     UTF8String (sicher aufgelöst, wie bei
//                     suspicious-string-pointer-cast). Bei leerem S löst der
//                     Index mit {$R+} einen Bereichsfehler aus, ohne Prüfung
//                     ergibt sich ein Zeiger ins Leere; außerdem erzwingt der
//                     Indexzugriff eine eigene Kopie (UniqueString). PChar(S)
//                     bzw. PAnsiChar(S) zeigen auch bei leerem S auf ein #0.
//                     Steht der Ausdruck in PChar(…), PAnsiChar(…),
//                     PWideChar(…), PByte(…) oder Pointer(…), ersetzt die
//                     Korrektur die ganze Umwandlung. Korrektur nur bei
//                     const-Parametern: Bei anderen Strings kann der Zeiger
//                     zum Schreiben dienen, dann ist die eigene Kopie gewollt
//                     (die Meldung nennt dafür UniqueString).

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  FirstCharAddressRuleId = 'first-char-address';

type
  TFirstCharAddressRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterStringAddressRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Rules.Builtin.TypedExpressions,
  Atlas.Common.Rules.TypedScope;

{ TFirstCharAddressRule }

function TFirstCharAddressRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(FirstCharAddressRuleId, TRuleSeverity.Warning,
    'Adresse des ersten Zeichens über S[1]');
end;

procedure TFirstCharAddressRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScope: TTypedScope;

  /// <summary>Ist AIndex der erste Index von ABase: 1 oder Low(ABase)?</summary>
  function IsFirstIndex(AIndex, ABase: TSyntaxNode): Boolean;
  begin
    AIndex := Unwrapped(AIndex);
    if (AIndex.Kind = TSyntaxKind.Literal) and (mScope.Text(AIndex) = '1') then
      Exit(True);
    Result := (AIndex.Kind = TSyntaxKind.Call) and (AIndex.ChildCount = 2) and
      (AIndex[0].Kind = TSyntaxKind.Identifier) and SameText(AIndex[0].Name, 'Low') and
      SameText(mScope.Text(Unwrapped(AIndex[1])), mScope.Text(ABase));
  end;

  /// <summary>Ist ASymbol ein const-Parameter dieser Datei? Vor dem Namen stehen nur weitere Namen mit Komma,
  /// davor "const".</summary>
  function IsConstParameter(const ASymbol: TResolvedSymbol): Boolean;
  var
    mTokens: TArray<TPascalToken>;
    mIndex: Integer;
  begin
    Result := False;
    if not ASymbol.IsParameter or ((ASymbol.Kind <> TResolvedKind.Local) and
      not SameText(ASymbol.FileName, mScope.FileName)) then
      Exit;
    mTokens := mScope.Tokens;
    mIndex := mScope.TokenAtPosition(ASymbol.SelectionRange.StartPos) - 1;
    while mIndex >= 0 do
    begin
      if mTokens[mIndex].Kind = TPascalTokenKind.Comment then
        Dec(mIndex)
      else if (mTokens[mIndex].Text = ',') or (mTokens[mIndex].Kind = TPascalTokenKind.Identifier) and
        not SameText(mTokens[mIndex].Text, 'const') then
        Dec(mIndex)
      else
        Exit(SameText(mTokens[mIndex].Text, 'const'));
    end;
  end;

  /// <summary>Umgebende Umwandlung in einen Zeigertyp (PChar(@S[1])) oder nil.</summary>
  function PointerCast(ANode: TSyntaxNode): TSyntaxNode;
  begin
    Result := nil;
    while (ANode.Parent <> nil) and (ANode.Parent.Kind = TSyntaxKind.ParenExpr) do
      ANode := ANode.Parent;
    if (ANode.Parent <> nil) and (ANode.Parent.Kind = TSyntaxKind.Call) and (ANode.Parent.ChildCount = 2) and
      (ANode.Parent[1] = ANode) and (ANode.Parent[0].Kind = TSyntaxKind.Identifier) and
      MatchText(ANode.Parent[0].Name, ['PChar', 'PAnsiChar', 'PWideChar', 'PByte', 'Pointer']) then
      Result := ANode.Parent;
  end;

  procedure CheckAddress(ANode: TSyntaxNode);
  var
    mAccess, mBase, mCast, mReplaced: TSyntaxNode;
    mSymbol, mType: TResolvedSymbol;
    mWidth: Integer;
    mPointer, mSafe, mMessage: string;
    mFixes: TArray<TRuleFix>;
  begin
    if ANode.ChildCount <> 1 then
      Exit;
    mAccess := Unwrapped(ANode[0]);
    if (mAccess.Kind <> TSyntaxKind.IndexAccess) or (mAccess.ChildCount <> 2) then
      Exit;
    mBase := mAccess[0];
    if not IsFirstIndex(mAccess[1], mBase) then
      Exit;
    if not mScope.SureType(mBase, mSymbol, mType) or mSymbol.IsType or
      not (mSymbol.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field]) then
      Exit;
    if not mType.Builtin and not SameText(mType.UnitName, 'System') then
      Exit;
    mWidth := TSuspiciousStringPointerCastRule.StringWidth(mType.Name);
    if mWidth = 0 then
      Exit;
    mPointer := 'PChar';
    if mWidth = 1 then
      mPointer := 'PAnsiChar';
    mCast := PointerCast(ANode);
    mReplaced := ANode;
    if mCast <> nil then
    begin
      mPointer := mCast[0].Name;
      mReplaced := mCast;
    end;
    mSafe := Format('%s(%s)', [mPointer, mScope.Text(mBase)]);
    mFixes := nil;
    if IsConstParameter(mSymbol) then
    begin
      mMessage := Format('Bei leerem %s löst %s mit Bereichsprüfung einen Fehler aus. %s ist auch für leere ' +
        'Strings sicher.', [mScope.Text(mBase), mScope.Text(ANode), mSafe]);
      mFixes := [TRuleFix.Create(Format('Durch %s ersetzen', [mSafe]),
        [TTextEdit.Create(TTextRange.Create(mReplaced.StartPos, mReplaced.EndPos), mSafe)])];
    end
    else
      mMessage := Format('Bei leerem %s löst %s mit Bereichsprüfung einen Fehler aus. Zum Lesen ist %s auch ' +
        'für leere Strings sicher, zum Schreiben vorher UniqueString(%s).', [mScope.Text(mBase), mScope.Text(ANode),
        mSafe, mScope.Text(mBase)]);
    AReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), mMessage, TRuleConfidence.High, mFixes);
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    mIndex: Integer;
    mNode: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if mNode.Kind = TSyntaxKind.AddressOf then
          CheckAddress(mNode);
        for mIndex := mNode.ChildCount - 1 downto 0 do
          mPending.Push(mNode[mIndex]);
      end;
    finally
      mPending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  mScope := TTypedScope.Create(AContext);
  try
    Visit(AContext.Tree.Root);
  finally
    mScope.Free;
  end;
end;

procedure RegisterStringAddressRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TFirstCharAddressRule.Create);
end;

end.
