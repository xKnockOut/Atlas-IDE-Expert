unit Atlas.Common.Rules.Builtin.Testing;

// Regeln für DUnitX-Tests:
//   dunitx-test-without-assert  [Test]- bzw. [TestCase]-Methode, die weder selbst noch über Methoden derselben
//                               Klasse oder Routinen der Unit eine Prüfung aufruft (#945): Sie ist immer grün.
//                               Als Prüfung zählen Aufrufe nach "assertPatterns" (Vorgabe Assert.*, WillRaise*,
//                               Check*), System.Assert und Aufrufe an Klassen mit Assert im Namen
//                               (TRuleAssert.Reports). Tests mit [WillRaise] oder [Ignore] bleiben still.
//                               Korrekturen: Assert.Pass als Platzhalter oder Sprung zur Methode.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TDUnitXTestWithoutAssertRule = class(TInterfacedObject, IRule)
  public
    /// <summary>Vorgabe von "assertPatterns": Assert.*, WillRaise*, Check*.</summary>
    class function DefaultPatterns: TArray<string>; static;
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Zählt der Aufruf AChain (z. B. Assert.AreEqual, TRuleAssert.Reports) als Prüfung?</summary>
    class function IsAssertion(const AChain: string; const APatterns: TArray<string>): Boolean; static;
  end;

procedure RegisterTestingRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.Attributes,
  Atlas.Common.Rules.Options;

const
  DUnitXTestWithoutAssertRuleId = 'dunitx-test-without-assert';

{ TDUnitXTestWithoutAssertRule }

class function TDUnitXTestWithoutAssertRule.DefaultPatterns: TArray<string>;
begin
  Result := ['Assert.*', 'WillRaise*', 'Check*'];
end;

function TDUnitXTestWithoutAssertRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(DUnitXTestWithoutAssertRuleId, TRuleSeverity.Hint, 'DUnitX-Test ohne Assert');
end;

class function TDUnitXTestWithoutAssertRule.IsAssertion(const AChain: string;
  const APatterns: TArray<string>): Boolean;
var
  Pattern: string;
  Parts: TArray<string>;
  Index: Integer;
begin
  // System.Assert(Bedingung) löst EAssertionFailed aus und lässt den Test scheitern.
  if SameText(AChain, 'Assert') or SameText(AChain, 'System.Assert') then
    Exit(True);
  for Pattern in APatterns do
    if MatchesGlob(Pattern, AChain) then
      Exit(True);
  // Eigene Prüfklassen: TRuleAssert.Reports, TJsonAssert.Equal.
  Parts := AChain.Split(['.']);
  for Index := 0 to High(Parts) - 1 do
    if ContainsText(Parts[Index], 'Assert') then
      Exit(True);
  Result := False;
end;

procedure TDUnitXTestWithoutAssertRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Code: TArray<Integer>;
  Lines: TArray<string>;
  LineBreak: string;
  Patterns: TArray<string>;
  Routines: TArray<TSyntaxNode>;

  function Token(APosition: Integer): TPascalToken;
  begin
    Result := Tokens[Code[APosition]];
  end;

  function IsWord(APosition: Integer): Boolean;
  begin
    Result := (APosition >= 0) and (APosition <= High(Code)) and
      (Token(APosition).Kind = TPascalTokenKind.Identifier);
  end;

  // Iterativ (Bericht M1).
  procedure CollectRoutines(ARoot: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        // Auch lokale Routinen: Ein Test prüft oft in einer eigenen Hilfsroutine (procedure Silent(…) mit Assert).
        if Node.Kind = TSyntaxKind.RoutineDecl then
          Routines := Routines + [Node];
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

  function FindRoutine(const AName: string): TSyntaxNode;
  var
    Routine: TSyntaxNode;
  begin
    for Routine in Routines do
      if SameText(Routine.Name, AName) then
        Exit(Routine);
    Result := nil;
  end;

  // Prüft ARoutine (oder eine von ihr aufgerufene Methode von AClassName bzw. Routine der Unit) etwas?
  function Asserts(ARoutine: TSyntaxNode; const AClassName: string; var AVisited: TArray<TSyntaxNode>): Boolean;
  var
    Block, Callee, Visited: TSyntaxNode;
    Position, Last: Integer;
    Chain: string;
  begin
    Result := False;
    for Visited in AVisited do
      if Visited = ARoutine then
        Exit;
    AVisited := AVisited + [ARoutine];
    Block := ARoutine.FindChild(TSyntaxKind.Block);
    if Block = nil then
      Exit;
    for Position := 0 to High(Code) do
    begin
      if (Token(Position).Offset < Block.StartOffset) or (Token(Position).Offset >= Block.EndOffset) or
        not IsWord(Position) or ((Position > 0) and Token(Position - 1).IsSymbol('.')) then
        Continue;
      // Punktkette ab hier: Assert.AreEqual, Self.Pruefen, TRuleAssert.Reports.
      Chain := Token(Position).Text;
      Last := Position;
      while (Last + 2 <= High(Code)) and Token(Last + 1).IsSymbol('.') and IsWord(Last + 2) do
      begin
        Inc(Last, 2);
        Chain := Chain + '.' + Token(Last).Text;
      end;
      if IsAssertion(Chain, Patterns) then
        Exit(True);
      if StartsText('Self.', Chain) then
        Chain := Copy(Chain, 6, MaxInt);
      if Pos('.', Chain) > 0 then
        Continue;
      Callee := FindRoutine(AClassName + '.' + Chain);
      if Callee = nil then
        Callee := FindRoutine(Chain);
      if (Callee <> nil) and Asserts(Callee, AClassName, AVisited) then
        Exit(True);
    end;
  end;

  function NameRange(AHeader: TSyntaxNode): TTextRange;
  var
    Position: Integer;
  begin
    Result := TTextRange.Create(AHeader.StartPos, AHeader.EndPos);
    for Position := 0 to High(Code) do
      if (Token(Position).Offset >= AHeader.StartOffset) and (Token(Position).Offset < AHeader.EndOffset) and
        IsWord(Position) and SameText(Token(Position).Text, AHeader.Name) then
        Exit(TTextRange.Create(Token(Position).StartPos, Token(Position).EndPos));
  end;

  // "Assert.Pass;" vor das "end" des Rumpfs, wenn es allein in seiner Zeile steht.
  function PassEdit(ABlock: TSyntaxNode; out AEdit: TTextEdit): Boolean;
  var
    Line: Integer;
    Indent: string;
  begin
    Result := False;
    Line := ABlock.EndPos.Line;
    if (Line > High(Lines)) or (ABlock.EndPos.Line = ABlock.StartPos.Line) or
      (Trim(Copy(Lines[Line], 1, ABlock.EndPos.Character - 3)) <> '') then
      Exit;
    Indent := TTextLines.IndentOf(Lines[Line]);
    AEdit := TTextEdit.Create(TTextRange.Create(Line, 0, Line, 0), Indent + '  Assert.Pass;' + LineBreak);
    Result := True;
  end;

  procedure CheckMethod(const AClassName: string; AHeader: TSyntaxNode);
  var
    Body, Block: TSyntaxNode;
    Visited: TArray<TSyntaxNode>;
    Fixes: TArray<TRuleFix>;
    Edit: TTextEdit;
    Fix: TRuleFix;
  begin
    Body := FindRoutine(AClassName + '.' + AHeader.Name);
    if Body = nil then
      Exit;
    Visited := nil;
    if Asserts(Body, AClassName, Visited) then
      Exit;
    Fixes := nil;
    Block := Body.FindChild(TSyntaxKind.Block);
    if (Block <> nil) and PassEdit(Block, Edit) then
    begin
      Fix := TRuleFix.Create('Assert.Pass; als Platzhalter einfügen', [Edit]);
      Fix.Alternative := True;
      Fixes := Fixes + [Fix];
    end;
    Fix := TRuleFix.Jump('Zur Methode springen', Body.StartPos);
    Fix.Alternative := True;
    Fixes := Fixes + [Fix];
    AReport.Add(NameRange(AHeader), 'Der Test prüft nichts; er ist immer grün.', Fixes);
  end;

  procedure CheckClass(const AClassName: string; AClass: TSyntaxNode);
  var
    Index: Integer;
    Child: TSyntaxNode;
    Names: TArray<string>;
  begin
    Names := nil;
    for Index := 0 to AClass.ChildCount - 1 do
    begin
      Child := AClass[Index];
      if Child.Kind = TSyntaxKind.Attribute then
      begin
        Names := Names + TAttributes.Names(Child);
        Continue;
      end;
      if (Child.Kind = TSyntaxKind.RoutineHeader) and (MatchText('Test', Names) or MatchText('TestCase', Names)) and
        not MatchText('Ignore', Names) and not MatchText('WillRaise', Names) and
        not MatchText('WillRaiseAny', Names) then
        CheckMethod(AClassName, Child);
      Names := nil;
    end;
  end;

  // Iterativ (Bericht M1).
  procedure Visit(ARoot: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
    Body: TSyntaxNode;
  begin
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.TypeDecl then
        begin
          Body := Node.FindChild(TSyntaxKind.ClassType);
          if Body <> nil then
            CheckClass(Node.Name, Body);
          Continue;
        end;
        if Node.Kind in [TSyntaxKind.Block, TSyntaxKind.RoutineDecl] then
          Continue;
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

var
  Index: Integer;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  // Ohne Attribut Test schweigt die Regel sofort.
  if not ContainsText(AContext.Text, 'Test') then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Code := nil;
  for Index := 0 to High(Tokens) do
    if not (Tokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
      Code := Code + [Index];
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  Patterns := TRuleOptions.Strings(AContext.Options, 'assertPatterns', DefaultPatterns);
  Routines := nil;
  CollectRoutines(AContext.Tree.Root);
  Visit(AContext.Tree.Root);
end;

procedure RegisterTestingRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TDUnitXTestWithoutAssertRule.Create);
end;

end.
