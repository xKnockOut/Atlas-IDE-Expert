unit Atlas.Common.Rules.Builtin.Statements.Cases;

// case-Anweisungen mit fehlenden oder doppelten Werten (#909):
//   case-missing-enum-value
//                     case über einen Aufzählungstyp ohne else, dem Werte fehlen
//                     (#929); mit Option requireElse auch mit else. Den Typ des
//                     Selektors löst die Namensauflösung, die Werte kommen aus
//                     dem Index bzw. der Unit selbst; die Korrektur ergänzt die
//                     fehlenden Zweige über TCaseCompletion (#449).
//   duplicate-case-label
//                     Zwei Marken einer case-Anweisung (wie E2030) bzw. eines
//                     varianten Record-Teils (wie E2027) decken denselben Wert ab,
//                     auch über Bereiche und Konstanten (#983). Die Werte rechnet
//                     Semantics.ConstantValues aus, Namen löst TNameResolver auf;
//                     Unbekanntes vergleicht die Regel nur über den Text. Die
//                     Korrektur entfernt den späteren Wert bzw. dessen Zweig.
//                     Bedingte Zweige über Pascal.ConditionalBranches: gemeldet
//                     wird nur, wenn die frühere Marke immer mit übersetzt wird.

interface

uses
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Contract;

const
  cCaseMissingEnumValueRuleId = 'case-missing-enum-value';
  cDuplicateCaseLabelRuleId = 'duplicate-case-label';

type
  TCaseMissingEnumValueRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TDuplicateCaseLabelRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

implementation

uses
  Atlas.Common.Pascal.TokenCursor,
  Atlas.Common.Rules.Derived,
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.ConstantValues,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Editing.CaseCompletion,
  Atlas.Text.Lines,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Builtin.Statements.Tokens,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TStatementsCasesText = (Title, AddMissing, Missing, DuplicateTitle, RemoveLater, RemoveBranch, SameLine, InRange,
    SameValue, Overlaps);

const
  cTexts: array[TStatementsCasesText] of TAtlasText = (
    (De: 'case über Aufzählung ohne alle Werte'; En: 'case over enumeration without all values'),
    (De: 'Fehlende Werte ergänzen (%d)'; En: 'Add missing values (%d)'),
    (De: 'Fehlende Werte von %s: %s.'; En: 'Missing values of %s: %s.'),
    (De: 'Doppelte case-Marke'; En: 'Duplicate case label'),
    (De: 'Doppelten Wert aus dem späteren Zweig entfernen'; En: 'Remove duplicate value from the later branch'),
    (De: 'Zweig mit doppeltem Wert entfernen'; En: 'Remove branch with duplicate value'),
    (De: '%s kommt schon in Zeile %d vor (wie %s).'; En: '%s already occurs in line %d (like %s).'),
    (De: '%s liegt schon in %s aus Zeile %d (wie %s).'; En: '%s already lies in %s from line %d (like %s).'),
    (De: '%s hat denselben Wert wie %s aus Zeile %d (wie %s).';
     En: '%s has the same value as %s from line %d (like %s).'),
    (De: '%s überschneidet sich mit %s aus Zeile %d (wie %s).'; En: '%s overlaps with %s from line %d (like %s).'));

{$SCOPEDENUMS OFF}

{ TCaseMissingEnumValueRule }

function TCaseMissingEnumValueRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cCaseMissingEnumValueRuleId, TRuleSeverity.Warning,
    cTexts[TStatementsCasesText.Title].Text);
end;

/// <summary>Werte der Aufzählung AContainer (qualifizierter Name) in AOwner, in Deklarationsreihenfolge.</summary>
function EnumMembers(const AOwner: TUnitIndex; const AContainer: string): TArray<string>;
var
  mSymbol: TIndexSymbol;
begin
  Result := nil;
  for mSymbol in AOwner.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.EnumMember) and SameText(mSymbol.Container, AContainer) then
    begin
      Result := Result + [mSymbol.Name];
    end;
  end;
end;

procedure TCaseMissingEnumValueRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mResolver: TNameResolver;
  mCache: IRuleDerivedCache;
  mFileName: string;
  mRequireElse: Boolean;

  // Kette A.B.C aus Bezeichnern; False bei Aufrufen, Indizes und Ausdrücken.
  function Chain(ANode: TSyntaxNode; var ANames: TArray<string>): Boolean;
  var
    mNode: TSyntaxNode;
    mMembers: TArray<string>;
    mIndex: Integer;
  begin
    // Iterativ (tiefe Bäume sprengen den Stapel nicht): von rechts nach links an der Kette entlang; die Namen der
    // Zugriffe kommen erst nach dem Bezeichner ganz links dazu.
    mMembers := nil;
    mNode := ANode;
    while (mNode.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.ParenExpr]) and (mNode.ChildCount = 1) do
    begin
      if mNode.Kind = TSyntaxKind.MemberAccess then
      begin
        mMembers := mMembers + [mNode.Name];
      end;
      mNode := mNode[0];
    end;
    Result := mNode.Kind = TSyntaxKind.Identifier;
    if not Result then
    begin
      Exit;
    end;
    ANames := ANames + [mNode.Name];
    for mIndex := High(mMembers) downto 0 do
    begin
      ANames := ANames + [mMembers[mIndex]];
    end;
  end;

  function OwnerUnit(const AType: TResolvedSymbol; out AUnit: TUnitIndex): Boolean;
  begin
    if SameText(AType.FileName, mFileName) then
    begin
      AUnit := mResolver.ExtractedUnit(AContext.Tree, mFileName);
      Exit(True);
    end;
    Result := (AContext.Index <> nil) and AContext.Index.FindFile(AType.FileName, AUnit);
  end;

  // Werte des Aufzählungstyps in Deklarationsreihenfolge; Aliase werden verfolgt.
  function EnumValues(AType: TResolvedSymbol; out ATypeName: string): TArray<string>;
  var
    mOwner: TUnitIndex;
    mStep: Integer;
  begin
    Result := nil;
    ATypeName := '';
    for mStep := 1 to 4 do
    begin
      if not AType.Found or not AType.IsType or not OwnerUnit(AType, mOwner) then
      begin
        Exit;
      end;
      if AType.SymbolKind = TIndexSymbolKind.EnumType then
      begin
        ATypeName := AType.Name;
        Exit(EnumMembers(mOwner, AType.QualifiedName));
      end;
      if (AType.SymbolKind <> TIndexSymbolKind.TypeAlias) or (AType.TypeName = '') or
        not mResolver.ResolveTypeFrom(mOwner, AType.TypeName, AType) then
      begin
        Exit;
      end;
    end;
  end;

  // Typ des Selektors von ACase, wenn er eine Kette aus Bezeichnern ist und die case-Anweisung einen Platz für
  // neue Zweige hat.
  function SelectorType(ACase: TSyntaxNode; out ASlot: TCaseBranchSlot; out AType: TResolvedSymbol): Boolean;
  var
    mNames: TArray<string>;
    mChain: TResolvedChainType;
    mOfPos: TTextPosition;
  begin
    mNames := nil;
    AType := Default(TResolvedSymbol);
    Result := Chain(ACase[0], mNames) and TCaseCompletion.OfPosition(AContext.Tree, ACase, mOfPos) and
      TCaseCompletion.BranchSlot(AContext.Text, AContext.Tree.Tokens, mOfPos, ASlot);
    Result := Result and mResolver.ChainType(AContext.Tree, mFileName, mNames, ACase[0].EndOffset, mChain) and
      mChain.TypeFound;
    if Result then
    begin
      AType := mChain.TypeInfo;
    end;
  end;

  // {$SCOPEDENUMS ON}: die vorhandenen Marken tragen den Typnamen.
  function LabelPrefix(const ALabels: TArray<string>; const ATypeName: string): string;
  var
    mLabel: string;
  begin
    Result := '';
    for mLabel in ALabels do
    begin
      if Pos('.', StringReplace(mLabel, '..', '', [rfReplaceAll])) > 0 then
      begin
        Result := ATypeName + '.';
      end;
    end;
  end;

  function CompletionFixes(ACase: TSyntaxNode; const AValues: TArray<string>; const APrefix: string):
    TArray<TRuleFix>;
  var
    mCompletion: TCaseCompletionEdits;
  begin
    Result := nil;
    if TCaseCompletion.Complete(AContext.Text, AContext.Tree, ACase, AValues, APrefix, mCompletion) then
    begin
      Result := [TRuleFix.Create(cTexts[TStatementsCasesText.AddMissing].Fmt([mCompletion.Count]), mCompletion.Edits)];
    end;
  end;

  procedure CheckCase(ACase: TSyntaxNode);
  var
    mValues, mAbsent: TArray<string>;
    mTypeSymbol: TResolvedSymbol;
    mHasElse: Boolean;
    mSlot: TCaseBranchSlot;
    mTypeName: string;
  begin
    mHasElse := (ACase.ChildCount > 0) and (ACase.FindChild(TSyntaxKind.CaseElse) <> nil);
    if (ACase.ChildCount = 0) or (mHasElse and not mRequireElse) or not SelectorType(ACase, mSlot, mTypeSymbol) then
    begin
      Exit;
    end;
    mValues := EnumValues(mTypeSymbol, mTypeName);
    if (mValues = nil) or not TCaseCompletion.Missing(mValues, mSlot.Labels, mAbsent) or (mAbsent = nil) then
    begin
      Exit;
    end;
    AReport.Add(TTextRange.Create(ACase[0].StartPos, ACase[0].EndPos), cTexts[TStatementsCasesText.Missing].Fmt(
      [mTypeName, string.Join(', ', mAbsent)]), TRuleConfidence.High,
      CompletionFixes(ACase, mValues, LabelPrefix(mSlot.Labels, mTypeName)));
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    mIndex: Integer;
    mNode: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (tiefe Bäume sprengen den Stapel nicht).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if mNode.Kind = TSyntaxKind.CaseStatement then
        begin
          CheckCase(mNode);
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
  mRequireElse := TRuleOptions.Bool(AContext.Options, 'requireElse', False);
  mFileName := ContextFileName(AContext);
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  mCache := TRuleDerived.Open(AContext);
  mResolver := TRuleDerived.Resolver(mCache, AContext);
  mResolver.PinTree(AContext.Tree, mFileName);
  try
    Visit(AContext.Tree.Root);
  finally
    mResolver.UnpinTree;
  end;
end;

{ TDuplicateCaseLabelRule }

type
  /// <summary>Eine Marke: Token AFirst..ALast, ausgewertet als Bereich Low..High (Known) oder nur über den
  /// Text.</summary>
  TCaseLabel = record
    Item: TSyntaxNode;
    First: Integer;
    Last: Integer;
    Known: Boolean;
    Lowest: Int64;
    Highest: Int64;
    IsRange: Boolean;
    Key: string;
    /// <summary>Position unter den Marken des Zweigs und deren Zahl.</summary>
    Position: Integer;
    Count: Integer;
  end;

function TDuplicateCaseLabelRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cDuplicateCaseLabelRuleId, TRuleSeverity.Error,
    cTexts[TStatementsCasesText.DuplicateTitle].Text);
end;

procedure TDuplicateCaseLabelRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TTokens;
  mValues: TConstantValues;
  mPaths: TArray<string>;

  function LabelText(const ALabel: TCaseLabel): string;
  begin
    Result := SourceText(AContext.Text, mTokens, ALabel.First, ALabel.Last);
  end;

  // Vergleichstext: Bezeichner ohne Groß-/Kleinschreibung, Literale wie geschrieben ('a' <> 'A').
  function LabelKey(AFirst, ALast: Integer): string;
  var
    mIndex: Integer;
  begin
    Result := '';
    for mIndex := AFirst to ALast do
    begin
      if mTokens[mIndex].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword] then
      begin
        Result := Result + LowerCase(mTokens[mIndex].Text) + ' ';
      end
      else if not IsTrivia(mTokens[mIndex]) then
      begin
        Result := Result + mTokens[mIndex].Text + ' ';
      end;
    end;
  end;

  // Bereiche der Marken eines Zweigs: Token vom Anfang bis zum ":" auf Klammerebene 0, getrennt an ","; False,
  // wenn eine Klammer nicht schließt.
  function SplitLabels(AItem: TSyntaxNode; out AParts: TArray<TCaseLabel>): Boolean;
  var
    mFirst, mColon, mIndex, mStart: Integer;
    mItem: TCaseLabel;
  begin
    AParts := nil;
    mFirst := NextCode(mTokens, TokenFrom(mTokens, AItem.StartOffset));
    mColon := DepthZero(mTokens, mFirst, TokenFrom(mTokens, AItem.EndOffset), ':', False);
    Result := mColon >= 0;
    mStart := mFirst;
    mIndex := mFirst;
    while Result and (mIndex <= mColon) do
    begin
      if (mIndex = mColon) or mTokens[mIndex].IsSymbol(',') then
      begin
        mItem := Default(TCaseLabel);
        mItem.Item := AItem;
        mItem.First := NextCode(mTokens, mStart);
        mItem.Last := PreviousCode(mTokens, mIndex);
        if mItem.Last >= mItem.First then
        begin
          AParts := AParts + [mItem];
        end;
        mStart := mIndex + 1;
      end
      else if mTokens[mIndex].IsSymbol('(') or mTokens[mIndex].IsSymbol('[') then
      begin
        // Klammern überspringen, damit "," darin nicht trennt.
        mIndex := MatchingParen(mTokens, mIndex, mColon);
        Result := mIndex >= 0;
      end;
      Inc(mIndex);
    end;
  end;

  // Wert bzw. Bereich der Marke AItem auswerten.
  procedure Evaluate(var AItem: TCaseLabel);
  var
    mRange: Integer;
    mLow, mHigh: Int64;
  begin
    AItem.Key := LabelKey(AItem.First, AItem.Last);
    mRange := DepthZero(mTokens, AItem.First, AItem.Last + 1, '..', False);
    AItem.IsRange := mRange >= 0;
    if AItem.IsRange then
    begin
      AItem.Known := mValues.Evaluate(AItem.First, mRange - 1, mLow) and
        mValues.Evaluate(mRange + 1, AItem.Last, mHigh) and (mLow <= mHigh);
    end
    else
    begin
      AItem.Known := mValues.Evaluate(AItem.First, AItem.Last, mLow);
      mHigh := mLow;
    end;
    AItem.Lowest := mLow;
    AItem.Highest := mHigh;
  end;

  // Marken eines Zweigs an ALabels anhängen.
  procedure AddLabels(AItem: TSyntaxNode; var ALabels: TArray<TCaseLabel>);
  var
    mIndex: Integer;
    mParts: TArray<TCaseLabel>;
    mItem: TCaseLabel;
  begin
    if not SplitLabels(AItem, mParts) then
    begin
      Exit;
    end;
    for mIndex := 0 to High(mParts) do
    begin
      mItem := mParts[mIndex];
      mItem.Position := mIndex;
      mItem.Count := Length(mParts);
      Evaluate(mItem);
      ALabels := ALabels + [mItem];
    end;
  end;

  function Overlaps(const A, B: TCaseLabel): Boolean;
  begin
    // Nur wenn A immer mit übersetzt wird, sobald B übersetzt wird: {$IFDEF X} 1: … {$ELSE} 1: …
    // {$ENDIF} stößt nie zusammen, 1: … {$IFDEF X} 1: … {$ENDIF} dagegen unter X immer.
    if not TConditionalBranches.Implies(TConditionalBranches.PathAt(mPaths, B.First),
      TConditionalBranches.PathAt(mPaths, A.First)) then
    begin
      Exit(False);
    end;
    if A.Known and B.Known then
    begin
      Result := (A.Lowest <= B.Highest) and (B.Lowest <= A.Highest);
    end
    else
    begin
      Result := not A.Known and not B.Known and (A.Key = B.Key);
    end;
  end;

  function Covers(const AOuter, AInner: TCaseLabel): Boolean;
  begin
    if AOuter.Known and AInner.Known then
    begin
      Result := (AOuter.Lowest <= AInner.Lowest) and (AInner.Highest <= AOuter.Highest);
    end
    else
    begin
      Result := AOuter.Key = AInner.Key;
    end;
  end;

  // Löscht die Marke ALabel bzw. den ganzen Zweig, wenn sie seine einzige ist.
  function RemovalFix(const ALabels: TArray<TCaseLabel>; ALabel: Integer): TRuleFix;
  var
    mCurrent: TCaseLabel;
    mNeighbour, mBefore, mItemLast, mAfter: Integer;
    mRange: TTextRange;
  begin
    mCurrent := ALabels[ALabel];
    if mCurrent.Count > 1 then
    begin
      if mCurrent.Position < mCurrent.Count - 1 then
      begin
        mNeighbour := ALabel + 1;
        mRange := TTextRange.Create(mTokens[mCurrent.First].StartPos, mTokens[ALabels[mNeighbour].First].StartPos);
      end
      else
      begin
        mNeighbour := ALabel - 1;
        mRange := TTextRange.Create(mTokens[ALabels[mNeighbour].Last].EndPos, mTokens[mCurrent.Last].EndPos);
      end;
      Exit(TRuleFix.Create(cTexts[TStatementsCasesText.RemoveLater].Text, [TRuleEdit.Create(mRange, '')],
        True));
    end;
    // Ganzer Zweig samt Semikolon, ab dem Ende des Codes davor.
    mBefore := PreviousCode(mTokens, mCurrent.First);
    mItemLast := PreviousCode(mTokens, TokenFrom(mTokens, mCurrent.Item.EndOffset));
    if (mBefore < 0) or (mItemLast < mCurrent.First) then
    begin
      Exit(Default(TRuleFix));
    end;
    mAfter := NextCode(mTokens, mItemLast + 1);
    if (mAfter <= High(mTokens)) and mTokens[mAfter].IsSymbol(';') then
    begin
      mItemLast := mAfter;
    end;
    mRange := TTextRange.Create(mTokens[mBefore].EndPos, mTokens[mItemLast].EndPos);
    Result := TRuleFix.Create(cTexts[TStatementsCasesText.RemoveBranch].Text, [TRuleEdit.Create(mRange, '')], False);
  end;

  function OverlapMessage(const AEarlier, ALabel: TCaseLabel; const ACode: string): string;
  var
    mText, mOther: string;
    mLine: Integer;
  begin
    mText := LabelText(ALabel);
    mOther := LabelText(AEarlier);
    mLine := mTokens[AEarlier.First].StartPos.Line + 1;
    if AEarlier.Key = ALabel.Key then
    begin
      Result := cTexts[TStatementsCasesText.SameLine].Fmt([mText, mLine, ACode]);
    end
    else if Covers(AEarlier, ALabel) and AEarlier.IsRange then
    begin
      Result := cTexts[TStatementsCasesText.InRange].Fmt([mText, mOther, mLine, ACode]);
    end
    else if Covers(AEarlier, ALabel) then
    begin
      Result := cTexts[TStatementsCasesText.SameValue].Fmt([mText, mOther, mLine, ACode]);
    end
    else
    begin
      Result := cTexts[TStatementsCasesText.Overlaps].Fmt([mText, mOther, mLine, ACode]);
    end;
  end;

  procedure ReportOverlap(const ALabels: TArray<TCaseLabel>; AEarlier, AIndex: Integer; const ACode: string);
  var
    mFix: TRuleFix;
    mFixes: TArray<TRuleFix>;
  begin
    mFixes := nil;
    if Covers(ALabels[AEarlier], ALabels[AIndex]) then
    begin
      mFix := RemovalFix(ALabels, AIndex);
      if mFix.Title <> '' then
      begin
        mFixes := [mFix];
      end;
    end;
    AReport.Add(TTextRange.Create(mTokens[ALabels[AIndex].First].StartPos, mTokens[ALabels[AIndex].Last].EndPos),
      OverlapMessage(ALabels[AEarlier], ALabels[AIndex], ACode), TRuleConfidence.High, mFixes);
  end;

  // Erste frühere Marke, mit der sich die Marke AIndex überschneidet; -1 ohne.
  function FirstOverlap(const ALabels: TArray<TCaseLabel>; AIndex: Integer): Integer;
  var
    mEarlier: Integer;
  begin
    for mEarlier := 0 to AIndex - 1 do
    begin
      if Overlaps(ALabels[mEarlier], ALabels[AIndex]) then
      begin
        Exit(mEarlier);
      end;
    end;
    Result := -1;
  end;

  procedure CheckLabels(AOwner: TSyntaxNode; const ACode: string);
  var
    mLabels: TArray<TCaseLabel>;
    mIndex, mEarlier: Integer;
  begin
    mLabels := nil;
    for mIndex := 0 to AOwner.ChildCount - 1 do
    begin
      if AOwner[mIndex].Kind = TSyntaxKind.CaseItem then
      begin
        AddLabels(AOwner[mIndex], mLabels);
      end;
    end;
    for mIndex := 1 to High(mLabels) do
    begin
      mEarlier := FirstOverlap(mLabels, mIndex);
      if mEarlier >= 0 then
      begin
        ReportOverlap(mLabels, mEarlier, mIndex, ACode);
      end;
    end;
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    mIndex: Integer;
    mNode: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (tiefe Bäume sprengen den Stapel nicht).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if mNode.Kind = TSyntaxKind.CaseStatement then
        begin
          CheckLabels(mNode, 'E2030');
        end
        else if mNode.Kind = TSyntaxKind.VariantPart then
        begin
          CheckLabels(mNode, 'E2027');
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

var
  mResolver: TNameResolver;
  mCache: IRuleDerivedCache;
  mFileName: string;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mPaths := TConditionalBranches.Paths(mTokens);
  mFileName := ContextFileName(AContext);
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  mCache := TRuleDerived.Open(AContext);
  mResolver := TRuleDerived.Resolver(mCache, AContext);
  mResolver.PinTree(AContext.Tree, mFileName);
  try
    mValues := TConstantValues.Create(AContext.Tree, mFileName, AContext.Index, mResolver);
    try
      Visit(AContext.Tree.Root);
    finally
      mValues.Free;
    end;
  finally
    mResolver.UnpinTree;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Statements.Cases', cTexts);

end.
