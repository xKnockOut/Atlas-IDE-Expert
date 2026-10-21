unit Atlas.Common.Rules.Builtin.Statements;

// Regeln für Anweisungen, die anders laufen als geschrieben (#909):
//   empty-statement   Semikolon direkt nach then, do oder else (#912): die
//                     folgende Zeile läuft immer bzw. die Schleife dreht leer.
//                     Leere Blöcke begin … end nach then, do oder else ebenso,
//                     außer mit Kommentar darin (Option allowCommented).
// Grundlage ist der Syntaxbaum: if, while, for, for-in und with ohne Rumpf
// bzw. mit leerem Block; das Schlüsselwort davor sucht die Regel in den Token.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  EmptyStatementRuleId = 'empty-statement';

type
  TEmptyStatementRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterStatementRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
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

procedure RegisterStatementRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TEmptyStatementRule.Create);
end;

end.
