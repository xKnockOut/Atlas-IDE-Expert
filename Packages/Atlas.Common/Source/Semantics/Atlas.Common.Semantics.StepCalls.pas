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
    cStatementKinds = [TSyntaxKind.AssignStatement, TSyntaxKind.CallStatement, TSyntaxKind.IfStatement,
      TSyntaxKind.CaseStatement, TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
      TSyntaxKind.RepeatStatement, TSyntaxKind.WithStatement, TSyntaxKind.TryStatement, TSyntaxKind.RaiseStatement,
      TSyntaxKind.GotoStatement, TSyntaxKind.LabeledStatement, TSyntaxKind.InlineVar, TSyntaxKind.InlineConst];
    /// <summary>Anweisungen ohne eigene Unteranweisungen: Sie gelten immer ganz.</summary>
    cSimpleKinds = [TSyntaxKind.AssignStatement, TSyntaxKind.CallStatement, TSyntaxKind.RaiseStatement,
      TSyntaxKind.GotoStatement, TSyntaxKind.InlineVar, TSyntaxKind.InlineConst];
    cExpressionKinds = [TSyntaxKind.Identifier, TSyntaxKind.Literal, TSyntaxKind.MemberAccess, TSyntaxKind.Call,
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
  begin
    Exit;
  end;
  if IsGeneric(ACallee) then
  begin
    Result := ReceiverOf(ACallee[0]);
  end
  else
  begin
    Result := ACallee[0];
  end;
end;

class function TStepCalls.NamePosition(ACallee: TSyntaxNode; out APosition: TTextPosition): Boolean;
begin
  Result := False;
  if ACallee = nil then
  begin
    Exit;
  end;
  case ACallee.Kind of
    TSyntaxKind.Identifier, TSyntaxKind.InheritedExpr:
      begin
        APosition := ACallee.StartPos;
        Result := True;
      end;
    TSyntaxKind.MemberAccess:
      if IsGeneric(ACallee) then
      begin
        Result := NamePosition(ACallee[0], APosition);
      end
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
  mSite: TStepCallSite;
begin
  mSite.Node := ANode;
  mSite.Callee := ACallee;
  mSite.Receiver := ReceiverOf(ACallee);
  mSite.Assigned := AAssigned;
  mSite.Explicit := AExplicit;
  ASites := ASites + [mSite];
end;

class procedure TStepCalls.VisitReceiver(ACallee: TSyntaxNode; var ASites: TArray<TStepCallSite>);
begin
  if ACallee = nil then
  begin
    Exit;
  end;
  case ACallee.Kind of
    TSyntaxKind.Identifier, TSyntaxKind.InheritedExpr:
      ;
    TSyntaxKind.MemberAccess:
      if IsGeneric(ACallee) then
      begin
        VisitReceiver(ACallee[0], ASites);
      end
      else if ACallee.ChildCount > 0 then
      begin
        Visit(ACallee[0], ASites);
      end;
  else
    Visit(ACallee, ASites);
  end;
end;

class procedure TStepCalls.Visit(ANode: TSyntaxNode; var ASites: TArray<TStepCallSite>);
var
  mIndex: Integer;
begin
  if ANode = nil then
  begin
    Exit;
  end;
  case ANode.Kind of
    TSyntaxKind.Call:
      begin
        if ANode.ChildCount = 0 then
        begin
          Exit;
        end;
        VisitReceiver(ANode[0], ASites);
        for mIndex := 1 to ANode.ChildCount - 1 do
        begin
          Visit(ANode[mIndex], ASites);
        end;
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
        begin
          Exit;
        end;
        VisitReceiver(ANode[0], ASites);
        for mIndex := 1 to ANode.ChildCount - 1 do
        begin
          Visit(ANode[mIndex], ASites);
        end;
        // Liste[i] bzw. Kunde.Items[i]: Getter der indizierten oder der Default-Property.
        AddSite(ASites, ANode, ANode[0], False, False);
      end;
    // @Routine und anonyme Methoden rufen nichts auf; Typargumente auch nicht.
    TSyntaxKind.AddressOf, TSyntaxKind.AnonymousMethod, TSyntaxKind.Literal, TSyntaxKind.GenericArgs:
      ;
  else
    for mIndex := 0 to ANode.ChildCount - 1 do
    begin
      if ANode[mIndex].Kind in cExpressionKinds then
      begin
        Visit(ANode[mIndex], ASites);
      end;
    end;
  end;
end;

class procedure TStepCalls.VisitTarget(ATarget: TSyntaxNode; var ASites: TArray<TStepCallSite>);
var
  mIndex: Integer;
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
        for mIndex := 1 to ATarget.ChildCount - 1 do
        begin
          Visit(ATarget[mIndex], ASites);
        end;
        AddSite(ASites, ATarget, ATarget[0], True, False);
      end;
  else
    // P^.X := …, (A as TB).C := …: nur die Aufrufe darin.
    Visit(ATarget, ASites);
  end;
end;

const
  // Teile einer Anweisung, die selbst Anweisungen enthalten.
  cNestedKinds = [TSyntaxKind.Block, TSyntaxKind.CaseItem, TSyntaxKind.CaseElse, TSyntaxKind.ExceptBlock,
    TSyntaxKind.FinallyBlock, TSyntaxKind.ExceptionHandler];

/// <summary>Zuweisung: rechte Seite zuerst, dann das Ziel (Empfänger, Setter).</summary>
procedure CollectAssign(AStatement: TSyntaxNode; var ASites: TArray<TStepCallSite>);
begin
  if AStatement.ChildCount > 1 then
  begin
    TStepCalls.Visit(AStatement[1], ASites);
  end;
  if AStatement.ChildCount > 0 then
  begin
    TStepCalls.VisitTarget(AStatement[0], ASites);
  end;
end;

/// <summary>Aufrufe aus dem Teil AChild der Anweisung AStatement; APartial: nur Ausdrücke über ALine.</summary>
procedure CollectChild(AStatement, AChild: TSyntaxNode; ALine: Integer; APartial: Boolean;
  var ASites: TArray<TStepCallSite>);
begin
  if AChild.Kind in TStepCalls.cExpressionKinds then
  begin
    if not APartial or ((AChild.StartPos.Line <= ALine) and (AChild.EndPos.Line >= ALine)) then
    begin
      TStepCalls.Visit(AChild, ASites);
    end;
  end
  // Nur, was in derselben Zeile beginnt: if A then B; zählt B mit.
  else if not APartial and ((AChild.Kind in TStepCalls.cStatementKinds) or (AChild.Kind in cNestedKinds)) and
    (AChild.StartPos.Line = AStatement.StartPos.Line) then
  begin
    TStepCalls.CollectStatement(AChild, ALine, False, ASites);
  end;
end;

class procedure TStepCalls.CollectStatement(AStatement: TSyntaxNode; ALine: Integer; APartial: Boolean;
  var ASites: TArray<TStepCallSite>);
var
  mIndex: Integer;
begin
  if AStatement.Kind = TSyntaxKind.AssignStatement then
  begin
    CollectAssign(AStatement, ASites);
    Exit;
  end;
  for mIndex := 0 to AStatement.ChildCount - 1 do
  begin
    CollectChild(AStatement, AStatement[mIndex], ALine, APartial, ASites);
  end;
end;

/// <summary>Äußerste Anweisung, die in ALine beginnt (AStarting), und innerste, die ALine enthält
/// (AContaining).</summary>
procedure StatementsAt(ATree: TSyntaxTree; ALine: Integer; out AStarting, AContaining: TSyntaxNode);
var
  mStarting, mContaining: TSyntaxNode;
begin
  mStarting := nil;
  mContaining := nil;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := (ANode.StartPos.Line <= ALine) and (ANode.EndPos.Line >= ALine);
      if Result and (ANode.Kind in TStepCalls.cStatementKinds) then
      begin
        // Vorordnung: Die erste, die in der Zeile beginnt, ist die äußerste.
        if (mStarting = nil) and (ANode.StartPos.Line = ALine) then
        begin
          mStarting := ANode;
        end;
        mContaining := ANode;
      end;
    end);
  AStarting := mStarting;
  AContaining := mContaining;
end;

/// <summary>Anweisungen ab AStarting in ALine; weitere derselben Zeile (A; B;) laufen im selben Schritt.</summary>
procedure CollectLine(AStarting: TSyntaxNode; ALine: Integer; var AStatement: TStepStatement);
var
  mLast, mNext: TSyntaxNode;
begin
  AStatement.Node := AStarting;
  TStepCalls.CollectStatement(AStarting, ALine, False, AStatement.Sites);
  mLast := AStarting;
  mNext := TStepCalls.NextStatement(mLast);
  while (mNext <> nil) and (mNext.StartPos.Line = ALine) do
  begin
    TStepCalls.CollectStatement(mNext, ALine, False, AStatement.Sites);
    mLast := mNext;
    mNext := TStepCalls.NextStatement(mLast);
  end;
  AStatement.FollowLine := TStepCalls.FollowLine(mLast);
end;

class function TStepCalls.Find(ATree: TSyntaxTree; ALine: Integer; out AStatement: TStepStatement): Boolean;
var
  mStarting, mContaining: TSyntaxNode;
begin
  AStatement := Default(TStepStatement);
  AStatement.FollowLine := -1;
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit(False);
  end;
  StatementsAt(ATree, ALine, mStarting, mContaining);
  if mStarting <> nil then
  begin
    CollectLine(mStarting, ALine, AStatement);
  end
  else if mContaining <> nil then
  begin
    AStatement.Node := mContaining;
    CollectStatement(mContaining, ALine, not (mContaining.Kind in cSimpleKinds), AStatement.Sites);
    AStatement.FollowLine := FollowLine(mContaining);
  end;
  Result := AStatement.Node <> nil;
end;

class function TStepCalls.FirstStatement(ANode: TSyntaxNode): TSyntaxNode;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    if ANode[mIndex].Kind in cStatementKinds then
    begin
      Exit(ANode[mIndex]);
    end
    else if ANode[mIndex].Kind = TSyntaxKind.Block then
    begin
      Result := FirstStatement(ANode[mIndex]);
      if Result <> nil then
      begin
        Exit;
      end;
    end;
  end;
end;

class function TStepCalls.NextStatement(ANode: TSyntaxNode): TSyntaxNode;
var
  mParent: TSyntaxNode;
  mIndex, mOwn: Integer;
begin
  Result := nil;
  mParent := ANode.Parent;
  if mParent = nil then
  begin
    Exit;
  end;
  mOwn := -1;
  for mIndex := 0 to mParent.ChildCount - 1 do
  begin
    if mParent[mIndex] = ANode then
    begin
      mOwn := mIndex;
      Break;
    end;
  end;
  if mOwn < 0 then
  begin
    Exit;
  end;
  for mIndex := mOwn + 1 to mParent.ChildCount - 1 do
  begin
    if mParent[mIndex].Kind in cStatementKinds then
    begin
      Exit(mParent[mIndex]);
    end
    else if mParent[mIndex].Kind = TSyntaxKind.Block then
    begin
      // begin … end als Anweisung: seine erste Anweisung, sonst weiter.
      Result := FirstStatement(mParent[mIndex]);
      if Result <> nil then
      begin
        Exit;
      end;
    end;
  end;
end;

/// <summary>Ende des Rumpfs von AParent, bevor die nächste Anweisung zählt: True, wenn damit entschieden.</summary>
function HeadFollow(AParent: TSyntaxNode; out ALine: Integer): Boolean;
begin
  ALine := -1;
  case AParent.Kind of
    TSyntaxKind.WhileStatement, TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement:
      begin
        // Ende des Rumpfs: Die Schleife prüft wieder im Kopf.
        ALine := AParent.StartPos.Line;
        Result := True;
      end;
    TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod:
      Result := True;
  else
    Result := False;
  end;
end;

/// <summary>Ende des try-Teils ACurrent: Der finally-Teil läuft als Nächstes.</summary>
function FinallyFollow(ATry, ACurrent: TSyntaxNode; out ALine: Integer): Boolean;
var
  mPart, mFirst: TSyntaxNode;
begin
  ALine := -1;
  mPart := ATry.FindChild(TSyntaxKind.FinallyBlock);
  mFirst := nil;
  if (mPart <> nil) and (ACurrent.Kind <> TSyntaxKind.FinallyBlock) then
  begin
    mFirst := TStepCalls.FirstStatement(mPart);
  end;
  Result := mFirst <> nil;
  if Result then
  begin
    ALine := mFirst.StartPos.Line;
  end;
end;

/// <summary>Letzte Anweisung ACurrent in AParent ohne Nachfolger: True, wenn damit entschieden.</summary>
function TailFollow(AParent, ACurrent: TSyntaxNode; out ALine: Integer): Boolean;
begin
  ALine := -1;
  Result := False;
  case AParent.Kind of
    TSyntaxKind.Block:
      if (AParent.Parent <> nil) and (AParent.Parent.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod])
      then
      begin
        // Ende der Routine: Ihr end trägt Code (Aufräumen, Rücksprung).
        ALine := AParent.EndPos.Line;
        Result := True;
      end;
    TSyntaxKind.RepeatStatement:
      if (AParent.ChildCount > 0) and (AParent[AParent.ChildCount - 1].Kind in TStepCalls.cExpressionKinds) then
      begin
        ALine := AParent[AParent.ChildCount - 1].StartPos.Line;
        Result := True;
      end;
    TSyntaxKind.TryStatement:
      Result := FinallyFollow(AParent, ACurrent, ALine);
    TSyntaxKind.InitializationSection, TSyntaxKind.FinalizationSection:
      Result := True;
  else
    // Übrige Arten: nichts zu tun.
  end;
end;

/// <summary>Ein Schritt nach außen von ACurrent: True, wenn die Folgezeile ALine (auch -1) feststeht.</summary>
function StepFollow(ACurrent: TSyntaxNode; out ALine: Integer): Boolean;
var
  mParent, mNext: TSyntaxNode;
begin
  mParent := ACurrent.Parent;
  if HeadFollow(mParent, ALine) then
  begin
    Exit(True);
  end;
  mNext := TStepCalls.NextStatement(ACurrent);
  if mNext <> nil then
  begin
    ALine := mNext.StartPos.Line;
    Exit(True);
  end;
  Result := TailFollow(mParent, ACurrent, ALine);
end;

class function TStepCalls.FollowLine(AStatement: TSyntaxNode): Integer;
var
  mCurrent: TSyntaxNode;
begin
  Result := -1;
  mCurrent := AStatement;
  while (mCurrent <> nil) and (mCurrent.Parent <> nil) do
  begin
    if StepFollow(mCurrent, Result) then
    begin
      Exit;
    end;
    mCurrent := mCurrent.Parent;
  end;
end;

end.
