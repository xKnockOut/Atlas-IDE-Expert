unit Atlas.Common.Rules.Builtin.Ownership;

// Regeln für Besitz von Objekten:
//   owned-item-freed  Element einer besitzenden Liste zusätzlich freigegeben (#947): Liste[I].Free,
//                     FreeAndNil(Liste[I]) oder Element.Free für ein Element aus Liste[I], Liste.First/Last bzw.
//                     "for Element in Liste do", während TObjectList/TObjectList<T> (OwnsObjects, Vorgabe True)
//                     bzw. TObjectDictionary mit doOwnsValues das Element selbst freigibt: bei Delete, Remove,
//                     Clear, einer Zuweisung an Liste[I] oder spätestens beim Freigeben der Liste. Besitzend ist
//                     eine Liste, wenn sie in der Unit so erzeugt wird (TObjectList ohne False, TObjectDictionary
//                     mit doOwnsValues) bzw. ohne Erzeugung als TObjectList deklariert ist, und kein
//                     "OwnsObjects := False" folgt. Extract in derselben Routine lässt die Regel schweigen.
//                     Korrekturen: Free entfernen, Delete bzw. Remove statt Free, Extract statt Remove.
//   create-without-assignment  "TStringList.Create;" als eigene Anweisung (#948): Das Objekt wird erzeugt, aber
//                     nirgends gespeichert und nie freigegeben. Still bleiben Komponenten mit Owner (erstes Argument
//                     Self, Owner, AOwner, Application bzw. ein Nachfahr von TComponent mit Argument ungleich nil),
//                     Threads (geben sich mit FreeOnTerminate selbst frei), unbekannte Klassen mit Argumenten und
//                     Klassen aus "selfRegistering". Korrektur: Zuweisung an eine neue lokale Variable, die
//                     folgenden Anweisungen des Blocks in try/finally mit Free.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TOwnedItemFreedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Besitzt eine Liste, die mit ATypeName und den Argumenten AArguments von Create erzeugt wird,
    /// ihre Elemente? AIsDictionary meldet ein TObjectDictionary (besitzt nur mit doOwnsValues).</summary>
    class function CreatesOwning(const ATypeName, AArguments: string; out AIsDictionary: Boolean): Boolean; static;
  end;

  TCreateWithoutAssignmentRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Folgt AName der Namensregel für Typen (TName, EName)?</summary>
    class function LooksLikeType(const AName: string): Boolean; static;
    /// <summary>Name der lokalen Variablen für die Korrektur: TImportProtokoll → ImportProtokoll.</summary>
    class function VariableName(const ATypeName: string): string; static;
  end;

procedure RegisterOwnershipRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.RegularExpressions,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Builtin.Inheritance;

const
  OwnedItemFreedRuleId = 'owned-item-freed';
  CreateWithoutAssignmentRuleId = 'create-without-assignment';
  RemoveMethods: array[0..4] of string = ('Delete', 'Remove', 'RemoveItem', 'Clear', 'DeleteRange');
  ExtractMethods: array[0..3] of string = ('Extract', 'ExtractAt', 'ExtractItem', 'ExtractPair');

type
  /// <summary>Eine besitzende Liste der Unit.</summary>
  TOwningList = record
    Name: string;
    IsDictionary: Boolean;
  end;

  /// <summary>Art einer erzeugten Klasse für create-without-assignment.</summary>
{$SCOPEDENUMS ON}
  TCreatedKind = (Unknown, Plain, Component, Thread);
{$SCOPEDENUMS OFF}

  /// <summary>Eine Freigabe eines Listenelements in einer Routine.</summary>
  TItemFree = record
    List: TOwningList;
    /// <summary>Code-Position des ersten und letzten Tokens des freigegebenen Ausdrucks.</summary>
    First, Last: Integer;
    /// <summary>Indexausdruck bei Liste[Index].Free, sonst leer.</summary>
    IndexText: string;
    /// <summary>Name der Elementvariablen bei Element.Free, sonst leer.</summary>
    Alias: string;
  end;

{ TOwnedItemFreedRule }

function TOwnedItemFreedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(OwnedItemFreedRuleId, TRuleSeverity.Error,
    'Element einer besitzenden Liste zusätzlich freigegeben');
end;

class function TOwnedItemFreedRule.CreatesOwning(const ATypeName, AArguments: string;
  out AIsDictionary: Boolean): Boolean;
begin
  AIsDictionary := ContainsText(ATypeName, 'TObjectDictionary');
  if AIsDictionary then
    Result := ContainsText(AArguments, 'doOwnsValues')
  else
    Result := not TRegEx.IsMatch(AArguments, '\bFalse\b', [roIgnoreCase]);
end;

procedure TOwnedItemFreedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Code: TArray<Integer>;
  Lines: TArray<string>;
  LineBreak: string;
  Lists: TArray<TOwningList>;

  function Token(APosition: Integer): TPascalToken;
  begin
    Result := Tokens[Code[APosition]];
  end;

  function IsWord(APosition: Integer): Boolean;
  begin
    Result := (APosition >= 0) and (APosition <= High(Code)) and
      (Token(APosition).Kind = TPascalTokenKind.Identifier);
  end;

  function IsSym(APosition: Integer; const ASymbol: string): Boolean;
  begin
    Result := (APosition >= 0) and (APosition <= High(Code)) and Token(APosition).IsSymbol(ASymbol);
  end;

  function IsName(APosition: Integer; const AName: string): Boolean;
  begin
    Result := IsWord(APosition) and SameText(Token(APosition).Text, AName);
  end;

  // Passende schließende Klammer zu AOpen ("(" oder "["), sonst -1.
  function Closing(AOpen: Integer): Integer;
  var
    Depth: Integer;
  begin
    Depth := 0;
    for Result := AOpen to High(Code) do
      if Token(Result).IsSymbol('(') or Token(Result).IsSymbol('[') then
        Inc(Depth)
      else if Token(Result).IsSymbol(')') or Token(Result).IsSymbol(']') then
      begin
        Dec(Depth);
        if Depth = 0 then
          Exit;
      end;
    Result := -1;
  end;

  function TextBetween(AFirst, ALast: Integer): string;
  begin
    Result := Copy(AContext.Text, Token(AFirst).Offset + 1,
      Token(ALast).Offset + Length(Token(ALast).Text) - Token(AFirst).Offset);
  end;

  function NodeAt(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode;
  var
    Index: Integer;
  begin
    Result := ANode;
    for Index := 0 to ANode.ChildCount - 1 do
      if (AOffset >= ANode[Index].StartOffset) and (AOffset < ANode[Index].EndOffset) then
        Exit(NodeAt(ANode[Index], AOffset));
  end;

  procedure AddList(const AName: string; AIsDictionary: Boolean);
  var
    Item: TOwningList;
  begin
    for Item in Lists do
      if SameText(Item.Name, AName) then
        Exit;
    Item.Name := AName;
    Item.IsDictionary := AIsDictionary;
    Lists := Lists + [Item];
  end;

  // Position des Typnamens nach "Unit.Unit." ab APosition.
  function SkipUnitPrefix(APosition: Integer): Integer;
  begin
    Result := APosition;
    while IsWord(Result) and IsSym(Result + 1, '.') and IsWord(Result + 2) and
      not SameText(Token(Result).Text, 'TObjectList') and not SameText(Token(Result).Text, 'TObjectDictionary') do
      Inc(Result, 2);
  end;

  // Position nach den generischen Argumenten "<…>" ab APosition.
  function SkipGenericArgs(APosition: Integer): Integer;
  var
    Depth: Integer;
  begin
    Result := APosition;
    if not IsSym(Result, '<') then
      Exit;
    Depth := 0;
    while Result <= High(Code) do
    begin
      if Token(Result).IsSymbol('<') then
        Inc(Depth)
      else if Token(Result).IsSymbol('>') then
        Dec(Depth)
      else if Token(Result).IsSymbol('>>') then
        Dec(Depth, 2)
      else if Token(Result).IsSymbol(';') then
        Exit;
      Inc(Result);
      if Depth <= 0 then
        Exit;
    end;
  end;

  // Besitzende Listen der Unit: Erzeugungen, sonst Deklarationen als TObjectList; ohne OwnsObjects := False.
  procedure CollectLists;
  var
    Position, TypePosition, After, Close, Names: Integer;
    Arguments: string;
    Owning, IsDictionary: Boolean;
    Created, NotOwning, Declared: TArray<string>;
    Index: Integer;
  begin
    Lists := nil;
    Created := nil;
    NotOwning := nil;
    Declared := nil;
    for Position := 0 to High(Code) - 2 do
    begin
      if not IsWord(Position) then
        Continue;
      // Name := TObjectList<T>.Create(…);
      if IsSym(Position + 1, ':=') then
      begin
        TypePosition := SkipUnitPrefix(Position + 2);
        if not IsName(TypePosition, 'TObjectList') and not IsName(TypePosition, 'TObjectDictionary') then
          Continue;
        After := SkipGenericArgs(TypePosition + 1);
        if not IsSym(After, '.') or not IsName(After + 1, 'Create') then
          Continue;
        Arguments := '';
        if IsSym(After + 2, '(') then
        begin
          Close := Closing(After + 2);
          if Close > After + 3 then
            Arguments := TextBetween(After + 3, Close - 1);
        end;
        Created := Created + [Token(Position).Text];
        Owning := CreatesOwning(Token(TypePosition).Text, Arguments, IsDictionary);
        if Owning then
          AddList(Token(Position).Text, IsDictionary)
        else
          NotOwning := NotOwning + [Token(Position).Text];
        Continue;
      end;
      // Name.OwnsObjects := False;
      if IsSym(Position + 1, '.') and IsName(Position + 2, 'OwnsObjects') and IsSym(Position + 3, ':=') and
        IsName(Position + 4, 'False') then
      begin
        NotOwning := NotOwning + [Token(Position).Text];
        Continue;
      end;
      // A, B: TObjectList;
      if IsSym(Position + 1, ':') and IsName(SkipUnitPrefix(Position + 2), 'TObjectList') then
      begin
        Names := Position;
        while IsWord(Names) do
        begin
          Declared := Declared + [Token(Names).Text];
          if not IsSym(Names - 1, ',') then
            Break;
          Dec(Names, 2);
        end;
      end;
    end;
    for Index := 0 to High(Declared) do
      if IndexText(Declared[Index], Created) < 0 then
        AddList(Declared[Index], False);
    for Index := High(Lists) downto 0 do
      if IndexText(Lists[Index].Name, NotOwning) >= 0 then
        Delete(Lists, Index, 1);
  end;

  function ListAt(APosition: Integer; out AList: TOwningList): Boolean;
  var
    Item: TOwningList;
  begin
    Result := False;
    if not IsWord(APosition) then
      Exit;
    // Nur der Name selbst oder Self.Name, keine fremden Objekte.
    if IsSym(APosition - 1, '.') and not IsName(APosition - 2, 'Self') then
      Exit;
    for Item in Lists do
      if SameText(Item.Name, Token(APosition).Text) then
      begin
        AList := Item;
        Exit(True);
      end;
  end;

  // Liste[Index] bzw. Liste.Items[Index] ab APosition; liefert die Position nach "]" und den Indextext.
  function ElementAccess(APosition: Integer; out AAfter: Integer; out AIndex: string): Boolean;
  var
    Open, Close: Integer;
  begin
    Result := False;
    Open := APosition + 1;
    if IsSym(Open, '.') and IsName(Open + 1, 'Items') then
      Inc(Open, 2);
    if not IsSym(Open, '[') then
      Exit;
    Close := Closing(Open);
    if Close < 0 then
      Exit;
    AIndex := Trim(TextBetween(Open + 1, Close - 1));
    AAfter := Close + 1;
    Result := True;
  end;

  // Steht bei APosition eine Freigabe "X.Free", "X.Destroy", "X.DisposeOf" (AExprLast = letztes Token von X)?
  function FreeAfter(AExprLast: Integer): Boolean;
  begin
    Result := IsSym(AExprLast + 1, '.') and (IsName(AExprLast + 2, 'Free') or IsName(AExprLast + 2, 'Destroy') or
      IsName(AExprLast + 2, 'DisposeOf'));
  end;

  // Elementvariablen der Routine: V := L[I], V := L.Items[I], L.First/Last, for V in L / L.Values.
  function AliasList(ABlock: TSyntaxNode; AFreePosition: Integer; const AName: string;
    out AList: TOwningList): Boolean;
  var
    Position, After: Integer;
    Index: string;
    Node: TSyntaxNode;
  begin
    Result := False;
    for Position := 0 to AFreePosition - 1 do
    begin
      if (Token(Position).Offset < ABlock.StartOffset) or not IsName(Position, AName) then
        Continue;
      // V := Liste[I]; V := Liste.Items[I]; V := Liste.First
      if IsSym(Position + 1, ':=') and ListAt(Position + 2, AList) then
      begin
        if ElementAccess(Position + 2, After, Index) and IsSym(After, ';') then
          Result := True
        else if IsSym(Position + 3, '.') and (IsName(Position + 4, 'First') or IsName(Position + 4, 'Last')) and
          IsSym(Position + 5, ';') then
          Result := True;
        Continue;
      end;
      // for V in Liste do / for V in Dictionary.Values do: nur, wenn die Freigabe in der Schleife steht.
      if (Position > 1) and (Token(Position - 1).IsKeyword('for') or (Token(Position - 1).IsKeyword('var') and
        Token(Position - 2).IsKeyword('for'))) and Token(Position + 1).IsKeyword('in') and
        ListAt(Position + 2, AList) and ((Token(Position + 3).IsKeyword('do') and not AList.IsDictionary) or
        (IsSym(Position + 3, '.') and IsName(Position + 4, 'Values') and AList.IsDictionary)) then
      begin
        Node := NodeAt(AContext.Tree.Root, Token(Position).Offset);
        while (Node <> nil) and (Node.Kind <> TSyntaxKind.ForInStatement) do
          Node := Node.Parent;
        if (Node <> nil) and (Token(AFreePosition).Offset < Node.EndOffset) then
          Result := True;
      end;
    end;
  end;

  // Anweisung (CallStatement) um APosition, wenn sie allein in ihren Zeilen in einem Block steht. Ist sie der
  // einzige Rumpf einer for-in-Schleife, die ganze Schleife.
  function OwnStatement(APosition: Integer; out ANode: TSyntaxNode): Boolean;
  var
    Node: TSyntaxNode;
  begin
    Result := False;
    Node := NodeAt(AContext.Tree.Root, Token(APosition).Offset);
    while (Node <> nil) and (Node.Kind <> TSyntaxKind.CallStatement) do
      Node := Node.Parent;
    if (Node = nil) or (Node.Parent = nil) then
      Exit;
    if (Node.Parent.Kind = TSyntaxKind.ForInStatement) and (Node.Parent[Node.Parent.ChildCount - 1] = Node) then
      Node := Node.Parent;
    if (Node.Parent = nil) or not (Node.Parent.Kind in [TSyntaxKind.Block, TSyntaxKind.TryStatement,
      TSyntaxKind.FinallyBlock, TSyntaxKind.ExceptBlock, TSyntaxKind.RepeatStatement]) then
      Exit;
    if (Node.StartPos.Line > High(Lines)) or (Node.EndPos.Line > High(Lines)) or
      (Trim(Copy(Lines[Node.StartPos.Line], 1, Node.StartPos.Character)) <> '') or
      ((Trim(Copy(Lines[Node.EndPos.Line], Node.EndPos.Character + 1, MaxInt)) <> '') and
      (Trim(Copy(Lines[Node.EndPos.Line], Node.EndPos.Character + 1, MaxInt)) <> ';')) then
      Exit;
    ANode := Node;
    Result := True;
  end;

  function RemoveFreeFix(APosition: Integer; out AFix: TRuleFix): Boolean;
  var
    Node: TSyntaxNode;
  begin
    Result := OwnStatement(APosition, Node);
    if Result then
      AFix := TRuleFix.Create('Free entfernen',
        [TTextEdit.Create(TTextRange.Create(Node.StartPos.Line, 0, Node.EndPos.Line + 1, 0), '')]);
  end;

  // Liste[I].Free → Liste.Delete(I) bzw. Dictionary.Remove(Key).
  function DeleteFix(const AFree: TItemFree; out AFix: TRuleFix): Boolean;
  var
    Node: TSyntaxNode;
    Method, Prefix: string;
  begin
    Result := (AFree.IndexText <> '') and OwnStatement(AFree.First, Node) and (Node.Kind = TSyntaxKind.CallStatement);
    if not Result then
      Exit;
    Method := 'Delete';
    if AFree.List.IsDictionary then
      Method := 'Remove';
    // "Self.Liste[I].Free": Self. bleibt stehen.
    Prefix := '';
    if IsSym(AFree.First - 1, '.') then
      Prefix := 'Self.';
    AFix := TRuleFix.Create(Format('%s statt Free', [Method]),
      [TTextEdit.Create(TTextRange.Create(Node.StartPos, Node.EndPos),
      Format('%s%s.%s(%s)', [Prefix, Token(AFree.First).Text, Method, AFree.IndexText]))]);
  end;

  procedure CheckRoutine(ARoutine: TSyntaxNode);
  var
    Block: TSyntaxNode;
    Position, After, Start, Last, RemovePosition: Integer;
    Frees: TArray<TItemFree>;
    Item: TItemFree;
    List: TOwningList;
    Index, Removal, Message, Owns: string;
    Extracted: Boolean;
    Fix: TRuleFix;
    Fixes: TArray<TRuleFix>;
  begin
    Block := ARoutine.FindChild(TSyntaxKind.Block);
    if Block = nil then
      Exit;
    // Freigaben sammeln.
    Frees := nil;
    for Position := 0 to High(Code) do
    begin
      if (Token(Position).Offset < Block.StartOffset) or (Token(Position).Offset >= Block.EndOffset) then
        Continue;
      Item := Default(TItemFree);
      // FreeAndNil(Liste[I]) bzw. FreeAndNil(V)
      if IsName(Position, 'FreeAndNil') and IsSym(Position + 1, '(') then
      begin
        Start := Position + 2;
        if IsName(Start, 'Self') and IsSym(Start + 1, '.') then
          Inc(Start, 2);
        if ListAt(Start, List) and ElementAccess(Start, After, Index) and IsSym(After, ')') then
        begin
          Item.List := List;
          Item.First := Start;
          Item.Last := After;
          Item.IndexText := Index;
          Frees := Frees + [Item];
        end
        else if IsWord(Start) and IsSym(Start + 1, ')') and AliasList(Block, Position, Token(Start).Text, List) then
        begin
          Item.List := List;
          Item.First := Position;
          Item.Last := Start + 1;
          Item.Alias := Token(Start).Text;
          Frees := Frees + [Item];
        end;
        Continue;
      end;
      // Liste[I].Free
      if ListAt(Position, List) and ElementAccess(Position, After, Index) and FreeAfter(After - 1) then
      begin
        Item.List := List;
        Item.First := Position;
        Item.Last := After + 1;
        Item.IndexText := Index;
        Frees := Frees + [Item];
        Continue;
      end;
      // V.Free
      if IsWord(Position) and not IsSym(Position - 1, '.') and FreeAfter(Position) and
        AliasList(Block, Position, Token(Position).Text, List) then
      begin
        Item.List := List;
        Item.First := Position;
        Item.Last := Position + 2;
        Item.Alias := Token(Position).Text;
        Frees := Frees + [Item];
      end;
    end;
    for Item in Frees do
    begin
      // Entfernen bzw. Extract derselben Liste in der Routine.
      Removal := '';
      RemovePosition := -1;
      Extracted := False;
      for Position := 0 to High(Code) - 2 do
      begin
        if (Token(Position).Offset < Block.StartOffset) or (Token(Position).Offset >= Block.EndOffset) or
          not ListAt(Position, List) or not SameText(List.Name, Item.List.Name) then
          Continue;
        if IsSym(Position + 1, '.') and (IndexText(Token(Position + 2).Text, ExtractMethods) >= 0) then
          Extracted := True
        else if (Removal = '') and IsSym(Position + 1, '.') and
          (IndexText(Token(Position + 2).Text, RemoveMethods) >= 0) then
        begin
          Removal := Token(Position + 2).Text;
          RemovePosition := Position + 2;
        end
        else if (Removal = '') and ElementAccess(Position, After, Index) and IsSym(After, ':=') then
          Removal := 'die Zuweisung an ' + Token(Position).Text + '[…]';
      end;
      if Extracted then
        Continue;
      Owns := 'seine Elemente (OwnsObjects)';
      if Item.List.IsDictionary then
        Owns := 'seine Werte (doOwnsValues)';
      Fixes := nil;
      if Removal <> '' then
      begin
        Message := Format('%s besitzt %s; %s gibt das Element ein zweites Mal frei.', [Item.List.Name, Owns,
          Removal]);
        if RemoveFreeFix(Item.First, Fix) then
          Fixes := Fixes + [Fix];
        // Remove(V) vor V.Free: Extract nimmt das Element heraus, ohne es freizugeben.
        if (RemovePosition >= 0) and SameText(Token(RemovePosition).Text, 'Remove') and (Item.Alias <> '') then
        begin
          if Item.List.IsDictionary then
            Fix := TRuleFix.Create('ExtractPair statt Remove', [TTextEdit.Create(TTextRange.Create(
              Token(RemovePosition).StartPos, Token(RemovePosition).EndPos), 'ExtractPair')])
          else
            Fix := TRuleFix.Create('Extract statt Remove', [TTextEdit.Create(TTextRange.Create(
              Token(RemovePosition).StartPos, Token(RemovePosition).EndPos), 'Extract')]);
          Fix.Alternative := Fixes <> nil;
          Fixes := Fixes + [Fix];
        end;
      end
      else
      begin
        Message := Format('%s besitzt %s; die Liste gibt das Element beim Freigeben ein zweites Mal frei.',
          [Item.List.Name, Owns]);
        if DeleteFix(Item, Fix) then
          Fixes := Fixes + [Fix]
        else if (Item.Alias <> '') and RemoveFreeFix(Item.First, Fix) then
          Fixes := Fixes + [Fix];
      end;
      Last := Item.Last;
      AReport.Add(TTextRange.Create(Token(Item.First).StartPos, Token(Last).EndPos), Message, Fixes);
    end;
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    if ANode.Kind = TSyntaxKind.RoutineDecl then
    begin
      CheckRoutine(ANode);
      Exit;
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index]);
  end;

var
  Index: Integer;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  if not ContainsText(AContext.Text, 'TObjectList') and not ContainsText(AContext.Text, 'TObjectDictionary') then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Code := nil;
  for Index := 0 to High(Tokens) do
    if not (Tokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
      Code := Code + [Index];
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  CollectLists;
  if Lists = nil then
    Exit;
  Visit(AContext.Tree.Root);
end;

{ TCreateWithoutAssignmentRule }

function TCreateWithoutAssignmentRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(CreateWithoutAssignmentRuleId, TRuleSeverity.Warning,
    'Objekt erzeugt und sofort verloren');
end;

class function TCreateWithoutAssignmentRule.LooksLikeType(const AName: string): Boolean;
begin
  Result := (Length(AName) >= 2) and CharInSet(AName[1], ['T', 'E']) and CharInSet(AName[2], ['A'..'Z']);
end;

class function TCreateWithoutAssignmentRule.VariableName(const ATypeName: string): string;
begin
  Result := ATypeName;
  if Pos('<', Result) > 0 then
    Result := Copy(Result, 1, Pos('<', Result) - 1);
  Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
  if LooksLikeType(Result) then
    Result := Copy(Result, 2, MaxInt);
  if Result = '' then
    Result := 'Objekt';
end;

procedure TCreateWithoutAssignmentRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Code: TArray<Integer>;
  Lines: TArray<string>;
  LineBreak: string;
  SelfRegistering: TArray<string>;
  Ancestry: TAncestry;

  function Token(APosition: Integer): TPascalToken;
  begin
    Result := Tokens[Code[APosition]];
  end;

  function IsWord(APosition: Integer): Boolean;
  begin
    Result := (APosition >= 0) and (APosition <= High(Code)) and
      (Token(APosition).Kind = TPascalTokenKind.Identifier);
  end;

  function IsSym(APosition: Integer; const ASymbol: string): Boolean;
  begin
    Result := (APosition >= 0) and (APosition <= High(Code)) and Token(APosition).IsSymbol(ASymbol);
  end;

  function CodeAt(AOffset: Integer): Integer;
  begin
    for Result := 0 to High(Code) do
      if Token(Result).Offset >= AOffset then
        Exit;
    Result := Length(Code);
  end;

  function Closing(AOpen: Integer): Integer;
  var
    Depth: Integer;
  begin
    Depth := 0;
    for Result := AOpen to High(Code) do
      if Token(Result).IsSymbol('(') or Token(Result).IsSymbol('[') then
        Inc(Depth)
      else if Token(Result).IsSymbol(')') or Token(Result).IsSymbol(']') then
      begin
        Dec(Depth);
        if Depth = 0 then
          Exit;
      end;
    Result := -1;
  end;

  function SkipGenericArgs(APosition: Integer): Integer;
  var
    Depth: Integer;
  begin
    Result := APosition;
    if not IsSym(Result, '<') then
      Exit;
    Depth := 0;
    while Result <= High(Code) do
    begin
      if Token(Result).IsSymbol('<') then
        Inc(Depth)
      else if Token(Result).IsSymbol('>') then
        Dec(Depth)
      else if Token(Result).IsSymbol('>>') then
        Dec(Depth, 2)
      else if Token(Result).IsSymbol(';') then
        Exit;
      Inc(Result);
      if Depth <= 0 then
        Exit;
    end;
  end;

  function TextBetween(AFirst, ALast: Integer): string;
  begin
    Result := Copy(AContext.Text, Token(AFirst).Offset + 1,
      Token(ALast).Offset + Length(Token(ALast).Text) - Token(AFirst).Offset);
  end;

  function IsSelfRegistering(const AClassName: string): Boolean;
  var
    Pattern: string;
  begin
    for Pattern in SelfRegistering do
      if MatchesGlob(Pattern, AClassName) then
        Exit(True);
    Result := False;
  end;

  // Art der Klasse über die Vorfahren in Datei und Index; Unknown, wenn die Kette vor TObject abbricht.
  function KindOf(const AClassName: string): TCreatedKind;
  var
    Name: string;
    Depth: Integer;
    Body: TSyntaxNode;
  begin
    // Records (TPoint.Create(1, 2)) belegen keinen Heap.
    Body := TRoutineBody.TypeBody(AContext.Tree.Root, AClassName);
    if (Body <> nil) and (Body.Kind = TSyntaxKind.RecordType) then
      Exit(TCreatedKind.Unknown);
    Name := AClassName;
    for Depth := 0 to 63 do
    begin
      if SameText(Name, 'TComponent') then
        Exit(TCreatedKind.Component);
      if SameText(Name, 'TThread') then
        Exit(TCreatedKind.Thread);
      if SameText(Name, 'TObject') then
        Exit(TCreatedKind.Plain);
      Name := Ancestry.ParentOf(Name);
      if Name = '' then
        Break;
    end;
    Result := TCreatedKind.Unknown;
  end;

  // "Name := T.Create(…);" mit try/finally um die folgenden Anweisungen des Blocks.
  function AssignFix(ARoutine, AStatement: TSyntaxNode; const ATypeText: string; out AFix: TRuleFix): Boolean;
  var
    Parent, LastSibling: TSyntaxNode;
    Index, Line, LastLine: Integer;
    Indent, UnitIndent, Name, Rest, NewText: string;
  begin
    Result := False;
    Parent := AStatement.Parent;
    if (Parent = nil) or not (Parent.Kind in [TSyntaxKind.Block, TSyntaxKind.TryStatement, TSyntaxKind.FinallyBlock,
      TSyntaxKind.ExceptBlock]) or (AStatement.StartPos.Line <> AStatement.EndPos.Line) or
      (AStatement.EndPos.Line > High(Lines)) or
      (Trim(Copy(Lines[AStatement.StartPos.Line], 1, AStatement.StartPos.Character)) <> '') then
      Exit;
    Rest := Trim(Copy(Lines[AStatement.EndPos.Line], AStatement.EndPos.Character + 1, MaxInt));
    if (Rest <> '') and (Rest <> ';') then
      Exit;
    // Letzte folgende Anweisung desselben Blocks; sie muss ihre Zeile allein beenden.
    LastSibling := AStatement;
    for Index := 0 to Parent.ChildCount - 1 do
      if Parent[Index].StartOffset > AStatement.StartOffset then
        LastSibling := Parent[Index];
    LastLine := LastSibling.EndPos.Line;
    if LastLine > High(Lines) then
      Exit;
    Rest := Trim(Copy(Lines[LastLine], LastSibling.EndPos.Character + 1, MaxInt));
    if (Rest <> '') and (Rest <> ';') then
      Exit;
    Indent := Copy(Lines[AStatement.StartPos.Line], 1, AStatement.StartPos.Character);
    UnitIndent := TRoutineBody.IndentUnit(AContext.Formatting);
    Name := TRoutineBody.UniqueName(Tokens, VariableName(ATypeText));
    NewText := Indent + Name + ' := ' + TrimLeft(Lines[AStatement.StartPos.Line]) + LineBreak + Indent + 'try' +
      LineBreak;
    for Line := AStatement.StartPos.Line + 1 to LastLine do
      if Trim(Lines[Line]) = '' then
        NewText := NewText + LineBreak
      else
        NewText := NewText + UnitIndent + Lines[Line] + LineBreak;
    NewText := NewText + Indent + 'finally' + LineBreak + Indent + UnitIndent + Name + '.Free;' + LineBreak + Indent +
      'end;' + LineBreak;
    AFix := TRuleFix.Create(Format('An %s zuweisen und in try/finally freigeben', [Name]),
      [TRoutineBody.AddVariable(AContext.Text, ARoutine, Name, ATypeText, AContext.Formatting),
      TTextEdit.Create(TTextRange.Create(AStatement.StartPos.Line, 0, LastLine + 1, 0), NewText)]);
    Result := True;
  end;

  procedure CheckStatement(ARoutine, AStatement: TSyntaxNode);
  var
    Position, ClassPosition, After, Close, Next: Integer;
    ClassName, TypeText, FirstArgument: string;
    HasArguments: Boolean;
    Kind: TCreatedKind;
    Fix: TRuleFix;
    Fixes: TArray<TRuleFix>;
  begin
    Position := CodeAt(AStatement.StartOffset);
    if not IsWord(Position) then
      Exit;
    // Unit.TKlasse<T>.Create(…)
    ClassPosition := Position;
    After := SkipGenericArgs(Position + 1);
    while IsSym(After, '.') and IsWord(After + 1) and not SameText(Token(After + 1).Text, 'Create') do
    begin
      ClassPosition := After + 1;
      After := SkipGenericArgs(After + 2);
    end;
    if not IsSym(After, '.') or not IsWord(After + 1) or not SameText(Token(After + 1).Text, 'Create') then
      Exit;
    Next := After + 2;
    HasArguments := False;
    FirstArgument := '';
    if IsSym(Next, '(') then
    begin
      Close := Closing(Next);
      if Close < 0 then
        Exit;
      HasArguments := Close > Next + 1;
      if HasArguments and (IsWord(Next + 1) or Token(Next + 1).IsKeyword('nil')) and
        (IsSym(Next + 2, ',') or IsSym(Next + 2, ')')) then
        FirstArgument := Token(Next + 1).Text;
      Next := Close + 1;
    end;
    // Die Anweisung endet mit Create(…): nichts wird weitergegeben oder gespeichert.
    if (Next <= High(Code)) and (Token(Next).Offset < AStatement.EndOffset) then
      Exit;
    ClassName := Token(ClassPosition).Text;
    Kind := KindOf(ClassName);
    if (not LooksLikeType(ClassName) and (Kind = TCreatedKind.Unknown)) or IsSelfRegistering(ClassName) or
      (Kind = TCreatedKind.Thread) then
      Exit;
    // Komponenten mit Owner gibt der Owner frei; unbekannte Klassen mit Argumenten tragen sich oft selbst ein.
    // Gemeldet werden mit Argumenten nur bekannte Klassen ohne TComponent und Aufrufe mit nil als Owner.
    if HasArguments and not SameText(FirstArgument, 'nil') and
      ((Kind <> TCreatedKind.Plain) or MatchText(FirstArgument, ['Self', 'Owner', 'AOwner', 'Application'])) then
      Exit;
    TypeText := TextBetween(Position, After - 1);
    Fixes := nil;
    if AssignFix(ARoutine, AStatement, TypeText, Fix) then
      Fixes := [Fix];
    AReport.Add(TTextRange.Create(Token(Position).StartPos, Token(Next - 1).EndPos),
      Format('Das erzeugte %s wird nirgends gespeichert und nie freigegeben (Speicherleck).', [TypeText]), Fixes);
  end;

  procedure VisitStatements(ARoutine, ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    if ANode.Kind = TSyntaxKind.CallStatement then
      CheckStatement(ARoutine, ANode);
    // Lokale Routinen prüft Visit für sich.
    if (ANode <> ARoutine) and (ANode.Kind = TSyntaxKind.RoutineDecl) then
      Exit;
    for Index := 0 to ANode.ChildCount - 1 do
      VisitStatements(ARoutine, ANode[Index]);
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    if ANode.Kind = TSyntaxKind.RoutineDecl then
      VisitStatements(ANode, ANode);
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index]);
  end;

var
  Index: Integer;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'Create') then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Code := nil;
  for Index := 0 to High(Tokens) do
    if not (Tokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
      Code := Code + [Index];
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  SelfRegistering := TRuleOptions.Strings(AContext.Options, 'selfRegistering', nil);
  Ancestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(TRuleDerived.Open(AContext), AContext));
  try
    Visit(AContext.Tree.Root);
  finally
    Ancestry.Free;
  end;
end;

procedure RegisterOwnershipRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TOwnedItemFreedRule.Create);
  ARegistry.Register(TCreateWithoutAssignmentRule.Create);
end;

end.
