unit Atlas.Common.Rules.Builtin.Events;

// Regeln für Ereignisse und Methodenzeiger:
//   event-call-without-assigned  FOnChange(Self) bzw. OnChange(Self) in einer Methode der Klasse, ohne dass
//                                Assigned(FOnChange) (oder FOnChange <> nil) den Aufruf schützt (#946): ohne
//                                Handler folgt eine Zugriffsverletzung. Ereignisse sind Felder und Properties
//                                der Klasse mit Methodenzeiger- oder Referenztyp: procedure/function … of object,
//                                reference to …, TNotifyEvent, TProc/TFunc, Typen auf …Event sowie Typen der Unit
//                                bzw. des Index mit solcher Deklaration. Schutz: der Aufruf steht im then-Zweig
//                                einer Bedingung mit Assigned (auch while), im else-Zweig von not Assigned, hinter
//                                "Assigned(F) and" oder nach "if not Assigned(F) then Exit/raise". Korrektur: in
//                                "if Assigned(F) then" einschließen, wenn der Aufruf als eigene Anweisung in
//                                einem Block steht. Still bleiben Felder, die ein Konstruktor mit einem Wert
//                                belegt (eingereichte Abhängigkeiten wie FReadText := AReadText), Properties
//                                auf solche Felder und gleichnamige lokale Variablen oder Parameter.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TEventCallWithoutAssignedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Ist ATypeName ohne Blick in Unit und Index ein Ereignistyp (TNotifyEvent, TProc, …Event,
    /// procedure … of object, reference to …)?</summary>
    class function IsKnownEventType(const ATypeName: string): Boolean; static;
  end;

procedure RegisterEventRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.RegularExpressions,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract;

const
  EventCallWithoutAssignedRuleId = 'event-call-without-assigned';
  KnownEventTypes: array[0..9] of string = ('TNotifyEvent', 'TProc', 'TFunc', 'TPredicate', 'TThreadProcedure',
    'TThreadMethod', 'TGetStrProc', 'TWndMethod', 'TMethod', 'TCallback');
  ProceduralPattern = '^\s*(reference\s+to\s+)?(procedure|function)\b';
  StatementStarts: array[0..8] of string = (';', 'begin', 'then', 'do', 'else', 'try', 'finally', 'except',
    'repeat');

{ TEventCallWithoutAssignedRule }

function TEventCallWithoutAssignedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(EventCallWithoutAssignedRuleId, TRuleSeverity.Warning,
    'Ereignis ohne Assigned-Prüfung aufgerufen');
end;

/// <summary>Name ohne Unit und ohne generische Argumente: System.SysUtils.TFunc&lt;Integer&gt; → TFunc.</summary>
function ShortTypeName(const ATypeName: string): string;
begin
  Result := Trim(ATypeName);
  if Pos('<', Result) > 0 then
    Result := Copy(Result, 1, Pos('<', Result) - 1);
  Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
end;

class function TEventCallWithoutAssignedRule.IsKnownEventType(const ATypeName: string): Boolean;
var
  Name: string;
begin
  if TRegEx.IsMatch(ATypeName, ProceduralPattern, [roIgnoreCase]) then
    Exit(True);
  Name := ShortTypeName(ATypeName);
  Result := (IndexText(Name, KnownEventTypes) >= 0) or
    ((Length(Name) > 6) and StartsStr('T', Name) and EndsStr('Event', Name));
end;

procedure TEventCallWithoutAssignedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Code: TArray<Integer>;
  Lines: TArray<string>;
  LineBreak: string;
  UnitTypes: TArray<TSyntaxNode>;
  Routines: TArray<TSyntaxNode>;

  function Token(APosition: Integer): TPascalToken;
  begin
    Result := Tokens[Code[APosition]];
  end;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  // Ohne Leerraum, klein und ohne "self.", für den Vergleich von Bedingungen.
  function Normalized(const AText: string): string;
  var
    Index: Integer;
  begin
    Result := '';
    for Index := 1 to Length(AText) do
      if not CharInSet(AText[Index], [' ', #9, #10, #13]) then
        Result := Result + AText[Index];
    Result := StringReplace(LowerCase(Result), 'self.', '', [rfReplaceAll]);
  end;

  procedure CollectTypes(ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    if ANode.Kind = TSyntaxKind.TypeDecl then
      UnitTypes := UnitTypes + [ANode];
    if ANode.Kind = TSyntaxKind.RoutineDecl then
      Routines := Routines + [ANode];
    if ANode.Kind in [TSyntaxKind.Block, TSyntaxKind.RoutineDecl] then
      Exit;
    for Index := 0 to ANode.ChildCount - 1 do
      CollectTypes(ANode[Index]);
  end;

  // Ereignistyp: bekannt, als Methodenzeiger in der Unit deklariert oder im Index.
  function IsEventType(const ATypeName: string): Boolean;
  var
    Decl: TSyntaxNode;
    Name, Text: string;
    Location: TSymbolLocation;
  begin
    if IsKnownEventType(ATypeName) then
      Exit(True);
    Name := ShortTypeName(ATypeName);
    for Decl in UnitTypes do
      if SameText(Decl.Name, Name) then
      begin
        Text := NodeText(Decl);
        Text := Copy(Text, Pos('=', Text) + 1, MaxInt);
        Exit(TRegEx.IsMatch(Text, ProceduralPattern, [roIgnoreCase]));
      end;
    if AContext.Index <> nil then
      for Location in AContext.Index.FindSymbols(Name) do
        if (Location.Symbol.Container = '') and (Location.Symbol.Kind = TIndexSymbolKind.TypeAlias) and
          (ContainsText(Location.Symbol.Signature, 'of object') or
          ContainsText(Location.Symbol.Signature, 'reference to')) then
          Exit(True);
    Result := False;
  end;

  // Weist ein Konstruktor (bzw. mit AAnyMethod irgendeine Methode) von AClassName dem Feld AName einen Wert
  // ungleich nil zu? Dann ist es eine eingereichte Abhängigkeit (FReadText := AReadText) und kein Ereignis,
  // das ein Nutzer setzt.
  function Injected(ANode: TSyntaxNode; const AClassName, AName: string; AAnyMethod: Boolean): Boolean;
  var
    Index, Position: Integer;
    Block: TSyntaxNode;
  begin
    Result := False;
    if ANode.Kind = TSyntaxKind.RoutineDecl then
    begin
      Block := ANode.FindChild(TSyntaxKind.Block);
      if (Block = nil) or not StartsText(AClassName + '.', ANode.Name) or
        (not AAnyMethod and not StartsText('constructor', TrimLeft(NodeText(ANode)))) then
        Exit;
      for Position := 0 to High(Code) - 2 do
        if (Token(Position).Offset >= Block.StartOffset) and (Token(Position).Offset < Block.EndOffset) and
          (Token(Position).Kind = TPascalTokenKind.Identifier) and SameText(Token(Position).Text, AName) and
          Token(Position + 1).IsSymbol(':=') and not Token(Position + 2).IsKeyword('nil') then
          Exit(True);
      Exit;
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      if Injected(ANode[Index], AClassName, AName, AAnyMethod) then
        Exit(True);
  end;

  // Felder und Properties der Klasse mit Ereignistyp; ohne Felder, die der Konstruktor belegt (ohne
  // schreibbare Property: irgendeine Methode der Klasse), und ohne Properties, die solche Felder lesen.
  function EventsOf(const AClassName: string; AClass: TSyntaxNode): TArray<string>;
  var
    Index: Integer;
    Member, TypeNode: TSyntaxNode;
    Name: string;
    ReadField: TMatch;
    Written: TArray<string>;

    function IsInjected(const AField: string): Boolean;
    begin
      Result := Injected(AContext.Tree.Root, AClassName, AField, IndexText(AField, Written) < 0);
    end;

  begin
    Result := nil;
    // Felder, die eine Property schreibt: Ereignisse, die der Nutzer der Klasse setzt.
    Written := nil;
    for Index := 0 to AClass.ChildCount - 1 do
      if AClass[Index].Kind = TSyntaxKind.PropertyDecl then
      begin
        ReadField := TRegEx.Match(NodeText(AClass[Index]), '\bwrite\s+(\w+)', [roIgnoreCase]);
        if ReadField.Success then
          Written := Written + [ReadField.Groups[1].Value];
      end;
    for Index := 0 to AClass.ChildCount - 1 do
    begin
      Member := AClass[Index];
      if not (Member.Kind in [TSyntaxKind.Field, TSyntaxKind.PropertyDecl]) then
        Continue;
      TypeNode := Member.FindChild(TSyntaxKind.ProcedureType);
      if (TypeNode = nil) and (Member.FindChild(TSyntaxKind.TypeReference) <> nil) and
        IsEventType(NodeText(Member.FindChild(TSyntaxKind.TypeReference))) then
        TypeNode := Member.FindChild(TSyntaxKind.TypeReference);
      if TypeNode = nil then
        Continue;
      if Member.Kind = TSyntaxKind.PropertyDecl then
      begin
        ReadField := TRegEx.Match(NodeText(Member), '\bread\s+(\w+)', [roIgnoreCase]);
        if ReadField.Success and IsInjected(ReadField.Groups[1].Value) then
          Continue;
      end;
      for Name in Member.Name.Split([',']) do
        if (Trim(Name) <> '') and
          ((Member.Kind = TSyntaxKind.PropertyDecl) or not IsInjected(Trim(Name))) then
          Result := Result + [Trim(Name)];
    end;
  end;

  // Deklariert ARoutine (auch in anonymen Methoden) eine Variable, Konstante oder einen Parameter AName?
  function Shadowed(ANode: TSyntaxNode; const AName: string): Boolean;
  var
    Index: Integer;
    Name: string;
  begin
    if ANode.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.Parameter, TSyntaxKind.InlineVar,
      TSyntaxKind.InlineConst] then
      for Name in ANode.Name.Split([',']) do
        if SameText(Trim(Name), AName) then
          Exit(True);
    for Index := 0 to ANode.ChildCount - 1 do
      if Shadowed(ANode[Index], AName) then
        Exit(True);
    Result := False;
  end;

  // Innerster Knoten unter ANode, der AOffset enthält.
  function NodeAt(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode;
  var
    Index: Integer;
  begin
    Result := ANode;
    for Index := 0 to ANode.ChildCount - 1 do
      if (AOffset >= ANode[Index].StartOffset) and (AOffset < ANode[Index].EndOffset) then
        Exit(NodeAt(ANode[Index], AOffset));
  end;

  function Positive(const ACondition, AName: string): Boolean;
  var
    Start: Integer;
  begin
    Result := ContainsStr(ACondition, AName + '<>nil') or ContainsStr(ACondition, 'nil<>' + AName);
    Start := Pos('assigned(' + AName + ')', ACondition);
    while not Result and (Start > 0) do
    begin
      Result := (Start < 4) or (Copy(ACondition, Start - 3, 3) <> 'not');
      Start := PosEx('assigned(' + AName + ')', ACondition, Start + 1);
    end;
  end;

  function Negative(const ACondition, AName: string): Boolean;
  begin
    Result := ContainsStr(ACondition, 'notassigned(' + AName + ')') or ContainsStr(ACondition, AName + '=nil') or
      ContainsStr(ACondition, 'nil=' + AName);
  end;

  // Endet ABranch (Zweig einer Bedingung) mit Exit oder raise?
  function Leaves(ABranch: TSyntaxNode): Boolean;
  begin
    Result := (ABranch.Kind = TSyntaxKind.RaiseStatement) or
      TRegEx.IsMatch(NodeText(ABranch), '\b(exit|raise)\b', [roIgnoreCase]);
  end;

  // "Ok := … and Assigned(F);" vor AOffset: Ok steht für die Prüfung.
  function AssignedFlag(ARoutine: TSyntaxNode; AOffset: Integer; const AFlag, AName: string): Boolean;
  var
    Index: Integer;
    Node: TSyntaxNode;
    Value: string;
  begin
    Result := False;
    for Index := 0 to High(Code) - 1 do
      if (Token(Index).Offset > ARoutine.StartOffset) and (Token(Index).Offset < AOffset) and
        SameText(Token(Index).Text, AFlag) and Token(Index + 1).IsSymbol(':=') then
      begin
        Node := NodeAt(ARoutine, Token(Index).Offset);
        while (Node <> nil) and (Node.Kind <> TSyntaxKind.AssignStatement) and (Node <> ARoutine) do
          Node := Node.Parent;
        if (Node = nil) or (Node.Kind <> TSyntaxKind.AssignStatement) then
          Continue;
        Value := Copy(AContext.Text, Token(Index + 1).Offset + 3, Node.EndOffset - Token(Index + 1).Offset - 2);
        Result := Positive(Normalized(Value), AName) and not TRegEx.IsMatch(Value, '\bor\b', [roIgnoreCase]);
      end;
  end;

  // Steht AFlag für Assigned(F): ein vorher belegter Merker oder eine Methode der Klasse ohne Parameter mit
  // "Result := … and Assigned(F)" (CanEnterCredentials)?
  function FlagFor(ARoutine: TSyntaxNode; AOffset: Integer; const AFlag, AName: string): Boolean;
  var
    ClassName: string;
    Callee: TSyntaxNode;
  begin
    if not TRegEx.IsMatch(AFlag, '^\w+$') then
      Exit(False);
    if AssignedFlag(ARoutine, AOffset, AFlag, AName) then
      Exit(True);
    Result := False;
    ClassName := Copy(ARoutine.Name, 1, LastDelimiter('.', ARoutine.Name) - 1);
    if ClassName = '' then
      Exit;
    for Callee in Routines do
      if SameText(Callee.Name, ClassName + '.' + AFlag) and
        (Pos('(', Copy(NodeText(Callee), 1, Pos(';', NodeText(Callee)))) = 0) then
        Exit(AssignedFlag(Callee, Callee.EndOffset, 'Result', AName));
  end;

  // Schützt eine Bedingung den Aufruf bei AOffset in ARoutine?
  function Guarded(ARoutine: TSyntaxNode; AOffset: Integer; const AName: string): Boolean;
  var
    Node, Parent, Branch: TSyntaxNode;
    Index: Integer;
    Condition, Prefix: string;
  begin
    Node := NodeAt(ARoutine, AOffset);
    // Kurzschluss im selben Ausdruck: "Assigned(F) and F(Self)", "not Assigned(F) or not F(Self)".
    Parent := Node;
    while (Parent <> nil) and (Parent <> ARoutine) and not (Parent.Kind in [TSyntaxKind.AssignStatement,
      TSyntaxKind.CallStatement, TSyntaxKind.IfStatement, TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement,
      TSyntaxKind.CaseStatement, TSyntaxKind.Block]) do
      Parent := Parent.Parent;
    if (Parent <> nil) and (Parent <> ARoutine) then
    begin
      Prefix := Normalized(Copy(AContext.Text, Parent.StartOffset + 1, AOffset - Parent.StartOffset));
      if (Positive(Prefix, AName) and ContainsStr(Prefix, 'assigned(' + AName + ')and')) or
        (ContainsStr(Prefix, AName + '<>niland')) or
        (Negative(Prefix, AName) and (ContainsStr(Prefix, 'notassigned(' + AName + ')or') or
        ContainsStr(Prefix, AName + '=nilor'))) then
        Exit(True);
    end;
    while (Node <> nil) and (Node <> ARoutine) do
    begin
      Parent := Node.Parent;
      if (Parent <> nil) and (Parent.Kind = TSyntaxKind.IfStatement) and (Parent.ChildCount > 1) then
      begin
        Condition := Normalized(NodeText(Parent[0]));
        if (Node = Parent[1]) and (Positive(Condition, AName) or FlagFor(ARoutine, Parent.StartOffset, Condition,
          AName)) then
          Exit(True)
        else if (Parent.ChildCount > 2) and (Node = Parent[2]) and Negative(Condition, AName) then
          Exit(True);
      end;
      // "while Assigned(F) do F(Self);"
      if (Parent <> nil) and (Parent.Kind = TSyntaxKind.WhileStatement) and (Parent.ChildCount > 1) and
        (Node = Parent[1]) and Positive(Normalized(NodeText(Parent[0])), AName) then
        Exit(True);
      Node := Parent;
    end;
    // "if not Assigned(F) then Exit;" bzw. "if not Ok then Exit;" mit "Ok := … and Assigned(F)" vor dem Aufruf.
    Result := False;
    for Index := 0 to High(Code) do
      if (Token(Index).Offset > ARoutine.StartOffset) and (Token(Index).Offset < AOffset) and
        Token(Index).IsKeyword('if') then
      begin
        Node := NodeAt(ARoutine, Token(Index).Offset);
        while (Node <> nil) and (Node.Kind <> TSyntaxKind.IfStatement) and (Node <> ARoutine) do
          Node := Node.Parent;
        if (Node = nil) or (Node.Kind <> TSyntaxKind.IfStatement) or (Node.ChildCount < 2) or
          (Node.EndOffset > AOffset) then
          Continue;
        Branch := Node[1];
        Condition := Normalized(NodeText(Node[0]));
        if not Leaves(Branch) then
          Continue;
        if Negative(Condition, AName) then
          Exit(True);
        if StartsStr('not', Condition) and FlagFor(ARoutine, Node.StartOffset, Copy(Condition, 4, MaxInt), AName) then
          Exit(True);
      end;
  end;

  // "if Assigned(F) then" vor die Anweisung; nur in Blöcken und wenn die Anweisung allein am Zeilenanfang steht.
  function WrapFix(ARoutine: TSyntaxNode; AFirst: Integer; const AName: string; out AFix: TRuleFix): Boolean;
  var
    Statement: TSyntaxNode;
    Line: Integer;
    Indent: string;
  begin
    Result := False;
    Statement := NodeAt(ARoutine, Token(AFirst).Offset);
    while (Statement <> nil) and (Statement.Kind <> TSyntaxKind.CallStatement) and (Statement <> ARoutine) do
      Statement := Statement.Parent;
    if (Statement = nil) or (Statement.Kind <> TSyntaxKind.CallStatement) or (Statement.Parent = nil) or
      not (Statement.Parent.Kind in [TSyntaxKind.Block, TSyntaxKind.TryStatement, TSyntaxKind.FinallyBlock,
      TSyntaxKind.ExceptBlock, TSyntaxKind.RepeatStatement]) or (Statement.StartOffset <> Token(AFirst).Offset) then
      Exit;
    Line := Statement.StartPos.Line;
    if (Line > High(Lines)) or (Trim(Copy(Lines[Line], 1, Statement.StartPos.Character)) <> '') then
      Exit;
    Indent := Copy(Lines[Line], 1, Statement.StartPos.Character);
    AFix := TRuleFix.Create(Format('In if Assigned(%s) then einschließen', [AName]),
      [TTextEdit.Create(TTextRange.Create(Statement.StartPos, Statement.StartPos), 'if Assigned(' + AName +
      ') then' + LineBreak + Indent + '  ')]);
    Result := True;
  end;

  procedure CheckRoutine(ARoutine: TSyntaxNode; const AEvents: TArray<string>);
  var
    Block: TSyntaxNode;
    Position, First, Next: Integer;
    Name, Written: string;
    Fix: TRuleFix;
    Fixes: TArray<TRuleFix>;
    IsCall: Boolean;
  begin
    Block := ARoutine.FindChild(TSyntaxKind.Block);
    if Block = nil then
      Exit;
    for Position := 0 to High(Code) - 1 do
    begin
      if (Token(Position).Offset < Block.StartOffset) or (Token(Position).Offset >= Block.EndOffset) or
        (Token(Position).Kind <> TPascalTokenKind.Identifier) or (IndexText(Token(Position).Text, AEvents) < 0) then
        Continue;
      First := Position;
      if (Position > 0) and Token(Position - 1).IsSymbol('.') then
      begin
        if (Position < 2) or not SameText(Token(Position - 2).Text, 'Self') then
          Continue;
        First := Position - 2;
      end;
      Next := Position + 1;
      IsCall := Token(Next).IsSymbol('(');
      // Ohne Argumente nur als eigene Anweisung: "FOnIdle;".
      if not IsCall and ((First = 0) or MatchText(Token(First - 1).Text, StatementStarts)) then
        IsCall := Token(Next).IsSymbol(';') or Token(Next).IsKeyword('end') or Token(Next).IsKeyword('else');
      if not IsCall then
        Continue;
      Name := LowerCase(Token(Position).Text);
      if ((First = Position) and Shadowed(ARoutine, Name)) or Guarded(ARoutine, Token(Position).Offset, Name) then
        Continue;
      Written := Token(Position).Text;
      Fixes := nil;
      if WrapFix(ARoutine, First, Written, Fix) then
        Fixes := [Fix];
      AReport.Add(TTextRange.Create(Token(Position).StartPos, Token(Position).EndPos),
        Format('%s kann nil sein; ohne Assigned-Prüfung folgt eine Zugriffsverletzung.', [Written]), Fixes);
    end;
  end;

  procedure CheckRoutines(ANode: TSyntaxNode; const AClassName: string; const AEvents: TArray<string>);
  var
    Index: Integer;
  begin
    if ANode.Kind = TSyntaxKind.RoutineDecl then
    begin
      if StartsText(AClassName + '.', ANode.Name) then
        CheckRoutine(ANode, AEvents);
      Exit;
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      CheckRoutines(ANode[Index], AClassName, AEvents);
  end;

var
  Index: Integer;
  Decl, ClassNode: TSyntaxNode;
  Events: TArray<string>;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Code := nil;
  for Index := 0 to High(Tokens) do
    if not (Tokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
      Code := Code + [Index];
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  UnitTypes := nil;
  Routines := nil;
  CollectTypes(AContext.Tree.Root);
  for Decl in UnitTypes do
  begin
    ClassNode := Decl.FindChild(TSyntaxKind.ClassType);
    if ClassNode = nil then
      ClassNode := Decl.FindChild(TSyntaxKind.RecordType);
    if ClassNode = nil then
      Continue;
    Events := EventsOf(Decl.Name, ClassNode);
    if Events <> nil then
      CheckRoutines(AContext.Tree.Root, Decl.Name, Events);
  end;
end;

procedure RegisterEventRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TEventCallWithoutAssignedRule.Create);
end;

end.
