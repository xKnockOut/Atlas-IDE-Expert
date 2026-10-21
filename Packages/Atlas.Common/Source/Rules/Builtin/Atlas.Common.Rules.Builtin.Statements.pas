unit Atlas.Common.Rules.Builtin.Statements;

// Regeln für Anweisungen, die anders laufen als geschrieben (#909):
//   empty-statement   Semikolon direkt nach then, do oder else (#912): die
//                     folgende Zeile läuft immer bzw. die Schleife dreht leer.
//                     Leere Blöcke begin … end nach then, do oder else ebenso,
//                     außer mit Kommentar darin (Option allowCommented).
//   loop-off-by-one   for I := 0 to X.Count bzw. to Length(A) über nullbasierte
//                     Listen und Arrays, 0 to Length(S) und S[0] bei einsbasierten
//                     Strings (#913); {$ZEROBASEDSTRINGS ON} macht Strings
//                     nullbasiert. Gemeldet wird eine Schleife nur, wenn ihr
//                     Rumpf X[I] bzw. A[I] liest; die Anzahl erkennt die Option
//                     countNames (Vorgabe Count und Length).
//   collection-modified-in-loop
//                     Delete, Remove, Add … auf der Liste, über die die Schleife
//                     gerade vorwärts per Index oder mit for … in läuft (#914).
//                     Ein Break oder Exit direkt nach dem Aufruf beendet die
//                     Schleife und bleibt still; die Methoden nennt die Option
//                     mutatingMethods.
// Grundlage ist der Syntaxbaum: if, while, for, for-in und with ohne Rumpf
// bzw. mit leerem Block; das Schlüsselwort davor sucht die Regel in den Token.

interface

uses
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  EmptyStatementRuleId = 'empty-statement';
  LoopOffByOneRuleId = 'loop-off-by-one';
  CollectionModifiedInLoopRuleId = 'collection-modified-in-loop';

type
  TEmptyStatementRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

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

procedure RegisterStatementRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.DeclaredTypes,
  Atlas.Common.Rules.Options;

type
  TTokens = TArray<TPascalToken>;
  TSyntaxKinds = set of TSyntaxKind;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

function NextCode(const ATokens: TTokens; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= High(ATokens)) and IsTrivia(ATokens[Result]) do
    Inc(Result);
end;

/// <summary>Erstes Token ab AOffset (Index), High + 1 ohne.</summary>
function TokenFrom(const ATokens: TTokens; AOffset: Integer): Integer;
var
  Low, High, Middle: Integer;
begin
  Low := 0;
  High := Length(ATokens);
  while Low < High do
  begin
    Middle := (Low + High) div 2;
    if ATokens[Middle].Offset < AOffset then
      Low := Middle + 1
    else
      High := Middle;
  end;
  Result := Low;
end;

function StatementKinds: TSyntaxKinds;
begin
  Result := [TSyntaxKind.Block, TSyntaxKind.AsmBlock, TSyntaxKind.AssignStatement, TSyntaxKind.CallStatement,
    TSyntaxKind.IfStatement, TSyntaxKind.CaseStatement, TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement,
    TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement, TSyntaxKind.WithStatement, TSyntaxKind.TryStatement,
    TSyntaxKind.RaiseStatement, TSyntaxKind.GotoStatement, TSyntaxKind.LabeledStatement, TSyntaxKind.InlineVar,
    TSyntaxKind.InlineConst, TSyntaxKind.Error];
end;

/// <summary>Erste Anweisung unter ANode, die nach AOffset beginnt; nil ohne.</summary>
function StatementAfter(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode;
var
  Index: Integer;
begin
  for Index := 0 to ANode.ChildCount - 1 do
    if (ANode[Index].Kind in StatementKinds) and (ANode[Index].StartOffset >= AOffset) then
      Exit(ANode[Index]);
  Result := nil;
end;

/// <summary>Quelltext der Token AFirst..ALast wie geschrieben.</summary>
function SourceText(const AText: string; const ATokens: TTokens; AFirst, ALast: Integer): string;
begin
  Result := Copy(AText, ATokens[AFirst].Offset + 1,
    ATokens[ALast].Offset + Length(ATokens[ALast].Text) - ATokens[AFirst].Offset);
end;

/// <summary>Code-Token AFirst..ALast ohne Leerraum und Kommentare, kleingeschrieben (zum Vergleichen).</summary>
function CodeKey(const ATokens: TTokens; AFirst, ALast: Integer): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := AFirst to ALast do
    if not IsTrivia(ATokens[Index]) then
      Result := Result + LowerCase(ATokens[Index].Text);
end;

/// <summary>Letztes Code-Token vor AIndex (AIndex selbst ausgeschlossen).</summary>
function PreviousCode(const ATokens: TTokens; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(ATokens[Result]) do
    Dec(Result);
end;

/// <summary>Index der schließenden Klammer zu AOpen, -1 ohne.</summary>
function Closing(const ATokens: TTokens; AOpen, AStop: Integer): Integer;
var
  Depth: Integer;
begin
  Depth := 0;
  for Result := AOpen to AStop - 1 do
    if ATokens[Result].IsSymbol('(') or ATokens[Result].IsSymbol('[') then
      Inc(Depth)
    else if ATokens[Result].IsSymbol(')') or ATokens[Result].IsSymbol(']') then
    begin
      Dec(Depth);
      if Depth = 0 then
        Exit;
    end;
  Result := -1;
end;

/// <summary>Erstes Token AText (Schlüsselwort bzw. Symbol) in AFrom..AStop-1 auf Klammerebene 0; -1 ohne.</summary>
function DepthZero(const ATokens: TTokens; AFrom, AStop: Integer; const AText: string; AKeyword: Boolean): Integer;
var
  Index, Depth: Integer;
begin
  Depth := 0;
  for Index := AFrom to AStop - 1 do
    if ATokens[Index].IsSymbol('(') or ATokens[Index].IsSymbol('[') then
      Inc(Depth)
    else if ATokens[Index].IsSymbol(')') or ATokens[Index].IsSymbol(']') then
      Dec(Depth)
    else if (Depth = 0) and ((AKeyword and ATokens[Index].IsKeyword(AText)) or
      (not AKeyword and ATokens[Index].IsSymbol(AText))) then
      Exit(Index);
  Result := -1;
end;

/// <summary>Bilden die ABaseCount Code-Token vor AIndex die Basis ABaseKey (CodeKey), ohne Punkt davor?</summary>
function BaseBefore(const ATokens: TTokens; AIndex: Integer; const ABaseKey: string; ABaseCount: Integer): Boolean;
var
  Before, Count, Prev: Integer;
  Key: string;
begin
  Key := '';
  Before := AIndex;
  Count := 0;
  while Count < ABaseCount do
  begin
    Before := PreviousCode(ATokens, Before);
    if Before < 0 then
      Exit(False);
    Key := LowerCase(ATokens[Before].Text) + Key;
    Inc(Count);
  end;
  Prev := PreviousCode(ATokens, Before);
  Result := (Key = ABaseKey) and ((Prev < 0) or not ATokens[Prev].IsSymbol('.'));
end;

function IsStringType(const AType: string): Boolean;
begin
  Result := MatchText(AType, ['string', 'UnicodeString', 'AnsiString', 'WideString', 'RawByteString',
    'UTF8String']);
end;

{ TEmptyStatementRule }

function TEmptyStatementRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(EmptyStatementRuleId, TRuleSeverity.Warning,
    'Leere Anweisung nach then, do oder else');
end;

procedure TEmptyStatementRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  AllowCommented: Boolean;
  Report: IRuleReport;

  // AKeyword: Index von then/do/else; ABody: Anweisung danach oder nil.
  procedure Inspect(AKeyword: Integer; ABody: TSyntaxNode; AIsLoop: Boolean);
  var
    Next, After, Index: Integer;
    Word, Message: string;
    HasComment: Boolean;
  begin
    if AKeyword < 0 then
      Exit;
    Word := LowerCase(Tokens[AKeyword].Text);
    Next := NextCode(Tokens, AKeyword + 1);
    if Next > High(Tokens) then
      Exit;
    if Tokens[Next].IsSymbol(';') and ((ABody = nil) or (ABody.StartOffset > Tokens[Next].Offset)) then
    begin
      After := NextCode(Tokens, Next + 1);
      // Am Blockende ändert das Semikolon nichts am Ablauf (z. B. while not Fertig do; als Warteschleife).
      if (After > High(Tokens)) or (Tokens[After].Kind = TPascalTokenKind.Keyword) and
        MatchText(Tokens[After].Text, ['end', 'until', 'except', 'finally', 'else']) then
        Exit;
      if AIsLoop then
        Message := Format('Leere Anweisung nach %s: die Schleife dreht leer.', [Word])
      else
        Message := Format('Leere Anweisung nach %s: die nächste Zeile läuft immer.', [Word]);
      Report.Add(TTextRange.Create(Tokens[AKeyword].StartPos, Tokens[Next].EndPos), Message, TRuleConfidence.High,
        [TRuleFix.Create('Semikolon entfernen', [TRuleEdit.Create(TTextRange.Create(Tokens[Next].StartPos,
        Tokens[Next].EndPos), '')])]);
      Exit;
    end;
    // begin end ohne Anweisung, mit Kommentar darin nur bei allowCommented = false.
    if (ABody <> nil) and (ABody.Kind = TSyntaxKind.Block) and (ABody.ChildCount = 0) and
      (Tokens[Next].IsKeyword('begin')) and (Tokens[Next].Offset = ABody.StartOffset) then
    begin
      HasComment := False;
      Index := Next + 1;
      while (Index <= High(Tokens)) and (Tokens[Index].Offset < ABody.EndOffset) do
      begin
        if Tokens[Index].Kind = TPascalTokenKind.Comment then
          HasComment := True;
        Inc(Index);
      end;
      if HasComment and AllowCommented then
        Exit;
      Report.Add(TTextRange.Create(Tokens[AKeyword].StartPos, Tokens[Index - 1].EndPos),
        Format('Leerer Block nach %s: hier passiert nichts.', [Word]), TRuleConfidence.High);
    end;
  end;

  // Schlüsselwort AWord dieses Knotens: auf Klammerebene 0 und nicht in einer untergeordneten Anweisung.
  function OwnKeyword(ANode: TSyntaxNode; AFrom, AStop: Integer; const AWord: string): Integer;
  var
    Index, Child, Depth: Integer;
    Inside: Boolean;
  begin
    Depth := 0;
    for Index := AFrom to AStop - 1 do
    begin
      if Tokens[Index].IsSymbol('(') or Tokens[Index].IsSymbol('[') then
        Inc(Depth)
      else if Tokens[Index].IsSymbol(')') or Tokens[Index].IsSymbol(']') then
        Dec(Depth)
      else if (Depth = 0) and Tokens[Index].IsKeyword(AWord) then
      begin
        Inside := False;
        for Child := 0 to ANode.ChildCount - 1 do
          if (ANode[Child].Kind in StatementKinds) and (Tokens[Index].Offset >= ANode[Child].StartOffset) and
            (Tokens[Index].Offset < ANode[Child].EndOffset) then
            Inside := True;
        if not Inside then
          Exit(Index);
      end;
    end;
    Result := -1;
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Index, Stop, ThenIndex, ElseIndex, DoIndex: Integer;
    Body: TSyntaxNode;
  begin
    Stop := TokenFrom(Tokens, ANode.EndOffset);
    case ANode.Kind of
      TSyntaxKind.IfStatement:
        if ANode.ChildCount > 0 then
        begin
          ThenIndex := OwnKeyword(ANode, TokenFrom(Tokens, ANode[0].EndOffset), Stop, 'then');
          if ThenIndex >= 0 then
          begin
            ElseIndex := OwnKeyword(ANode, ThenIndex + 1, Stop, 'else');
            Body := StatementAfter(ANode, Tokens[ThenIndex].Offset);
            if (Body <> nil) and (ElseIndex >= 0) and (Body.StartOffset > Tokens[ElseIndex].Offset) then
              Body := nil;
            Inspect(ThenIndex, Body, False);
            if ElseIndex >= 0 then
              Inspect(ElseIndex, StatementAfter(ANode, Tokens[ElseIndex].Offset), False);
          end;
        end;
      TSyntaxKind.WhileStatement, TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WithStatement:
        begin
          DoIndex := OwnKeyword(ANode, TokenFrom(Tokens, ANode.StartOffset), Stop, 'do');
          if DoIndex >= 0 then
            Inspect(DoIndex, StatementAfter(ANode, Tokens[DoIndex].Offset), ANode.Kind <> TSyntaxKind.WithStatement);
        end;
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index]);
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Tokens := AContext.Tree.Tokens;
  AllowCommented := TRuleOptions.Bool(AContext.Options, 'allowCommented', True);
  Report := AReport;
  Visit(AContext.Tree.Root);
end;

{ TLoopOffByOneRule }

function TLoopOffByOneRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(LoopOffByOneRuleId, TRuleSeverity.Warning,
    'Schleife läuft einen Schritt zu weit');
end;

class function TLoopOffByOneRule.ZeroBasedStrings(const ATokens: TArray<TPascalToken>): Boolean;
var
  Token: TPascalToken;
  Text: string;
begin
  Result := False;
  for Token in ATokens do
    if Token.Kind = TPascalTokenKind.Directive then
    begin
      Text := UpperCase(StringReplace(Token.Text, ' ', '', [rfReplaceAll]));
      if Pos('$ZEROBASEDSTRINGS', Text) = 0 then
        Continue;
      Result := (Pos('$ZEROBASEDSTRINGSON', Text) > 0) or (Pos('$ZEROBASEDSTRINGS+', Text) > 0);
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
      if (AOffset >= Block.StartOffset) and (AOffset < Block.EndOffset) then
        Exit(True);
    Result := False;
  end;

  procedure CollectBlocks(ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    if (ANode.Kind = TSyntaxKind.Block) and (ANode.Parent <> nil) and
      (ANode.Parent.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.InitializationSection,
      TSyntaxKind.FinalizationSection, TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile]) then
    begin
      Blocks := Blocks + [ANode];
      Exit;
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      CollectBlocks(ANode[Index]);
  end;

  /// Erstes Code-Token AWord bzw. ASymbol auf Klammerebene 0 in AFrom..AStop-1; -1 ohne.
  function AtDepthZero(AFrom, AStop: Integer; const AText: string; AKeyword: Boolean): Integer;
  var
    Index, Depth: Integer;
  begin
    Depth := 0;
    for Index := AFrom to AStop - 1 do
      if Tokens[Index].IsSymbol('(') or Tokens[Index].IsSymbol('[') then
        Inc(Depth)
      else if Tokens[Index].IsSymbol(')') or Tokens[Index].IsSymbol(']') then
        Dec(Depth)
      else if (Depth = 0) and ((AKeyword and Tokens[Index].IsKeyword(AText)) or
        (not AKeyword and Tokens[Index].IsSymbol(AText))) then
        Exit(Index);
    Result := -1;
  end;

  // Liest der Rumpf ABase[AVar]? ABaseKey '' = Items[AVar] bzw. Self[AVar].
  function BodyIndexes(AFrom, AStop: Integer; const ABaseKey: string; ABaseCount: Integer;
    const AVar: string): Boolean;
  var
    Index, Inner, Close, Before, Count, Prev: Integer;
    Key: string;
  begin
    for Index := AFrom to AStop - 1 do
    begin
      if not Tokens[Index].IsSymbol('[') then
        Continue;
      Inner := NextCode(Tokens, Index + 1);
      Close := NextCode(Tokens, Inner + 1);
      if (Close >= AStop) or not SameText(Tokens[Inner].Text, AVar) or not Tokens[Close].IsSymbol(']') then
        Continue;
      if ABaseKey = '' then
      begin
        Before := PreviousCode(Tokens, Index);
        if (Before >= 0) and MatchText(Tokens[Before].Text, ['Items', 'Self']) then
          Exit(True);
        Continue;
      end;
      // Die ABaseCount Code-Token vor [ müssen die Basis ergeben; Basis.Items[I] zählt mit.
      Key := '';
      Before := Index;
      Prev := PreviousCode(Tokens, Index);
      if (Prev > 0) and SameText(Tokens[Prev].Text, 'Items') and Tokens[PreviousCode(Tokens, Prev)].IsSymbol('.') then
        Before := PreviousCode(Tokens, Prev);
      Count := 0;
      while (Count < ABaseCount) and (Before > 0) do
      begin
        Before := PreviousCode(Tokens, Before);
        if Before < 0 then
          Break;
        Key := LowerCase(Tokens[Before].Text) + Key;
        Inc(Count);
      end;
      if Key <> ABaseKey then
        Continue;
      // Andere.Kunden[I] gehört nicht zu Kunden.
      Prev := PreviousCode(Tokens, Before);
      if (Prev < 0) or not Tokens[Prev].IsSymbol('.') then
        Exit(True);
    end;
    Result := False;
  end;

  function CodeCount(AFirst, ALast: Integer): Integer;
  var
    Index: Integer;
  begin
    Result := 0;
    for Index := AFirst to ALast do
      if not IsTrivia(Tokens[Index]) then
        Inc(Result);
  end;

  procedure Inspect(ANode: TSyntaxNode);
  var
    First, Stop, Assign, ToIndex, DoIndex, LowFirst, LowLast, HighFirst, HighLast, Open, Close, Dot,
      BaseFirst, BaseLast: Integer;
    LowKey, BaseKey, BaseText, HighText, TypeName, Message, Replacement, FixTitle: string;
    IsCall, IsString: Boolean;
    Edit: TRuleEdit;
  begin
    Close := -1;
    FixTitle := '';
    Edit := Default(TRuleEdit);
    First := TokenFrom(Tokens, ANode.StartOffset);
    Stop := TokenFrom(Tokens, ANode.EndOffset);
    Assign := AtDepthZero(First, Stop, ':=', False);
    if Assign < 0 then
      Exit;
    ToIndex := AtDepthZero(Assign + 1, Stop, 'to', True);
    if ToIndex < 0 then
      Exit; // downto: das prüft for-high-to-low
    DoIndex := AtDepthZero(ToIndex + 1, Stop, 'do', True);
    if DoIndex < 0 then
      Exit;
    LowFirst := NextCode(Tokens, Assign + 1);
    LowLast := PreviousCode(Tokens, ToIndex);
    HighFirst := NextCode(Tokens, ToIndex + 1);
    HighLast := PreviousCode(Tokens, DoIndex);
    if (LowLast < LowFirst) or (HighLast < HighFirst) then
      Exit;
    LowKey := CodeKey(Tokens, LowFirst, LowLast);
    HighText := Trim(SourceText(AContext.Text, Tokens, HighFirst, HighLast));
    BaseFirst := -1;
    BaseLast := -1;
    IsCall := False;
    // Length(A): Name aus countNames mit Klammer um die ganze Obergrenze (oder mit - 1 bei Strings).
    Open := NextCode(Tokens, HighFirst + 1);
    if (Tokens[HighFirst].Kind = TPascalTokenKind.Identifier) and (IndexText(Tokens[HighFirst].Text, CountNames) >= 0) and
      (Open <= HighLast) and Tokens[Open].IsSymbol('(') then
    begin
      Close := Closing(Tokens, Open, HighLast + 1);
      if Close > Open + 1 then
      begin
        IsCall := True;
        BaseFirst := NextCode(Tokens, Open + 1);
        BaseLast := PreviousCode(Tokens, Close);
        if Close <> HighLast then
        begin
          // Nur "Length(S) - 1" bei Strings; sonst ist es kein einfacher Fall.
          if CodeKey(Tokens, Close + 1, HighLast) <> '-1' then
            Exit;
        end;
      end;
    end
    // X.Count bzw. Count: letzter Name aus countNames.
    else if (Tokens[HighLast].Kind = TPascalTokenKind.Identifier) and
      (IndexText(Tokens[HighLast].Text, CountNames) >= 0) then
    begin
      Dot := PreviousCode(Tokens, HighLast);
      if HighLast = HighFirst then
      begin
        BaseFirst := HighLast + 1;
        BaseLast := HighLast; // leer: Items[I]
      end
      else if (Dot >= HighFirst) and Tokens[Dot].IsSymbol('.') and (Dot > HighFirst) then
      begin
        BaseFirst := HighFirst;
        BaseLast := PreviousCode(Tokens, Dot);
      end
      else
        Exit;
    end
    else
      Exit;
    if BaseFirst < 0 then
      Exit;
    if BaseLast >= BaseFirst then
    begin
      BaseKey := CodeKey(Tokens, BaseFirst, BaseLast);
      BaseText := Trim(SourceText(AContext.Text, Tokens, BaseFirst, BaseLast));
    end
    else
    begin
      BaseKey := '';
      BaseText := '';
    end;
    TypeName := '';
    if (BaseFirst = BaseLast) and (Tokens[BaseFirst].Kind = TPascalTokenKind.Identifier) then
      TypeName := Types.DeclaredType(Tokens[BaseFirst].Text, Tokens[BaseFirst].StartPos);
    IsString := IsCall and IsStringType(TypeName);
    if not BodyIndexes(DoIndex + 1, Stop, BaseKey, CodeCount(BaseFirst, BaseLast), ANode.Name) then
      Exit;
    Message := '';
    if IsString then
    begin
      Replacement := Format('Low(%s) to High(%s)', [BaseText, BaseText]);
      FixTitle := Format('Low(%s)/High(%s) verwenden', [BaseText, BaseText]);
      Edit := TRuleEdit.Create(TTextRange.Create(Tokens[LowFirst].StartPos, Tokens[HighLast].EndPos), Replacement);
      if not ZeroBased and (LowKey = '0') then
        Message := Format('Strings beginnen bei 1: der erste Durchlauf greift auf %s[0].', [BaseText])
      else if ZeroBased and (LowKey = '0') and (Close = HighLast) then
        Message := Format('Obergrenze %s: der letzte Durchlauf greift hinter das String-Ende ' +
          '(mit {$ZEROBASEDSTRINGS ON} sind Strings nullbasiert).', [HighText])
      else if ZeroBased and (LowKey = '1') and (Close = HighLast) then
        Message := Format('Mit {$ZEROBASEDSTRINGS ON} sind Strings nullbasiert: die Schleife überspringt %s[0] ' +
          'und greift hinter das Ende.', [BaseText]);
    end
    else if (LowKey = '0') and (not IsCall or (Close = HighLast)) then
    begin
      if IsCall then
      begin
        Message := Format('Obergrenze %s: der letzte Durchlauf greift hinter das Array-Ende (Index %s).',
          [HighText, Tokens[HighFirst].Text]);
        FixTitle := Format('High(%s) verwenden', [BaseText]);
        Edit := TRuleEdit.Create(TTextRange.Create(Tokens[HighFirst].StartPos, Tokens[HighLast].EndPos),
          Format('High(%s)', [BaseText]));
      end
      else
      begin
        Message := Format('Obergrenze %s: der letzte Durchlauf greift hinter das Listenende (Index %s).',
          [HighText, Tokens[HighLast].Text]);
        FixTitle := '„- 1“ ergänzen';
        Edit := TRuleEdit.Create(TTextRange.Create(Tokens[HighLast].EndPos, Tokens[HighLast].EndPos), ' - 1');
      end;
    end;
    if Message = '' then
      Exit;
    AReport.Add(TTextRange.Create(Tokens[LowFirst].StartPos, Tokens[HighLast].EndPos), Message, TRuleConfidence.High,
      [TRuleFix.Create(FixTitle, [Edit])]);
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    if ANode.Kind = TSyntaxKind.ForStatement then
      Inspect(ANode);
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index]);
  end;

  // S[0] bei einsbasierten Strings.
  procedure FindZeroIndex;
  var
    Index, Open, Zero, Close, Prev: Integer;
    Name: string;
  begin
    for Index := 0 to High(Tokens) do
    begin
      if Tokens[Index].Kind <> TPascalTokenKind.Identifier then
        Continue;
      Open := NextCode(Tokens, Index + 1);
      if (Open > High(Tokens)) or not Tokens[Open].IsSymbol('[') then
        Continue;
      Zero := NextCode(Tokens, Open + 1);
      Close := NextCode(Tokens, Zero + 1);
      if (Close > High(Tokens)) or not ((Tokens[Zero].Kind = TPascalTokenKind.Number) and (Tokens[Zero].Text = '0')) or
        not Tokens[Close].IsSymbol(']') or not InBlock(Tokens[Index].Offset) then
        Continue;
      Prev := PreviousCode(Tokens, Index);
      if (Prev >= 0) and (Tokens[Prev].IsSymbol('.') or Tokens[Prev].IsSymbol('@')) then
        Continue;
      Name := Tokens[Index].Text;
      if not IsStringType(Types.DeclaredType(Name, Tokens[Index].StartPos)) then
        Continue;
      AReport.Add(TTextRange.Create(Tokens[Index].StartPos, Tokens[Close].EndPos),
        Format('Strings beginnen bei 1: %s[0] liegt vor dem ersten Zeichen.', [Name]), TRuleConfidence.High,
        [TRuleFix.Create(Format('Low(%s) verwenden', [Name]),
        [TRuleEdit.Create(TTextRange.Create(Tokens[Zero].StartPos, Tokens[Zero].EndPos), Format('Low(%s)', [Name]))])]);
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Tokens := AContext.Tree.Tokens;
  CountNames := TRuleOptions.Strings(AContext.Options, 'countNames', ['Count', 'Length']);
  ZeroBased := ZeroBasedStrings(Tokens);
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    Blocks := nil;
    CollectBlocks(AContext.Tree.Root);
    Visit(AContext.Tree.Root);
    if not ZeroBased then
      FindZeroIndex;
  finally
    Types.Free;
  end;
end;

{ TCollectionModifiedInLoopRule }

class function TCollectionModifiedInLoopRule.DefaultMutatingMethods: TArray<string>;
begin
  Result := ['Add', 'Insert', 'Delete', 'Remove', 'Extract', 'Clear'];
end;

function TCollectionModifiedInLoopRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(CollectionModifiedInLoopRuleId, TRuleSeverity.Warning,
    'Liste in der eigenen Schleife verändert');
end;

procedure TCollectionModifiedInLoopRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Methods: TArray<string>;

  function CodeCount(AFirst, ALast: Integer): Integer;
  var
    Index: Integer;
  begin
    Result := 0;
    for Index := AFirst to ALast do
      if not IsTrivia(Tokens[Index]) then
        Inc(Result);
  end;

  // Folgt auf die Anweisung mit dem Aufruf (ab ACall) direkt Break oder Exit?
  function LeavesLoop(ACall, AStop: Integer): Boolean;
  var
    Semicolon, Next: Integer;
  begin
    Semicolon := DepthZero(Tokens, ACall, AStop, ';', False);
    if Semicolon < 0 then
      Exit(False);
    Next := NextCode(Tokens, Semicolon + 1);
    Result := (Next < AStop) and MatchText(Tokens[Next].Text, ['Break', 'Exit']);
  end;

  // Basis der Obergrenze: X in X.Count - 1, X.Count, High(X), Pred(X.Count), Length(X) - 1; sonst False.
  function BaseOfBound(AFirst, ALast: Integer; out ABaseFirst, ABaseLast: Integer): Boolean;
  var
    Last, Open, Close, Dot: Integer;
  begin
    Result := False;
    ABaseFirst := -1;
    ABaseLast := -1;
    Last := ALast;
    // "- 1" am Ende abtrennen.
    if (CodeCount(AFirst, ALast) > 2) and (Tokens[ALast].Kind = TPascalTokenKind.Number) and (Tokens[ALast].Text = '1') and
      Tokens[PreviousCode(Tokens, ALast)].IsSymbol('-') then
      Last := PreviousCode(Tokens, PreviousCode(Tokens, ALast));
    if (Tokens[AFirst].Kind = TPascalTokenKind.Identifier) and MatchText(Tokens[AFirst].Text, ['High', 'Length', 'Pred']) then
    begin
      Open := NextCode(Tokens, AFirst + 1);
      if not Tokens[Open].IsSymbol('(') then
        Exit;
      Close := Closing(Tokens, Open, Last + 1);
      if (Close <> Last) or (Close <= Open + 1) then
        Exit;
      if SameText(Tokens[AFirst].Text, 'Pred') then
        Exit(BaseOfBound(NextCode(Tokens, Open + 1), PreviousCode(Tokens, Close), ABaseFirst, ABaseLast));
      ABaseFirst := NextCode(Tokens, Open + 1);
      ABaseLast := PreviousCode(Tokens, Close);
      Exit(True);
    end;
    if (Tokens[Last].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[Last].Text, 'Count') then
    begin
      Dot := PreviousCode(Tokens, Last);
      if (Dot > AFirst) and Tokens[Dot].IsSymbol('.') then
      begin
        ABaseFirst := AFirst;
        ABaseLast := PreviousCode(Tokens, Dot);
        Result := True;
      end;
    end;
  end;

  // Meldet BaseKey.M( im Rumpf AFrom..AStop-1.
  procedure FindCalls(AFrom, AStop: Integer; const ABaseKey, ABaseText: string; ABaseCount: Integer;
    AForIn: Boolean; const AFix: TArray<TRuleFix>);
  var
    Index, Dot, Open: Integer;
    Method, Message: string;
    Fixes: TArray<TRuleFix>;
  begin
    for Index := AFrom to AStop - 1 do
    begin
      if (Tokens[Index].Kind <> TPascalTokenKind.Identifier) or (IndexText(Tokens[Index].Text, Methods) < 0) then
        Continue;
      Dot := PreviousCode(Tokens, Index);
      Open := NextCode(Tokens, Index + 1);
      if (Dot < 0) or not Tokens[Dot].IsSymbol('.') or not BaseBefore(Tokens, Dot, ABaseKey, ABaseCount) then
        Continue;
      // Clear ohne Klammern ist auch ein Aufruf; sonst muss "(" folgen.
      if not SameText(Tokens[Index].Text, 'Clear') and ((Open >= AStop) or not Tokens[Open].IsSymbol('(')) then
        Continue;
      if LeavesLoop(Index, AStop) then
        Continue;
      Method := Tokens[Index].Text;
      Fixes := nil;
      if AForIn then
        Message := Format('%s.%s in for … in über %s: die RTL wirft eine Exception, weil sich die Liste ändert. ' +
          'Elemente sammeln und nach der Schleife ändern.', [ABaseText, Method, ABaseText])
      else if MatchText(Method, ['Add']) then
        Message := Format('%s.%s in einer Vorwärtsschleife über %s: die neuen Elemente durchläuft die Schleife ' +
          'nicht, die Obergrenze steht beim Start fest.', [ABaseText, Method, ABaseText])
      else if MatchText(Method, ['Insert']) then
        Message := Format('%s.%s in einer Vorwärtsschleife über %s: die Elemente rücken nach, dasselbe Element ' +
          'kommt noch einmal, am Ende fehlen Elemente.', [ABaseText, Method, ABaseText])
      else
      begin
        Message := Format('%s.%s in einer Vorwärtsschleife über %s: das nächste Element wird übersprungen, ' +
          'am Ende folgt ein Indexfehler.', [ABaseText, Method, ABaseText]);
        Fixes := AFix;
      end;
      AReport.Add(TTextRange.Create(Tokens[PreviousCode(Tokens, Dot)].StartPos, Tokens[Index].EndPos), Message,
        TRuleConfidence.High, Fixes);
    end;
  end;

  procedure Inspect(ANode: TSyntaxNode);
  var
    First, Stop, Assign, ToIndex, InIndex, DoIndex, LowFirst, LowLast, HighFirst, HighLast, BaseFirst,
      BaseLast: Integer;
    BaseKey, BaseText, LowText, HighText: string;
    Fix: TArray<TRuleFix>;
  begin
    First := TokenFrom(Tokens, ANode.StartOffset);
    Stop := TokenFrom(Tokens, ANode.EndOffset);
    if ANode.Kind = TSyntaxKind.ForInStatement then
    begin
      InIndex := DepthZero(Tokens, First, Stop, 'in', True);
      DoIndex := DepthZero(Tokens, First, Stop, 'do', True);
      if (InIndex < 0) or (DoIndex < InIndex) then
        Exit;
      BaseFirst := NextCode(Tokens, InIndex + 1);
      BaseLast := PreviousCode(Tokens, DoIndex);
      if BaseLast < BaseFirst then
        Exit;
      BaseText := Trim(SourceText(AContext.Text, Tokens, BaseFirst, BaseLast));
      FindCalls(DoIndex + 1, Stop, CodeKey(Tokens, BaseFirst, BaseLast), BaseText, CodeCount(BaseFirst, BaseLast),
        True, nil);
      Exit;
    end;
    Assign := DepthZero(Tokens, First, Stop, ':=', False);
    if Assign < 0 then
      Exit;
    ToIndex := DepthZero(Tokens, Assign + 1, Stop, 'to', True);
    if ToIndex < 0 then
      Exit; // downto: rückwärts ist Löschen unbedenklich
    DoIndex := DepthZero(Tokens, ToIndex + 1, Stop, 'do', True);
    if DoIndex < 0 then
      Exit;
    LowFirst := NextCode(Tokens, Assign + 1);
    LowLast := PreviousCode(Tokens, ToIndex);
    HighFirst := NextCode(Tokens, ToIndex + 1);
    HighLast := PreviousCode(Tokens, DoIndex);
    if (LowLast < LowFirst) or (HighLast < HighFirst) or not BaseOfBound(HighFirst, HighLast, BaseFirst, BaseLast) then
      Exit;
    BaseKey := CodeKey(Tokens, BaseFirst, BaseLast);
    BaseText := Trim(SourceText(AContext.Text, Tokens, BaseFirst, BaseLast));
    LowText := Trim(SourceText(AContext.Text, Tokens, LowFirst, LowLast));
    HighText := Trim(SourceText(AContext.Text, Tokens, HighFirst, HighLast));
    Fix := [TRuleFix.Create('Schleife rückwärts (downto) umschreiben',
      [TRuleEdit.Create(TTextRange.Create(Tokens[LowFirst].StartPos, Tokens[HighLast].EndPos),
      HighText + ' downto ' + LowText)])];
    FindCalls(DoIndex + 1, Stop, BaseKey, BaseText, CodeCount(BaseFirst, BaseLast), False, Fix);
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    if ANode.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement] then
      Inspect(ANode);
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index]);
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Methods := TRuleOptions.Strings(AContext.Options, 'mutatingMethods', DefaultMutatingMethods);
  Visit(AContext.Tree.Root);
end;

procedure RegisterStatementRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TEmptyStatementRule.Create);
  ARegistry.Register(TLoopOffByOneRule.Create);
  ARegistry.Register(TCollectionModifiedInLoopRule.Create);
end;

end.
