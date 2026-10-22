unit Atlas.Common.Rules.Builtin.Loops;

// Regeln für Zählschleifen (#909, Gruppe Compiler vorab):
//   for-variable-misuse
//                     Die Variable einer for-Schleife wird im Rumpf zugewiesen
//                     oder mit Inc/Dec verändert (#1009, wie E2081), als
//                     var- bzw. out-Parameter an eine Routine dieser Datei
//                     übergeben (wie W1015) oder ist keine einfache lokale
//                     Variable: Feld der eigenen Klasse, globale Variable der
//                     Unit oder lokale Variable der umgebenden Routine (wie
//                     E1019). Parameter, unbekannte Namen und Schleifen in
//                     with-Anweisungen bleiben still, ebenso anonyme Methoden
//                     im Rumpf und Routinen mit Parserfehlern.
//                     Korrekturen: auf eine while-Schleife umstellen (nicht
//                     bei Continue im Rumpf) bzw. "for var" verwenden, wenn die
//                     Routine den Namen sonst nicht benutzt.
//   for-variable-after-loop
//                     Nach einer for-Schleife ist die Variable undefiniert,
//                     wenn die Schleife ohne Break endet (#1010, wie W1037).
//                     Vom normalen Ausgang der Schleife (Bedingungsknoten im
//                     Kontrollflussgraphen, Semantics.ControlFlow) folgt die
//                     Regel den Wegen bis zu einer Zuweisung; liest ein Knoten
//                     die Variable vorher sicher, meldet sie die Stelle. Eine
//                     unsichere Änderung (var-Argument, with, anonyme Methode)
//                     beendet den Weg ohne Meldung; Wege nur über mögliche
//                     Ausnahmen zählen nicht. Nur lokale Variablen der Routine,
//                     nicht for var. Korrektur wie oben: auf while umstellen,
//                     dann hat die Variable nach der Schleife einen Wert.

interface

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  ForVariableMisuseRuleId = 'for-variable-misuse';
  ForVariableAfterLoopRuleId = 'for-variable-after-loop';

type
  TForVariableMisuseRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TForVariableAfterLoopRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterLoopRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Semantics.ControlFlow,
  Atlas.Common.Rules.Derived;

type
  TNameSet = TDictionary<string, Boolean>;

/// <summary>Hat der Parser im Bereich von AScope einen Fehler gemeldet?</summary>
function ParserBroken(ATree: TSyntaxTree; AScope: TSyntaxNode): Boolean;
var
  Diagnostic: TSyntaxDiagnostic;
begin
  for Diagnostic in ATree.Diagnostics do
    if (Diagnostic.StartPos.Line >= AScope.StartPos.Line) and (Diagnostic.StartPos.Line <= AScope.EndPos.Line) then
      Exit(True);
  Result := False;
end;

/// <summary>Fügt die Namen "A,B" in ASet ein (klein).</summary>
procedure AddNames(ASet: TNameSet; const ANames: string);
var
  Part: string;
begin
  for Part in ANames.Split([',']) do
    if Trim(Part) <> '' then
      ASet.AddOrSetValue(LowerCase(Trim(Part)), True);
end;

/// <summary>Variablen der Abschnitte var direkt unter AOwner (Routine oder Unit-Abschnitt).</summary>
procedure AddVariables(ASet: TNameSet; AOwner: TSyntaxNode);
var
  Index, Item: Integer;
  Section: TSyntaxNode;
begin
  for Index := 0 to AOwner.ChildCount - 1 do
  begin
    Section := AOwner[Index];
    if Section.Kind = TSyntaxKind.VarSection then
      for Item := 0 to Section.ChildCount - 1 do
        if Section[Item].Kind = TSyntaxKind.VarDecl then
          AddNames(ASet, Section[Item].Name);
  end;
end;

/// <summary>Bezeichner ohne Kette (I, nicht Self.I oder X.I).</summary>
function IsPlainName(ANode: TSyntaxNode; const AName: string): Boolean;
begin
  Result := (ANode <> nil) and (ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, AName);
end;

function TokenAt(const ATokens: TArray<TPascalToken>; AOffset: Integer): Integer;
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

function NextCode(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= High(ATokens)) and (ATokens[Result].Kind in [TPascalTokenKind.Comment,
    TPascalTokenKind.Directive]) do
    Inc(Result);
end;

function PreviousCode(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and (ATokens[Result].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
    Dec(Result);
end;

function SourceOf(const AText: string; ANode: TSyntaxNode): string;
begin
  Result := Copy(AText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

// Leerraum am Anfang der Zeile, in der die Stelle AOffset (Spalte ACharacter) liegt.
function IndentAt(const AText: string; AOffset, ACharacter: Integer): string;
var
  LineStart, Index: Integer;
begin
  LineStart := AOffset - ACharacter;
  Index := LineStart + 1;
  while (Index <= AOffset) and CharInSet(AText[Index], [' ', #9]) do
    Inc(Index);
  Result := Copy(AText, LineStart + 1, Index - LineStart - 1);
end;

// Kommt im Rumpf ein Continue dieser Schleife vor (nicht in einer inneren Schleife)?
function HasOwnContinue(ANode: TSyntaxNode): Boolean;
var
  Index: Integer;
begin
  if ANode.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
    TSyntaxKind.RepeatStatement, TSyntaxKind.AnonymousMethod] then
    Exit(False);
  if (ANode.Kind = TSyntaxKind.CallStatement) and SameText(ANode.Name, 'Continue') then
    Exit(True);
  for Index := 0 to ANode.ChildCount - 1 do
    if HasOwnContinue(ANode[Index]) then
      Exit(True);
  Result := False;
end;

// Korrektur: for I := A to B do S wird I := A; while I <= B do begin S; Inc(I); end.
function WhileLoopFix(const AText: string; const ATokens: TArray<TPascalToken>; ALoop: TSyntaxNode;
  AInline: Boolean): TArray<TRuleFix>;
var
  StartExpr, StopExpr, Body, TypeRef: TSyntaxNode;
  DoToken, EndToken, Before, Index: Integer;
  Indent, Head, Step, Compare, LineBreak: string;
  Edits: TArray<TRuleEdit>;
begin
  Result := nil;
  if ALoop.ChildCount < 3 then
    Exit;
  StartExpr := ALoop[ALoop.ChildCount - 3];
  StopExpr := ALoop[ALoop.ChildCount - 2];
  Body := ALoop[ALoop.ChildCount - 1];
  TypeRef := ALoop.FindChild(TSyntaxKind.TypeReference);
  if HasOwnContinue(Body) then
    Exit;
  LineBreak := #10;
  if Pos(#13#10, AText) > 0 then
    LineBreak := #13#10;
  Compare := '<=';
  Step := 'Inc';
  for Index := TokenAt(ATokens, StartExpr.EndOffset) to TokenAt(ATokens, StopExpr.StartOffset) do
    if (Index <= High(ATokens)) and ATokens[Index].IsKeyword('downto') then
    begin
      Compare := '>=';
      Step := 'Dec';
    end;
  DoToken := PreviousCode(ATokens, TokenAt(ATokens, Body.StartOffset));
  if (DoToken < 0) or not ATokens[DoToken].IsKeyword('do') then
    Exit;
  Indent := IndentAt(AText, ALoop.StartOffset, ALoop.StartPos.Character);
  Head := ALoop.Name + ' := ' + SourceOf(AText, StartExpr) + ';';
  if AInline and (TypeRef <> nil) then
    Head := 'var ' + ALoop.Name + ': ' + SourceOf(AText, TypeRef) + ' := ' + SourceOf(AText, StartExpr) + ';'
  else if AInline then
    Head := 'var ' + Head;
  Head := Head + LineBreak + Indent + 'while ' + ALoop.Name + ' ' + Compare + ' ' + SourceOf(AText, StopExpr) + ' do';
  if Body.Kind = TSyntaxKind.Block then
  begin
    // Vor dem end des Blocks: Inc(I); fehlt das Semikolon nach der letzten Anweisung, kommt es dazu.
    EndToken := PreviousCode(ATokens, TokenAt(ATokens, Body.EndOffset));
    if (EndToken < 0) or not ATokens[EndToken].IsKeyword('end') then
      Exit;
    Edits := [TRuleEdit.Create(TTextRange.Create(ALoop.StartPos, ATokens[DoToken].EndPos), Head)];
    Before := PreviousCode(ATokens, EndToken);
    if (Before >= 0) and not ATokens[Before].IsSymbol(';') and not ATokens[Before].IsKeyword('begin') then
      Edits := Edits + [TRuleEdit.Create(TTextRange.Create(ATokens[Before].EndPos, ATokens[Before].EndPos), ';')];
    Edits := Edits + [TRuleEdit.Create(TTextRange.Create(ATokens[EndToken].StartPos, ATokens[EndToken].StartPos),
      '  ' + Step + '(' + ALoop.Name + ');' + LineBreak + IndentAt(AText, ATokens[EndToken].Offset,
      ATokens[EndToken].StartPos.Character))];
  end
  else
    Edits := [TRuleEdit.Create(TTextRange.Create(ALoop.StartPos, ATokens[DoToken].EndPos),
      Head + LineBreak + Indent + 'begin'),
      TRuleEdit.Create(TTextRange.Create(Body.EndPos, Body.EndPos), ';' + LineBreak + Indent + '  ' + Step + '(' +
      ALoop.Name + ');' + LineBreak + Indent + 'end')];
  Result := [TRuleFix.Create('Auf while-Schleife umstellen', Edits)];
end;

{ TForVariableMisuseRule }

function TForVariableMisuseRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(ForVariableMisuseRuleId, TRuleSeverity.Error,
    'Schleifenvariable verändert oder nicht lokal');
end;

procedure TForVariableMisuseRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Globals, Fields: TNameSet;
  VarRoutines: TDictionary<string, TArray<TArray<Boolean>>>;


  // Felder der Klassen dieser Datei (Typname klein -> Feldnamen) und Routinen mit var/out-Parametern.
  procedure CollectDeclarations(ANode: TSyntaxNode; const AClass: string);
  var
    Index, Item, Count: Integer;
    Child, Params: TSyntaxNode;
    Modes: TArray<Boolean>;
    Key: string;
    Known: TArray<TArray<Boolean>>;
  begin
    for Index := 0 to ANode.ChildCount - 1 do
    begin
      Child := ANode[Index];
      if (Child.Kind = TSyntaxKind.Field) and (AClass <> '') then
      begin
        for Key in Child.Name.Split([',']) do
          Fields.AddOrSetValue(AClass + '.' + LowerCase(Trim(Key)), True);
      end
      else if Child.Kind = TSyntaxKind.TypeDecl then
      begin
        CollectDeclarations(Child, LowerCase(Child.Name));
        Continue;
      end
      else if Child.Kind = TSyntaxKind.RoutineHeader then
      begin
        Params := Child.FindChild(TSyntaxKind.Parameters);
        Modes := nil;
        if Params <> nil then
          for Item := 0 to Params.ChildCount - 1 do
            if Params[Item].Kind = TSyntaxKind.Parameter then
              for Count := 1 to Length(Params[Item].Name.Split([','])) do
                Modes := Modes + [Params[Item].Modifier in [TParameterModifier.VarParam,
                  TParameterModifier.OutParam]];
        Key := LowerCase(Child.Name);
        if Pos('.', Key) > 0 then
          Key := Copy(Key, LastDelimiter('.', Key) + 1, MaxInt);
        if not VarRoutines.TryGetValue(Key, Known) then
          Known := nil;
        VarRoutines.AddOrSetValue(Key, Known + [Modes]);
      end;
      CollectDeclarations(Child, AClass);
    end;
  end;

  // Übergibt jede Deklaration von AName an der Stelle AArgument einen var- bzw. out-Parameter?
  function PassesByReference(const AName: string; AArgument: Integer): Boolean;
  var
    Known: TArray<TArray<Boolean>>;
    Modes: TArray<Boolean>;
  begin
    Result := False;
    if not VarRoutines.TryGetValue(LowerCase(AName), Known) then
      Exit;
    for Modes in Known do
      if (AArgument > High(Modes)) or not Modes[AArgument] then
        Exit(False);
    Result := True;
  end;


  // Meldungen im Rumpf: Zuweisung, Inc/Dec und var-Übergabe der Schleifenvariablen AName.
  procedure CheckBody(ANode, ALoop: TSyntaxNode; const AName: string; AInline: Boolean);
  var
    Index: Integer;
    Target, Call: TSyntaxNode;
    Name: string;
  begin
    // Anonyme Methoden laufen später, with kann den Namen umdeuten, eine innere Schleife mit demselben
    // Namen prüft der eigene Durchlauf.
    if (ANode.Kind in [TSyntaxKind.AnonymousMethod, TSyntaxKind.WithStatement]) or
      ((ANode.Kind = TSyntaxKind.ForStatement) and SameText(ANode.Name, AName)) then
      Exit;
    if (ANode.Kind = TSyntaxKind.AssignStatement) and (ANode.ChildCount > 0) and IsPlainName(ANode[0], AName) then
      AReport.Add(TTextRange.Create(ANode[0].StartPos, ANode[0].EndPos),
        Format('Schleifenvariable %s darf im Rumpf nicht zugewiesen werden (wie E2081).', [AName]),
        TRuleConfidence.High, WhileLoopFix(AContext.Text, Tokens, ALoop, AInline))
    else if (ANode.Kind = TSyntaxKind.CallStatement) and (ANode.ChildCount = 1) and
      (ANode[0].Kind = TSyntaxKind.Call) and (ANode[0].ChildCount > 1) and
      (ANode[0][0].Kind = TSyntaxKind.Identifier) then
    begin
      Call := ANode[0];
      Name := Call[0].Name;
      for Index := 1 to Call.ChildCount - 1 do
      begin
        Target := Call[Index];
        if not IsPlainName(Target, AName) then
          Continue;
        if (Index = 1) and (SameText(Name, 'Inc') or SameText(Name, 'Dec')) and not VarRoutines.ContainsKey('inc') and
          not VarRoutines.ContainsKey('dec') then
          AReport.Add(TTextRange.Create(Target.StartPos, Target.EndPos),
            Format('Schleifenvariable %s darf im Rumpf nicht verändert werden (wie E2081).', [AName]),
            TRuleConfidence.High, WhileLoopFix(AContext.Text, Tokens, ALoop, AInline))
        else if PassesByReference(Name, Index - 1) then
          AReport.Add(TTextRange.Create(Target.StartPos, Target.EndPos),
            Format('Schleifenvariable %s wird als var-Parameter an %s übergeben (wie W1015).', [AName, Name]),
            TRuleConfidence.High);
      end;
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      CheckBody(ANode[Index], ALoop, AName, AInline);
  end;

  // Kommt AName in ANode außerhalb von ALoop vor?
  function UsedOutside(ANode, ALoop: TSyntaxNode; const AName: string): Boolean;
  var
    Index: Integer;
  begin
    if ANode = ALoop then
      Exit(False);
    if (ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, AName) then
      Exit(True);
    for Index := 0 to ANode.ChildCount - 1 do
      if UsedOutside(ANode[Index], ALoop, AName) then
        Exit(True);
    Result := False;
  end;

  // Schleifen der Routine ARoutine (Rumpf ABody); AOuterLocals: Variablen der umgebenden Routinen.
  procedure CheckRoutine(ARoutine, ABody: TSyntaxNode; AOuterLocals: TNameSet; const AClass: string);
  var
    Locals: TNameSet;
    Header, Params: TSyntaxNode;
    Index: Integer;

    procedure CollectInline(ANode: TSyntaxNode);
    var
      Child: Integer;
    begin
      if ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
        Exit;
      if ANode.Kind in [TSyntaxKind.InlineVar, TSyntaxKind.InlineConst] then
        AddNames(Locals, ANode.Name);
      for Child := 0 to ANode.ChildCount - 1 do
        CollectInline(ANode[Child]);
    end;

    procedure VisitLoops(ANode: TSyntaxNode; AInWith: Boolean);
    var
      Child, ForToken: Integer;
      Name, Key, Kind: string;
      IsInline: Boolean;
      Fixes: TArray<TRuleFix>;
    begin
      if ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
        Exit;
      if ANode.Kind = TSyntaxKind.WithStatement then
        AInWith := True;
      if (ANode.Kind = TSyntaxKind.ForStatement) and (ANode.Name <> '') and not AInWith then
      begin
        Name := ANode.Name;
        // Erstes Code-Token nach for: var bei for var I, sonst der Name.
        ForToken := NextCode(Tokens, TokenAt(Tokens, ANode.StartOffset) + 1);
        IsInline := (ForToken <= High(Tokens)) and Tokens[ForToken].IsKeyword('var');
        Key := LowerCase(Name);
        if not IsInline and not Locals.ContainsKey(Key) then
        begin
          // Nicht lokal: lokale Variable einer umgebenden Routine, Feld der eigenen Klasse oder globale Variable.
          Kind := '';
          if AOuterLocals.ContainsKey(Key) then
            Kind := 'eine Variable der umgebenden Routine'
          else if (AClass <> '') and Fields.ContainsKey(AClass + '.' + Key) then
            Kind := 'ein Feld'
          else if Globals.ContainsKey(Key) then
            Kind := 'eine globale Variable';
          if Kind <> '' then
          begin
            Fixes := nil;
            if not UsedOutside(ABody, ANode, Name) then
              Fixes := [TRuleFix.Create('for var ' + Name + ' verwenden',
                [TRuleEdit.Create(TTextRange.Create(Tokens[ForToken].StartPos, Tokens[ForToken].StartPos), 'var ')])];
            AReport.Add(TTextRange.Create(Tokens[ForToken].StartPos, Tokens[ForToken].EndPos), Format('Schleifenvariable %s ist %s, keine einfache ' +
              'lokale Variable (wie E1019).', [Name, Kind]), TRuleConfidence.High, Fixes);
          end;
        end;
        if ANode.ChildCount > 0 then
          CheckBody(ANode[ANode.ChildCount - 1], ANode, Name, IsInline);
      end;
      for Child := 0 to ANode.ChildCount - 1 do
        VisitLoops(ANode[Child], AInWith);
    end;

  var
    Outer: TNameSet;
    Child: TSyntaxNode;
    Pair: TPair<string, Boolean>;
  begin
    Locals := TNameSet.Create;
    Outer := TNameSet.Create;
    try
      AddVariables(Locals, ARoutine);
      Header := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
      if Header <> nil then
      begin
        Params := Header.FindChild(TSyntaxKind.Parameters);
        if Params <> nil then
          for Index := 0 to Params.ChildCount - 1 do
            AddNames(Locals, Params[Index].Name);
      end;
      CollectInline(ABody);
      if not ParserBroken(AContext.Tree, ARoutine) then
        VisitLoops(ABody, False);
      // Lokale Routinen: deren umgebende Variablen sind diese plus die äußeren.
      for Pair in AOuterLocals do
        Outer.AddOrSetValue(Pair.Key, True);
      for Pair in Locals do
        Outer.AddOrSetValue(Pair.Key, True);
      for Index := 0 to ARoutine.ChildCount - 1 do
      begin
        Child := ARoutine[Index];
        if (Child.Kind = TSyntaxKind.RoutineDecl) and (Child.FindChild(TSyntaxKind.Block) <> nil) then
          CheckRoutine(Child, Child.FindChild(TSyntaxKind.Block), Outer, AClass);
      end;
    finally
      Outer.Free;
      Locals.Free;
    end;
  end;

  procedure VisitRoutines(ANode: TSyntaxNode);
  var
    Index: Integer;
    Body: TSyntaxNode;
    ClassName: string;
    NoOuter: TNameSet;
  begin
    for Index := 0 to ANode.ChildCount - 1 do
    begin
      Body := ANode[Index];
      if (Body.Kind = TSyntaxKind.RoutineDecl) and (Body.FindChild(TSyntaxKind.Block) <> nil) then
      begin
        ClassName := '';
        if Pos('.', Body.Name) > 0 then
          ClassName := LowerCase(Copy(Body.Name, 1, LastDelimiter('.', Body.Name) - 1));
        NoOuter := TNameSet.Create;
        try
          CheckRoutine(Body, Body.FindChild(TSyntaxKind.Block), NoOuter, ClassName);
        finally
          NoOuter.Free;
        end;
      end
      else if Body.Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection] then
        VisitRoutines(Body);
    end;
  end;

  procedure CollectGlobals(ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    AddVariables(Globals, ANode);
    for Index := 0 to ANode.ChildCount - 1 do
      if ANode[Index].Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection] then
        AddVariables(Globals, ANode[Index]);
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'for') then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Globals := TNameSet.Create;
  Fields := TNameSet.Create;
  VarRoutines := TDictionary<string, TArray<TArray<Boolean>>>.Create;
  try
    CollectGlobals(AContext.Tree.Root);
    CollectDeclarations(AContext.Tree.Root, '');
    VisitRoutines(AContext.Tree.Root);
  finally
    VarRoutines.Free;
    Fields.Free;
    Globals.Free;
  end;
end;

{ TForVariableAfterLoopRule }

function TForVariableAfterLoopRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(ForVariableAfterLoopRuleId, TRuleSeverity.Warning,
    'Schleifenvariable nach der Schleife gelesen');
end;

procedure TForVariableAfterLoopRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Cache: IRuleDerivedCache;
  Graph: TControlFlowGraph;
  Tokens: TArray<TPascalToken>;
  Reported: TDictionary<TSyntaxNode, Boolean>;

  function IsInside(ANode, AOuter: TSyntaxNode): Boolean;
  begin
    while (ANode <> nil) and (ANode <> AOuter) do
      ANode := ANode.Parent;
    Result := ANode <> nil;
  end;

  // Erster Bezeichner AName im Ausdrucksteil von ASyntax (nicht in eingebetteten Anweisungen oder anonymen
  // Methoden); nil ohne.
  function FindName(ASyntax: TSyntaxNode; const AName: string): TSyntaxNode;
  var
    Index: Integer;
  begin
    if ASyntax.Kind = TSyntaxKind.AnonymousMethod then
      Exit(nil);
    if (ASyntax.Kind = TSyntaxKind.Identifier) and SameText(ASyntax.Name, AName) then
      Exit(ASyntax);
    for Index := 0 to ASyntax.ChildCount - 1 do
      if not (ASyntax[Index].Kind in [TSyntaxKind.Block, TSyntaxKind.AssignStatement, TSyntaxKind.CallStatement,
        TSyntaxKind.IfStatement, TSyntaxKind.CaseStatement, TSyntaxKind.CaseItem, TSyntaxKind.CaseElse,
        TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
        TSyntaxKind.RepeatStatement, TSyntaxKind.WithStatement, TSyntaxKind.TryStatement,
        TSyntaxKind.RaiseStatement, TSyntaxKind.LabeledStatement]) then
      begin
        Result := FindName(ASyntax[Index], AName);
        if Result <> nil then
          Exit;
      end;
    Result := nil;
  end;

  procedure CheckLoop(ALoop: TSyntaxNode);
  var
    Condition, Node, Next: TFlowNode;
    Pending: TStack<TFlowNode>;
    Seen: TDictionary<TFlowNode, Boolean>;
    Name: string;
    Target: TSyntaxNode;
    Range: TTextRange;
  begin
    Condition := nil;
    for Node in Graph.Nodes do
      if (Node.Kind = TFlowNodeKind.Condition) and (Node.Syntax = ALoop) then
        Condition := Node;
    if (Condition = nil) or (Graph.IsReachable(Condition) <> TFlowAnswer.Yes) then
      Exit;
    Name := ALoop.Name;
    Pending := TStack<TFlowNode>.Create;
    Seen := TDictionary<TFlowNode, Boolean>.Create;
    try
      // Normaler Ausgang: Nachfolger der Bedingung außerhalb der Schleife.
      for Next in Condition.Successors do
        if (Next <> Condition) and ((Next.Syntax = nil) or not IsInside(Next.Syntax, ALoop)) then
          Pending.Push(Next);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Seen.ContainsKey(Node) then
          Continue;
        Seen.Add(Node, True);
        if SameText(Node.Defines, Name) or Node.TouchesName(Name) then
          Continue;
        if Node.ReadsName(Name) and (Node.Syntax <> nil) then
        begin
          Target := FindName(Node.Syntax, Name);
          if (Target <> nil) and not Reported.ContainsKey(Target) then
          begin
            Reported.Add(Target, True);
            Range := TTextRange.Create(Target.StartPos, Target.EndPos);
            AReport.Add(Range, Format('%s ist nach der Schleife undefiniert, wenn kein Break erreicht wurde ' +
              '(wie W1037).', [Name]), TRuleConfidence.High, WhileLoopFix(AContext.Text, Tokens, ALoop, False));
          end;
          Continue;
        end;
        for Next in Node.Successors do
          if not Node.IsImplicitRaiseEdge(Next) then
            Pending.Push(Next);
      end;
    finally
      Seen.Free;
      Pending.Free;
    end;
  end;

  procedure VisitLoops(ANode: TSyntaxNode; ALocals: TNameSet);
  var
    Index, ForToken: Integer;
  begin
    if ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
      Exit;
    if (ANode.Kind = TSyntaxKind.ForStatement) and ALocals.ContainsKey(LowerCase(ANode.Name)) then
    begin
      ForToken := NextCode(Tokens, TokenAt(Tokens, ANode.StartOffset) + 1);
      if (ForToken <= High(Tokens)) and not Tokens[ForToken].IsKeyword('var') then
        CheckLoop(ANode);
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      VisitLoops(ANode[Index], ALocals);
  end;

var
  Routine, Block: TSyntaxNode;
  Locals: TNameSet;
begin
  if (AContext.Tree = nil) or not ContainsText(AContext.Text, 'for') then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Cache := TRuleDerived.Open(AContext);
  Reported := TDictionary<TSyntaxNode, Boolean>.Create;
  Locals := TNameSet.Create;
  try
    for Routine in TRuleDerived.Routines(Cache, AContext) do
    begin
      Block := Routine.FindChild(TSyntaxKind.Block);
      if Block = nil then
        Continue;
      Locals.Clear;
      AddVariables(Locals, Routine);
      if Locals.Count = 0 then
        Continue;
      Graph := TRuleDerived.Graph(Cache, AContext, Routine);
      if (Graph = nil) or not Graph.Complete then
        Continue;
      VisitLoops(Block, Locals);
    end;
  finally
    Locals.Free;
    Reported.Free;
  end;
end;

procedure RegisterLoopRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TForVariableMisuseRule.Create);
  ARegistry.Register(TForVariableAfterLoopRule.Create);
end;

end.
