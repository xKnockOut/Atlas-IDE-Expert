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

type
  /// <summary>Eintrag des eigenen Stapels von TJumpOutsideAllowedScopeRule.Check (Bericht M1): Knoten samt
  /// Zustand der umschließenden Sprunggrenze.</summary>
  TJumpVisit = record
    Node: TSyntaxNode;
    Scope: TSyntaxNode;
    HasLoop: Boolean;
    FinallySinceLoop: Boolean;
    InFinally: Boolean;
  end;

  /// <summary>Gesetzte Marken einer Routine je Schlüssel (TLabelMisuseRule.LabelKey).</summary>
  TLabelSets = TObjectDictionary<string, TList<TSyntaxNode>>;

/// <summary>Hat der Parser im Bereich von AScope einen Fehler gemeldet (nil: irgendwo)? Dann ist die
/// Schachtelung dort nicht sicher. Meldungen der Prüfungen am fertigen Baum (TreeIntact, z. B. E2031)
/// zählen nicht: Der Baum ist dort vollständig.</summary>
function ParserBroken(ATree: TSyntaxTree; AScope: TSyntaxNode): Boolean;
var
  Diagnostic: TSyntaxDiagnostic;
begin
  for Diagnostic in ATree.Diagnostics do
  begin
    if not Diagnostic.TreeIntact and ((AScope = nil) or ((Diagnostic.StartPos.Line >= AScope.StartPos.Line) and
      (Diagnostic.StartPos.Line <= AScope.EndPos.Line))) then
    begin
      Exit(True);
    end;
  end;
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
      begin
        for Part in ANode.Name.Split([',', '.']) do
        begin
          Names.AddOrSetValue(LowerCase(Trim(Part)), True);
        end;
      end;
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
  begin
    Exit;
  end;
  Target := AStatement[0];
  if (Target.Kind = TSyntaxKind.Call) and (Target.ChildCount > 0) then
  begin
    Target := Target[0];
  end;
  if Target.Kind = TSyntaxKind.Identifier then
  begin
    Result := LowerCase(Target.Name);
  end;
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
    begin
      Exit;
    end;
    Range := TTextRange.Create(AStatement.StartPos,
      TTextPosition.Create(AStatement.StartPos.Line, AStatement.StartPos.Character + Length(AName)));
    Fixes := nil;
    if AWithFix then
    begin
      Fixes := [TRuleFix.Create('Break durch Exit ersetzen', [TRuleEdit.Create(Range, 'Exit')])];
    end;
    AReport.Add(Range, AMessage, TRuleConfidence.High, Fixes);
  end;

  /// <summary>Zustand AEntry für den Knoten ANode nachführen: neue Sprunggrenze, Schleife oder finally.</summary>
  procedure Enter(var AEntry: TJumpVisit; ANode: TSyntaxNode);
  begin
    if IsJumpScope(ANode) then
    begin
      AEntry.Scope := ANode;
      AEntry.HasLoop := False;
      AEntry.FinallySinceLoop := False;
      AEntry.InFinally := False;
    end
    else if IsLoop(ANode) then
    begin
      AEntry.HasLoop := True;
      AEntry.FinallySinceLoop := False;
    end
    else if ANode.Kind = TSyntaxKind.FinallyBlock then
    begin
      AEntry.FinallySinceLoop := True;
      AEntry.InFinally := True;
    end;
  end;

  /// <summary>Break, Continue oder Exit als Anweisung ANode mit dem Zustand AEntry prüfen.</summary>
  procedure CheckCall(ANode: TSyntaxNode; const AEntry: TJumpVisit);
  var
    mName, mWritten: string;
  begin
    mName := PlainCallName(ANode);
    if not MatchStr(mName, ['break', 'continue', 'exit']) or Declared.ContainsKey(mName) then
    begin
      Exit;
    end;
    mWritten := Copy(AContext.Text, ANode.StartOffset + 1, Length(mName));
    if (mName <> 'exit') and not AEntry.HasLoop then
    begin
      Report(ANode, AEntry.Scope, mName, Format('%s außerhalb einer Schleife (wie E2097).', [mWritten]),
        (mName = 'break') and not AEntry.InFinally);
    end
    else if ((mName <> 'exit') and AEntry.FinallySinceLoop) or ((mName = 'exit') and AEntry.InFinally) then
    begin
      Report(ANode, AEntry.Scope, mName, Format('%s darf einen finally-Block nicht verlassen (wie E2126).',
        [mWritten]), False);
    end;
  end;

  // AHasLoop: eine Schleife umschließt die Stelle in derselben Routine; AFinallySinceLoop: zwischen ihr und der
  // Stelle liegt ein finally; AInFinally: irgendein finally der Routine umschließt die Stelle.
  // Iterativ (Bericht M1): der Stapel trägt den Zustand je Knoten mit, wie zuvor die Parameter der Rekursion.
  procedure Visit(ARoot: TSyntaxNode);
  var
    mPending: TStack<TJumpVisit>;
    mEntry, mChildEntry: TJumpVisit;
    mNode: TSyntaxNode;
    mIndex: Integer;
  begin
    mPending := TStack<TJumpVisit>.Create;
    try
      mEntry := Default(TJumpVisit);
      mEntry.Node := ARoot;
      mPending.Push(mEntry);
      while mPending.Count > 0 do
      begin
        mEntry := mPending.Pop;
        mNode := mEntry.Node;
        Enter(mEntry, mNode);
        if mNode.Kind = TSyntaxKind.CallStatement then
        begin
          CheckCall(mNode, mEntry);
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mChildEntry := mEntry;
          mChildEntry.Node := mNode[mIndex];
          mPending.Push(mChildEntry);
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
  Declared := DeclaredNames(AContext.Tree.Root);
  try
    Visit(AContext.Tree.Root);
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
  begin
    Result := IntToStr(Number);
  end
  else
  begin
    Result := LowerCase(AName);
  end;
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
      begin
        Low := Middle + 1;
      end
      else
      begin
        High := Middle;
      end;
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
      begin
        Result := [Node] + Result;
      end;
      Node := Node.Parent;
    end;
  end;

  // Ist AOuter ein Anfangsstück von AInner?
  function IsPrefix(const AOuter, AInner: TArray<TSyntaxNode>): Boolean;
  var
    Index: Integer;
  begin
    if Length(AOuter) > Length(AInner) then
    begin
      Exit(False);
    end;
    for Index := 0 to High(AOuter) do
    begin
      if AOuter[Index] <> AInner[Index] then
      begin
        Exit(False);
      end;
    end;
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

  /// <summary>Token der Marken im label-Abschnitt ASection (bis zum Semikolon) an AProc übergeben; endet,
  /// sobald AProc True liefert.</summary>
  function ForEachLabel(ASection: TSyntaxNode; const AProc: TFunc<Integer, Boolean>): Boolean;
  var
    mToken: Integer;
  begin
    mToken := TokenAt(ASection.StartOffset) + 1;
    while (mToken <= High(Tokens)) and (Tokens[mToken].Offset < ASection.EndOffset) and
      not Tokens[mToken].IsSymbol(';') do
    begin
      if (Tokens[mToken].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Number]) and AProc(mToken) then
      begin
        Exit(True);
      end;
      Inc(mToken);
    end;
    Result := False;
  end;

  /// <summary>Deklariert der label-Abschnitt ASection die Marke AKey?</summary>
  function SectionDeclares(ASection: TSyntaxNode; const AKey: string): Boolean;
  begin
    Result := ForEachLabel(ASection,
      function(AToken: Integer): Boolean
      begin
        Result := LabelKey(Tokens[AToken].Text) = AKey;
      end);
  end;

  /// <summary>Deklariert die Routine ARoutine in einem label-Abschnitt die Marke AKey?</summary>
  function RoutineDeclares(ARoutine: TSyntaxNode; const AKey: string): Boolean;
  var
    mIndex: Integer;
  begin
    for mIndex := 0 to ARoutine.ChildCount - 1 do
    begin
      if (ARoutine[mIndex].Kind = TSyntaxKind.LabelSection) and SectionDeclares(ARoutine[mIndex], AKey) then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  // Ist AKey in einer Routine deklariert, die AScope umgibt? Sonst meldet die Syntaxprüfung den Sprung (E2031).
  function DeclaredOutside(AScope: TSyntaxNode; const AKey: string): Boolean;
  var
    mOuter: TSyntaxNode;
  begin
    mOuter := AScope.Parent;
    while mOuter <> nil do
    begin
      if (mOuter.Kind = TSyntaxKind.RoutineDecl) and RoutineDeclares(mOuter, AKey) then
      begin
        Exit(True);
      end;
      mOuter := mOuter.Parent;
    end;
    Result := False;
  end;

  /// <summary>label A, B, 10; in den Deklarationen der Routine AScope: Schlüssel und Token der Marke.</summary>
  procedure CollectDeclared(AScope: TSyntaxNode; ADeclared: TDictionary<string, Integer>);
  var
    mIndex: Integer;
  begin
    for mIndex := 0 to AScope.ChildCount - 1 do
    begin
      if AScope[mIndex].Kind = TSyntaxKind.LabelSection then
      begin
        ForEachLabel(AScope[mIndex],
          function(AToken: Integer): Boolean
          begin
            ADeclared.AddOrSetValue(LabelKey(Tokens[AToken].Text), AToken);
            Result := False;
          end);
      end;
    end;
  end;

  procedure AddSet(ASets: TLabelSets; ANode: TSyntaxNode);
  var
    mName: string;
    mList: TList<TSyntaxNode>;
  begin
    mName := LabelKey(ANode.Name);
    if not ASets.TryGetValue(mName, mList) then
    begin
      mList := TList<TSyntaxNode>.Create;
      ASets.Add(mName, mList);
    end;
    mList.Add(ANode);
  end;

  /// <summary>Gesetzte Marken und goto-Anweisungen unter ARoot; False, wenn ein asm-Block vorkommt (dessen
  /// Marken sieht der Baum nicht). Iterativ (Bericht M1).</summary>
  function Collect(ARoot: TSyntaxNode; ASets: TLabelSets; AGotos: TList<TSyntaxNode>): Boolean;
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mChild: Integer;
  begin
    Result := True;
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        // Verschachtelte Routinen und anonyme Methoden haben eigene Marken.
        if mNode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
        begin
          Continue;
        end;
        case mNode.Kind of
          TSyntaxKind.AsmBlock:
            Result := False;
          TSyntaxKind.LabeledStatement:
            AddSet(ASets, mNode);
          TSyntaxKind.GotoStatement:
            if mNode.Name <> '' then
            begin
              AGotos.Add(mNode);
            end;
        else
          // Übrige Knoten setzen keine Marke.
        end;
        for mChild := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mChild]);
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

  /// <summary>Wird die Marke in AList an AIndex nie ohne eine frühere übersetzt?</summary>
  function SetEarlier(AList: TList<TSyntaxNode>; AIndex: Integer): Boolean;
  var
    mFirst: Integer;
  begin
    for mFirst := 0 to AIndex - 1 do
    begin
      if TConditionalBranches.Implies(PathOf(AList[AIndex]), PathOf(AList[mFirst])) then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  /// <summary>E2073: dieselbe Marke zweimal gesetzt, wenn die spätere nie ohne die frühere übersetzt wird;
  /// E2093: gesetzt, aber in dieser Routine nicht deklariert.</summary>
  procedure CheckSets(ASets: TLabelSets; ADeclared: TDictionary<string, Integer>);
  var
    mKey: string;
    mIndex: Integer;
    mNode: TSyntaxNode;
  begin
    for mKey in ASets.Keys do
    begin
      for mIndex := 1 to ASets[mKey].Count - 1 do
      begin
        mNode := ASets[mKey][mIndex];
        if SetEarlier(ASets[mKey], mIndex) then
        begin
          AReport.Add(NameRange(mNode, mNode.Name), Format('Marke %s ist bereits gesetzt (wie E2073).',
            [mNode.Name]), TRuleConfidence.High);
        end;
      end;
    end;
    for mKey in ASets.Keys do
    begin
      if ADeclared.ContainsKey(mKey) then
      begin
        Continue;
      end;
      for mNode in ASets[mKey] do
      begin
        AReport.Add(NameRange(mNode, mNode.Name), Format('Marke %s ist in dieser Routine nicht deklariert ' +
          '(wie E2093).', [mNode.Name]), TRuleConfidence.High);
      end;
    end;
  end;

  /// <summary>Länge des gemeinsamen Anfangs der Ketten AGotoChain und ATargetChain.</summary>
  function CommonLength(const AGotoChain, ATargetChain: TArray<TSyntaxNode>): Integer;
  begin
    Result := 0;
    while (Result < Length(AGotoChain)) and (Result < Length(ATargetChain)) and
      (AGotoChain[Result] = ATargetChain[Result]) do
    begin
      Inc(Result);
    end;
  end;

  /// <summary>E2127: goto ANode in einen try-Block hinein oder aus ihm heraus zum Ziel ATarget.</summary>
  procedure CheckTryJump(AScope, ANode, ATarget: TSyntaxNode);
  var
    mGotoChain, mTargetChain: TArray<TSyntaxNode>;
    mFirst: Integer;
  begin
    mGotoChain := TryChain(ANode, AScope);
    mTargetChain := TryChain(ATarget, AScope);
    if (Length(mGotoChain) = Length(mTargetChain)) and IsPrefix(mGotoChain, mTargetChain) then
    begin
      Exit;
    end;
    // Gemeinsamer Anfang beider Ketten; der erste Block danach steht in der Meldung.
    mFirst := CommonLength(mGotoChain, mTargetChain);
    if mFirst = Length(mGotoChain) then
    begin
      AReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), Format('goto %s springt in einen %s ' +
        '(wie E2127).', [ANode.Name, BlockName(mTargetChain[mFirst])]), TRuleConfidence.High);
    end
    else
    begin
      AReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), Format('goto %s verlässt einen %s ' +
        '(wie E2127).', [ANode.Name, BlockName(mGotoChain[mFirst])]), TRuleConfidence.High);
    end;
  end;

  procedure CheckGoto(AScope, ANode: TSyntaxNode; ASets: TLabelSets; ADeclared: TDictionary<string, Integer>);
  var
    mKey: string;
  begin
    mKey := LabelKey(ANode.Name);
    if not ADeclared.ContainsKey(mKey) then
    begin
      // Nirgends deklariert und nirgends gesetzt: das meldet schon die Syntaxprüfung (E2031).
      if not ASets.ContainsKey(mKey) and DeclaredOutside(AScope, mKey) then
      begin
        AReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), Format('Marke %s ist in dieser Routine ' +
          'nicht deklariert (wie E2093).', [ANode.Name]), TRuleConfidence.High);
      end;
    end
    // E2127 nur bei genau einem Ziel.
    else if ASets.ContainsKey(mKey) and (ASets[mKey].Count = 1) then
    begin
      CheckTryJump(AScope, ANode, ASets[mKey][0]);
    end;
  end;

  /// <summary>Springt eine goto-Anweisung aus AGotos die Marke AKey an?</summary>
  function Jumped(AGotos: TList<TSyntaxNode>; const AKey: string): Boolean;
  var
    mNode: TSyntaxNode;
  begin
    for mNode in AGotos do
    begin
      if LabelKey(mNode.Name) = AKey then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  /// <summary>E2074: deklariert und angesprungen, aber nie gesetzt.</summary>
  procedure CheckNeverSet(ASets: TLabelSets; ADeclared: TDictionary<string, Integer>; AGotos: TList<TSyntaxNode>);
  var
    mPair: TPair<string, Integer>;
  begin
    for mPair in ADeclared do
    begin
      if not ASets.ContainsKey(mPair.Key) and Jumped(AGotos, mPair.Key) then
      begin
        AReport.Add(TTextRange.Create(Tokens[mPair.Value].StartPos, Tokens[mPair.Value].EndPos),
          Format('Marke %s wird angesprungen, aber nie gesetzt (wie E2074).', [Tokens[mPair.Value].Text]),
          TRuleConfidence.High);
      end;
    end;
  end;

  procedure CheckScope(AScope, ABody: TSyntaxNode);
  var
    mDeclared: TDictionary<string, Integer>;
    mSets: TLabelSets;
    mGotos: TList<TSyntaxNode>;
    mNode: TSyntaxNode;
  begin
    mDeclared := TDictionary<string, Integer>.Create;
    mSets := TLabelSets.Create([doOwnsValues]);
    mGotos := TList<TSyntaxNode>.Create;
    try
      CollectDeclared(AScope, mDeclared);
      // Marken im asm-Block sieht der Baum nicht.
      if not Collect(ABody, mSets, mGotos) then
      begin
        Exit;
      end;
      CheckSets(mSets, mDeclared);
      for mNode in mGotos do
      begin
        CheckGoto(AScope, mNode, mSets, mDeclared);
      end;
      CheckNeverSet(mSets, mDeclared, mGotos);
    finally
      mGotos.Free;
      mSets.Free;
      mDeclared.Free;
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
        if Node.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile] then
        begin
          Body := Node.FindChild(TSyntaxKind.Block);
          if (Body <> nil) and not ParserBroken(AContext.Tree, Node) then
          begin
            CheckScope(Node, Body);
          end;
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
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or
    not (ContainsText(AContext.Text, 'goto') or ContainsText(AContext.Text, 'label')) then
  begin
    Exit;
  end;
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
