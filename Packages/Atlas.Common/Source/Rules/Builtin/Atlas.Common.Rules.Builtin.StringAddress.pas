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
  Atlas.Common.Rules.TypedScope,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TStringAddressText = (Title, EmptyRead, ReplaceWith, EmptyWrite);

const
  cTexts: array[TStringAddressText] of TAtlasText = (
    (De: 'Adresse des ersten Zeichens über S[1]'; En: 'Address of the first character via S[1]'),
    (De: 'Bei leerem %s löst %s mit Bereichsprüfung einen Fehler aus. %s ist auch für leere Strings sicher.';
     En: 'With an empty %s, %s raises an error under range checking. %s is safe for empty strings too.'),
    (De: 'Durch %s ersetzen'; En: 'Replace with %s'),
    (De: 'Bei leerem %s löst %s mit Bereichsprüfung einen Fehler aus. Zum Lesen ist %s auch für leere Strings ' +
      'sicher, zum Schreiben vorher UniqueString(%s).';
     En: 'With an empty %s, %s raises an error under range checking. For reading, %s is safe for empty strings too; ' +
      'for writing, call UniqueString(%s) first.'));

{$SCOPEDENUMS OFF}

{ TFirstCharAddressRule }

function TFirstCharAddressRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(FirstCharAddressRuleId, TRuleSeverity.Warning,
    cTexts[TStringAddressText.Title].Text);
end;

procedure TFirstCharAddressRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScope: TTypedScope;

  /// <summary>Ist AIndex der erste Index von ABase: 1 oder Low(ABase)?</summary>
  function IsFirstIndex(AIndex, ABase: TSyntaxNode): Boolean;
  begin
    AIndex := Unwrapped(AIndex);
    if (AIndex.Kind = TSyntaxKind.Literal) and (mScope.Text(AIndex) = '1') then
    begin
      Exit(True);
    end;
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
    begin
      Exit;
    end;
    mTokens := mScope.Tokens;
    mIndex := mScope.TokenAtPosition(ASymbol.SelectionRange.StartPos) - 1;
    while mIndex >= 0 do
    begin
      if mTokens[mIndex].Kind = TPascalTokenKind.Comment then
      begin
        Dec(mIndex);
      end
      else if (mTokens[mIndex].Text = ',') or (mTokens[mIndex].Kind = TPascalTokenKind.Identifier) and
        not SameText(mTokens[mIndex].Text, 'const') then
      begin
        Dec(mIndex);
      end
      else
      begin
        Exit(SameText(mTokens[mIndex].Text, 'const'));
      end;
    end;
  end;

  /// <summary>Umgebende Umwandlung in einen Zeigertyp (PChar(@S[1])) oder nil.</summary>
  function PointerCast(ANode: TSyntaxNode): TSyntaxNode;
  begin
    Result := nil;
    while (ANode.Parent <> nil) and (ANode.Parent.Kind = TSyntaxKind.ParenExpr) do
    begin
      ANode := ANode.Parent;
    end;
    if (ANode.Parent = nil) or (ANode.Parent.Kind <> TSyntaxKind.Call) or (ANode.Parent.ChildCount <> 2) then
    begin
      Exit;
    end;
    if (ANode.Parent[1] = ANode) and (ANode.Parent[0].Kind = TSyntaxKind.Identifier) and
      MatchText(ANode.Parent[0].Name, ['PChar', 'PAnsiChar', 'PWideChar', 'PByte', 'Pointer']) then
    begin
      Result := ANode.Parent;
    end;
  end;

  /// <summary>Ist ANode @S[1] auf einer String-Variablen oder einem String-Feld? Liefert S, das Symbol und die
  /// Zeichenbreite.</summary>
  function IsFirstCharAddress(ANode: TSyntaxNode; out ABase: TSyntaxNode; out ASymbol: TResolvedSymbol;
    out AWidth: Integer): Boolean;
  var
    mAccess: TSyntaxNode;
    mType: TResolvedSymbol;
  begin
    Result := False;
    ABase := nil;
    AWidth := 0;
    mAccess := nil;
    if ANode.ChildCount = 1 then
    begin
      mAccess := Unwrapped(ANode[0]);
    end;
    if (mAccess = nil) or (mAccess.Kind <> TSyntaxKind.IndexAccess) or (mAccess.ChildCount <> 2) or
      not IsFirstIndex(mAccess[1], mAccess[0]) then
    begin
      Exit;
    end;
    ABase := mAccess[0];
    if not mScope.SureType(ABase, ASymbol, mType) or ASymbol.IsType or
      not (ASymbol.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field]) then
    begin
      Exit;
    end;
    if mType.Builtin or SameText(mType.UnitName, 'System') then
    begin
      AWidth := TSuspiciousStringPointerCastRule.StringWidth(mType.Name);
    end;
    Result := AWidth <> 0;
  end;

  procedure CheckAddress(ANode: TSyntaxNode);
  var
    mBase, mCast, mReplaced: TSyntaxNode;
    mSymbol: TResolvedSymbol;
    mWidth: Integer;
    mPointer, mSafe, mMessage: string;
    mFixes: TArray<TRuleFix>;
  begin
    if not IsFirstCharAddress(ANode, mBase, mSymbol, mWidth) then
    begin
      Exit;
    end;
    mPointer := 'PChar';
    if mWidth = 1 then
    begin
      mPointer := 'PAnsiChar';
    end;
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
      mMessage := cTexts[TStringAddressText.EmptyRead].Fmt([mScope.Text(mBase), mScope.Text(ANode), mSafe]);
      mFixes := [TRuleFix.Create(cTexts[TStringAddressText.ReplaceWith].Fmt([mSafe]),
        [TTextEdit.Create(TTextRange.Create(mReplaced.StartPos, mReplaced.EndPos), mSafe)])];
    end
    else
    begin
      mMessage := cTexts[TStringAddressText.EmptyWrite].Fmt([mScope.Text(mBase), mScope.Text(ANode),
        mSafe, mScope.Text(mBase)]);
    end;
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
        begin
          CheckAddress(mNode);
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
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

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.StringAddress', cTexts);

end.
