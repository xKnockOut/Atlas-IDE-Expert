unit Atlas.Common.Rules.Builtin.Jumps;

// Regeln für Sprünge (#909, Gruppe Compiler vorab):
//   jump-outside-allowed-scope
//                     Break oder Continue außerhalb einer Schleife (#984, wie
//                     E2097) bzw. Break, Continue oder Exit, die einen
//                     finally-Block verlassen (wie E2126). Eine Schleife ganz
//                     im finally-Block bleibt erlaubt. Routinen und anonyme
//                     Methoden beginnen neu: Ein Break in einer anonymen
//                     Methode gehört nicht zur Schleife um sie herum.
//                     Korrektur außerhalb eines finally: Break durch Exit
//                     ersetzen.
//   label-misuse      Sprungmarken (#995): Marke doppelt gesetzt (wie E2073),
//                     deklariert und angesprungen, aber nie gesetzt (E2074),
//                     gesetzt oder angesprungen, aber in der Routine nicht
//                     deklariert (E2093), und goto in einen try-Block hinein
//                     oder aus ihm heraus, auch zwischen try-Teil und except
//                     bzw. finally (E2127). Marken gelten je Routine bzw.
//                     Programmblock; die Deklarationen liest die Regel aus den
//                     Token der label-Abschnitte. Doppelte Marken in Zweigen,
//                     die sich ausschließen, bleiben still
//                     (Pascal.ConditionalBranches); Routinen mit asm-Block
//                     ebenso, weil der Baum Marken im asm nicht sieht.
//
// Grundlage ist der Syntaxbaum. Gemeldet werden nur einfache Aufrufe (Break;
// nicht TMonitor.Exit(FLock)) und nur, wenn die Datei den Namen nicht selbst
// deklariert. Meldet der Parser in der Routine einen Fehler, ist die
// Schachtelung nicht sicher, und die Regel bleibt dort still.

interface

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  JumpOutsideAllowedScopeRuleId = 'jump-outside-allowed-scope';
  LabelMisuseRuleId = 'label-misuse';

type
  TJumpOutsideAllowedScopeRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Name eines einfachen Aufrufs als Anweisung (Exit, Exit(1), Break) in Kleinbuchstaben;
    /// '' bei Aufrufen über ein Objekt (TMonitor.Exit(FLock)) und anderen Anweisungen.</summary>
    class function PlainCallName(AStatement: TSyntaxNode): string; static;
  end;

  TLabelMisuseRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Schlüssel einer Marke zum Vergleichen: Ziffernmarken als Zahl (007 = 7), sonst klein.</summary>
    class function LabelKey(const AName: string): string; static;
  end;

procedure RegisterJumpRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.ConditionalBranches;

/// <summary>Hat der Parser im Bereich von AScope einen Fehler gemeldet (nil: irgendwo)? Dann ist die
/// Schachtelung dort nicht sicher.</summary>
function ParserBroken(ATree: TSyntaxTree; AScope: TSyntaxNode): Boolean;
var
  Diagnostic: TSyntaxDiagnostic;
begin
  for Diagnostic in ATree.Diagnostics do
    if (AScope = nil) or ((Diagnostic.StartPos.Line >= AScope.StartPos.Line) and
      (Diagnostic.StartPos.Line <= AScope.EndPos.Line)) then
      Exit(True);
  Result := False;
end;

/// <summary>Routinen, anonyme Methoden und Abschnitte mit eigenen Anweisungen: Grenze für Sprünge.</summary>
function IsJumpScope(ANode: TSyntaxNode): Boolean;
begin
  Result := ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod,
    TSyntaxKind.InitializationSection, TSyntaxKind.FinalizationSection, TSyntaxKind.ProgramFile,
    TSyntaxKind.LibraryFile];
end;

function IsLoop(ANode: TSyntaxNode): Boolean;
begin
  Result := ANode.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
    TSyntaxKind.RepeatStatement];
end;

/// <summary>Namen, die die Datei selbst deklariert (Routinen, Variablen, Konstanten, Felder, Parameter …),
/// klein. Ein eigenes Break ist dann kein Sprung.</summary>
function DeclaredNames(ARoot: TSyntaxNode): TDictionary<string, Boolean>;
var
  Names: TDictionary<string, Boolean>;
begin
  Names := TDictionary<string, Boolean>.Create;
  ARoot.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      Part: string;
    begin
      if (ANode.Name <> '') and (ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.RoutineHeader,
        TSyntaxKind.VarDecl, TSyntaxKind.ConstDecl, TSyntaxKind.Field, TSyntaxKind.PropertyDecl,
        TSyntaxKind.Parameter, TSyntaxKind.TypeDecl, TSyntaxKind.InlineVar, TSyntaxKind.InlineConst]) then
        for Part in ANode.Name.Split([',', '.']) do
          Names.AddOrSetValue(LowerCase(Trim(Part)), True);
      Result := True;
    end);
  Result := Names;
end;

{ TJumpOutsideAllowedScopeRule }

function TJumpOutsideAllowedScopeRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(JumpOutsideAllowedScopeRuleId, TRuleSeverity.Error,
    'Break, Continue oder Exit an unzulässiger Stelle');
end;

class function TJumpOutsideAllowedScopeRule.PlainCallName(AStatement: TSyntaxNode): string;
var
  Target: TSyntaxNode;
begin
  Result := '';
  if (AStatement = nil) or (AStatement.Kind <> TSyntaxKind.CallStatement) or (AStatement.ChildCount <> 1) then
    Exit;
  Target := AStatement[0];
  if (Target.Kind = TSyntaxKind.Call) and (Target.ChildCount > 0) then
    Target := Target[0];
  if Target.Kind = TSyntaxKind.Identifier then
    Result := LowerCase(Target.Name);
end;

procedure TJumpOutsideAllowedScopeRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Declared: TDictionary<string, Boolean>;

  procedure Report(AStatement, AScope: TSyntaxNode; const AName, AMessage: string; AWithFix: Boolean);
  var
    Range: TTextRange;
    Fixes: TArray<TRuleFix>;
  begin
    if ParserBroken(AContext.Tree, AScope) then
      Exit;
    Range := TTextRange.Create(AStatement.StartPos,
      TTextPosition.Create(AStatement.StartPos.Line, AStatement.StartPos.Character + Length(AName)));
    Fixes := nil;
    if AWithFix then
      Fixes := [TRuleFix.Create('Break durch Exit ersetzen', [TRuleEdit.Create(Range, 'Exit')])];
    AReport.Add(Range, AMessage, TRuleConfidence.High, Fixes);
  end;

  // AHasLoop: eine Schleife umschließt die Stelle in derselben Routine; AFinallySinceLoop: zwischen ihr und der
  // Stelle liegt ein finally; AInFinally: irgendein finally der Routine umschließt die Stelle.
  procedure Visit(ANode, AScope: TSyntaxNode; AHasLoop, AFinallySinceLoop, AInFinally: Boolean);
  var
    Index: Integer;
    Name, Written: string;
  begin
    if IsJumpScope(ANode) then
    begin
      AScope := ANode;
      AHasLoop := False;
      AFinallySinceLoop := False;
      AInFinally := False;
    end
    else if IsLoop(ANode) then
    begin
      AHasLoop := True;
      AFinallySinceLoop := False;
    end
    else if ANode.Kind = TSyntaxKind.FinallyBlock then
    begin
      AFinallySinceLoop := True;
      AInFinally := True;
    end
    else if ANode.Kind = TSyntaxKind.CallStatement then
    begin
      Name := PlainCallName(ANode);
      if ((Name = 'break') or (Name = 'continue') or (Name = 'exit')) and not Declared.ContainsKey(Name) then
      begin
        Written := Copy(AContext.Text, ANode.StartOffset + 1, Length(Name));
        if (Name <> 'exit') and not AHasLoop then
          Report(ANode, AScope, Name, Format('%s außerhalb einer Schleife (wie E2097).', [Written]),
            (Name = 'break') and not AInFinally)
        else if ((Name <> 'exit') and AFinallySinceLoop) or ((Name = 'exit') and AInFinally) then
          Report(ANode, AScope, Name, Format('%s darf einen finally-Block nicht verlassen (wie E2126).',
            [Written]), False);
      end;
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index], AScope, AHasLoop, AFinallySinceLoop, AInFinally);
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Declared := DeclaredNames(AContext.Tree.Root);
  try
    Visit(AContext.Tree.Root, nil, False, False, False);
  finally
    Declared.Free;
  end;
end;

{ TLabelMisuseRule }

function TLabelMisuseRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(LabelMisuseRuleId, TRuleSeverity.Error, 'Sprungmarke falsch verwendet');
end;

class function TLabelMisuseRule.LabelKey(const AName: string): string;
var
  Number: Integer;
begin
  // Ziffernmarken vergleicht Delphi als Zahl: 007 und 7 sind dieselbe Marke.
  if (AName <> '') and CharInSet(AName[1], ['0'..'9']) and TryStrToInt(AName, Number) then
    Result := IntToStr(Number)
  else
    Result := LowerCase(AName);
end;

procedure TLabelMisuseRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Paths: TArray<string>;

  function TokenAt(AOffset: Integer): Integer;
  var
    Low, High, Middle: Integer;
  begin
    Low := 0;
    High := Length(Tokens);
    while Low < High do
    begin
      Middle := (Low + High) div 2;
      if Tokens[Middle].Offset < AOffset then
        Low := Middle + 1
      else
        High := Middle;
    end;
    Result := Low;
  end;

  function PathOf(ANode: TSyntaxNode): string;
  begin
    Result := TConditionalBranches.PathAt(Paths, TokenAt(ANode.StartOffset));
  end;

  // try-Anweisungen und ihre Teile von der Routine bis zu ANode, als Kette von Knoten.
  function TryChain(ANode, AScope: TSyntaxNode): TArray<TSyntaxNode>;
  var
    Node: TSyntaxNode;
  begin
    Result := nil;
    Node := ANode.Parent;
    while (Node <> nil) and (Node <> AScope) do
    begin
      if Node.Kind in [TSyntaxKind.TryStatement, TSyntaxKind.ExceptBlock, TSyntaxKind.FinallyBlock] then
        Result := [Node] + Result;
      Node := Node.Parent;
    end;
  end;

  // Ist AOuter ein Anfangsstück von AInner?
  function IsPrefix(const AOuter, AInner: TArray<TSyntaxNode>): Boolean;
  var
    Index: Integer;
  begin
    if Length(AOuter) > Length(AInner) then
      Exit(False);
    for Index := 0 to High(AOuter) do
      if AOuter[Index] <> AInner[Index] then
        Exit(False);
    Result := True;
  end;

  // Art des Blocks für die Meldung: try-, except- oder finally-Block.
  function BlockName(ANode: TSyntaxNode): string;
  begin
    case ANode.Kind of
      TSyntaxKind.ExceptBlock:
        Result := 'except-Block';
      TSyntaxKind.FinallyBlock:
        Result := 'finally-Block';
    else
      Result := 'try-Block';
    end;
  end;

  function NameRange(ANode: TSyntaxNode; const AName: string): TTextRange;
  begin
    Result := TTextRange.Create(ANode.StartPos,
      TTextPosition.Create(ANode.StartPos.Line, ANode.StartPos.Character + Length(AName)));
  end;

  procedure CheckScope(AScope, ABody: TSyntaxNode);
  var
    Declared: TDictionary<string, Integer>;
    Sets: TObjectDictionary<string, TList<TSyntaxNode>>;
    Gotos: TList<TSyntaxNode>;
    HasAsm: Boolean;
    Index, First: Integer;
    Section, Node, Earlier, Target: TSyntaxNode;
    Key: string;
    Pair: TPair<string, Integer>;
    GotoChain, TargetChain: TArray<TSyntaxNode>;

    procedure Collect(ANode: TSyntaxNode);
    var
      Child: Integer;
      Name: string;
      List: TList<TSyntaxNode>;
    begin
      // Verschachtelte Routinen und anonyme Methoden haben eigene Marken.
      if ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
        Exit;
      if ANode.Kind = TSyntaxKind.AsmBlock then
        HasAsm := True
      else if ANode.Kind = TSyntaxKind.LabeledStatement then
      begin
        Name := LabelKey(ANode.Name);
        if not Sets.TryGetValue(Name, List) then
        begin
          List := TList<TSyntaxNode>.Create;
          Sets.Add(Name, List);
        end;
        List.Add(ANode);
      end
      else if (ANode.Kind = TSyntaxKind.GotoStatement) and (ANode.Name <> '') then
        Gotos.Add(ANode);
      for Child := 0 to ANode.ChildCount - 1 do
        Collect(ANode[Child]);
    end;

  begin
    Declared := TDictionary<string, Integer>.Create;
    Sets := TObjectDictionary<string, TList<TSyntaxNode>>.Create([doOwnsValues]);
    Gotos := TList<TSyntaxNode>.Create;
    try
      // label A, B, 10; in den Deklarationen der Routine: Token bis zum Semikolon.
      for Index := 0 to AScope.ChildCount - 1 do
      begin
        Section := AScope[Index];
        if Section.Kind <> TSyntaxKind.LabelSection then
          Continue;
        First := TokenAt(Section.StartOffset) + 1;
        while (First <= High(Tokens)) and (Tokens[First].Offset < Section.EndOffset) and
          not Tokens[First].IsSymbol(';') do
        begin
          if Tokens[First].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Number] then
            Declared.AddOrSetValue(LabelKey(Tokens[First].Text), First);
          Inc(First);
        end;
      end;
      HasAsm := False;
      Collect(ABody);
      if HasAsm then
        Exit; // Marken im asm-Block sieht der Baum nicht.
      // E2073: dieselbe Marke zweimal gesetzt, wenn die spätere nie ohne die frühere übersetzt wird.
      for Key in Sets.Keys do
        for Index := 1 to Sets[Key].Count - 1 do
        begin
          Node := Sets[Key][Index];
          for First := 0 to Index - 1 do
          begin
            Earlier := Sets[Key][First];
            if TConditionalBranches.Implies(PathOf(Node), PathOf(Earlier)) then
            begin
              AReport.Add(NameRange(Node, Node.Name), Format('Marke %s ist bereits gesetzt (wie E2073).',
                [Node.Name]), TRuleConfidence.High);
              Break;
            end;
          end;
        end;
      // E2093: gesetzt oder angesprungen, aber in dieser Routine nicht deklariert.
      for Key in Sets.Keys do
        if not Declared.ContainsKey(Key) then
          for Node in Sets[Key] do
            AReport.Add(NameRange(Node, Node.Name), Format('Marke %s ist in dieser Routine nicht deklariert ' +
              '(wie E2093).', [Node.Name]), TRuleConfidence.High);
      for Node in Gotos do
      begin
        Key := LabelKey(Node.Name);
        if not Declared.ContainsKey(Key) then
        begin
          if not Sets.ContainsKey(Key) then
            AReport.Add(TTextRange.Create(Node.StartPos, Node.EndPos), Format('Marke %s ist in dieser Routine ' +
              'nicht deklariert (wie E2093).', [Node.Name]), TRuleConfidence.High);
          Continue;
        end;
        // E2127: goto in einen try-Block hinein oder aus ihm heraus; nur bei genau einem Ziel.
        if not Sets.ContainsKey(Key) or (Sets[Key].Count <> 1) then
          Continue;
        Target := Sets[Key][0];
        GotoChain := TryChain(Node, AScope);
        TargetChain := TryChain(Target, AScope);
        if (Length(GotoChain) = Length(TargetChain)) and IsPrefix(GotoChain, TargetChain) then
          Continue;
        // Gemeinsamer Anfang beider Ketten; der erste Block danach steht in der Meldung.
        First := 0;
        while (First < Length(GotoChain)) and (First < Length(TargetChain)) and
          (GotoChain[First] = TargetChain[First]) do
          Inc(First);
        if First = Length(GotoChain) then
          AReport.Add(TTextRange.Create(Node.StartPos, Node.EndPos), Format('goto %s springt in einen %s ' +
            '(wie E2127).', [Node.Name, BlockName(TargetChain[First])]), TRuleConfidence.High)
        else
          AReport.Add(TTextRange.Create(Node.StartPos, Node.EndPos), Format('goto %s verlässt einen %s ' +
            '(wie E2127).', [Node.Name, BlockName(GotoChain[First])]), TRuleConfidence.High);
      end;
      // E2074: deklariert und angesprungen, aber nie gesetzt.
      for Pair in Declared do
        if not Sets.ContainsKey(Pair.Key) then
          for Node in Gotos do
            if LabelKey(Node.Name) = Pair.Key then
            begin
              AReport.Add(TTextRange.Create(Tokens[Pair.Value].StartPos, Tokens[Pair.Value].EndPos), Format('Marke %s wird angesprungen, aber nie ' +
                'gesetzt (wie E2074).', [Tokens[Pair.Value].Text]), TRuleConfidence.High);
              Break;
            end;
    finally
      Gotos.Free;
      Sets.Free;
      Declared.Free;
    end;
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Index: Integer;
    Body: TSyntaxNode;
  begin
    if ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile] then
    begin
      Body := ANode.FindChild(TSyntaxKind.Block);
      if (Body <> nil) and not ParserBroken(AContext.Tree, ANode) then
        CheckScope(ANode, Body);
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index]);
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or
    not (ContainsText(AContext.Text, 'goto') or ContainsText(AContext.Text, 'label')) then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Paths := TConditionalBranches.Paths(Tokens);
  Visit(AContext.Tree.Root);
end;

procedure RegisterJumpRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TJumpOutsideAllowedScopeRule.Create);
  ARegistry.Register(TLabelMisuseRule.Create);
end;

end.
