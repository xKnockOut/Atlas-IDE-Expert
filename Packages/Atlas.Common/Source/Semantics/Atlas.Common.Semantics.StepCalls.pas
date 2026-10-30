unit Atlas.Common.Semantics.StepCalls;

// Gezielt hineinspringen (#836), Teil ohne Index: die Anweisung am
// Ausführungspunkt, die Stellen, die einen Aufruf auslösen können, in
// Ausführungsreihenfolge, und die Zeile der Folgeanweisung.
//
// Anweisung: die äußerste, die in der Zeile beginnt (if A then B; zählt mit B),
// samt weiteren Anweisungen, die in derselben Zeile folgen (A; B;).
// Beginnt keine dort, gilt die innerste, die über die Zeile reicht; von einer
// zusammengesetzten Anweisung (if, while, repeat … until) dann nur die
// Ausdrücke, die die Zeile berühren (until-Bedingung, mehrzeilige Bedingung).
// Verschachtelte Anweisungen gehören dazu, wenn sie in der Startzeile ihrer
// umgebenden beginnen; Rümpfe in eigenen Zeilen haben eigene Zeilen im
// Debugger.
//
// Reihenfolge wie der Compiler sie auswertet: Empfänger vor dem Punkt, dann
// die Argumente von links nach rechts, dann der Aufruf selbst; bei einer
// Zuweisung erst die rechte Seite, dann der Empfänger links und zuletzt der
// Setter. Anonyme Methoden und @Routine rufen nichts auf.
// Welche Stelle wirklich ein Aufruf ist (Methode, Funktion, Getter, Setter)
// und nicht Variable, Feld oder Typumwandlung, entscheidet erst die
// Namensauflösung (Atlas.Common.Lsp.StepTargets).
//
// Folgeanweisung: die nächste Anweisung derselben Liste; am Ende einer Liste
// der Kopf der umgebenden Schleife, die until-Zeile, die erste Anweisung des
// finally-Teils oder das end der Routine; sonst eine Ebene höher. -1, wenn
// es keine gibt (Ende von initialization).

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  TStepCallSite = record
    /// <summary>Knoten der Stelle: Call, Identifier, MemberAccess, IndexAccess oder InheritedExpr.</summary>
    Node: TSyntaxNode;
    /// <summary>Name, den die Namensauflösung prüft (Identifier, MemberAccess, InheritedExpr); bei IndexAccess der
    /// indizierte Ausdruck.</summary>
    Callee: TSyntaxNode;
    /// <summary>Ausdruck vor dem Punkt (Kunde bei Kunde.Name); nil ohne.</summary>
    Receiver: TSyntaxNode;
    /// <summary>Linke Seite einer Zuweisung: Setter statt Getter.</summary>
    Assigned: Boolean;
    /// <summary>Mit Klammern geschrieben (Foo() bzw. Foo(X)).</summary>
    Explicit: Boolean;
  end;

  TStepStatement = record
    /// <summary>Gewählte Anweisung; nil ohne.</summary>
    Node: TSyntaxNode;
    Sites: TArray<TStepCallSite>;
    /// <summary>Zeile (ab 0) der Folgeanweisung; -1 ohne.</summary>
    FollowLine: Integer;
  end;

  TStepCalls = class
  public const
    StatementKinds = [TSyntaxKind.AssignStatement, TSyntaxKind.CallStatement, TSyntaxKind.IfStatement,
      TSyntaxKind.CaseStatement, TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
      TSyntaxKind.RepeatStatement, TSyntaxKind.WithStatement, TSyntaxKind.TryStatement, TSyntaxKind.RaiseStatement,
      TSyntaxKind.GotoStatement, TSyntaxKind.LabeledStatement, TSyntaxKind.InlineVar, TSyntaxKind.InlineConst];
    /// <summary>Anweisungen ohne eigene Unteranweisungen: Sie gelten immer ganz.</summary>
    SimpleKinds = [TSyntaxKind.AssignStatement, TSyntaxKind.CallStatement, TSyntaxKind.RaiseStatement,
      TSyntaxKind.GotoStatement, TSyntaxKind.InlineVar, TSyntaxKind.InlineConst];
    ExpressionKinds = [TSyntaxKind.Identifier, TSyntaxKind.Literal, TSyntaxKind.MemberAccess, TSyntaxKind.Call,
      TSyntaxKind.IndexAccess, TSyntaxKind.Dereference, TSyntaxKind.AddressOf, TSyntaxKind.GenericArgs,
      TSyntaxKind.SetConstructor, TSyntaxKind.BinaryExpr, TSyntaxKind.UnaryExpr, TSyntaxKind.ParenExpr,
      TSyntaxKind.InheritedExpr, TSyntaxKind.AnonymousMethod, TSyntaxKind.RangeExpr, TSyntaxKind.IfExpr];
  private
    class function IsGeneric(ANode: TSyntaxNode): Boolean; static;
    class procedure AddSite(var ASites: TArray<TStepCallSite>; ANode, ACallee: TSyntaxNode; AAssigned,
      AExplicit: Boolean); static;
    class procedure VisitReceiver(ACallee: TSyntaxNode; var ASites: TArray<TStepCallSite>); static;
    class procedure VisitTarget(ATarget: TSyntaxNode; var ASites: TArray<TStepCallSite>); static;
    class procedure CollectStatement(AStatement: TSyntaxNode; ALine: Integer; APartial: Boolean;
      var ASites: TArray<TStepCallSite>); static;
    class function NextStatement(ANode: TSyntaxNode): TSyntaxNode; static;
    class function FirstStatement(ANode: TSyntaxNode): TSyntaxNode; static;
  public
    /// <summary>Anweisung an der Zeile ALine (ab 0) samt Aufrufstellen und Folgezeile; False ohne Anweisung.
    /// </summary>
    class function Find(ATree: TSyntaxTree; ALine: Integer; out AStatement: TStepStatement): Boolean; static;
    /// <summary>Aufrufstellen des Ausdrucks ANode in Ausführungsreihenfolge (angehängt an ASites).</summary>
    class procedure Visit(ANode: TSyntaxNode; var ASites: TArray<TStepCallSite>); static;
    /// <summary>Zeile der Anweisung, die nach AStatement läuft; -1 ohne.</summary>
    class function FollowLine(AStatement: TSyntaxNode): Integer; static;
    /// <summary>Stelle des Namens, den die Namensauflösung für ACallee prüft: Bezeichner, Mitglied hinter dem
    /// Punkt, inherited. False ohne Namen (etwa bei einem Aufruf eines Aufrufergebnisses).</summary>
    class function NamePosition(ACallee: TSyntaxNode; out APosition: TTextPosition): Boolean; static;
    /// <summary>Empfänger vor dem Punkt von ACallee (ohne Typargumente); nil ohne.</summary>
    class function ReceiverOf(ACallee: TSyntaxNode): TSyntaxNode; static;
  end;

implementation

{ TStepCalls }

class function TStepCalls.IsGeneric(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode <> nil) and (ANode.Kind = TSyntaxKind.MemberAccess) and
    (ANode.FindChild(TSyntaxKind.GenericArgs) <> nil);
end;

class function TStepCalls.ReceiverOf(ACallee: TSyntaxNode): TSyntaxNode;
begin
  Result := nil;
  if (ACallee = nil) or (ACallee.Kind <> TSyntaxKind.MemberAccess) or (ACallee.ChildCount = 0) then
    Exit;
  if IsGeneric(ACallee) then
    Result := ReceiverOf(ACallee[0])
  else
    Result := ACallee[0];
end;

class function TStepCalls.NamePosition(ACallee: TSyntaxNode; out APosition: TTextPosition): Boolean;
begin
  Result := False;
  if ACallee = nil then
    Exit;
  case ACallee.Kind of
    TSyntaxKind.Identifier, TSyntaxKind.InheritedExpr:
      begin
        APosition := ACallee.StartPos;
        Result := True;
      end;
    TSyntaxKind.MemberAccess:
      if IsGeneric(ACallee) then
        Result := NamePosition(ACallee[0], APosition)
      else if (ACallee.Name <> '') and (ACallee.EndPos.Character >= Length(ACallee.Name)) then
      begin
        // Der Name steht am Ende des Knotens (A.B: B endet mit dem Knoten).
        APosition := TTextPosition.Create(ACallee.EndPos.Line, ACallee.EndPos.Character - Length(ACallee.Name));
        Result := True;
      end;
  else
    // Übrige Arten: nichts zu tun.
  end;
end;

class procedure TStepCalls.AddSite(var ASites: TArray<TStepCallSite>; ANode, ACallee: TSyntaxNode; AAssigned,
  AExplicit: Boolean);
var
  Site: TStepCallSite;
begin
  Site.Node := ANode;
  Site.Callee := ACallee;
  Site.Receiver := ReceiverOf(ACallee);
  Site.Assigned := AAssigned;
  Site.Explicit := AExplicit;
  ASites := ASites + [Site];
end;

class procedure TStepCalls.VisitReceiver(ACallee: TSyntaxNode; var ASites: TArray<TStepCallSite>);
begin
  if ACallee = nil then
    Exit;
  case ACallee.Kind of
    TSyntaxKind.Identifier, TSyntaxKind.InheritedExpr:
      ;
    TSyntaxKind.MemberAccess:
      if IsGeneric(ACallee) then
        VisitReceiver(ACallee[0], ASites)
      else if ACallee.ChildCount > 0 then
        Visit(ACallee[0], ASites);
  else
    Visit(ACallee, ASites);
  end;
end;

class procedure TStepCalls.Visit(ANode: TSyntaxNode; var ASites: TArray<TStepCallSite>);
var
  Index: Integer;
begin
  if ANode = nil then
    Exit;
  case ANode.Kind of
    TSyntaxKind.Call:
      begin
        if ANode.ChildCount = 0 then
          Exit;
        VisitReceiver(ANode[0], ASites);
        for Index := 1 to ANode.ChildCount - 1 do
          Visit(ANode[Index], ASites);
        AddSite(ASites, ANode, ANode[0], False, True);
      end;
    TSyntaxKind.Identifier, TSyntaxKind.InheritedExpr:
      AddSite(ASites, ANode, ANode, False, False);
    TSyntaxKind.MemberAccess:
      begin
        VisitReceiver(ANode, ASites);
        AddSite(ASites, ANode, ANode, False, False);
      end;
    TSyntaxKind.IndexAccess:
      begin
        if ANode.ChildCount = 0 then
          Exit;
        VisitReceiver(ANode[0], ASites);
        for Index := 1 to ANode.ChildCount - 1 do
          Visit(ANode[Index], ASites);
        // Liste[i] bzw. Kunde.Items[i]: Getter der indizierten oder der Default-Property.
        AddSite(ASites, ANode, ANode[0], False, False);
      end;
    // @Routine und anonyme Methoden rufen nichts auf; Typargumente auch nicht.
    TSyntaxKind.AddressOf, TSyntaxKind.AnonymousMethod, TSyntaxKind.Literal, TSyntaxKind.GenericArgs:
      ;
  else
    for Index := 0 to ANode.ChildCount - 1 do
      if ANode[Index].Kind in ExpressionKinds then
        Visit(ANode[Index], ASites);
  end;
end;

class procedure TStepCalls.VisitTarget(ATarget: TSyntaxNode; var ASites: TArray<TStepCallSite>);
var
  Index: Integer;
begin
  case ATarget.Kind of
    TSyntaxKind.Identifier:
      AddSite(ASites, ATarget, ATarget, True, False);
    TSyntaxKind.MemberAccess:
      begin
        VisitReceiver(ATarget, ASites);
        AddSite(ASites, ATarget, ATarget, True, False);
      end;
    TSyntaxKind.IndexAccess:
      if ATarget.ChildCount > 0 then
      begin
        VisitReceiver(ATarget[0], ASites);
        for Index := 1 to ATarget.ChildCount - 1 do
          Visit(ATarget[Index], ASites);
        AddSite(ASites, ATarget, ATarget[0], True, False);
      end;
  else
    // P^.X := …, (A as TB).C := …: nur die Aufrufe darin.
    Visit(ATarget, ASites);
  end;
end;

class procedure TStepCalls.CollectStatement(AStatement: TSyntaxNode; ALine: Integer; APartial: Boolean;
  var ASites: TArray<TStepCallSite>);
var
  Index: Integer;
  Child: TSyntaxNode;
begin
  if AStatement.Kind = TSyntaxKind.AssignStatement then
  begin
    // Rechte Seite zuerst, dann das Ziel (Empfänger, Setter).
    if AStatement.ChildCount > 1 then
      Visit(AStatement[1], ASites);
    if AStatement.ChildCount > 0 then
      VisitTarget(AStatement[0], ASites);
    Exit;
  end;
  for Index := 0 to AStatement.ChildCount - 1 do
  begin
    Child := AStatement[Index];
    if Child.Kind in ExpressionKinds then
    begin
      if not APartial or ((Child.StartPos.Line <= ALine) and (Child.EndPos.Line >= ALine)) then
        Visit(Child, ASites);
    end
    else if APartial then
      Continue
    else if Child.Kind in StatementKinds then
    begin
      // Nur, was in derselben Zeile beginnt: if A then B; zählt B mit.
      if Child.StartPos.Line = AStatement.StartPos.Line then
        CollectStatement(Child, ALine, False, ASites);
    end
    else if Child.Kind in [TSyntaxKind.Block, TSyntaxKind.CaseItem, TSyntaxKind.CaseElse, TSyntaxKind.ExceptBlock,
      TSyntaxKind.FinallyBlock, TSyntaxKind.ExceptionHandler] then
    begin
      if Child.StartPos.Line = AStatement.StartPos.Line then
        CollectStatement(Child, ALine, False, ASites);
    end;
  end;
end;

class function TStepCalls.Find(ATree: TSyntaxTree; ALine: Integer; out AStatement: TStepStatement): Boolean;
var
  Starting, Containing: TSyntaxNode;
begin
  AStatement := Default(TStepStatement);
  AStatement.FollowLine := -1;
  Result := False;
  if (ATree = nil) or (ATree.Root = nil) then
    Exit;
  Starting := nil;
  Containing := nil;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := (ANode.StartPos.Line <= ALine) and (ANode.EndPos.Line >= ALine);
      if not Result then
        Exit;
      if ANode.Kind in StatementKinds then
      begin
        // Vorordnung: Die erste, die in der Zeile beginnt, ist die äußerste.
        if (Starting = nil) and (ANode.StartPos.Line = ALine) then
          Starting := ANode;
        Containing := ANode;
      end;
    end);
  if Starting <> nil then
  begin
    AStatement.Node := Starting;
    CollectStatement(Starting, ALine, False, AStatement.Sites);
    // Weitere Anweisungen derselben Zeile (A; B;) laufen im selben Schritt.
    Containing := NextStatement(Starting);
    while (Containing <> nil) and (Containing.StartPos.Line = ALine) do
    begin
      CollectStatement(Containing, ALine, False, AStatement.Sites);
      Starting := Containing;
      Containing := NextStatement(Starting);
    end;
    AStatement.FollowLine := FollowLine(Starting);
    Exit(True);
  end
  else if Containing <> nil then
  begin
    AStatement.Node := Containing;
    CollectStatement(Containing, ALine, not (Containing.Kind in SimpleKinds), AStatement.Sites);
  end
  else
    Exit;
  AStatement.FollowLine := FollowLine(AStatement.Node);
  Result := True;
end;

class function TStepCalls.FirstStatement(ANode: TSyntaxNode): TSyntaxNode;
var
  Index: Integer;
begin
  Result := nil;
  for Index := 0 to ANode.ChildCount - 1 do
    if ANode[Index].Kind in StatementKinds then
      Exit(ANode[Index])
    else if ANode[Index].Kind = TSyntaxKind.Block then
    begin
      Result := FirstStatement(ANode[Index]);
      if Result <> nil then
        Exit;
    end;
end;

class function TStepCalls.NextStatement(ANode: TSyntaxNode): TSyntaxNode;
var
  Parent: TSyntaxNode;
  Index, Own: Integer;
begin
  Result := nil;
  Parent := ANode.Parent;
  if Parent = nil then
    Exit;
  Own := -1;
  for Index := 0 to Parent.ChildCount - 1 do
    if Parent[Index] = ANode then
    begin
      Own := Index;
      Break;
    end;
  if Own < 0 then
    Exit;
  for Index := Own + 1 to Parent.ChildCount - 1 do
    if Parent[Index].Kind in StatementKinds then
      Exit(Parent[Index])
    else if Parent[Index].Kind = TSyntaxKind.Block then
    begin
      // begin … end als Anweisung: seine erste Anweisung, sonst weiter.
      Result := FirstStatement(Parent[Index]);
      if Result <> nil then
        Exit;
    end;
end;

class function TStepCalls.FollowLine(AStatement: TSyntaxNode): Integer;
var
  Current, Parent, Next, Part: TSyntaxNode;
begin
  Result := -1;
  Current := AStatement;
  while (Current <> nil) and (Current.Parent <> nil) do
  begin
    Parent := Current.Parent;
    case Parent.Kind of
      TSyntaxKind.WhileStatement, TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement:
        // Ende des Rumpfs: Die Schleife prüft wieder im Kopf.
        Exit(Parent.StartPos.Line);
      TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod:
        Exit;
    else
      // Übrige Arten: nichts zu tun.
    end;
    Next := NextStatement(Current);
    if Next <> nil then
      Exit(Next.StartPos.Line);
    case Parent.Kind of
      TSyntaxKind.Block:
        if (Parent.Parent <> nil) and (Parent.Parent.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod])
        then
          // Ende der Routine: Ihr end trägt Code (Aufräumen, Rücksprung).
          Exit(Parent.EndPos.Line);
      TSyntaxKind.RepeatStatement:
        if (Parent.ChildCount > 0) and (Parent[Parent.ChildCount - 1].Kind in ExpressionKinds) then
          Exit(Parent[Parent.ChildCount - 1].StartPos.Line);
      TSyntaxKind.TryStatement:
        begin
          // Ende des try-Teils: Der finally-Teil läuft als Nächstes.
          Part := Parent.FindChild(TSyntaxKind.FinallyBlock);
          if (Part <> nil) and (Current.Kind <> TSyntaxKind.FinallyBlock) then
          begin
            Next := FirstStatement(Part);
            if Next <> nil then
              Exit(Next.StartPos.Line);
          end;
        end;
      TSyntaxKind.InitializationSection, TSyntaxKind.FinalizationSection:
        Exit;
    else
      // Übrige Arten: nichts zu tun.
    end;
    Current := Parent;
  end;
end;

end.
