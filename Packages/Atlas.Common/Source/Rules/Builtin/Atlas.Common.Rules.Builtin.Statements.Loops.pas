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
  LoopOffByOneRuleId = 'loop-off-by-one';
  CollectionModifiedInLoopRuleId = 'collection-modified-in-loop';

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
  Atlas.Common.Rules.Derived,
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.DeclaredTypes,
  Atlas.Common.Semantics.ConstantValues,
  Atlas.Common.Editing.AccessorCreation,
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
  Result := TRuleDescriptor.Create(LoopOffByOneRuleId, TRuleSeverity.Warning,
    cTexts[TStatementsLoopsText.Title].Text);
end;

class function TLoopOffByOneRule.ZeroBasedStrings(const ATokens: TArray<TPascalToken>): Boolean;
var
  Token: TPascalToken;
  Text: string;
begin
  Result := False;
  for Token in ATokens do
  begin
    if Token.Kind = TPascalTokenKind.Directive then
    begin
      Text := UpperCase(StringReplace(Token.Text, ' ', '', [rfReplaceAll]));
      if Pos('$ZEROBASEDSTRINGS', Text) = 0 then
      begin
        Continue;
      end;
      Result := (Pos('$ZEROBASEDSTRINGSON', Text) > 0) or (Pos('$ZEROBASEDSTRINGS+', Text) > 0);
    end;
  end;
end;

procedure TLoopOffByOneRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Types: TDeclaredTypes;
  CountNames: TArray<string>;
  ZeroBased: Boolean;
  Blocks: TArray<TSyntaxNode>;

  function InBlock(AOffset: Integer): Boolean;
  var
    Block: TSyntaxNode;
  begin
    for Block in Blocks do
    begin
      if (AOffset >= Block.StartOffset) and (AOffset < Block.EndOffset) then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  procedure CollectBlocks(ARoot: TSyntaxNode);
  var
    Index: Integer;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind = TSyntaxKind.Block) and (Node.Parent <> nil) and
          (Node.Parent.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.InitializationSection,
          TSyntaxKind.FinalizationSection, TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile]) then
        begin
          Blocks := Blocks + [Node];
          Continue;
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
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
      mBefore := PreviousCode(Tokens, AOpen);
      Exit((mBefore >= 0) and MatchText(Tokens[mBefore].Text, ['Items', 'Self']));
    end;
    mBefore := AOpen;
    mPrev := PreviousCode(Tokens, AOpen);
    if (mPrev > 0) and SameText(Tokens[mPrev].Text, 'Items') and Tokens[PreviousCode(Tokens, mPrev)].IsSymbol('.') then
    begin
      mBefore := PreviousCode(Tokens, mPrev);
    end;
    Result := BaseBefore(Tokens, mBefore, ABaseKey, ABaseCount);
  end;

  // Liest der Rumpf ABase[AVar]? ABaseKey '' = Items[AVar] bzw. Self[AVar].
  function BodyIndexes(AFrom, AStop: Integer; const ABaseKey: string; ABaseCount: Integer;
    const AVar: string): Boolean;
  var
    mIndex, mInner, mClose: Integer;
  begin
    for mIndex := AFrom to AStop - 1 do
    begin
      if not Tokens[mIndex].IsSymbol('[') then
      begin
        Continue;
      end;
      mInner := NextCode(Tokens, mIndex + 1);
      mClose := NextCode(Tokens, mInner + 1);
      if (mClose < AStop) and SameText(Tokens[mInner].Text, AVar) and Tokens[mClose].IsSymbol(']') and
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
    mOpen := NextCode(Tokens, AHeader.HighFirst + 1);
    Result := (Tokens[AHeader.HighFirst].Kind = TPascalTokenKind.Identifier) and
      (IndexText(Tokens[AHeader.HighFirst].Text, CountNames) >= 0) and (mOpen <= AHeader.HighLast) and
      Tokens[mOpen].IsSymbol('(');
  end;

  // Length(A) mit Klammer um die ganze Obergrenze (oder mit - 1 bei Strings).
  function CallBase(const AHeader: TLoopHeader; var ABase: TLoopBase): Boolean;
  var
    mOpen: Integer;
  begin
    mOpen := NextCode(Tokens, AHeader.HighFirst + 1);
    ABase.Close := Closing(Tokens, mOpen, AHeader.HighLast + 1);
    Result := ABase.Close > mOpen + 1;
    if Result then
    begin
      ABase.IsCall := True;
      ABase.First := NextCode(Tokens, mOpen + 1);
      ABase.Last := PreviousCode(Tokens, ABase.Close);
      // Nur "Length(S) - 1" bei Strings; sonst ist es kein einfacher Fall.
      Result := (ABase.Close = AHeader.HighLast) or (CodeKey(Tokens, ABase.Close + 1, AHeader.HighLast) = '-1');
    end;
  end;

  // X.Count bzw. Count: letzter Name aus countNames.
  function CountBase(const AHeader: TLoopHeader; var ABase: TLoopBase): Boolean;
  var
    mDot: Integer;
  begin
    Result := (Tokens[AHeader.HighLast].Kind = TPascalTokenKind.Identifier) and
      (IndexText(Tokens[AHeader.HighLast].Text, CountNames) >= 0);
    if not Result then
    begin
      Exit;
    end;
    mDot := PreviousCode(Tokens, AHeader.HighLast);
    if AHeader.HighLast = AHeader.HighFirst then
    begin
      ABase.First := AHeader.HighLast + 1;
      ABase.Last := AHeader.HighLast; // leer: Items[I]
    end
    else if (mDot > AHeader.HighFirst) and Tokens[mDot].IsSymbol('.') then
    begin
      ABase.First := AHeader.HighFirst;
      ABase.Last := PreviousCode(Tokens, mDot);
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
      ABase.Key := CodeKey(Tokens, ABase.First, ABase.Last);
      ABase.Text := Trim(SourceText(AContext.Text, Tokens, ABase.First, ABase.Last));
    end;
  end;

  function IsStringBase(const ABase: TLoopBase): Boolean;
  begin
    Result := ABase.IsCall and (ABase.First = ABase.Last) and
      (Tokens[ABase.First].Kind = TPascalTokenKind.Identifier);
    Result := Result and IsStringType(Types.DeclaredType(Tokens[ABase.First].Text, Tokens[ABase.First].StartPos));
  end;

  function StringMessage(const AHeader: TLoopHeader; const ABase: TLoopBase; const ALowKey,
    AHighText: string): string;
  var
    mWholeLength: Boolean;
  begin
    Result := '';
    mWholeLength := ZeroBased and (ABase.Close = AHeader.HighLast);
    if not ZeroBased and (ALowKey = '0') then
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
      [TRuleEdit.Create(TTextRange.Create(Tokens[AHeader.LowFirst].StartPos, Tokens[AHeader.HighLast].EndPos),
      Format('Low(%s) to High(%s)', [ABase.Text, ABase.Text]))]);
  end;

  function IndexMessage(const AHeader: TLoopHeader; const ABase: TLoopBase; const AHighText: string;
    out AFix: TRuleFix): string;
  begin
    if ABase.IsCall then
    begin
      Result := cTexts[TStatementsLoopsText.ArrayEnd].Fmt([AHighText, Tokens[AHeader.HighFirst].Text]);
      AFix := TRuleFix.Create(cTexts[TStatementsLoopsText.UseHigh].Fmt([ABase.Text]),
        [TRuleEdit.Create(TTextRange.Create(Tokens[AHeader.HighFirst].StartPos, Tokens[AHeader.HighLast].EndPos),
        Format('High(%s)', [ABase.Text]))]);
    end
    else
    begin
      Result := cTexts[TStatementsLoopsText.ListEnd].Fmt([AHighText, Tokens[AHeader.HighLast].Text]);
      AFix := TRuleFix.Create(cTexts[TStatementsLoopsText.AddMinusOne].Text,
        [TRuleEdit.Create(TTextRange.Create(Tokens[AHeader.HighLast].EndPos,
        Tokens[AHeader.HighLast].EndPos), ' - 1')]);
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
    if not ParseForHeader(Tokens, ANode, mHeader) or not FindBase(mHeader, mBase) or not BodyIndexes(
      mHeader.DoIndex + 1, mHeader.Stop, mBase.Key, CodeCount(Tokens, mBase.First, mBase.Last), ANode.Name) then
    begin
      Exit;
    end;
    mLowKey := CodeKey(Tokens, mHeader.LowFirst, mHeader.LowLast);
    mHighText := Trim(SourceText(AContext.Text, Tokens, mHeader.HighFirst, mHeader.HighLast));
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
      AReport.Add(TTextRange.Create(Tokens[mHeader.LowFirst].StartPos, Tokens[mHeader.HighLast].EndPos), mMessage,
        TRuleConfidence.High, [mFix]);
    end;
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    Index: Integer;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.ForStatement then
        begin
          Inspect(Node);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  // Folgt auf den Bezeichner AIndex [0] in einem Rumpf, ohne . oder @ davor? AZero/AClose: Token von 0 und ].
  function IsZeroIndex(AIndex: Integer; out AZero, AClose: Integer): Boolean;
  var
    mOpen, mPrev: Integer;
  begin
    AZero := -1;
    AClose := -1;
    mOpen := NextCode(Tokens, AIndex + 1);
    if (mOpen > High(Tokens)) or not Tokens[mOpen].IsSymbol('[') then
    begin
      Exit(False);
    end;
    AZero := NextCode(Tokens, mOpen + 1);
    AClose := NextCode(Tokens, AZero + 1);
    if (AClose > High(Tokens)) or not ((Tokens[AZero].Kind = TPascalTokenKind.Number) and (Tokens[AZero].Text = '0')) or
      not Tokens[AClose].IsSymbol(']') or not InBlock(Tokens[AIndex].Offset) then
    begin
      Exit(False);
    end;
    mPrev := PreviousCode(Tokens, AIndex);
    Result := (mPrev < 0) or not (Tokens[mPrev].IsSymbol('.') or Tokens[mPrev].IsSymbol('@'));
  end;

  // S[0] bei einsbasierten Strings.
  procedure FindZeroIndex;
  var
    mIndex, mZero, mClose: Integer;
    mName: string;
  begin
    for mIndex := 0 to High(Tokens) do
    begin
      if (Tokens[mIndex].Kind <> TPascalTokenKind.Identifier) or not IsZeroIndex(mIndex, mZero, mClose) then
      begin
        Continue;
      end;
      mName := Tokens[mIndex].Text;
      if IsStringType(Types.DeclaredType(mName, Tokens[mIndex].StartPos)) then
      begin
        AReport.Add(TTextRange.Create(Tokens[mIndex].StartPos, Tokens[mClose].EndPos),
          cTexts[TStatementsLoopsText.StringIndexZero].Fmt([mName]),
          TRuleConfidence.High, [TRuleFix.Create(cTexts[TStatementsLoopsText.UseLow].Fmt([mName]),
          [TRuleEdit.Create(TTextRange.Create(Tokens[mZero].StartPos, Tokens[mZero].EndPos),
          Format('Low(%s)', [mName]))])]);
      end;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  CountNames := TRuleOptions.Strings(AContext.Options, 'countNames', ['Count', 'Length']);
  ZeroBased := ZeroBasedStrings(Tokens);
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    Blocks := nil;
    CollectBlocks(AContext.Tree.Root);
    Visit(AContext.Tree.Root);
    if not ZeroBased then
    begin
      FindZeroIndex;
    end;
  finally
    Types.Free;
  end;
end;

{ TCollectionModifiedInLoopRule }

type
  /// <summary>Liste, über die eine Schleife läuft: CodeKey, Text, Zahl der Code-Token, for … in und Korrektur.</summary>
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
  Result := TRuleDescriptor.Create(CollectionModifiedInLoopRuleId, TRuleSeverity.Warning,
    cTexts[TStatementsLoopsText.ModifiedTitle].Text);
end;

procedure TCollectionModifiedInLoopRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Methods: TArray<string>;

  // Beginnt zwischen dem Rumpfanfang ABody und dem Aufruf ACall eine innere Schleife?
  function HasInnerLoop(ABody, ACall: Integer): Boolean;
  var
    mIndex: Integer;
  begin
    Result := False;
    for mIndex := ABody to ACall - 1 do
    begin
      if (Tokens[mIndex].Kind = TPascalTokenKind.Keyword) and
        MatchText(Tokens[mIndex].Text, ['for', 'while', 'repeat']) then
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
    Result := (Tokens[AIndex].Kind = TPascalTokenKind.Identifier) and MatchText(Tokens[AIndex].Text, ['Break', 'Exit']);
    if Result then
    begin
      mPrevious := PreviousCode(Tokens, AIndex);
      Result := (mPrevious >= 0) and Tokens[mPrevious].IsSymbol(';');
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
    mIndex := DepthZero(Tokens, ACall, AStop, ';', False);
    if mIndex < 0 then
    begin
      Exit;
    end;
    mDepth := 0;
    mDone := False;
    Inc(mIndex);
    while (mIndex < AStop) and not mDone do
    begin
      if Tokens[mIndex].Kind = TPascalTokenKind.Keyword then
      begin
        // Ende des Blocks mit dem Aufruf: kein Break, kein Exit.
        mDone := not StepDepth(Tokens[mIndex].Text, mDepth);
      end
      else if (mDepth = 0) and IsLeave(mIndex) then
      begin
        Result := SameText(Tokens[mIndex].Text, 'Exit') or not HasInnerLoop(ABody, ACall);
        mDone := True;
      end;
      Inc(mIndex);
    end;
  end;

  // Letztes Token der Obergrenze AFirst..ALast ohne "- 1" am Ende.
  function WithoutMinusOne(AFirst, ALast: Integer): Integer;
  begin
    Result := ALast;
    if (CodeCount(Tokens, AFirst, ALast) > 2) and (Tokens[ALast].Kind = TPascalTokenKind.Number) and
      (Tokens[ALast].Text = '1') and Tokens[PreviousCode(Tokens, ALast)].IsSymbol('-') then
    begin
      Result := PreviousCode(Tokens, PreviousCode(Tokens, ALast));
    end;
  end;

  // Argument von High(…), Length(…) bzw. Pred(…), wenn die Klammer bei ALast schließt.
  function CallArgument(AFirst, ALast: Integer; out AArgFirst, AArgLast: Integer): Boolean;
  var
    mOpen, mClose: Integer;
  begin
    mOpen := NextCode(Tokens, AFirst + 1);
    mClose := -1;
    if Tokens[mOpen].IsSymbol('(') then
    begin
      mClose := Closing(Tokens, mOpen, ALast + 1);
    end;
    Result := (mClose = ALast) and (mClose > mOpen + 1);
    AArgFirst := NextCode(Tokens, mOpen + 1);
    AArgLast := PreviousCode(Tokens, mClose);
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
    if (Tokens[AFirst].Kind = TPascalTokenKind.Identifier) and
      MatchText(Tokens[AFirst].Text, ['High', 'Length', 'Pred']) then
    begin
      Result := CallArgument(AFirst, mLast, ABaseFirst, ABaseLast);
      if Result and SameText(Tokens[AFirst].Text, 'Pred') then
      begin
        Result := BaseOfBound(ABaseFirst, ABaseLast, ABaseFirst, ABaseLast);
      end;
      Exit;
    end;
    if (Tokens[mLast].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[mLast].Text, 'Count') then
    begin
      mDot := PreviousCode(Tokens, mLast);
      if (mDot > AFirst) and Tokens[mDot].IsSymbol('.') then
      begin
        ABaseFirst := AFirst;
        ABaseLast := PreviousCode(Tokens, mDot);
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
    if (Tokens[AIndex].Kind <> TPascalTokenKind.Identifier) or (IndexText(Tokens[AIndex].Text, Methods) < 0) then
    begin
      Exit(False);
    end;
    ADot := PreviousCode(Tokens, AIndex);
    if (ADot < 0) or not Tokens[ADot].IsSymbol('.') or not BaseBefore(Tokens, ADot, ATarget.Key, ATarget.Count) then
    begin
      Exit(False);
    end;
    // Clear ohne Klammern ist auch ein Aufruf; sonst muss "(" folgen.
    mOpen := NextCode(Tokens, AIndex + 1);
    Result := SameText(Tokens[AIndex].Text, 'Clear') or ((mOpen < AStop) and Tokens[mOpen].IsSymbol('('));
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
        mMessage := CallMessage(ATarget, Tokens[mIndex].Text, mFixes);
        AReport.Add(TTextRange.Create(Tokens[PreviousCode(Tokens, mDot)].StartPos, Tokens[mIndex].EndPos), mMessage,
          TRuleConfidence.High, mFixes);
      end;
    end;
  end;

  function Target(ABaseFirst, ABaseLast: Integer; AForIn: Boolean): TLoopTarget;
  begin
    Result.Key := CodeKey(Tokens, ABaseFirst, ABaseLast);
    Result.Text := Trim(SourceText(AContext.Text, Tokens, ABaseFirst, ABaseLast));
    Result.Count := CodeCount(Tokens, ABaseFirst, ABaseLast);
    Result.ForIn := AForIn;
    Result.Fix := nil;
  end;

  procedure InspectForIn(ANode: TSyntaxNode);
  var
    mFirst, mStop, mIn, mDo, mBaseFirst, mBaseLast: Integer;
  begin
    mFirst := TokenFrom(Tokens, ANode.StartOffset);
    mStop := TokenFrom(Tokens, ANode.EndOffset);
    mIn := DepthZero(Tokens, mFirst, mStop, 'in', True);
    mDo := DepthZero(Tokens, mFirst, mStop, 'do', True);
    if (mIn < 0) or (mDo < mIn) then
    begin
      Exit;
    end;
    mBaseFirst := NextCode(Tokens, mIn + 1);
    mBaseLast := PreviousCode(Tokens, mDo);
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
    if not ParseForHeader(Tokens, ANode, mHeader) or
      not BaseOfBound(mHeader.HighFirst, mHeader.HighLast, mBaseFirst, mBaseLast) then
    begin
      Exit;
    end;
    mTarget := Target(mBaseFirst, mBaseLast, False);
    mLowText := Trim(SourceText(AContext.Text, Tokens, mHeader.LowFirst, mHeader.LowLast));
    mHighText := Trim(SourceText(AContext.Text, Tokens, mHeader.HighFirst, mHeader.HighLast));
    mTarget.Fix := [TRuleFix.Create(cTexts[TStatementsLoopsText.RewriteDownto].Text,
      [TRuleEdit.Create(TTextRange.Create(Tokens[mHeader.LowFirst].StartPos, Tokens[mHeader.HighLast].EndPos),
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
    Index: Integer;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement] then
        begin
          Inspect(Node);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Methods := TRuleOptions.Strings(AContext.Options, 'mutatingMethods', DefaultMutatingMethods);
  Visit(AContext.Tree.Root);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Statements.Loops', cTexts);

end.
