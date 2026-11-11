unit Atlas.Common.Rules.Builtin.Statements.Loops;

// Schleifen, die anders laufen als geschrieben (#909):
//   loop-off-by-one   for I := 0 to X.Count bzw. to Length(A) über nullbasierte
//                     Listen und Arrays, 0 to Length(S) und S[0] bei einsbasierten
//                     Strings (#913, S[0] wie E2157); {$ZEROBASEDSTRINGS ON} macht Strings
//                     nullbasiert. Gemeldet wird eine Schleife nur, wenn ihr
//                     Rumpf X[I] bzw. A[I] liest; die Anzahl erkennt die Option
//                     countNames (Vorgabe Count und Length).
//   collection-modified-in-loop
//                     Delete, Remove, Add … auf der Liste, über die die Schleife
//                     gerade vorwärts per Index oder mit for … in läuft (#914).
//                     Ein Break oder Exit ohne Bedingung danach im selben Block
//                     (Break nicht aus einer inneren Schleife) beendet die
//                     Schleife und bleibt still; die Methoden nennt die Option
//                     mutatingMethods.

interface

uses
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Contract;

const
  cLoopOffByOneRuleId = 'loop-off-by-one';
  cCollectionModifiedInLoopRuleId = 'collection-modified-in-loop';

type
  TLoopOffByOneRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Stehen Strings in AText nullbasiert ({$ZEROBASEDSTRINGS ON} bzw. {$ZEROBASEDSTRINGS+})?</summary>
    class function ZeroBasedStrings(const ATokens: TArray<TPascalToken>): Boolean; static;
  end;

  TCollectionModifiedInLoopRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Vorgabe der Option mutatingMethods.</summary>
    class function DefaultMutatingMethods: TArray<string>; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.DeclaredTypes,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Builtin.Statements.Tokens,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TStatementsLoopsText = (Title, StringZero, StringEnd, ZeroBased, UseLowHigh, ArrayEnd, UseHigh, ListEnd,
    AddMinusOne, StringIndexZero, UseLow, ModifiedTitle, ForIn, ForwardAdd, ForwardInsert, ForwardDelete,
    RewriteDownto);

const
  cTexts: array[TStatementsLoopsText] of TAtlasText = (
    (De: 'Schleife läuft einen Schritt zu weit'; En: 'Loop runs one step too far'),
    (De: 'Strings beginnen bei 1: der erste Durchlauf greift auf %s[0].';
     En: 'Strings start at 1: the first iteration accesses %s[0].'),
    (De: 'Obergrenze %s: der letzte Durchlauf greift hinter das String-Ende (mit {$ZEROBASEDSTRINGS ON} sind Strings ' +
      'nullbasiert).';
     En: 'Upper bound %s: the last iteration accesses beyond the end of the string (with {$ZEROBASEDSTRINGS ON} ' +
      'strings are zero-based).'),
    (De: 'Mit {$ZEROBASEDSTRINGS ON} sind Strings nullbasiert: die Schleife überspringt %s[0] und greift hinter das ' +
      'Ende.';
     En: 'With {$ZEROBASEDSTRINGS ON} strings are zero-based: the loop skips %s[0] and accesses beyond the end.'),
    (De: 'Low(%s)/High(%s) verwenden'; En: 'Use Low(%s)/High(%s)'),
    (De: 'Obergrenze %s: der letzte Durchlauf greift hinter das Array-Ende (Index %s).';
     En: 'Upper bound %s: the last iteration accesses beyond the end of the array (index %s).'),
    (De: 'High(%s) verwenden'; En: 'Use High(%s)'),
    (De: 'Obergrenze %s: der letzte Durchlauf greift hinter das Listenende (Index %s).';
     En: 'Upper bound %s: the last iteration accesses beyond the end of the list (index %s).'),
    (De: '„- 1“ ergänzen'; En: 'Add “- 1”'),
    (De: 'Strings beginnen bei 1: %s[0] liegt vor dem ersten Zeichen (wie E2157).';
     En: 'Strings start at 1: %s[0] lies before the first character (like E2157).'),
    (De: 'Low(%s) verwenden'; En: 'Use Low(%s)'),
    (De: 'Liste in der eigenen Schleife verändert'; En: 'List modified in its own loop'),
    (De: '%s.%s in for … in über %s: die RTL wirft eine Exception, weil sich die Liste ändert. Elemente sammeln und ' +
      'nach der Schleife ändern.';
     En: '%s.%s in for … in over %s: the RTL raises an exception because the list changes. Collect the elements and ' +
      'change them after the loop.'),
    (De: '%s.%s in einer Vorwärtsschleife über %s: die neuen Elemente durchläuft die Schleife nicht, die Obergrenze ' +
      'steht beim Start fest.';
     En: '%s.%s in a forward loop over %s: the loop does not visit the new elements, the upper bound is fixed at the ' +
      'start.'),
    (De: '%s.%s in einer Vorwärtsschleife über %s: die Elemente rücken nach, dasselbe Element kommt noch einmal, am ' +
      'Ende fehlen Elemente.';
     En: '%s.%s in a forward loop over %s: the elements move up, the same element comes again, elements are missing ' +
      'at the end.'),
    (De: '%s.%s in einer Vorwärtsschleife über %s: das nächste Element wird übersprungen, am Ende folgt ein ' +
      'Indexfehler.';
     En: '%s.%s in a forward loop over %s: the next element is skipped, an index error follows at the end.'),
    (De: 'Schleife rückwärts (downto) umschreiben'; En: 'Rewrite the loop backwards (downto)'));

{$SCOPEDENUMS OFF}

{ TLoopOffByOneRule }

type
  /// <summary>Token des Kopfs for V := Unten to Oben do.</summary>
  TLoopHeader = record
    Stop, DoIndex, LowFirst, LowLast, HighFirst, HighLast: Integer;
  end;

  /// <summary>Basis der Obergrenze: A in Length(A) bzw. X in X.Count; Close ist die schließende Klammer.</summary>
  TLoopBase = record
    First, Last, Close: Integer;
    IsCall: Boolean;
    Key, Text: string;
  end;

/// <summary>Kopf for V := Unten to Oben do von ANode; False bei downto und unvollständigem Kopf.</summary>
function ParseForHeader(const ATokens: TTokens; ANode: TSyntaxNode; out AHeader: TLoopHeader): Boolean;
var
  mAssign, mTo: Integer;
begin
  AHeader := Default(TLoopHeader);
  AHeader.Stop := TokenFrom(ATokens, ANode.EndOffset);
  AHeader.DoIndex := -1;
  mTo := -1;
  mAssign := DepthZero(ATokens, TokenFrom(ATokens, ANode.StartOffset), AHeader.Stop, ':=', False);
  if mAssign >= 0 then
  begin
    mTo := DepthZero(ATokens, mAssign + 1, AHeader.Stop, 'to', True);
  end;
  if mTo >= 0 then
  begin
    AHeader.DoIndex := DepthZero(ATokens, mTo + 1, AHeader.Stop, 'do', True);
  end;
  if AHeader.DoIndex < 0 then
  begin
    Exit(False);
  end;
  AHeader.LowFirst := NextCode(ATokens, mAssign + 1);
  AHeader.LowLast := PreviousCode(ATokens, mTo);
  AHeader.HighFirst := NextCode(ATokens, mTo + 1);
  AHeader.HighLast := PreviousCode(ATokens, AHeader.DoIndex);
  Result := (AHeader.LowLast >= AHeader.LowFirst) and (AHeader.HighLast >= AHeader.HighFirst);
end;

/// <summary>Zahl der Code-Token in AFirst..ALast.</summary>
function CodeCount(const ATokens: TTokens; AFirst, ALast: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  for mIndex := AFirst to ALast do
  begin
    if not IsTrivia(ATokens[mIndex]) then
    begin
      Inc(Result);
    end;
  end;
end;

function TLoopOffByOneRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cLoopOffByOneRuleId, TRuleSeverity.Warning,
    cTexts[TStatementsLoopsText.Title].Text);
end;

class function TLoopOffByOneRule.ZeroBasedStrings(const ATokens: TArray<TPascalToken>): Boolean;
var
  mToken: TPascalToken;
  mText: string;
begin
  Result := False;
  for mToken in ATokens do
  begin
    if mToken.Kind = TPascalTokenKind.Directive then
    begin
      mText := UpperCase(StringReplace(mToken.Text, ' ', '', [rfReplaceAll]));
      if Pos('$ZEROBASEDSTRINGS', mText) = 0 then
      begin
        Continue;
      end;
      Result := (Pos('$ZEROBASEDSTRINGSON', mText) > 0) or (Pos('$ZEROBASEDSTRINGS+', mText) > 0);
    end;
  end;
end;

procedure TLoopOffByOneRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TTokens;
  mTypes: TDeclaredTypes;
  mCountNames: TArray<string>;
  mZeroBased: Boolean;
  mBlocks: TArray<TSyntaxNode>;

  function InBlock(AOffset: Integer): Boolean;
  var
    mBlock: TSyntaxNode;
  begin
    for mBlock in mBlocks do
    begin
      if (AOffset >= mBlock.StartOffset) and (AOffset < mBlock.EndOffset) then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  procedure CollectBlocks(ARoot: TSyntaxNode);
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
        if (mNode.Kind = TSyntaxKind.Block) and (mNode.Parent <> nil) and
          (mNode.Parent.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.InitializationSection,
          TSyntaxKind.FinalizationSection, TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile]) then
        begin
          mBlocks := mBlocks + [mNode];
          Continue;
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

  // Steht vor dem [ an AOpen die Basis ABaseKey? ABaseKey '' = Items[AVar] bzw. Self[AVar]; Basis.Items[I] zählt
  // mit, Andere.Kunden[I] gehört nicht zu Kunden.
  function IndexesBase(AOpen: Integer; const ABaseKey: string; ABaseCount: Integer): Boolean;
  var
    mBefore, mPrev: Integer;
  begin
    if ABaseKey = '' then
    begin
      mBefore := PreviousCode(mTokens, AOpen);
      Exit((mBefore >= 0) and MatchText(mTokens[mBefore].Text, ['Items', 'Self']));
    end;
    mBefore := AOpen;
    mPrev := PreviousCode(mTokens, AOpen);
    if (mPrev > 0) and SameText(mTokens[mPrev].Text, 'Items') and mTokens[PreviousCode(mTokens, mPrev)].IsSymbol('.') then
    begin
      mBefore := PreviousCode(mTokens, mPrev);
    end;
    Result := BaseBefore(mTokens, mBefore, ABaseKey, ABaseCount);
  end;

  // Liest der Rumpf ABase[AVar]? ABaseKey '' = Items[AVar] bzw. Self[AVar].
  function BodyIndexes(AFrom, AStop: Integer; const ABaseKey: string; ABaseCount: Integer;
    const AVar: string): Boolean;
  var
    mIndex, mInner, mClose: Integer;
  begin
    for mIndex := AFrom to AStop - 1 do
    begin
      if not mTokens[mIndex].IsSymbol('[') then
      begin
        Continue;
      end;
      mInner := NextCode(mTokens, mIndex + 1);
      mClose := NextCode(mTokens, mInner + 1);
      if (mClose < AStop) and SameText(mTokens[mInner].Text, AVar) and mTokens[mClose].IsSymbol(']') and
        IndexesBase(mIndex, ABaseKey, ABaseCount) then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  // Obergrenze Length(A): Name aus countNames mit Klammer.
  function IsCountCall(const AHeader: TLoopHeader): Boolean;
  var
    mOpen: Integer;
  begin
    mOpen := NextCode(mTokens, AHeader.HighFirst + 1);
    Result := (mTokens[AHeader.HighFirst].Kind = TPascalTokenKind.Identifier) and
      (IndexText(mTokens[AHeader.HighFirst].Text, mCountNames) >= 0) and (mOpen <= AHeader.HighLast) and
      mTokens[mOpen].IsSymbol('(');
  end;

  // Length(A) mit Klammer um die ganze Obergrenze (oder mit - 1 bei Strings).
  function CallBase(const AHeader: TLoopHeader; var ABase: TLoopBase): Boolean;
  var
    mOpen: Integer;
  begin
    mOpen := NextCode(mTokens, AHeader.HighFirst + 1);
    ABase.Close := Closing(mTokens, mOpen, AHeader.HighLast + 1);
    Result := ABase.Close > mOpen + 1;
    if Result then
    begin
      ABase.IsCall := True;
      ABase.First := NextCode(mTokens, mOpen + 1);
      ABase.Last := PreviousCode(mTokens, ABase.Close);
      // Nur "Length(S) - 1" bei Strings; sonst ist es kein einfacher Fall.
      Result := (ABase.Close = AHeader.HighLast) or (CodeKey(mTokens, ABase.Close + 1, AHeader.HighLast) = '-1');
    end;
  end;

  // X.Count bzw. Count: letzter Name aus countNames.
  function CountBase(const AHeader: TLoopHeader; var ABase: TLoopBase): Boolean;
  var
    mDot: Integer;
  begin
    Result := (mTokens[AHeader.HighLast].Kind = TPascalTokenKind.Identifier) and
      (IndexText(mTokens[AHeader.HighLast].Text, mCountNames) >= 0);
    if not Result then
    begin
      Exit;
    end;
    mDot := PreviousCode(mTokens, AHeader.HighLast);
    if AHeader.HighLast = AHeader.HighFirst then
    begin
      ABase.First := AHeader.HighLast + 1;
      ABase.Last := AHeader.HighLast; // leer: Items[I]
    end
    else if (mDot > AHeader.HighFirst) and mTokens[mDot].IsSymbol('.') then
    begin
      ABase.First := AHeader.HighFirst;
      ABase.Last := PreviousCode(mTokens, mDot);
    end
    else
    begin
      Result := False;
    end;
  end;

  function FindBase(const AHeader: TLoopHeader; out ABase: TLoopBase): Boolean;
  begin
    ABase := Default(TLoopBase);
    ABase.Close := -1;
    ABase.First := -1;
    if IsCountCall(AHeader) then
    begin
      Result := CallBase(AHeader, ABase);
    end
    else
    begin
      Result := CountBase(AHeader, ABase);
    end;
    Result := Result and (ABase.First >= 0);
    if Result and (ABase.Last >= ABase.First) then
    begin
      ABase.Key := CodeKey(mTokens, ABase.First, ABase.Last);
      ABase.Text := Trim(SourceText(AContext.Text, mTokens, ABase.First, ABase.Last));
    end;
  end;

  function IsStringBase(const ABase: TLoopBase): Boolean;
  begin
    Result := ABase.IsCall and (ABase.First = ABase.Last) and
      (mTokens[ABase.First].Kind = TPascalTokenKind.Identifier);
    Result := Result and IsStringType(mTypes.DeclaredType(mTokens[ABase.First].Text, mTokens[ABase.First].StartPos));
  end;

  function StringMessage(const AHeader: TLoopHeader; const ABase: TLoopBase; const ALowKey,
    AHighText: string): string;
  var
    mWholeLength: Boolean;
  begin
    Result := '';
    mWholeLength := mZeroBased and (ABase.Close = AHeader.HighLast);
    if not mZeroBased and (ALowKey = '0') then
    begin
      Result := cTexts[TStatementsLoopsText.StringZero].Fmt([ABase.Text]);
    end
    else if mWholeLength and (ALowKey = '0') then
    begin
      Result := cTexts[TStatementsLoopsText.StringEnd].Fmt([AHighText]);
    end
    else if mWholeLength and (ALowKey = '1') then
    begin
      Result := cTexts[TStatementsLoopsText.ZeroBased].Fmt([ABase.Text]);
    end;
  end;

  function StringFix(const AHeader: TLoopHeader; const ABase: TLoopBase): TRuleFix;
  begin
    Result := TRuleFix.Create(cTexts[TStatementsLoopsText.UseLowHigh].Fmt([ABase.Text, ABase.Text]),
      [TRuleEdit.Create(TTextRange.Create(mTokens[AHeader.LowFirst].StartPos, mTokens[AHeader.HighLast].EndPos),
      Format('Low(%s) to High(%s)', [ABase.Text, ABase.Text]))]);
  end;

  function IndexMessage(const AHeader: TLoopHeader; const ABase: TLoopBase; const AHighText: string;
    out AFix: TRuleFix): string;
  begin
    if ABase.IsCall then
    begin
      Result := cTexts[TStatementsLoopsText.ArrayEnd].Fmt([AHighText, mTokens[AHeader.HighFirst].Text]);
      AFix := TRuleFix.Create(cTexts[TStatementsLoopsText.UseHigh].Fmt([ABase.Text]),
        [TRuleEdit.Create(TTextRange.Create(mTokens[AHeader.HighFirst].StartPos, mTokens[AHeader.HighLast].EndPos),
        Format('High(%s)', [ABase.Text]))]);
    end
    else
    begin
      Result := cTexts[TStatementsLoopsText.ListEnd].Fmt([AHighText, mTokens[AHeader.HighLast].Text]);
      AFix := TRuleFix.Create(cTexts[TStatementsLoopsText.AddMinusOne].Text,
        [TRuleEdit.Create(TTextRange.Create(mTokens[AHeader.HighLast].EndPos,
        mTokens[AHeader.HighLast].EndPos), ' - 1')]);
    end;
  end;

  procedure Inspect(ANode: TSyntaxNode);
  var
    mHeader: TLoopHeader;
    mBase: TLoopBase;
    mLowKey, mHighText, mMessage: string;
    mFix: TRuleFix;
  begin
    // downto prüft for-high-to-low.
    if not ParseForHeader(mTokens, ANode, mHeader) or not FindBase(mHeader, mBase) or not BodyIndexes(
      mHeader.DoIndex + 1, mHeader.Stop, mBase.Key, CodeCount(mTokens, mBase.First, mBase.Last), ANode.Name) then
    begin
      Exit;
    end;
    mLowKey := CodeKey(mTokens, mHeader.LowFirst, mHeader.LowLast);
    mHighText := Trim(SourceText(AContext.Text, mTokens, mHeader.HighFirst, mHeader.HighLast));
    mMessage := '';
    mFix := Default(TRuleFix);
    if IsStringBase(mBase) then
    begin
      mMessage := StringMessage(mHeader, mBase, mLowKey, mHighText);
      mFix := StringFix(mHeader, mBase);
    end
    else if (mLowKey = '0') and (not mBase.IsCall or (mBase.Close = mHeader.HighLast)) then
    begin
      mMessage := IndexMessage(mHeader, mBase, mHighText, mFix);
    end;
    if mMessage <> '' then
    begin
      AReport.Add(TTextRange.Create(mTokens[mHeader.LowFirst].StartPos, mTokens[mHeader.HighLast].EndPos), mMessage,
        TRuleConfidence.High, [mFix]);
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
        if mNode.Kind = TSyntaxKind.ForStatement then
        begin
          Inspect(mNode);
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

  // Folgt auf den Bezeichner AIndex [0] in einem Rumpf, ohne . oder @ davor? AZero/AClose: Token von 0 und ].
  function IsZeroIndex(AIndex: Integer; out AZero, AClose: Integer): Boolean;
  var
    mOpen, mPrev: Integer;
  begin
    AZero := -1;
    AClose := -1;
    mOpen := NextCode(mTokens, AIndex + 1);
    if (mOpen > High(mTokens)) or not mTokens[mOpen].IsSymbol('[') then
    begin
      Exit(False);
    end;
    AZero := NextCode(mTokens, mOpen + 1);
    AClose := NextCode(mTokens, AZero + 1);
    if (AClose > High(mTokens)) or not ((mTokens[AZero].Kind = TPascalTokenKind.Number) and
      (mTokens[AZero].Text = '0')) or
      not mTokens[AClose].IsSymbol(']') or not InBlock(mTokens[AIndex].Offset) then
    begin
      Exit(False);
    end;
    mPrev := PreviousCode(mTokens, AIndex);
    Result := (mPrev < 0) or not (mTokens[mPrev].IsSymbol('.') or mTokens[mPrev].IsSymbol('@'));
  end;

  // S[0] bei einsbasierten Strings.
  procedure FindZeroIndex;
  var
    mIndex, mZero, mClose: Integer;
    mName: string;
  begin
    for mIndex := 0 to High(mTokens) do
    begin
      if (mTokens[mIndex].Kind <> TPascalTokenKind.Identifier) or not IsZeroIndex(mIndex, mZero, mClose) then
      begin
        Continue;
      end;
      mName := mTokens[mIndex].Text;
      if IsStringType(mTypes.DeclaredType(mName, mTokens[mIndex].StartPos)) then
      begin
        AReport.Add(TTextRange.Create(mTokens[mIndex].StartPos, mTokens[mClose].EndPos),
          cTexts[TStatementsLoopsText.StringIndexZero].Fmt([mName]),
          TRuleConfidence.High, [TRuleFix.Create(cTexts[TStatementsLoopsText.UseLow].Fmt([mName]),
          [TRuleEdit.Create(TTextRange.Create(mTokens[mZero].StartPos, mTokens[mZero].EndPos),
          Format('Low(%s)', [mName]))])]);
      end;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mCountNames := TRuleOptions.Strings(AContext.Options, 'countNames', ['Count', 'Length']);
  mZeroBased := ZeroBasedStrings(mTokens);
  mTypes := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    mBlocks := nil;
    CollectBlocks(AContext.Tree.Root);
    Visit(AContext.Tree.Root);
    if not mZeroBased then
    begin
      FindZeroIndex;
    end;
  finally
    mTypes.Free;
  end;
end;

{ TCollectionModifiedInLoopRule }

type
  /// <summary>Liste, über die eine Schleife läuft: CodeKey, Text, Zahl der Code-Token, for … in und
  /// Korrektur.</summary>
  TLoopTarget = record
    Key, Text: string;
    Count: Integer;
    ForIn: Boolean;
    Fix: TArray<TRuleFix>;
  end;

class function TCollectionModifiedInLoopRule.DefaultMutatingMethods: TArray<string>;
begin
  Result := ['Add', 'Insert', 'Delete', 'Remove', 'Extract', 'Clear'];
end;

function TCollectionModifiedInLoopRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cCollectionModifiedInLoopRuleId, TRuleSeverity.Warning,
    cTexts[TStatementsLoopsText.ModifiedTitle].Text);
end;

procedure TCollectionModifiedInLoopRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TTokens;
  mMethods: TArray<string>;

  // Beginnt zwischen dem Rumpfanfang ABody und dem Aufruf ACall eine innere Schleife?
  function HasInnerLoop(ABody, ACall: Integer): Boolean;
  var
    mIndex: Integer;
  begin
    Result := False;
    for mIndex := ABody to ACall - 1 do
    begin
      if (mTokens[mIndex].Kind = TPascalTokenKind.Keyword) and
        MatchText(mTokens[mIndex].Text, ['for', 'while', 'repeat']) then
      begin
        Exit(True);
      end;
    end;
  end;

  // Blocktiefe nach dem Schlüsselwort AWord; False am Ende des Blocks mit dem Aufruf.
  function StepDepth(const AWord: string; var ADepth: Integer): Boolean;
  begin
    Result := True;
    if MatchText(AWord, ['begin', 'try', 'case', 'repeat', 'asm']) then
    begin
      Inc(ADepth);
    end
    else if MatchText(AWord, ['end', 'until']) then
    begin
      Result := ADepth > 0;
      Dec(ADepth);
    end;
  end;

  // Break oder Exit am Anfang einer Anweisung; "if … then Break" ist bedingt.
  function IsLeave(AIndex: Integer): Boolean;
  var
    mPrevious: Integer;
  begin
    Result := (mTokens[AIndex].Kind = TPascalTokenKind.Identifier) and MatchText(mTokens[AIndex].Text, ['Break', 'Exit']);
    if Result then
    begin
      mPrevious := PreviousCode(mTokens, AIndex);
      Result := (mPrevious >= 0) and mTokens[mPrevious].IsSymbol(';');
    end;
  end;

  // Verlässt der Block mit dem Aufruf (ab ACall) die Schleife? Ja, wenn nach der Anweisung im selben Block ohne
  // Bedingung Break oder Exit steht, auch nach weiteren Anweisungen (Merker setzen, Schlüssel austragen). Break zählt
  // nur, wenn zwischen dem Rumpfanfang ABody und dem Aufruf keine innere Schleife beginnt; sonst verlässt es nur diese.
  function LeavesLoop(ABody, ACall, AStop: Integer): Boolean;
  var
    mIndex, mDepth: Integer;
    mDone: Boolean;
  begin
    Result := False;
    mIndex := DepthZero(mTokens, ACall, AStop, ';', False);
    if mIndex < 0 then
    begin
      Exit;
    end;
    mDepth := 0;
    mDone := False;
    Inc(mIndex);
    while (mIndex < AStop) and not mDone do
    begin
      if mTokens[mIndex].Kind = TPascalTokenKind.Keyword then
      begin
        // Ende des Blocks mit dem Aufruf: kein Break, kein Exit.
        mDone := not StepDepth(mTokens[mIndex].Text, mDepth);
      end
      else if (mDepth = 0) and IsLeave(mIndex) then
      begin
        Result := SameText(mTokens[mIndex].Text, 'Exit') or not HasInnerLoop(ABody, ACall);
        mDone := True;
      end;
      Inc(mIndex);
    end;
  end;

  // Letztes Token der Obergrenze AFirst..ALast ohne "- 1" am Ende.
  function WithoutMinusOne(AFirst, ALast: Integer): Integer;
  begin
    Result := ALast;
    if (CodeCount(mTokens, AFirst, ALast) > 2) and (mTokens[ALast].Kind = TPascalTokenKind.Number) and
      (mTokens[ALast].Text = '1') and mTokens[PreviousCode(mTokens, ALast)].IsSymbol('-') then
    begin
      Result := PreviousCode(mTokens, PreviousCode(mTokens, ALast));
    end;
  end;

  // Argument von High(…), Length(…) bzw. Pred(…), wenn die Klammer bei ALast schließt.
  function CallArgument(AFirst, ALast: Integer; out AArgFirst, AArgLast: Integer): Boolean;
  var
    mOpen, mClose: Integer;
  begin
    mOpen := NextCode(mTokens, AFirst + 1);
    mClose := -1;
    if mTokens[mOpen].IsSymbol('(') then
    begin
      mClose := Closing(mTokens, mOpen, ALast + 1);
    end;
    Result := (mClose = ALast) and (mClose > mOpen + 1);
    AArgFirst := NextCode(mTokens, mOpen + 1);
    AArgLast := PreviousCode(mTokens, mClose);
  end;

  // Basis der Obergrenze: X in X.Count - 1, X.Count, High(X), Pred(X.Count), Length(X) - 1; sonst False.
  function BaseOfBound(AFirst, ALast: Integer; out ABaseFirst, ABaseLast: Integer): Boolean;
  var
    mLast, mDot: Integer;
  begin
    Result := False;
    ABaseFirst := -1;
    ABaseLast := -1;
    mLast := WithoutMinusOne(AFirst, ALast);
    if (mTokens[AFirst].Kind = TPascalTokenKind.Identifier) and
      MatchText(mTokens[AFirst].Text, ['High', 'Length', 'Pred']) then
    begin
      Result := CallArgument(AFirst, mLast, ABaseFirst, ABaseLast);
      if Result and SameText(mTokens[AFirst].Text, 'Pred') then
      begin
        Result := BaseOfBound(ABaseFirst, ABaseLast, ABaseFirst, ABaseLast);
      end;
      Exit;
    end;
    if (mTokens[mLast].Kind = TPascalTokenKind.Identifier) and SameText(mTokens[mLast].Text, 'Count') then
    begin
      mDot := PreviousCode(mTokens, mLast);
      if (mDot > AFirst) and mTokens[mDot].IsSymbol('.') then
      begin
        ABaseFirst := AFirst;
        ABaseLast := PreviousCode(mTokens, mDot);
        Result := True;
      end;
    end;
  end;

  // Ist Token AIndex ein verändernder Aufruf Basis.M( bzw. Basis.Clear? ADot: Token des Punkts.
  function IsMutatingCall(AIndex, AStop: Integer; const ATarget: TLoopTarget; out ADot: Integer): Boolean;
  var
    mOpen: Integer;
  begin
    ADot := -1;
    if (mTokens[AIndex].Kind <> TPascalTokenKind.Identifier) or (IndexText(mTokens[AIndex].Text, mMethods) < 0) then
    begin
      Exit(False);
    end;
    ADot := PreviousCode(mTokens, AIndex);
    if (ADot < 0) or not mTokens[ADot].IsSymbol('.') or not BaseBefore(mTokens, ADot, ATarget.Key, ATarget.Count) then
    begin
      Exit(False);
    end;
    // Clear ohne Klammern ist auch ein Aufruf; sonst muss "(" folgen.
    mOpen := NextCode(mTokens, AIndex + 1);
    Result := SameText(mTokens[AIndex].Text, 'Clear') or ((mOpen < AStop) and mTokens[mOpen].IsSymbol('('));
  end;

  function CallMessage(const ATarget: TLoopTarget; const AMethod: string; out AFixes: TArray<TRuleFix>): string;
  begin
    AFixes := nil;
    if ATarget.ForIn then
    begin
      Result := cTexts[TStatementsLoopsText.ForIn].Fmt([ATarget.Text, AMethod, ATarget.Text]);
    end
    else if MatchText(AMethod, ['Add']) then
    begin
      Result := cTexts[TStatementsLoopsText.ForwardAdd].Fmt([ATarget.Text, AMethod, ATarget.Text]);
    end
    else if MatchText(AMethod, ['Insert']) then
    begin
      Result := cTexts[TStatementsLoopsText.ForwardInsert].Fmt([ATarget.Text, AMethod, ATarget.Text]);
    end
    else
    begin
      Result := cTexts[TStatementsLoopsText.ForwardDelete].Fmt([ATarget.Text, AMethod, ATarget.Text]);
      AFixes := ATarget.Fix;
    end;
  end;

  // Meldet Basis.M( im Rumpf AFrom..AStop-1.
  procedure FindCalls(AFrom, AStop: Integer; const ATarget: TLoopTarget);
  var
    mIndex, mDot: Integer;
    mMessage: string;
    mFixes: TArray<TRuleFix>;
  begin
    for mIndex := AFrom to AStop - 1 do
    begin
      if IsMutatingCall(mIndex, AStop, ATarget, mDot) and not LeavesLoop(AFrom, mIndex, AStop) then
      begin
        mMessage := CallMessage(ATarget, mTokens[mIndex].Text, mFixes);
        AReport.Add(TTextRange.Create(mTokens[PreviousCode(mTokens, mDot)].StartPos, mTokens[mIndex].EndPos), mMessage,
          TRuleConfidence.High, mFixes);
      end;
    end;
  end;

  function Target(ABaseFirst, ABaseLast: Integer; AForIn: Boolean): TLoopTarget;
  begin
    Result.Key := CodeKey(mTokens, ABaseFirst, ABaseLast);
    Result.Text := Trim(SourceText(AContext.Text, mTokens, ABaseFirst, ABaseLast));
    Result.Count := CodeCount(mTokens, ABaseFirst, ABaseLast);
    Result.ForIn := AForIn;
    Result.Fix := nil;
  end;

  procedure InspectForIn(ANode: TSyntaxNode);
  var
    mFirst, mStop, mIn, mDo, mBaseFirst, mBaseLast: Integer;
  begin
    mFirst := TokenFrom(mTokens, ANode.StartOffset);
    mStop := TokenFrom(mTokens, ANode.EndOffset);
    mIn := DepthZero(mTokens, mFirst, mStop, 'in', True);
    mDo := DepthZero(mTokens, mFirst, mStop, 'do', True);
    if (mIn < 0) or (mDo < mIn) then
    begin
      Exit;
    end;
    mBaseFirst := NextCode(mTokens, mIn + 1);
    mBaseLast := PreviousCode(mTokens, mDo);
    if mBaseLast >= mBaseFirst then
    begin
      FindCalls(mDo + 1, mStop, Target(mBaseFirst, mBaseLast, True));
    end;
  end;

  procedure InspectFor(ANode: TSyntaxNode);
  var
    mHeader: TLoopHeader;
    mBaseFirst, mBaseLast: Integer;
    mTarget: TLoopTarget;
    mLowText, mHighText: string;
  begin
    // downto: rückwärts ist Löschen unbedenklich
    if not ParseForHeader(mTokens, ANode, mHeader) or
      not BaseOfBound(mHeader.HighFirst, mHeader.HighLast, mBaseFirst, mBaseLast) then
    begin
      Exit;
    end;
    mTarget := Target(mBaseFirst, mBaseLast, False);
    mLowText := Trim(SourceText(AContext.Text, mTokens, mHeader.LowFirst, mHeader.LowLast));
    mHighText := Trim(SourceText(AContext.Text, mTokens, mHeader.HighFirst, mHeader.HighLast));
    mTarget.Fix := [TRuleFix.Create(cTexts[TStatementsLoopsText.RewriteDownto].Text,
      [TRuleEdit.Create(TTextRange.Create(mTokens[mHeader.LowFirst].StartPos, mTokens[mHeader.HighLast].EndPos),
      mHighText + ' downto ' + mLowText)])];
    FindCalls(mHeader.DoIndex + 1, mHeader.Stop, mTarget);
  end;

  procedure Inspect(ANode: TSyntaxNode);
  begin
    if ANode.Kind = TSyntaxKind.ForInStatement then
    begin
      InspectForIn(ANode);
    end
    else
    begin
      InspectFor(ANode);
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
        if mNode.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement] then
        begin
          Inspect(mNode);
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
  mTokens := AContext.Tree.Tokens;
  mMethods := TRuleOptions.Strings(AContext.Options, 'mutatingMethods', DefaultMutatingMethods);
  Visit(AContext.Tree.Root);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Statements.Loops', cTexts);

end.
